"use strict";

const {
  AVAILABILITY,
  LIFECYCLE,
  PROMOTION_KIND,
  QUANTITY_RELIABILITY,
  effectivePublicPrice,
} = require("./catalog_contract");
const {resolveBestOffer} = require("./catalog_search_service");

const SHOPPING_DTO_VERSION = 2;

function buildPublicCandidate({candidate, catalog, query}) {
  if (!candidate) return null;
  const product = find(catalog.products, "productId", candidate.productId);
  const variant = find(catalog.variants, "variantId", candidate.variantId);
  const offers = publicOffers({candidate, catalog, query});
  const primaryOffer = offers.find((offer) => offer.offerId === candidate.bestOfferId) ||
    offers[0] || null;
  return {
    shoppingDtoVersion: SHOPPING_DTO_VERSION,
    candidateId: candidate.variantId,
    product: publicProduct(product),
    variant: publicVariant(variant),
    productId: candidate.productId,
    variantId: candidate.variantId,
    brand: product?.brand || null,
    displayName: product?.normalizedModelIdentity || product?.canonicalType || null,
    canonicalType: product?.canonicalType || null,
    canonicalFamily: product?.canonicalFamily || null,
    exactColorName: variant?.exactColorName || null,
    bestOfferId: primaryOffer?.offerId || null,
    primaryOffer,
    effectivePublicPrice: primaryOffer?.effectivePrice || candidate.effectivePublicPrice || null,
    selectedSizeEvidence: primaryOffer?.selectedSizeEvidence || candidate.selectedSizeEvidence || null,
    freshnessEvidence: primaryOffer?.freshness || candidate.freshnessEvidence || null,
    image: publicImage(variant, product),
    ranking: {
      hardConstraintGate: candidate.rankingComponents?.hardConstraintGate === true,
      softPreferenceScore: candidate.rankingComponents?.softPreferenceScore || 0,
    },
  };
}

function buildPublicCandidateDetail({candidate, catalog, query}) {
  const value = buildPublicCandidate({candidate, catalog, query});
  if (!value) return null;
  const offers = publicOffers({candidate, catalog, query});
  return {
    status: "OK",
    shoppingDtoVersion: SHOPPING_DTO_VERSION,
    candidate: value,
    product: value.product,
    variant: value.variant,
    primaryOffer: value.primaryOffer,
    alternativeOffers: offers.filter((offer) => offer.offerId !== value.primaryOffer?.offerId),
    // Backward-compatible aggregate; v2 clients should use primaryOffer and
    // alternativeOffers.
    offers,
  };
}

function publicOffers({candidate, catalog, query}) {
  const partners = new Map((catalog.partners || []).map((value) => [value.partnerId, value]));
  const sizesByOffer = groupBy(catalog.sizes || [], "offerId");
  const rawOffers = (catalog.offers || []).filter((offer) =>
    candidate.relevantOfferIds.includes(offer.offerId) &&
    offer.lifecycleState !== LIFECYCLE.DISCONTINUED);
  const selectedSizeKeys = new Set((query?.selectedSizeKeys || []).map((value) =>
    String(value).toLowerCase()));
  const preferredSizeKey = query?.preferredSizeKey || null;
  const best = resolveBestOffer({
    offers: rawOffers,
    sizesByOffer,
    selectedSizeKeys,
    preferredSizeKey,
    availableNow: query?.availableNow === true,
  });
  const values = rawOffers.map((offer) => publicOffer({
    offer,
    partner: partners.get(offer.partnerId),
    sizes: sizesByOffer.get(offer.offerId) || [],
    selectedSizeKeys,
    preferredSizeKey,
  }));
  values.sort((left, right) => {
    if (left.offerId === best?.offer?.offerId) return -1;
    if (right.offerId === best?.offer?.offerId) return 1;
    if (left.selectedSizeEvidence.purchasable !== right.selectedSizeEvidence.purchasable) {
      return left.selectedSizeEvidence.purchasable ? -1 : 1;
    }
    if (left.effectivePrice.price.currency === right.effectivePrice.price.currency) {
      const price = left.effectivePrice.price.amountMinor - right.effectivePrice.price.amountMinor;
      if (price !== 0) return price;
    }
    return left.offerId.localeCompare(right.offerId);
  });
  return values;
}

function publicOffer({offer, partner, sizes, selectedSizeKeys, preferredSizeKey}) {
  const effective = effectivePublicPrice(offer);
  const publicSale = bestPublicSale(offer);
  const selectedSizes = sizes
    .filter((size) => selectedSizeKeys.has(String(size.normalizedSizeKey).toLowerCase()))
    .map((size) => ({
      normalizedSizeKey: size.normalizedSizeKey,
      displayLabel: size.partnerSizeLabel || size.normalizedSizeKey,
      selected: true,
      preferred: preferredSizeKey != null &&
        String(preferredSizeKey).toLowerCase() === String(size.normalizedSizeKey).toLowerCase(),
      availability: size.availability || AVAILABILITY.UNKNOWN,
      reliableQuantity: size.quantityReliability === QUANTITY_RELIABILITY.EXACT ?
        size.exactQuantity : null,
      partnerReliableLowStockSignal:
        size.quantityReliability === QUANTITY_RELIABILITY.PARTNER_LOW_STOCK_SIGNAL,
      availabilityVerifiedAt: size.observedAt || offer.lastVerifiedAt ||
        offer.freshness?.lastSuccessfulVerificationAt || null,
    }))
    .sort((left, right) => {
      if (left.preferred !== right.preferred) return left.preferred ? -1 : 1;
      return String(left.normalizedSizeKey).localeCompare(String(right.normalizedSizeKey));
    });
  const anyAvailable = selectedSizes.some((size) => size.availability === AVAILABILITY.AVAILABLE);
  return {
    offerId: offer.offerId,
    partnerId: offer.partnerId,
    store: {
      partnerId: offer.partnerId,
      displayName: partner?.publicStoreName || offer.partnerId,
    },
    url: validatedPublicUrl(offer.url, partner?.allowedDomains),
    regularPrice: offer.regularPrice,
    salePrice: publicSale,
    effectivePrice: {
      price: effective.price,
      requiresPublicCoupon: effective.requiresPublicCoupon === true,
      couponCode: effective.requiresPublicCoupon ? effective.couponCode : null,
    },
    publicEffectivePrice: {
      price: effective.price,
      requiresPublicCoupon: effective.requiresPublicCoupon === true,
      couponCode: effective.requiresPublicCoupon ? effective.couponCode : null,
    },
    selectedSizes,
    sizes: selectedSizes.map((size) => ({
      normalizedSizeKey: size.normalizedSizeKey,
      availability: size.availability,
      exactQuantity: size.reliableQuantity,
    })),
    selectedSizeEvidence: {
      purchasable: offer.overallAvailability === AVAILABILITY.AVAILABLE &&
        (selectedSizeKeys.size === 0 || anyAvailable),
      availability: selectedSizes.length === 0 ? AVAILABILITY.UNKNOWN :
        (anyAvailable ? AVAILABILITY.AVAILABLE :
          (selectedSizes.every((size) => size.availability === AVAILABILITY.UNAVAILABLE) ?
            AVAILABILITY.UNAVAILABLE : AVAILABILITY.UNKNOWN)),
    },
    overallAvailability: offer.overallAvailability || AVAILABILITY.UNKNOWN,
    lifecycleState: offer.lifecycleState || LIFECYCLE.UNKNOWN_OR_STALE,
    freshness: {
      stale: offer.freshness?.stale === true,
      priceVerifiedAt: offer.lastVerifiedAt ||
        offer.freshness?.lastSuccessfulVerificationAt || null,
      availabilityVerifiedAt: offer.freshness?.lastSuccessfulVerificationAt ||
        offer.lastVerifiedAt || null,
    },
  };
}

function bestPublicSale(offer) {
  const sales = (offer.promotions || [])
    .filter((promotion) => promotion.kind === PROMOTION_KIND.PUBLIC_SALE)
    .filter((promotion) => promotion.price?.currency === offer.regularPrice?.currency)
    .filter((promotion) => promotion.price.amountMinor < offer.regularPrice.amountMinor)
    .sort((left, right) => left.price.amountMinor - right.price.amountMinor);
  return sales[0]?.price || null;
}

function validatedPublicUrl(value, allowedDomains) {
  try {
    const url = new URL(String(value || ""));
    if (url.protocol !== "https:") return null;
    if (!Array.isArray(allowedDomains) || allowedDomains.length === 0) return null;
    const host = url.hostname.toLowerCase();
    const allowed = allowedDomains.some((domain) =>
      host === String(domain).toLowerCase() ||
      host.endsWith(`.${String(domain).toLowerCase()}`));
    if (!allowed) return null;
    return url.toString();
  } catch (_) {
    return null;
  }
}

function publicProduct(product) {
  if (!product) return null;
  return {
    productId: product.productId,
    displayName: product.normalizedModelIdentity || product.canonicalType || null,
    brand: product.brand || null,
    canonicalType: product.canonicalType || null,
    canonicalFamily: product.canonicalFamily || null,
  };
}

function publicVariant(variant) {
  if (!variant) return null;
  return {
    variantId: variant.variantId,
    productId: variant.productId,
    exactColorName: variant.exactColorName || null,
    color: {
      primaryFamily: variant.colorProfile?.primary?.family || null,
      exactColorCode: variant.exactColorCode || null,
    },
    fit: variant.fit || null,
    material: variant.material || null,
    pattern: variant.pattern || null,
    styles: Array.isArray(variant.styles) ? variant.styles : [],
  };
}

function publicImage(variant, product) {
  const source = variant?.publicImage || product?.publicImage || null;
  if (source?.status === "AVAILABLE_VERIFIED_GARMENT_ONLY" &&
      typeof source.url === "string" && source.url.startsWith("https://")) {
    return {status: source.status, url: source.url, wardrobeEligible: false};
  }
  return {
    status: source?.status === "PENDING_VALIDATION" ?
      "PENDING_VALIDATION" : "NOT_AVAILABLE",
    url: null,
    wardrobeEligible: false,
  };
}

function find(values, field, id) {
  return (values || []).find((value) => value[field] === id) || null;
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

module.exports = {
  SHOPPING_DTO_VERSION,
  buildPublicCandidate,
  buildPublicCandidateDetail,
  validatedPublicUrl,
};
