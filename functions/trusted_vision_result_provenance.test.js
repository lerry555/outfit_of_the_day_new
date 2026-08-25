"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {PROVENANCE_CONTRACT, RUNTIME_POLICIES,
  validateTrustedVisionResultForRuntime: validate} =
  require("./trusted_vision_result_provenance");
const {createFakeTrustedVisionAnalysisClient} =
  require("./trusted_vision_analysis_client");
const {createTrustedVisionProductionAnalysisClient} =
  require("./trusted_vision_production_analysis_client");
const {createMemoryTransactionalStore} =
  require("./wardrobe_profile_firestore_repository");
const {runQualificationAuthorityShadow} =
  require("./wardrobe_authority_shadow_runner");
const {handleQualificationAuthorityEndpoint} =
  require("./wardrobe_qualification_authority_endpoint");
const {createFakeStorageMetadataClient} =
  require("./trusted_storage_metadata_adapter");
const {buildGenerationId} = require("./wardrobe_qualification_revision_contract");

const ROOT = path.resolve(__dirname, "..");
const SCENARIO = "front_only_garment";
const UID = "user-1";
const ITEM = "item-1";
const STORAGE_PATH = "wardrobe/user-1/item.jpg";
const GENERATION = "7";
const CLOCK = "2026-08-05T12:00:00.000Z";

function auth() { return {authenticated: true, uid: UID, tokenVerified: true,
  emulatorVerified: true, appCheckPresent: true, appCheckVerified: true,
  authType: "firebase_auth"}; }
function document() { return {name: "Tank", storagePath: STORAGE_PATH,
  qualificationAuthority: {contractVersion: 1, imageRevision: 1,
    wardrobeItemRevision: 1, uploadGeneration: GENERATION,
    generationId: buildGenerationId({itemId: ITEM, imageRevision: 1,
      sourceStoragePath: STORAGE_PATH, sourceObjectGeneration: GENERATION,
      uploadGeneration: GENERATION}), sourceStoragePath: STORAGE_PATH,
    sourceObjectGeneration: GENERATION, sourceObjectMetageneration: "1",
    sourceImageSha256: null, sourceUpdatedAt: CLOCK, assignedAt: CLOCK}}; }
function storage() { return createFakeStorageMetadataClient({[STORAGE_PATH]: {
  generation: GENERATION, metageneration: "1", size: "100",
  contentType: "image/jpeg", updated: CLOCK}}); }
async function fixtureResult() {
  return createFakeTrustedVisionAnalysisClient().analyzeCurrentSource({
    itemId: ITEM, scenarioId: SCENARIO, sourceStoragePath: STORAGE_PATH});
}
async function liveResult(counter = {calls: 0}) {
  const captured = JSON.parse(fs.readFileSync(path.join(ROOT,
    "test/fixtures/backend_qualification/parser",
    `${SCENARIO}.parser.json`), "utf8"));
  const client = createTrustedVisionProductionAnalysisClient({
    readObjectBytes: async () => ({buffer: Buffer.from("image"),
      contentType: "image/jpeg"}), getApiKey: () => "test-only-key",
    fetchImpl: async () => { counter.calls++; return {ok: true,
      json: async () => ({choices: [{message: {content:
        JSON.stringify(captured.views[0].response)}}]})}; },
    canonicalTypes: ["tank_top"],
  });
  return client.analyzeCurrentSource({itemId: ITEM, scenarioId: SCENARIO,
    sourceStoragePath: STORAGE_PATH});
}
function check(result, policy, expectedVersions) {
  return validate(result, {policy, expectedVersions});
}

test("fixture non-live passes fixture-only policy", async () => {
  const r = check(await fixtureResult(), RUNTIME_POLICIES.fixtureOnly);
  assert.equal(r.ok, true); assert.equal(r.contract, PROVENANCE_CONTRACT);
});
test("fixture live model fails fixture-only policy", async () => {
  const v = structuredClone(await fixtureResult()); v.provenance.liveModel = true;
  assert.equal(check(v, RUNTIME_POLICIES.fixtureOnly).reasonCode,
    "fixture_live_model_forbidden");
});
test("trusted live passes shadow and controlled policies", async () => {
  const v = await liveResult(); assert.equal(v.provenance.liveModel, true);
  assert.equal(check(v, RUNTIME_POLICIES.productionShadow).ok, true);
  assert.equal(check(v, RUNTIME_POLICIES.productionControlledWrite).ok, true);
});
test("production rejects non-live and fixture transport", async () => {
  const v = structuredClone(await liveResult()); v.provenance.liveModel = false;
  assert.equal(check(v, RUNTIME_POLICIES.productionShadow).reasonCode,
    "production_live_model_required");
  assert.equal(check(await fixtureResult(),
    RUNTIME_POLICIES.productionShadow).reasonCode,
  "production_trusted_source_required");
});
test("client source rejected for true and false live flag", async () => {
  for (const flag of [true, false]) { const v = structuredClone(await liveResult());
    v.provenance.source = "client_parser_result"; v.provenance.liveModel = flag;
    assert.equal(check(v, RUNTIME_POLICIES.productionShadow).reasonCode,
      "production_trusted_source_required"); }
});
test("model prompt and schema mismatches fail", async () => {
  const cases = [["model_identifier_mismatch", v => v.provenance.modelIdentifier = "x"],
    ["prompt_version_mismatch", v => v.provenance.promptVersion = "x"],
    ["vision_schema_version_mismatch", v => v.provenance.visionSchemaVersion = 8],
    ["parser_model_version_mismatch", v => v.parser.views[0].response.modelVersion = "x"],
    ["parser_schema_version_mismatch", v => v.parser.views[0].response.schemaVersion = 8]];
  for (const [reason, mutate] of cases) { const v = structuredClone(await liveResult());
    mutate(v); assert.equal(check(v, RUNTIME_POLICIES.productionShadow).reasonCode,
      reason); }
});
test("pipeline and qualification mismatches fail", async () => {
  const v = await liveResult();
  assert.equal(check(v, RUNTIME_POLICIES.productionShadow,
    {pipelineVersion: "x"}).reasonCode, "pipeline_version_mismatch");
  assert.equal(check(v, RUNTIME_POLICIES.productionShadow,
    {qualificationVersion: "x"}).reasonCode, "qualification_version_mismatch");
});
test("missing malformed provenance and unknown policy fail", async () => {
  const a = structuredClone(await liveResult()); delete a.provenance;
  assert.equal(check(a, RUNTIME_POLICIES.productionShadow).reasonCode,
    "trusted_vision_provenance_missing");
  const b = structuredClone(await liveResult()); delete b.provenance.liveModel;
  assert.equal(check(b, RUNTIME_POLICIES.productionShadow).reasonCode,
    "trusted_vision_provenance_malformed");
  assert.equal(check(await liveResult(), "unknown").reasonCode,
    "unknown_runtime_policy");
});
test("raw malformed parser fails strict validation", async () => {
  const v = structuredClone(await liveResult()); v.parser.views = [];
  assert.equal(check(v, RUNTIME_POLICIES.productionShadow).reasonCode,
    "strict_parser_validation_failed");
});
test("trusted server source reference is mandatory", async () => {
  const v = structuredClone(await liveResult());
  v.parser.views[0].response.sourceReference = "https://client/x";
  assert.equal(check(v, RUNTIME_POLICIES.productionShadow).reasonCode,
    "trusted_server_source_reference_required");
});
test("validation is deterministic and returns no raw response or token", async () => {
  const v = await liveResult(); const a = check(v, RUNTIME_POLICIES.productionShadow);
  assert.deepEqual(a, check(v, RUNTIME_POLICIES.productionShadow));
  assert.equal(JSON.stringify(a).includes("observations"), false);
  assert.equal(JSON.stringify(a).includes("test-only-key"), false);
});
test("trusted live shadow continues with zero writes", async () => {
  const counter = {calls: 0}; const live = await liveResult(counter);
  const store = createMemoryTransactionalStore({
    [`users/${UID}/wardrobe/${ITEM}`]: document()});
  const before = JSON.stringify(store._dump());
  const r = await runQualificationAuthorityShadow({itemId: ITEM,
    action: "analyze_current_source"}, {
    authContext: auth(), store, storageMetadataClient: storage(),
    visionClient: {analyzeCurrentSource: async () => live}, assignedAt: CLOCK,
    provenancePolicy: RUNTIME_POLICIES.productionShadow});
  assert.notEqual(r.status, "invalid_parser_result");
  assert.equal(r.wroteProfile, false); assert.equal(JSON.stringify(store._dump()), before);
  assert.equal(counter.calls, 1);
});
test("controlled endpoint accepts trusted live provenance", async () => {
  const live = await liveResult(); const store = createMemoryTransactionalStore({
    [`users/${UID}/wardrobe/${ITEM}`]: document()});
  const r = await handleQualificationAuthorityEndpoint({contractVersion: 1,
    itemId: ITEM, action: "analyze_current_source", assignedAt: CLOCK}, {
    authContext: auth(), store, storageMetadataClient: storage(),
    visionClient: {analyzeCurrentSource: async () => live}, serverClock: () => CLOCK,
    provenancePolicy: RUNTIME_POLICIES.productionControlledWrite});
  assert.notEqual(r.status, "invalid_parser_result");
});
test("cost gate precedes Storage and Vision", async () => {
  let storageCalls = 0; let visionCalls = 0;
  const r = await runQualificationAuthorityShadow({itemId: ITEM}, {
    authContext: auth(), store: createMemoryTransactionalStore({
      [`users/${UID}/wardrobe/${ITEM}`]: document()}),
    costGate: {begin: () => ({ok: false, reasonCode: "rate_limited"})},
    storageMetadataClient: {getMetadata: async () => {storageCalls++;}},
    visionClient: {analyzeCurrentSource: async () => {visionCalls++;}},
    provenancePolicy: RUNTIME_POLICIES.productionShadow});
  assert.equal(r.status, "resource_exhausted");
  assert.equal(storageCalls, 0); assert.equal(visionCalls, 0);
});
