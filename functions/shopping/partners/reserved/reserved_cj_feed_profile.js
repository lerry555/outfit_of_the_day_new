"use strict";

const {FIELD_STATUS} = require("../cj/cj_product_feed_schema");
const {
  ADAPTER_KEY,
  EXPECTED_CURRENCY,
  MARKET,
  PARTNER_ID,
} = require("./reserved_cj_constants");

/**
 * Reserved-specific field confidence registry.
 * CJ schema support ≠ Reserved population.
 */
const ReservedCjFeedProfile = Object.freeze({
  partnerId: PARTNER_ID,
  adapterKey: ADAPTER_KEY,
  market: MARKET,
  expectedCurrency: EXPECTED_CURRENCY,
  profileStatus: "PENDING_SAMPLE",
  fields: Object.freeze({
    productId: {
      sourceField: "id",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "CJ schema supports id; Reserved population unconfirmed",
      normalization: "stable partner listing id",
      fallback: null,
    },
    variantGroupId: {
      sourceField: "item_group_id",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "CJ optional; Reserved behavior unknown",
      normalization: "group color variants when present",
      fallback: "partner-scoped productId only",
    },
    gtin: {
      sourceField: "gtin",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "CJ optional",
      normalization: "strong identity when present",
      fallback: "partner-only identity",
    },
    manufacturerSku: {
      sourceField: "mpn",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "CJ optional mpn",
      normalization: "manufacturerSku evidence",
      fallback: null,
    },
    color: {
      sourceField: "color",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "CJ optional; required for exact Variant quality",
      normalization: "exactColorName",
      fallback: "NO_GO or GO_WITH_LIMITATIONS if missing",
    },
    size: {
      sourceField: "size",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "CJ optional",
      normalization: "size label / per-row size",
      fallback: "UNKNOWN size availability",
    },
    sizeAvailability: {
      sourceField: "availability + size row model",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "Cannot claim per-size stock until sample proves row model",
      normalization: "AVAILABLE/UNAVAILABLE/UNKNOWN",
      fallback: "UNKNOWN — never invent UNAVAILABLE",
    },
    quantity: {
      sourceField: null,
      status: FIELD_STATUS.UNAVAILABLE,
      evidence: "Standard CJ shopping feed has no reliable exact quantity field",
      normalization: null,
      fallback: "omit exactQuantity",
    },
    price: {
      sourceField: "price",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "CJ required in spec; SK EUR must be confirmed in sample",
      normalization: "integer minor + EUR",
      fallback: null,
    },
    salePrice: {
      sourceField: "sale_price",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "CJ optional → PUBLIC_SALE if populated",
      normalization: "PUBLIC_SALE",
      fallback: "no sale",
    },
    coupon: {
      sourceField: null,
      status: FIELD_STATUS.UNAVAILABLE,
      evidence: "Coupons typically separate from product feed",
      normalization: null,
      fallback: "separate promotions path later",
    },
    link: {
      sourceField: "link",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "May be CJ tracking URL and/or merchant URL",
      normalization: "validated CatalogOffer.url",
      fallback: null,
    },
    image: {
      sourceField: "image_link",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "CJ required in spec",
      normalization: "PartnerImageCandidate",
      fallback: "NOT_AVAILABLE",
    },
    additionalImages: {
      sourceField: "additional_image_link",
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "CJ optional",
      normalization: "extra candidates",
      fallback: "single image only",
    },
    imageRole: {
      sourceField: null,
      status: FIELD_STATUS.UNSUPPORTED,
      evidence: "No packshot/role in standard Google Shopping / CJ shopping feed",
      normalization: null,
      fallback: "partnerClaimsProductOnly=false always",
    },
    feedCompleteness: {
      sourceField: null,
      status: FIELD_STATUS.SAMPLE_REQUIRED,
      evidence: "No public completeness guarantee for Reserved SK",
      normalization: "classifyDisappearance",
      fallback: "MUST_NOT_DISCONTINUE until confirmed",
    },
  }),
});

function getFieldStatus(fieldKey) {
  const field = ReservedCjFeedProfile.fields[fieldKey];
  return field ? field.status : FIELD_STATUS.UNAVAILABLE;
}

function isProductionMappingEnabled() {
  return false;
}

module.exports = {
  ReservedCjFeedProfile,
  getFieldStatus,
  isProductionMappingEnabled,
};
