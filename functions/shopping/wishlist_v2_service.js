"use strict";

const crypto = require("crypto");
const {catalogRevisionFor, resolveBestOffer} = require("./catalog_search_service");
const {effectivePublicPrice, LIFECYCLE} = require("./catalog_contract");
const {buildPublicCandidateDetail} = require("./public_shopping_dto");
const {deriveWishlistCatalogFacts} =
  require("./monitoring/wishlist_catalog_facts");
const {evaluateWishlistMonitoring} =
  require("./monitoring/wishlist_monitoring_engine");

const WISHLIST_SCHEMA_VERSION = 2;
const WISHLIST_COLLECTION = "wishlistV2";
const MAX_SELECTED_SIZES = 12;

class WishlistV2Error extends Error {
  constructor(code, message = code) {
    super(message);
    this.code = code;
  }
}

function createFirestoreWishlistV2Repository(db) {
  if (!db || typeof db.collection !== "function") {
    throw new Error("wishlist_v2_firestore_repository_requires_db");
  }
  return {
    async get(uid, itemId) {
      const snapshot = await ref(uid, itemId).get();
      return snapshot.exists ? decodeStored(snapshot.data()) : null;
    },
    async upsert(uid, item, {previousVariantId = null} = {}) {
      const itemRef = ref(uid, item.wishlistItemId);
      const subscriptionId = subscriptionDocId(uid, item.wishlistItemId);
      const subscriptionRef = subscription(item.variantId, subscriptionId);
      await db.runTransaction(async (transaction) => {
        transaction.set(itemRef, encodeStored(item));
        if (previousVariantId && previousVariantId !== item.variantId) {
          transaction.delete(subscription(
            previousVariantId, subscriptionId));
        }
        transaction.set(subscriptionRef, {
          schemaVersion: 1,
          userId: uid,
          ownerUid: uid,
          wishlistItemId: item.wishlistItemId,
          variantId: item.variantId,
          priceMonitoringEnabled: item.priceMonitoringEnabled === true,
          sizeMonitoringEnabled: item.sizeMonitoringEnabled === true,
          informationalEnabled: true,
          updatedAt: new Date(item.updatedAt),
          createdAt: new Date(item.createdAt || item.updatedAt),
        });
      });
      return item;
    },
    async remove(uid, itemId) {
      const target = ref(uid, itemId);
      const snapshot = await target.get();
      if (!snapshot.exists) return false;
      const item = decodeStored(snapshot.data());
      await db.runTransaction(async (transaction) => {
        transaction.delete(target);
        transaction.delete(subscription(
          item.variantId, subscriptionDocId(uid, itemId)));
      });
      return true;
    },
    async list(uid) {
      const snapshot = await db.collection("users").doc(uid)
        .collection(WISHLIST_COLLECTION).get();
      return snapshot.docs.map((doc) => decodeStored(doc.data()));
    },
    async getByItemId(uid, itemId) {
      const snapshot = await ref(uid, itemId).get();
      return snapshot.exists ? decodeStored(snapshot.data()) : null;
    },
    async listSubscribers(variantId) {
      const snapshot = await db.collection("wishlistSubscriptions")
        .doc(variantId).collection("subscribers").get();
      return snapshot.docs.map((doc) => doc.data());
    },
    async saveEvaluation(uid, item, events) {
      const itemRef = ref(uid, item.wishlistItemId);
      const eventRefs = events.map((event) =>
        db.collection("wishlistEvents").doc(event.eventId));
      return db.runTransaction(async (transaction) => {
        const snapshots = [];
        for (const eventRef of eventRefs) snapshots.push(await transaction.get(eventRef));
        transaction.set(itemRef, encodeStored(item));
        const created = [];
        for (let index = 0; index < events.length; index++) {
          if (snapshots[index].exists) continue;
          transaction.create(eventRefs[index], encodeEvent(events[index]));
          created.push(events[index]);
        }
        return created;
      });
    },
    async listPendingEvents(uid) {
      const snapshot = await db.collection("wishlistEvents")
        .where("ownerUid", "==", uid).limit(100).get();
      return snapshot.docs.map((doc) => decodeEvent(doc.data()))
        .filter((event) => !["DELIVERED", "SKIPPED"].includes(
          event.delivery?.status));
    },
    async acknowledge(uid, itemId, mutation) {
      const itemRef = ref(uid, itemId);
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(itemRef);
        if (!snapshot.exists) return null;
        const next = mutation(decodeStored(snapshot.data()));
        transaction.set(itemRef, encodeStored(next));
        return next;
      });
    },
    async acquireRefreshLease(uid, operationId, now, ttlMs) {
      const leaseRef = db.collection("wishlistRefreshLeases").doc(uid);
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(leaseRef);
        const existing = snapshot.exists ? snapshot.data() : null;
        const expiresAt = existing?.expiresAt?.toMillis?.() || 0;
        if (expiresAt > now && existing.operationId !== operationId) return false;
        transaction.set(leaseRef, {
          ownerUid: uid,
          operationId,
          createdAt: new Date(now),
          expiresAt: new Date(now + ttlMs),
        });
        return true;
      });
    },
    async releaseRefreshLease(uid, operationId) {
      const leaseRef = db.collection("wishlistRefreshLeases").doc(uid);
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(leaseRef);
        if (snapshot.exists && snapshot.data().operationId === operationId) {
          transaction.delete(leaseRef);
        }
      });
    },
  };
  function ref(uid, itemId) {
    return db.collection("users").doc(uid).collection(WISHLIST_COLLECTION).doc(itemId);
  }
  function subscription(variantId, subscriptionId) {
    return db.collection("wishlistSubscriptions").doc(variantId)
      .collection("subscribers").doc(subscriptionId);
  }
}

function subscriptionDocId(userId, wishlistItemId) {
  return `${userId}_${wishlistItemId}`;
}

function createMemoryWishlistV2Repository() {
  const values = new Map();
  const subscriptions = new Map();
  const events = new Map();
  const leases = new Map();
  const key = (uid, itemId) => `${uid}:${itemId}`;
  return {
    async get(uid, itemId) { return clone(values.get(key(uid, itemId)) || null); },
    async upsert(uid, item, {previousVariantId = null} = {}) {
      values.set(key(uid, item.wishlistItemId), clone(item));
      const subscriptionId = subscriptionDocId(uid, item.wishlistItemId);
      if (previousVariantId && previousVariantId !== item.variantId) {
        subscriptions.delete(`${previousVariantId}:${subscriptionId}`);
      }
      subscriptions.set(`${item.variantId}:${subscriptionId}`, {
        userId: uid,
        ownerUid: uid,
        wishlistItemId: item.wishlistItemId,
        variantId: item.variantId,
        priceMonitoringEnabled: item.priceMonitoringEnabled === true,
        sizeMonitoringEnabled: item.sizeMonitoringEnabled === true,
        informationalEnabled: true,
      });
      return clone(item);
    },
    async remove(uid, itemId) {
      const item = values.get(key(uid, itemId));
      if (!item) return false;
      values.delete(key(uid, itemId));
      subscriptions.delete(
        `${item.variantId}:${subscriptionDocId(uid, itemId)}`);
      return true;
    },
    async list(uid) {
      return [...values.entries()]
        .filter(([storedKey]) => storedKey.startsWith(`${uid}:`))
        .map(([, value]) => clone(value));
    },
    dump() { return clone([...values.values()]); },
    async getByItemId(uid, itemId) {
      return clone(values.get(key(uid, itemId)) || null);
    },
    async listSubscribers(variantId) {
      return clone([...subscriptions.values()].filter((value) =>
        value.variantId === variantId));
    },
    async saveEvaluation(uid, item, eventValues) {
      values.set(key(uid, item.wishlistItemId), clone(item));
      const created = [];
      for (const event of eventValues) {
        if (events.has(event.eventId)) continue;
        events.set(event.eventId, clone(event));
        created.push(clone(event));
      }
      return created;
    },
    async listPendingEvents(uid) {
      return clone([...events.values()].filter((event) =>
        event.ownerUid === uid &&
        !["DELIVERED", "SKIPPED"].includes(event.delivery?.status)));
    },
    async acknowledge(uid, itemId, mutation) {
      const item = values.get(key(uid, itemId));
      if (!item) return null;
      const next = mutation(clone(item));
      values.set(key(uid, itemId), clone(next));
      return clone(next);
    },
    async acquireRefreshLease(uid, operationId, now, ttlMs) {
      const current = leases.get(uid);
      if (current && current.expiresAt > now &&
          current.operationId !== operationId) return false;
      leases.set(uid, {operationId, expiresAt: now + ttlMs});
      return true;
    },
    async releaseRefreshLease(uid, operationId) {
      if (leases.get(uid)?.operationId === operationId) leases.delete(uid);
    },
    dumpEvents() { return clone([...events.values()]); },
    dumpSubscriptions() { return clone([...subscriptions.values()]); },
  };
}

function createWishlistV2Service({
  repository,
  catalogRepository,
  monitoringService = null,
  now = () => Date.now(),
}) {
  if (!repository || !catalogRepository) throw new Error("wishlist_v2_dependencies_required");

  async function dispatch(auth, request) {
    const uid = requireAuth(auth);
    const operation = String(request?.operation || "");
    switch (operation) {
      case "ADD_OR_UPSERT": return upsert(uid, request, false);
      case "UPDATE_INTENT": return upsert(uid, request, true);
      case "REMOVE": return remove(uid, request);
      case "GET_ITEMS": return getItems(uid);
      case "GET_ITEM": return getItem(uid, request);
      case "REFRESH_ALL":
        if (!monitoringService) throw new WishlistV2Error("MONITORING_UNAVAILABLE");
        return monitoringService.refreshAll(uid, {
          operationId: request.operationId == null ? undefined :
            safeId(request.operationId, "operation_id"),
        });
      case "REFRESH_ITEM":
        if (!monitoringService) throw new WishlistV2Error("MONITORING_UNAVAILABLE");
        return monitoringService.refreshItem(
          uid, safeId(request.wishlistItemId, "wishlist_item_id"));
      case "ACKNOWLEDGE":
      case "ACKNOWLEDGE_HIGHLIGHTS":
        if (!monitoringService) throw new WishlistV2Error("MONITORING_UNAVAILABLE");
        if (!Array.isArray(request.wishlistItemIds)) {
          throw new WishlistV2Error("INVALID_ARGUMENT", "wishlist_item_ids_required");
        }
        return monitoringService.acknowledge(uid,
          request.wishlistItemIds.map((value) => safeId(value, "wishlist_item_id")),
          Array.isArray(request.eventIds) ? request.eventIds.map(String) : null);
      default: throw new WishlistV2Error("INVALID_ARGUMENT", "unknown_operation");
    }
  }

  async function upsert(uid, request, updateOnly) {
    rejectForgedFields(request);
    const intent = validateIntent(request);
    const itemId = wishlistItemId(uid, intent.variantId);
    const existing = await repository.get(uid, itemId);
    if (updateOnly && !existing) throw new WishlistV2Error("WISHLIST_NOT_FOUND");
    const catalog = await catalogRepository.readCompleteSnapshot();
    const facts = authoritativeFacts(catalog, intent);
    const timestamp = now();
    const initialItem = {
      schemaVersion: WISHLIST_SCHEMA_VERSION,
      wishlistItemId: itemId,
      ownerUid: uid,
      variantId: intent.variantId,
      selectedSizes: intent.selectedSizes,
      preferredSize: intent.preferredSize,
      targetPrice: intent.targetPrice,
      priceMonitoringEnabled: intent.priceMonitoringEnabled,
      sizeMonitoringEnabled: intent.sizeMonitoringEnabled,
      createdAt: existing?.createdAt || timestamp,
      updatedAt: timestamp,
      tracking: existing?.tracking || {},
    };
    const monitoringFacts = deriveWishlistCatalogFacts(catalog, initialItem);
    const item = evaluateWishlistMonitoring({
      item: initialItem,
      facts: monitoringFacts,
      catalogRevision: catalogRevisionFor(catalog),
      syncRunId: `baseline_${itemId}_${timestamp}`,
      now: timestamp,
      baseline: true,
    }).item;
    await repository.upsert(uid, item, {
      previousVariantId: existing?.variantId || null,
    });
    return {status: existing ? "UPDATED" : "CREATED", item: publicWishlistItem(item, facts.detail)};
  }

  async function remove(uid, request) {
    const variantId = safeId(request?.variantId, "variant_id");
    const removed = await repository.remove(uid, wishlistItemId(uid, variantId));
    return {status: removed ? "REMOVED" : "NOT_FOUND", variantId};
  }

  async function getItems(uid) {
    const [items, catalog] = await Promise.all([
      repository.list(uid),
      catalogRepository.readCompleteSnapshot(),
    ]);
    const {sortWishlistItems} = require("./monitoring/wishlist_monitoring_engine");
    const sorted = sortWishlistItems(items);
    return {
      status: "OK",
      items: sorted.map((item) => {
        let detail = null;
        try {
          const facts = authoritativeFacts(catalog, {
            variantId: item.variantId,
            selectedSizes: item.selectedSizes,
            preferredSize: item.preferredSize,
            targetPrice: item.targetPrice,
            priceMonitoringEnabled: item.priceMonitoringEnabled,
            sizeMonitoringEnabled: item.sizeMonitoringEnabled,
          });
          detail = facts.detail;
        } catch (_) {
          detail = item.currentCatalogProjection || null;
        }
        return publicWishlistItem(item, detail);
      }),
    };
  }

  async function getItem(uid, request) {
    const variantId = safeId(request?.variantId, "variant_id");
    const item = await repository.get(uid, wishlistItemId(uid, variantId));
    if (!item) throw new WishlistV2Error("WISHLIST_NOT_FOUND");
    const catalog = await catalogRepository.readCompleteSnapshot();
    const facts = authoritativeFacts(catalog, {
      variantId: item.variantId, selectedSizes: item.selectedSizes,
      preferredSize: item.preferredSize, targetPrice: item.targetPrice,
      priceMonitoringEnabled: item.priceMonitoringEnabled,
      sizeMonitoringEnabled: item.sizeMonitoringEnabled,
    });
    return {status: "OK", item: publicWishlistItem(item, facts.detail)};
  }

  return {dispatch, repository};
}

function authoritativeFacts(catalog, intent) {
  const variant = (catalog.variants || []).find((value) =>
    value.variantId === intent.variantId && value.lifecycleState !== LIFECYCLE.DISCONTINUED);
  if (!variant) throw new WishlistV2Error("INVALID_VARIANT");
  const product = (catalog.products || []).find((value) => value.productId === variant.productId);
  if (!product) throw new WishlistV2Error("INVALID_VARIANT");
  const offers = (catalog.offers || []).filter((offer) =>
    offer.variantId === variant.variantId && offer.lifecycleState !== LIFECYCLE.DISCONTINUED);
  const sizesByOffer = groupBy(catalog.sizes || [], "offerId");
  const knownSizeKeys = new Set();
  for (const offer of offers) {
    for (const size of sizesByOffer.get(offer.offerId) || []) {
      knownSizeKeys.add(String(size.normalizedSizeKey).toLowerCase());
    }
  }
  if (intent.selectedSizes.some((size) => !knownSizeKeys.has(size.toLowerCase()))) {
    throw new WishlistV2Error("INVALID_SELECTED_SIZE");
  }
  const selectedSet = new Set(intent.selectedSizes.map((value) => value.toLowerCase()));
  const best = resolveBestOffer({
    offers, sizesByOffer, selectedSizeKeys: selectedSet,
    preferredSizeKey: intent.preferredSize, availableNow: false,
  });
  const effectivePrice = best ? effectivePublicPrice(best.offer).price : null;
  const priceState = !effectivePrice || effectivePrice.currency !== intent.targetPrice.currency ?
    "UNKNOWN" :
    (effectivePrice.amountMinor <= intent.targetPrice.amountMinor ? "SATISFIED" : "UNSATISFIED");
  const sizeStates = {};
  const sizeAvailability = {};
  for (const selected of intent.selectedSizes) {
    const facts = offers.flatMap((offer) =>
      (sizesByOffer.get(offer.offerId) || []).filter((size) =>
        String(size.normalizedSizeKey).toLowerCase() === selected.toLowerCase()));
    const state = facts.some((size) => size.availability === "AVAILABLE") ? "AVAILABLE" :
      (facts.length && facts.every((size) => size.availability === "UNAVAILABLE") ?
        "UNAVAILABLE" : "UNKNOWN");
    sizeStates[selected] = state;
    sizeAvailability[selected] = state;
  }
  const candidate = {
    variantId: variant.variantId, productId: product.productId,
    relevantOfferIds: offers.map((offer) => offer.offerId),
    bestOfferId: best?.offer?.offerId || null,
    rankingComponents: {hardConstraintGate: true},
  };
  return {
    priceState,
    sizeStates,
    sizeAvailability,
    effectivePrice,
    lastSuccessfulVerification: best?.offer?.lastVerifiedAt ||
      best?.offer?.freshness?.lastSuccessfulVerificationAt || null,
    detail: buildPublicCandidateDetail({
      candidate,
      catalog,
      query: {
        selectedSizeKeys: intent.selectedSizes,
        preferredSizeKey: intent.preferredSize,
        availableNow: false,
      },
    }),
  };
}

function validateIntent(request) {
  const variantId = safeId(request?.variantId, "variant_id");
  if (!Array.isArray(request?.selectedSizes) ||
      request.selectedSizes.length < 1 || request.selectedSizes.length > MAX_SELECTED_SIZES) {
    throw new WishlistV2Error("INVALID_SELECTED_SIZES");
  }
  const selectedSizes = [...new Set(request.selectedSizes.map((value) =>
    String(value || "").trim().toUpperCase()))];
  if (selectedSizes.some((value) => !/^[A-Z0-9._-]{1,32}$/.test(value))) {
    throw new WishlistV2Error("INVALID_SELECTED_SIZES");
  }
  const preferredSize = request.preferredSize == null ? null :
    String(request.preferredSize).trim().toUpperCase();
  if (preferredSize != null && !selectedSizes.includes(preferredSize)) {
    throw new WishlistV2Error("PREFERRED_SIZE_NOT_SELECTED");
  }
  const targetPrice = validateMoney(request.targetPrice);
  if (typeof request.priceMonitoringEnabled !== "boolean" ||
      typeof request.sizeMonitoringEnabled !== "boolean") {
    throw new WishlistV2Error("INVALID_MONITORING_OPTIONS");
  }
  return {
    variantId, selectedSizes, preferredSize, targetPrice,
    priceMonitoringEnabled: request.priceMonitoringEnabled,
    sizeMonitoringEnabled: request.sizeMonitoringEnabled,
  };
}

function rejectForgedFields(request) {
  const forbidden = [
    "ownerUid", "tracking", "evaluatedPriceState", "evaluatedSizeStates",
    "lastKnownEffectivePrice", "highlightState", "currentPrice", "availability",
    "quantity", "gold", "url", "store", "couponCode", "lowStockMonitoringEnabled",
  ];
  if (forbidden.some((field) => Object.prototype.hasOwnProperty.call(request || {}, field))) {
    throw new WishlistV2Error("FORGED_SERVER_STATE");
  }
}

function publicWishlistItem(item, detail) {
  return {
    schemaVersion: item.schemaVersion,
    wishlistItemId: item.wishlistItemId,
    variantId: item.variantId,
    selectedSizes: item.selectedSizes,
    preferredSize: item.preferredSize,
    targetPrice: item.targetPrice,
    priceMonitoringEnabled: item.priceMonitoringEnabled,
    sizeMonitoringEnabled: item.sizeMonitoringEnabled,
    createdAt: item.createdAt,
    updatedAt: item.updatedAt,
    tracking: clone(item.tracking),
    currentCatalogProjection: detail,
  };
}

function wishlistItemId(uid, variantId) {
  return `wish_${crypto.createHash("sha256").update(`${uid}\0${variantId}`)
    .digest("hex").slice(0, 32)}`;
}
function validateMoney(value) {
  if (!value || !Number.isSafeInteger(value.amountMinor) || value.amountMinor < 0 ||
      !/^[A-Z]{3}$/.test(String(value.currency || ""))) {
    throw new WishlistV2Error("INVALID_TARGET_PRICE");
  }
  return {amountMinor: value.amountMinor, currency: value.currency};
}
function safeId(value, label) {
  const text = String(value || "");
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(text)) {
    throw new WishlistV2Error("INVALID_ARGUMENT", `invalid_${label}`);
  }
  return text;
}
function requireAuth(auth) {
  if (!auth || typeof auth.uid !== "string" || !auth.uid) {
    throw new WishlistV2Error("UNAUTHENTICATED");
  }
  return auth.uid;
}
function groupBy(values, field) {
  const result = new Map();
  for (const value of values) {
    const group = result.get(value[field]) || [];
    group.push(value);
    result.set(value[field], group);
  }
  return result;
}
function encodeStored(item) {
  return {...clone(item), createdAt: new Date(item.createdAt), updatedAt: new Date(item.updatedAt)};
}
function encodeEvent(event) {
  return {
    ...clone(event),
    createdAt: new Date(event.createdAt),
    expiresAt: new Date(event.expiresAt),
  };
}
function decodeEvent(event) {
  return {
    ...clone(event),
    createdAt: millis(event.createdAt),
    expiresAt: millis(event.expiresAt),
  };
}
function decodeStored(item) {
  if (!item || item.schemaVersion !== WISHLIST_SCHEMA_VERSION) {
    throw new WishlistV2Error("UNSUPPORTED_WISHLIST_SCHEMA");
  }
  return {...clone(item), createdAt: millis(item.createdAt), updatedAt: millis(item.updatedAt)};
}
function millis(value) {
  if (typeof value === "number") return value;
  if (value instanceof Date) return value.getTime();
  if (value && typeof value.toMillis === "function") return value.toMillis();
  throw new WishlistV2Error("MALFORMED_WISHLIST");
}
function clone(value) { return value == null ? value : structuredClone(value); }

module.exports = {
  WISHLIST_COLLECTION,
  WISHLIST_SCHEMA_VERSION,
  WishlistV2Error,
  createFirestoreWishlistV2Repository,
  createMemoryWishlistV2Repository,
  createWishlistV2Service,
  subscriptionDocId,
  wishlistItemId,
};
