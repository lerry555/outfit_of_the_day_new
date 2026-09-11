"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createStylistOneBrainEngineV2,
  explicitStylingDestinationCandidateV2,
} = require("./stylist_one_brain_engine_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");
const {oneBrainPromptV2} = require("./openai_one_brain_model_port_v2");

const NOW = Date.parse("2026-09-11T12:00:00.000Z");

function request(message, {turnId = "t1", revision = 0} = {}) {
  return {
    chatId: "chat_general_location",
    turnId,
    expectedSessionRevision: revision,
    latestUserInput: message,
    explicitUiActionId: null,
    freshClientObservations: {},
    clientCapabilities: {
      shoppingEnabled: false,
      supportsProgress: true,
      todayDateKey: "2026-09-11",
      tomorrowDateKey: "2026-09-12",
      timezoneOffsetMinutes: 120,
      recentHistory: [],
    },
  };
}

function enginePorts({resolvedLocation, calls}) {
  return {
    wardrobeTool: {
      async retrieve() {
        calls.wardrobe += 1;
        return [];
      },
    },
    locationResolver: {
      async resolve(query) {
        calls.location += 1;
        calls.query = query;
        return resolvedLocation;
      },
    },
    weatherTool: {
      async getForecast() {
        calls.weather += 1;
        throw new Error("weather must not run before broad-location clarification");
      },
    },
    shoppingTool: {
      async search() {
        calls.shopping += 1;
        return {candidateIds: [], appliedHardConstraints: [], reply: ""};
      },
    },
    stylistBrain: {
      async brainTurn() {
        calls.brain += 1;
        return {
          kind: "final",
          pendingReplyDisposition: "none",
          statePatch: {
            scenarioMode: "current",
            context: {
              activity: {key: "hiking", label: "turistika", source: "user"},
              date: {dateKey: "2026-09-17", label: "budúci štvrtok", source: "user"},
              timeWindow: {key: "day", label: "cez deň", source: "one_brain_default"},
              environment: "outdoor",
              groundingRequirements: {
                weatherRequired: true,
                weatherLocationField: "destination",
                terrainRequiredFields: [],
              },
            },
          },
          result: {action: "chat", assistantText: "placeholder", display: {kind: "none", itemIds: []}},
        };
      },
    },
  };
}

test("general destination extractor finds Poland without country hard-coding", () => {
  assert.deepEqual(
    explicitStylingDestinationCandidateV2("buduci stvrtok ideme do polska na turu a ja neviem co na seba"),
    {query: "polska", targetField: "destination"},
  );
});

test("general destination extractor is not Austria-specific", () => {
  assert.deepEqual(
    explicitStylingDestinationCandidateV2("v sobotu ideme do Francuzska na vylet a potrebujem outfit"),
    {query: "Francuzska", targetField: "destination"},
  );
  assert.deepEqual(
    explicitStylingDestinationCandidateV2("zajtra ideme do USA na turu, co si mam obliect"),
    {query: "USA", targetField: "destination"},
  );
});

test("event trip targets eventLocation while hiking targets destination", () => {
  assert.deepEqual(
    explicitStylingDestinationCandidateV2("ideme do Berlina na koncert a neviem co na seba"),
    {query: "Berlina", targetField: "eventLocation"},
  );
});

test("country-level explicit destination preserves scenario context before clarification", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brain: 0, location: 0, wardrobe: 0, weather: 0, shopping: 0, query: null};
  const engine = createStylistOneBrainEngineV2({
    sessionRepository: repository,
    ...enginePorts({
      calls,
      resolvedLocation: {
        providerId: "geo:any-country",
        label: "Poľsko",
        lat: 52.0,
        lng: 19.0,
        source: "fake-geocoder",
        granularity: "country",
        countryCode: "PL",
      },
    }),
    clock: () => NOW,
  });

  const result = await engine.resolveTurn({
    uid: "u_general_country",
    request: request("buduci stvrtok ideme do polska na turu a ja neviem co na seba"),
    bootstrapInput: {
      currentOutfitItemIds: [],
      persistedSelectionReasonsByItemId: {},
      knownExplicitDurableChoices: {},
    },
  });

  assert.equal(result.action, "clarify");
  assert.equal(result.clarification.field, "destination");
  assert.match(result.assistantText, /dosť široké/);
  assert.match(result.assistantText, /Kam približne/);
  assert.equal(calls.query, "polska");
  assert.equal(calls.location, 1);
  assert.equal(calls.brain, 1, "Brain parses the original scenario before runtime commits the location clarification");
  assert.equal(calls.wardrobe, 0, "do not read the wardrobe before the one useful location answer");
  assert.equal(calls.weather, 0);
  const saved = await repository.get({uid: "u_general_country", chatId: "chat_general_location"});
  assert.equal(saved.state.context.activity.key, "hiking");
  assert.equal(saved.state.context.date.dateKey, "2026-09-17");
  assert.equal(saved.state.context.environment, "outdoor");
});

test("pending location answer cannot dead-end as bare acknowledgement", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brain: 0, location: 0, wardrobe: 0, weather: 0, shopping: 0, queries: []};
  const engine = createStylistOneBrainEngineV2({
    sessionRepository: repository,
    wardrobeTool: {
      async retrieve() {
        calls.wardrobe += 1;
        return [];
      },
    },
    locationResolver: {
      async resolve(query) {
        calls.location += 1;
        calls.queries.push(query);
        if (calls.location === 1) {
          return {providerId: "geo:ch", label: "Švajčiarsko", lat: 46.8, lng: 8.2,
            source: "fake-geocoder", granularity: "country", countryCode: "CH"};
        }
        return {providerId: "geo:alps", label: "Alpy", lat: 46.5, lng: 10.0,
          source: "fake-geocoder", granularity: "region", countryCode: "CH"};
      },
    },
    weatherTool: {
      async getForecast() {
        calls.weather += 1;
        return {locationProviderId: "geo:alps", dateKey: "2026-09-16", timeWindowKey: "day",
          fetchedAt: "2026-09-11T12:00:00.000Z", source: "fake-weather", snapshot: {}};
      },
    },
    shoppingTool: {async search() { calls.shopping += 1; return {candidateIds: [], reply: ""}; }},
    stylistBrain: {
      async brainTurn(input) {
        calls.brain += 1;
        if (calls.brain === 1) {
          return {
            kind: "final",
            pendingReplyDisposition: "none",
            statePatch: {
              scenarioMode: "current",
              context: {
                activity: {key: "hiking", label: "turistika", source: "user"},
                date: {dateKey: "2026-09-16", label: "o týždeň v stredu", source: "user"},
                timeWindow: {key: "day", label: "cez deň", source: "one_brain_default"},
                environment: "outdoor",
                groundingRequirements: {weatherRequired: true, weatherLocationField: "destination", terrainRequiredFields: []},
              },
            },
            result: {action: "chat", assistantText: "placeholder", display: {kind: "none", itemIds: []}},
          };
        }
        if (input.stage === "tools") {
          return {
            kind: "final",
            pendingReplyDisposition: "answer",
            statePatch: {scenarioMode: "current", context: {}},
            result: {action: "chat", assistantText: "Rozumiem.", display: {kind: "none", itemIds: []}},
          };
        }
        return {
          kind: "final",
          statePatch: {scenarioMode: "current", context: {}},
          result: {action: "chat", assistantText: "Pokračujem po location a wardrobe tooloch.", display: {kind: "none", itemIds: []}},
        };
      },
    },
    clock: () => NOW,
  });

  const first = await engine.resolveTurn({
    uid: "u_pending_location",
    request: request("o tyzden v stredu ideme do svajciarska na turu a ja neviem co si obliect"),
    bootstrapInput: {currentOutfitItemIds: [], persistedSelectionReasonsByItemId: {}, knownExplicitDurableChoices: {}},
  });
  assert.equal(first.action, "clarify");

  const second = await engine.resolveTurn({
    uid: "u_pending_location",
    request: request("do alp :D", {turnId: "t2", revision: 1}),
  });
  assert.equal(second.action, "chat");
  assert.equal(second.assistantText, "Pokračujem po location a wardrobe tooloch.");
  assert.notEqual(second.assistantText, "Rozumiem.");
  assert.equal(calls.brain, 3);
  assert.equal(calls.location, 2);
  assert.equal(calls.queries[1], "do alp");
  assert.equal(calls.wardrobe, 1);
});

test("layering contract rejects warmth-by-stacking logic for thin sports outerwear", () => {
  const prompt = oneBrainPromptV2("answer");
  assert.match(prompt, /Vrstvenie horných dielov musí mať funkčný zmysel/);
  assert.match(prompt, /ľahší outer s nižším warmth/);
  assert.match(prompt, /športová\/tréningová\/track bunda/);
  assert.match(prompt, /NIE JE ďalšia teplá vrstva/);
  assert.match(prompt, /Nikdy netvrď, že tenšia bunda pridáva teplo/);
});
