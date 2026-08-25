"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeAbsenceOracle,
  qualifyAbsenceBundles,
} = require("./observation_absence_qualifier");

const DEFAULT_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/" +
  "backend_observation_absence_qualifier_oracle_manifest.json");
const SOURCE = path.resolve(__dirname, "observation_absence_qualifier.js");

function runAbsenceParity({manifestPath = DEFAULT_MANIFEST} = {}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== PROVIDER_ID ||
      manifest.providerVersion !== PROVIDER_VERSION) {
    throw new Error("absence_manifest_invalid");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) throw new Error("absence_ready_invalid");
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  let invocationCount = 0;
  const scenarios = ready.map((entry) => {
    const bytes = fs.readFileSync(path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(bytes) !== entry.oracleSha256) {
      throw new Error(`absence_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = decodeAbsenceOracle(JSON.parse(bytes));
    if (oracle.scenarioId !== entry.scenarioId) {
      throw new Error(`absence_scenario_mismatch:${entry.scenarioId}`);
    }
    const invocations = oracle.invocations.map((item) => {
      const output = qualifyAbsenceBundles(item.providerInput);
      const differences = diff(item.providerOutput, output);
      return {
        invocationId: item.invocationId,
        viewCount: item.viewCount,
        orderedViewIds: item.orderedViewIds,
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
    parityStatus: passed === 8 && passedInvocations === 8 ?
      "parity_ready" : "parity_failed",
    scenarios,
  });
}

function buildAbsenceParityEntry(report) {
  return {
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    dartProviderSource:
      "lib/domain/wardrobe_profile/observation_absence_qualifier.dart",
    nodeProviderSource: "functions/observation_absence_qualifier.js",
    inputContract: "observation_absence_qualifier_input/v1",
    outputContract: "ObservationAbsenceQualificationReport/v1",
    oracleContractVersion: 1,
    scenarioCount: report.scenarioCount,
    invocationCount: report.invocationCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    parityStatus: report.parityStatus,
    canonicalImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dependencyVersions: {
      absenceOracleContract: 1,
      observationBundleDecoder: "qualification-v1",
      negativeClaimCorroborator: "negative-claim-corroborator-v1",
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
  buildAbsenceParityEntry,
  runAbsenceParity,
};
