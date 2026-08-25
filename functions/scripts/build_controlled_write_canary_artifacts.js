"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {fingerprint} = require("../wardrobe_authority_redaction");
const {decodeControlledWritePolicy, fingerprintPolicy} =
  require("../controlled_write_activation_policy");
const {decodeLease, PURPOSE} = require("../controlled_write_single_use_lease");

const DEFAULT_OPERATOR_FILE = path.resolve(__dirname, "../..",
  ".local_audit/.operator_shadow_smoke_candidate.json");

function buildControlledWriteCanaryArtifacts(input) {
  const validFromMs = Date.parse(input.validFrom);
  const expiresAtMs = Date.parse(input.expiresAt);
  if (!Number.isFinite(validFromMs) || !Number.isFinite(expiresAtMs) ||
      expiresAtMs <= validFromMs || expiresAtMs - validFromMs > 15 * 60 * 1000) {
    throw new Error("controlled_write_operator_window_invalid");
  }
  const leaseId = input.leaseId || crypto.randomUUID();
  const policy = decodeControlledWritePolicy({contractVersion: 1, enabled: true,
    allowedUid: input.uid, allowedItemId: input.itemId,
    allowedAction: "analyze_current_source", leaseId,
    validFrom: new Date(validFromMs).toISOString(),
    expiresAt: new Date(expiresAtMs).toISOString(), maxAcceptedRequests: 1,
    expectedMode: "controlled_write",
    sourceGenerationFingerprint: input.sourceGenerationFingerprint || null,
    policyVersion: input.policyVersion || "controlled-write-canary-v1",
    provenance: {source: "offline_operator_helper"}});
  const policyFingerprint = fingerprintPolicy(policy);
  const lease = decodeLease({contractVersion: 1, leaseId, policyFingerprint,
    allowedUid: policy.allowedUid, allowedItemId: policy.allowedItemId,
    allowedAction: policy.allowedAction, validFrom: policy.validFrom,
    expiresAt: policy.expiresAt, maxAcceptedRequests: 1,
    acceptedRequestCount: 0, status: "fresh", consumedAt: null,
    consumedByInvocationId: null, purpose: PURPOSE,
    expectedMode: "controlled_write",
    createdAt: input.createdAt || new Date(validFromMs).toISOString()});
  return Object.freeze({policy, lease, readiness: Object.freeze({
    policyContract: "ControlledWriteActivationPolicy/v1",
    leaseContract: "ControlledWriteSingleUseLease/v1",
    uidFingerprint: fingerprint(policy.allowedUid),
    itemFingerprint: fingerprint(policy.allowedItemId),
    policyFingerprint, leaseFingerprint: fingerprint(leaseId),
    action: policy.allowedAction, windowMinutes:
      (expiresAtMs - validFromMs) / 60000, writesPerformed: 0})});
}

function loadOperatorCandidate(file = DEFAULT_OPERATOR_FILE) {
  const raw = JSON.parse(fs.readFileSync(file, "utf8"));
  const uid = String(raw.uid || raw.userId || "").trim();
  const itemId = String(raw.itemId || raw.wardrobeItemId || "").trim();
  if (!uid || !itemId) throw new Error("controlled_write_operator_candidate_invalid");
  return Object.freeze({uid, itemId});
}

if (require.main === module) {
  const candidate = loadOperatorCandidate();
  const validFrom = process.argv[2];
  const expiresAt = process.argv[3];
  const artifacts = buildControlledWriteCanaryArtifacts({...candidate,
    validFrom, expiresAt});
  process.stdout.write(`${JSON.stringify(artifacts.readiness, null, 2)}\n`);
}

module.exports = {DEFAULT_OPERATOR_FILE, buildControlledWriteCanaryArtifacts,
  loadOperatorCandidate};
