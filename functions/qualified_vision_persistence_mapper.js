"use strict";

/**
 * Node port of Dart QualifiedVisionPersistenceMapper.map.
 *
 * Pure / sync / deterministic. Accepts only
 * qualified_vision_persistence_mapper_input/v1 from
 * PrepareQualifiedVisionPersistenceMapperInput.
 *
 * Offline / fixture parity only. Production context without trusted
 * revision authority fails closed. Not imported by production entry points.
 */

const {
  FAMILY_WIRE,
  canonicalToFamily,
} = require("./vision_family_identity_resolver");

const PROVIDER_ID = "QualifiedVisionPersistenceMapper";
const PROVIDER_VERSION = "qualified-vision-persistence-mapper-v1";
const ORACLE_CONTRACT_VERSION = 1;
const INPUT_CONTRACT = "qualified_vision_persistence_mapper_input/v1";
const OUTPUT_CONTRACT = "WardrobeProfilePersistenceMappingResult/v1";
const FIXTURE_CONTEXT_MODE = "fixture_authoritative_context_v1";
const PRODUCTION_CONTEXT_MODE = "production";

const PERSISTENCE_SCHEMA_VERSION = 1;
const PERSISTENCE_EVIDENCE_VERSION = 1;
const RESOLVER_COMPATIBILITY_VERSION = 1;

const PROPERTY = Object.freeze({
  family: "identity.family",
  canonicalType: "identity.canonicalType",
  coverage: "visual.coverage",
  hasHood: "visual.observations.hasHood",
  frontClosure: "visual.observations.frontClosure",
  visibleBulk: "visual.observations.visibleBulk",
  surfaceAppearance: "visual.observations.surfaceAppearance",
  necklineShape: "visual.observations.necklineShape",
  visiblePocketStructure: "visual.observations.visiblePocketStructure",
  visibleStretchCue: "visual.observations.visibleStretchCue",
  sportyCues: "visual.observations.sportyCues",
  formalCues: "visual.observations.formalCues",
  footwearConstruction: "visual.observations.footwearConstruction",
  footwearFastening: "visual.observations.footwearFastening",
  soleProfile: "visual.observations.soleProfile",
  visibleTread: "visual.observations.visibleTread",
  footwearUpperHeight: "visual.observations.footwearUpperHeight",
  warmth: "capabilities.warmth",
  formality: "capabilities.formality",
  supportedLayerRoles: "capabilities.supportedLayerRoles",
  mobility: "capabilities.mobility",
  breathability: "capabilities.breathability",
  walkingComfort: "capabilities.walkingComfort",
  traction: "capabilities.traction",
});

const MACHINE_EVIDENCE_PROPERTIES = new Set([
  PROPERTY.family,
  PROPERTY.canonicalType,
  PROPERTY.coverage,
  PROPERTY.hasHood,
  PROPERTY.frontClosure,
  PROPERTY.visibleBulk,
  PROPERTY.surfaceAppearance,
  PROPERTY.necklineShape,
  PROPERTY.visiblePocketStructure,
  PROPERTY.visibleStretchCue,
  PROPERTY.sportyCues,
  PROPERTY.formalCues,
  PROPERTY.footwearConstruction,
  PROPERTY.footwearFastening,
  PROPERTY.soleProfile,
  PROPERTY.visibleTread,
  PROPERTY.footwearUpperHeight,
  PROPERTY.warmth,
  PROPERTY.formality,
  PROPERTY.supportedLayerRoles,
  PROPERTY.mobility,
  PROPERTY.breathability,
  PROPERTY.walkingComfort,
  PROPERTY.traction,
]);

const CAPABILITY_INFERENCE_PROPERTIES = new Set([
  PROPERTY.warmth,
  PROPERTY.formality,
  PROPERTY.supportedLayerRoles,
  PROPERTY.mobility,
  PROPERTY.breathability,
  PROPERTY.walkingComfort,
  PROPERTY.traction,
]);

const FAMILY_WIRE_VALUES = new Set(Object.values(FAMILY_WIRE));

const OBSERVATION_NAMES = Object.freeze({
  coverage: PROPERTY.coverage,
  hasHood: PROPERTY.hasHood,
  frontClosure: PROPERTY.frontClosure,
  visibleBulk: PROPERTY.visibleBulk,
  surfaceAppearance: PROPERTY.surfaceAppearance,
  necklineShape: PROPERTY.necklineShape,
  visiblePocketStructure: PROPERTY.visiblePocketStructure,
  visibleStretchCue: PROPERTY.visibleStretchCue,
  sportyCues: PROPERTY.sportyCues,
  formalCues: PROPERTY.formalCues,
  footwearConstruction: PROPERTY.footwearConstruction,
  footwearFastening: PROPERTY.footwearFastening,
  soleProfile: PROPERTY.soleProfile,
  visibleTread: PROPERTY.visibleTread,
  footwearUpperHeight: PROPERTY.footwearUpperHeight,
});

const CAPABILITY_SUPPORT_PROPERTIES = Object.freeze({
  "capability_inference:warmth.bulk_and_insulating_surface": [
    "visibleBulk", "surfaceAppearance",
  ],
  "capability_inference:warmth.bulk_and_full_coverage": [
    "visibleBulk", "coverage",
  ],
  "capability_inference:warmth.ankle_upper_and_bulk": [
    "footwearUpperHeight", "visibleBulk",
  ],
  "capability_inference:warmth.low_bulk_mesh": [
    "visibleBulk", "surfaceAppearance",
  ],
  "capability_inference:warmth.low_bulk_full_coverage": [
    "visibleBulk", "coverage",
  ],
  "capability_inference:breathability.mesh_and_low_bulk": [
    "surfaceAppearance", "visibleBulk",
  ],
  "capability_inference:breathability.mesh_and_open_construction": [
    "surfaceAppearance", "footwearConstruction",
  ],
  "capability_inference:mobility.stretch_and_sporty_construction": [
    "visibleStretchCue", "sportyCues",
  ],
  "capability_inference:mobility.visible_stretch": ["visibleStretchCue"],
  "capability_inference:formality.formal_over_sporty_cues": [
    "formalCues", "sportyCues",
  ],
  "capability_inference:formality.strong_formal_cues": ["formalCues"],
  "capability_inference:formality.strong_sporty_cues": [
    "sportyCues", "formalCues",
  ],
  "capability_inference:supported_layer_roles.hooded_zip_layer": [
    "hasHood", "frontClosure", "visibleBulk",
  ],
  "capability_inference:supported_layer_roles.knit_pullover": [
    "surfaceAppearance", "frontClosure", "visibleBulk",
  ],
  "capability_inference:walking_comfort.sporty_low_cut_supported_sole": [
    "footwearConstruction", "footwearUpperHeight", "soleProfile", "sportyCues",
  ],
  "capability_inference:traction.pronounced_visible_tread": ["visibleTread"],
  "capability_inference:traction.low_visible_tread": ["visibleTread"],
});

const ENUM_VALUES = Object.freeze({
  [PROPERTY.coverage]: new Set(["minimal", "partial", "full"]),
  [PROPERTY.frontClosure]: new Set([
    "none", "partial_zip", "full_zip", "buttons", "snaps", "other",
  ]),
  [PROPERTY.visibleBulk]: new Set(["low", "medium", "high"]),
  [PROPERTY.surfaceAppearance]: new Set([
    "knit", "woven", "fleece_like", "quilted", "smooth", "textured", "mesh",
    "leather_like",
  ]),
  [PROPERTY.necklineShape]: new Set([
    "crew", "v_neck", "scoop", "high_neck", "collared", "other",
  ]),
  [PROPERTY.visiblePocketStructure]: new Set([
    "none", "standard", "cargo", "patch", "other",
  ]),
  [PROPERTY.sportyCues]: new Set(["low", "medium", "high"]),
  [PROPERTY.formalCues]: new Set(["low", "medium", "high"]),
  [PROPERTY.footwearConstruction]: new Set([
    "open", "partially_open", "closed",
  ]),
  [PROPERTY.footwearFastening]: new Set([
    "laces", "zipper", "elastic_side_panels", "slip_on", "straps", "buckles",
    "other",
  ]),
  [PROPERTY.soleProfile]: new Set(["thin", "standard", "chunky"]),
  [PROPERTY.visibleTread]: new Set(["low", "moderate", "pronounced"]),
  [PROPERTY.footwearUpperHeight]: new Set([
    "low_cut", "ankle", "high_shaft",
  ]),
  [PROPERTY.mobility]: new Set([
    "unknown", "very_low", "low", "medium", "high", "very_high",
  ]),
  [PROPERTY.breathability]: new Set([
    "unknown", "very_low", "low", "medium", "high", "very_high",
  ]),
  [PROPERTY.walkingComfort]: new Set([
    "unknown", "very_low", "low", "medium", "high", "very_high",
  ]),
  [PROPERTY.traction]: new Set([
    "unknown", "very_low", "low", "medium", "high", "very_high",
  ]),
});

const VALUE_STATES = new Set([
  "known", "unknown", "not_visible", "not_applicable",
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
  "unknown", "observed", "inferred", "defaulted",
]);
const ANALYSIS_KINDS = new Set(["initial_analysis", "reanalysis"]);

/**
 * @param {object} raw prepare-stage output (+ optional contextMode)
 * @returns {Readonly<object>} WardrobeProfilePersistenceMappingResult wire map
 */
function mapQualifiedVisionPersistence(raw) {
  const input = decodeMapperInput(raw);
  const analysis = input.analysisProjection;
  const context = input.mappingContext;

  const contextFailure = validateContext(context, analysis);
  if (contextFailure != null) {
    return resultIncompatible(contextFailure);
  }
  if (!analysis.inputAssessmentValid) {
    return resultInvalid("vision_input_not_valid");
  }

  const observations = [];
  const observationByProperty = new Map();
  for (const runtime of analysis.observationEvidence) {
    if (!runtime.active ||
        runtime.source !== "visual_observation" ||
        !MACHINE_EVIDENCE_PROPERTIES.has(runtime.property) ||
        runtime.property === PROPERTY.family ||
        runtime.property === PROPERTY.canonicalType ||
        runtime.property.startsWith("capabilities.")) {
      continue;
    }
    const persisted = toObservation(runtime, context);
    const existing = observationByProperty.get(persisted.property);
    if (existing != null && !sameEvidence(existing, persisted)) {
      return resultFailure(`conflicting_observation:${persisted.property}`);
    }
    observationByProperty.set(persisted.property, existing ?? persisted);
  }
  observations.push(...observationByProperty.values());

  const omitted = [];
  let family = toFamily(analysis, context, observationByProperty);
  let canonical = toCanonical(analysis, context, observationByProperty);

  const identityBlockedByMultiPhoto =
    !analysis.multiPhotoAssessment.permitsIdentityPromotion;
  if (identityBlockedByMultiPhoto) {
    family = null;
    canonical = null;
    if (analysis.multiPhotoAssessment.physicalIdentity !==
        "sameItemSupported") {
      omitted.push("identity_omitted:multi_photo_physical_conflict");
    } else {
      omitted.push("identity_omitted:multi_photo_semantic_conflict");
    }
  }
  if (family != null && canonical != null) {
    const familyEnum = canonicalToFamily.get(canonical.value);
    const familyWire = familyEnum == null ? null : FAMILY_WIRE[familyEnum];
    if (familyWire !== family.value) {
      family = null;
      canonical = null;
      omitted.push("identity_omitted:cross_family_conflict");
    }
  }

  const capabilities = [];
  for (const runtime of analysis.capabilityEvidence) {
    const persisted = toCapability(runtime, context, observationByProperty);
    if (persisted == null) {
      omitted.push(`capability_omitted:${runtime.property}`);
    } else {
      capabilities.push(persisted);
    }
  }

  const evidence = [
    ...(family == null ? [] : [family]),
    ...(canonical == null ? [] : [canonical]),
    ...observations,
    ...capabilities,
  ].sort(compareEvidence);
  const duplicateFailure = findDuplicateFailure(evidence);
  if (duplicateFailure != null) {
    return resultFailure(duplicateFailure);
  }
  const byId = new Map();
  for (const item of evidence) {
    byId.set(item.id, item);
  }
  const deduplicated = [...byId.values()].sort(compareEvidence);
  if (deduplicated.length === 0) {
    return resultNoPersistable("no_qualified_evidence");
  }

  const envelope = {
    metadata: {
      schemaVersion: PERSISTENCE_SCHEMA_VERSION,
      evidenceSchemaVersion: PERSISTENCE_EVIDENCE_VERSION,
      resolverCompatibilityVersion: RESOLVER_COMPATIBILITY_VERSION,
      generationId: context.generationId,
      revision: context.revision,
      createdAt: context.createdAt,
      updatedAt: context.updatedAt,
      status: "ready",
    },
    source: {
      imageRevision: context.imageRevision,
      wardrobeItemRevision: context.wardrobeItemRevision,
      ...(context.storagePath != null ? {storagePath: context.storagePath} : {}),
      ...(context.imageHash != null ? {imageHash: context.imageHash} : {}),
      ...(context.uploadGeneration != null ?
        {uploadGeneration: context.uploadGeneration} : {}),
    },
    analysis: {
      analysisId: context.analysisId,
      kind: context.analysisKind,
      completedAt: context.completedAt,
      modelIdentifier: context.modelIdentifier,
      pipelineVersion: context.pipelineVersion,
      promptVersion: context.promptVersion,
      visionSchemaVersion: context.visionSchemaVersion,
      qualificationVersion: context.qualificationVersion,
    },
    machineEvidence: deduplicated.map(encodeMachineEvidence),
    userCorrections: {},
  };

  try {
    validateEnvelope(envelope);
  } catch (error) {
    return resultFailure(`codec_validation:${error.message}`);
  }

  return deepFreeze({
    status: "mapped",
    omittedEvidenceReasonCodes: Object.freeze([...omitted].sort()),
    envelope: deepFreeze(envelope),
  });
}

function decodeMapperInput(raw) {
  if (!isObject(raw)) fail("mapper_input_not_object");
  const forbidden = [
    "machineEvidence", "resolvedProfile", "resolvedCache",
    "repositorySnapshot", "casExpectedRevision", "firestoreTimestamp",
    "userCorrections", "writeDecision", "envelope",
  ];
  for (const field of forbidden) {
    if (Object.prototype.hasOwnProperty.call(raw, field)) {
      fail(`forbidden_authority_field:${field}`);
    }
  }
  const contextMode = raw.contextMode ?? inferContextMode(raw.mappingContext);
  if (contextMode === PRODUCTION_CONTEXT_MODE &&
      raw.trustedRevisionAuthority !== true) {
    fail("trusted_revision_context_unavailable");
  }
  if (contextMode !== FIXTURE_CONTEXT_MODE &&
      contextMode !== PRODUCTION_CONTEXT_MODE) {
    fail("context_mode_invalid");
  }
  const analysisProjection = decodeAnalysisProjection(raw.analysisProjection);
  const mappingContext = decodeMappingContext(raw.mappingContext);
  return {contextMode, analysisProjection, mappingContext};
}

function inferContextMode(context) {
  if (!isObject(context)) return FIXTURE_CONTEXT_MODE;
  if (typeof context.generationId === "string" &&
      context.generationId.startsWith("fixture-generation:")) {
    return FIXTURE_CONTEXT_MODE;
  }
  return PRODUCTION_CONTEXT_MODE;
}

function decodeAnalysisProjection(raw) {
  const value = requireObject(raw, "analysisProjection");
  const analysisId = requireNonEmpty(value.analysisId, "analysisId");
  const modelVersion = requireNonEmpty(value.modelVersion, "modelVersion");
  const schemaVersion = requirePositiveInt(value.schemaVersion, "schemaVersion");
  const inputAssessment = requireString(value.inputAssessment, "inputAssessment");
  if (typeof value.inputAssessmentValid !== "boolean") {
    fail("inputAssessmentValid_invalid");
  }
  if (value.inputAssessmentValid !== (inputAssessment === "valid_single_item")) {
    fail("inputAssessmentValid_mismatch");
  }
  return {
    analysisId,
    modelVersion,
    schemaVersion,
    inputAssessment,
    inputAssessmentValid: value.inputAssessmentValid,
    observationEvidence: requireArray(
      value.observationEvidence, "observationEvidence")
      .map((item) => decodeRuntimeEvidence(item, "observationEvidence")),
    qualifiedIdentityEvidence: requireArray(
      value.qualifiedIdentityEvidence, "qualifiedIdentityEvidence")
      .map((item) => decodeRuntimeEvidence(item, "qualifiedIdentityEvidence")),
    capabilityEvidence: requireArray(
      value.capabilityEvidence, "capabilityEvidence")
      .map((item) => decodeRuntimeEvidence(item, "capabilityEvidence")),
    identityQualification: requireObject(
      value.identityQualification, "identityQualification"),
    familyIdentity: requireObject(value.familyIdentity, "familyIdentity"),
    multiPhotoAssessment: requireObject(
      value.multiPhotoAssessment, "multiPhotoAssessment"),
  };
}

function decodeRuntimeEvidence(raw, label) {
  if (!isObject(raw)) fail(`${label}_item_invalid`);
  const valueState = raw.valueState == null ? "known" :
    requireEnum(raw.valueState, VALUE_STATES, `${label}.valueState`);
  return {
    id: requireNonEmpty(raw.id, `${label}.id`),
    property: requireNonEmpty(raw.property, `${label}.property`),
    value: Object.prototype.hasOwnProperty.call(raw, "value") ? raw.value : null,
    valueState,
    source: requireEnum(raw.source, EVIDENCE_SOURCES, `${label}.source`),
    nature: requireEnum(raw.nature, EVIDENCE_NATURES, `${label}.nature`),
    confidence: requireConfidence(raw.confidence, `${label}.confidence`),
    method: requireNonEmpty(raw.method, `${label}.method`),
    createdAt: requireUtc(raw.createdAt, `${label}.createdAt`),
    modelVersion: raw.modelVersion == null ? null :
      requireNonEmpty(raw.modelVersion, `${label}.modelVersion`),
    sourceReference: raw.sourceReference == null ? null :
      requireNonEmpty(raw.sourceReference, `${label}.sourceReference`),
    active: raw.active !== false,
    verified: raw.verified === true,
  };
}

function decodeMappingContext(raw) {
  const value = requireObject(raw, "mappingContext");
  const createdAt = requireUtc(value.createdAt, "createdAt");
  const updatedAt = requireUtc(value.updatedAt, "updatedAt");
  if (Date.parse(updatedAt) < Date.parse(createdAt)) {
    fail("provenance_value_invalid");
  }
  return {
    generationId: requireNonEmpty(value.generationId, "generationId"),
    revision: requireNonNegativeInt(value.revision, "revision"),
    createdAt,
    updatedAt,
    imageRevision: requireNonNegativeInt(value.imageRevision, "imageRevision"),
    wardrobeItemRevision: requireNonNegativeInt(
      value.wardrobeItemRevision, "wardrobeItemRevision"),
    storagePath: value.storagePath == null ? null :
      requireNonEmpty(value.storagePath, "storagePath"),
    imageHash: value.imageHash == null ? null :
      requireNonEmpty(value.imageHash, "imageHash"),
    uploadGeneration: value.uploadGeneration == null ? null :
      requireNonEmpty(value.uploadGeneration, "uploadGeneration"),
    analysisId: requireNonEmpty(value.analysisId, "analysisId"),
    analysisKind: requireEnum(value.analysisKind, ANALYSIS_KINDS, "analysisKind"),
    completedAt: requireUtc(value.completedAt, "completedAt"),
    modelIdentifier: requireNonEmpty(value.modelIdentifier, "modelIdentifier"),
    pipelineVersion: requireNonEmpty(value.pipelineVersion, "pipelineVersion"),
    promptVersion: requireNonEmpty(value.promptVersion, "promptVersion"),
    visionSchemaVersion: requirePositiveInt(
      value.visionSchemaVersion, "visionSchemaVersion"),
    qualificationVersion: requireNonEmpty(
      value.qualificationVersion, "qualificationVersion"),
  };
}

function validateContext(context, analysis) {
  if (context.generationId.trim() === "" ||
      context.analysisId.trim() === "" ||
      context.modelIdentifier.trim() === "" ||
      context.pipelineVersion.trim() === "" ||
      context.promptVersion.trim() === "" ||
      context.qualificationVersion.trim() === "") {
    return "required_provenance_missing";
  }
  if (context.revision < 0 ||
      context.imageRevision < 0 ||
      context.wardrobeItemRevision < 0 ||
      context.visionSchemaVersion <= 0 ||
      Date.parse(context.updatedAt) < Date.parse(context.createdAt)) {
    return "provenance_value_invalid";
  }
  if (context.analysisId !== analysis.analysisId) return "analysis_id_mismatch";
  if (context.visionSchemaVersion !== analysis.schemaVersion) {
    return "vision_schema_version_mismatch";
  }
  if (context.modelIdentifier !== analysis.modelVersion) {
    return "model_identifier_mismatch";
  }
  return null;
}

function toObservation(runtime, context) {
  return {
    id: makeId("observation", context.analysisId, runtime.property),
    property: runtime.property,
    value: runtime.value,
    valueState: runtime.valueState,
    source: "visual_observation",
    nature: "observed",
    confidence: runtime.confidence,
    method: "vision_observation",
    createdAt: context.completedAt,
    modelVersion: runtime.modelVersion ?? context.modelIdentifier,
    identityQualification: null,
    supportingEvidenceIds: [],
  };
}

function toFamily(analysis, context, observationByProperty) {
  const report = analysis.familyIdentity;
  const qualification = report.state === "confirmed" ? "confirmed" :
    report.state === "supported" ? "supported" : null;
  const family = report.resolvedFamily;
  if (qualification == null || family == null) return null;
  const candidate = (report.candidates || []).find(
    (item) => item.family === family);
  if (candidate == null) return null;
  const supports = supportIds(
    (candidate.evidence || []).map((item) => String(item).split(":").pop()),
    observationByProperty,
  );
  if (supports.length === 0) return null;
  return {
    id: makeId("family", context.analysisId, family),
    property: PROPERTY.family,
    value: family,
    valueState: "known",
    source: "ai_inference",
    nature: "inferred",
    confidence: report.confidence,
    method: "vision_family_identity",
    createdAt: context.completedAt,
    modelVersion: context.modelIdentifier,
    identityQualification: qualification,
    supportingEvidenceIds: supports,
  };
}

function toCanonical(analysis, context, observationByProperty) {
  const report = analysis.identityQualification;
  const selected = report.selectedCanonicalType;
  const qualification = report.state === "confirmed" ? "confirmed" :
    report.state === "supported" ? "supported" : null;
  if (selected == null || qualification == null) return null;
  const runtime = analysis.qualifiedIdentityEvidence.find((item) =>
    item.active &&
    item.property === PROPERTY.canonicalType &&
    item.value === selected);
  const candidate = (report.candidates || []).find(
    (item) => item.canonicalType === selected);
  if (runtime == null || candidate == null) return null;
  const supports = supportIds([
    ...(candidate.usedDefiningSupports || []),
    ...(candidate.usedSupportingObservations || []),
  ], observationByProperty);
  if (supports.length === 0) return null;
  return {
    id: makeId("canonical", context.analysisId, selected),
    property: PROPERTY.canonicalType,
    value: selected,
    valueState: "known",
    source: "ai_inference",
    nature: "inferred",
    confidence: runtime.confidence,
    method: "vision_v2_identity_candidate",
    createdAt: context.completedAt,
    modelVersion: runtime.modelVersion ?? context.modelIdentifier,
    identityQualification: qualification,
    supportingEvidenceIds: supports,
  };
}

function toCapability(runtime, context, observationByProperty) {
  if (!runtime.active ||
      runtime.source !== "ai_inference" ||
      runtime.nature !== "inferred" ||
      !runtime.method.startsWith("capability_inference:") ||
      !Object.prototype.hasOwnProperty.call(
        CAPABILITY_SUPPORT_PROPERTIES, runtime.method)) {
    return null;
  }
  const required = CAPABILITY_SUPPORT_PROPERTIES[runtime.method];
  const supports = supportIds(required, observationByProperty);
  if (supports.length !== required.length) return null;
  return {
    id: makeId("capability", context.analysisId, runtime.property),
    property: runtime.property,
    value: runtime.value,
    valueState: runtime.valueState,
    source: "ai_inference",
    nature: "inferred",
    confidence: runtime.confidence,
    method: runtime.method,
    createdAt: context.completedAt,
    modelVersion: runtime.modelVersion ?? "capability-inference-v1",
    identityQualification: null,
    supportingEvidenceIds: supports,
  };
}

function supportIds(names, observationByProperty) {
  const ids = new Set();
  for (const name of names) {
    const property = observationProperty(name);
    const evidence = property == null ?
      null : observationByProperty.get(property);
    if (evidence != null) ids.add(evidence.id);
  }
  return [...ids].sort();
}

function observationProperty(value) {
  if (value === PROPERTY.coverage ||
      String(value).startsWith("visual.observations.")) {
    return value;
  }
  return OBSERVATION_NAMES[value] ?? null;
}

function findDuplicateFailure(evidence) {
  const byId = new Map();
  for (const item of evidence) {
    const existing = byId.get(item.id);
    if (existing != null && !sameEvidence(existing, item)) {
      return `conflicting_duplicate_id:${item.id}`;
    }
    byId.set(item.id, item);
  }
  return null;
}

function sameEvidence(left, right) {
  return left.id === right.id &&
    left.property === right.property &&
    valueKey(left.value) === valueKey(right.value) &&
    left.valueState === right.valueState &&
    left.source === right.source &&
    left.nature === right.nature &&
    left.confidence === right.confidence &&
    left.method === right.method &&
    left.modelVersion === right.modelVersion &&
    left.identityQualification === right.identityQualification;
}

function compareEvidence(left, right) {
  const rank = evidenceRank(left) - evidenceRank(right);
  if (rank !== 0) return rank;
  const property = left.property.localeCompare(right.property);
  if (property !== 0) return property;
  return left.id.localeCompare(right.id);
}

function evidenceRank(item) {
  if (item.property === PROPERTY.family) return 0;
  if (item.property === PROPERTY.canonicalType) return 1;
  if (item.property === PROPERTY.coverage ||
      item.property.startsWith("visual.observations.")) {
    return 2;
  }
  return 3;
}

function makeId(kind, analysisId, discriminator) {
  return `${kind}:${encodeComponent(analysisId)}:${encodeComponent(discriminator)}`;
}

/** Dart Uri.encodeComponent compatible for our fixtures. */
function encodeComponent(value) {
  return encodeURIComponent(String(value))
    .replace(/[!'()*]/g, (char) =>
      `%${char.charCodeAt(0).toString(16).toUpperCase()}`);
}

function valueKey(value) {
  if (Array.isArray(value)) return value.join("|");
  return `${value}`;
}

function encodeMachineEvidence(evidence) {
  const encoded = {
    id: evidence.id,
    property: evidence.property,
    value: evidence.value,
    valueState: evidence.valueState,
    source: evidence.source,
    nature: evidence.nature,
    confidence: evidence.confidence,
    method: evidence.method,
    createdAt: evidence.createdAt,
    modelVersion: evidence.modelVersion,
  };
  if (evidence.identityQualification != null) {
    encoded.identityQualification = evidence.identityQualification;
  }
  if (evidence.supportingEvidenceIds.length > 0) {
    encoded.supportingEvidenceIds = evidence.supportingEvidenceIds;
  }
  return encoded;
}

function validateEnvelope(envelope) {
  const metadata = envelope.metadata;
  if (metadata.schemaVersion !== PERSISTENCE_SCHEMA_VERSION ||
      metadata.evidenceSchemaVersion !== PERSISTENCE_EVIDENCE_VERSION) {
    throw new Error("unsupported_persistence_version");
  }
  if (metadata.resolverCompatibilityVersion <= 0 ||
      metadata.generationId.trim() === "" ||
      metadata.revision < 0 ||
      Date.parse(metadata.updatedAt) < Date.parse(metadata.createdAt)) {
    throw new Error("invalid_metadata");
  }
  if (envelope.source.imageRevision < 0 ||
      envelope.source.wardrobeItemRevision < 0) {
    throw new Error("invalid_source_revision");
  }
  const analysis = envelope.analysis;
  if (analysis.analysisId.trim() === "" ||
      analysis.modelIdentifier.trim() === "" ||
      analysis.pipelineVersion.trim() === "" ||
      analysis.promptVersion.trim() === "" ||
      analysis.qualificationVersion.trim() === "" ||
      analysis.visionSchemaVersion <= 0) {
    throw new Error("invalid_analysis");
  }
  const ids = new Set();
  for (const evidence of envelope.machineEvidence) {
    validateMachineEvidence(evidence);
    if (ids.has(evidence.id)) {
      throw new Error("duplicate_machine_evidence_id");
    }
    ids.add(evidence.id);
  }
}

function validateMachineEvidence(evidence) {
  if (evidence.id.trim() === "" ||
      evidence.method.trim() === "" ||
      evidence.modelVersion.trim() === "" ||
      !MACHINE_EVIDENCE_PROPERTIES.has(evidence.property)) {
    throw new Error("machine_evidence_not_allow_listed");
  }
  if (evidence.source !== "visual_observation" &&
      evidence.source !== "ai_inference") {
    throw new Error("machine_evidence_source_forbidden");
  }
  if (evidence.source === "visual_observation" &&
      evidence.nature !== "observed") {
    throw new Error("visual_evidence_nature_invalid");
  }
  if (evidence.source === "ai_inference" && evidence.nature !== "inferred") {
    throw new Error("ai_evidence_nature_invalid");
  }
  const isIdentity = evidence.property === PROPERTY.family ||
    evidence.property === PROPERTY.canonicalType;
  if (isIdentity) {
    if (evidence.source !== "ai_inference" ||
        evidence.identityQualification == null ||
        !evidence.method.startsWith("vision_") ||
        !Array.isArray(evidence.supportingEvidenceIds) ||
        evidence.supportingEvidenceIds.length === 0) {
      throw new Error("qualified_identity_evidence_required");
    }
  } else if (evidence.identityQualification != null) {
    throw new Error("identity_qualification_for_non_identity_evidence");
  }
  if (CAPABILITY_INFERENCE_PROPERTIES.has(evidence.property) &&
      (evidence.source !== "ai_inference" ||
        evidence.nature !== "inferred" ||
        !evidence.method.startsWith("capability_inference:") ||
        !Array.isArray(evidence.supportingEvidenceIds) ||
        evidence.supportingEvidenceIds.length === 0)) {
    throw new Error("item_specific_capability_provenance_required");
  }
  if (typeof evidence.confidence !== "number" ||
      !Number.isFinite(evidence.confidence) ||
      evidence.confidence < 0 || evidence.confidence > 1) {
    throw new Error("machine_evidence_confidence_invalid");
  }
  if (evidence.valueState === "known") {
    if (evidence.value == null) {
      throw new Error("known_machine_evidence_value_required");
    }
    validatePropertyValue(evidence.property, evidence.value);
  } else if (evidence.value != null) {
    throw new Error("non_value_machine_evidence_must_be_null");
  }
}

function validatePropertyValue(property, value) {
  if (property === PROPERTY.canonicalType) {
    if (typeof value !== "string" || !canonicalToFamily.has(value)) {
      throw new Error(`unknown_canonical_key:${value}`);
    }
    return;
  }
  if (property === PROPERTY.family) {
    if (typeof value !== "string" || !FAMILY_WIRE_VALUES.has(value)) {
      throw new Error(`unknown_family_key:${value}`);
    }
    return;
  }
  if (property === PROPERTY.hasHood ||
      property === PROPERTY.visibleStretchCue) {
    if (typeof value !== "boolean") throw new Error(`invalid_bool:${property}`);
    return;
  }
  if (property === PROPERTY.warmth || property === PROPERTY.formality) {
    if (!Number.isInteger(value) || value < 0 || value > 10) {
      throw new Error(`invalid_scale:${property}`);
    }
    return;
  }
  const allowed = ENUM_VALUES[property];
  if (allowed != null && (typeof value !== "string" || !allowed.has(value))) {
    throw new Error(`unknown_enum_value:${property}:${value}`);
  }
}

function resultMapped(envelope, omitted) {
  return deepFreeze({
    status: "mapped",
    omittedEvidenceReasonCodes: Object.freeze([...omitted]),
    envelope: deepFreeze(envelope),
  });
}

function resultInvalid(reasonCode) {
  return deepFreeze({
    status: "invalidInput",
    reasonCode,
    omittedEvidenceReasonCodes: Object.freeze([]),
  });
}

function resultIncompatible(reasonCode) {
  return deepFreeze({
    status: "incompatibleInput",
    reasonCode,
    omittedEvidenceReasonCodes: Object.freeze([]),
  });
}

function resultFailure(reasonCode) {
  return deepFreeze({
    status: "mappingFailure",
    reasonCode,
    omittedEvidenceReasonCodes: Object.freeze([]),
  });
}

function resultNoPersistable(reasonCode) {
  return deepFreeze({
    status: "noPersistableEvidence",
    reasonCode,
    omittedEvidenceReasonCodes: Object.freeze([]),
  });
}

function requireObject(value, label) {
  if (!isObject(value)) fail(`${label}_not_object`);
  return value;
}

function requireArray(value, label) {
  if (!Array.isArray(value)) fail(`${label}_not_array`);
  return value;
}

function requireString(value, label) {
  if (typeof value !== "string") fail(`${label}_not_string`);
  return value;
}

function requireNonEmpty(value, label) {
  const text = requireString(value, label).trim();
  if (!text) fail(`${label}_empty`);
  return text;
}

function requireEnum(value, allowed, label) {
  const text = requireString(value, label);
  if (!allowed.has(text)) fail(`${label}_invalid`);
  return text;
}

function requireConfidence(value, label) {
  if (typeof value !== "number" || Number.isNaN(value) ||
      value < 0 || value > 1) {
    fail(`${label}_invalid`);
  }
  return value;
}

function requirePositiveInt(value, label) {
  if (!Number.isInteger(value) || value <= 0) fail(`${label}_invalid`);
  return value;
}

function requireNonNegativeInt(value, label) {
  if (!Number.isInteger(value) || value < 0) fail(`${label}_invalid`);
  return value;
}

function requireUtc(value, label) {
  const text = requireNonEmpty(value, label);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(text)) {
    fail(`${label}_non_utc_timestamp`);
  }
  if (Number.isNaN(Date.parse(text))) fail(`${label}_invalid_timestamp`);
  return text;
}

function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
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
  CAPABILITY_SUPPORT_PROPERTIES,
  FIXTURE_CONTEXT_MODE,
  INPUT_CONTRACT,
  MACHINE_EVIDENCE_PROPERTIES,
  ORACLE_CONTRACT_VERSION,
  OUTPUT_CONTRACT,
  PERSISTENCE_EVIDENCE_VERSION,
  PERSISTENCE_SCHEMA_VERSION,
  PRODUCTION_CONTEXT_MODE,
  PROPERTY,
  PROVIDER_ID,
  PROVIDER_VERSION,
  RESOLVER_COMPATIBILITY_VERSION,
  mapQualifiedVisionPersistence,
  makeId,
};
