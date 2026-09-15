"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createStylistOneBrainEngineV2,
} = require("./stylist_one_brain_engine_v2");
const {
  createMemoryStylistSessionRepositoryV2,
} = require("./stylist_session_repository_v2");

test("forced broad-country clarification survives Brain scenarioMode=new in durable session", async () => {
  const uid = "user_country_parent";
  const chatId = "chat_country_parent";
  const repository = createMemoryStylistSessionRepositoryV2();
  await repository.ensure({uid, chatId});

  let brainSession = null;
  const stylistBrain = {
    async brainTurn(input) {
      brainSession = input.session;
      assert.equal(input.stage, "tools");
      assert.equal(input.runtimeConstraints.forcedClarificationField, "destination");
      assert.equal(input.session.context.destination?.countryCode, "US");
      return {
        kind: "final",
        pendingReplyDisposition: "none",
        statePatch: {
          scenarioMode: "new",
          scenarioReferenceId: null,
          context: {
            activity: {id: "hiking", label: "túra", source: "user"},
            date: {dateKey: "2026-09-16", source: "user"},
            timeWindow: {key: "day", label: "cez deň", source: "one_brain_default"},
            terrain: {surface: null, difficulty: null, condition: null},
            environment: "outdoor",
            groundingRequirements: {
              weatherRequired: true,
              weatherLocationField: "destination",
              terrainRequiredFields: [],
            },
          },
        },
        result: {
          action: "chat",
          assistantText: "Rozumiem.",
          display: {kind: "none", itemIds: []},
        },
      };
    },
  };

  const engine = createStylistOneBrainEngineV2({
    sessionRepository: repository,
    wardrobeTool: {async retrieve() { return []; }},
    locationResolver: {async resolve() { throw new Error("network resolver must not be needed for local USA country hint"); }},
    weatherTool: {async getForecast() { throw new Error("broad country must not fetch weather yet"); }},
    shoppingTool: {async search() { return {candidateIds: []}; }},
    stylistBrain,
  });

  const result = await engine.resolveTurn({
    uid,
    request: {
      chatId,
      turnId: "turn_country_parent_1",
      expectedSessionRevision: 0,
      latestUserInput: "zajtra idem do USA na túru a potrebujem outfit",
      explicitUiActionId: null,
      freshClientObservations: {},
      clientCapabilities: {
        todayDateKey: "2026-09-15",
        tomorrowDateKey: "2026-09-16",
      },
    },
  });

  assert.equal(result.action, "clarify");
  assert.equal(result.clarification?.field, "destination");
  assert.ok(brainSession);

  const saved = await repository.get({uid, chatId});
  assert.equal(saved.state.revision, 1);
  assert.equal(saved.state.context.destination?.granularity, "country");
  assert.equal(saved.state.context.destination?.countryCode, "US");
  assert.match(saved.state.context.destination?.label || "", /Spojené štáty|United States/iu);
  assert.deepEqual(
    saved.state.conversationMemory.answeredClarificationFields.destination,
    saved.state.context.destination,
  );
  assert.equal(saved.state.conversationMemory.pendingQuestion?.field, "destination");
  assert.equal(saved.state.conversationMemory.pendingQuestion?.resumeAction, "generate_outfit");
  assert.equal(saved.state.context.groundingRequirements.weatherRequired, true);
  assert.equal(saved.state.context.groundingRequirements.weatherLocationField, "destination");
});
