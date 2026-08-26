"use strict";

const artifact = require("./artifacts/wardrobe_ontology_v2.json");
const TYPES = new Map(artifact.items.map((x) => [x.canonicalType, Object.freeze(x)]));
const SOURCES = new Set(["visual_ai", "knowledge_base", "user_correction", "migration", "system"]);
const ARRAY_FIELDS = ["bodySlots", "styles", "occasionFit", "seasons", "userOverrideFields"];

function fail(code, details = {}) { const error = new Error(code); error.code = code; error.details = details; throw error; }
function canonicalDefinition(type) { return TYPES.get(String(type || "").trim()) || null; }
function resolveCanonicalAlias(value) {
  const key = String(value || "").trim().toLowerCase(); if (!key) return null;
  if (TYPES.has(key)) return key;
  const matches = artifact.items.filter((x) => [...x.aliases, ...x.deprecatedAliases].some((a) => a.toLowerCase() === key));
  return matches.length === 1 ? matches[0].canonicalType : null;
}
function enrichIdentity(canonicalType) {
  const kb = canonicalDefinition(canonicalType); if (!kb) fail("v2_unknown_canonical_type", {canonicalType});
  return {canonicalType: kb.canonicalType, canonicalFamily: kb.canonicalFamily, bodySlots: [...kb.defaultBodySlots], layerPosition: kb.defaultLayerPosition, outfitFunctions: [...kb.outfitFunctions], uiProjection: {...kb.uiProjection}, accessoryGroup: kb.accessoryGroup, multiplicity: {...kb.multiplicity}};
}
function validateColorRole(value, path, errors) {
  if (value == null) return;
  if (typeof value !== "object" || Array.isArray(value)) { errors.push(`${path}.object_required`); return; }
  if (typeof value.family !== "string" || !value.family.trim()) errors.push(`${path}.family_required`);
  if (value.hex != null && !/^#[0-9a-f]{6}$/i.test(value.hex)) errors.push(`${path}.hex_invalid`);
  if (value.proportion != null && (!(typeof value.proportion === "number") || value.proportion < 0 || value.proportion > 1)) errors.push(`${path}.proportion_invalid`);
}
function validateWardrobeItemV2(input, {strict = true} = {}) {
  const errors = [], warnings = [];
  if (!input || typeof input !== "object" || Array.isArray(input)) return {ok:false, errors:["item.object_required"], warnings};
  if (input.ontologyVersion !== artifact.ontologyVersion) errors.push("ontologyVersion.invalid");
  if (input.taxonomyVersion !== artifact.taxonomyVersion) errors.push("taxonomyVersion.invalid");
  if (input.kbVersion !== artifact.kbVersion) errors.push("kbVersion.invalid");
  const kb = canonicalDefinition(input.canonicalType); if (!kb) errors.push("canonicalType.unknown");
  for (const f of ARRAY_FIELDS) if (!Array.isArray(input[f])) errors.push(`${f}.array_required`);
  if (kb) {
    for (const slot of input.bodySlots || []) if (!artifact.enums.bodySlots.includes(slot)) errors.push(`bodySlots.invalid:${slot}`);
    if (!kb.supportedLayerPositions.includes(input.layerPosition)) errors.push("layerPosition.not_supported_for_type");
    if (input.canonicalFamily !== kb.canonicalFamily) errors.push("canonicalFamily.kb_mismatch");
  }
  const cp = input.colorProfile;
  if (!cp || typeof cp !== "object" || Array.isArray(cp)) errors.push("colorProfile.object_required");
  else {
    validateColorRole(cp.primary, "colorProfile.primary", errors); validateColorRole(cp.secondary, "colorProfile.secondary", errors);
    if (!Array.isArray(cp.accents)) errors.push("colorProfile.accents.array_required"); else cp.accents.forEach((x,i)=>validateColorRole(x,`colorProfile.accents.${i}`,errors));
    for (const tone of ["metalTone","hardwareTone"]) if (!artifact.enums.metalTones.includes(cp[tone])) errors.push(`colorProfile.${tone}.invalid`);
  }
  if (!Number.isInteger(input.formality) || input.formality < 1 || input.formality > 10) errors.push("formality.range");
  if (!Number.isInteger(input.warmth) || input.warmth < 1 || input.warmth > 10) {
    errors.push("warmth.range");
  } else if (kb?.warmthRange &&
      (input.warmth < kb.warmthRange.min || input.warmth > kb.warmthRange.max)) {
    errors.push("warmth.out_of_type_range");
  }
  if (input.setMembership != null) {
    const s = input.setMembership;
    if (typeof s !== "object" || !String(s.setId || "").trim() || !String(s.setType || "").trim()) errors.push("setMembership.invalid");
  }
  const attrs = input.attributes;
  if (!attrs || typeof attrs !== "object" || Array.isArray(attrs)) errors.push("attributes.object_required");
  if (!input.fieldSources || typeof input.fieldSources !== "object") errors.push("fieldSources.object_required");
  else for (const [field, source] of Object.entries(input.fieldSources)) if (!SOURCES.has(source)) errors.push(`fieldSources.invalid:${field}`);
  if (!input.fieldConfidence || typeof input.fieldConfidence !== "object") errors.push("fieldConfidence.object_required");
  else for (const [field, confidence] of Object.entries(input.fieldConfidence)) if (typeof confidence !== "number" || confidence < 0 || confidence > 1) errors.push(`fieldConfidence.invalid:${field}`);
  for (const field of input.userOverrideFields || []) {
    const source = input.fieldSources?.[field];
    const validSetAuthority = field === "setMembership" &&
      (source === "user_confirmation" || source === "user_correction");
    if (source !== "user_correction" && !validSetAuthority) {
      errors.push(`userOverrideFields.source_mismatch:${field}`);
    }
  }
  for (const legacy of ["layerRole","layer_role","stylingLayerRole","canonical_type","primary_type"]) if (Object.hasOwn(input, legacy)) (strict ? errors : warnings).push(`legacy_field_present:${legacy}`);
  return {ok: errors.length === 0, errors:[...new Set(errors)].sort(), warnings:[...new Set(warnings)].sort()};
}
function applyAnalyzerResult(existing, analyzerResult) {
  const overrides = new Set(existing?.userOverrideFields || []); const result = {...existing};
  const candidate = analyzerResult.identity?.canonicalType; if (!overrides.has("canonicalType") && candidate) Object.assign(result, enrichIdentity(candidate));
  const mapping = {colorProfile: analyzerResult.observed?.colorProfile, attributes: analyzerResult.observed?.attributes, formality: analyzerResult.inferred?.formality, styles: analyzerResult.inferred?.styles, occasionFit: analyzerResult.inferred?.occasionFit, warmth: analyzerResult.inferred?.warmth};
  result.fieldSources = {...existing?.fieldSources}; result.fieldConfidence = {...existing?.fieldConfidence};
  for (const [field,value] of Object.entries(mapping)) if (!overrides.has(field) && value != null) { result[field] = value; result.fieldSources[field] = "visual_ai"; const c=analyzerResult.evidence?.fieldConfidence?.[field]; if (typeof c === "number") result.fieldConfidence[field]=c; }
  return result;
}

module.exports = {artifact, canonicalDefinition, resolveCanonicalAlias, enrichIdentity, validateWardrobeItemV2, applyAnalyzerResult};
