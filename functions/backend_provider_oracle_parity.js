"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {
  ORACLE_CONTRACT_VERSION,
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeProviderOracle,
  provideObservationEvidence,
} = require("./vision_observation_evidence_provider");

const DEFAULT_ORACLE_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_provider_oracle_manifest.json");
const PROVIDER_SOURCE = path.resolve(__dirname,
  "vision_observation_evidence_provider.js");
const DART_PROVIDER_SOURCE = "lib/domain/wardrobe_profile/" +
  "vision_observation_evidence_provider.dart";

function runObservationEvidenceProviderParity({
  oracleManifestPath = DEFAULT_ORACLE_MANIFEST,
} = {}) {
  const manifest = readJson(oracleManifestPath);
  validateOracleManifest(manifest);
  const fixtureRoot = path.dirname(path.dirname(oracleManifestPath));
  const scenarios = [];
  for (const entry of manifest.fixtures.filter((item) =>
    item.status === "ready")) {
    const oraclePath = path.resolve(fixtureRoot, entry.oraclePath);
    const oracleBytes = fs.readFileSync(oraclePath);
    const oracleSha256 = sha256(oracleBytes);
    if (oracleSha256 !== entry.oracleSha256) {
      throw new Error(`oracle_sha256_mismatch:${entry.scenarioId}`);
    }
    const oracle = decodeProviderOracle(JSON.parse(oracleBytes));
    if (oracle.scenarioId !== entry.scenarioId) {
      throw new Error(`oracle_scenario_mismatch:${entry.scenarioId}`);
    }
    if (oracle.providerInputSha256 !== entry.providerInputSha256) {
      throw new Error(`provider_input_sha256_mismatch:${entry.scenarioId}`);
    }
    if (oracle.providerOutputSha256 !== entry.providerOutputSha256) {
      throw new Error(`provider_output_sha256_mismatch:${entry.scenarioId}`);
    }
    const actual = provideObservationEvidence(oracle.providerInput);
    const differences = diff(oracle.providerOutput, actual);
    scenarios.push(Object.freeze({
      scenarioId: entry.scenarioId,
      passed: differences.length === 0,
      differences: Object.freeze(differences),
      outputSha256: sha256(canonicalBytes(actual)),
      viewCount: oracle.orderedViewProvenance.length,
    }));
  }
  scenarios.sort((left, right) =>
    left.scenarioId.localeCompare(right.scenarioId));
  const passed = scenarios.filter((item) => item.passed).length;
  return deepFreeze({
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    scenarioCount: scenarios.length,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    parityStatus: passed === scenarios.length && scenarios.length === 8 ?
      "parity_ready" : "parity_failed",
    scenarios,
  });
}

function buildProviderParityManifest(report) {
  if (!report || report.providerId !== PROVIDER_ID) {
    throw new Error("provider_parity_report_invalid");
  }
  return {
    manifestVersion: 1,
    providers: [{
      providerId: PROVIDER_ID,
      providerVersion: PROVIDER_VERSION,
      dartProviderSource: DART_PROVIDER_SOURCE,
      nodeProviderSource: "functions/vision_observation_evidence_provider.js",
      inputContract: "provider_oracle.providerInput/v1",
      outputContract: "List<ProfileEvidence>/provider_oracle_v1",
      oracleContractVersion: ORACLE_CONTRACT_VERSION,
      scenarioCount: report.scenarioCount,
      passedScenarios: report.passedScenarios,
      failedScenarios: report.failedScenarios,
      parityStatus: report.parityStatus,
      canonicalImplementationSha256: sha256(
        fs.readFileSync(PROVIDER_SOURCE)),
      dependencyVersions: {
        backendQualificationInputContract: 1,
        backendQualificationReferenceContract: 1,
        providerOracleContract: ORACLE_CONTRACT_VERSION,
      },
      outputSha256ByScenario: Object.fromEntries(report.scenarios.map(
        (item) => [item.scenarioId, item.outputSha256])),
    }],
  };
}

function validateOracleManifest(manifest) {
  if (!manifest || manifest.manifestVersion !== 1 ||
      manifest.oracleContractVersion !== ORACLE_CONTRACT_VERSION ||
      manifest.providerId !== PROVIDER_ID ||
      manifest.providerVersion !== PROVIDER_VERSION ||
      !Array.isArray(manifest.fixtures)) {
    throw new Error("provider_oracle_manifest_invalid");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) throw new Error("provider_oracle_ready_count_invalid");
  if (manifest.fixtures.some((item) =>
    !["ready", "source_missing"].includes(item.status))) {
    throw new Error("provider_oracle_status_invalid");
  }
}

function canonicalBytes(value) {
  return Buffer.from(`${JSON.stringify(canonicalize(value), null, 2)}\n`);
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort()
      .map((key) => [key, canonicalize(value[key])]));
  }
  return Object.is(value, -0) ? 0 : value;
}

function diff(expected, actual, currentPath = "$") {
  if (Object.is(expected, actual)) return [];
  if (Array.isArray(expected) && Array.isArray(actual)) {
    if (expected.length !== actual.length) {
      return [difference(currentPath, expected.length, actual.length,
        "ordering_mismatch")];
    }
    return expected.flatMap((item, index) =>
      diff(item, actual[index], `${currentPath}[${index}]`));
  }
  if (isObject(expected) && isObject(actual)) {
    const keys = [...new Set([
      ...Object.keys(expected),
      ...Object.keys(actual),
    ])].sort();
    return keys.flatMap((key) => {
      if (!Object.hasOwn(expected, key)) {
        return [difference(`${currentPath}.${key}`, undefined, actual[key],
          "unexpected_field")];
      }
      if (!Object.hasOwn(actual, key)) {
        return [difference(`${currentPath}.${key}`, expected[key], undefined,
          "missing_field")];
      }
      return diff(expected[key], actual[key], `${currentPath}.${key}`);
    });
  }
  const mismatchType = (expected === null) !== (actual === null) ?
    "null_vs_omitted" :
    typeof expected === "number" || typeof actual === "number" ?
      "numeric_mismatch" :
      typeof expected === "string" && typeof actual === "string" ?
        "enum_mismatch" : "decision_mismatch";
  return [difference(currentPath, expected, actual, mismatchType)];
}

function difference(jsonPath, expected, actual, mismatchType) {
  return Object.freeze({jsonPath, expected, actual, mismatchType});
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
}
function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}
function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    Object.values(value).forEach(deepFreeze);
  }
  return value;
}

module.exports = {
  DEFAULT_ORACLE_MANIFEST,
  buildProviderParityManifest,
  canonicalBytes,
  diff,
  runObservationEvidenceProviderParity,
};
