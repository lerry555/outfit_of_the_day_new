"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeNegativeClaimOracle,
  qualifyNegativeClaims,
} = require("./vision_negative_claim_corroborator");

const DEFAULT_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_negative_claim_corroborator_oracle_manifest.json");
const SOURCE = path.resolve(__dirname, "vision_negative_claim_corroborator.js");

function runNegativeClaimParity({manifestPath = DEFAULT_MANIFEST} = {}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== PROVIDER_ID ||
      manifest.providerVersion !== PROVIDER_VERSION) {
    throw new Error("negative_claim_manifest_invalid");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) throw new Error("negative_claim_ready_invalid");
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  let invocationCount = 0;
  const scenarios = ready.map((entry) => {
    const bytes = fs.readFileSync(path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(bytes) !== entry.oracleSha256) {
      throw new Error(`negative_claim_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = decodeNegativeClaimOracle(JSON.parse(bytes));
    if (oracle.scenarioId !== entry.scenarioId) {
      throw new Error(`negative_claim_scenario_mismatch:${entry.scenarioId}`);
    }
    const invocations = oracle.invocations.map((item) => {
      const output = qualifyNegativeClaims(item.providerInput);
      const differences = diff(item.providerOutput, output);
      return {
        invocationId: item.invocationId,
        viewId: item.viewId,
        viewIndex: item.viewIndex,
        passed: differences.length === 0,
        differences,
        outputSha256: sha256(canonicalBytes(output)),
      };
    });
    invocationCount += invocations.length;
    return {
      scenarioId: entry.scenarioId,
      passed: invocations.every((item) => item.passed),
      invocationCount: invocations.length,
      invocations,
      outputSha256: sha256(canonicalBytes(
        invocations.map((item) => item.outputSha256))),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  const passed = scenarios.filter((item) => item.passed).length;
  const passedInvocations = scenarios.reduce((sum, item) =>
    sum + item.invocations.filter((inv) => inv.passed).length, 0);
  return deepFreeze({
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    scenarioCount: scenarios.length,
    invocationCount,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    passedInvocations,
    failedInvocations: invocationCount - passedInvocations,
    parityStatus: passed === 8 && passedInvocations === 9 ?
      "parity_ready" : "parity_failed",
    scenarios,
  });
}

function buildNegativeClaimParityEntry(report) {
  return {
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    dartProviderSource:
      "lib/domain/wardrobe_profile/vision_framing_attestation.dart",
    nodeProviderSource: "functions/vision_negative_claim_corroborator.js",
    inputContract: "negative_claim_corroborator_input/v1",
    outputContract: "NegativeClaimCorroborationReport/v1",
    oracleContractVersion: 1,
    scenarioCount: report.scenarioCount,
    invocationCount: report.invocationCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    parityStatus: report.parityStatus,
    canonicalImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dependencyVersions: {
      negativeClaimOracleContract: 1,
      observationBundleDecoder: "qualification-v1",
      framingAttestor: "framing-attestor-v1",
      visibilityTrust: "visibility-trust-v1",
    },
    outputSha256ByScenario: Object.fromEntries(report.scenarios.map(
      (item) => [item.scenarioId, item.outputSha256])),
  };
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    Object.values(value).forEach(deepFreeze);
  }
  return value;
}

module.exports = {
  buildNegativeClaimParityEntry,
  runNegativeClaimParity,
};
