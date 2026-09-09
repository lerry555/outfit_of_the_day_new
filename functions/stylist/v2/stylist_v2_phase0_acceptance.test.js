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
const {SafetyCriticalTurnError} = require("./stylist_turn_validator_v2");
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
  providerId: "place:martin", label: "Martin", lat: 49.0636, lng: 18.9217,
  observedAt: "2026-09-08T08:00:00.000Z", source: "gps",
};
const tatras = {providerId: "place:tatras", label: "Vysoké Tatry", lat: 49.1667, lng: 20.1333};
const bratislava = {providerId: "place:bratislava", label: "Bratislava", lat: 48.1486, lng: 17.1077};
const zilina = {providerId: "place:zilina", label: "Žilina", lat: 49.2231, lng: 18.7394};
const wardrobe = [
  {id: "shirt", category: "tops", bodySlots: ["upper_body"]},
  {id: "jeans", category: "bottoms", bodySlots: ["lower_body"]},
  {id: "shorts", category: "bottoms", bodySlots: ["lower_body"]},
  {id: "shoes", category: "footwear", bodySlots: ["feet"]},
  {id: "hiking-boots", category: "footwear", bodySlots: ["feet"], safety: {hikingTechnical: true}},
  {id: "hoodie", category: "layers", bodySlots: ["upper_body"]},
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

function finalEnvelope(result, statePatch) {
  return {kind: "final", result, ...(statePatch ? {statePatch} : {})};
}

function toolEnvelope(requests, statePatch) {
  return {kind: "tool_request", requests, ...(statePatch ? {statePatch} : {})};
}

function harness({initialStates = [], modelResults = [], shoppingResult, weatherSnapshots} = {}) {
  const ledger = new CallLedgerV2();
  const sessionRepository = new InMemorySessionRepositoryV2(ledger, initialStates);
  const ports = {
    sessionRepository,
    wardrobeTool: new FakeWardrobeToolV2(ledger, wardrobe),
    locationResolver: new FakeLocationResolverV2(ledger, {
      "Vysoké Tatry.": tatras,
      "Vysoké Tatry": tatras,
      Bratislava: bratislava,
      "Bratislava.": bratislava,
      Žilina: zilina,
      "Žilina.": zilina,
    }),
    weatherTool: new FakeWeatherToolV2(ledger, weatherSnapshots),
    shoppingTool: new FakeShoppingToolV2(ledger, shoppingResult),
    stylistModel: new FakeStylistModelPortV2(ledger, modelResults),
    clock: () => NOW,
  };
  return {ledger, ports, sessionRepository, coordinator: createStylistTurnCoordinatorV2(ports)};
}

function fullOutfitResult(text = "Toto je výsledný outfit.") {
  return {
    action: "generate_outfit",
    assistantText: text,
    resultingOutfit: {
      itemIds: ["shirt", "jeans", "shoes"],
      selectionReasonsByItemId: {
        shirt: "vhodný vrch pre udalosť",
        jeans: "primerané krytie nôh",
        shoes: "pohodlná obuv",
      },
    },
    display: {kind: "outfit", itemIds: ["shirt", "jeans", "shoes"]},
  };
}

function modelCallIndex(ledger, method) {
  return ledger.entries.findIndex((entry) => entry.port === "model" && entry.method === method);
}

test("Scenario A keeps GPS separate, asks only material hiking facts, and retrieves before final selection", async () => {
  const firstPlanningFinal = finalEnvelope({
    action: "clarify",
    assistantText: "Kam presne ideš?",
    clarification: {field: "destination", question: "Kam presne ideš?", actionId: "clarify_destination"},
    display: {kind: "none", itemIds: []},
  }, {
    context: {
      activity: {id: "hiking"},
      date: {dateKey: "2026-09-09", source: "user"},
      timeWindow: {key: "daytime", label: "cez deň"},
      groundingRequirements: {
        weatherRequired: true,
        weatherLocationField: "destination",
        terrainRequiredFields: ["difficulty"],
      },
    },
  });
  const generationResult = {
    action: "generate_outfit",
    assistantText: "Na ľahkú trasu volím tričko, rifle a turistické topánky.",
    resultingOutfit: {
      itemIds: ["shirt", "jeans", "hiking-boots"],
      selectionReasonsByItemId: {
        shirt: "priedušná vrstva na dennú túru",
        jeans: "krytie nôh na trase",
        "hiking-boots": "stabilná turistická obuv",
      },
    },
    display: {kind: "outfit", itemIds: ["shirt", "jeans", "hiking-boots"]},
  };
  const h = harness({modelResults: [
    firstPlanningFinal,
    toolEnvelope(
      [{tool: "wardrobe", scope: "full_relevant"}],
      {context: {terrain: {surface: null, difficulty: "easy", condition: null}}},
    ),
    finalEnvelope(generationResult),
  ]});

  const first = await h.coordinator.resolveTurn(request("chat-a", "a-1", 0,
    "Zajtra idem na túru, potrebujem outfit.", {
      freshClientObservations: {currentLocationObservation: martin},
    }));
  assert.equal(first.action, "clarify");
  assert.equal(first.clarification.field, "destination");
  assert.deepEqual(first.display, {kind: "none", itemIds: []});
  let saved = await h.sessionRepository.read("chat-a");
  assert.equal(saved.context.destination, null);
  assert.equal(saved.context.currentLocationObservation.providerId, "place:martin");
  assert.equal(h.ledger.calls("weather", "getForecast").length, 0);

  const reopened = createStylistTurnCoordinatorV2(h.ports);
  const second = await reopened.resolveTurn(request("chat-a", "a-2", 1, "Vysoké Tatry."));
  assert.equal(second.action, "clarify");
  assert.equal(second.clarification.field, "terrain.difficulty");
  assert.equal((second.assistantText.match(/\?/g) || []).length, 1);
  saved = await h.sessionRepository.read("chat-a");
  assert.equal(saved.context.destination.providerId, "place:tatras");
  assert.equal(saved.context.currentLocationObservation.providerId, "place:martin");
  let weatherCalls = h.ledger.calls("weather", "getForecast");
  // Do not spend a weather call while another material clarification is
  // still pending. The forecast is fetched only on the turn that can
  // actually proceed to final outfit selection.
  assert.equal(weatherCalls.length, 0);

  const third = await reopened.resolveTurn(request("chat-a", "a-3", 2, "Ľahká trasa."));
  assert.equal(third.action, "generate_outfit");
  assert.deepEqual(third.display.itemIds, third.resultingOutfit.itemIds);
  weatherCalls = h.ledger.calls("weather", "getForecast");
  assert.equal(weatherCalls.length, 1);
  assert.equal(weatherCalls[0].args.location.providerId, "place:tatras");
  saved = await h.sessionRepository.read("chat-a");
  assert.deepEqual(saved.context.terrain, {surface: null, difficulty: "easy", condition: null});
  assert.equal(h.ledger.calls("model", "plan").length, 2);
  assert.equal(h.ledger.calls("model", "final").length, 1);
  const wardrobeIndex = h.ledger.entries.findIndex((entry) => entry.port === "wardrobe");
  assert.ok(wardrobeIndex < modelCallIndex(h.ledger, "final"));
  const finalInput = h.ledger.calls("model", "final")[0].args;
  assert.deepEqual(finalInput.toolResults.wardrobeItems.map((item) => item.id), wardrobe.map((item) => item.id));

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

test("Scenario B retrieves current outfit plus requested category before the one-slot edit", async () => {
  const existing = bootstrapExistingChatV2({
    chatId: "chat-b",
    currentOutfitItemIds: ["shirt", "jeans", "shoes"],
    persistedSelectionReasonsByItemId: {
      shirt: "funguje farebne s outfitom",
      jeans: "krytie nôh do chladnejšieho rána",
      shoes: "pohodlné na mestskú chôdzu",
    },
  });
  const editResult = {
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
    editScope: {
      replaceItemIds: ["jeans"],
      allowedSlots: ["lower_body"],
      allowedCategories: ["bottoms"],
    },
    display: {kind: "items", itemIds: ["shorts"]},
  };
  const h = harness({
    initialStates: [existing],
    modelResults: [
      toolEnvelope([{
        tool: "wardrobe",
        scope: "current_outfit_plus_category",
        category: "bottoms",
        editScope: editResult.editScope,
      }]),
      finalEnvelope(editResult),
    ],
  });
  const result = await h.coordinator.resolveTurn(request("chat-b", "b-1", 0,
    "Rifle by som vymenil za kraťasy."));
  assert.deepEqual(result.resultingOutfit.itemIds, ["shirt", "shorts", "shoes"]);
  const retrieval = h.ledger.calls("wardrobe", "retrieve")[0];
  assert.deepEqual(retrieval.args, {
    scope: "current_outfit_plus_category",
    itemIds: ["shirt", "jeans", "shoes"],
    category: "bottoms",
  });
  assert.ok(h.ledger.entries.indexOf(retrieval) < modelCallIndex(h.ledger, "final"));
  assert.deepEqual(h.ledger.calls("model", "final")[0].args.toolResults.wardrobeItems.map((item) => item.id),
    ["shirt", "jeans", "shorts", "shoes"]);
  const saved = await h.sessionRepository.read("chat-b");
  assert.deepEqual(saved.currentOutfit.selectionReasonHistory, [{
    itemId: "jeans", reason: "krytie nôh do chladnejšieho rána", outfitRevision: 1,
  }]);
});

test("edit scope rejects retained replacements and unrelated second-slot additions", async () => {
  const cases = [
    {
      name: "retained-jeans",
      tool: {
        tool: "wardrobe",
        scope: "current_outfit_plus_category",
        category: "bottoms",
        editScope: {
          replaceItemIds: ["jeans"], allowedSlots: ["lower_body"], allowedCategories: ["bottoms"],
        },
      },
      itemIds: ["shirt", "jeans", "shorts", "shoes"],
      reasons: {
        shirt: "shirt reason", jeans: "jeans reason", shorts: "new shorts reason", shoes: "shoes reason",
      },
    },
    {
      name: "extra-hoodie",
      tool: {
        tool: "wardrobe",
        scope: "full_relevant",
        editScope: {
          replaceItemIds: ["jeans"], allowedSlots: ["lower_body"], allowedCategories: ["bottoms"],
        },
      },
      itemIds: ["shirt", "shorts", "shoes", "hoodie"],
      reasons: {
        shirt: "shirt reason", shorts: "new shorts reason", shoes: "shoes reason", hoodie: "unrelated layer",
      },
    },
  ];
  for (const entry of cases) {
    const initial = bootstrapExistingChatV2({
      chatId: entry.name,
      currentOutfitItemIds: ["shirt", "jeans", "shoes"],
      persistedSelectionReasonsByItemId: {
        shirt: "shirt reason", jeans: "jeans reason", shoes: "shoes reason",
      },
    });
    const h = harness({initialStates: [initial], modelResults: [
      toolEnvelope([entry.tool]),
      finalEnvelope({
        action: "edit_outfit",
        assistantText: "Mením spodný diel.",
        resultingOutfit: {itemIds: entry.itemIds, selectionReasonsByItemId: entry.reasons},
        editScope: {
          replaceItemIds: ["jeans"],
          allowedSlots: ["lower_body"],
          allowedCategories: ["bottoms"],
        },
        display: {kind: "items", itemIds: entry.itemIds.filter((id) => !["shirt", "shoes"].includes(id))},
      }),
    ]});
    await assert.rejects(
      h.coordinator.resolveTurn(request(entry.name, `${entry.name}-1`, 0, "Vymeň rifle za kraťasy.")),
      SafetyCriticalTurnError,
    );
    assert.equal(h.ledger.calls("session", "write").length, 0);
  }
});

test("planning phase cannot return a final outfit before any wardrobe retrieval", async () => {
  const h = harness({modelResults: [finalEnvelope(fullOutfitResult())]});
  await assert.rejects(
    h.coordinator.resolveTurn(request("early-final", "early-final-1", 0, "Vytvor outfit.")),
    /planning phase may finalize only/,
  );
  assert.equal(h.ledger.calls("wardrobe").length, 0);
  assert.equal(h.ledger.calls("model", "final").length, 0);
  assert.equal(h.ledger.calls("session", "write").length, 0);
});

test("Scenario C resolves typed Yes against persisted Shopping context", async () => {
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
  assert.equal(h.ledger.calls("model").length, 0);
  const call = h.ledger.calls("shopping", "search")[0].args;
  assert.equal(call.actionId, "abc123");
  assert.equal(call.destination.providerId, "place:tatras");
  assert.equal(call.weather.locationProviderId, "place:tatras");
  assert.deepEqual(call.terrain, {surface: "trail", difficulty: "steep", condition: "wet"});
});

test("typed negative variants deterministically decline exactly one pending action", async () => {
  for (const [index, negative] of ["Nie", "nie, ďakujem", "nechcem"].entries()) {
    const state = clone(createEmptySessionStateV2(`decline-${index}`));
    state.conversationMemory.pendingAction = {
      type: "action", kind: "shopping", actionId: `shop-${index}`,
    };
    const h = harness({initialStates: [validateStylistSessionStateV2(state)]});
    const result = await h.coordinator.resolveTurn(request(`decline-${index}`, `decline-turn-${index}`, 0, negative));
    assert.equal(result.action, "chat");
    assert.equal(h.ledger.calls("shopping").length, 0);
    assert.equal(h.ledger.calls("model").length, 0);
    const saved = await h.sessionRepository.read(`decline-${index}`);
    assert.equal(saved.conversationMemory.pendingAction, null);
  }
});

test("Scenario D consultation retrieves current outfit only before explanation", async () => {
  const state = bootstrapExistingChatV2({
    chatId: "chat-d",
    currentOutfitItemIds: ["shirt", "jeans", "shoes"],
    persistedSelectionReasonsByItemId: {shirt: "farba", jeans: "krytie", shoes: "pohodlie"},
  });
  const mutable = clone(state);
  mutable.conversationMemory.communicatedWarnings = ["footwear_not_hiking_grade"];
  const h = harness({
    initialStates: [validateStylistSessionStateV2(mutable)],
    modelResults: [
      toolEnvelope([{tool: "wardrobe", scope: "current_outfit"}]),
      finalEnvelope({
        action: "explain_outfit",
        assistantText: "Áno, rifle sú v poriadku — dávajú ti krytie nôh a stále ladia s tričkom.",
        display: {kind: "none", itemIds: []},
      }),
    ],
  });
  const result = await h.coordinator.resolveTurn(request("chat-d", "d-1", 0, "A rifle sú v poriadku?"));
  assert.equal(result.action, "explain_outfit");
  assert.deepEqual(result.resultingOutfit.itemIds, ["shirt", "jeans", "shoes"]);
  assert.deepEqual(h.ledger.calls("wardrobe", "retrieve")[0].args, {
    scope: "current_outfit", itemIds: ["shirt", "jeans", "shoes"], category: null,
  });
  assert.deepEqual(h.ledger.calls("model", "final")[0].args.toolResults.wardrobeItems.map((item) => item.id),
    ["shirt", "jeans", "shoes"]);
  assert.doesNotMatch(result.assistantText, /obuv|topán/i);
});

test("Scenario E greeting uses neither wardrobe nor model", async () => {
  const h = harness();
  const result = await h.coordinator.resolveTurn(request("chat-e", "e-1", 0, "Ahoj."));
  assert.equal(result.action, "chat");
  assert.deepEqual(result.resultingOutfit.itemIds, []);
  assert.equal(h.ledger.calls("model").length, 0);
  assert.equal(h.ledger.calls("wardrobe").length, 0);
});

test("Scenario F conversation-only turn permits an empty outfit and no wardrobe", async () => {
  const h = harness({modelResults: [finalEnvelope({
    action: "chat",
    assistantText: "K modrej sa pekne hodí biela, sivá aj tlmená béžová.",
    display: {kind: "none", itemIds: []},
  })]});
  const result = await h.coordinator.resolveTurn(request("chat-f", "f-1", 0,
    "Aké farby sa hodia k modrej?"));
  assert.equal(result.action, "chat");
  assert.deepEqual(result.resultingOutfit.itemIds, []);
  assert.equal(h.ledger.calls("model", "plan").length, 1);
  assert.equal(h.ledger.calls("wardrobe").length, 0);
});

test("remote concert and wedding use their provider-resolved event location as generic weather authority", async () => {
  const concert = harness({modelResults: [
    toolEnvelope([
      {tool: "location", query: "Bratislava", targetField: "eventLocation"},
      {tool: "wardrobe", scope: "full_relevant"},
    ], {
      context: {
        activity: {id: "concert"},
        date: {dateKey: "2026-09-09", source: "user"},
        groundingRequirements: {
          weatherRequired: true,
          weatherLocationField: "eventLocation",
          terrainRequiredFields: [],
        },
      },
    }),
    finalEnvelope(fullOutfitResult()),
  ]});
  const concertResult = await concert.coordinator.resolveTurn(request("concert", "concert-1", 0,
    "Zajtra idem na koncert do Bratislavy.", {
      freshClientObservations: {currentLocationObservation: martin},
    }));
  assert.equal(concertResult.action, "generate_outfit");
  assert.doesNotMatch(concertResult.assistantText, /ktorej časti dňa|kam presne|terén/i);
  let saved = await concert.sessionRepository.read("concert");
  assert.equal(saved.context.eventLocation.providerId, bratislava.providerId);
  assert.equal(saved.context.currentLocationObservation.providerId, "place:martin");
  assert.equal(saved.context.timeWindow.key, "day");
  assert.equal(concert.ledger.calls("weather", "getForecast")[0].args.location.providerId,
    bratislava.providerId);
  assert.equal(concert.ledger.calls("wardrobe", "retrieve").length, 1);
  assert.ok(concert.ledger.entries.findIndex((item) => item.port === "wardrobe") < modelCallIndex(concert.ledger, "final"));

  const wedding = harness({modelResults: [
    toolEnvelope([
      {tool: "location", query: "Žilina", targetField: "eventLocation"},
      {tool: "wardrobe", scope: "full_relevant"},
    ], {
      context: {
        activity: {id: "wedding"},
        groundingRequirements: {
          weatherRequired: true,
          weatherLocationField: "eventLocation",
          terrainRequiredFields: [],
        },
      },
    }),
    toolEnvelope(
      [{tool: "wardrobe", scope: "full_relevant"}],
      {context: {
        date: {dateKey: "2026-09-09", source: "user"},
        timeWindow: {key: "afternoon", label: "popoludní"},
      }},
    ),
    finalEnvelope(fullOutfitResult()),
  ]});
  const weddingFirst = await wedding.coordinator.resolveTurn(request("wedding", "wedding-1", 0,
    "Idem na svadbu do Žiliny.", {
      freshClientObservations: {currentLocationObservation: martin},
    }));
  assert.equal(weddingFirst.action, "clarify");
  assert.equal(weddingFirst.clarification.field, "date");
  assert.equal(wedding.ledger.calls("weather").length, 0);
  assert.equal(wedding.ledger.calls("wardrobe").length, 0);

  const weddingResult = await wedding.coordinator.resolveTurn(request(
    "wedding", "wedding-2", 1, "Zajtra popoludní.",
  ));
  assert.equal(weddingResult.action, "generate_outfit");
  assert.doesNotMatch(weddingResult.assistantText, /kam presne|terén/i);
  saved = await wedding.sessionRepository.read("wedding");
  assert.equal(saved.context.eventLocation.providerId, zilina.providerId);
  assert.equal(saved.context.currentLocationObservation.providerId, "place:martin");
  assert.equal(wedding.ledger.calls("weather", "getForecast")[0].args.location.providerId,
    zilina.providerId);
  assert.ok(wedding.ledger.entries.findIndex((item) => item.port === "wardrobe") < modelCallIndex(wedding.ledger, "final"));
});

test("explicit destination candidate is resolved in the first hiking turn without a repeat question", async () => {
  const h = harness({modelResults: [
    toolEnvelope([
      {tool: "location", query: "Vysoké Tatry", targetField: "destination"},
      {tool: "wardrobe", scope: "full_relevant"},
    ], {
      context: {
        activity: {id: "hiking"},
        date: {dateKey: "2026-09-09", source: "user"},
        timeWindow: {key: "daytime", label: "cez deň"},
        groundingRequirements: {
          weatherRequired: true,
          weatherLocationField: "destination",
          terrainRequiredFields: [],
        },
      },
    }),
    finalEnvelope(fullOutfitResult("Outfit je pripravený pre počasie vo Vysokých Tatrách.")),
  ]});
  const result = await h.coordinator.resolveTurn(request("explicit-tatras", "tatras-1", 0,
    "Zajtra idem na túru do Vysokých Tatier, potrebujem outfit.", {
      freshClientObservations: {currentLocationObservation: martin},
    }));
  assert.equal(result.action, "generate_outfit");
  assert.doesNotMatch(result.assistantText, /kam presne|aká náročná|povrch/i);
  const saved = await h.sessionRepository.read("explicit-tatras");
  assert.equal(saved.context.destination.providerId, "place:tatras");
  assert.equal(saved.context.currentLocationObservation.providerId, "place:martin");
  assert.equal(h.ledger.calls("location", "resolve")[0].args.query, "Vysoké Tatry");
  assert.equal(h.ledger.calls("weather", "getForecast")[0].args.location.providerId, "place:tatras");
});

test("resolved event location with no remaining grounding continues the same turn and never defaults to terrain", async () => {
  const state = clone(createEmptySessionStateV2("resolved-event"));
  state.context.activity = {id: "concert"};
  state.context.date = {dateKey: "2026-09-09", source: "user"};
  state.context.timeWindow = {key: "evening", label: "večer"};
  state.context.groundingRequirements = {
    weatherRequired: true,
    weatherLocationField: "eventLocation",
    terrainRequiredFields: [],
  };
  state.conversationMemory.pendingQuestion = {
    type: "question", actionId: "clarify_event_location", field: "eventLocation",
    question: "Kde presne sa podujatie koná?", acceptsYesNo: false,
  };
  const h = harness({
    initialStates: [validateStylistSessionStateV2(state)],
    modelResults: [finalEnvelope(fullOutfitResult())],
  });
  const result = await h.coordinator.resolveTurn(request("resolved-event", "event-2", 0, "Bratislava."));
  assert.equal(result.action, "generate_outfit");
  assert.notEqual(result.action, "clarify");
  assert.equal(h.ledger.calls("weather")[0].args.location.providerId, "place:bratislava");
  assert.equal(h.ledger.calls("wardrobe", "retrieve").length, 1);
  assert.equal(h.ledger.calls("model", "plan").length, 0);
  assert.equal(h.ledger.calls("model", "final").length, 1);
});

test("final mutation cannot select an ID absent from the wardrobe tool result", async () => {
  const h = harness({modelResults: [
    toolEnvelope([{tool: "wardrobe", scope: "category", category: "bottoms"}]),
    finalEnvelope({
      action: "generate_outfit",
      assistantText: "Vybral som outfit.",
      resultingOutfit: {
        itemIds: ["shorts", "hoodie"],
        selectionReasonsByItemId: {shorts: "ľahký spodok", hoodie: "vrstva"},
      },
      display: {kind: "outfit", itemIds: ["shorts", "hoodie"]},
    }),
  ]});
  await assert.rejects(
    h.coordinator.resolveTurn(request("unsupplied", "unsupplied-1", 0, "Vytvor outfit.")),
    SafetyCriticalTurnError,
  );
  const supplied = h.ledger.calls("model", "final")[0].args.toolResults.wardrobeItems.map((item) => item.id);
  assert.deepEqual(supplied, ["jeans", "shorts"]);
  assert.equal(h.ledger.calls("session", "write").length, 0);
});
