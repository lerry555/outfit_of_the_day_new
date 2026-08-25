"use strict";

const {
  decodeProviderInput: decodeObservationBundle,
} = require("./vision_observation_evidence_provider");

const PROVIDER_ID = "VisionVisibilityTrustQualifier";
const PROVIDER_VERSION = "visibility-trust-v1";
const ORACLE_CONTRACT_VERSION = 1;
const PROPERTY_ORDER = Object.freeze([
  "coverage", "hasHood", "frontClosure", "visibleBulk",
  "surfaceAppearance", "necklineShape", "visiblePocketStructure",
  "visibleStretchCue", "sportyCues", "formalCues",
  "footwearConstruction", "footwearFastening", "soleProfile",
  "visibleTread", "footwearUpperHeight",
]);
const INPUT_ASSESSMENTS = new Set([
  "valid_single_item", "multiple_items", "insufficient_visual_information",
  "non_wardrobe_object", "ambiguous_subject",
]);
const SCOPES = new Set(["complete", "sufficient", "partial", "not_visible"]);
const REGIONS = new Set([
  "full_silhouette", "front", "back", "side", "collar", "neckline",
  "pocket_area", "surface_detail", "fastening_area", "footwear_upper",
  "outsole", "sole_profile",
]);
const REQUIREMENTS = Object.freeze({
  visiblePocketStructure: requirement(
    ["pocket_area", "front", "side", "back"],
    ["front", "side", "pocket_area"], "sufficient", "complete", true, true, 0.9),
  hasHood: requirement(
    ["collar", "back"], ["collar", "back"],
    "sufficient", "sufficient", false, true, 0.9),
  frontClosure: requirement(
    ["front"], ["front"], "sufficient", "sufficient", false, true, 0.9),
  visibleStretchCue: requirement(
    ["surface_detail", "side"], [], "sufficient", "complete", false, false, 0.85),
  necklineShape: requirement(
    ["neckline"], [], "sufficient", "complete"),
  footwearFastening: requirement(
    ["fastening_area", "footwear_upper"], [], "sufficient", "complete"),
  visibleTread: requirement(
    ["outsole"], [], "sufficient", "complete"),
  visibleBulk: requirement(
    ["full_silhouette", "side"], [], "sufficient", "complete", false, true, 0.9),
  coverage: requirement(
    ["full_silhouette"], [], "sufficient", "complete"),
  footwearUpperHeight: requirement(
    ["footwear_upper", "side"], [], "sufficient", "complete"),
  footwearConstruction: requirement(
    ["footwear_upper"], [], "sufficient", "complete"),
  soleProfile: requirement(
    ["sole_profile", "side"], [], "sufficient", "complete"),
});

function decodeVisibilityInput(value) {
  if (!isObject(value)) fail("visibility_input_invalid");
  const bundle = decodeObservationBundle(value.bundle);
  if (!INPUT_ASSESSMENTS.has(value.inputAssessment)) {
    fail("visibility_input_assessment_invalid");
  }
  if (!Number.isInteger(value.viewCount) || value.viewCount < 0) {
    fail("visibility_view_count_invalid");
  }
  if (!isObject(value.complementaryRegions)) {
    fail("visibility_complementary_regions_invalid");
  }
  const complementaryRegions = {};
  for (const [property, regions] of Object.entries(value.complementaryRegions)) {
    if (!PROPERTY_ORDER.includes(property) || !Array.isArray(regions) ||
        regions.some((region) => !REGIONS.has(region))) {
      fail(`visibility_complementary_region_invalid:${property}`);
    }
    complementaryRegions[property] = [...new Set(regions)].sort();
  }
  return deepFreeze({
    bundle,
    inputAssessment: value.inputAssessment,
    viewCount: value.viewCount,
    complementaryRegions,
  });
}

function qualifyVisibility(inputValue) {
  const input = decodeVisibilityInput(inputValue);
  const qualifiedBundle = {
    analysisId: input.bundle.analysisId,
    modelVersion: input.bundle.modelVersion,
    sourceReference: input.bundle.sourceReference,
    observedAt: input.bundle.observedAt,
    quality: structuredClone(input.bundle.quality),
  };
  const properties = {};
  for (const property of PROPERTY_ORDER) {
    if (!Object.hasOwn(input.bundle, property)) continue;
    const result = qualifyProperty(
      property, input.bundle[property], input.bundle.quality,
      input.inputAssessment, input.viewCount,
      input.complementaryRegions[property] || []);
    qualifiedBundle[property] = result.observation;
    properties[property] = result.report;
  }
  return deepFreeze({
    qualifiedBundle,
    inputAssessment: input.inputAssessment,
    properties,
  });
}

function qualifyProperty(property, raw, quality, assessment, viewCount,
    complementaryRegions) {
  const declared = raw.visibilityScope ||
    (raw.state === "not_visible" ? "not_visible" : "partial");
  if (assessment !== "valid_single_item") {
    return {
      observation: raw.state === "not_applicable" ?
        {state: "not_applicable", confidence: 1} :
        {state: "unknown", confidence: 0},
      report: report(property, raw.visibilityScope, "not_visible", "rejected",
        raw.visibleRegions || [], [], "contradicted",
        ["invalid_input_visibility_rejected"]),
    };
  }
  const requirement = REQUIREMENTS[property];
  if (raw.state !== "observed" || !requirement) {
    return {
      observation: structuredClone(raw),
      report: report(property, raw.visibilityScope, declared,
        raw.state === "observed" ? "unverified" : "supported",
        raw.visibleRegions || [], [],
        raw.visibilityScope === "not_visible" ? "contradicted" : "undeclared",
        [raw.state === "observed" ?
          "no_property_visibility_requirement" :
          "non_observed_state_preserved"]),
    };
  }
  const absence = isAbsence(property, raw.value);
  const requiredRegions = absence ?
    requirement.requiredAbsenceRegions : requirement.requiredPositiveRegions;
  const rawRegions = raw.visibleRegions || [];
  const impliedRegions = absence || rawRegions.length > 0 ?
    [] : impliedPositiveRegions(property, raw.value);
  const effectiveRegions = new Set([
    ...rawRegions, ...complementaryRegions, ...impliedRegions,
  ]);
  const hasRegions = requiredRegions.length === 0 ? !absence :
    absence ? requiredRegions.every((item) => effectiveRegions.has(item)) :
      requiredRegions.some((item) => effectiveRegions.has(item));
  let qualifiedScope = declared;
  let trust = "trusted";
  let declarationState = raw.visibilityScope === "not_visible" ?
    "contradicted" :
    rawRegions.some((item) => requiredRegions.includes(item)) ?
      "explicitlyVisible" :
      impliedRegions.length > 0 ? "impliedByPositiveObservation" : "undeclared";
  const reasons = [];
  if (raw.visibilityScope === "not_visible") {
    qualifiedScope = "not_visible";
    trust = "rejected";
    reasons.push("declared_not_visible");
  } else if (rawRegions.length === 0 && impliedRegions.length === 0) {
    qualifiedScope = "partial";
    trust = "unverified";
    reasons.push("no_declared_relevant_regions");
  } else if (!hasRegions) {
    qualifiedScope = "partial";
    trust = "rejected";
    reasons.push("required_region_not_declared");
  } else if (impliedRegions.length > 0 &&
      !rawRegions.some((item) => requiredRegions.includes(item))) {
    if (scopeRank(qualifiedScope) < scopeRank("sufficient")) {
      qualifiedScope = "sufficient";
    }
    trust = "supported";
    reasons.push("positive_observation_implies_region");
  }
  if (quality.itemFullyVisible === false && qualifiedScope === "complete") {
    qualifiedScope = "sufficient";
    trust = "supported";
    reasons.push("cropped_item_downgraded_complete");
  }
  if (quality.occlusion === "substantial" || quality.clarity === "low" ||
      quality.backgroundInterference === "high") {
    qualifiedScope = "partial";
    trust = "unverified";
    reasons.push("image_quality_limits_visibility");
  }
  if (absence && !requirement.absenceCanBeObserved) {
    qualifiedScope = "partial";
    trust = "rejected";
    reasons.push("absence_not_visually_provable");
  }
  if (absence && requirement.absenceRequiresMultipleViews && viewCount < 2) {
    qualifiedScope = "partial";
    trust = "unverified";
    reasons.push("absence_requires_complementary_views");
  }
  const minimum = absence ?
    requirement.minimumAbsenceScope : requirement.minimumPositiveScope;
  if (scopeRank(qualifiedScope) < scopeRank(minimum)) {
    reasons.push("qualified_scope_below_property_minimum");
  }
  const usable = trust !== "rejected" &&
    scopeRank(qualifiedScope) >= scopeRank(minimum);
  const confidence = Math.min(raw.confidence,
    requirement.maximumTrustedConfidence);
  const observation = usable ? {
    state: "observed",
    value: structuredClone(raw.value),
    confidence,
    visibilityScope: qualifiedScope,
    visibleRegions: [...new Set([...rawRegions, ...impliedRegions])].sort(),
  } : {state: "unknown", confidence: 0};
  if (reasons.length === 0) {
    reasons.push("declared_scope_and_regions_supported");
  }
  if (confidence < raw.confidence) {
    reasons.push("visibility_confidence_calibrated");
  }
  return {
    observation,
    report: report(property, raw.visibilityScope, qualifiedScope, trust,
      rawRegions, impliedRegions, declarationState, reasons),
  };
}

function decodeVisibilityOracle(value) {
  if (!isObject(value) ||
      value.oracleContractVersion !== ORACLE_CONTRACT_VERSION ||
      value.providerId !== PROVIDER_ID ||
      value.providerVersion !== PROVIDER_VERSION ||
      typeof value.scenarioId !== "string" ||
      !Array.isArray(value.invocations) || value.invocations.length === 0) {
    fail("visibility_oracle_invalid");
  }
  return deepFreeze({
    scenarioId: value.scenarioId,
    invocations: value.invocations.map((item, index) => {
      if (!isObject(item) || item.viewIndex !== index ||
          typeof item.viewId !== "string" || !isObject(item.providerOutput)) {
        fail(`visibility_invocation_invalid:${index}`);
      }
      return {
        viewIndex: item.viewIndex,
        viewId: item.viewId,
        providerInput: decodeVisibilityInput(item.providerInput),
        providerOutput: structuredClone(item.providerOutput),
      };
    }),
  });
}

function requirement(positive, absence, minimumPositiveScope,
    minimumAbsenceScope, absenceRequiresMultipleViews = false,
    absenceCanBeObserved = true, maximumTrustedConfidence = 0.95) {
  return Object.freeze({
    requiredPositiveRegions: Object.freeze(positive),
    requiredAbsenceRegions: Object.freeze(absence),
    minimumPositiveScope,
    minimumAbsenceScope,
    absenceRequiresMultipleViews,
    absenceCanBeObserved,
    maximumTrustedConfidence,
  });
}
function isAbsence(property, value) {
  return (property === "hasHood" || property === "visibleStretchCue") ?
    value === false :
    (property === "frontClosure" ||
      property === "visiblePocketStructure") ? value === "none" : false;
}
function impliedPositiveRegions(property, value) {
  if (property === "hasHood" && value === true) return ["collar"];
  if (property === "frontClosure" && value !== "none") return ["front"];
  if (property === "visiblePocketStructure" && value !== "none") {
    return ["pocket_area"];
  }
  if (property === "visibleStretchCue" && value === true) {
    return ["surface_detail"];
  }
  return {
    necklineShape: ["neckline"],
    footwearFastening: ["fastening_area"],
    visibleTread: ["outsole"],
    footwearUpperHeight: ["footwear_upper"],
    footwearConstruction: ["footwear_upper"],
    soleProfile: ["sole_profile"],
  }[property] || [];
}
function report(property, modelScope, systemScope, trust, modelRegions,
    impliedRegions, declarationState, reasonCodes) {
  return {
    property,
    modelDeclaredVisibilityScope: modelScope ?? null,
    systemQualifiedVisibilityScope: systemScope,
    visibilityTrust: trust,
    modelDeclaredRegions: [...modelRegions].sort(),
    impliedRegions: [...impliedRegions].sort(),
    regionDeclarationState: declarationState,
    reasonCodes,
  };
}
function scopeRank(scope) {
  if (!SCOPES.has(scope)) fail("visibility_scope_invalid");
  return {complete: 3, sufficient: 2, partial: 1, not_visible: 0}[scope];
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
  PROPERTY_ORDER,
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeVisibilityInput,
  decodeVisibilityOracle,
  qualifyVisibility,
};
