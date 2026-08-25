"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildApplicabilityParityEntry,
  runApplicabilityQualifierParity,
} = require("./backend_applicability_qualifier_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeApplicabilityInput,
  qualifyApplicability,
} = require("./vision_property_applicability_qualifier");

test("applicability qualifier has stable identity and strict input", () => {
  assert.equal(PROVIDER_ID, "VisionPropertyApplicabilityQualifier");
  assert.equal(PROVIDER_VERSION, "applicability-v1");
  const input = fixtureInput();
  assert.doesNotThrow(() => decodeApplicabilityInput(input));
  assert.throws(() => decodeApplicabilityInput({
    ...input,
    subject: {...input.subject, subjectDomain: "invented"},
  }), /applicability_subject_domain_invalid/);
  assert.throws(() => decodeApplicabilityInput({
    ...input,
    bundle: {...input.bundle, coverage: {
      state: "observed", value: "invented", confidence: 0.5,
    }},
  }), /enum_value_invalid:coverage/);
});

test("garment footwear and shared applicability exactly follow registry", () => {
  const garment = qualifyApplicability(fixtureInput("garment_upper"));
  assert.equal(garment.properties.hasHood.state, "applicable");
  assert.equal(garment.properties.footwearConstruction.state, "notApplicable");
  assert.deepEqual(garment.qualifiedBundle.footwearConstruction,
    {state: "not_applicable", confidence: 1});

  const footwear = qualifyApplicability(fixtureInput("footwear"));
  assert.equal(footwear.properties.coverage.state, "notApplicable");
  assert.equal(footwear.properties.footwearConstruction.state, "applicable");
  assert.equal(footwear.properties.sportyCues.state, "applicable");
});

test("unknown domain is conservative including shared uncertainty", () => {
  const output = qualifyApplicability(fixtureInput("unknown"));
  assert.equal(output.properties.coverage.state, "notApplicable");
  assert.equal(output.properties.sportyCues.state, "uncertain");
  assert.deepEqual(output.qualifiedBundle.sportyCues,
    {state: "not_applicable", confidence: 1});
});

test("missing observations stay omitted and applicable values are preserved", () => {
  const input = fixtureInput();
  delete input.bundle.hasHood;
  const output = qualifyApplicability(input);
  assert.equal(Object.hasOwn(output.properties, "hasHood"), false);
  assert.deepEqual(output.qualifiedBundle.coverage, input.bundle.coverage);
});

test("provider is immutable deterministic and does not mutate input", () => {
  const input = fixtureInput();
  const before = canonicalBytes(input);
  const first = qualifyApplicability(input);
  const second = qualifyApplicability(input);
  assert(canonicalBytes(input).equals(before));
  assert.deepEqual(first, second);
  assert(Object.isFrozen(first));
  assert(Object.isFrozen(first.qualifiedBundle));
});

test("all eight scenarios and nine invocations have exact parity", () => {
  const report = runApplicabilityQualifierParity();
  assert.equal(report.scenarioCount, 8);
  assert.equal(report.invocationCount, 9);
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.parityStatus, "parity_ready");
  assert(report.scenarios.every((item) => item.passed));
  assert(report.scenarios.flatMap((item) => item.invocations)
    .every((item) => item.differences.length === 0));
});

test("multi-view ordering and deterministic rerun are stable", () => {
  const first = runApplicabilityQualifierParity();
  const second = runApplicabilityQualifierParity();
  assert(canonicalBytes(first).equals(canonicalBytes(second)));
  const multi = first.scenarios.find((item) =>
    item.scenarioId === "conflicting_multi_view");
  assert.deepEqual(multi.invocations.map((item) => item.viewId),
    ["view_1", "view_2"]);
  assert(canonicalBytes(buildApplicabilityParityEntry(first)).equals(
    canonicalBytes(buildApplicabilityParityEntry(second))));
});

test("applicability Node stage remains production isolated", () => {
  const root = path.resolve(__dirname, "..");
  const source = fs.readFileSync(path.join(
    __dirname, "vision_property_applicability_qualifier.js"), "utf8");
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(source,
    /Date\.now|Math\.random|process\.env|fetch\(|https?:|firebase/i);
  assert.doesNotMatch(source, /firestore|storage|mapper|persistence/i);
  assert.doesNotMatch(production,
    /vision_property_applicability_qualifier|backend_applicability_qualifier/);
  assert.equal(fs.existsSync(path.join(root,
    "lib/domain/wardrobe_profile/vision_subject_safety.dart")), true);
});

function fixtureInput(domain = "garment_upper") {
  return {
    bundle: {
      analysisId: "analysis",
      modelVersion: "model",
      sourceReference: "image",
      observedAt: "2026-07-31T00:00:00.000Z",
      quality: {},
      coverage: {
        state: "observed",
        value: "full",
        confidence: 0.9,
      },
      hasHood: {
        state: "observed",
        value: true,
        confidence: 0.8,
      },
      sportyCues: {
        state: "observed",
        value: "high",
        confidence: 0.8,
      },
      footwearConstruction: {
        state: "observed",
        value: "closed",
        confidence: 0.9,
      },
    },
    subject: {subjectDomain: domain},
  };
}
