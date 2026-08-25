"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {createTrustedVisionProductionAnalysisClient} =
  require("./trusted_vision_production_analysis_client");
const {createMemoryTransactionalStore} =
  require("./wardrobe_profile_firestore_repository");
const {createFakeStorageMetadataClient} =
  require("./trusted_storage_metadata_adapter");
const {buildGenerationId} = require("./wardrobe_qualification_revision_contract");
const {RUNTIME_POLICIES} = require("./trusted_vision_result_provenance");
const {resolveOpenAISecret} = require("./openai_secret_binding");
const {ACTION_KIND, mapShadowAnalysisKind, runQualificationAuthorityShadow} =
  require("./wardrobe_authority_shadow_runner");
const {createMemoryShadowLeaseStore} = require("./single_use_shadow_lease");

const ROOT = path.resolve(__dirname, "..");
const READY = ["blurred_item", "complementary_multi_view",
  "conflicting_multi_view", "cropped_lower", "cropped_upper",
  "dark_low_contrast", "front_only_garment", "shoe_without_outsole"];
const UID = "user-1"; const ITEM = "item-1";
const STORAGE = "wardrobe/user-1/item.jpg"; const GEN = "7";
const CLOCK = "2026-08-05T12:00:00.000Z";

function fixture(id) { return JSON.parse(fs.readFileSync(path.join(ROOT,
  "test/fixtures/backend_qualification/parser", `${id}.parser.json`), "utf8")); }
function auth() { return {authenticated: true, uid: UID, tokenVerified: true,
  emulatorVerified: true, appCheckPresent: true, appCheckVerified: true,
  authType: "firebase_auth"}; }
function document() { return {name: "Item", storagePath: STORAGE,
  qualificationAuthority: {contractVersion: 1, imageRevision: 1,
    wardrobeItemRevision: 1, uploadGeneration: GEN,
    generationId: buildGenerationId({itemId: ITEM, imageRevision: 1,
      sourceStoragePath: STORAGE, sourceObjectGeneration: GEN,
      uploadGeneration: GEN}), sourceStoragePath: STORAGE,
    sourceObjectGeneration: GEN, sourceObjectMetageneration: "1",
    sourceImageSha256: null, sourceUpdatedAt: CLOCK, assignedAt: CLOCK}}; }
function storage() { return createFakeStorageMetadataClient({[STORAGE]: {
  generation: GEN, metageneration: "1", size: "5", contentType: "image/jpeg",
  updated: CLOCK}}); }
function clientFor(id, counters) { const response = fixture(id).views[0].response;
  const types = [...new Set((response.identityCandidates || [])
    .map((item) => item.canonicalType).filter(Boolean))];
  return createTrustedVisionProductionAnalysisClient({canonicalTypes:
    types.length ? types : ["tank_top"], readObjectBytes: async () => {
      counters.byteReads++; return {buffer: Buffer.from("image"),
        contentType: "image/jpeg"}; }, getApiKey: () =>
      resolveOpenAISecret({value: () => "test-only-key"}),
    fetchImpl: async () => { counters.fetches++; return {ok: true,
      json: async () => ({choices: [{message: {content:
        JSON.stringify(response)}}]})}; }}); }
async function run(id, action = "analyze_current_source", extra = {}) {
  const counters = {fetches: 0, byteReads: 0};
  const store = createMemoryTransactionalStore({
    [`users/${UID}/wardrobe/${ITEM}`]: document()});
  const before = JSON.stringify(store._dump());
  const result = await runQualificationAuthorityShadow({itemId: ITEM, action}, {
    authContext: auth(), store, storageMetadataClient: storage(),
    visionClient: clientFor(id, counters), assignedAt: CLOCK,
    provenancePolicy: RUNTIME_POLICIES.productionShadow, ...extra});
  return {before, counters, result, store};
}

test("analysis action policy is explicit and fail closed", () => {
  assert.deepEqual(ACTION_KIND, {analyze_current_source: "initial_analysis",
    reanalyze_current_source: "reanalysis"});
  assert.equal(mapShadowAnalysisKind("analyze_current_source"), "initial_analysis");
  assert.equal(mapShadowAnalysisKind("reanalyze_current_source"), "reanalysis");
  assert.throws(() => mapShadowAnalysisKind("unknown"), /shadow_action_invalid/);
});

test("eight production-client fake-fetch scenarios use runtime and write zero", async () => {
  for (const id of READY) { const x = await run(id);
    assert.equal(x.result.status, "shadow_ok", `${id}:${x.result.reasonCode}`);
    assert.equal(x.result.mapperStatus, "mapped", id);
    assert.equal(x.result.wroteProfile, false, id);
    assert.equal(JSON.stringify(x.store._dump()), x.before, id);
    assert.equal(x.counters.fetches, 1, id); assert.equal(x.counters.byteReads, 1, id);
    assert.equal(x.result.paritySummary.scenarioId, undefined, id); }
});

test("initial and reanalysis are deterministic and identity-distinct", async () => {
  const initialA = await run("front_only_garment");
  const initialB = await run("front_only_garment");
  const reanalysis = await run("front_only_garment", "reanalyze_current_source");
  assert.deepEqual(initialA.result, initialB.result);
  assert.notEqual(initialA.result.analysisId, reanalysis.result.analysisId);
  assert.equal(reanalysis.result.status, "shadow_ok");
});

test("runtime failure and write attempts fail without mutating production store", async () => {
  const failed = await run("front_only_garment", "analyze_current_source", {
    runRuntimeOrchestrator: () => ({status: "mapper_failed"})});
  assert.equal(failed.result.status, "qualification_failed");
  assert.equal(failed.result.wroteProfile, false);
  assert.equal(JSON.stringify(failed.store._dump()), failed.before);
});

test("production shadow source has no legacy oracle runtime dependency", () => {
  const source = fs.readFileSync(path.join(__dirname,
    "wardrobe_authority_shadow_runner.js"), "utf8");
  assert.doesNotMatch(source, /wardrobe_backend_qualification_orchestrator/);
  assert.doesNotMatch(source, /runBackendQualificationOrchestration/);
  assert.doesNotMatch(source, /scenarioId|fixtureRoot|offlineScenarioId/);
  assert.match(source, /runLiveParserBackendQualification/);
  assert.match(source, /buildTrustedVisionQualificationInput/);
  assert.match(source, /allocateServerAnalysisIdentity/);
});

test("controlled exact cohort fake production E2E consumes one lease", async () => {
  const shadowPolicy = {contractVersion: 1, enabled: true, allowedUid: UID,
    allowedItemId: ITEM, leaseId: "test-lease", validFrom: CLOCK,
    expiresAt: "2026-08-05T12:15:00.000Z", maxAcceptedRequests: 1,
    analysisActions: ["analyze_current_source"], expectedMode: "shadow",
    sourceGenerationFingerprint: null, provenance: {source: "test-injection"}};
  const shadowLeaseStore = createMemoryShadowLeaseStore({contractVersion: 1,
    leaseId: "test-lease", validFrom: CLOCK,
    expiresAt: "2026-08-05T12:15:00.000Z", maxAcceptedRequests: 1,
    acceptedRequestCount: 0, consumedAt: null, consumedByInvocationId: null,
    status: "fresh", createdAt: CLOCK});
  const controlled = {requireControlledShadowPolicy: true, shadowPolicy,
    shadowLeaseStore, serverNow: CLOCK, invocationId: "fake-call"};
  const first = await run("front_only_garment", "analyze_current_source", controlled);
  const second = await run("front_only_garment", "analyze_current_source", controlled);
  assert.equal(first.result.status, "shadow_ok");
  assert.equal(first.counters.fetches, 1);
  assert.equal(JSON.stringify(first.store._dump()), first.before);
  assert.equal(second.result.status, "shadow_blocked");
  assert.equal(second.result.reasonCode, "shadow_lease_consumed");
  assert.equal(second.counters.fetches, 0);
  assert.equal(second.counters.byteReads, 0);
});
