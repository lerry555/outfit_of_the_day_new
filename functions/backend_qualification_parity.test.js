"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");
const {
  validateQualificationInput,
  validateQualificationReference,
} = require("./backend_qualification_contract");
const {
  PARITY_KINDS,
  assertParity,
  compareFixtureParity,
  compareParity,
  loadGoldenManifest,
  normalizeReference,
} = require("./backend_qualification_parity");

function input(overrides = {}) {
  return {
    contractVersion: 1,
    analysisId: "analysis-1",
    sourceReference: "fixture://cropped_upper",
    modelIdentifier: "vision-model-v1",
    visionSchemaVersion: 9,
    observedAt: "2026-07-29T10:00:00.000Z",
    quality: {clarity: "high"},
    inputAssessment: "valid_single_item",
    subjectAssessment: {framingClass: "partial_item"},
    observations: {coverage: {state: "observed", value: "partial"}},
    identityCandidates: [],
    validationErrors: [],
    ...overrides,
  };
}

function evidence({
  id = "observation:analysis-1:coverage",
  property = "visual.coverage",
  value = "partial",
  valueState = "known",
  supportingEvidenceIds = [],
  qualificationTier,
} = {}) {
  const result = {
    id,
    property,
    value,
    valueState,
    source: "visual_observation",
    nature: "observed",
    confidence: 0.8,
    method: "vision_observation",
    supportingEvidenceIds,
  };
  if (qualificationTier != null) {
    result.qualificationTier = qualificationTier;
  }
  return result;
}

function reference(overrides = {}) {
  const observation = evidence();
  const canonical = evidence({
    id: "canonical:analysis-1:t_shirt",
    property: "identity.canonicalType",
    value: "t_shirt",
    supportingEvidenceIds: [observation.id],
    qualificationTier: "supported",
  });
  const capability = evidence({
    id: "capability:analysis-1:mobility",
    property: "capabilities.mobility",
    value: 7,
    supportingEvidenceIds: [observation.id],
  });
  return {
    contractVersion: 1,
    fixtureId: "cropped_upper",
    producer: "dart_vision_v2_shadow_orchestrator",
    producerVersion: "qualification-v1",
    observationEvidence: [observation],
    identityQualification: {
      tier: "supported",
      selectedCanonicalType: "t_shirt",
    },
    familyQualification: {tier: "supported", family: "top"},
    capabilityEvidence: [capability],
    omittedReasons: ["identity_omitted:framing_limit"],
    machineEvidence: [observation, canonical, capability],
    ...overrides,
  };
}

test("qualification input DTO is versioned and excludes resolved output", () => {
  assert.deepEqual(validateQualificationInput(input()), []);
  assert.deepEqual(
    validateQualificationInput(input({resolvedProfile: {canonical: "x"}})),
    ["input.resolvedProfile.forbidden"],
  );
  assert.deepEqual(
    validateQualificationInput(input({contractVersion: 2})),
    ["input.contractVersion.unsupported"],
  );
});

test("reference contract covers parity-critical fields", () => {
  assert.deepEqual(validateQualificationReference(reference()), []);
  const invalid = reference({
    identityQualification: {tier: "invented"},
    machineEvidence: [evidence({valueState: "neutral"})],
  });
  assert.deepEqual(validateQualificationReference(invalid), [
    "reference.identityQualification.tier.invalid",
    "reference.machineEvidence.0.valueState.invalid",
  ]);
});

test("loader references the one existing Phase 4.9 scenario catalog", () => {
  const manifest = loadGoldenManifest(path.resolve(
    __dirname,
    "../test/fixtures/backend_qualification_golden_manifest.json",
  ));
  assert.equal(manifest.fixtures.length, 16);
  assert.equal(manifest.fixtures[0].id, "cropped_upper");
  assert.equal(manifest.fixtures[0].scenario.id, "cropped_upper");
  assert.equal(manifest.fixtures[0].goldenStatus, "ready");
  assert.equal(manifest.fixtures[0].dartReference.fixtureId, "cropped_upper");
  assert(Object.isFrozen(manifest.fixtures[0].scenario));
  assert.equal(
    compareFixtureParity(
      manifest.fixtures[0],
      structuredClone(manifest.fixtures[0].dartReference),
    ).kind,
    "byte_identical",
  );
});

test("byte-identical output has the strongest parity result", () => {
  assert.equal(
    compareParity(reference(), structuredClone(reference())).kind,
    PARITY_KINDS.BYTE_IDENTICAL,
  );
});

test("map and evidence ordering differences are semantically identical", () => {
  const expected = reference();
  const actual = {
    machineEvidence: [...expected.machineEvidence].reverse(),
    omittedReasons: expected.omittedReasons,
    capabilityEvidence: expected.capabilityEvidence,
    familyQualification: expected.familyQualification,
    identityQualification: expected.identityQualification,
    observationEvidence: expected.observationEvidence,
    producerVersion: expected.producerVersion,
    producer: expected.producer,
    fixtureId: expected.fixtureId,
    contractVersion: expected.contractVersion,
  };
  assert.equal(
    compareParity(expected, actual).kind,
    PARITY_KINDS.SEMANTICALLY_IDENTICAL,
  );
  assert.deepEqual(
    normalizeReference(actual).machineEvidence.map((item) => item.id),
    [...expected.machineEvidence].sort((a, b) => a.id.localeCompare(b.id))
      .map((item) => item.id),
  );
});

test("omitted reasons compare as deterministic set", () => {
  const expected = reference({
    omittedReasons: ["b", "a"],
  });
  const actual = reference({
    omittedReasons: ["a", "b", "a"],
  });
  assert.equal(
    compareParity(expected, actual).kind,
    PARITY_KINDS.SEMANTICALLY_IDENTICAL,
  );
});

test("qualification tier difference is a parity failure", () => {
  const actual = reference({
    identityQualification: {
      tier: "confirmed",
      selectedCanonicalType: "t_shirt",
    },
  });
  const report = compareParity(reference(), actual);
  assert.equal(report.kind, PARITY_KINDS.FAILURE);
  assert(report.differences.some((item) =>
    item.path === "$.identityQualification.tier"));
  assert.throws(() => assertParity(reference(), actual),
    /qualification_parity_failed/);
});

test("evidence ID and valueState differences are failures", () => {
  const actual = reference();
  actual.observationEvidence = [
    evidence({id: "different-id", valueState: "unknown"}),
  ];
  const report = compareParity(reference(), actual);
  assert.equal(report.kind, PARITY_KINDS.FAILURE);
  assert(report.differences.some((item) => item.path.endsWith(".id")));
  assert(report.differences.some((item) => item.path.endsWith(".valueState")));
});

test("supporting evidence IDs are order-insensitive but membership-sensitive", () => {
  const expected = reference();
  expected.capabilityEvidence[0].supportingEvidenceIds = ["support:b", "support:a"];
  const reordered = structuredClone(expected);
  reordered.capabilityEvidence[0].supportingEvidenceIds.reverse();
  assert.equal(
    compareParity(expected, reordered).kind,
    PARITY_KINDS.SEMANTICALLY_IDENTICAL,
  );
  reordered.capabilityEvidence[0].supportingEvidenceIds = ["support:a"];
  assert.equal(
    compareParity(expected, reordered).kind,
    PARITY_KINDS.FAILURE,
  );
});

test("intentional difference needs path reason and decision reference", () => {
  const actual = reference({
    familyQualification: {tier: "confirmed", family: "top"},
  });
  const accepted = compareParity(reference(), actual, {
    intentionalDifferences: [{
      path: "$.familyQualification.tier",
      reason: "Backend fixes documented tier naming defect.",
      decisionReference: "ADR-003",
    }],
  });
  assert.equal(accepted.kind, PARITY_KINDS.INTENTIONAL_DIFFERENCE);

  const undeclared = compareParity(reference(), actual);
  assert.equal(undeclared.kind, PARITY_KINDS.FAILURE);
  const malformed = compareParity(reference(), actual, {
    intentionalDifferences: [{
      path: "$.familyQualification.tier",
      reason: "",
      decisionReference: "",
    }],
  });
  assert.equal(malformed.kind, PARITY_KINDS.FAILURE);
  assert.equal(
    malformed.reasonCode,
    "intentional_difference_declaration_invalid",
  );
});
