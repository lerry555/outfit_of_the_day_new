"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  FIXTURE_CONTEXT_MODE,
  ORACLE_CONTRACT_VERSION,
  PROVIDER_ID,
  PROVIDER_VERSION,
  mapQualifiedVisionPersistence,
} = require("./qualified_vision_persistence_mapper");
const {
  runQualifiedVisionPersistenceMapperInputParity,
} = require("./backend_qualified_vision_persistence_mapper_input_parity");

const DEFAULT_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/" +
  "backend_qualified_vision_persistence_mapper_oracle_manifest.json");
const PREPARE_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/" +
  "backend_qualified_vision_persistence_mapper_input_orchestration_manifest.json");
const SOURCE = path.resolve(__dirname, "qualified_vision_persistence_mapper.js");
const DART_SOURCE =
  "lib/domain/wardrobe_profile/qualified_vision_persistence_mapper.dart";

function runQualifiedVisionPersistenceMapperParity({
  manifestPath = DEFAULT_MANIFEST,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== PROVIDER_ID ||
      manifest.providerVersion !== PROVIDER_VERSION) {
    throw new Error("persistence_mapper_oracle_integrity_failure");
  }
  if (manifest.readyScenarioCount !== 8 || manifest.invocationCount !== 8) {
    throw new Error("persistence_mapper_oracle_integrity_failure");
  }
  const prepare = JSON.parse(fs.readFileSync(PREPARE_MANIFEST, "utf8"));
  if (prepare.parityStatus !== "orchestration_ready" ||
      prepare.passedScenarios !== 8) {
    throw new Error("persistence_mapper_oracle_integrity_failure");
  }
  const inputParity = runQualifiedVisionPersistenceMapperInputParity();
  if (inputParity.passedScenarios !== 8) {
    throw new Error("persistence_mapper_oracle_integrity_failure");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  const scenarios = ready.map((entry) => {
    const oracleBytes = fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(oracleBytes) !== entry.oracleSha256) {
      throw new Error(`mapper_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = JSON.parse(oracleBytes.toString("utf8"));
    const expected = oracle.invocations[0].mapperOutput;
    const input = {
      ...structuredClone(oracle.invocations[0].mapperInput),
      contextMode: FIXTURE_CONTEXT_MODE,
    };
    const actual = mapQualifiedVisionPersistence(input);
    const differences = diff(expected, actual);
    const counts = countEvidence(actual);
    return {
      scenarioId: entry.scenarioId,
      passed: differences.length === 0,
      differences,
      outputSha256: sha256(canonicalBytes(actual)),
      expectedOutputSha256: sha256(canonicalBytes(expected)),
      status: actual.status,
      reasonCode: actual.reasonCode ?? null,
      omitted: actual.omittedEvidenceReasonCodes || [],
      counts,
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  const passed = scenarios.filter((item) => item.passed).length;
  const rerun = runOnce(manifestPath);
  const deterministic = scenarios.every((item, index) =>
    item.outputSha256 === rerun.scenarios[index].outputSha256);
  const distribution = aggregateDistribution(scenarios);
  const distributionOk =
    distribution.mapped === 7 &&
    distribution.invalidInput === 1 &&
    distribution.noPersistableEvidence === 0 &&
    distribution.incompatibleInput === 0 &&
    distribution.mappingFailure === 0 &&
    distribution.totalMachineEvidence === 110 &&
    distribution.familyEvidence === 4 &&
    distribution.canonicalEvidence === 1 &&
    distribution.observationEvidence === 105 &&
    distribution.capabilityEvidence === 0 &&
    distribution.omittedTotal === 13 &&
    distribution.omittedTraction === 6 &&
    distribution.omittedWalkingComfort === 6 &&
    distribution.omittedMultiPhotoPhysical === 1;
  return deepFreeze({
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    oracleContractVersion: ORACLE_CONTRACT_VERSION,
    scenarioCount: scenarios.length,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    parityStatus: passed === 8 && deterministic && distributionOk ?
      "parity_ready" : "parity_failed",
    deterministic,
    distributionOk,
    distribution,
    scenarios,
    nodeImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dartImplementationSha256: sha256(fs.readFileSync(
      path.resolve(__dirname, "..", DART_SOURCE))),
    prepareStageManifest:
      "backend_qualified_vision_persistence_mapper_input_orchestration_manifest.json",
    productionStatus: "blocked_without_trusted_revision_contract",
  });
}

function runOnce(manifestPath) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  const scenarios = ready.map((entry) => {
    const oracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath), "utf8"));
    const actual = mapQualifiedVisionPersistence({
      ...structuredClone(oracle.invocations[0].mapperInput),
      contextMode: FIXTURE_CONTEXT_MODE,
    });
    return {
      scenarioId: entry.scenarioId,
      outputSha256: sha256(canonicalBytes(actual)),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  return {scenarios};
}

function countEvidence(result) {
  const evidence = result.envelope?.machineEvidence || [];
  let family = 0;
  let canonical = 0;
  let observation = 0;
  let capability = 0;
  for (const item of evidence) {
    if (item.property === "identity.family") family++;
    else if (item.property === "identity.canonicalType") canonical++;
    else if (String(item.property).startsWith("capabilities.")) capability++;
    else observation++;
  }
  return {
    total: evidence.length,
    family,
    canonical,
    observation,
    capability,
    omitted: (result.omittedEvidenceReasonCodes || []).length,
  };
}

function aggregateDistribution(scenarios) {
  const distribution = {
    mapped: 0,
    invalidInput: 0,
    noPersistableEvidence: 0,
    incompatibleInput: 0,
    mappingFailure: 0,
    totalMachineEvidence: 0,
    familyEvidence: 0,
    canonicalEvidence: 0,
    observationEvidence: 0,
    capabilityEvidence: 0,
    omittedTotal: 0,
    omittedTraction: 0,
    omittedWalkingComfort: 0,
    omittedMultiPhotoPhysical: 0,
  };
  for (const scenario of scenarios) {
    distribution[scenario.status] = (distribution[scenario.status] || 0) + 1;
    distribution.totalMachineEvidence += scenario.counts.total;
    distribution.familyEvidence += scenario.counts.family;
    distribution.canonicalEvidence += scenario.counts.canonical;
    distribution.observationEvidence += scenario.counts.observation;
    distribution.capabilityEvidence += scenario.counts.capability;
    distribution.omittedTotal += scenario.counts.omitted;
    for (const reason of scenario.omitted) {
      if (reason === "capability_omitted:capabilities.traction") {
        distribution.omittedTraction++;
      }
      if (reason === "capability_omitted:capabilities.walkingComfort") {
        distribution.omittedWalkingComfort++;
      }
      if (reason === "identity_omitted:multi_photo_physical_conflict") {
        distribution.omittedMultiPhotoPhysical++;
      }
    }
  }
  return distribution;
}

function buildQualifiedVisionPersistenceMapperParityEntry(report) {
  return deepFreeze({
    providerId: report.providerId,
    providerVersion: report.providerVersion,
    oracleContractVersion: report.oracleContractVersion,
    parityStatus: report.parityStatus,
    productionStatus: report.productionStatus,
    scenarioCount: report.scenarioCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    deterministic: report.deterministic,
    distributionOk: report.distributionOk,
    distribution: report.distribution,
    nodeImplementationSha256: report.nodeImplementationSha256,
    dartImplementationSha256: report.dartImplementationSha256,
    prepareStageManifest: report.prepareStageManifest,
    outputSha256ByScenario: Object.fromEntries(
      report.scenarios.map((item) => [item.scenarioId, item.outputSha256])),
  });
}

function updateProviderParityManifest(report, {
  manifestPath = path.resolve(__dirname, "../test/fixtures/" +
    "backend_qualification/backend_provider_parity_manifest.json"),
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const entry = {
    canonicalImplementationSha256: report.nodeImplementationSha256,
    dartProviderSource:
      "lib/domain/wardrobe_profile/qualified_vision_persistence_mapper.dart",
    dependencyVersions: {
      dartImplementationSha256: report.dartImplementationSha256,
      prepareStage: "qualified-vision-persistence-mapper-input-v1",
      prepareStageManifest: report.prepareStageManifest,
      persistenceSchemaVersion: 1,
      persistenceEvidenceVersion: 1,
      resolverCompatibilityVersion: 1,
      mapperOracleContract: 1,
      fixtureContextMode: FIXTURE_CONTEXT_MODE,
    },
    failedScenarios: report.failedScenarios,
    inputContract: "qualified_vision_persistence_mapper_input/v1",
    invocationCount: report.scenarioCount,
    nodeProviderSource: "functions/qualified_vision_persistence_mapper.js",
    oracleContractVersion: report.oracleContractVersion,
    outputContract: "WardrobeProfilePersistenceMappingResult/v1",
    outputSha256ByScenario: Object.fromEntries(
      report.scenarios.map((item) => [item.scenarioId, item.outputSha256])),
    parityStatus: report.parityStatus,
    passedScenarios: report.passedScenarios,
    providerId: report.providerId,
    providerVersion: report.providerVersion,
    scenarioCount: report.scenarioCount,
    productionStatus: report.productionStatus,
  };
  const providers = manifest.providers.filter(
    (item) => item.providerId !== report.providerId);
  providers.push(entry);
  providers.sort((left, right) =>
    left.providerId.localeCompare(right.providerId));
  const next = {
    manifestVersion: 1,
    providers,
  };
  const bytes = Buffer.from(`${JSON.stringify(next, null, 2)}\n`, "utf8");
  fs.writeFileSync(manifestPath, bytes);
  const again = Buffer.from(
    `${JSON.stringify(JSON.parse(fs.readFileSync(manifestPath, "utf8")), null, 2)}\n`,
    "utf8");
  if (!bytes.equals(again)) {
    throw new Error("provider_parity_manifest_not_byte_identical");
  }
  return entry;
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function deepFreeze(value) {
  if (value == null || typeof value !== "object") return value;
  if (Object.isFrozen(value)) return value;
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

module.exports = {
  buildQualifiedVisionPersistenceMapperParityEntry,
  runQualifiedVisionPersistenceMapperParity,
  updateProviderParityManifest,
};

if (require.main === module) {
  const report = runQualifiedVisionPersistenceMapperParity();
  if (report.parityStatus === "parity_ready") {
    updateProviderParityManifest(report);
  }
  process.stdout.write(`${JSON.stringify({
    parityStatus: report.parityStatus,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    deterministic: report.deterministic,
    distributionOk: report.distributionOk,
    distribution: report.distribution,
  }, null, 2)}\n`);
}
