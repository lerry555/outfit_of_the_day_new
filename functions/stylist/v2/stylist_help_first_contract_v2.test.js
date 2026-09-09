"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {clone, createEmptySessionStateV2, validateStylistSessionStateV2} = require("./stylist_session_state_v2");
const {createStylistTurnCoordinatorV2, deterministicRemoteOutfitClarificationV2} = require("./stylist_turn_coordinator_v2");
const {
  CallLedgerV2,
  FakeLocationResolverV2,
  FakeShoppingToolV2,
  FakeStylistModelPortV2,
  FakeWardrobeToolV2,
  FakeWeatherToolV2,
  InMemorySessionRepositoryV2,
} = require("./fake_ports_v2");
const {
  PLAN_MODEL,
  PLAN_REASONING,
  FINAL_MODEL,
  FINAL_REASONING,
  FINAL_REASONING_ESCALATED,
  finalReasoningForInputV2,
  shouldPreloadCurrentOutfitV2,
} = require("./openai_stylist_model_port_v2");
const {locationIsTooBroadForWeatherV2} = require("./open_meteo_ports_v2");

const NOW = Date.parse("2026-09-09T08:30:00.000Z");
const tatras = {providerId: "place:tatras", label: "Vysoké Tatry", lat: 49.1667, lng: 20.1333, source: "fake", granularity: "locality"};
const teryho = {providerId: "place:teryho", label: "Téryho chata, Vysoké Tatry", lat: 49.1902, lng: 20.1990, source: "fake", granularity: "poi"};
const usa = {providerId: "place:usa", label: "United States", lat: 39.8, lng: -98.6, source: "fake", granularity: "country"};
const newYork = {providerId: "place:new-york", label: "New York, United States", lat: 40.7128, lng: -74.0060, source: "fake", granularity: "locality"};
const wardrobe = [
  {id: "shirt", name: "Tričko", category: "tops", bodySlots: ["upper_body"]},
  {id: "jeans", name: "Rifle", category: "bottoms", bodySlots: ["lower_body"]},
  {id: "sneakers", name: "Bežecké tenisky", category: "footwear", bodySlots: ["feet"], safety: {hikingTechnical: false}},
];

function pendingDestinationState(chatId, {attempts = [], location = null} = {}) {
  const state = clone(createEmptySessionStateV2(chatId));
  state.context.activity = {id: "hiking", label: "túra", source: "user"};
  state.context.date = {dateKey: "2026-09-10", source: "user"};
  state.context.destination = location ? clone(location) : null;
  state.context.groundingRequirements = {
    weatherRequired: true,
    weatherLocationField: "destination",
    terrainRequiredFields: [],
  };
  state.conversationMemory.pendingQuestion = {
    type: "question",
    actionId: "clarify_destination",
    field: "destination",
    question: "Kam ideš?",
    acceptsYesNo: false,
    ...(attempts.length ? {attemptedAnswers: [...attempts]} : {}),
  };
  return validateStylistSessionStateV2(state);
}

function request(chatId, turnId, expectedSessionRevision, latestUserInput) {
  return {
    chatId,
    turnId,
    expectedSessionRevision,
    latestUserInput,
    explicitUiActionId: null,
    freshClientObservations: {},
    clientCapabilities: {
      todayDateKey: "2026-09-09",
      tomorrowDateKey: "2026-09-10",
      recentHistory: [],
    },
  };
}

function finalEnvelope(result, statePatch = {}) {
  return {kind: "final", result, statePatch};
}

function outfitResult(text = "Na zajtrajšiu túru by som zvolil tričko, rifle a tvoje bežecké tenisky.") {
  return {
    action: "generate_outfit",
    assistantText: text,
    resultingOutfit: {
      itemIds: ["shirt", "jeans", "sneakers"],
      selectionReasonsByItemId: {
        shirt: "ľahký vrch na dennú túru",
        jeans: "praktický spodný diel z dostupného šatníka",
        sneakers: "najpraktickejšia dostupná obuv bez známych technických podmienok",
      },
      compromises: ["Bežecké tenisky nie sú turistická obuv."],
      missingWardrobeNeeds: ["turistická obuv"],
    },
    display: {kind: "outfit", itemIds: ["shirt", "jeans", "sneakers"]},
    quickReplies: [
      {actionId: "shop_hiking_shoes_yes", label: "Áno"},
      {actionId: "shop_hiking_shoes_no", label: "Nie"},
    ],
  };
}

function harness({initialStates = [], resolutions = {}, modelResults = [], weatherSnapshots = {}} = {}) {
  const ledger = new CallLedgerV2();
  const sessionRepository = new InMemorySessionRepositoryV2(ledger, initialStates);
  const coordinator = createStylistTurnCoordinatorV2({
    sessionRepository,
    wardrobeTool: new FakeWardrobeToolV2(ledger, wardrobe),
    locationResolver: new FakeLocationResolverV2(ledger, resolutions),
    weatherTool: new FakeWeatherToolV2(ledger, weatherSnapshots),
    shoppingTool: new FakeShoppingToolV2(ledger),
    stylistModel: new FakeStylistModelPortV2(ledger, modelResults),
    clock: () => NOW,
  });
  return {ledger, sessionRepository, coordinator};
}

test("golden: friendly greeting is local and touches no expensive tools", async () => {
  const h = harness();
  const result = await h.coordinator.resolveTurn(request("greeting", "g-1", 0, "Ahoj divočák 👋"));
  assert.equal(result.action, "chat");
  assert.match(result.assistantText, /ahoj/i);
  assert.equal(h.ledger.calls("model").length, 0);
  assert.equal(h.ledger.calls("wardrobe").length, 0);
  assert.equal(h.ledger.calls("location").length, 0);
  assert.equal(h.ledger.calls("weather").length, 0);
});

test("golden: obvious tomorrow hiking request asks destination without a model call", async () => {
  const h = harness();
  const result = await h.coordinator.resolveTurn(
    request("fast-hike", "fh-1", 0, "zajtra idem na túru potrebujem outfit"),
  );
  assert.equal(result.action, "clarify");
  assert.equal(result.clarification.field, "destination");
  assert.equal(result.assistantText, "Kam približne ideš?");
  assert.equal(h.ledger.calls("model").length, 0);
  assert.equal(h.ledger.calls("location").length, 0);
  assert.equal(h.ledger.calls("weather").length, 0);
  assert.equal(h.ledger.calls("wardrobe").length, 0);

  const saved = await h.sessionRepository.read("fast-hike");
  assert.equal(saved.context.activity.id, "hiking");
  assert.equal(saved.context.date.dateKey, "2026-09-10");
  assert.equal(saved.context.timeWindow.key, "day");
  assert.equal(saved.context.groundingRequirements.weatherLocationField, "destination");
  assert.equal(saved.conversationMemory.pendingQuestion.field, "destination");
});

test("golden: fast clarification does not steal a request that already includes a destination", () => {
  const state = createEmptySessionStateV2("fast-with-place");
  const result = deterministicRemoteOutfitClarificationV2(
    request("fast-with-place", "fh-2", 0, "zajtra idem na túru do Tatier potrebujem outfit"),
    state,
  );
  assert.equal(result, null);
});

test("golden: meta reply to a pending location is explained, never geocoded", async () => {
  const state = pendingDestinationState("why-location");
  const h = harness({initialStates: [state]});
  const result = await h.coordinator.resolveTurn(request("why-location", "w-1", 0, "Načo ti to je?"));
  assert.equal(result.action, "clarify");
  assert.match(result.assistantText, /počas/i);
  assert.equal(result.clarification.field, "destination");
  assert.equal(h.ledger.calls("location").length, 0);
  assert.equal(h.ledger.calls("model").length, 0);
  const saved = await h.sessionRepository.read("why-location");
  assert.equal(saved.conversationMemory.pendingQuestion.field, "destination");
});

test("golden: country-level destination asks once for a useful narrower place", async () => {
  const state = pendingDestinationState("usa-trip");
  const h = harness({initialStates: [state], resolutions: {USA: usa}});
  const result = await h.coordinator.resolveTurn(request("usa-trip", "u-1", 0, "USA"));
  assert.equal(result.action, "clarify");
  assert.equal(result.clarification.field, "destination");
  assert.match(result.assistantText, /mesto|štát|stat|región|region/i);
  assert.equal(h.ledger.calls("location").length, 1);
  assert.equal(h.ledger.calls("weather").length, 0);
  assert.equal(h.ledger.calls("wardrobe").length, 0);
  assert.equal(h.ledger.calls("model").length, 0);
  const saved = await h.sessionRepository.read("usa-trip");
  assert.equal(saved.context.destination, null);
  assert.deepEqual(saved.conversationMemory.pendingQuestion.attemptedAnswers, ["USA"]);
});

test("golden: a useful destination defaults weather to the broad day and goes straight to one final stylist call", async () => {
  const state = pendingDestinationState("tatry-trip");
  const h = harness({
    initialStates: [state],
    resolutions: {Tatry: tatras},
    weatherSnapshots: {"place:tatras|2026-09-10|day": {summary: "mild"}},
    modelResults: [finalEnvelope(outfitResult())],
  });
  const result = await h.coordinator.resolveTurn(request("tatry-trip", "t-1", 0, "Tatry"));
  assert.equal(result.action, "generate_outfit");
  assert.doesNotMatch(result.assistantText, /ktorej časti dňa|ktorej casti dna/i);
  const saved = await h.sessionRepository.read("tatry-trip");
  assert.equal(saved.context.destination.providerId, "place:tatras");
  assert.equal(saved.context.timeWindow.key, "day");
  assert.equal(h.ledger.calls("weather", "getForecast").length, 1);
  assert.equal(h.ledger.calls("wardrobe", "retrieve").length, 1);
  assert.equal(h.ledger.calls("model", "plan").length, 0);
  assert.equal(h.ledger.calls("model", "final").length, 1);
});

test("golden: Tatry followed by Teryho chata refines context and never falls back to the generic loop", async () => {
  const state = pendingDestinationState("teryho-trip", {attempts: ["do Tatier"]});
  const h = harness({
    initialStates: [state],
    resolutions: {"Téryho chata, Tatier": teryho},
    weatherSnapshots: {"place:teryho|2026-09-10|day": {summary: "mountain"}},
    modelResults: [finalEnvelope(outfitResult())],
  });
  const result = await h.coordinator.resolveTurn(request("teryho-trip", "th-1", 0, "Téryho chata"));
  assert.equal(result.action, "generate_outfit");
  assert.notEqual(result.assistantText, "Kam presne ideš?");
  const saved = await h.sessionRepository.read("teryho-trip");
  assert.equal(saved.context.destination.providerId, "place:teryho");
  assert.equal(saved.context.timeWindow.key, "day");
  assert.equal(h.ledger.calls("model", "plan").length, 0);
  assert.equal(h.ledger.calls("model", "final").length, 1);
});

test("golden: user can skip unknown remote weather context and still get a useful wardrobe recommendation", async () => {
  const state = pendingDestinationState("skip-place");
  const h = harness({
    initialStates: [state],
    modelResults: [
      finalEnvelope(outfitResult("Nevieme presné podmienky, takže volím bezpečný všeobecný základ z tvojho šatníka.")),
    ],
  });
  const result = await h.coordinator.resolveTurn(request("skip-place", "s-1", 0, "Neviem, daj mi proste outfit"));
  assert.equal(result.action, "generate_outfit");
  assert.equal(h.ledger.calls("location").length, 0);
  assert.equal(h.ledger.calls("weather").length, 0);
  assert.equal(h.ledger.calls("wardrobe", "retrieve").length, 1);
  assert.equal(h.ledger.calls("model", "plan").length, 0);
  assert.equal(h.ledger.calls("model", "final").length, 1);
  const saved = await h.sessionRepository.read("skip-place");
  assert.equal(saved.context.groundingRequirements.weatherRequired, false);
  assert.equal(saved.conversationMemory.pendingQuestion, null);
});

test("golden: only country granularity is too broad for ordinary weather grounding", () => {
  assert.equal(locationIsTooBroadForWeatherV2(usa), true);
  assert.equal(locationIsTooBroadForWeatherV2(newYork), false);
  assert.equal(locationIsTooBroadForWeatherV2(tatras), false);
  assert.equal(locationIsTooBroadForWeatherV2(teryho), false);
});

test("golden: model routing uses cheap planner and low-reasoning Terra for ordinary final styling", () => {
  assert.equal(PLAN_MODEL, "gpt-5.6-luna");
  assert.equal(PLAN_REASONING, "low");
  assert.equal(FINAL_MODEL, "gpt-5.6-terra");
  assert.equal(FINAL_REASONING, "low");
  assert.equal(FINAL_REASONING_ESCALATED, "medium");
});

test("golden: safety-sensitive terrain escalates final reasoning to medium", () => {
  const session = clone(createEmptySessionStateV2("reasoning"));
  session.context.terrain = {surface: "rock", difficulty: "technical", condition: "wet"};
  const input = {request: {latestUserInput: "vyber mi outfit"}, session};
  assert.equal(finalReasoningForInputV2(input), "medium");

  session.context.terrain = {surface: null, difficulty: null, condition: null};
  assert.equal(finalReasoningForInputV2(input), "low");
});

test("golden: current outfit is preloaded only for turns that actually discuss or edit it", () => {
  const session = clone(createEmptySessionStateV2("preload"));
  session.currentOutfit.itemIds = ["shirt", "jeans", "sneakers"];
  assert.equal(shouldPreloadCurrentOutfitV2({request: {latestUserInput: "Ahoj, ako sa máš?"}, session}), false);
  assert.equal(shouldPreloadCurrentOutfitV2({request: {latestUserInput: "A rifle sú v poriadku?"}, session}), true);
  assert.equal(shouldPreloadCurrentOutfitV2({request: {latestUserInput: "Vymeň mi topánky."}, session}), true);
});
