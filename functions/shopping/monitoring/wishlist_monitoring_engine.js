"use strict";

const crypto = require("crypto");
const {
  EVENT_TYPES,
  LOW_STOCK_QUANTITY_POLICY_V1,
  WISHLIST_EVENT_RETENTION_MS_V1,
  WISHLIST_LAST_EVENT_IDS_CAP_V1,
} = require("./wishlist_monitoring_constants");

/**
 * Pure deterministic Wishlist monitoring engine.
 * Dart WishlistTrackingEvaluator is the semantic oracle for price/size
 * transitions. Discontinued must never manufacture UNKNOWN → UNAVAILABLE.
 */
function evaluateWishlistMonitoring({
  item,
  facts,
  catalogRevision,
  syncRunId,
  now = Date.now(),
  baseline = false,
}) {
  const previous = item.tracking || {};
  if (facts.successfulVerification !== true) {
    return {
      item: withTracking(item, {
        ...previous,
        freshness: {
          ...(previous.freshness || {}),
          stale: true,
          lastRefreshFailureAt: now,
        },
      }),
      events: [],
      newlyGold: false,
      lowStockNotification: null,
    };
  }

  const nextPrice = facts.priceState || "UNKNOWN";
  const previousPrice = previous.evaluatedPriceState || "UNKNOWN";
  const previousSizes = normalizeStates(
    previous.evaluatedSizeStates, item.selectedSizes);
  const nextSizes = mergeSizeStates({
    previousSizes,
    observedSizes: facts.sizeStates,
    sizeEvidence: facts.sizeEvidence,
    selectedSizes: item.selectedSizes,
  });
  const nextLifecycle = facts.lifecycleState || previous.lifecycleState ||
    "UNKNOWN";
  const events = [];

  if (!baseline && previousPrice !== "UNKNOWN" && nextPrice !== "UNKNOWN" &&
      previousPrice !== nextPrice) {
    events.push(buildEvent({
      item,
      condition: "PRICE",
      type: nextPrice === "SATISFIED" ?
        EVENT_TYPES.PRICE_TARGET_SATISFIED :
        EVENT_TYPES.PRICE_TARGET_UNSATISFIED,
      oldState: previousPrice,
      newState: nextPrice,
      catalogRevision,
      syncRunId,
      facts,
      now,
    }));
  }

  if (!baseline) {
    for (const size of item.selectedSizes || []) {
      const before = previousSizes[size] || "UNKNOWN";
      const after = nextSizes[size] || "UNKNOWN";
      // UNKNOWN must never participate in size transition events.
      if (before === "UNKNOWN" || after === "UNKNOWN" || before === after) {
        continue;
      }
      events.push(buildEvent({
        item,
        condition: "SIZE",
        type: after === "AVAILABLE" ?
          EVENT_TYPES.SIZE_AVAILABLE : EVENT_TYPES.SIZE_UNAVAILABLE,
        oldState: before,
        newState: after,
        sizeKey: size,
        catalogRevision,
        syncRunId,
        facts,
        now,
      }));
    }
  }

  const knownIds = new Set(previous.lastEventIds || []);
  const newEvents = events.filter((event) => !knownIds.has(event.eventId));
  const positive = newEvents.filter(isGoldEligibleEvent);
  const lowStock = deriveLowStockEpisode({
    previous,
    facts,
    selectedSizes: item.selectedSizes,
    catalogRevision,
    syncRunId,
    item,
    now,
    baseline,
  });
  const highlight = positive.length ? {
    state: "UNACKNOWLEDGED",
    eventIds: [
      ...((previous.highlight?.state === "UNACKNOWLEDGED" ?
        previous.highlight.eventIds : []) || []),
      ...positive.map((event) => event.eventId),
    ].slice(-WISHLIST_LAST_EVENT_IDS_CAP_V1),
    occurredAt: now,
  } : normalizeHighlight(previous.highlight);

  const lastEventIds = [
    ...(previous.lastEventIds || []),
    ...newEvents.map((event) => event.eventId),
    ...(lowStock.event ? [lowStock.event.eventId] : []),
  ].slice(-WISHLIST_LAST_EVENT_IDS_CAP_V1);

  const sortTier = highlight.state === "UNACKNOWLEDGED" ? 0 :
    (lowStock.state === "LOW_STOCK" ? 1 : 2);

  const allNewEvents = lowStock.event ?
    [...newEvents, lowStock.event] : newEvents;

  return {
    item: withTracking(item, {
      ...previous,
      evaluatedPriceState: nextPrice,
      evaluatedSizeStates: nextSizes,
      lastKnownEffectivePrice: facts.effectivePrice ||
        previous.lastKnownEffectivePrice || null,
      lastKnownSelectedSizeAvailability: nextSizes,
      lastKnownReliableQuantities: facts.reliableQuantities ||
        previous.lastKnownReliableQuantities || {},
      lastKnownCoupon: Object.prototype.hasOwnProperty.call(facts, "coupon") ?
        facts.coupon : (previous.lastKnownCoupon || null),
      lastSuccessfulVerification: facts.lastSuccessfulVerification || null,
      lastCatalogRevision: catalogRevision,
      lastSyncRunId: syncRunId,
      lifecycleState: nextLifecycle,
      lowStockState: lowStock.state,
      lowStockEpisode: lowStock.episode,
      lowStockPolicyVersion: LOW_STOCK_QUANTITY_POLICY_V1.name,
      lastEventIds,
      highlight,
      highlightState: highlight.state === "UNACKNOWLEDGED" ? "GOLD" : "NONE",
      sortTier,
      sortEventAt: highlight.state === "UNACKNOWLEDGED" ?
        (highlight.occurredAt || now) : (previous.sortEventAt || 0),
      freshness: {
        stale: false,
        priceVerifiedAt: facts.priceVerifiedAt || null,
        availabilityVerifiedAt: facts.availabilityVerifiedAt || null,
        lastRefreshFailureAt: null,
      },
    }),
    events: allNewEvents,
    newlyGold: positive.length > 0,
    lowStockNotification: lowStock.event,
  };
}

function acknowledgeHighlight(item, now = Date.now(), eventIds = null) {
  const tracking = item.tracking || {};
  const highlight = normalizeHighlight(tracking.highlight);
  if (highlight.state !== "UNACKNOWLEDGED") return item;
  const acknowledgedIds = Array.isArray(eventIds) && eventIds.length ?
    eventIds : highlight.eventIds;
  const remaining = highlight.eventIds.filter((id) =>
    !acknowledgedIds.includes(id));
  if (remaining.length) {
    return withTracking(item, {
      ...tracking,
      highlight: {...highlight, eventIds: remaining},
      highlightState: "GOLD",
      sortTier: 0,
    });
  }
  return withTracking(item, {
    ...tracking,
    highlight: {
      ...highlight,
      state: "ACKNOWLEDGED",
      eventIds: [],
      acknowledgedAt: now,
    },
    highlightState: "NONE",
    sortTier: tracking.lowStockState === "LOW_STOCK" ? 1 : 2,
  });
}

/**
 * Preserve prior size when observation lacks authoritative per-size evidence.
 * Lifecycle/discontinued alone never invents UNAVAILABLE from UNKNOWN/AVAILABLE.
 */
function mergeSizeStates({
  previousSizes,
  observedSizes,
  sizeEvidence,
  selectedSizes,
}) {
  const next = {};
  for (const size of selectedSizes || []) {
    const previous = previousSizes[size] || "UNKNOWN";
    const hasEvidence = sizeEvidence ?
      sizeEvidence[size] === true :
      (observedSizes && Object.prototype.hasOwnProperty.call(observedSizes, size) &&
        observedSizes[size] !== "UNKNOWN");
    if (!hasEvidence) {
      next[size] = previous;
      continue;
    }
    const observed = observedSizes[size];
    next[size] = ["AVAILABLE", "UNAVAILABLE"].includes(observed) ?
      observed : previous;
  }
  return next;
}

function deriveLowStockEpisode({
  previous,
  facts,
  selectedSizes,
  catalogRevision,
  syncRunId,
  item,
  now,
  baseline,
}) {
  const state = computeLowStockState(facts, selectedSizes);
  const previousEpisode = previous.lowStockEpisode &&
    typeof previous.lowStockEpisode === "object" ?
    previous.lowStockEpisode : null;
  const wasActive = previousEpisode?.status === "ACTIVE" ||
    previous.lowStockState === "LOW_STOCK";

  if (state !== "LOW_STOCK") {
    return {
      state: state === "NORMAL" ? "NORMAL" : (previous.lowStockState || "UNKNOWN"),
      episode: wasActive ? {
        ...previousEpisode,
        status: "CLOSED",
        closedAt: now,
        closedSyncRunId: syncRunId,
      } : previousEpisode,
      event: null,
    };
  }

  if (wasActive) {
    return {
      state: "LOW_STOCK",
      episode: {
        ...previousEpisode,
        status: "ACTIVE",
        lastQuantitySnapshot: facts.reliableQuantities || {},
      },
      event: null,
    };
  }

  const episodeId = `lse_${crypto.createHash("sha256")
    .update([item.wishlistItemId, catalogRevision, syncRunId].join("|"))
    .digest("hex").slice(0, 24)}`;
  const episode = {
    episodeId,
    status: "ACTIVE",
    enteredAt: now,
    enteredSyncRunId: syncRunId,
    notified: !baseline,
    lastQuantitySnapshot: facts.reliableQuantities || {},
  };
  if (baseline) {
    return {state: "LOW_STOCK", episode: {...episode, notified: false}, event: null};
  }
  const event = buildEvent({
    item,
    condition: "LOW_STOCK_INFO",
    type: EVENT_TYPES.LOW_STOCK_ENTERED,
    oldState: previous.lowStockState || "UNKNOWN",
    newState: "LOW_STOCK",
    catalogRevision,
    syncRunId,
    facts,
    now,
  });
  return {state: "LOW_STOCK", episode, event};
}

function computeLowStockState(facts, selectedSizes) {
  if (facts.partnerReliableLowStockSignal === true) return "LOW_STOCK";
  const values = Object.entries(facts.reliableQuantities || {})
    .filter(([size]) => (selectedSizes || []).includes(size))
    .map(([, quantity]) => quantity)
    .filter((quantity) => Number.isSafeInteger(quantity) && quantity >= 0);
  if (!values.length) return "UNKNOWN";
  return values.some((quantity) =>
    quantity <= LOW_STOCK_QUANTITY_POLICY_V1.maxInclusiveQuantity) ?
    "LOW_STOCK" : "NORMAL";
}

function buildEvent({
  item,
  condition,
  type,
  oldState,
  newState,
  sizeKey = null,
  catalogRevision,
  syncRunId,
  facts,
  now,
}) {
  const identity = [
    item.ownerUid || "",
    item.wishlistItemId,
    condition,
    type,
    oldState,
    newState,
    sizeKey || "",
    catalogRevision || "",
    syncRunId || "",
  ].join("|");
  return {
    eventId: `wev_${crypto.createHash("sha256").update(identity)
      .digest("hex").slice(0, 32)}`,
    schemaVersion: 1,
    ownerUid: item.ownerUid,
    wishlistItemId: item.wishlistItemId,
    variantId: item.variantId,
    condition,
    type,
    sizeKey,
    oldState,
    newState,
    previousState: oldState,
    nextState: newState,
    goldEligible: isGoldEligibleType(type),
    notifyEligible: null,
    effectivePrice: facts.effectivePrice || null,
    targetPrice: item.targetPrice,
    coupon: facts.coupon || null,
    displayName: facts.product?.normalizedModelIdentity ||
      facts.product?.canonicalType || null,
    brand: facts.product?.brand || null,
    catalogRevision,
    syncRunId,
    createdAt: now,
    expiresAt: now + WISHLIST_EVENT_RETENTION_MS_V1,
    delivery: {status: "PENDING", attempts: 0},
  };
}

function isGoldEligibleEvent(event) {
  return isGoldEligibleType(event.type);
}

function isGoldEligibleType(type) {
  return type === EVENT_TYPES.PRICE_TARGET_SATISFIED ||
    type === EVENT_TYPES.SIZE_AVAILABLE;
}

function isPositiveEvent(event) {
  return isGoldEligibleEvent(event);
}

function normalizeStates(raw, selectedSizes) {
  const result = {};
  for (const size of selectedSizes || []) {
    const value = raw?.[size];
    result[size] = ["AVAILABLE", "UNAVAILABLE"].includes(value) ?
      value : "UNKNOWN";
  }
  return result;
}

function normalizeHighlight(raw) {
  if (raw && typeof raw === "object") {
    return {
      state: raw.state === "UNACKNOWLEDGED" ? "UNACKNOWLEDGED" :
        (raw.state === "ACKNOWLEDGED" ? "ACKNOWLEDGED" : "NONE"),
      eventIds: Array.isArray(raw.eventIds) ?
        raw.eventIds.slice(0, WISHLIST_LAST_EVENT_IDS_CAP_V1) : [],
      occurredAt: Number.isSafeInteger(raw.occurredAt) ? raw.occurredAt : null,
      ...(Number.isSafeInteger(raw.acknowledgedAt) ?
        {acknowledgedAt: raw.acknowledgedAt} : {}),
    };
  }
  return {state: "NONE", eventIds: [], occurredAt: null};
}

function withTracking(item, tracking) {
  return {...structuredClone(item), tracking};
}

function sortWishlistItems(items) {
  return [...items].sort((a, b) => {
    const tierA = Number.isInteger(a.tracking?.sortTier) ?
      a.tracking.sortTier : tierFor(a);
    const tierB = Number.isInteger(b.tracking?.sortTier) ?
      b.tracking.sortTier : tierFor(b);
    if (tierA !== tierB) return tierA - tierB;
    const atA = a.tracking?.sortEventAt || a.updatedAt || 0;
    const atB = b.tracking?.sortEventAt || b.updatedAt || 0;
    if (atA !== atB) return atB - atA;
    return String(a.wishlistItemId).localeCompare(String(b.wishlistItemId));
  });
}

function tierFor(item) {
  if (item.tracking?.highlightState === "GOLD" ||
      item.tracking?.highlight?.state === "UNACKNOWLEDGED") return 0;
  if (item.tracking?.lowStockState === "LOW_STOCK") return 1;
  return 2;
}

module.exports = {
  EVENT_TYPES,
  LOW_STOCK_POLICY: LOW_STOCK_QUANTITY_POLICY_V1,
  LOW_STOCK_QUANTITY_POLICY_V1,
  acknowledgeHighlight,
  computeLowStockState,
  evaluateWishlistMonitoring,
  isGoldEligibleEvent,
  isPositiveEvent,
  mergeSizeStates,
  sortWishlistItems,
};
