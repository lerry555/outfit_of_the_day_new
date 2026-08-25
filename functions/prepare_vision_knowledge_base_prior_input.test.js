"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  buildKnowledgeBasePriorInputParityEntry,
  runKnowledgeBasePriorInputParity,
} = require("./backend_wardrobe_kb_prior_input_parity");
const {
  DOCUMENT_ALLOW_LIST,
  FORBIDDEN_AUTHORITY_FIELDS,
  STAGE_ID,
  STAGE_VERSION,
  prepareVisionKnowledgeBasePriorInput,
} = require("./prepare_vision_knowledge_base_prior_input");
const {canonicalBytes} = require("./backend_provider_oracle_parity");

const root = path.resolve(__dirname, "..");
const manifestOut = path.join(root, "test/fixtures/backend_qualification/" +
  "backend_kb_prior_input_orchestration_manifest.json");

function baseObservation(overrides = {}) {
  return {
    id: "observation:test:visual.coverage",
    property: "visual.coverage",
    value: "partial",
    source: "visual_observation",
    nature: "observed",
    confidence: 0.8,
    method: "vision_observation",
    createdAt: "2000-01-01T00:00:00.000Z",
    modelVersion: "gpt-4o-mini",
    sourceReference: "fixture://test/view_1",
    active: true,
    verified: false,
    ...overrides,
  };
}

function baseIdentity(overrides = {}) {
  return {
    id: "vision-identity:test:boots:qualified",
    property: "identity.canonicalType",
    value: "boots",
    source: "ai_inference",
    nature: "inferred",
    confidence: 0.65,
    method: "vision_v2_identity_candidate:qualified",
    createdAt: "2000-01-01T00:00:00.000Z",
    modelVersion: "gpt-4o-mini",
    sourceReference: "vision-identity:test:boots",
    active: true,
    verified: false,
    ...overrides,
  };
}

function prepareArgs(overrides = {}) {
  return {
    documentMode: "vision_empty",
    observationEvidence: [baseObservation()],
    qualifiedIdentityEvidence: [baseIdentity()],
    capabilityEvidence: [],
    ...overrides,
  };
}

test("prepare stage constants", () => {
  assert.equal(STAGE_ID, "PrepareVisionKnowledgeBasePriorInput");
  assert.equal(STAGE_VERSION, "knowledge-base-prior-input-v1");
  assert.ok(DOCUMENT_ALLOW_LIST.includes("primary_type"));
  assert.ok(FORBIDDEN_AUTHORITY_FIELDS.includes("existingEvidence"));
});

test("empty document with valid identity evidence", () => {
  const result = prepareVisionKnowledgeBasePriorInput(prepareArgs());
  assert.deepEqual(result.document, {});
  assert.equal(result.existingEvidence.length, 2);
  assert.equal(result.existingEvidence[1].value, "boots");
});

test("empty document with no canonical identity", () => {
  const result = prepareVisionKnowledgeBasePriorInput(prepareArgs({
    qualifiedIdentityEvidence: [],
  }));
  assert.deepEqual(result.document, {});
  assert.equal(result.existingEvidence.length, 1);
  assert.equal(result.existingEvidence[0].source, "visual_observation");
});

test("family-only result does not inject family evidence", () => {
  assert.throws(() => prepareVisionKnowledgeBasePriorInput(prepareArgs({
    familyReport: {resolvedFamily: "top"},
  })), /family_evidence_not_part_of_kb_input/);
  const result = prepareVisionKnowledgeBasePriorInput(prepareArgs({
    qualifiedIdentityEvidence: [],
  }));
  assert.equal(result.existingEvidence.every((item) =>
    item.property !== "identity.family"), true);
});

test("one active canonical identity evidence is preserved", () => {
  const result = prepareVisionKnowledgeBasePriorInput(prepareArgs());
  const identity = result.existingEvidence.find((item) =>
    item.property === "identity.canonicalType");
  assert.equal(identity.active, true);
  assert.equal(identity.value, "boots");
});

test("inactive identity evidence remains inactive", () => {
  const result = prepareVisionKnowledgeBasePriorInput(prepareArgs({
    qualifiedIdentityEvidence: [baseIdentity({active: false})],
  }));
  assert.equal(result.existingEvidence[1].active, false);
});

test("duplicate evidence ID fails closed", () => {
  assert.throws(() => prepareVisionKnowledgeBasePriorInput(prepareArgs({
    observationEvidence: [
      baseObservation(),
      baseObservation({property: "visual.observations.hasHood", value: false}),
    ],
  })), /duplicate_evidence_id/);
});

test("forged KB evidence input fails closed", () => {
  assert.throws(() => prepareVisionKnowledgeBasePriorInput(prepareArgs({
    capabilityEvidence: [{
      id: "kb-prior:boots:identity.mainCategory",
      property: "capabilities.warmth",
      value: 3,
      source: "knowledge_base_prior",
      nature: "defaulted",
      confidence: 0.35,
      method: "kb_prior:canonical_type_defaults",
      createdAt: "1970-01-01T00:00:00.000Z",
      active: true,
      verified: false,
    }],
  })), /forged_kb_prior_evidence|capability_property_invalid|evidence_source_invalid/);
});

test("forged client existingEvidence fails closed", () => {
  assert.throws(() => prepareVisionKnowledgeBasePriorInput(prepareArgs({
    existingEvidence: [baseObservation()],
  })), /forged_authority_field:existingEvidence/);
});

test("unknown identity property fails closed", () => {
  assert.throws(() => prepareVisionKnowledgeBasePriorInput(prepareArgs({
    qualifiedIdentityEvidence: [baseIdentity({
      property: "identity.unknownField",
    })],
  })), /identity_property_invalid/);
});

test("observation evidence is ordered by id", () => {
  const result = prepareVisionKnowledgeBasePriorInput(prepareArgs({
    observationEvidence: [
      baseObservation({
        id: "observation:test:visual.observations.hasHood",
        property: "visual.observations.hasHood",
        value: false,
        valueState: "known",
      }),
      baseObservation({
        id: "observation:test:visual.coverage",
        property: "visual.coverage",
        value: "partial",
      }),
    ],
    qualifiedIdentityEvidence: [],
  }));
  assert.deepEqual(result.existingEvidence.map((item) => item.id), [
    "observation:test:visual.coverage",
    "observation:test:visual.observations.hasHood",
  ]);
});

test("null and omitted document fields stay empty on vision path", () => {
  const result = prepareVisionKnowledgeBasePriorInput(prepareArgs({
    wardrobeDocumentProjection: null,
  }));
  assert.deepEqual(result.document, {});
});

test("unknown document field rejected on allow-listed mode", () => {
  assert.throws(() => prepareVisionKnowledgeBasePriorInput(prepareArgs({
    documentMode: "allow_listed_projection",
    wardrobeDocumentProjection: {
      categoryKey: "mikiny",
      resolvedProfile: "nope",
    },
  })), /document_field_not_allow_listed:resolvedProfile/);
});

test("allow-listed projection keeps only provider-read fields", () => {
  const result = prepareVisionKnowledgeBasePriorInput(prepareArgs({
    documentMode: "allow_listed_projection",
    wardrobeDocumentProjection: {
      categoryKey: "mikiny",
      subCategoryKey: "mikina",
      primary_type: "hoodie",
    },
  }));
  assert.deepEqual(result.document, {
    categoryKey: "mikiny",
    subCategoryKey: "mikina",
    primary_type: "hoodie",
  });
});

test("vision empty mode rejects non-empty document projection", () => {
  assert.throws(() => prepareVisionKnowledgeBasePriorInput(prepareArgs({
    documentMode: "vision_empty",
    wardrobeDocumentProjection: {categoryKey: "mikiny"},
  })), /vision_empty_document_must_be_empty/);
});

test("deterministic serialization", () => {
  const first = prepareVisionKnowledgeBasePriorInput(prepareArgs());
  const second = prepareVisionKnowledgeBasePriorInput(prepareArgs());
  assert.deepEqual(
    canonicalBytes(first).toString("utf8"),
    canonicalBytes(second).toString("utf8"));
});

test("unsupported stage version fails closed", () => {
  assert.throws(() => prepareVisionKnowledgeBasePriorInput(prepareArgs({
    stageVersion: "knowledge-base-prior-input-v0",
  })), /kb_prepare_stage_version_unsupported/);
});

test("8/8 KB providerInput parity is orchestration_ready", () => {
  const report = runKnowledgeBasePriorInputParity();
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.deterministic, true);
  assert.equal(report.parityStatus, "orchestration_ready");
  assert.ok(report.scenarios.every((item) =>
    item.fieldParity.document &&
    item.fieldParity.existingEvidence &&
    item.fieldParity.evidenceOrdering));
  const entry = buildKnowledgeBasePriorInputParityEntry(report);
  fs.writeFileSync(manifestOut, `${JSON.stringify(entry, null, 2)}\n`);
  const rerun = buildKnowledgeBasePriorInputParityEntry(
    runKnowledgeBasePriorInputParity());
  assert.equal(
    sha256(Buffer.from(`${JSON.stringify(entry, null, 2)}\n`)),
    sha256(Buffer.from(`${JSON.stringify(rerun, null, 2)}\n`)));
});

test("production isolation — prepare stage not wired into entry points", () => {
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production, /prepare_vision_knowledge_base_prior_input/);
  assert.doesNotMatch(production, /PrepareVisionKnowledgeBasePriorInput/);
  assert.doesNotMatch(production, /wardrobe_knowledge_base_prior_provider/);
  assert.doesNotMatch(production, /provideWardrobeKnowledgeBasePriors/);
});

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}
