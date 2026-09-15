"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {createStylistOneBrainEngineV2} = require("./stylist_one_brain_engine_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");
const {createDeterministicShellBrainV2} = require("./stylist_production_bridge_one_brain_v2");

const NOW = Date.parse("2026-09-15T12:00:00.000Z");

function request() {
  return {
    chatId: "production-wiring-missing-location",
    turnId: "turn-1",
    expectedSessionRevision: 0,
    latestUserInput: "zajtra idem na túru potrebujem outfit",
    explicitUiActionId: null,
    freshClientObservations: {},
    clientCapabilities: {
      shoppingEnabled: false,
      supportsProgress: true,
      todayDateKey: "2026-09-15",
      tomorrowDateKey: "2026-09-16",
      timezoneOffsetMinutes: 120,
      recentHistory: [],
    },
  };
}

test("production One-Brain wiring clarifies missing hiking destination without a model call", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  let delegatedBrainCalls = 0;
  const rawBrain = {
    async brainTurn() {
      delegatedBrainCalls += 1;
      return {
        kind: "final",
        pendingReplyDisposition: "none",
        statePatch: {},
        result: {
          action: "generate_outfit",
          assistantText: "This must never be reached for the deterministic clarification.",
          resultingOutfit: {
            itemIds: ["shirt", "pants", "shoes"],
            selectionReasonsByItemId: {
              shirt: "test",
              pants: "test",
              shoes: "test",
            },
          },
          display: {kind: "outfit", itemIds: ["shirt", "pants", "shoes"]},
        },
      };
    },
  };
  const stylistBrain = createDeterministicShellBrainV2(rawBrain);
  const engine = createStylistOneBrainEngineV2({
    sessionRepository: repository,
    wardrobeTool: {
      async retrieve() { throw new Error("wardrobe must not be queried"); },
    },
    locationResolver: {
      async resolve() { throw new Error("location resolver must not be queried"); },
    },
    weatherTool: {
      async getForecast() { throw new Error("weather must not be queried"); },
    },
    shoppingTool: {
      async search() { throw new Error("shopping must not be queried"); },
    },
    stylistBrain,
    clock: () => NOW,
  });

  const result = await engine.resolveTurn({
    uid: "qa-user",
    request: request(),
    bootstrapInput: {
      currentOutfitItemIds: [],
      persistedSelectionReasonsByItemId: {},
      knownExplicitDurableChoices: {},
    },
  });

  assert.equal(delegatedBrainCalls, 0);
  assert.equal(result.action, "clarify");
  assert.equal(result.assistantText, "Kam približne ideš?");
  assert.equal(result.clarification.field, "destination");
  assert.equal(result.clarification.resumeAction, "generate_outfit");
  assert.equal(result.resultingSessionRevision, 1);
});
