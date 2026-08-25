"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildWardrobeKnowledgeBasePriorParityEntry,
  runWardrobeKnowledgeBasePriorParity,
} = require("./backend_wardrobe_kb_prior_parity");
const {
  PROPERTY,
  PROVIDER_ID,
  PROVIDER_VERSION,
  provideWardrobeKnowledgeBasePriors,
} = require("./wardrobe_knowledge_base_prior_provider");
const {
  loadClothingKnowledgeBasePriorArtifact,
} = require("./clothing_knowledge_base_prior_loader");

const root = path.resolve(__dirname, "..");
const SOURCE = path.join(__dirname, "wardrobe_knowledge_base_prior_provider.js");
const PARITY_MANIFEST = path.join(root,
  "test/fixtures/backend_qualification/backend_provider_parity_manifest.json");

function identity(value = "hoodie", overrides = {}) {
  return {
    id: `vision-identity:test:${value}:qualified`,
    property: PROPERTY.canonicalType,
    value,
    source: "ai_inference",
    nature: "inferred",
    confidence: 0.8,
    method: "test",
    createdAt: "2000-01-01T00:00:00.000Z",
    active: true,
    verified: false,
    ...overrides,
  };
}

function input(overrides = {}) {
  return {
    document: {},
    existingEvidence: [identity()],
    ...overrides,
  };
}

test("provider constants", () => {
  assert.equal(PROVIDER_ID, "WardrobeKnowledgeBasePriorProvider");
  assert.equal(PROVIDER_VERSION, "wardrobe-kb-prior-provider-v1");
});

test("empty document + empty evidence yields empty output", () => {
  const output = provideWardrobeKnowledgeBasePriors({
    document: {},
    existingEvidence: [],
  });
  assert.deepEqual(output, []);
});

test("valid canonical identity evidence emits defaults", () => {
  const output = provideWardrobeKnowledgeBasePriors(input());
  assert.ok(output.length >= 6);
  assert.equal(output.every((item) => item.source === "knowledge_base_prior"),
    true);
  assert.equal(output.find((item) => item.property === PROPERTY.warmth)
    .dependsOnCanonicalType, "hoodie");
  assert.equal(output.some((item) =>
    item.property === PROPERTY.canonicalType), false);
});

test("inactive canonical identity evidence yields empty output", () => {
  const output = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity("hoodie", {active: false})],
  }));
  assert.deepEqual(output, []);
});

test("multiple distinct identity evidence yields empty output", () => {
  const output = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity("hoodie"), identity("boots", {
      id: "vision-identity:test:boots:qualified",
    })],
  }));
  assert.deepEqual(output, []);
});

test("duplicate identity evidence with same canonical still emits", () => {
  const output = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [
      identity("hoodie"),
      identity("hoodie", {id: "vision-identity:test:hoodie:qualified:2"}),
    ],
  }));
  assert.ok(output.length >= 6);
});

test("unknown canonical key yields empty output", () => {
  const output = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity("not_a_real_canonical_type_xyz")],
  }));
  assert.deepEqual(output, []);
});

test("missing KB entry / malformed canonical yields empty output", () => {
  assert.deepEqual(provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity("   ")],
  })), []);
  assert.deepEqual(provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity(123)],
  })), []);
});

test("canonical evidence wins over conflicting document field", () => {
  const output = provideWardrobeKnowledgeBasePriors({
    document: {primary_type: "boots"},
    existingEvidence: [identity("hoodie")],
  });
  assert.ok(output.some((item) =>
    item.property === PROPERTY.mainCategory && item.value === "oblecenie"));
  assert.equal(output.every((item) =>
    !String(item.id).includes(":boots:")), true);
});

test("document-only primary_type canonical input", () => {
  const output = provideWardrobeKnowledgeBasePriors({
    document: {primary_type: "hoodie"},
    existingEvidence: [],
  });
  const canonical = output.find((item) =>
    item.property === PROPERTY.canonicalType);
  assert.ok(canonical);
  assert.equal(canonical.nature, "inferred");
  assert.equal(canonical.method, "kb_prior:structured_primary_type");
  assert.equal(canonical.confidence, 0.45);
  assert.equal(canonical.sourceReference, "structured_primary_type:hoodie");
  assert.equal(Object.hasOwn(canonical, "dependsOnCanonicalType"), false);
});

test("document category/subcategory structured taxonomy path", () => {
  const output = provideWardrobeKnowledgeBasePriors({
    document: {
      categoryKey: "mikiny",
      subCategoryKey: "mikina_s_kapucnou",
    },
    existingEvidence: [],
  });
  const canonical = output.find((item) =>
    item.property === PROPERTY.canonicalType);
  assert.ok(canonical);
  assert.equal(canonical.value, "hoodie");
  assert.equal(canonical.method, "kb_prior:structured_taxonomy");
});

test("family-only input does not create KB priors", () => {
  const output = provideWardrobeKnowledgeBasePriors({
    document: {},
    existingEvidence: [],
  });
  assert.deepEqual(output, []);
  assert.equal(output.some((item) =>
    item.property === "identity.family"), false);
});

test("valid KB entry emits all default priors", () => {
  const output = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity("boots")],
  }));
  const props = output.map((item) => item.property).sort();
  assert.deepEqual(props, [
    PROPERTY.formality,
    PROPERTY.layerRole,
    PROPERTY.warmth,
    PROPERTY.category,
    PROPERTY.mainCategory,
    PROPERTY.subcategory,
  ].sort());
});

test("existing non-defaulted property suppresses that prior", () => {
  const output = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [
      identity("hoodie"),
      {
        id: "warmth-observed",
        property: PROPERTY.warmth,
        value: 7,
        source: "visual_observation",
        nature: "observed",
        confidence: 0.9,
        method: "test",
        createdAt: "2000-01-01T00:00:00.000Z",
        active: true,
        verified: false,
      },
    ],
  }));
  assert.equal(output.some((item) => item.property === PROPERTY.warmth), false);
  assert.ok(output.some((item) => item.property === PROPERTY.formality));
});

test("empty KB prior output for no identity and empty document", () => {
  assert.deepEqual(provideWardrobeKnowledgeBasePriors({
    document: {},
    existingEvidence: [],
  }), []);
});

test("evidence ordering and ID determinism", () => {
  const first = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity("boots")],
  }));
  const second = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity("boots")],
  }));
  assert.deepEqual(first.map((item) => item.id), second.map((item) => item.id));
  assert.deepEqual(first.map((item) => item.property), [
    PROPERTY.mainCategory,
    PROPERTY.category,
    PROPERTY.subcategory,
    PROPERTY.layerRole,
    PROPERTY.warmth,
    PROPERTY.formality,
  ]);
});

test("confidence default and sourceReference creation", () => {
  const output = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity("boots")],
  }));
  assert.ok(output.every((item) => item.confidence === 0.35));
  assert.ok(output.every((item) =>
    item.sourceReference === "clothing_knowledge_base:boots"));
  assert.ok(output.every((item) =>
    !Object.hasOwn(item, "supportingEvidenceIds")));
});

test("null/omitted boundaries for known valueState", () => {
  const output = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity("boots")],
  }));
  assert.ok(output.every((item) => !Object.hasOwn(item, "valueState")));
});

test("artifact SHA mismatch and unsupported schema fail closed", () => {
  assert.throws(() => provideWardrobeKnowledgeBasePriors(input(), {
    expectedArtifactContentSha256:
      "0000000000000000000000000000000000000000000000000000000000000000",
  }), /kb_artifact_sha_mismatch/);
  assert.throws(() => provideWardrobeKnowledgeBasePriors(input(), {
    expectedArtifactSchemaVersion: 99,
  }), /kb_artifact_unsupported_version/);
});

test("forged KB evidence rejection", () => {
  assert.throws(() => provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [{
      id: "kb-prior:hoodie:identity.mainCategory",
      property: PROPERTY.mainCategory,
      value: "oblecenie",
      source: "knowledge_base_prior",
      nature: "defaulted",
      confidence: 0.35,
      method: "kb_prior:canonical_type_defaults",
      createdAt: "1970-01-01T00:00:00.000Z",
      active: true,
      verified: false,
    }],
  })), /forged_kb_prior_evidence/);
});

test("compatibility and legacy fallbacks are not emitted", () => {
  const output = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity("boots")],
  }));
  assert.equal(output.some((item) =>
    item.source === "legacy_fallback" ||
    String(item.method).includes("compatibility")), false);
});

test("deterministic repeated execution and immutable output", () => {
  const args = input({existingEvidence: [identity("boots")]});
  const first = provideWardrobeKnowledgeBasePriors(args);
  const second = provideWardrobeKnowledgeBasePriors(args);
  assert(canonicalBytes(first).equals(canonicalBytes(second)));
  assert.throws(() => {
    first.push({});
  });
  assert.throws(() => {
    first[0].confidence = 1;
  });
});

test("8/8 oracle parity with expected evidence distribution", () => {
  const report = runWardrobeKnowledgeBasePriorParity();
  assert.equal(report.parityStatus, "parity_ready");
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.deterministic, true);
  assert.equal(report.distributionOk, true);
  assert.equal(report.kbEvidenceCount, 6);
  assert.equal(report.emptyOutputScenarios, 7);
  assert.equal(report.shoeEvidenceCount, 6);
  const shoe = report.scenarios.find((item) =>
    item.scenarioId === "shoe_without_outsole");
  assert.equal(shoe.invocations[0].outputCount, 6);
});

test("parity entry is stable and updates provider parity manifest", () => {
  const first = buildWardrobeKnowledgeBasePriorParityEntry(
    runWardrobeKnowledgeBasePriorParity());
  const second = buildWardrobeKnowledgeBasePriorParityEntry(
    runWardrobeKnowledgeBasePriorParity());
  assert.equal(first.parityStatus, "parity_ready");
  assert(canonicalBytes(first).equals(canonicalBytes(second)));
  const manifest = JSON.parse(fs.readFileSync(PARITY_MANIFEST, "utf8"));
  const without = manifest.providers.filter((item) =>
    item.providerId !== PROVIDER_ID);
  without.push(first);
  without.sort((a, b) => a.providerId.localeCompare(b.providerId));
  const next = {manifestVersion: 1, providers: without};
  const encoded = `${JSON.stringify(canonicalize(next), null, 2)}\n`;
  const encodedAgain = `${JSON.stringify(canonicalize({
    manifestVersion: 1,
    providers: [...without].sort((a, b) =>
      a.providerId.localeCompare(b.providerId)),
  }), null, 2)}\n`;
  assert.equal(encoded, encodedAgain);
  fs.writeFileSync(PARITY_MANIFEST, encoded);
  assert.equal(
    JSON.parse(fs.readFileSync(PARITY_MANIFEST, "utf8")).providers.length, 13);
});

test("provider remains production isolated", () => {
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production, /wardrobe_knowledge_base_prior_provider/);
  assert.doesNotMatch(production, /provideWardrobeKnowledgeBasePriors/);
  const source = fs.readFileSync(SOURCE, "utf8");
  assert.doesNotMatch(source,
    /firebase|firestore|WardrobeProfileResolver|QualifiedVisionPersistenceMapper/);
});

test("loader integration returns immutable artifact for provider", () => {
  const artifact = loadClothingKnowledgeBasePriorArtifact();
  const output = provideWardrobeKnowledgeBasePriors(input({
    existingEvidence: [identity("boots")],
  }), {kbArtifact: artifact});
  assert.equal(output.length, 6);
});

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort()
      .map((key) => [key, canonicalize(value[key])]));
  }
  return value;
}
