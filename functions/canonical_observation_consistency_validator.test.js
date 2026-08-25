"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildCanonicalConsistencyParityEntry,
  runCanonicalConsistencyParity,
} = require("./backend_canonical_consistency_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeCanonicalConsistencyInput,
  validateCanonicalConsistency,
} = require("./canonical_observation_consistency_validator");

test("canonical validator has stable identity and strict input", () => {
  assert.equal(PROVIDER_ID, "CanonicalObservationConsistencyValidator");
  assert.equal(PROVIDER_VERSION, "canonical-consistency-v1");
  assert.doesNotThrow(() => decodeCanonicalConsistencyInput(fixtureInput()));
  assert.throws(() => decodeCanonicalConsistencyInput({}),
    /canonical_consistency_input_invalid/);
});

test("unknown signatures remain uncertain without invented support", () => {
  const input = fixtureInput();
  input.identityEvidence[0].value = "invented";
  const output = validateCanonicalConsistency(input);
  assert.equal(output.results[0].compatibilityLevel, "uncertain");
  assert.deepEqual(output.results[0].missingExpectedEvidence,
    ["signature.unavailable"]);
});

test("conflicting observations are aggregated conservatively", () => {
  const input = fixtureInput();
  input.observationEvidence.push({
    ...input.observationEvidence[0],
    id: "observation-2",
    value: false,
  });
  const output = validateCanonicalConsistency(input);
  assert.equal(output.results[0].compatibilityLevel, "uncertain");
  assert.deepEqual(output.results[0].conflictingEvidence,
    ["visual.observations.hasHood"]);
});

test("provider is immutable deterministic and does not mutate input", () => {
  const input = fixtureInput();
  const before = canonicalBytes(input);
  const first = validateCanonicalConsistency(input);
  const second = validateCanonicalConsistency(input);
  assert(canonicalBytes(input).equals(before));
  assert.deepEqual(first, second);
  assert(Object.isFrozen(first));
});

test("all eight canonical consistency scenarios have exact parity", () => {
  const report = runCanonicalConsistencyParity();
  assert.equal(report.scenarioCount, 8);
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.parityStatus, "parity_ready");
  assert(report.scenarios.every((item) => item.differences.length === 0));
});

test("parity rerun and manifest entry are deterministic", () => {
  const first = runCanonicalConsistencyParity();
  const second = runCanonicalConsistencyParity();
  assert(canonicalBytes(first).equals(canonicalBytes(second)));
  assert(canonicalBytes(buildCanonicalConsistencyParityEntry(first)).equals(
    canonicalBytes(buildCanonicalConsistencyParityEntry(second))));
});

test("canonical validator remains production isolated", () => {
  const source = fs.readFileSync(path.join(
    __dirname, "canonical_observation_consistency_validator.js"), "utf8");
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(source,
    /Date\.now|Math\.random|process\.env|fetch\(|https?:|firebase/i);
  assert.doesNotMatch(source, /firestore|storage|mapper|persistence/i);
  assert.doesNotMatch(production,
    /canonical_observation_consistency_validator|backend_canonical_consistency/);
});

function fixtureInput() {
  return {
    identityEvidence: [{
      id: "identity",
      property: "identity.canonicalType",
      value: "hoodie",
      source: "ai_inference",
      nature: "inferred",
      confidence: 0.8,
      verified: false,
      active: true,
      method: "fixture",
      createdAt: "2026-07-31T00:00:00.000Z",
    }],
    observationEvidence: [{
      id: "observation",
      property: "visual.observations.hasHood",
      value: true,
      source: "visual_observation",
      nature: "observed",
      confidence: 0.8,
      verified: false,
      active: true,
      method: "fixture",
      createdAt: "2026-07-31T00:00:00.000Z",
    }],
  };
}
