"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {createMemoryCatalogSearchRepository} = require("./catalog_search_repository");
const {
  createMemoryWishlistV2Repository,
  createWishlistV2Service,
} = require("./wishlist_v2_service");

function catalog({price = 1800, availability = "AVAILABLE"} = {}) {
  return {
    partners: [{partnerId: "store", publicStoreName: "Store", allowedDomains: ["store.test"]}],
    products: [{productId: "p", brand: "Brand", normalizedModelIdentity: "Hoodie",
      canonicalType: "hoodie", canonicalFamily: "top"}],
    variants: [{variantId: "v", productId: "p", exactColorName: "Navy",
      colorProfile: {primary: {family: "navy"}}, lifecycleState: "ACTIVE"}],
    offers: [{offerId: "o", variantId: "v", partnerId: "store",
      url: "https://store.test/v", regularPrice: {amountMinor: price, currency: "EUR"},
      promotions: [], overallAvailability: "AVAILABLE", lifecycleState: "ACTIVE",
      lastVerifiedAt: "2026-08-15T10:00:00.000Z", freshness: {stale: false}}],
    sizes: [
      {offerId: "o", normalizedSizeKey: "M", partnerSizeLabel: "M",
        availability, quantityReliability: "UNKNOWN"},
      {offerId: "o", normalizedSizeKey: "L", partnerSizeLabel: "L",
        availability: "UNKNOWN", quantityReliability: "UNKNOWN"},
    ],
  };
}
function request(overrides = {}) {
  return {
    operation: "ADD_OR_UPSERT", variantId: "v", selectedSizes: ["M"],
    preferredSize: "M", targetPrice: {amountMinor: 2000, currency: "EUR"},
    priceMonitoringEnabled: true, sizeMonitoringEnabled: true, ...overrides,
  };
}
function service(input = catalog()) {
  const repository = createMemoryWishlistV2Repository();
  return {
    repository,
    value: createWishlistV2Service({
      repository,
      catalogRepository: createMemoryCatalogSearchRepository(input),
      now: () => 1000,
    }),
  };
}

test("creation initializes satisfied/available baseline without event or gold", async () => {
  const app = service();
  const result = await app.value.dispatch({uid: "a"}, request());
  assert.equal(result.status, "CREATED");
  assert.equal(result.item.tracking.evaluatedPriceState, "SATISFIED");
  assert.equal(result.item.tracking.evaluatedSizeStates.M, "AVAILABLE");
  assert.deepEqual(result.item.tracking.lastEventIds, []);
  assert.equal(result.item.tracking.highlightState, "NONE");
});

test("unsatisfied, unavailable and unknown baselines remain distinct", async () => {
  const unavailable = await service(catalog({price: 2500, availability: "UNAVAILABLE"}))
    .value.dispatch({uid: "a"}, request());
  assert.equal(unavailable.item.tracking.evaluatedPriceState, "UNSATISFIED");
  assert.equal(unavailable.item.tracking.evaluatedSizeStates.M, "UNAVAILABLE");
  const unknown = await service(catalog({availability: "UNKNOWN"}))
    .value.dispatch({uid: "a"}, request());
  assert.equal(unknown.item.tracking.evaluatedSizeStates.M, "UNKNOWN");
});

test("duplicate add is owner+variant idempotent and updates intent", async () => {
  const app = service(catalog({price: 2500}));
  const first = await app.value.dispatch({uid: "a"}, request());
  const second = await app.value.dispatch({uid: "a"}, request({
    targetPrice: {amountMinor: 3000, currency: "EUR"},
  }));
  assert.equal(second.status, "UPDATED");
  assert.equal(second.item.wishlistItemId, first.item.wishlistItemId);
  assert.equal(second.item.tracking.evaluatedPriceState, "SATISFIED");
  assert.equal(app.repository.dump().length, 1);
  assert.deepEqual(second.item.tracking.lastEventIds, []);
});

test("multi-size update baselines new size and monitoring disable preserves target", async () => {
  const app = service();
  await app.value.dispatch({uid: "a"}, request());
  const result = await app.value.dispatch({uid: "a"}, request({
    operation: "UPDATE_INTENT", selectedSizes: ["M", "L"], preferredSize: "L",
    priceMonitoringEnabled: false,
  }));
  assert.equal(result.item.preferredSize, "L");
  assert.equal(result.item.tracking.evaluatedSizeStates.L, "UNKNOWN");
  assert.equal(result.item.targetPrice.amountMinor, 2000);
});

test("validation rejects forged state, invalid size/preference/money and missing auth", async () => {
  const app = service();
  await assert.rejects(app.value.dispatch(null, request()), (error) => error.code === "UNAUTHENTICATED");
  await assert.rejects(app.value.dispatch({uid: "a"}, request({gold: true})),
    (error) => error.code === "FORGED_SERVER_STATE");
  await assert.rejects(app.value.dispatch({uid: "a"}, request({
    selectedSizes: ["XL"], preferredSize: "XL",
  })),
    (error) => error.code === "INVALID_SELECTED_SIZE");
  await assert.rejects(app.value.dispatch({uid: "a"}, request({preferredSize: "L"})),
    (error) => error.code === "PREFERRED_SIZE_NOT_SELECTED");
  await assert.rejects(app.value.dispatch({uid: "a"}, request({targetPrice: null})),
    (error) => error.code === "INVALID_TARGET_PRICE");
});

test("users list/remove only their deterministic item", async () => {
  const app = service();
  await app.value.dispatch({uid: "a"}, request());
  assert.equal((await app.value.dispatch({uid: "b"}, {operation: "GET_ITEMS"})).items.length, 0);
  assert.equal((await app.value.dispatch({uid: "a"}, {operation: "GET_ITEMS"})).items.length, 1);
  assert.equal((await app.value.dispatch({uid: "b"}, {operation: "REMOVE", variantId: "v"})).status,
    "NOT_FOUND");
  assert.equal((await app.value.dispatch({uid: "a"}, {operation: "REMOVE", variantId: "v"})).status,
    "REMOVED");
});
