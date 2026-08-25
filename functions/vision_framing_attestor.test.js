"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildFramingAttestorParityEntry,
  runFramingAttestorParity,
} = require("./backend_framing_attestor_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  attestFraming,
  decodeFramingInput,
  decodeFramingOracle,
} = require("./vision_framing_attestor");

const root = path.resolve(__dirname, "..");
const oracleDirectory = path.join(root, "test/fixtures/backend_qualification",
  "provider_oracles/vision_framing_attestor_v1");

test("framing validator has stable identity and strict oracle decoder", () => {
  assert.equal(PROVIDER_ID, "VisionFramingAttestor");
  assert.equal(PROVIDER_VERSION, "framing-attestor-v1");
  const oracle = readOracle("cropped_upper");
  assert.equal(decodeFramingOracle(oracle).scenarioId, "cropped_upper");
  assert.throws(() => decodeFramingOracle({
    ...oracle, oracleContractVersion: 2,
  }), /framing_oracle_contract_unsupported/);
  assert.throws(() => decodeFramingOracle({
    ...oracle, providerId: "Other",
  }), /framing_provider_id_invalid/);
  assert.throws(() => decodeFramingOracle({
    ...oracle, providerVersion: "other",
  }), /framing_provider_version_invalid/);
});

test("input decoder rejects unknown enums null omission and duplicates", () => {
  const input = validInput();
  assert.doesNotThrow(() => decodeFramingInput(input));
  assert.throws(() => decodeFramingInput({
    ...input, inputAssessment: "invented",
  }), /input_assessment_invalid/);
  assert.throws(() => decodeFramingInput({
    ...input, subject: {...input.subject, framingClass: "invented"},
  }), /framing_class_invalid/);
  assert.throws(() => decodeFramingInput({
    ...input, attestations: {
      ...input.attestations, visibleBoundaries: ["top", "top"],
    },
  }), /framing_boundaries_invalid/);
  const omitted = {...input};
  delete omitted.attestations;
  assert.throws(() => decodeFramingInput(omitted), /attestations_omitted/);
});

test("legacy null attestations preserve the Dart legacy result", () => {
  const output = attestFraming({...validInput(), attestations: null});
  assert.deepEqual(output, {
    modelDeclaredFraming: "full_item",
    systemAttestedFraming: "full_item",
    framingTrustState: "legacyUnverified",
    framingEvidence: null,
    framingContradictions: [],
    reasonCodes: ["legacy_schema_without_framing_attestations"],
  });
});

test("local detail severe crop and discontinuous silhouette downgrade", () => {
  const detail = attestFraming({
    ...validInput(),
    attestations: {
      ...validInput().attestations,
      localDetailOnly: true,
      visibleItemExtent: "local",
    },
  });
  assert.equal(detail.systemAttestedFraming, "detail_only");
  assert.deepEqual(detail.reasonCodes,
    ["local_detail_only", "model_full_item_downgraded"]);

  const severe = attestFraming({
    ...validInput(),
    attestations: {
      ...validInput().attestations,
      cropIndicators: ["severe_crop"],
    },
  });
  assert.equal(severe.systemAttestedFraming, "partial_item");
  assert.ok(severe.framingContradictions.includes("severe_crop"));

  const discontinuous = attestFraming({
    ...validInput(),
    attestations: {
      ...validInput().attestations,
      primarySilhouetteContinuous: false,
    },
  });
  assert.equal(discontinuous.systemAttestedFraming, "partial_item");
});

test("invalid subject cannot retain whole-item framing", () => {
  const output = attestFraming({
    ...validInput(),
    inputAssessment: "multiple_items",
  });
  assert.equal(output.systemAttestedFraming, "ambiguous_framing");
  assert.ok(output.framingContradictions.includes(
    "input_or_subject_rejects_whole_item_framing"));
});

test("conservative model framing is never silently promoted", () => {
  const input = validInput();
  const output = attestFraming({
    ...input,
    subject: {...input.subject, framingClass: "partial_item"},
  });
  assert.equal(output.systemAttestedFraming, "partial_item");
  assert.ok(output.reasonCodes.includes(
    "conservative_model_framing_not_auto_promoted"));
});

test("provider is deterministic immutable and does not mutate input", () => {
  const input = validInput();
  const before = canonicalBytes(input);
  const first = attestFraming(input);
  const second = attestFraming(input);
  assert(canonicalBytes(input).equals(before));
  assert.deepEqual(first, second);
  assert(Object.isFrozen(first));
  assert(Object.isFrozen(first.framingEvidence));
});

test("all eight scenarios and nine invocations have exact parity", () => {
  const report = runFramingAttestorParity();
  assert.equal(report.scenarioCount, 8);
  assert.equal(report.invocationCount, 9);
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.parityStatus, "parity_ready");
  for (const scenario of report.scenarios) {
    assert.equal(scenario.passed, true, scenario.scenarioId);
    for (const invocation of scenario.invocations) {
      assert.deepEqual(invocation.differences, []);
    }
  }
});

test("multi-view order and invocation cardinality are preserved", () => {
  const report = runFramingAttestorParity();
  const multi = report.scenarios.find((item) =>
    item.scenarioId === "conflicting_multi_view");
  assert.equal(multi.invocationCount, 2);
  assert.deepEqual(multi.invocations.map((item) => item.viewId),
    ["view_1", "view_2"]);
  assert(report.scenarios.filter((item) =>
    item.scenarioId !== "conflicting_multi_view")
    .every((item) => item.invocationCount === 1));
});

test("two full parity runs and manifest entries are deterministic", () => {
  const first = runFramingAttestorParity();
  const second = runFramingAttestorParity();
  assert(canonicalBytes(first).equals(canonicalBytes(second)));
  assert(canonicalBytes(buildFramingAttestorParityEntry(first)).equals(
    canonicalBytes(buildFramingAttestorParityEntry(second))));
});

test("failed report cannot become parity_ready", () => {
  const report = runFramingAttestorParity();
  const failed = buildFramingAttestorParityEntry({
    ...report,
    passedScenarios: 7,
    failedScenarios: 1,
    parityStatus: "parity_failed",
  });
  assert.equal(failed.parityStatus, "parity_failed");
});

test("Node framing migration remains outside production", () => {
  const source = fs.readFileSync(path.join(
    __dirname, "vision_framing_attestor.js"), "utf8");
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(source,
    /Date\.now|Math\.random|process\.env|fetch\(|https?:|firebase/i);
  assert.doesNotMatch(source, /firestore|storage|mapper|persistence/i);
  assert.doesNotMatch(production,
    /vision_framing_attestor|backend_framing_attestor_parity/);
});

function validInput() {
  return {
    inputAssessment: "valid_single_item",
    subject: {
      subjectCountEstimate: 1,
      cardinalityState: "single_item_supported",
      primarySubjectPresent: true,
      sameItemConsistency: "same_item_supported",
      subjectDomain: "garment_upper",
      framingClass: "full_item",
      reasonCodes: [],
    },
    quality: {
      itemFullyVisible: true,
      occlusion: "none",
      backgroundInterference: "low",
      clarity: "high",
    },
    attestations: {
      visibleBoundaries: ["bottom", "left", "right", "top"],
      primarySilhouetteContinuous: true,
      visibleItemExtent: "whole",
      localDetailOnly: false,
      cropIndicators: [],
      subjectOrientation: "front",
    },
  };
}
function readOracle(id) {
  return JSON.parse(fs.readFileSync(path.join(
    oracleDirectory, `${id}.oracle.json`), "utf8"));
}
