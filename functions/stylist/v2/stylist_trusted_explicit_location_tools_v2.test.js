"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {clone, createEmptySessionStateV2} = require("./stylist_session_state_v2");
const {
  executeRequestedToolsV2,
  restoreTrustedExplicitLocationV2,
} = require("./stylist_one_brain_engine_v2");

const lyon = Object.freeze({
  providerId: "openmeteo:lyon",
  label: "Lyon, Auvergne-Rhône-Alpes, Francúzsko",
  lat: 45.74846,
  lng: 4.84671,
  source: "open-meteo-geocoding",
  granularity: "locality",
  countryCode: "FR",
});

function weddingState() {
  const state = clone(createEmptySessionStateV2("trusted-lyon"));
  state.context.eventLocation = clone(lyon);
  state.context.date = {dateKey: "2026-09-16", source: "deterministic_user_text"};
  state.context.timeWindow = {key: "day", label: "cez deň", source: "one_brain_default"};
  state.conversationMemory.answeredClarificationFields.eventLocation = clone(lyon);
  return state;
}

function newScenarioEnvelope() {
  return {
    kind: "tool_request",
    pendingReplyDisposition: "none",
    statePatch: {
      scenarioMode: "new",
      context: {
        activity: {id: "wedding", label: "svadba", source: "user"},
        date: {dateKey: "2026-09-16", source: "deterministic_user_text"},
        timeWindow: {key: "day", label: "cez deň", source: "one_brain_default"},
      },
    },
    requests: [{tool: "wardrobe", scope: "full_relevant", category: null, editScope: null}],
  };
}

test("current-turn deterministic Lyon survives scenarioMode new and grounds weather", async () => {
  const weatherCalls = [];
  const executed = await executeRequestedToolsV2({
    envelope: newScenarioEnvelope(),
    state: weddingState(),
    wardrobeTool: {async retrieve() { throw new Error("preloaded wardrobe expected"); }},
    locationResolver: {async resolve() { throw new Error("location must not be re-geocoded"); }},
    weatherTool: {
      async getForecast({location, date, timeWindow}) {
        weatherCalls.push({location: clone(location), date: clone(date), timeWindow: clone(timeWindow)});
        return {
          locationProviderId: location.providerId,
          dateKey: date.dateKey,
          timeWindowKey: timeWindow.key,
          fetchedAt: "2026-09-15T18:00:00.000Z",
          source: "test-weather",
          snapshot: {representativeTempC: 18, minTempC: 13, maxTempC: 21},
        };
      },
    },
    knownWardrobeItems: [{id: "blazer"}],
    trustedExplicitLocation: {field: "eventLocation", location: clone(lyon)},
  });

  assert.equal(executed.workingState.context.eventLocation.providerId, lyon.providerId);
  assert.match(executed.workingState.context.eventLocation.label, /Lyon/);
  assert.equal(executed.workingState.context.groundingRequirements.weatherRequired, true);
  assert.equal(executed.workingState.context.groundingRequirements.weatherLocationField, "eventLocation");
  assert.equal(executed.toolResults.weatherStatus, "resolved");
  assert.equal(executed.workingState.context.weather.locationProviderId, lyon.providerId);
  assert.equal(weatherCalls.length, 1);
  assert.equal(weatherCalls[0].location.countryCode, "FR");
});

test("scenarioMode new still clears a stale location when there is no current-turn trusted marker", async () => {
  let weatherCalls = 0;
  const executed = await executeRequestedToolsV2({
    envelope: newScenarioEnvelope(),
    state: weddingState(),
    wardrobeTool: {async retrieve() { throw new Error("preloaded wardrobe expected"); }},
    locationResolver: {async resolve() { throw new Error("no location request expected"); }},
    weatherTool: {async getForecast() { weatherCalls += 1; throw new Error("weather must not run"); }},
    knownWardrobeItems: [{id: "blazer"}],
  });

  assert.equal(executed.workingState.context.eventLocation, null);
  assert.equal(executed.workingState.context.weather, null);
  assert.equal(executed.toolResults.weatherStatus, "not_requested");
  assert.equal(weatherCalls, 0);
});

test("trusted weather is restored only when it still matches the trusted location/date/window", () => {
  const state = clone(createEmptySessionStateV2("trusted-weather"));
  state.context.date = {dateKey: "2026-09-16", source: "deterministic_user_text"};
  state.context.timeWindow = {key: "day", label: "cez deň", source: "one_brain_default"};
  const weather = {
    locationProviderId: lyon.providerId,
    dateKey: "2026-09-16",
    timeWindowKey: "day",
    fetchedAt: "2026-09-15T18:00:00.000Z",
    source: "test-weather",
    snapshot: {representativeTempC: 18},
  };
  const restored = restoreTrustedExplicitLocationV2(state, {
    field: "eventLocation",
    location: clone(lyon),
    weather,
  });
  assert.equal(restored.context.weather.locationProviderId, lyon.providerId);
  assert.equal(restored.context.groundingRequirements.weatherLocationField, "eventLocation");
});
