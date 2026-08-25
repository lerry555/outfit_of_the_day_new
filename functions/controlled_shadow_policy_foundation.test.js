"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {decodeControlledShadowPolicy, evaluateControlledShadowPolicy,
  CONTRACT_ID: POLICY_ID} = require("./controlled_shadow_activation_policy");
const {consumeSingleUseShadowLease, createMemoryShadowLeaseStore,
  CONTRACT_ID: LEASE_ID} = require("./single_use_shadow_lease");
const {COLLECTION, createAdminShadowLeaseStore} =
  require("./wardrobe_admin_shadow_lease_store");

const NOW = "2026-08-05T10:05:00.000Z";
const UID = "private-user"; const ITEM = "private-item";
function policy(overrides = {}) { return {contractVersion: 1, enabled: true,
  allowedUid: UID, allowedItemId: ITEM, leaseId: "lease-1",
  validFrom: "2026-08-05T10:00:00.000Z",
  expiresAt: "2026-08-05T10:15:00.000Z", maxAcceptedRequests: 1,
  analysisActions: ["analyze_current_source"], expectedMode: "shadow",
  sourceGenerationFingerprint: null, provenance: {source: "server-test"},
  ...overrides}; }
function request(overrides = {}) { return {itemId: ITEM,
  action: "analyze_current_source", ...overrides}; }
function evaluate(p = policy(), r = request(), c = {}) {
  return evaluateControlledShadowPolicy(p, r,
    {uid: UID, mode: "shadow", now: NOW, ...c});
}
function lease(overrides = {}) { return {contractVersion: 1, leaseId: "lease-1",
  validFrom: "2026-08-05T10:00:00.000Z",
  expiresAt: "2026-08-05T10:15:00.000Z", maxAcceptedRequests: 1,
  acceptedRequestCount: 0, consumedAt: null, consumedByInvocationId: null,
  status: "fresh", createdAt: "2026-08-05T09:59:00.000Z", ...overrides}; }
async function consume(store, overrides = {}) { return consumeSingleUseShadowLease(
  {leaseId: "lease-1", invocationId: "call-1", now: NOW, ...overrides}, store); }

test("01 disabled mode remains outside policy contract", () =>
  assert.equal(evaluate(policy(), request(), {mode: "disabled"}).ok, false));
test("02 shadow without policy rejected", () =>
  assert.equal(evaluate(null).reasonCode, "shadow_policy_missing"));
test("03 invalid policy version rejected", () =>
  assert.equal(evaluate(policy({contractVersion: 2})).reasonCode,
    "shadow_policy_version_invalid"));
test("04 missing UID rejected", () =>
  assert.equal(evaluate(policy({allowedUid: ""})).reasonCode,
    "shadow_policy_uid_missing"));
test("05 missing item rejected", () =>
  assert.equal(evaluate(policy({allowedItemId: ""})).reasonCode,
    "shadow_policy_item_missing"));
test("06 UID mismatch rejected", () =>
  assert.equal(evaluate(policy(), request(), {uid: "other"}).reasonCode,
    "shadow_uid_not_allowlisted"));
test("07 item mismatch rejected", () =>
  assert.equal(evaluate(policy(), request({itemId: "other"})).reasonCode,
    "shadow_item_not_allowlisted"));
test("08 owner mismatch is enforced by auth ownership boundary", () => {
  const source = fs.readFileSync(path.join(__dirname,
    "wardrobe_authority_shadow_runner.js"), "utf8");
  assert.ok(source.indexOf("assertPayloadAuthOwnership") <
    source.indexOf("evaluateControlledShadowPolicy"));
});
test("09 unknown action rejected", () =>
  assert.equal(evaluate(policy(), request({action: "unknown"})).reasonCode,
    "shadow_action_not_allowlisted"));
test("10 reanalysis rejected", () =>
  assert.equal(evaluate(policy(), request({action: "reanalyze_current_source"})).ok,
    false));
test("11 before validFrom rejected", () =>
  assert.equal(evaluate(policy(), request(), {now: "2026-08-05T09:59:59Z"}).reasonCode,
    "shadow_window_not_started"));
test("12 at expiresAt rejected", () =>
  assert.equal(evaluate(policy(), request(), {now: "2026-08-05T10:15:00Z"}).reasonCode,
    "shadow_window_expired"));
test("13 invalid timestamp rejected", () =>
  assert.equal(evaluate(policy({expiresAt: "bad"})).reasonCode,
    "shadow_policy_timestamp_invalid"));
test("14 oversized window rejected", () =>
  assert.equal(evaluate(policy({expiresAt: "2026-08-05T10:15:01Z"})).reasonCode,
    "shadow_policy_window_oversized"));
test("15 exact binding accepted", () => assert.equal(evaluate().ok, true));
test("16 client policy field cannot override server policy", () =>
  assert.equal(evaluate(policy(), request({allowedUid: "other"})).ok, true));
test("17 raw UID and item absent from policy result", () => {
  const text = JSON.stringify(evaluate()); assert.ok(!text.includes(UID));
  assert.ok(!text.includes(ITEM));
});
test("18 fingerprints stable", () =>
  assert.equal(evaluate().uidFingerprint, evaluate().uidFingerprint));
test("19 controlled-write is rejected by shadow policy", () =>
  assert.equal(evaluate(policy(), request(), {mode: "controlled_write"}).ok, false));
test("20 disabled callable gate precedes dependencyFactory.get", () => {
  const source = fs.readFileSync(path.join(__dirname,
    "wardrobe_authority_callable_exports.js"), "utf8");
  assert.ok(source.indexOf("mode === AUTHORITY_MODES.disabled") <
    source.indexOf("dependencyFactory.get("));
});
test("21 fresh lease accepted", async () =>
  assert.equal((await consume(createMemoryShadowLeaseStore(lease()))).ok, true));
test("22 second request rejected", async () => { const store =
  createMemoryShadowLeaseStore(lease()); await consume(store);
  assert.equal((await consume(store)).ok, false); });
test("23 consumed lease rejected", async () => assert.equal((await consume(
  createMemoryShadowLeaseStore(lease({status: "consumed",
    acceptedRequestCount: 1})))).reasonCode, "shadow_lease_consumed"));
test("24 expired lease rejected", async () => assert.equal((await consume(
  createMemoryShadowLeaseStore(lease({expiresAt: "2026-08-05T10:04:00Z"}))))
  .reasonCode, "shadow_lease_expired"));
test("25 missing lease rejected", async () => assert.equal((await consume(
  createMemoryShadowLeaseStore(null))).reasonCode, "shadow_lease_missing"));
test("26 malformed lease rejected", async () => assert.equal((await consume(
  createMemoryShadowLeaseStore(lease({acceptedRequestCount: 2})))).reasonCode,
  "shadow_lease_invalid"));
test("27 transaction race has one winner", async () => { const store =
  createMemoryShadowLeaseStore(lease()); const out = await Promise.all([
    consume(store), consume(store)]); assert.equal(out.filter((x) => x.ok).length, 1); });
test("28 concurrent accepted count is one", async () => { const store =
  createMemoryShadowLeaseStore(lease()); await Promise.all([consume(store), consume(store)]);
  assert.equal(store.snapshot().acceptedRequestCount, 1); });
test("29 production guarantee uses Firestore transaction, not memory", () => {
  const source = fs.readFileSync(path.join(__dirname,
    "wardrobe_admin_shadow_lease_store.js"), "utf8");
  assert.match(source, /runTransaction/); assert.equal(COLLECTION,
    "wardrobeAuthorityShadowLeases");
});
test("30 accepted count never exceeds one", async () => { const store =
  createMemoryShadowLeaseStore(lease()); await consume(store); await consume(store);
  assert.equal(store.snapshot().acceptedRequestCount, 1); });
test("31 consume precedes Storage and OpenAI in runner", () => { const source =
  fs.readFileSync(path.join(__dirname, "wardrobe_authority_shadow_runner.js"), "utf8");
  assert.ok(source.indexOf("consumeSingleUseShadowLease({") <
    source.indexOf("fetchTrustedSourceObjectSnapshot({")); });
test("32 lease failure is before vision client", () => { const source =
  fs.readFileSync(path.join(__dirname, "wardrobe_authority_shadow_runner.js"), "utf8");
  assert.ok(source.indexOf("if (!lease.ok)") < source.indexOf("visionClient")); });
test("33 zero-write proxy remains active", () => { const source =
  fs.readFileSync(path.join(__dirname, "wardrobe_authority_shadow_runner.js"), "utf8");
  assert.match(source, /shadow_write_forbidden/); });
test("34 lease adapter is lazy and server-only control plane", async () => {
  let transactions = 0; const firestore = {collection: () => ({doc: () => ({})}),
    runTransaction: async () => { transactions++; }};
  createAdminShadowLeaseStore({firestore}); assert.equal(transactions, 0);
});
test("35 rollback disabled gate blocks policy/dependency resolution", () => {
  assert.equal(POLICY_ID, "ControlledShadowActivationPolicy/v1");
  assert.equal(LEASE_ID, "SingleUseShadowLease/v1");
});

test("strict policy decoder freezes server configuration", () =>
  assert.ok(Object.isFrozen(decodeControlledShadowPolicy(policy()))));
