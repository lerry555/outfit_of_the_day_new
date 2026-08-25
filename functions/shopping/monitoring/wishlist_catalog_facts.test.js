"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {deriveWishlistCatalogFacts} = require("./wishlist_catalog_facts");

function item() {
  return {
    variantId: "navy", selectedSizes: ["M"], preferredSize: "M",
    targetPrice: {amountMinor: 2000, currency: "EUR"},
  };
}
function catalog() {
  return {
    products: [{productId: "p", brand: "Brand", normalizedModelIdentity: "Hoodie"}],
    variants: [
      {variantId: "navy", productId: "p", lifecycleState: "ACTIVE",
        freshness: {stale: false}},
      {variantId: "white", productId: "p", lifecycleState: "ACTIVE",
        freshness: {stale: false}},
    ],
    offers: [{
      offerId: "a", variantId: "navy", partnerId: "a",
      regularPrice: {amountMinor: 2500, currency: "EUR"},
      promotions: [], overallAvailability: "AVAILABLE", lifecycleState: "ACTIVE",
      freshness: {stale: false}, lastVerifiedAt: "2026-08-15T10:00:00.000Z",
    }, {
      offerId: "white-cheap", variantId: "white", partnerId: "a",
      regularPrice: {amountMinor: 1000, currency: "EUR"},
      promotions: [], overallAvailability: "AVAILABLE", lifecycleState: "ACTIVE",
      freshness: {stale: false},
    }],
    sizes: [
      {offerId: "a", normalizedSizeKey: "M", availability: "AVAILABLE",
        exactQuantity: 3, quantityReliability: "EXACT"},
      {offerId: "white-cheap", normalizedSizeKey: "M", availability: "AVAILABLE",
        quantityReliability: "UNKNOWN"},
    ],
  };
}

test("exact color variant isolates unrelated cheaper color", () => {
  const result = deriveWishlistCatalogFacts(catalog(), item());
  assert.equal(result.effectivePrice.amountMinor, 2500);
  assert.equal(result.priceState, "UNSATISFIED");
  assert.equal(result.reliableQuantities.M, 3);
});

test("public coupon reaches target and preserves coupon code", () => {
  const value = catalog();
  value.offers[0].promotions = [{
    kind: "PUBLIC_COUPON",
    price: {amountMinor: 1900, currency: "EUR"},
    code: "SAVE6",
  }];
  const result = deriveWishlistCatalogFacts(value, item());
  assert.equal(result.priceState, "SATISFIED");
  assert.deepEqual(result.coupon, {required: true, code: "SAVE6"});
});

test("member price never satisfies public target", () => {
  const value = catalog();
  value.offers[0].promotions = [{
    kind: "MEMBER_ONLY",
    price: {amountMinor: 1800, currency: "EUR"},
  }];
  const result = deriveWishlistCatalogFacts(value, item());
  assert.equal(result.priceState, "UNSATISFIED");
  assert.equal(result.effectivePrice.amountMinor, 2500);
});

test("new valid store becomes best and disappearing restores unsatisfied price", () => {
  const value = catalog();
  value.offers.push({
    offerId: "b", variantId: "navy", partnerId: "b",
    regularPrice: {amountMinor: 1900, currency: "EUR"},
    promotions: [], overallAvailability: "AVAILABLE", lifecycleState: "ACTIVE",
    freshness: {stale: false},
  });
  value.sizes.push({
    offerId: "b", normalizedSizeKey: "M", availability: "AVAILABLE",
    quantityReliability: "UNKNOWN",
  });
  assert.equal(deriveWishlistCatalogFacts(value, item()).priceState, "SATISFIED");
  value.offers.find((offer) => offer.offerId === "b").lifecycleState =
    "DISCONTINUED";
  assert.equal(deriveWishlistCatalogFacts(value, item()).priceState, "UNSATISFIED");
});

test("stale catalog is a failed refresh, never unavailable", () => {
  const value = catalog();
  value.variants[0].freshness.stale = true;
  const result = deriveWishlistCatalogFacts(value, item());
  assert.equal(result.successfulVerification, false);
  assert.equal(result.failureCode, "CATALOG_STALE");
  assert.deepEqual(result.sizeStates, {});
  assert.deepEqual(result.sizeEvidence, {});
});

test("discontinued without size evidence does not claim UNAVAILABLE", () => {
  const value = catalog();
  value.variants[0].lifecycleState = "DISCONTINUED";
  value.offers = [];
  value.sizes = [];
  const result = deriveWishlistCatalogFacts(value, item());
  assert.equal(result.successfulVerification, true);
  assert.equal(result.lifecycleState, "DISCONTINUED");
  assert.equal(result.sizeEvidence.M, false);
  assert.equal(Object.prototype.hasOwnProperty.call(result.sizeStates, "M"),
    false);
});

test("discontinued with authoritative UNAVAILABLE size evidence reports it", () => {
  const value = catalog();
  value.variants[0].lifecycleState = "DISCONTINUED";
  value.offers[0].lifecycleState = "DISCONTINUED";
  value.sizes[0].availability = "UNAVAILABLE";
  const result = deriveWishlistCatalogFacts(value, item());
  assert.equal(result.sizeEvidence.M, true);
  assert.equal(result.sizeStates.M, "UNAVAILABLE");
});
