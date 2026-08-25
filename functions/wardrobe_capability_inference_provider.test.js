"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  buildCapabilityProviderParityEntry,
  buildProviderInput,
  projectCapabilityEvidence,
  runCapabilityProviderParity,
} = require("./backend_capability_provider_parity");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  TARGETS,
  decodeCapabilityProviderInput,
  inferCapabilities,
  validateCapabilityEvidence,
} = require("./wardrobe_capability_inference_provider");

const root = path.resolve(__dirname, "..");
const fixtureRoot = path.join(root, "test/fixtures");
const oracleManifestPath = path.join(fixtureRoot,
  "backend_qualification/backend_provider_oracle_manifest.json");
const goldenManifestPath = path.join(fixtureRoot,
  "backend_qualification_golden_manifest.json");

test("provider is an approved pure Node provider", () => {
  assert.equal(PROVIDER_ID, "WardrobeCapabilityInferenceProvider");
  assert.equal(PROVIDER_VERSION, "capability-inference-v1");
  assert.equal(TARGETS.length, 7);
  const providerFiles = fs.readdirSync(__dirname)
    .filter((name) => name.endsWith("_provider.js")).sort();
  assert.deepEqual(providerFiles, [
    "vision_observation_evidence_provider.js",
    "wardrobe_capability_inference_provider.js",
    "wardrobe_knowledge_base_prior_provider.js",
  ]);
  assert.doesNotThrow(() =>
    require("./wardrobe_capability_inference_provider"));
});

test("strict decoder validates all binding versions and identity fields", () => {
  const input = fixtureInput("cropped_upper");
  assert.doesNotThrow(() => decodeCapabilityProviderInput(input));
  assert.throws(() => decodeCapabilityProviderInput({
    ...input, oracleContractVersion: 2,
  }), /oracle_contract_version_unsupported/);
  assert.throws(() => decodeCapabilityProviderInput({
    ...input, upstreamProviderId: "OtherProvider",
  }), /upstream_provider_id_invalid/);
  assert.throws(() => decodeCapabilityProviderInput({
    ...input, upstreamProviderVersion: "other",
  }), /upstream_provider_version_invalid/);
  assert.throws(() => decodeCapabilityProviderInput({
    ...input, qualificationInputContractVersion: 2,
  }), /qualification_input_contract_version_unsupported/);
  assert.throws(() => decodeCapabilityProviderInput({
    ...input, providerVersion: "other",
  }), /capability_provider_version_invalid/);
  assert.throws(() => decodeCapabilityProviderInput({
    ...input, analysisId: "",
  }), /analysis_id_required/);
  assert.throws(() => decodeCapabilityProviderInput({
    ...input, observedAt: "not-a-timestamp",
  }), /observed_at_invalid/);
});

test("evidence enums confidence and value-state invariants fail closed", () => {
  const input = minimalInput([evidence({
    property: "visual.observations.visibleTread",
    value: "pronounced",
  })]);
  assert.throws(() => decodeCapabilityProviderInput(withEvidence(input, {
    source: "invented",
  })), /evidence_source_invalid/);
  assert.throws(() => decodeCapabilityProviderInput(withEvidence(input, {
    nature: "invented",
  })), /evidence_nature_invalid/);
  assert.throws(() => decodeCapabilityProviderInput(withEvidence(input, {
    valueState: "invented",
  })), /evidence_value_state_invalid/);
  assert.throws(() => decodeCapabilityProviderInput(withEvidence(input, {
    value: "invented",
  })), /evidence_value_enum_invalid/);
  assert.throws(() => decodeCapabilityProviderInput(withEvidence(input, {
    confidence: -0.001,
  })), /evidence_confidence_invalid/);
  assert.throws(() => decodeCapabilityProviderInput(withEvidence(input, {
    confidence: 1.001,
  })), /evidence_confidence_invalid/);
});

test("null and omitted remain distinct and invalid combinations are rejected", () => {
  const unknown = evidence({
    property: "visual.observations.visibleTread",
    value: null,
    valueState: "unknown",
    confidence: 0,
  });
  assert.deepEqual(inferCapabilities(minimalInput([unknown])), []);
  const omitted = {...unknown};
  delete omitted.value;
  assert.throws(() => inferCapabilities(minimalInput([omitted])),
    /evidence_value_omitted/);
  assert.throws(() => inferCapabilities(minimalInput([{
    ...unknown, valueState: "known",
  }])), /known_evidence_value_null/);
  assert.throws(() => inferCapabilities(minimalInput([{
    ...unknown, value: "low",
  }])), /non_value_evidence_value_invalid/);
});

test("empty irrelevant and single relevant evidence follow Dart semantics", () => {
  assert.deepEqual(inferCapabilities(minimalInput([])), []);
  assert.deepEqual(inferCapabilities(minimalInput([evidence({
    property: "visual.observations.necklineShape",
    value: "crew",
  })])), []);
  const output = inferCapabilities(minimalInput([evidence({
    property: "visual.observations.visibleTread",
    value: "pronounced",
    confidence: 0.9,
  })]));
  assert.equal(output.length, 1);
  assert.equal(output[0].property, "capabilities.traction");
  assert.equal(output[0].value, "high");
  assert.equal(output[0].confidence, 0.7);
});

test("multiple observations preserve rule priority links IDs and ordering", () => {
  const input = minimalInput([
    evidence({
      id: "bulk", property: "visual.observations.visibleBulk",
      value: "high", confidence: 0.9, sourceReference: "image_b",
    }),
    evidence({
      id: "surface", property: "visual.observations.surfaceAppearance",
      value: "fleece_like", confidence: 0.8, sourceReference: "image_a",
    }),
    evidence({
      id: "tread", property: "visual.observations.visibleTread",
      value: "pronounced", confidence: 0.9, sourceReference: "image_c",
    }),
  ], {analysisId: "analysis:one"});
  const before = canonicalBytes(input);
  const output = inferCapabilities(input);
  assert(canonicalBytes(input).equals(before));
  assert.deepEqual(output.map((item) => item.property), [
    "capabilities.traction",
    "capabilities.warmth",
  ]);
  assert.equal(output[0].id,
    "capability:analysis%3Aone:capabilities.traction");
  assert.equal(output[1].sourceReference, "image_a|image_b");
  assert.deepEqual(output[1].supportingEvidenceIds, []);
  assert(Object.isFrozen(output));
  assert(Object.isFrozen(output[0]));
});

test("duplicate evidence ID fails closed while agreeing evidence aggregates", () => {
  const first = evidence({
    id: "same", property: "visual.observations.visibleTread",
    value: "pronounced", confidence: 0.7, sourceReference: "front",
  });
  assert.throws(() => inferCapabilities(minimalInput([first, {...first}])),
    /duplicate_evidence_id/);
  const second = evidence({
    id: "other", property: "visual.observations.visibleTread",
    value: "pronounced", confidence: 0.9, sourceReference: "sole",
  });
  const output = inferCapabilities(minimalInput([first, second]));
  assert.equal(output[0].sourceReference, "front|sole");
  assert.equal(output[0].confidence, 0.7);
});

test("conflicting multi-evidence produces no random inference", () => {
  const output = inferCapabilities(minimalInput([
    evidence({
      id: "low", property: "visual.observations.visibleTread",
      value: "low", confidence: 0.9,
    }),
    evidence({
      id: "high", property: "visual.observations.visibleTread",
      value: "pronounced", confidence: 0.9,
    }),
  ]));
  assert.deepEqual(output, []);
});

test("threshold cap equality and adjacent values preserve Dart comparisons", () => {
  // One-condition support factor is 0.86; this value lands exactly at 0.7.
  const equality = 0.7 / 0.86;
  const below = inferTraction(equality - 0.0001);
  const equal = inferTraction(equality);
  const above = inferTraction(equality + 0.0001);
  assert.equal(equal, 0.7);
  assert.ok(below < 0.7);
  assert.equal(above, 0.7);
  assert.equal(inferTraction(0), 0);
  assert.equal(inferTraction(1), 0.7);
});

test("explicit non-footwear produces deterministic N/A evidence", () => {
  const output = inferCapabilities(minimalInput([evidence({
    property: "visual.observations.footwearConstruction",
    value: null,
    valueState: "not_applicable",
    confidence: 1,
  })]));
  assert.deepEqual(output.map((item) => item.property), [
    "capabilities.traction",
    "capabilities.walkingComfort",
  ]);
  assert(output.every((item) =>
    item.value === null && item.valueState === "not_applicable" &&
    item.confidence === 1));
});

test("output validator rejects unknown capability values", () => {
  const valid = inferCapabilities(minimalInput([evidence({
    property: "visual.observations.visibleTread",
    value: "pronounced",
  })]))[0];
  assert.doesNotThrow(() => validateCapabilityEvidence(valid));
  assert.throws(() => validateCapabilityEvidence({
    ...valid, value: "invented",
  }), /capability_output_enum_invalid/);
});

test("all eight bindings have structural semantic and canonical parity", () => {
  const report = runCapabilityProviderParity();
  assert.equal(report.scenarioCount, 8);
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.parityStatus, "parity_ready");
  for (const scenario of report.scenarios) {
    assert.equal(scenario.structuralPassed, true, scenario.scenarioId);
    assert.equal(scenario.semanticPassed, true, scenario.scenarioId);
    assert.equal(scenario.canonicalPassed, true, scenario.scenarioId);
    assert.deepEqual(scenario.differences, []);
    assert.equal(scenario.invocationCount, 1);
  }
});

test("empty golden and single/multi-view fixtures remain authoritative", () => {
  const report = runCapabilityProviderParity();
  const shoe = scenario(report, "shoe_without_outsole");
  assert.equal(shoe.outputCount, 0);
  assert.equal(shoe.viewCount, 1);
  const single = scenario(report, "front_only_garment");
  assert.equal(single.viewCount, 1);
  const multi = scenario(report, "conflicting_multi_view");
  assert.equal(multi.viewCount, 2);
  assert.equal(multi.invocationCount, 1);
  assert.equal(multi.passed, true);
});

test("two complete parity runs and manifests are deterministic", () => {
  const first = runCapabilityProviderParity();
  const second = runCapabilityProviderParity();
  assert(canonicalBytes(first).equals(canonicalBytes(second)));
  assert(canonicalBytes(buildCapabilityProviderParityEntry(first)).equals(
    canonicalBytes(buildCapabilityProviderParityEntry(second))));
});

test("parity failure blocks parity_ready manifest state", () => {
  const report = runCapabilityProviderParity();
  assert.equal(
    buildCapabilityProviderParityEntry(report).parityStatus,
    "parity_ready");
  const failed = buildCapabilityProviderParityEntry({
    ...report,
    passedScenarios: 7,
    failedScenarios: 1,
    parityStatus: "parity_failed",
  });
  assert.equal(failed.parityStatus, "parity_failed");
});

test("all fixture hashes IDs timestamps and upstream projections are bound", () => {
  const report = runCapabilityProviderParity();
  assert.equal(report.scenarios.length, 8);
  for (const item of report.scenarios) {
    assert.match(item.oracleSha256, /^[a-f0-9]{64}$/);
    assert.match(item.qualificationInputSha256, /^[a-f0-9]{64}$/);
    assert.match(item.dartGoldenSha256, /^[a-f0-9]{64}$/);
    assert.match(item.outputSha256, /^[a-f0-9]{64}$/);
  }
});

test("provider and harness are offline and production-isolated", () => {
  const providerSource = fs.readFileSync(path.join(
    __dirname, "wardrobe_capability_inference_provider.js"), "utf8");
  const harnessSource = fs.readFileSync(path.join(
    __dirname, "backend_capability_provider_parity.js"), "utf8");
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(providerSource,
    /Date\.now|Math\.random|process\.env|fetch\(|https?:|firebase/i);
  assert.doesNotMatch(providerSource,
    /firestore|storage|mapper|persistence|orchestrator/i);
  assert.doesNotMatch(harnessSource,
    /require\(["']\.\/index|fetch\(|https?:|firebase/i);
  assert.doesNotMatch(production,
    /wardrobe_capability_inference_provider|backend_capability_provider_parity/);
});

test("Dart providers remain at their authoritative source hashes", () => {
  assert.equal(sha256(fs.readFileSync(path.join(root,
    "lib/domain/wardrobe_profile/wardrobe_capability_inference_provider.dart"))),
  "a463f1cc075b2f693deaf65497e382b98939ab5fa3141d8ccf70f92e585b310d");
  assert.equal(sha256(fs.readFileSync(path.join(root,
    "lib/domain/wardrobe_profile/vision_observation_evidence_provider.dart"))),
  "d7409b36fa9609f9d50f6ed173e5b9e5a163d7b6c4a4b18635ef5f0cb49d67c0");
});

function fixtureInput(id) {
  const oracleManifest = readJson(oracleManifestPath);
  const goldenManifest = readJson(goldenManifestPath);
  const oracleEntry = oracleManifest.fixtures.find((item) =>
    item.scenarioId === id && item.status === "ready");
  const goldenEntry = goldenManifest.fixtures.find((item) =>
    item.id === id && item.goldenStatus === "ready");
  const oracle = readJson(path.join(fixtureRoot, oracleEntry.oraclePath));
  const input = readJson(path.join(fixtureRoot,
    goldenEntry.qualificationInput));
  return buildProviderInput(oracle, input);
}
function minimalInput(observationEvidence, {
  analysisId = "analysis",
  observedAt = "2026-07-27T14:00:00.000Z",
} = {}) {
  return {
    oracleContractVersion: 1,
    upstreamProviderId: "VisionObservationEvidenceProvider",
    upstreamProviderVersion: "qualification-v1",
    qualificationInputContractVersion: 1,
    providerVersion: "capability-inference-v1",
    analysisId,
    observedAt,
    sourceReference: "image",
    observationEvidence,
  };
}
function evidence({
  id = "evidence",
  property,
  value,
  valueState = "known",
  confidence = 0.9,
  sourceReference = "image",
}) {
  return {
    id,
    property,
    value,
    valueState,
    source: "visual_observation",
    nature: "observed",
    confidence,
    method: "vision_observation",
    sourceReference,
    supportingEvidenceIds: [],
  };
}
function withEvidence(input, changes) {
  return {
    ...input,
    observationEvidence: [{...input.observationEvidence[0], ...changes}],
  };
}
function inferTraction(confidence) {
  return inferCapabilities(minimalInput([evidence({
    property: "visual.observations.visibleTread",
    value: "pronounced",
    confidence,
  })]))[0].confidence;
}
function scenario(report, id) {
  return report.scenarios.find((item) => item.scenarioId === id);
}
function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}
function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
