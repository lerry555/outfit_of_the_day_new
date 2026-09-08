"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {deleteDoc, doc, getDoc, setDoc} = require("firebase/firestore");
const {clone, createEmptySessionStateV2} = require("./stylist_session_state_v2");
const {
  StylistSessionRepositoryV2Error,
  createFirestoreStylistSessionRepositoryV2,
} = require("./stylist_session_repository_v2");

const PROJECT_ID = "demo-ootd-rules-9cr";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");
let environment;
let appSerial = 0;

function adminRepository() {
  const app = initializeApp({projectId: PROJECT_ID}, `stylist-v2-${appSerial++}`);
  return {app, repository: createFirestoreStylistSessionRepositoryV2(getFirestore(app))};
}

function acceptedTurn(state, turnId, assistantText = "ok") {
  const result = {
    turnId,
    resultingSessionRevision: state.revision + 1,
    action: "chat",
    assistantText,
  };
  const next = clone(state);
  next.revision += 1;
  next.replay.turns = [...next.replay.turns, {turnId, result: clone(result)}];
  return {nextState: next, result};
}

test.before(async () => {
  environment = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: fs.readFileSync(RULES_PATH, "utf8")},
  });
});

test.after(async () => { await environment?.cleanup(); });
test.beforeEach(async () => { await environment.clearFirestore(); });

test("owner can read canonical session but cannot mutate it; turn receipts are server-only", async () => {
  const fixture = adminRepository();
  await fixture.repository.ensure({uid: "owner", chatId: "chat-1"});
  const stored = await fixture.repository.get({uid: "owner", chatId: "chat-1"});
  const turn = acceptedTurn(stored.state, "turn-1");
  await fixture.repository.commitTurn({
    uid: "owner", chatId: "chat-1", turnId: "turn-1", expectedRevision: 0,
    nextState: turn.nextState, result: turn.result,
  });

  const owner = environment.authenticatedContext("owner").firestore();
  const other = environment.authenticatedContext("other").firestore();
  const sessionRef = doc(owner, "users/owner/stylistSessionsV2/chat-1");
  const turnRef = doc(owner, "users/owner/stylistSessionsV2/chat-1/turns/turn-1");

  const ownerRead = await assertSucceeds(getDoc(sessionRef));
  assert.equal(ownerRead.exists(), true);
  await assertFails(getDoc(doc(other, "users/owner/stylistSessionsV2/chat-1")));
  await assertFails(setDoc(sessionRef, {revision: 999}, {merge: true}));
  await assertFails(deleteDoc(sessionRef));
  await assertFails(getDoc(turnRef));
  await assertFails(setDoc(turnRef, {forged: true}));

  await deleteApp(fixture.app);
});

test("session survives fresh repository instances and duplicate turn replays exactly once", async () => {
  const first = adminRepository();
  const created = await first.repository.ensure({
    uid: "owner",
    chatId: "chat-durable",
    bootstrapState: createEmptySessionStateV2("chat-durable"),
  });
  const turn = acceptedTurn(created.state, "stable-turn", "persisted result");
  const committed = await first.repository.commitTurn({
    uid: "owner", chatId: "chat-durable", turnId: "stable-turn", expectedRevision: 0,
    nextState: turn.nextState, result: turn.result,
  });
  assert.equal(committed.replayed, false);

  const second = adminRepository();
  const reopened = await second.repository.get({uid: "owner", chatId: "chat-durable"});
  assert.equal(reopened.state.revision, 1);
  assert.deepEqual(reopened.state.replay.turns.at(-1).result, turn.result);

  const replay = await second.repository.commitTurn({
    uid: "owner", chatId: "chat-durable", turnId: "stable-turn", expectedRevision: 0,
    nextState: turn.nextState, result: turn.result,
  });
  assert.equal(replay.replayed, true);
  assert.deepEqual(replay.result, turn.result);

  await deleteApp(first.app);
  await deleteApp(second.app);
});

test("two different turns at the same revision serialize with one conflict", async () => {
  const fixture = adminRepository();
  const created = await fixture.repository.ensure({uid: "owner", chatId: "chat-race"});
  const left = acceptedTurn(created.state, "left", "left");
  const right = acceptedTurn(created.state, "right", "right");

  const outcomes = await Promise.allSettled([
    fixture.repository.commitTurn({
      uid: "owner", chatId: "chat-race", turnId: "left", expectedRevision: 0,
      nextState: left.nextState, result: left.result,
    }),
    fixture.repository.commitTurn({
      uid: "owner", chatId: "chat-race", turnId: "right", expectedRevision: 0,
      nextState: right.nextState, result: right.result,
    }),
  ]);

  assert.equal(outcomes.filter((item) => item.status === "fulfilled").length, 1);
  const rejected = outcomes.find((item) => item.status === "rejected");
  assert.equal(rejected.reason instanceof StylistSessionRepositoryV2Error, true);
  assert.equal(rejected.reason.code, "SESSION_CONFLICT");
  const finalState = await fixture.repository.get({uid: "owner", chatId: "chat-race"});
  assert.equal(finalState.state.revision, 1);

  await deleteApp(fixture.app);
});
