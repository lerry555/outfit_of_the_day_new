"use strict";

const {
  decodeProviderInput: decodeObservationBundle,
} = require("./vision_observation_evidence_provider");

const PROVIDER_ID = "VisionNegativeClaimCorroborator";
const PROVIDER_VERSION = "negative-claim-corroborator-v1";
const ORACLE_CONTRACT_VERSION = 1;

const PROPERTY_ORDER = Object.freeze([
  "coverage", "hasHood", "frontClosure", "visibleBulk",
  "surfaceAppearance", "necklineShape", "visiblePocketStructure",
  "visibleStretchCue", "sportyCues", "formalCues",
  "footwearConstruction", "footwearFastening", "soleProfile",
  "visibleTread", "footwearUpperHeight",
]);
const NEGATIVE_PROPERTIES = Object.freeze([
  "frontClosure", "hasHood", "visiblePocketStructure", "visibleStretchCue",
]);
const CARDINALITIES = new Set([
  "single_item_supported", "single_item_uncertain", "multiple_items",
  "fragment_only", "no_wardrobe_subject", "ambiguous_subject",
]);
const SAME_ITEM_STATES = new Set([
  "same_item_supported", "same_item_uncertain", "different_items_suspected",
  "conflicting_subjects", "not_applicable",
]);
const SUBJECT_DOMAINS = new Set([
  "garment_upper", "garment_lower", "garment_outerwear", "footwear",
  "accessory", "mixed", "unknown",
]);
const GARMENT_DOMAINS = new Set([
  "garment_upper", "garment_lower", "garment_outerwear",
]);
const UPPER_OUTER_DOMAINS = new Set(["garment_upper", "garment_outerwear"]);
const FRAMING_CLASSES = new Set([
  "full_item", "mostly_visible", "partial_item", "detail_only",
  "ambiguous_framing", "no_item",
]);
const TRUST_STATES = new Set(["attested", "downgraded", "legacyUnverified"]);
const BOUNDARIES = new Set(["top", "bottom", "left", "right"]);
const ITEM_EXTENTS = new Set(["whole", "broad", "local", "indeterminate"]);
const ORIENTATIONS = new Set(["front", "side", "back", "mixed", "unknown"]);
const REGIONS = new Set([
  "full_silhouette", "front", "back", "side", "collar", "neckline",
  "pocket_area", "surface_detail", "fastening_area", "footwear_upper",
  "outsole", "sole_profile",
]);
const OCCLUSIONS = new Set(["none", "partial", "substantial"]);

function decodeNegativeClaimInput(value) {
  if (!isObject(value)) fail("negative_claim_input_invalid");
  const bundle = decodeObservationBundle(value.bundle);
  if (!Object.hasOwn(bundle, "quality") ||
      !OCCLUSIONS.has(bundle.quality.occlusion)) {
    fail("negative_claim_quality_occlusion_invalid");
  }
  const subject = decodeSubject(value.subject);
  const framing = decodeFraming(value.framing);
  if (!Number.isInteger(value.viewCount) || value.viewCount < 0) {
    fail("negative_claim_view_count_invalid");
  }
  if (typeof value.sameItemViews !== "boolean") {
    fail("negative_claim_same_item_views_invalid");
  }
  if (!isObject(value.complementaryRegions)) {
    fail("negative_claim_complementary_regions_invalid");
  }
  const complementaryRegions = {};
  for (const [property, regions] of Object.entries(value.complementaryRegions)) {
    if (!PROPERTY_ORDER.includes(property) || !Array.isArray(regions) ||
        regions.some((region) => !REGIONS.has(region))) {
      fail(`negative_claim_complementary_region_invalid:${property}`);
    }
    complementaryRegions[property] = [...new Set(regions)].sort();
  }
  if (!Array.isArray(value.conflictingPositiveProperties) ||
      value.conflictingPositiveProperties.some((item) =>
        typeof item !== "string" || !NEGATIVE_PROPERTIES.includes(item))) {
    fail("negative_claim_conflicting_positives_invalid");
  }
  const conflictingPositiveProperties = [
    ...new Set(value.conflictingPositiveProperties),
  ].sort();
  return deepFreeze({
    bundle,
    subject,
    framing,
    viewCount: value.viewCount,
    sameItemViews: value.sameItemViews,
    complementaryRegions,
    conflictingPositiveProperties,
  });
}

function qualifyNegativeClaims(inputValue) {
  const input = decodeNegativeClaimInput(inputValue);
  const audits = {};
  const orientation = input.framing.framingEvidence == null ?
    "unknown" :
    input.framing.framingEvidence.subjectOrientation;
  const frontOrientation = orientation === "front" || orientation === "mixed";

  const frontClosure = check({
    property: "frontClosure",
    value: input.bundle.frontClosure,
    isNegative: (value) => value === "none",
    required: ["front", "fastening_area"],
    domainAllowed: UPPER_OUTER_DOMAINS.has(input.subject.subjectDomain),
    orientationAllowed: frontOrientation,
    input,
  }, audits);
  const hasHood = check({
    property: "hasHood",
    value: input.bundle.hasHood,
    isNegative: (value) => value === false,
    required: ["collar", "back"],
    domainAllowed: UPPER_OUTER_DOMAINS.has(input.subject.subjectDomain),
    orientationAllowed: orientation === "back" || orientation === "mixed",
    input,
  }, audits);
  const visiblePocketStructure = check({
    property: "visiblePocketStructure",
    value: input.bundle.visiblePocketStructure,
    isNegative: (value) => value === "none",
    required: ["front", "side", "back", "pocket_area"],
    domainAllowed: GARMENT_DOMAINS.has(input.subject.subjectDomain),
    orientationAllowed: orientation === "mixed",
    requiresMultipleViews: true,
    input,
  }, audits);
  const visibleStretchCue = check({
    property: "visibleStretchCue",
    value: input.bundle.visibleStretchCue,
    isNegative: (value) => value === false,
    required: ["surface_detail"],
    domainAllowed: true,
    orientationAllowed: true,
    visuallyConfirmable: false,
    input,
  }, audits);

  const qualifiedBundle = {
    analysisId: input.bundle.analysisId,
    modelVersion: input.bundle.modelVersion,
    sourceReference: input.bundle.sourceReference,
    observedAt: input.bundle.observedAt,
    quality: structuredClone(input.bundle.quality),
  };
  for (const property of PROPERTY_ORDER) {
    if (!Object.hasOwn(input.bundle, property)) continue;
    if (property === "frontClosure") {
      qualifiedBundle.frontClosure = frontClosure;
    } else if (property === "hasHood") {
      qualifiedBundle.hasHood = hasHood;
    } else if (property === "visiblePocketStructure") {
      qualifiedBundle.visiblePocketStructure = visiblePocketStructure;
    } else if (property === "visibleStretchCue") {
      qualifiedBundle.visibleStretchCue = visibleStretchCue;
    } else {
      qualifiedBundle[property] = structuredClone(input.bundle[property]);
    }
  }
  return deepFreeze({
    claims: audits,
    qualifiedBundle,
  });
}

function check({
  property,
  value,
  isNegative,
  required,
  domainAllowed,
  orientationAllowed,
  requiresMultipleViews = false,
  visuallyConfirmable = true,
  input,
}, audits) {
  if (value == null || value.state !== "observed" || !isNegative(value.value)) {
    return value == null ? undefined : structuredClone(value);
  }
  const covered = new Set([
    ...(value.visibleRegions || []),
    ...(input.complementaryRegions[property] || []),
  ]);
  const missing = required.filter((item) => !covered.has(item)).sort();
  const reasons = [];
  if (!domainAllowed) reasons.push("negative_claim_domain_not_applicable");
  if (!hasWholeItemSilhouette(input.framing)) {
    reasons.push("system_framing_lacks_whole_item_silhouette");
  }
  if (!orientationAllowed) {
    reasons.push("subject_orientation_cannot_assess_region");
  }
  if (missing.length) reasons.push("required_region_not_positively_visible");
  if (input.bundle.quality.occlusion !== "none") {
    reasons.push("occlusion_blocks_absence");
  }
  if (cropBlocksAbsence(input.framing)) reasons.push("crop_blocks_absence");
  if (!visuallyConfirmable) reasons.push("absence_not_visually_confirmable");
  if (requiresMultipleViews &&
      (!input.sameItemViews || input.viewCount < 2)) {
    reasons.push("complementary_same_item_views_required");
  }
  const hasPositiveConflict =
    input.conflictingPositiveProperties.includes(property);
  if (hasPositiveConflict) reasons.push("conflicting_positive_evidence");
  const corroborated = reasons.length === 0;
  audits[property] = {
    property,
    corroborationState: hasPositiveConflict ? "conflicting" :
      corroborated ? "corroborated" :
        domainAllowed ? "blocked" : "notApplicable",
    requiredRegions: [...required].sort(),
    coveredRequiredRegions: required.filter((item) => covered.has(item)).sort(),
    missingRequiredRegions: missing,
    corroboratingViews: input.viewCount,
    conflictingPositiveEvidence: hasPositiveConflict,
    reasonCodes: corroborated ?
      ["negative_claim_corroborated"] :
      [...reasons].sort(),
  };
  return corroborated ? structuredClone(value) : {state: "unknown", confidence: 0};
}

function hasWholeItemSilhouette(framing) {
  const evidence = framing.framingEvidence;
  if (evidence == null) return false;
  return evidence.localDetailOnly === false &&
    evidence.primarySilhouetteContinuous === true &&
    (evidence.visibleItemExtent === "whole" ||
      evidence.visibleItemExtent === "broad") &&
    (framing.systemAttestedFraming === "full_item" ||
      framing.systemAttestedFraming === "mostly_visible");
}

function cropBlocksAbsence(framing) {
  const evidence = framing.framingEvidence;
  if (evidence == null) return true;
  return evidence.cropIndicators.length > 0;
}

function decodeSubject(value) {
  if (!isObject(value)) fail("negative_claim_subject_invalid");
  if (!Number.isInteger(value.subjectCountEstimate) ||
      value.subjectCountEstimate < 0) {
    fail("negative_claim_subject_count_invalid");
  }
  requireEnum(value.cardinalityState, CARDINALITIES,
    "negative_claim_cardinality_invalid");
  if (typeof value.primarySubjectPresent !== "boolean") {
    fail("negative_claim_primary_subject_invalid");
  }
  requireEnum(value.sameItemConsistency, SAME_ITEM_STATES,
    "negative_claim_same_item_invalid");
  requireEnum(value.subjectDomain, SUBJECT_DOMAINS,
    "negative_claim_subject_domain_invalid");
  requireEnum(value.framingClass, FRAMING_CLASSES,
    "negative_claim_framing_class_invalid");
  if (typeof value.permitsFamily !== "boolean" ||
      typeof value.permitsCanonical !== "boolean") {
    fail("negative_claim_subject_permits_invalid");
  }
  if (!Array.isArray(value.reasonCodes) ||
      value.reasonCodes.some((item) => typeof item !== "string")) {
    fail("negative_claim_subject_reasons_invalid");
  }
  return {
    subjectCountEstimate: value.subjectCountEstimate,
    cardinalityState: value.cardinalityState,
    primarySubjectPresent: value.primarySubjectPresent,
    sameItemConsistency: value.sameItemConsistency,
    subjectDomain: value.subjectDomain,
    framingClass: value.framingClass,
    permitsFamily: value.permitsFamily,
    permitsCanonical: value.permitsCanonical,
    reasonCodes: [...value.reasonCodes],
  };
}

function decodeFraming(value) {
  if (!isObject(value)) fail("negative_claim_framing_invalid");
  requireEnum(value.modelDeclaredFraming, FRAMING_CLASSES,
    "negative_claim_model_framing_invalid");
  requireEnum(value.systemAttestedFraming, FRAMING_CLASSES,
    "negative_claim_system_framing_invalid");
  requireEnum(value.framingTrustState, TRUST_STATES,
    "negative_claim_framing_trust_invalid");
  if (!Array.isArray(value.framingContradictions) ||
      value.framingContradictions.some((item) => typeof item !== "string")) {
    fail("negative_claim_framing_contradictions_invalid");
  }
  if (!Array.isArray(value.reasonCodes) ||
      value.reasonCodes.some((item) => typeof item !== "string")) {
    fail("negative_claim_framing_reasons_invalid");
  }
  let framingEvidence = null;
  if (value.framingEvidence !== null) {
    if (!Object.hasOwn(value, "framingEvidence")) {
      fail("negative_claim_framing_evidence_omitted");
    }
    framingEvidence = decodeEvidence(value.framingEvidence);
  }
  return {
    modelDeclaredFraming: value.modelDeclaredFraming,
    systemAttestedFraming: value.systemAttestedFraming,
    framingTrustState: value.framingTrustState,
    framingEvidence,
    framingContradictions: [...value.framingContradictions],
    reasonCodes: [...value.reasonCodes],
  };
}

function decodeEvidence(value) {
  if (!isObject(value)) fail("negative_claim_framing_evidence_invalid");
  if (!Array.isArray(value.visibleBoundaries) ||
      value.visibleBoundaries.some((item) => !BOUNDARIES.has(item))) {
    fail("negative_claim_boundaries_invalid");
  }
  requireEnum(value.visibleItemExtent, ITEM_EXTENTS,
    "negative_claim_item_extent_invalid");
  if (typeof value.primarySilhouetteContinuous !== "boolean") {
    fail("negative_claim_silhouette_invalid");
  }
  requireEnum(value.subjectOrientation, ORIENTATIONS,
    "negative_claim_orientation_invalid");
  if (typeof value.localDetailOnly !== "boolean") {
    fail("negative_claim_local_detail_invalid");
  }
  if (!Array.isArray(value.cropIndicators) ||
      value.cropIndicators.some((item) => typeof item !== "string")) {
    fail("negative_claim_crop_indicators_invalid");
  }
  return {
    visibleBoundaries: [...value.visibleBoundaries].sort(),
    visibleItemExtent: value.visibleItemExtent,
    primarySilhouetteContinuous: value.primarySilhouetteContinuous,
    subjectOrientation: value.subjectOrientation,
    localDetailOnly: value.localDetailOnly,
    cropIndicators: [...value.cropIndicators].sort(),
  };
}

function decodeNegativeClaimOracle(value) {
  if (!isObject(value)) fail("negative_claim_oracle_invalid");
  if (value.oracleVersion !== ORACLE_CONTRACT_VERSION ||
      value.providerId !== PROVIDER_ID ||
      value.providerVersion !== PROVIDER_VERSION) {
    fail("negative_claim_oracle_identity_invalid");
  }
  if (!Array.isArray(value.invocations) || !value.invocations.length) {
    fail("negative_claim_oracle_invocations_invalid");
  }
  const ids = new Set();
  const invocations = value.invocations.map((item, index) => {
    if (!isObject(item)) fail("negative_claim_invocation_invalid");
    if (typeof item.invocationId !== "string" || !item.invocationId) {
      fail("negative_claim_invocation_id_invalid");
    }
    if (ids.has(item.invocationId)) fail("negative_claim_invocation_id_duplicate");
    ids.add(item.invocationId);
    if (!Number.isInteger(item.viewIndex) || item.viewIndex !== index) {
      fail("negative_claim_view_index_invalid");
    }
    return {
      invocationId: item.invocationId,
      viewIndex: item.viewIndex,
      viewId: item.viewId,
      assetSha256: item.assetSha256,
      providerInput: decodeNegativeClaimInput(item.providerInput),
      providerInputSha256: item.providerInputSha256,
      providerOutput: item.providerOutput,
      providerOutputSha256: item.providerOutputSha256,
    };
  });
  return deepFreeze({
    oracleVersion: value.oracleVersion,
    providerId: value.providerId,
    providerVersion: value.providerVersion,
    scenarioId: value.scenarioId,
    invocations,
  });
}

function requireEnum(value, allowed, code) {
  if (!allowed.has(value)) fail(code);
}
function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}
function fail(code) {
  throw new Error(code);
}
function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    Object.values(value).forEach(deepFreeze);
  }
  return value;
}

module.exports = {
  PROVIDER_ID,
  PROVIDER_VERSION,
  ORACLE_CONTRACT_VERSION,
  decodeNegativeClaimInput,
  decodeNegativeClaimOracle,
  qualifyNegativeClaims,
};
