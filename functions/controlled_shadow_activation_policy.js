"use strict";

const {fingerprint} = require("./wardrobe_authority_redaction");
const CONTRACT_ID = "ControlledShadowActivationPolicy/v1";
const CONTRACT_VERSION = 1; const MAX_WINDOW_MS = 15 * 60 * 1000;
const ACTION = "analyze_current_source";

function decodeControlledShadowPolicy(raw) {
  object(raw, "shadow_policy_missing");
  exact(raw, ["contractVersion", "enabled", "allowedUid", "allowedItemId",
    "leaseId", "validFrom", "expiresAt", "maxAcceptedRequests",
    "analysisActions", "expectedMode", "sourceGenerationFingerprint",
    "provenance"]);
  if (raw.contractVersion !== 1) fail("shadow_policy_version_invalid");
  if (raw.enabled !== true) fail("shadow_policy_disabled");
  const allowedUid = text(raw.allowedUid, "shadow_policy_uid_missing");
  const allowedItemId = text(raw.allowedItemId, "shadow_policy_item_missing");
  const leaseId = text(raw.leaseId, "shadow_policy_lease_missing");
  const validFrom = instant(raw.validFrom); const expiresAt = instant(raw.expiresAt);
  if (expiresAt <= validFrom) fail("shadow_policy_window_invalid");
  if (expiresAt - validFrom > MAX_WINDOW_MS) fail("shadow_policy_window_oversized");
  if (raw.maxAcceptedRequests !== 1) fail("shadow_policy_request_limit_invalid");
  if (!Array.isArray(raw.analysisActions) || raw.analysisActions.length !== 1 ||
      raw.analysisActions[0] !== ACTION) fail("shadow_policy_action_invalid");
  if (raw.expectedMode !== "shadow") fail("shadow_policy_mode_invalid");
  if (raw.sourceGenerationFingerprint != null &&
      (typeof raw.sourceGenerationFingerprint !== "string" ||
       !/^[a-f0-9]{64}$/.test(raw.sourceGenerationFingerprint))) {
    fail("shadow_policy_source_fingerprint_invalid");
  }
  object(raw.provenance, "shadow_policy_provenance_invalid");
  return deepFreeze({...raw, allowedUid, allowedItemId, leaseId,
    validFrom: new Date(validFrom).toISOString(),
    expiresAt: new Date(expiresAt).toISOString()});
}

function evaluateControlledShadowPolicy(raw, request, context) {
  let policy; try { policy = decodeControlledShadowPolicy(raw); } catch (e) {
    return denied(e.message); }
  if (context.mode !== "shadow") return denied("shadow_policy_mode_mismatch");
  if (context.uid !== policy.allowedUid) return denied("shadow_uid_not_allowlisted");
  if (request.itemId !== policy.allowedItemId) return denied("shadow_item_not_allowlisted");
  if (request.action !== ACTION) return denied("shadow_action_not_allowlisted");
  let now; try { now = instant(context.now); } catch (_) {
    return denied("shadow_policy_clock_invalid");
  }
  if (now < Date.parse(policy.validFrom)) return denied("shadow_window_not_started");
  if (now >= Date.parse(policy.expiresAt)) return denied("shadow_window_expired");
  return deepFreeze({ok: true, contractId: CONTRACT_ID, leaseId: policy.leaseId,
    uidFingerprint: fingerprint(policy.allowedUid),
    itemFingerprint: fingerprint(policy.allowedItemId), reasonCode: "shadow_policy_accepted"});
}
function denied(reasonCode) { return Object.freeze({ok: false, contractId: CONTRACT_ID,
  reasonCode}); }
function instant(v) { const n = Date.parse(v); if (!Number.isFinite(n))
  fail("shadow_policy_timestamp_invalid"); return n; }
function text(v, c) { if (typeof v !== "string" || !v.trim()) fail(c); return v.trim(); }
function object(v, c) { if (!v || typeof v !== "object" || Array.isArray(v)) fail(c); }
function exact(v, keys) { for (const k of Object.keys(v)) if (!keys.includes(k))
  fail(`shadow_policy_unknown_field:${k}`); }
function deepFreeze(v) { if (v && typeof v === "object" && !Object.isFrozen(v)) {
  Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; }
function fail(c) { throw new Error(c); }
module.exports = {ACTION, CONTRACT_ID, CONTRACT_VERSION, MAX_WINDOW_MS,
  decodeControlledShadowPolicy, evaluateControlledShadowPolicy};
