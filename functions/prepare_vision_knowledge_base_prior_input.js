"use strict";

/**
 * Trusted Knowledge-Base Prior input preparation (orchestration stage).
 *
 * Pure / deterministic. Not a production provider and not imported by
 * deployed Vision entry points. Builds wardrobe_kb_prior_input/v1 matching
 * Dart WardrobeKnowledgeBasePriorProvider.provide arguments at the call site
 * in VisionV2ShadowOrchestrator.analyze:
 *
 *   document: {}
 *   existingEvidence: [...observationEvidence, ...qualifiedIdentity, ...capabilityEvidence]
 *
 * Family identity is intentionally excluded — Dart does not pass it here.
 */

const STAGE_ID = "PrepareVisionKnowledgeBasePriorInput";
const STAGE_VERSION = "knowledge-base-prior-input-v1";
const CONTRACT_VERSION = 1;
const INPUT_CONTRACT = "wardrobe_kb_prior_input/v1";

const FORBIDDEN_AUTHORITY_FIELDS = Object.freeze([
  "existingEvidence",
  "providerInput",
  "preparedProviderInput",
  "resolvedProfile",
  "knowledgeBaseEvidence",
  "kbEvidence",
  "kbPriors",
  "fallbackEvidence",
  "selectedCanonicalType",
  "canonicalType",
]);

/** Document fields actually read by WardrobeKnowledgeBasePriorProvider. */
const DOCUMENT_ALLOW_LIST = Object.freeze([
  "mainGroupKey",
  "mainGroup",
  "categoryKey",
  "category",
  "subCategoryKey",
  "subCategory",
  "primary_type",
  "primaryType",
  "secondary_type",
  "secondaryType",
]);

const EVIDENCE_SOURCES = new Set([
  "visual_observation",
  "ai_inference",
  "product_metadata",
  "user_correction",
  "legacy_fallback",
  "knowledge_base_prior",
  "label_ocr",
]);

const EVIDENCE_NATURES = new Set([
  "observed",
  "inferred",
  "defaulted",
  "asserted",
]);

const VALUE_STATES = new Set([
  "known",
  "unknown",
  "not_visible",
  "not_applicable",
]);

/**
 * @param {object} raw
 * @returns {Readonly<{document: object, existingEvidence: object[]}>}
 */
function prepareVisionKnowledgeBasePriorInput(raw) {
  const input = decodePrepareInput(raw);
  const observationEvidence = projectObservationEvidence(
    input.observationEvidence, input.observationProvenance)
    .sort((left, right) => compareUtf16(left.id, right.id));
  const qualifiedIdentityEvidence = input.qualifiedIdentityEvidence.map(
    (item) => projectIdentityEvidence(item));
  const capabilityEvidence = input.capabilityEvidence.map(
    (item) => projectCapabilityEvidence(item));
  assertNoDuplicateIds([
    ...observationEvidence,
    ...qualifiedIdentityEvidence,
    ...capabilityEvidence,
  ]);
  assertNoKnowledgeBasePriorInput([
    ...observationEvidence,
    ...qualifiedIdentityEvidence,
    ...capabilityEvidence,
  ]);
  const document = projectDocument(input);
  return deepFreeze({
    document,
    existingEvidence: [
      ...observationEvidence,
      ...qualifiedIdentityEvidence,
      ...capabilityEvidence,
    ],
  });
}

function decodePrepareInput(raw) {
  if (!isObject(raw)) fail("kb_prepare_input_invalid");
  for (const field of FORBIDDEN_AUTHORITY_FIELDS) {
    if (Object.hasOwn(raw, field)) {
      fail(`forged_authority_field:${field}`);
    }
  }
  if (Object.hasOwn(raw, "familyIdentity") ||
      Object.hasOwn(raw, "familyReport") ||
      Object.hasOwn(raw, "familyEvidence")) {
    fail("family_evidence_not_part_of_kb_input");
  }
  if (raw.contractVersion !== undefined &&
      raw.contractVersion !== CONTRACT_VERSION) {
    fail("kb_prepare_contract_version_unsupported");
  }
  if (raw.stageVersion !== undefined && raw.stageVersion !== STAGE_VERSION) {
    fail("kb_prepare_stage_version_unsupported");
  }
  if (!Array.isArray(raw.observationEvidence)) {
    fail("observation_evidence_required");
  }
  if (!Array.isArray(raw.qualifiedIdentityEvidence)) {
    fail("qualified_identity_evidence_required");
  }
  if (!Array.isArray(raw.capabilityEvidence)) {
    fail("capability_evidence_required");
  }
  const documentMode = raw.documentMode === undefined ?
    "vision_empty" : requireText(raw.documentMode, "document_mode_invalid");
  if (documentMode !== "vision_empty" &&
      documentMode !== "allow_listed_projection") {
    fail("document_mode_unsupported");
  }
  const observationProvenance = decodeObservationProvenance(
    raw.observationProvenance, raw.observationEvidence);
  return {
    observationEvidence: raw.observationEvidence.map((item, index) =>
      decodeIncomingEvidence(item, index, "observation")),
    qualifiedIdentityEvidence: raw.qualifiedIdentityEvidence.map(
      (item, index) => decodeIncomingEvidence(item, index, "identity")),
    capabilityEvidence: raw.capabilityEvidence.map((item, index) =>
      decodeIncomingEvidence(item, index, "capability")),
    observationProvenance,
    documentMode,
    wardrobeDocumentProjection: raw.wardrobeDocumentProjection,
  };
}

function decodeObservationProvenance(value, observationEvidence) {
  const needsEnrichment = observationEvidence.some((item) =>
    !isObject(item) ||
    !Object.hasOwn(item, "createdAt") ||
    !Object.hasOwn(item, "modelVersion") ||
    !Object.hasOwn(item, "sourceReference") ||
    !Object.hasOwn(item, "active") ||
    !Object.hasOwn(item, "verified"));
  if (!needsEnrichment) {
    if (value === undefined || value === null) return null;
  }
  if (!isObject(value)) fail("observation_provenance_required");
  return {
    observedAt: requireTimestamp(value.observedAt, "observed_at_invalid"),
    modelVersion: requireText(value.modelVersion, "model_version_required"),
    sourceReference: requireText(
      value.sourceReference, "source_reference_required"),
  };
}

function decodeIncomingEvidence(value, index, kind) {
  if (!isObject(value)) fail(`evidence_invalid:${kind}:${index}`);
  const id = requireText(value.id, `evidence_id_required:${kind}:${index}`);
  const property = requireText(
    value.property, `evidence_property_required:${kind}:${index}`);
  if (!EVIDENCE_SOURCES.has(value.source)) {
    fail(`evidence_source_invalid:${kind}:${index}`);
  }
  if (!EVIDENCE_NATURES.has(value.nature)) {
    fail(`evidence_nature_invalid:${kind}:${index}`);
  }
  requireText(value.method, `evidence_method_required:${kind}:${index}`);
  requireConfidence(value.confidence, `evidence_confidence_invalid:${kind}:${index}`);
  if (!Object.hasOwn(value, "value")) {
    fail(`evidence_value_omitted:${kind}:${index}`);
  }
  const valueState = Object.hasOwn(value, "valueState") ?
    value.valueState : "known";
  if (!VALUE_STATES.has(valueState)) {
    fail(`evidence_value_state_invalid:${kind}:${index}`);
  }
  if (valueState === "known") {
    // known may still carry null only when explicitly represented; Dart allows
    // non-null for known. Non-known must be null.
  } else if (value.value !== null) {
    fail(`non_value_evidence_value_invalid:${kind}:${index}`);
  }
  if (kind === "observation" && value.source !== "visual_observation") {
    fail(`observation_source_invalid:${index}`);
  }
  if (kind === "observation" && value.nature !== "observed") {
    fail(`observation_nature_invalid:${index}`);
  }
  if (kind === "capability" && !property.startsWith("capabilities.")) {
    fail(`capability_property_invalid:${index}`);
  }
  if (kind === "identity" && property !== "identity.canonicalType") {
    fail(`identity_property_invalid:${index}`);
  }
  return structuredClone(value);
}

function projectObservationEvidence(items, provenance) {
  return items.map((item, index) => {
    const createdAt = Object.hasOwn(item, "createdAt") ?
      requireTimestamp(item.createdAt, `observation_created_at_invalid:${index}`) :
      provenance.observedAt;
    const modelVersion = Object.hasOwn(item, "modelVersion") ?
      requireText(item.modelVersion, `observation_model_version_invalid:${index}`) :
      provenance.modelVersion;
    const sourceReference = Object.hasOwn(item, "sourceReference") ?
      requireText(item.sourceReference,
        `observation_source_reference_invalid:${index}`) :
      provenance.sourceReference;
    return projectProfileEvidenceWire({
      ...item,
      createdAt,
      modelVersion,
      sourceReference,
      active: item.active !== false,
      verified: item.verified === true,
    }, `observation:${index}`);
  });
}

function projectIdentityEvidence(item) {
  return projectProfileEvidenceWire({
    ...item,
    active: item.active !== false,
    verified: item.verified === true,
    createdAt: requireTimestamp(
      item.createdAt, "identity_created_at_required"),
    modelVersion: Object.hasOwn(item, "modelVersion") ?
      requireText(item.modelVersion, "identity_model_version_invalid") :
      undefined,
    sourceReference: Object.hasOwn(item, "sourceReference") ?
      requireText(item.sourceReference, "identity_source_reference_invalid") :
      undefined,
  }, "identity");
}

function projectCapabilityEvidence(item) {
  return projectProfileEvidenceWire({
    ...item,
    active: item.active !== false,
    verified: item.verified === true,
    createdAt: requireTimestamp(
      item.createdAt, "capability_created_at_required"),
    modelVersion: Object.hasOwn(item, "modelVersion") ?
      requireText(item.modelVersion, "capability_model_version_invalid") :
      undefined,
    sourceReference: Object.hasOwn(item, "sourceReference") ?
      requireText(item.sourceReference, "capability_source_reference_invalid") :
      undefined,
  }, "capability");
}

/**
 * Dart ProfileEvidence.toMap() wire: omit known valueState, omit null
 * optionals, never emit supportingEvidenceIds.
 */
function projectProfileEvidenceWire(item, label) {
  const valueState = Object.hasOwn(item, "valueState") ?
    item.valueState : "known";
  if (!VALUE_STATES.has(valueState)) {
    fail(`evidence_value_state_invalid:${label}`);
  }
  const result = {
    id: requireText(item.id, `evidence_id_required:${label}`),
    property: requireText(item.property, `evidence_property_required:${label}`),
    value: cloneValue(item.value),
    source: item.source,
    nature: item.nature,
    confidence: item.confidence,
    verified: item.verified === true,
    active: item.active !== false,
    method: requireText(item.method, `evidence_method_required:${label}`),
    createdAt: requireTimestamp(item.createdAt, `created_at_invalid:${label}`),
  };
  if (valueState !== "known") {
    result.valueState = valueState;
  }
  if (item.modelVersion !== undefined && item.modelVersion !== null) {
    result.modelVersion = requireText(
      item.modelVersion, `model_version_invalid:${label}`);
  }
  if (item.sourceReference !== undefined && item.sourceReference !== null) {
    result.sourceReference = requireText(
      item.sourceReference, `source_reference_invalid:${label}`);
  }
  if (item.dependsOnCanonicalType !== undefined &&
      item.dependsOnCanonicalType !== null) {
    result.dependsOnCanonicalType = requireText(
      item.dependsOnCanonicalType, `depends_on_invalid:${label}`);
  }
  if (item.supersedesEvidenceId !== undefined &&
      item.supersedesEvidenceId !== null) {
    result.supersedesEvidenceId = requireText(
      item.supersedesEvidenceId, `supersedes_invalid:${label}`);
  }
  return result;
}

function projectDocument(input) {
  if (input.documentMode === "vision_empty") {
    if (input.wardrobeDocumentProjection !== undefined &&
        input.wardrobeDocumentProjection !== null &&
        (!isObject(input.wardrobeDocumentProjection) ||
          Object.keys(input.wardrobeDocumentProjection).length > 0)) {
      fail("vision_empty_document_must_be_empty");
    }
    return {};
  }
  if (!isObject(input.wardrobeDocumentProjection)) {
    fail("wardrobe_document_projection_invalid");
  }
  const projected = {};
  for (const [key, value] of Object.entries(input.wardrobeDocumentProjection)) {
    if (!DOCUMENT_ALLOW_LIST.includes(key)) {
      fail(`document_field_not_allow_listed:${key}`);
    }
    if (value === undefined) continue;
    if (value !== null && typeof value !== "string") {
      fail(`document_field_type_invalid:${key}`);
    }
    if (typeof value === "string") {
      const trimmed = value.trim();
      if (trimmed.length === 0) continue;
      projected[key] = trimmed;
    }
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

function assertNoKnowledgeBasePriorInput(evidence) {
  for (const item of evidence) {
    if (item.source === "knowledge_base_prior") {
      fail("forged_kb_prior_evidence");
    }
    if (typeof item.id === "string" && item.id.startsWith("kb-prior:")) {
      fail("forged_kb_prior_evidence");
    }
  }
}

function compareUtf16(left, right) {
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

function requireTimestamp(value, reason) {
  if (typeof value !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value)) {
    fail(reason);
  }
  return value;
}

function requireText(value, reason) {
  if (typeof value !== "string" || value.length === 0) fail(reason);
  return value;
}

function requireConfidence(value, reason) {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      value < 0 || value > 1) {
    fail(reason);
  }
  return value;
}

function cloneValue(value) {
  if (value === null || typeof value !== "object") return value;
  return structuredClone(value);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function deepFreeze(value) {
  if (value === null || typeof value !== "object" || Object.isFrozen(value)) {
    return value;
  }
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

function fail(reason) {
  throw new Error(reason);
}

module.exports = {
  CONTRACT_VERSION,
  DOCUMENT_ALLOW_LIST,
  FORBIDDEN_AUTHORITY_FIELDS,
  INPUT_CONTRACT,
  STAGE_ID,
  STAGE_VERSION,
  prepareVisionKnowledgeBasePriorInput,
};
