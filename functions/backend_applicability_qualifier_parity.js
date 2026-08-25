"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeApplicabilityOracle,
  qualifyApplicability,
} = require("./vision_property_applicability_qualifier");

const DEFAULT_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_applicability_qualifier_oracle_manifest.json");
const SOURCE = path.resolve(
  __dirname, "vision_property_applicability_qualifier.js");

function runApplicabilityQualifierParity({
  manifestPath = DEFAULT_MANIFEST,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleContractVersion !== 1 ||
      manifest.providerId !== PROVIDER_ID ||
      manifest.providerVersion !== PROVIDER_VERSION) {
    throw new Error("applicability_manifest_invalid");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) throw new Error("applicability_ready_invalid");
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  const scenarios = ready.map((entry) => {
    const bytes = fs.readFileSync(path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(bytes) !== entry.oracleSha256) {
      throw new Error(`applicability_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = decodeApplicabilityOracle(JSON.parse(bytes));
    const invocations = oracle.invocations.map((item) => {
      const output = qualifyApplicability(item.providerInput);
      const differences = diff(item.providerOutput, output);
      return {
        viewId: item.viewId,
        passed: differences.length === 0,
        differences,
        outputSha256: sha256(canonicalBytes(output)),
      };
    });
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
  return deepFreeze({
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    scenarioCount: scenarios.length,
    invocationCount: scenarios.reduce(
      (sum, item) => sum + item.invocationCount, 0),
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    parityStatus: passed === 8 ? "parity_ready" : "parity_failed",
    scenarios,
  });
}

function buildApplicabilityParityEntry(report) {
  return {
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    dartProviderSource:
      "lib/domain/wardrobe_profile/vision_subject_safety.dart",
    nodeProviderSource:
      "functions/vision_property_applicability_qualifier.js",
    inputContract: "applicability_oracle.invocations.input/v1",
    outputContract: "VisionApplicabilityReport/v1",
    oracleContractVersion: 1,
    scenarioCount: report.scenarioCount,
    invocationCount: report.invocationCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    parityStatus: report.parityStatus,
    canonicalImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dependencyVersions: {
      applicabilityOracleContract: 1,
      observationBundleDecoder: "qualification-v1",
      framingAttestor: "framing-attestor-v1",
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
  buildApplicabilityParityEntry,
  runApplicabilityQualifierParity,
};
