"use strict";

/**
 * Trusted Wardrobe Profile Resolver input preparation (orchestration stage).
 *
 * Pure / deterministic. Not a production provider and not imported by
 * deployed Vision entry points. Builds wardrobe_profile_resolver_input/v1
 * matching Dart WardrobeProfileResolver.resolve arguments at the call site
 * in VisionV2ShadowOrchestrator.analyze:
 *
 *   allEvidence = [
 *     ...observationEvidence,
 *     ...qualifiedIdentity,
 *     ...capabilityEvidence,
 *     ...kbEvidence,
 *   ]
 *   resolve(itemId: itemId, evidence: allEvidence)
 *
 * Family identity is intentionally excluded — Dart does not pass it here.
 * Observation evidence is projected in deterministic id order (same as
 * PrepareVisionKnowledgeBasePriorInput) so the composed list matches the
 * authoritative Vision call-site / oracle providerInput.
 */

const STAGE_ID = "PrepareWardrobeProfileResolverInput";
const STAGE_VERSION = "wardrobe-profile-resolver-input-v1";
const CONTRACT_VERSION = 1;
const INPUT_CONTRACT = "wardrobe_profile_resolver_input/v1";
const RESOLVER_COMPATIBILITY_VERSION = 1;

const FORBIDDEN_AUTHORITY_FIELDS = Object.freeze([
  "evidence",
  "resolverInput",
  "providerInput",
  "preparedProviderInput",
  "resolvedProfile",
  "selectedCanonicalType",
  "canonicalType",
  "selectedCapabilities",
  "familyEvidence",
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

/**
 * @param {object} raw
 * @returns {Readonly<{itemId: string, evidence: object[]}>}
 */
function prepareWardrobeProfileResolverInput(raw) {
  const input = decodePrepareInput(raw);
  const observationEvidence = projectObservationEvidence(
    input.observationEvidence, input.observationProvenance)
    .sort((left, right) => compareUtf16(left.id, right.id));
  const qualifiedIdentityEvidence = input.qualifiedIdentityEvidence.map(
    (item) => projectIdentityEvidence(item));
  const capabilityEvidence = input.capabilityEvidence.map(
    (item) => projectCapabilityEvidence(item));
  const knowledgeBaseEvidence = input.knowledgeBaseEvidence.map(
    (item) => projectKnowledgeBaseEvidence(item));
  const legacyFallbackEvidence = input.legacyFallbackEvidence.map(
    (item) => projectFallbackEvidence(item, "legacy_fallback"));
  const compatibilityFallbackEvidence =
    input.compatibilityFallbackEvidence.map(
      (item) => projectFallbackEvidence(item, "compatibility"));
  const userCorrectionEvidence = input.userCorrectionEvidence.map(
    (item) => projectUserCorrectionEvidence(item));

  assertNoDuplicateIds([
    ...observationEvidence,
    ...qualifiedIdentityEvidence,
    ...capabilityEvidence,
    ...knowledgeBaseEvidence,
    ...legacyFallbackEvidence,
    ...compatibilityFallbackEvidence,
    ...userCorrectionEvidence,
  ]);
  assertNoKnowledgeBasePriorInUpstream([
    ...observationEvidence,
    ...qualifiedIdentityEvidence,
    ...capabilityEvidence,
    ...legacyFallbackEvidence,
    ...compatibilityFallbackEvidence,
    ...userCorrectionEvidence,
  ]);
  assertKnowledgeBaseEvidenceTrusted(knowledgeBaseEvidence);

  // Family report may be supplied for orchestration context but must never
  // enter resolver evidence (Dart call site ignores it).
  void input.familyIdentityReport;

  return deepFreeze({
    itemId: input.itemId,
    evidence: [
      ...observationEvidence,
      ...qualifiedIdentityEvidence,
      ...capabilityEvidence,
      ...knowledgeBaseEvidence,
      ...legacyFallbackEvidence,
      ...compatibilityFallbackEvidence,
      ...userCorrectionEvidence,
    ],
  });
}

function decodePrepareInput(raw) {
  if (!isObject(raw)) fail("resolver_prepare_input_invalid");
  for (const field of FORBIDDEN_AUTHORITY_FIELDS) {
    if (Object.hasOwn(raw, field)) {
      fail(`forged_authority_field:${field}`);
    }
  }
  if (Object.hasOwn(raw, "familyEvidence")) {
    fail("family_evidence_not_part_of_resolver_input");
  }
  if (raw.contractVersion !== undefined &&
      raw.contractVersion !== CONTRACT_VERSION) {
    fail("resolver_prepare_contract_version_unsupported");
  }
  if (raw.stageVersion !== undefined && raw.stageVersion !== STAGE_VERSION) {
    fail("resolver_prepare_stage_version_unsupported");
  }
  if (raw.resolverCompatibilityVersion !== undefined &&
      raw.resolverCompatibilityVersion !== RESOLVER_COMPATIBILITY_VERSION) {
    fail("resolver_compatibility_version_unsupported");
  }
  const itemId = requireText(raw.itemId, "item_id_required");
  if (!Array.isArray(raw.observationEvidence)) {
    fail("observation_evidence_required");
  }
  if (!Array.isArray(raw.qualifiedIdentityEvidence)) {
    fail("qualified_identity_evidence_required");
  }
  if (!Array.isArray(raw.capabilityEvidence)) {
    fail("capability_evidence_required");
  }
  if (!Array.isArray(raw.knowledgeBaseEvidence)) {
    fail("knowledge_base_evidence_required");
  }
  const observationProvenance = decodeObservationProvenance(
    raw.observationProvenance, raw.observationEvidence);
  return {
    itemId,
    observationEvidence: raw.observationEvidence.map((item, index) =>
      decodeIncomingEvidence(item, index, "observation")),
    qualifiedIdentityEvidence: raw.qualifiedIdentityEvidence.map(
      (item, index) => decodeIncomingEvidence(item, index, "identity")),
    capabilityEvidence: raw.capabilityEvidence.map((item, index) =>
      decodeIncomingEvidence(item, index, "capability")),
    knowledgeBaseEvidence: raw.knowledgeBaseEvidence.map((item, index) =>
      decodeIncomingEvidence(item, index, "knowledge_base")),
    legacyFallbackEvidence: optionalEvidenceArray(
      raw.legacyFallbackEvidence, "legacy"),
    compatibilityFallbackEvidence: optionalEvidenceArray(
      raw.compatibilityFallbackEvidence, "compatibility"),
    userCorrectionEvidence: optionalEvidenceArray(
      raw.userCorrectionEvidence, "user_correction"),
    observationProvenance,
    familyIdentityReport: raw.familyIdentityReport,
  };
}

function optionalEvidenceArray(value, kind) {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) fail(`${kind}_evidence_invalid`);
  return value.map((item, index) => decodeIncomingEvidence(item, index, kind));
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
  requireText(value.id, `evidence_id_required:${kind}:${index}`);
  requireText(value.property, `evidence_property_required:${kind}:${index}`);
  if (!EVIDENCE_SOURCES.has(value.source)) {
    fail(`evidence_source_invalid:${kind}:${index}`);
  }
  if (!EVIDENCE_NATURES.has(value.nature)) {
    fail(`evidence_nature_invalid:${kind}:${index}`);
  }
  requireText(value.method, `evidence_method_required:${kind}:${index}`);
  requireConfidence(value.confidence,
    `evidence_confidence_invalid:${kind}:${index}`);
  if (!Object.hasOwn(value, "value")) {
    fail(`evidence_value_omitted:${kind}:${index}`);
  }
  const valueState = Object.hasOwn(value, "valueState") ?
    value.valueState : "known";
  if (!VALUE_STATES.has(valueState)) {
    fail(`evidence_value_state_invalid:${kind}:${index}`);
  }
  if (valueState !== "known" && value.value !== null) {
    fail(`non_value_evidence_value_invalid:${kind}:${index}`);
  }
  if (kind === "observation" && value.source !== "visual_observation") {
    fail(`observation_source_invalid:${index}`);
  }
  if (kind === "observation" && value.nature !== "observed") {
    fail(`observation_nature_invalid:${index}`);
  }
  if (kind === "capability" &&
      !String(value.property).startsWith("capabilities.")) {
    fail(`capability_property_invalid:${index}`);
  }
  if (kind === "identity" && value.property !== "identity.canonicalType") {
    fail(`identity_property_invalid:${index}`);
  }
  if (kind === "knowledge_base" && value.source !== "knowledge_base_prior") {
    fail(`knowledge_base_source_invalid:${index}`);
  }
  if (kind === "legacy" && value.source !== "legacy_fallback") {
    fail(`legacy_source_invalid:${index}`);
  }
  if (kind === "user_correction" && value.source !== "user_correction") {
    fail(`user_correction_source_invalid:${index}`);
  }
  if (kind === "compatibility") {
    // Compatibility group is an explicit future/read-path slot. Vision path
    // leaves it empty. When present, source must not forge KB/resolved values.
    if (value.source === "knowledge_base_prior") {
      fail(`compatibility_kb_forge:${index}`);
    }
  }
  return structuredClone(value);
}

function projectObservationEvidence(items, provenance) {
  return items.map((item, index) => {
    const createdAt = Object.hasOwn(item, "createdAt") ?
      requireTimestamp(item.createdAt,
        `observation_created_at_invalid:${index}`) :
      provenance.observedAt;
    const modelVersion = Object.hasOwn(item, "modelVersion") ?
      requireText(item.modelVersion,
        `observation_model_version_invalid:${index}`) :
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

function projectKnowledgeBaseEvidence(item) {
  return projectProfileEvidenceWire({
    ...item,
    active: item.active !== false,
    verified: item.verified === true,
    createdAt: requireTimestamp(
      item.createdAt, "kb_created_at_required"),
    modelVersion: Object.hasOwn(item, "modelVersion") ?
      requireText(item.modelVersion, "kb_model_version_invalid") :
      undefined,
    sourceReference: Object.hasOwn(item, "sourceReference") ?
      requireText(item.sourceReference, "kb_source_reference_invalid") :
      undefined,
    dependsOnCanonicalType: item.dependsOnCanonicalType,
  }, "knowledge_base");
}

function projectFallbackEvidence(item, label) {
  return projectProfileEvidenceWire({
    ...item,
    active: item.active !== false,
    verified: item.verified === true,
    createdAt: requireTimestamp(
      item.createdAt, `${label}_created_at_required`),
    modelVersion: Object.hasOwn(item, "modelVersion") ?
      requireText(item.modelVersion, `${label}_model_version_invalid`) :
      undefined,
    sourceReference: Object.hasOwn(item, "sourceReference") ?
      requireText(item.sourceReference, `${label}_source_reference_invalid`) :
      undefined,
  }, label);
}

function projectUserCorrectionEvidence(item) {
  return projectProfileEvidenceWire({
    ...item,
    active: item.active !== false,
    verified: item.verified === true,
    createdAt: requireTimestamp(
      item.createdAt, "user_correction_created_at_required"),
    modelVersion: Object.hasOwn(item, "modelVersion") ?
      requireText(item.modelVersion, "user_correction_model_version_invalid") :
      undefined,
    sourceReference: Object.hasOwn(item, "sourceReference") ?
      requireText(item.sourceReference,
        "user_correction_source_reference_invalid") :
      undefined,
  }, "user_correction");
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

function assertNoDuplicateIds(evidence) {
  const seen = new Set();
  for (const item of evidence) {
    if (seen.has(item.id)) fail(`duplicate_evidence_id:${item.id}`);
    seen.add(item.id);
  }
}

function assertNoKnowledgeBasePriorInUpstream(evidence) {
  for (const item of evidence) {
    if (item.source === "knowledge_base_prior") {
      fail("forged_kb_prior_evidence");
    }
    if (typeof item.id === "string" && item.id.startsWith("kb-prior:")) {
      fail("forged_kb_prior_evidence");
    }
  }
}

function assertKnowledgeBaseEvidenceTrusted(evidence) {
  for (const item of evidence) {
    if (item.source !== "knowledge_base_prior") {
      fail("untrusted_kb_prior_evidence");
    }
    if (typeof item.id !== "string" || !item.id.startsWith("kb-prior:")) {
      fail("untrusted_kb_prior_evidence_id");
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
  FORBIDDEN_AUTHORITY_FIELDS,
  INPUT_CONTRACT,
  RESOLVER_COMPATIBILITY_VERSION,
  STAGE_ID,
  STAGE_VERSION,
  prepareWardrobeProfileResolverInput,
};
