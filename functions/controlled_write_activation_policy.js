"use strict";

const crypto = require("node:crypto");
const {fingerprint} = require("./wardrobe_authority_redaction");

const CONTRACT_ID = "ControlledWriteActivationPolicy/v1";
const CONTRACT_VERSION = 1;
const MAX_WINDOW_MS = 15 * 60 * 1000;
const ACTION = "analyze_current_source";

function decodeControlledWritePolicy(raw) {
  object(raw, "controlled_write_policy_missing");
  exact(raw, ["contractVersion", "enabled", "allowedUid", "allowedItemId",
    "allowedAction", "leaseId", "validFrom", "expiresAt",
    "maxAcceptedRequests", "expectedMode", "sourceGenerationFingerprint",
    "policyVersion", "provenance"]);
  if (raw.contractVersion !== CONTRACT_VERSION) fail("controlled_write_policy_invalid");
  if (raw.enabled !== true) fail("controlled_write_policy_invalid");
  const allowedUid = text(raw.allowedUid, "controlled_write_policy_invalid");
  const allowedItemId = text(raw.allowedItemId, "controlled_write_policy_invalid");
  const leaseId = text(raw.leaseId, "controlled_write_policy_invalid");
  const policyVersion = text(raw.policyVersion, "controlled_write_policy_invalid");
  if (raw.allowedAction !== ACTION) fail("controlled_write_action_not_allowed");
  if (raw.expectedMode !== "controlled_write") {
    fail("controlled_write_policy_mode_mismatch");
  }
  if (raw.maxAcceptedRequests !== 1) fail("controlled_write_policy_invalid");
  const validFromMs = instant(raw.validFrom);
  const expiresAtMs = instant(raw.expiresAt);
  if (expiresAtMs <= validFromMs || expiresAtMs - validFromMs > MAX_WINDOW_MS) {
    fail("controlled_write_policy_invalid");
  }
  if (raw.sourceGenerationFingerprint != null &&
      !/^[a-f0-9]{64}$/.test(String(raw.sourceGenerationFingerprint))) {
    fail("controlled_write_policy_invalid");
  }
  object(raw.provenance, "controlled_write_policy_invalid");
  const decoded = {...raw, allowedUid, allowedItemId, leaseId, policyVersion,
    validFrom: new Date(validFromMs).toISOString(),
    expiresAt: new Date(expiresAtMs).toISOString()};
  return deepFreeze(decoded);
}

function evaluateControlledWritePolicy(raw, request, context) {
  let policy;
  try { policy = decodeControlledWritePolicy(raw); } catch (error) {
    return denied(normalizePolicyError(error));
  }
  if (context.mode !== "controlled_write") {
    return denied("controlled_write_policy_mode_mismatch");
  }
  if (context.uid !== policy.allowedUid) {
    return denied("controlled_write_uid_not_allowlisted");
  }
  if (!request || request.itemId !== policy.allowedItemId) {
    return denied("controlled_write_item_not_allowlisted");
  }
  if (request.action !== policy.allowedAction || request.action !== ACTION) {
    return denied("controlled_write_action_not_allowed");
  }
  let now;
  try { now = instant(context.now); } catch (_) {
    return denied("controlled_write_policy_invalid");
  }
  if (now < Date.parse(policy.validFrom)) {
    return denied("controlled_write_window_not_active");
  }
  if (now >= Date.parse(policy.expiresAt)) {
    return denied("controlled_write_window_expired");
  }
  if (policy.sourceGenerationFingerprint != null &&
      policy.sourceGenerationFingerprint !== context.sourceGenerationFingerprint) {
    return denied("controlled_write_source_generation_mismatch");
  }
  const accepted = {ok: true, contractId: CONTRACT_ID,
    reasonCode: "controlled_write_policy_accepted", leaseId: policy.leaseId,
    policyFingerprint: fingerprintPolicy(policy),
    uidFingerprint: fingerprint(policy.allowedUid),
    itemFingerprint: fingerprint(policy.allowedItemId)};
  Object.defineProperty(accepted, "_policy", {value: policy, enumerable: false});
  return deepFreeze(accepted);
}

function fingerprintPolicy(policy) {
  return crypto.createHash("sha256")
    .update(JSON.stringify(canonicalize(policy)), "utf8").digest("hex");
}

function normalizePolicyError(error) {
  const code = String(error && error.message || "controlled_write_policy_invalid");
  if (code === "controlled_write_policy_missing") return code;
  if (code === "controlled_write_policy_mode_mismatch") return code;
  if (code === "controlled_write_action_not_allowed") return code;
  return "controlled_write_policy_invalid";
}
function denied(reasonCode) { return Object.freeze({ok: false,
  contractId: CONTRACT_ID, reasonCode}); }
function instant(value) { const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) fail("controlled_write_policy_invalid"); return parsed; }
function text(value, code) { if (typeof value !== "string" || !value.trim()) fail(code);
  return value.trim(); }
function object(value, code) { if (!value || typeof value !== "object" ||
  Array.isArray(value)) fail(code); }
function exact(value, keys) { for (const key of Object.keys(value)) {
  if (!keys.includes(key)) fail("controlled_write_policy_invalid");
} }
function canonicalize(value) { if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") { const out = {};
    for (const key of Object.keys(value).sort()) out[key] = canonicalize(value[key]);
    return out; } return value; }
function deepFreeze(value) { if (value && typeof value === "object" &&
  !Object.isFrozen(value)) { Object.values(value).forEach(deepFreeze);
  Object.freeze(value); } return value; }
function fail(code) { throw new Error(code); }

module.exports = {ACTION, CONTRACT_ID, CONTRACT_VERSION, MAX_WINDOW_MS,
  decodeControlledWritePolicy, evaluateControlledWritePolicy, fingerprintPolicy};
