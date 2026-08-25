"use strict";

const {effectivePublicPrice, LIFECYCLE, QUANTITY_RELIABILITY} =
  require("../catalog_contract");
const {resolveBestOffer} = require("../catalog_search_service");

/**
 * Resolve authoritative catalog facts for one Wishlist item / exact Variant.
 * Size evidence is independent of Variant lifecycle.
 * DISCONTINUED alone never invents per-size UNAVAILABLE.
 */
function deriveWishlistCatalogFacts(catalog, item) {
  const variant = (catalog.variants || []).find((value) =>
    value.variantId === item.variantId);
  if (!variant) {
    return failedFacts("VARIANT_NOT_FOUND");
  }
  const product = (catalog.products || []).find((value) =>
    value.productId === variant.productId) || null;
  const lifecycleState = variant.lifecycleState || LIFECYCLE.UNKNOWN_OR_STALE;
  const confirmedDiscontinued = lifecycleState === LIFECYCLE.DISCONTINUED;

  // Offers that remain usable for public price/size evidence. Discontinued
  // variant may still carry historical size rows; we never invent UNAVAILABLE.
  const offers = (catalog.offers || []).filter((offer) =>
    offer.variantId === variant.variantId &&
    offer.lifecycleState !== LIFECYCLE.DISCONTINUED);
  const sizesByOffer = groupBy(catalog.sizes || [], "offerId");
  const stale = !confirmedDiscontinued && (
    variant.freshness?.stale === true ||
    (offers.length > 0 && offers.every((offer) => offer.freshness?.stale === true))
  );
  if (stale) {
    return failedFacts("CATALOG_STALE", lifecycleState, product, variant);
  }

  const selected = new Set((item.selectedSizes || []).map((value) =>
    String(value).toLowerCase()));
  const best = confirmedDiscontinued ? null : resolveBestOffer({
    offers,
    sizesByOffer,
    selectedSizeKeys: selected,
    preferredSizeKey: item.preferredSize,
    availableNow: false,
  });
  const effective = best ? effectivePublicPrice(best.offer) : null;
  const effectivePrice = effective?.price || null;
  const priceState = confirmedDiscontinued ? "UNKNOWN" :
    (!effectivePrice ||
      effectivePrice.currency !== item.targetPrice.currency ?
      "UNKNOWN" :
      (effectivePrice.amountMinor <= item.targetPrice.amountMinor ?
        "SATISFIED" : "UNSATISFIED"));

  const sizeStates = {};
  const sizeEvidence = {};
  for (const selectedSize of item.selectedSizes || []) {
    const sizeFacts = collectSizeFacts({
      catalog,
      variantId: variant.variantId,
      selectedSize,
      offers,
      sizesByOffer,
      confirmedDiscontinued,
    });
    if (!sizeFacts.hasAuthoritativeEvidence) {
      // Preserve prior size in the engine — do not claim UNKNOWN evidence.
      sizeEvidence[selectedSize] = false;
      continue;
    }
    sizeEvidence[selectedSize] = true;
    sizeStates[selectedSize] = sizeFacts.state;
  }

  const quantitySourceSizes = confirmedDiscontinued ?
    allVariantSizes(catalog, variant.variantId) :
    (best ? sizesByOffer.get(best.offer.offerId) || [] : []);
  const reliableQuantities = {};
  let partnerReliableLowStockSignal = false;
  for (const size of quantitySourceSizes) {
    const key = (item.selectedSizes || []).find((selectedSize) =>
      String(selectedSize).toLowerCase() ===
      String(size.normalizedSizeKey).toLowerCase());
    if (!key) continue;
    if (size.quantityReliability === QUANTITY_RELIABILITY.EXACT &&
        Number.isSafeInteger(size.exactQuantity)) {
      reliableQuantities[key] = size.exactQuantity;
    }
    if (size.quantityReliability ===
        QUANTITY_RELIABILITY.PARTNER_LOW_STOCK_SIGNAL) {
      partnerReliableLowStockSignal = true;
    }
  }

  const priceVerifiedAt = best?.offer?.lastVerifiedAt ||
    best?.offer?.freshness?.lastSuccessfulVerificationAt || null;
  const availabilityVerifiedAt = latest(
    ...Object.values(sizeStates).length ?
      [(catalog.variants || []).find((value) =>
        value.variantId === item.variantId)?.lastVerifiedAt] : [],
    best?.offer?.freshness?.lastSuccessfulVerificationAt,
    best?.offer?.lastVerifiedAt,
    variant.lastVerifiedAt,
  );

  return {
    successfulVerification: true,
    failureCode: null,
    lifecycleState,
    product,
    variant,
    priceState,
    sizeStates,
    sizeEvidence,
    effectivePrice,
    coupon: effective?.requiresPublicCoupon ? {
      required: true,
      code: effective.couponCode || null,
    } : null,
    reliableQuantities,
    partnerReliableLowStockSignal,
    priceVerifiedAt,
    availabilityVerifiedAt,
    lastSuccessfulVerification: latest(priceVerifiedAt, availabilityVerifiedAt,
      variant.lastVerifiedAt),
  };
}

function collectSizeFacts({
  catalog,
  variantId,
  selectedSize,
  offers,
  sizesByOffer,
  confirmedDiscontinued,
}) {
  // Prefer active offer sizes; if discontinued, still accept explicit size
  // rows attached to any offer for this variant when availability is known.
  let sizeFacts = offers.flatMap((offer) =>
    (sizesByOffer.get(offer.offerId) || []).filter((size) =>
      String(size.normalizedSizeKey).toLowerCase() ===
      String(selectedSize).toLowerCase()));
  if (!sizeFacts.length && confirmedDiscontinued) {
    sizeFacts = allVariantSizes(catalog, variantId).filter((size) =>
      String(size.normalizedSizeKey).toLowerCase() ===
      String(selectedSize).toLowerCase() &&
      ["AVAILABLE", "UNAVAILABLE"].includes(size.availability));
  }
  if (!sizeFacts.length) {
    return {hasAuthoritativeEvidence: false, state: "UNKNOWN"};
  }
  if (sizeFacts.some((size) => size.availability === "AVAILABLE")) {
    return {hasAuthoritativeEvidence: true, state: "AVAILABLE"};
  }
  if (sizeFacts.every((size) => size.availability === "UNAVAILABLE")) {
    return {hasAuthoritativeEvidence: true, state: "UNAVAILABLE"};
  }
  // Mixed/unknown availability rows are not authoritative UNAVAILABLE proof.
  return {hasAuthoritativeEvidence: false, state: "UNKNOWN"};
}

function allVariantSizes(catalog, variantId) {
  const offerIds = new Set((catalog.offers || [])
    .filter((offer) => offer.variantId === variantId)
    .map((offer) => offer.offerId));
  return (catalog.sizes || []).filter((size) => offerIds.has(size.offerId));
}

function failedFacts(code, lifecycleState = "UNKNOWN", product = null,
  variant = null) {
  return {
    successfulVerification: false,
    failureCode: code,
    lifecycleState,
    product,
    variant,
    sizeStates: {},
    sizeEvidence: {},
  };
}
function groupBy(values, field) {
  const result = new Map();
  for (const value of values) {
    const group = result.get(value[field]) || [];
    group.push(value);
    result.set(value[field], group);
  }
  return result;
}
function latest(...values) {
  return values.filter(Boolean).sort().at(-1) || null;
}

module.exports = {deriveWishlistCatalogFacts};
