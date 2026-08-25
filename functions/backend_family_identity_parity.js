"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  ORACLE_CONTRACT_VERSION,
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeFamilyOracle,
  familyTaxonomySha256,
  resolveVisionFamilyIdentity,
} = require("./vision_family_identity_resolver");

const DEFAULT_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_family_identity_oracle_manifest.json");
const PREPARE_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/" +
  "backend_family_identity_input_orchestration_parity_manifest.json");
const SOURCE = path.resolve(__dirname, "vision_family_identity_resolver.js");
const DART_SOURCE =
  "lib/domain/wardrobe_profile/vision_family_identity.dart";

function runFamilyIdentityParity({
  manifestPath = DEFAULT_MANIFEST,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== PROVIDER_ID ||
      manifest.providerVersion !== PROVIDER_VERSION) {
    throw new Error("family_identity_oracle_integrity_failure");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) {
    throw new Error("family_identity_oracle_integrity_failure");
  }
  if (manifest.taxonomyRegistrySha256 !== familyTaxonomySha256) {
    throw new Error("family_taxonomy_sha_integrity_failure");
  }
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  let invocationCount = 0;
  const statusCounts = {
    confirmed: 0,
    supported: 0,
    invalid_input: 0,
    ambiguous: 0,
    insufficient_evidence: 0,
    conflicting: 0,
  };
  let selectedFamily = 0;
  let nullFamily = 0;
  const scenarios = ready.map((entry) => {
    const bytes = fs.readFileSync(path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(bytes) !== entry.oracleSha256) {
      throw new Error(`family_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = decodeFamilyOracle(JSON.parse(bytes.toString("utf8")));
    if (oracle.scenarioId !== entry.scenarioId) {
      throw new Error(`family_scenario_mismatch:${entry.scenarioId}`);
    }
    const invocations = oracle.invocations.map((item) => {
      const output = resolveVisionFamilyIdentity(item.providerInput);
      const differences = diff(item.providerOutput, output);
      const fieldParity = {
        state: item.providerOutput.state === output.state,
        resolvedFamily:
          item.providerOutput.resolvedFamily === output.resolvedFamily,
        confidence: item.providerOutput.confidence === output.confidence,
        candidates: diff(item.providerOutput.candidates, output.candidates)
          .length === 0,
        reasonCodes: diff(item.providerOutput.reasonCodes, output.reasonCodes)
          .length === 0,
        supportingEvidence: diff(
          item.providerOutput.candidates?.map((c) => c.evidence) ?? [],
          output.candidates.map((c) => c.evidence)).length === 0,
      };
      statusCounts[output.state] = (statusCounts[output.state] ?? 0) + 1;
      if (output.resolvedFamily == null) nullFamily++;
      else selectedFamily++;
      return {
        invocationId: item.invocationId,
        passed: differences.length === 0,
        differences,
        fieldParity,
        outputSha256: sha256(canonicalBytes(output)),
        state: output.state,
        resolvedFamily: output.resolvedFamily,
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
  const rerun = runFamilyIdentityParityOnce({manifestPath});
  const deterministic = scenarios.every((item, index) =>
    item.outputSha256 === rerun.scenarios[index].outputSha256);
  const distributionOk =
    statusCounts.confirmed === 3 &&
    statusCounts.supported === 1 &&
    statusCounts.invalid_input === 4 &&
    selectedFamily === 4 &&
    nullFamily === 4;
  return deepFreeze({
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    scenarioCount: scenarios.length,
    invocationCount,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    passedInvocations,
    failedInvocations: invocationCount - passedInvocations,
    parityStatus: passed === 8 && passedInvocations === 8 && deterministic &&
      distributionOk ? "parity_ready" : "parity_failed",
    deterministic,
    distributionOk,
    statusCounts,
    selectedFamily,
    nullFamily,
    scenarios,
    taxonomyRegistrySha256: familyTaxonomySha256,
    dartImplementationSha256: manifest.providerImplementationSha256,
  });
}

function runFamilyIdentityParityOnce({manifestPath}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  const scenarios = ready.map((entry) => {
    const oracle = decodeFamilyOracle(JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath), "utf8")));
    const invocations = oracle.invocations.map((item) => ({
      outputSha256: sha256(canonicalBytes(
        resolveVisionFamilyIdentity(item.providerInput))),
    }));
    return {
      scenarioId: entry.scenarioId,
      outputSha256: sha256(canonicalBytes(
        invocations.map((item) => item.outputSha256))),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  return {scenarios};
}

function buildFamilyIdentityParityEntry(report) {
  let prepareStage = "family-identity-input-v1";
  let prepareStageManifest =
    "backend_family_identity_input_orchestration_parity_manifest.json";
  if (fs.existsSync(PREPARE_MANIFEST)) {
    const prepare = JSON.parse(fs.readFileSync(PREPARE_MANIFEST, "utf8"));
    prepareStage = prepare.stageVersion;
  }
  return {
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    dartProviderSource: DART_SOURCE,
    nodeProviderSource: "functions/vision_family_identity_resolver.js",
    inputContract: "vision_family_identity_input/v1",
    outputContract: "VisionFamilyIdentityReport/v1",
    oracleContractVersion: ORACLE_CONTRACT_VERSION,
    scenarioCount: report.scenarioCount,
    invocationCount: report.invocationCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    parityStatus: report.parityStatus,
    canonicalImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dependencyVersions: {
      familyOracleContract: ORACLE_CONTRACT_VERSION,
      prepareStage,
      prepareStageManifest,
      identityQualification: "vision-identity-qualification-v1",
      framingAttestor: "framing-attestor-v1",
      familyTaxonomy: "vision-canonical-family-registry-v1",
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
  buildFamilyIdentityParityEntry,
  runFamilyIdentityParity,
};
