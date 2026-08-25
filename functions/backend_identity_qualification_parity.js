"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  ORACLE_CONTRACT_VERSION,
  decodeIdentityOracle,
  qualifyVisionIdentity,
} = require("./vision_identity_qualifier");

const DEFAULT_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_identity_qualification_oracle_manifest.json");
const PREPARE_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/" +
  "backend_identity_qualification_input_orchestration_parity_manifest.json");
const SOURCE = path.resolve(__dirname, "vision_identity_qualifier.js");

function runIdentityQualificationParity({
  manifestPath = DEFAULT_MANIFEST,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== PROVIDER_ID ||
      manifest.providerVersion !== PROVIDER_VERSION) {
    throw new Error("identity_qualification_oracle_integrity_failure");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) {
    throw new Error("identity_qualification_oracle_integrity_failure");
  }
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  let invocationCount = 0;
  const scenarios = ready.map((entry) => {
    const bytes = fs.readFileSync(path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(bytes) !== entry.oracleSha256) {
      throw new Error(`identity_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = decodeIdentityOracle(JSON.parse(bytes.toString("utf8")));
    if (oracle.scenarioId !== entry.scenarioId) {
      throw new Error(`identity_scenario_mismatch:${entry.scenarioId}`);
    }
    const invocations = oracle.invocations.map((item) => {
      const output = qualifyVisionIdentity(item.providerInput);
      const differences = diff(item.providerOutput, output);
      const fieldParity = {
        report: diff(item.providerOutput.report, output.report).length === 0,
        qualifiedIdentityEvidence: diff(
          item.providerOutput.qualifiedIdentityEvidence,
          output.qualifiedIdentityEvidence).length === 0,
        status: item.providerOutput.report.state === output.report.state,
        selectedCanonicalType:
          item.providerOutput.report.selectedCanonicalType ===
            output.report.selectedCanonicalType,
      };
      return {
        invocationId: item.invocationId,
        passed: differences.length === 0,
        differences,
        fieldParity,
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
  const rerun = runIdentityQualificationParityOnce({manifestPath});
  const deterministic = scenarios.every((item, index) =>
    item.outputSha256 === rerun.scenarios[index].outputSha256);
  return deepFreeze({
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    scenarioCount: scenarios.length,
    invocationCount,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    passedInvocations,
    failedInvocations: invocationCount - passedInvocations,
    parityStatus: passed === 8 && passedInvocations === 8 && deterministic ?
      "parity_ready" : "parity_failed",
    deterministic,
    scenarios,
    taxonomyRegistrySha256: manifest.taxonomyRegistrySha256,
    dartImplementationSha256: manifest.providerImplementationSha256,
  });
}

function runIdentityQualificationParityOnce({manifestPath}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  const scenarios = ready.map((entry) => {
    const oracle = decodeIdentityOracle(JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath), "utf8")));
    const invocations = oracle.invocations.map((item) => ({
      outputSha256: sha256(canonicalBytes(
        qualifyVisionIdentity(item.providerInput))),
    }));
    return {
      scenarioId: entry.scenarioId,
      outputSha256: sha256(canonicalBytes(
        invocations.map((item) => item.outputSha256))),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  return {scenarios};
}

function buildIdentityQualificationParityEntry(report) {
  const prepare = JSON.parse(fs.readFileSync(PREPARE_MANIFEST, "utf8"));
  return {
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    dartProviderSource:
      "lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart",
    nodeProviderSource: "functions/vision_identity_qualifier.js",
    inputContract: "vision_identity_qualification_input/v1",
    outputContract: "VisionIdentityQualificationResult/v1",
    oracleContractVersion: ORACLE_CONTRACT_VERSION,
    scenarioCount: report.scenarioCount,
    invocationCount: report.invocationCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    parityStatus: report.parityStatus,
    canonicalImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dependencyVersions: {
      identityOracleContract: ORACLE_CONTRACT_VERSION,
      prepareStage: prepare.stageVersion,
      prepareStageManifest: "backend_identity_qualification_input_orchestration_parity_manifest.json",
      canonicalConsistency: "canonical-consistency-v1",
      framingAttestor: "framing-attestor-v1",
      observationEvidence: "qualification-v1",
      taxonomyRegistrySha256: report.taxonomyRegistrySha256,
      dartImplementationSha256: report.dartImplementationSha256,
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
  buildIdentityQualificationParityEntry,
  runIdentityQualificationParity,
};
