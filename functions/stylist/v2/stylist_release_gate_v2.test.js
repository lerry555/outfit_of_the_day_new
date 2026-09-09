"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {buildCachedSimpleAgentInputV1} = require("../simple_stylist_prompt_cache_v1");
const {createOpenAiStylistModelPortV2} = require("./openai_stylist_model_port_v2");
const {createStylistChatV2Handler} = require("./stylist_production_bridge_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");

const NOW = Date.parse("2026-09-09T08:30:00.000Z");
const UID = "qa_user";
const TATRY = {
  providerId: "place:tatry",
  label: "Vysoké Tatry",
  lat: 49.1667,
  lng: 20.1333,
  source: "release_gate",
  granularity: "locality",
};
const USA = {
  providerId: "place:usa",
  label: "United States",
  lat: 39.8,
  lng: -98.6,
  source: "release_gate",
  granularity: "country",
};

const WARDROBE = Object.freeze([
  Object.freeze({
    id: "shirt", name: "Čierne tričko", category: "tops", canonicalType: "t_shirt",
    canonicalFamily: "tops", bodySlots: ["upper_body"], layerPosition: "base",
    colorProfile: {primary: {family: "black", proportion: 1}}, colors: ["black"],
    warmth: 2, formality: 2, outfitFunctions: ["base_layer"], seasons: ["spring", "summer", "autumn"],
    productImageUrl: "https://example.invalid/shirt-product.png",
  }),
  Object.freeze({
    id: "pants", name: "Sivé tepláky", category: "bottoms", canonicalType: "joggers",
    canonicalFamily: "bottoms", bodySlots: ["lower_body"], layerPosition: "base",
    colorProfile: {primary: {family: "gray", proportion: 1}}, colors: ["gray"],
    warmth: 4, formality: 1, outfitFunctions: ["casual"], seasons: ["spring", "autumn"],
    productImageUrl: "https://example.invalid/pants-product.png",
  }),
  Object.freeze({
    id: "sneakers", name: "Športové tenisky", category: "footwear", canonicalType: "running_shoes",
    canonicalFamily: "footwear", bodySlots: ["feet"], layerPosition: "base",
    colorProfile: {primary: {family: "white", proportion: 1}}, colors: ["white"],
    warmth: 2, formality: 1, outfitFunctions: ["sport"], seasons: ["spring", "summer", "autumn"],
    safety: {hikingTechnical: false}, productImageUrl: "https://example.invalid/shoes-product.png",
  }),
  Object.freeze({
    id: "hoodie", name: "Svetlomodrá mikina", category: "tops", canonicalType: "hoodie",
    canonicalFamily: "tops", bodySlots: ["upper_body"], layerPosition: "mid",
    colorProfile: {primary: {family: "blue", proportion: 1}}, colors: ["blue"],
    warmth: 5, formality: 1, outfitFunctions: ["mid_layer"], seasons: ["spring", "autumn", "winter"],
    productImageUrl: "https://example.invalid/hoodie-product.png",
  }),
]);

function patchDefaults() {
  return {
    activityId: null,
    activityLabel: null,
    dateKey: null,
    timeWindowKey: null,
    terrainSurface: "unknown",
    terrainDifficulty: "unknown",
    terrainCondition: "unknown",
    replaceGroundingRequirements: false,
    weatherRequired: false,
    weatherLocationField: "none",
    terrainRequiredFields: [],
  };
}

function plannerWardrobeRaw() {
  return {
    kind: "tool_request",
    action: "none",
    assistantText: "",
    clarificationField: null,
    clarificationQuestion: null,
    locationQuery: null,
    locationTargetField: "none",
    wardrobeScope: "full_relevant",
    wardrobeCategory: null,
    replaceItemIds: [],
    retainItemIds: [],
    allowedSlots: [],
    allowedCategories: [],
    allowRemovalOnly: false,
    patch: patchDefaults(),
  };
}

function finalRaw({hiking = false, invalidId = false} = {}) {
  const shirt = invalidId ? "not_owned" : "shirt";
  return {
    action: "generate_outfit",
    assistantText: hiking
      ? "Na bežnú suchú túru by som zvolil ľahké vrstvy a pohodlný základ. Športové tenisky sú použiteľný kompromis len na nenáročný chodník, nie na technický alebo mokrý terén."
      : "Na bežný deň by som zvolil jednoduchú pohodlnú kombináciu. Je praktická a jednotlivé kúsky spolu pôsobia čisto.",
    resultingOutfitItemIds: [shirt, "pants", "sneakers"],
    selectionReasons: [
      {itemId: shirt, reason: "ľahký vrch"},
      {itemId: "pants", reason: "pohodlný spodný diel"},
      {itemId: "sneakers", reason: "najpraktickejšia dostupná obuv"},
    ],
    displayKind: "outfit",
    displayItemIds: [shirt, "pants", "sneakers"],
    editReplaceItemIds: [],
    editRetainItemIds: [],
    editAllowedSlots: [],
    editAllowedCategories: [],
    editAllowRemovalOnly: false,
    clarificationField: null,
    clarificationQuestion: null,
    offerShopping: hiking,
    shoppingNeedLabel: hiking ? "turistická obuv" : null,
    shoppingNeedCanonicalType: hiking ? "hiking_shoes" : null,
    shoppingHardConstraints: [],
    shoppingSoftPreferences: [],
  };
}

function baseData(sessionId, turnId, message, extra = {}) {
  return {
    v2SessionId: sessionId,
    turnId,
    message,
    history: [],
    currentOutfitItemIds: [],
    currentSelectionReasons: [],
    shoppingEnabled: false,
    clientContext: {
      todayDateKey: "2026-09-09",
      tomorrowDateKey: "2026-09-10",
      timezoneOffsetMinutes: 120,
    },
    ...extra,
  };
}

function makeHarness({invalidFinal = false} = {}) {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {model: [], wardrobe: [], location: [], weather: [], cache: []};

  const wardrobeTool = {
    async retrieve(request) {
      calls.wardrobe.push(JSON.parse(JSON.stringify(request || {})));
      const ids = Array.isArray(request?.itemIds) ? request.itemIds : [];
      if (request?.scope === "current_outfit") return WARDROBE.filter((item) => ids.includes(item.id));
      if (request?.scope === "category") {
        return WARDROBE.filter((item) => item.category === request.category || item.canonicalFamily === request.category);
      }
      return WARDROBE.map((item) => JSON.parse(JSON.stringify(item)));
    },
    async materialize(ids, reasonsById = {}) {
      const byId = new Map(WARDROBE.map((item) => [item.id, item]));
      return ids.map((id) => byId.get(id)).filter(Boolean).map((item) => ({
        ...JSON.parse(JSON.stringify(item)),
        ...(reasonsById[item.id] ? {stylistSelectionReason: reasonsById[item.id]} : {}),
      }));
    },
  };

  const executeStructured = async (input) => {
    calls.model.push({schemaName: input.schemaName, model: input.model, reasoningEffort: input.reasoningEffort});
    const cached = buildCachedSimpleAgentInputV1(input, "release-gate");
    calls.cache.push(cached);
    const payload = JSON.parse(input.messages[1].content);
    if (input.schemaName === "stylist_v2_plan") return plannerWardrobeRaw();
    const hiking = payload?.session?.context?.activity?.id === "hiking";
    return finalRaw({hiking, invalidId: invalidFinal});
  };

  const handler = createStylistChatV2Handler({
    db: {},
    admin: {},
    logger: {warn() {}, info() {}},
    resolveOpenAISecret: () => "unused",
    clock: () => NOW,
    sessionRepository: repository,
    locationResolver: {
      async resolve(query) {
        calls.location.push(query);
        const normalized = String(query || "").toLowerCase();
        if (normalized.includes("usa")) return USA;
        if (normalized.includes("tatr")) return TATRY;
        return null;
      },
    },
    weatherTool: {
      async getForecast(request) {
        calls.weather.push(JSON.parse(JSON.stringify(request || {})));
        return {summary: "dry_mild", minTempC: 10, maxTempC: 17, precipitationMm: 0};
      },
    },
    modelFactory: () => createOpenAiStylistModelPortV2({executeStructured}),
    wardrobeToolFactory: () => wardrobeTool,
    shoppingToolFactory: () => ({async search() { return {candidateIds: [], appliedHardConstraints: []}; }}),
  });

  return {handler, repository, calls};
}

async function invoke(handler, data) {
  return handler(data, {auth: {uid: UID}});
}

function assertHealthy(response) {
  assert.equal(response.ok, true);
  assert.equal(response.failClosed, false);
  assert.notEqual(response.action, "simple_agent_fail_closed");
  assert.ok(String(response.reply || "").trim());
}

test("release gate: server greeting stays cheap and never touches model/tools", async () => {
  const h = makeHarness();
  const response = await invoke(h.handler, baseData("greeting_chat", "g1", "čauko divočák"));
  assertHealthy(response);
  assert.equal(response.action, "chat");
  assert.equal(h.calls.model.length, 0);
  assert.equal(h.calls.wardrobe.length, 0);
  assert.equal(h.calls.location.length, 0);
  assert.equal(h.calls.weather.length, 0);
});

test("release gate: reproduced hike conversation is help-first, one-final-call, and CTA-safe", async () => {
  const h = makeHarness();

  const first = await invoke(h.handler, baseData("hike_chat", "h1", "zajtra idem na túru potrebujem outfit", {
    clientContext: {
      todayDateKey: "2026-09-09", tomorrowDateKey: "2026-09-10", timezoneOffsetMinutes: 120,
      latitude: 49.0614, longitude: 18.9197, userGpsLocation: "Martin, Slovakia",
    },
  }));
  assertHealthy(first);
  assert.equal(first.action, "clarify");
  assert.match(first.reply, /kam približne/i);
  assert.equal(h.calls.model.length, 0);
  assert.equal(h.calls.location.length, 0);
  assert.equal(h.calls.weather.length, 0);
  assert.equal(h.calls.wardrobe.length, 0);

  const why = await invoke(h.handler, baseData("hike_chat", "h2", "načo ti to je"));
  assertHealthy(why);
  assert.equal(why.action, "clarify");
  assert.match(why.reply, /počas/i);
  assert.equal(h.calls.model.length, 0);
  assert.equal(h.calls.location.length, 0);

  const outfit = await invoke(h.handler, baseData("hike_chat", "h3", "do Tatier"));
  assertHealthy(outfit);
  assert.equal(outfit.action, "generate_outfit");
  assert.equal(h.calls.model.length, 1);
  assert.equal(h.calls.model[0].schemaName, "stylist_v2_final");
  assert.equal(h.calls.model[0].model, "gpt-5.6-luna");
  assert.equal(h.calls.location.length, 1);
  assert.equal(h.calls.weather.length, 1);
  assert.equal(h.calls.wardrobe.length, 1);
  assert.deepEqual(outfit.resultingOutfitItemIds, ["shirt", "pants", "sneakers"]);
  assert.equal(outfit.quickReplyMode, "yes_no");
  assert.equal(outfit.quickReplyPrompt, "Chceš, aby som ti vybral vhodnejšie turistické topánky?");
  assert.doesNotMatch(outfit.stylistComment, /chceš/i);
  assert.doesNotMatch(outfit.stylistComment, /kam približne|ktorej časti dňa|presnú trasu/i);

  const modelCallsBeforeReplay = h.calls.model.length;
  const toolCallsBeforeReplay = h.calls.wardrobe.length + h.calls.location.length + h.calls.weather.length;
  const replay = await invoke(h.handler, baseData("hike_chat", "h3", "do Tatier"));
  assert.deepEqual(replay, outfit);
  assert.equal(h.calls.model.length, modelCallsBeforeReplay);
  assert.equal(h.calls.wardrobe.length + h.calls.location.length + h.calls.weather.length, toolCallsBeforeReplay);
});

test("release gate: provisional session migrates without losing the pending destination", async () => {
  const h = makeHarness();
  const first = await invoke(h.handler, baseData("provisional_1", "p1", "zajtra idem na túru potrebujem outfit"));
  assert.equal(first.action, "clarify");

  const second = await invoke(h.handler, baseData("real_chat_1", "p2", "do Tatier", {
    previousV2SessionId: "provisional_1",
    chatId: "real_chat_1",
  }));
  assertHealthy(second);
  assert.equal(second.action, "generate_outfit");
  assert.equal(h.calls.model.length, 1);
  assert.doesNotMatch(second.reply, /kam približne/i);

  const stored = await h.repository.get({uid: UID, chatId: "real_chat_1"});
  assert.equal(stored.state.context.destination.providerId, "place:tatry");
});

test("release gate: user can skip location and still get an outfit without weather/geocoder loops", async () => {
  const h = makeHarness();
  const first = await invoke(h.handler, baseData("skip_chat", "s1", "zajtra idem na túru potrebujem outfit"));
  assert.equal(first.action, "clarify");

  const outfit = await invoke(h.handler, baseData("skip_chat", "s2", "neviem, daj mi proste outfit"));
  assertHealthy(outfit);
  assert.equal(outfit.action, "generate_outfit");
  assert.equal(h.calls.location.length, 0);
  assert.equal(h.calls.weather.length, 0);
  assert.equal(h.calls.wardrobe.length, 1);
  assert.equal(h.calls.model.length, 1);
});

test("release gate: country-only destination narrows once without spending a model call", async () => {
  const h = makeHarness();
  await invoke(h.handler, baseData("country_chat", "c1", "zajtra idem na túru potrebujem outfit"));
  const response = await invoke(h.handler, baseData("country_chat", "c2", "USA"));
  assertHealthy(response);
  assert.equal(response.action, "clarify");
  assert.match(response.reply, /mesto|štát|stat|región|region/i);
  assert.equal(h.calls.model.length, 0);
  assert.equal(h.calls.weather.length, 0);
  assert.equal(h.calls.wardrobe.length, 0);
});

test("release gate: current GPS never silently becomes a remote hike destination", async () => {
  const h = makeHarness();
  const response = await invoke(h.handler, baseData("gps_chat", "gps1", "zajtra idem na túru potrebujem outfit", {
    clientContext: {
      todayDateKey: "2026-09-09", tomorrowDateKey: "2026-09-10", timezoneOffsetMinutes: 120,
      latitude: 49.0614, longitude: 18.9197, userGpsLocation: "Martin, Slovakia",
    },
  }));
  assertHealthy(response);
  assert.equal(response.action, "clarify");
  assert.match(response.reply, /kam približne/i);
  assert.equal(h.calls.location.length, 0);
  assert.equal(h.calls.model.length, 0);
});

test("release gate: generic indoor outfit crosses plan -> cache adapter -> wardrobe -> final without fail-closed", async () => {
  const h = makeHarness();
  const response = await invoke(h.handler, baseData("cinema_chat", "k1", "zajtra idem do kina, potrebujem outfit"));
  assertHealthy(response);
  assert.equal(response.action, "generate_outfit");
  assert.deepEqual(h.calls.model.map((call) => call.schemaName), ["stylist_v2_plan", "stylist_v2_final"]);
  assert.equal(h.calls.wardrobe.length, 1);
  assert.equal(h.calls.location.length, 0);
  assert.equal(h.calls.weather.length, 0);
  assert.equal(h.calls.cache.length, 2);
  for (const cached of h.calls.cache) {
    assert.ok(cached?.input?.length >= 3);
  }
});

test("release gate: invalid model-owned item fails closed and never mutates current outfit", async () => {
  const h = makeHarness({invalidFinal: true});
  const response = await invoke(h.handler, baseData("invalid_chat", "i1", "zajtra idem do kina, potrebujem outfit"));
  assert.equal(response.ok, false);
  assert.equal(response.failClosed, true);
  assert.equal(response.action, "simple_agent_fail_closed");
  assert.deepEqual(response.resultingOutfitItemIds, []);

  const stored = await h.repository.get({uid: UID, chatId: "invalid_chat"});
  assert.ok(stored);
  assert.deepEqual(stored.state.currentOutfit.itemIds, []);
});

test("release gate: unauthenticated production request is rejected before any expensive work", async () => {
  const h = makeHarness();
  await assert.rejects(
    () => h.handler(baseData("auth_chat", "a1", "ahoj"), {}),
    (error) => error?.code === "unauthenticated",
  );
  assert.equal(h.calls.model.length, 0);
  assert.equal(h.calls.wardrobe.length, 0);
  assert.equal(h.calls.location.length, 0);
  assert.equal(h.calls.weather.length, 0);
});
