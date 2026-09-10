from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path, old, new):
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"anchor not found in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def regex_replace_once(path, pattern, replacement):
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"regex anchor count={count} in {path}: {pattern[:120]!r}")
    path.write_text(updated, encoding="utf-8")


# 1) Server-owned grounding wins over planner questionnaire wishes.
grounding = ROOT / "functions/stylist/v2/stylist_grounding_policy_v2.js"
replace_once(
    grounding,
    '    terrainRequiredFields: uniqueTerrainFields(base.terrainRequiredFields, patch.terrainRequiredFields, must?.terrainRequiredFields),',
    '    terrainRequiredFields: uniqueTerrainFields(base.terrainRequiredFields, must ? must.terrainRequiredFields : patch.terrainRequiredFields),',
)
regex_replace_once(
    grounding,
    r'function missingGroundingFieldV2\(state\) \{.*?\n\}',
    '''function clarificationWasSkippedV2(state, field) {
  return state?.conversationMemory?.answeredClarificationFields?.[field]?.status === "unknown";
}

function missingGroundingFieldV2(state) {
  const grounding = state?.context?.groundingRequirements;
  if (!grounding) return null;
  if (grounding.weatherLocationField && !state.context[grounding.weatherLocationField] &&
      !clarificationWasSkippedV2(state, grounding.weatherLocationField)) return grounding.weatherLocationField;
  if (grounding.weatherRequired) {
    if (!state.context.date && !clarificationWasSkippedV2(state, "date")) return "date";
    if (!state.context.timeWindow && !clarificationWasSkippedV2(state, "timeWindow")) return "timeWindow";
  }
  const terrain = state.context.terrain || {};
  const missingTerrain = (grounding.terrainRequiredFields || []).find((field) =>
    terrain[field] == null && !clarificationWasSkippedV2(state, `terrain.${field}`));
  return missingTerrain ? `terrain.${missingTerrain}` : null;
}''',
)

# 2) Preflight must never surface a field that the user explicitly skipped.
preflight = ROOT / "functions/stylist/v2/stylist_preflight_v2.js"
regex_replace_once(
    preflight,
    r'function highestPriorityMissingGroundingV2\(state\) \{.*?\n\}',
    '''function clarificationWasSkippedV2(state, field) {
  return state?.conversationMemory?.answeredClarificationFields?.[field]?.status === "unknown";
}

function highestPriorityMissingGroundingV2(state) {
  const grounding = state.context.groundingRequirements;
  if (grounding.weatherLocationField && !state.context[grounding.weatherLocationField] &&
      !clarificationWasSkippedV2(state, grounding.weatherLocationField)) return grounding.weatherLocationField;
  if (grounding.weatherRequired) {
    if (!state.context.date && !clarificationWasSkippedV2(state, "date")) return "date";
    if (!state.context.timeWindow && !clarificationWasSkippedV2(state, "timeWindow")) return "timeWindow";
  }
  const missingTerrainField = grounding.terrainRequiredFields.find((field) =>
    state.context.terrain[field] == null && !clarificationWasSkippedV2(state, `terrain.${field}`));
  if (missingTerrainField) return `terrain.${missingTerrainField}`;
  return null;
}''',
)

# 3) Coordinator: universal skip/defer and no planner-created terrain questionnaire.
coordinator = ROOT / "functions/stylist/v2/stylist_turn_coordinator_v2.js"
old_disable = '''function disableOptionalWeatherGroundingV2(state) {
  const next = clone(state);
  next.context.weather = null;
  next.context.groundingRequirements = {
    ...next.context.groundingRequirements,
    weatherRequired: false,
    weatherLocationField: null,
  };
  next.conversationMemory.pendingQuestion = null;
  return next;
}
'''
new_disable = old_disable + '''
function skipPendingClarificationV2(state, field) {
  const next = clone(state);
  next.conversationMemory.answeredClarificationFields = {
    ...(next.conversationMemory.answeredClarificationFields || {}),
    [field]: {status: "unknown", source: "user"},
  };
  next.conversationMemory.pendingQuestion = null;

  if (String(field || "").startsWith("terrain.")) {
    const terrainField = String(field).slice("terrain.".length);
    next.context.groundingRequirements = {
      ...next.context.groundingRequirements,
      terrainRequiredFields: (next.context.groundingRequirements?.terrainRequiredFields || [])
        .filter((entry) => entry !== terrainField),
    };
  } else if (["currentLocationObservation", "destination", "eventLocation", "date", "timeWindow"].includes(field)) {
    next.context.weather = null;
    next.context.groundingRequirements = {
      ...next.context.groundingRequirements,
      weatherRequired: false,
      weatherLocationField: null,
    };
  }
  return next;
}
'''
replace_once(coordinator, old_disable, new_disable)

regex_replace_once(
    coordinator,
    r'function applySafeStatePatch\(state, statePatch = \{\}\) \{.*?\n\}\n\nfunction applyAcceptedResult',
    '''function applySafeStatePatch(state, statePatch = {}) {
  let next = clone(state);
  if (statePatch.scenarioMode === "restore" && statePatch.scenarioReferenceId) next = restoreScenarioSnapshotV2(next, statePatch.scenarioReferenceId);
  else if (statePatch.scenarioMode === "new") next = beginNewScenarioV2(next);
  const context = statePatch.context || {};
  for (const key of ["activity", "date", "timeWindow", "terrain", "environment"]) {
    if (Object.prototype.hasOwnProperty.call(context, key)) next.context[key] = clone(context[key]);
  }
  if (Object.prototype.hasOwnProperty.call(context, "groundingRequirements")) {
    const incoming = clone(context.groundingRequirements || {});
    const serverOwnedTerrain = new Set(next.context.groundingRequirements?.terrainRequiredFields || []);
    incoming.terrainRequiredFields = (incoming.terrainRequiredFields || [])
      .filter((field) => serverOwnedTerrain.has(field));
    next.context.groundingRequirements = incoming;
  }
  const memory = statePatch.conversationMemory || {};
  for (const key of ["communicatedWarnings", "rejectedWardrobeItemIds", "rejectedShoppingOptionIds", "userCorrections", "acceptedCompromises"]) {
    if (Object.prototype.hasOwnProperty.call(memory, key)) next.conversationMemory[key] = bounded(memory[key]);
  }
  if (Object.prototype.hasOwnProperty.call(statePatch, "pendingAction")) next.conversationMemory.pendingAction = clone(statePatch.pendingAction);
  if (statePatch.shopping) next.shopping = {...next.shopping, ...clone(statePatch.shopping)};
  return next;
}

function applyAcceptedResult''',
)

regex_replace_once(
    coordinator,
    r'      const pendingQuestion = workingState\.conversationMemory\.pendingQuestion;\n      const pendingField = pendingQuestion\?\.field;\n      if \(!decision && \["destination", "eventLocation"\]\.includes\(pendingField\)\) \{.*?\n      \}\n\n      // The common flow after answering the one location question',
    '''      const pendingQuestion = workingState.conversationMemory.pendingQuestion;
      const pendingField = pendingQuestion?.field;
      const pendingDisposition = pendingField ? pendingLocationReplyDispositionV2(request.latestUserInput) : null;

      // "Neviem", "preskoč" and equivalent replies work for every clarification,
      // not only locations. Persist that the user does not know the fact so the
      // same field cannot become another questionnaire turn later in the scenario.
      if (!decision && pendingField && !["destination", "eventLocation"].includes(pendingField)) {
        if (pendingDisposition === "defer") {
          workingState.conversationMemory.pendingQuestion = null;
          decision = deferredPendingDecisionV2();
        } else if (pendingDisposition === "skip") {
          workingState = skipPendingClarificationV2(workingState, pendingField);
          pendingLocationContinuation = true;
        }
      }

      if (!decision && ["destination", "eventLocation"].includes(pendingField)) {
        const disposition = pendingDisposition;
        if (disposition === "why") {
          decision = whyLocationClarificationDecision(pendingField);
        } else if (disposition === "defer") {
          workingState.conversationMemory.pendingQuestion = null;
          decision = deferredPendingDecisionV2();
        } else if (disposition === "skip") {
          workingState = skipPendingClarificationV2(workingState, pendingField);
          pendingLocationContinuation = true;
        } else if (disposition === "location") {
          const resolution = await resolvePendingLocationAnswerV2(locationResolver, pendingQuestion, request.latestUserInput);
          if (!resolution.resolved) {
            // Exact weather is optional after the user has already answered the
            // one useful location question. A geocoder miss is a tool failure,
            // not a reason to trap the conversation in another questionnaire.
            rememberPendingLocationAttemptV2(workingState, pendingField, request.latestUserInput);
            workingState = skipPendingClarificationV2(workingState, pendingField);
            pendingLocationContinuation = true;
          } else if (locationIsTooBroadForWeatherV2(resolution.resolved)) {
            // One location clarification is enough. Keep the broad place as useful
            // semantic context, but continue without pretending we have precise
            // local weather instead of asking the user for yet another place.
            rememberPendingLocationAttemptV2(workingState, pendingField, request.latestUserInput);
            workingState.context[pendingField] = resolution.resolved;
            workingState.conversationMemory.answeredClarificationFields[pendingField] = clone(resolution.resolved);
            workingState = disableOptionalWeatherGroundingV2(workingState);
            pendingLocationContinuation = true;
          } else {
            workingState.context[pendingField] = resolution.resolved;
            workingState.conversationMemory.answeredClarificationFields[pendingField] = clone(resolution.resolved);
            workingState.conversationMemory.pendingQuestion = null;
            workingState = applyHelpFirstDefaultsV2(workingState);
            toolResults.resolvedLocations.push({targetField: pendingField, location: clone(resolution.resolved)});
            const missing = highestPriorityMissingGroundingV2(workingState);
            if (missing) decision = clarificationDecision(missing);
            else pendingLocationContinuation = true;
          }
        }
      }

      // The common flow after answering the one location question''',
)

# Export the helper for deterministic torture tests.
replace_once(
    coordinator,
    '  resolvePendingLocationAnswerV2,\n  unresolvedLocationClarificationDecision,',
    '  resolvePendingLocationAnswerV2,\n  skipPendingClarificationV2,\n  unresolvedLocationClarificationDecision,',
)

# 4) Prompt-level alignment: the model should not fight the deterministic guard.
model = ROOT / "functions/stylist/v2/openai_stylist_model_port_v2.js"
planner_anchor = '    "pendingQuestion je iba kontext. Ak používateľ odpovie otázkou typu \'načo ti to je?\', \'prečo?\', povie \'neviem\', \'je mi to jedno\', \'preskoč to\' alebo \'daj mi proste outfit\', NESMIEŠ tú vetu interpretovať ako hodnotu pending poľa.",\n'
planner_insert = planner_anchor + '    "Ak answeredClarificationFields pri poli obsahuje status=unknown, používateľ tento fakt nevie alebo ho preskočil. V tom istom scenári sa na toto pole už NIKDY nepýtaj; pokračuj konzervatívne.",\n    "terrainRequiredFields sú server-owned safety požiadavky, nie zoznam otázok pre používateľa. Nepridávaj surface/difficulty/condition iba na zlepšenie rady; neznámy terén má typicky viesť ku konzervatívnejšej obuvi/vrstvám, nie k ďalšej otázke.",\n'
replace_once(model, planner_anchor, planner_insert)
final_anchor = '    "HLAVNÉ PRAVIDLO: HELP FIRST, CLARIFY ONLY WHEN NECESSARY. Keď vieš bezpečne odporučiť rozumný outfit, urob to namiesto ďalšej otázky.",\n'
final_insert = final_anchor + '    "Ak používateľ niektorú clarification odmietol alebo nevie (answeredClarificationFields status=unknown), tú istú otázku neopakuj. Urob bezpečný konzervatívny predpoklad a dokonči pomoc.",\n    "Neznámy povrch/náročnosť/condition pri bežnej túre nie je automaticky dôvod na výsluch. Ak nie je explicitný safety red flag, vyber konzervatívnejšiu vhodnú obuv a vysvetli kompromis.",\n'
replace_once(model, final_anchor, final_insert)

# 5) Update Phase-0 acceptance: one useful location question, no terrain questionnaire.
acceptance = ROOT / "functions/stylist/v2/stylist_v2_phase0_acceptance.test.js"
new_scenario_a = r'''test("Scenario A asks one material hiking location question and never turns unknown terrain into a questionnaire", async () => {
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
      // Deliberately simulate an over-eager planner. The coordinator must not
      // let it create a terrain questionnaire that the server did not require.
      groundingRequirements: {
        weatherRequired: true,
        weatherLocationField: "destination",
        terrainRequiredFields: ["difficulty"],
      },
    },
  });
  const generationResult = {
    action: "generate_outfit",
    assistantText: "Na túru volím tričko, rifle a turistické topánky; pri neznámom teréne idem konzervatívnejšie.",
    resultingOutfit: {
      itemIds: ["shirt", "jeans", "hiking-boots"],
      selectionReasonsByItemId: {
        shirt: "priedušná vrstva na dennú túru",
        jeans: "krytie nôh na trase",
        "hiking-boots": "konzervatívna stabilná turistická obuv pri neznámom teréne",
      },
    },
    display: {kind: "outfit", itemIds: ["shirt", "jeans", "hiking-boots"]},
  };
  const h = harness({modelResults: [
    firstPlanningFinal,
    finalEnvelope(generationResult),
  ]});

  const first = await h.coordinator.resolveTurn(request("chat-a", "a-1", 0,
    "Zajtra idem na túru, potrebujem outfit.", {
      freshClientObservations: {currentLocationObservation: martin},
    }));
  assert.equal(first.action, "clarify");
  assert.equal(first.clarification.field, "destination");
  let saved = await h.sessionRepository.read("chat-a");
  assert.deepEqual(saved.context.groundingRequirements.terrainRequiredFields, []);

  const reopened = createStylistTurnCoordinatorV2(h.ports);
  const second = await reopened.resolveTurn(request("chat-a", "a-2", 1, "Vysoké Tatry."));
  assert.equal(second.action, "generate_outfit");
  assert.deepEqual(second.display.itemIds, second.resultingOutfit.itemIds);
  assert.equal((second.assistantText.match(/\?/g) || []).length, 0);

  saved = await h.sessionRepository.read("chat-a");
  assert.equal(saved.context.destination.providerId, "place:tatras");
  assert.deepEqual(saved.context.terrain, {surface: null, difficulty: null, condition: null});
  assert.deepEqual(saved.context.groundingRequirements.terrainRequiredFields, []);
  assert.equal(h.ledger.calls("weather", "getForecast").length, 1);
  assert.equal(h.ledger.calls("model", "plan").length, 1);
  assert.equal(h.ledger.calls("model", "final").length, 1);
});

'''
regex_replace_once(
    acceptance,
    r'test\("Scenario A keeps GPS separate, asks only material hiking facts, and retrieves before final selection".*?\n\}\);\n\ntest\("Scenario B',
    new_scenario_a + 'test("Scenario B',
)

# 6) Conversation torture suite: reproduce the phone failure and harden generic skip semantics.
torture = ROOT / "functions/stylist/v2/stylist_help_first_torture_v2.test.js"
torture.write_text(r'''"use strict";

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
    modelResults: [
      toolEnvelope([
        {tool: "location", query: "Rakúska", targetField: "destination"},
      ], {
        context: {
          activity: {id: "hiking", label: "túra", source: "user"},
          date: {dateKey: "2026-09-11", source: "user"},
          timeWindow: {key: "day", label: "cez deň", source: "help_first_default"},
          // Simulate the exact over-eager planner behavior that caused the bug.
          groundingRequirements: {
            weatherRequired: true,
            weatherLocationField: "destination",
            terrainRequiredFields: ["surface"],
          },
        },
      }),
      hikingOutfitEnvelope(),
    ],
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
  assert.equal(h.ledger.calls("model", "plan").length, 1);
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
''', encoding="utf-8")

print("Applied help-first clarification fix and torture suite")
