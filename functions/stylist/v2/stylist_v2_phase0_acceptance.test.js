"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  bootstrapExistingChatV2,
  clone,
  createEmptySessionStateV2,
  validateStylistSessionStateV2,
} = require("./stylist_session_state_v2");
const {StaleSessionRevisionError} = require("./stylist_preflight_v2");
const {createStylistTurnCoordinatorV2} = require("./stylist_turn_coordinator_v2");
const {
  CallLedgerV2,
  FakeLocationResolverV2,
  FakeShoppingToolV2,
  FakeStylistModelPortV2,
  FakeWardrobeToolV2,
  FakeWeatherToolV2,
  InMemorySessionRepositoryV2,
} = require("./fake_ports_v2");

const NOW = Date.parse("2026-09-08T08:05:00.000Z");
const martin = {
  providerId: "place:martin",
  label: "Martin",
  lat: 49.0636,
  lng: 18.9217,
  observedAt: "2026-09-08T08:00:00.000Z",
  source: "gps",
};
const tatras = {providerId: "place:tatras", label: "Vysoké Tatry", lat: 49.1667, lng: 20.1333};
const wardrobe = [
  {id: "shirt", category: "tops"},
  {id: "jeans", category: "bottoms"},
  {id: "shorts", category: "bottoms"},
  {id: "shoes", category: "footwear"},
  {id: "hiking-boots", category: "footwear"},
];

function request(chatId, turnId, expectedSessionRevision, latestUserInput, extra = {}) {
  return {
    chatId,
    turnId,
    expectedSessionRevision,
    latestUserInput,
    clientCapabilities: {typedQuickReplies: true, explicitDisplay: true},
    ...extra,
  };
}

function harness({initialStates = [], modelResults = [], shoppingResult, weatherSnapshots} = {}) {
  const ledger = new CallLedgerV2();
  const sessionRepository = new InMemorySessionRepositoryV2(ledger, initialStates);
  const ports = {
    sessionRepository,
    wardrobeTool: new FakeWardrobeToolV2(ledger, wardrobe),
    locationResolver: new FakeLocationResolverV2(ledger, {"Vysoké Tatry.": tatras}),
    weatherTool: new FakeWeatherToolV2(ledger, weatherSnapshots),
    shoppingTool: new FakeShoppingToolV2(ledger, shoppingResult),
    stylistModel: new FakeStylistModelPortV2(ledger, modelResults),
    clock: () => NOW,
  };
  return {ledger, ports, sessionRepository, coordinator: createStylistTurnCoordinatorV2(ports)};
}

test("Scenario A resolves destination separately from GPS and uses only destination weather", async () => {
  const firstDecision = {
    action: "clarify",
    assistantText: "Kam presne ideš na túru?",
    clarification: {field: "destination", question: "Kam presne ideš na túru?", actionId: "clarify_destination"},
    display: {kind: "none", itemIds: []},
    statePatch: {
      context: {
        activity: {id: "hiking"},
        date: {dateKey: "2026-09-09", source: "user"},
        timeWindow: {key: "daytime", label: "cez deň"},
      },
    },
  };
  const generationDecision = {
    action: "generate_outfit",
    assistantText: "Na ľahkú suchú trasu volím tričko, kraťasy a turistické topánky.",
    resultingOutfit: {
      itemIds: ["shirt", "shorts", "hiking-boots"],
      selectionReasonsByItemId: {
        shirt: "priedušná vrstva na dennú túru",
        shorts: "ľahký spodný diel na teplú suchú trasu",
        "hiking-boots": "stabilná obuv pre turistickú trasu",
      },
    },
    display: {kind: "outfit", itemIds: ["shirt", "shorts", "hiking-boots"]},
    retrievalScope: "full_relevant",
    statePatch: {context: {terrain: {surface: "trail", difficulty: "easy", condition: "dry"}}},
  };
  const h = harness({modelResults: [firstDecision, generationDecision]});

  const first = await h.coordinator.resolveTurn(request("chat-a", "a-1", 0,
    "Zajtra idem na túru, potrebujem outfit.", {
      freshClientObservations: {currentLocationObservation: martin},
    }));
  assert.equal(first.action, "clarify");
  assert.equal(first.clarification.field, "destination");
  assert.equal((first.assistantText.match(/\?/g) || []).length, 1);
  assert.deepEqual(first.display, {kind: "none", itemIds: []});
  let saved = await h.sessionRepository.read("chat-a");
  assert.equal(saved.context.destination, null);
  assert.equal(saved.context.currentLocationObservation.providerId, "place:martin");
  assert.equal(h.ledger.calls("weather", "getForecast").length, 0);

  // A new coordinator simulates reopening/reloading the chat between turns.
  const reopened = createStylistTurnCoordinatorV2(h.ports);
  const second = await reopened.resolveTurn(request("chat-a", "a-2", 1, "Vysoké Tatry."));
  assert.equal(second.action, "clarify");
  assert.equal(second.clarification.field, "terrain");
  assert.equal((second.assistantText.match(/\?/g) || []).length, 1);
  saved = await h.sessionRepository.read("chat-a");
  assert.equal(saved.context.destination.providerId, "place:tatras");
  assert.equal(saved.context.currentLocationObservation.providerId, "place:martin");
  const weatherCalls = h.ledger.calls("weather", "getForecast");
  assert.equal(weatherCalls.length, 1);
  assert.equal(weatherCalls[0].args.location.providerId, "place:tatras");
  assert.notEqual(weatherCalls[0].args.location.providerId, "place:martin");

  const third = await reopened.resolveTurn(request("chat-a", "a-3", 2, "Ľahký suchý chodník."));
  assert.equal(third.action, "generate_outfit");
  assert.deepEqual(third.display.itemIds, third.resultingOutfit.itemIds);
  assert.equal(h.ledger.calls("model", "turn").length, 2);
  assert.equal(h.ledger.calls("wardrobe", "retrieve")[0].args.scope, "full_relevant");

  const countsBeforeReplay = {
    model: h.ledger.calls("model").length,
    weather: h.ledger.calls("weather").length,
    wardrobe: h.ledger.calls("wardrobe").length,
    writes: h.ledger.calls("session", "write").length,
  };
  const replay = await reopened.resolveTurn(request("chat-a", "a-3", 2, "ignored on stable replay"));
  assert.deepEqual(replay, third);
  assert.deepEqual({
    model: h.ledger.calls("model").length,
    weather: h.ledger.calls("weather").length,
    wardrobe: h.ledger.calls("wardrobe").length,
    writes: h.ledger.calls("session", "write").length,
  }, countsBeforeReplay);

  await assert.rejects(
    reopened.resolveTurn(request("chat-a", "a-stale", 1, "nová správa")),
    StaleSessionRevisionError,
  );
});

test("Scenario B changes only the requested lower-body item and retains historical reasons", async () => {
  const existing = bootstrapExistingChatV2({
    chatId: "chat-b",
    currentOutfitItemIds: ["shirt", "jeans", "shoes"],
    persistedSelectionReasonsByItemId: {
      shirt: "funguje farebne s outfitom",
      jeans: "krytie nôh do chladnejšieho rána",
      shoes: "pohodlné na mestskú chôdzu",
    },
  });
  const h = harness({
    initialStates: [existing],
    modelResults: [{
      action: "edit_outfit",
      assistantText: "Kraťasy outfit odľahčia; tričko aj topánky nechávam bez zmeny.",
      resultingOutfit: {
        itemIds: ["shirt", "shorts", "shoes"],
        selectionReasonsByItemId: {
          shirt: "funguje farebne s outfitom",
          shorts: "ľahší spodný diel podľa požadovanej zmeny",
          shoes: "pohodlné na mestskú chôdzu",
        },
      },
      editScope: {replaceItemIds: ["jeans"], slots: ["lower_body"]},
      display: {kind: "items", itemIds: ["shorts"]},
      retrievalScope: "category",
      retrievalCategory: "bottoms",
    }],
  });
  const result = await h.coordinator.resolveTurn(request("chat-b", "b-1", 0,
    "Rifle by som vymenil za kraťasy."));
  assert.deepEqual(result.resultingOutfit.itemIds, ["shirt", "shorts", "shoes"]);
  assert.equal(result.resultingOutfit.selectionReasonsByItemId.shirt, "funguje farebne s outfitom");
  assert.equal(result.resultingOutfit.selectionReasonsByItemId.shoes, "pohodlné na mestskú chôdzu");
  const saved = await h.sessionRepository.read("chat-b");
  assert.deepEqual(saved.currentOutfit.selectionReasonHistory, [{
    itemId: "jeans",
    reason: "krytie nôh do chladnejšieho rána",
    outfitRevision: 1,
  }]);
  assert.equal(saved.currentOutfit.selectionReasonsByItemId.shorts,
    "ľahší spodný diel podľa požadovanej zmeny");
  assert.deepEqual(h.ledger.calls("wardrobe", "retrieve")[0].args, {
    scope: "category", itemIds: ["shirt", "jeans", "shoes"], category: "bottoms",
  });
});

test("Scenario C resolves typed Yes against the persisted Shopping action and full inherited context", async () => {
  const state = clone(createEmptySessionStateV2("chat-c"));
  state.context.activity = {id: "hiking"};
  state.context.destination = tatras;
  state.context.date = {dateKey: "2026-09-09", source: "user"};
  state.context.timeWindow = {key: "daytime", label: "cez deň"};
  state.context.terrain = {surface: "trail", difficulty: "steep", condition: "wet"};
  state.context.weather = {
    locationProviderId: "place:tatras", dateKey: "2026-09-09", timeWindowKey: "daytime",
    fetchedAt: "2026-09-08T08:00:00.000Z", source: "fake-weather-v2", snapshot: {rain: true},
  };
  state.currentOutfit.missingWardrobeNeeds = ["hiking_footwear"];
  state.shopping.missingNeed = "hiking_footwear";
  state.shopping.hardConstraints = ["wet_technical_grip"];
  state.shopping.softPreferences = ["dark_color"];
  state.shopping.openedReason = "wardrobe lacks safe hiking footwear";
  state.conversationMemory.pendingAction = {
    type: "action", kind: "shopping", actionId: "abc123", need: "hiking_footwear",
  };
  const h = harness({initialStates: [validateStylistSessionStateV2(state)], shoppingResult: {candidateIds: ["product-1"]}});
  const result = await h.coordinator.resolveTurn(request("chat-c", "c-1", 0, "Áno."));
  assert.equal(result.action, "shop");
  assert.deepEqual(result.display, {kind: "shopping", itemIds: ["product-1"]});
  assert.equal(h.ledger.calls("model").length, 0);
  const call = h.ledger.calls("shopping", "search")[0].args;
  assert.equal(call.actionId, "abc123");
  assert.equal(call.destination.providerId, "place:tatras");
  assert.equal(call.weather.locationProviderId, "place:tatras");
  assert.deepEqual(call.terrain, {surface: "trail", difficulty: "steep", condition: "wet"});
  assert.equal(call.missingNeed, "hiking_footwear");
});

test("Scenario D is explanation-only with no cards, mutation, or repeated footwear warning", async () => {
  const state = bootstrapExistingChatV2({
    chatId: "chat-d",
    currentOutfitItemIds: ["shirt", "jeans", "shoes"],
    persistedSelectionReasonsByItemId: {shirt: "farba", jeans: "krytie", shoes: "pohodlie"},
  });
  const mutable = clone(state);
  mutable.conversationMemory.communicatedWarnings = ["footwear_not_hiking_grade"];
  const h = harness({
    initialStates: [validateStylistSessionStateV2(mutable)],
    modelResults: [{
      action: "explain_outfit",
      assistantText: "Áno, rifle sú v poriadku — dávajú ti krytie nôh a stále ladia s tričkom.",
      display: {kind: "none", itemIds: []},
    }],
  });
  const result = await h.coordinator.resolveTurn(request("chat-d", "d-1", 0, "A rifle sú v poriadku?"));
  assert.equal(result.action, "explain_outfit");
  assert.deepEqual(result.resultingOutfit.itemIds, ["shirt", "jeans", "shoes"]);
  assert.deepEqual(result.display, {kind: "none", itemIds: []});
  assert.doesNotMatch(result.assistantText, /obuv|topán/i);
});

test("Scenario E greeting uses neither wardrobe nor model", async () => {
  const h = harness();
  const result = await h.coordinator.resolveTurn(request("chat-e", "e-1", 0, "Ahoj."));
  assert.equal(result.action, "chat");
  assert.deepEqual(result.resultingOutfit.itemIds, []);
  assert.deepEqual(result.display, {kind: "none", itemIds: []});
  assert.equal(h.ledger.calls("model").length, 0);
  assert.equal(h.ledger.calls("wardrobe").length, 0);
});

test("Scenario F conversation-only turn permits an empty outfit", async () => {
  const h = harness({modelResults: [{
    action: "chat",
    assistantText: "K modrej sa pekne hodí biela, sivá aj tlmená béžová.",
    display: {kind: "none", itemIds: []},
  }]});
  const result = await h.coordinator.resolveTurn(request("chat-f", "f-1", 0,
    "Aké farby sa hodia k modrej?"));
  assert.equal(result.action, "chat");
  assert.deepEqual(result.resultingOutfit.itemIds, []);
  assert.equal(h.ledger.calls("model").length, 1);
  assert.equal(h.ledger.calls("wardrobe").length, 0);
});
