"use strict";

/**
 * Node port of Dart WardrobeProfileResolver.resolve.
 *
 * Pure / sync / deterministic. Not imported by production entry points.
 * Accepts only wardrobe_profile_resolver_input/v1 from
 * PrepareWardrobeProfileResolverInput — does not recompose evidence.
 */

const PROVIDER_ID = "WardrobeProfileResolver";
const PROVIDER_VERSION = "wardrobe-profile-resolver-v1";
const INPUT_CONTRACT = "wardrobe_profile_resolver_input/v1";
const OUTPUT_CONTRACT = "ResolvedWardrobeItemProfile/v1";
const ORACLE_CONTRACT_VERSION = 1;
const RESOLVER_COMPATIBILITY_VERSION = 1;

const FORBIDDEN_AUTHORITY_FIELDS = Object.freeze([
  "resolvedProfile",
  "selectedCanonicalType",
  "selectedCapabilities",
  "familyEvidence",
  "familyIdentityReport",
  "preparedResolverOutput",
]);

/** EvidenceSource enum declaration order = Dart `.index`. */
const EVIDENCE_SOURCES = Object.freeze([
  "user_correction",
  "verified_product_metadata",
  "label_metadata",
  "visual_observation",
  "ai_inference",
  "knowledge_base_prior",
  "legacy_fallback",
]);
const EVIDENCE_SOURCE_INDEX = Object.freeze(
  Object.fromEntries(EVIDENCE_SOURCES.map((item, index) => [item, index])));

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

const PROPERTY = Object.freeze({
  displayName: "identity.displayName",
  canonicalType: "identity.canonicalType",
  primaryType: "identity.primaryType",
  secondaryType: "identity.secondaryType",
  mainCategory: "identity.mainCategory",
  category: "identity.category",
  subcategory: "identity.subcategory",
  brand: "identity.brand",
  colors: "visual.colors",
  baseColors: "visual.baseColors",
  patterns: "visual.patterns",
  styles: "visual.styles",
  fit: "visual.fit",
  vibe: "visual.vibe",
  logoProminence: "visual.logoProminence",
  visualIdentity: "visual.visualIdentity",
  visualDescription: "visual.visualDescription",
  materialFeel: "visual.materialFeel",
  coverage: "visual.coverage",
  hasHood: "visual.observations.hasHood",
  frontClosure: "visual.observations.frontClosure",
  visibleBulk: "visual.observations.visibleBulk",
  surfaceAppearance: "visual.observations.surfaceAppearance",
  necklineShape: "visual.observations.necklineShape",
  visiblePocketStructure: "visual.observations.visiblePocketStructure",
  visibleStretchCue: "visual.observations.visibleStretchCue",
  sportyCues: "visual.observations.sportyCues",
  formalCues: "visual.observations.formalCues",
  footwearConstruction: "visual.observations.footwearConstruction",
  footwearFastening: "visual.observations.footwearFastening",
  soleProfile: "visual.observations.soleProfile",
  visibleTread: "visual.observations.visibleTread",
  footwearUpperHeight: "visual.observations.footwearUpperHeight",
  warmth: "capabilities.warmth",
  formality: "capabilities.formality",
  layerRole: "capabilities.layerRole",
  supportedLayerRoles: "capabilities.supportedLayerRoles",
  mobility: "capabilities.mobility",
  breathability: "capabilities.breathability",
  windProtection: "capabilities.windProtection",
  rainProtection: "capabilities.rainProtection",
  walkingComfort: "capabilities.walkingComfort",
  traction: "capabilities.traction",
  rainSuitability: "capabilities.rainSuitability",
  outdoorSuitability: "capabilities.outdoorSuitability",
  seasons: "suitability.seasons",
  occasions: "suitability.occasions",
  activities: "suitability.activities",
  terrain: "suitability.terrain",
});

const ALL_PROPERTIES = new Set(Object.values(PROPERTY));

const COLLECTION_PROPERTIES = new Set([
  PROPERTY.colors,
  PROPERTY.baseColors,
  PROPERTY.patterns,
  PROPERTY.styles,
  PROPERTY.supportedLayerRoles,
  PROPERTY.seasons,
  PROPERTY.occasions,
  PROPERTY.activities,
  PROPERTY.terrain,
]);

const CAPABILITY_LEVEL_PROPERTIES = new Set([
  PROPERTY.mobility,
  PROPERTY.breathability,
  PROPERTY.windProtection,
  PROPERTY.rainProtection,
  PROPERTY.walkingComfort,
  PROPERTY.traction,
  PROPERTY.outdoorSuitability,
]);

const BOOLEAN_OBSERVATION_PROPERTIES = new Set([
  PROPERTY.hasHood,
  PROPERTY.visibleStretchCue,
]);

const VISUAL_AMOUNT_PROPERTIES = new Set([
  PROPERTY.visibleBulk,
  PROPERTY.sportyCues,
  PROPERTY.formalCues,
]);

const CANONICAL_DEPENDENT_PROPERTIES = new Set([
  PROPERTY.warmth,
  PROPERTY.formality,
  PROPERTY.layerRole,
  PROPERTY.supportedLayerRoles,
  PROPERTY.mobility,
  PROPERTY.breathability,
  PROPERTY.windProtection,
  PROPERTY.rainProtection,
  PROPERTY.walkingComfort,
  PROPERTY.traction,
  PROPERTY.rainSuitability,
  PROPERTY.outdoorSuitability,
  PROPERTY.seasons,
  PROPERTY.occasions,
  PROPERTY.activities,
  PROPERTY.terrain,
]);

const LAYER_ROLES = Object.freeze([
  {dartName: "baseLayer", wire: "base_layer"},
  {dartName: "midLayer", wire: "mid_layer"},
  {dartName: "outerLayer", wire: "outer_layer"},
  {dartName: "bottom", wire: "bottom"},
  {dartName: "footwear", wire: "footwear"},
  {dartName: "accessory", wire: "accessory"},
]);

const CAPABILITY_LEVELS = Object.freeze([
  {dartName: "veryLow", wire: "very_low", aliases: ["verylow", "very_low"]},
  {dartName: "low", wire: "low", aliases: ["low"]},
  {dartName: "medium", wire: "medium", aliases: ["medium"]},
  {dartName: "high", wire: "high", aliases: ["high"]},
  {dartName: "veryHigh", wire: "very_high", aliases: ["veryhigh", "very_high"]},
]);

const RAIN_SUITABILITY = Object.freeze([
  {dartName: "unsuitable", wire: "unsuitable"},
  {dartName: "limited", wire: "limited"},
  {dartName: "suitable", wire: "suitable"},
]);

const COVERAGE = Object.freeze([
  {dartName: "minimal", wire: "minimal"},
  {dartName: "partial", wire: "partial"},
  {dartName: "full", wire: "full"},
]);

const FRONT_CLOSURE = Object.freeze([
  {dartName: "none", wire: "none"},
  {dartName: "partialZip", wire: "partial_zip"},
  {dartName: "fullZip", wire: "full_zip"},
  {dartName: "buttons", wire: "buttons"},
  {dartName: "snaps", wire: "snaps"},
  {dartName: "other", wire: "other"},
]);

const VISUAL_AMOUNT = Object.freeze([
  {dartName: "low", wire: "low"},
  {dartName: "medium", wire: "medium"},
  {dartName: "high", wire: "high"},
]);

const SURFACE_APPEARANCE = Object.freeze([
  {dartName: "knit", wire: "knit"},
  {dartName: "woven", wire: "woven"},
  {dartName: "fleeceLike", wire: "fleece_like"},
  {dartName: "quilted", wire: "quilted"},
  {dartName: "smooth", wire: "smooth"},
  {dartName: "textured", wire: "textured"},
  {dartName: "mesh", wire: "mesh"},
  {dartName: "leatherLike", wire: "leather_like"},
]);

const NECKLINE_SHAPE = Object.freeze([
  {dartName: "crew", wire: "crew"},
  {dartName: "vNeck", wire: "v_neck"},
  {dartName: "scoop", wire: "scoop"},
  {dartName: "highNeck", wire: "high_neck"},
  {dartName: "collared", wire: "collared"},
  {dartName: "other", wire: "other"},
]);

const VISIBLE_POCKET = Object.freeze([
  {dartName: "none", wire: "none"},
  {dartName: "standard", wire: "standard"},
  {dartName: "cargo", wire: "cargo"},
  {dartName: "patch", wire: "patch"},
  {dartName: "other", wire: "other"},
]);

const FOOTWEAR_CONSTRUCTION = Object.freeze([
  {dartName: "open", wire: "open"},
  {dartName: "partiallyOpen", wire: "partially_open"},
  {dartName: "closed", wire: "closed"},
]);

const FOOTWEAR_FASTENING = Object.freeze([
  {dartName: "laces", wire: "laces"},
  {dartName: "zipper", wire: "zipper"},
  {dartName: "elasticSidePanels", wire: "elastic_side_panels"},
  {dartName: "slipOn", wire: "slip_on"},
  {dartName: "straps", wire: "straps"},
  {dartName: "buckles", wire: "buckles"},
  {dartName: "other", wire: "other"},
]);

const SOLE_PROFILE = Object.freeze([
  {dartName: "thin", wire: "thin"},
  {dartName: "standard", wire: "standard"},
  {dartName: "chunky", wire: "chunky"},
]);

const VISIBLE_TREAD = Object.freeze([
  {dartName: "low", wire: "low"},
  {dartName: "moderate", wire: "moderate"},
  {dartName: "pronounced", wire: "pronounced"},
]);

const FOOTWEAR_UPPER_HEIGHT = Object.freeze([
  {dartName: "lowCut", wire: "low_cut"},
  {dartName: "ankle", wire: "ankle"},
  {dartName: "highShaft", wire: "high_shaft"},
]);

function policy(values) {
  return Object.freeze({
    verifiedProduct: values.verifiedProduct,
    label: values.label,
    visual: values.visual,
    ai: values.ai,
    kb: values.kb,
    legacy: values.legacy,
  });
}

const DEFAULT_POLICY = policy({
  verifiedProduct: 85, label: 82, visual: 70, ai: 65, kb: 30, legacy: 15,
});
const VISUAL_POLICY = policy({
  verifiedProduct: 86, label: 82, visual: 92, ai: 68, kb: 25, legacy: 15,
});
const CAPABILITY_POLICY = policy({
  verifiedProduct: 88, label: 92, visual: 82, ai: 68, kb: 30, legacy: 15,
});
const TECHNICAL_POLICY = policy({
  verifiedProduct: 92, label: 95, visual: 78, ai: 65, kb: 25, legacy: 15,
});
const SUITABILITY_POLICY = policy({
  verifiedProduct: 85, label: 65, visual: 55, ai: 70, kb: 30, legacy: 15,
});

const POLICIES = Object.freeze({
  [PROPERTY.canonicalType]: policy({
    verifiedProduct: 92, label: 88, visual: 68, ai: 72, kb: 35, legacy: 15,
  }),
  [PROPERTY.brand]: policy({
    verifiedProduct: 94, label: 90, visual: 55, ai: 45, kb: 20, legacy: 20,
  }),
  [PROPERTY.colors]: VISUAL_POLICY,
  [PROPERTY.patterns]: VISUAL_POLICY,
  [PROPERTY.fit]: VISUAL_POLICY,
  [PROPERTY.coverage]: VISUAL_POLICY,
  [PROPERTY.hasHood]: VISUAL_POLICY,
  [PROPERTY.frontClosure]: VISUAL_POLICY,
  [PROPERTY.visibleBulk]: VISUAL_POLICY,
  [PROPERTY.surfaceAppearance]: VISUAL_POLICY,
  [PROPERTY.necklineShape]: VISUAL_POLICY,
  [PROPERTY.visiblePocketStructure]: VISUAL_POLICY,
  [PROPERTY.visibleStretchCue]: VISUAL_POLICY,
  [PROPERTY.sportyCues]: VISUAL_POLICY,
  [PROPERTY.formalCues]: VISUAL_POLICY,
  [PROPERTY.footwearConstruction]: VISUAL_POLICY,
  [PROPERTY.footwearFastening]: VISUAL_POLICY,
  [PROPERTY.soleProfile]: VISUAL_POLICY,
  [PROPERTY.visibleTread]: VISUAL_POLICY,
  [PROPERTY.footwearUpperHeight]: VISUAL_POLICY,
  [PROPERTY.warmth]: CAPABILITY_POLICY,
  [PROPERTY.formality]: CAPABILITY_POLICY,
  [PROPERTY.layerRole]: CAPABILITY_POLICY,
  [PROPERTY.supportedLayerRoles]: CAPABILITY_POLICY,
  [PROPERTY.mobility]: TECHNICAL_POLICY,
  [PROPERTY.breathability]: TECHNICAL_POLICY,
  [PROPERTY.windProtection]: TECHNICAL_POLICY,
  [PROPERTY.rainProtection]: TECHNICAL_POLICY,
  [PROPERTY.walkingComfort]: TECHNICAL_POLICY,
  [PROPERTY.traction]: TECHNICAL_POLICY,
  [PROPERTY.rainSuitability]: TECHNICAL_POLICY,
  [PROPERTY.outdoorSuitability]: TECHNICAL_POLICY,
  [PROPERTY.seasons]: SUITABILITY_POLICY,
  [PROPERTY.occasions]: SUITABILITY_POLICY,
});

/**
 * @param {object} raw wardrobe_profile_resolver_input/v1
 * @returns {Readonly<object>} ResolvedWardrobeItemProfile/v1 wire map
 */
function resolveWardrobeProfile(raw) {
  const input = decodeResolverInput(raw);
  const usableEvidence = sanitizeEvidence(input.evidence);
  const canonicalType = resolveField(PROPERTY.canonicalType, usableEvidence);
  const canonicalValue = canonicalType.state === "known" ?
    canonicalType.value : null;
  const field = (property) => resolveField(
    property, usableEvidence, canonicalValue);

  return deepFreeze({
    itemId: input.itemId,
    identity: {
      displayName: field(PROPERTY.displayName),
      canonicalType,
      primaryType: field(PROPERTY.primaryType),
      secondaryType: field(PROPERTY.secondaryType),
      mainCategory: field(PROPERTY.mainCategory),
      category: field(PROPERTY.category),
      subcategory: field(PROPERTY.subcategory),
      brand: field(PROPERTY.brand),
    },
    visual: {
      colors: field(PROPERTY.colors),
      baseColors: field(PROPERTY.baseColors),
      patterns: field(PROPERTY.patterns),
      styles: field(PROPERTY.styles),
      fit: field(PROPERTY.fit),
      vibe: field(PROPERTY.vibe),
      logoProminence: field(PROPERTY.logoProminence),
      visualIdentity: field(PROPERTY.visualIdentity),
      visualDescription: field(PROPERTY.visualDescription),
      materialFeel: field(PROPERTY.materialFeel),
      coverage: field(PROPERTY.coverage),
      hasHood: field(PROPERTY.hasHood),
      frontClosure: field(PROPERTY.frontClosure),
      visibleBulk: field(PROPERTY.visibleBulk),
      surfaceAppearance: field(PROPERTY.surfaceAppearance),
      necklineShape: field(PROPERTY.necklineShape),
      visiblePocketStructure: field(PROPERTY.visiblePocketStructure),
      visibleStretchCue: field(PROPERTY.visibleStretchCue),
      sportyCues: field(PROPERTY.sportyCues),
      formalCues: field(PROPERTY.formalCues),
      footwearConstruction: field(PROPERTY.footwearConstruction),
      footwearFastening: field(PROPERTY.footwearFastening),
      soleProfile: field(PROPERTY.soleProfile),
      visibleTread: field(PROPERTY.visibleTread),
      footwearUpperHeight: field(PROPERTY.footwearUpperHeight),
    },
    capabilities: {
      warmth: field(PROPERTY.warmth),
      formality: field(PROPERTY.formality),
      layerRole: field(PROPERTY.layerRole),
      supportedLayerRoles: field(PROPERTY.supportedLayerRoles),
      mobility: field(PROPERTY.mobility),
      breathability: field(PROPERTY.breathability),
      windProtection: field(PROPERTY.windProtection),
      rainProtection: field(PROPERTY.rainProtection),
      walkingComfort: field(PROPERTY.walkingComfort),
      traction: field(PROPERTY.traction),
      rainSuitability: field(PROPERTY.rainSuitability),
      outdoorSuitability: field(PROPERTY.outdoorSuitability),
    },
    suitability: {
      seasons: field(PROPERTY.seasons),
      occasions: field(PROPERTY.occasions),
      activities: field(PROPERTY.activities),
      terrain: field(PROPERTY.terrain),
    },
    metadata: {
      schemaVersion: 1,
      taxonomyVersion: 1,
      resolverVersion: 1,
      revision: 0,
    },
    evidence: usableEvidence.map(projectEvidenceWire),
  });
}

function decodeResolverInput(raw) {
  if (!isObject(raw)) fail("resolver_input_invalid");
  for (const field of FORBIDDEN_AUTHORITY_FIELDS) {
    if (Object.hasOwn(raw, field)) fail(`forged_authority_field:${field}`);
  }
  if (raw.inputContract !== undefined && raw.inputContract !== INPUT_CONTRACT) {
    fail("resolver_input_contract_invalid");
  }
  if (raw.providerVersion !== undefined &&
      raw.providerVersion !== PROVIDER_VERSION) {
    fail("resolver_version_invalid");
  }
  if (raw.resolverCompatibilityVersion !== undefined &&
      raw.resolverCompatibilityVersion !== RESOLVER_COMPATIBILITY_VERSION) {
    fail("resolver_compatibility_version_unsupported");
  }
  const itemId = requireText(raw.itemId, "item_id_required");
  if (!Array.isArray(raw.evidence)) fail("evidence_required");
  const evidence = raw.evidence.map((item, index) =>
    decodeEvidence(item, index));
  return {itemId, evidence};
}

function decodeEvidence(value, index) {
  if (!isObject(value)) fail(`evidence_invalid:${index}`);
  const id = requireText(value.id, `evidence_id_required:${index}`);
  const property = requireText(value.property, `evidence_property_required:${index}`);
  if (!EVIDENCE_SOURCE_INDEX.hasOwnProperty(value.source)) {
    fail(`evidence_source_invalid:${index}`);
  }
  if (!EVIDENCE_NATURES.has(value.nature)) {
    fail(`evidence_nature_invalid:${index}`);
  }
  requireText(value.method, `evidence_method_required:${index}`);
  requireConfidence(value.confidence, `evidence_confidence_invalid:${index}`);
  if (!Object.hasOwn(value, "value")) fail(`evidence_value_omitted:${index}`);
  const valueState = Object.hasOwn(value, "valueState") ?
    value.valueState : "known";
  if (!VALUE_STATES.has(valueState)) {
    fail(`evidence_value_state_invalid:${index}`);
  }
  if (valueState !== "known" && value.value !== null) {
    fail(`non_value_evidence_value_invalid:${index}`);
  }
  if (typeof value.active !== "boolean") fail(`evidence_active_invalid:${index}`);
  if (typeof value.verified !== "boolean") {
    fail(`evidence_verified_invalid:${index}`);
  }
  requireTimestamp(value.createdAt, `created_at_invalid:${index}`);
  return structuredClone(value);
}

function sanitizeEvidence(evidence) {
  const active = evidence.filter((item) => item.active === true);
  const invalidDuplicateIds = new Set();
  const firstById = new Map();
  for (const item of active) {
    const first = firstById.get(item.id);
    if (first == null) {
      firstById.set(item.id, item);
    } else if (!sameAssertion(first, item)) {
      invalidDuplicateIds.add(item.id);
    }
  }
  const supersededIds = new Set();
  for (const item of active.filter(isUsableAssertion)) {
    const supersededId = item.supersedesEvidenceId;
    if (supersededId == null) continue;
    const target = firstById.get(supersededId);
    if (target != null && target.property === item.property) {
      supersededIds.add(supersededId);
    }
  }
  return active
    .filter((item) =>
      !invalidDuplicateIds.has(item.id) &&
      !supersededIds.has(item.id) &&
      isUsableAssertion(item))
    .sort(compareEvidenceIdentity);
}

function isUsableAssertion(item) {
  if (typeof item.id !== "string" || item.id.trim() === "" ||
      typeof item.property !== "string" || item.property.trim() === "" ||
      typeof item.method !== "string" || item.method.trim() === "" ||
      typeof item.confidence !== "number" || !Number.isFinite(item.confidence) ||
      item.confidence < 0 || item.confidence > 1 ||
      !ALL_PROPERTIES.has(item.property)) {
    return false;
  }
  const valueState = Object.hasOwn(item, "valueState") ?
    item.valueState : "known";
  return valueState !== "known" ||
    normalizeUntyped(item.property, item.value) != null;
}

function sameAssertion(left, right) {
  const leftState = Object.hasOwn(left, "valueState") ?
    left.valueState : "known";
  const rightState = Object.hasOwn(right, "valueState") ?
    right.valueState : "known";
  return left.property === right.property &&
    valueKey(left.value) === valueKey(right.value) &&
    leftState === rightState &&
    left.source === right.source &&
    left.nature === right.nature &&
    left.confidence === right.confidence &&
    left.verified === right.verified &&
    left.active === right.active &&
    left.method === right.method &&
    left.createdAt === right.createdAt &&
    (left.modelVersion ?? null) === (right.modelVersion ?? null) &&
    (left.sourceReference ?? null) === (right.sourceReference ?? null) &&
    (left.supersedesEvidenceId ?? null) ===
      (right.supersedesEvidenceId ?? null) &&
    (left.dependsOnCanonicalType ?? null) ===
      (right.dependsOnCanonicalType ?? null);
}

function resolveField(property, evidence, resolvedCanonicalType = null) {
  const fieldPolicy = POLICIES[property] ?? DEFAULT_POLICY;
  const candidates = [];
  for (const item of evidence) {
    if (item.property !== property) continue;
    if (isStaleOrUnsafeDefault(item, property, resolvedCanonicalType)) {
      continue;
    }
    const valueState = Object.hasOwn(item, "valueState") ?
      item.valueState : "known";
    if (valueState === "unknown" || valueState === "not_visible") continue;
    const normalized = valueState === "not_applicable" ?
      null : normalizeUntyped(property, item.value, {
        collectionAsSet: property === PROPERTY.seasons ||
          property === PROPERTY.occasions ||
          property === PROPERTY.activities ||
          property === PROPERTY.terrain,
      });
    if (normalized == null && valueState !== "not_applicable") continue;
    candidates.push({
      evidence: item,
      value: normalized == null ? null : normalized.output,
      valueKey: valueState === "not_applicable" ?
        "state:not_applicable" : normalized.valueKey,
      authority: authorityFor(fieldPolicy, item.source),
      quality: quality(fieldPolicy, item),
      valueState,
    });
  }
  if (candidates.length === 0) return unknownField();
  candidates.sort(compareCandidates);
  const winner = candidates[0];
  const sameValue = candidates.filter(
    (candidate) => candidate.valueKey === winner.valueKey);
  const significantConflicts = candidates.filter((candidate) =>
    candidate.valueKey !== winner.valueKey &&
    isSignificantConflict(winner, candidate));
  const unresolved = significantConflicts.some((candidate) =>
    isUnresolvablePair(winner, candidate));
  const conflictIds = significantConflicts
    .map((candidate) => candidate.evidence.id)
    .sort(compareUtf16);
  if (unresolved) {
    return unknownField({
      resolutionReason: "unresolved_high_authority_conflict",
      conflictingEvidenceIds: [winner.evidence.id, ...conflictIds]
        .sort(compareUtf16),
    });
  }
  const winningIds = sameValue.map((item) => item.evidence.id).sort(compareUtf16);
  if (winner.valueState === "not_applicable") {
    return notApplicableField({
      nature: winner.evidence.nature,
      winningSource: winner.evidence.source,
      confidence: winner.evidence.confidence,
      winningEvidenceIds: winningIds,
      conflictingEvidenceIds: conflictIds,
      userCorrected: winner.evidence.source === "user_correction",
      resolutionReason: resolutionReason(winner, conflictIds.length > 0),
    });
  }
  return knownField({
    value: winner.value,
    nature: winner.evidence.nature,
    winningSource: winner.evidence.source,
    confidence: winner.evidence.confidence,
    winningEvidenceIds: winningIds,
    conflictingEvidenceIds: conflictIds,
    userCorrected: winner.evidence.source === "user_correction",
    resolutionReason: resolutionReason(winner, conflictIds.length > 0),
  });
}

function isStaleOrUnsafeDefault(evidence, property, resolvedCanonicalType) {
  if (evidence.nature !== "defaulted" ||
      !CANONICAL_DEPENDENT_PROPERTIES.has(property)) {
    return false;
  }
  const dependency = typeof evidence.dependsOnCanonicalType === "string" ?
    evidence.dependsOnCanonicalType.trim() : "";
  if (dependency === "") {
    return resolvedCanonicalType != null;
  }
  return resolvedCanonicalType != null &&
    normalizedString(dependency) !== normalizedString(resolvedCanonicalType);
}

function isSignificantConflict(winner, challenger) {
  if (challenger.evidence.source === "user_correction") return true;
  if (challenger.evidence.nature === "defaulted" ||
      challenger.evidence.nature === "unknown") {
    return false;
  }
  return challenger.authority >= 60 &&
    (challenger.evidence.verified === true ||
      challenger.evidence.confidence >= 0.6);
}

function isUnresolvablePair(winner, challenger) {
  if (winner.evidence.source === "user_correction") return false;
  return winner.authority >= 80 &&
    challenger.authority >= 80 &&
    winner.authority === challenger.authority &&
    winner.evidence.confidence >= 0.6 &&
    challenger.evidence.confidence >= 0.6;
}

function resolutionReason(winner, hasConflict) {
  if (winner.evidence.source === "user_correction") {
    return hasConflict ?
      "user_correction_overrode_conflict" : "user_correction";
  }
  const base = `selected_${winner.evidence.source}`;
  return hasConflict ? `${base}_with_conflict` : base;
}

function quality(fieldPolicy, evidence) {
  const natureAdjustment = evidence.nature === "observed" ? 4 :
    evidence.nature === "inferred" ? 0 :
      evidence.nature === "defaulted" ? -15 : -8;
  const verifiedAdjustment = evidence.verified === true ? 4 : 0;
  const confidenceAdjustment = Math.round(evidence.confidence * 5);
  return authorityFor(fieldPolicy, evidence.source) * 100 +
    natureAdjustment * 10 +
    verifiedAdjustment * 10 +
    confidenceAdjustment;
}

function authorityFor(fieldPolicy, source) {
  switch (source) {
  case "user_correction": return 100;
  case "verified_product_metadata": return fieldPolicy.verifiedProduct;
  case "label_metadata": return fieldPolicy.label;
  case "visual_observation": return fieldPolicy.visual;
  case "ai_inference": return fieldPolicy.ai;
  case "knowledge_base_prior": return fieldPolicy.kb;
  case "legacy_fallback": return fieldPolicy.legacy;
  default: fail(`evidence_source_invalid:${source}`);
  }
}

function normalizeUntyped(property, raw, {collectionAsSet = false} = {}) {
  if (COLLECTION_PROPERTIES.has(property)) {
    if (property === PROPERTY.supportedLayerRoles) {
      return normalizeLayerRoles(raw);
    }
    return normalizeCollection(raw, collectionAsSet);
  }
  if (property === PROPERTY.warmth || property === PROPERTY.formality) {
    const level = normalizeLevel(raw);
    return level == null ? null : {
      output: level,
      valueKey: `int:${level}`,
    };
  }
  if (property === PROPERTY.layerRole) {
    return normalizeEnumValue(raw, LAYER_ROLES, "WardrobeLayerRole", {
      aliasKey: (key) => key.replaceAll("-", "_"),
      aliases: {shoes: "footwear"},
    });
  }
  if (CAPABILITY_LEVEL_PROPERTIES.has(property)) {
    return normalizeCapabilityLevel(raw);
  }
  if (property === PROPERTY.coverage) {
    return normalizeEnumValue(raw, COVERAGE, "GarmentCoverage");
  }
  if (BOOLEAN_OBSERVATION_PROPERTIES.has(property)) {
    return typeof raw === "boolean" ?
      {output: raw, valueKey: `bool:${raw}`} : null;
  }
  if (property === PROPERTY.frontClosure) {
    return normalizeEnumValue(raw, FRONT_CLOSURE, "FrontClosure");
  }
  if (VISUAL_AMOUNT_PROPERTIES.has(property)) {
    return normalizeEnumValue(raw, VISUAL_AMOUNT, "VisualAmount");
  }
  if (property === PROPERTY.surfaceAppearance) {
    return normalizeEnumValue(raw, SURFACE_APPEARANCE, "SurfaceAppearance");
  }
  if (property === PROPERTY.necklineShape) {
    return normalizeEnumValue(raw, NECKLINE_SHAPE, "NecklineShape");
  }
  if (property === PROPERTY.visiblePocketStructure) {
    return normalizeEnumValue(raw, VISIBLE_POCKET, "VisiblePocketStructure");
  }
  if (property === PROPERTY.footwearConstruction) {
    return normalizeEnumValue(raw, FOOTWEAR_CONSTRUCTION, "FootwearConstruction");
  }
  if (property === PROPERTY.footwearFastening) {
    return normalizeEnumValue(raw, FOOTWEAR_FASTENING, "FootwearFastening");
  }
  if (property === PROPERTY.soleProfile) {
    return normalizeEnumValue(raw, SOLE_PROFILE, "SoleProfile");
  }
  if (property === PROPERTY.visibleTread) {
    return normalizeEnumValue(raw, VISIBLE_TREAD, "VisibleTread");
  }
  if (property === PROPERTY.footwearUpperHeight) {
    return normalizeEnumValue(raw, FOOTWEAR_UPPER_HEIGHT, "FootwearUpperHeight");
  }
  if (property === PROPERTY.rainSuitability) {
    return normalizeEnumValue(raw, RAIN_SUITABILITY, "RainSuitability");
  }
  const stringValue = normalizeString(raw);
  return stringValue == null ? null : {
    output: stringValue,
    valueKey: `string:${normalizedString(stringValue)}`,
  };
}

function normalizeCollection(raw, asSet) {
  if (!Array.isArray(raw)) return null;
  const byKey = new Map();
  for (const value of raw) {
    const normalized = normalizeString(value);
    if (normalized == null) return null;
    const key = normalizedString(normalized);
    if (!byKey.has(key)) byKey.set(key, normalized);
  }
  if (byKey.size === 0) return null;
  const values = [...byKey.values()].sort((left, right) =>
    compareUtf16(normalizedString(left), normalizedString(right)));
  return {
    output: values,
    valueKey: `[${values.map((item) =>
      `string:${normalizedString(item)}`).sort(compareUtf16).join("|")}]`,
  };
}

function normalizeLevel(raw) {
  if (typeof raw === "number" && Number.isInteger(raw)) return raw;
  if (typeof raw === "number" && Number.isFinite(raw) &&
      raw === Math.round(raw)) {
    return raw;
  }
  return null;
}

function normalizeString(raw) {
  if (typeof raw !== "string") return null;
  const value = raw.trim();
  return value === "" || normalizedString(value) === "unknown" ? null : value;
}

function normalizeCapabilityLevel(raw) {
  if (typeof raw !== "string") return null;
  const key = normalizedString(raw);
  for (const item of CAPABILITY_LEVELS) {
    if (item.aliases.includes(key)) {
      return {
        output: item.wire,
        valueKey: `CapabilityLevel:${item.dartName}`,
      };
    }
  }
  return null;
}

function normalizeLayerRoles(raw) {
  if (!Array.isArray(raw)) return null;
  const roles = [];
  const seen = new Set();
  for (const value of raw) {
    const role = normalizeEnumValue(value, LAYER_ROLES, "WardrobeLayerRole", {
      aliasKey: (key) => key.replaceAll("-", "_"),
      aliases: {shoes: "footwear"},
    });
    if (role == null) return null;
    if (!seen.has(role.output)) {
      seen.add(role.output);
      roles.push(role);
    }
  }
  if (roles.length === 0) return null;
  roles.sort((left, right) => compareUtf16(left.output, right.output));
  return {
    output: roles.map((item) => item.output),
    valueKey: `[${roles.map((item) => item.valueKey).sort(compareUtf16)
      .join("|")}]`,
  };
}

function normalizeEnumValue(raw, table, typeName, options = {}) {
  if (typeof raw !== "string") return null;
  let key = normalizedString(raw);
  if (options.aliasKey) key = options.aliasKey(key);
  if (options.aliases && options.aliases[key]) {
    key = options.aliases[key];
  }
  for (const item of table) {
    if (normalizedString(item.wire) === key ||
        normalizedString(item.dartName) === key) {
      return {
        output: item.wire,
        valueKey: `${typeName}:${item.dartName}`,
      };
    }
  }
  return null;
}

function valueKey(value) {
  if (Array.isArray(value)) {
    const elements = value.map((item) => valueKey(item)).sort(compareUtf16);
    return `[${elements.join("|")}]`;
  }
  if (typeof value === "string") {
    return `string:${normalizedString(value)}`;
  }
  if (typeof value === "boolean") return `bool:${value}`;
  if (typeof value === "number") return `int:${value}`;
  if (value == null) return "Null:null";
  return `${typeof value}:${value}`;
}

function compareEvidenceIdentity(left, right) {
  const id = compareUtf16(left.id, right.id);
  if (id !== 0) return id;
  const property = compareUtf16(left.property, right.property);
  if (property !== 0) return property;
  return compareUtf16(valueKey(left.value), valueKey(right.value));
}

function compareCandidates(left, right) {
  const qualityCmp = right.quality - left.quality;
  if (qualityCmp !== 0) return qualityCmp < 0 ? -1 : 1;
  const source = EVIDENCE_SOURCE_INDEX[left.evidence.source] -
    EVIDENCE_SOURCE_INDEX[right.evidence.source];
  if (source !== 0) return source;
  return compareEvidenceIdentity(left.evidence, right.evidence);
}

function unknownField({
  resolutionReason = "insufficient_evidence",
  conflictingEvidenceIds = [],
} = {}) {
  const result = {
    value: null,
    isKnown: false,
    state: "unknown",
    confidence: 0,
    userCorrected: false,
    resolutionReason,
  };
  if (conflictingEvidenceIds.length > 0) {
    result.conflictingEvidenceIds = conflictingEvidenceIds;
  }
  return result;
}

function notApplicableField({
  nature,
  winningSource,
  confidence,
  winningEvidenceIds,
  conflictingEvidenceIds,
  userCorrected,
  resolutionReason,
}) {
  const result = {
    value: null,
    isKnown: false,
    state: "not_applicable",
    nature,
    winningSource,
    confidence,
    userCorrected,
    resolutionReason,
  };
  if (winningEvidenceIds.length > 0) {
    result.winningEvidenceIds = winningEvidenceIds;
  }
  if (conflictingEvidenceIds.length > 0) {
    result.conflictingEvidenceIds = conflictingEvidenceIds;
  }
  return result;
}

function knownField({
  value,
  nature,
  winningSource,
  confidence,
  winningEvidenceIds,
  conflictingEvidenceIds,
  userCorrected,
  resolutionReason,
}) {
  const result = {
    value,
    isKnown: true,
    state: "known",
    nature,
    winningSource,
    confidence,
    userCorrected,
    resolutionReason,
  };
  if (winningEvidenceIds.length > 0) {
    result.winningEvidenceIds = winningEvidenceIds;
  }
  if (conflictingEvidenceIds.length > 0) {
    result.conflictingEvidenceIds = conflictingEvidenceIds;
  }
  return result;
}

function projectEvidenceWire(item) {
  const valueState = Object.hasOwn(item, "valueState") ?
    item.valueState : "known";
  const result = {
    id: item.id,
    property: item.property,
    value: cloneValue(item.value),
    source: item.source,
    nature: item.nature,
    confidence: item.confidence,
    verified: item.verified === true,
    active: item.active !== false,
    method: item.method,
    createdAt: item.createdAt,
  };
  if (valueState !== "known") result.valueState = valueState;
  if (item.modelVersion != null) result.modelVersion = item.modelVersion;
  if (item.sourceReference != null) {
    result.sourceReference = item.sourceReference;
  }
  if (item.dependsOnCanonicalType != null) {
    result.dependsOnCanonicalType = item.dependsOnCanonicalType;
  }
  if (item.supersedesEvidenceId != null) {
    result.supersedesEvidenceId = item.supersedesEvidenceId;
  }
  return result;
}

function normalizedString(value) {
  return value.trim().toLowerCase();
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

function decodeResolverOracle(value) {
  if (!isObject(value)) fail("resolver_oracle_invalid");
  return structuredClone(value);
}

module.exports = {
  FORBIDDEN_AUTHORITY_FIELDS,
  INPUT_CONTRACT,
  ORACLE_CONTRACT_VERSION,
  OUTPUT_CONTRACT,
  PROPERTY,
  PROVIDER_ID,
  PROVIDER_VERSION,
  RESOLVER_COMPATIBILITY_VERSION,
  decodeResolverOracle,
  resolveWardrobeProfile,
};
