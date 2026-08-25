"use strict";

const {PARTNER_CAPABILITY} = require("../partner_capabilities");
const {createBasePartnerAdapter} = require("../partner_normalize");
const {createPartnerError, PARTNER_ERROR} = require("../partner_errors");

/**
 * Synthetic Partner C — partial API, unknown sizes, schema drift, rate limit,
 * retry scenarios via injectable transport.
 */
const ADAPTER_KEY = "synthetic_partner_c_partial";
const ADAPTER_VERSION = "1";

function createSyntheticPartnerCAdapter({
  transport,
  pageSize = 25,
} = {}) {
  const publicConfig = {
    partnerId: "synthetic_c_eu",
    displayName: "Synthetic Partner C",
    publicStoreName: "Synthetic Partner C",
    status: "ACTIVE",
    market: "EU",
    currency: "EUR",
    allowedDomains: ["api.synthetic-c.test", "shop.synthetic-c.test"],
    adapterKey: ADAPTER_KEY,
    adapterVersion: ADAPTER_VERSION,
    capabilities: [
      PARTNER_CAPABILITY.FULL_CATALOG_SNAPSHOT,
      PARTNER_CAPABILITY.INCREMENTAL_UPDATES,
      PARTNER_CAPABILITY.STABLE_PARTNER_PRODUCT_ID,
      PARTNER_CAPABILITY.STABLE_VARIANT_ID,
      PARTNER_CAPABILITY.PRICE,
      PARTNER_CAPABILITY.SIZE_AVAILABILITY,
      PARTNER_CAPABILITY.MARKET_SCOPE,
      PARTNER_CAPABILITY.CURRENCY,
      PARTNER_CAPABILITY.PAGINATION,
      PARTNER_CAPABILITY.POLLING,
    ],
  };

  if (typeof transport !== "function") {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_c_transport_required",
    );
  }

  return createBasePartnerAdapter({
    publicConfig,
    privateConfigDefaults: {
      rateLimit: {
        pageSize,
        requestsPerSecond: 2,
        requestsPerMinute: 60,
        maxPagesPerRun: 100,
      },
      authMethod: "bearer",
      secretRef: "SHOPPING_PARTNER_SECRET_SLOT_A",
    },
    async fetchPage(args) {
      return transport(args);
    },
  });
}

function samplePartnerCRecord(overrides = {}) {
  return {
    partnerProductId: "c-prod-1",
    partnerVariantId: "c-var-black",
    partnerListingId: "c-list-1",
    brand: "PartialBrand",
    modelIdentity: "PB-1",
    canonicalType: "jeans",
    canonicalFamily: "bottoms",
    colorName: "Black",
    colorProfile: {primary: {family: "black"}},
    productEvidence: {
      reliablePartnerProductId: "synthetic_c_eu:c-prod-1",
    },
    variantEvidence: {
      reliablePartnerVariantId: "synthetic_c_eu:c-var-black",
    },
    url: "https://shop.synthetic-c.test/c-prod-1",
    regularPrice: {amountMinor: 7900, currency: "EUR"},
    promotions: [],
    offerAvailability: "AVAILABLE",
    sizes: [{
      normalizedSizeKey: "32",
      partnerSizeLabel: "32",
      sizeSystem: "EU",
      // Missing availability → UNKNOWN
    }],
    images: [],
    observedAt: "2026-08-15T12:00:00.000Z",
    ...overrides,
  };
}

module.exports = {
  ADAPTER_KEY,
  ADAPTER_VERSION,
  createSyntheticPartnerCAdapter,
  samplePartnerCRecord,
};
