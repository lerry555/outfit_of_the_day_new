"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createStylistChatV2Handler} = require("./stylist_production_bridge_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");

const NOW = Date.parse("2026-09-09T06:00:00.000Z");

test("first production V2 turn bootstraps persisted selection reasons without fail-closed", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const wardrobeTool = {
    async retrieve(request) {
      const ids = Array.isArray(request?.itemIds) ? request.itemIds : [];
      return ids.map((id) => ({id, category: "tops", bodySlots: ["upper_body"]}));
    },
    async materialize(itemIds, reasonsByItemId) {
      return itemIds.map((id) => ({id, name: id, selectionReason: reasonsByItemId[id] || null}));
    },
  };
  const stylistModel = {
    planningNeedsCurrentOutfit: false,
    async turn() {
      return {
        kind: "final",
        statePatch: {},
        result: {
          action: "chat",
          assistantText: "Outfit nechávam bez zmeny.",
          display: {kind: "none", itemIds: []},
        },
      };
    },
  };
  const warnings = [];
  const handler = createStylistChatV2Handler({
    db: {},
    admin: {},
    logger: {warn(message, data) { warnings.push({message, data}); }},
    resolveOpenAISecret: async () => "unused",
    clock: () => NOW,
    sessionRepository: repository,
    locationResolver: {async resolve() { return null; }},
    weatherTool: {async getForecast() { return null; }},
    modelFactory: () => stylistModel,
    wardrobeToolFactory: () => wardrobeTool,
    shoppingToolFactory: () => ({
      async search() { return {candidateIds: [], appliedHardConstraints: []}; },
    }),
  });

  const response = await handler({
    v2SessionId: "chat_bootstrap",
    turnId: "turn_bootstrap",
    message: "Čo povieš na tento outfit?",
    currentOutfitItemIds: ["shirt", "jeans"],
    currentSelectionReasons: [
      {itemId: "shirt", reason: "sedí k zvyšku"},
      {itemId: "jeans", reason: "vhodný spodný diel"},
    ],
    clientContext: {},
  }, {auth: {uid: "user-a"}});

  assert.equal(response.ok, true);
  assert.equal(response.failClosed, false);
  assert.equal(response.action, "chat");
  assert.deepEqual(response.resultingOutfitItemIds, ["shirt", "jeans"]);
  assert.equal(warnings.length, 0);

  const stored = await repository.get({uid: "user-a", chatId: "chat_bootstrap"});
  assert.deepEqual(stored.state.currentOutfit.selectionReasonsByItemId, {
    shirt: "sedí k zvyšku",
    jeans: "vhodný spodný diel",
  });
});

test("production bridge routes generic fashion advice through fast chat before expensive tools", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {fast: 0, model: 0, wardrobe: 0, info: []};
  const handler = createStylistChatV2Handler({
    db: {},
    admin: {},
    logger: {
      warn() {},
      info(message, data) { calls.info.push({message, data}); },
    },
    resolveOpenAISecret: async () => "unused",
    clock: () => NOW,
    sessionRepository: repository,
    fastChatFactory: () => ({
      async turn({message}) {
        calls.fast += 1;
        assert.equal(message, "Aké farby sa hodia k modrej?");
        return {reply: "K modrej funguje biela, sivá aj béžová. Pre výraznejší kontrast môžeš pridať oranžový detail."};
      },
    }),
    modelFactory: () => {
      calls.model += 1;
      throw new Error("full_model_must_not_run");
    },
    wardrobeToolFactory: () => {
      calls.wardrobe += 1;
      throw new Error("wardrobe_must_not_run");
    },
    locationResolver: {async resolve() { throw new Error("location_must_not_run"); }},
    weatherTool: {async getForecast() { throw new Error("weather_must_not_run"); }},
    shoppingToolFactory: () => ({async search() { throw new Error("shopping_must_not_run"); }}),
  });

  const response = await handler({
    v2SessionId: "fast_chat",
    turnId: "fast_1",
    message: "Aké farby sa hodia k modrej?",
    history: [],
    currentOutfitItemIds: [],
    currentSelectionReasons: [],
    shoppingEnabled: false,
    clientContext: {},
  }, {auth: {uid: "user-fast"}});

  assert.equal(response.ok, true);
  assert.equal(response.failClosed, false);
  assert.equal(response.action, "chat");
  assert.equal(response.modelPath, "stylist_v2_fast_chat");
  assert.equal(response.quickReplyMode, "none");
  assert.deepEqual(response.resultingOutfitItemIds, []);
  assert.equal(calls.fast, 1);
  assert.equal(calls.model, 0);
  assert.equal(calls.wardrobe, 0);
  assert.ok(calls.info.some((entry) => entry.message === "STYLIST_V2_TURN_LATENCY" && entry.data?.path === "fast_chat"));
});

test("server local advice intro bypasses every AI/tool path", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {model: 0, fast: 0, wardrobe: 0, location: 0, weather: 0};
  const handler = createStylistChatV2Handler({
    db: {}, admin: {}, logger: {warn() {}, info() {}}, resolveOpenAISecret: async () => "unused", clock: () => NOW,
    sessionRepository: repository,
    fastChatFactory: () => { calls.fast += 1; throw new Error("fast_chat_must_not_be_created"); },
    modelFactory: () => { calls.model += 1; throw new Error("model_must_not_run"); },
    wardrobeToolFactory: () => { calls.wardrobe += 1; throw new Error("wardrobe_must_not_run"); },
    shoppingToolFactory: () => ({async search() { throw new Error("shopping_must_not_run"); }}),
    locationResolver: {async resolve() { calls.location += 1; throw new Error("location_must_not_run"); }},
    weatherTool: {async getForecast() { calls.weather += 1; throw new Error("weather_must_not_run"); }},
  });

  const response = await handler({
    v2SessionId: "local_intro", turnId: "intro_1", message: "ahoj divočák potrebujem poradiť",
    history: [], currentOutfitItemIds: [], currentSelectionReasons: [], shoppingEnabled: false, clientContext: {},
  }, {auth: {uid: "user-local"}});

  assert.equal(response.ok, true);
  assert.equal(response.modelPath, "stylist_v2_local_chat");
  assert.equal(response.reply, "Ahoj! Jasné 🙂 S čím ti môžem pomôcť?");
  assert.deepEqual(calls, {model: 0, fast: 0, wardrobe: 0, location: 0, weather: 0});
});
