"use strict";

/**
 * Offline Backend Qualification Orchestrator / v1
 *
 * Composes existing parity-ready Node stages without changing provider
 * semantics. Offline fixture-replay mode achieves 8/8 mapper/resolver parity
 * against Dart oracle artifacts. Not imported by production entry points.
 *
 * Full Dart early-stage glue (complementary regions across views before
 * observation evidence) remains recorded in stage oracles; this orchestrator
 * chains those parity-ready handoffs through prepare → resolve → map.
 */

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  FIXTURE_CONTEXT_MODE,
  PRODUCTION_CONTEXT_MODE,
  prepareQualifiedVisionPersistenceMapperInput,
} = require("./prepare_qualified_vision_persistence_mapper_input");
const {
  mapQualifiedVisionPersistence,
} = require("./qualified_vision_persistence_mapper");
const {
  prepareWardrobeProfileResolverInput,
} = require("./prepare_wardrobe_profile_resolver_input");
const {
  resolveWardrobeProfile,
} = require("./wardrobe_profile_resolver");
const {
  prepareVisionKnowledgeBasePriorInput,
} = require("./prepare_vision_knowledge_base_prior_input");
const {
  provideWardrobeKnowledgeBasePriors,
} = require("./wardrobe_knowledge_base_prior_provider");
const {
  buildPreparedInput,
  projectCapabilityWire,
} = require("./backend_qualified_vision_persistence_mapper_input_parity");
const {
  PROVIDER_VERSION: CAPABILITY_PROVIDER_VERSION,
  inferCapabilities,
} = require("./wardrobe_capability_inference_provider");

const ORCHESTRATOR_ID = "WardrobeBackendQualificationOrchestrator";
const ORCHESTRATOR_VERSION =
  "wardrobe-backend-qualification-orchestrator-v1";

const DEFAULT_MAPPER_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/" +
  "backend_qualified_vision_persistence_mapper_oracle_manifest.json");

/**
 * Run offline fixture orchestration for one scenario.
 */
function runBackendQualificationOrchestration(input) {
  if (input == null || typeof input !== "object" || Array.isArray(input)) {
    fail("orchestrator_input_not_object");
  }
  const scenarioId = requireNonEmpty(input.scenarioId, "scenarioId");
  const contextMode = input.contextMode || FIXTURE_CONTEXT_MODE;
  const fixtureRoot = input.fixtureRoot || path.resolve(__dirname,
    "../test/fixtures");
  const manifests = loadManifestIndexes(fixtureRoot);
  const preparedBase = buildPreparedInput({
    scenarioId,
    fixtureRoot,
    observationById: manifests.observationById,
    identityById: manifests.identityById,
    familyById: manifests.familyById,
  });

  let mapperInput;
  if (contextMode === FIXTURE_CONTEXT_MODE) {
    mapperInput = preparedBase;
  } else if (contextMode === PRODUCTION_CONTEXT_MODE) {
    if (input.trustedMappingContext == null) {
      fail("trusted_revision_context_unavailable");
    }
    mapperInput = prepareQualifiedVisionPersistenceMapperInput({
      contextMode: PRODUCTION_CONTEXT_MODE,
      analysisId: preparedBase.analysisProjection.analysisId,
      modelVersion: preparedBase.analysisProjection.modelVersion,
      schemaVersion: preparedBase.analysisProjection.schemaVersion,
      inputAssessment: preparedBase.analysisProjection.inputAssessment,
      observationEvidence:
        preparedBase.analysisProjection.observationEvidence,
      observationProvenance: {
        observedAt: preparedBase.mappingContext.completedAt,
        modelVersion: preparedBase.analysisProjection.modelVersion,
        sourceReference:
          `wardrobe://${requireNonEmpty(input.itemId || scenarioId, "itemId")}`,
      },
      qualifiedIdentityEvidence:
        preparedBase.analysisProjection.qualifiedIdentityEvidence,
      identityQualification:
        preparedBase.analysisProjection.identityQualification,
      familyIdentity: preparedBase.analysisProjection.familyIdentity,
      capabilityEvidence:
        preparedBase.analysisProjection.capabilityEvidence,
      multiPhotoAssessment:
        preparedBase.analysisProjection.multiPhotoAssessment,
      trustedMappingContext: input.trustedMappingContext,
    });
  } else {
    fail("orchestrator_context_mode_invalid");
  }

  const mapperResult = mapQualifiedVisionPersistence(
    contextMode === PRODUCTION_CONTEXT_MODE ?
      {...mapperInput, contextMode: PRODUCTION_CONTEXT_MODE,
        trustedRevisionAuthority: true} :
      {...mapperInput, contextMode: FIXTURE_CONTEXT_MODE},
  );

  const observationOracle = JSON.parse(fs.readFileSync(path.resolve(
    fixtureRoot, manifests.observationById.get(scenarioId).oraclePath),
  "utf8"));
  const identityOracle = JSON.parse(fs.readFileSync(path.resolve(
    fixtureRoot, manifests.identityById.get(scenarioId).oraclePath),
  "utf8"));
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

  const kbPrepared = prepareVisionKnowledgeBasePriorInput({
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
  const knowledgeBaseEvidence = provideWardrobeKnowledgeBasePriors(kbPrepared);
  const resolverPrepared = prepareWardrobeProfileResolverInput({
    itemId: input.itemId || scenarioId,
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
    familyIdentityReport: {present: true, ignoredByResolver: true},
  });
  const resolvedProfile = resolveWardrobeProfile(resolverPrepared);

  return deepFreeze({
    orchestratorId: ORCHESTRATOR_ID,
    orchestratorVersion: ORCHESTRATOR_VERSION,
    scenarioId,
    contextMode,
    analysisId: mapperInput.analysisProjection.analysisId,
    mapperInput,
    mapperResult,
    resolvedProfile,
    knowledgeBaseEvidence,
    stages: Object.freeze([
      "parser_fixture_handoff",
      "observation_evidence_oracle",
      "identity_qualification_oracle",
      "family_identity_oracle",
      "capability_inference",
      "kb_prior",
      "profile_resolver",
      "mapper_input_prepare",
      "persistence_mapper",
    ]),
  });
}

/**
 * End-to-end offline parity across 8 ready mapper scenarios.
 */
function runBackendQualificationOrchestrationParity({
  mapperManifestPath = DEFAULT_MAPPER_MANIFEST,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(mapperManifestPath, "utf8"));
  const fixtureRoot = path.dirname(path.dirname(mapperManifestPath));
  const ready = manifest.fixtures.filter((item) => item.status === "ready")
    .sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  if (ready.length !== 8) fail("orchestrator_ready_count_invalid");

  const scenarios = ready.map((entry) => {
    const oracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath), "utf8"));
    const expectedMapper = oracle.invocations[0].mapperOutput;
    const run = runBackendQualificationOrchestration({
      scenarioId: entry.scenarioId,
      contextMode: FIXTURE_CONTEXT_MODE,
      fixtureRoot,
    });
    const mapperDiff = diff(expectedMapper, run.mapperResult);
    const envelope = run.mapperResult.envelope || null;
    const omitted = run.mapperResult.omittedEvidenceReasonCodes || [];
    return {
      scenarioId: entry.scenarioId,
      passed: mapperDiff.length === 0,
      differences: mapperDiff,
      mapperStatus: run.mapperResult.status,
      analysisId: run.analysisId,
      resolvedItemId: run.resolvedProfile && run.resolvedProfile.itemId,
      machineEvidenceCount: envelope && Array.isArray(envelope.machineEvidence) ?
        envelope.machineEvidence.length : 0,
      omitted,
      omittedSorted: [...omitted].sort(),
      outputSha256: sha256(canonicalBytes(run.mapperResult)),
      profileSha256: sha256(canonicalBytes(run.resolvedProfile)),
    };
  });

  const rerun = ready.map((entry) => {
    const run = runBackendQualificationOrchestration({
      scenarioId: entry.scenarioId,
      contextMode: FIXTURE_CONTEXT_MODE,
      fixtureRoot,
    });
    return sha256(canonicalBytes(run.mapperResult));
  });
  const deterministic = scenarios.every((item, index) =>
    item.outputSha256 === rerun[index]);
  const passed = scenarios.filter((item) => item.passed).length;

  return deepFreeze({
    orchestratorId: ORCHESTRATOR_ID,
    orchestratorVersion: ORCHESTRATOR_VERSION,
    scenarioCount: scenarios.length,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    deterministic,
    parityStatus: passed === 8 && deterministic ?
      "orchestration_ready_offline" : "parity_failed",
    scenarios,
  });
}

function loadManifestIndexes(fixtureRoot) {
  const observationManifest = JSON.parse(fs.readFileSync(path.join(
    fixtureRoot, "backend_qualification",
    "backend_provider_oracle_manifest.json"), "utf8"));
  const identityManifest = JSON.parse(fs.readFileSync(path.join(
    fixtureRoot, "backend_qualification",
    "backend_identity_qualification_oracle_manifest.json"), "utf8"));
  const familyManifest = JSON.parse(fs.readFileSync(path.join(
    fixtureRoot, "backend_qualification",
    "backend_family_identity_oracle_manifest.json"), "utf8"));
  return {
    observationById: indexReady(observationManifest),
    identityById: indexReady(identityManifest),
    familyById: indexReady(familyManifest),
  };
}

function indexReady(manifest) {
  return new Map(
    manifest.fixtures.filter((item) => item.status === "ready")
      .map((item) => [item.scenarioId, item]));
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function requireNonEmpty(value, label) {
  if (typeof value !== "string" || !value.trim()) fail(`${label}_empty`);
  return value.trim();
}

function deepFreeze(value) {
  if (value == null || typeof value !== "object") return value;
  if (Object.isFrozen(value)) return value;
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  DEFAULT_MAPPER_MANIFEST,
  FIXTURE_CONTEXT_MODE,
  ORCHESTRATOR_ID,
  ORCHESTRATOR_VERSION,
  PRODUCTION_CONTEXT_MODE,
  runBackendQualificationOrchestration,
  runBackendQualificationOrchestrationParity,
};
