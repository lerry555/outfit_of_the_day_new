"use strict";

/**
 * Strict read-only loader for the Dart-generated Clothing Knowledge Base
 * prior artifact (clothing-kb-prior-artifact-v1).
 *
 * Not a provider. Does not invent ProfileEvidence, defaults, or fallbacks.
 * Validates schemaVersion + content SHA against the authoritative artifact
 * manifest and returns an immutable validated view.
 */

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ARTIFACT_ID = "ClothingKnowledgeBasePriorArtifact";
const ARTIFACT_VERSION = "clothing-kb-prior-artifact-v1";
const SUPPORTED_SCHEMA_VERSION = 1;

const DEFAULT_ARTIFACT_MANIFEST = path.resolve(__dirname,
  "artifacts/clothing_knowledge_base_prior_v1.manifest.json");

const LAYER_ROLES = new Set([
  "base_layer",
  "mid_layer",
  "outer_layer",
  "bottom",
  "footwear",
  "accessory",
]);

const MAIN_CATEGORIES = new Set([
  "oblecenie",
  "obuv",
  "doplnky",
]);

const REQUIRED_ITEM_FIELDS = Object.freeze([
  "canonicalType",
  "mainCategory",
  "category",
  "subcategory",
  "layerRole",
  "warmthDefault",
  "formalityDefault",
  "aliases",
]);

const FORBIDDEN_ITEM_FIELDS = Object.freeze([
  "skName",
  "categoryLabels",
  "legacyFallback",
  "compatibilityFallback",
  "resolvedDefault",
  "fallback",
]);

/**
 * @param {{
 *   artifactPath?: string,
 *   artifactManifestPath?: string,
 *   expectedContentSha256?: string,
 *   expectedSchemaVersion?: number,
 * }} [options]
 */
function loadClothingKnowledgeBasePriorArtifact(options = {}) {
  const artifactManifestPath = options.artifactManifestPath ??
    DEFAULT_ARTIFACT_MANIFEST;
  const manifest = readJson(artifactManifestPath);
  validateArtifactManifest(manifest);
  const expectedContentSha256 = options.expectedContentSha256 ??
    manifest.artifactContentSha256;
  const expectedSchemaVersion = options.expectedSchemaVersion ??
    manifest.schemaVersion;
  if (expectedSchemaVersion !== SUPPORTED_SCHEMA_VERSION) {
    fail("kb_artifact_unsupported_version");
  }
  const fixtureRoot = path.dirname(path.dirname(artifactManifestPath));
  const artifactPath = options.artifactPath ??
    path.resolve(fixtureRoot, manifest.artifactPath);
  const artifactBytes = fs.readFileSync(artifactPath);
  const contentSha256 = sha256(artifactBytes);
  if (contentSha256 !== expectedContentSha256) {
    fail("kb_artifact_sha_mismatch");
  }
  const artifact = JSON.parse(artifactBytes.toString("utf8"));
  validateArtifactDocument(artifact, {
    expectedSchemaVersion,
    contentSha256,
  });
  const items = artifact.items.map((item) => deepFreeze(structuredClone(item)));
  assertStableOrdering(items);
  return deepFreeze({
    schemaVersion: artifact.schemaVersion,
    artifactId: artifact.artifactId,
    artifactVersion: artifact.artifactVersion,
    contentSha256,
    itemCount: items.length,
    items,
    lookupPolicy: structuredClone(artifact.lookupPolicy),
    providerFields: [...artifact.providerFields],
    excludedFromArtifact: [...artifact.excludedFromArtifact],
    sourceDartPath: artifact.sourceDartPath,
    sourceDartSha256: artifact.sourceDartSha256,
  });
}

function validateArtifactManifest(manifest) {
  if (!isObject(manifest)) fail("kb_artifact_manifest_invalid");
  if (manifest.kind !== "kb_artifact") fail("kb_artifact_manifest_kind_invalid");
  if (manifest.status !== "artifact_ready") {
    fail("kb_artifact_manifest_status_invalid");
  }
  if (manifest.artifactId !== ARTIFACT_ID) {
    fail("kb_artifact_manifest_id_invalid");
  }
  if (manifest.artifactVersion !== ARTIFACT_VERSION) {
    fail("kb_artifact_manifest_version_invalid");
  }
  if (manifest.schemaVersion !== SUPPORTED_SCHEMA_VERSION) {
    fail("kb_artifact_unsupported_version");
  }
  requireSha(manifest.artifactContentSha256, "kb_artifact_manifest_sha_invalid");
  requireText(manifest.artifactPath, "kb_artifact_manifest_path_invalid");
  if (typeof manifest.artifactPath === "string" &&
      (path.isAbsolute(manifest.artifactPath) ||
        manifest.artifactPath.includes(".."))) {
    fail("kb_artifact_absolute_path_rejected");
  }
}

function validateArtifactDocument(artifact, {
  expectedSchemaVersion,
  contentSha256,
}) {
  if (!isObject(artifact)) fail("kb_artifact_root_invalid");
  rejectTimestamps(artifact);
  rejectAbsolutePaths(artifact);
  if (artifact.schemaVersion !== expectedSchemaVersion) {
    fail("kb_artifact_unsupported_version");
  }
  if (artifact.artifactId !== ARTIFACT_ID) fail("kb_artifact_id_invalid");
  if (artifact.artifactVersion !== ARTIFACT_VERSION) {
    fail("kb_artifact_version_invalid");
  }
  if (!Array.isArray(artifact.items)) fail("kb_artifact_items_invalid");
  if (artifact.itemCount !== artifact.items.length) {
    fail("kb_artifact_item_count_mismatch");
  }
  if (!isObject(artifact.lookupPolicy)) fail("kb_artifact_lookup_policy_invalid");
  if (!Array.isArray(artifact.providerFields)) {
    fail("kb_artifact_provider_fields_invalid");
  }
  if (!Array.isArray(artifact.excludedFromArtifact)) {
    fail("kb_artifact_excluded_invalid");
  }
  requireText(artifact.sourceDartPath, "kb_artifact_source_path_invalid");
  if (path.isAbsolute(artifact.sourceDartPath) ||
      artifact.sourceDartPath.includes(":\\") ||
      artifact.sourceDartPath.startsWith("/Users/")) {
    fail("kb_artifact_absolute_path_rejected");
  }
  requireSha(artifact.sourceDartSha256, "kb_artifact_source_sha_invalid");
  const seenCanonical = new Set();
  const seenAliases = new Set();
  for (const [index, item] of artifact.items.entries()) {
    validateItem(item, index, seenCanonical, seenAliases);
  }
  // contentSha256 is computed from file bytes; keep for caller binding only.
  void contentSha256;
}

function validateItem(item, index, seenCanonical, seenAliases) {
  if (!isObject(item)) fail(`kb_artifact_item_invalid:${index}`);
  for (const field of FORBIDDEN_ITEM_FIELDS) {
    if (Object.hasOwn(item, field)) {
      fail(`kb_artifact_forbidden_field:${field}`);
    }
  }
  for (const field of REQUIRED_ITEM_FIELDS) {
    if (!Object.hasOwn(item, field)) {
      fail(`kb_artifact_missing_field:${field}`);
    }
  }
  const canonicalType = requireCanonicalKey(
    item.canonicalType, `canonical_type_invalid:${index}`);
  if (seenCanonical.has(canonicalType)) {
    fail(`kb_artifact_duplicate_canonical:${canonicalType}`);
  }
  seenCanonical.add(canonicalType);
  requireText(item.mainCategory, `main_category_invalid:${index}`);
  if (!MAIN_CATEGORIES.has(item.mainCategory)) {
    fail(`kb_artifact_main_category_invalid:${item.mainCategory}`);
  }
  requireText(item.category, `category_invalid:${index}`);
  requireText(item.subcategory, `subcategory_invalid:${index}`);
  requireText(item.layerRole, `layer_role_invalid:${index}`);
  if (!LAYER_ROLES.has(item.layerRole)) {
    fail(`kb_artifact_layer_role_invalid:${item.layerRole}`);
  }
  requireIntInRange(item.warmthDefault, 1, 10, `warmth_invalid:${index}`);
  requireIntInRange(item.formalityDefault, 1, 10, `formality_invalid:${index}`);
  if (!Array.isArray(item.aliases) ||
      !item.aliases.every((alias) => typeof alias === "string")) {
    fail(`kb_artifact_aliases_invalid:${index}`);
  }
  const sortedAliases = [...item.aliases].sort((a, b) => compareUtf16(a, b));
  if (JSON.stringify(item.aliases) !== JSON.stringify(sortedAliases)) {
    fail(`kb_artifact_alias_ordering_invalid:${index}`);
  }
  for (const alias of item.aliases) {
    const key = alias.trim().toLowerCase();
    if (key.length === 0) fail(`kb_artifact_alias_empty:${index}`);
    if (seenCanonical.has(key)) continue;
    if (seenAliases.has(key)) fail(`kb_artifact_duplicate_alias:${alias}`);
    seenAliases.add(key);
  }
  const allowedKeys = new Set(REQUIRED_ITEM_FIELDS);
  for (const key of Object.keys(item)) {
    if (!allowedKeys.has(key)) fail(`kb_artifact_unknown_item_field:${key}`);
  }
}

function assertStableOrdering(items) {
  for (let i = 1; i < items.length; i++) {
    if (compareUtf16(items[i - 1].canonicalType, items[i].canonicalType) > 0) {
      fail("kb_artifact_item_ordering_invalid");
    }
  }
}

function compareUtf16(left, right) {
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

function rejectTimestamps(value, pathLabel = "$") {
  if (Array.isArray(value)) {
    value.forEach((item, index) =>
      rejectTimestamps(item, `${pathLabel}[${index}]`));
    return;
  }
  if (!isObject(value)) {
    if (typeof value === "string" &&
        /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(value)) {
      fail(`kb_artifact_timestamp_rejected:${pathLabel}`);
    }
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    if (/timestamp|createdAt|updatedAt|generatedAt/i.test(key) &&
        key !== "sourceDartSha256") {
      // SHA fields are allowed; temporal keys are not part of the artifact.
      if (typeof child === "string" &&
          /^\d{4}-\d{2}-\d{2}T/.test(child)) {
        fail(`kb_artifact_timestamp_rejected:${pathLabel}.${key}`);
      }
    }
    rejectTimestamps(child, `${pathLabel}.${key}`);
  }
}

function rejectAbsolutePaths(value, pathLabel = "$") {
  if (Array.isArray(value)) {
    value.forEach((item, index) =>
      rejectAbsolutePaths(item, `${pathLabel}[${index}]`));
    return;
  }
  if (typeof value === "string") {
    if (path.isAbsolute(value) || value.includes(":\\") ||
        value.startsWith("/Users/") || value.startsWith("/home/")) {
      fail(`kb_artifact_absolute_path_rejected:${pathLabel}`);
    }
    return;
  }
  if (!isObject(value)) return;
  for (const [key, child] of Object.entries(value)) {
    rejectAbsolutePaths(child, `${pathLabel}.${key}`);
  }
}

function requireCanonicalKey(value, reason) {
  if (typeof value !== "string" ||
      !/^[a-z][a-z0-9_]*$/.test(value)) {
    fail(reason);
  }
  return value;
}

function requireIntInRange(value, min, max, reason) {
  if (!Number.isInteger(value) || value < min || value > max) fail(reason);
  return value;
}

function requireText(value, reason) {
  if (typeof value !== "string" || value.length === 0) fail(reason);
  return value;
}

function requireSha(value, reason) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) fail(reason);
  return value;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
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

module.exports = {
  ARTIFACT_ID,
  ARTIFACT_VERSION,
  DEFAULT_ARTIFACT_MANIFEST,
  SUPPORTED_SCHEMA_VERSION,
  loadClothingKnowledgeBasePriorArtifact,
};
