"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {compactWardrobeItemV1, normalizeRequestV1, validateAgentResultV1,
  buildModelInputV1, createSimpleStylistAgentV1, SIMPLE_AGENT_RESULT_SCHEMA} = require("./simple_stylist_agent_v1");
const {footwearWeatherFactsV1, isWinterFootwearV1} = require("./simple_stylist_footwear_v1");
const {buildCachedSimpleAgentInputV1} = require("./simple_stylist_prompt_cache_v1");

function item(id, type, slot, warmth = 3, seasons = ["summer"]) {
  return {id, name: id, ontologyVersion: "2.0.0", canonicalType: type,
    canonicalFamily: slot === "feet" ? "footwear" : slot === "lower_body" ? "bottoms" : "tops",
    bodySlots: [slot], layerPosition: slot === "feet" ? "outer" : "base", warmth, seasons,
    colorProfile: {primary: {family: "black", proportion: 1}}, outfitFunctions: [], occasionFit: []};
}
const wardrobe = [item("top", "t_shirt", "upper_body"), item("bottom", "jeans", "lower_body"),
  item("sneakers", "sneakers", "feet"), item("winter", "winter_boots", "feet", 8, ["autumn", "winter"]),
  item("chelsea", "chelsea_boots", "feet", 4, ["spring", "autumn"]),
  item("hiking", "hiking_shoes", "feet", 5, ["spring", "autumn"]),
  {...item("hoodie", "hoodie", "upper_body", 5), layerPosition: "mid"}];
const mild = {morningTempC: 16, noonTempC: 24, eveningTempC: 21, minTempC: 12,
  maxTempC: 25, willRain: false, fromOpenMeteo: true};
function request({current = [], weather = mild, items = wardrobe, message = "Zajtra ráno ideme na huby, čo si obliecť?"} = {}) {
  return {message, wardrobeItems: items, currentOutfitItemIds: current,
    weatherContext: {tomorrow: weather}, clientContext: {tomorrowDateKey: "2026-09-03"}};
}
function result(shoe = "sneakers", {use = "terrain", status = "conditional", window = "morning", message,
  ids = ["top", "bottom", ...(shoe ? [shoe] : [])], changed = true, requested = true} = {}) {
  const limitation = message ?? (status === "conditional" ?
    "Tenisky ber len na ľahký suchý chodník; na náročný mokrý les ti chýba vhodná turistická obuv." :
    status === "missing" ? "Na tento mokrý terén ti chýba vhodná obuv; doplň turistický pár." : "");
  return {stylistComment: `Toto je návrh. ${limitation}`.trim(), resultingOutfitItemIds: ids,
    displayItemIds: requested ? ids : [], outfitChanged: changed, outfitRequested: requested,
    weatherContextKey: "tomorrow", hardRequirementEvidence: [], commentGroundingEvidence: [],
    selectionReasons: ids.map((itemId) => ({itemId, reason: "Kus pre uvedený účel."})),
    footwearAssessment: {use, weatherWindow: window, status, message: limitation}};
}
const check = (raw, req = request()) => validateAgentResultV1(raw, normalizeRequestV1(req));

test("mild forest morning rejects winter boots even though sneakers are available", () => {
  const checked = check(result("winter"));
  assert.equal(checked.valid, false);
  assert.ok(checked.errors.includes("winter_footwear_without_winter_conditions:winter"));
  assert.ok(checked.errors.includes("terrain_footwear_not_supported:winter"));
});

test("mild wet weather and a winter calendar date do not justify insulated footwear", () => {
  const req = request({weather: {...mild, willRain: true}});
  req.clientContext.tomorrowDateKey = "2026-12-23";
  assert.equal(check(result("winter", {use: "everyday", status: "suitable"}), req).valid, false);
});

test("frost outside winter allows winter boots without claiming traction", () => {
  const req = request({weather: {...mild, morningTempC: -3}});
  req.clientContext.tomorrowDateKey = "2026-04-03";
  assert.equal(check(result("winter"), req).valid, true);
});

test("original hourly WMO snow/freezing precipitation is evidence, rain/clouds are not", () => {
  for (const code of [56, 57, 66, 67, 71, 73, 75, 77, 85, 86]) {
    const codes = Array(24).fill(0); codes[8] = code;
    const req = request({weather: {...mild, hourlyWeatherCodeByLocalHour: codes}});
    assert.equal(check(result("winter"), req).valid, true, `wintry code ${code}`);
  }
  for (const code of [0, 3, 61, 63, 65, 80, 81, 82, 95]) {
    const codes = Array(24).fill(code);
    assert.equal(check(result("winter"), request({weather: {...mild,
      hourlyWeatherCodeByLocalHour: codes}})).valid, false, `non-wintry code ${code}`);
  }
});

test("evening snow cannot justify morning boots and other-day cold cannot leak", () => {
  const codes = Array(24).fill(0); codes[21] = 75;
  const req = request({weather: {...mild, hourlyWeatherCodeByLocalHour: codes}});
  req.weatherContext.today = {morningTempC: -10, willSnow: true};
  req.weatherContext.willSnow = true; // Unscoped sibling facts must not override tomorrow.
  assert.equal(check(result("winter"), req).valid, false);
});

test("hourly requested window wins over the daily aggregate", () => {
  const temps = Array(24).fill(24); temps[8] = -2;
  const weather = {...mild, hourlyTempCByLocalHour: temps};
  assert.equal(check(result("winter"), request({weather})).valid, true);
  assert.equal(check(result("winter", {window: "noon"}), request({weather})).valid, false);
});

test("null, booleans and absent temperatures never become freezing zero", () => {
  for (const value of [null, undefined, false, "", "0", NaN]) {
    assert.equal(footwearWeatherFactsV1({tomorrow: {morningTempC: value}}, "tomorrow", "morning").minTempC, null);
  }
  assert.equal(footwearWeatherFactsV1({tomorrow: {morningTempC: 0}}, "tomorrow", "morning").minTempC, 0);
  assert.deepEqual(footwearWeatherFactsV1({tomorrow: {morningTempC: -5, willSnow: true,
    fromOpenMeteo: false}}, "tomorrow", "morning"), {minTempC: null, wintry: false});
});

test("light Chelsea boots remain possible in town, not a substitute for hiking footwear", () => {
  assert.equal(isWinterFootwearV1(compactWardrobeItemV1(wardrobe.find((it) => it.id === "chelsea"))), false);
  assert.equal(check(result("chelsea", {use: "everyday", status: "suitable"})).valid, true);
  assert.ok(check(result("chelsea")).errors.includes("terrain_footwear_not_supported:chelsea"));
});

test("high-warmth winter boots are recognized across SK and EN season metadata", () => {
  for (const seasons of [["zima", "jeseň"], ["winter", "autumn"]]) {
    assert.equal(isWinterFootwearV1(compactWardrobeItemV1(item("warm", "boots", "feet", 8, seasons))), true);
  }
  assert.equal(isWinterFootwearV1(compactWardrobeItemV1(item("light", "boots", "feet", 4, ["winter"]))), false);
});

test("terrain sneakers require an honest visible limitation; hiking footwear can be suitable", () => {
  assert.equal(check(result()).valid, true);
  assert.ok(check(result("sneakers", {status: "suitable"})).errors.includes("terrain_footwear_requires_honest_limitation:sneakers"));
  assert.equal(check(result("hiking", {status: "suitable"})).valid, true);
  const raw = result(); raw.stylistComment = "Perfektné tenisky do každého lesa.";
  assert.ok(check(raw).errors.includes("footwear_limitation_not_in_comment"));
});

test("explicit footwear gap permits a partial outfit, but never hides a selected pair", () => {
  const req = request({items: wardrobe.filter((it) => !["sneakers", "hiking"].includes(it.id))});
  assert.equal(check(result(null, {status: "missing"}), req).valid, true);
  assert.equal(check(result(null, {status: "suitable"}), req).valid, false);
  assert.ok(check(result("winter", {status: "missing"}), req).errors.includes("missing_footwear_has_selected_shoes"));
});

test("footwear gap cannot bypass other core slots, duplicate pairs or skin-base restrictions", () => {
  assert.equal(check(result(null, {status: "missing", ids: ["top"]})).valid, false);
  assert.equal(check(result(null, {status: "missing", ids: ["top", "bottom", "winter", "sneakers"]})).valid, false);
});

test("partial-outfit explanations and ordinary chat preserve IDs without forcing shoes", () => {
  const req = request({current: ["top", "bottom"], message: "Koľko bude stupňov?"});
  assert.equal(check(result(null, {use: "none", status: "not_applicable", changed: false,
    requested: false}), req).valid, true);
  assert.equal(check(result(null, {status: "missing", changed: false}), req).valid, true);
});

test("an unrelated edit preserves existing shoes while a later footwear edit can correct them", () => {
  const req = request({current: ["top", "bottom", "winter"], message: "Pridaj mikinu."});
  assert.equal(check(result("winter", {ids: ["top", "bottom", "winter", "hoodie"]}), req).valid, true);
  assert.equal(check(result("sneakers"), req).valid, true);
});

test("bad winter selection gets one repair; repeated bad selection still fails closed", async () => {
  let attempts = 0;
  const agent = createSimpleStylistAgentV1({logger: {}, executeModel: async (input) => {
    attempts++;
    if (attempts === 2) assert.ok(JSON.parse(input.messages[1].content).repair.validationErrors
      .includes("winter_footwear_without_winter_conditions:winter"));
    return attempts === 1 ? result("winter") : result("sneakers");
  }});
  const fixed = await agent.resolve(request());
  assert.equal(attempts, 2);
  assert.deepEqual(fixed.resultingOutfitItemIds, ["top", "bottom", "sneakers"]);
  assert.equal(fixed.footwearAssessment.status, "conditional");
  attempts = 0;
  const bad = createSimpleStylistAgentV1({logger: {}, executeModel: async () => {attempts++; return result("winter");}});
  await assert.rejects(() => bad.resolve(request()));
  assert.equal(attempts, 2);
});

test("one-percent detail and broad color panel remain distinct in model and cached transport", () => {
  const hoodie = item("blue", "hoodie", "upper_body", 5);
  const detailed = (p) => ({...hoodie, colorProfile: {primary: {family: "blue", proportion: 1 - p},
    secondary: {family: "black", proportion: p}, accents: [{family: "red", proportion: .02}]}});
  const tiny = compactWardrobeItemV1(detailed(.01));
  const panel = compactWardrobeItemV1(detailed(.4));
  assert.notDeepEqual(tiny, panel);
  assert.equal(tiny.colorProportions.secondary, .01);
  assert.equal(panel.colorProportions.secondary, .4);
  const input = buildModelInputV1(normalizeRequestV1(request({items: [...wardrobe, detailed(.01)]})));
  const transport = buildCachedSimpleAgentInputV1(input, "test");
  assert.ok(JSON.stringify(transport).includes('colorProportions'));
  assert.equal(JSON.parse(input.messages[1].content).wardrobeV2.at(-1).colorProportions.secondary, .01);
});

test("unknown/invalid coverage stays unknown and accent proportions remain aligned", () => {
  const raw = item("detail", "t_shirt", "upper_body");
  raw.colorProfile = {primary: {family: "black", proportion: null}, secondary: {family: "red", proportion: "0.1"},
    accents: [{family: "", proportion: .9}, {family: "blue", proportion: .05}, {family: "white", proportion: 2}]};
  const compact = compactWardrobeItemV1(raw);
  assert.deepEqual(compact.accentColors, ["blue", "white"]);
  assert.deepEqual(compact.colorProportions, {primary: null, secondary: null, accents: [.05, null]});
});

test("strict model contract includes functional assessment and prompt balances tiny details", () => {
  assert.ok(SIMPLE_AGENT_RESULT_SCHEMA.required.includes("footwearAssessment"));
  const input = buildModelInputV1(normalizeRequestV1(request()));
  const prompt = input.messages[0].content;
  assert.ok(prompt.includes("účel a podmienky použitia"));
  assert.ok(prompt.includes("nie najchladnejšia časť dňa"));
  assert.ok(prompt.includes("Drobné približne 1–5 % akcenty nesmú byť hlavným dôvodom"));
  assert.ok(prompt.includes("nevymýšľaj"));
});
