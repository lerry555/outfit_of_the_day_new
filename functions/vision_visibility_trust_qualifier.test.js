"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildVisibilityParityEntry,
  runVisibilityTrustParity,
} = require("./backend_visibility_trust_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeVisibilityInput,
  qualifyVisibility,
} = require("./vision_visibility_trust_qualifier");

test("visibility qualifier has stable identity and strict context", () => {
  assert.equal(PROVIDER_ID, "VisionVisibilityTrustQualifier");
  assert.equal(PROVIDER_VERSION, "visibility-trust-v1");
  const input = fixtureInput();
  assert.doesNotThrow(() => decodeVisibilityInput(input));
  assert.throws(() => decodeVisibilityInput({
    ...input, inputAssessment: "invented",
  }), /visibility_input_assessment_invalid/);
  assert.throws(() => decodeVisibilityInput({
    ...input, complementaryRegions: {coverage: ["invented"]},
  }), /visibility_complementary_region_invalid/);
});

test("invalid input rejects observations and preserves not applicable", () => {
  const output = qualifyVisibility({
    ...fixtureInput(), inputAssessment: "multiple_items",
  });
  assert.deepEqual(output.qualifiedBundle.coverage,
    {state: "unknown", confidence: 0});
  assert.equal(output.properties.coverage.visibilityTrust, "rejected");
});

test("quality and confidence calibration preserve exact v1 semantics", () => {
  const input = fixtureInput();
  input.bundle.coverage.confidence = 0.99;
  input.bundle.quality.itemFullyVisible = false;
  const output = qualifyVisibility(input);
  assert.equal(output.qualifiedBundle.coverage.visibilityScope, "sufficient");
  assert.equal(output.qualifiedBundle.coverage.confidence, 0.95);
  assert.deepEqual(output.properties.coverage.reasonCodes, [
    "cropped_item_downgraded_complete",
    "visibility_confidence_calibrated",
  ]);
});

test("sufficient pocket absence does not meet complete absence minimum", () => {
  const input = fixtureInput();
  input.bundle.visiblePocketStructure = {
    state: "observed",
    value: "none",
    confidence: 0.9,
    visibilityScope: "sufficient",
    visibleRegions: ["front", "side", "pocket_area"],
  };
  input.viewCount = 2;
  input.complementaryRegions = {
    visiblePocketStructure: ["front", "side", "pocket_area"],
  };
  const output = qualifyVisibility(input);
  assert(output.properties.visiblePocketStructure.reasonCodes.includes(
    "qualified_scope_below_property_minimum"));
  assert.deepEqual(output.qualifiedBundle.visiblePocketStructure,
    {state: "unknown", confidence: 0});
});

test("provider is immutable deterministic and does not mutate input", () => {
  const input = fixtureInput();
  const before = canonicalBytes(input);
  const first = qualifyVisibility(input);
  const second = qualifyVisibility(input);
  assert(canonicalBytes(input).equals(before));
  assert.deepEqual(first, second);
  assert(Object.isFrozen(first));
});

test("all eight scenarios and nine invocations have exact parity", () => {
  const report = runVisibilityTrustParity();
  assert.equal(report.scenarioCount, 8);
  assert.equal(report.invocationCount, 9);
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.parityStatus, "parity_ready");
  assert(report.scenarios.flatMap((item) => item.invocations)
    .every((item) => item.differences.length === 0));
});

test("multi-view ordering and deterministic rerun are stable", () => {
  const first = runVisibilityTrustParity();
  const second = runVisibilityTrustParity();
  assert(canonicalBytes(first).equals(canonicalBytes(second)));
  const multi = first.scenarios.find((item) =>
    item.scenarioId === "conflicting_multi_view");
  assert.deepEqual(multi.invocations.map((item) => item.viewId),
    ["view_1", "view_2"]);
  assert(canonicalBytes(buildVisibilityParityEntry(first)).equals(
    canonicalBytes(buildVisibilityParityEntry(second))));
});

test("visibility Node stage remains production isolated", () => {
  const source = fs.readFileSync(path.join(
    __dirname, "vision_visibility_trust_qualifier.js"), "utf8");
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(source,
    /Date\.now|Math\.random|process\.env|fetch\(|https?:|firebase/i);
  assert.doesNotMatch(source, /firestore|storage|mapper|persistence/i);
  assert.doesNotMatch(production,
    /vision_visibility_trust_qualifier|backend_visibility_trust_parity/);
});

function fixtureInput() {
  return {
    bundle: {
      analysisId: "analysis",
      modelVersion: "model",
      sourceReference: "image",
      observedAt: "2026-07-31T00:00:00.000Z",
      quality: {
        clarity: "high",
        occlusion: "none",
        itemFullyVisible: true,
        backgroundInterference: "low",
      },
      coverage: {
        state: "observed",
        value: "full",
        confidence: 0.9,
        visibilityScope: "complete",
        visibleRegions: ["full_silhouette"],
      },
    },
    inputAssessment: "valid_single_item",
    viewCount: 1,
    complementaryRegions: {},
  };
}
