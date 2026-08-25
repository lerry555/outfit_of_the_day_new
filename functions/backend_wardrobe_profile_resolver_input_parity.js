"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  CONTRACT_VERSION,
  STAGE_ID,
  STAGE_VERSION,
  prepareWardrobeProfileResolverInput,
} = require("./prepare_wardrobe_profile_resolver_input");
const {
  prepareVisionKnowledgeBasePriorInput,
} = require("./prepare_vision_knowledge_base_prior_input");
const {
  PROVIDER_VERSION: CAPABILITY_PROVIDER_VERSION,
  inferCapabilities,
} = require("./wardrobe_capability_inference_provider");
const {
  provideWardrobeKnowledgeBasePriors,
} = require("./wardrobe_knowledge_base_prior_provider");

const DEFAULT_RESOLVER_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_wardrobe_profile_resolver_oracle_manifest.json");
const DEFAULT_OBS_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_provider_oracle_manifest.json");
const DEFAULT_IDENTITY_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_identity_qualification_oracle_manifest.json");
const DEFAULT_KB_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_wardrobe_kb_prior_oracle_manifest.json");
const SOURCE = path.resolve(__dirname,
  "prepare_wardrobe_profile_resolver_input.js");

function runWardrobeProfileResolverInputParity({
  resolverManifestPath = DEFAULT_RESOLVER_MANIFEST,
  observationManifestPath = DEFAULT_OBS_MANIFEST,
  identityManifestPath = DEFAULT_IDENTITY_MANIFEST,
  kbManifestPath = DEFAULT_KB_MANIFEST,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(resolverManifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== "WardrobeProfileResolver" ||
      manifest.providerVersion !== "wardrobe-profile-resolver-v1") {
    throw new Error("profile_resolver_input_oracle_integrity_failure");
  }
  if (manifest.readyScenarioCount !== 8 ||
      manifest.invocationCount !== 8) {
    throw new Error("profile_resolver_input_oracle_integrity_failure");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) {
    throw new Error("profile_resolver_input_oracle_integrity_failure");
  }
  const observationManifest = JSON.parse(
    fs.readFileSync(observationManifestPath, "utf8"));
  const identityManifest = JSON.parse(
    fs.readFileSync(identityManifestPath, "utf8"));
  const kbManifest = JSON.parse(fs.readFileSync(kbManifestPath, "utf8"));
  if (identityManifest.providerId !== "VisionIdentityQualification" ||
      identityManifest.readyScenarioCount !== 8 ||
      kbManifest.providerId !== "WardrobeKnowledgeBasePriorProvider" ||
      kbManifest.readyScenarioCount !== 8) {
    throw new Error("profile_resolver_input_oracle_integrity_failure");
  }
  const fixtureRoot = path.dirname(path.dirname(resolverManifestPath));
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
      throw new Error(`resolver_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = JSON.parse(oracleBytes.toString("utf8"));
    if (!Array.isArray(oracle.invocations) || oracle.invocations.length !== 1) {
      throw new Error(`resolver_invocation_count_invalid:${entry.scenarioId}`);
    }
    const expected = oracle.invocations[0].resolverInput;
    const prepared = buildPreparedInput({
      scenarioId: entry.scenarioId,
      fixtureRoot,
      observationById,
      identityById,
    });
    const differences = diff(expected, prepared);
    const membership = evidenceMembership(prepared.evidence);
    const expectedMembership = evidenceMembership(expected.evidence);
    const fieldParity = {
      itemId: expected.itemId === prepared.itemId,
      evidence:
        diff(expected.evidence, prepared.evidence).length === 0,
      evidenceOrdering: evidenceIds(expected.evidence)
        .join("\n") === evidenceIds(prepared.evidence).join("\n"),
      observationCount:
        membership.observation === expectedMembership.observation,
      identityCount: membership.identity === expectedMembership.identity,
      capabilityCount:
        membership.capability === expectedMembership.capability,
      kbCount: membership.kb === expectedMembership.kb,
      familyCount: membership.family === 0 &&
        expectedMembership.family === 0,
      fallbackCount: membership.fallback === 0 &&
        expectedMembership.fallback === 0,
      userCorrectionCount: membership.userCorrection === 0 &&
        expectedMembership.userCorrection === 0,
    };
    return {
      scenarioId: entry.scenarioId,
      passed: differences.length === 0,
      differences,
      fieldParity,
      membership,
      expectedMembership,
      outputSha256: sha256(canonicalBytes(prepared)),
      expectedInputSha256: sha256(canonicalBytes(expected)),
      evidenceCount: prepared.evidence.length,
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  const passed = scenarios.filter((item) => item.passed).length;
  const rerun = runWardrobeProfileResolverInputParityOnce({
    resolverManifestPath,
    observationManifestPath,
    identityManifestPath,
    kbManifestPath,
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
    dartResolverSha256: manifest.providerImplementationSha256,
    knowledgeBaseArtifactContentSha256:
      kbManifest.knowledgeBaseArtifactContentSha256,
    productionAuthorityVerdict: passed === 8 && deterministic ?
      "resolver_input_builder_sufficient_for_node_port" :
      "profile_resolver_input_parity_failed",
  });
}

function runWardrobeProfileResolverInputParityOnce({
  resolverManifestPath,
  observationManifestPath,
  identityManifestPath,
  kbManifestPath,
}) {
  const manifest = JSON.parse(fs.readFileSync(resolverManifestPath, "utf8"));
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const observationManifest = JSON.parse(
    fs.readFileSync(observationManifestPath, "utf8"));
  const identityManifest = JSON.parse(
    fs.readFileSync(identityManifestPath, "utf8"));
  void kbManifestPath;
  const fixtureRoot = path.dirname(path.dirname(resolverManifestPath));
  const observationById = new Map(
    observationManifest.fixtures.filter((item) => item.status === "ready")
      .map((item) => [item.scenarioId, item]));
  const identityById = new Map(
    identityManifest.fixtures.filter((item) => item.status === "ready")
      .map((item) => [item.scenarioId, item]));
  const scenarios = ready.map((entry) => {
    const prepared = buildPreparedInput({
      scenarioId: entry.scenarioId,
      fixtureRoot,
      observationById,
      identityById,
    });
    return {
      scenarioId: entry.scenarioId,
      outputSha256: sha256(canonicalBytes(prepared)),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  return {scenarios};
}

function buildPreparedInput({
  scenarioId,
  fixtureRoot,
  observationById,
  identityById,
}) {
  const observationEntry = observationById.get(scenarioId);
  const identityEntry = identityById.get(scenarioId);
  if (!observationEntry || !identityEntry) {
    throw new Error(`upstream_oracle_missing:${scenarioId}`);
  }
  const observationOracle = JSON.parse(fs.readFileSync(
    path.resolve(fixtureRoot, observationEntry.oraclePath), "utf8"));
  const identityOracle = JSON.parse(fs.readFileSync(
    path.resolve(fixtureRoot, identityEntry.oraclePath), "utf8"));
  const qualificationInput = JSON.parse(fs.readFileSync(path.join(
    fixtureRoot, "backend_qualification", "input",
    `${scenarioId}.input.json`), "utf8"));
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
  const kbInput = prepareVisionKnowledgeBasePriorInput({
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
  const knowledgeBaseEvidence = provideWardrobeKnowledgeBasePriors(kbInput);
  return prepareWardrobeProfileResolverInput({
    itemId: scenarioId,
    resolverCompatibilityVersion: 1,
    observationEvidence: observationOracle.providerOutput,
    observationProvenance: {
      observedAt: observationOracle.providerInput.observedAt,
      modelVersion: observationOracle.providerInput.modelVersion,
      sourceReference: observationOracle.providerInput.sourceReference,
    },
    qualifiedIdentityEvidence:
      identityOracle.invocations[0].providerOutput.qualifiedIdentityEvidence,
    capabilityEvidence,
    knowledgeBaseEvidence,
    // Present in 4 scenarios upstream; must not affect resolver input.
    familyIdentityReport: {present: true, ignoredByResolver: true},
  });
}

function buildWardrobeProfileResolverInputParityEntry(report) {
  return deepFreeze({
    stageId: report.stageId,
    stageVersion: report.stageVersion,
    contractVersion: report.contractVersion,
    parityStatus: report.parityStatus,
    productionAuthorityVerdict: report.productionAuthorityVerdict,
    scenarioCount: report.scenarioCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    deterministic: report.deterministic,
    nodeImplementationSha256: report.nodeImplementationSha256,
    dartCallSiteSha256: report.dartCallSiteSha256,
    dartResolverSha256: report.dartResolverSha256,
    knowledgeBaseArtifactContentSha256:
      report.knowledgeBaseArtifactContentSha256,
    scenarios: report.scenarios.map((item) => ({
      scenarioId: item.scenarioId,
      passed: item.passed,
      outputSha256: item.outputSha256,
      expectedInputSha256: item.expectedInputSha256,
      evidenceCount: item.evidenceCount,
      membership: item.membership,
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

function evidenceMembership(items) {
  let observation = 0;
  let identity = 0;
  let capability = 0;
  let kb = 0;
  let family = 0;
  let fallback = 0;
  let userCorrection = 0;
  for (const item of items) {
    if (item.property === "identity.family") family++;
    if (item.source === "knowledge_base_prior") {
      kb++;
      continue;
    }
    if (item.source === "legacy_fallback") {
      fallback++;
      continue;
    }
    if (item.source === "user_correction") {
      userCorrection++;
      continue;
    }
    if (item.source === "visual_observation") {
      observation++;
      continue;
    }
    if (item.property === "identity.canonicalType") {
      identity++;
      continue;
    }
    if (String(item.property).startsWith("capabilities.")) {
      capability++;
      continue;
    }
  }
  return {
    total: items.length,
    observation,
    identity,
    capability,
    kb,
    family,
    fallback,
    userCorrection,
  };
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
  buildWardrobeProfileResolverInputParityEntry,
  runWardrobeProfileResolverInputParity,
};
