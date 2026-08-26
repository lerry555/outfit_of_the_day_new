"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  createMemoryCatalogSearchRepository,
} = require("./catalog_search_repository");
const {
  createShoppingOrchestrator,
} = require("./shopping_orchestration_service");
const {
  handleStylistShoppingTurn,
  validateShoppingAiActionInRuntime,
} = require("./stylist_shopping_runtime");
const {buildShoppingNeeds} = require("./stylist_shopping_contract");

function catalog(count = 7) {
  const products = [];
  const variants = [];
  const offers = [];
  const sizes = [];
  for (let index = 0; index < count; index++) {
    products.push({
      productId: `p${index}`,
      brand: index === 1 ? "Nike" : "Fixture",
      normalizedModelIdentity: `hoodie-${index}`,
      canonicalType: "hoodie",
      canonicalFamily: "top",
    });
    variants.push({
      variantId: `v${index}`,
      productId: `p${index}`,
      exactColorName: "Navy",
      colorProfile: {primary: {family: "navy"}},
      styles: [],
      detailAttributes: {zipper: false},
      lifecycleState: "ACTIVE",
    });
    offers.push({
      offerId: `o${index}`,
      variantId: `v${index}`,
      partnerId: "fixture-store",
      url: `https://fixture.test/${index}`,
      regularPrice: {amountMinor: 1900 + index * 100, currency: "EUR"},
      promotions: [],
      overallAvailability: "AVAILABLE",
      lifecycleState: "ACTIVE",
      freshness: {stale: false},
    });
    sizes.push({
      offerId: `o${index}`,
      normalizedSizeKey: "M",
      availability: "AVAILABLE",
      quantityReliability: "EXACT",
      exactQuantity: 2,
    });
  }
  return {products, variants, offers, sizes};
}

function app(input = catalog()) {
  return createShoppingOrchestrator({
    repository: createMemoryCatalogSearchRepository(input),
  });
}

async function turn(message, shoppingContext = {}, options = {}) {
  return handleStylistShoppingTurn({
    auth: {uid: "user"},
    message,
    shoppingContext,
    orchestrator: options.orchestrator || app(),
    wardrobeSignal: options.wardrobeSignal || null,
  });
}

function response(result) {
  assert.equal(result.handled, true);
  return result.response;
}

test("ambiguous source has exactly one typed question", async () => {
  const value = response(await turn("Ukáž mi niečo k týmto nohaviciam."));
  assert.equal(value.action, "SHOPPING_CLARIFY_SOURCE");
  assert.equal(value.messageAttachments.length, 1);
  assert.deepEqual(value.messageAttachments[0].options, ["WARDROBE", "SHOPPING"]);
});

test("Wardrobe source choice passes the original request to existing Stylist", async () => {
  const result = await turn("WARDROBE", {
    activeClarification: "SHOPPING_SOURCE",
    pendingSourceText: "Ukáž mi niečo k týmto nohaviciam.",
  });
  assert.equal(result.handled, false);
  assert.equal(result.clearShoppingContext, true);
  assert.equal(result.passThroughMessage, "Ukáž mi niečo k týmto nohaviciam.");
});

test("explicit new-item and buy intents start Shopping directly", async () => {
  for (const text of [
    "Ukáž mi niečo nové k týmto nohaviciam.",
    "Chcem si kúpiť mikinu.",
  ]) {
    const value = response(await turn(text));
    assert.equal(value.action, "START_SHOPPING_SEARCH");
    assert.equal(value.messageAttachments[0].kind, "shopping_candidate");
  }
});

test("normal outfit request remains in the existing Stylist path", async () => {
  const result = await turn("Čo si mám obliecť do práce?");
  assert.equal(result.handled, false);
});

test("Wardrobe gap asks permission and owned solution suppresses Shopping", async () => {
  const ask = response(await turn("Potrebujem outfit", {}, {
    wardrobeSignal: {gapDetected: true, needLabel: "košeľa"},
  }));
  assert.equal(ask.action, "ASK_PERMISSION_TO_SHOP");
  const owned = await turn("Potrebujem outfit", {}, {
    wardrobeSignal: {gapDetected: true, suitableOwnedItemExists: true},
  });
  assert.equal(owned.handled, false);
});

test("best-owned compromise offers a replacement without shaming the wardrobe", async () => {
  const ask = response(await turn("Potrebujem outfit", {}, {
    wardrobeSignal: {
      gapDetected: true,
      suitableOwnedItemExists: false,
      bestOwnedCompromiseExists: true,
      needLabel: "trailová obuv s lepším gripom",
    },
  }));
  assert.equal(ask.action, "ASK_PERMISSION_TO_SHOP");
  assert.match(ask.reply, /najbližšiu možnosť/);
  assert.doesNotMatch(ask.reply, /^Chýba ti/);
});

test("permission yes starts and permission no stays in Wardrobe", async () => {
  const yes = response(await turn("áno", {
    activeClarification: "SHOPPING_PERMISSION",
    pendingNeedText: "Chcem si kúpiť mikinu",
  }));
  assert.equal(yes.action, "START_SHOPPING_SEARCH");
  const no = response(await turn("nie", {
    activeClarification: "SHOPPING_PERMISSION",
  }));
  assert.equal(no.action, "RETURN_TO_WARDROBE_STYLIST");
});

test("completely new outfit preserves new-item semantics and multi-item model", () => {
  const completelyNew = buildShoppingNeeds("Chcem úplne nový outfit");
  assert.equal(completelyNew.mode, "COMPLETELY_NEW_OUTFIT");
  assert.equal(completelyNew.allowOwnedSimilarity, true);
  assert.equal(completelyNew.needs.length, 3);
  assert.equal(buildShoppingNeeds("nový top a topánky").needs.length, 2);
  assert.deepEqual(buildShoppingNeeds("mikina + nohavice").needs.map((item) =>
    item.canonicalType), ["hoodie", "trousers"]);
});

test("too expensive asks one question then numeric price reaches Phase 4 refine", async () => {
  const orchestrator = app();
  const started = response(await turn("Chcem si kúpiť mikinu", {}, {orchestrator}));
  const context = started.shoppingContextPatch;
  const ask = response(await turn("Je to drahé.", context, {orchestrator}));
  assert.equal(ask.action, "ASK_SHOPPING_MAX_PRICE");
  const refinedContext = {...context, ...ask.shoppingContextPatch};
  const refined = response(await turn("max 20 €", refinedContext, {orchestrator}));
  assert.equal(refined.action, "REFINE_SHOPPING_SEARCH");
  assert.equal(refined.shoppingContextPatch.query.constraints
    .find((item) => item.field === "maxPrice").value.amountMinor, 2000);
});

test("show more uses the existing pool without a requery", async () => {
  let reads = 0;
  const base = createMemoryCatalogSearchRepository(catalog());
  const repository = {
    async readCompleteSnapshot() {
      reads += 1;
      return base.readCompleteSnapshot();
    },
  };
  const orchestrator = createShoppingOrchestrator({repository});
  const started = response(await turn("Chcem si kúpiť mikinu", {}, {orchestrator}));
  const afterStartReads = reads;
  const more = response(await turn("Ukáž ďalšie.", started.shoppingContextPatch,
    {orchestrator}));
  assert.equal(more.action, "SHOW_MORE_SHOPPING");
  assert.equal(more.messageAttachments[0].payload, undefined);
  assert.equal(reads, afterStartReads + 1, "only catalog-revision validation reads");
});

test("show all emits a compact result-group attachment", async () => {
  const orchestrator = app();
  const started = response(await turn("Chcem si kúpiť mikinu", {}, {orchestrator}));
  const all = response(await turn("Ukáž všetky.", started.shoppingContextPatch,
    {orchestrator}));
  assert.equal(all.action, "SHOW_ALL_SHOPPING");
  assert.equal(all.messageAttachments.length, 1);
  assert.equal(all.messageAttachments[0].kind, "shopping_result_group");
});

test("references focus first, second, unique brand, and authoritative price", async () => {
  const orchestrator = app();
  const started = response(await turn("Chcem si kúpiť mikinu", {}, {orchestrator}));
  let context = started.shoppingContextPatch;
  for (const text of ["prvá", "druhá", "Nike", "za 19 €"]) {
    const focused = response(await turn(text, context,
      {orchestrator}));
    assert.equal(focused.action, "FOCUS_SHOPPING_PRODUCT");
    context = {...context, ...focused.shoppingContextPatch};
  }
});

test("ambiguous references ask once and stale candidates fail Phase 4 validation", async () => {
  const orchestrator = app();
  const started = response(await turn("Chcem si kúpiť mikinu", {}, {orchestrator}));
  const ambiguous = response(await turn("Fixture", started.shoppingContextPatch,
    {orchestrator}));
  assert.equal(ambiguous.messageAttachments.length, 1);
  assert.equal(ambiguous.messageAttachments[0].kind, "shopping_clarification");
  const stale = await orchestrator.sessionStore.get(
    started.shoppingContextPatch.sessionId,
  );
  stale.searchMeta.catalogRevision = "stale-revision";
  await orchestrator.sessionStore.put(stale);
  await assert.rejects(turn("prvá", started.shoppingContextPatch,
    {orchestrator}), (error) => error.code === "POOL_STALE");
});

test("zero-result diagnostics reach copy without silent relaxation", async () => {
  const value = response(await turn("Chcem si kúpiť mikinu", {}, {
    orchestrator: app({products: [], variants: [], offers: [], sizes: []}),
  }));
  assert.equal(value.action, "START_SHOPPING_SEARCH");
  assert.equal(value.zeroResultDiagnostics.exactResultCount, 0);
  assert.match(value.reply, /automaticky neuvoľnil|Presnú zhodu/);
});

test("none of these rejects only presented candidates and advances pool", async () => {
  const orchestrator = app();
  const started = response(await turn("Chcem si kúpiť mikinu", {}, {orchestrator}));
  const next = response(await turn("Ani jedna sa mi nepáči.",
    started.shoppingContextPatch, {orchestrator}));
  assert.equal(next.action, "SHOW_MORE_SHOPPING");
  const first = new Set(started.shoppingContextPatch.presentedVariantIds);
  assert.equal(next.shoppingContextPatch.presentedVariantIds.some((id) =>
    first.has(id)), false);
});

test("style, logo, and darker commands have one safe clarification", async () => {
  const orchestrator = app();
  const started = response(await turn("Chcem si kúpiť mikinu", {}, {orchestrator}));
  for (const text of ["Toto nie je môj štýl.", "bez veľkého loga", "tmavšiu"]) {
    const value = response(await turn(text, started.shoppingContextPatch,
      {orchestrator}));
    assert.equal(value.messageAttachments.length, 1);
    assert.equal(value.messageAttachments[0].kind, "shopping_clarification");
  }
});

test("hard zipper and available-now patches are server refinements", async () => {
  const orchestrator = app();
  const started = response(await turn("Chcem si kúpiť mikinu", {}, {orchestrator}));
  const zipper = response(await turn("bez zipsu", started.shoppingContextPatch,
    {orchestrator}));
  assert.equal(zipper.shoppingContextPatch.query.constraints.some((item) =>
    item.field === "detail" && item.strength === "hard"), true);
  const available = response(await turn("potrebujem to dnes",
    zipper.shoppingContextPatch, {orchestrator}));
  assert.equal(available.shoppingContextPatch.query.availableNow, true);
});

test("topic switch clears Shopping routing and category switch resets focus", async () => {
  const normal = await turn("čo si mám zajtra obliecť do práce?", {
    sessionId: "existing",
    focusedVariantId: "v1",
  });
  assert.equal(normal.handled, false);
  assert.equal(normal.clearShoppingContext, true);
  const orchestrator = app();
  const started = response(await turn("Chcem si kúpiť mikinu", {},
    {orchestrator}));
  const newCategory = response(await turn("teraz mi nájdi nohavice",
    started.shoppingContextPatch, {orchestrator}));
  assert.equal(newCategory.action, "REFINE_SHOPPING_SEARCH");
  assert.equal(newCategory.shoppingContextPatch.query.constraints
    .find((item) => item.field === "canonicalType").value, "trousers");
});

test("liked expensive item offers confirmed Wishlist V2 editor contract", async () => {
  const orchestrator = app();
  const started = response(await turn("Chcem si kúpiť mikinu", {}, {orchestrator}));
  const liked = response(await turn("Tá Nike sa mi páči, ale je drahá.",
    started.shoppingContextPatch, {orchestrator}));
  assert.equal(liked.messageAttachments[0].kind, "wishlist_offer");
  assert.equal(liked.messageAttachments[0].persistenceContract, "WISHLIST_V2");
  assert.equal(liked.messageAttachments[0].persistsOnlyAfterConfirmation, true);
  const editor = response(await turn("áno wishlist", {
    ...started.shoppingContextPatch,
    pendingWishlistOfferVariantId: "v1",
  }, {orchestrator}));
  assert.equal(editor.action, "WISHLIST_EDITOR");
  assert.equal(editor.messageAttachments[0].persistenceContract, "WISHLIST_V2");
});

test("AI-like catalog facts are rejected in the actual runtime validator", () => {
  const context = {presentedVariantIds: ["v1"]};
  assert.deepEqual(validateShoppingAiActionInRuntime(
    {type: "FOCUS_SHOPPING_PRODUCT", variantId: "forged"}, context),
  {valid: false, code: "UNKNOWN_CANDIDATE"});
  for (const field of ["offerId", "price", "store", "url", "coupon",
    "availability", "quantity"]) {
    const validation = validateShoppingAiActionInRuntime({
      type: "FOCUS_SHOPPING_PRODUCT", variantId: "v1", [field]: "forged",
    }, context);
    assert.equal(validation.code, "CATALOG_FACT_FORGERY");
  }
});
