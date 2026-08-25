"use strict";

/**
 * Strict loader for VisionCanonicalFamilyRegistry deploy artifact.
 * Runtime reads only files under functions/artifacts/ — never Dart sources.
 */

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ARTIFACT_ID = "VisionCanonicalFamilyRegistryArtifact";
const ARTIFACT_VERSION = "vision-canonical-family-registry-artifact-v1";
const SUPPORTED_SCHEMA_VERSION = 1;
const FAMILY_TAXONOMY_VERSION = "vision-canonical-family-registry-v1";

const DEFAULT_MANIFEST = path.resolve(
  __dirname, "artifacts/vision_canonical_family_registry_v1.manifest.json");

const FAMILY_ENUMS = new Set([
  "top",
  "knitwear",
  "trousers",
  "shorts",
  "jacketOuterwear",
  "sneakers",
  "boots",
]);

/**
 * @param {{
 *   artifactPath?: string,
 *   artifactManifestPath?: string,
 *   expectedContentSha256?: string,
 * }} [options]
 */
function loadVisionCanonicalFamilyRegistryArtifact(options = {}) {
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
    fail("family_artifact_sha_mismatch");
  }
  const artifact = JSON.parse(artifactBytes.toString("utf8"));
  validateArtifact(artifact);
  const map = new Map();
  for (const [canonical, family] of Object.entries(artifact.entries)) {
    if (!FAMILY_ENUMS.has(family)) {
      fail(`family_taxonomy_unknown_family:${family}`);
    }
    if (map.has(canonical)) fail(`family_taxonomy_duplicate:${canonical}`);
    map.set(canonical, family);
  }
  if (map.size !== artifact.entryCount) {
    fail("family_taxonomy_entry_count_mismatch");
  }
  return Object.freeze({
    schemaVersion: artifact.schemaVersion,
    artifactId: artifact.artifactId,
    artifactVersion: artifact.artifactVersion,
    familyTaxonomyVersion: artifact.familyTaxonomyVersion,
    sourceDartPath: artifact.sourceDartPath,
    sourceDartSha256: artifact.sourceDartSha256,
    contentSha256,
    entryCount: artifact.entryCount,
    canonicalToFamily: Object.freeze(map),
    // Parity contract: taxonomy SHA remains the Dart source SHA.
    familyTaxonomySha256: artifact.sourceDartSha256,
  });
}

function validateManifest(manifest) {
  if (!isObject(manifest)) fail("family_artifact_manifest_invalid");
  if (manifest.kind !== "family_registry_artifact") {
    fail("family_artifact_manifest_kind_invalid");
  }
  if (manifest.status !== "artifact_ready") {
    fail("family_artifact_manifest_status_invalid");
  }
  if (manifest.artifactId !== ARTIFACT_ID) {
    fail("family_artifact_manifest_id_invalid");
  }
  if (manifest.artifactVersion !== ARTIFACT_VERSION) {
    fail("family_artifact_manifest_version_invalid");
  }
  if (manifest.schemaVersion !== SUPPORTED_SCHEMA_VERSION) {
    fail("family_artifact_manifest_schema_invalid");
  }
  if (typeof manifest.artifactPath !== "string" ||
      manifest.artifactPath.includes("..") ||
      path.isAbsolute(manifest.artifactPath)) {
    fail("family_artifact_manifest_path_invalid");
  }
}

function validateArtifact(artifact) {
  if (!isObject(artifact)) fail("family_artifact_invalid");
  if (artifact.schemaVersion !== SUPPORTED_SCHEMA_VERSION) {
    fail("family_artifact_schema_invalid");
  }
  if (artifact.artifactId !== ARTIFACT_ID) fail("family_artifact_id_invalid");
  if (artifact.artifactVersion !== ARTIFACT_VERSION) {
    fail("family_artifact_version_invalid");
  }
  if (artifact.familyTaxonomyVersion !== FAMILY_TAXONOMY_VERSION) {
    fail("family_artifact_taxonomy_version_invalid");
  }
  if (typeof artifact.sourceDartSha256 !== "string" ||
      !/^[a-f0-9]{64}$/.test(artifact.sourceDartSha256)) {
    fail("family_artifact_source_sha_invalid");
  }
  if (!isObject(artifact.entries)) fail("family_artifact_entries_invalid");
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
  FAMILY_TAXONOMY_VERSION,
  SUPPORTED_SCHEMA_VERSION,
  loadVisionCanonicalFamilyRegistryArtifact,
};
