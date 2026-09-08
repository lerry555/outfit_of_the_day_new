"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  bootstrapExistingChatV2,
  clone,
  createEmptySessionStateV2,
  validateStylistSessionStateV2,
} = require("./stylist_session_state_v2");
const {validateTurnRequestV2, validateTurnResultContractV2} = require("./stylist_turn_contract_v2");
const {AmbiguousAffirmationError, runPreflightV2} = require("./stylist_preflight_v2");
const {
  RepairableStructuralTurnError,
  SafetyCriticalTurnError,
  VALIDATOR_BOUNDARIES_V2,
  validateAuthoritativeTurnV2,
} = require("./stylist_turn_validator_v2");
const {STYLIST_SESSION_V2_PATH, intendedClientAccessV2} = require("./firestore_rules_contract_v2");
const {
  DETERMINISTIC,
  INTEGRATION,
  MODEL_EVAL,
  MODEL_QUALITY_EVAL_SPECS_V2,
  PROBLEM_BACKLOG_V2,
} = require("./stylist_v2_backlog");

function baseRequest(overrides = {}) {
  return {
    chatId: "chat-contract",
    turnId: "turn-1",
    expectedSessionRevision: 0,
    latestUserInput: "Ahoj",
    clientCapabilities: {typedQuickReplies: true},
    ...overrides,
  };
}

function completeHikingState(chatId = "chat-validator") {
  const state = clone(createEmptySessionStateV2(chatId));
  state.context.activity = {id: "hiking"};
  state.context.destination = {providerId: "tatras", label: "Vysoké Tatry"};
  state.context.date = {dateKey: "2026-09-09", source: "user"};
  state.context.timeWindow = {key: "daytime", label: "cez deň"};
  state.context.terrain = {surface: "trail", difficulty: "easy", condition: "dry"};
  state.context.groundingRequirements = {
    weatherRequired: true,
    weatherLocationField: "destination",
    terrainRequiredFields: [],
  };
  state.context.weather = {
    locationProviderId: "tatras",
    dateKey: "2026-09-09",
    timeWindowKey: "daytime",
    fetchedAt: "2026-09-08T08:00:00Z",
    source: "fake",
    snapshot: {temperatureC: 18},
  };
  return validateStylistSessionStateV2(state);
}

function generatedResult(overrides = {}) {
  return {
    turnId: "turn-1",
    action: "generate_outfit",
    assistantText: "Toto je výsledný outfit.",
    resultingOutfit: {
      itemIds: ["shirt", "boots"],
      selectionReasonsByItemId: {shirt: "priedušnosť", boots: "stabilita"},
    },
    editScope: null,
    clarification: null,
    display: {kind: "outfit", itemIds: ["shirt", "boots"]},
    shoppingResult: null,
    quickReplies: [],
    resultingSessionRevision: 1,
    ...overrides,
  };
}

test("existing-chat bootstrap keeps exact outfit/reasons and invents no destination, terrain, weather, or pending work", () => {
  const state = bootstrapExistingChatV2({
    chatId: "old-chat",
    currentOutfitItemIds: ["shirt", "jeans", "shoes"],
    persistedSelectionReasonsByItemId: {
      shirt: "persisted shirt reason",
      jeans: "persisted jeans reason",
      shoes: "persisted shoes reason",
    },
    knownExplicitDurableChoices: {
      activity: {id: "city_walk"},
      rejectedWardrobeItemIds: ["old-jacket"],
    },
  });
  assert.deepEqual(state.currentOutfit.itemIds, ["shirt", "jeans", "shoes"]);
  assert.equal(state.currentOutfit.selectionReasonsByItemId.jeans, "persisted jeans reason");
  assert.deepEqual(state.context.activity, {id: "city_walk"});
  assert.equal(state.context.destination, null);
  assert.deepEqual(state.context.terrain, {surface: null, difficulty: null, condition: null});
  assert.equal(state.context.weather, null);
  assert.equal(state.conversationMemory.pendingAction, null);
  assert.equal(state.conversationMemory.pendingQuestion, null);
  assert.ok(Object.isFrozen(state.currentOutfit.selectionReasonsByItemId));
  const unknownReason = bootstrapExistingChatV2({
    chatId: "bad-old-chat",
    currentOutfitItemIds: ["jeans"],
    persistedSelectionReasonsByItemId: {},
  });
  assert.deepEqual(unknownReason.currentOutfit.selectionReasonsByItemId, {jeans: null});
});

test("unknown terrain stays orthogonal and activity names do not imply wet, muddy, steep, rocky, snow, or ice", () => {
  for (const activityId of ["hiking", "forest", "mushroom_picking"]) {
    const state = clone(createEmptySessionStateV2(`terrain-${activityId}`));
    state.context.activity = {id: activityId};
    const validated = validateStylistSessionStateV2(state);
    assert.deepEqual(validated.context.terrain, {surface: null, difficulty: null, condition: null});
  }
  const invalid = clone(createEmptySessionStateV2("invalid-terrain"));
  invalid.context.terrain = {surface: "wetGround", difficulty: null, condition: null};
  assert.throws(() => validateStylistSessionStateV2(invalid), /orthogonal/);
});

test("request is strict and cannot submit prose history, current outfit, or destination as authority", () => {
  assert.throws(() => validateTurnRequestV2(baseRequest({history: [{role: "user", content: "old"}]})),
    /unsupported field history/);
  assert.throws(() => validateTurnRequestV2(baseRequest({currentOutfitItemIds: ["client-id"]})),
    /unsupported field currentOutfitItemIds/);
  assert.throws(() => validateTurnRequestV2(baseRequest({destination: "Tatry"})),
    /unsupported field destination/);
});

test("isolated affirmative text is rejected without exactly one active referent", () => {
  const request = validateTurnRequestV2(baseRequest({latestUserInput: "Áno."}));
  assert.throws(() => runPreflightV2(createEmptySessionStateV2("chat-contract"), request),
    AmbiguousAffirmationError);
  const state = clone(createEmptySessionStateV2("chat-contract"));
  state.conversationMemory.pendingAction = {type: "action", kind: "shopping", actionId: "shop-1"};
  state.conversationMemory.pendingQuestion = {
    type: "question", field: "approval", actionId: "question-1", question: "Súhlasíš?", acceptsYesNo: true,
  };
  assert.throws(() => runPreflightV2(validateStylistSessionStateV2(state), request),
    AmbiguousAffirmationError);
});

test("isolated negative text is rejected without exactly one active referent", () => {
  for (const latestUserInput of ["Nie", "nie, ďakujem", "nechcem"]) {
    const negativeRequest = validateTurnRequestV2(baseRequest({latestUserInput}));
    assert.throws(() => runPreflightV2(createEmptySessionStateV2("chat-contract"), negativeRequest),
      AmbiguousAffirmationError);
  }
});

test("explicit UI action ID resolves only its exact persisted referent", () => {
  const state = clone(createEmptySessionStateV2("chat-contract"));
  state.conversationMemory.pendingAction = {type: "action", kind: "shopping", actionId: "shop-1"};
  const validated = validateStylistSessionStateV2(state);
  const matched = runPreflightV2(validated, validateTurnRequestV2(baseRequest({
    latestUserInput: "",
    explicitUiActionId: "shop-1",
  })));
  assert.equal(matched.kind, "pending");
  assert.equal(matched.pending.actionId, "shop-1");
  assert.throws(() => runPreflightV2(validated, validateTurnRequestV2(baseRequest({
    latestUserInput: "",
    explicitUiActionId: "different-action",
  }))), AmbiguousAffirmationError);
});

test("stale GPS observation is not accepted as current authority and can never become destination", async () => {
  const {createStylistTurnCoordinatorV2} = require("./stylist_turn_coordinator_v2");
  const {
    CallLedgerV2, FakeLocationResolverV2, FakeShoppingToolV2, FakeStylistModelPortV2,
    FakeWardrobeToolV2, FakeWeatherToolV2, InMemorySessionRepositoryV2,
  } = require("./fake_ports_v2");
  const ledger = new CallLedgerV2();
  const repository = new InMemorySessionRepositoryV2(ledger);
  const coordinator = createStylistTurnCoordinatorV2({
    sessionRepository: repository,
    wardrobeTool: new FakeWardrobeToolV2(ledger),
    locationResolver: new FakeLocationResolverV2(ledger),
    weatherTool: new FakeWeatherToolV2(ledger),
    shoppingTool: new FakeShoppingToolV2(ledger),
    stylistModel: new FakeStylistModelPortV2(ledger),
    clock: () => Date.parse("2026-09-08T10:00:00Z"),
  });
  await coordinator.resolveTurn(baseRequest({
    latestUserInput: "Ahoj.",
    freshClientObservations: {currentLocationObservation: {
      providerId: "martin", label: "Martin", observedAt: "2026-09-08T08:00:00Z", source: "gps",
    }},
  }));
  const saved = await repository.read("chat-contract");
  assert.equal(saved.context.currentLocationObservation, null);
  assert.equal(saved.context.destination, null);
});

test("mismatched remote-event weather provenance is safety-critical outside hiking too", () => {
  const eventState = clone(createEmptySessionStateV2("generic-event-weather"));
  eventState.context.activity = {id: "concert"};
  eventState.context.eventLocation = {providerId: "bratislava", label: "Bratislava"};
  eventState.context.date = {dateKey: "2026-09-09", source: "user"};
  eventState.context.timeWindow = {key: "evening", label: "večer"};
  eventState.context.groundingRequirements = {
    weatherRequired: true,
    weatherLocationField: "eventLocation",
    terrainRequiredFields: [],
  };
  eventState.context.weather = {
    locationProviderId: "bratislava", dateKey: "2026-09-09", timeWindowKey: "evening",
    fetchedAt: "2026-09-08T08:00:00Z", source: "fake", snapshot: {},
  };
  const previousState = validateStylistSessionStateV2(eventState);
  const proposed = clone(previousState);
  proposed.context.weather.locationProviderId = "martin";
  assert.throws(() => validateAuthoritativeTurnV2({
    rawResult: generatedResult(),
    previousState,
    proposedState: validateStylistSessionStateV2(proposed),
    wardrobeItems: [{id: "shirt"}, {id: "boots"}],
  }), SafetyCriticalTurnError);
});

test("unsafe footwear on materially risky terrain is a safety-critical hard-constraint failure", () => {
  const previousState = completeHikingState("unsafe-footwear");
  const proposed = clone(previousState);
  proposed.context.terrain = {surface: "trail", difficulty: "steep", condition: "wet"};
  assert.throws(() => validateAuthoritativeTurnV2({
    rawResult: generatedResult(),
    previousState,
    proposedState: validateStylistSessionStateV2(proposed),
    wardrobeItems: [
      {id: "shirt", category: "tops"},
      {id: "boots", category: "footwear", safety: {hikingTechnical: false}},
    ],
  }), /unsafe footwear/);
});

test("clarification cardinality and display/result divergence are repairable structural failures", () => {
  const state = createEmptySessionStateV2("contract-result");
  assert.throws(() => validateTurnResultContractV2({
    turnId: "x",
    action: "clarify",
    assistantText: "Kam ideš? A kedy?",
    resultingOutfit: {itemIds: [], selectionReasonsByItemId: {}},
    editScope: null,
    clarification: {field: "destination", question: "Kam ideš? A kedy?", actionId: "q"},
    display: {kind: "none", itemIds: []},
    shoppingResult: null,
    quickReplies: [],
    resultingSessionRevision: 1,
  }, state), /exactly one question/);

  let structural;
  try {
    validateAuthoritativeTurnV2({
      rawResult: generatedResult({display: {kind: "outfit", itemIds: ["shirt"]}}),
      previousState: completeHikingState(),
      proposedState: completeHikingState(),
      wardrobeItems: [{id: "shirt"}, {id: "boots"}],
    });
  } catch (error) {
    structural = error;
  }
  assert.ok(structural instanceof RepairableStructuralTurnError);
  assert.equal(structural.maxFutureCorrectionAttempts, 1);
});

test("show_items is explicit but non-mutating, and stop is non-mutating with no cards", () => {
  const state = createEmptySessionStateV2("show-stop");
  const shown = validateAuthoritativeTurnV2({
    rawResult: {
      turnId: "show-1", action: "show_items", assistantText: "Tu je tričko.",
      resultingOutfit: {itemIds: [], selectionReasonsByItemId: {}},
      editScope: null, clarification: null, display: {kind: "items", itemIds: ["shirt"]},
      shoppingResult: null, quickReplies: [], resultingSessionRevision: 1,
    },
    previousState: state,
    proposedState: state,
    wardrobeItems: [{id: "shirt", category: "tops"}],
  });
  assert.deepEqual(shown.resultingOutfit.itemIds, []);
  assert.deepEqual(shown.display.itemIds, ["shirt"]);
  const stopped = validateTurnResultContractV2({
    turnId: "stop-1", action: "stop", assistantText: "Dobre, zastavím sa tu.",
    resultingOutfit: {itemIds: [], selectionReasonsByItemId: {}},
    editScope: null, clarification: null, display: {kind: "none", itemIds: []},
    shoppingResult: null, quickReplies: [], resultingSessionRevision: 1,
  }, state);
  assert.equal(stopped.action, "stop");
});

test("retained reasons cannot be rewritten and Shopping hard constraints cannot be relaxed", () => {
  const base = clone(completeHikingState("immutable-reasons"));
  base.currentOutfit.itemIds = ["shirt", "boots"];
  base.currentOutfit.selectionReasonsByItemId = {shirt: "original shirt reason", boots: "original boot reason"};
  base.currentOutfit.revision = 1;
  const state = validateStylistSessionStateV2(base);
  const immutableEditScope = {replaceItemIds: ["boots"], allowedSlots: ["feet"]};
  assert.throws(() => validateAuthoritativeTurnV2({
    rawResult: generatedResult({
      action: "edit_outfit",
      resultingOutfit: {
        itemIds: ["shirt", "boots"],
        selectionReasonsByItemId: {shirt: "rewritten reason", boots: "original boot reason"},
      },
      editScope: immutableEditScope,
      display: {kind: "items", itemIds: ["boots"]},
    }),
    previousState: state,
    proposedState: state,
    wardrobeItems: [
      {id: "shirt", category: "tops", bodySlots: ["upper_body"]},
      {id: "boots", category: "footwear", bodySlots: ["feet"]},
    ],
    authorizedEditScope: immutableEditScope,
  }), /cannot be rewritten/);

  const shoppingState = clone(createEmptySessionStateV2("hard-shopping"));
  shoppingState.shopping.hardConstraints = ["waterproof", "technical_grip"];
  const validatedShoppingState = validateStylistSessionStateV2(shoppingState);
  assert.throws(() => validateAuthoritativeTurnV2({
    rawResult: {
      turnId: "shop-1", action: "shop", assistantText: "Tu sú možnosti.",
      resultingOutfit: {itemIds: [], selectionReasonsByItemId: {}}, editScope: null,
      clarification: null, display: {kind: "shopping", itemIds: ["p1"]},
      shoppingResult: {candidateIds: ["p1"], appliedHardConstraints: ["waterproof"]},
      quickReplies: [], resultingSessionRevision: 1,
    },
    previousState: validatedShoppingState,
    proposedState: validatedShoppingState,
  }), /silently relaxed/);
});

test("cosmetics normalize locally while subjective styling quality is not schema-validated", () => {
  const state = createEmptySessionStateV2("cosmetics");
  const result = validateTurnResultContractV2({
    turnId: "cosmetic-turn",
    action: "chat",
    assistantText: "  Toto    nie je hodnotené ako dobrý štýl.  ",
    resultingOutfit: {itemIds: [], selectionReasonsByItemId: {}},
    editScope: null,
    clarification: null,
    display: {kind: "none", itemIds: []},
    shoppingResult: null,
    quickReplies: [{actionId: "later", label: ""}],
    resultingSessionRevision: 1,
  }, state);
  assert.equal(result.assistantText, "Toto nie je hodnotené ako dobrý štýl.");
  assert.deepEqual(result.quickReplies, [{actionId: "later", label: "later"}]);
  assert.equal(VALIDATOR_BOUNDARIES_V2.subjectiveQuality.includes("outside"), true);
});

test("Phase-0 Firestore contract is server-write-only without changing production rules", () => {
  assert.equal(STYLIST_SESSION_V2_PATH, "users/{uid}/stylistSessionsV2/{chatId}");
  assert.equal(intendedClientAccessV2({operation: "get", authenticatedUid: "u1", pathUid: "u1"}), true);
  for (const operation of ["create", "update", "delete"]) {
    assert.equal(intendedClientAccessV2({operation, authenticatedUid: "u1", pathUid: "u1"}), false);
  }
  assert.equal(intendedClientAccessV2({operation: "get", authenticatedUid: "u2", pathUid: "u1"}), false);
});

test("all 30 problems have one explicit disposition and every model-quality item has an eval fixture", () => {
  assert.equal(PROBLEM_BACKLOG_V2.length, 30);
  assert.deepEqual(PROBLEM_BACKLOG_V2.map((entry) => entry.id), Array.from({length: 30}, (_, index) => index + 1));
  const allowed = new Set([DETERMINISTIC, INTEGRATION, MODEL_EVAL]);
  assert.equal(PROBLEM_BACKLOG_V2.every((entry) => allowed.has(entry.classification) && entry.safeguard), true);
  const evalIds = new Set(MODEL_QUALITY_EVAL_SPECS_V2.flatMap((spec) => spec.problemIds));
  const classifiedEvalIds = PROBLEM_BACKLOG_V2.filter((entry) => entry.classification === MODEL_EVAL)
    .map((entry) => entry.id);
  assert.equal(classifiedEvalIds.every((id) => evalIds.has(id)), true);
  assert.equal(MODEL_QUALITY_EVAL_SPECS_V2.every((spec) => spec.input && spec.relevantSessionState &&
    spec.expectedQualities.length && spec.forbiddenBehavior.length), true);
});
