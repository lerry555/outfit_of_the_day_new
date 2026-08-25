"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildNegativeClaimParityEntry,
  runNegativeClaimParity,
} = require("./backend_negative_claim_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeNegativeClaimInput,
  qualifyNegativeClaims,
} = require("./vision_negative_claim_corroborator");

function baseInput(overrides = {}) {
  return {
    bundle: {
      analysisId: "analysis-1",
      modelVersion: "gpt-4o-mini",
      sourceReference: "fixture://test/view_1",
      observedAt: "2000-01-01T00:00:00.000Z",
      quality: {
        itemFullyVisible: true,
        occlusion: "none",
        backgroundInterference: "low",
        clarity: "high",
      },
      coverage: {
        state: "observed",
        value: "full",
        confidence: 0.9,
        visibilityScope: "complete",
        visibleRegions: ["full_silhouette"],
      },
      hasHood: {
        state: "observed",
        value: false,
        confidence: 0.9,
        visibilityScope: "sufficient",
        visibleRegions: ["collar", "back"],
      },
      frontClosure: {
        state: "observed",
        value: "full_zip",
        confidence: 0.9,
        visibilityScope: "complete",
        visibleRegions: ["front", "fastening_area"],
      },
      visiblePocketStructure: {
        state: "unknown",
        confidence: 0,
      },
      visibleStretchCue: {
        state: "unknown",
        confidence: 0,
      },
    },
    subject: {
      subjectCountEstimate: 1,
      cardinalityState: "single_item_supported",
      primarySubjectPresent: true,
      sameItemConsistency: "same_item_supported",
      subjectDomain: "garment_upper",
      framingClass: "full_item",
      permitsFamily: true,
      permitsCanonical: true,
      reasonCodes: ["whole_item_attestations_consistent"],
    },
    framing: {
      modelDeclaredFraming: "full_item",
      systemAttestedFraming: "full_item",
      framingTrustState: "attested",
      framingEvidence: {
        visibleBoundaries: ["top", "bottom", "left", "right"],
        visibleItemExtent: "whole",
        primarySilhouetteContinuous: true,
        subjectOrientation: "back",
        localDetailOnly: false,
        cropIndicators: [],
      },
      framingContradictions: [],
      reasonCodes: ["whole_item_attestations_consistent"],
    },
    viewCount: 2,
    sameItemViews: true,
    complementaryRegions: {
      hasHood: ["collar", "back"],
    },
    conflictingPositiveProperties: [],
    ...overrides,
  };
}

test("negative claim provider has stable identity", () => {
  assert.equal(PROVIDER_ID, "VisionNegativeClaimCorroborator");
  assert.equal(PROVIDER_VERSION, "negative-claim-corroborator-v1");
});

test("strict decoder rejects unknown enums and invalid combinations", () => {
  assert.doesNotThrow(() => decodeNegativeClaimInput(baseInput()));
  assert.throws(() => decodeNegativeClaimInput({
    ...baseInput(),
    subject: {...baseInput().subject, subjectDomain: "invented"},
  }), /negative_claim_subject_domain_invalid/);
  assert.throws(() => decodeNegativeClaimInput({
    ...baseInput(),
    complementaryRegions: {hasHood: ["invented"]},
  }), /negative_claim_complementary_region_invalid/);
  assert.throws(() => decodeNegativeClaimInput({
    ...baseInput(),
    conflictingPositiveProperties: ["coverage"],
  }), /negative_claim_conflicting_positives_invalid/);
  assert.throws(() => decodeNegativeClaimInput({
    ...baseInput(),
    sameItemViews: "yes",
  }), /negative_claim_same_item_views_invalid/);
});

test("no negative claim leaves empty claims and preserves bundle", () => {
  const input = baseInput({
    bundle: {
      ...baseInput().bundle,
      hasHood: {state: "unknown", confidence: 0},
    },
  });
  const output = qualifyNegativeClaims(input);
  assert.deepEqual(output.claims, {});
  assert.deepEqual(output.qualifiedBundle.hasHood, {state: "unknown", confidence: 0});
});

test("inapplicable domain marks notApplicable and unknown observation", () => {
  const input = baseInput({
    subject: {...baseInput().subject, subjectDomain: "footwear"},
    framing: {
      ...baseInput().framing,
      framingEvidence: {
        ...baseInput().framing.framingEvidence,
        subjectOrientation: "back",
      },
    },
  });
  const output = qualifyNegativeClaims(input);
  assert.equal(output.claims.hasHood.corroborationState, "notApplicable");
  assert.deepEqual(output.qualifiedBundle.hasHood, {state: "unknown", confidence: 0});
  assert.ok(output.claims.hasHood.reasonCodes.includes(
    "negative_claim_domain_not_applicable"));
});

test("missing required regions blocks claim", () => {
  const input = baseInput({
    bundle: {
      ...baseInput().bundle,
      hasHood: {
        state: "observed",
        value: false,
        confidence: 0.9,
        visibilityScope: "sufficient",
        visibleRegions: ["collar"],
      },
    },
    complementaryRegions: {hasHood: ["collar"]},
  });
  const output = qualifyNegativeClaims(input);
  assert.equal(output.claims.hasHood.corroborationState, "blocked");
  assert.deepEqual(output.claims.hasHood.missingRequiredRegions, ["back"]);
  assert.ok(output.claims.hasHood.reasonCodes.includes(
    "required_region_not_positively_visible"));
});

test("sameItemViews false blocks multi-view pocket absence", () => {
  const input = baseInput({
    sameItemViews: false,
    viewCount: 2,
    framing: {
      ...baseInput().framing,
      framingEvidence: {
        ...baseInput().framing.framingEvidence,
        subjectOrientation: "mixed",
      },
    },
    bundle: {
      ...baseInput().bundle,
      hasHood: {state: "unknown", confidence: 0},
      visiblePocketStructure: {
        state: "observed",
        value: "none",
        confidence: 0.9,
        visibilityScope: "complete",
        visibleRegions: ["front", "side", "back", "pocket_area"],
      },
    },
    complementaryRegions: {
      visiblePocketStructure: ["front", "side", "back", "pocket_area"],
    },
  });
  const output = qualifyNegativeClaims(input);
  assert.equal(output.claims.visiblePocketStructure.corroborationState, "blocked");
  assert.ok(output.claims.visiblePocketStructure.reasonCodes.includes(
    "complementary_same_item_views_required"));
});

test("insufficient view count blocks multi-view pocket absence", () => {
  const input = baseInput({
    viewCount: 1,
    sameItemViews: true,
    framing: {
      ...baseInput().framing,
      framingEvidence: {
        ...baseInput().framing.framingEvidence,
        subjectOrientation: "mixed",
      },
    },
    bundle: {
      ...baseInput().bundle,
      hasHood: {state: "unknown", confidence: 0},
      visiblePocketStructure: {
        state: "observed",
        value: "none",
        confidence: 0.9,
        visibilityScope: "complete",
        visibleRegions: ["front", "side", "back", "pocket_area"],
      },
    },
    complementaryRegions: {
      visiblePocketStructure: ["front", "side", "back", "pocket_area"],
    },
  });
  const output = qualifyNegativeClaims(input);
  assert.ok(output.claims.visiblePocketStructure.reasonCodes.includes(
    "complementary_same_item_views_required"));
});

test("back orientation cannot assess frontClosure absence", () => {
  const input = baseInput({
    bundle: {
      ...baseInput().bundle,
      hasHood: {state: "unknown", confidence: 0},
      frontClosure: {
        state: "observed",
        value: "none",
        confidence: 0.9,
        visibilityScope: "sufficient",
        visibleRegions: ["front", "fastening_area"],
      },
    },
    complementaryRegions: {
      frontClosure: ["front", "fastening_area"],
    },
  });
  const output = qualifyNegativeClaims(input);
  assert.equal(output.claims.frontClosure.corroborationState, "blocked");
  assert.ok(output.claims.frontClosure.reasonCodes.includes(
    "subject_orientation_cannot_assess_region"));
});

test("conflicting positive evidence yields conflicting state", () => {
  const input = baseInput({
    conflictingPositiveProperties: ["hasHood"],
  });
  const output = qualifyNegativeClaims(input);
  assert.equal(output.claims.hasHood.corroborationState, "conflicting");
  assert.equal(output.claims.hasHood.conflictingPositiveEvidence, true);
  assert.ok(output.claims.hasHood.reasonCodes.includes(
    "conflicting_positive_evidence"));
  assert.deepEqual(output.qualifiedBundle.hasHood, {state: "unknown", confidence: 0});
});

test("corroborated hood absence preserves observed false", () => {
  const output = qualifyNegativeClaims(baseInput());
  assert.equal(output.claims.hasHood.corroborationState, "corroborated");
  assert.deepEqual(output.claims.hasHood.reasonCodes, ["negative_claim_corroborated"]);
  assert.equal(output.qualifiedBundle.hasHood.state, "observed");
  assert.equal(output.qualifiedBundle.hasHood.value, false);
});

test("stretch false is never visually confirmable", () => {
  const input = baseInput({
    framing: {
      ...baseInput().framing,
      framingEvidence: {
        ...baseInput().framing.framingEvidence,
        subjectOrientation: "front",
      },
    },
    bundle: {
      ...baseInput().bundle,
      hasHood: {state: "unknown", confidence: 0},
      visibleStretchCue: {
        state: "observed",
        value: false,
        confidence: 0.8,
        visibilityScope: "complete",
        visibleRegions: ["surface_detail"],
      },
    },
    complementaryRegions: {visibleStretchCue: ["surface_detail"]},
  });
  const output = qualifyNegativeClaims(input);
  assert.equal(output.claims.visibleStretchCue.corroborationState, "blocked");
  assert.ok(output.claims.visibleStretchCue.reasonCodes.includes(
    "absence_not_visually_confirmable"));
});

test("provider is immutable deterministic and does not mutate input", () => {
  const input = baseInput();
  const before = canonicalBytes(input);
  const first = qualifyNegativeClaims(input);
  const second = qualifyNegativeClaims(input);
  assert(canonicalBytes(input).equals(before));
  assert.deepEqual(first, second);
});

test("oracle parity is exact across eight scenarios and nine invocations", () => {
  const report = runNegativeClaimParity();
  assert.equal(report.scenarioCount, 8);
  assert.equal(report.invocationCount, 9);
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.passedInvocations, 9);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.parityStatus, "parity_ready");
  const conflicting = report.scenarios.find(
    (item) => item.scenarioId === "conflicting_multi_view");
  assert.equal(conflicting.invocationCount, 2);
  assert.equal(conflicting.passed, true);
});

test("parity rerun is deterministic and manifest entry is stable", () => {
  const first = runNegativeClaimParity();
  const second = runNegativeClaimParity();
  assert.deepEqual(first, second);
  const entry = buildNegativeClaimParityEntry(first);
  assert.equal(entry.parityStatus, "parity_ready");
  assert.equal(entry.invocationCount, 9);
  assert.equal(entry.nodeProviderSource,
    "functions/vision_negative_claim_corroborator.js");
  assert.match(entry.canonicalImplementationSha256, /^[a-f0-9]{64}$/);
});

test("provider remains production isolated", () => {
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production, /vision_negative_claim_corroborator/);
  assert.doesNotMatch(production, /NegativeClaimCorroborator/);
  assert.doesNotMatch(production, /qualifyNegativeClaims/);
});
