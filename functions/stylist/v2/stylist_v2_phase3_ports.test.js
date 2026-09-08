"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createOpenMeteoLocationResolverV2, createOpenMeteoWeatherToolV2} = require("./open_meteo_ports_v2");
const {projectWardrobeItemV2, categoryMatches} = require("./firestore_wardrobe_tool_v2");
const {createEmptySessionStateV2, clone, validateStylistSessionStateV2} = require("./stylist_session_state_v2");
const {resolvePendingReferentV2} = require("./stylist_preflight_v2");
const {planEnvelope} = require("./openai_stylist_model_port_v2");
const {createStylistTurnCoordinatorV2} = require("./stylist_turn_coordinator_v2");

function jsonResponse(body, ok = true) {
  return {ok, status: ok ? 200 : 500, async json() { return body; }};
}

test("Open-Meteo location and weather preserve provider/date/time provenance", async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    calls.push(String(url));
    if (String(url).includes("geocoding-api")) {
      return jsonResponse({results: [{id: 123, name: "Vysoké Tatry", admin1: "Prešovský kraj", country: "Slovensko", latitude: 49.14, longitude: 20.22}]});
    }
    return jsonResponse({timezone: "Europe/Bratislava", hourly: {
      temperature_2m: Array.from({length: 24}, (_, i) => 7 + i / 2),
      precipitation_probability: Array(24).fill(10),
      weather_code: Array(24).fill(1),
      wind_speed_10m: Array(24).fill(12),
    }});
  };
  const location = await createOpenMeteoLocationResolverV2({fetchImpl}).resolve("Vysoké Tatry");
  const weather = await createOpenMeteoWeatherToolV2({fetchImpl, clock: () => Date.UTC(2026, 8, 8, 18)}).getForecast({
    location, date: {dateKey: "2026-09-09"}, timeWindow: {key: "day"},
  });
  assert.equal(location.providerId, "openmeteo:123");
  assert.equal(weather.locationProviderId, "openmeteo:123");
  assert.equal(weather.dateKey, "2026-09-09");
  assert.equal(weather.timeWindowKey, "day");
  assert.equal(weather.source, "open-meteo");
  assert.equal(calls.length, 2);
});

test("weather snapshot is scoped to the requested activity window", () => {
  const hourly = {
    temperature_2m: Array.from({length: 24}, (_, i) => i),
    precipitation_probability: Array(24).fill(0),
    weather_code: Array(24).fill(1),
    wind_speed_10m: Array(24).fill(5),
  };
  const {buildSnapshot} = require("./open_meteo_ports_v2");
  const afternoon = buildSnapshot({timezone: "Europe/Bratislava", hourly}, "afternoon");
  assert.equal(afternoon.minTempC, 12);
  assert.equal(afternoon.maxTempC, 18);
  assert.equal(afternoon.localHours.includes(6), false);
});

test("Wardrobe projection derives only conservative hiking technical authority", () => {
  const hiking = projectWardrobeItemV2("hike", {canonicalType: "hiking_shoes", bodySlots: ["feet"]});
  const sneakers = projectWardrobeItemV2("sneakers", {canonicalType: "sneakers", bodySlots: ["feet"]});
  const winter = projectWardrobeItemV2("winter", {canonicalType: "winter_boots", bodySlots: ["feet"]});
  assert.equal(hiking.category, "footwear");
  assert.equal(hiking.safety.hikingTechnical, true);
  assert.equal(sneakers.safety.hikingTechnical, false);
  assert.equal(winter.safety.hikingTechnical, false);
  assert.equal(categoryMatches(sneakers, "footwear"), true);
});

test("currentLocationObservation is a valid local weather authority without becoming destination", () => {
  const state = clone(createEmptySessionStateV2("chat_local"));
  state.context.currentLocationObservation = {
    providerId: "gps:49.1,18.9", label: "Martin", lat: 49.1, lng: 18.9,
    observedAt: "2026-09-08T18:00:00.000Z", source: "device_gps",
  };
  state.context.groundingRequirements = {
    weatherRequired: true,
    weatherLocationField: "currentLocationObservation",
    terrainRequiredFields: [],
  };
  const valid = validateStylistSessionStateV2(state);
  assert.equal(valid.context.destination, null);
  assert.equal(valid.context.groundingRequirements.weatherLocationField, "currentLocationObservation");
});

test("typed yes/no action IDs resolve against one pending referent", () => {
  const state = clone(createEmptySessionStateV2("chat_actions"));
  state.conversationMemory.pendingAction = {type: "action", kind: "shopping", actionId: "shop_123"};
  const yes = resolvePendingReferentV2(state, {explicitUiActionId: "shop_123_yes", latestUserInput: ""});
  const no = resolvePendingReferentV2(state, {explicitUiActionId: "shop_123_no", latestUserInput: ""});
  assert.equal(yes.answer, "yes");
  assert.equal(no.answer, "no");
});

test("planner normalizer can resolve explicit destination without inventing terrain", () => {
  const state = createEmptySessionStateV2("chat_tatry");
  const envelope = planEnvelope({
    kind: "tool_request", action: "none", assistantText: "", clarificationField: null, clarificationQuestion: null,
    locationQuery: "Vysoké Tatry", locationTargetField: "destination",
    wardrobeScope: "full_relevant", wardrobeCategory: null,
    replaceItemIds: [], retainItemIds: [], allowedSlots: [], allowedCategories: [], allowRemovalOnly: false,
    patch: {
      activityId: "hiking", activityLabel: "túra", dateKey: "2026-09-09", timeWindowKey: "day",
      terrainSurface: "unknown", terrainDifficulty: "unknown", terrainCondition: "unknown",
      replaceGroundingRequirements: true, weatherRequired: true, weatherLocationField: "destination", terrainRequiredFields: [],
    },
  }, {session: state});
  assert.equal(envelope.kind, "tool_request");
  assert.equal(envelope.requests[0].targetField, "destination");
  assert.deepEqual(envelope.statePatch.context.terrain, undefined);
  assert.equal(envelope.statePatch.context.groundingRequirements.weatherLocationField, "destination");
});

test("production planner may receive current outfit facts before freezing edit scope", async () => {
  const state = clone(createEmptySessionStateV2("chat_edit"));
  state.currentOutfit.itemIds = ["shirt", "jeans", "shoes"];
  state.currentOutfit.selectionReasonsByItemId = {shirt: "top", jeans: "coverage", shoes: "comfort"};
  const writes = [];
  const calls = [];
  const repository = {async read() { return clone(state); }, async write(next) { writes.push(next); }};
  const wardrobeTool = {async retrieve(request) {
    calls.push(request);
    return request.itemIds.map((id) => ({id, bodySlots: id === "jeans" ? ["lower_body"] : id === "shoes" ? ["feet"] : ["upper_body"], category: id === "shoes" ? "footwear" : ""}));
  }};
  const stylistModel = {
    planningNeedsCurrentOutfit: true,
    async turn(input) {
      assert.equal(input.phase, "plan");
      assert.equal(input.toolResults.wardrobeItems.length, 3);
      return {kind: "final", statePatch: {}, result: {action: "chat", assistantText: "Rifle sú v poriadku.", display: {kind: "none", itemIds: []}}};
    },
  };
  const coordinator = createStylistTurnCoordinatorV2({
    sessionRepository: repository, wardrobeTool,
    locationResolver: {resolve: async () => null}, weatherTool: {getForecast: async () => null},
    shoppingTool: {search: async () => ({candidateIds: [], appliedHardConstraints: []})}, stylistModel,
    clock: () => Date.UTC(2026, 8, 8, 18),
  });
  const result = await coordinator.resolveTurn({
    chatId: "chat_edit", turnId: "turn_edit", expectedSessionRevision: 0,
    latestUserInput: "A rifle sú v poriadku?", explicitUiActionId: null,
    freshClientObservations: {}, clientCapabilities: {},
  });
  assert.equal(result.action, "chat");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].scope, "current_outfit");
  assert.equal(writes.length, 1);
});
