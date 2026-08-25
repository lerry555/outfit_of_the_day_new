"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {SECRET_NAME, CONTRACT_ID, resolveControlledShadowPolicy,
  controlledShadowPolicyAvailability} = require("./controlled_shadow_policy_config");
const {createAdminShadowLeaseStore, COLLECTION} =
  require("./wardrobe_admin_shadow_lease_store");
const {consumeSingleUseShadowLease} = require("./single_use_shadow_lease");
const {buildControlledShadowArtifacts} =
  require("./scripts/build_controlled_shadow_policy_payload");
const {createWardrobeAuthorityProductionDependencies} =
  require("./wardrobe_authority_production_dependencies");

const NOW = "2026-08-05T10:05:00.000Z";
function raw(overrides = {}) { return {contractVersion: 1, enabled: true,
  allowedUid: "uid-secret", allowedItemId: "item-secret", leaseId: "lease-1",
  validFrom: "2026-08-05T10:00:00.000Z",
  expiresAt: "2026-08-05T10:15:00.000Z", maxAcceptedRequests: 1,
  analysisActions: ["analyze_current_source"], expectedMode: "shadow",
  sourceGenerationFingerprint: null, provenance: {source: "test"}, ...overrides}; }
function secret(value) { return {value: () => value}; }
function lease(overrides = {}) { return {contractVersion: 1, leaseId: "lease-1",
  validFrom: "2026-08-05T10:00:00.000Z",
  expiresAt: "2026-08-05T10:15:00.000Z", maxAcceptedRequests: 1,
  acceptedRequestCount: 0, consumedAt: null, consumedByInvocationId: null,
  status: "fresh", createdAt: NOW, ...overrides}; }
function fakeFirestore(seed = lease(), options = {}) { let value = seed; let queue =
  Promise.resolve(); let writes = 0; return {collection(name) { assert.equal(name,
    COLLECTION); return {doc: () => ({get: async () => { if (options.readReject)
      throw new Error("firestore down"); return {exists: !!value, data: () => value}; }})}; },
  runTransaction(callback) { if (options.transactionReject)
    return Promise.reject(new Error("firestore down")); const run = queue.then(() =>
      callback({get: async () => ({exists: !!value, data: () => structuredClone(value)}),
        set: (_ref, next) => {writes++; value = structuredClone(next);}}));
    queue = run.catch(() => {}); return run; }, snapshot: () => value,
  writes: () => writes}; }
function factory(options = {}) { return createWardrobeAuthorityProductionDependencies({
  config: {environmentMode: "production", projectId: "test-project",
    storageBucket: "test-project.appspot.com", region: "us-east1",
    visionSchemaVersion: 9, modelIdentifier: "gpt-4o-mini",
    promptVersion: "vision-v2-schema-9", qualificationVersion: "qualification-v1",
    revisionContractVersion: "wardrobe-qualification-revision-context-v1",
    persistenceSchemaVersion: 1},
  memoryDocs: {}, storageMetadataClient: {}, visionClient: {}, ...options}); }

test("01 exact secret name and contract", () => { assert.equal(SECRET_NAME,
  "WARDROBE_SHADOW_POLICY"); assert.equal(CONTRACT_ID,
  "ControlledShadowPolicyConfiguration/v1"); });
test("02 valid policy JSON", () => assert.equal(resolveControlledShadowPolicy(
  secret(JSON.stringify(raw()))).enabled, true));
test("03 invalid JSON rejected", () => assert.throws(() =>
  resolveControlledShadowPolicy(secret("{")), /shadow_policy_json_invalid/));
test("04 unknown field rejected", () => assert.throws(() =>
  resolveControlledShadowPolicy(secret(JSON.stringify(raw({extra: true})))),
  /shadow_policy_unknown_field/));
test("05 missing UID rejected", () => assert.throws(() =>
  resolveControlledShadowPolicy(secret(JSON.stringify(raw({allowedUid: ""})))),
  /shadow_policy_uid_missing/));
test("06 missing item rejected", () => assert.throws(() =>
  resolveControlledShadowPolicy(secret(JSON.stringify(raw({allowedItemId: ""})))),
  /shadow_policy_item_missing/));
test("07 invalid action rejected", () => assert.throws(() =>
  resolveControlledShadowPolicy(secret(JSON.stringify(raw({analysisActions: ["x"]})))),
  /shadow_policy_action_invalid/));
test("08 invalid mode rejected", () => assert.throws(() =>
  resolveControlledShadowPolicy(secret(JSON.stringify(raw({expectedMode: "disabled"})))),
  /shadow_policy_mode_invalid/));
test("09 invalid timestamps rejected", () => assert.throws(() =>
  resolveControlledShadowPolicy(secret(JSON.stringify(raw({validFrom: "bad"})))),
  /shadow_policy_timestamp_invalid/));
test("10 oversized window rejected", () => assert.throws(() =>
  resolveControlledShadowPolicy(secret(JSON.stringify(raw({expiresAt:
    "2026-08-05T10:15:01Z"})))), /shadow_policy_window_oversized/));
test("11 request maximum must be one", () => assert.throws(() =>
  resolveControlledShadowPolicy(secret(JSON.stringify(raw({maxAcceptedRequests: 2})))),
  /shadow_policy_request_limit_invalid/));
test("12 readiness never exposes raw policy", () => { const out = JSON.stringify(
  controlledShadowPolicyAvailability(secret(JSON.stringify(raw()))));
  assert.ok(!out.includes("uid-secret")); assert.ok(!out.includes("item-secret")); });
test("13 disabled path does not resolve config", () => { let calls = 0; const f =
  factory({resolveShadowPolicy: () => {calls++;}}); assert.equal(f.peekConstructed(), false);
  assert.equal(calls, 0); });
test("14 shadow missing config rejected", () => assert.throws(() =>
  factory().get({mode: "shadow"}), /shadow_policy_resolver_missing/));
test("15 controlled write does not reuse shadow policy", () => { let calls = 0;
  factory({resolveShadowPolicy: () => {calls++;},
    resolveControlledWritePolicy: () => ({}),
    createControlledWriteLeaseStore: () => ({})})
    .get({mode: "controlled_write"});
  assert.equal(calls, 0); });
test("16 deterministic redacted fingerprints", () => { const a =
  buildControlledShadowArtifacts({uid: "u", itemId: "i", validFrom: raw().validFrom,
    expiresAt: raw().expiresAt, leaseId: "l"}); const b =
  buildControlledShadowArtifacts({uid: "u", itemId: "i", validFrom: raw().validFrom,
    expiresAt: raw().expiresAt, leaseId: "l"}); assert.deepEqual(a.readiness,
    b.readiness); });
test("17 missing lease", async () => assert.equal((await createAdminShadowLeaseStore(
  {firestore: fakeFirestore(null)}).read("lease-1")).reasonCode,
  "shadow_lease_missing"));
test("18 valid fresh lease read", async () => assert.equal((await
  createAdminShadowLeaseStore({firestore: fakeFirestore()}).read("lease-1")).ok, true));
test("19 consumed lease rejected", async () => { const store = createAdminShadowLeaseStore(
  {firestore: fakeFirestore(lease({status: "consumed", acceptedRequestCount: 1}))});
  assert.equal((await consumeSingleUseShadowLease({leaseId: "lease-1", now: NOW,
    invocationId: "i"}, store)).reasonCode, "shadow_lease_consumed"); });
test("20 expired lease rejected", async () => { const store = createAdminShadowLeaseStore(
  {firestore: fakeFirestore(lease({expiresAt: "2026-08-05T10:04:00Z"}))});
  assert.equal((await consumeSingleUseShadowLease({leaseId: "lease-1", now: NOW,
    invocationId: "i"}, store)).reasonCode, "shadow_lease_expired"); });
test("21 malformed lease rejected", async () => { const store = createAdminShadowLeaseStore(
  {firestore: fakeFirestore(lease({acceptedRequestCount: 3}))}); assert.equal((await
  consumeSingleUseShadowLease({leaseId: "lease-1", now: NOW, invocationId: "i"}, store))
  .reasonCode, "shadow_lease_invalid"); });
test("22 atomic consume writes once", async () => { const db = fakeFirestore(); const store =
  createAdminShadowLeaseStore({firestore: db}); assert.equal((await
  consumeSingleUseShadowLease({leaseId: "lease-1", now: NOW, invocationId: "i"}, store)).ok,
  true); assert.equal(db.writes(), 1); });
test("23 concurrent consume has one winner", async () => { const db = fakeFirestore();
  const store = createAdminShadowLeaseStore({firestore: db}); const input =
  {leaseId: "lease-1", now: NOW, invocationId: "i"}; const out = await Promise.all([
    consumeSingleUseShadowLease(input, store), consumeSingleUseShadowLease(input, store)]);
  assert.equal(out.filter((x) => x.ok).length, 1); });
test("24 count never exceeds one", async () => { const db = fakeFirestore(); const store =
  createAdminShadowLeaseStore({firestore: db}); const input = {leaseId: "lease-1", now: NOW,
    invocationId: "i"}; await consumeSingleUseShadowLease(input, store);
  await consumeSingleUseShadowLease(input, store); assert.equal(db.snapshot()
    .acceptedRequestCount, 1); });
test("25 consumedAt uses injected server clock", async () => { const db = fakeFirestore();
  await consumeSingleUseShadowLease({leaseId: "lease-1", now: NOW, invocationId: "i"},
    createAdminShadowLeaseStore({firestore: db})); assert.equal(db.snapshot().consumedAt, NOW); });
test("26 invocation ID recorded", async () => { const db = fakeFirestore(); await
  consumeSingleUseShadowLease({leaseId: "lease-1", now: NOW, invocationId: "call-x"},
    createAdminShadowLeaseStore({firestore: db})); assert.equal(db.snapshot()
    .consumedByInvocationId, "call-x"); });
test("27 adapter path cannot address business data", () => assert.equal(COLLECTION,
  "wardrobeAuthorityShadowLeases"));
test("28 production factory has no memory lease fallback", () => assert.throws(() =>
  factory({resolveShadowPolicy: () => raw()}).get({mode: "shadow"}),
  /shadow_lease_store_factory_missing/));
test("29 Firestore read rejection mapped", async () => assert.equal((await
  createAdminShadowLeaseStore({firestore: fakeFirestore(null, {readReject: true})})
    .read("lease-1")).reasonCode, "shadow_lease_read_failed"));
test("30 transaction rejection mapped", async () => { const store =
  createAdminShadowLeaseStore({firestore: fakeFirestore(lease(),
    {transactionReject: true})}); assert.equal((await consumeSingleUseShadowLease(
    {leaseId: "lease-1", now: NOW, invocationId: "i"}, store)).reasonCode,
  "shadow_lease_transaction_failed"); });

test("helper source does not log raw identity", () => { const source = fs.readFileSync(
  path.join(__dirname, "scripts/build_controlled_shadow_policy_payload.js"), "utf8");
  assert.doesNotMatch(source, /console\.log/); });
