"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {createAdminFirestoreTransactionRunner} =
  require("./wardrobe_admin_firestore_transactional_store");
const {createMemoryTransactionalStore, AUTHORITY_KEY, ENVELOPE_KEY} =
  require("./wardrobe_profile_firestore_repository");
const {createFakeStorageMetadataClient} =
  require("./trusted_storage_metadata_adapter");
const {createFakeTrustedVisionAnalysisClient} =
  require("./trusted_vision_analysis_client");
const {handleQualificationAuthorityEndpoint} =
  require("./wardrobe_qualification_authority_endpoint");
const {RUNTIME_POLICIES} = require("./trusted_vision_result_provenance");

const UID = "controlled-user";
const ITEM = "controlled-item";
const STORAGE = "wardrobe/controlled-user/item.jpg";
const GENERATION = "1700000000000000";
const SERVER_TIME = "2026-08-06T15:00:00.000Z";
const CLIENT_TIME = "1999-01-01T00:00:00.000Z";
const KEY = `users/${UID}/wardrobe/${ITEM}`;

function buildRuntime({runtime, document} = {}) {
  const memory = createMemoryTransactionalStore({[KEY]: document || {
    name: "Tank", storagePath: STORAGE,
  }});
  let transactionCount = 0;
  const store = {
    _get: memory._get.bind(memory),
    _dump: memory._dump.bind(memory),
    async runTransaction(uid, itemId, callback) {
      transactionCount++;
      return memory.runTransaction(uid, itemId, callback);
    },
  };
  return {store, transactionCount: () => transactionCount, deps: {
    authContext: {authenticated: true, uid: UID, tokenVerified: true,
      emulatorVerified: true, appCheckPresent: true, appCheckVerified: true,
      authType: "firebase_auth"},
    store,
    storageMetadataClient: createFakeStorageMetadataClient({[STORAGE]: {
      generation: GENERATION, metageneration: "1", size: "100",
      contentType: "image/jpeg", updated: SERVER_TIME,
    }}),
    visionClient: createFakeTrustedVisionAnalysisClient(),
    scenarioId: "front_only_garment",
    serverClock: () => SERVER_TIME,
    provenancePolicy: RUNTIME_POLICIES.fixtureOnly,
    ...(runtime ? {runRuntimeOrchestrator: runtime} : {}),
  }};
}

function request(overrides = {}) {
  return {contractVersion: 1, itemId: ITEM,
    action: "analyze_current_source", assignedAt: CLIENT_TIME, ...overrides};
}

test("controlled write uses fixture-free source and has no legacy orchestrator", () => {
  const source = fs.readFileSync(path.join(__dirname,
    "wardrobe_qualification_authority_endpoint.js"), "utf8");
  assert.doesNotMatch(source, /wardrobe_backend_qualification_orchestrator/);
  assert.doesNotMatch(source, /runBackendQualificationOrchestration/);
  assert.match(source, /runLiveParserBackendQualification/);
  assert.match(source, /buildTrustedVisionQualificationInput/);
  assert.match(source, /allocateServerAnalysisIdentity/);
});

test("client assignedAt is ignored and server clock owns persisted timestamps", async () => {
  const x = buildRuntime();
  const result = await handleQualificationAuthorityEndpoint(request(), x.deps);
  assert.equal(result.status, "mutation_applied");
  assert.equal(x.transactionCount(), 1);
  const doc = x.store._dump()[KEY];
  assert.equal(doc[AUTHORITY_KEY].assignedAt, SERVER_TIME);
  assert.equal(doc[AUTHORITY_KEY].sourceUpdatedAt, SERVER_TIME);
  assert.equal(doc[ENVELOPE_KEY].analysis.completedAt, SERVER_TIME);
  assert.equal(doc[ENVELOPE_KEY].metadata.createdAt, SERVER_TIME);
  assert.equal(JSON.stringify(doc).includes(CLIENT_TIME), false);
});

test("lazy authority and profile are written by one final transaction", async () => {
  const x = buildRuntime();
  assert.equal(x.store._dump()[KEY][AUTHORITY_KEY], undefined);
  const result = await handleQualificationAuthorityEndpoint(request(), x.deps);
  assert.equal(result.status, "mutation_applied");
  assert.equal(result.authorityInitialized, true);
  assert.equal(result.wroteProfile, true);
  assert.equal(x.transactionCount(), 1);
  const doc = x.store._dump()[KEY];
  assert.ok(doc[AUTHORITY_KEY]);
  assert.ok(doc[ENVELOPE_KEY]);
});

test("pipeline failure performs zero transaction and zero business writes", async () => {
  const x = buildRuntime({runtime: () => {
    throw new Error("injected_runtime_failure");
  }});
  const before = JSON.stringify(x.store._dump());
  const result = await handleQualificationAuthorityEndpoint(request(), x.deps);
  assert.equal(result.status, "qualification_failed");
  assert.equal(x.transactionCount(), 0);
  assert.equal(JSON.stringify(x.store._dump()), before);
});

test("Admin bridge applies exactly one merge patch inside one transaction", async () => {
  const calls = {transactions: 0, gets: 0, sets: 0};
  const ref = {path: KEY};
  const firestore = {
    collection(name) {
      assert.equal(name, "users");
      return {doc(uid) {
        assert.equal(uid, UID);
        return {collection(child) {
          assert.equal(child, "wardrobe");
          return {doc(item) {
            assert.equal(item, ITEM);
            return ref;
          }};
        }};
      }};
    },
    async runTransaction(body) {
      calls.transactions++;
      return body({
        async get(actual) {
          calls.gets++; assert.equal(actual, ref);
          return {exists: true, data: () => ({name: "Tank"})};
        },
        set(actual, patch, options) {
          calls.sets++; assert.equal(actual, ref);
          assert.deepEqual(patch, {wardrobeProfile: {ok: true}});
          assert.deepEqual(options, {merge: true});
        },
      });
    },
  };
  const run = createAdminFirestoreTransactionRunner({firestore});
  const result = await run(UID, ITEM, async (state) => {
    assert.deepEqual(state, {exists: true, data: {name: "Tank"}});
    return {writePatch: {wardrobeProfile: {ok: true}}, result: {ok: true}};
  });
  assert.deepEqual(result, {ok: true});
  assert.deepEqual(calls, {transactions: 1, gets: 1, sets: 1});
});

test("Admin bridge does not write for a no-write repository decision", async () => {
  let sets = 0;
  const ref = {};
  const firestore = {collection: () => ({doc: () => ({collection: () =>
    ({doc: () => ref})})}), runTransaction: async (body) => body({
    get: async () => ({exists: false, data: () => null}),
    set: () => { sets++; },
  })};
  const result = await createAdminFirestoreTransactionRunner({firestore})(
    UID, ITEM, async () => ({writePatch: null, result: {status: "not_found"}}));
  assert.deepEqual(result, {status: "not_found"});
  assert.equal(sets, 0);
});
