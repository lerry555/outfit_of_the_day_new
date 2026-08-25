"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  ORACLE_CONTRACT_VERSION,
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeKbPriorOracle,
  provideWardrobeKnowledgeBasePriors,
  structuredTaxonomySourceSha256,
} = require("./wardrobe_knowledge_base_prior_provider");
const {
  loadClothingKnowledgeBasePriorArtifact,
} = require("./clothing_knowledge_base_prior_loader");

const DEFAULT_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_wardrobe_kb_prior_oracle_manifest.json");
const PREPARE_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_kb_prior_input_orchestration_manifest.json");
const ARTIFACT_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_clothing_kb_prior_artifact_manifest.json");
const LOADER_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_clothing_kb_prior_loader_manifest.json");
const SOURCE = path.resolve(__dirname,
  "wardrobe_knowledge_base_prior_provider.js");
const DART_SOURCE =
  "lib/domain/wardrobe_profile/wardrobe_knowledge_base_prior_provider.dart";

function runWardrobeKnowledgeBasePriorParity({
  manifestPath = DEFAULT_MANIFEST,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== PROVIDER_ID ||
      manifest.providerVersion !== PROVIDER_VERSION) {
    throw new Error("kb_prior_oracle_or_artifact_integrity_failure");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8 || manifest.invocationCount !== 8) {
    throw new Error("kb_prior_oracle_or_artifact_integrity_failure");
  }
  const artifactManifest = JSON.parse(fs.readFileSync(ARTIFACT_MANIFEST, "utf8"));
  if (manifest.knowledgeBaseArtifactContentSha256 !==
      artifactManifest.artifactContentSha256) {
    throw new Error("kb_prior_oracle_or_artifact_integrity_failure");
  }
  const kbArtifact = loadClothingKnowledgeBasePriorArtifact({
    expectedContentSha256: artifactManifest.artifactContentSha256,
    expectedSchemaVersion: artifactManifest.schemaVersion,
  });
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  let invocationCount = 0;
  let kbEvidenceCount = 0;
  let emptyOutput = 0;
  let shoeEvidence = 0;
  const propertyCounts = {};
  const scenarios = ready.map((entry) => {
    const bytes = fs.readFileSync(path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(bytes) !== entry.oracleSha256) {
      throw new Error(`kb_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = decodeKbPriorOracle(JSON.parse(bytes.toString("utf8")));
    if (oracle.scenarioId !== entry.scenarioId) {
      throw new Error(`kb_scenario_mismatch:${entry.scenarioId}`);
    }
    const invocations = oracle.invocations.map((item) => {
      const inputBefore = canonicalBytes(item.providerInput);
      const output = provideWardrobeKnowledgeBasePriors(item.providerInput, {
        kbArtifact,
        expectedArtifactContentSha256: artifactManifest.artifactContentSha256,
      });
      if (!canonicalBytes(item.providerInput).equals(inputBefore)) {
        throw new Error(`kb_input_mutated:${entry.scenarioId}`);
      }
      const differences = diff(item.providerOutput, output);
      kbEvidenceCount += output.length;
      if (output.length === 0) emptyOutput++;
      if (entry.scenarioId === "shoe_without_outsole") {
        shoeEvidence = output.length;
      }
      for (const evidence of output) {
        propertyCounts[evidence.property] =
          (propertyCounts[evidence.property] ?? 0) + 1;
      }
      return {
        invocationId: item.invocationId,
        passed: differences.length === 0,
        differences,
        outputCount: output.length,
        outputSha256: sha256(canonicalBytes(output)),
        fieldParity: {
          evidenceCount: item.providerOutput.length === output.length,
          evidenceIds: evidenceIds(item.providerOutput).join("\n") ===
            evidenceIds(output).join("\n"),
          ordering: evidenceIds(item.providerOutput).join("\n") ===
            evidenceIds(output).join("\n"),
        },
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
  const rerun = runWardrobeKnowledgeBasePriorParityOnce({
    manifestPath,
    kbArtifact,
    artifactContentSha256: artifactManifest.artifactContentSha256,
  });
  const deterministic = scenarios.every((item, index) =>
    item.outputSha256 === rerun.scenarios[index].outputSha256);
  const distributionOk =
    invocationCount === 8 &&
    kbEvidenceCount === 6 &&
    shoeEvidence === 6 &&
    emptyOutput === 7 &&
    propertyCounts["identity.mainCategory"] === 1 &&
    propertyCounts["identity.category"] === 1 &&
    propertyCounts["identity.subcategory"] === 1 &&
    propertyCounts["capabilities.layerRole"] === 1 &&
    propertyCounts["capabilities.warmth"] === 1 &&
    propertyCounts["capabilities.formality"] === 1;
  return deepFreeze({
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    scenarioCount: scenarios.length,
    invocationCount,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    kbEvidenceCount,
    emptyOutputScenarios: emptyOutput,
    shoeEvidenceCount: shoeEvidence,
    propertyCounts,
    parityStatus: passed === 8 && deterministic && distributionOk ?
      "parity_ready" : "parity_failed",
    deterministic,
    distributionOk,
    scenarios,
    dartImplementationSha256: manifest.providerImplementationSha256,
    knowledgeBaseArtifactContentSha256: kbArtifact.contentSha256,
    knowledgeBaseArtifactSchemaVersion: kbArtifact.schemaVersion,
    structuredTaxonomySourceSha256,
    nodeImplementationSha256: sha256(fs.readFileSync(SOURCE)),
  });
}

function runWardrobeKnowledgeBasePriorParityOnce({
  manifestPath,
  kbArtifact,
  artifactContentSha256,
}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  const scenarios = ready.map((entry) => {
    const oracle = decodeKbPriorOracle(JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath), "utf8")));
    const invocations = oracle.invocations.map((item) => ({
      outputSha256: sha256(canonicalBytes(
        provideWardrobeKnowledgeBasePriors(item.providerInput, {
          kbArtifact,
          expectedArtifactContentSha256: artifactContentSha256,
        }))),
    }));
    return {
      scenarioId: entry.scenarioId,
      outputSha256: sha256(canonicalBytes(
        invocations.map((item) => item.outputSha256))),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  return {scenarios};
}

function buildWardrobeKnowledgeBasePriorParityEntry(report) {
  let prepareStage = "knowledge-base-prior-input-v1";
  let prepareStageManifest =
    "backend_kb_prior_input_orchestration_manifest.json";
  if (fs.existsSync(PREPARE_MANIFEST)) {
    const prepare = JSON.parse(fs.readFileSync(PREPARE_MANIFEST, "utf8"));
    prepareStage = prepare.stageVersion;
  }
  let loaderManifest =
    "backend_clothing_kb_prior_loader_manifest.json";
  if (fs.existsSync(LOADER_MANIFEST)) {
    loaderManifest = path.basename(LOADER_MANIFEST);
  }
  return {
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    dartProviderSource: DART_SOURCE,
    nodeProviderSource: "functions/wardrobe_knowledge_base_prior_provider.js",
    inputContract: "wardrobe_kb_prior_input/v1",
    outputContract: "ProfileEvidence[]/kb_prior_v1",
    oracleContractVersion: ORACLE_CONTRACT_VERSION,
    scenarioCount: report.scenarioCount,
    invocationCount: report.invocationCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    parityStatus: report.parityStatus,
    canonicalImplementationSha256: report.nodeImplementationSha256,
    dependencyVersions: {
      kbOracleContract: ORACLE_CONTRACT_VERSION,
      prepareStage,
      prepareStageManifest,
      kbArtifact: "clothing-kb-prior-artifact-v1",
      kbArtifactManifest: "backend_clothing_kb_prior_artifact_manifest.json",
      kbLoaderManifest: loaderManifest,
      kbArtifactSchemaVersion: report.knowledgeBaseArtifactSchemaVersion,
      kbArtifactContentSha256: report.knowledgeBaseArtifactContentSha256,
      structuredTaxonomySourceSha256: report.structuredTaxonomySourceSha256,
      dartImplementationSha256: report.dartImplementationSha256,
    },
    outputSha256ByScenario: Object.fromEntries(report.scenarios.map(
      (item) => [item.scenarioId, item.outputSha256])),
  };
}

function evidenceIds(items) {
  return items.map((item) => item.id);
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
  buildWardrobeKnowledgeBasePriorParityEntry,
  runWardrobeKnowledgeBasePriorParity,
};
