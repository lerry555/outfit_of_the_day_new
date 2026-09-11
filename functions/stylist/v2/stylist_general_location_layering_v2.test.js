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

function request(message) {
  return {
    chatId: "chat_general_location",
    turnId: "t1",
    expectedSessionRevision: 0,
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
        throw new Error("Brain must not run before broad-country clarification");
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

test("country-level explicit destination clarifies before any Brain or wardrobe call", async () => {
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
  assert.equal(calls.brain, 0, "broad explicit country must not depend on a model choosing the location tool");
  assert.equal(calls.wardrobe, 0, "do not read the wardrobe before the one useful location answer");
  assert.equal(calls.weather, 0);
});

test("layering contract rejects warmth-by-stacking logic for thin sports outerwear", () => {
  const prompt = oneBrainPromptV2("answer");
  assert.match(prompt, /Vrstvenie horných dielov musí mať funkčný zmysel/);
  assert.match(prompt, /ľahší outer s nižším warmth/);
  assert.match(prompt, /športová\/tréningová\/track bunda/);
  assert.match(prompt, /NIE JE ďalšia teplá vrstva/);
  assert.match(prompt, /Nikdy netvrď, že tenšia bunda pridáva teplo/);
});
