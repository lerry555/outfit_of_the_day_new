"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {buildCachedSimpleAgentInputV1} = require("../simple_stylist_prompt_cache_v1");
const {
  createOpenAiStylistModelPortV2,
  finalEnvelope,
  shoppingQuickReplyPromptV2,
} = require("./openai_stylist_model_port_v2");

function baseInput() {
  return {
    phase: "final",
    request: {turnId: "turn-1", latestUserInput: "vyber mi outfit"},
    session: {context: {terrain: {surface: null, difficulty: null, condition: null}}, currentOutfit: {itemIds: [], selectionReasonsByItemId: {}}},
    preflightResolution: {},
    toolResults: {
      wardrobeItems: [{
        id: "shirt", name: "Tričko", canonicalType: "t_shirt", canonicalFamily: "tops",
        bodySlots: ["upper_body"], layerPosition: "base", warmth: 1, formality: 1,
        productImageUrl: "https://img.example/product.png", cutoutImageUrl: "https://img.example/cutout.png",
        cleanImageUrl: "https://img.example/clean.png", imageUrl: "https://img.example/person.jpg",
        originalImageUrl: "https://img.example/person.jpg", storagePath: "wardrobe/u/shirt.jpg",
        cleanStoragePath: "wardrobe_clean/u/shirt.png", productStoragePath: "wardrobe_product/u/shirt.png",
        processing: {product: "done"},
      }],
      weatherSnapshot: {summary: "mild"},
    },
  };
}

function validChatRaw() {
  return {
    action: "chat", assistantText: "Jasné.", resultingOutfitItemIds: [], selectionReasons: [],
    displayKind: "none", displayItemIds: [], editReplaceItemIds: [], editRetainItemIds: [],
    editAllowedSlots: [], editAllowedCategories: [], editAllowRemovalOnly: false,
    clarificationField: null, clarificationQuestion: null, offerShopping: false,
    shoppingNeedLabel: null, shoppingNeedCanonicalType: null,
    shoppingHardConstraints: [], shoppingSoftPreferences: [],
  };
}

test("final model payload sends semantic wardrobe once and strips image transport fields", async () => {
  let call;
  const port = createOpenAiStylistModelPortV2({
    executeStructured: async (input) => {
      call = input;
      return validChatRaw();
    },
  });
  await port.turn(baseInput());
  assert.equal(call.model, "gpt-5.6-luna");
  assert.equal(call.reasoningEffort, "low");
  const payload = JSON.parse(call.messages[1].content);
  assert.equal(Object.hasOwn(payload, "wardrobeV2"), false);
  assert.equal(payload.toolResults.wardrobeItems.length, 1);
  const item = payload.toolResults.wardrobeItems[0];
  assert.equal(item.id, "shirt");
  for (const key of ["productImageUrl", "cutoutImageUrl", "cleanImageUrl", "imageUrl", "originalImageUrl", "storagePath", "cleanStoragePath", "productStoragePath", "processing"]) {
    assert.equal(Object.hasOwn(item, key), false, key);
  }
  assert.deepEqual(payload.toolResults.weatherSnapshot, {summary: "mild"});
});

test("production prompt cache accepts the V2 nested wardrobe contract without duplicating inventory", async () => {
  let cached;
  const port = createOpenAiStylistModelPortV2({
    executeStructured: async (input) => {
      // This is the real adapter used by createOpenAiSimpleAgentExecutorV1.
      // Before this regression fix it threw: `wardrobeV2 is not iterable`.
      cached = buildCachedSimpleAgentInputV1(input, "test-scope");
      return validChatRaw();
    },
  });

  await port.turn(baseInput());

  const cachedInventory = JSON.parse(cached.input[1].content[0].text);
  assert.deepEqual(cachedInventory.toolResults.wardrobeItems.map((item) => item.id), ["shirt"]);
  assert.equal(Object.hasOwn(cachedInventory, "wardrobeV2"), false);

  const turn = JSON.parse(cached.input[2].content);
  assert.equal(Object.hasOwn(turn, "wardrobeV2"), false);
  assert.equal(Object.hasOwn(turn.toolResults, "wardrobeItems"), false);
  assert.deepEqual(turn.toolResults.weatherSnapshot, {summary: "mild"});
});

test("prompt cache keeps the legacy top-level wardrobeV2 contract compatible", () => {
  const cached = buildCachedSimpleAgentInputV1({
    messages: [
      {role: "system", content: "legacy"},
      {role: "user", content: JSON.stringify({
        wardrobeV2: [{id: "b"}, {id: "a"}],
        weatherContext: {summary: "mild"},
      })},
    ],
  }, "legacy-scope");

  const cachedInventory = JSON.parse(cached.input[1].content[0].text);
  assert.deepEqual(cachedInventory.wardrobeV2.map((item) => item.id), ["a", "b"]);
  const turn = JSON.parse(cached.input[2].content);
  assert.equal(Object.hasOwn(turn, "wardrobeV2"), false);
  assert.deepEqual(turn.weatherContext, {summary: "mild"});
});

test("shopping CTA is footwear-specific instead of anonymous yes/no buttons", () => {
  assert.equal(shoppingQuickReplyPromptV2("turistická obuv", "hiking_shoes"),
    "Chceš, aby som ti pozrel vhodné topánky v obchodoch?");
  const envelope = finalEnvelope({
    action: "generate_outfit", assistantText: "Tenisky sú tu len kompromis. Chceš, aby som ti niečo vybral?",
    resultingOutfitItemIds: ["shirt"], selectionReasons: [{itemId: "shirt", reason: "ľahký vrch"}],
    displayKind: "outfit", displayItemIds: ["shirt"], editReplaceItemIds: [], editRetainItemIds: [],
    editAllowedSlots: [], editAllowedCategories: [], editAllowRemovalOnly: false,
    clarificationField: null, clarificationQuestion: null, offerShopping: true,
    shoppingNeedLabel: "turistická obuv", shoppingNeedCanonicalType: "hiking_shoes",
    shoppingHardConstraints: [], shoppingSoftPreferences: [],
  }, baseInput());
  assert.equal(envelope.result.quickReplyPrompt,
    "Chceš, aby som ti pozrel vhodné topánky v obchodoch?");
  assert.doesNotMatch(envelope.result.assistantText, /Chceš/i);
});

test("model payload excludes durable replay history and full weather arrays", async () => {
  let call;
  const input = baseInput();
  input.session.replay = {turns: Array.from({length: 30}, (_, i) => ({turnId: `old-${i}`, result: {assistantText: "old"}}))};
  input.session.wardrobePreferences = {retrievalCache: {huge: "x".repeat(5000)}};
  input.session.context.weather = {
    locationProviderId: "place:1", dateKey: "2026-09-11", timeWindowKey: "day", source: "open-meteo",
    snapshot: {temperatureC: Array(24).fill(12), weatherCode: Array(24).fill(1), representativeTempC: 12, minTempC: 8, maxTempC: 15, willRain: false},
  };
  const port = createOpenAiStylistModelPortV2({executeStructured: async (request) => { call = request; return validChatRaw(); }});
  await port.turn(input);
  const payload = JSON.parse(call.messages[1].content);
  assert.equal(Object.hasOwn(payload.session, "replay"), false);
  assert.equal(Object.hasOwn(payload.session, "wardrobePreferences"), false);
  assert.equal(Object.hasOwn(payload.session, "scenarioMemory"), false);
  assert.equal(Object.hasOwn(payload.session.context.weather.snapshot, "temperatureC"), false);
  assert.equal(payload.session.context.weather.snapshot.representativeTempC, 12);
});

test("wardrobe projection sent to model is semantic and intentionally lean", async () => {
  let call;
  const input = baseInput();
  input.toolResults.wardrobeItems[0].debugBlob = "x".repeat(2000);
  input.toolResults.wardrobeItems[0].colorProfile = {primary: {family: "blue", lab: [1, 2, 3]}, accents: [{family: "white", huge: "x".repeat(1000)}]};
  const port = createOpenAiStylistModelPortV2({executeStructured: async (request) => { call = request; return validChatRaw(); }});
  await port.turn(input);
  const item = JSON.parse(call.messages[1].content).toolResults.wardrobeItems[0];
  assert.equal(item.id, "shirt");
  assert.equal(item.primaryColor, "blue");
  assert.deepEqual(item.accentColors, ["white"]);
  assert.equal(Object.hasOwn(item, "colorProfile"), false);
  assert.equal(Object.hasOwn(item, "debugBlob"), false);
});

test("shopping CTA can offer both missing hiking pants and footwear", () => {
  assert.equal(
    shoppingQuickReplyPromptV2("turistické nohavice a turistická obuv", "hiking_pants_and_shoes"),
    "Chceš, aby som ti pozrel vhodné turistické nohavice a topánky v obchodoch?",
  );
});


test("absent warmth/formality stay absent instead of becoming zero", async () => {
  let call;
  const input = baseInput();
  input.toolResults.wardrobeItems[0].warmth = null;
  input.toolResults.wardrobeItems[0].formality = null;
  const port = createOpenAiStylistModelPortV2({executeStructured: async (request) => { call = request; return validChatRaw(); }});
  await port.turn(input);
  const item = JSON.parse(call.messages[1].content).toolResults.wardrobeItems[0];
  assert.equal(Object.hasOwn(item, "warmth"), false);
  assert.equal(Object.hasOwn(item, "formality"), false);
});
