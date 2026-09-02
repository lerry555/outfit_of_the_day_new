"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {normalizeRequestV1, validateAgentResultV1, createSimpleStylistAgentV1,
  buildModelInputV1} = require("./simple_stylist_agent_v1");

const wardrobe = [
  ["top", "t_shirt", "tops", "upper_body", "base"],
  ["jeans", "jeans", "bottoms", "lower_body", "base"],
  ["shorts", "casual_shorts", "bottoms", "lower_body", "base"],
  ["sneakers", "running_shoes", "footwear", "feet", "outer"],
  ["other-shoes", "sneakers", "footwear", "feet", "outer"],
  ["hoodie", "hoodie", "tops", "upper_body", "mid"],
].map(([id, canonicalType, canonicalFamily, slot, layerPosition]) => ({
  id, name: id, ontologyVersion: "2.0.0", canonicalType, canonicalFamily,
  bodySlots: [slot], layerPosition, colorProfile: {primary: {family: "black"}},
  warmth: 4, formality: 3, outfitFunctions: [], seasons: ["spring", "autumn"],
}));
const current = ["top", "jeans", "sneakers"];
const warning = "Tenisky ber iba ako kompromis na ľahký suchý terén; do mokrého strmého lesa chýba turistická obuv.";
const noAssessment = {use: "none", weatherWindow: "unknown", status: "not_applicable", message: ""};
const conditional = {use: "terrain", weatherWindow: "morning", status: "conditional", message: warning};
function request(message = "A rifle sú v poriadku?", ids = current, history = [
  {role: "user", content: "Idem ráno na huby, odporuč mi outfit."},
  {role: "assistant", content: `Na ráno skús tričko a rifle. ${warning}`},
]) {
  return normalizeRequestV1({message, history, currentOutfitItemIds: ids,
    currentSelectionReasons: ids.map((itemId) => ({itemId, reason: "Pôvodný dôvod."})),
    wardrobeItems: wardrobe, weatherContext: {tomorrow: {morningTempC: 14, noonTempC: 24,
      willRain: false, fromOpenMeteo: true}}});
}
function answer(overrides = {}) {
  return {stylistComment: "Rifle zakryjú nohy; pri dlhšej chôdzi si over, že ťa neobmedzujú v pohybe.",
    resultingOutfitItemIds: current, displayItemIds: [], outfitChanged: false, outfitRequested: false,
    weatherContextKey: "tomorrow", hardRequirementEvidence: [],
    commentGroundingEvidence: [{itemId: "jeans", outfitContext: "result", field: "included", expectedValue: "true"}],
    selectionReasons: [], footwearAssessment: noAssessment, ...overrides};
}
const check = (raw, req = request()) => validateAgentResultV1(raw, req);

test("garment explanation can ground the exact item without displaying its card", () => {
  const checked = check(answer());
  assert.equal(checked.valid, true, checked.errors.join(","));
  assert.deepEqual(checked.value.displayItemIds, []);
  assert.deepEqual(checked.value.resultingOutfitItemIds, current);
  assert.equal(checked.value.outfitRequested, false);
  assert.equal(checked.value.selectionReasons.length, current.length);
});

test("remembered conditional footwear never forces its warning into an unrelated answer", () => {
  const checked = check(answer({footwearAssessment: conditional}));
  assert.equal(checked.valid, true, checked.errors.join(","));
  assert.ok(!checked.value.stylistComment.includes(warning));
});

test("a newly selected terrain compromise still must disclose its limitation", () => {
  const raw = answer({outfitRequested: true, outfitChanged: true, displayItemIds: current,
    footwearAssessment: conditional, selectionReasons: current.map((itemId) => ({itemId, reason: "Nová voľba."}))});
  assert.ok(check(raw, request("Vyber outfit.", [])).errors.includes("footwear_limitation_not_in_comment"));
  assert.equal(check({...raw, stylistComment: warning}, request("Vyber outfit.", [])).valid, true);
});

test("a newly selected shoe cannot skip assessment even when the rest of the outfit exists", () => {
  const ids = ["top", "jeans", "other-shoes"];
  const raw = answer({resultingOutfitItemIds: ids, displayItemIds: ["other-shoes"],
    outfitChanged: true, outfitRequested: true, selectionReasons: [{itemId: "other-shoes", reason: "Nový pár."}]});
  assert.ok(check(raw).errors.includes("changed_footwear_requires_footwear_assessment"));
});

test("an unrelated layer addition can preserve conditional shoes without repeating their warning", () => {
  const raw = answer({resultingOutfitItemIds: [...current, "hoodie"], displayItemIds: ["hoodie"],
    outfitRequested: true, outfitChanged: true, selectionReasons: [{itemId: "hoodie", reason: "Vrstva na ráno."}]});
  assert.equal(check(raw, request("Pridaj mikinu.")).valid, true);
  assert.equal(check({...raw, footwearAssessment: conditional}, request("Pridaj mikinu.")).valid, true);
});

test("partial outfit explanation preserves the gap without repeating its disclosure", () => {
  const ids = ["top", "jeans"];
  const raw = answer({resultingOutfitItemIds: ids,
    footwearAssessment: {...conditional, status: "missing", message: "Chýba vhodná turistická obuv."}});
  assert.equal(check(raw, request("A rifle sú dobré?", ids)).valid, true);
});

test("adding a layer to a previously partial outfit does not force a new footwear warning", () => {
  const ids = ["top", "jeans"];
  const raw = answer({resultingOutfitItemIds: [...ids, "hoodie"], displayItemIds: ["hoodie"],
    outfitRequested: true, outfitChanged: true, selectionReasons: [{itemId: "hoodie", reason: "Vrstva navyše."}]});
  assert.equal(check(raw, request("Pridaj mikinu.", ids)).valid, true);
  assert.ok(!check({...raw, resultingOutfitItemIds: ["top", "hoodie"]}, request("Pridaj mikinu.", ids)).valid);
});

test("a new footwear gap still needs a visible disclosure", () => {
  const ids = ["top", "jeans"];
  const raw = answer({resultingOutfitItemIds: ids, displayItemIds: ids,
    outfitRequested: true, outfitChanged: true, footwearAssessment: {...conditional, status: "missing"},
    selectionReasons: ids.map((itemId) => ({itemId, reason: "Nový výber."}))});
  assert.ok(check(raw, request("Vyber outfit.", [])).errors.includes("footwear_limitation_not_in_comment"));
  assert.equal(check({...raw, stylistComment: warning}, request("Vyber outfit.", [])).valid, true);
});

test("a direct question about existing shoes may discuss the limitation without changing IDs", () => {
  const raw = answer({stylistComment: warning, footwearAssessment: conditional});
  assert.equal(check(raw, request("A tie tenisky zvládnu mokrý strmý les?")).valid, true);
});

test("explicit show requests can display an item or full outfit without changing it", () => {
  for (const displayItemIds of [["jeans"], current]) {
    assert.equal(check(answer({outfitRequested: true, displayItemIds}),
      request("Ukáž mi outfit.")).valid, true);
  }
});

test("a consultation with an unsolicited card is rejected and repaired once, not silently rendered", async () => {
  const inputs = [];
  const agent = createSimpleStylistAgentV1({logger: {}, executeModel: async (input) => {
    inputs.push(input);
    return answer({displayItemIds: inputs.length === 1 ? ["jeans"] : []});
  }});
  const result = await agent.resolve({message: "A rifle sú v poriadku?", wardrobeItems: wardrobe,
    currentOutfitItemIds: current});
  assert.equal(inputs.length, 2);
  assert.ok(JSON.parse(inputs[1].messages[1].content).repair.validationErrors.includes("chat_turn_display_not_empty"));
  assert.deepEqual(result.displayItems, []);
  assert.deepEqual(result.resultingOutfitItemIds, current);
});

test("consultation rejects actual outfit mutations and selection constraints but permits grounding", () => {
  assert.ok(check(answer({resultingOutfitItemIds: ["top", "shorts", "sneakers"], outfitChanged: true})).errors
    .includes("chat_turn_mutated_current_outfit"));
  assert.ok(check(answer({hardRequirementEvidence: [{itemId: "jeans", field: "included", expectedValue: "true"}]})).errors
    .includes("chat_turn_hard_requirement_not_empty"));
  assert.ok(check(answer({commentGroundingEvidence: [{itemId: "jeans", outfitContext: "result",
    field: "primaryColor", expectedValue: "red"}]})).errors.includes("comment_grounding_not_satisfied:jeans:primaryColor:red"));
});

test("advice agreement, refusal and unavailable-shopping discussion remain text-only", async () => {
  const outputs = [
    "Pri výbere turistickej obuvi si over pohodlné usadenie a vhodnosť podrážky pre plánovaný terén.",
    "Rozumiem. Pri rifliach si najmä over voľnosť pohybu pri kroku do kopca.",
    "Obchody tu zatiaľ neviem prehľadať; hľadaj turistickú obuv pre svoj terén a nechaj si overiť veľkosť pri skúšaní.",
  ];
  const messages = ["Áno, poraď mi.", "Nič kupovať nechcem. Čo ešte tie rifle?", "Nájdi mi pár v obchode do 80 eur."];
  const history = [{role: "assistant", content: "Chceš poradiť, aký typ obuvi hľadať?"}];
  const inputs = [];
  const agent = createSimpleStylistAgentV1({logger: {}, executeModel: async (input) => {
    inputs.push(input); return answer({stylistComment: outputs.shift()});
  }});
  for (const message of messages) {
    const result = await agent.resolve({message, wardrobeItems: wardrobe, currentOutfitItemIds: current, history});
    assert.deepEqual(result.displayItems, []);
    assert.deepEqual(result.resultingOutfitItemIds, current);
    history.push({role: "user", content: message}, {role: "assistant", content: result.reply});
  }
  assert.equal(inputs.length, messages.length);
  assert.ok(JSON.parse(inputs[2].messages[1].content).recentConversationHistory.some((entry) => entry.content.includes("Nič kupovať")));
});

test("the single-model prompt distinguishes consultation, requested cards and feasible help", () => {
  const input = buildModelInputV1(request());
  const prompt = input.messages[0].content;
  assert.ok(prompt.includes("Vysvetlenie nikdy automaticky nezobrazuje kartu"));
  assert.ok(prompt.includes("commentGroundingEvidence vyplň"));
  assert.ok(prompt.includes("Už oznámené upozornenie neopakuj"));
  assert.ok(prompt.includes("jeden konkrétny uskutočniteľný ďalší krok"));
  assert.ok(prompt.includes("MUSÍ nasledovať"));
  assert.ok(prompt.includes("Toto platí aj pri conditional kompromise"));
  assert.ok(prompt.includes("NIE JE pripojený nástroj na prehľadávanie obchodov"));
  assert.ok(prompt.includes("Po súhlase na túto ponuku rovno poraď"));
  assert.ok(!prompt.includes("zobraziť alebo vysvetliť outfit"));
});

test("new-compromise repair asks for an exact current-reply excerpt, not a repeated historical warning", async () => {
  const inputs = [];
  const disclosure = "Tenisky sú iba na ľahký suchý chodník.";
  const agent = createSimpleStylistAgentV1({logger: {}, executeModel: async (input) => {
    inputs.push(input);
    return answer({stylistComment: `Rifle zakryjú nohy. ${disclosure}`,
      displayItemIds: current, outfitChanged: true, outfitRequested: true,
      selectionReasons: current.map((itemId) => ({itemId, reason: "Výber na ranný chodník."})),
      footwearAssessment: {...conditional, message: inputs.length === 1 ? warning : disclosure}});
  }});
  const result = await agent.resolve({message: "Vyber outfit na lesný chodník.", wardrobeItems: wardrobe,
    currentOutfitItemIds: []});
  assert.equal(inputs.length, 2);
  assert.ok(JSON.parse(inputs[1].messages[1].content).repair.footwearDisclosure.includes("presne kopírovať"));
  assert.equal(result.stylistComment.split(disclosure).length - 1, 1);
  assert.equal(result.footwearAssessment.message, disclosure);
});
