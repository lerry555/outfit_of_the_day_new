"use strict";

/**
 * Generates deploy-packaged taxonomy artifacts from Dart sources of truth.
 * Run from repo root (dev/CI only). Not imported by production callables.
 *
 * Outputs under functions/artifacts/ (included in Firebase Functions package).
 */

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..", "..");
const ARTIFACTS_DIR = path.join(ROOT, "functions", "artifacts");

const FAMILY_DART = path.join(
  ROOT, "lib", "domain", "wardrobe_profile", "vision_family_identity.dart");
const CANONICAL_RESOLVER_DART = path.join(
  ROOT, "lib", "utils", "canonical_resolver.dart");
const KB_FIXTURE = path.join(
  ROOT, "test", "fixtures", "backend_qualification", "artifacts",
  "clothing_knowledge_base_prior_v1.json");
const KB_FIXTURE_MANIFEST = path.join(
  ROOT, "test", "fixtures", "backend_qualification",
  "backend_clothing_kb_prior_artifact_manifest.json");

const FAMILY_WIRE = Object.freeze({
  top: "top",
  knitwear: "knitwear",
  trousers: "trousers",
  shorts: "shorts",
  jacketOuterwear: "jacket_outerwear",
  sneakers: "sneakers",
  boots: "boots",
});

function sha256(buf) {
  return crypto.createHash("sha256").update(buf).digest("hex");
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), {recursive: true});
  const body = `${JSON.stringify(value, null, 2)}\n`;
  fs.writeFileSync(filePath, body, "utf8");
  return sha256(Buffer.from(body, "utf8"));
}

function generateFamilyRegistry() {
  const source = fs.readFileSync(FAMILY_DART);
  const text = source.toString("utf8");
  const block = text.match(
    /static const Map<String, VisionIdentityFamily> canonicalToFamily = \{([\s\S]*?)\};/);
  if (!block) throw new Error("family_taxonomy_registry_missing");
  const entries = [...block[1].matchAll(
    /'([^']+)':\s*VisionIdentityFamily\.(\w+)/g)];
  if (entries.length === 0) throw new Error("family_taxonomy_registry_empty");
  const map = {};
  for (const match of entries) {
    const canonical = match[1];
    const family = match[2];
    if (!Object.hasOwn(FAMILY_WIRE, family)) {
      throw new Error(`family_taxonomy_unknown_family:${family}`);
    }
    if (Object.hasOwn(map, canonical)) {
      throw new Error(`family_taxonomy_duplicate:${canonical}`);
    }
    map[canonical] = family;
  }
  const orderedKeys = Object.keys(map).sort();
  const orderedEntries = {};
  for (const key of orderedKeys) orderedEntries[key] = map[key];

  const sourceDartSha256 = sha256(source);
  const artifactBody = {
    schemaVersion: 1,
    artifactId: "VisionCanonicalFamilyRegistryArtifact",
    artifactVersion: "vision-canonical-family-registry-artifact-v1",
    familyTaxonomyVersion: "vision-canonical-family-registry-v1",
    sourceDartPath: "lib/domain/wardrobe_profile/vision_family_identity.dart",
    sourceDartSha256,
    entryCount: orderedKeys.length,
    entries: orderedEntries,
  };
  const artifactPath = path.join(
    ARTIFACTS_DIR, "vision_canonical_family_registry_v1.json");
  const body = `${JSON.stringify(artifactBody, null, 2)}\n`;
  fs.mkdirSync(ARTIFACTS_DIR, {recursive: true});
  fs.writeFileSync(artifactPath, body, "utf8");
  const contentSha256 = sha256(Buffer.from(body, "utf8"));
  const manifest = {
    kind: "family_registry_artifact",
    status: "artifact_ready",
    manifestVersion: 1,
    schemaVersion: 1,
    artifactId: artifactBody.artifactId,
    artifactVersion: artifactBody.artifactVersion,
    artifactPath: "artifacts/vision_canonical_family_registry_v1.json",
    artifactContentSha256: contentSha256,
    sourceDartPath: artifactBody.sourceDartPath,
    sourceDartSha256,
    entryCount: artifactBody.entryCount,
    generationCommand:
      "node functions/scripts/generate_deploy_taxonomy_artifacts.js",
  };
  writeJson(path.join(
    ARTIFACTS_DIR, "vision_canonical_family_registry_v1.manifest.json"),
  manifest);
  return {sourceDartSha256, contentSha256, entryCount: orderedKeys.length};
}

function generateStructuredTaxonomy() {
  const source = fs.readFileSync(CANONICAL_RESOLVER_DART);
  const text = source.toString("utf8");
  const ambiguous = [];
  const ambiguousBlock = text.match(
    /_ambiguousStructuredCanonicalKeys\s*=\s*<String>\{([\s\S]*?)\};/);
  if (!ambiguousBlock) throw new Error("structured_taxonomy_ambiguous_parse_failed");
  for (const match of ambiguousBlock[1].matchAll(/'([^']+)'/g)) {
    ambiguous.push(match[1]);
  }
  ambiguous.sort();
  const mapBlock = text.match(
    /_categorySubCanonical\s*=\s*<String,\s*String>\{([\s\S]*?)\};/);
  if (!mapBlock) throw new Error("structured_taxonomy_map_parse_failed");
  const map = {};
  for (const match of mapBlock[1].matchAll(/'([^']+)'\s*:\s*'([^']+)'/g)) {
    map[match[1]] = match[2];
  }
  const keys = Object.keys(map).sort();
  if (keys.length === 0) throw new Error("structured_taxonomy_map_empty");
  const orderedMap = {};
  for (const key of keys) orderedMap[key] = map[key];

  const sourceDartSha256 = sha256(source);
  const artifactBody = {
    schemaVersion: 1,
    artifactId: "CanonicalResolverStructuredTaxonomyArtifact",
    artifactVersion: "canonical-resolver-structured-taxonomy-artifact-v1",
    sourceDartPath: "lib/utils/canonical_resolver.dart",
    sourceDartSha256,
    entryCount: keys.length,
    ambiguousStructuredKeys: ambiguous,
    categorySubCanonical: orderedMap,
  };
  const artifactPath = path.join(
    ARTIFACTS_DIR, "canonical_resolver_structured_taxonomy_v1.json");
  const body = `${JSON.stringify(artifactBody, null, 2)}\n`;
  fs.mkdirSync(ARTIFACTS_DIR, {recursive: true});
  fs.writeFileSync(artifactPath, body, "utf8");
  const contentSha256 = sha256(Buffer.from(body, "utf8"));
  writeJson(path.join(
    ARTIFACTS_DIR, "canonical_resolver_structured_taxonomy_v1.manifest.json"), {
    kind: "structured_taxonomy_artifact",
    status: "artifact_ready",
    manifestVersion: 1,
    schemaVersion: 1,
    artifactId: artifactBody.artifactId,
    artifactVersion: artifactBody.artifactVersion,
    artifactPath: "artifacts/canonical_resolver_structured_taxonomy_v1.json",
    artifactContentSha256: contentSha256,
    sourceDartPath: artifactBody.sourceDartPath,
    sourceDartSha256,
    entryCount: artifactBody.entryCount,
    generationCommand:
      "node functions/scripts/generate_deploy_taxonomy_artifacts.js",
  });
  return {sourceDartSha256, contentSha256, entryCount: keys.length};
}

function mirrorClothingKbArtifact() {
  const artifactBytes = fs.readFileSync(KB_FIXTURE);
  const fixtureManifest = JSON.parse(fs.readFileSync(KB_FIXTURE_MANIFEST, "utf8"));
  const contentSha256 = sha256(artifactBytes);
  if (contentSha256 !== fixtureManifest.artifactContentSha256) {
    throw new Error("kb_fixture_sha_mismatch");
  }
  const destArtifact = path.join(
    ARTIFACTS_DIR, "clothing_knowledge_base_prior_v1.json");
  fs.mkdirSync(ARTIFACTS_DIR, {recursive: true});
  fs.writeFileSync(destArtifact, artifactBytes);
  const manifest = {
    ...fixtureManifest,
    artifactPath: "artifacts/clothing_knowledge_base_prior_v1.json",
    deployPackagePath: "functions/artifacts/clothing_knowledge_base_prior_v1.json",
    mirroredFrom:
      "test/fixtures/backend_qualification/artifacts/clothing_knowledge_base_prior_v1.json",
  };
  writeJson(path.join(
    ARTIFACTS_DIR, "clothing_knowledge_base_prior_v1.manifest.json"), manifest);
  return {contentSha256, itemCount: fixtureManifest.itemCount};
}

function main() {
  const family = generateFamilyRegistry();
  const structured = generateStructuredTaxonomy();
  const kb = mirrorClothingKbArtifact();
  console.log(JSON.stringify({ok: true, family, structured, kb}, null, 2));
}

if (require.main === module) {
  main();
}

module.exports = {
  generateFamilyRegistry,
  generateStructuredTaxonomy,
  mirrorClothingKbArtifact,
};
