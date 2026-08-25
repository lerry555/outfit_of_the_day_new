"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildWardrobeProfileResolverParityEntry,
  runWardrobeProfileResolverParity,
  updateProviderParityManifest,
} = require("./backend_wardrobe_profile_resolver_parity");
const {
  FORBIDDEN_AUTHORITY_FIELDS,
  PROPERTY,
  PROVIDER_ID,
  PROVIDER_VERSION,
  resolveWardrobeProfile,
} = require("./wardrobe_profile_resolver");

const root = path.resolve(__dirname, "..");

function evidence(overrides = {}) {
  return {
    id: "e1",
    property: PROPERTY.canonicalType,
    value: "boots",
    source: "ai_inference",
    nature: "inferred",
    confidence: 0.7,
    method: "test",
    createdAt: "1970-01-01T00:00:00.000Z",
    active: true,
    verified: false,
    ...overrides,
  };
}

function resolve(items, itemId = "item") {
  return resolveWardrobeProfile({itemId, evidence: items});
}

test("resolver constants", () => {
  assert.equal(PROVIDER_ID, "WardrobeProfileResolver");
  assert.equal(PROVIDER_VERSION, "wardrobe-profile-resolver-v1");
  assert.ok(FORBIDDEN_AUTHORITY_FIELDS.includes("resolvedProfile"));
});

test("empty evidence", () => {
  const profile = resolve([]);
  assert.equal(profile.identity.canonicalType.state, "unknown");
  assert.equal(profile.capabilities.warmth.state, "unknown");
  assert.deepEqual(profile.evidence, []);
});

test("inactive evidence ignored", () => {
  const profile = resolve([evidence({active: false})]);
  assert.equal(profile.identity.canonicalType.state, "unknown");
});

test("active evidence selected", () => {
  const profile = resolve([evidence()]);
  assert.equal(profile.identity.canonicalType.value, "boots");
  assert.equal(profile.identity.canonicalType.winningSource, "ai_inference");
});

test("verified boosts quality over unverified same source", () => {
  const profile = resolve([
    evidence({
      id: "a",
      value: "sneakers",
      confidence: 0.7,
      verified: false,
    }),
    evidence({
      id: "b",
      value: "boots",
      confidence: 0.7,
      verified: true,
    }),
  ]);
  assert.equal(profile.identity.canonicalType.value, "boots");
});

test("user correction beats machine evidence", () => {
  const profile = resolve([
    evidence({id: "ai", value: "sneakers", confidence: 0.95}),
    evidence({
      id: "user",
      value: "boots",
      source: "user_correction",
      nature: "observed",
      confidence: 1,
      verified: true,
    }),
  ]);
  assert.equal(profile.identity.canonicalType.value, "boots");
  assert.equal(
    profile.identity.canonicalType.winningSource, "user_correction");
});

test("visual observation beats KB prior for visual properties", () => {
  const profile = resolve([
    evidence({
      id: "kb",
      property: PROPERTY.colors,
      value: ["black"],
      source: "knowledge_base_prior",
      nature: "defaulted",
      confidence: 0.9,
    }),
    evidence({
      id: "vis",
      property: PROPERTY.colors,
      value: ["navy"],
      source: "visual_observation",
      nature: "observed",
      confidence: 0.7,
    }),
  ]);
  assert.deepEqual(profile.visual.colors.value, ["navy"]);
  assert.equal(profile.visual.colors.winningSource, "visual_observation");
});

test("item-specific AI capability beats KB capability prior", () => {
  const profile = resolve([
    evidence({
      id: "canon",
      property: PROPERTY.canonicalType,
      value: "boots",
      confidence: 0.8,
    }),
    evidence({
      id: "kb",
      property: PROPERTY.warmth,
      value: 4,
      source: "knowledge_base_prior",
      nature: "defaulted",
      confidence: 0.9,
      dependsOnCanonicalType: "boots",
    }),
    evidence({
      id: "cap",
      property: PROPERTY.warmth,
      value: 7,
      source: "ai_inference",
      nature: "inferred",
      confidence: 0.7,
    }),
  ]);
  assert.equal(profile.capabilities.warmth.value, 7);
  assert.equal(profile.capabilities.warmth.winningSource, "ai_inference");
});

test("known vs unknown / not_visible / not_applicable", () => {
  assert.equal(resolve([
    evidence({
      id: "u",
      property: PROPERTY.hasHood,
      value: null,
      valueState: "unknown",
      source: "visual_observation",
      nature: "unknown",
      confidence: 0,
    }),
  ]).visual.hasHood.state, "unknown");
  assert.equal(resolve([
    evidence({
      id: "nv",
      property: PROPERTY.hasHood,
      value: null,
      valueState: "not_visible",
      source: "visual_observation",
      nature: "observed",
      confidence: 0.4,
    }),
  ]).visual.hasHood.state, "unknown");
  assert.equal(resolve([
    evidence({
      id: "na",
      property: PROPERTY.hasHood,
      value: null,
      valueState: "not_applicable",
      source: "visual_observation",
      nature: "observed",
      confidence: 0.8,
    }),
  ]).visual.hasHood.state, "not_applicable");
});

test("equal-priority same value merges winning ids", () => {
  const profile = resolve([
    evidence({id: "a", value: "boots", confidence: 0.7}),
    evidence({id: "b", value: "boots", confidence: 0.7}),
  ]);
  assert.deepEqual(
    profile.identity.canonicalType.winningEvidenceIds, ["a", "b"]);
});

test("confidence winner", () => {
  const profile = resolve([
    evidence({id: "low", value: "sneakers", confidence: 0.5}),
    evidence({id: "high", value: "boots", confidence: 0.9}),
  ]);
  assert.equal(profile.identity.canonicalType.value, "boots");
});

test("deterministic evidence-ID tie-break", () => {
  const first = resolve([
    evidence({id: "b", value: "boots", confidence: 0.7}),
    evidence({id: "a", value: "sneakers", confidence: 0.7}),
  ]);
  const second = resolve([
    evidence({id: "a", value: "sneakers", confidence: 0.7}),
    evidence({id: "b", value: "boots", confidence: 0.7}),
  ]);
  assert.equal(first.identity.canonicalType.value,
    second.identity.canonicalType.value);
});

test("duplicate identical evidence id kept for both copies", () => {
  const profile = resolve([
    evidence({id: "dup"}),
    evidence({id: "dup"}),
  ]);
  assert.equal(profile.evidence.length, 2);
  assert.equal(profile.identity.canonicalType.value, "boots");
  assert.deepEqual(
    profile.identity.canonicalType.winningEvidenceIds, ["dup", "dup"]);
});

test("duplicate conflicting evidence id dropped", () => {
  const profile = resolve([
    evidence({id: "dup", value: "boots"}),
    evidence({id: "dup", value: "sneakers"}),
  ]);
  assert.equal(profile.evidence.length, 0);
  assert.equal(profile.identity.canonicalType.state, "unknown");
});

test("canonical identity resolved and unresolved", () => {
  assert.equal(resolve([evidence()]).identity.canonicalType.value, "boots");
  assert.equal(resolve([]).identity.canonicalType.state, "unknown");
});

test("family evidence ignored by current contract", () => {
  const profile = resolve([
    evidence({
      id: "fam",
      property: "identity.family",
      value: "footwear",
      source: "ai_inference",
      nature: "inferred",
      confidence: 0.8,
    }),
  ]);
  assert.equal(Object.hasOwn(profile.identity, "family"), false);
  assert.equal(profile.evidence.length, 0);
});

test("observation and capability properties resolved", () => {
  const profile = resolve([
    evidence({
      id: "cov",
      property: PROPERTY.coverage,
      value: "partial",
      source: "visual_observation",
      nature: "observed",
      confidence: 0.9,
    }),
    evidence({
      id: "walk",
      property: PROPERTY.walkingComfort,
      value: "high",
      source: "ai_inference",
      nature: "inferred",
      confidence: 0.6,
    }),
  ]);
  assert.equal(profile.visual.coverage.value, "partial");
  assert.equal(profile.capabilities.walkingComfort.value, "high");
});

test("KB prior selected when no item-specific evidence", () => {
  const profile = resolve([
    evidence({id: "canon", value: "boots", confidence: 0.8}),
    evidence({
      id: "kb-prior:boots:capabilities.warmth",
      property: PROPERTY.warmth,
      value: 7,
      source: "knowledge_base_prior",
      nature: "defaulted",
      confidence: 0.35,
      dependsOnCanonicalType: "boots",
    }),
  ]);
  assert.equal(profile.capabilities.warmth.value, 7);
  assert.equal(
    profile.capabilities.warmth.winningSource, "knowledge_base_prior");
});

test("legacy fallback selected", () => {
  const profile = resolve([
    evidence({
      id: "legacy",
      property: PROPERTY.brand,
      value: "LegacyBrand",
      source: "legacy_fallback",
      nature: "unknown",
      confidence: 0.2,
    }),
  ]);
  assert.equal(profile.identity.brand.winningSource, "legacy_fallback");
});

test("compatibility-like label metadata selected", () => {
  const profile = resolve([
    evidence({
      id: "label",
      property: PROPERTY.brand,
      value: "LabelBrand",
      source: "label_metadata",
      nature: "observed",
      confidence: 0.8,
    }),
  ]);
  assert.equal(profile.identity.brand.winningSource, "label_metadata");
});

test("no fallback available remains unknown", () => {
  assert.equal(resolve([]).identity.brand.state, "unknown");
});

test("forged resolved profile rejected", () => {
  assert.throws(() => resolveWardrobeProfile({
    itemId: "x",
    evidence: [],
    resolvedProfile: {},
  }), /forged_authority_field:resolvedProfile/);
});

test("invalid source rejected", () => {
  assert.throws(() => resolve([evidence({source: "nope"})]),
    /evidence_source_invalid/);
});

test("invalid confidence rejected", () => {
  assert.throws(() => resolve([evidence({confidence: 2})]),
    /evidence_confidence_invalid/);
});

test("empty itemId rejected", () => {
  assert.throws(() => resolveWardrobeProfile({itemId: "", evidence: []}),
    /item_id_required/);
});

test("deterministic full profile serialization", () => {
  const args = {
    itemId: "item",
    evidence: [evidence(), evidence({
      id: "vis",
      property: PROPERTY.coverage,
      value: "full",
      source: "visual_observation",
      nature: "observed",
      confidence: 0.9,
    })],
  };
  const first = resolveWardrobeProfile(args);
  const second = resolveWardrobeProfile(args);
  assert.deepEqual(
    Array.from(canonicalBytes(first)),
    Array.from(canonicalBytes(second)),
  );
});

test("immutable input and output", () => {
  const args = {itemId: "item", evidence: [evidence()]};
  const profile = resolveWardrobeProfile(args);
  assert.throws(() => {
    profile.itemId = "mut";
  }, TypeError);
  args.evidence[0].value = "sneakers";
  assert.equal(profile.identity.canonicalType.value, "boots");
});

test("stale KB default discarded after canonical mismatch", () => {
  const profile = resolve([
    evidence({id: "canon", value: "sneakers", confidence: 0.8}),
    evidence({
      id: "kb-prior:boots:capabilities.warmth",
      property: PROPERTY.warmth,
      value: 7,
      source: "knowledge_base_prior",
      nature: "defaulted",
      confidence: 0.35,
      dependsOnCanonicalType: "boots",
    }),
  ]);
  assert.equal(profile.capabilities.warmth.state, "unknown");
});

test("8/8 oracle parity with expected distribution", () => {
  const report = runWardrobeProfileResolverParity();
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.parityStatus, "parity_ready");
  assert.equal(report.deterministic, true);
  assert.equal(report.distributionOk, true);
  assert.equal(report.distribution.resolvedCanonical, 1);
  assert.equal(report.distribution.resolvedFamily, 0);
  assert.equal(report.distribution.observationFields, 86);
  assert.equal(report.distribution.capabilityFields, 17);
  assert.equal(report.distribution.kbSelected, 6);
  assert.equal(report.distribution.visualSelected, 86);
  assert.equal(report.distribution.aiSelected, 15);
  assert.equal(report.distribution.legacySelected, 0);
  assert.equal(report.distribution.conflictFields, 0);
  assert.equal(report.distribution.fullyUnresolvedProfiles, 0);
});

test("parity entry is stable and updates provider parity manifest", () => {
  const report = runWardrobeProfileResolverParity();
  const entry = buildWardrobeProfileResolverParityEntry(report);
  const first = canonicalBytes(entry);
  const second = canonicalBytes(
    buildWardrobeProfileResolverParityEntry(runWardrobeProfileResolverParity()));
  assert.deepEqual(Array.from(first), Array.from(second));
  const updated = updateProviderParityManifest(report);
  const providers = updated.providers.filter(
    (item) => item.parityStatus === "parity_ready");
  assert.equal(providers.length, 13);
  assert.ok(providers.some((item) => item.providerId === PROVIDER_ID));
  const again = updateProviderParityManifest(report);
  assert.deepEqual(
    Array.from(canonicalBytes(updated)),
    Array.from(canonicalBytes(again)),
  );
  assert.equal(
    crypto.createHash("sha256").update(fs.readFileSync(
      path.join(root, "functions/wardrobe_profile_resolver.js")))
      .digest("hex"),
    entry.canonicalImplementationSha256,
  );
});

test("resolver remains production isolated", () => {
  const production = [
    fs.readFileSync(path.join(root, "functions/index.js"), "utf8"),
    fs.readFileSync(path.join(root, "functions/vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production,
    /wardrobe_profile_resolver|resolveWardrobeProfile|WardrobeProfileResolver/);
  assert.doesNotMatch(production,
    /qualified_vision_persistence_mapper|mapQualifiedVisionPersistence/);
  assert.equal(
    fs.existsSync(path.join(root,
      "functions/qualified_vision_persistence_mapper.js")),
    true,
  );
});
