"use strict";

/**
 * Trusted Identity Qualification input preparation (orchestration stage).
 *
 * Pure / deterministic. Not a production provider and not imported by
 * deployed Vision entry points. Builds BackendIdentityQualificationInput/v1
 * matching Dart VisionIdentityQualifier.qualify arguments.
 */

const {
  validateCanonicalConsistency,
} = require("./canonical_observation_consistency_validator");
const {attestFraming} = require("./vision_framing_attestor");

const STAGE_ID = "PrepareVisionIdentityQualificationInput";
const STAGE_VERSION = "identity-qualification-input-v1";
const CONTRACT_VERSION = 1;
const IDENTITY_METHOD = "vision_v2_identity_candidate";
const IDENTITY_PROPERTY = "identity.canonicalType";
const FORBIDDEN_AUTHORITY_FIELDS = Object.freeze([
  "identityEvidence",
  "declaredByEvidenceId",
  "consistency",
  "inputIsValid",
  "qualifiedIdentityEvidence",
  "providerInput",
]);

const PHYSICAL_CLAIMS = new Set([
  "same_physical_item",
  "different_physical_items",
  "undeclared",
]);
const INPUT_ASSESSMENTS = new Set([
  "valid_single_item",
  "multiple_items",
  "insufficient_visual_information",
  "non_wardrobe_object",
  "ambiguous_subject",
]);

/**
 * @param {object} raw
 * @returns {Readonly<{
 *   identityEvidence: object[],
 *   consistency: object,
 *   declaredByEvidenceId: object,
 *   inputIsValid: boolean,
 * }>}
 */
function prepareVisionIdentityQualificationInput(raw) {
  const input = decodePrepareInput(raw);
  const materialized = materializeVisionIdentityEvidence({
    responses: input.responses,
    allowedCanonicalTypes: input.allowedCanonicalTypes,
  });
  const consistency = validateCanonicalConsistency({
    identityEvidence: materialized.identityEvidence,
    observationEvidence: input.observationEvidence,
  });
  const framingReports = input.framingReports ??
    input.responses.map((response) => attestFraming({
      inputAssessment: response.inputAssessment,
      subject: response.subject,
      quality: response.quality,
      attestations: response.framingAttestations,
    }));
  if (framingReports.length !== input.responses.length) {
    fail("framing_report_count_mismatch");
  }
  const systemSubjects = framingReports.map((report, index) =>
    applyFramingToSubject(report, input.responses[index].subject));
  const validity = computeVisionIdentityInputValidity({
    responses: input.responses,
    framingReports,
    systemSubjects,
    multiViewSubjectBinding: input.multiViewSubjectBinding,
  });
  return deepFreeze({
    identityEvidence: materialized.identityEvidence,
    consistency,
    declaredByEvidenceId: materialized.declaredByEvidenceId,
    inputIsValid: validity.isValid,
  });
}

function materializeVisionIdentityEvidence({
  responses,
  allowedCanonicalTypes,
}) {
  const allow = new Set(allowedCanonicalTypes);
  const declaredByEvidenceId = {};
  const identityEvidence = [];
  for (const response of responses) {
    for (const candidate of response.identityCandidates) {
      if (!allow.has(candidate.canonicalType)) {
        fail(`unknown_canonical_key:${candidate.canonicalType}`);
      }
      const evidenceId =
        `vision-identity:${response.analysisId}:${candidate.canonicalType}`;
      declaredByEvidenceId[evidenceId] = {
        defining: sortedUniqueStrings(
          candidate.definingObservations ?? []),
        supporting: sortedUniqueStrings(
          candidate.supportingObservations ?? []),
      };
      identityEvidence.push({
        id: evidenceId,
        property: IDENTITY_PROPERTY,
        value: candidate.canonicalType,
        source: "ai_inference",
        nature: "inferred",
        confidence: candidate.confidence,
        verified: false,
        active: true,
        method: IDENTITY_METHOD,
        createdAt: response.observedAt,
        modelVersion: response.modelVersion,
        sourceReference: response.sourceReference,
      });
    }
  }
  identityEvidence.sort((left, right) => left.id.localeCompare(right.id));
  return deepFreeze({identityEvidence, declaredByEvidenceId});
}

function computeVisionIdentityInputValidity({
  responses,
  framingReports,
  systemSubjects,
  multiViewSubjectBinding,
}) {
  const reasons = [];
  const multi = assessMultiPhotoConsistency(
    systemSubjects, multiViewSubjectBinding);
  const permitsIdentityPromotion =
    multi.physicalIdentity === "sameItemSupported" &&
    multi.semanticAgreement === "consistent";
  if (!permitsIdentityPromotion) {
    if (multi.physicalIdentity !== "sameItemSupported") {
      reasons.push("physical_identity_not_same_item");
    }
    if (multi.semanticAgreement !== "consistent") {
      reasons.push("semantic_agreement_not_consistent");
    }
  }
  const perViewValid = responses.every((response, index) => {
    if (response.inputAssessment !== "valid_single_item") {
      reasons.push(`parser_input_invalid:${index}`);
      return false;
    }
    if (response.schemaVersion < 8) return true;
    const subjectOk = permitsCanonical(systemSubjects[index]);
    const silhouetteOk = hasWholeItemSilhouette(framingReports[index]);
    if (!subjectOk) reasons.push(`subject_permits_canonical_false:${index}`);
    if (!silhouetteOk) {
      reasons.push(`framing_no_whole_item_silhouette:${index}`);
    }
    return subjectOk && silhouetteOk;
  });
  const isValid = perViewValid && permitsIdentityPromotion;
  return deepFreeze({
    isValid,
    reasonCodes: [...new Set(reasons)].sort(),
    multiPhotoAssessment: multi,
    permitsIdentityPromotion,
  });
}

function applyFramingToSubject(framingReport, subject) {
  return deepFreeze({
    ...subject,
    framingClass: framingReport.systemAttestedFraming,
    reasonCodes: [
      ...subject.reasonCodes,
      ...framingReport.reasonCodes,
    ],
  });
}

function permitsCanonical(subject) {
  return subject.cardinalityState === "single_item_supported" &&
    subject.sameItemConsistency === "same_item_supported" &&
    (subject.framingClass === "full_item" ||
      subject.framingClass === "mostly_visible") &&
    subject.subjectDomain !== "unknown" &&
    subject.subjectDomain !== "mixed";
}

function hasWholeItemSilhouette(framingReport) {
  const attestations = framingReport.framingEvidence;
  if (attestations == null) return false;
  return attestations.localDetailOnly === false &&
    attestations.primarySilhouetteContinuous === true &&
    (attestations.visibleItemExtent === "whole" ||
      attestations.visibleItemExtent === "broad") &&
    (framingReport.systemAttestedFraming === "full_item" ||
      framingReport.systemAttestedFraming === "mostly_visible");
}

function assessMultiPhotoSemanticAgreement(assessments) {
  const items = [...assessments];
  if (items.length === 0) return "unknown";
  const domains = new Set(items.map((item) => item.subjectDomain));
  if (domains.has("mixed")) return "unknown";
  if (domains.has("unknown") && domains.size > 1) return "unknown";
  if (domains.size <= 1) return "consistent";
  if (domains.size === 2 &&
      domains.has("garment_upper") &&
      domains.has("garment_outerwear")) {
    return "compatible";
  }
  return "conflicting";
}

function assessMultiPhotoConsistency(assessments, binding) {
  const items = [...assessments];
  const semantic = assessMultiPhotoSemanticAgreement(items);
  const reasons = [];
  if (items.length === 0) {
    reasons.push("empty_assessments");
    return deepFreeze({
      physicalIdentity: "sameItemUncertain",
      semanticAgreement: semantic,
      binding,
      reasonCodes: reasons,
      sameItemViews: false,
      permitsIdentityPromotion: false,
    });
  }
  if (items.some((item) =>
    item.cardinalityState !== "single_item_supported")) {
    reasons.push("cardinality_veto");
    return freezeAssessment("differentItemsSuspected", semantic, binding,
      reasons);
  }
  if (items.some((item) =>
    item.sameItemConsistency === "different_items_suspected" ||
    item.sameItemConsistency === "conflicting_subjects")) {
    reasons.push("per_view_subject_conflict_veto");
    return freezeAssessment("conflictingSubjects", semantic, binding, reasons);
  }
  if (items.length === 1) {
    if (items[0].sameItemConsistency === "same_item_supported") {
      reasons.push("single_view_local_same_item");
      return freezeAssessment("sameItemSupported", semantic, binding, reasons);
    }
    reasons.push("single_view_local_uncertain");
    return freezeAssessment("sameItemUncertain", semantic, binding, reasons);
  }
  switch (binding.physicalIdentityClaim) {
  case "different_physical_items":
    reasons.push("binding_different_physical_items");
    return freezeAssessment("conflictingSubjects", semantic, binding, reasons);
  case "same_physical_item":
    reasons.push("binding_same_physical_item");
    return freezeAssessment("sameItemSupported", semantic, binding, reasons);
  case "undeclared":
  default:
    reasons.push("binding_undeclared_fail_closed");
    return freezeAssessment("sameItemUncertain", semantic, binding, reasons);
  }
}

function freezeAssessment(physicalIdentity, semanticAgreement, binding,
    reasons) {
  const sameItemViews = physicalIdentity === "sameItemSupported";
  const permitsIdentityPromotion = sameItemViews &&
    semanticAgreement === "consistent";
  return deepFreeze({
    physicalIdentity,
    semanticAgreement,
    binding,
    reasonCodes: [...reasons],
    sameItemViews,
    permitsIdentityPromotion,
  });
}

function decodePrepareInput(value) {
  if (!isObject(value)) fail("prepare_input_invalid");
  for (const field of FORBIDDEN_AUTHORITY_FIELDS) {
    if (Object.hasOwn(value, field)) {
      fail(`forged_client_authority_field:${field}`);
    }
  }
  if (!Array.isArray(value.allowedCanonicalTypes) ||
      value.allowedCanonicalTypes.length === 0 ||
      value.allowedCanonicalTypes.some((item) => typeof item !== "string" ||
        item.trim() === "")) {
    fail("taxonomy_allow_list_invalid");
  }
  if (value.taxonomyRegistrySha256 != null) {
    if (typeof value.taxonomyRegistrySha256 !== "string" ||
        !/^[a-f0-9]{64}$/.test(value.taxonomyRegistrySha256)) {
      fail("taxonomy_sha_invalid");
    }
    if (value.expectedTaxonomyRegistrySha256 != null &&
        value.taxonomyRegistrySha256 !==
          value.expectedTaxonomyRegistrySha256) {
      fail("taxonomy_sha_mismatch");
    }
  }
  if (!Array.isArray(value.responses) || value.responses.length === 0) {
    fail("prepare_responses_invalid");
  }
  if (!Array.isArray(value.observationEvidence)) {
    fail("observation_evidence_invalid");
  }
  const responses = value.responses.map(decodeTrustedResponse);
  const multiViewSubjectBinding = decodeBinding(
    value.multiViewSubjectBinding);
  let framingReports = null;
  if (value.framingReports != null) {
    if (!Array.isArray(value.framingReports) ||
        value.framingReports.length !== responses.length) {
      fail("framing_reports_invalid");
    }
    framingReports = value.framingReports.map(decodeFramingReport);
  }
  return deepFreeze({
    responses,
    observationEvidence: value.observationEvidence.map(decodeEvidenceLoose),
    allowedCanonicalTypes: [...value.allowedCanonicalTypes],
    multiViewSubjectBinding,
    framingReports,
    taxonomyRegistrySha256: value.taxonomyRegistrySha256 ?? null,
  });
}

function decodeTrustedResponse(value, index = 0) {
  if (!isObject(value)) fail(`response_invalid:${index}`);
  requireText(value.analysisId, `analysis_id_required:${index}`);
  requireText(value.observedAt, `observed_at_required:${index}`);
  requireText(value.modelVersion, `model_version_required:${index}`);
  requireText(value.sourceReference, `source_reference_required:${index}`);
  if (!Number.isInteger(value.schemaVersion) ||
      value.schemaVersion < 2 || value.schemaVersion > 9) {
    fail(`schema_version_invalid:${index}`);
  }
  requireEnum(value.inputAssessment, INPUT_ASSESSMENTS,
    `input_assessment_invalid:${index}`);
  if (!Array.isArray(value.identityCandidates) ||
      value.identityCandidates.length > 3) {
    fail(`identity_candidates_invalid:${index}`);
  }
  const identityCandidates = value.identityCandidates.map((candidate, cIndex) =>
    decodeCandidate(candidate, `${index}:${cIndex}`));
  const subject = decodeSubject(value.subject ?? value.subjectAssessment,
    index);
  const quality = decodeQuality(value.quality, index);
  let framingAttestations = null;
  const rawAttestations = value.framingAttestations ??
    (isObject(value.subjectAssessment) ?
      value.subjectAssessment.framingAttestations : null);
  if (rawAttestations != null) {
    framingAttestations = decodeAttestations(rawAttestations, index);
  }
  return deepFreeze({
    analysisId: value.analysisId,
    observedAt: value.observedAt,
    modelVersion: value.modelVersion,
    sourceReference: value.sourceReference,
    schemaVersion: value.schemaVersion,
    inputAssessment: value.inputAssessment,
    identityCandidates,
    subject,
    quality,
    framingAttestations,
  });
}

function decodeCandidate(value, path) {
  if (!isObject(value)) fail(`candidate_invalid:${path}`);
  requireText(value.canonicalType, `canonical_type_required:${path}`);
  if (typeof value.confidence !== "number" || !Number.isFinite(value.confidence) ||
      value.confidence < 0 || value.confidence > 1) {
    fail(`candidate_confidence_invalid:${path}`);
  }
  if (value.definingObservations != null &&
      (!Array.isArray(value.definingObservations) ||
        value.definingObservations.some((item) => typeof item !== "string"))) {
    fail(`defining_observations_invalid:${path}`);
  }
  if (value.supportingObservations != null &&
      (!Array.isArray(value.supportingObservations) ||
        value.supportingObservations.some((item) =>
          typeof item !== "string"))) {
    fail(`supporting_observations_invalid:${path}`);
  }
  return deepFreeze({
    canonicalType: value.canonicalType,
    confidence: value.confidence,
    definingObservations: value.definingObservations ?? [],
    supportingObservations: value.supportingObservations ?? [],
  });
}

function decodeSubject(value, index) {
  if (!isObject(value)) fail(`subject_invalid:${index}`);
  requireText(value.cardinalityState, `cardinality_required:${index}`);
  requireText(value.sameItemConsistency, `same_item_required:${index}`);
  requireText(value.subjectDomain, `subject_domain_required:${index}`);
  requireText(value.framingClass, `framing_class_required:${index}`);
  if (typeof value.primarySubjectPresent !== "boolean") {
    fail(`primary_subject_invalid:${index}`);
  }
  if (!Number.isInteger(value.subjectCountEstimate)) {
    fail(`subject_count_invalid:${index}`);
  }
  return deepFreeze({
    subjectCountEstimate: value.subjectCountEstimate,
    cardinalityState: value.cardinalityState,
    primarySubjectPresent: value.primarySubjectPresent,
    sameItemConsistency: value.sameItemConsistency,
    subjectDomain: value.subjectDomain,
    framingClass: value.framingClass,
    reasonCodes: Array.isArray(value.reasonCodes) ?
      value.reasonCodes.map(String) : [],
  });
}

function decodeQuality(value, index) {
  if (!isObject(value)) fail(`quality_invalid:${index}`);
  return deepFreeze(structuredClone(value));
}

function decodeAttestations(value, index) {
  if (!isObject(value)) fail(`attestations_invalid:${index}`);
  return deepFreeze(structuredClone(value));
}

function decodeFramingReport(value) {
  if (!isObject(value) ||
      typeof value.systemAttestedFraming !== "string") {
    fail("framing_report_invalid");
  }
  return deepFreeze({
    modelDeclaredFraming: value.modelDeclaredFraming,
    systemAttestedFraming: value.systemAttestedFraming,
    framingTrustState: value.framingTrustState,
    framingEvidence: value.framingEvidence == null ?
      null : structuredClone(value.framingEvidence),
    framingContradictions: Array.isArray(value.framingContradictions) ?
      [...value.framingContradictions] : [],
    reasonCodes: Array.isArray(value.reasonCodes) ?
      [...value.reasonCodes] : [],
  });
}

function decodeBinding(value) {
  if (value == null) {
    return deepFreeze({
      contractVersion: 1,
      physicalIdentityClaim: "undeclared",
      source: "undeclared",
      reasonCodes: [],
    });
  }
  if (!isObject(value)) fail("multi_view_binding_invalid");
  requireEnum(value.physicalIdentityClaim, PHYSICAL_CLAIMS,
    "physical_identity_claim_invalid");
  return deepFreeze({
    contractVersion: value.contractVersion ?? 1,
    physicalIdentityClaim: value.physicalIdentityClaim,
    source: value.source ?? "undeclared",
    reasonCodes: Array.isArray(value.reasonCodes) ?
      value.reasonCodes.map(String) : [],
  });
}

function decodeEvidenceLoose(value) {
  if (!isObject(value) || typeof value.id !== "string" ||
      typeof value.property !== "string") {
    fail("observation_evidence_item_invalid");
  }
  return deepFreeze(structuredClone(value));
}

function sortedUniqueStrings(values) {
  return [...new Set(values.map(String))].sort();
}

function requireText(value, reason) {
  if (typeof value !== "string" || value.trim() === "") fail(reason);
  return value;
}

function requireEnum(value, allowed, reason) {
  if (typeof value !== "string" || !allowed.has(value)) fail(reason);
  return value;
}

function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    Object.values(value).forEach(deepFreeze);
  }
  return value;
}

function fail(reason) {
  throw new Error(reason);
}

module.exports = {
  CONTRACT_VERSION,
  FORBIDDEN_AUTHORITY_FIELDS,
  STAGE_ID,
  STAGE_VERSION,
  applyFramingToSubject,
  assessMultiPhotoConsistency,
  computeVisionIdentityInputValidity,
  hasWholeItemSilhouette,
  materializeVisionIdentityEvidence,
  permitsCanonical,
  prepareVisionIdentityQualificationInput,
};
