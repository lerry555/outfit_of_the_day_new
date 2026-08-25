"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {AVAILABILITY, LIFECYCLE, PROMOTION_KIND} = require("./catalog_contract");
const {SEARCH_COMPLETENESS, searchCatalog} = require("./catalog_search_service");
const {executeCatalogSearch, refineCatalogSearch} = require("./catalog_search_query_service");
const {createMemoryCatalogSearchRepository} = require("./catalog_search_repository");
const {
  POOL_REFINEMENT,
  createResultPool,
  markShown,
  page,
  rejectCandidate,
  validateProductFocus,
} = require("./shopping_result_pool");

function query(overrides = {}) {
  return {
    queryId: "q", sessionId: "session", revision: 1,
    constraints: [{field: "canonicalType", operator: "equals", value: "hoodie", strength: "hard"}],
    selectedSizeKeys: ["M"], preferredSizeKey: "M", availableNow: false,
    ...overrides,
  };
}

function product(id, overrides = {}) {
  return {
    productId: id, brand: "Fixture", canonicalType: "hoodie",
    canonicalFamily: "top", ...overrides,
  };
}

function variant(id, productId, overrides = {}) {
  return {
    variantId: id, productId, exactColorName: "Navy",
    colorProfile: {primary: {family: "navy"}}, fit: "oversized",
    material: "cotton", pattern: "solid", styles: ["casual"],
    detailAttributes: {zipper: false}, lifecycleState: LIFECYCLE.ACTIVE,
    ...overrides,
  };
}

function offer(id, variantId, overrides = {}) {
  return {
    offerId: id, variantId, partnerId: "store", partnerListingId: id,
    regularPrice: {amountMinor: 4500, currency: "EUR"},
    promotions: [], overallAvailability: AVAILABILITY.AVAILABLE,
    lifecycleState: LIFECYCLE.ACTIVE, freshness: {stale: false}, ...overrides,
  };
}

function size(offerId, key, availability = AVAILABILITY.AVAILABLE, overrides = {}) {
  return {
    offerId, normalizedSizeKey: key, partnerSizeLabel: key, sizeSystem: "INTL",
    availability, exactQuantity: null, quantityReliability: "UNKNOWN", ...overrides,
  };
}

function catalog({products, variants, offers, sizes, scanLimit} = {}) {
  return {products: products || [product("p")], variants: variants || [variant("v", "p")],
    offers: offers || [offer("o", "v")], sizes: sizes || [size("o", "M")], scanLimit};
}

function ids(result) {
  return result.candidates.map((candidate) => candidate.variantId);
}

test("exact canonical type, color, brand, fit, and negative detail constraints gate candidates", () => {
  const result = searchCatalog({
    query: query({constraints: [
      {field: "canonicalType", operator: "equals", value: "hoodie", strength: "hard"},
      {field: "color", operator: "equals", value: "navy", strength: "hard"},
      {field: "brand", operator: "equals", value: "Fixture", strength: "hard"},
      {field: "fit", operator: "equals", value: "oversized", strength: "hard"},
      {field: "detail", operator: "excludes", value: {key: "zipper", value: true}, strength: "hard"},
    ]}),
    catalog: catalog(),
  });
  assert.deepEqual(ids(result), ["v"]);
});

test("family is only matched through an explicit family constraint", () => {
  const input = catalog({products: [product("p", {canonicalType: "zip_hoodie", canonicalFamily: "top"})]});
  assert.equal(searchCatalog({query: query(), catalog: input}).candidates.length, 0);
  const broader = searchCatalog({
    query: query({constraints: [{field: "canonicalFamily", operator: "equals", value: "top", strength: "hard"}]}),
    catalog: input,
  });
  assert.deepEqual(ids(broader), ["v"]);
});

test("white, brand, and fit mismatches cannot satisfy navy hard query", () => {
  const variants = [
    variant("white", "p", {colorProfile: {primary: {family: "white"}}}),
    variant("brand", "brand-product"),
    variant("fit", "p", {fit: "regular"}),
  ];
  const products = [product("p"), product("brand-product", {brand: "Other"})];
  const offers = variants.map((value) => offer(`o-${value.variantId}`, value.variantId));
  const sizes = offers.map((value) => size(value.offerId, "M"));
  const result = searchCatalog({
    query: query({constraints: [
      {field: "color", operator: "equals", value: "navy", strength: "hard"},
      {field: "brand", operator: "equals", value: "Fixture", strength: "hard"},
      {field: "fit", operator: "equals", value: "oversized", strength: "hard"},
    ]}),
    catalog: catalog({products, variants, offers, sizes}),
  });
  assert.equal(result.candidates.length, 0);
});

test("unknown fit and unknown negative detail never verify hard constraints", () => {
  const input = catalog({variants: [variant("v", "p", {fit: null, detailAttributes: {}})]});
  const result = searchCatalog({
    query: query({constraints: [
      {field: "fit", operator: "equals", value: "oversized", strength: "hard"},
      {field: "detail", operator: "excludes", value: {key: "zipper", value: true}, strength: "hard"},
    ]}),
    catalog: input,
  });
  assert.equal(result.candidates.length, 0);
  assert.equal(result.diagnostics.blockingConstraints[0].unknownCount, 1);
});

test("known zipper violates a hard no-zipper constraint without silent relaxation", () => {
  const result = searchCatalog({
    query: query({constraints: [
      {field: "detail", operator: "excludes", value: {key: "zipper", value: true},
        strength: "hard", relaxable: false, absolute: true},
    ]}),
    catalog: catalog({variants: [variant("v", "p", {detailAttributes: {zipper: true}})]}),
  });
  assert.equal(result.candidates.length, 0);
  assert.equal(result.diagnostics.blockingConstraints[0].maySuggestRelaxation, false);
});

test("public coupon qualifies under budget while member-only price does not", () => {
  const variants = [variant("coupon", "p"), variant("member", "p")];
  const offers = [
    offer("coupon-offer", "coupon", {regularPrice: {amountMinor: 5500, currency: "EUR"},
      promotions: [{kind: PROMOTION_KIND.PUBLIC_COUPON, price: {amountMinor: 4900, currency: "EUR"}, code: "SAVE"}]}),
    offer("member-offer", "member", {regularPrice: {amountMinor: 5500, currency: "EUR"},
      promotions: [{kind: PROMOTION_KIND.MEMBER_ONLY, price: {amountMinor: 4500, currency: "EUR"}}]}),
  ];
  const result = searchCatalog({
    query: query({constraints: [{field: "maxPrice", operator: "atMost", value: {amountMinor: 5000, currency: "EUR"}, strength: "hard"}]}),
    catalog: catalog({variants, offers, sizes: [size("coupon-offer", "M"), size("member-offer", "M")]}),
  });
  assert.deepEqual(ids(result), ["coupon"]);
  assert.equal(result.candidates[0].effectivePublicPrice.couponCode, "SAVE");
});

test("currency mismatch is unknown and cannot satisfy a hard price constraint", () => {
  const result = searchCatalog({
    query: query({constraints: [{field: "maxPrice", operator: "atMost", value: {amountMinor: 5000, currency: "EUR"}, strength: "hard"}]}),
    catalog: catalog({offers: [offer("usd", "v", {regularPrice: {amountMinor: 3000, currency: "USD"}})],
      sizes: [size("usd", "M")]}),
  });
  assert.equal(result.candidates.length, 0);
  assert.equal(result.diagnostics.blockingConstraints[0].unknownCount, 1);
});

test("unavailable desired M remains recommendable unless availableNow is required", () => {
  const input = catalog({sizes: [size("o", "M", AVAILABILITY.UNAVAILABLE)]});
  const ordinary = searchCatalog({query: query(), catalog: input});
  const now = searchCatalog({query: query({availableNow: true}), catalog: input});
  assert.deepEqual(ids(ordinary), ["v"]);
  assert.equal(ordinary.candidates[0].selectedSizeEvidence.purchasableForSelectedSize, false);
  assert.equal(now.candidates.length, 0);
});

test("preferred M offer beats cheaper selected L offer when M is available", () => {
  const input = catalog({
    offers: [offer("m", "v", {regularPrice: {amountMinor: 4500, currency: "EUR"}}),
      offer("l", "v", {regularPrice: {amountMinor: 3000, currency: "EUR"}})],
    sizes: [size("m", "M"), size("l", "L")],
  });
  const result = searchCatalog({query: query({selectedSizeKeys: ["M", "L"]}), catalog: input});
  assert.equal(result.candidates[0].bestOfferId, "m");
});

test("selected L is valid when preferred M is unavailable, but unselected sizes never substitute", () => {
  const input = catalog({
    offers: [offer("m", "v"), offer("l", "v")],
    sizes: [size("m", "M", AVAILABILITY.UNAVAILABLE), size("l", "L")],
  });
  const result = searchCatalog({
    query: query({selectedSizeKeys: ["M", "L"], availableNow: true}), catalog: input,
  });
  assert.equal(result.candidates[0].bestOfferId, "l");
  assert.equal(result.candidates[0].selectedSizeEvidence.selectedSizeKey, "L");
});

test("unselected XL and unknown selected size never satisfy availableNow", () => {
  const input = catalog({sizes: [
    size("o", "XL", AVAILABILITY.AVAILABLE),
    size("o", "M", AVAILABILITY.UNKNOWN),
  ]});
  const result = searchCatalog({query: query({availableNow: true}), catalog: input});
  assert.equal(result.candidates.length, 0);
});

test("fresh equivalent offer ranks above stale cheap offer and discontinued offers disappear", () => {
  const variants = [variant("stale", "p"), variant("fresh", "p"), variant("gone", "p")];
  const offers = [
    offer("stale-o", "stale", {regularPrice: {amountMinor: 2000, currency: "EUR"}, freshness: {stale: true}}),
    offer("fresh-o", "fresh", {regularPrice: {amountMinor: 3000, currency: "EUR"}}),
    offer("gone-o", "gone", {lifecycleState: LIFECYCLE.DISCONTINUED}),
  ];
  const result = searchCatalog({
    query: query(), catalog: catalog({variants, offers,
      sizes: [size("stale-o", "M"), size("fresh-o", "M"), size("gone-o", "M")]}),
  });
  assert.deepEqual(ids(result), ["fresh", "stale"]);
});

test("soft preferences rank only after hard gates and stable variantId resolves ties", () => {
  const variants = [variant("b", "p", {styles: ["casual"]}), variant("a", "p", {styles: ["street"]})];
  const offers = [offer("ob", "b"), offer("oa", "a")];
  const input = catalog({variants, offers, sizes: [size("ob", "M"), size("oa", "M")]});
  const tie = searchCatalog({query: query(), catalog: input});
  assert.deepEqual(ids(tie), ["a", "b"]);
  const soft = searchCatalog({
    query: query({constraints: [{field: "style", operator: "includes", value: "casual", strength: "soft"}]}),
    catalog: input,
  });
  assert.deepEqual(ids(soft), ["b", "a"]);
});

test("same query and catalog revision always produce identical ordering", () => {
  const input = catalog({
    variants: [variant("v2", "p"), variant("v1", "p")],
    offers: [offer("o2", "v2"), offer("o1", "v1")],
    sizes: [size("o2", "M"), size("o1", "M")],
  });
  const first = searchCatalog({query: query(), catalog: input});
  const second = searchCatalog({query: query(), catalog: input});
  assert.deepEqual(ids(first), ids(second));
  assert.equal(first.catalogRevision, second.catalogRevision);
});

test("result pool pages 37 candidates without repeats and keeps rejections session-local", () => {
  const products = [], variants = [], offers = [], sizes = [];
  for (let index = 0; index < 37; index++) {
    const id = `v-${String(index).padStart(2, "0")}`;
    products.push(product(`p-${index}`));
    variants.push(variant(id, `p-${index}`));
    offers.push(offer(`o-${index}`, id));
    sizes.push(size(`o-${index}`, "M"));
  }
  const result = searchCatalog({query: query(), catalog: catalog({products, variants, offers, sizes})});
  assert.equal(result.exactResultCount, 37);
  let pool = createResultPool(result);
  const first = page(pool, 3);
  pool = markShown(pool, first);
  pool = rejectCandidate(pool, "v-03");
  const second = page(pool, 3);
  assert.deepEqual(first, ["v-00", "v-01", "v-02"]);
  assert.deepEqual(second, ["v-04", "v-05", "v-06"]);
  assert.equal(page(pool, 99).length, 33);
});

test("complete narrowing reuses snapshot while broadening and revision changes require requery", async () => {
  const input = catalog({products: [product("p", {brand: "Fixture"}), product("p2", {brand: "Other"})],
    variants: [variant("v", "p"), variant("v2", "p2")],
    offers: [offer("o", "v"), offer("o2", "v2")], sizes: [size("o", "M"), size("o2", "M")]});
  const original = query();
  const originalResult = await executeCatalogSearch({
    query: original, repository: createMemoryCatalogSearchRepository(input),
  });
  const narrowed = query({revision: 2, constraints: [...original.constraints,
    {field: "brand", operator: "equals", value: "Fixture", strength: "hard"}]});
  const reusable = refineCatalogSearch({
    previousQuery: original, nextQuery: narrowed, previousResult: originalResult,
    currentCatalogRevision: originalResult.catalogRevision,
  });
  assert.equal(reusable.decision, POOL_REFINEMENT.POOL_REUSABLE);
  assert.deepEqual(ids(reusable.result), ["v"]);
  const broadened = refineCatalogSearch({
    previousQuery: narrowed, nextQuery: original, previousResult: reusable.result,
    currentCatalogRevision: originalResult.catalogRevision,
  });
  assert.equal(broadened.decision, POOL_REFINEMENT.REQUERY_REQUIRED);
  const stale = refineCatalogSearch({
    previousQuery: original, nextQuery: narrowed, previousResult: originalResult,
    currentCatalogRevision: "changed",
  });
  assert.equal(stale.decision, POOL_REFINEMENT.REQUERY_REQUIRED);
});

test("focus must belong to active pool and matching catalog revision", () => {
  const result = searchCatalog({query: query(), catalog: catalog()});
  const pool = createResultPool(result);
  assert.equal(validateProductFocus({pool, catalogRevision: result.catalogRevision, variantId: "v",
    offerId: "o", searchResult: result}).valid, true);
  assert.equal(validateProductFocus({pool, catalogRevision: "new", variantId: "v"}).valid, false);
  assert.equal(validateProductFocus({pool, catalogRevision: result.catalogRevision, variantId: "forged"}).valid, false);
});

test("incomplete scan never reports a misleading exact total", () => {
  const variants = [variant("v1", "p"), variant("v2", "p")];
  const offers = [offer("o1", "v1"), offer("o2", "v2")];
  const result = searchCatalog({query: query(),
    catalog: catalog({variants, offers, sizes: [size("o1", "M"), size("o2", "M")], scanLimit: 1})});
  assert.equal(result.completeness, SEARCH_COMPLETENESS.INCOMPLETE);
  assert.equal(result.exactResultCount, null);
});

test("affiliate terms are not accepted as ranking inputs and low stock stays informational", () => {
  const result = searchCatalog({
    query: query(),
    catalog: catalog({sizes: [size("o", "M", AVAILABILITY.AVAILABLE,
      {exactQuantity: 1, quantityReliability: "EXACT"})]}),
  });
  const serialized = JSON.stringify(result);
  assert.equal(serialized.includes("affiliate"), false);
  assert.equal(result.candidates[0].rankingComponents.lowStockScore, undefined);
});
