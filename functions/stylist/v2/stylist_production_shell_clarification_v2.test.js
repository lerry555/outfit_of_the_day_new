"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createEmptySessionStateV2} = require("./stylist_session_state_v2");
const {createDeterministicShellBrainV2} = require("./stylist_production_bridge_one_brain_v2");

function input(message, session = createEmptySessionStateV2("shell-clarification")) {
  return {
    stage: "tools",
    request: {
      chatId: "shell-clarification",
      turnId: "turn-1",
      latestUserInput: message,
      explicitUiActionId: null,
      clientCapabilities: {
        todayDateKey: "2026-09-15",
        tomorrowDateKey: "2026-09-16",
        recentHistory: [],
      },
    },
    session,
    toolResults: {wardrobeItems: []},
    runtimeConstraints: {allowClarification: true},
  };
}

test("production shell asks destination before One-Brain for obvious tomorrow hiking outfit", async () => {
  let delegated = 0;
  const brain = createDeterministicShellBrainV2({
    async brainTurn() {
      delegated += 1;
      return {kind: "final", result: {action: "chat", assistantText: "unexpected"}, statePatch: {}};
    },
  });

  const result = await brain.brainTurn(input("zajtra idem na túru potrebujem outfit"));

  assert.equal(delegated, 0);
  assert.equal(result.kind, "final");
  assert.equal(result.result.action, "clarify");
  assert.equal(result.result.assistantText, "Kam približne ideš?");
  assert.equal(result.result.clarification.field, "destination");
  assert.equal(result.result.clarification.resumeAction, "generate_outfit");
  assert.equal(result.statePatch.context.activity.id, "hiking");
  assert.equal(result.statePatch.context.date.dateKey, "2026-09-16");
  assert.equal(result.statePatch.context.timeWindow.key, "day");
  assert.equal(result.statePatch.context.groundingRequirements.weatherRequired, true);
  assert.equal(result.statePatch.context.groundingRequirements.weatherLocationField, "destination");
});

test("production shell delegates when the same hiking request already contains a destination", async () => {
  let delegated = 0;
  const expected = {kind: "final", result: {action: "chat", assistantText: "delegated"}, statePatch: {}};
  const brain = createDeterministicShellBrainV2({
    async brainTurn() {
      delegated += 1;
      return expected;
    },
  });

  const result = await brain.brainTurn(input("zajtra idem na túru do Tatier potrebujem outfit"));

  assert.equal(delegated, 1);
  assert.equal(result, expected);
});

test("production shell does not replace an already grounded destination", async () => {
  let delegated = 0;
  const session = JSON.parse(JSON.stringify(createEmptySessionStateV2("grounded-shell")));
  session.context.destination = {
    providerId: "place:tatras",
    label: "Vysoké Tatry",
    lat: 49.1667,
    lng: 20.1333,
    source: "test",
    granularity: "locality",
  };
  const brain = createDeterministicShellBrainV2({
    async brainTurn() {
      delegated += 1;
      return {kind: "final", result: {action: "chat", assistantText: "delegated"}, statePatch: {}};
    },
  });

  const result = await brain.brainTurn(input("zajtra idem na túru potrebujem outfit", session));

  assert.equal(delegated, 1);
  assert.equal(result.result.assistantText, "delegated");
});
