"use strict";

/**
 * Node port of Dart WardrobeKnowledgeBasePriorProvider.provide.
 *
 * Pure / sync / deterministic.
 * Knowledge Base data comes only from the generated artifact via
 * clothing_knowledge_base_prior_loader.js — no hand-maintained JS registry.
 *
 * Structured category|subcategory taxonomy used by the document path comes
 * from the deploy-packaged CanonicalResolver artifact (Dart source of truth),
 * not from runtime Dart file reads.
 */

const crypto = require("node:crypto");
const {
  loadClothingKnowledgeBasePriorArtifact,
} = require("./clothing_knowledge_base_prior_loader");
const {
  loadCanonicalResolverStructuredTaxonomyArtifact,
} = require("./canonical_resolver_structured_taxonomy_loader");
const {
  DOCUMENT_ALLOW_LIST,
} = require("./prepare_vision_knowledge_base_prior_input");

const PROVIDER_ID = "WardrobeKnowledgeBasePriorProvider";
const PROVIDER_VERSION = "wardrobe-kb-prior-provider-v1";
const INPUT_CONTRACT = "wardrobe_kb_prior_input/v1";
const OUTPUT_CONTRACT = "ProfileEvidence[]/kb_prior_v1";
const ORACLE_CONTRACT_VERSION = 1;
const TIMELESS_PRIOR_TIMESTAMP = "1970-01-01T00:00:00.000Z";

const PROPERTY = Object.freeze({
  canonicalType: "identity.canonicalType",
  mainCategory: "identity.mainCategory",
  category: "identity.category",
  subcategory: "identity.subcategory",
  layerRole: "capabilities.layerRole",
  warmth: "capabilities.warmth",
  formality: "capabilities.formality",
});

const EVIDENCE_SOURCES = new Set([
  "visual_observation",
  "ai_inference",
  "product_metadata",
  "user_correction",
  "legacy_fallback",
  "knowledge_base_prior",
  "label_ocr",
]);
const EVIDENCE_NATURES = new Set([
  "observed",
  "inferred",
  "defaulted",
  "asserted",
]);
const VALUE_STATES = new Set([
  "known",
  "unknown",
  "not_visible",
  "not_applicable",
]);

const {
  categorySubCanonical,
  ambiguousStructuredKeys,
  structuredTaxonomySourceSha256,
} = loadStructuredTaxonomy();

/**
 * @param {object} rawInput wardrobe_kb_prior_input/v1
 * @param {{
 *   kbArtifact?: object,
 *   expectedArtifactContentSha256?: string,
 *   expectedArtifactSchemaVersion?: number,
 * }} [options]
 * @returns {ReadonlyArray<object>}
 */
function provideWardrobeKnowledgeBasePriors(rawInput, options = {}) {
  const input = decodeProviderInput(rawInput);
  const kbArtifact = options.kbArtifact ??
    loadClothingKnowledgeBasePriorArtifact({
      expectedContentSha256: options.expectedArtifactContentSha256,
      expectedSchemaVersion: options.expectedArtifactSchemaVersion,
    });
  const lookup = buildKbLookup(kbArtifact);
  const existing = input.existingEvidence;
  const explicitCanonical = singleKnownCanonical(existing, lookup);
  const hasNonDefaultCanonical = existing.some((item) =>
    item.active &&
    item.property === PROPERTY.canonicalType &&
    item.nature !== "defaulted");
  const inferredCanonical = explicitCanonical == null ?
    structuredCanonicalCandidate(input.document, lookup) : null;
  const canonical = explicitCanonical ??
    inferredCanonical?.kb.canonicalType ?? null;
  if (canonical == null) return deepFreeze([]);

  const kb = lookup.findByCanonicalType(canonical);
  if (kb == null) return deepFreeze([]);

  const evidence = [];
  if (!hasNonDefaultCanonical) {
    evidence.push(buildEvidence({
      property: PROPERTY.canonicalType,
      value: kb.canonicalType,
      canonicalType: kb.canonicalType,
      nature: explicitCanonical == null ? "inferred" : "defaulted",
      method: explicitCanonical == null ?
        inferredCanonical.method : "kb_prior:classified_legacy_canonical",
      confidence: explicitCanonical == null ? 0.45 : 0.35,
      typeDependent: false,
      sourceReference: explicitCanonical == null ?
        inferredCanonical.sourceReference : null,
    }));
  }

  const addDefault = (property, value) => {
    if (!canSupplyDefault(property, existing)) return;
    evidence.push(buildEvidence({
      property,
      value,
      canonicalType: kb.canonicalType,
    }));
  };

  addDefault(PROPERTY.mainCategory, kb.mainCategory);
  addDefault(PROPERTY.category, kb.category);
  addDefault(PROPERTY.subcategory, kb.subcategory);
  addDefault(PROPERTY.layerRole, kb.layerRole);
  addDefault(PROPERTY.warmth, kb.warmthDefault);
  addDefault(PROPERTY.formality, kb.formalityDefault);

  return deepFreeze(evidence);
}

function decodeProviderInput(raw) {
  if (!isObject(raw)) fail("kb_prior_input_invalid");
  if (Object.hasOwn(raw, "providerInput") ||
      Object.hasOwn(raw, "preparedProviderInput") ||
      Object.hasOwn(raw, "resolvedProfile") ||
      Object.hasOwn(raw, "knowledgeBaseEvidence")) {
    fail("forged_client_prepared_input");
  }
  if (raw.inputContract !== undefined && raw.inputContract !== INPUT_CONTRACT) {
    fail("kb_prior_input_contract_invalid");
  }
  if (raw.providerVersion !== undefined &&
      raw.providerVersion !== PROVIDER_VERSION) {
    fail("kb_prior_provider_version_invalid");
  }
  if (!isObject(raw.document)) fail("kb_prior_document_invalid");
  for (const key of Object.keys(raw.document)) {
    if (!DOCUMENT_ALLOW_LIST.includes(key)) {
      fail(`document_field_not_allow_listed:${key}`);
    }
  }
  if (!Array.isArray(raw.existingEvidence)) {
    fail("kb_prior_existing_evidence_invalid");
  }
  const ids = new Set();
  const existingEvidence = raw.existingEvidence.map((item, index) => {
    const decoded = decodeEvidence(item, index);
    if (ids.has(decoded.id)) fail(`duplicate_evidence_id:${decoded.id}`);
    ids.add(decoded.id);
    if (decoded.source === "knowledge_base_prior" ||
        decoded.id.startsWith("kb-prior:")) {
      fail("forged_kb_prior_evidence");
    }
    return decoded;
  });
  return {
    document: structuredClone(raw.document),
    existingEvidence,
  };
}

function decodeEvidence(value, index) {
  if (!isObject(value)) fail(`evidence_invalid:${index}`);
  const id = requireText(value.id, `evidence_id_required:${index}`);
  const property = requireText(value.property, `evidence_property_required:${index}`);
  if (!EVIDENCE_SOURCES.has(value.source)) {
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
  requireTimestamp(value.createdAt, `created_at_invalid:${index}`);
  return {
    id,
    property,
    value: cloneValue(value.value),
    valueState,
    source: value.source,
    nature: value.nature,
    confidence: value.confidence,
    method: value.method,
    createdAt: value.createdAt,
    active: value.active !== false,
    verified: value.verified === true,
    modelVersion: Object.hasOwn(value, "modelVersion") ?
      requireText(value.modelVersion, `model_version_invalid:${index}`) :
      undefined,
    sourceReference: Object.hasOwn(value, "sourceReference") ?
      requireText(value.sourceReference, `source_reference_invalid:${index}`) :
      undefined,
    dependsOnCanonicalType: Object.hasOwn(value, "dependsOnCanonicalType") ?
      requireText(value.dependsOnCanonicalType,
        `depends_on_invalid:${index}`) : undefined,
    supportingEvidenceIds: Object.hasOwn(value, "supportingEvidenceIds") ?
      requireStringArray(value.supportingEvidenceIds,
        `supporting_evidence_ids_invalid:${index}`) : undefined,
  };
}

function singleKnownCanonical(evidence, lookup) {
  const values = new Set();
  for (const item of evidence) {
    if (!item.active || item.property !== PROPERTY.canonicalType) continue;
    if (typeof item.value !== "string") continue;
    const trimmed = item.value.trim();
    if (trimmed.length === 0) continue;
    const kb = lookup.findByCanonicalType(trimmed);
    if (kb == null) continue;
    values.add(kb.canonicalType);
  }
  return values.size === 1 ? [...values][0] : null;
}

function canSupplyDefault(property, existing) {
  return !existing.some((item) =>
    item.active &&
    item.property === property &&
    item.nature !== "defaulted");
}

function structuredCanonicalCandidate(document, lookup) {
  if (hasAliasConflict(document, ["mainGroupKey", "mainGroup"]) ||
      hasAliasConflict(document, ["categoryKey", "category"]) ||
      hasAliasConflict(document, ["subCategoryKey", "subCategory"]) ||
      hasAliasConflict(document, ["primary_type", "primaryType"]) ||
      hasAliasConflict(document, ["secondary_type", "secondaryType"])) {
    return null;
  }
  const mainGroup = firstString(document, ["mainGroupKey", "mainGroup"]);
  const category = firstString(document, ["categoryKey", "category"]);
  const subcategory = firstString(document, ["subCategoryKey", "subCategory"]);
  const primaryType = firstString(document, ["primary_type", "primaryType"]);
  const secondaryType = firstString(document, ["secondary_type", "secondaryType"]);

  const candidates = [];
  const taxonomy = resolveStructuredTaxonomy(document, lookup);
  if (taxonomy != null) {
    const kb = lookup.findByCanonicalType(taxonomy.canonicalType);
    if (kb != null) {
      candidates.push({
        kb,
        method: "kb_prior:structured_taxonomy",
        sourceReference:
          `structured_taxonomy:${mainGroup ?? ""}|${category ?? ""}|${subcategory ?? ""}`,
      });
    }
  }

  const addStructuredType = (value, field) => {
    if (value == null) return;
    const kb = lookup.findByCanonicalType(value) ??
      lookup.findByAlias(value);
    if (kb == null) return;
    candidates.push({
      kb,
      method: `kb_prior:structured_${field}`,
      sourceReference: `structured_${field}:${value}`,
    });
  };
  addStructuredType(primaryType, "primary_type");
  addStructuredType(secondaryType, "secondary_type");
  if (candidates.length === 0) return null;
  const canonicalTypes = new Set(
    candidates.map((item) => item.kb.canonicalType));
  if (canonicalTypes.size !== 1) return null;
  return candidates[0];
}

function resolveStructuredTaxonomy(document, lookup) {
  if (hasStructuredAliasConflict(document, ["categoryKey", "category"]) ||
      hasStructuredAliasConflict(document, ["subCategoryKey", "subCategory"])) {
    return null;
  }
  const categoryKey = firstString(document, ["categoryKey", "category"]);
  const subCategoryKey = firstString(document, ["subCategoryKey", "subCategory"]);
  const category = normalizeResolverKey(categoryKey ?? "");
  const subcategory = normalizeResolverKey(subCategoryKey ?? "");
  if (category.length === 0 || subcategory.length === 0) return null;
  const compositeKey = `${category}|${subcategory}`;
  if (ambiguousStructuredKeys.has(compositeKey)) return null;
  const canonicalType = categorySubCanonical.get(compositeKey);
  if (canonicalType == null) return null;
  if (lookup.findByCanonicalType(canonicalType) == null) return null;
  return {canonicalType};
}

function buildEvidence({
  property,
  value,
  canonicalType,
  nature = "defaulted",
  method = "kb_prior:canonical_type_defaults",
  confidence = 0.35,
  typeDependent = true,
  sourceReference = null,
}) {
  const result = {
    id: `kb-prior:${canonicalType}:${property}`,
    property,
    value: cloneValue(value),
    source: "knowledge_base_prior",
    nature,
    confidence,
    verified: false,
    active: true,
    method,
    createdAt: TIMELESS_PRIOR_TIMESTAMP,
    sourceReference: sourceReference ??
      `clothing_knowledge_base:${canonicalType}`,
  };
  if (typeDependent) {
    result.dependsOnCanonicalType = canonicalType;
  }
  return result;
}

function buildKbLookup(artifact) {
  const byCanonical = new Map();
  const byAlias = new Map();
  for (const item of artifact.items) {
    byCanonical.set(normalizeMatchKey(item.canonicalType), item);
    for (const alias of item.aliases) {
      const key = normalizeMatchKey(alias);
      if (key.length === 0) continue;
      if (!byAlias.has(key)) byAlias.set(key, item);
    }
  }
  return {
    findByCanonicalType(value) {
      const key = normalizeMatchKey(value);
      if (key.length === 0) return null;
      return byCanonical.get(key) ?? null;
    },
    findByAlias(value) {
      const key = normalizeMatchKey(value);
      if (key.length === 0) return null;
      return byAlias.get(key) ?? null;
    },
  };
}

function normalizeMatchKey(raw) {
  let out = String(raw).trim().toLowerCase();
  if (out.length === 0) return "";
  out = stripDiacritics(out);
  out = out.replace(/[\s_\-/]+/g, "");
  return out;
}

function normalizeResolverKey(raw) {
  let out = String(raw).trim().toLowerCase();
  if (out.length === 0) return "";
  out = stripDiacritics(out);
  out = out.replace(/[\s_\-/|]+/g, "");
  return out;
}

function stripDiacritics(value) {
  const repl = {
    á: "a", ä: "a", č: "c", ď: "d", é: "e", ě: "e", í: "i", ĺ: "l", ľ: "l",
    ň: "n", ó: "o", ô: "o", ŕ: "r", ř: "r", š: "s", ť: "t", ú: "u", ů: "u",
    ü: "u", ý: "y", ž: "z",
  };
  let out = "";
  for (const ch of value) out += repl[ch] ?? ch;
  return out;
}

function firstString(document, keys) {
  for (const key of keys) {
    const value = document[key];
    if (typeof value !== "string") continue;
    const trimmed = value.trim();
    if (trimmed.length > 0) return trimmed;
  }
  return null;
}

function hasAliasConflict(document, keys) {
  const values = new Set();
  for (const key of keys) {
    const value = document[key];
    if (typeof value !== "string") continue;
    const trimmed = value.trim().toLowerCase();
    if (trimmed.length > 0) values.add(trimmed);
  }
  return values.size > 1;
}

function hasStructuredAliasConflict(document, keys) {
  const values = new Set();
  for (const key of keys) {
    const normalized = normalizeResolverKey(String(document[key] ?? ""));
    if (normalized.length > 0) values.add(normalized);
  }
  return values.size > 1;
}

function loadStructuredTaxonomy() {
  const loaded = loadCanonicalResolverStructuredTaxonomyArtifact();
  return {
    categorySubCanonical: loaded.categorySubCanonical,
    ambiguousStructuredKeys: loaded.ambiguousStructuredKeys,
    structuredTaxonomySourceSha256: loaded.structuredTaxonomySourceSha256,
  };
}

function decodeKbPriorOracle(value) {
  if (!isObject(value)) fail("oracle_root_invalid");
  if (value.oracleVersion !== ORACLE_CONTRACT_VERSION) {
    fail("oracle_version_unsupported");
  }
  if (value.providerId !== PROVIDER_ID) fail("oracle_provider_id_invalid");
  if (value.providerVersion !== PROVIDER_VERSION) {
    fail("oracle_provider_version_invalid");
  }
  requireText(value.scenarioId, "oracle_scenario_id_required");
  if (!Array.isArray(value.invocations) || value.invocations.length !== 1) {
    fail("oracle_invocations_invalid");
  }
  const invocation = value.invocations[0];
  const providerInput = invocation.providerInput;
  decodeProviderInput(providerInput);
  if (!Array.isArray(invocation.providerOutput)) {
    fail("oracle_provider_output_invalid");
  }
  return deepFreeze({
    scenarioId: value.scenarioId,
    invocations: [{
      invocationId: requireText(
        invocation.invocationId, "invocation_id_required"),
      providerInput: structuredClone(providerInput),
      providerOutput: structuredClone(invocation.providerOutput),
    }],
  });
}

function requireStringArray(value, reason) {
  if (!Array.isArray(value) ||
      !value.every((item) => typeof item === "string" && item.length > 0)) {
    fail(reason);
  }
  return [...value];
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
  if (Array.isArray(value)) {
    for (const child of value) deepFreeze(child);
    return Object.freeze(value);
  }
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function fail(reason) {
  throw new Error(reason);
}

module.exports = {
  INPUT_CONTRACT,
  ORACLE_CONTRACT_VERSION,
  OUTPUT_CONTRACT,
  PROPERTY,
  PROVIDER_ID,
  PROVIDER_VERSION,
  TIMELESS_PRIOR_TIMESTAMP,
  decodeKbPriorOracle,
  decodeProviderInput,
  provideWardrobeKnowledgeBasePriors,
  structuredTaxonomySourceSha256,
};
