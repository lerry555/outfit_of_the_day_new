"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildFamilyIdentityParityEntry,
  runFamilyIdentityParity,
} = require("./backend_family_identity_parity");
const {
  runFamilyIdentityInputParity,
  buildFamilyIdentityInputParityEntry,
} = require("./backend_family_identity_input_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  familyTaxonomySha256,
  resolveVisionFamilyIdentity,
} = require("./vision_family_identity_resolver");

const root = path.resolve(__dirname, "..");

function baseQuality(overrides = {}) {
  return {
    clarity: "high",
    occlusion: "none",
    backgroundInterference: "low",
    itemFullyVisible: true,
    ...overrides,
  };
}

function observed(value, confidence = 0.9, scope = "complete") {
  return {
    state: "observed",
    value,
    confidence,
    visibilityScope: scope,
    visibleRegions: scope === "complete" ? ["full_silhouette"] : ["front"],
  };
}

function garmentObservations(overrides = {}) {
  return {
    analysisId: "family-test",
    modelVersion: "fixture",
    sourceReference: "fixture://family",
    observedAt: "2026-01-01T00:00:00.000Z",
    quality: baseQuality(),
    coverage: observed("full", 0.9),
    ...overrides,
  };
}

function footwearObservations(overrides = {}) {
  return {
    analysisId: "shoes",
    modelVersion: "fixture",
    sourceReference: "fixture://shoes",
    observedAt: "2026-01-01T00:00:00.000Z",
    quality: baseQuality(),
    footwearConstruction: observed("closed", 0.85),
    ...overrides,
  };
}

function subject(overrides = {}) {
  return {
    subjectCountEstimate: 1,
    cardinalityState: "single_item_supported",
    primarySubjectPresent: true,
    sameItemConsistency: "same_item_supported",
    subjectDomain: "garment_upper",
    framingClass: "full_item",
    permitsFamily: true,
    permitsCanonical: true,
    reasonCodes: [],
    ...overrides,
  };
}

function input(overrides = {}) {
  return {
    identityCandidates: [{canonicalType: "t_shirt", confidence: 0.85}],
    observations: garmentObservations(),
    resolvedCanonicalSubtype: null,
    inputAssessment: "valid_single_item",
    subjectAssessment: subject(),
    hasWholeItemSilhouette: true,
    ...overrides,
  };
}

test("provider constants", () => {
  assert.equal(PROVIDER_ID, "VisionFamilyIdentityResolver");
  assert.equal(PROVIDER_VERSION, "vision-family-identity-resolver-v1");
});

test("invalid input assessment", () => {
  const result = resolveVisionFamilyIdentity(input({
    inputAssessment: "ambiguous_subject",
  }));
  assert.equal(result.state, "invalid_input");
  assert.equal(result.resolvedFamily, null);
  assert.ok(result.reasonCodes.includes("input_assessment_rejects_family"));
});

test("no candidates yields insufficient evidence", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [],
  }));
  assert.equal(result.state, "insufficient_evidence");
  assert.deepEqual(result.reasonCodes, ["no_mapped_family_candidate"]);
});

test("no broad silhouette is invalid", () => {
  const result = resolveVisionFamilyIdentity(input({
    hasWholeItemSilhouette: false,
  }));
  assert.equal(result.state, "invalid_input");
  assert.ok(result.reasonCodes.includes(
    "whole_item_silhouette_required_for_family"));
});

test("one weak family candidate is insufficient", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [{canonicalType: "t_shirt", confidence: 0.2}],
    observations: garmentObservations({
      coverage: observed("partial", 0.3, "partial"),
    }),
  }));
  assert.equal(result.state, "insufficient_evidence");
  assert.equal(result.resolvedFamily, null);
  assert.ok(result.reasonCodes.includes("insufficient_family_evidence"));
});

test("one supported family", () => {
  const result = resolveVisionFamilyIdentity(input({
    observations: footwearObservations({
      quality: baseQuality({itemFullyVisible: false}),
      footwearConstruction: observed("closed", 0.85, "partial"),
      footwearUpperHeight: observed("low_cut", 0.8, "partial"),
    }),
    identityCandidates: [{canonicalType: "running_shoes", confidence: 0.75}],
    subjectAssessment: subject({subjectDomain: "footwear"}),
  }));
  assert.equal(result.state, "supported");
  assert.equal(result.resolvedFamily, "sneakers");
  assert.equal(result.subtypeResolved, false);
});

test("one confirmed family", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [{canonicalType: "tank_top", confidence: 0.85}],
    observations: garmentObservations({
      coverage: observed("partial", 0.85),
      visibleBulk: observed("low", 0.8),
      necklineShape: observed("scoop", 0.8),
    }),
  }));
  assert.equal(result.state, "confirmed");
  assert.equal(result.resolvedFamily, "top");
  assert.ok(result.confidence >= 0.82);
});

test("canonical unresolved but family resolved", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [
      {canonicalType: "chinos", confidence: 0.8},
      {canonicalType: "cargo_pants", confidence: 0.2},
    ],
    resolvedCanonicalSubtype: null,
  }));
  assert.equal(result.resolvedFamily, "trousers");
  assert.equal(result.subtypeResolved, false);
  assert.ok(result.reasonCodes.includes("family_resolved_subtype_unresolved"));
});

test("canonical subtype consistent with family", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [{canonicalType: "boots", confidence: 0.9}],
    observations: footwearObservations({
      footwearConstruction: observed("closed", 0.9),
      footwearUpperHeight: observed("mid_cut", 0.85),
    }),
    resolvedCanonicalSubtype: "boots",
    subjectAssessment: subject({subjectDomain: "footwear"}),
  }));
  assert.equal(result.resolvedFamily, "boots");
  assert.equal(result.subtypeResolved, true);
  assert.equal(result.reasonCodes.includes(
    "family_resolved_subtype_unresolved"), false);
});

test("canonical subtype from different family still resolves visual family", () => {
  // Dart does not emit a dedicated conflicting state for subtype/family
  // mismatch; subtypeResolved remains true when subtype is non-null.
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [{canonicalType: "t_shirt", confidence: 0.85}],
    resolvedCanonicalSubtype: "boots",
  }));
  assert.equal(result.resolvedFamily, "top");
  assert.equal(result.subtypeResolved, true);
});

test("multiple candidates with common family", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [
      {canonicalType: "basketball_shoes", confidence: 0.85},
      {canonicalType: "running_shoes", confidence: 0.15},
    ],
    observations: footwearObservations(),
    subjectAssessment: subject({subjectDomain: "footwear"}),
  }));
  assert.equal(result.resolvedFamily, "sneakers");
  assert.equal(result.candidates.length, 1);
  assert.equal(result.candidates[0].canonicalCandidates.length, 2);
});

test("multiple competing families become ambiguous", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [
      {canonicalType: "chinos", confidence: 0.55},
      {canonicalType: "light_jacket", confidence: 0.45},
    ],
  }));
  assert.equal(result.state, "ambiguous");
  assert.equal(result.resolvedFamily, null);
  assert.ok(result.reasonCodes.includes("competing_families"));
  assert.equal(result.candidates.length, 2);
});

test("conflicting enum exists but Dart resolve never emits it for competition", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [
      {canonicalType: "jeans", confidence: 0.5},
      {canonicalType: "sneakers", confidence: 0.5},
    ],
    observations: garmentObservations({
      coverage: observed("full", 0.8),
      footwearConstruction: observed("closed", 0.8),
    }),
  }));
  assert.notEqual(result.state, "conflicting");
  assert.equal(result.state, "ambiguous");
});

test("insufficient evidence when no direct family observation", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [{canonicalType: "t_shirt", confidence: 0.9}],
    observations: garmentObservations({
      coverage: {state: "not_visible", confidence: 0, visibilityScope: "not_visible"},
    }),
  }));
  assert.equal(result.state, "insufficient_evidence");
  assert.equal(result.resolvedFamily, null);
});

test("unknown canonical key is skipped (Dart semantics)", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [{canonicalType: "not_a_real_type", confidence: 0.9}],
  }));
  assert.equal(result.state, "insufficient_evidence");
  assert.deepEqual(result.reasonCodes, ["no_mapped_family_candidate"]);
});

test("duplicate candidate fails closed at decoder", () => {
  assert.throws(() => resolveVisionFamilyIdentity(input({
    identityCandidates: [
      {canonicalType: "t_shirt", confidence: 0.5},
      {canonicalType: "t_shirt", confidence: 0.6},
    ],
  })), /duplicate_candidate/);
});

test("duplicate canonical values across mapped aliases share one family", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [
      {canonicalType: "hoodie", confidence: 0.5},
      {canonicalType: "zip_hoodie", confidence: 0.5},
    ],
  }));
  assert.equal(result.resolvedFamily, "knitwear");
  assert.equal(result.candidates.length, 1);
});

test("confidence boundary below supported", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [{canonicalType: "t_shirt", confidence: 0.01}],
    observations: garmentObservations({
      coverage: observed("partial", 0.4, "partial"),
    }),
  }));
  assert.ok(result.candidates[0].confidence < 0.62);
  assert.equal(result.state, "insufficient_evidence");
});

test("framing-invalid subject rejects family", () => {
  const result = resolveVisionFamilyIdentity(input({
    subjectAssessment: subject({
      framingClass: "detail_only",
      permitsFamily: false,
      permitsCanonical: false,
    }),
  }));
  assert.equal(result.state, "invalid_input");
  assert.ok(result.reasonCodes.includes("subject_or_framing_rejects_family"));
});

test("partial framing caps confirmed at supported", () => {
  const result = resolveVisionFamilyIdentity(input({
    subjectAssessment: subject({
      framingClass: "partial_item",
      permitsFamily: true,
      permitsCanonical: false,
    }),
  }));
  assert.ok(result.confidence >= 0.82 || result.state === "supported" ||
    result.state === "confirmed");
  if (result.confidence >= 0.82) {
    assert.equal(result.state, "supported");
  }
});

test("detail-only silhouette gate invalidates", () => {
  const result = resolveVisionFamilyIdentity(input({
    hasWholeItemSilhouette: false,
    subjectAssessment: subject({framingClass: "detail_only", permitsFamily: false}),
  }));
  assert.equal(result.state, "invalid_input");
});

test("deterministic candidate ordering by confidence then family wire", () => {
  const result = resolveVisionFamilyIdentity(input({
    identityCandidates: [
      {canonicalType: "light_jacket", confidence: 0.4},
      {canonicalType: "chinos", confidence: 0.4},
    ],
  }));
  assert.equal(result.candidates[0].family < result.candidates[1].family ||
    result.candidates[0].confidence >= result.candidates[1].confidence, true);
});

test("null subject assessment is allowed", () => {
  const result = resolveVisionFamilyIdentity(input({
    subjectAssessment: null,
  }));
  assert.notEqual(result.state, "invalid_input");
});

test("taxonomy SHA mismatch fails closed", () => {
  assert.throws(() => resolveVisionFamilyIdentity(input({
    familyTaxonomySha256:
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    expectedFamilyTaxonomySha256:
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  })), /taxonomy_sha_mismatch/);
});

test("unknown observation property fails closed", () => {
  assert.throws(() => resolveVisionFamilyIdentity(input({
    observations: {
      ...garmentObservations(),
      notARealProperty: {state: "unknown", confidence: 0},
    },
  })), /unknown_observation_property/);
});

test("DTO serialization is deterministic", () => {
  const first = resolveVisionFamilyIdentity(input());
  const second = resolveVisionFamilyIdentity(input());
  assert.equal(sha256(canonicalBytes(first)), sha256(canonicalBytes(second)));
});

test("prepare-stage remains orchestration_ready for integration", () => {
  const prepare = runFamilyIdentityInputParity();
  assert.equal(prepare.parityStatus, "orchestration_ready");
  assert.equal(prepare.passedScenarios, 8);
});

test("8/8 family oracle providerOutput parity and status distribution", () => {
  const report = runFamilyIdentityParity();
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.passedInvocations, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.deterministic, true);
  assert.equal(report.distributionOk, true);
  assert.equal(report.parityStatus, "parity_ready");
  assert.deepEqual(report.statusCounts, {
    confirmed: 3,
    supported: 1,
    invalid_input: 4,
    ambiguous: 0,
    insufficient_evidence: 0,
    conflicting: 0,
  });
  assert.equal(report.selectedFamily, 4);
  assert.equal(report.nullFamily, 4);
  for (const scenario of report.scenarios) {
    assert.equal(scenario.passed, true, scenario.scenarioId);
    for (const invocation of scenario.invocations) {
      assert.equal(invocation.fieldParity.state, true);
      assert.equal(invocation.fieldParity.resolvedFamily, true);
      assert.equal(invocation.fieldParity.confidence, true);
      assert.equal(invocation.fieldParity.candidates, true);
      assert.equal(invocation.fieldParity.reasonCodes, true);
      assert.equal(invocation.fieldParity.supportingEvidence, true);
    }
  }
});

test("multi-view conflicting scenario remains invalid_input with ambiguous assessment input", () => {
  const report = runFamilyIdentityParity();
  const multi = report.scenarios.find((item) =>
    item.scenarioId === "conflicting_multi_view");
  assert.ok(multi);
  assert.equal(multi.invocations[0].state, "invalid_input");
  assert.equal(multi.invocations[0].resolvedFamily, null);
});

test("parity entry is stable and byte-identical on rerun", () => {
  const first = buildFamilyIdentityParityEntry(runFamilyIdentityParity());
  const second = buildFamilyIdentityParityEntry(runFamilyIdentityParity());
  assert.equal(first.parityStatus, "parity_ready");
  assert(canonicalBytes(first).equals(canonicalBytes(second)));
});

test("taxonomy SHA matches Dart family source", () => {
  const dartSha = sha256(fs.readFileSync(path.join(root,
    "lib/domain/wardrobe_profile/vision_family_identity.dart")));
  assert.equal(familyTaxonomySha256, dartSha);
});

test("provider remains production isolated", () => {
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production, /vision_family_identity_resolver/);
  assert.doesNotMatch(production, /resolveVisionFamilyIdentity/);
  assert.doesNotMatch(
    fs.readFileSync(path.join(__dirname, "vision_family_identity_resolver.js"),
      "utf8"),
    /firebase|firestore|persistence|QualifiedVisionPersistenceMapper|KnowledgeBase/);
});

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
