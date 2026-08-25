"use strict";

const {PARTNER_CAPABILITY} = require("../partner_capabilities");
const {createBasePartnerAdapter} = require("../partner_normalize");
const {PROMOTION_KIND, QUANTITY_RELIABILITY} = require("../../catalog_contract");
const {PARTNER_IMAGE_ROLE} = require("../partner_images");

/**
 * Synthetic Partner A — full snapshot, GTIN, exact quantity, image roles,
 * public coupon. No real retailer name.
 */
const ADAPTER_KEY = "synthetic_partner_a_full";
const ADAPTER_VERSION = "1";

function createSyntheticPartnerAAdapter({
  records = [],
  pageSize = 50,
} = {}) {
  const publicConfig = {
    partnerId: "synthetic_a_sk",
    displayName: "Synthetic Partner A",
    publicStoreName: "Synthetic Partner A",
    status: "ACTIVE",
    market: "SK",
    currency: "EUR",
    allowedDomains: ["images.synthetic-a.test", "shop.synthetic-a.test"],
    adapterKey: ADAPTER_KEY,
    adapterVersion: ADAPTER_VERSION,
    capabilities: [
      PARTNER_CAPABILITY.FULL_CATALOG_SNAPSHOT,
      PARTNER_CAPABILITY.GTIN,
      PARTNER_CAPABILITY.STABLE_PARTNER_PRODUCT_ID,
      PARTNER_CAPABILITY.STABLE_VARIANT_ID,
      PARTNER_CAPABILITY.PRICE,
      PARTNER_CAPABILITY.PUBLIC_COUPON,
      PARTNER_CAPABILITY.PUBLIC_SALE,
      PARTNER_CAPABILITY.SIZE_AVAILABILITY,
      PARTNER_CAPABILITY.EXACT_QUANTITY,
      PARTNER_CAPABILITY.MULTIPLE_IMAGES,
      PARTNER_CAPABILITY.IMAGE_ROLES,
      PARTNER_CAPABILITY.MARKET_SCOPE,
      PARTNER_CAPABILITY.CURRENCY,
      PARTNER_CAPABILITY.PAGINATION,
      PARTNER_CAPABILITY.LIFECYCLE_DISCONTINUED,
    ],
  };

  const all = [...records];

  return createBasePartnerAdapter({
    publicConfig,
    privateConfigDefaults: {
      rateLimit: {pageSize, requestsPerSecond: 20, requestsPerMinute: 600},
    },
    async fetchPage({pageToken, pageSize: size, mode}) {
      if (mode !== "FULL") {
        const err = new Error("partner_full_only");
        err.code = "FATAL_CONFIGURATION";
        throw err;
      }
      const start = pageToken ? Number(pageToken) : 0;
      if (!Number.isFinite(start) || start < 0) {
        const err = new Error("partner_page_token_invalid");
        err.code = "INVALID_PAYLOAD";
        throw err;
      }
      const slice = all.slice(start, start + size);
      const next = start + size;
      const done = next >= all.length;
      return {
        records: slice,
        nextPageToken: done ? null : String(next),
        done,
        completenessGuaranteed: done,
      };
    },
  });
}

function samplePartnerARecord(overrides = {}) {
  return {
    partnerProductId: "a-prod-1",
    partnerVariantId: "a-var-navy",
    partnerListingId: "a-list-1",
    brand: "SyntheticBrand",
    modelIdentity: "SB-TEE-001",
    canonicalType: "t_shirt",
    canonicalFamily: "tops",
    colorName: "Navy",
    colorCode: "NVY",
    colorProfile: {primary: {family: "blue"}},
    productEvidence: {
      gtin: "8590000000001",
      reliablePartnerProductId: "synthetic_a_sk:a-prod-1",
    },
    variantEvidence: {
      gtin: "8590000000001",
      reliablePartnerVariantId: "synthetic_a_sk:a-var-navy",
    },
    url: "https://shop.synthetic-a.test/p/a-prod-1",
    regularPrice: {amountMinor: 4900, currency: "EUR"},
    promotions: [{
      kind: PROMOTION_KIND.PUBLIC_COUPON,
      price: {amountMinor: 3900, currency: "EUR"},
      code: "SAVE10",
    }],
    offerAvailability: "AVAILABLE",
    lifecycle: "ACTIVE",
    sizes: [{
      normalizedSizeKey: "M",
      partnerSizeLabel: "M",
      sizeSystem: "ALPHA",
      availability: "AVAILABLE",
      exactQuantity: 3,
      quantityReliability: QUANTITY_RELIABILITY.EXACT,
    }],
    images: [{
      url: "https://images.synthetic-a.test/a-prod-1-front.jpg",
      partnerRole: PARTNER_IMAGE_ROLE.PRODUCT_ONLY,
      partnerClaimsProductOnly: true,
      partnerPosition: 0,
    }, {
      url: "https://images.synthetic-a.test/a-prod-1-model.jpg",
      partnerRole: PARTNER_IMAGE_ROLE.MODEL,
      partnerClaimsProductOnly: false,
      partnerPosition: 1,
    }],
    observedAt: "2026-08-15T10:00:00.000Z",
    ...overrides,
  };
}

module.exports = {
  ADAPTER_KEY,
  ADAPTER_VERSION,
  createSyntheticPartnerAAdapter,
  samplePartnerARecord,
};
