"use strict";

const crypto = require("crypto");
const {
  AVAILABILITY,
  LIFECYCLE,
  PROMOTION_KIND,
  effectivePublicPrice,
} = require("./catalog_contract");

const SEARCH_CONTRACT_VERSION = "shopping-deterministic-search-v1";
const MATCH_STATUS = Object.freeze({
  MATCH: "MATCH",
  MISMATCH: "MISMATCH",
  UNKNOWN: "UNKNOWN",
});
const SEARCH_COMPLETENESS = Object.freeze({
  COMPLETE: "COMPLETE",
  INCOMPLETE: "INCOMPLETE",
});

/**
 * Pure deterministic search over authoritative Phase 2 DTOs. It intentionally
 * accepts no raw partner payloads and makes no network or AI calls.
 */
function searchCatalog({query, catalog, catalogRevision = catalogRevisionFor(catalog)}) {
  const normalizedQuery = decodeShoppingQuery(query);
  const products = mapBy(catalog.products || [], "productId");
  const offersByVariant = groupBy(catalog.offers || [], "variantId");
  const sizesByOffer = groupBy(catalog.sizes || [], "offerId");
  const limit = catalog.scanLimit || Infinity;
  const variants = [...(catalog.variants || [])]
    .sort((left, right) => left.variantId.localeCompare(right.variantId));
  const scannedVariants = variants.slice(0, limit);
  const isComplete = scannedVariants.length === variants.length;
  const candidates = [];
  const rejected = [];
  const funnel = initialFunnel(normalizedQuery.constraints);

  for (const variant of scannedVariants) {
    const product = products.get(variant.productId);
    if (!product || variant.lifecycleState === LIFECYCLE.DISCONTINUED) {
      rejected.push({variantId: variant.variantId, reason: "DISCONTINUED_OR_ORPHANED"});
      continue;
    }
    const evaluated = evaluateVariant({
      query: normalizedQuery,
      product,
      variant,
      offers: offersByVariant.get(variant.variantId) || [],
      sizesByOffer,
    });
    updateFunnel(funnel, evaluated.constraintEvidence);
    if (!evaluated.exact) {
      rejected.push({
        variantId: variant.variantId,
        constraintEvidence: evaluated.constraintEvidence,
        reason: "HARD_CONSTRAINT_NOT_VERIFIED",
      });
      continue;
    }
    candidates.push(evaluated.candidate);
  }

  candidates.sort(compareCandidates);
  const diagnostics = candidates.length === 0 ?
    buildZeroResultDiagnostics(normalizedQuery, funnel, rejected) : null;
  return {
    contractVersion: SEARCH_CONTRACT_VERSION,
    queryId: normalizedQuery.queryId,
    queryRevision: normalizedQuery.revision,
    catalogRevision,
    completeness: isComplete ? SEARCH_COMPLETENESS.COMPLETE : SEARCH_COMPLETENESS.INCOMPLETE,
    exactResultCount: isComplete ? candidates.length : null,
    scannedExactCandidateCount: candidates.length,
    candidates,
    rejectedCandidateCount: rejected.length,
    diagnostics,
    observability: {
      projectionDocsScanned: scannedVariants.length,
      authoritativeVariantsHydrated: scannedVariants.length,
      candidatesRejectedByHardConstraints: rejected.length,
      candidatesRanked: candidates.length,
      firestoreQueryCount: catalog.firestoreQueryCount || 0,
      searchComplete: isComplete,
      resultPoolReused: false,
    },
    // Deliberately internal server state used only for deterministic
    // narrowing. Consumers must not accept it from clients.
    _catalogSnapshot: catalog,
  };
}

function decodeShoppingQuery(raw) {
  if (!raw || typeof raw !== "object") throw new Error("shopping_search_invalid_query");
  if (!Array.isArray(raw.constraints)) throw new Error("shopping_search_constraints_required");
  return {
    queryId: requiredText(raw.queryId, "query_id"),
    sessionId: requiredText(raw.sessionId, "session_id"),
    revision: Number.isSafeInteger(raw.revision) ? raw.revision : 1,
    availableNow: raw.availableNow === true,
    selectedSizeKeys: normalizeSet(raw.selectedSizeKeys),
    preferredSizeKey: raw.preferredSizeKey == null ? null : String(raw.preferredSizeKey),
    constraints: raw.constraints.map(decodeConstraint),
  };
}

function decodeConstraint(raw) {
  const allowedFields = new Set([
    "canonicalType", "canonicalFamily", "color", "brand", "fit",
    "material", "pattern", "style", "detail", "maxPrice",
  ]);
  const allowedOperators = new Set(["equals", "excludes", "atMost", "includes"]);
  if (!raw || !allowedFields.has(raw.field) || !allowedOperators.has(raw.operator)) {
    throw new Error("shopping_search_invalid_constraint");
  }
  if (!["hard", "soft"].includes(raw.strength)) {
    throw new Error("shopping_search_invalid_constraint_strength");
  }
  return {
    field: raw.field,
    operator: raw.operator,
    value: raw.value,
    strength: raw.strength,
    source: raw.source || "explicitUser",
    relaxable: raw.relaxable !== false,
    absolute: raw.absolute === true,
  };
}

function evaluateVariant({query, product, variant, offers, sizesByOffer}) {
  const constraintEvidence = [];
  const selectedSizeKeys = normalizeSet(query.selectedSizeKeys);
  const sizeRequest = {
    selectedSizeKeys,
    preferredSizeKey: query.preferredSizeKey || null,
    availableNow: query.availableNow,
  };
  const bestOffer = resolveBestOffer({...sizeRequest, offers, sizesByOffer});

  for (const constraint of query.constraints) {
    const evidence = evaluateConstraint({constraint, product, variant, offers, sizesByOffer, sizeRequest, bestOffer});
    constraintEvidence.push(evidence);
  }
  if (query.availableNow && !bestOffer?.purchasableForSelectedSize) {
    constraintEvidence.push({
      field: "availableNow",
      operator: "equals",
      strength: "hard",
      source: "query",
      status: MATCH_STATUS.MISMATCH,
      reason: "NO_VERIFIED_PURCHASABLE_SELECTED_SIZE",
    });
  }
  if (!offers.some((offer) => offer.lifecycleState !== LIFECYCLE.DISCONTINUED)) {
    constraintEvidence.push({
      field: "offerLifecycle",
      operator: "equals",
      strength: "hard",
      source: "server",
      status: MATCH_STATUS.MISMATCH,
      reason: "NO_ACTIVE_OFFER",
    });
  }
  const hardFailures = constraintEvidence.filter((evidence) =>
    evidence.strength === "hard" && evidence.status !== MATCH_STATUS.MATCH);
  const exact = hardFailures.length === 0;
  const softScore = constraintEvidence
    .filter((evidence) => evidence.strength === "soft" && evidence.status === MATCH_STATUS.MATCH)
    .length;
  const freshnessScore = bestOffer?.freshness?.stale === true ? 0 : 1;
  const priceScore = bestOffer ? -bestOffer.effectivePrice.price.amountMinor : -Number.MAX_SAFE_INTEGER;
  const candidate = {
    variantId: variant.variantId,
    productId: product.productId,
    relevantOfferIds: offers
      .filter((offer) => offer.lifecycleState !== LIFECYCLE.DISCONTINUED)
      .map((offer) => offer.offerId).sort(),
    bestOfferId: bestOffer?.offer?.offerId || null,
    effectivePublicPrice: bestOffer?.effectivePrice || null,
    selectedSizeEvidence: bestOffer ? {
      selectedSizeKey: bestOffer.selectedSizeKey,
      availability: bestOffer.sizeAvailability?.availability || null,
      purchasableForSelectedSize: bestOffer.purchasableForSelectedSize,
    } : null,
    freshnessEvidence: bestOffer?.freshness || {stale: true, reason: "NO_ACTIVE_OFFER"},
    constraintEvidence,
    unmetConstraints: constraintEvidence.filter((item) => item.status !== MATCH_STATUS.MATCH),
    suitabilityEvidence: {
      status: "NOT_EVALUATED",
      reason: "No safe Phase 3 OutfitSuitabilityPolicyV2 context adapter available.",
    },
    wardrobeCompatibilityEvidence: {status: "NOT_EVALUATED"},
    setSignal: 0,
    rankingComponents: {
      hardConstraintGate: hardFailures.length === 0,
      softPreferenceScore: softScore,
      freshnessScore,
      selectedSizePurchasableScore: bestOffer?.purchasableForSelectedSize ? 1 : 0,
      validPublicPriceMinor: bestOffer?.effectivePrice.price.amountMinor || null,
      validPublicPriceCurrency: bestOffer?.effectivePrice.price.currency || null,
      priceScore,
    },
    deterministicScore: softScore * 1000 + freshnessScore * 100 +
      (bestOffer?.purchasableForSelectedSize ? 10 : 0) +
      (bestOffer ? Math.max(0, 9 - Math.floor(bestOffer.effectivePrice.price.amountMinor / 10000)) : 0),
  };
  return {exact, candidate, constraintEvidence};
}

function evaluateConstraint({constraint, product, variant, offers, sizesByOffer, sizeRequest, bestOffer}) {
  let actual;
  if (constraint.field === "canonicalType") actual = product.canonicalType;
  else if (constraint.field === "canonicalFamily") actual = product.canonicalFamily;
  else if (constraint.field === "color") actual = variant.colorProfile?.primary?.family;
  else if (constraint.field === "brand") actual = product.brand;
  else if (constraint.field === "fit") actual = variant.fit;
  else if (constraint.field === "material") actual = variant.material;
  else if (constraint.field === "pattern") actual = variant.pattern;
  else if (constraint.field === "style") actual = variant.styles;
  else if (constraint.field === "detail") actual = variant.detailAttributes;
  else if (constraint.field === "maxPrice") {
    return evaluateMaxPrice(constraint, offers, sizesByOffer, sizeRequest, bestOffer);
  }
  const status = compareKnown(actual, constraint);
  return {
    field: constraint.field,
    operator: constraint.operator,
    value: constraint.value,
    strength: constraint.strength,
    source: constraint.source,
    relaxable: constraint.relaxable,
    absolute: constraint.absolute,
    status,
    actual: actual == null ? null : actual,
    reason: status === MATCH_STATUS.UNKNOWN ? "CATALOG_FACT_UNKNOWN" : null,
  };
}

function evaluateMaxPrice(constraint, offers, sizesByOffer, sizeRequest, bestOffer) {
  const max = decodeMoneyConstraint(constraint.value);
  const comparable = [];
  let incompatibleCurrency = false;
  for (const offer of offers) {
    if (offer.lifecycleState === LIFECYCLE.DISCONTINUED) continue;
    const price = effectivePublicPrice(offer);
    if (price.price.currency !== max.currency) {
      incompatibleCurrency = true;
      continue;
    }
    const resolution = resolveBestOffer({...sizeRequest, offers: [offer], sizesByOffer});
    comparable.push({price, resolution});
  }
  const matching = comparable.some((entry) => entry.price.price.amountMinor <= max.amountMinor);
  return {
    field: constraint.field,
    operator: constraint.operator,
    value: max,
    strength: constraint.strength,
    source: constraint.source,
    relaxable: constraint.relaxable,
    absolute: constraint.absolute,
    status: matching ? MATCH_STATUS.MATCH :
      (comparable.length === 0 && incompatibleCurrency ? MATCH_STATUS.UNKNOWN : MATCH_STATUS.MISMATCH),
    actual: bestOffer?.effectivePrice.price || null,
    reason: matching ? null :
      (incompatibleCurrency ? "CURRENCY_INCOMPATIBLE" : "NO_PUBLIC_EFFECTIVE_PRICE_AT_OR_BELOW_MAX"),
  };
}

function compareKnown(actual, constraint) {
  if (actual == null) return MATCH_STATUS.UNKNOWN;
  if (constraint.field === "detail") {
    if (!constraint.value || typeof constraint.value !== "object") return MATCH_STATUS.UNKNOWN;
    const value = actual[constraint.value.key];
    if (value == null) return MATCH_STATUS.UNKNOWN;
    return compareValue(value, constraint.value.value, constraint.operator);
  }
  if (Array.isArray(actual)) {
    if (actual.length === 0) return MATCH_STATUS.UNKNOWN;
    const values = normalizeSet(actual);
    const wanted = String(constraint.value).toLowerCase();
    const present = values.has(wanted);
    return constraint.operator === "excludes" ? (present ? MATCH_STATUS.MISMATCH : MATCH_STATUS.MATCH) :
      (present ? MATCH_STATUS.MATCH : MATCH_STATUS.MISMATCH);
  }
  return compareValue(actual, constraint.value, constraint.operator);
}

function compareValue(actual, wanted, operator) {
  const left = typeof actual === "string" ? actual.toLowerCase() : actual;
  const right = typeof wanted === "string" ? wanted.toLowerCase() : wanted;
  if (operator === "excludes") return left === right ? MATCH_STATUS.MISMATCH : MATCH_STATUS.MATCH;
  return left === right ? MATCH_STATUS.MATCH : MATCH_STATUS.MISMATCH;
}

function resolveBestOffer({offers, sizesByOffer, selectedSizeKeys = new Set(), preferredSizeKey = null, availableNow = false}) {
  const selected = normalizeSet(selectedSizeKeys);
  const candidates = [];
  for (const offer of offers) {
    if (offer.lifecycleState === LIFECYCLE.DISCONTINUED) continue;
    const sizes = sizesByOffer.get(offer.offerId) || [];
    const size = chooseSize(sizes, selected, preferredSizeKey);
    const purchasable = offer.overallAvailability === AVAILABILITY.AVAILABLE &&
      (selected.size === 0 || size?.availability === AVAILABILITY.AVAILABLE);
    if (availableNow && !purchasable) continue;
    candidates.push({
      offer,
      effectivePrice: effectivePublicPrice(offer),
      sizeAvailability: size || null,
      selectedSizeKey: size?.normalizedSizeKey || null,
      purchasableForSelectedSize: purchasable,
      freshness: offer.freshness || {stale: true},
    });
  }
  candidates.sort((left, right) => {
    const leftSizeRank = sizeRank(left.selectedSizeKey, preferredSizeKey, selected);
    const rightSizeRank = sizeRank(right.selectedSizeKey, preferredSizeKey, selected);
    if (leftSizeRank !== rightSizeRank) return leftSizeRank - rightSizeRank;
    if (left.purchasableForSelectedSize !== right.purchasableForSelectedSize) {
      return left.purchasableForSelectedSize ? -1 : 1;
    }
    if ((left.freshness.stale === true) !== (right.freshness.stale === true)) {
      return left.freshness.stale === true ? 1 : -1;
    }
    const priceOrder = compareMoney(left.effectivePrice.price, right.effectivePrice.price);
    if (priceOrder !== 0) return priceOrder;
    return left.offer.offerId.localeCompare(right.offer.offerId);
  });
  return candidates[0] || null;
}

function chooseSize(sizes, selected, preferredSizeKey) {
  if (selected.size === 0) return null;
  return [...sizes]
    .filter((size) => selected.has(String(size.normalizedSizeKey).toLowerCase()))
    .sort((left, right) => {
      const rank = sizeRank(left.normalizedSizeKey, preferredSizeKey, selected) -
        sizeRank(right.normalizedSizeKey, preferredSizeKey, selected);
      return rank || String(left.normalizedSizeKey).localeCompare(String(right.normalizedSizeKey));
    })[0] || null;
}

function sizeRank(key, preferredSizeKey, selected) {
  if (selected.size === 0) return 0;
  if (key == null) return 3;
  if (preferredSizeKey != null && String(key).toLowerCase() === String(preferredSizeKey).toLowerCase()) return 0;
  return selected.has(String(key).toLowerCase()) ? 1 : 2;
}

function compareCandidates(left, right) {
  const l = left.rankingComponents;
  const r = right.rankingComponents;
  if (l.softPreferenceScore !== r.softPreferenceScore) return r.softPreferenceScore - l.softPreferenceScore;
  if (l.freshnessScore !== r.freshnessScore) return r.freshnessScore - l.freshnessScore;
  if (l.selectedSizePurchasableScore !== r.selectedSizePurchasableScore) {
    return r.selectedSizePurchasableScore - l.selectedSizePurchasableScore;
  }
  const lPrice = l.validPublicPriceMinor ?? Number.MAX_SAFE_INTEGER;
  const rPrice = r.validPublicPriceMinor ?? Number.MAX_SAFE_INTEGER;
  if (l.validPublicPriceCurrency === r.validPublicPriceCurrency && lPrice !== rPrice) {
    return lPrice - rPrice;
  }
  return left.variantId.localeCompare(right.variantId);
}

function buildZeroResultDiagnostics(query, funnel, rejected) {
  const blockers = query.constraints
    .filter((constraint) => constraint.strength === "hard")
    .map((constraint, index) => ({
      constraint,
      verifiedMatchCount: funnel[index].match,
      mismatchCount: funnel[index].mismatch,
      unknownCount: funnel[index].unknown,
      blocksExactResults: funnel[index].match === 0,
      maySuggestRelaxation: constraint.relaxable !== false && constraint.absolute !== true,
    }))
    .filter((item) => item.blocksExactResults || item.mismatchCount > 0 || item.unknownCount > 0);
  return {
    exactResultCount: 0,
    blockingConstraints: blockers,
    rejectedCandidateCount: rejected.length,
  };
}

function initialFunnel(constraints) {
  return constraints.map(() => ({match: 0, mismatch: 0, unknown: 0}));
}

function updateFunnel(funnel, evidence) {
  for (let index = 0; index < evidence.length; index++) {
    const current = evidence[index];
    if (funnel[index] && current.status) {
      funnel[index][current.status.toLowerCase()]++;
    }
  }
}

function decodeMoneyConstraint(value) {
  if (!value || !Number.isSafeInteger(value.amountMinor) || value.amountMinor < 0 ||
      !/^[A-Z]{3}$/.test(String(value.currency || ""))) {
    throw new Error("shopping_search_invalid_max_price");
  }
  return {amountMinor: value.amountMinor, currency: value.currency};
}

function catalogRevisionFor(catalog) {
  const canonical = JSON.stringify({
    products: [...(catalog.products || [])].sort(byId("productId")),
    variants: [...(catalog.variants || [])].sort(byId("variantId")),
    offers: [...(catalog.offers || [])].sort(byId("offerId")),
    sizes: [...(catalog.sizes || [])].sort((a, b) =>
      `${a.offerId}:${a.normalizedSizeKey}`.localeCompare(`${b.offerId}:${b.normalizedSizeKey}`)),
  });
  return `catalog_${crypto.createHash("sha256").update(canonical).digest("hex").slice(0, 16)}`;
}

function mapBy(values, field) {
  return new Map(values.map((value) => [value[field], value]));
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
function normalizeSet(value) {
  return new Set([...(value || [])].map((item) => String(item).toLowerCase()));
}
function requiredText(value, name) {
  const text = String(value || "").trim();
  if (!text) throw new Error(`shopping_search_invalid_${name}`);
  return text;
}
function compareMoney(left, right) {
  // No FX policy exists in Phase 3. Different currencies are deliberately
  // incomparable; callers continue to stable non-price tie breakers.
  if (left.currency !== right.currency) return 0;
  return left.amountMinor - right.amountMinor;
}
function byId(field) {
  return (left, right) => String(left[field]).localeCompare(String(right[field]));
}

module.exports = {
  MATCH_STATUS,
  SEARCH_COMPLETENESS,
  SEARCH_CONTRACT_VERSION,
  catalogRevisionFor,
  decodeShoppingQuery,
  resolveBestOffer,
  searchCatalog,
};
