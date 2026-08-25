"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const {
  ARTIFACT_ID,
  ARTIFACT_VERSION,
  DEFAULT_ARTIFACT_MANIFEST,
  SUPPORTED_SCHEMA_VERSION,
  loadClothingKnowledgeBasePriorArtifact,
} = require("./clothing_knowledge_base_prior_loader");

const root = path.resolve(__dirname, "..");
const loaderManifestOut = path.join(root,
  "test/fixtures/backend_qualification/" +
  "backend_clothing_kb_prior_loader_manifest.json");
const SOURCE = path.resolve(__dirname, "clothing_knowledge_base_prior_loader.js");

function loadValid() {
  return loadClothingKnowledgeBasePriorArtifact();
}

function withTempArtifact(mutate, run) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "kb-artifact-"));
  try {
    const manifest = JSON.parse(fs.readFileSync(DEFAULT_ARTIFACT_MANIFEST, "utf8"));
    const sourceArtifact = path.resolve(__dirname, manifest.artifactPath);
    const artifact = JSON.parse(fs.readFileSync(sourceArtifact, "utf8"));
    mutate(artifact, manifest);
    const artifactPath = path.join(dir, "artifact.json");
    const manifestPath = path.join(dir, "manifest.json");
    const bytes = Buffer.from(`${JSON.stringify(canonicalize(artifact), null, 2)}\n`);
    fs.writeFileSync(artifactPath, bytes);
    manifest.artifactPath = "artifact.json";
    manifest.artifactContentSha256 = sha256(bytes);
    fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    // Fix fixtureRoot resolution: loader uses dirname(dirname(manifestPath)).
    // Put files under dir/backend_qualification/ style by nesting.
    const nested = path.join(dir, "backend_qualification");
    fs.mkdirSync(nested, {recursive: true});
    const nestedArtifact = path.join(nested, "artifact.json");
    const nestedManifest = path.join(dir, "backend_qualification_manifest.json");
    fs.writeFileSync(nestedArtifact, bytes);
    manifest.artifactPath = "backend_qualification/artifact.json";
    manifest.artifactContentSha256 = sha256(bytes);
    fs.writeFileSync(nestedManifest, `${JSON.stringify(manifest, null, 2)}\n`);
    return run({
      artifactPath: nestedArtifact,
      artifactManifestPath: nestedManifest,
      bytes,
      artifact,
      manifest,
    });
  } finally {
    fs.rmSync(dir, {recursive: true, force: true});
  }
}

test("valid artifact load", () => {
  const loaded = loadValid();
  assert.equal(loaded.artifactId, ARTIFACT_ID);
  assert.equal(loaded.artifactVersion, ARTIFACT_VERSION);
  assert.equal(loaded.schemaVersion, SUPPORTED_SCHEMA_VERSION);
  assert.equal(loaded.itemCount, 131);
  assert.equal(loaded.items.length, 131);
});

test("exact schema version and SHA match", () => {
  const manifest = JSON.parse(fs.readFileSync(DEFAULT_ARTIFACT_MANIFEST, "utf8"));
  const loaded = loadClothingKnowledgeBasePriorArtifact({
    expectedContentSha256: manifest.artifactContentSha256,
    expectedSchemaVersion: 1,
  });
  assert.equal(loaded.contentSha256, manifest.artifactContentSha256);
  assert.equal(loaded.schemaVersion, 1);
});

test("SHA mismatch fails closed", () => {
  assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
    expectedContentSha256:
      "0000000000000000000000000000000000000000000000000000000000000000",
  }), /kb_artifact_sha_mismatch/);
});

test("unsupported version fails closed", () => {
  assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
    expectedSchemaVersion: 99,
  }), /kb_artifact_unsupported_version/);
});

test("malformed canonical key fails closed", () => {
  withTempArtifact((artifact) => {
    artifact.items[0].canonicalType = "Bad Key!";
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /canonical_type_invalid/);
  });
});

test("duplicate canonical entry fails closed", () => {
  withTempArtifact((artifact) => {
    artifact.items.push(structuredClone(artifact.items[0]));
    artifact.itemCount = artifact.items.length;
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /kb_artifact_duplicate_canonical/);
  });
});

test("duplicate alias fails closed", () => {
  withTempArtifact((artifact) => {
    artifact.items[0].aliases = ["shared-alias"];
    artifact.items[1].aliases = ["shared-alias"];
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /kb_artifact_duplicate_alias/);
  });
});

test("unknown item field fails closed", () => {
  withTempArtifact((artifact) => {
    artifact.items[0].unexpectedPropertyPath = "capabilities.warmth";
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /kb_artifact_unknown_item_field/);
  });
});

test("invalid value type fails closed", () => {
  withTempArtifact((artifact) => {
    artifact.items[0].warmthDefault = "warm";
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /warmth_invalid/);
  });
});

test("invalid confidence-like warmth range fails closed", () => {
  withTempArtifact((artifact) => {
    artifact.items[0].warmthDefault = 99;
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /warmth_invalid/);
  });
});

test("invalid layer role fails closed", () => {
  withTempArtifact((artifact) => {
    artifact.items[0].layerRole = "cape";
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /kb_artifact_layer_role_invalid/);
  });
});

test("invalid main category fails closed", () => {
  withTempArtifact((artifact) => {
    artifact.items[0].mainCategory = "unknown_main";
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /kb_artifact_main_category_invalid/);
  });
});

test("unexpected compatibility fallback fails closed", () => {
  withTempArtifact((artifact) => {
    artifact.items[0].compatibilityFallback = true;
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /kb_artifact_forbidden_field:compatibilityFallback/);
  });
});

test("unexpected legacy fallback fails closed", () => {
  withTempArtifact((artifact) => {
    artifact.items[0].legacyFallback = "legacy";
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /kb_artifact_forbidden_field:legacyFallback/);
  });
});

test("timestamp rejection", () => {
  withTempArtifact((artifact) => {
    artifact.generatedAt = "2026-08-03T00:00:00.000Z";
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /kb_artifact_timestamp_rejected|kb_artifact_unknown/);
  });
});

test("absolute-path rejection", () => {
  withTempArtifact((artifact) => {
    artifact.sourceDartPath = "C:\\\\Users\\\\x\\\\clothing_knowledge_base.dart";
  }, ({artifactPath, artifactManifestPath}) => {
    assert.throws(() => loadClothingKnowledgeBasePriorArtifact({
      artifactPath,
      artifactManifestPath,
    }), /kb_artifact_absolute_path_rejected/);
  });
});

test("deterministic ordering and immutable output", () => {
  const loaded = loadValid();
  for (let i = 1; i < loaded.items.length; i++) {
    assert.ok(
      loaded.items[i - 1].canonicalType < loaded.items[i].canonicalType ||
      loaded.items[i - 1].canonicalType === loaded.items[i].canonicalType);
  }
  assert.throws(() => {
    loaded.items.push({});
  });
  assert.throws(() => {
    loaded.items[0].warmthDefault = 1;
  });
});

test("byte-identical repeated load and round-trip integrity", () => {
  const first = loadValid();
  const second = loadValid();
  assert.equal(first.contentSha256, second.contentSha256);
  assert.deepEqual(first.items, second.items);
  const manifest = JSON.parse(fs.readFileSync(DEFAULT_ARTIFACT_MANIFEST, "utf8"));
  const artifactBytes = fs.readFileSync(
    path.resolve(__dirname, manifest.artifactPath));
  assert.equal(sha256(artifactBytes), first.contentSha256);
  const loaderManifest = {
    manifestVersion: 1,
    kind: "kb_artifact_loader",
    status: "artifact_loader_ready",
    artifactId: ARTIFACT_ID,
    artifactVersion: ARTIFACT_VERSION,
    schemaVersion: SUPPORTED_SCHEMA_VERSION,
    artifactPath: manifest.artifactPath,
    artifactContentSha256: first.contentSha256,
    sourceDartSha256: first.sourceDartSha256,
    nodeLoaderSource: "functions/clothing_knowledge_base_prior_loader.js",
    nodeLoaderSha256: sha256(fs.readFileSync(SOURCE)),
    validationStatus: "passed",
    deterministic: true,
  };
  fs.writeFileSync(loaderManifestOut,
    `${JSON.stringify(loaderManifest, null, 2)}\n`);
});

test("production isolation — loader not wired into entry points", () => {
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production, /clothing_knowledge_base_prior_loader/);
  assert.doesNotMatch(production, /loadClothingKnowledgeBasePriorArtifact/);
});

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort()
      .map((key) => [key, canonicalize(value[key])]));
  }
  return value;
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}
