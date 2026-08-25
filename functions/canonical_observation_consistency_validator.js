"use strict";

const PROVIDER_ID = "CanonicalObservationConsistencyValidator";
const PROVIDER_VERSION = "canonical-consistency-v1";
const ORACLE_CONTRACT_VERSION = 1;
const ALLOWED_SOURCES = new Set([
  "user_correction", "verified_product_metadata", "label_metadata",
  "visual_observation",
]);
const cue = (property, compatible, incompatible, needed, strong = false) =>
  Object.freeze({property, compatible: new Set(compatible),
    incompatible: new Set(incompatible), needed, weight: strong ? 2 : 1,
    strong});
const signature = (types, cues, minimumDefiningSupports = 0) =>
  Object.freeze({types, cues, minimumDefiningSupports});
const C = "visual.coverage";
const O = "visual.observations.";
const SIGNATURES = [
  signature(["hoodie"], [
    cue(`${O}hasHood`, [true], [false], "show_hood_area", true),
    cue(`${O}frontClosure`, ["none", "partial_zip", "full_zip"],
      ["buttons", "snaps"], "show_front_closure"),
    cue(`${O}sportyCues`, ["medium", "high"], [], "clear_full_item_image"),
  ]),
  signature(["zip_hoodie"], [
    cue(`${O}hasHood`, [true], [false], "show_hood_area", true),
    cue(`${O}frontClosure`, ["full_zip"], ["none", "buttons", "snaps"],
      "show_front_closure", true),
    cue(`${O}sportyCues`, ["medium", "high"], [], "clear_full_item_image"),
  ]),
  signature(["sweater", "knit_sweater"], [
    cue(`${O}surfaceAppearance`, ["knit"], ["smooth", "mesh", "leather_like"],
      "close_surface_image", true),
    cue(`${O}hasHood`, [false], [true], "show_hood_area", true),
    cue(`${O}frontClosure`, ["none"], ["full_zip"], "show_front_closure", true),
  ]),
  signature(["crewneck_sweatshirt", "sweatshirt"], [
    cue(`${O}hasHood`, [false], [true], "show_hood_area", true),
    cue(`${O}frontClosure`, ["none"], ["full_zip", "buttons"],
      "show_front_closure"),
    cue(`${O}surfaceAppearance`, ["fleece_like", "smooth", "textured"],
      ["leather_like"], "close_surface_image"),
  ]),
  signature(["softshell", "light_jacket"], [
    cue(`${O}frontClosure`, ["full_zip", "snaps"], ["none"],
      "show_front_closure"),
    cue(`${O}visibleBulk`, ["low", "medium"], ["high"],
      "full_side_profile_image", true),
    cue(`${O}surfaceAppearance`, ["smooth", "woven"],
      ["quilted", "fleece_like"], "close_surface_image"),
  ]),
  signature(["puffer_jacket"], [
    cue(`${O}visibleBulk`, ["high"], ["low"], "full_side_profile_image", true),
    cue(`${O}surfaceAppearance`, ["quilted"], ["mesh"],
      "close_surface_image", true),
    cue(C, ["full"], ["minimal"], "full_item_image"),
  ], 2),
  signature(["winter_jacket"], [
    cue(`${O}visibleBulk`, ["medium", "high"], ["low"],
      "full_side_profile_image", true),
    cue(`${O}surfaceAppearance`, ["quilted", "smooth", "woven"], ["mesh"],
      "close_surface_image"),
    cue(C, ["full"], ["minimal"], "full_item_image"),
  ]),
  signature(["t_shirt"], [
    cue(`${O}visibleBulk`, ["low"], ["high"], "full_side_profile_image"),
    cue(`${O}hasHood`, [false], [true], "show_hood_area"),
    cue(`${O}frontClosure`, ["none"], ["full_zip"], "show_front_closure"),
    cue(`${O}necklineShape`, ["crew", "scoop"], ["high_neck", "collared"],
      "clear_neckline_image"),
  ]),
  signature(["v_neck_t_shirt"], [
    cue(`${O}necklineShape`, ["v_neck"], ["crew", "high_neck", "collared"],
      "clear_neckline_image", true),
    cue(`${O}visibleBulk`, ["low"], ["high"], "full_side_profile_image"),
    cue(`${O}frontClosure`, ["none"], ["full_zip", "buttons"],
      "show_front_closure"),
  ], 1),
  signature(["tank_top"], [
    cue(C, ["minimal"], ["full"], "full_item_image", true),
    cue(`${O}visibleBulk`, ["low"], ["high"], "full_side_profile_image"),
  ]),
  signature(["shorts"], [
    cue(C, ["minimal", "partial"], ["full"], "full_garment_shape_image", true),
  ], 1),
  signature(["cargo_shorts"], [
    cue(C, ["minimal", "partial"], ["full"], "full_garment_shape_image", true),
    cue(`${O}visiblePocketStructure`, ["cargo"], ["none", "standard"],
      "clear_side_pocket_image", true),
  ], 2),
  signature(["jeans", "slim_jeans", "straight_jeans", "skinny_jeans"], [
    cue(C, ["full"], ["minimal"], "full_item_image"),
    cue(`${O}surfaceAppearance`, ["woven", "textured"], ["mesh", "quilted"],
      "close_surface_image"),
  ]),
  signature(["chinos", "corduroy_pants"], [
    cue(C, ["full"], ["minimal"], "full_item_image"),
    cue(`${O}formalCues`, ["medium", "high"], ["low"],
      "clear_full_item_image"),
    cue(`${O}sportyCues`, ["low"], ["high"], "clear_full_item_image"),
  ], 1),
  signature(["cargo_pants"], [
    cue(`${O}visiblePocketStructure`, ["cargo"], ["none", "standard"],
      "clear_side_pocket_image", true),
    cue(C, ["full"], ["minimal"], "full_item_image"),
    cue(`${O}sportyCues`, ["medium", "high"], ["low"],
      "clear_full_item_image"),
    cue(`${O}formalCues`, ["low"], ["high"], "clear_full_item_image"),
  ], 1),
  signature(["suit_trousers"], [
    cue(C, ["full"], ["minimal"], "full_item_image"),
    cue(`${O}formalCues`, ["high"], ["low"], "clear_full_item_image", true),
    cue(`${O}sportyCues`, ["low"], ["high"], "clear_full_item_image", true),
  ]),
  signature(["sneakers"], [
    cue(`${O}footwearConstruction`, ["closed"], ["open"],
      "full_footwear_image"),
    cue(`${O}footwearUpperHeight`, ["low_cut"], ["high_shaft"],
      "side_footwear_image"),
  ]),
  signature(["running_shoes"], [
    cue(`${O}footwearUpperHeight`, ["low_cut"], ["high_shaft"],
      "side_footwear_image"),
    cue(`${O}sportyCues`, ["high"], ["low"], "clear_full_footwear_image"),
    cue(`${O}surfaceAppearance`, ["mesh"], ["leather_like"],
      "clear_footwear_upper_image", true),
    cue(`${O}soleProfile`, ["standard", "chunky"], ["thin"],
      "clear_side_sole_image", true),
    cue(`${O}footwearConstruction`, ["closed"], ["open"],
      "full_footwear_image"),
  ], 2),
  signature(["hiking_shoes"], [
    cue(`${O}visibleTread`, ["pronounced"], ["low"], "sole_photo", true),
    cue(`${O}sportyCues`, ["high"], ["low"], "clear_full_footwear_image", true),
    cue(`${O}footwearConstruction`, ["closed"], ["open"],
      "full_footwear_image"),
  ]),
  signature(["boots"], [
    cue(`${O}footwearUpperHeight`, ["ankle"], ["low_cut"],
      "side_footwear_image", true),
    cue(`${O}visibleTread`, ["low", "moderate"], ["pronounced"], "sole_photo"),
    cue(`${O}formalCues`, ["medium", "high"], ["low"],
      "clear_full_footwear_image"),
  ]),
  signature(["chelsea_boots"], [
    cue(`${O}footwearUpperHeight`, ["ankle"], ["low_cut", "high_shaft"],
      "side_footwear_image", true),
    cue(`${O}footwearFastening`, ["elastic_side_panels"], ["laces", "straps"],
      "clear_side_footwear_image", true),
    cue(`${O}formalCues`, ["medium", "high"], ["low"],
      "clear_full_footwear_image"),
  ], 2),
  signature(["winter_boots"], [
    cue(`${O}footwearUpperHeight`, ["ankle", "high_shaft"], ["low_cut"],
      "side_footwear_image", true),
    cue(`${O}visibleBulk`, ["high"], ["low"], "full_side_profile_image", true),
  ]),
];
const REGISTRY = new Map(SIGNATURES.flatMap((item) =>
  item.types.map((type) => [type, item])));

function decodeCanonicalConsistencyInput(value) {
  if (!isObject(value) || !Array.isArray(value.identityEvidence) ||
      !Array.isArray(value.observationEvidence)) {
    fail("canonical_consistency_input_invalid");
  }
  return deepFreeze({
    identityEvidence: value.identityEvidence.map(decodeEvidence),
    observationEvidence: value.observationEvidence.map(decodeEvidence),
  });
}

function validateCanonicalConsistency(inputValue) {
  const input = decodeCanonicalConsistencyInput(inputValue);
  const facts = buildFacts(input.observationEvidence);
  const candidates = input.identityEvidence.filter((item) =>
    item.active && item.property === "identity.canonicalType" &&
    item.valueState === "known" && typeof item.value === "string" &&
    item.value.trim()).sort(compareIdentity);
  const results = candidates.map((item) => validateCandidate(item, facts));
  const canonicalTypes = [...new Set(
    results.map((item) => item.candidateCanonicalType))].sort();
  const neededEvidence = [...new Set(
    results.flatMap((item) => item.neededEvidence))].sort();
  return deepFreeze({
    results,
    identityConflict: results.some((item) =>
      item.compatibilityLevel === "conflicting") ||
      hasCompetingIdentityConflict(results),
    candidateGap: candidateGap(results),
    competingCanonicalTypes: canonicalTypes,
    decisionRelevantDifferences: decisionRelevantDifferences(results),
    neededEvidence,
  });
}

function validateCandidate(identity, facts) {
  const canonical = identity.value.trim().toLowerCase();
  const sig = REGISTRY.get(canonical);
  if (!sig) {
    return result(identity, canonical, "uncertain", 0, [], [], [], [], 
      ["signature.unavailable"], ["signature.unavailable"],
      ["signature_not_covered", "missing_signature_coverage"],
      ["supported_signature_or_verified_model"]);
  }
  let supportScore = 0;
  let conflictScore = 0;
  let strongConflict = false;
  let observationConflict = false;
  const supporting = [], defining = [], supportingOnly = [], conflicting = [];
  const missing = [], missingDefining = [], reasons = [], needed = [];
  for (const item of sig.cues) {
    const fact = facts.get(item.property) || {state: "missing"};
    if (fact.state === "missing") {
      missing.push(item.property);
      if (item.strong) missingDefining.push(item.property);
      needed.push(item.needed);
      reasons.push(`missing:${item.property}`);
    } else if (fact.state === "conflicting") {
      observationConflict = true;
      conflicting.push(item.property);
      if (item.strong) missingDefining.push(item.property);
      needed.push(item.needed);
      reasons.push(`observation_conflict:${item.property}`);
    } else if (fact.state === "notApplicable") {
      missing.push(item.property);
      if (item.strong) missingDefining.push(item.property);
      reasons.push(`not_applicable:${item.property}`);
    } else if (item.compatible.has(fact.value)) {
      supportScore += item.weight;
      supporting.push(item.property);
      (item.strong ? defining : supportingOnly).push(item.property);
      reasons.push(`supports:${item.property}=${valueKey(fact.value)}`);
    } else if (item.incompatible.has(fact.value)) {
      conflictScore += item.weight;
      strongConflict ||= item.strong;
      conflicting.push(item.property);
      if (item.strong) missingDefining.push(item.property);
      needed.push(item.needed);
      reasons.push(`conflicts:${item.property}=${valueKey(fact.value)}`);
    }
  }
  const score = supportScore - conflictScore;
  const level = strongConflict || conflictScore >= 2 ? "conflicting" :
    observationConflict ? "uncertain" :
      supportScore >= 4 ? "strong" :
        supportScore >= 1 ? "compatible" : "uncertain";
  [supporting, defining, supportingOnly, conflicting, missing,
    missingDefining, reasons, needed].forEach((items) => items.sort());
  return result(identity, canonical, level, score, supporting, defining,
    supportingOnly, conflicting, missing, missingDefining, reasons,
    [...new Set(needed)]);
}

function buildFacts(evidence) {
  const byProperty = new Map();
  for (const item of evidence) {
    if (!item.active ||
        !(item.property === C || item.property.startsWith(O)) ||
        !ALLOWED_SOURCES.has(item.source)) continue;
    if (!byProperty.has(item.property)) byProperty.set(item.property, []);
    byProperty.get(item.property).push(item);
  }
  return new Map([...byProperty].map(([property, items]) => {
    const values = new Set(items.filter((item) => item.valueState === "known")
      .map((item) => typeof item.value === "string" ?
        item.value.trim().toLowerCase() : item.value));
    if (values.size > 1) return [property, {state: "conflicting"}];
    if (values.size === 1) {
      return [property, {state: "known", value: [...values][0]}];
    }
    return [property, {state: items.some((item) =>
      item.valueState === "not_applicable") ? "notApplicable" : "missing"}];
  }));
}
function result(identity, canonical, level, score, supporting, defining,
    supportingOnly, conflicting, missing, missingDefining, reasons, needed) {
  return {
    identityEvidenceId: identity.id,
    candidateCanonicalType: canonical,
    identitySource: identity.source,
    identityConfidence: identity.confidence,
    compatibilityLevel: level,
    score,
    supportingEvidence: supporting,
    definingEvidence: defining,
    supportingOnlyEvidence: supportingOnly,
    conflictingEvidence: conflicting,
    missingExpectedEvidence: missing,
    missingDefiningEvidence: missingDefining,
    reasonCodes: reasons,
    neededEvidence: needed,
  };
}
function hasCompetingIdentityConflict(results) {
  if (new Set(results.map((item) => item.candidateCanonicalType)).size < 2) {
    return false;
  }
  return results.some((item) =>
    ["strong", "compatible"].includes(item.compatibilityLevel));
}
function candidateGap(results) {
  if (results.length < 2) return "unavailable";
  const scores = results.map((item) => item.score).sort((a, b) => b - a);
  const difference = scores[0] - scores[1];
  return difference === 0 ? "none" : difference >= 3 ? "large" : "small";
}
function decisionRelevantDifferences(results) {
  if (results.length < 2) return [];
  return [...new Set(results.flatMap((item) =>
    [...item.supportingEvidence, ...item.conflictingEvidence]))].sort();
}
function compareIdentity(left, right) {
  return left.value.toLowerCase().localeCompare(right.value.toLowerCase()) ||
    left.id.localeCompare(right.id);
}
function decodeEvidence(value) {
  if (!isObject(value) || typeof value.id !== "string" ||
      typeof value.property !== "string" || typeof value.source !== "string" ||
      typeof value.confidence !== "number" ||
      value.confidence < 0 || value.confidence > 1) fail("evidence_invalid");
  const valueState = value.valueState || "known";
  if (!["known", "unknown", "not_visible", "not_applicable"].includes(
    valueState) ||
      (valueState !== "known" && value.value != null)) {
    fail("evidence_value_state_invalid");
  }
  return {
    ...structuredClone(value),
    active: value.active !== false,
    valueState,
  };
}
function decodeCanonicalConsistencyOracle(value) {
  if (!isObject(value) || value.oracleContractVersion !== 1 ||
      value.providerId !== PROVIDER_ID ||
      value.providerVersion !== PROVIDER_VERSION ||
      typeof value.scenarioId !== "string" ||
      !isObject(value.providerOutput)) fail("canonical_oracle_invalid");
  return deepFreeze({
    scenarioId: value.scenarioId,
    providerInput: decodeCanonicalConsistencyInput(value.providerInput),
    providerOutput: structuredClone(value.providerOutput),
  });
}
function valueKey(value) {
  return typeof value === "string" ? value : String(value);
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

function minimumDefiningSupportsFor(canonicalType) {
  if (typeof canonicalType !== "string") return 0;
  const signature = REGISTRY.get(canonicalType.trim().toLowerCase());
  if (!signature) return 0;
  if (signature.minimumDefiningSupports > 0) {
    return signature.minimumDefiningSupports;
  }
  return signature.cues.some((cue) => cue.strong) ? 1 : 0;
}

module.exports = {
  ORACLE_CONTRACT_VERSION,
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeCanonicalConsistencyInput,
  decodeCanonicalConsistencyOracle,
  minimumDefiningSupportsFor,
  validateCanonicalConsistency,
};
