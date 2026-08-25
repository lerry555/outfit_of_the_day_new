"use strict";

const crypto = require("crypto");
const {catalogRevisionFor} = require("../catalog_search_service");
const {normalizeCatalogChangeSet} = require("./catalog_change_set");
const {CHANGESET_SOURCES} = require("./wishlist_monitoring_constants");
const {
  WISHLIST_REFRESH_LEASE_MS_V1,
  WISHLIST_REFRESH_MAX_ITEMS_V1,
  WISHLIST_VARIANT_CHUNK_SIZE_V1,
} = require("./wishlist_monitoring_constants");
const {deriveWishlistCatalogFacts} = require("./wishlist_catalog_facts");
const {
  acknowledgeHighlight,
  evaluateWishlistMonitoring,
  sortWishlistItems,
} = require("./wishlist_monitoring_engine");

function createWishlistMonitoringService({
  repository,
  catalogRepository,
  notificationService = null,
  now = () => Date.now(),
}) {
  if (!repository || !catalogRepository) {
    throw new Error("wishlist_monitoring_dependencies_required");
  }

  async function refreshAll(uid, {operationId = opaqueId()} = {}) {
    const timestamp = now();
    const acquired = await repository.acquireRefreshLease(
      uid, operationId, timestamp, WISHLIST_REFRESH_LEASE_MS_V1);
    if (!acquired) return {status: "REFRESH_IN_PROGRESS", operationId};
    try {
      const allItems = await repository.list(uid);
      const truncated = allItems.length > WISHLIST_REFRESH_MAX_ITEMS_V1;
      const items = allItems
        .slice()
        .sort((a, b) => String(a.wishlistItemId)
          .localeCompare(String(b.wishlistItemId)))
        .slice(0, WISHLIST_REFRESH_MAX_ITEMS_V1);
      const catalog = await catalogRepository.readCompleteSnapshot();
      const syncRunId = `manual_refresh_all_${operationId}`;
      const result = await evaluateItems({
        items,
        catalog,
        catalogRevision: catalogRevisionFor(catalog),
        syncRunId,
      });
      await deliver([...new Set(items.map((item) => item.ownerUid || uid))],
        syncRunId);
      return {
        ...response("OK", operationId, result),
        truncated,
        truncatedCount: truncated ?
          allItems.length - WISHLIST_REFRESH_MAX_ITEMS_V1 : 0,
        maxItems: WISHLIST_REFRESH_MAX_ITEMS_V1,
      };
    } finally {
      await repository.releaseRefreshLease(uid, operationId);
    }
  }

  async function refreshItem(uid, itemId, {
    source = CHANGESET_SOURCES.MANUAL_REFRESH,
  } = {}) {
    const item = await repository.getByItemId(uid, itemId);
    if (!item) return {status: "NOT_FOUND", itemId};
    const catalog = await catalogRepository.readCompleteSnapshot();
    const catalogRevision = catalogRevisionFor(catalog);
    const syncRunId = `${String(source).toLowerCase()}_${itemId}_${catalogRevision}`;
    const result = await evaluateItems({
      items: [item],
      catalog,
      catalogRevision,
      syncRunId,
    });
    await deliver([uid], syncRunId);
    return response("OK", null, result);
  }

  async function processCatalogChangeSet(raw) {
    const catalog = await catalogRepository.readCompleteSnapshot();
    const expanded = expandVariantIds(catalog, {
      changedOfferIds: Array.isArray(raw?.changedOfferIds) ?
        raw.changedOfferIds : [],
      changedSizeIds: Array.isArray(raw?.changedSizeIds) ?
        raw.changedSizeIds : [],
    });
    const changeSet = normalizeCatalogChangeSet({
      ...raw,
      source: raw?.source || CHANGESET_SOURCES.CATALOG_SYNC,
      syncRunId: raw?.syncRunId || raw?.changeSetId || opaqueId(),
      catalogRevision: raw?.catalogRevision || catalogRevisionFor(catalog),
      successfulVerificationAt: raw?.successfulVerificationAt || null,
      changedVariantIds: [
        ...(Array.isArray(raw?.changedVariantIds) ? raw.changedVariantIds : []),
        ...expanded,
      ],
    });

    const uniqueItems = new Map();
    for (let index = 0; index < changeSet.changedVariantIds.length;
      index += WISHLIST_VARIANT_CHUNK_SIZE_V1) {
      const chunk = changeSet.changedVariantIds.slice(
        index, index + WISHLIST_VARIANT_CHUNK_SIZE_V1);
      for (const variantId of chunk) {
        const subscribers = await repository.listSubscribers(variantId);
        for (const subscriber of subscribers) {
          const item = await repository.getByItemId(
            subscriber.ownerUid || subscriber.userId,
            subscriber.wishlistItemId);
          if (item && item.variantId === variantId) {
            uniqueItems.set(
              `${item.ownerUid}:${item.wishlistItemId}`, item);
          }
        }
      }
    }

    const result = await evaluateItems({
      items: [...uniqueItems.values()],
      catalog,
      catalogRevision: changeSet.catalogRevision,
      syncRunId: changeSet.syncRunId,
    });
    await deliver([...new Set(
      [...uniqueItems.values()].map((item) => item.ownerUid))],
    changeSet.syncRunId);
    return response("OK", changeSet.syncRunId, result);
  }

  async function acknowledge(uid, itemIds, eventIds = null) {
    const ids = [...new Set(itemIds || [])].slice(0, WISHLIST_REFRESH_MAX_ITEMS_V1);
    let acknowledged = 0;
    for (const itemId of ids) {
      const value = await repository.acknowledge(uid, itemId, (item) =>
        acknowledgeHighlight(item, now(), eventIds));
      if (value) acknowledged++;
    }
    return {status: "OK", acknowledged};
  }

  async function evaluateItems({items, catalog, catalogRevision, syncRunId}) {
    const changedItemIds = [];
    const goldItemIds = [];
    const failures = [];
    const succeeded = [];
    for (const item of items) {
      try {
        const facts = deriveWishlistCatalogFacts(catalog, item);
        const evaluated = evaluateWishlistMonitoring({
          item,
          facts,
          catalogRevision,
          syncRunId,
          now: now(),
        });
        const createdEvents = await repository.saveEvaluation(
          item.ownerUid, evaluated.item, evaluated.events);
        if (facts.successfulVerification !== true) {
          failures.push({
            wishlistItemId: item.wishlistItemId,
            code: facts.failureCode || "REFRESH_FAILED",
            stale: true,
          });
        } else {
          succeeded.push(item.wishlistItemId);
        }
        changedItemIds.push(item.wishlistItemId);
        if (evaluated.newlyGold && createdEvents.length) {
          goldItemIds.push(item.wishlistItemId);
        }
      } catch (error) {
        // Preserve last-known-good by writing failure freshness only when
        // possible; never invent transitions on thrown failures.
        try {
          const failed = evaluateWishlistMonitoring({
            item,
            facts: {successfulVerification: false, failureCode: "REFRESH_FAILED"},
            catalogRevision,
            syncRunId,
            now: now(),
          });
          await repository.saveEvaluation(item.ownerUid, failed.item, []);
        } catch (_) {
          // ignore secondary persistence errors
        }
        failures.push({
          wishlistItemId: item.wishlistItemId,
          code: error?.code || error?.message || "REFRESH_FAILED",
          stale: true,
        });
        changedItemIds.push(item.wishlistItemId);
      }
    }
    return {
      changedItemIds,
      goldItemIds,
      failures,
      succeeded,
      total: items.length,
    };
  }

  async function deliver(ownerUids, syncRunId) {
    if (!notificationService) return;
    for (const uid of ownerUids) {
      const pending = await repository.listPendingEvents(uid);
      const grouped = new Map();
      for (const event of pending) {
        if (event.syncRunId && syncRunId && event.syncRunId !== syncRunId) {
          // Still deliver older pending retries; keep them in the batch.
        }
        const values = grouped.get(event.wishlistItemId) || [];
        values.push(event);
        grouped.set(event.wishlistItemId, values);
      }
      const values = [];
      for (const [itemId, events] of grouped) {
        const item = await repository.getByItemId(uid, itemId);
        if (item) values.push({item, events});
      }
      if (values.length) {
        await notificationService.deliverOwnerBatch(uid, values, {syncRunId});
      }
    }
  }

  return {
    acknowledge,
    processCatalogChangeSet,
    refreshAll,
    refreshItem,
    sortWishlistItems,
  };
}

function expandVariantIds(catalog, changeSet) {
  if (!catalog) return [];
  const fromOffers = new Set();
  const offerIds = new Set(changeSet.changedOfferIds || []);
  const sizeIds = new Set(changeSet.changedSizeIds || []);
  for (const offer of catalog.offers || []) {
    if (offerIds.has(offer.offerId)) fromOffers.add(offer.variantId);
  }
  for (const size of catalog.sizes || []) {
    if (!sizeIds.has(size.sizeId || size.id)) continue;
    const offer = (catalog.offers || []).find((value) =>
      value.offerId === size.offerId);
    if (offer) fromOffers.add(offer.variantId);
  }
  return [...fromOffers];
}

function uniqueIds(values) {
  return [...new Set(values.map(String))];
}

function response(status, operationId, result) {
  return {
    status,
    operationId,
    total: result.total,
    updatedCount: result.succeeded.length,
    failedCount: result.failures.length,
    changedItemIds: result.changedItemIds,
    goldItemIds: result.goldItemIds,
    failures: result.failures,
    items: result.succeeded.map((wishlistItemId) => ({
      wishlistItemId,
      status: "UPDATED",
    })).concat(result.failures.map((failure) => ({
      wishlistItemId: failure.wishlistItemId,
      status: "FAILED",
      code: failure.code,
      stale: true,
    }))),
  };
}

function opaqueId() {
  return crypto.randomBytes(12).toString("base64url");
}

module.exports = {
  CHANGESET_SOURCES,
  createWishlistMonitoringService,
};
