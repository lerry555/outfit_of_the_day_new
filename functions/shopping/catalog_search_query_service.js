"use strict";

const {catalogRevisionFor, searchCatalog} = require("./catalog_search_service");
const {POOL_REFINEMENT, evaluateRefinement} = require("./shopping_result_pool");

async function executeCatalogSearch({query, repository}) {
  const catalog = await repository.readCompleteSnapshot();
  const result = searchCatalog({query, catalog, catalogRevision: catalogRevisionFor(catalog)});
  return result;
}

/**
 * A complete broader snapshot can be filtered/ranked locally for narrowing.
 * Broadening or a catalog revision change requires a fresh repository read.
 */
function refineCatalogSearch({previousQuery, nextQuery, previousResult, currentCatalogRevision}) {
  const decision = evaluateRefinement({
    previousQuery,
    nextQuery,
    previousSearchComplete: previousResult.completeness === "COMPLETE",
    catalogRevisionUnchanged: previousResult.catalogRevision === currentCatalogRevision,
  });
  if (decision === POOL_REFINEMENT.REQUERY_REQUIRED) {
    return {decision};
  }
  const result = searchCatalog({
    query: nextQuery,
    catalog: previousResult._catalogSnapshot,
    catalogRevision: previousResult.catalogRevision,
  });
  result.observability.resultPoolReused = true;
  return {decision, result};
}

module.exports = {
  executeCatalogSearch,
  refineCatalogSearch,
};
