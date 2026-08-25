"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  createMemoryWishlistV2Repository,
  createWishlistV2Service,
  subscriptionDocId,
  wishlistItemId,
} = require("../wishlist_v2_service");
const {
  createWishlistMonitoringService,
} = require("./wishlist_monitoring_service");
const {CHANGESET_SOURCES} = require("./wishlist_monitoring_constants");
const {EVENT_TYPES} = require("./wishlist_monitoring_engine");

function catalog({price = 2500, size = "UNAVAILABLE", lifecycle = "ACTIVE"} = {}) {
  return {
    products: [{productId: "p", brand: "Brand", normalizedModelIdentity: "Hoodie"}],
    variants: [{
      variantId: "navy", productId: "p", lifecycleState: lifecycle,
      freshness: {stale: false},
    }],
    offers: lifecycle === "DISCONTINUED" ? [] : [{
      offerId: "o1", variantId: "navy", partnerId: "a",
      regularPrice: {amountMinor: price, currency: "EUR"},
      promotions: [], overallAvailability: size,
      lifecycleState: "ACTIVE",
      freshness: {stale: false},
      lastVerifiedAt: "2026-08-15T12:00:00.000Z",
    }],
    sizes: lifecycle === "DISCONTINUED" ? [] : [{
      offerId: "o1", normalizedSizeKey: "M", availability: size,
      exactQuantity: 5, quantityReliability: "EXACT",
    }],
  };
}

function createHarness(initialCatalog) {
  let snapshot = initialCatalog;
  const repository = createMemoryWishlistV2Repository();
  const catalogRepository = {
    async readCompleteSnapshot() {
      return structuredClone(snapshot);
    },
  };
  const delivered = [];
  const notificationService = {
    async deliverOwnerBatch(uid, values, meta) {
      delivered.push({uid, values, meta});
      return {status: "ACCEPTED"};
    },
  };
  const monitoringService = createWishlistMonitoringService({
    repository,
    catalogRepository,
    notificationService,
    now: () => 1_700_000_100_000,
  });
  const service = createWishlistV2Service({
    repository,
    catalogRepository,
    monitoringService,
    now: () => 1_700_000_000_000,
  });
  return {
    service,
    repository,
    monitoringService,
    delivered,
    setCatalog(next) {
      snapshot = next;
    },
  };
}

test("ADD keeps reverse subscription even when monitors are OFF", async () => {
  const harness = createHarness(catalog());
  await harness.service.dispatch({uid: "u1"}, {
    operation: "ADD_OR_UPSERT",
    variantId: "navy",
    selectedSizes: ["M"],
    preferredSize: "M",
    targetPrice: {amountMinor: 2000, currency: "EUR"},
    priceMonitoringEnabled: false,
    sizeMonitoringEnabled: false,
  });
  const itemId = wishlistItemId("u1", "navy");
  const subs = await harness.repository.listSubscribers("navy");
  assert.equal(subs.length, 1);
  assert.equal(subs[0].wishlistItemId, itemId);
  assert.equal(subs[0].informationalEnabled, true);
  assert.equal(
    `${subs[0].variantId}:${subscriptionDocId("u1", itemId)}`.includes(itemId),
    true,
  );
});

test("Refresh All partial failure preserves last-known-good without fake transitions",
  async () => {
    const harness = createHarness(catalog({price: 2500, size: "UNAVAILABLE"}));
    await harness.service.dispatch({uid: "u1"}, {
      operation: "ADD_OR_UPSERT",
      variantId: "navy",
      selectedSizes: ["M"],
      preferredSize: "M",
      targetPrice: {amountMinor: 2000, currency: "EUR"},
      priceMonitoringEnabled: true,
      sizeMonitoringEnabled: true,
    });
    harness.setCatalog({
      products: catalog().products,
      variants: [{
        variantId: "navy", productId: "p", lifecycleState: "ACTIVE",
        freshness: {stale: true},
      }],
      offers: catalog().offers,
      sizes: catalog().sizes,
    });
    const before = await harness.repository.get("u1", wishlistItemId("u1", "navy"));
    const result = await harness.service.dispatch({uid: "u1"}, {
      operation: "REFRESH_ALL",
      operationId: "op1",
    });
    const after = await harness.repository.get("u1", wishlistItemId("u1", "navy"));
    assert.equal(result.failedCount, 1);
    assert.equal(after.tracking.evaluatedPriceState,
      before.tracking.evaluatedPriceState);
    assert.equal(after.tracking.evaluatedSizeStates.M,
      before.tracking.evaluatedSizeStates.M);
    assert.equal(after.tracking.freshness.stale, true);
    assert.equal((await harness.repository.dumpEvents()).length, 0);
  });

test("catalog ChangeSet fanout evaluates only subscribed items", async () => {
  const harness = createHarness(catalog({price: 2500, size: "UNAVAILABLE"}));
  await harness.service.dispatch({uid: "u1"}, {
    operation: "ADD_OR_UPSERT",
    variantId: "navy",
    selectedSizes: ["M"],
    preferredSize: "M",
    targetPrice: {amountMinor: 2000, currency: "EUR"},
    priceMonitoringEnabled: true,
    sizeMonitoringEnabled: true,
  });
  harness.setCatalog(catalog({price: 1900, size: "AVAILABLE"}));
  const result = await harness.monitoringService.processCatalogChangeSet({
    source: CHANGESET_SOURCES.TEST_INJECT,
    syncRunId: "run_price_drop",
    catalogRevision: "rev_price_drop",
    successfulVerificationAt: "2026-08-15T12:00:00.000Z",
    changedVariantIds: ["navy"],
  });
  assert.equal(result.updatedCount, 1);
  const events = await harness.repository.dumpEvents();
  assert.ok(events.some((event) =>
    event.type === EVENT_TYPES.PRICE_TARGET_SATISFIED));
  assert.ok(events.some((event) => event.type === EVENT_TYPES.SIZE_AVAILABLE));
  assert.equal(harness.delivered.length, 1);
  assert.equal(harness.delivered[0].meta.syncRunId, "run_price_drop");
});

test("duplicate refresh lease prevents concurrent Refresh All", async () => {
  const harness = createHarness(catalog());
  await harness.service.dispatch({uid: "u1"}, {
    operation: "ADD_OR_UPSERT",
    variantId: "navy",
    selectedSizes: ["M"],
    preferredSize: "M",
    targetPrice: {amountMinor: 2000, currency: "EUR"},
    priceMonitoringEnabled: true,
    sizeMonitoringEnabled: true,
  });
  const now = 1_700_000_100_000;
  await harness.repository.acquireRefreshLease("u1", "opA", now, 60_000);
  const result = await harness.service.dispatch({uid: "u1"}, {
    operation: "REFRESH_ALL",
    operationId: "opB",
  });
  assert.equal(result.status, "REFRESH_IN_PROGRESS");
});
