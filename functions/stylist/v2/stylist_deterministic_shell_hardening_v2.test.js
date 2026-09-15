"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  parseDeterministicDateV2,
  detectDeterministicEditScopeV2,
} = require("./stylist_deterministic_shell_v2");
const {localCountryLocationHintV2} = require("./open_meteo_ports_v2");
const {explicitStylingDestinationCandidateV2} = require("./stylist_one_brain_engine_v2");
const {sortStylistItemIdsV2} = require("./stylist_outfit_order_v2");
const {materializeStylistCardItemV2, projectWardrobeItemV2} = require("./firestore_wardrobe_tool_v2");

const TODAY = "2026-09-13"; // Sunday.

const dateCases = [
  ["dnes idem na veceru", "2026-09-13"],
  ["zajtra idem na pohovor", "2026-09-14"],
  ["pozajtra ideme na turu", "2026-09-15"],
  ["o 2 dni ideme do Andorry", "2026-09-15"],
  ["o dva dni ideme do Andorry", "2026-09-15"],
  ["za 3 dni mam svadbu", "2026-09-16"],
  ["za tri dni mam svadbu", "2026-09-16"],
  ["o 5 dni koncert", "2026-09-18"],
  ["o pat dni koncert", "2026-09-18"],
  ["o tyzden idem do Pariza", "2026-09-20"],
  ["za jeden tyzden idem do Pariza", "2026-09-20"],
  ["o 2 tyzdne idem na dovolenku", "2026-09-27"],
  ["o dva tyzdne idem na dovolenku", "2026-09-27"],
  ["buduci pondelok praca", "2026-09-14"],
  ["buduci utorok rande", "2026-09-15"],
  ["buducu stredu vecera", "2026-09-16"],
  ["buduci stvrtok koncert", "2026-09-17"],
  ["buduci piatok svadba", "2026-09-18"],
  ["buducu sobotu oslava", "2026-09-19"],
  ["buducu nedelu vylet", "2026-09-20"],
  ["o tyzden v stredu mam pohovor", "2026-09-23"],
  ["15.9. idem na turu", "2026-09-15"],
  ["1.10. idem na koncert", "2026-10-01"],
  ["31.12.2026 ples", "2026-12-31"],
];
for (const [input, expected] of dateCases) {
  test(`date shell: ${input} -> ${expected}`, () => {
    assert.equal(parseDeterministicDateV2(input, TODAY)?.dateKey, expected);
  });
}

const broadCountries = [
  ["USA", "US"], ["U.S.A.", "US"], ["US", "US"], ["Amerika", "US"], ["Ameriky", "US"],
  ["United States", "US"], ["Spojené štáty", "US"],
  ["Kanada", "CA"], ["Kanady", "CA"], ["Mexiko", "MX"], ["Mexika", "MX"],
  ["Brazília", "BR"], ["Brazílie", "BR"], ["Argentína", "AR"], ["Argentíny", "AR"],
  ["Francúzsko", "FR"], ["Francúzska", "FR"], ["Nemecko", "DE"], ["Nemecka", "DE"],
  ["Španielsko", "ES"], ["Španielska", "ES"], ["Taliansko", "IT"], ["Talianska", "IT"],
  ["Portugalsko", "PT"], ["Portugalska", "PT"], ["UK", "GB"], ["U.K.", "GB"],
  ["Veľká Británia", "GB"], ["Britain", "GB"], ["Írsko", "IE"], ["Írska", "IE"],
  ["Nórsko", "NO"], ["Nórska", "NO"], ["Švédsko", "SE"], ["Švédska", "SE"],
  ["Fínsko", "FI"], ["Fínska", "FI"], ["Island", "IS"], ["Japonsko", "JP"], ["Japonska", "JP"],
  ["Austrália", "AU"], ["Austrálie", "AU"], ["Nový Zéland", "NZ"], ["India", "IN"], ["Indie", "IN"],
  ["Švajčiarsko", "CH"], ["Švajčiarska", "CH"], ["Rakúsko", "AT"], ["Rakúska", "AT"],
  ["Poľsko", "PL"], ["Poľska", "PL"], ["Andorra", "AD"], ["Andorry", "AD"],
  ["Česko", "CZ"], ["Česka", "CZ"], ["Maďarsko", "HU"], ["Maďarska", "HU"],
  ["Chorvátsko", "HR"], ["Chorvátska", "HR"], ["Grécko", "GR"], ["Grécka", "GR"],
  ["UAE", "AE"], ["Emiráty", "AE"],
];
for (const [input, code] of broadCountries) {
  test(`country shell: ${input} is broad ${code}`, () => {
    const value = localCountryLocationHintV2(input);
    assert.equal(value?.granularity, "country");
    assert.equal(value?.countryCode, code);
  });
}

const specificPlaces = [
  "New York", "Los Angeles", "San Francisco", "California", "Colorado", "Miami",
  "Toronto", "Vancouver", "Montreal", "Paríž", "Lyon", "Berlín", "Mníchov", "Tokio", "Osaka",
  "Londýn", "Manchester", "Barcelona", "Madrid", "Rím", "Miláno", "Praha", "Viedeň", "Budapešť",
  "Alpy", "Pyreneje", "Tatry", "Vysoké Tatry", "Dolomity", "Mallorca", "Sicília",
];
for (const input of specificPlaces) {
  test(`country shell: ${input} is not a whole country`, () => {
    assert.equal(localCountryLocationHintV2(input), null);
  });
}

const travelCases = [
  ["idem do USA na turistiku a potrebujem outfit", "destination"],
  ["ideme do Kanady na vylet neviem co na seba", "destination"],
  ["idem do Francuzska na svadbu potrebujem outfit", "eventLocation"],
  ["idem do Nemecka na pohovor potrebujem outfit", "eventLocation"],
  ["letime do Spanielska na festival a chcem outfit", "eventLocation"],
  ["cestujem do Japonska na koncert neviem co si obliect", "eventLocation"],
  ["ideme do Rakuska na turu a ja neviem co na seba", "destination"],
  ["ideme do Andorry na turistiku potrebujem outfit", "destination"],
  ["idem do Polska na vylet potrebujem outfit", "destination"],
  ["idem do Talianska na ples potrebujem outfit", "eventLocation"],
  ["cestujeme do UK na koncert potrebujem outfit", "eventLocation"],
  ["letime do USA na festival potrebujem outfit", "eventLocation"],
];
for (const [input, targetField] of travelCases) {
  test(`travel shell extracts ${targetField}: ${input}`, () => {
    const candidate = explicitStylingDestinationCandidateV2(input);
    assert.ok(candidate?.query);
    assert.equal(candidate?.targetField, targetField);
    assert.equal(candidate?.resumeAction, "generate_outfit");
  });
}

const items = [
  {id: "hoodie", name: "Čierna mikina", category: "tops", bodySlots: ["upper_body"], layerPosition: "mid", canonicalType: "hoodie"},
  {id: "tee", name: "Sivé tričko", category: "tops", bodySlots: ["upper_body"], layerPosition: "base", canonicalType: "t_shirt"},
  {id: "pants", name: "Tepláky", category: "bottoms", bodySlots: ["lower_body"], layerPosition: "", canonicalType: "sweatpants"},
  {id: "shoes", name: "Biele tenisky", category: "footwear", bodySlots: ["feet"], layerPosition: "", canonicalType: "sneakers"},
  {id: "hoodie2", name: "Modrá mikina", category: "tops", bodySlots: ["upper_body"], layerPosition: "mid", canonicalType: "hoodie"},
  {id: "tee2", name: "Biele tričko", category: "tops", bodySlots: ["upper_body"], layerPosition: "base", canonicalType: "t_shirt"},
  {id: "pants2", name: "Čierne nohavice", category: "bottoms", bodySlots: ["lower_body"], layerPosition: "", canonicalType: "pants"},
  {id: "shoes2", name: "Čierne tenisky", category: "footwear", bodySlots: ["feet"], layerPosition: "", canonicalType: "sneakers"},
];
const state = {currentOutfit: {itemIds: ["hoodie", "tee", "pants", "shoes"]}};
const editCases = [
  ["mohol by si mi zmenit mikinu za nieco ine?", "hoodie", "hoodie"],
  ["vymen mikinu", "hoodie", "hoodie"],
  ["skus inu mikinu", "hoodie", "hoodie"],
  ["zmen mi tricko", "tee", "upper_body"],
  ["vymen tricko za ine", "tee", "upper_body"],
  ["chcem ine nohavice", "pants", "lower_body"],
  ["zmen gate", "pants", "lower_body"],
  ["vymen teplaky", "pants", "lower_body"],
  ["daj ine topanky", "shoes", "footwear"],
  ["zmen tenisky", "shoes", "footwear"],
];
for (const [input, target, category] of editCases) {
  test(`edit shell authorizes exactly one item: ${input}`, () => {
    const edit = detectDeterministicEditScopeV2(input, state, items);
    assert.equal(edit?.targetItemId, target);
    assert.equal(edit?.category, category);
    assert.deepEqual(edit?.editScope.replaceItemIds, [target]);
    assert.deepEqual(edit?.editScope.retainItemIds, []);
    assert.equal(edit?.editScope.allowRemovalOnly, false);
  });
}

test("edit shell ignores vague non-edit conversation", () => {
  assert.equal(detectDeterministicEditScopeV2("co hovoris na tu mikinu?", state, items), null);
});

test("edit shell refuses a replacement when wardrobe has no alternative", () => {
  assert.equal(detectDeterministicEditScopeV2("zmen mikinu", state, items.filter((x) => x.id !== "hoodie2")), null);
});

function permutations(values) {
  if (values.length <= 1) return [values];
  return values.flatMap((value, index) => permutations(values.filter((_, i) => i !== index)).map((rest) => [value, ...rest]));
}
for (const permutation of permutations(["hoodie", "tee", "pants", "shoes"])) {
  test(`display order is stable for ${permutation.join(",")}`, () => {
    assert.deepEqual(sortStylistItemIdsV2(permutation, items), ["hoodie", "tee", "pants", "shoes"]);
  });
}

test("image lineage preserves product/cutout/clean/original candidates", () => {
  const item = projectWardrobeItemV2("x", {
    name: "Test mikina", category: "tops", bodySlots: ["upper_body"], layerPosition: "mid",
    productImageUrl: "https://example.test/product.png",
    cutoutImageUrl: "https://example.test/cutout.png",
    cleanImageUrl: "https://example.test/clean.png",
    imageUrl: "https://example.test/original.png",
    productStoragePath: "product/x.png", cleanStoragePath: "clean/x.png", storagePath: "raw/x.png",
  });
  const card = materializeStylistCardItemV2(item, "reason");
  assert.equal(card.productImageUrl, "https://example.test/product.png");
  assert.equal(card.cutoutImageUrl, "https://example.test/cutout.png");
  assert.equal(card.cleanImageUrl, "https://example.test/clean.png");
  assert.equal(card.imageUrl, "https://example.test/original.png");
  assert.equal(card.stylistSelectionReason, "reason");
});


test("date shell rolls an implicit month/day into the next year", () => {
  assert.equal(parseDeterministicDateV2("15.1. ideme na ples", "2026-12-20")?.dateKey, "2027-01-15");
});

test("date shell keeps an implicit month/day on today when it is the same date", () => {
  assert.equal(parseDeterministicDateV2("20.12. ideme na veceru", "2026-12-20")?.dateKey, "2026-12-20");
});

test("date shell honors an explicitly written past year instead of silently rewriting it", () => {
  assert.equal(parseDeterministicDateV2("15.1.2026 sme mali ples", "2026-12-20")?.dateKey, "2026-01-15");
});

test("date shell finds the next valid leap day for an implicit 29 February", () => {
  assert.equal(parseDeterministicDateV2("29.2. ideme na oslavu", "2027-03-01")?.dateKey, "2028-02-29");
});

test("date shell treats this weekday as inclusive but future weekday wording as strictly future", () => {
  assert.equal(parseDeterministicDateV2("tento stvrtok vecera", "2026-09-17")?.dateKey, "2026-09-17");
  assert.equal(parseDeterministicDateV2("buduci stvrtok vecera", "2026-09-17")?.dateKey, "2026-09-24");
  assert.equal(parseDeterministicDateV2("stvrtok vecera", "2026-09-17")?.dateKey, "2026-09-24");
});

test("date shell declines authority for conflicting simple date wording", () => {
  assert.equal(parseDeterministicDateV2("zajtra nie, radsej dnes", TODAY), null);
  assert.equal(parseDeterministicDateV2("dnes alebo zajtra", TODAY), null);
  assert.equal(parseDeterministicDateV2("15.9. alebo 16.9.", TODAY), null);
  assert.equal(parseDeterministicDateV2("15.9. alebo zajtra", TODAY), null);
});

test("edit shell does not treat the adjective 'ine' as an edit command by itself", () => {
  assert.equal(detectDeterministicEditScopeV2("ake ine tenisky mam?", state, items), null);
  assert.equal(detectDeterministicEditScopeV2("mas aj ine tenisky?", state, items), null);
  assert.equal(detectDeterministicEditScopeV2("ukaz mi ine tenisky", state, items), null);
  assert.equal(detectDeterministicEditScopeV2("co ine by sa hodilo k tej mikine?", state, items), null);
  assert.equal(detectDeterministicEditScopeV2("zmenil by si mikinu?", state, items), null);
});

test("edit shell distinguishes a hoodie from an outer jacket in the same outfit", () => {
  const layeredItems = [
    ...items,
    {id: "jacket", name: "Čierna bunda", category: "tops", bodySlots: ["upper_body"], layerPosition: "outer", canonicalType: "jacket"},
    {id: "jacket2", name: "Modrá bunda", category: "tops", bodySlots: ["upper_body"], layerPosition: "outer", canonicalType: "jacket"},
  ];
  const layeredState = {currentOutfit: {itemIds: ["jacket", "hoodie", "tee", "pants", "shoes"]}};
  const hoodieEdit = detectDeterministicEditScopeV2("zmen mikinu", layeredState, layeredItems);
  assert.equal(hoodieEdit?.targetItemId, "hoodie");
  assert.equal(hoodieEdit?.category, "hoodie");
  const jacketEdit = detectDeterministicEditScopeV2("zmen bundu", layeredState, layeredItems);
  assert.equal(jacketEdit?.targetItemId, "jacket");
  assert.equal(jacketEdit?.category, "jacket");
});

test("edit shell treats skirt as lower-body clothing, never as a full-body garment", () => {
  const skirtItems = [
    {id: "skirt", name: "Čierna sukňa", category: "bottoms", bodySlots: ["lower_body"], canonicalType: "skirt"},
    {id: "skirt2", name: "Béžová sukňa", category: "bottoms", bodySlots: ["lower_body"], canonicalType: "skirt"},
    {id: "tee", name: "Tričko", category: "tops", bodySlots: ["upper_body"], canonicalType: "t_shirt"},
  ];
  const skirtState = {currentOutfit: {itemIds: ["skirt", "tee"]}};
  const edit = detectDeterministicEditScopeV2("vymen suknu", skirtState, skirtItems);
  assert.equal(edit?.targetItemId, "skirt");
  assert.equal(edit?.category, "lower_body");
  assert.deepEqual(edit?.editScope.allowedSlots, ["lower_body"]);
});

test("display order falls back to category/canonical metadata when bodySlots are missing", () => {
  const legacyItems = [
    {id: "legacyShoes", category: "footwear", canonicalType: "sneakers"},
    {id: "legacyTee", category: "tops", canonicalType: "t_shirt"},
    {id: "legacyPants", category: "bottoms", canonicalType: "pants"},
    {id: "legacyJacket", category: "outerwear", canonicalType: "jacket"},
    {id: "legacyCap", category: "accessories", accessoryGroup: "headwear"},
  ];
  assert.deepEqual(
    sortStylistItemIdsV2(legacyItems.map((item) => item.id), legacyItems),
    ["legacyJacket", "legacyTee", "legacyPants", "legacyShoes", "legacyCap"],
  );
});


test("edit shell allows a different lower-body type when replacing sweatpants", () => {
  const edit = detectDeterministicEditScopeV2("vymen teplaky", state, items);
  assert.equal(edit?.targetItemId, "pants");
  assert.equal(edit?.category, "lower_body");
  assert.ok(edit?.editScope.allowedCategories.includes("bottoms"));
});

test("edit shell allows footwear-category alternatives when replacing sneakers", () => {
  const mixedFootwear = [
    ...items.filter((item) => item.id !== "shoes2"),
    {id: "boots2", name: "Čierne čižmy", category: "footwear", bodySlots: ["feet"], canonicalType: "boots"},
  ];
  const edit = detectDeterministicEditScopeV2("zmen tenisky", state, mixedFootwear);
  assert.equal(edit?.targetItemId, "shoes");
  assert.equal(edit?.category, "footwear");
});


test("date shell declines authority across mixed independent date-expression families", () => {
  const conflicting = [
    "15.9. alebo o 2 dni",
    "15.9. alebo buduci piatok",
    "o 2 dni alebo o 3 dni",
    "buduci piatok alebo sobotu",
    "pozajtra alebo buduci utorok",
    "o tyzden alebo 30.9.",
    "o dva tyzdne alebo najblizsi piatok",
  ];
  for (const input of conflicting) {
    assert.equal(parseDeterministicDateV2(input, TODAY), null, input);
  }
});

test("date shell keeps overlapping compound recognizers as one date expression", () => {
  assert.equal(parseDeterministicDateV2("o tyzden v stredu mam pohovor", TODAY)?.dateKey, "2026-09-23");
  assert.equal(parseDeterministicDateV2("za 2 tyzdne vo stvrtok koncert", TODAY)?.dateKey, "2026-10-01");
  assert.equal(parseDeterministicDateV2("o dva tyzdne v piatok vylet", TODAY)?.dateKey, "2026-10-02");
});
