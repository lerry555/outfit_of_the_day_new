"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  createDeterministicShellBrainV2,
  specificWeatherLocationFieldV2,
} = require("./stylist_production_bridge_one_brain_v2");

function sessionWithLocation(location, overrides = {}) {
  return {
    context: {
      destination: null,
      eventLocation: location,
      date: {dateKey: "2026-09-16", source: "deterministic_user_text"},
      timeWindow: {key: "day", label: "cez deň", source: "one_brain_default"},
      weather: null,
      groundingRequirements: {
        weatherRequired: false,
        weatherLocationField: null,
        terrainRequiredFields: [],
      },
      ...overrides,
    },
    conversationMemory: {pendingQuestion: null},
  };
}

test("specific explicit event location requires a weather tool pass before generate_outfit final", async () => {
  const session = sessionWithLocation({
    providerId: "openmeteo:lyon",
    label: "Lyon, Auvergne-Rhône-Alpes, Francúzsko",
    lat: 45.74846,
    lng: 4.84671,
    source: "open-meteo-geocoding",
    granularity: "locality",
    countryCode: "FR",
  });
  assert.equal(specificWeatherLocationFieldV2(session), "eventLocation");

  const rawBrain = {
    async brainTurn() {
      return {
        kind: "final",
        pendingReplyDisposition: "none",
        statePatch: {
          context: {
            activity: {id: "wedding", label: "svadba", source: "user"},
            environment: "indoor",
          },
        },
        result: {
          action: "generate_outfit",
          assistantText: "Na svadbu zvoľ sako, košeľu, chinos nohavice a spoločenské topánky.",
          resultingOutfit: {
            itemIds: ["blazer", "shirt", "chinos", "dress_shoes"],
            selectionReasonsByItemId: {},
            compromises: [],
            missingWardrobeNeeds: [],
          },
          display: {kind: "outfit", itemIds: ["blazer", "shirt", "chinos", "dress_shoes"]},
        },
      };
    },
  };

  const wrapped = createDeterministicShellBrainV2(rawBrain);
  const result = await wrapped.brainTurn({
    stage: "tools",
    session,
    request: {latestUserInput: "zajtra idem v Lyone vo Francúzsku na svadbu a potrebujem outfit"},
  });

  assert.equal(result.kind, "tool_request");
  assert.equal(result.pendingReplyDisposition, "none");
  assert.deepEqual(result.requests, [
    {tool: "wardrobe", scope: "full_relevant", category: null, editScope: null},
  ]);
  assert.equal(result.statePatch.context.activity.id, "wedding");
});

test("broad country and already-grounded weather do not force the final through tools", () => {
  const france = sessionWithLocation({
    providerId: "country:FR",
    label: "Francúzsko",
    lat: 46.2,
    lng: 2.2,
    source: "local-country",
    granularity: "country",
    countryCode: "FR",
  });
  assert.equal(specificWeatherLocationFieldV2(france), null);

  const lyonWithWeather = sessionWithLocation({
    providerId: "openmeteo:lyon",
    label: "Lyon, Francúzsko",
    lat: 45.74846,
    lng: 4.84671,
    granularity: "locality",
    countryCode: "FR",
  }, {
    weather: {
      locationProviderId: "openmeteo:lyon",
      dateKey: "2026-09-16",
      timeWindowKey: "day",
      source: "fake-weather",
      snapshot: {representativeTempC: 21},
    },
  });
  assert.equal(specificWeatherLocationFieldV2(lyonWithWeather), null);
});

test("ordinary chat final is not promoted to a tool request", async () => {
  const session = sessionWithLocation({
    providerId: "openmeteo:lyon",
    label: "Lyon, Francúzsko",
    lat: 45.74846,
    lng: 4.84671,
    granularity: "locality",
    countryCode: "FR",
  });
  const final = {
    kind: "final",
    pendingReplyDisposition: "none",
    statePatch: {},
    result: {
      action: "chat",
      assistantText: "Áno, na svadbu je to vhodné.",
      display: {kind: "none", itemIds: []},
    },
  };
  const wrapped = createDeterministicShellBrainV2({async brainTurn() { return final; }});
  assert.deepEqual(await wrapped.brainTurn({stage: "tools", session, request: {latestUserInput: "je to vhodné?"}}), final);
});