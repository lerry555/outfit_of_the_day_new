"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  MAX_SESSION_POOL_CANDIDATES,
  ShoppingSessionStoreError,
  createMemoryShoppingSessionStore,
} = require("./shopping_session_store");

function session(count = 1) {
  const ids = Array.from({length: count}, (_, index) => `v${index}`);
  return {
    sessionId: "opaque", ownerUid: "owner", createdAt: 1, updatedAt: 1,
    expiresAt: 1_000_000, version: 0,
    query: {queryId: "q", sessionId: "intent", revision: 1, constraints: []},
    searchMeta: {queryId: "q", queryRevision: 1, catalogRevision: "catalog",
      completeness: "COMPLETE", exactResultCount: count, diagnostics: null},
    pool: {queryId: "q", queryRevision: 1, catalogRevision: "catalog",
      orderedCandidateIds: ids, shownCandidateIds: [], rejectedCandidateIds: [], cursor: 0},
  };
}

test("bounded pool fails closed rather than truncating completeness", async () => {
  const store = createMemoryShoppingSessionStore({now: () => 1});
  await assert.rejects(store.put(session(MAX_SESSION_POOL_CANDIDATES + 1)),
    (error) => error instanceof ShoppingSessionStoreError &&
      error.code === "RESULT_POOL_TOO_LARGE");
});

test("memory store remains injectable with owner and version guards", async () => {
  const store = createMemoryShoppingSessionStore({now: () => 1});
  await store.createSession({session: session()});
  await assert.rejects(store.mutate("opaque", {ownerUid: "other"}, (value) =>
    ({session: value, result: {}})), (error) => error.code === "SESSION_FORBIDDEN");
  const updated = await store.mutate("opaque", {ownerUid: "owner", expectedVersion: 0},
    (value) => ({session: value, result: {ok: true}}));
  assert.equal(updated.session.version, 1);
  await assert.rejects(store.mutate("opaque", {ownerUid: "owner", expectedVersion: 0},
    (value) => ({session: value, result: {}})), (error) => error.code === "SESSION_CONFLICT");
});
