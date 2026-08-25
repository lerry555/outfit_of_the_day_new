"use strict";

const crypto = require("crypto");

const CONTRACT_VERSION = "shopping-catalog-contract-v1";
const AVAILABILITY = Object.freeze({
  AVAILABLE: "AVAILABLE",
  UNAVAILABLE: "UNAVAILABLE",
  UNKNOWN: "UNKNOWN",
});
const LIFECYCLE = Object.freeze({
  ACTIVE: "ACTIVE",
  UNAVAILABLE: "UNAVAILABLE",
  DISCONTINUED: "DISCONTINUED",
  UNKNOWN_OR_STALE: "UNKNOWN_OR_STALE",
});
const QUANTITY_RELIABILITY = Object.freeze({
  EXACT: "EXACT",
  PARTNER_LOW_STOCK_SIGNAL: "PARTNER_LOW_STOCK_SIGNAL",
  UNKNOWN: "UNKNOWN",
});
const PROMOTION_KIND = Object.freeze({
  PUBLIC_SALE: "PUBLIC_SALE",
  PUBLIC_COUPON: "PUBLIC_COUPON",
  MEMBER_ONLY: "MEMBER_ONLY",
  BUNDLE: "BUNDLE",
  // Partner-classified non-public / unsupported kinds (Phase 8). Never enter
  // effectivePublicPrice; retained for catalog truth and adapter diagnostics.
  STUDENT: "STUDENT",
  VIP: "VIP",
  OTHER_UNSUPPORTED: "OTHER_UNSUPPORTED",
});

const PUBLIC_EFFECTIVE_PROMOTION_KINDS = Object.freeze(new Set([
  PROMOTION_KIND.PUBLIC_SALE,
  PROMOTION_KIND.PUBLIC_COUPON,
]));

function assertText(value, field) {
  const text = String(value || "").trim();
  if (!text) throw new Error(`shopping_catalog_invalid_${field}`);
  return text;
}

function decodeMoney(raw, field) {
  if (!raw || typeof raw !== "object") {
    throw new Error(`shopping_catalog_invalid_${field}`);
  }
  const amountMinor = raw.amountMinor;
  const currency = String(raw.currency || "").trim().toUpperCase();
  if (!Number.isSafeInteger(amountMinor) || amountMinor < 0) {
    throw new Error(`shopping_catalog_invalid_${field}_amount_minor`);
  }
  if (!/^[A-Z]{3}$/.test(currency)) {
    throw new Error(`shopping_catalog_invalid_${field}_currency`);
  }
  return {amountMinor, currency};
}

function normalizeAllowedDomains(rawDomains) {
  if (!Array.isArray(rawDomains) || rawDomains.length === 0) {
    throw new Error("shopping_catalog_invalid_partner_allowed_domains");
  }
  return [...new Set(rawDomains.map((value) =>
    assertText(value, "partner_allowed_domain").toLowerCase()))].sort();
}

function validateOfferUrl(rawUrl, allowedDomains) {
  const value = assertText(rawUrl, "offer_url");
  let url;
  try {
    url = new URL(value);
  } catch (_) {
    throw new Error("shopping_catalog_invalid_offer_url");
  }
  if (url.protocol !== "https:") {
    throw new Error("shopping_catalog_offer_url_requires_https");
  }
  const host = url.hostname.toLowerCase();
  const allowed = allowedDomains.some((domain) =>
    host === domain || host.endsWith(`.${domain}`));
  if (!allowed) throw new Error("shopping_catalog_offer_url_domain_not_allowed");
  return url.toString();
}

function normalizeIdentityEvidence(raw = {}) {
  const pick = (name) => {
    const value = raw[name];
    return value == null || String(value).trim() === "" ? null : String(value).trim();
  };
  return {
    gtin: pick("gtin"),
    manufacturerModelId: pick("manufacturerModelId"),
    manufacturerSku: pick("manufacturerSku"),
    reliablePartnerProductId: pick("reliablePartnerProductId"),
    reliablePartnerVariantId: pick("reliablePartnerVariantId"),
  };
}

function productIdentityKeys(evidence) {
  return [
    evidence.gtin && `gtin:${evidence.gtin}`,
    evidence.manufacturerModelId && `model:${evidence.manufacturerModelId}`,
    evidence.manufacturerSku && `sku:${evidence.manufacturerSku}`,
    evidence.reliablePartnerProductId &&
      `partner-product:${evidence.reliablePartnerProductId}`,
  ].filter(Boolean);
}

function variantIdentityKeys(evidence) {
  return [
    evidence.gtin && `gtin:${evidence.gtin}`,
    evidence.manufacturerSku && `sku:${evidence.manufacturerSku}`,
    evidence.reliablePartnerVariantId &&
      `partner-variant:${evidence.reliablePartnerVariantId}`,
  ].filter(Boolean);
}

function stableId(prefix, value) {
  return `${prefix}_${crypto.createHash("sha256").update(value).digest("hex").slice(0, 24)}`;
}

function effectivePublicPrice(offer) {
  let result = {
    price: offer.regularPrice,
    requiresPublicCoupon: false,
    couponCode: null,
  };
  for (const promotion of offer.promotions || []) {
    if (!PUBLIC_EFFECTIVE_PROMOTION_KINDS.has(promotion.kind)) continue;
    if (promotion.expired === true) continue;
    if (promotion.price.currency !== result.price.currency) {
      throw new Error("shopping_catalog_promotion_currency_mismatch");
    }
    if (promotion.price.amountMinor < result.price.amountMinor) {
      result = {
        price: promotion.price,
        requiresPublicCoupon: promotion.kind === PROMOTION_KIND.PUBLIC_COUPON,
        couponCode: promotion.code || null,
      };
    }
  }
  return result;
}

function normalizePromotionValidity(raw, nowIso) {
  const validFrom = raw.validFrom == null ? null : String(raw.validFrom);
  const validUntil = raw.validUntil == null ? null : String(raw.validUntil);
  if (validFrom != null && Number.isNaN(Date.parse(validFrom))) {
    throw new Error("shopping_catalog_invalid_promotion_valid_from");
  }
  if (validUntil != null && Number.isNaN(Date.parse(validUntil))) {
    throw new Error("shopping_catalog_invalid_promotion_valid_until");
  }
  const nowMs = Date.parse(nowIso || new Date().toISOString());
  let expired = false;
  if (validUntil != null && Date.parse(validUntil) < nowMs) expired = true;
  if (validFrom != null && Date.parse(validFrom) > nowMs) expired = true;
  return {validFrom, validUntil, expired};
}

function normalizePromotions(rawPromotions, currency, {now} = {}) {
  if (rawPromotions == null) return [];
  if (!Array.isArray(rawPromotions)) {
    throw new Error("shopping_catalog_invalid_promotions");
  }
  return rawPromotions.map((raw) => {
    const kind = assertText(raw.kind, "promotion_kind");
    if (!Object.values(PROMOTION_KIND).includes(kind)) {
      throw new Error("shopping_catalog_invalid_promotion_kind");
    }
    const price = decodeMoney(raw.price, "promotion_price");
    if (price.currency !== currency) {
      throw new Error("shopping_catalog_promotion_currency_mismatch");
    }
    if (kind === PROMOTION_KIND.PUBLIC_COUPON &&
        !String(raw.code || "").trim()) {
      throw new Error("shopping_catalog_public_coupon_code_required");
    }
    const validity = normalizePromotionValidity(raw, now);
    return {
      kind,
      price,
      code: kind === PROMOTION_KIND.PUBLIC_COUPON ? String(raw.code).trim() : null,
      description: raw.description == null ? null : String(raw.description),
      validFrom: validity.validFrom,
      validUntil: validity.validUntil,
      expired: validity.expired,
    };
  });
}

function normalizeAvailability(raw, field) {
  if (raw == null) return AVAILABILITY.UNKNOWN;
  const value = String(raw).trim().toUpperCase();
  if (!Object.values(AVAILABILITY).includes(value)) {
    throw new Error(`shopping_catalog_invalid_${field}`);
  }
  return value;
}

function normalizeLifecycle(raw) {
  if (raw == null) return LIFECYCLE.ACTIVE;
  const value = String(raw).trim().toUpperCase();
  if (!Object.values(LIFECYCLE).includes(value)) {
    throw new Error("shopping_catalog_invalid_lifecycle");
  }
  return value;
}

function normalizeSize(raw, offerId) {
  const availability = normalizeAvailability(raw.availability, "size_availability");
  const exactQuantity = raw.exactQuantity == null ? null : raw.exactQuantity;
  if (exactQuantity != null &&
      (!Number.isSafeInteger(exactQuantity) || exactQuantity < 0)) {
    throw new Error("shopping_catalog_invalid_exact_quantity");
  }
  const reliability = raw.quantityReliability == null ?
    QUANTITY_RELIABILITY.UNKNOWN : String(raw.quantityReliability).trim().toUpperCase();
  if (!Object.values(QUANTITY_RELIABILITY).includes(reliability)) {
    throw new Error("shopping_catalog_invalid_quantity_reliability");
  }
  if (exactQuantity != null && reliability !== QUANTITY_RELIABILITY.EXACT) {
    throw new Error("shopping_catalog_exact_quantity_requires_reliability");
  }
  return {
    offerId,
    normalizedSizeKey: assertText(raw.normalizedSizeKey, "normalized_size_key"),
    partnerSizeLabel: assertText(raw.partnerSizeLabel, "partner_size_label"),
    sizeSystem: assertText(raw.sizeSystem, "size_system"),
    availability,
    exactQuantity,
    quantityReliability: reliability,
    observedAt: raw.observedAt || null,
  };
}

module.exports = {
  AVAILABILITY,
  CONTRACT_VERSION,
  LIFECYCLE,
  PROMOTION_KIND,
  PUBLIC_EFFECTIVE_PROMOTION_KINDS,
  QUANTITY_RELIABILITY,
  assertText,
  decodeMoney,
  effectivePublicPrice,
  normalizeAllowedDomains,
  normalizeAvailability,
  normalizeIdentityEvidence,
  normalizeLifecycle,
  normalizePromotionValidity,
  normalizePromotions,
  normalizeSize,
  productIdentityKeys,
  stableId,
  validateOfferUrl,
  variantIdentityKeys,
};
