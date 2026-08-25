"use strict";

const PROVIDER_ID = "WardrobeCapabilityInferenceProvider";
const PROVIDER_VERSION = "capability-inference-v1";
const UPSTREAM_PROVIDER_ID = "VisionObservationEvidenceProvider";
const UPSTREAM_PROVIDER_VERSION = "qualification-v1";
const ORACLE_CONTRACT_VERSION = 1;
const QUALIFICATION_INPUT_CONTRACT_VERSION = 1;

const VALUE_STATES = new Set([
  "known",
  "unknown",
  "not_visible",
  "not_applicable",
]);
const OBSERVATION_PROPERTIES = new Set([
  "visual.coverage",
  "visual.observations.hasHood",
  "visual.observations.frontClosure",
  "visual.observations.visibleBulk",
  "visual.observations.surfaceAppearance",
  "visual.observations.necklineShape",
  "visual.observations.visiblePocketStructure",
  "visual.observations.visibleStretchCue",
  "visual.observations.sportyCues",
  "visual.observations.formalCues",
  "visual.observations.footwearConstruction",
  "visual.observations.footwearFastening",
  "visual.observations.soleProfile",
  "visual.observations.visibleTread",
  "visual.observations.footwearUpperHeight",
]);
const CAPABILITY_PROPERTIES = new Set([
  "capabilities.warmth",
  "capabilities.breathability",
  "capabilities.mobility",
  "capabilities.formality",
  "capabilities.supportedLayerRoles",
  "capabilities.walkingComfort",
  "capabilities.traction",
]);
const CAPABILITY_LEVELS = new Set([
  "very_low",
  "low",
  "medium",
  "high",
  "very_high",
]);

const TARGETS = Object.freeze([
  target("capabilities.warmth", "warmth", [
    rule("warmth.bulk_and_insulating_surface", 7, 0.68, [
      condition("visual.observations.visibleBulk", ["high"]),
      condition("visual.observations.surfaceAppearance",
        ["fleece_like", "quilted"]),
    ]),
    rule("warmth.bulk_and_full_coverage", 6, 0.58, [
      condition("visual.observations.visibleBulk", ["high"]),
      condition("visual.coverage", ["full"]),
    ]),
    rule("warmth.ankle_upper_and_bulk", 6, 0.52, [
      condition("visual.observations.footwearUpperHeight",
        ["ankle", "high_shaft"]),
      condition("visual.observations.visibleBulk", ["high"]),
    ]),
    rule("warmth.low_bulk_mesh", 2, 0.62, [
      condition("visual.observations.visibleBulk", ["low"]),
      condition("visual.observations.surfaceAppearance", ["mesh"]),
    ]),
    rule("warmth.low_bulk_full_coverage", 3, 0.48, [
      condition("visual.observations.visibleBulk", ["low"]),
      condition("visual.coverage", ["full"]),
    ]),
  ]),
  target("capabilities.breathability", "breathability", [
    rule("breathability.mesh_and_low_bulk", "high", 0.62, [
      condition("visual.observations.surfaceAppearance", ["mesh"]),
      condition("visual.observations.visibleBulk", ["low"]),
    ]),
    rule("breathability.mesh_and_open_construction", "high", 0.58, [
      condition("visual.observations.surfaceAppearance", ["mesh"]),
      condition("visual.observations.footwearConstruction",
        ["open", "partially_open"]),
    ]),
  ]),
  target("capabilities.mobility", "mobility", [
    rule("mobility.stretch_and_sporty_construction", "high", 0.7, [
      condition("visual.observations.visibleStretchCue", [true]),
      condition("visual.observations.sportyCues", ["high"]),
    ]),
    rule("mobility.visible_stretch", "medium", 0.55, [
      condition("visual.observations.visibleStretchCue", [true]),
    ]),
  ]),
  target("capabilities.formality", "formality", [
    rule("formality.formal_over_sporty_cues", 8, 0.75, [
      condition("visual.observations.formalCues", ["high"]),
      condition("visual.observations.sportyCues", ["low"]),
    ]),
    rule("formality.strong_formal_cues", 7, 0.65, [
      condition("visual.observations.formalCues", ["high"]),
    ]),
    rule("formality.strong_sporty_cues", 3, 0.62, [
      condition("visual.observations.sportyCues", ["high"]),
      condition("visual.observations.formalCues", ["low"]),
    ]),
  ]),
  target("capabilities.supportedLayerRoles", "supported_layer_roles", [
    rule("supported_layer_roles.hooded_zip_layer",
      ["mid_layer", "outer_layer"], 0.58, [
        condition("visual.observations.hasHood", [true]),
        condition("visual.observations.frontClosure", ["full_zip"]),
        condition("visual.observations.visibleBulk", ["medium", "high"]),
      ]),
    rule("supported_layer_roles.knit_pullover",
      ["base_layer", "mid_layer"], 0.52, [
        condition("visual.observations.surfaceAppearance", ["knit"]),
        condition("visual.observations.frontClosure", ["none"]),
        condition("visual.observations.visibleBulk", ["medium", "high"]),
      ]),
  ]),
  target("capabilities.walkingComfort", "walking_comfort", [
    rule("walking_comfort.sporty_low_cut_supported_sole", "medium", 0.5, [
      condition("visual.observations.footwearConstruction", ["closed"]),
      condition("visual.observations.footwearUpperHeight", ["low_cut"]),
      condition("visual.observations.soleProfile", ["standard", "chunky"]),
      condition("visual.observations.sportyCues", ["high"]),
    ]),
  ], true),
  target("capabilities.traction", "traction", [
    rule("traction.pronounced_visible_tread", "high", 0.7, [
      condition("visual.observations.visibleTread", ["pronounced"]),
    ]),
    rule("traction.low_visible_tread", "low", 0.65, [
      condition("visual.observations.visibleTread", ["low"]),
    ]),
  ], true),
]);

function decodeCapabilityProviderInput(value) {
  if (!isObject(value)) fail("capability_input_invalid");
  if (value.oracleContractVersion !== ORACLE_CONTRACT_VERSION) {
    fail("oracle_contract_version_unsupported");
  }
  if (value.upstreamProviderId !== UPSTREAM_PROVIDER_ID) {
    fail("upstream_provider_id_invalid");
  }
  if (value.upstreamProviderVersion !== UPSTREAM_PROVIDER_VERSION) {
    fail("upstream_provider_version_invalid");
  }
  if (value.qualificationInputContractVersion !==
      QUALIFICATION_INPUT_CONTRACT_VERSION) {
    fail("qualification_input_contract_version_unsupported");
  }
  if (value.providerVersion !== PROVIDER_VERSION) {
    fail("capability_provider_version_invalid");
  }
  const analysisId = requireText(value.analysisId, "analysis_id_required");
  const observedAt = requireTimestamp(value.observedAt);
  const sourceReference = requireText(
    value.sourceReference, "source_reference_required");
  if (!Array.isArray(value.observationEvidence)) {
    fail("observation_evidence_invalid");
  }
  const ids = new Set();
  const observationEvidence = value.observationEvidence.map((item, index) => {
    const decoded = decodeObservationEvidence(
      item, index, observedAt, sourceReference);
    if (ids.has(decoded.id)) fail("duplicate_evidence_id");
    ids.add(decoded.id);
    return decoded;
  });
  return deepFreeze({
    analysisId,
    observedAt,
    providerVersion: value.providerVersion,
    observationEvidence,
  });
}

function inferCapabilities(inputValue) {
  const input = decodeCapabilityProviderInput(inputValue);
  const observations = buildObservationIndex(input.observationEvidence);
  const output = [];
  for (const capabilityTarget of TARGETS) {
    if (capabilityTarget.footwearOnly &&
        isExplicitlyNotApplicable(
          observations, "visual.observations.footwearConstruction")) {
      output.push(buildEvidence(input, capabilityTarget.property, null,
        "not_applicable", 1,
        `${capabilityTarget.reasonPrefix}.explicit_non_footwear`,
        sourceReferencesFor(observations,
          ["visual.observations.footwearConstruction"])));
      continue;
    }
    for (const inferenceRule of capabilityTarget.rules) {
      const match = matchRule(observations, inferenceRule);
      if (match === null) continue;
      output.push(buildEvidence(input, capabilityTarget.property,
        inferenceRule.value, "known", match.confidence,
        inferenceRule.reason, match.sourceReferences));
      break;
    }
  }
  output.sort((left, right) => left.property.localeCompare(right.property));
  return deepFreeze(output);
}

function decodeObservationEvidence(value, index, observedAt, sourceReference) {
  if (!isObject(value)) fail(`evidence_invalid:${index}`);
  const id = requireText(value.id, `evidence_id_required:${index}`);
  const property = requireText(
    value.property, `evidence_property_required:${index}`);
  if (!OBSERVATION_PROPERTIES.has(property)) {
    fail(`evidence_property_invalid:${index}`);
  }
  if (value.source !== "visual_observation") {
    fail(`evidence_source_invalid:${index}`);
  }
  if (value.nature !== "observed") {
    fail(`evidence_nature_invalid:${index}`);
  }
  if (value.method !== "vision_observation") {
    fail(`evidence_method_invalid:${index}`);
  }
  if (!VALUE_STATES.has(value.valueState)) {
    fail(`evidence_value_state_invalid:${index}`);
  }
  requireConfidence(value.confidence, `evidence_confidence_invalid:${index}`);
  if (!Object.hasOwn(value, "value")) fail(`evidence_value_omitted:${index}`);
  if (value.valueState === "known") {
    if (value.value === null) fail(`known_evidence_value_null:${index}`);
  } else if (value.value !== null) {
    fail(`non_value_evidence_value_invalid:${index}`);
  }
  validateObservationValue(property, value.value, value.valueState, index);
  if (!Array.isArray(value.supportingEvidenceIds) ||
      !value.supportingEvidenceIds.every((item) =>
        typeof item === "string" && item.length > 0)) {
    fail(`supporting_evidence_ids_invalid:${index}`);
  }
  return {
    id,
    property,
    value: cloneValue(value.value),
    valueState: value.valueState,
    source: value.source,
    nature: value.nature,
    confidence: value.confidence,
    active: value.active !== false,
    method: value.method,
    createdAt: observedAt,
    sourceReference: Object.hasOwn(value, "sourceReference") ?
      requireText(value.sourceReference,
        `evidence_source_reference_invalid:${index}`) : sourceReference,
    supportingEvidenceIds: [...value.supportingEvidenceIds],
  };
}

function validateObservationValue(property, value, valueState, index) {
  if (valueState !== "known") return;
  const allowed = {
    "visual.coverage": ["minimal", "partial", "full"],
    "visual.observations.hasHood": [true, false],
    "visual.observations.frontClosure":
      ["none", "partial_zip", "full_zip", "buttons", "snaps", "other"],
    "visual.observations.visibleBulk": ["low", "medium", "high"],
    "visual.observations.surfaceAppearance":
      ["knit", "woven", "fleece_like", "quilted", "smooth",
        "textured", "mesh", "leather_like"],
    "visual.observations.necklineShape":
      ["crew", "v_neck", "scoop", "high_neck", "collared", "other"],
    "visual.observations.visiblePocketStructure":
      ["none", "standard", "cargo", "patch", "other"],
    "visual.observations.visibleStretchCue": [true, false],
    "visual.observations.sportyCues": ["low", "medium", "high"],
    "visual.observations.formalCues": ["low", "medium", "high"],
    "visual.observations.footwearConstruction":
      ["open", "partially_open", "closed"],
    "visual.observations.footwearFastening":
      ["laces", "zipper", "elastic_side_panels", "slip_on",
        "straps", "buckles", "other"],
    "visual.observations.soleProfile": ["thin", "standard", "chunky"],
    "visual.observations.visibleTread": ["low", "moderate", "pronounced"],
    "visual.observations.footwearUpperHeight":
      ["low_cut", "ankle", "high_shaft"],
  }[property];
  if (!allowed.some((item) => Object.is(item, value))) {
    fail(`evidence_value_enum_invalid:${index}`);
  }
}

function buildObservationIndex(evidence) {
  const raw = new Map();
  for (const item of evidence) {
    if (!item.active || item.source !== "visual_observation" ||
        !(item.property === "visual.coverage" ||
          item.property.startsWith("visual.observations."))) {
      continue;
    }
    if (!raw.has(item.property)) raw.set(item.property, []);
    raw.get(item.property).push(item);
  }
  const values = new Map();
  const notApplicable = new Set();
  for (const [property, items] of raw) {
    values.set(property, aggregate(items));
    if (items.some((item) => item.valueState === "not_applicable")) {
      notApplicable.add(property);
    }
  }
  return {raw, values, notApplicable};
}

function aggregate(evidence) {
  const known = evidence.filter((item) => item.valueState === "known");
  if (known.length === 0) return null;
  const byValue = new Map();
  for (const item of known) {
    const key = valueKey(item.value);
    if (!byValue.has(key)) byValue.set(key, []);
    byValue.get(key).push(item);
  }
  if (byValue.size > 1) {
    return {hasConflict: true, value: null, confidence: 0,
      supportingEvidenceCount: 0, sourceReferences: []};
  }
  const agreeing = [...byValue.values()][0];
  const confidence = agreeing.reduce(
    (sum, item) => sum + item.confidence, 0) / agreeing.length;
  const sourceReferences = [...new Set(agreeing
    .map((item) => item.sourceReference)
    .filter((item) => typeof item === "string" && item.length > 0))].sort();
  return {
    hasConflict: false,
    value: agreeing[0].value,
    confidence,
    supportingEvidenceCount: agreeing.length,
    sourceReferences,
  };
}

function matchRule(observations, inferenceRule) {
  const matched = [];
  for (const required of inferenceRule.conditions) {
    const observation = observations.values.get(required.property);
    if (observation == null || observation.hasConflict ||
        !required.acceptedValues.some((item) =>
          Object.is(item, observation.value))) {
      return null;
    }
    matched.push(observation);
  }
  const averageConfidence = matched.reduce(
    (sum, item) => sum + item.confidence, 0) / matched.length;
  const agreementBonus = matched.reduce(
    (sum, item) => sum + (item.supportingEvidenceCount - 1), 0);
  const supportFactor = clamp(
    0.82 + inferenceRule.conditions.length * 0.04 +
      clamp(agreementBonus, 0, 2) * 0.03, 0, 1);
  const confidence = clamp(
    averageConfidence * supportFactor, 0, inferenceRule.maxConfidence);
  const sourceReferences = [...new Set(
    matched.flatMap((item) => item.sourceReferences))].sort();
  return {
    confidence: dartFixedFour(confidence),
    sourceReferences,
  };
}

function buildEvidence(
    input, property, value, valueState, confidence, reason, sourceReferences) {
  const result = {
    id: `capability:${dartEncodeComponent(input.analysisId)}:${property}`,
    property,
    value: cloneValue(value),
    valueState,
    source: "ai_inference",
    nature: "inferred",
    confidence,
    verified: false,
    active: true,
    method: `capability_inference:${reason}`,
    createdAt: input.observedAt,
    modelVersion: input.providerVersion,
    supportingEvidenceIds: [],
  };
  if (sourceReferences.length > 0) {
    result.sourceReference = sourceReferences.join("|");
  }
  validateCapabilityEvidence(result);
  return result;
}

function validateCapabilityEvidence(value) {
  if (!isObject(value) || !CAPABILITY_PROPERTIES.has(value.property)) {
    fail("capability_output_property_invalid");
  }
  const idMatch = typeof value.id === "string" ?
    /^capability:([^:]+):(capabilities\.[A-Za-z]+)$/.exec(value.id) : null;
  if (!idMatch || idMatch[2] !== value.property) {
    fail("capability_output_id_invalid");
  }
  if (!VALUE_STATES.has(value.valueState) ||
      !["known", "not_applicable"].includes(value.valueState)) {
    fail("capability_output_value_state_invalid");
  }
  if (value.valueState === "not_applicable") {
    if (value.value !== null || value.confidence !== 1) {
      fail("capability_output_not_applicable_invalid");
    }
  } else {
    if (value.value === null) fail("capability_output_known_value_invalid");
    if (value.property === "capabilities.supportedLayerRoles") {
      const roles = new Set([
        "base_layer", "mid_layer", "outer_layer", "bottom",
        "footwear", "accessory",
      ]);
      if (!Array.isArray(value.value) ||
          !value.value.every((item) => roles.has(item))) {
        fail("capability_output_enum_invalid");
      }
    } else if (["capabilities.warmth", "capabilities.formality"]
      .includes(value.property)) {
      if (!Number.isInteger(value.value) ||
          value.value < 0 || value.value > 10) {
        fail("capability_output_enum_invalid");
      }
    } else if (typeof value.value !== "string" ||
        !CAPABILITY_LEVELS.has(value.value)) {
      fail("capability_output_enum_invalid");
    }
  }
  requireConfidence(value.confidence, "capability_output_confidence_invalid");
  requireTimestamp(value.createdAt);
  requireText(value.method, "capability_output_method_invalid");
  if (value.source !== "ai_inference" || value.nature !== "inferred" ||
      value.verified !== false || value.active !== true ||
      value.modelVersion !== PROVIDER_VERSION) {
    fail("capability_output_provenance_invalid");
  }
  if (!Array.isArray(value.supportingEvidenceIds) ||
      !value.supportingEvidenceIds.every((item) =>
        typeof item === "string" && item.length > 0)) {
    fail("capability_output_supporting_ids_invalid");
  }
}

function isExplicitlyNotApplicable(observations, property) {
  return observations.notApplicable.has(property) &&
    observations.values.get(property) == null;
}
function sourceReferencesFor(observations, properties) {
  const result = new Set();
  for (const property of properties) {
    for (const item of observations.raw.get(property) || []) {
      if (item.sourceReference) result.add(item.sourceReference);
    }
  }
  return [...result].sort();
}
function target(property, reasonPrefix, rules, footwearOnly = false) {
  return deepFreeze({property, reasonPrefix, rules, footwearOnly});
}
function rule(reason, value, maxConfidence, conditions) {
  return deepFreeze({reason, value, maxConfidence, conditions});
}
function condition(property, acceptedValues) {
  return deepFreeze({property, acceptedValues});
}
function valueKey(value) {
  if (typeof value === "string") return value.trim().toLowerCase();
  return `${typeof value}:${String(value)}`;
}
function clamp(value, minimum, maximum) {
  return value < minimum ? minimum : value > maximum ? maximum : value;
}
function dartFixedFour(value) {
  // Ports Dart's `double.parse(value.toStringAsFixed(4))` policy.
  const scaled = value * 10000;
  return Math.floor(scaled + 0.5) / 10000;
}
function dartEncodeComponent(value) {
  return encodeURIComponent(value).replace(/[!'()*]/g, (character) =>
    `%${character.charCodeAt(0).toString(16).toUpperCase()}`);
}
function cloneValue(value) {
  return value && typeof value === "object" ? structuredClone(value) : value;
}
function requireConfidence(value, reason) {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      value < 0 || value > 1) fail(reason);
}
function requireTimestamp(value) {
  requireText(value, "observed_at_required");
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) ||
      Number.isNaN(Date.parse(value))) {
    fail("observed_at_invalid");
  }
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
  PROVIDER_ID,
  PROVIDER_VERSION,
  QUALIFICATION_INPUT_CONTRACT_VERSION,
  TARGETS,
  UPSTREAM_PROVIDER_ID,
  UPSTREAM_PROVIDER_VERSION,
  decodeCapabilityProviderInput,
  inferCapabilities,
  validateCapabilityEvidence,
};
