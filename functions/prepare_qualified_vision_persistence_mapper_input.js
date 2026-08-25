"use strict";

/**
 * Trusted QualifiedVisionPersistenceMapper input preparation
 * (orchestration stage).
 *
 * Pure / deterministic. Not imported by production Vision entry points.
 * Builds qualified_vision_persistence_mapper_input/v1 matching the Dart
 * offline mapper oracle projection:
 *
 *   { analysisProjection, mappingContext }
 *
 * Fixture mode synthesizes PersistenceMappingContext from scenarioId +
 * analysis-matched fields (fixture_authoritative_context_v1).
 * Production mode requires an explicit trusted mapping context and fails
 * closed without it (trusted_revision_context_unavailable).
 *
 * Does not run the mapper, repository, CAS, or Firestore write.
 */

const STAGE_ID = "PrepareQualifiedVisionPersistenceMapperInput";
const STAGE_VERSION = "qualified-vision-persistence-mapper-input-v1";
const CONTRACT_VERSION = 1;
const INPUT_CONTRACT = "qualified_vision_persistence_mapper_input/v1";
const FIXTURE_CONTEXT_MODE = "fixture_authoritative_context_v1";
const PRODUCTION_CONTEXT_MODE = "production";
const MAPPER_COMPATIBILITY_VERSION = 1;
const PERSISTENCE_SCHEMA_VERSION = 1;
const PERSISTENCE_EVIDENCE_VERSION = 1;
const RESOLVER_COMPATIBILITY_VERSION = 1;

const FORBIDDEN_AUTHORITY_FIELDS = Object.freeze([
  "analysisProjection",
  "mapperInput",
  "preparedMapperInput",
  "machineEvidence",
  "resolvedProfile",
  "resolvedCache",
  "knowledgeBaseEvidence",
  "envelope",
  "repositorySnapshot",
  "casExpectedRevision",
  "firestoreTimestamp",
  "userCorrections",
  "writeDecision",
]);

const CONTEXT_MODES = new Set([
  FIXTURE_CONTEXT_MODE,
  PRODUCTION_CONTEXT_MODE,
]);

const INPUT_ASSESSMENTS = new Set([
  "valid_single_item",
  "multiple_items",
  "insufficient_visual_information",
  "non_wardrobe_object",
  "ambiguous_subject",
]);

const EVIDENCE_SOURCES = new Set([
  "user_correction",
  "verified_product_metadata",
  "label_metadata",
  "visual_observation",
  "ai_inference",
  "knowledge_base_prior",
  "legacy_fallback",
]);

const EVIDENCE_NATURES = new Set([
  "unknown",
  "observed",
  "inferred",
  "defaulted",
]);

const VALUE_STATES = new Set([
  "known",
  "unknown",
  "not_visible",
  "not_applicable",
]);

const ANALYSIS_KINDS = new Set([
  "initial_analysis",
  "reanalysis",
]);

/**
 * @param {object} raw
 * @returns {Readonly<{analysisProjection: object, mappingContext: object}>}
 */
function prepareQualifiedVisionPersistenceMapperInput(raw) {
  const input = decodePrepareInput(raw);
  const observationEvidence = projectObservationEvidence(
    input.observationEvidence, input.observationProvenance)
    .sort((left, right) => compareUtf16(left.id, right.id));
  const qualifiedIdentityEvidence = input.qualifiedIdentityEvidence.map(
    (item) => projectEvidence(item));
  const capabilityEvidence = input.capabilityEvidence.map(
    (item) => projectEvidence(item));
  assertNoDuplicateIds([
    ...observationEvidence,
    ...qualifiedIdentityEvidence,
    ...capabilityEvidence,
  ]);
  assertNoForbiddenEvidenceSources(observationEvidence, new Set([
    "visual_observation",
  ]));
  assertNoKnowledgeBaseEvidence([
    ...observationEvidence,
    ...qualifiedIdentityEvidence,
    ...capabilityEvidence,
  ]);

  const analysisProjection = deepFreeze({
    analysisId: input.analysisId,
    capabilityEvidence,
    familyIdentity: deepFreeze(structuredClone(input.familyIdentity)),
    identityQualification: deepFreeze(
      structuredClone(input.identityQualification)),
    inputAssessment: input.inputAssessment,
    inputAssessmentValid: input.inputAssessment === "valid_single_item",
    modelVersion: input.modelVersion,
    multiPhotoAssessment: deepFreeze(
      structuredClone(input.multiPhotoAssessment)),
    observationEvidence,
    qualifiedIdentityEvidence,
    schemaVersion: input.schemaVersion,
  });

  const mappingContext = input.contextMode === FIXTURE_CONTEXT_MODE ?
    buildFixtureMappingContext(input) :
    validateTrustedMappingContext(input);

  assertAnalysisContextConsistency(analysisProjection, mappingContext);

  return deepFreeze({
    analysisProjection,
    mappingContext,
  });
}

function buildFixtureMappingContext(input) {
  const observedAt = requireUtcTimestamp(
    input.observationProvenance.observedAt, "observationProvenance.observedAt");
  return deepFreeze({
    analysisId: input.analysisId,
    analysisKind: "initial_analysis",
    completedAt: observedAt,
    createdAt: observedAt,
    generationId: `fixture-generation:${input.scenarioId}`,
    imageHash: `fixture-hash:${input.scenarioId}`,
    imageRevision: 1,
    modelIdentifier: input.modelVersion,
    pipelineVersion: "vision-v2-phase-4.9",
    promptVersion: "vision-v2-schema-9",
    qualificationVersion: "qualification-v1",
    revision: 1,
    storagePath: `fixture://wardrobe/${input.scenarioId}/source.jpg`,
    updatedAt: observedAt,
    uploadGeneration: `fixture-upload:${input.scenarioId}`,
    visionSchemaVersion: input.schemaVersion,
    wardrobeItemRevision: 1,
  });
}

function validateTrustedMappingContext(input) {
  if (input.trustedMappingContext == null) {
    fail("trusted_revision_context_unavailable");
  }
  const context = decodeMappingContext(
    input.trustedMappingContext, "trustedMappingContext");
  if (context.generationId.startsWith("fixture-generation:")) {
    fail("production_context_rejects_fixture_generation");
  }
  if (typeof context.storagePath === "string" &&
      context.storagePath.startsWith("fixture://")) {
    fail("production_context_rejects_fixture_storage_path");
  }
  return context;
}

function decodePrepareInput(raw) {
  if (!isObject(raw)) fail("prepare_input_not_object");
  for (const field of FORBIDDEN_AUTHORITY_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(raw, field)) {
      fail(`forbidden_authority_field:${field}`);
    }
  }
  const contextMode = requireString(raw.contextMode, "contextMode");
  if (!CONTEXT_MODES.has(contextMode)) fail("context_mode_invalid");
  if (contextMode === PRODUCTION_CONTEXT_MODE &&
      raw.trustedMappingContext == null) {
    fail("trusted_revision_context_unavailable");
  }
  const scenarioId = contextMode === FIXTURE_CONTEXT_MODE ?
    requireNonEmptyString(raw.scenarioId, "scenarioId") : null;
  if (contextMode === FIXTURE_CONTEXT_MODE) {
    assertFixtureSafeScenarioId(scenarioId);
  }
  const analysisId = requireNonEmptyString(raw.analysisId, "analysisId");
  const modelVersion = requireNonEmptyString(raw.modelVersion, "modelVersion");
  const schemaVersion = requirePositiveInt(raw.schemaVersion, "schemaVersion");
  const inputAssessment = requireString(raw.inputAssessment, "inputAssessment");
  if (!INPUT_ASSESSMENTS.has(inputAssessment)) {
    fail("input_assessment_invalid");
  }
  if (raw.persistenceSchemaVersion != null &&
      raw.persistenceSchemaVersion !== PERSISTENCE_SCHEMA_VERSION) {
    fail("unsupported_persistence_schema");
  }
  if (raw.persistenceEvidenceVersion != null &&
      raw.persistenceEvidenceVersion !== PERSISTENCE_EVIDENCE_VERSION) {
    fail("unsupported_persistence_evidence_version");
  }
  if (raw.resolverCompatibilityVersion != null &&
      raw.resolverCompatibilityVersion !== RESOLVER_COMPATIBILITY_VERSION) {
    fail("unsupported_resolver_compatibility_version");
  }
  const observationProvenance = decodeObservationProvenance(
    raw.observationProvenance);
  return {
    contextMode,
    scenarioId,
    analysisId,
    modelVersion,
    schemaVersion,
    inputAssessment,
    observationEvidence: requireArray(
      raw.observationEvidence, "observationEvidence"),
    observationProvenance,
    qualifiedIdentityEvidence: requireArray(
      raw.qualifiedIdentityEvidence, "qualifiedIdentityEvidence"),
    identityQualification: requireObject(
      raw.identityQualification, "identityQualification"),
    familyIdentity: requireObject(raw.familyIdentity, "familyIdentity"),
    capabilityEvidence: requireArray(
      raw.capabilityEvidence, "capabilityEvidence"),
    multiPhotoAssessment: decodeMultiPhotoAssessment(
      raw.multiPhotoAssessment),
    trustedMappingContext: raw.trustedMappingContext ?? null,
  };
}

function decodeObservationProvenance(raw) {
  const value = requireObject(raw, "observationProvenance");
  return {
    observedAt: requireUtcTimestamp(value.observedAt, "observedAt"),
    modelVersion: requireNonEmptyString(value.modelVersion, "modelVersion"),
    sourceReference: requireNonEmptyString(
      value.sourceReference, "sourceReference"),
  };
}

function decodeMultiPhotoAssessment(raw) {
  const value = requireObject(raw, "multiPhotoAssessment");
  requireString(value.physicalIdentity, "multiPhotoAssessment.physicalIdentity");
  requireString(
    value.semanticAgreement, "multiPhotoAssessment.semanticAgreement");
  if (typeof value.permitsIdentityPromotion !== "boolean") {
    fail("multiPhotoAssessment.permitsIdentityPromotion_invalid");
  }
  if (typeof value.sameItemViews !== "boolean") {
    fail("multiPhotoAssessment.sameItemViews_invalid");
  }
  requireArray(value.reasonCodes, "multiPhotoAssessment.reasonCodes");
  requireObject(
    value.multiViewSubjectBinding, "multiPhotoAssessment.multiViewSubjectBinding");
  if (Object.prototype.hasOwnProperty.call(value, "binding")) {
    fail("multiPhotoAssessment_uses_dart_wire_key_multiViewSubjectBinding");
  }
  return value;
}

function decodeMappingContext(raw, label) {
  const value = requireObject(raw, label);
  const createdAt = requireUtcTimestamp(value.createdAt, `${label}.createdAt`);
  const updatedAt = requireUtcTimestamp(value.updatedAt, `${label}.updatedAt`);
  const completedAt = requireUtcTimestamp(
    value.completedAt, `${label}.completedAt`);
  if (Date.parse(updatedAt) < Date.parse(createdAt)) {
    fail("provenance_value_invalid");
  }
  const generationId = requireNonEmptyString(
    value.generationId, `${label}.generationId`);
  const revision = requireNonNegativeInt(value.revision, `${label}.revision`);
  const imageRevision = requireNonNegativeInt(
    value.imageRevision, `${label}.imageRevision`);
  const wardrobeItemRevision = requireNonNegativeInt(
    value.wardrobeItemRevision, `${label}.wardrobeItemRevision`);
  const analysisId = requireNonEmptyString(
    value.analysisId, `${label}.analysisId`);
  const analysisKind = requireString(value.analysisKind, `${label}.analysisKind`);
  if (!ANALYSIS_KINDS.has(analysisKind)) fail("analysis_kind_invalid");
  const modelIdentifier = requireNonEmptyString(
    value.modelIdentifier, `${label}.modelIdentifier`);
  const pipelineVersion = requireNonEmptyString(
    value.pipelineVersion, `${label}.pipelineVersion`);
  const promptVersion = requireNonEmptyString(
    value.promptVersion, `${label}.promptVersion`);
  const qualificationVersion = requireNonEmptyString(
    value.qualificationVersion, `${label}.qualificationVersion`);
  const visionSchemaVersion = requirePositiveInt(
    value.visionSchemaVersion, `${label}.visionSchemaVersion`);
  assertNoAbsolutePath(value.storagePath);
  assertNoSecretLike(value.storagePath);
  assertNoSecretLike(value.imageHash);
  assertNoSecretLike(value.uploadGeneration);
  return deepFreeze({
    analysisId,
    analysisKind,
    completedAt,
    createdAt,
    generationId,
    ...(value.imageHash != null ? {
      imageHash: requireNonEmptyString(value.imageHash, `${label}.imageHash`),
    } : {}),
    imageRevision,
    modelIdentifier,
    pipelineVersion,
    promptVersion,
    qualificationVersion,
    revision,
    ...(value.storagePath != null ? {
      storagePath: requireNonEmptyString(
        value.storagePath, `${label}.storagePath`),
    } : {}),
    updatedAt,
    ...(value.uploadGeneration != null ? {
      uploadGeneration: requireNonEmptyString(
        value.uploadGeneration, `${label}.uploadGeneration`),
    } : {}),
    visionSchemaVersion,
    wardrobeItemRevision,
  });
}

function assertAnalysisContextConsistency(analysis, context) {
  if (context.analysisId !== analysis.analysisId) {
    fail("analysis_id_mismatch");
  }
  if (context.modelIdentifier !== analysis.modelVersion) {
    fail("model_identifier_mismatch");
  }
  if (context.visionSchemaVersion !== analysis.schemaVersion) {
    fail("vision_schema_version_mismatch");
  }
  if (context.qualificationVersion !== "qualification-v1") {
    fail("qualification_version_mismatch");
  }
}

function projectObservationEvidence(list, provenance) {
  return list.map((item) => {
    if (!isObject(item)) fail("observation_evidence_item_invalid");
    const projected = {
      active: item.active !== false,
      confidence: requireConfidence(item.confidence, "confidence"),
      createdAt: requireUtcTimestamp(
        item.createdAt ?? provenance.observedAt, "createdAt"),
      id: requireNonEmptyString(item.id, "id"),
      method: requireNonEmptyString(item.method, "method"),
      modelVersion: requireNonEmptyString(
        item.modelVersion ?? provenance.modelVersion, "modelVersion"),
      nature: requireEnum(item.nature, EVIDENCE_NATURES, "nature"),
      property: requireNonEmptyString(item.property, "property"),
      source: requireEnum(item.source, EVIDENCE_SOURCES, "source"),
      sourceReference: requireNonEmptyString(
        item.sourceReference ?? provenance.sourceReference, "sourceReference"),
      value: Object.prototype.hasOwnProperty.call(item, "value") ?
        item.value : null,
      verified: item.verified === true,
    };
    if (item.valueState != null && item.valueState !== "known") {
      projected.valueState = requireEnum(
        item.valueState, VALUE_STATES, "valueState");
    }
    return projected;
  });
}

function projectEvidence(item) {
  if (!isObject(item)) fail("evidence_item_invalid");
  const projected = {
    active: item.active !== false,
    confidence: requireConfidence(item.confidence, "confidence"),
    createdAt: requireUtcTimestamp(item.createdAt, "createdAt"),
    id: requireNonEmptyString(item.id, "id"),
    method: requireNonEmptyString(item.method, "method"),
    modelVersion: requireNonEmptyString(item.modelVersion, "modelVersion"),
    nature: requireEnum(item.nature, EVIDENCE_NATURES, "nature"),
    property: requireNonEmptyString(item.property, "property"),
    source: requireEnum(item.source, EVIDENCE_SOURCES, "source"),
    value: Object.prototype.hasOwnProperty.call(item, "value") ?
      item.value : null,
    verified: item.verified === true,
  };
  if (item.sourceReference != null) {
    projected.sourceReference = requireNonEmptyString(
      item.sourceReference, "sourceReference");
  }
  if (item.valueState != null && item.valueState !== "known") {
    projected.valueState = requireEnum(
      item.valueState, VALUE_STATES, "valueState");
  }
  return projected;
}

function assertNoDuplicateIds(evidence) {
  const seen = new Set();
  for (const item of evidence) {
    if (seen.has(item.id)) fail(`duplicate_evidence_id:${item.id}`);
    seen.add(item.id);
  }
}

function assertNoForbiddenEvidenceSources(evidence, allowed) {
  for (const item of evidence) {
    if (!allowed.has(item.source)) {
      fail(`observation_source_invalid:${item.source}`);
    }
  }
}

function assertNoKnowledgeBaseEvidence(evidence) {
  for (const item of evidence) {
    if (item.source === "knowledge_base_prior" ||
        String(item.id).startsWith("kb-prior:")) {
      fail("knowledge_base_evidence_forbidden_in_mapper_input");
    }
  }
}

function assertFixtureSafeScenarioId(scenarioId) {
  if (/[\\/]/.test(scenarioId) || scenarioId.includes("..")) {
    fail("scenario_id_path_unsafe");
  }
  if (/^[A-Za-z]:/.test(scenarioId)) fail("scenario_id_absolute_path");
}

function assertNoAbsolutePath(value) {
  if (value == null) return;
  const text = String(value);
  if (text.includes("\\") || /^[A-Za-z]:/.test(text) || text.startsWith("/Users/") ||
      text.startsWith("/home/")) {
    fail("absolute_path_rejected");
  }
}

function assertNoSecretLike(value) {
  if (value == null) return;
  const text = String(value);
  if (/Bearer\s/i.test(text) || /signature=/i.test(text) ||
      /X-Goog-Signature/i.test(text) || /token=/i.test(text)) {
    fail("secret_or_signed_url_rejected");
  }
}

function requireUtcTimestamp(value, label) {
  const text = requireNonEmptyString(value, label);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(text)) {
    fail(`${label}_non_utc_timestamp`);
  }
  if (Number.isNaN(Date.parse(text))) fail(`${label}_invalid_timestamp`);
  return text;
}

function requireConfidence(value, label) {
  if (typeof value !== "number" || Number.isNaN(value) ||
      value < 0 || value > 1) {
    fail(`${label}_invalid`);
  }
  return value;
}

function requireEnum(value, allowed, label) {
  const text = requireString(value, label);
  if (!allowed.has(text)) fail(`${label}_invalid`);
  return text;
}

function requireArray(value, label) {
  if (!Array.isArray(value)) fail(`${label}_not_array`);
  return value;
}

function requireObject(value, label) {
  if (!isObject(value)) fail(`${label}_not_object`);
  return value;
}

function requireString(value, label) {
  if (typeof value !== "string") fail(`${label}_not_string`);
  return value;
}

function requireNonEmptyString(value, label) {
  const text = requireString(value, label).trim();
  if (!text) fail(`${label}_empty`);
  return text;
}

function requirePositiveInt(value, label) {
  if (!Number.isInteger(value) || value <= 0) fail(`${label}_invalid`);
  return value;
}

function requireNonNegativeInt(value, label) {
  if (!Number.isInteger(value) || value < 0) fail(`${label}_invalid`);
  return value;
}

function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function compareUtf16(left, right) {
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

function fail(code) {
  throw new Error(code);
}

function deepFreeze(value) {
  if (value == null || typeof value !== "object") return value;
  if (Object.isFrozen(value)) return value;
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

module.exports = {
  CONTRACT_VERSION,
  FIXTURE_CONTEXT_MODE,
  FORBIDDEN_AUTHORITY_FIELDS,
  INPUT_CONTRACT,
  MAPPER_COMPATIBILITY_VERSION,
  PERSISTENCE_EVIDENCE_VERSION,
  PERSISTENCE_SCHEMA_VERSION,
  PRODUCTION_CONTEXT_MODE,
  RESOLVER_COMPATIBILITY_VERSION,
  STAGE_ID,
  STAGE_VERSION,
  prepareQualifiedVisionPersistenceMapperInput,
};
