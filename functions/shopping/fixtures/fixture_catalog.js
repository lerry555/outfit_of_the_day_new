"use strict";

const {AVAILABILITY, PROMOTION_KIND, QUANTITY_RELIABILITY} =
  require("../catalog_contract");

const navyRecord = Object.freeze({
  fixtureProductRef: "model-hoodie",
  fixtureVariantRef: "model-hoodie-navy",
  fixtureListingRef: "navy-a",
  fixtureBrand: "Fixture Brand",
  fixtureModelIdentity: "everyday-hoodie",
  fixtureCanonicalType: "hoodie",
  fixtureCanonicalFamily: "top",
  fixtureProductEvidence: {manufacturerModelId: "HOODIE-MODEL-1"},
  fixtureVariantEvidence: {manufacturerSku: "HOODIE-NAVY-1"},
  fixtureColorName: "Navy",
  fixtureColorCode: "NVY",
  fixtureColorProfile: {primary: {family: "navy"}, accents: []},
  fixtureRegularPrice: {amountMinor: 4900, currency: "EUR"},
  fixtureOfferAvailability: AVAILABILITY.AVAILABLE,
  fixtureSizes: [{
    normalizedSizeKey: "M", partnerSizeLabel: "M", sizeSystem: "INTL",
    availability: AVAILABILITY.AVAILABLE,
    exactQuantity: 3, quantityReliability: QUANTITY_RELIABILITY.EXACT,
  }],
  fixtureObservedAt: "2026-08-15T10:00:00.000Z",
});

const navyCouponRecord = Object.freeze({
  ...navyRecord,
  fixtureListingRef: "navy-b",
  fixtureRegularPrice: {amountMinor: 4500, currency: "EUR"},
  fixturePromotions: [{
    kind: PROMOTION_KIND.PUBLIC_COUPON,
    price: {amountMinor: 3900, currency: "EUR"},
    code: "FIXTURE10",
  }],
  fixtureSizes: [{
    normalizedSizeKey: "M", partnerSizeLabel: "M", sizeSystem: "INTL",
    availability: AVAILABILITY.UNAVAILABLE,
  }, {
    normalizedSizeKey: "L", partnerSizeLabel: "L", sizeSystem: "INTL",
    availability: AVAILABILITY.AVAILABLE,
  }],
});

const whiteRecord = Object.freeze({
  ...navyRecord,
  fixtureVariantRef: "model-hoodie-white",
  fixtureListingRef: "white-a",
  fixtureVariantEvidence: {manufacturerSku: "HOODIE-WHITE-1"},
  fixtureColorName: "White",
  fixtureColorCode: "WHT",
  fixtureColorProfile: {primary: {family: "white"}, accents: []},
  fixtureRegularPrice: {amountMinor: 2900, currency: "EUR"},
  fixtureSizes: [{
    normalizedSizeKey: "M", partnerSizeLabel: "M", sizeSystem: "INTL",
    availability: AVAILABILITY.AVAILABLE,
  }],
});

const weakSimilarA = Object.freeze({
  ...navyRecord,
  fixtureProductRef: "lookalike-a",
  fixtureVariantRef: "lookalike-a-navy",
  fixtureListingRef: "lookalike-a",
  fixtureModelIdentity: "soft navy hoodie",
  fixtureProductEvidence: {},
  fixtureVariantEvidence: {},
  fixtureRegularPrice: {amountMinor: 3100, currency: "EUR"},
});

const weakSimilarB = Object.freeze({
  ...weakSimilarA,
  fixtureProductRef: "lookalike-b",
  fixtureVariantRef: "lookalike-b-navy",
  fixtureListingRef: "lookalike-b",
});

const memberOnlyRecord = Object.freeze({
  ...navyRecord,
  fixtureListingRef: "member-only",
  fixtureRegularPrice: {amountMinor: 5500, currency: "EUR"},
  fixturePromotions: [{
    kind: PROMOTION_KIND.MEMBER_ONLY,
    price: {amountMinor: 4500, currency: "EUR"},
  }],
});

function fixturePartnerConfig(partnerId, domain) {
  return {
    partnerId,
    publicStoreName: `Fixture Store ${partnerId}`,
    allowedDomains: [domain],
    capabilities: ["full_snapshot", "size_availability", "public_coupon"],
  };
}

function withUrl(record, domain) {
  return {...record, fixtureUrl: `https://${domain}/products/${record.fixtureListingRef}`};
}

module.exports = {
  fixturePartnerConfig,
  memberOnlyRecord,
  navyCouponRecord,
  navyRecord,
  weakSimilarA,
  weakSimilarB,
  whiteRecord,
  withUrl,
};
