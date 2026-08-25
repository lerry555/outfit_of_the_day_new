"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  CONTRACT_VERSION,
  STAGE_ID,
  STAGE_VERSION,
  prepareVisionKnowledgeBasePriorInput,
} = require("./prepare_vision_knowledge_base_prior_input");
const {
  PROVIDER_VERSION: CAPABILITY_PROVIDER_VERSION,
  inferCapabilities,
} = require("./wardrobe_capability_inference_provider");

const DEFAULT_KB_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_wardrobe_kb_prior_oracle_manifest.json");
const DEFAULT_OBS_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_provider_oracle_manifest.json");
const DEFAULT_IDENTITY_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_identity_qualification_oracle_manifest.json");
const SOURCE = path.resolve(__dirname,
  "prepare_vision_knowledge_base_prior_input.js");

function runKnowledgeBasePriorInputParity({
  kbManifestPath = DEFAULT_KB_MANIFEST,
  observationManifestPath = DEFAULT_OBS_MANIFEST,
  identityManifestPath = DEFAULT_IDENTITY_MANIFEST,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(kbManifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== "WardrobeKnowledgeBasePriorProvider" ||
      manifest.providerVersion !== "wardrobe-kb-prior-provider-v1") {
    throw new Error("kb_input_or_artifact_integrity_failure");
  }
  if (manifest.readyScenarioCount !== 8 ||
      manifest.invocationCount !== 8) {
    throw new Error("kb_input_or_artifact_integrity_failure");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) {
    throw new Error("kb_input_or_artifact_integrity_failure");
  }
  const observationManifest = JSON.parse(
    fs.readFileSync(observationManifestPath, "utf8"));
  const identityManifest = JSON.parse(
    fs.readFileSync(identityManifestPath, "utf8"));
  if (identityManifest.providerId !== "VisionIdentityQualification" ||
      identityManifest.readyScenarioCount !== 8) {
    throw new Error("kb_input_or_artifact_integrity_failure");
  }
  const fixtureRoot = path.dirname(path.dirname(kbManifestPath));
  const observationById = new Map(
    observationManifest.fixtures.filter((item) => item.status === "ready")
      .map((item) => [item.scenarioId, item]));
  const identityById = new Map(
    identityManifest.fixtures.filter((item) => item.status === "ready")
      .map((item) => [item.scenarioId, item]));
  const scenarios = ready.map((entry) => {
    const oracleBytes = fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(oracleBytes) !== entry.oracleSha256) {
      throw new Error(`kb_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = JSON.parse(oracleBytes.toString("utf8"));
    if (!Array.isArray(oracle.invocations) || oracle.invocations.length !== 1) {
      throw new Error(`kb_invocation_count_invalid:${entry.scenarioId}`);
    }
    const expected = oracle.invocations[0].providerInput;
    const observationEntry = observationById.get(entry.scenarioId);
    const identityEntry = identityById.get(entry.scenarioId);
    if (!observationEntry || !identityEntry) {
      throw new Error(`upstream_oracle_missing:${entry.scenarioId}`);
    }
    const observationOracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, observationEntry.oraclePath), "utf8"));
    const identityOracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, identityEntry.oraclePath), "utf8"));
    const qualificationInput = JSON.parse(fs.readFileSync(path.join(
      fixtureRoot, "backend_qualification", "input",
      `${entry.scenarioId}.input.json`), "utf8"));
    const capabilityEvidence = projectCapabilityWire(inferCapabilities({
      oracleContractVersion: observationOracle.oracleContractVersion,
      upstreamProviderId: observationOracle.providerId,
      upstreamProviderVersion: observationOracle.providerVersion,
      qualificationInputContractVersion: qualificationInput.contractVersion,
      providerVersion: CAPABILITY_PROVIDER_VERSION,
      analysisId: qualificationInput.analysisId,
      observedAt: qualificationInput.observedAt,
      sourceReference: observationOracle.providerInput.sourceReference,
      observationEvidence: structuredClone(observationOracle.providerOutput)
        .sort((left, right) => left.id.localeCompare(right.id)),
    }));
    const prepared = prepareVisionKnowledgeBasePriorInput({
      documentMode: "vision_empty",
      observationEvidence: observationOracle.providerOutput,
      observationProvenance: {
        observedAt: observationOracle.providerInput.observedAt,
        modelVersion: observationOracle.providerInput.modelVersion,
        sourceReference: observationOracle.providerInput.sourceReference,
      },
      qualifiedIdentityEvidence:
        identityOracle.invocations[0].providerOutput.qualifiedIdentityEvidence,
      capabilityEvidence,
    });
    const differences = diff(expected, prepared);
    const fieldParity = {
      document: diff(expected.document, prepared.document).length === 0,
      existingEvidence:
        diff(expected.existingEvidence, prepared.existingEvidence).length === 0,
      evidenceOrdering: evidenceIds(expected.existingEvidence)
        .join("\n") === evidenceIds(prepared.existingEvidence).join("\n"),
    };
    return {
      scenarioId: entry.scenarioId,
      passed: differences.length === 0,
      differences,
      fieldParity,
      outputSha256: sha256(canonicalBytes(prepared)),
      expectedInputSha256: sha256(canonicalBytes(expected)),
      evidenceCount: prepared.existingEvidence.length,
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  const passed = scenarios.filter((item) => item.passed).length;
  const rerun = runKnowledgeBasePriorInputParityOnce({
    kbManifestPath,
    observationManifestPath,
    identityManifestPath,
  });
  const deterministic = scenarios.every((item, index) =>
    item.outputSha256 === rerun.scenarios[index].outputSha256);
  return deepFreeze({
    stageId: STAGE_ID,
    stageVersion: STAGE_VERSION,
    contractVersion: CONTRACT_VERSION,
    scenarioCount: scenarios.length,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    parityStatus: passed === 8 && deterministic ?
      "orchestration_ready" : "parity_failed",
    deterministic,
    scenarios,
    nodeImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dartCallSiteSha256: manifest.callSitePreparationSha256,
    knowledgeBaseArtifactContentSha256:
      manifest.knowledgeBaseArtifactContentSha256,
  });
}

function runKnowledgeBasePriorInputParityOnce({
  kbManifestPath,
  observationManifestPath,
  identityManifestPath,
}) {
  const manifest = JSON.parse(fs.readFileSync(kbManifestPath, "utf8"));
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const observationManifest = JSON.parse(
    fs.readFileSync(observationManifestPath, "utf8"));
  const identityManifest = JSON.parse(
    fs.readFileSync(identityManifestPath, "utf8"));
  const fixtureRoot = path.dirname(path.dirname(kbManifestPath));
  const observationById = new Map(
    observationManifest.fixtures.filter((item) => item.status === "ready")
      .map((item) => [item.scenarioId, item]));
  const identityById = new Map(
    identityManifest.fixtures.filter((item) => item.status === "ready")
      .map((item) => [item.scenarioId, item]));
  const scenarios = ready.map((entry) => {
    const oracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath), "utf8"));
    const observationOracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot,
        observationById.get(entry.scenarioId).oraclePath), "utf8"));
    const identityOracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot,
        identityById.get(entry.scenarioId).oraclePath), "utf8"));
    const qualificationInput = JSON.parse(fs.readFileSync(path.join(
      fixtureRoot, "backend_qualification", "input",
      `${entry.scenarioId}.input.json`), "utf8"));
    const capabilityEvidence = projectCapabilityWire(inferCapabilities({
      oracleContractVersion: observationOracle.oracleContractVersion,
      upstreamProviderId: observationOracle.providerId,
      upstreamProviderVersion: observationOracle.providerVersion,
      qualificationInputContractVersion: qualificationInput.contractVersion,
      providerVersion: CAPABILITY_PROVIDER_VERSION,
      analysisId: qualificationInput.analysisId,
      observedAt: qualificationInput.observedAt,
      sourceReference: observationOracle.providerInput.sourceReference,
      observationEvidence: structuredClone(observationOracle.providerOutput)
        .sort((left, right) => left.id.localeCompare(right.id)),
    }));
    const prepared = prepareVisionKnowledgeBasePriorInput({
      documentMode: "vision_empty",
      observationEvidence: observationOracle.providerOutput,
      observationProvenance: {
        observedAt: observationOracle.providerInput.observedAt,
        modelVersion: observationOracle.providerInput.modelVersion,
        sourceReference: observationOracle.providerInput.sourceReference,
      },
      qualifiedIdentityEvidence:
        identityOracle.invocations[0].providerOutput.qualifiedIdentityEvidence,
      capabilityEvidence,
    });
    return {
      scenarioId: entry.scenarioId,
      outputSha256: sha256(canonicalBytes(prepared)),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  return {scenarios};
}

function buildKnowledgeBasePriorInputParityEntry(report) {
  return deepFreeze({
    stageId: report.stageId,
    stageVersion: report.stageVersion,
    contractVersion: report.contractVersion,
    parityStatus: report.parityStatus,
    scenarioCount: report.scenarioCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    deterministic: report.deterministic,
    nodeImplementationSha256: report.nodeImplementationSha256,
    dartCallSiteSha256: report.dartCallSiteSha256,
    knowledgeBaseArtifactContentSha256:
      report.knowledgeBaseArtifactContentSha256,
    scenarios: report.scenarios.map((item) => ({
      scenarioId: item.scenarioId,
      passed: item.passed,
      outputSha256: item.outputSha256,
      expectedInputSha256: item.expectedInputSha256,
      evidenceCount: item.evidenceCount,
      fieldParity: item.fieldParity,
    })),
  });
}

function projectCapabilityWire(items) {
  return items.map((item) => {
    const projected = {
      active: item.active !== false,
      confidence: item.confidence,
      createdAt: item.createdAt,
      id: item.id,
      method: item.method,
      modelVersion: item.modelVersion,
      nature: item.nature,
      property: item.property,
      source: item.source,
      value: item.value,
      verified: item.verified === true,
    };
    if (item.sourceReference) {
      projected.sourceReference = item.sourceReference;
    }
    if (item.valueState && item.valueState !== "known") {
      projected.valueState = item.valueState;
    }
    return projected;
  });
}

function evidenceIds(items) {
  return items.map((item) => item.id);
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function deepFreeze(value) {
  if (value === null || typeof value !== "object" || Object.isFrozen(value)) {
    return value;
  }
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

module.exports = {
  buildKnowledgeBasePriorInputParityEntry,
  runKnowledgeBasePriorInputParity,
};
