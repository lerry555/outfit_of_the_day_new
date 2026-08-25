"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {CONTRACT_ID, OPENAI_API_KEY_SECRET, SECRET_NAME,
  openAISecretAvailability, resolveOpenAISecret} =
  require("./openai_secret_binding");
const {WARDROBE_SHADOW_POLICY_SECRET, SECRET_NAME: SHADOW_POLICY_SECRET_NAME} =
  require("./controlled_shadow_policy_config");
const {WARDROBE_CONTROLLED_WRITE_POLICY_SECRET} =
  require("./controlled_write_policy_config");
const {buildWardrobeAuthorityCallables} =
  require("./wardrobe_authority_callable_exports");
const {createWardrobeAuthorityProductionDependencies} =
  require("./wardrobe_authority_production_dependencies");
const {runQualificationAuthorityShadow} =
  require("./wardrobe_authority_shadow_runner");
const {createMemoryTransactionalStore} =
  require("./wardrobe_profile_firestore_repository");
const {createFakeStorageMetadataClient} =
  require("./trusted_storage_metadata_adapter");
const {buildGenerationId} = require("./wardrobe_qualification_revision_contract");
const {RUNTIME_POLICIES} = require("./trusted_vision_result_provenance");

const ROOT = path.resolve(__dirname, ".."); const VALUE = "unit-test-secret-value";
const UID = "user-1"; const ITEM = "item-1";
const STORAGE = "wardrobe/user-1/item.jpg"; const GEN = "7";
const CLOCK = "2026-08-05T12:00:00.000Z";
function secret(value = VALUE) { return {value: () => value}; }
function fakeFunctions(captured) { return {region() { return this; },
  runWith(options) { captured.push(options); return this; }, https: {
    onCall(handler) { return handler; }, HttpsError: class extends Error {
      constructor(code, message) { super(message); this.code = code; }
    }}}; }
function auth() { return {authenticated: true, uid: UID, tokenVerified: true,
  emulatorVerified: true, appCheckPresent: true, appCheckVerified: true,
  authType: "firebase_auth"}; }
function doc() { return {storagePath: STORAGE, qualificationAuthority: {
  contractVersion: 1, imageRevision: 1, wardrobeItemRevision: 1,
  uploadGeneration: GEN, generationId: buildGenerationId({itemId: ITEM,
    imageRevision: 1, sourceStoragePath: STORAGE, sourceObjectGeneration: GEN,
    uploadGeneration: GEN}), sourceStoragePath: STORAGE,
  sourceObjectGeneration: GEN, sourceObjectMetageneration: "1",
  sourceImageSha256: null, sourceUpdatedAt: CLOCK, assignedAt: CLOCK}}; }
function storage() { return createFakeStorageMetadataClient({[STORAGE]: {
  generation: GEN, metageneration: "1", size: "5", contentType: "image/jpeg",
  updated: CLOCK}}); }

test("1 secret declaration exists", () => assert.equal(CONTRACT_ID,
  "OpenAISecretBinding/v1"));
test("2 exact secret name", () => { assert.equal(SECRET_NAME, "OPENAI_API_KEY");
  assert.equal(OPENAI_API_KEY_SECRET.name, SECRET_NAME); });
test("3 lifecycle callable has no OpenAI secret", () => { const c = [];
  buildWardrobeAuthorityCallables({functions: fakeFunctions(c)});
  assert.equal(c[0].secrets, undefined); });
test("4 authority callable has explicit secret binding", () => { const c = [];
  buildWardrobeAuthorityCallables({functions: fakeFunctions(c)});
  assert.deepEqual(c[1].secrets,
    [OPENAI_API_KEY_SECRET, WARDROBE_SHADOW_POLICY_SECRET,
      WARDROBE_CONTROLLED_WRITE_POLICY_SECRET]); });
test("5 disabled mode never constructs dependencies or resolves secret", async () => {
  let gets = 0; let resolves = 0; const c = [];
  const built = buildWardrobeAuthorityCallables({functions: fakeFunctions(c),
    resolveMode: () => ({mode: "disabled"}), dependencyFactory: {get() { gets++;
      return {resolveOpenAISecret() { resolves++; }}; }}});
  await assert.rejects(() => built.authorityCallable({}, {auth: {uid: UID}}),
    /wardrobe_authority_mode_disabled/); assert.equal(gets, 0);
  assert.equal(resolves, 0); });
test("6 disabled response remains stable", async () => { const c = [];
  const built = buildWardrobeAuthorityCallables({functions: fakeFunctions(c),
    resolveMode: () => ({mode: "disabled"})});
  await assert.rejects(() => built.authorityCallable({}, {}), (e) =>
    e.code === "failed-precondition" &&
    e.message === "wardrobe_authority_mode_disabled"); });
test("7 shadow missing secret fails before Vision bytes", async () => {
  let vision = 0; const store = createMemoryTransactionalStore({
    [`users/${UID}/wardrobe/${ITEM}`]: doc()}); const before = JSON.stringify(store._dump());
  const result = await runQualificationAuthorityShadow({itemId: ITEM,
    action: "analyze_current_source"}, {authContext: auth(), store,
    storageMetadataClient: storage(), resolveOpenAISecret() {
      throw new Error("openai_secret_unavailable"); }, visionClient: {
      async analyzeCurrentSource() { vision++; }}, assignedAt: CLOCK,
    provenancePolicy: RUNTIME_POLICIES.productionShadow});
  assert.equal(result.reasonCode, "openai_secret_unavailable");
  assert.equal(vision, 0); assert.equal(JSON.stringify(store._dump()), before); });
test("8 controlled resolver missing fails closed", () => assert.throws(
  () => resolveOpenAISecret(secret("")), /openai_secret_unavailable/));
test("9 valid fake secret reaches trusted resolver", () =>
  assert.equal(resolveOpenAISecret(secret()), VALUE));
test("10 key absent from availability status", () => assert.equal(
  JSON.stringify(openAISecretAvailability(secret())).includes(VALUE), false));
test("11 key absent from public module metadata", () => assert.equal(
  JSON.stringify({CONTRACT_ID, SECRET_NAME}).includes(VALUE), false));
test("12 key absent from provenance contract", () => { const source =
  fs.readFileSync(path.join(__dirname, "trusted_vision_result_provenance.js"), "utf8");
  assert.equal(source.includes(VALUE), false); });
test("13 key absent from missing-secret errors", () => { let message = "";
  try { resolveOpenAISecret(secret("")); } catch (e) { message = e.message; }
  assert.equal(message, "openai_secret_unavailable"); });
test("14 authority wiring has no process env key fallback", () => { const source =
  fs.readFileSync(path.join(__dirname, "openai_secret_binding.js"), "utf8");
  assert.doesNotMatch(source, /process\.env/); });
test("15 authority wiring has no functions config fallback", () => { const source =
  fs.readFileSync(path.join(__dirname, "openai_secret_binding.js"), "utf8");
  assert.doesNotMatch(source, /functions\.config|\.config\(\)/); });
test("16 client key is rejected", async () => { const {createTrustedVisionProductionAnalysisClient} =
  require("./trusted_vision_production_analysis_client"); const client =
  createTrustedVisionProductionAnalysisClient(); await assert.rejects(() =>
    client.analyzeCurrentSource({itemId: ITEM, sourceStoragePath: STORAGE,
      apiKey: VALUE}), /client_media_rejected:apiKey/); });
test("17 importing binding does not resolve secret", () =>
  assert.equal(typeof OPENAI_API_KEY_SECRET.value, "function"));
test("18 production factory construction is deterministic and lazy", () => {
  let resolves = 0; const options = {config: {environmentMode: "production",
    projectId: "outfit-prod", storageBucket: "outfit-prod.appspot.com",
    region: "us-east1", visionSchemaVersion: 9, modelIdentifier: "gpt-4o-mini",
    promptVersion: "vision-v2-schema-9", qualificationVersion: "qualification-v1",
    revisionContractVersion: "wardrobe-qualification-revision-context-v1",
    persistenceSchemaVersion: 1}, memoryDocs: {}, fakeStorageByPath: {},
    fetchImpl: async () => {}, readObjectBytes: async () => {},
    resolveOpenAISecret: () => { resolves++; return VALUE; }};
  const factory = createWardrobeAuthorityProductionDependencies(options);
  assert.equal(factory.peekConstructed(), false); const a = factory.get();
  assert.equal(a, factory.get()); assert.equal(resolves, 0); });
test("19 deployed trigger metadata binds only authority", () => { const x =
  require("./index"); const a = x.wardrobeQualificationAuthority.__trigger;
  const l = x.wardrobeRevisionLifecycle.__trigger;
  assert.deepEqual(a.secrets.map((s) => s.name),
    [SECRET_NAME, SHADOW_POLICY_SECRET_NAME,
      WARDROBE_CONTROLLED_WRITE_POLICY_SECRET.name]);
  assert.equal(l.secrets, undefined); });
test("20 source contains no literal key assignment", () => { const source =
  fs.readFileSync(path.join(__dirname, "openai_secret_binding.js"), "utf8");
  assert.doesNotMatch(source, /OPENAI_API_KEY\s*=\s*["'][^"']+/); });
test("21 production Vision resolves secret before byte read", async () => {
  const order = []; const {createTrustedVisionProductionAnalysisClient} =
    require("./trusted_vision_production_analysis_client");
  const client = createTrustedVisionProductionAnalysisClient({
    getApiKey: () => { order.push("secret"); throw new Error(
      "openai_secret_unavailable"); }, readObjectBytes: async () => {
      order.push("bytes"); return {buffer: Buffer.from("x"),
        contentType: "image/jpeg"}; }, fetchImpl: async () => { order.push("fetch"); }});
  await assert.rejects(() => client.analyzeCurrentSource({itemId: ITEM,
    sourceStoragePath: STORAGE}), /openai_secret_unavailable/);
  assert.deepEqual(order, ["secret"]);
});
