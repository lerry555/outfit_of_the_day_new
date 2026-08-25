"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {decodeControlledWritePolicy, evaluateControlledWritePolicy,
  fingerprintPolicy, CONTRACT_ID: POLICY_ID} =
  require("./controlled_write_activation_policy");
const {resolveControlledWritePolicy, SECRET_NAME} =
  require("./controlled_write_policy_config");
const {consumeControlledWriteLease, createMemoryControlledWriteLeaseStore,
  CONTRACT_ID: LEASE_ID, PURPOSE} = require("./controlled_write_single_use_lease");
const {createAdminControlledWriteLeaseStore, COLLECTION} =
  require("./wardrobe_admin_controlled_write_lease_store");
const {createWardrobeAuthorityProductionDependencies} =
  require("./wardrobe_authority_production_dependencies");
const {buildControlledWriteCanaryArtifacts} =
  require("./scripts/build_controlled_write_canary_artifacts");
const {buildWardrobeAuthorityCallables} =
  require("./wardrobe_authority_callable_exports");

const UID = "private-controlled-user";
const ITEM = "private-controlled-item";
const NOW = "2026-08-06T15:05:00.000Z";
function policy(overrides = {}) { return {contractVersion: 1, enabled: true,
  allowedUid: UID, allowedItemId: ITEM, allowedAction: "analyze_current_source",
  leaseId: "controlled-lease", validFrom: "2026-08-06T15:00:00.000Z",
  expiresAt: "2026-08-06T15:15:00.000Z", maxAcceptedRequests: 1,
  expectedMode: "controlled_write", sourceGenerationFingerprint: null,
  policyVersion: "canary-v1", provenance: {source: "test"}, ...overrides}; }
function evaluate(p = policy(), request = {}, context = {}) {
  return evaluateControlledWritePolicy(p, {itemId: ITEM,
    action: "analyze_current_source", ...request}, {uid: UID,
    mode: "controlled_write", now: NOW, sourceGenerationFingerprint: null,
    ...context});
}
function lease(overrides = {}) { const p = policy(); return {contractVersion: 1,
  leaseId: p.leaseId, policyFingerprint: fingerprintPolicy(p), allowedUid: UID,
  allowedItemId: ITEM, allowedAction: p.allowedAction, validFrom: p.validFrom,
  expiresAt: p.expiresAt, maxAcceptedRequests: 1, acceptedRequestCount: 0,
  status: "fresh", consumedAt: null, consumedByInvocationId: null,
  purpose: PURPOSE, expectedMode: "controlled_write", createdAt: p.validFrom,
  ...overrides}; }
function leaseInput(p = policy(), overrides = {}) { return {leaseId: p.leaseId,
  policyFingerprint: fingerprintPolicy(p), allowedUid: p.allowedUid,
  allowedItemId: p.allowedItemId, allowedAction: p.allowedAction, now: NOW,
  invocationId: "invocation-1", ...overrides}; }
function secret(value) { return {value: () => value}; }

test("01 policy and config identities are separate from shadow", () => {
  assert.equal(POLICY_ID, "ControlledWriteActivationPolicy/v1");
  assert.equal(SECRET_NAME, "WARDROBE_CONTROLLED_WRITE_POLICY");
  assert.notEqual(SECRET_NAME, "WARDROBE_SHADOW_POLICY");
});
test("02 valid exact policy accepted", () => assert.equal(evaluate().ok, true));
test("03 missing policy", () => assert.equal(evaluate(null).reasonCode,
  "controlled_write_policy_missing"));
test("04 invalid JSON", () => assert.throws(() =>
  resolveControlledWritePolicy(secret("{")), /controlled_write_policy_invalid/));
test("05 unknown field", () => assert.throws(() =>
  decodeControlledWritePolicy(policy({extra: true})), /controlled_write_policy_invalid/));
test("06 missing UID", () => assert.equal(evaluate(policy({allowedUid: ""})).reasonCode,
  "controlled_write_policy_invalid"));
test("07 UID mismatch", () => assert.equal(evaluate(policy(), {}, {uid: "other"})
  .reasonCode, "controlled_write_uid_not_allowlisted"));
test("08 missing item", () => assert.equal(evaluate(policy({allowedItemId: ""}))
  .reasonCode, "controlled_write_policy_invalid"));
test("09 item mismatch", () => assert.equal(evaluate(policy(), {itemId: "other"})
  .reasonCode, "controlled_write_item_not_allowlisted"));
test("10 action mismatch", () => assert.equal(evaluate(policy(), {action: "unknown"})
  .reasonCode, "controlled_write_action_not_allowed"));
test("11 reanalysis rejected", () => assert.equal(evaluate(policy(),
  {action: "reanalyze_current_source"}).reasonCode,
  "controlled_write_action_not_allowed"));
test("12 shadow cannot use controlled policy", () => assert.equal(evaluate(policy(), {},
  {mode: "shadow"}).reasonCode, "controlled_write_policy_mode_mismatch"));
test("13 policy cannot authorize disabled", () => assert.equal(evaluate(policy(), {},
  {mode: "disabled"}).ok, false));
test("14 before validFrom", () => assert.equal(evaluate(policy(), {},
  {now: "2026-08-06T14:59:59Z"}).reasonCode,
  "controlled_write_window_not_active"));
test("15 expired", () => assert.equal(evaluate(policy(), {},
  {now: policy().expiresAt}).reasonCode, "controlled_write_window_expired"));
test("16 window over 15 minutes", () => assert.equal(evaluate(policy({expiresAt:
  "2026-08-06T15:15:01Z"})).reasonCode, "controlled_write_policy_invalid"));
test("17 max request exactly one", () => assert.equal(evaluate(policy({
  maxAcceptedRequests: 2})).reasonCode, "controlled_write_policy_invalid"));
test("18 invalid mode rejected", () => assert.equal(evaluate(policy({
  expectedMode: "shadow"})).reasonCode, "controlled_write_policy_mode_mismatch"));
test("19 source fingerprint mismatch", () => assert.equal(evaluate(policy({
  sourceGenerationFingerprint: "a".repeat(64)})).reasonCode,
  "controlled_write_source_generation_mismatch"));
test("20 policy result contains fingerprints but no raw identity", () => {
  const output = JSON.stringify(evaluate());
  assert.equal(output.includes(UID), false); assert.equal(output.includes(ITEM), false);
});

test("21 lease identity", () => assert.equal(LEASE_ID,
  "ControlledWriteSingleUseLease/v1"));
test("22 missing lease", async () => assert.equal((await consumeControlledWriteLease(
  leaseInput(), createMemoryControlledWriteLeaseStore(null))).reasonCode,
  "controlled_write_lease_missing"));
test("23 malformed lease", async () => assert.equal((await consumeControlledWriteLease(
  leaseInput(), createMemoryControlledWriteLeaseStore(lease({extra: true}))))
  .reasonCode, "controlled_write_lease_invalid"));
for (const [name, changes] of [["purpose", {purpose: "shadow"}],
  ["mode", {expectedMode: "shadow"}], ["UID", {allowedUid: "other"}],
  ["item", {allowedItemId: "other"}], ["action", {allowedAction: "other"}],
  ["policy fingerprint", {policyFingerprint: "b".repeat(64)}]]) {
  test(`lease binding mismatch: ${name}`, async () => assert.equal(
    (await consumeControlledWriteLease(leaseInput(),
      createMemoryControlledWriteLeaseStore(lease(changes)))).reasonCode,
    "controlled_write_lease_binding_mismatch"));
}
test("30 expired lease", async () => assert.equal((await consumeControlledWriteLease(
  leaseInput(), createMemoryControlledWriteLeaseStore(lease({validFrom:
    "2026-08-06T14:45:00Z", expiresAt: "2026-08-06T15:00:00Z"}))))
  .reasonCode, "controlled_write_lease_expired"));
test("31 consumed lease", async () => assert.equal((await consumeControlledWriteLease(
  leaseInput(), createMemoryControlledWriteLeaseStore(lease({status: "consumed",
    acceptedRequestCount: 1})))).reasonCode, "controlled_write_lease_consumed"));
test("32 fresh lease accepted", async () => assert.equal((await
  consumeControlledWriteLease(leaseInput(),
    createMemoryControlledWriteLeaseStore(lease()))).ok, true));
test("33 second consume rejected", async () => { const store =
  createMemoryControlledWriteLeaseStore(lease()); await consumeControlledWriteLease(
    leaseInput(), store); assert.equal((await consumeControlledWriteLease(
      leaseInput(), store)).reasonCode, "controlled_write_lease_consumed"); });
test("34 concurrent consume has one winner", async () => { const store =
  createMemoryControlledWriteLeaseStore(lease()); const out = await Promise.all([
    consumeControlledWriteLease(leaseInput(), store),
    consumeControlledWriteLease(leaseInput(), store)]);
  assert.equal(out.filter((item) => item.ok).length, 1);
  assert.equal(store.snapshot().acceptedRequestCount, 1); });
test("35 no memory fallback in production factory", () => {
  const factory = productionFactory({resolveControlledWritePolicy: () => policy()});
  assert.throws(() => factory.get({mode: "controlled_write"}),
    /controlled_write_lease_store_factory_missing/);
});
test("36 Admin rejection maps fail closed", async () => { const store =
  createAdminControlledWriteLeaseStore({firestore: {collection: () => ({doc: () =>
    ({})}), runTransaction: async () => { throw new Error("down"); }}});
  assert.equal((await consumeControlledWriteLease(leaseInput(), store)).reasonCode,
    "controlled_write_lease_invalid"); });

test("37 controlled dependencies are lazy and mode-separated", () => {
  let policyCalls = 0; let leaseCalls = 0; const factory = productionFactory({
    resolveControlledWritePolicy: () => { policyCalls++; return policy(); },
    createControlledWriteLeaseStore: () => { leaseCalls++;
      return createMemoryControlledWriteLeaseStore(lease()); }});
  assert.equal(policyCalls, 0); factory.get({mode: "disabled"});
  assert.equal(policyCalls, 0); factory.get({mode: "shadow"});
  assert.equal(policyCalls, 0); factory.get({mode: "controlled_write"});
  assert.equal(policyCalls, 1); assert.equal(leaseCalls, 1);
});
test("38 gate order is before endpoint Firestore read", () => { const source =
  fs.readFileSync(path.join(__dirname, "wardrobe_authority_callable_exports.js"),
    "utf8"); assert.ok(source.indexOf("consumeControlledWriteLease({") <
    source.indexOf("authorityHandler.handle(data")); });
test("39 disabled gate remains first", () => { const source = fs.readFileSync(
  path.join(__dirname, "wardrobe_authority_callable_exports.js"), "utf8");
  assert.ok(source.indexOf("mode === AUTHORITY_MODES.disabled") <
    source.indexOf("dependencyFactory.get({mode})")); });
test("40 production adapter uses atomic transaction and server-only Rules path", () => {
  const source = fs.readFileSync(path.join(__dirname,
    "wardrobe_admin_controlled_write_lease_store.js"), "utf8");
  assert.match(source, /runTransaction/); assert.equal(COLLECTION,
    "wardrobeAuthorityShadowLeases");
});
test("41 operator helper creates no writes and redacts identity", () => {
  const artifacts = buildControlledWriteCanaryArtifacts({uid: UID, itemId: ITEM,
    validFrom: policy().validFrom, expiresAt: policy().expiresAt,
    leaseId: "controlled-lease"}); const output = JSON.stringify(artifacts.readiness);
  assert.equal(output.includes(UID), false); assert.equal(output.includes(ITEM), false);
  assert.equal(artifacts.readiness.writesPerformed, 0);
});
test("42 helper source has no Firebase or secret write", () => { const source =
  fs.readFileSync(path.join(__dirname,
    "scripts/build_controlled_write_canary_artifacts.js"), "utf8");
  assert.doesNotMatch(source, /firebase-admin|setSecret|transaction\.set/);
});
test("43 shadow source remains separate", () => { const shadow = fs.readFileSync(
  path.join(__dirname, "wardrobe_authority_shadow_runner.js"), "utf8");
  assert.doesNotMatch(shadow, /ControlledWriteActivationPolicy|consumeControlledWrite/);
});
test("44 rules deny shared control-plane collection", () => { const rules =
  fs.readFileSync(path.join(__dirname, "../firestore.rules"), "utf8");
  assert.match(rules, /match \/wardrobeAuthorityShadowLeases\/\{leaseId\}/);
});

test("45 configured source generation fingerprint is honored", () => {
  const expected = "a".repeat(64);
  assert.equal(evaluate(policy({sourceGenerationFingerprint: expected}), {},
    {sourceGenerationFingerprint: expected}).ok, true);
});
test("46 policy mismatch stops before lease and business dependencies", async () => {
  const probe = callableProbe({controlledWritePolicy: policy({allowedItemId:
    "different-item"})});
  await assert.rejects(() => probe.callable({itemId: ITEM,
    action: "analyze_current_source"}, callableContext()),
  (error) => error.code === "permission-denied" &&
      /controlled_write_item_not_allowlisted/.test(error.message));
  assert.deepEqual(probe.counts(), {controlledGets: 1, leaseConsumes: 0,
    businessGets: 0});
});
test("47 missing lease stops before business dependencies", async () => {
  const probe = callableProbe({leaseResult: {ok: false,
    reasonCode: "controlled_write_lease_missing"}});
  await assert.rejects(() => probe.callable({itemId: ITEM,
    action: "analyze_current_source"}, callableContext()),
  (error) => error.code === "failed-precondition" &&
      /controlled_write_lease_missing/.test(error.message));
  assert.deepEqual(probe.counts(), {controlledGets: 1, leaseConsumes: 1,
    businessGets: 0});
});
test("48 App Check gate stops before policy, lease, and business dependencies",
  async () => {
    const probe = callableProbe();
    await assert.rejects(() => probe.callable({itemId: ITEM,
      action: "analyze_current_source"}, callableContext({app: undefined})),
    (error) => error.code === "failed-precondition" &&
        /app_check_required_missing/.test(error.message));
    assert.deepEqual(probe.counts(), {controlledGets: 0, leaseConsumes: 0,
      businessGets: 0});
  });
test("49 client control-plane field stops before policy and lease", async () => {
  const probe = callableProbe();
  await assert.rejects(() => probe.callable({itemId: ITEM,
    action: "analyze_current_source", leaseId: "client-value"},
  callableContext()), (error) => error.code === "invalid-argument" &&
      /forbidden_request_field:leaseId/.test(error.message));
  assert.deepEqual(probe.counts(), {controlledGets: 0, leaseConsumes: 0,
    businessGets: 0});
});

function callableContext(overrides = {}) {
  return {auth: {uid: UID}, app: {appId: "verified-app"},
    rawRequest: {id: "request-1"}, ...overrides};
}

function callableProbe(options = {}) {
  let controlledGets = 0; let leaseConsumes = 0; let businessGets = 0;
  const fakeFunctions = {region() { return this; }, runWith() { return this; },
    https: {onCall(handler) { return handler; }, HttpsError: class extends Error {
      constructor(code, message) { super(message); this.code = code; }
    }}};
  const leaseStore = {async consumeAtomically(_leaseId, evaluator) {
    leaseConsumes++;
    if (options.leaseResult) return options.leaseResult;
    return evaluator(null);
  }};
  const dependencyFactory = {get(runtime = {}) {
    if (runtime.mode === "controlled_write") {
      controlledGets++;
      return {controlledWritePolicy: options.controlledWritePolicy || policy(),
        controlledWriteLeaseStore: leaseStore, serverNow: NOW,
        invocationIdFactory: () => "request-1"};
    }
    businessGets++;
    throw new Error("business_dependencies_must_not_be_created");
  }};
  const cohortPolicy = {evaluate({uid, mode}) { return uid === UID &&
    mode === "controlled_write" ? {ok: true} : {ok: false,
      reasonCode: "controlled_write_uid_not_allowlisted"}; }};
  const built = buildWardrobeAuthorityCallables({functions: fakeFunctions,
    dependencyFactory, cohortPolicy, resolveMode: () =>
      ({mode: "controlled_write"}), costGate: {begin: () => ({ok: true,
      release() {}})}});
  return {callable: built.authorityCallable, counts: () =>
    ({controlledGets, leaseConsumes, businessGets})};
}

function productionFactory(extra = {}) {
  return createWardrobeAuthorityProductionDependencies({config: {
    environmentMode: "production", projectId: "test-project",
    storageBucket: "test-project.appspot.com", region: "us-east1",
    visionSchemaVersion: 9, modelIdentifier: "gpt-4o-mini",
    promptVersion: "vision-v2-schema-9", qualificationVersion: "qualification-v1",
    revisionContractVersion: "wardrobe-qualification-revision-context-v1",
    persistenceSchemaVersion: 1}, memoryDocs: {}, storageMetadataClient: {},
  visionClient: {}, resolveShadowPolicy: () => ({enabled: false}),
  createShadowLeaseStore: () => ({}), ...extra});
}
