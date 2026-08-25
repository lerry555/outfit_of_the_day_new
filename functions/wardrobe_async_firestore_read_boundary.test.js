"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  READ_CONTRACT,
  createAdminFirestoreTransactionalStore,
  normalizeWardrobeDocumentRead,
} = require("./wardrobe_admin_firestore_transactional_store");
const {
  createMemoryTransactionalStore,
} = require("./wardrobe_profile_firestore_repository");
const {
  runQualificationAuthorityShadow,
} = require("./wardrobe_authority_shadow_runner");
const {
  handleQualificationAuthorityEndpoint,
} = require("./wardrobe_qualification_authority_endpoint");
const {
  createFakeStorageMetadataClient,
} = require("./trusted_storage_metadata_adapter");
const {
  createFakeTrustedVisionAnalysisClient,
} = require("./trusted_vision_analysis_client");
const {
  buildGenerationId,
} = require("./wardrobe_qualification_revision_contract");
const {
  BACKEND_CONTRACT_GRAPH,
} = require("./backend_provider_dependency_graph");

const UID = "user-1";
const ITEM = "item-1";
const PATH = "wardrobe/user-1/item.jpg";
const GENERATION = "7";
const CLOCK = "2026-08-05T10:00:00.000Z";
const SCENARIO = "front_only_garment";

function authContext() {
  return {
    authenticated: true,
    uid: UID,
    tokenVerified: true,
    emulatorVerified: true,
    appCheckPresent: true,
    appCheckVerified: true,
    authType: "firebase_auth",
  };
}

function authorityDocument() {
  return {
    name: "Tank",
    storagePath: PATH,
    qualificationAuthority: {
      contractVersion: 1,
      imageRevision: 1,
      wardrobeItemRevision: 1,
      uploadGeneration: GENERATION,
      generationId: buildGenerationId({
        itemId: ITEM,
        imageRevision: 1,
        sourceStoragePath: PATH,
        sourceObjectGeneration: GENERATION,
        uploadGeneration: GENERATION,
      }),
      sourceStoragePath: PATH,
      sourceObjectGeneration: GENERATION,
      sourceObjectMetageneration: "1",
      sourceImageSha256: null,
      sourceUpdatedAt: CLOCK,
      assignedAt: CLOCK,
    },
  };
}

function storageClient() {
  return createFakeStorageMetadataClient({
    [PATH]: {
      generation: GENERATION,
      metageneration: "1",
      size: "100",
      contentType: "image/jpeg",
      updated: CLOCK,
    },
  });
}

function asyncStore(initialDocument) {
  const memory = createMemoryTransactionalStore(
    initialDocument == null ? {} : {
      [`users/${UID}/wardrobe/${ITEM}`]: initialDocument,
    });
  const store = createAdminFirestoreTransactionalStore({
    runTransaction: memory.runTransaction.bind(memory),
    get: async (uid, itemId) => memory._get(uid, itemId),
  });
  return {memory, store};
}

async function runShadow(store, overrides = {}) {
  return runQualificationAuthorityShadow({
    contractVersion: 1,
    itemId: ITEM,
    action: "analyze_current_source",
    offlineScenarioId: SCENARIO,
  }, {
    authContext: authContext(),
    store,
    storageMetadataClient: storageClient(),
    visionClient: createFakeTrustedVisionAnalysisClient(),
    assignedAt: CLOCK,
    scenarioId: SCENARIO,
    ...overrides,
  });
}

test("read contract identity", () => {
  assert.equal(READ_CONTRACT, "WardrobeDocumentReadStore/v1");
});

test("dependency graph keeps async boundary ready after provenance correction", () => {
  const boundary = BACKEND_CONTRACT_GRAPH.find(
    (item) => item.id === "AsyncFirestoreReadBoundary");
  const orchestrator = BACKEND_CONTRACT_GRAPH.find(
    (item) => item.id === "WardrobeBackendQualificationOrchestrator");
  const productionSwitch = BACKEND_CONTRACT_GRAPH.find(
    (item) => item.id === "ProductionAuthoritySwitch");
  assert.equal(boundary.status, "runtime_ready");
  assert.deepEqual([...boundary.blockers], []);
  assert.ok(!orchestrator.blockers.includes(
    "async_firestore_read_boundary_pending"));
  assert.ok(!orchestrator.blockers.includes(
    "live_model_provenance_gate_pending"));
  assert.equal(productionSwitch.status, "not_started");
  assert.ok(productionSwitch.blockers.includes(
    "controlled_write_canary_retry_pending"));
});

test("snapshot normalization null and undefined", async () => {
  assert.equal(await normalizeWardrobeDocumentRead(null), null);
  assert.equal(await normalizeWardrobeDocumentRead(undefined), null);
});

test("snapshot normalization plain object and Promise plain object", async () => {
  const direct = await normalizeWardrobeDocumentRead({name: "A"});
  const promised = await normalizeWardrobeDocumentRead(
    Promise.resolve({name: "B"}));
  assert.deepEqual(direct, {name: "A"});
  assert.deepEqual(promised, {name: "B"});
});

test("snapshot normalization exists false and exists true", async () => {
  assert.equal(await normalizeWardrobeDocumentRead({
    exists: false,
    data() { return undefined; },
  }), null);
  const document = await normalizeWardrobeDocumentRead({
    exists: true,
    data() { return {name: "A", nested: {value: 1}}; },
  });
  assert.deepEqual(document, {name: "A", nested: {value: 1}});
});

test("snapshot normalization rejects missing data and malformed snapshots", async () => {
  await assert.rejects(() => normalizeWardrobeDocumentRead({
    exists: true,
    data() { return undefined; },
  }), /wardrobe_document_read_snapshot_data_missing/);
  await assert.rejects(() => normalizeWardrobeDocumentRead({exists: true}),
    /wardrobe_document_read_malformed_snapshot/);
  await assert.rejects(() => normalizeWardrobeDocumentRead({
    exists: "yes",
    data() { return {}; },
  }), /wardrobe_document_read_malformed_snapshot/);
  await assert.rejects(() => normalizeWardrobeDocumentRead([]),
    /wardrobe_document_read_invalid_result/);
});

test("snapshot normalization propagates rejected Promise", async () => {
  await assert.rejects(() => normalizeWardrobeDocumentRead(
    Promise.reject(new Error("read_rejected"))), /read_rejected/);
});

test("snapshot normalization clones and deeply freezes document", async () => {
  const source = {name: "A", nested: {value: 1}, list: [{x: 2}]};
  const document = await normalizeWardrobeDocumentRead(source);
  source.nested.value = 9;
  assert.equal(document.nested.value, 1);
  assert.equal(Object.isFrozen(document), true);
  assert.equal(Object.isFrozen(document.nested), true);
  assert.equal(Object.isFrozen(document.list), true);
  assert.throws(() => { document.nested.value = 3; }, TypeError);
});

test("Admin Firestore reader uses exact wardrobe document path", async () => {
  const calls = [];
  const firestore = {
    collection(name) {
      calls.push(name);
      return {
        doc(uid) {
          calls.push(uid);
          return {
            collection(child) {
              calls.push(child);
              return {
                doc(itemId) {
                  calls.push(itemId);
                  return {get: async () => ({
                    exists: true,
                    data: () => ({name: "A"}),
                  })};
                },
              };
            },
          };
        },
      };
    },
  };
  const store = createAdminFirestoreTransactionalStore({
    firestore,
    runTransaction: async () => null,
  });
  assert.deepEqual(await store._get(UID, ITEM), {name: "A"});
  assert.deepEqual(calls, ["users", UID, "wardrobe", ITEM]);
});

test("memory sync read remains compatible with await", async () => {
  const memory = createMemoryTransactionalStore({
    [`users/${UID}/wardrobe/${ITEM}`]: {name: "sync"},
  });
  assert.deepEqual(await memory._get(UID, ITEM), {name: "sync"});
});

test("shadow awaits Promise document with existing authority", async () => {
  const {memory, store} = asyncStore(authorityDocument());
  const before = JSON.stringify(memory._dump());
  const result = await runShadow(store);
  assert.notEqual(result.status, "shadow_blocked");
  assert.notEqual(result.reasonCode, "missing_storage_path");
  assert.equal(result.migrationClass, "already_initialized");
  assert.equal(JSON.stringify(memory._dump()), before);
});

test("shadow awaits Promise legacy document and remains zero-write", async () => {
  const {memory, store} = asyncStore({name: "Legacy", storagePath: PATH});
  const before = JSON.stringify(memory._dump());
  const result = await runShadow(store);
  assert.equal(result.wouldInitializeAuthority, true);
  assert.equal(result.wroteProfile, false);
  assert.equal(JSON.stringify(memory._dump()), before);
});

test("shadow async missing document maps to item_not_found", async () => {
  const {store} = asyncStore(null);
  const result = await runShadow(store);
  assert.equal(result.status, "item_not_found");
  assert.equal(result.reasonCode, "wardrobe_item_not_found");
});

test("shadow async rejection is deterministic and skips Vision", async () => {
  let visionCalls = 0;
  const store = {
    runTransaction: async () => null,
    _get: async () => { throw new Error("sensitive backend detail"); },
  };
  const visionClient = {
    async analyzeCurrentSource() { visionCalls++; return null; },
  };
  const first = await runShadow(store, {visionClient});
  const second = await runShadow(store, {visionClient});
  assert.equal(first.status, "internal");
  assert.equal(first.reasonCode, "wardrobe_document_read_failed");
  assert.deepEqual(first, second);
  assert.equal(JSON.stringify(first).includes("sensitive"), false);
  assert.equal(visionCalls, 0);
});

test("shadow malformed snapshot fails closed before Vision", async () => {
  let visionCalls = 0;
  const store = createAdminFirestoreTransactionalStore({
    runTransaction: async () => null,
    get: async () => ({exists: true}),
  });
  const result = await runShadow(store, {
    visionClient: {async analyzeCurrentSource() { visionCalls++; }},
  });
  assert.equal(result.status, "internal");
  assert.equal(result.reasonCode, "wardrobe_document_read_failed");
  assert.equal(visionCalls, 0);
});

test("authority endpoint awaits async initial read", async () => {
  const {store} = asyncStore(authorityDocument());
  const result = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: ITEM,
    action: "analyze_current_source",
    offlineScenarioId: SCENARIO,
  }, {
    authContext: authContext(),
    store,
    storageMetadataClient: storageClient(),
    visionClient: createFakeTrustedVisionAnalysisClient(),
    serverClock: () => CLOCK,
    scenarioId: SCENARIO,
  });
  assert.notEqual(result.status, "item_not_found");
  assert.notEqual(result.status, "authority_missing");
});

test("authority endpoint awaits async post-initialization read", async () => {
  const {store} = asyncStore({name: "Legacy", storagePath: PATH});
  const result = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: ITEM,
    action: "analyze_current_source",
    offlineScenarioId: SCENARIO,
  }, {
    authContext: authContext(),
    store,
    storageMetadataClient: storageClient(),
    visionClient: createFakeTrustedVisionAnalysisClient(),
    serverClock: () => CLOCK,
    scenarioId: SCENARIO,
  });
  assert.equal(result.authorityInitialized, true);
  assert.notEqual(result.status, "authority_missing");
});

test("authority endpoint missing and rejected reads fail closed", async () => {
  const missing = await handleQualificationAuthorityEndpoint({
    contractVersion: 1, itemId: ITEM, action: "analyze_current_source",
  }, {
    authContext: authContext(),
    store: asyncStore(null).store,
  });
  assert.equal(missing.status, "item_not_found");

  const rejected = await handleQualificationAuthorityEndpoint({
    contractVersion: 1, itemId: ITEM, action: "analyze_current_source",
  }, {
    authContext: authContext(),
    store: {
      runTransaction: async () => null,
      _get: async () => { throw new Error("secret"); },
    },
  });
  assert.equal(rejected.status, "repository_failed");
  assert.equal(rejected.reasonCode, "wardrobe_document_read_failed");
  assert.equal(rejected.retryable, true);
  assert.equal(JSON.stringify(rejected).includes("secret"), false);
});
