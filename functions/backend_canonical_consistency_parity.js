"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeCanonicalConsistencyOracle,
  validateCanonicalConsistency,
} = require("./canonical_observation_consistency_validator");

const DEFAULT_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_canonical_consistency_oracle_manifest.json");
const SOURCE = path.resolve(
  __dirname, "canonical_observation_consistency_validator.js");

function runCanonicalConsistencyParity({manifestPath = DEFAULT_MANIFEST} = {}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleContractVersion !== 1 ||
      manifest.providerId !== PROVIDER_ID ||
      manifest.providerVersion !== PROVIDER_VERSION) {
    throw new Error("canonical_manifest_invalid");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) throw new Error("canonical_ready_invalid");
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  const scenarios = ready.map((entry) => {
    const bytes = fs.readFileSync(path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(bytes) !== entry.oracleSha256) {
      throw new Error(`canonical_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = decodeCanonicalConsistencyOracle(JSON.parse(bytes));
    const output = validateCanonicalConsistency(oracle.providerInput);
    const differences = diff(oracle.providerOutput, output);
    return {
      scenarioId: entry.scenarioId,
      passed: differences.length === 0,
      differences,
      outputSha256: sha256(canonicalBytes(output)),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  const passed = scenarios.filter((item) => item.passed).length;
  return deepFreeze({
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    scenarioCount: scenarios.length,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    parityStatus: passed === 8 ? "parity_ready" : "parity_failed",
    scenarios,
  });
}

function buildCanonicalConsistencyParityEntry(report) {
  return {
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    dartProviderSource:
      "lib/domain/wardrobe_profile/canonical_observation_consistency_validator.dart",
    nodeProviderSource:
      "functions/canonical_observation_consistency_validator.js",
    inputContract: "canonical_consistency_oracle.input/v1",
    outputContract: "CanonicalConsistencyReport/v1",
    oracleContractVersion: 1,
    scenarioCount: report.scenarioCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    parityStatus: report.parityStatus,
    canonicalImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dependencyVersions: {
      canonicalConsistencyOracleContract: 1,
      observationEvidenceProvider: "qualification-v1",
      signatureRegistry: "canonical-consistency-v1",
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
  buildCanonicalConsistencyParityEntry,
  runCanonicalConsistencyParity,
};
