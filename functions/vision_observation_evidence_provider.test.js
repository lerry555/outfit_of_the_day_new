"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  PROPERTY_SPECS,
  PROVIDER_ID,
  decodeProviderInput,
  decodeProviderOracle,
  provideObservationEvidence,
} = require("./vision_observation_evidence_provider");
const {
  buildProviderParityManifest,
  canonicalBytes,
  diff,
  runObservationEvidenceProviderParity,
} = require("./backend_provider_oracle_parity");

const root = path.resolve(__dirname, "..");
const oracleDirectory = path.join(root, "test/fixtures/backend_qualification",
  "provider_oracles/vision_observation_evidence_v1");

test("observation provider remains the first of approved provider ports", () => {
  assert.equal(PROVIDER_ID, "VisionObservationEvidenceProvider");
  assert.equal(PROPERTY_SPECS.length, 15);
  const providerPorts = fs.readdirSync(__dirname)
    .filter((name) => name.endsWith("_provider.js") &&
      name !== "vision_parser_fixture_capture_provider.js")
    .sort();
  assert.deepEqual(providerPorts, [
    "vision_observation_evidence_provider.js",
    "wardrobe_capability_inference_provider.js",
    "wardrobe_knowledge_base_prior_provider.js",
  ]);
});

test("input and oracle contracts fail closed", () => {
  const oracle = readOracle("cropped_upper");
  assert.equal(decodeProviderOracle(oracle).scenarioId, "cropped_upper");
  assert.throws(() => decodeProviderOracle({
    ...oracle, oracleContractVersion: 2,
  }), /oracle_contract_version_unsupported/);
  assert.throws(() => decodeProviderOracle({
    ...oracle, providerId: "OtherProvider",
  }), /oracle_provider_id_invalid/);
  assert.throws(() => decodeProviderInput({
    ...oracle.providerInput,
    coverage: {...oracle.providerInput.coverage, state: "invented"},
  }), /observation_state_invalid:coverage/);
  assert.throws(() => decodeProviderInput({
    ...oracle.providerInput,
    surfaceAppearance: {
      state: "observed", value: "invented", confidence: 0.5,
    },
  }), /enum_value_invalid:surfaceAppearance/);
});

test("null and omitted observation remain distinct", () => {
  const input = structuredClone(readOracle("cropped_upper").providerInput);
  delete input.coverage;
  const omitted = decodeProviderInput(input);
  assert.equal(Object.hasOwn(omitted, "coverage"), false);
  assert.throws(() => decodeProviderInput({...input, coverage: null}),
    /observation_null_not_allowed:coverage/);
});

test("non-value states preserve Dart confidence and scope invariants", () => {
  const input = structuredClone(readOracle("cropped_upper").providerInput);
  assert.throws(() => decodeProviderInput({
    ...input, coverage: {state: "unknown", confidence: 0.1},
  }), /non_observed_confidence_invalid:coverage/);
  assert.throws(() => decodeProviderInput({
    ...input, coverage: {
      state: "not_visible", confidence: 0, visibilityScope: "partial",
    },
  }), /not_visible_scope_invalid:coverage/);
  assert.throws(() => decodeProviderInput({
    ...input, coverage: {
      state: "not_applicable", confidence: 1, value: "full",
    },
  }), /non_observed_value_forbidden:coverage/);
});

test("provider output is immutable and follows Dart property ordering", () => {
  const oracle = readOracle("cropped_upper");
  const inputSnapshot = canonicalBytes(oracle.providerInput);
  const output = provideObservationEvidence(oracle.providerInput);
  assert(Object.isFrozen(output));
  assert(Object.isFrozen(output[0]));
  assert.deepEqual(output.map((item) => item.property),
    oracle.providerOutput.map((item) => item.property));
  assert(canonicalBytes(oracle.providerInput).equals(inputSnapshot));
});

test("all eight provider oracles have structural and canonical parity", () => {
  const report = runObservationEvidenceProviderParity();
  assert.equal(report.scenarioCount, 8);
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.parityStatus, "parity_ready");
  for (const scenario of report.scenarios) {
    assert.equal(scenario.passed, true, scenario.scenarioId);
    assert.deepEqual(scenario.differences, []);
  }
});

test("single and multi-view oracle provenance remains ordered", () => {
  const single = decodeProviderOracle(readOracle("front_only_garment"));
  assert.equal(single.orderedViewProvenance.length, 1);
  assert.equal(single.orderedViewProvenance[0].viewId, "view_1");
  const multi = decodeProviderOracle(readOracle("conflicting_multi_view"));
  assert.deepEqual(multi.orderedViewProvenance.map((item) => item.viewId),
    ["view_1", "view_2"]);
  assert.deepEqual(provideObservationEvidence(multi.providerInput),
    multi.providerOutput);
});

test("two full parity runs are byte-identical", () => {
  const first = runObservationEvidenceProviderParity();
  const second = runObservationEvidenceProviderParity();
  assert(canonicalBytes(first).equals(canonicalBytes(second)));
  assert.deepEqual(first.scenarios.map((item) => item.outputSha256),
    second.scenarios.map((item) => item.outputSha256));
});

test("diff reports an exact JSON path without dumping the oracle", () => {
  const differences = diff(
    [{valueState: "known", confidence: 0.8}],
    [{valueState: "unknown", confidence: 0.8}],
  );
  assert.deepEqual(differences, [{
    jsonPath: "$[0].valueState",
    expected: "known",
    actual: "unknown",
    mismatchType: "enum_mismatch",
  }]);
});

test("parity manifest becomes ready only for complete parity", () => {
  const report = runObservationEvidenceProviderParity();
  const ready = buildProviderParityManifest(report);
  assert.equal(ready.providers.length, 1);
  assert.equal(ready.providers[0].parityStatus, "parity_ready");
  const failed = buildProviderParityManifest({
    ...report, passedScenarios: 7, failedScenarios: 1,
    parityStatus: "parity_failed",
  });
  assert.equal(failed.providers[0].parityStatus, "parity_failed");
});

test("provider is pure offline and absent from production entry points", () => {
  const source = fs.readFileSync(path.join(__dirname,
    "vision_observation_evidence_provider.js"), "utf8");
  const parity = fs.readFileSync(path.join(__dirname,
    "backend_provider_oracle_parity.js"), "utf8");
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(root,
      "lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(source, /Date\.now|Math\.random|fetch\(|https?:|firebase/i);
  assert.doesNotMatch(source, /mapper|persistence|firestore|storage/i);
  assert.doesNotMatch(parity, /require\(["']\.\/index|firebase|https?:/i);
  assert.doesNotMatch(production,
    /vision_observation_evidence_provider\.js|backend_provider_oracle_parity/);
});

test("oracle, parser, input, golden, and Dart provider integrity is stable", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root,
    "test/fixtures/backend_qualification/backend_provider_oracle_manifest.json")));
  for (const entry of manifest.fixtures.filter((item) =>
    item.status === "ready")) {
    const oraclePath = path.join(root, "test/fixtures",
      entry.oraclePath);
    assert.equal(sha256(fs.readFileSync(oraclePath)), entry.oracleSha256);
  }
  assert.equal(
    sha256(fs.readFileSync(path.join(root,
      "lib/domain/wardrobe_profile/vision_observation_evidence_provider.dart"))),
    "d7409b36fa9609f9d50f6ed173e5b9e5a163d7b6c4a4b18635ef5f0cb49d67c0",
  );
});

function readOracle(id) {
  return JSON.parse(fs.readFileSync(path.join(oracleDirectory,
    `${id}.oracle.json`), "utf8"));
}
function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
