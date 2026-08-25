"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const {fingerprint} = require("../wardrobe_authority_redaction");
const {decodeControlledShadowPolicy} =
  require("../controlled_shadow_activation_policy");

function buildControlledShadowArtifacts({uid, itemId, validFrom, expiresAt,
  sourceGenerationFingerprint = null, leaseId = crypto.randomUUID()}) {
  const policy = decodeControlledShadowPolicy({contractVersion: 1, enabled: true,
    allowedUid: uid, allowedItemId: itemId, leaseId, validFrom, expiresAt,
    maxAcceptedRequests: 1, analysisActions: ["analyze_current_source"],
    expectedMode: "shadow", sourceGenerationFingerprint,
    provenance: {source: "operator_generated"}});
  const lease = Object.freeze({contractVersion: 1, leaseId,
    validFrom: policy.validFrom, expiresAt: policy.expiresAt,
    maxAcceptedRequests: 1, acceptedRequestCount: 0, consumedAt: null,
    consumedByInvocationId: null, status: "fresh",
    createdAt: new Date().toISOString()});
  return Object.freeze({policy, lease, readiness: Object.freeze({
    uidFingerprint: fingerprint(uid), itemFingerprint: fingerprint(itemId),
    leaseFingerprint: fingerprint(leaseId), windowMinutes:
      (Date.parse(policy.expiresAt) - Date.parse(policy.validFrom)) / 60000})});
}

function main(argv) {
  const [uid, itemId, validFrom, expiresAt, policyFile, leaseFile] = argv;
  if (!uid || !itemId || !validFrom || !expiresAt || !policyFile || !leaseFile) {
    throw new Error("usage: uid itemId validFrom expiresAt policyFile leaseFile");
  }
  const artifacts = buildControlledShadowArtifacts({uid, itemId, validFrom,
    expiresAt});
  fs.writeFileSync(policyFile, JSON.stringify(artifacts.policy, null, 2),
    {encoding: "utf8", flag: "wx"});
  fs.writeFileSync(leaseFile, JSON.stringify(artifacts.lease, null, 2),
    {encoding: "utf8", flag: "wx"});
  process.stdout.write(`${JSON.stringify(artifacts.readiness)}\n`);
}

if (require.main === module) main(process.argv.slice(2));
module.exports = {buildControlledShadowArtifacts};
