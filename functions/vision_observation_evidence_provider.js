"use strict";

const PROVIDER_ID = "VisionObservationEvidenceProvider";
const PROVIDER_VERSION = "qualification-v1";
const ORACLE_CONTRACT_VERSION = 1;

const STATES = new Set([
  "observed",
  "unknown",
  "not_visible",
  "not_applicable",
]);
const VISIBILITY_SCOPES = new Set([
  "complete",
  "sufficient",
  "partial",
  "not_visible",
]);
const VISUAL_REGIONS = new Set([
  "full_silhouette",
  "front",
  "side",
  "back",
  "collar",
  "neckline",
  "pocket_area",
  "footwear_upper",
  "fastening_area",
  "sole_profile",
  "outsole",
  "surface_detail",
]);

const PROPERTY_SPECS = Object.freeze([
  spec("coverage", "visual.coverage", strings("minimal", "partial", "full")),
  spec("hasHood", "visual.observations.hasHood", booleanValue),
  spec("frontClosure", "visual.observations.frontClosure",
    strings("none", "partial_zip", "full_zip", "buttons", "snaps", "other")),
  spec("visibleBulk", "visual.observations.visibleBulk",
    strings("low", "medium", "high")),
  spec("surfaceAppearance", "visual.observations.surfaceAppearance",
    strings("knit", "woven", "fleece_like", "quilted", "smooth",
      "textured", "mesh", "leather_like")),
  spec("necklineShape", "visual.observations.necklineShape",
    strings("crew", "v_neck", "scoop", "high_neck", "collared", "other")),
  spec("visiblePocketStructure",
    "visual.observations.visiblePocketStructure",
    strings("none", "standard", "cargo", "patch", "other")),
  spec("visibleStretchCue", "visual.observations.visibleStretchCue",
    booleanValue),
  spec("sportyCues", "visual.observations.sportyCues",
    strings("low", "medium", "high")),
  spec("formalCues", "visual.observations.formalCues",
    strings("low", "medium", "high")),
  spec("footwearConstruction",
    "visual.observations.footwearConstruction",
    strings("open", "partially_open", "closed")),
  spec("footwearFastening", "visual.observations.footwearFastening",
    strings("laces", "zipper", "elastic_side_panels", "slip_on",
      "straps", "buckles", "other")),
  spec("soleProfile", "visual.observations.soleProfile",
    strings("thin", "standard", "chunky")),
  spec("visibleTread", "visual.observations.visibleTread",
    strings("low", "moderate", "pronounced")),
  spec("footwearUpperHeight", "visual.observations.footwearUpperHeight",
    strings("low_cut", "ankle", "high_shaft")),
]);

function decodeProviderOracle(value) {
  if (!isObject(value)) fail("oracle_root_invalid");
  if (value.oracleContractVersion !== ORACLE_CONTRACT_VERSION) {
    fail("oracle_contract_version_unsupported");
  }
  if (value.providerId !== PROVIDER_ID) fail("oracle_provider_id_invalid");
  if (value.providerVersion !== PROVIDER_VERSION) {
    fail("oracle_provider_version_invalid");
  }
  requireText(value.scenarioId, "oracle_scenario_id_required");
  if (!Array.isArray(value.orderedViewProvenance) ||
      value.orderedViewProvenance.length === 0) {
    fail("oracle_ordered_views_invalid");
  }
  const input = decodeProviderInput(value.providerInput);
  if (!Array.isArray(value.providerOutput)) fail("oracle_output_invalid");
  return deepFreeze({
    scenarioId: value.scenarioId,
    orderedViewProvenance: structuredClone(value.orderedViewProvenance),
    providerInput: input,
    providerOutput: structuredClone(value.providerOutput),
    providerInputSha256: requireSha(value.providerInputSha256,
      "oracle_input_sha_invalid"),
    providerOutputSha256: requireSha(value.providerOutputSha256,
      "oracle_output_sha_invalid"),
  });
}

function decodeProviderInput(value) {
  if (!isObject(value)) fail("provider_input_invalid");
  const input = {
    analysisId: requireText(value.analysisId, "analysis_id_required"),
    modelVersion: requireText(value.modelVersion, "model_version_required"),
    sourceReference: requireText(value.sourceReference,
      "source_reference_required"),
    observedAt: requireTimestamp(value.observedAt),
    quality: decodeQuality(value.quality),
  };
  for (const property of PROPERTY_SPECS) {
    if (!Object.hasOwn(value, property.inputKey)) continue;
    if (value[property.inputKey] === null) {
      fail(`observation_null_not_allowed:${property.inputKey}`);
    }
    input[property.inputKey] = decodeObservation(
      value[property.inputKey], property);
  }
  return deepFreeze(input);
}

function provideObservationEvidence(inputValue) {
  const input = decodeProviderInput(inputValue);
  const evidence = [];
  for (const property of PROPERTY_SPECS) {
    const observation = input[property.inputKey];
    if (observation === undefined) continue;
    evidence.push({
      id: `observation:${dartEncodeComponent(input.analysisId)}:` +
        `${dartEncodeComponent(input.sourceReference)}:${property.path}`,
      property: property.path,
      value: observation.state === "observed" ? observation.value : null,
      valueState: stateToValueState(observation.state),
      source: "visual_observation",
      nature: "observed",
      confidence: observation.confidence,
      method: "vision_observation",
      supportingEvidenceIds: [],
    });
  }
  return deepFreeze(evidence);
}

function decodeObservation(value, property) {
  if (!isObject(value)) fail(`observation_invalid:${property.inputKey}`);
  if (!STATES.has(value.state)) {
    fail(`observation_state_invalid:${property.inputKey}`);
  }
  if (value.state === "observed") {
    if (!Object.hasOwn(value, "value")) {
      fail(`observation_value_required:${property.inputKey}`);
    }
    property.validateValue(value.value, property.inputKey);
    requireConfidence(value.confidence, property.inputKey);
    if (Object.hasOwn(value, "visibilityScope") &&
        !VISIBILITY_SCOPES.has(value.visibilityScope)) {
      fail(`visibility_scope_invalid:${property.inputKey}`);
    }
    if (Object.hasOwn(value, "visibleRegions")) {
      if (!Array.isArray(value.visibleRegions) ||
          !value.visibleRegions.every((item) => VISUAL_REGIONS.has(item))) {
        fail(`visible_regions_invalid:${property.inputKey}`);
      }
    }
    return {
      state: value.state,
      value: value.value,
      confidence: value.confidence,
      ...(Object.hasOwn(value, "visibilityScope") ?
        {visibilityScope: value.visibilityScope} : {}),
      ...(Object.hasOwn(value, "visibleRegions") ?
        {visibleRegions: [...value.visibleRegions]} : {}),
    };
  }
  if (Object.hasOwn(value, "value")) {
    fail(`non_observed_value_forbidden:${property.inputKey}`);
  }
  const expectedConfidence = value.state === "not_applicable" ? 1 : 0;
  if (value.confidence !== expectedConfidence) {
    fail(`non_observed_confidence_invalid:${property.inputKey}`);
  }
  if (value.state === "not_visible") {
    if (value.visibilityScope !== "not_visible") {
      fail(`not_visible_scope_invalid:${property.inputKey}`);
    }
  } else if (Object.hasOwn(value, "visibilityScope")) {
    fail(`non_observed_scope_forbidden:${property.inputKey}`);
  }
  if (Object.hasOwn(value, "visibleRegions")) {
    fail(`non_observed_regions_forbidden:${property.inputKey}`);
  }
  return {
    state: value.state,
    confidence: expectedConfidence,
    ...(value.state === "not_visible" ?
      {visibilityScope: "not_visible"} : {}),
  };
}

function decodeQuality(value) {
  if (!isObject(value)) fail("quality_invalid");
  const result = {};
  if (Object.hasOwn(value, "itemFullyVisible")) {
    if (typeof value.itemFullyVisible !== "boolean") {
      fail("quality_item_fully_visible_invalid");
    }
    result.itemFullyVisible = value.itemFullyVisible;
  }
  for (const key of ["backgroundInterference", "clarity"]) {
    if (Object.hasOwn(value, key)) {
      strings("low", "medium", "high")(value[key], `quality.${key}`);
      result[key] = value[key];
    }
  }
  if (Object.hasOwn(value, "occlusion")) {
    strings("none", "partial", "substantial")(
      value.occlusion, "quality.occlusion");
    result.occlusion = value.occlusion;
  }
  return result;
}

function stateToValueState(state) {
  switch (state) {
    case "observed": return "known";
    case "unknown": return "unknown";
    case "not_visible": return "not_visible";
    case "not_applicable": return "not_applicable";
    default: fail("observation_state_unreachable");
  }
}

function dartEncodeComponent(value) {
  return encodeURIComponent(value).replace(/[!'()*]/g, (character) =>
    `%${character.charCodeAt(0).toString(16).toUpperCase()}`);
}

function spec(inputKey, path, validateValue) {
  return Object.freeze({inputKey, path, validateValue});
}
function strings(...allowed) {
  const values = new Set(allowed);
  return (value, label) => {
    if (typeof value !== "string" || !values.has(value)) {
      fail(`enum_value_invalid:${label}`);
    }
  };
}
function booleanValue(value, label) {
  if (typeof value !== "boolean") fail(`boolean_value_invalid:${label}`);
}
function requireConfidence(value, label) {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      value < 0 || value > 1) {
    fail(`confidence_invalid:${label}`);
  }
}
function requireTimestamp(value) {
  requireText(value, "observed_at_required");
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) ||
      Number.isNaN(Date.parse(value))) {
    fail("observed_at_invalid");
  }
  return value;
}
function requireSha(value, reason) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) fail(reason);
  return value;
}
function requireText(value, reason) {
  if (typeof value !== "string" || !value.trim()) fail(reason);
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
  PROPERTY_SPECS,
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeProviderInput,
  decodeProviderOracle,
  provideObservationEvidence,
};
