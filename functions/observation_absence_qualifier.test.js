"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildAbsenceParityEntry,
  runAbsenceParity,
} = require("./backend_observation_absence_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeAbsenceInput,
  qualifyAbsenceBundles,
  qualify,
  POLICIES,
} = require("./observation_absence_qualifier");

function obs(value, scope, confidence = 0.95, regions) {
  const result = {
    state: "observed",
    value,
    confidence,
    visibilityScope: scope,
  };
  if (regions) result.visibleRegions = regions;
  return result;
}

function bundle(overrides = {}) {
  return {
    analysisId: overrides.analysisId || "analysis-1",
    modelVersion: "gpt-4o-mini",
    sourceReference: overrides.sourceReference || "fixture://view_1",
    observedAt: "2000-01-01T00:00:00.000Z",
    quality: {
      itemFullyVisible: true,
      occlusion: "none",
      backgroundInterference: "low",
      clarity: "high",
    },
    coverage: obs("full", "complete", 0.9, ["full_silhouette"]),
    ...overrides,
  };
}

test("absence provider has stable identity", () => {
  assert.equal(PROVIDER_ID, "ObservationAbsenceQualifier");
  assert.equal(PROVIDER_VERSION, "observation-absence-qualifier-v1");
});

test("strict decoder rejects empty bundles and unknown enums", () => {
  assert.throws(() => decodeAbsenceInput({bundles: []}), /empty/);
  assert.throws(() => decodeAbsenceInput({
    bundles: [bundle({coverage: {state: "observed", value: "weird",
      confidence: 0.5}})],
  }));
  assert.throws(() => decodeAbsenceInput({
    bundles: [
      bundle({analysisId: "dup"}),
      bundle({analysisId: "dup", sourceReference: "fixture://view_2"}),
    ],
  }), /duplicate_analysis_id/);
});

test("empty property list yields no-op unknown absence audits", () => {
  const inputBundle = bundle();
  delete inputBundle.hasHood;
  delete inputBundle.frontClosure;
  delete inputBundle.visiblePocketStructure;
  delete inputBundle.visibleStretchCue;
  const result = qualifyAbsenceBundles({bundles: [inputBundle]});
  assert.equal(result.hasHood.disposition, "unchanged");
  assert.deepEqual(result.hasHood.reasonCodes, ["no_observed_absence_evidence"]);
  assert.equal(result.hasHood.qualified.state, "unknown");
  assert.equal(result.qualifiedBundle.hasHood.state, "unknown");
});

test("one bundle unchanged observed positive remains qualified", () => {
  const output = qualifyAbsenceBundles({
    bundles: [bundle({
      hasHood: obs(true, "sufficient", 0.88, ["collar"]),
    })],
  });
  assert.equal(output.hasHood.disposition, "qualified");
  assert.deepEqual(output.hasHood.reasonCodes, ["positive_existence_observed"]);
  assert.equal(output.hasHood.qualified.value, true);
  assert.equal(output.qualifiedBundle.hasHood.value, true);
});

test("unknown and not_visible and not_applicable no-op paths", () => {
  assert.equal(qualify({
    policy: POLICIES.visiblePocketStructure,
    raw: [{state: "unknown", confidence: 0}],
  }).qualified.state, "unknown");
  assert.equal(qualify({
    policy: POLICIES.visiblePocketStructure,
    raw: [{state: "not_visible", confidence: 0, visibilityScope: "not_visible"}],
  }).disposition, "degradedToNotVisible");
  assert.equal(qualify({
    policy: POLICIES.visiblePocketStructure,
    raw: [{state: "not_applicable", confidence: 1}],
  }).disposition, "unchanged");
  assert.deepEqual(qualify({
    policy: POLICIES.visiblePocketStructure,
    raw: [{state: "not_applicable", confidence: 1}],
  }).reasonCodes, ["property_not_applicable"]);
});

test("agreeing known values keep higher confidence winner", () => {
  const result = qualify({
    policy: POLICIES.hasHood,
    raw: [
      obs(true, "sufficient", 0.7),
      obs(true, "complete", 0.9),
    ],
  });
  assert.equal(result.disposition, "qualified");
  assert.equal(result.qualified.confidence, 0.9);
});

test("conflicting known positives yield conflict unknown", () => {
  const result = qualify({
    policy: POLICIES.visiblePocketStructure,
    raw: [
      obs("cargo", "sufficient", 0.8),
      obs("standard", "complete", 0.9),
    ],
  });
  assert.equal(result.disposition, "conflict");
  assert.equal(result.qualified.state, "unknown");
  assert.deepEqual(result.reasonCodes, ["conflicting_positive_observations"]);
});

test("observed negative without corroboration degrades to unknown", () => {
  const result = qualify({
    policy: POLICIES.visiblePocketStructure,
    raw: [obs("none", "partial", 0.95)],
  });
  assert.equal(result.disposition, "degradedToUnknown");
  assert.deepEqual(result.reasonCodes, ["insufficient_visibility_for_absence"]);
});

test("corroborated negative caps confidence and confirms absence", () => {
  const result = qualify({
    policy: POLICIES.visiblePocketStructure,
    raw: [obs("none", "complete", 0.95)],
  });
  assert.equal(result.disposition, "qualified");
  assert.equal(result.qualified.value, "none");
  assert.equal(result.qualified.confidence, 0.9);
  assert.ok(result.reasonCodes.includes("complete_visibility_confirms_absence"));
  assert.ok(result.reasonCodes.includes("absence_confidence_calibrated"));
  assert.equal(Object.hasOwn(result.qualified, "visibleRegions"), false);
});

test("rejected stretch negative is never visually provable", () => {
  const result = qualify({
    policy: POLICIES.visibleStretchCue,
    raw: [obs(false, "complete", 0.9)],
  });
  assert.equal(result.disposition, "degradedToUnknown");
  assert.deepEqual(result.reasonCodes, ["absence_not_visually_provable"]);
});

test("mixed known plus unknown keeps positive", () => {
  const result = qualify({
    policy: POLICIES.hasHood,
    raw: [
      {state: "unknown", confidence: 0},
      obs(true, "sufficient", 0.8),
    ],
  });
  assert.equal(result.disposition, "qualified");
  assert.equal(result.qualified.value, true);
});

test("mixed known plus not_visible keeps positive", () => {
  const result = qualify({
    policy: POLICIES.frontClosure,
    raw: [
      {state: "not_visible", confidence: 0, visibilityScope: "not_visible"},
      obs("full_zip", "sufficient", 0.85),
    ],
  });
  assert.equal(result.disposition, "qualified");
  assert.equal(result.qualified.value, "full_zip");
});

test("complementary multi-view merge confirms pocket none", () => {
  const result = qualify({
    policy: POLICIES.visiblePocketStructure,
    raw: [
      obs("none", "sufficient", 0.88),
      obs("none", "sufficient", 0.91),
    ],
  });
  assert.equal(result.disposition, "qualified");
  assert.ok(result.reasonCodes.includes(
    "multiple_sufficient_views_confirm_absence"));
  assert.ok(result.reasonCodes.includes("absence_confidence_calibrated"));
  assert.equal(result.qualified.confidence, 0.9);
});

test("conflicting-positive overrides negative", () => {
  const result = qualify({
    policy: POLICIES.visiblePocketStructure,
    raw: [
      obs("none", "partial", 0.95),
      obs("cargo", "sufficient", 0.8),
    ],
  });
  assert.equal(result.disposition, "qualified");
  assert.deepEqual(result.reasonCodes, [
    "positive_existence_overrides_negative",
    "negative_absence_not_decisive",
  ]);
  assert.equal(result.qualified.value, "cargo");
});

test("deterministic ordering and null omission are stable", () => {
  const first = qualifyAbsenceBundles({
    bundles: [bundle({
      hasHood: obs(false, "partial", 0.7),
      frontClosure: {state: "not_applicable", confidence: 1},
      visiblePocketStructure: {state: "unknown", confidence: 0},
      visibleStretchCue: obs(false, "complete", 0.8),
    })],
  });
  const second = qualifyAbsenceBundles({
    bundles: [bundle({
      hasHood: obs(false, "partial", 0.7),
      frontClosure: {state: "not_applicable", confidence: 1},
      visiblePocketStructure: {state: "unknown", confidence: 0},
      visibleStretchCue: obs(false, "complete", 0.8),
    })],
  });
  assert.deepEqual(first, second);
  assert.equal(Object.hasOwn(first.hasHood.qualified, "value"), false);
  assert.equal(Object.hasOwn(first.frontClosure.qualified, "visibilityScope"),
    false);
});

test("source reference and provenance come from first bundle", () => {
  const output = qualifyAbsenceBundles({
    bundles: [
      bundle({
        analysisId: "a1",
        sourceReference: "fixture://view_1",
        hasHood: obs(true, "sufficient", 0.8),
      }),
      bundle({
        analysisId: "a2",
        sourceReference: "fixture://view_2",
        hasHood: obs(true, "complete", 0.9),
      }),
    ],
  });
  assert.equal(output.qualifiedBundle.analysisId, "a1");
  assert.equal(output.qualifiedBundle.sourceReference, "fixture://view_1");
  assert.equal(output.hasHood.qualified.confidence, 0.9);
});

test("ordinary conflict across views becomes unknown", () => {
  const output = qualifyAbsenceBundles({
    bundles: [
      bundle({coverage: obs("full", "complete", 0.9)}),
      bundle({
        analysisId: "a2",
        sourceReference: "fixture://view_2",
        coverage: obs("partial", "complete", 0.8),
      }),
    ],
  });
  assert.equal(output.qualifiedBundle.coverage.state, "unknown");
});

test("oracle parity is exact across eight scenarios and eight invocations", () => {
  const report = runAbsenceParity();
  assert.equal(report.scenarioCount, 8);
  assert.equal(report.invocationCount, 8);
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.passedInvocations, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.parityStatus, "parity_ready");
  const conflicting = report.scenarios.find(
    (item) => item.scenarioId === "conflicting_multi_view");
  assert.equal(conflicting.invocationCount, 1);
  assert.equal(conflicting.invocations[0].viewCount, 2);
  assert.deepEqual(conflicting.invocations[0].orderedViewIds,
    ["view_1", "view_2"]);
  assert.equal(conflicting.invocations[0].invocationId,
    "conflicting_multi_view::observation-absence-qualifier");
  assert.equal(conflicting.passed, true);
});

test("parity rerun is deterministic and manifest entry is stable", () => {
  const first = runAbsenceParity();
  const second = runAbsenceParity();
  assert.deepEqual(first, second);
  const entry = buildAbsenceParityEntry(first);
  assert.equal(entry.parityStatus, "parity_ready");
  assert.equal(entry.invocationCount, 8);
  assert.equal(entry.nodeProviderSource,
    "functions/observation_absence_qualifier.js");
  assert.match(entry.canonicalImplementationSha256, /^[a-f0-9]{64}$/);
  assert(canonicalBytes(entry).equals(canonicalBytes(
    buildAbsenceParityEntry(second))));
});

test("provider remains production isolated", () => {
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production, /observation_absence_qualifier/);
  assert.doesNotMatch(production, /qualifyAbsenceBundles/);
  assert.doesNotMatch(production, /ObservationAbsenceQualifier/);
});
