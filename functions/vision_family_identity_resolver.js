"use strict";

/**
 * Node port of Dart VisionFamilyIdentityResolver.resolve.
 * Pure / sync / deterministic.
 *
 * Taxonomy map loads from the deploy-packaged generated artifact
 * (VisionCanonicalFamilyRegistryArtifact) derived from Dart source of truth —
 * no hand-maintained second registry and no runtime Dart file reads.
 */

const {
  loadVisionCanonicalFamilyRegistryArtifact,
} = require("./vision_canonical_family_registry_loader");

const PROVIDER_ID = "VisionFamilyIdentityResolver";
const PROVIDER_VERSION = "vision-family-identity-resolver-v1";
const ORACLE_CONTRACT_VERSION = 1;
const FAMILY_TAXONOMY_VERSION = "vision-canonical-family-registry-v1";

const INPUT_ASSESSMENTS = new Set([
  "valid_single_item",
  "multiple_items",
  "insufficient_visual_information",
  "non_wardrobe_object",
  "ambiguous_subject",
]);
const OBSERVATION_STATES = new Set([
  "observed", "unknown", "not_visible", "not_applicable",
]);
const VISIBILITY_SCOPES = new Set([
  "complete", "sufficient", "partial", "not_visible",
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

const FAMILY_WIRE = Object.freeze({
  top: "top",
  knitwear: "knitwear",
  trousers: "trousers",
  shorts: "shorts",
  jacketOuterwear: "jacket_outerwear",
  sneakers: "sneakers",
  boots: "boots",
});

const {canonicalToFamily, familyTaxonomySha256} = loadCanonicalFamilyRegistry();

function resolveVisionFamilyIdentity(rawInput) {
  const input = decodeFamilyIdentityInput(rawInput);
  if (input.familyTaxonomySha256 != null &&
      input.familyTaxonomySha256 !== familyTaxonomySha256) {
    fail("taxonomy_sha_mismatch");
  }
  if (input.expectedFamilyTaxonomySha256 != null &&
      input.familyTaxonomySha256 != null &&
      input.familyTaxonomySha256 !== input.expectedFamilyTaxonomySha256) {
    fail("taxonomy_sha_mismatch");
  }

  const assessmentValid = input.inputAssessment === "valid_single_item";
  const subjectRejects = input.subjectAssessment != null &&
    !input.subjectAssessment.permitsFamily;
  if (!assessmentValid || subjectRejects || !input.hasWholeItemSilhouette) {
    return deepFreeze({
      state: "invalid_input",
      resolvedFamily: null,
      confidence: 0,
      candidates: [],
      subtypeCandidates: subtypes(input.identityCandidates),
      subtypeResolved: false,
      reasonCodes: [
        ...(!assessmentValid ? ["input_assessment_rejects_family"] : []),
        ...(subjectRejects ? ["subject_or_framing_rejects_family"] : []),
        ...(!input.hasWholeItemSilhouette ?
          ["whole_item_silhouette_required_for_family"] : []),
      ],
    });
  }

  const grouped = new Map();
  for (const candidate of input.identityCandidates) {
    const family = canonicalToFamily.get(candidate.canonicalType);
    if (family == null) continue;
    if (!grouped.has(family)) grouped.set(family, []);
    grouped.get(family).push(candidate);
  }
  if (grouped.size === 0) {
    return deepFreeze({
      state: "insufficient_evidence",
      resolvedFamily: null,
      confidence: 0,
      candidates: [],
      subtypeCandidates: subtypes(input.identityCandidates),
      subtypeResolved: input.resolvedCanonicalSubtype != null,
      reasonCodes: ["no_mapped_family_candidate"],
    });
  }

  const qualityConfidence = qualityConfidenceOf(input.observations.quality);
  const familyCandidates = [...grouped.entries()].map(([family, items]) => {
    const generalEvidence = familyEvidence(family, input.observations);
    const candidateAgreement = items.reduce(
      (sum, item) => sum + item.confidence, 0);
    const candidateConfidence = candidateAgreement > 1 ?
      1.0 : candidateAgreement;
    const visibilityConfidence = generalEvidence.directConfidence === 0 ?
      0.0 : generalEvidence.directConfidence;
    const confidence = generalEvidence.directConfidence === 0 ?
      0.0 :
      (candidateConfidence * 0.30 +
        generalEvidence.directConfidence * 0.35 +
        generalEvidence.supportingConfidence * 0.10 +
        qualityConfidence * 0.15 +
        visibilityConfidence * 0.10);
    return {
      family: FAMILY_WIRE[family],
      canonicalCandidates: subtypes(items),
      confidence,
      evidence: generalEvidence.evidence,
      confidenceComponents: {
        candidateAgreement: candidateConfidence,
        directFamilyEvidence: generalEvidence.directConfidence,
        supportingFamilyEvidence: generalEvidence.supportingConfidence,
        imageQuality: qualityConfidence,
        visibilityTrust: visibilityConfidence,
      },
    };
  }).sort((left, right) => {
    const byConfidence = right.confidence - left.confidence;
    if (byConfidence !== 0) return byConfidence < 0 ? -1 : 1;
    return left.family.localeCompare(right.family);
  });

  const top = familyCandidates[0];
  const ambiguous = familyCandidates.length > 1 &&
    top.confidence - familyCandidates[1].confidence < 0.20;
  const supported = !ambiguous && top.confidence >= 0.62;
  const capsAtSupported = input.subjectAssessment?.capsFamilyAtSupported ===
    true;
  const confirmed = supported && top.confidence >= 0.82 && !capsAtSupported;
  const state = ambiguous ? "ambiguous" :
    confirmed ? "confirmed" :
      supported ? "supported" : "insufficient_evidence";
  return deepFreeze({
    state,
    resolvedFamily: supported ? top.family : null,
    confidence: supported ? top.confidence : 0,
    candidates: familyCandidates,
    subtypeCandidates: subtypes(input.identityCandidates),
    subtypeResolved: input.resolvedCanonicalSubtype != null,
    reasonCodes: [
      ...(ambiguous ? ["competing_families"] : []),
      ...(!ambiguous && !supported ? ["insufficient_family_evidence"] : []),
      ...(supported ?
        ["taxonomy_family_agrees_with_visual_family_evidence"] : []),
      ...(supported && input.resolvedCanonicalSubtype == null ?
        ["family_resolved_subtype_unresolved"] : []),
    ],
  });
}

function familyEvidence(family, observations) {
  if (family === "sneakers" || family === "boots") {
    const construction = observations.footwearConstruction;
    const height = observations.footwearUpperHeight;
    const fastening = observations.footwearFastening;
    const surface = observations.surfaceAppearance;
    const evidence = [
      ...(familyVisible(construction) ? ["tier1:footwearConstruction"] : []),
      ...(familyVisible(height) ? ["tier1:footwearUpperHeight"] : []),
      ...(familyVisible(fastening) ? ["tier2:footwearFastening"] : []),
      ...(familyVisible(surface) ? ["tier2:surfaceAppearance"] : []),
    ];
    const direct = [
      ...(familyVisible(construction) ? [scopeAdjusted(construction)] : []),
      ...(familyVisible(height) ? [scopeAdjusted(height)] : []),
    ];
    const supporting = [
      ...(familyVisible(fastening) ? [scopeAdjusted(fastening)] : []),
      ...(familyVisible(surface) ? [scopeAdjusted(surface)] : []),
    ];
    return {
      directConfidence: direct.length === 0 ? 0 :
        clamp01(Math.max(...direct) + (direct.length > 1 ? 0.05 : 0)),
      supportingConfidence: supporting.length === 0 ? 0 :
        Math.max(...supporting),
      evidence,
    };
  }
  const coverage = observations.coverage;
  const bulk = observations.visibleBulk;
  const neckline = observations.necklineShape;
  const closure = observations.frontClosure;
  const direct = familyVisible(coverage) ? scopeAdjusted(coverage) : 0.0;
  const supporting = [
    ...(familyVisible(bulk) ? [scopeAdjusted(bulk)] : []),
    ...(familyVisible(neckline) ? [scopeAdjusted(neckline)] : []),
    ...(familyVisible(closure) && closure.value !== "none" ?
      [scopeAdjusted(closure)] : []),
  ];
  return {
    directConfidence: direct,
    supportingConfidence: supporting.length === 0 ? 0 :
      Math.max(...supporting),
    evidence: [
      ...(familyVisible(coverage) ? ["tier1:coverage"] : []),
      ...(familyVisible(bulk) ? ["tier2:visibleBulk"] : []),
      ...(familyVisible(neckline) ? ["tier2:necklineShape"] : []),
      ...(familyVisible(closure) && closure.value !== "none" ?
        ["tier2:frontClosure"] : []),
    ],
  };
}

function familyVisible(value) {
  return value != null && value.state === "observed";
}

function scopeAdjusted(value) {
  const multiplier = value.visibilityScope === "complete" ? 1.0 :
    value.visibilityScope === "sufficient" ? 0.9 :
      value.visibilityScope === "partial" ? 0.7 :
        value.visibilityScope === "not_visible" ? 0.0 : 0.6;
  return value.confidence * multiplier;
}

function qualityConfidenceOf(quality) {
  let result = quality.clarity === "high" ? 0.95 :
    quality.clarity === "medium" ? 0.7 :
      quality.clarity === "low" ? 0.2 : 0.5;
  if (quality.itemFullyVisible === false && result > 0.7) result = 0.7;
  if (quality.occlusion === "partial" && result > 0.65) result = 0.65;
  if (quality.occlusion === "substantial" && result > 0.25) result = 0.25;
  if (quality.backgroundInterference === "high" && result > 0.35) {
    result = 0.35;
  }
  return result;
}

function subtypes(candidates) {
  return [...new Set(candidates.map((item) => item.canonicalType))].sort();
}

function clamp01(value) {
  return Math.min(1, Math.max(0, value));
}

function decodeFamilyIdentityInput(value) {
  if (!isObject(value)) fail("family_input_invalid");
  if (!Array.isArray(value.identityCandidates)) {
    fail("identity_candidates_invalid");
  }
  if (value.identityCandidates.length > 3) {
    fail("identity_candidates_too_many");
  }
  const seen = new Set();
  const identityCandidates = value.identityCandidates.map((item, index) => {
    const decoded = decodeCandidate(item, index);
    if (seen.has(decoded.canonicalType)) {
      fail(`duplicate_candidate:${decoded.canonicalType}`);
    }
    seen.add(decoded.canonicalType);
    return decoded;
  });
  if (!isObject(value.observations)) fail("observations_invalid");
  const observations = decodeObservations(value.observations);
  if (value.resolvedCanonicalSubtype != null &&
      typeof value.resolvedCanonicalSubtype !== "string") {
    fail("resolved_canonical_subtype_invalid");
  }
  if (value.resolvedCanonicalSubtype != null &&
      value.resolvedCanonicalSubtype.trim() === "") {
    fail("resolved_canonical_subtype_empty");
  }
  requireEnum(value.inputAssessment, INPUT_ASSESSMENTS,
    "input_assessment_invalid");
  if (typeof value.hasWholeItemSilhouette !== "boolean") {
    fail("has_whole_item_silhouette_invalid");
  }
  let subjectAssessment = null;
  if (value.subjectAssessment != null) {
    subjectAssessment = decodeSubject(value.subjectAssessment);
  }
  if (value.familyTaxonomySha256 != null) {
    if (typeof value.familyTaxonomySha256 !== "string" ||
        !/^[a-f0-9]{64}$/.test(value.familyTaxonomySha256)) {
      fail("taxonomy_sha_invalid");
    }
  }
  if (value.expectedFamilyTaxonomySha256 != null) {
    if (typeof value.expectedFamilyTaxonomySha256 !== "string" ||
        !/^[a-f0-9]{64}$/.test(value.expectedFamilyTaxonomySha256)) {
      fail("taxonomy_sha_expected_invalid");
    }
  }
  return deepFreeze({
    identityCandidates,
    observations,
    resolvedCanonicalSubtype: value.resolvedCanonicalSubtype ?? null,
    inputAssessment: value.inputAssessment,
    subjectAssessment,
    hasWholeItemSilhouette: value.hasWholeItemSilhouette,
    familyTaxonomySha256: value.familyTaxonomySha256 ?? null,
    expectedFamilyTaxonomySha256: value.expectedFamilyTaxonomySha256 ?? null,
  });
}

function decodeCandidate(value, index) {
  if (!isObject(value)) fail(`candidate_invalid:${index}`);
  requireText(value.canonicalType, `canonical_type_required:${index}`);
  if (typeof value.confidence !== "number" || !Number.isFinite(value.confidence) ||
      value.confidence < 0 || value.confidence > 1) {
    fail(`candidate_confidence_invalid:${index}`);
  }
  return deepFreeze({
    canonicalType: value.canonicalType,
    confidence: value.confidence,
  });
}

function decodeObservations(value) {
  requireText(value.analysisId, "analysis_id_required");
  requireText(value.modelVersion, "model_version_required");
  requireText(value.sourceReference, "source_reference_required");
  requireText(value.observedAt, "observed_at_required");
  if (!isObject(value.quality)) fail("quality_invalid");
  const observations = {
    analysisId: value.analysisId,
    modelVersion: value.modelVersion,
    sourceReference: value.sourceReference,
    observedAt: value.observedAt,
    quality: decodeQuality(value.quality),
  };
  const seen = new Set();
  for (const key of Object.keys(value)) {
    if (["analysisId", "modelVersion", "sourceReference", "observedAt",
      "quality"].includes(key)) {
      continue;
    }
    if (!OBSERVATION_PROPERTIES.includes(key)) {
      fail(`unknown_observation_property:${key}`);
    }
    if (seen.has(key)) fail(`duplicate_observation_property:${key}`);
    seen.add(key);
    observations[key] = decodeObservationValue(value[key], key);
  }
  return deepFreeze(observations);
}

function decodeObservationValue(value, path) {
  if (!isObject(value)) fail(`observation_invalid:${path}`);
  requireEnum(value.state, OBSERVATION_STATES, `observation_state_invalid:${path}`);
  if (value.state !== "observed") {
    if (Object.hasOwn(value, "value") && value.value != null) {
      fail(`non_observed_value_forbidden:${path}`);
    }
    const expectedConfidence = value.state === "not_applicable" ? 1 : 0;
    if (value.confidence !== expectedConfidence) {
      fail(`non_observed_confidence_invalid:${path}`);
    }
    if (value.state === "not_visible") {
      if (value.visibilityScope !== "not_visible") {
        fail(`not_visible_scope_invalid:${path}`);
      }
      return deepFreeze({
        state: "not_visible",
        confidence: 0,
        visibilityScope: "not_visible",
      });
    }
    if (value.visibilityScope != null) {
      fail(`non_observed_scope_forbidden:${path}`);
    }
    return deepFreeze({
      state: value.state,
      confidence: expectedConfidence,
    });
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
    requireEnum(value.visibilityScope, VISIBILITY_SCOPES,
      `visibility_scope_invalid:${path}`);
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

function decodeQuality(value) {
  const result = {};
  if (Object.hasOwn(value, "itemFullyVisible")) {
    if (typeof value.itemFullyVisible !== "boolean") {
      fail("quality_item_fully_visible_invalid");
    }
    result.itemFullyVisible = value.itemFullyVisible;
  }
  for (const key of ["backgroundInterference", "clarity"]) {
    if (Object.hasOwn(value, key)) {
      if (typeof value[key] !== "string") fail(`quality_${key}_invalid`);
      result[key] = value[key];
    }
  }
  if (Object.hasOwn(value, "occlusion")) {
    if (typeof value.occlusion !== "string") fail("quality_occlusion_invalid");
    result.occlusion = value.occlusion;
  }
  return deepFreeze(result);
}

function decodeSubject(value) {
  if (!isObject(value)) fail("subject_invalid");
  requireText(value.cardinalityState, "cardinality_required");
  requireText(value.sameItemConsistency, "same_item_required");
  requireText(value.subjectDomain, "subject_domain_required");
  requireText(value.framingClass, "framing_class_required");
  if (typeof value.primarySubjectPresent !== "boolean") {
    fail("primary_subject_invalid");
  }
  if (!Number.isInteger(value.subjectCountEstimate)) {
    fail("subject_count_invalid");
  }
  if (typeof value.permitsFamily !== "boolean") fail("permits_family_invalid");
  if (typeof value.permitsCanonical !== "boolean") {
    fail("permits_canonical_invalid");
  }
  const framingClass = value.framingClass;
  const capsFamilyAtSupported = framingClass === "partial_item";
  return deepFreeze({
    subjectCountEstimate: value.subjectCountEstimate,
    cardinalityState: value.cardinalityState,
    primarySubjectPresent: value.primarySubjectPresent,
    sameItemConsistency: value.sameItemConsistency,
    subjectDomain: value.subjectDomain,
    framingClass,
    permitsFamily: value.permitsFamily,
    permitsCanonical: value.permitsCanonical,
    capsFamilyAtSupported,
    reasonCodes: Array.isArray(value.reasonCodes) ?
      value.reasonCodes.map(String) : [],
  });
}

function decodeFamilyOracle(value) {
  if (!isObject(value)) fail("family_oracle_invalid");
  if (value.oracleVersion !== ORACLE_CONTRACT_VERSION) {
    fail("family_oracle_version_invalid");
  }
  if (value.providerId !== PROVIDER_ID) fail("family_oracle_provider_invalid");
  if (value.providerVersion !== PROVIDER_VERSION) {
    fail("family_oracle_provider_version_invalid");
  }
  if (!Array.isArray(value.invocations) || value.invocations.length !== 1) {
    fail("family_oracle_invocations_invalid");
  }
  return deepFreeze({
    scenarioId: value.scenarioId,
    invocations: value.invocations.map((item) => deepFreeze({
      invocationId: item.invocationId,
      providerInput: decodeFamilyIdentityInput(item.providerInput),
      providerOutput: item.providerOutput,
    })),
  });
}

function loadCanonicalFamilyRegistry() {
  const loaded = loadVisionCanonicalFamilyRegistryArtifact();
  return {
    canonicalToFamily: loaded.canonicalToFamily,
    familyTaxonomySha256: loaded.familyTaxonomySha256,
  };
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
  FAMILY_TAXONOMY_VERSION,
  FAMILY_WIRE,
  ORACLE_CONTRACT_VERSION,
  PROVIDER_ID,
  PROVIDER_VERSION,
  canonicalToFamily,
  decodeFamilyIdentityInput,
  decodeFamilyOracle,
  familyTaxonomySha256,
  resolveVisionFamilyIdentity,
};
