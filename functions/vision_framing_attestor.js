"use strict";

const PROVIDER_ID = "VisionFramingAttestor";
const PROVIDER_VERSION = "framing-attestor-v1";
const ORACLE_CONTRACT_VERSION = 1;

const INPUT_ASSESSMENTS = new Set([
  "valid_single_item",
  "multiple_items",
  "insufficient_visual_information",
  "non_wardrobe_object",
  "ambiguous_subject",
]);
const CARDINALITIES = new Set([
  "single_item_supported",
  "single_item_uncertain",
  "multiple_items",
  "fragment_only",
  "no_wardrobe_subject",
  "ambiguous_subject",
]);
const SAME_ITEM_STATES = new Set([
  "same_item_supported",
  "same_item_uncertain",
  "different_items_suspected",
  "conflicting_subjects",
  "not_applicable",
]);
const SUBJECT_DOMAINS = new Set([
  "garment_upper",
  "garment_lower",
  "garment_outerwear",
  "footwear",
  "accessory",
  "mixed",
  "unknown",
]);
const FRAMING_CLASSES = new Set([
  "full_item",
  "mostly_visible",
  "partial_item",
  "detail_only",
  "ambiguous_framing",
  "no_item",
]);
const BOUNDARIES = new Set(["top", "bottom", "left", "right"]);
const ITEM_EXTENTS = new Set(["whole", "broad", "local", "indeterminate"]);
const ORIENTATIONS = new Set(["front", "side", "back", "mixed", "unknown"]);
const QUALITY_LEVELS = new Set(["low", "medium", "high"]);
const OCCLUSIONS = new Set(["none", "partial", "substantial"]);

function decodeFramingInput(value) {
  if (!isObject(value)) fail("framing_input_invalid");
  requireEnum(value.inputAssessment, INPUT_ASSESSMENTS,
    "input_assessment_invalid");
  const subject = decodeSubject(value.subject);
  const quality = decodeQuality(value.quality);
  let attestations = null;
  if (value.attestations !== null) {
    if (!Object.hasOwn(value, "attestations")) {
      fail("attestations_omitted");
    }
    attestations = decodeAttestations(value.attestations);
  }
  return deepFreeze({
    inputAssessment: value.inputAssessment,
    subject,
    quality,
    attestations,
  });
}

function attestFraming(inputValue) {
  const input = decodeFramingInput(inputValue);
  const {subject, quality, attestations} = input;
  if (attestations === null) {
    return deepFreeze({
      modelDeclaredFraming: subject.framingClass,
      systemAttestedFraming: subject.framingClass,
      framingTrustState: "legacyUnverified",
      framingEvidence: null,
      framingContradictions: [],
      reasonCodes: ["legacy_schema_without_framing_attestations"],
    });
  }
  const contradictions = [];
  const reasons = [];
  const validSubject =
    input.inputAssessment === "valid_single_item" &&
    subject.cardinalityState === "single_item_supported" &&
    subject.primarySubjectPresent &&
    !["unknown", "mixed"].includes(subject.subjectDomain);
  let framing;
  if (!validSubject) {
    framing = subject.primarySubjectPresent ?
      "ambiguous_framing" : "no_item";
    contradictions.push("input_or_subject_rejects_whole_item_framing");
  } else if (attestations.localDetailOnly ||
      attestations.visibleItemExtent === "local") {
    framing = "detail_only";
    if (subject.framingClass !== "detail_only") {
      contradictions.push("local_detail_contradicts_declared_framing");
    }
  } else if (!attestations.primarySilhouetteContinuous ||
      attestations.visibleItemExtent === "indeterminate") {
    framing = "partial_item";
    contradictions.push("silhouette_not_continuous_or_indeterminate");
  } else {
    const top = attestations.visibleBoundaries.includes("top");
    const bottom = attestations.visibleBoundaries.includes("bottom");
    const severeCrop = attestations.cropIndicators.includes("severe_crop");
    if (severeCrop) {
      framing = "partial_item";
      contradictions.push("severe_crop");
    } else if (quality.itemFullyVisible === true &&
        top && bottom &&
        attestations.visibleItemExtent === "whole" &&
        attestations.cropIndicators.length === 0) {
      framing = "full_item";
    } else if (attestations.visibleItemExtent === "broad" ||
        (attestations.visibleItemExtent === "whole" && (top || bottom))) {
      framing = "mostly_visible";
      if (!top || !bottom) {
        contradictions.push("whole_item_boundary_missing");
      }
      if (quality.itemFullyVisible === false) {
        contradictions.push("item_not_fully_visible");
      }
    } else {
      framing = "partial_item";
    }
  }
  if (framingRank(framing) > framingRank(subject.framingClass)) {
    framing = subject.framingClass;
    reasons.push("conservative_model_framing_not_auto_promoted");
  }
  if (subject.framingClass === "full_item" && framing !== "full_item") {
    reasons.push("model_full_item_downgraded");
  }
  reasons.push(
    framing === "full_item" ?
      "whole_item_attestations_consistent" :
      framing === "mostly_visible" ?
        "broad_silhouette_attested" :
        framing === "detail_only" ?
          "local_detail_only" :
          "whole_item_attestations_insufficient",
  );
  contradictions.sort();
  reasons.sort();
  return deepFreeze({
    modelDeclaredFraming: subject.framingClass,
    systemAttestedFraming: framing,
    framingTrustState:
      framing === subject.framingClass ? "attested" : "downgraded",
    framingEvidence: structuredClone(attestations),
    framingContradictions: contradictions,
    reasonCodes: reasons,
  });
}

function decodeFramingOracle(value) {
  if (!isObject(value)) fail("framing_oracle_invalid");
  if (value.oracleContractVersion !== ORACLE_CONTRACT_VERSION) {
    fail("framing_oracle_contract_unsupported");
  }
  if (value.providerId !== PROVIDER_ID) fail("framing_provider_id_invalid");
  if (value.providerVersion !== PROVIDER_VERSION) {
    fail("framing_provider_version_invalid");
  }
  requireText(value.scenarioId, "framing_scenario_id_required");
  if (!Array.isArray(value.invocations) || value.invocations.length === 0) {
    fail("framing_invocations_invalid");
  }
  const invocations = value.invocations.map((item, index) => {
    if (!isObject(item) || item.viewIndex !== index) {
      fail(`framing_invocation_order_invalid:${index}`);
    }
    requireText(item.viewId, `framing_view_id_required:${index}`);
    requireSha(item.assetSha256, `framing_asset_sha_invalid:${index}`);
    requireSha(item.providerInputSha256,
      `framing_input_sha_invalid:${index}`);
    requireSha(item.providerOutputSha256,
      `framing_output_sha_invalid:${index}`);
    if (!isObject(item.providerOutput)) {
      fail(`framing_output_invalid:${index}`);
    }
    return {
      viewIndex: item.viewIndex,
      viewId: item.viewId,
      assetSha256: item.assetSha256,
      providerInput: decodeFramingInput(item.providerInput),
      providerInputSha256: item.providerInputSha256,
      providerOutput: structuredClone(item.providerOutput),
      providerOutputSha256: item.providerOutputSha256,
    };
  });
  return deepFreeze({
    scenarioId: value.scenarioId,
    sourceParserFixtureSha256: requireSha(
      value.sourceParserFixtureSha256, "framing_parser_sha_invalid"),
    sourceQualificationInputSha256: requireSha(
      value.sourceQualificationInputSha256, "framing_input_source_sha_invalid"),
    sourceDartReferenceGoldenSha256: requireSha(
      value.sourceDartReferenceGoldenSha256,
      "framing_golden_sha_invalid"),
    invocations,
  });
}

function decodeSubject(value) {
  if (!isObject(value)) fail("framing_subject_invalid");
  if (!Number.isInteger(value.subjectCountEstimate) ||
      value.subjectCountEstimate < 0 || value.subjectCountEstimate > 3) {
    fail("framing_subject_count_invalid");
  }
  requireEnum(value.cardinalityState, CARDINALITIES,
    "framing_cardinality_invalid");
  if (typeof value.primarySubjectPresent !== "boolean") {
    fail("framing_primary_subject_invalid");
  }
  requireEnum(value.sameItemConsistency, SAME_ITEM_STATES,
    "framing_same_item_invalid");
  requireEnum(value.subjectDomain, SUBJECT_DOMAINS,
    "framing_subject_domain_invalid");
  requireEnum(value.framingClass, FRAMING_CLASSES,
    "framing_class_invalid");
  if (!Array.isArray(value.reasonCodes) ||
      !value.reasonCodes.every((item) => typeof item === "string")) {
    fail("framing_subject_reasons_invalid");
  }
  return {
    subjectCountEstimate: value.subjectCountEstimate,
    cardinalityState: value.cardinalityState,
    primarySubjectPresent: value.primarySubjectPresent,
    sameItemConsistency: value.sameItemConsistency,
    subjectDomain: value.subjectDomain,
    framingClass: value.framingClass,
    reasonCodes: [...value.reasonCodes],
  };
}

function decodeQuality(value) {
  if (!isObject(value)) fail("framing_quality_invalid");
  const result = {};
  if (Object.hasOwn(value, "itemFullyVisible")) {
    if (typeof value.itemFullyVisible !== "boolean") {
      fail("framing_quality_visibility_invalid");
    }
    result.itemFullyVisible = value.itemFullyVisible;
  }
  if (Object.hasOwn(value, "occlusion")) {
    requireEnum(value.occlusion, OCCLUSIONS,
      "framing_quality_occlusion_invalid");
    result.occlusion = value.occlusion;
  }
  for (const key of ["backgroundInterference", "clarity"]) {
    if (!Object.hasOwn(value, key)) continue;
    requireEnum(value[key], QUALITY_LEVELS, `framing_quality_${key}_invalid`);
    result[key] = value[key];
  }
  return result;
}

function decodeAttestations(value) {
  if (!isObject(value)) fail("framing_attestations_invalid");
  if (!Array.isArray(value.visibleBoundaries) ||
      !value.visibleBoundaries.every((item) => BOUNDARIES.has(item)) ||
      new Set(value.visibleBoundaries).size !== value.visibleBoundaries.length) {
    fail("framing_boundaries_invalid");
  }
  if (typeof value.primarySilhouetteContinuous !== "boolean" ||
      typeof value.localDetailOnly !== "boolean") {
    fail("framing_attestation_boolean_invalid");
  }
  requireEnum(value.visibleItemExtent, ITEM_EXTENTS,
    "framing_extent_invalid");
  if (!Array.isArray(value.cropIndicators) ||
      !value.cropIndicators.every((item) => typeof item === "string") ||
      new Set(value.cropIndicators).size !== value.cropIndicators.length) {
    fail("framing_crop_indicators_invalid");
  }
  requireEnum(value.subjectOrientation, ORIENTATIONS,
    "framing_orientation_invalid");
  return {
    visibleBoundaries: [...value.visibleBoundaries].sort(),
    primarySilhouetteContinuous: value.primarySilhouetteContinuous,
    visibleItemExtent: value.visibleItemExtent,
    localDetailOnly: value.localDetailOnly,
    cropIndicators: [...value.cropIndicators].sort(),
    subjectOrientation: value.subjectOrientation,
  };
}

function framingRank(value) {
  switch (value) {
    case "full_item": return 4;
    case "mostly_visible": return 3;
    case "partial_item": return 2;
    case "detail_only": return 1;
    case "ambiguous_framing":
    case "no_item": return 0;
    default: fail("framing_rank_unreachable");
  }
}
function requireEnum(value, values, reason) {
  if (typeof value !== "string" || !values.has(value)) fail(reason);
}
function requireText(value, reason) {
  if (typeof value !== "string" || !value.trim()) fail(reason);
  return value;
}
function requireSha(value, reason) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) fail(reason);
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
  ORACLE_CONTRACT_VERSION,
  PROVIDER_ID,
  PROVIDER_VERSION,
  attestFraming,
  decodeFramingInput,
  decodeFramingOracle,
};
