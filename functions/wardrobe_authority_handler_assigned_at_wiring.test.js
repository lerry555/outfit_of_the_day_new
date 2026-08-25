"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {createQualificationAuthorityHandler} =
  require("./wardrobe_qualification_authority_handler");
const {createMemoryTransactionalStore, AUTHORITY_KEY, ENVELOPE_KEY} =
  require("./wardrobe_profile_firestore_repository");
const {createFakeStorageMetadataClient} =
  require("./trusted_storage_metadata_adapter");
const {createFakeTrustedVisionAnalysisClient} =
  require("./trusted_vision_analysis_client");
const {handleQualificationAuthorityEndpoint} =
  require("./wardrobe_qualification_authority_endpoint");
const {RUNTIME_POLICIES} = require("./trusted_vision_result_provenance");
const {phase9bExportReadinessState} =
  require("./wardrobe_authority_export_gate");

const UID = "handler-user";
const ITEM = "handler-item";
const STORAGE = "wardrobe/handler-user/item.jpg";
const GENERATION = "1700000000000000";
const SERVER_TIME = "2026-08-06T16:00:00.000Z";
const CLIENT_TIME = "1999-01-01T00:00:00.000Z";
const KEY = `users/${UID}/wardrobe/${ITEM}`;

function authRuntime() {
  return {
    auth: {uid: UID, token: {firebase: {sign_in_provider: "google.com"}}},
    app: {appId: "debug-app"},
    tokenVerified: true,
    appCheckPresent: true,
    appCheckVerified: true,
  };
}

function buildDeps({serverClock, assignedAt, runtime} = {}) {
  const memory = createMemoryTransactionalStore({
    [KEY]: {name: "Tank", storagePath: STORAGE},
  });
  let transactionCount = 0;
  const store = {
    _get: memory._get.bind(memory),
    _dump: memory._dump.bind(memory),
    async runTransaction(uid, itemId, callback) {
      transactionCount++;
      return memory.runTransaction(uid, itemId, callback);
    },
  };
  const deps = {
    config: {environmentMode: "test", projectId: "test",
      storageBucket: "test.appspot.com", region: "us-east1",
      appCheckMode: "disabled_for_emulator_only"},
    store,
    storageMetadataClient: createFakeStorageMetadataClient({[STORAGE]: {
      generation: GENERATION, metageneration: "1", size: "100",
      contentType: "image/jpeg", updated: SERVER_TIME,
    }}),
    visionClient: createFakeTrustedVisionAnalysisClient(),
    handleQualificationAuthorityEndpoint,
    provenancePolicy: RUNTIME_POLICIES.fixtureOnly,
    assignedAt: assignedAt === undefined ? null : assignedAt,
    serverClock: serverClock === undefined ? (() => SERVER_TIME) : serverClock,
    ...(runtime ? {runRuntimeOrchestrator: runtime} : {}),
  };
  return {deps, store, transactionCount: () => transactionCount, memory};
}

function handlerFor(deps) {
  return createQualificationAuthorityHandler({
    dependencyFactory: {get: () => deps},
    exportReadinessState: phase9bExportReadinessState(),
    enforceExportGate: false,
    defaultScenarioId: "front_only_garment",
  });
}

test("01 production handler source passes serverClock not client assignedAt", () => {
  const source = fs.readFileSync(path.join(__dirname,
    "wardrobe_qualification_authority_handler.js"), "utf8");
  assert.match(source, /serverClock:\s*deps\.serverClock/);
  assert.doesNotMatch(source, /assignedAt:\s*data\.assignedAt/);
  assert.doesNotMatch(source, /data\.assignedAt\s*\|\|/);
  assert.doesNotMatch(source, /assignedAt:\s*deps\.assignedAt/);
});

test("02 endpoint resolveServerAssignedAt requires serverClock only", () => {
  const source = fs.readFileSync(path.join(__dirname,
    "wardrobe_qualification_authority_endpoint.js"), "utf8");
  assert.match(source, /server_clock_required/);
  assert.match(source, /server_clock_invalid/);
  assert.doesNotMatch(source,
    /function resolveServerAssignedAt[\s\S]*deps\.assignedAt/);
});

test("03 handler passes serverClock and ignores client assignedAt", async () => {
  const x = buildDeps();
  const handler = handlerFor(x.deps);
  const result = await handler.handle({
    contractVersion: 1,
    itemId: ITEM,
    action: "analyze_current_source",
    assignedAt: CLIENT_TIME,
  }, authRuntime());
  assert.equal(result.ok, true);
  assert.equal(x.transactionCount(), 1);
  const doc = x.store._dump()[KEY];
  assert.equal(doc[AUTHORITY_KEY].assignedAt, SERVER_TIME);
  assert.equal(doc[ENVELOPE_KEY].analysis.completedAt, SERVER_TIME);
  assert.equal(JSON.stringify(doc).includes(CLIENT_TIME), false);
});

test("04 client assignedAt cannot override serverClock via deps.assignedAt", async () => {
  const x = buildDeps({assignedAt: CLIENT_TIME});
  const handler = handlerFor(x.deps);
  const result = await handler.handle({
    contractVersion: 1,
    itemId: ITEM,
    action: "analyze_current_source",
    assignedAt: "1980-01-01T00:00:00.000Z",
  }, authRuntime());
  assert.equal(result.ok, true);
  const doc = x.store._dump()[KEY];
  assert.equal(doc[AUTHORITY_KEY].assignedAt, SERVER_TIME);
  assert.equal(JSON.stringify(doc).includes(CLIENT_TIME), false);
  assert.equal(JSON.stringify(doc).includes("1980-01-01"), false);
});

test("05 missing serverClock fail-closed with no writes", async () => {
  const x = buildDeps({serverClock: null});
  const before = JSON.stringify(x.store._dump());
  const handler = handlerFor(x.deps);
  const result = await handler.handle({
    contractVersion: 1,
    itemId: ITEM,
    action: "analyze_current_source",
  }, authRuntime());
  assert.equal(result.ok, false);
  assert.equal(result.error.message, "server_clock_required");
  assert.equal(x.transactionCount(), 0);
  assert.equal(JSON.stringify(x.store._dump()), before);
});

test("06 invalid serverClock fail-closed with no writes", async () => {
  const x = buildDeps({serverClock: () => "not-a-timestamp"});
  const before = JSON.stringify(x.store._dump());
  const handler = handlerFor(x.deps);
  const result = await handler.handle({
    contractVersion: 1,
    itemId: ITEM,
    action: "analyze_current_source",
  }, authRuntime());
  assert.equal(result.ok, false);
  assert.equal(result.error.message, "assignedAt_non_utc_timestamp");
  assert.equal(x.transactionCount(), 0);
  assert.equal(JSON.stringify(x.store._dump()), before);
});

test("07 throwing serverClock fail-closed", async () => {
  const x = buildDeps({serverClock: () => { throw new Error("clock_down"); }});
  const before = JSON.stringify(x.store._dump());
  const handler = handlerFor(x.deps);
  const result = await handler.handle({
    contractVersion: 1,
    itemId: ITEM,
    action: "analyze_current_source",
  }, authRuntime());
  assert.equal(result.ok, false);
  assert.equal(result.error.message, "server_clock_invalid");
  assert.equal(x.transactionCount(), 0);
  assert.equal(JSON.stringify(x.store._dump()), before);
});

test("08 pipeline failure creates no assignedAt write", async () => {
  const x = buildDeps();
  x.deps.visionClient = {
    async analyzeCurrentSource() {
      throw new Error("injected_vision_failure");
    },
  };
  const before = JSON.stringify(x.store._dump());
  const handler = handlerFor(x.deps);
  const result = await handler.handle({
    contractVersion: 1,
    itemId: ITEM,
    action: "analyze_current_source",
  }, authRuntime());
  assert.equal(result.ok, false);
  assert.equal(x.transactionCount(), 0);
  assert.equal(JSON.stringify(x.store._dump()), before);
  assert.equal(x.store._dump()[KEY][AUTHORITY_KEY], undefined);
});

test("09 authority and profile share consistent assignedAt", async () => {
  const x = buildDeps();
  const handler = handlerFor(x.deps);
  const result = await handler.handle({
    contractVersion: 1,
    itemId: ITEM,
    action: "analyze_current_source",
  }, authRuntime());
  assert.equal(result.ok, true);
  const doc = x.store._dump()[KEY];
  assert.equal(doc[AUTHORITY_KEY].assignedAt, SERVER_TIME);
  assert.equal(doc[AUTHORITY_KEY].sourceUpdatedAt, SERVER_TIME);
  assert.equal(doc[ENVELOPE_KEY].analysis.completedAt, SERVER_TIME);
  assert.equal(doc[ENVELOPE_KEY].metadata.createdAt, SERVER_TIME);
});

test("10 assignedAt deterministic with fake clock", async () => {
  const x = buildDeps({serverClock: () => "2026-08-06T17:30:00.000Z"});
  const handler = handlerFor(x.deps);
  await handler.handle({
    contractVersion: 1,
    itemId: ITEM,
    action: "analyze_current_source",
  }, authRuntime());
  assert.equal(x.store._dump()[KEY][AUTHORITY_KEY].assignedAt,
    "2026-08-06T17:30:00.000Z");
});

test("11 external callable payload fields unchanged in client contract", () => {
  const source = fs.readFileSync(path.join(__dirname, "..",
    "lib/Services/wardrobe_qualification_authority_client.dart"), "utf8");
  assert.match(source, /'contractVersion': 1/);
  assert.match(source, /'itemId': itemId/);
  assert.match(source, /'action': action/);
  assert.doesNotMatch(source, /assignedAt/);
  assert.doesNotMatch(source, /serverClock/);
});
