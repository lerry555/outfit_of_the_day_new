"use strict";

const {PARTNER_CAPABILITY} = require("../partner_capabilities");
const {createBasePartnerAdapter} = require("../partner_normalize");
const {PROMOTION_KIND} = require("../../catalog_contract");
const {PARTNER_IMAGE_ROLE} = require("../partner_images");

/**
 * Synthetic Partner B — incremental, no GTIN, manufacturer SKU, no quantity,
 * member pricing, unreliable product-only image claim.
 */
const ADAPTER_KEY = "synthetic_partner_b_incremental";
const ADAPTER_VERSION = "1";

function createSyntheticPartnerBAdapter({
  records = [],
  pageSize = 50,
} = {}) {
  const publicConfig = {
    partnerId: "synthetic_b_cz",
    displayName: "Synthetic Partner B",
    publicStoreName: "Synthetic Partner B",
    status: "ACTIVE",
    market: "CZ",
    currency: "CZK",
    allowedDomains: ["cdn.synthetic-b.test", "shop.synthetic-b.test"],
    adapterKey: ADAPTER_KEY,
    adapterVersion: ADAPTER_VERSION,
    capabilities: [
      PARTNER_CAPABILITY.INCREMENTAL_UPDATES,
      PARTNER_CAPABILITY.DELTA_CURSOR,
      PARTNER_CAPABILITY.MANUFACTURER_SKU,
      PARTNER_CAPABILITY.STABLE_PARTNER_PRODUCT_ID,
      PARTNER_CAPABILITY.STABLE_VARIANT_ID,
      PARTNER_CAPABILITY.PRICE,
      PARTNER_CAPABILITY.MEMBER_PRICING,
      PARTNER_CAPABILITY.SIZE_AVAILABILITY,
      PARTNER_CAPABILITY.MULTIPLE_IMAGES,
      PARTNER_CAPABILITY.IMAGE_ROLES,
      PARTNER_CAPABILITY.MARKET_SCOPE,
      PARTNER_CAPABILITY.CURRENCY,
      PARTNER_CAPABILITY.PAGINATION,
    ],
  };

  const all = [...records];

  return createBasePartnerAdapter({
    publicConfig,
    privateConfigDefaults: {
      rateLimit: {pageSize, requestsPerSecond: 10, requestsPerMinute: 300},
    },
    async fetchPage({pageToken, pageSize: size, mode}) {
      if (mode !== "INCREMENTAL") {
        const err = new Error("partner_incremental_only");
        err.code = "FATAL_CONFIGURATION";
        throw err;
      }
      const start = pageToken ? Number(pageToken) : 0;
      const slice = all.slice(start, start + size);
      const next = start + size;
      const done = next >= all.length;
      return {
        records: slice,
        nextPageToken: done ? null : String(next),
        done,
        completenessGuaranteed: false,
      };
    },
  });
}

function samplePartnerBRecord(overrides = {}) {
  return {
    partnerProductId: "b-prod-9",
    partnerVariantId: "b-var-white",
    partnerListingId: "b-list-9",
    brand: "OtherBrand",
    modelIdentity: "OB-HOOD-9",
    canonicalType: "hoodie",
    canonicalFamily: "tops",
    colorName: "White",
    colorCode: "WHT",
    colorProfile: {primary: {family: "white"}},
    productEvidence: {
      manufacturerSku: "OB-HOOD-9",
      reliablePartnerProductId: "synthetic_b_cz:b-prod-9",
    },
    variantEvidence: {
      manufacturerSku: "OB-HOOD-9-WHT",
      reliablePartnerVariantId: "synthetic_b_cz:b-var-white",
    },
    url: "https://shop.synthetic-b.test/item/b-prod-9",
    regularPrice: {amountMinor: 129900, currency: "CZK"},
    promotions: [{
      kind: PROMOTION_KIND.MEMBER_ONLY,
      price: {amountMinor: 99900, currency: "CZK"},
      description: "members club",
    }],
    offerAvailability: "AVAILABLE",
    lifecycle: "ACTIVE",
    sizes: [{
      normalizedSizeKey: "L",
      partnerSizeLabel: "L",
      sizeSystem: "ALPHA",
      availability: "AVAILABLE",
      // no exact quantity
    }],
    images: [{
      url: "https://cdn.synthetic-b.test/b9.jpg",
      partnerRole: PARTNER_IMAGE_ROLE.PRODUCT_ONLY,
      // Unreliable claim — adapter must not treat as OOTD-approved.
      partnerClaimsProductOnly: true,
      partnerPosition: 0,
    }],
    observedAt: "2026-08-15T11:00:00.000Z",
    ...overrides,
  };
}

module.exports = {
  ADAPTER_KEY,
  ADAPTER_VERSION,
  createSyntheticPartnerBAdapter,
  samplePartnerBRecord,
};
