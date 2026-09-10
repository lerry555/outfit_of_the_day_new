"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {clone, createEmptySessionStateV2} = require("./stylist_session_state_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");
const {createStylistTurnEngineV2} = require("./stylist_turn_engine_v2");
const {highestPriorityMissingGroundingV2} = require("./stylist_preflight_v2");
const {
  applyMandatoryGroundingV2,
  createGroundingEnforcedStylistModelV2,
  inferMandatoryGroundingV2,
  mergeGroundingRequirementsV2,
} = require("./stylist_grounding_policy_v2");
const {
  pendingLocationReplyDispositionV2,
  skipPendingClarificationV2,
} = require("./stylist_turn_coordinator_v2");
const {
  CallLedgerV2,
  FakeLocationResolverV2,
  FakeShoppingToolV2,
  FakeStylistModelPortV2,
  FakeWardrobeToolV2,
  FakeWeatherToolV2,
} = require("./fake_ports_v2");

const NOW = Date.parse("2026-09-10T10:00:00.000Z");
const wardrobe = [
  {id: "shirt", category: "tops", bodySlots: ["upper_body"]},
  {id: "pants", category: "bottoms", bodySlots: ["lower_body"]},
  {id: "hiking-boots", category: "footwear", bodySlots: ["feet"], safety: {hikingTechnical: true}},
];
const austria = {providerId: "place:austria", label: "Rakúsko", lat: 47.5, lng: 14.5, granularity: "country"};
const alps = {providerId: "place:alps", label: "Alpy, Rakúsko", lat: 47.2, lng: 12.3, granularity: "region"};

function request(chatId, turnId, revision, text) {
  return {
    chatId,
    turnId,
    expectedSessionRevision: revision,
    latestUserInput: text,
    clientCapabilities: {
      typedQuickReplies: true,
      explicitDisplay: true,
      todayDateKey: "2026-09-10",
      tomorrowDateKey: "2026-09-11",
    },
  };
}

function toolEnvelope(requests, statePatch) {
  return {kind: "tool_request", requests, statePatch};
}

function hikingOutfitEnvelope(text = "Tu je bezpečný univerzálny outfit na túru.") {
  return {
    kind: "final",
    result: {
      action: "generate_outfit",
      assistantText: text,
      resultingOutfit: {
        itemIds: ["shirt", "pants", "hiking-boots"],
        selectionReasonsByItemId: {
          shirt: "základná vrstva",
          pants: "krytie nôh",
          "hiking-boots": "konzervatívna turistická obuv pri neznámom povrchu",
        },
      },
      display: {kind: "outfit", itemIds: ["shirt", "pants", "hiking-boots"]},
    },
  };
}

function engineHarness({modelResults, resolutions = {}, weatherSnapshots = {}}) {
  const ledger = new CallLedgerV2();
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const engine = createStylistTurnEngineV2({
    sessionRepository: repository,
    wardrobeTool: new FakeWardrobeToolV2(ledger, wardrobe),
    locationResolver: new FakeLocationResolverV2(ledger, resolutions),
    weatherTool: new FakeWeatherToolV2(ledger, weatherSnapshots),
    shoppingTool: new FakeShoppingToolV2(ledger),
    stylistModel: new FakeStylistModelPortV2(ledger, modelResults),
    clock: () => NOW,
  });
  return {engine, ledger, repository};
}

test("phone regression: Austria hike -> Alps proceeds to outfit and never asks terrain", async () => {
  const h = engineHarness({
    resolutions: {"Rakúska": austria, "do Álp": alps, "Álp": alps},
    // The common remote-outfit grammar is deterministic: no planning model
    // call is allowed before the one final stylist decision.
    modelResults: [hikingOutfitEnvelope()],
  });

  const first = await h.engine.resolveTurn({
    uid: "user-a",
    request: request("chat-phone", "turn-1", 0, "zajtra chcem ísť do Rakúska na túru potrebujem outfit"),
  });
  assert.equal(first.action, "clarify");
  assert.equal(first.clarification.field, "destination");

  const second = await h.engine.resolveTurn({
    uid: "user-a",
    request: request("chat-phone", "turn-2", 1, "do Álp"),
  });
  assert.equal(second.action, "generate_outfit");
  assert.equal(second.clarification, null);
  assert.equal((second.assistantText.match(/\?/g) || []).length, 0);

  const saved = await h.repository.get({uid: "user-a", chatId: "chat-phone"});
  assert.equal(saved.state.context.destination.providerId, "place:alps");
  assert.deepEqual(saved.state.context.groundingRequirements.terrainRequiredFields, []);
  assert.equal(h.ledger.calls("model", "plan").length, 0);
  assert.equal(h.ledger.calls("model", "final").length, 1);
});

test("one broad location answer is enough: keep it as context and continue weatherless", async () => {
  const state = clone(createEmptySessionStateV2("chat-broad"));
  state.context.activity = {id: "hiking", label: "túra", source: "user"};
  state.context.date = {dateKey: "2026-09-11", source: "user"};
  state.context.timeWindow = {key: "day", label: "cez deň", source: "help_first_default"};
  state.context.groundingRequirements = {weatherRequired: true, weatherLocationField: "destination", terrainRequiredFields: []};
  state.conversationMemory.pendingQuestion = {
    type: "question", field: "destination", question: "Kam približne ideš?",
    actionId: "clarify_destination", acceptsYesNo: false,
  };

  const h = engineHarness({
    resolutions: {"niekde v Rakúsku": austria, "Rakúsku": austria},
    modelResults: [hikingOutfitEnvelope("Presnú lokálnu predpoveď nemám, preto volím konzervatívny outfit.")],
  });
  await h.repository.ensure({uid: "user-a", chatId: "chat-broad", bootstrapState: state});

  const result = await h.engine.resolveTurn({
    uid: "user-a",
    request: request("chat-broad", "turn-1", 0, "niekde v Rakúsku"),
  });
  assert.equal(result.action, "generate_outfit");
  assert.equal(h.ledger.calls("weather", "getForecast").length, 0);
  const saved = await h.repository.get({uid: "user-a", chatId: "chat-broad"});
  assert.equal(saved.state.context.destination.providerId, "place:austria");
  assert.equal(saved.state.context.groundingRequirements.weatherRequired, false);
  assert.equal(saved.state.conversationMemory.pendingQuestion, null);
});

test("neviem and skip phrases are universal pending-clarification exits", () => {
  for (const phrase of ["neviem", "netuším", "je mi to jedno", "preskoč to", "nerieš", "daj mi proste outfit", "proste mi daj outfit"]) {
    assert.equal(pendingLocationReplyDispositionV2(phrase), "skip", phrase);
  }
});

test("skipping any material clarification persists unknown and makes it non-repeatable", () => {
  const cases = [
    ["terrain.surface", ["surface"]],
    ["terrain.difficulty", ["difficulty"]],
    ["terrain.condition", ["condition"]],
    ["destination", []],
    ["eventLocation", []],
    ["date", []],
    ["timeWindow", []],
    ["currentLocationObservation", []],
  ];

  for (const [field, terrainRequiredFields] of cases) {
    const state = clone(createEmptySessionStateV2(`skip-${field.replace(/\W/g, "-")}`));
    state.context.groundingRequirements = {
      weatherRequired: !field.startsWith("terrain."),
      weatherLocationField: field === "destination" || field === "eventLocation" || field === "currentLocationObservation" ? field :
        (!field.startsWith("terrain.") ? "currentLocationObservation" : null),
      terrainRequiredFields,
    };
    if (["date", "timeWindow"].includes(field)) {
      state.context.currentLocationObservation = {
        providerId: "gps:test", label: "Martin", observedAt: "2026-09-10T09:59:00.000Z",
      };
    }
    state.conversationMemory.pendingQuestion = {
      type: "question", field, question: `question ${field}`, actionId: `clarify_${field.replace(/\W/g, "_")}`,
      acceptsYesNo: false,
    };

    const next = skipPendingClarificationV2(state, field);
    assert.equal(next.conversationMemory.pendingQuestion, null, field);
    assert.deepEqual(next.conversationMemory.answeredClarificationFields[field], {status: "unknown", source: "user"}, field);
    assert.notEqual(highestPriorityMissingGroundingV2(next), field, field);
    if (field.startsWith("terrain.")) assert.deepEqual(next.context.groundingRequirements.terrainRequiredFields, [], field);
    else assert.equal(next.context.groundingRequirements.weatherRequired, false, field);
  }
});

test("planner cannot promote optional terrain facts into mandatory questions", async () => {
  const state = clone(createEmptySessionStateV2("planner-terrain"));
  state.context.currentLocationObservation = {
    providerId: "gps:martin", label: "Martin", observedAt: "2026-09-10T09:59:00.000Z",
  };
  const message = "daj mi outfit na zajtra";
  const policy = inferMandatoryGroundingV2({latestUserInput: message, state});
  const grounded = applyMandatoryGroundingV2(state, policy);
  const model = createGroundingEnforcedStylistModelV2({async turn() {
    return toolEnvelope([{tool: "wardrobe", scope: "full_relevant", category: null, editScope: null}], {
      context: {
        date: {dateKey: "2026-09-11", source: "user"},
        timeWindow: {key: "day", label: "cez deň"},
        groundingRequirements: {
          weatherRequired: true,
          weatherLocationField: "currentLocationObservation",
          terrainRequiredFields: ["surface", "difficulty", "condition"],
        },
      },
    });
  }}, policy);

  const envelope = await model.turn({phase: "plan", request: {latestUserInput: message}, session: grounded});
  assert.deepEqual(envelope.statePatch.context.groundingRequirements.terrainRequiredFields, []);
});

test("truly server-owned terrain requirements are preserved while planner additions are rejected", () => {
  const merged = mergeGroundingRequirementsV2(
    {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: ["surface"]},
    {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: ["difficulty", "condition"]},
    {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: ["surface"]},
  );
  assert.deepEqual(merged.terrainRequiredFields, ["surface"]);
});

test("legacy pending terrain bug: saying neviem goes straight to an outfit", async () => {
  const state = clone(createEmptySessionStateV2("chat-legacy-terrain"));
  state.context.activity = {id: "hiking", label: "túra", source: "user"};
  state.context.destination = alps;
  state.context.date = {dateKey: "2026-09-11", source: "user"};
  state.context.timeWindow = {key: "day", label: "cez deň", source: "help_first_default"};
  state.context.groundingRequirements = {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: ["surface"]};
  state.conversationMemory.pendingQuestion = {
    type: "question", field: "terrain.surface", question: "Po akom povrchu pôjdeš?",
    actionId: "clarify_terrain_surface", acceptsYesNo: false,
  };

  const h = engineHarness({modelResults: [hikingOutfitEnvelope()]});
  await h.repository.ensure({uid: "user-a", chatId: "chat-legacy-terrain", bootstrapState: state});
  const result = await h.engine.resolveTurn({
    uid: "user-a",
    request: request("chat-legacy-terrain", "turn-1", 0, "neviem"),
  });

  assert.equal(result.action, "generate_outfit");
  assert.equal(result.clarification, null);
  const saved = await h.repository.get({uid: "user-a", chatId: "chat-legacy-terrain"});
  assert.equal(saved.state.context.destination.providerId, "place:alps");
  assert.deepEqual(saved.state.context.groundingRequirements.terrainRequiredFields, []);
  assert.deepEqual(saved.state.conversationMemory.answeredClarificationFields["terrain.surface"], {status: "unknown", source: "user"});
});
