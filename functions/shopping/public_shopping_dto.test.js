"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {buildPublicCandidateDetail} = require("./public_shopping_dto");

function input() {
  const candidate = {
    variantId: "v1", productId: "p1", relevantOfferIds: ["o1", "o2"],
    bestOfferId: "o1", rankingComponents: {hardConstraintGate: true},
  };
  const catalog = {
    products: [{productId: "p1", brand: "Brand", normalizedModelIdentity: "Hoodie",
      canonicalType: "hoodie", canonicalFamily: "top", privateIdentity: "never"}],
    variants: [{variantId: "v1", productId: "p1", exactColorName: "Navy",
      colorProfile: {primary: {family: "navy"}}, lifecycleState: "ACTIVE"}],
    partners: [
      {partnerId: "a", publicStoreName: "Store A", allowedDomains: ["a.test"], secret: "never"},
      {partnerId: "b", publicStoreName: "Store B", allowedDomains: ["b.test"], secret: "never"},
    ],
    offers: [{
      offerId: "o1", variantId: "v1", partnerId: "a", url: "https://a.test/v1",
      regularPrice: {amountMinor: 5000, currency: "EUR"},
      promotions: [{kind: "PUBLIC_SALE", price: {amountMinor: 4500, currency: "EUR"}},
        {kind: "MEMBER_ONLY", price: {amountMinor: 3000, currency: "EUR"}}],
      overallAvailability: "AVAILABLE", lifecycleState: "ACTIVE",
      lastVerifiedAt: "2026-08-15T10:00:00.000Z", freshness: {stale: false},
      affiliateCommission: 999,
    }, {
      offerId: "o2", variantId: "v1", partnerId: "b", url: "https://evil.test/v1",
      regularPrice: {amountMinor: 3900, currency: "EUR"},
      promotions: [{kind: "PUBLIC_COUPON", price: {amountMinor: 3500, currency: "EUR"},
        code: "SAVE"}],
      overallAvailability: "AVAILABLE", lifecycleState: "ACTIVE",
      freshness: {stale: true, lastSuccessfulVerificationAt: "2026-08-15T09:00:00.000Z"},
    }],
    sizes: [{
      offerId: "o1", normalizedSizeKey: "M", partnerSizeLabel: "M",
      availability: "AVAILABLE", exactQuantity: 3, quantityReliability: "EXACT",
      observedAt: "2026-08-15T10:00:00.000Z",
    }, {
      offerId: "o2", normalizedSizeKey: "M", partnerSizeLabel: "M",
      availability: "UNAVAILABLE", exactQuantity: null, quantityReliability: "UNKNOWN",
    }],
  };
  const query = {selectedSizeKeys: ["M"], preferredSizeKey: "M", availableNow: false};
  return {candidate, catalog, query};
}

test("v2 detail exposes authoritative sale, store, selected size, quantity and freshness", () => {
  const result = buildPublicCandidateDetail(input());
  assert.equal(result.shoppingDtoVersion, 2);
  assert.equal(result.primaryOffer.store.displayName, "Store A");
  assert.equal(result.primaryOffer.regularPrice.amountMinor, 5000);
  assert.equal(result.primaryOffer.salePrice.amountMinor, 4500);
  assert.equal(result.primaryOffer.effectivePrice.price.amountMinor, 4500);
  assert.equal(result.primaryOffer.selectedSizes[0].reliableQuantity, 3);
  assert.equal(result.primaryOffer.freshness.priceVerifiedAt, "2026-08-15T10:00:00.000Z");
});

test("member price is excluded and coupon remains explicit", () => {
  const result = buildPublicCandidateDetail(input());
  assert.notEqual(result.primaryOffer.effectivePrice.price.amountMinor, 3000);
  const coupon = result.offers.find((offer) => offer.offerId === "o2");
  assert.equal(coupon.effectivePrice.price.amountMinor, 3500);
  assert.equal(coupon.effectivePrice.requiresPublicCoupon, true);
  assert.equal(coupon.effectivePrice.couponCode, "SAVE");
});

test("invalid partner-domain URL and private/affiliate fields never leak", () => {
  const result = buildPublicCandidateDetail(input());
  assert.equal(result.offers.find((offer) => offer.offerId === "o2").url, null);
  const encoded = JSON.stringify(result);
  assert.equal(encoded.includes("privateIdentity"), false);
  assert.equal(encoded.includes("secret"), false);
  assert.equal(encoded.includes("affiliate"), false);
});

test("unreliable quantity is null and unavailable remains distinct from unknown", () => {
  const result = buildPublicCandidateDetail(input());
  const second = result.offers.find((offer) => offer.offerId === "o2");
  assert.equal(second.selectedSizes[0].reliableQuantity, null);
  assert.equal(second.selectedSizes[0].availability, "UNAVAILABLE");
});
