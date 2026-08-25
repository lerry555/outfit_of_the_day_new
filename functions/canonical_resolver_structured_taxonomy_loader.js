"use strict";

/**
 * Strict loader for CanonicalResolver structured taxonomy deploy artifact.
 * Runtime reads only files under functions/artifacts/ — never Dart sources.
 */

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ARTIFACT_ID = "CanonicalResolverStructuredTaxonomyArtifact";
const ARTIFACT_VERSION = "canonical-resolver-structured-taxonomy-artifact-v1";
const SUPPORTED_SCHEMA_VERSION = 1;

const DEFAULT_MANIFEST = path.resolve(
  __dirname,
  "artifacts/canonical_resolver_structured_taxonomy_v1.manifest.json");

/**
 * @param {{
 *   artifactPath?: string,
 *   artifactManifestPath?: string,
 *   expectedContentSha256?: string,
 * }} [options]
 */
function loadCanonicalResolverStructuredTaxonomyArtifact(options = {}) {
  const artifactManifestPath = options.artifactManifestPath ?? DEFAULT_MANIFEST;
  const manifest = readJson(artifactManifestPath);
  validateManifest(manifest);
  const expectedContentSha256 = options.expectedContentSha256 ??
    manifest.artifactContentSha256;
  const artifactPath = options.artifactPath ??
    path.resolve(__dirname, manifest.artifactPath);
  const artifactBytes = fs.readFileSync(artifactPath);
  const contentSha256 = sha256(artifactBytes);
  if (contentSha256 !== expectedContentSha256) {
    fail("structured_taxonomy_sha_mismatch");
  }
  const artifact = JSON.parse(artifactBytes.toString("utf8"));
  validateArtifact(artifact);

  const categorySubCanonical = new Map();
  for (const [key, value] of Object.entries(artifact.categorySubCanonical)) {
    if (typeof key !== "string" || typeof value !== "string") {
      fail("structured_taxonomy_entry_invalid");
    }
    if (categorySubCanonical.has(key)) {
      fail(`structured_taxonomy_duplicate:${key}`);
    }
    categorySubCanonical.set(key, value);
  }
  if (categorySubCanonical.size !== artifact.entryCount) {
    fail("structured_taxonomy_entry_count_mismatch");
  }
  const ambiguousStructuredKeys = new Set(artifact.ambiguousStructuredKeys);
  return Object.freeze({
    schemaVersion: artifact.schemaVersion,
    artifactId: artifact.artifactId,
    artifactVersion: artifact.artifactVersion,
    sourceDartPath: artifact.sourceDartPath,
    sourceDartSha256: artifact.sourceDartSha256,
    contentSha256,
    entryCount: artifact.entryCount,
    categorySubCanonical,
    ambiguousStructuredKeys,
    // Parity contract: SHA remains Dart source SHA.
    structuredTaxonomySourceSha256: artifact.sourceDartSha256,
  });
}

function validateManifest(manifest) {
  if (!isObject(manifest)) fail("structured_taxonomy_manifest_invalid");
  if (manifest.kind !== "structured_taxonomy_artifact") {
    fail("structured_taxonomy_manifest_kind_invalid");
  }
  if (manifest.status !== "artifact_ready") {
    fail("structured_taxonomy_manifest_status_invalid");
  }
  if (manifest.artifactId !== ARTIFACT_ID) {
    fail("structured_taxonomy_manifest_id_invalid");
  }
  if (manifest.artifactVersion !== ARTIFACT_VERSION) {
    fail("structured_taxonomy_manifest_version_invalid");
  }
  if (typeof manifest.artifactPath !== "string" ||
      manifest.artifactPath.includes("..") ||
      path.isAbsolute(manifest.artifactPath)) {
    fail("structured_taxonomy_manifest_path_invalid");
  }
}

function validateArtifact(artifact) {
  if (!isObject(artifact)) fail("structured_taxonomy_artifact_invalid");
  if (artifact.schemaVersion !== SUPPORTED_SCHEMA_VERSION) {
    fail("structured_taxonomy_schema_invalid");
  }
  if (artifact.artifactId !== ARTIFACT_ID) {
    fail("structured_taxonomy_id_invalid");
  }
  if (artifact.artifactVersion !== ARTIFACT_VERSION) {
    fail("structured_taxonomy_version_invalid");
  }
  if (typeof artifact.sourceDartSha256 !== "string" ||
      !/^[a-f0-9]{64}$/.test(artifact.sourceDartSha256)) {
    fail("structured_taxonomy_source_sha_invalid");
  }
  if (!Array.isArray(artifact.ambiguousStructuredKeys)) {
    fail("structured_taxonomy_ambiguous_invalid");
  }
  if (!isObject(artifact.categorySubCanonical)) {
    fail("structured_taxonomy_map_invalid");
  }
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function sha256(buf) {
  return crypto.createHash("sha256").update(buf).digest("hex");
}

function fail(reason) {
  throw new Error(reason);
}

module.exports = {
  ARTIFACT_ID,
  ARTIFACT_VERSION,
  SUPPORTED_SCHEMA_VERSION,
  loadCanonicalResolverStructuredTaxonomyArtifact,
};
