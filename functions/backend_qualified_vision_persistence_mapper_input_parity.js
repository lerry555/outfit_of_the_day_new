"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  CONTRACT_VERSION,
  FIXTURE_CONTEXT_MODE,
  INPUT_CONTRACT,
  PERSISTENCE_EVIDENCE_VERSION,
  PERSISTENCE_SCHEMA_VERSION,
  RESOLVER_COMPATIBILITY_VERSION,
  STAGE_ID,
  STAGE_VERSION,
  prepareQualifiedVisionPersistenceMapperInput,
} = require("./prepare_qualified_vision_persistence_mapper_input");
const {
  PROVIDER_VERSION: CAPABILITY_PROVIDER_VERSION,
  inferCapabilities,
} = require("./wardrobe_capability_inference_provider");
const {attestFraming} = require("./vision_framing_attestor");
const {
  applyFramingToSubject,
  assessMultiPhotoConsistency,
} = require("./prepare_vision_identity_qualification_input");

const DEFAULT_MAPPER_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/" +
  "backend_qualified_vision_persistence_mapper_oracle_manifest.json");
const DEFAULT_OBS_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_provider_oracle_manifest.json");
const DEFAULT_IDENTITY_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_identity_qualification_oracle_manifest.json");
const DEFAULT_FAMILY_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_family_identity_oracle_manifest.json");
const DEFAULT_RESOLVER_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_wardrobe_profile_resolver_oracle_manifest.json");
const SOURCE = path.resolve(__dirname,
  "prepare_qualified_vision_persistence_mapper_input.js");

function runQualifiedVisionPersistenceMapperInputParity({
  mapperManifestPath = DEFAULT_MAPPER_MANIFEST,
  observationManifestPath = DEFAULT_OBS_MANIFEST,
  identityManifestPath = DEFAULT_IDENTITY_MANIFEST,
  familyManifestPath = DEFAULT_FAMILY_MANIFEST,
  resolverManifestPath = DEFAULT_RESOLVER_MANIFEST,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(mapperManifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== "QualifiedVisionPersistenceMapper" ||
      manifest.providerVersion !==
        "qualified-vision-persistence-mapper-v1") {
    throw new Error("persistence_mapper_input_oracle_integrity_failure");
  }
  if (manifest.readyScenarioCount !== 8 || manifest.invocationCount !== 8) {
    throw new Error("persistence_mapper_input_oracle_integrity_failure");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) {
    throw new Error("persistence_mapper_input_oracle_integrity_failure");
  }
  const observationManifest = JSON.parse(
    fs.readFileSync(observationManifestPath, "utf8"));
  const identityManifest = JSON.parse(
    fs.readFileSync(identityManifestPath, "utf8"));
  const familyManifest = JSON.parse(
    fs.readFileSync(familyManifestPath, "utf8"));
  const resolverManifest = JSON.parse(
    fs.readFileSync(resolverManifestPath, "utf8"));
  if (identityManifest.readyScenarioCount !== 8 ||
      familyManifest.readyScenarioCount !== 8 ||
      resolverManifest.readyScenarioCount !== 8) {
    throw new Error("persistence_mapper_input_oracle_integrity_failure");
  }
  const fixtureRoot = path.dirname(path.dirname(mapperManifestPath));
  const observationById = indexReady(observationManifest);
  const identityById = indexReady(identityManifest);
  const familyById = indexReady(familyManifest);
  const scenarios = ready.map((entry) => {
    const oracleBytes = fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(oracleBytes) !== entry.oracleSha256) {
      throw new Error(`mapper_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = JSON.parse(oracleBytes.toString("utf8"));
    if (!Array.isArray(oracle.invocations) || oracle.invocations.length !== 1) {
      throw new Error(`mapper_invocation_count_invalid:${entry.scenarioId}`);
    }
    const expected = oracle.invocations[0].mapperInput;
    const prepared = buildPreparedInput({
      scenarioId: entry.scenarioId,
      fixtureRoot,
      observationById,
      identityById,
      familyById,
    });
    const differences = diff(expected, prepared);
    const fieldParity = {
      analysisProjection:
        diff(expected.analysisProjection, prepared.analysisProjection)
          .length === 0,
      observationEvidence:
        diff(
          expected.analysisProjection.observationEvidence,
          prepared.analysisProjection.observationEvidence,
        ).length === 0,
      identity:
        diff(
          expected.analysisProjection.identityQualification,
          prepared.analysisProjection.identityQualification,
        ).length === 0 &&
        diff(
          expected.analysisProjection.qualifiedIdentityEvidence,
          prepared.analysisProjection.qualifiedIdentityEvidence,
        ).length === 0,
      family:
        diff(
          expected.analysisProjection.familyIdentity,
          prepared.analysisProjection.familyIdentity,
        ).length === 0,
      capability:
        diff(
          expected.analysisProjection.capabilityEvidence,
          prepared.analysisProjection.capabilityEvidence,
        ).length === 0,
      multiPhoto:
        diff(
          expected.analysisProjection.multiPhotoAssessment,
          prepared.analysisProjection.multiPhotoAssessment,
        ).length === 0,
      mappingContext:
        diff(expected.mappingContext, prepared.mappingContext).length === 0,
      revisionProvenance:
        expected.mappingContext.generationId ===
          prepared.mappingContext.generationId &&
        expected.mappingContext.revision === prepared.mappingContext.revision &&
        expected.mappingContext.imageRevision ===
          prepared.mappingContext.imageRevision &&
        expected.mappingContext.wardrobeItemRevision ===
          prepared.mappingContext.wardrobeItemRevision,
      versions:
        expected.mappingContext.visionSchemaVersion ===
          prepared.mappingContext.visionSchemaVersion &&
        expected.mappingContext.qualificationVersion ===
          prepared.mappingContext.qualificationVersion &&
        expected.analysisProjection.schemaVersion ===
          prepared.analysisProjection.schemaVersion,
    };
    return {
      scenarioId: entry.scenarioId,
      passed: differences.length === 0,
      differences,
      fieldParity,
      outputSha256: sha256(canonicalBytes(prepared)),
      expectedInputSha256: sha256(canonicalBytes(expected)),
      observationCount:
        prepared.analysisProjection.observationEvidence.length,
      capabilityCount:
        prepared.analysisProjection.capabilityEvidence.length,
      mappingStatus: entry.mappingStatus ??
        oracle.invocations[0].mappingStatus,
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  const passed = scenarios.filter((item) => item.passed).length;
  const rerun = runOnce({
    mapperManifestPath,
    observationManifestPath,
    identityManifestPath,
    familyManifestPath,
  });
  const deterministic = scenarios.every((item, index) =>
    item.outputSha256 === rerun.scenarios[index].outputSha256);
  return deepFreeze({
    stageId: STAGE_ID,
    stageVersion: STAGE_VERSION,
    contractVersion: CONTRACT_VERSION,
    inputContract: INPUT_CONTRACT,
    fixtureContextMode: FIXTURE_CONTEXT_MODE,
    persistenceSchemaVersion: PERSISTENCE_SCHEMA_VERSION,
    persistenceEvidenceVersion: PERSISTENCE_EVIDENCE_VERSION,
    resolverCompatibilityVersion: RESOLVER_COMPATIBILITY_VERSION,
    scenarioCount: scenarios.length,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    parityStatus: passed === 8 && deterministic ?
      "orchestration_ready" : "parity_failed",
    deterministic,
    scenarios,
    nodeImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dartMapperSha256: manifest.providerImplementationSha256,
    dartExporterSha256: manifest.exporterImplementationSha256,
    serializerSha256: manifest.serializerSha256,
    resolverOracleManifestSha256: manifest.resolverOracleManifestSha256,
    productionModeStatus: "blocked_without_trusted_revision_context",
    offlinePortReadinessVerdict: passed === 8 && deterministic ?
      "mapper_input_builder_ready_for_offline_node_port" :
      "persistence_mapper_input_parity_failed",
    productionRevisionVerdict: "trusted_revision_contract_required_for_production",
  });
}

function runOnce({
  mapperManifestPath,
  observationManifestPath,
  identityManifestPath,
  familyManifestPath,
}) {
  const manifest = JSON.parse(fs.readFileSync(mapperManifestPath, "utf8"));
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const observationManifest = JSON.parse(
    fs.readFileSync(observationManifestPath, "utf8"));
  const identityManifest = JSON.parse(
    fs.readFileSync(identityManifestPath, "utf8"));
  const familyManifest = JSON.parse(
    fs.readFileSync(familyManifestPath, "utf8"));
  const fixtureRoot = path.dirname(path.dirname(mapperManifestPath));
  const observationById = indexReady(observationManifest);
  const identityById = indexReady(identityManifest);
  const familyById = indexReady(familyManifest);
  const scenarios = ready.map((entry) => {
    const prepared = buildPreparedInput({
      scenarioId: entry.scenarioId,
      fixtureRoot,
      observationById,
      identityById,
      familyById,
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
  familyById,
}) {
  const observationEntry = observationById.get(scenarioId);
  const identityEntry = identityById.get(scenarioId);
  const familyEntry = familyById.get(scenarioId);
  if (!observationEntry || !identityEntry || !familyEntry) {
    throw new Error(`upstream_oracle_missing:${scenarioId}`);
  }
  const observationOracle = JSON.parse(fs.readFileSync(
    path.resolve(fixtureRoot, observationEntry.oraclePath), "utf8"));
  const identityOracle = JSON.parse(fs.readFileSync(
    path.resolve(fixtureRoot, identityEntry.oraclePath), "utf8"));
  const familyOracle = JSON.parse(fs.readFileSync(
    path.resolve(fixtureRoot, familyEntry.oraclePath), "utf8"));
  const qualificationInput = JSON.parse(fs.readFileSync(path.join(
    fixtureRoot, "backend_qualification", "input",
    `${scenarioId}.input.json`), "utf8"));
  const parser = JSON.parse(fs.readFileSync(path.join(
    fixtureRoot, "backend_qualification", "parser",
    `${scenarioId}.parser.json`), "utf8"));
  const primary = parser.views[0].response;
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
  const multiPhotoAssessment = reconstructMultiPhotoAssessment(parser);
  // Resolver oracle is bound for integrity but mapper ignores resolvedProfile.
  void DEFAULT_RESOLVER_MANIFEST;
  return prepareQualifiedVisionPersistenceMapperInput({
    contextMode: FIXTURE_CONTEXT_MODE,
    scenarioId,
    analysisId: primary.analysisId,
    modelVersion: primary.modelVersion,
    schemaVersion: primary.schemaVersion,
    inputAssessment: primary.inputAssessment,
    observationEvidence: observationOracle.providerOutput,
    observationProvenance: {
      observedAt: observationOracle.providerInput.observedAt,
      modelVersion: observationOracle.providerInput.modelVersion,
      sourceReference: observationOracle.providerInput.sourceReference,
    },
    qualifiedIdentityEvidence:
      identityOracle.invocations[0].providerOutput.qualifiedIdentityEvidence,
    identityQualification:
      identityOracle.invocations[0].providerOutput.report,
    familyIdentity: familyOracle.invocations[0].providerOutput,
    capabilityEvidence,
    multiPhotoAssessment,
    persistenceSchemaVersion: PERSISTENCE_SCHEMA_VERSION,
    persistenceEvidenceVersion: PERSISTENCE_EVIDENCE_VERSION,
    resolverCompatibilityVersion: RESOLVER_COMPATIBILITY_VERSION,
  });
}

function reconstructMultiPhotoAssessment(parser) {
  const binding = parser.multiViewSubjectBinding ?? {
    contractVersion: 1,
    physicalIdentityClaim: "undeclared",
    reasonCodes: ["default_undeclared"],
    source: "unknown",
  };
  const systemSubjects = parser.views.map((view) => {
    const response = view.response;
    const report = attestFraming({
      inputAssessment: response.inputAssessment,
      subject: response.subjectAssessment,
      quality: response.quality,
      attestations: response.subjectAssessment.framingAttestations,
    });
    return applyFramingToSubject(report, response.subjectAssessment);
  });
  const multi = assessMultiPhotoConsistency(systemSubjects, binding);
  const {binding: bind, ...rest} = multi;
  return {
    ...rest,
    multiViewSubjectBinding: bind,
  };
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

function buildQualifiedVisionPersistenceMapperInputParityEntry(report) {
  return deepFreeze({
    stageId: report.stageId,
    stageVersion: report.stageVersion,
    contractVersion: report.contractVersion,
    inputContract: report.inputContract,
    fixtureContextMode: report.fixtureContextMode,
    persistenceSchemaVersion: report.persistenceSchemaVersion,
    persistenceEvidenceVersion: report.persistenceEvidenceVersion,
    resolverCompatibilityVersion: report.resolverCompatibilityVersion,
    parityStatus: report.parityStatus,
    offlinePortReadinessVerdict: report.offlinePortReadinessVerdict,
    productionRevisionVerdict: report.productionRevisionVerdict,
    productionModeStatus: report.productionModeStatus,
    scenarioCount: report.scenarioCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    deterministic: report.deterministic,
    nodeImplementationSha256: report.nodeImplementationSha256,
    dartMapperSha256: report.dartMapperSha256,
    dartExporterSha256: report.dartExporterSha256,
    serializerSha256: report.serializerSha256,
    resolverOracleManifestSha256: report.resolverOracleManifestSha256,
    scenarios: report.scenarios.map((item) => ({
      scenarioId: item.scenarioId,
      passed: item.passed,
      outputSha256: item.outputSha256,
      expectedInputSha256: item.expectedInputSha256,
      observationCount: item.observationCount,
      capabilityCount: item.capabilityCount,
      mappingStatus: item.mappingStatus,
      fieldParity: item.fieldParity,
    })),
  });
}

function updateMapperInputOrchestrationManifest(report, {
  manifestPath = path.resolve(__dirname, "../test/fixtures/" +
    "backend_qualification/" +
    "backend_qualified_vision_persistence_mapper_input_orchestration_manifest.json"),
} = {}) {
  const entry = buildQualifiedVisionPersistenceMapperInputParityEntry(report);
  const bytes = Buffer.from(`${JSON.stringify(entry, null, 2)}\n`, "utf8");
  fs.mkdirSync(path.dirname(manifestPath), {recursive: true});
  fs.writeFileSync(manifestPath, bytes);
  const again = Buffer.from(
    `${JSON.stringify(JSON.parse(fs.readFileSync(manifestPath, "utf8")), null, 2)}\n`,
    "utf8");
  if (!bytes.equals(again)) {
    throw new Error("orchestration_manifest_not_byte_identical");
  }
  return entry;
}

function indexReady(manifest) {
  return new Map(
    manifest.fixtures.filter((item) => item.status === "ready")
      .map((item) => [item.scenarioId, item]));
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
  STAGE_ID,
  STAGE_VERSION,
  CONTRACT_VERSION,
  INPUT_CONTRACT,
  FIXTURE_CONTEXT_MODE,
  PERSISTENCE_SCHEMA_VERSION,
  PERSISTENCE_EVIDENCE_VERSION,
  RESOLVER_COMPATIBILITY_VERSION,
  buildPreparedInput,
  buildQualifiedVisionPersistenceMapperInputParityEntry,
  projectCapabilityWire,
  reconstructMultiPhotoAssessment,
  runQualifiedVisionPersistenceMapperInputParity,
  updateMapperInputOrchestrationManifest,
};

if (require.main === module) {
  const report = runQualifiedVisionPersistenceMapperInputParity();
  updateMapperInputOrchestrationManifest(report);
  process.stdout.write(`${JSON.stringify({
    parityStatus: report.parityStatus,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    deterministic: report.deterministic,
    offlinePortReadinessVerdict: report.offlinePortReadinessVerdict,
    productionRevisionVerdict: report.productionRevisionVerdict,
  }, null, 2)}\n`);
}
