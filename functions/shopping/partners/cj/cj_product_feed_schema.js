"use strict";

/**
 * CJ-level shopping product feed schema (network).
 * Based on CJ Product Feeds for Shopping documentation (Google Shopping–aligned).
 * Merchant population of any field is NOT inferred here.
 *
 * Evidence: https://developers.cj.com/docs/data-imports/product-feeds
 * Product Search API: POST https://ads.api.cj.com/query (Bearer Personal Access Token)
 */

const FIELD_STATUS = Object.freeze({
  CONFIRMED: "CONFIRMED",
  SAMPLE_REQUIRED: "SAMPLE_REQUIRED",
  OPTIONAL: "OPTIONAL",
  UNAVAILABLE: "UNAVAILABLE",
  UNSUPPORTED: "UNSUPPORTED",
});

/** Network-level: schema can carry these fields. */
const CJ_SHOPPING_FEED_FIELDS = Object.freeze({
  id: {status: FIELD_STATUS.CONFIRMED, requiredInSpec: true},
  title: {status: FIELD_STATUS.CONFIRMED, requiredInSpec: true},
  description: {status: FIELD_STATUS.CONFIRMED, requiredInSpec: true},
  link: {status: FIELD_STATUS.CONFIRMED, requiredInSpec: true},
  image_link: {status: FIELD_STATUS.CONFIRMED, requiredInSpec: true},
  additional_image_link: {status: FIELD_STATUS.CONFIRMED, requiredInSpec: false},
  availability: {status: FIELD_STATUS.CONFIRMED, requiredInSpec: true},
  price: {status: FIELD_STATUS.CONFIRMED, requiredInSpec: true},
  sale_price: {status: FIELD_STATUS.OPTIONAL, requiredInSpec: false},
  brand: {status: FIELD_STATUS.OPTIONAL, requiredInSpec: false},
  gtin: {status: FIELD_STATUS.OPTIONAL, requiredInSpec: false},
  mpn: {status: FIELD_STATUS.OPTIONAL, requiredInSpec: false},
  item_group_id: {status: FIELD_STATUS.OPTIONAL, requiredInSpec: false},
  color: {status: FIELD_STATUS.OPTIONAL, requiredInSpec: false},
  size: {status: FIELD_STATUS.OPTIONAL, requiredInSpec: false},
  size_system: {status: FIELD_STATUS.OPTIONAL, requiredInSpec: false},
  google_product_category: {status: FIELD_STATUS.OPTIONAL, requiredInSpec: false},
  product_type: {status: FIELD_STATUS.OPTIONAL, requiredInSpec: false},
  condition: {status: FIELD_STATUS.OPTIONAL, requiredInSpec: false},
  // No standard image role / packshot field in Google Shopping feed.
  image_role: {status: FIELD_STATUS.UNSUPPORTED, requiredInSpec: false},
});

const CJ_AVAILABILITY_VALUES = Object.freeze([
  "in_stock",
  "out_of_stock",
  "preorder",
  "backorder",
]);

const CJ_PRODUCT_SEARCH_ENDPOINT = "https://ads.api.cj.com/query";
const CJ_AUTH_MODEL = Object.freeze({
  type: "bearer_personal_access_token",
  header: "Authorization: Bearer <Personal Access Token>",
  companyIdArg: "companyId",
  evidence: "https://developers.cj.com/account/personal-access-tokens",
  productSearchDocs: "https://developers.cj.com/graphql/reference/Product%20Feed",
});

const CJ_FEED_DELIVERY = Object.freeze({
  downloadableExport: "Account > Subscriptions product catalog export (HTTP/SFTP/email ZIP)",
  formats: ["XML", "CSV"],
  compression: "ZIP typical for downloadable export",
  api: "GraphQL Product Search / shoppingProductFeeds / products",
  cadence: "UNKNOWN — advertiser regenerates; REQUIRES ACCOUNT ACCESS",
});

module.exports = {
  CJ_AUTH_MODEL,
  CJ_AVAILABILITY_VALUES,
  CJ_FEED_DELIVERY,
  CJ_PRODUCT_SEARCH_ENDPOINT,
  CJ_SHOPPING_FEED_FIELDS,
  FIELD_STATUS,
};
