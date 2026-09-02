"use strict";

// Offline integration test. Refuse to run against any production database.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {initializeTestEnvironment, assertFails} = require("@firebase/rules-unit-testing");
const {doc, setDoc, getDoc} = require("firebase/firestore");
const admin = require("firebase-admin");
const {createIdempotentTaskRunnerV1} = require("./idempotent_task_v1");

let env;
let app;
let db;
test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "emulator_required_no_production_access");
  const projectId = "demo-ootd-cost-controls";
  env = await initializeTestEnvironment({projectId,
    firestore: {rules: fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")}});
  app = admin.initializeApp({projectId}, "cost-controls-emulator");
  db = app.firestore();
});
test.after(async () => {
  await env?.cleanup();
  await app?.delete();
});

test("existing rules deny all client reads and writes to the cost/control collections", async () => {
  for (const name of ["aiUsageEventsV1", "aiTaskRunsV1", "aiExactResultCachesV1"]) {
    await db.collection(name).doc("test").set({owner: "owner", status: "complete"});
    for (const client of [env.unauthenticatedContext(), env.authenticatedContext("owner")]) {
      const ref = doc(client.firestore(), name, "test");
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, {status: "complete", result: {fake: true}}));
    }
  }
});

test("Firestore transactions admit one concurrent request and persist replay result", async () => {
  const runner = () => createIdempotentTaskRunnerV1({db, logger: {warn() {}}});
  let calls = 0;
  const task = {uid: "owner", feature: "chat", requestId: "concurrent-job", payload: {message: "hello"},
    execute: async () => { calls++; return {reply: "hello"}; }};
  const results = await Promise.allSettled([runner()(task), runner()(task), runner()(task)]);
  assert.equal(calls, 1);
  assert.ok(results.some((result) => result.status === "fulfilled"));
  assert.deepEqual(await runner()(task), {result: {reply: "hello"}, replayed: true});
  await assert.rejects(runner()({...task, payload: {message: "changed"}}), {code: "request_id_conflict"});
});
