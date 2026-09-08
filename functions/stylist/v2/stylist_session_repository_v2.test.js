"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  bootstrapExistingChatV2,
  clone,
  createEmptySessionStateV2,
} = require("./stylist_session_state_v2");
const {
  StylistSessionRepositoryV2Error,
  createMemoryStylistSessionRepositoryV2,
} = require("./stylist_session_repository_v2");

function result(turnId, revision, text = "ok") {
  return {turnId, resultingSessionRevision: revision, action: "chat", assistantText: text};
}

function nextState(state, turnId, response) {
  const next = clone(state);
  next.revision = state.revision + 1;
  next.replay.turns = [...next.replay.turns, {turnId, result: clone(response)}];
  return next;
}

test("ensure is idempotent and legacy bootstrap preserves only explicit durable truth", async () => {
  let now = 1000;
  const repo = createMemoryStylistSessionRepositoryV2({now: () => now});
  const first = await repo.ensureFromLegacy({
    uid: "owner",
    chatId: "chat-1",
    bootstrapInput: {
      currentOutfitItemIds: ["shirt", "jeans"],
      persistedSelectionReasonsByItemId: {shirt: "persisted shirt", jeans: "persisted jeans"},
      knownExplicitDurableChoices: {activity: {id: "city_walk"}},
    },
  });
  assert.equal(first.created, true);
  assert.deepEqual(first.state.currentOutfit.itemIds, ["shirt", "jeans"]);
  assert.equal(first.state.currentOutfit.selectionReasonsByItemId.jeans, "persisted jeans");
  assert.deepEqual(first.state.context.activity, {id: "city_walk"});
  assert.equal(first.state.context.destination, null);
  assert.equal(first.state.context.weather, null);
  assert.equal(first.state.conversationMemory.pendingAction, null);

  now = 2000;
  const second = await repo.ensure({
    uid: "owner",
    chatId: "chat-1",
    bootstrapState: createEmptySessionStateV2("chat-1"),
  });
  assert.equal(second.created, false);
  assert.deepEqual(second.state.currentOutfit.itemIds, ["shirt", "jeans"]);
  assert.equal(second.createdAt, first.createdAt);
  assert.equal(second.updatedAt, first.updatedAt);
});

test("commit is compare-and-swap, stores exact replay, and duplicate turn wins before stale revision", async () => {
  let now = 1000;
  const repo = createMemoryStylistSessionRepositoryV2({now: () => now});
  const created = await repo.ensure({uid: "owner", chatId: "chat-2"});
  const response = result("turn-1", 1, "first");
  const proposed = nextState(created.state, "turn-1", response);
  now = 1100;
  const committed = await repo.commitTurn({
    uid: "owner",
    chatId: "chat-2",
    turnId: "turn-1",
    expectedRevision: 0,
    nextState: proposed,
    result: response,
  });
  assert.equal(committed.replayed, false);
  assert.equal(committed.resultingSessionRevision, 1);
  const stored = await repo.get({uid: "owner", chatId: "chat-2"});
  assert.equal(stored.state.revision, 1);
  assert.deepEqual(stored.state.replay.turns.at(-1), {turnId: "turn-1", result: response});

  const duplicate = await repo.commitTurn({
    uid: "owner",
    chatId: "chat-2",
    turnId: "turn-1",
    expectedRevision: 0,
    nextState: proposed,
    result: response,
  });
  assert.equal(duplicate.replayed, true);
  assert.deepEqual(duplicate.result, response);
});

test("two competing turns at one revision cannot both commit", async () => {
  const repo = createMemoryStylistSessionRepositoryV2();
  const created = await repo.ensure({uid: "owner", chatId: "chat-race"});
  const leftResult = result("left", 1, "left");
  const rightResult = result("right", 1, "right");
  const outcomes = await Promise.allSettled([
    repo.commitTurn({uid: "owner", chatId: "chat-race", turnId: "left", expectedRevision: 0,
      nextState: nextState(created.state, "left", leftResult), result: leftResult}),
    repo.commitTurn({uid: "owner", chatId: "chat-race", turnId: "right", expectedRevision: 0,
      nextState: nextState(created.state, "right", rightResult), result: rightResult}),
  ]);
  assert.equal(outcomes.filter((item) => item.status === "fulfilled").length, 1);
  const rejected = outcomes.find((item) => item.status === "rejected");
  assert.equal(rejected.reason instanceof StylistSessionRepositoryV2Error, true);
  assert.equal(rejected.reason.code, "SESSION_CONFLICT");
});

test("commit rejects missing or mismatched replay receipt before persistence", async () => {
  const repo = createMemoryStylistSessionRepositoryV2();
  const created = await repo.ensure({uid: "owner", chatId: "chat-bad"});
  const response = result("turn-1", 1);
  const missingReplay = clone(created.state);
  missingReplay.revision = 1;
  await assert.rejects(repo.commitTurn({
    uid: "owner", chatId: "chat-bad", turnId: "turn-1", expectedRevision: 0,
    nextState: missingReplay, result: response,
  }), (error) => error.code === "TURN_RECEIPT_MALFORMED");
  const still = await repo.get({uid: "owner", chatId: "chat-bad"});
  assert.equal(still.state.revision, 0);
});

test("repository identity is path-bound and malformed IDs fail closed", async () => {
  const repo = createMemoryStylistSessionRepositoryV2();
  await repo.ensure({uid: "owner", chatId: "chat-owner"});
  assert.equal(await repo.get({uid: "other", chatId: "chat-owner"}), null);
  await assert.rejects(repo.ensure({uid: "owner/other", chatId: "bad"}),
    (error) => error.code === "SESSION_MALFORMED");
});

test("bootstrap helper remains compatible with Phase-0 state contract", () => {
  const state = bootstrapExistingChatV2({
    chatId: "compat",
    currentOutfitItemIds: ["shirt"],
    persistedSelectionReasonsByItemId: {shirt: "known reason"},
  });
  assert.equal(state.revision, 0);
  assert.equal(state.currentOutfit.revision, 1);
});

test("Phase-1 access contract keeps session owner-readable and turn receipts server-only", () => {
  const {intendedClientAccessV2} = require("./firestore_rules_contract_v2");
  assert.equal(intendedClientAccessV2({operation: "get", authenticatedUid: "u", pathUid: "u"}), true);
  assert.equal(intendedClientAccessV2({operation: "update", authenticatedUid: "u", pathUid: "u"}), false);
  assert.equal(intendedClientAccessV2({operation: "get", authenticatedUid: "u", pathUid: "u",
    resourceKind: "turn"}), false);
});
