"use strict";

/**
 * Explicit partner capability keys. Adapters MUST declare only what is true.
 * Unsupported capabilities must remain absent — never inferred.
 */
const PARTNER_CAPABILITY = Object.freeze({
  FULL_CATALOG_SNAPSHOT: "full_catalog_snapshot",
  INCREMENTAL_UPDATES: "incremental_updates",
  DELTA_CURSOR: "delta_cursor",
  GTIN: "gtin",
  MANUFACTURER_SKU: "manufacturer_sku",
  MANUFACTURER_MODEL: "manufacturer_model",
  STABLE_PARTNER_PRODUCT_ID: "stable_partner_product_id",
  STABLE_VARIANT_ID: "stable_variant_id",
  PRICE: "price",
  PUBLIC_SALE: "public_sale",
  PUBLIC_COUPON: "public_coupon",
  MEMBER_PRICING: "member_pricing",
  SIZE_AVAILABILITY: "size_availability",
  EXACT_QUANTITY: "exact_quantity",
  EXPLICIT_LOW_STOCK_SIGNAL: "explicit_low_stock_signal",
  LIFECYCLE_DISCONTINUED: "lifecycle_discontinued",
  MULTIPLE_IMAGES: "multiple_images",
  IMAGE_ROLES: "image_roles",
  WEBHOOK: "webhook",
  POLLING: "polling",
  MARKET_SCOPE: "market_scope",
  CURRENCY: "currency",
  PAGINATION: "pagination",
});

const ALL_PARTNER_CAPABILITIES = Object.freeze(
  Object.values(PARTNER_CAPABILITY).sort(),
);

function normalizeCapabilities(raw) {
  const list = Array.isArray(raw) ? raw : [];
  const unknown = [];
  const known = new Set();
  for (const item of list) {
    const key = String(item || "").trim();
    if (!key) continue;
    if (!ALL_PARTNER_CAPABILITIES.includes(key)) {
      unknown.push(key);
      continue;
    }
    known.add(key);
  }
  if (unknown.length) {
    const error = new Error("partner_capability_unknown");
    error.code = "FATAL_CONFIGURATION";
    error.unknownCapabilities = unknown;
    throw error;
  }
  return [...known].sort();
}

function hasCapability(capabilities, key) {
  const set = capabilities instanceof Set ?
    capabilities : new Set(capabilities || []);
  return set.has(key);
}

module.exports = {
  ALL_PARTNER_CAPABILITIES,
  PARTNER_CAPABILITY,
  hasCapability,
  normalizeCapabilities,
};
