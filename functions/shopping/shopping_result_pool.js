"use strict";

const POOL_REFINEMENT = Object.freeze({
  POOL_REUSABLE: "POOL_REUSABLE",
  REQUERY_REQUIRED: "REQUERY_REQUIRED",
});

function createResultPool(searchResult) {
  if (!searchResult || !Array.isArray(searchResult.candidates)) {
    throw new Error("shopping_result_pool_search_result_required");
  }
  return {
    queryId: searchResult.queryId,
    queryRevision: searchResult.queryRevision,
    catalogRevision: searchResult.catalogRevision,
    orderedCandidateIds: searchResult.candidates.map((candidate) => candidate.variantId),
    shownCandidateIds: [],
    rejectedCandidateIds: [],
    cursor: 0,
  };
}

function page(pool, limit) {
  requirePool(pool);
  if (!Number.isSafeInteger(limit) || limit < 0) {
    throw new Error("shopping_result_pool_invalid_limit");
  }
  const shown = new Set(pool.shownCandidateIds);
  const rejected = new Set(pool.rejectedCandidateIds);
  return pool.orderedCandidateIds
    .filter((id) => !shown.has(id) && !rejected.has(id))
    .slice(0, limit);
}

function markShown(pool, ids) {
  requirePool(pool);
  const visible = new Set(page(pool, pool.orderedCandidateIds.length));
  const accepted = [...ids].filter((id) => visible.has(id));
  return {
    ...pool,
    shownCandidateIds: unique([...pool.shownCandidateIds, ...accepted]),
    cursor: pool.cursor + accepted.length,
  };
}

function rejectCandidate(pool, candidateId) {
  requirePool(pool);
  if (!pool.orderedCandidateIds.includes(candidateId)) return pool;
  return {...pool, rejectedCandidateIds: unique([...pool.rejectedCandidateIds, candidateId])};
}

function validateProductFocus({pool, catalogRevision, variantId, offerId = null, searchResult}) {
  requirePool(pool);
  if (pool.catalogRevision !== catalogRevision) {
    return {valid: false, reason: "STALE_CATALOG_REVISION"};
  }
  if (!pool.orderedCandidateIds.includes(variantId)) {
    return {valid: false, reason: "VARIANT_NOT_IN_ACTIVE_POOL"};
  }
  if (offerId != null) {
    const candidate = searchResult?.candidates?.find((item) => item.variantId === variantId);
    if (!candidate || !candidate.relevantOfferIds.includes(offerId)) {
      return {valid: false, reason: "OFFER_NOT_IN_CANDIDATE"};
    }
  }
  return {valid: true, focusedVariantId: variantId, focusedOfferId: offerId};
}

function evaluateRefinement({previousQuery, nextQuery, previousSearchComplete, catalogRevisionUnchanged}) {
  if (!previousSearchComplete || !catalogRevisionUnchanged) {
    return POOL_REFINEMENT.REQUERY_REQUIRED;
  }
  return isNarrowerOrEqual(previousQuery, nextQuery) ?
    POOL_REFINEMENT.POOL_REUSABLE : POOL_REFINEMENT.REQUERY_REQUIRED;
}

function isNarrowerOrEqual(previousQuery, nextQuery) {
  const oldConstraints = previousQuery.constraints || [];
  const newConstraints = nextQuery.constraints || [];
  return oldConstraints.every((old) => newConstraints.some((next) =>
    sameConstraintOrNarrower(old, next)));
}

function sameConstraintOrNarrower(old, next) {
  if (old.field !== next.field || old.operator !== next.operator) return false;
  if (old.field === "maxPrice" && old.operator === "atMost") {
    return old.value?.currency === next.value?.currency &&
      Number.isSafeInteger(old.value?.amountMinor) &&
      Number.isSafeInteger(next.value?.amountMinor) &&
      next.value.amountMinor <= old.value.amountMinor;
  }
  return JSON.stringify(old.value) === JSON.stringify(next.value);
}

function unique(values) {
  return [...new Set(values)];
}
function requirePool(pool) {
  if (!pool || !Array.isArray(pool.orderedCandidateIds)) {
    throw new Error("shopping_result_pool_invalid");
  }
}

module.exports = {
  POOL_REFINEMENT,
  createResultPool,
  evaluateRefinement,
  markShown,
  page,
  rejectCandidate,
  validateProductFocus,
};
