"use strict";

/**
 * Trusted Family Identity input preparation (orchestration stage).
 *
 * Pure / deterministic. Not a production provider and not imported by
 * deployed Vision entry points. Builds BackendFamilyIdentityInput/v1 matching
 * Dart VisionFamilyIdentityResolver.resolve arguments at the call site in
 * VisionV2ShadowOrchestrator.analyze.
 */

const {attestFraming} = require("./vision_framing_attestor");
const {
  assessMultiPhotoConsistency,
  hasWholeItemSilhouette,
} = require("./prepare_vision_identity_qualification_input");

const STAGE_ID = "PrepareVisionFamilyIdentityInput";
const STAGE_VERSION = "family-identity-input-v1";
const CONTRACT_VERSION = 1;
const FAMILY_TAXONOMY_VERSION = "vision-canonical-family-registry-v1";

const FORBIDDEN_AUTHORITY_FIELDS = Object.freeze([
  "providerInput",
  "resolvedCanonicalSubtype",
  "hasWholeItemSilhouette",
  "familyIdentity",
  "resolvedFamily",
  "selectedFamily",
  "familyReport",
  "broadSilhouetteEligible",
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
const OBSERVATION_STATES = new Set([
  "observed",
  "unknown",
  "not_visible",
  "not_applicable",
]);
const OBSERVATION_PROPERTIES = Object.freeze([
  "coverage",
  "hasHood",
  "frontClosure",
  "visibleBulk",
  "surfaceAppearance",
  "necklineShape",
  "visiblePocketStructure",
  "visibleStretchCue",
  "sportyCues",
  "formalCues",
  "footwearConstruction",
  "footwearFastening",
  "soleProfile",
  "visibleTread",
  "footwearUpperHeight",
]);

/**
 * @param {object} raw
 * @returns {Readonly<{
 *   identityCandidates: object[],
 *   observations: object,
 *   resolvedCanonicalSubtype: string|null,
 *   inputAssessment: string,
 *   subjectAssessment: object|null,
 *   hasWholeItemSilhouette: boolean,
 * }>}
 */
function prepareVisionFamilyIdentityInput(raw) {
  const input = decodePrepareInput(raw);
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
    projectSystemSubject(report, input.responses[index].subject));
  const multi = assessMultiPhotoConsistency(
    systemSubjects, input.multiViewSubjectBinding);
  const combinedInputAssessment = computeCombinedInputAssessment(
    input.responses);
  const familyInputAssessment = multi.permitsIdentityPromotion ?
    combinedInputAssessment : "ambiguous_subject";
  const first = input.responses[0];
  const familySubjectAssessment = first.schemaVersion >= 8 ?
    systemSubjects[0] : null;
  const familyHasWholeItemSilhouette = first.schemaVersion < 9 ||
    hasWholeItemSilhouette(framingReports[0]);
  const identityCandidates = expandFamilyCandidates(input.responses);
  return deepFreeze({
    identityCandidates,
    observations: projectObservations(first),
    resolvedCanonicalSubtype:
      input.identityQualificationReport.selectedCanonicalType,
    inputAssessment: familyInputAssessment,
    subjectAssessment: familySubjectAssessment,
    hasWholeItemSilhouette: familyHasWholeItemSilhouette,
  });
}

function expandFamilyCandidates(responses) {
  const candidates = [];
  for (const response of responses) {
    for (const candidate of response.identityCandidates) {
      candidates.push({
        canonicalType: candidate.canonicalType,
        confidence: candidate.confidence,
      });
    }
  }
  return candidates;
}

function computeCombinedInputAssessment(responses) {
  if (responses.every((item) => item.inputAssessment === "valid_single_item")) {
    return "valid_single_item";
  }
  return responses.find((item) => item.inputAssessment !== "valid_single_item")
    .inputAssessment;
}

function projectSystemSubject(framingReport, subject) {
  const framingClass = framingReport.systemAttestedFraming;
  const reasonCodes = [
    ...subject.reasonCodes,
    ...framingReport.reasonCodes,
  ];
  const projected = {
    subjectCountEstimate: subject.subjectCountEstimate,
    cardinalityState: subject.cardinalityState,
    primarySubjectPresent: subject.primarySubjectPresent,
    sameItemConsistency: subject.sameItemConsistency,
    subjectDomain: subject.subjectDomain,
    framingClass,
    permitsFamily: permitsFamily({
      ...subject,
      framingClass,
    }),
    permitsCanonical: permitsCanonical({
      ...subject,
      framingClass,
    }),
    reasonCodes,
  };
  return deepFreeze(projected);
}

function permitsFamily(subject) {
  return subject.cardinalityState === "single_item_supported" &&
    subject.sameItemConsistency === "same_item_supported" &&
    (subject.framingClass === "full_item" ||
      subject.framingClass === "mostly_visible" ||
      subject.framingClass === "partial_item");
}

function permitsCanonical(subject) {
  return subject.cardinalityState === "single_item_supported" &&
    subject.sameItemConsistency === "same_item_supported" &&
    (subject.framingClass === "full_item" ||
      subject.framingClass === "mostly_visible") &&
    subject.subjectDomain !== "unknown" &&
    subject.subjectDomain !== "mixed";
}

/**
 * Dart ClothingObservationBundle.fromMap + toMap round-trip projection.
 * Non-observed states are normalized to factory defaults.
 */
function projectObservations(response) {
  const projected = {
    analysisId: response.analysisId,
    modelVersion: response.modelVersion,
    sourceReference: response.sourceReference,
    observedAt: response.observedAt,
    quality: {...response.quality},
  };
  for (const key of OBSERVATION_PROPERTIES) {
    if (!Object.hasOwn(response.observations, key)) continue;
    projected[key] = normalizeObservationValue(
      response.observations[key], key);
  }
  return deepFreeze(projected);
}

function normalizeObservationValue(value, path) {
  if (!isObject(value)) fail(`observation_invalid:${path}`);
  if (!OBSERVATION_STATES.has(value.state)) {
    fail(`observation_state_invalid:${path}`);
  }
  if (value.state !== "observed") {
    if (value.state === "unknown") {
      return deepFreeze({state: "unknown", confidence: 0});
    }
    if (value.state === "not_visible") {
      return deepFreeze({
        state: "not_visible",
        confidence: 0,
        visibilityScope: "not_visible",
      });
    }
    return deepFreeze({state: "not_applicable", confidence: 1});
  }
  if (!Object.hasOwn(value, "value") || value.value == null) {
    fail(`observation_value_required:${path}`);
  }
  if (typeof value.confidence !== "number" || !Number.isFinite(value.confidence) ||
      value.confidence < 0 || value.confidence > 1) {
    fail(`observation_confidence_invalid:${path}`);
  }
  const result = {
    state: "observed",
    value: value.value,
    confidence: value.confidence,
  };
  if (value.visibilityScope != null) {
    if (typeof value.visibilityScope !== "string") {
      fail(`visibility_scope_invalid:${path}`);
    }
    result.visibilityScope = value.visibilityScope;
  }
  if (Array.isArray(value.visibleRegions) && value.visibleRegions.length > 0) {
    if (value.visibleRegions.some((item) => typeof item !== "string")) {
      fail(`visible_regions_invalid:${path}`);
    }
    result.visibleRegions = [...value.visibleRegions].sort();
  }
  return deepFreeze(result);
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
  if (typeof value.familyTaxonomySha256 !== "string" ||
      !/^[a-f0-9]{64}$/.test(value.familyTaxonomySha256)) {
    fail("taxonomy_sha_invalid");
  }
  if (value.expectedFamilyTaxonomySha256 != null) {
    if (typeof value.expectedFamilyTaxonomySha256 !== "string" ||
        !/^[a-f0-9]{64}$/.test(value.expectedFamilyTaxonomySha256)) {
      fail("taxonomy_sha_expected_invalid");
    }
    if (value.familyTaxonomySha256 !== value.expectedFamilyTaxonomySha256) {
      fail("taxonomy_sha_mismatch");
    }
  }
  if (!Array.isArray(value.responses) || value.responses.length === 0) {
    fail("prepare_responses_invalid");
  }
  const allow = new Set(value.allowedCanonicalTypes);
  const responses = value.responses.map((item, index) =>
    decodeTrustedResponse(item, allow, index));
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
  const identityQualificationReport = decodeIdentityQualificationReport(
    value.identityQualificationReport);
  return deepFreeze({
    responses,
    multiViewSubjectBinding,
    framingReports,
    identityQualificationReport,
    allowedCanonicalTypes: [...value.allowedCanonicalTypes],
    familyTaxonomySha256: value.familyTaxonomySha256,
  });
}

function decodeIdentityQualificationReport(value) {
  if (!isObject(value)) fail("identity_qualification_report_invalid");
  if (value.selectedCanonicalType != null &&
      typeof value.selectedCanonicalType !== "string") {
    fail("selected_canonical_type_invalid");
  }
  if (typeof value.state !== "string" || value.state.trim() === "") {
    fail("identity_qualification_state_invalid");
  }
  return deepFreeze({
    selectedCanonicalType: value.selectedCanonicalType ?? null,
    state: value.state,
  });
}

function decodeTrustedResponse(value, allow, index = 0) {
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
  const seen = new Set();
  const identityCandidates = value.identityCandidates.map((candidate, cIndex) => {
    const decoded = decodeCandidate(candidate, `${index}:${cIndex}`, allow);
    const key = decoded.canonicalType;
    if (seen.has(key)) fail(`duplicate_candidate:${index}:${key}`);
    seen.add(key);
    return decoded;
  });
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
  if (!isObject(value.observations)) fail(`observations_required:${index}`);
  const observations = {};
  const seenProps = new Set();
  for (const [key, raw] of Object.entries(value.observations)) {
    if (!OBSERVATION_PROPERTIES.includes(key)) {
      fail(`unknown_observation_property:${index}:${key}`);
    }
    if (seenProps.has(key)) fail(`duplicate_observation_property:${index}:${key}`);
    seenProps.add(key);
    observations[key] = raw;
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
    observations,
  });
}

function decodeCandidate(value, path, allow) {
  if (!isObject(value)) fail(`candidate_invalid:${path}`);
  requireText(value.canonicalType, `canonical_type_required:${path}`);
  if (!allow.has(value.canonicalType)) {
    fail(`unknown_canonical_key:${value.canonicalType}`);
  }
  if (typeof value.confidence !== "number" || !Number.isFinite(value.confidence) ||
      value.confidence < 0 || value.confidence > 1) {
    fail(`candidate_confidence_invalid:${path}`);
  }
  return deepFreeze({
    canonicalType: value.canonicalType,
    confidence: value.confidence,
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
  const result = {};
  if (Object.hasOwn(value, "itemFullyVisible")) {
    if (typeof value.itemFullyVisible !== "boolean") {
      fail(`quality_item_fully_visible_invalid:${index}`);
    }
    result.itemFullyVisible = value.itemFullyVisible;
  }
  for (const key of ["backgroundInterference", "clarity"]) {
    if (Object.hasOwn(value, key)) {
      if (typeof value[key] !== "string") fail(`quality_${key}_invalid:${index}`);
      result[key] = value[key];
    }
  }
  if (Object.hasOwn(value, "occlusion")) {
    if (typeof value.occlusion !== "string") {
      fail(`quality_occlusion_invalid:${index}`);
    }
    result.occlusion = value.occlusion;
  }
  return deepFreeze(result);
}

function decodeAttestations(value, index) {
  if (!isObject(value)) fail(`attestations_invalid:${index}`);
  return deepFreeze({
    visibleBoundaries: Array.isArray(value.visibleBoundaries) ?
      [...value.visibleBoundaries] : [],
    primarySilhouetteContinuous: value.primarySilhouetteContinuous === true,
    visibleItemExtent: value.visibleItemExtent ?? null,
    localDetailOnly: value.localDetailOnly === true,
    cropIndicators: Array.isArray(value.cropIndicators) ?
      [...value.cropIndicators] : [],
    subjectOrientation: value.subjectOrientation ?? null,
  });
}

function decodeFramingReport(value) {
  if (!isObject(value)) fail("framing_report_invalid");
  requireText(value.systemAttestedFraming, "system_attested_framing_required");
  return deepFreeze({
    modelDeclaredFraming: value.modelDeclaredFraming ?? null,
    systemAttestedFraming: value.systemAttestedFraming,
    framingTrustState: value.framingTrustState ?? null,
    framingEvidence: value.framingEvidence ?? value.framingAttestations ?? null,
    framingContradictions: Array.isArray(value.framingContradictions) ?
      [...value.framingContradictions] : [],
    reasonCodes: Array.isArray(value.reasonCodes) ?
      value.reasonCodes.map(String) : [],
  });
}

function decodeBinding(value) {
  if (value == null) {
    return deepFreeze({
      contractVersion: 1,
      physicalIdentityClaim: "undeclared",
      reasonCodes: [],
    });
  }
  if (!isObject(value)) fail("multi_view_binding_invalid");
  if (value.contractVersion !== 1) fail("multi_view_binding_version_invalid");
  requireEnum(value.physicalIdentityClaim, PHYSICAL_CLAIMS,
    "physical_identity_claim_invalid");
  return deepFreeze({
    contractVersion: 1,
    physicalIdentityClaim: value.physicalIdentityClaim,
    reasonCodes: Array.isArray(value.reasonCodes) ?
      value.reasonCodes.map(String) : [],
  });
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
  FAMILY_TAXONOMY_VERSION,
  FORBIDDEN_AUTHORITY_FIELDS,
  OBSERVATION_PROPERTIES,
  STAGE_ID,
  STAGE_VERSION,
  computeCombinedInputAssessment,
  expandFamilyCandidates,
  normalizeObservationValue,
  permitsCanonical,
  permitsFamily,
  prepareVisionFamilyIdentityInput,
  projectObservations,
  projectSystemSubject,
};
