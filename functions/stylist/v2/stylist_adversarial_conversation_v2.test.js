"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {buildCachedSimpleAgentInputV1} = require("../simple_stylist_prompt_cache_v1");
const {createOpenAiStylistModelPortV2} = require("./openai_stylist_model_port_v2");
const {createStylistChatV2Handler} = require("./stylist_production_bridge_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");

const NOW = Date.parse("2026-09-09T08:30:00.000Z");
const UID = "qa_adversarial_user";
const TATRY = {
  providerId: "place:tatry",
  label: "Vysoké Tatry",
  lat: 49.1667,
  lng: 20.1333,
  source: "adversarial_gate",
  granularity: "locality",
};
const WARDROBE = Object.freeze([
  Object.freeze({
    id: "shirt", name: "Čierne tričko", category: "tops", canonicalType: "t_shirt",
    canonicalFamily: "tops", bodySlots: ["upper_body"], layerPosition: "base",
    colors: ["black"], warmth: 2, formality: 2, seasons: ["spring", "summer", "autumn"],
  }),
  Object.freeze({
    id: "pants", name: "Sivé nohavice", category: "bottoms", canonicalType: "trousers",
    canonicalFamily: "bottoms", bodySlots: ["lower_body"], layerPosition: "base",
    colors: ["gray"], warmth: 3, formality: 3, seasons: ["spring", "autumn"],
  }),
  Object.freeze({
    id: "sneakers", name: "Biele tenisky", category: "footwear", canonicalType: "sneakers",
    canonicalFamily: "footwear", bodySlots: ["feet"], layerPosition: "base",
    colors: ["white"], warmth: 2, formality: 2, seasons: ["spring", "summer", "autumn"],
    safety: {hikingTechnical: false},
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

function toolPlan({activityId, activityLabel, locationQuery = null, weatherRequired = false}) {
  return {
    kind: "tool_request",
    action: "none",
    assistantText: "",
    clarificationField: null,
    clarificationQuestion: null,
    locationQuery,
    locationTargetField: locationQuery ? "destination" : "none",
    wardrobeScope: "full_relevant",
    wardrobeCategory: null,
    replaceItemIds: [],
    retainItemIds: [],
    allowedSlots: [],
    allowedCategories: [],
    allowRemovalOnly: false,
    patch: {
      ...patchDefaults(),
      activityId,
      activityLabel,
      dateKey: "2026-09-10",
      timeWindowKey: "day",
      replaceGroundingRequirements: true,
      weatherRequired,
      weatherLocationField: weatherRequired ? "destination" : "none",
    },
  };
}

function finalRaw(activityId) {
  const hiking = activityId === "hiking";
  return {
    action: "generate_outfit",
    assistantText: hiking
      ? "Na bežnú suchú túru volím ľahký a pohodlný základ z tvojho šatníka. Tenisky beriem len ako kompromis na nenáročný chodník."
      : "Do kina volím jednoduchú pohodlnú kombináciu, ktorá pôsobí upravene bez zbytočného preháňania.",
    resultingOutfitItemIds: ["shirt", "pants", "sneakers"],
    selectionReasons: [
      {itemId: "shirt", reason: "praktický vrch"},
      {itemId: "pants", reason: "pohodlný spodný diel"},
      {itemId: "sneakers", reason: "pohodlná dostupná obuv"},
    ],
    displayKind: "outfit",
    displayItemIds: ["shirt", "pants", "sneakers"],
    editReplaceItemIds: [],
    editRetainItemIds: [],
    editAllowedSlots: [],
    editAllowedCategories: [],
    editAllowRemovalOnly: false,
    clarificationField: null,
    clarificationQuestion: null,
    offerShopping: false,
    shoppingNeedLabel: null,
    shoppingNeedCanonicalType: null,
    shoppingHardConstraints: [],
    shoppingSoftPreferences: [],
  };
}

function data(chatId, turnId, message) {
  return {
    v2SessionId: chatId,
    chatId,
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
  };
}

function harness() {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {model: [], wardrobe: [], location: [], weather: [], cache: [], warnings: []};

  const wardrobeTool = {
    async retrieve(request) {
      calls.wardrobe.push(JSON.parse(JSON.stringify(request || {})));
      return WARDROBE.map((item) => JSON.parse(JSON.stringify(item)));
    },
    async materialize(ids, reasons = {}) {
      const byId = new Map(WARDROBE.map((item) => [item.id, item]));
      return ids.map((id) => byId.get(id)).filter(Boolean).map((item) => ({
        ...JSON.parse(JSON.stringify(item)),
        ...(reasons[item.id] ? {stylistSelectionReason: reasons[item.id]} : {}),
      }));
    },
  };

  const executeStructured = async (input) => {
    calls.model.push({schemaName: input.schemaName, model: input.model, reasoningEffort: input.reasoningEffort});
    calls.cache.push(buildCachedSimpleAgentInputV1(input, "adversarial-gate"));
    const payload = JSON.parse(input.messages[1].content);
    const message = String(payload?.request?.latestUserInput || "").toLocaleLowerCase("sk-SK");
    if (input.schemaName === "stylist_v2_plan") {
      if (/kino|kina/.test(message)) {
        return toolPlan({activityId: "cinema", activityLabel: "kino", weatherRequired: false});
      }
      if (/tatr|tatier/.test(message)) {
        return toolPlan({
          activityId: "hiking",
          activityLabel: "túra",
          locationQuery: "Tatier",
          weatherRequired: true,
        });
      }
      return toolPlan({activityId: "casual", activityLabel: "bežný deň", weatherRequired: false});
    }
    return finalRaw(payload?.session?.context?.activity?.id || null);
  };

  const handler = createStylistChatV2Handler({
    db: {},
    admin: {},
    logger: {
      warn(message, details) { calls.warnings.push({message, details}); },
      info() {},
    },
    resolveOpenAISecret: () => "unused",
    clock: () => NOW,
    sessionRepository: repository,
    locationResolver: {
      async resolve(query) {
        calls.location.push(String(query || ""));
        const normalized = String(query || "").toLocaleLowerCase("sk-SK");
        if (normalized.includes("tatr") || normalized.includes("tatier")) return TATRY;
        return null;
      },
    },
    weatherTool: {
      async getForecast(request) {
        calls.weather.push(JSON.parse(JSON.stringify(request || {})));
        return {
          summary: "dry_mild",
          minTempC: 10,
          maxTempC: 17,
          precipitationMm: 0,
          locationProviderId: request.location.providerId,
          dateKey: request.date.dateKey,
          timeWindowKey: request.timeWindow.key,
          fetchedAt: new Date(NOW).toISOString(),
          source: "adversarial_gate",
        };
      },
    },
    modelFactory: () => createOpenAiStylistModelPortV2({executeStructured}),
    wardrobeToolFactory: () => wardrobeTool,
    shoppingToolFactory: () => ({async search() { return {candidateIds: [], appliedHardConstraints: []}; }}),
  });

  return {handler, repository, calls};
}

async function invoke(h, chatId, turnId, message) {
  return h.handler(data(chatId, turnId, message), {auth: {uid: UID}});
}

function healthy(response) {
  assert.equal(response.ok, true, `response=${JSON.stringify(response)}`);
  assert.equal(response.failClosed, false, `response=${JSON.stringify(response)}`);
}

test("adversarial: complete hike request with destination in one message never asks the destination again", async () => {
  const h = harness();
  const response = await invoke(h, "all_in_one", "a1", "zajtra idem do Tatier na túru, potrebujem outfit");
  healthy(response);
  assert.equal(response.action, "generate_outfit");
  assert.doesNotMatch(response.reply, /kam približne|ktorej časti dňa|presnú trasu/i);
  assert.deepEqual(h.calls.model.map((entry) => entry.schemaName), ["stylist_v2_final"]);
  assert.equal(h.calls.location.length, 1);
  assert.equal(h.calls.weather.length, 1);
  assert.equal(h.calls.wardrobe.length, 1);
  const stored = await h.repository.get({uid: UID, chatId: "all_in_one"});
  assert.equal(stored.state.context.destination.providerId, "place:tatry");
  assert.equal(stored.state.context.activity.id, "hiking");
});

test("adversarial: explicit new indoor plan replaces a pending hike question instead of being geocoded", async () => {
  const h = harness();
  const first = await invoke(h, "change_plan", "c1", "zajtra idem na túru, potrebujem outfit");
  healthy(first);
  assert.equal(first.action, "clarify");

  const before = {...Object.fromEntries(Object.entries(h.calls).map(([key, value]) => [key, value.length]))};
  const response = await invoke(h, "change_plan", "c2", "vlastne nie, zajtra idem do kina, potrebujem outfit");
  healthy(response);
  assert.equal(response.action, "generate_outfit");
  assert.match(response.reply, /kina|kino/i);
  assert.equal(h.calls.location.length, before.location);
  assert.equal(h.calls.weather.length, before.weather);
  assert.equal(h.calls.wardrobe.length, before.wardrobe + 1);
  assert.deepEqual(h.calls.model.slice(before.model).map((entry) => entry.schemaName), ["stylist_v2_plan", "stylist_v2_final"]);

  const stored = await h.repository.get({uid: UID, chatId: "change_plan"});
  assert.equal(stored.state.context.activity.id, "cinema");
  assert.equal(stored.state.context.destination, null);
  assert.equal(stored.state.conversationMemory.pendingQuestion, null);
  assert.equal(stored.state.context.groundingRequirements.weatherRequired, false);
});

test("adversarial: defer phrase ends the pending task instead of silently generating an outfit", async () => {
  const h = harness();
  const first = await invoke(h, "defer", "d1", "zajtra idem na túru, potrebujem outfit");
  healthy(first);
  assert.equal(first.action, "clarify");

  const before = {...Object.fromEntries(Object.entries(h.calls).map(([key, value]) => [key, value.length]))};
  const response = await invoke(h, "defer", "d2", "díky, zatiaľ to nerieš");
  healthy(response);
  assert.equal(response.action, "chat");
  assert.match(response.reply, /jasné|dobre|necháme|ozvi/i);
  assert.equal(h.calls.model.length, before.model);
  assert.equal(h.calls.location.length, before.location);
  assert.equal(h.calls.weather.length, before.weather);
  assert.equal(h.calls.wardrobe.length, before.wardrobe);

  const stored = await h.repository.get({uid: UID, chatId: "defer"});
  assert.equal(stored.state.conversationMemory.pendingQuestion, null);
  assert.deepEqual(stored.state.currentOutfit.itemIds, []);
});

test("adversarial: explicit skip-weather request still proceeds to an outfit", async () => {
  const h = harness();
  const first = await invoke(h, "skip_weather", "s1", "zajtra idem na túru, potrebujem outfit");
  healthy(first);
  assert.equal(first.action, "clarify");

  const response = await invoke(h, "skip_weather", "s2", "nerieš počasie, daj mi proste outfit");
  healthy(response);
  assert.equal(response.action, "generate_outfit");
  assert.equal(h.calls.location.length, 0);
  assert.equal(h.calls.weather.length, 0);
  assert.equal(h.calls.wardrobe.length, 1);
  assert.equal(h.calls.model.length, 1);
});
