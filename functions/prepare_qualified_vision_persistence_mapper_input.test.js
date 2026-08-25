"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildQualifiedVisionPersistenceMapperInputParityEntry,
  runQualifiedVisionPersistenceMapperInputParity,
  updateMapperInputOrchestrationManifest,
} = require("./backend_qualified_vision_persistence_mapper_input_parity");
const {
  FIXTURE_CONTEXT_MODE,
  FORBIDDEN_AUTHORITY_FIELDS,
  PRODUCTION_CONTEXT_MODE,
  STAGE_ID,
  STAGE_VERSION,
  prepareQualifiedVisionPersistenceMapperInput,
} = require("./prepare_qualified_vision_persistence_mapper_input");

const root = path.resolve(__dirname, "..");
const manifestOut = path.join(root, "test/fixtures/backend_qualification/" +
  "backend_qualified_vision_persistence_mapper_input_orchestration_manifest.json");

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
    id: "vision-identity:test:hoodie:qualified",
    property: "identity.canonicalType",
    value: "hoodie",
    source: "ai_inference",
    nature: "inferred",
    confidence: 0.7,
    method: "vision_v2_identity_candidate:qualified",
    createdAt: "2000-01-01T00:00:00.000Z",
    modelVersion: "gpt-4o-mini",
    active: true,
    verified: false,
    ...overrides,
  };
}

function baseCapability(overrides = {}) {
  return {
    id: "capability:test:capabilities.warmth",
    property: "capabilities.warmth",
    value: "medium",
    source: "ai_inference",
    nature: "inferred",
    confidence: 0.55,
    method: "capability_inference:warmth.bulk_and_insulating_surface",
    createdAt: "2000-01-01T00:00:00.000Z",
    modelVersion: "capability-inference-v1",
    active: true,
    verified: false,
    ...overrides,
  };
}

function baseMultiPhoto(overrides = {}) {
  return {
    physicalIdentity: "sameItemSupported",
    semanticAgreement: "consistent",
    multiViewSubjectBinding: {
      contractVersion: 1,
      physicalIdentityClaim: "undeclared",
      reasonCodes: ["default_undeclared"],
      source: "unknown",
    },
    sameItemViews: true,
    permitsIdentityPromotion: true,
    reasonCodes: ["single_view_local_same_item"],
    ...overrides,
  };
}

function baseInput(overrides = {}) {
  return {
    contextMode: FIXTURE_CONTEXT_MODE,
    scenarioId: "unit_scenario",
    analysisId: "analysis-1",
    modelVersion: "gpt-4o-mini",
    schemaVersion: 9,
    inputAssessment: "valid_single_item",
    observationEvidence: [baseObservation()],
    observationProvenance: {
      observedAt: "2000-01-01T00:00:00.000Z",
      modelVersion: "gpt-4o-mini",
      sourceReference: "fixture://test/view_1",
    },
    qualifiedIdentityEvidence: [baseIdentity()],
    identityQualification: {
      candidates: [],
      selectedCanonicalType: "hoodie",
      state: "supported",
      topMargin: 0.2,
    },
    familyIdentity: {
      candidates: [],
      confidence: 0.8,
      reasonCodes: [],
      resolvedFamily: "top",
      state: "confirmed",
      subtypeCandidates: ["hoodie"],
      subtypeResolved: true,
    },
    capabilityEvidence: [baseCapability()],
    multiPhotoAssessment: baseMultiPhoto(),
    ...overrides,
  };
}

function throwsCode(fn, code) {
  assert.throws(fn, (error) => {
    assert.equal(error.message, code);
    return true;
  });
}

test("valid fixture context prepares mapper input", () => {
  const prepared = prepareQualifiedVisionPersistenceMapperInput(baseInput());
  assert.equal(prepared.analysisProjection.analysisId, "analysis-1");
  assert.equal(prepared.analysisProjection.inputAssessmentValid, true);
  assert.equal(prepared.mappingContext.generationId,
    "fixture-generation:unit_scenario");
  assert.equal(prepared.mappingContext.revision, 1);
  assert.equal(prepared.mappingContext.storagePath,
    "fixture://wardrobe/unit_scenario/source.jpg");
  assert.equal(prepared.analysisProjection.observationEvidence.length, 1);
  assert.equal(prepared.analysisProjection.capabilityEvidence.length, 1);
});

test("production mode without trusted revision context fails closed", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    contextMode: PRODUCTION_CONTEXT_MODE,
    scenarioId: undefined,
    trustedMappingContext: null,
  })), "trusted_revision_context_unavailable");
});

test("mismatched analysis id fails", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    analysisId: "analysis-1",
    trustedMappingContext: {
      generationId: "gen-1",
      revision: 1,
      createdAt: "2000-01-01T00:00:00.000Z",
      updatedAt: "2000-01-01T00:00:00.000Z",
      imageRevision: 1,
      wardrobeItemRevision: 1,
      analysisId: "other",
      analysisKind: "initial_analysis",
      completedAt: "2000-01-01T00:00:00.000Z",
      modelIdentifier: "gpt-4o-mini",
      pipelineVersion: "vision-v2-phase-4.9",
      promptVersion: "vision-v2-schema-9",
      visionSchemaVersion: 9,
      qualificationVersion: "qualification-v1",
    },
    contextMode: PRODUCTION_CONTEXT_MODE,
    scenarioId: undefined,
  })), "analysis_id_mismatch");
});

test("mismatched model version fails", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    contextMode: PRODUCTION_CONTEXT_MODE,
    scenarioId: undefined,
    trustedMappingContext: {
      generationId: "gen-1",
      revision: 1,
      createdAt: "2000-01-01T00:00:00.000Z",
      updatedAt: "2000-01-01T00:00:00.000Z",
      imageRevision: 1,
      wardrobeItemRevision: 1,
      analysisId: "analysis-1",
      analysisKind: "initial_analysis",
      completedAt: "2000-01-01T00:00:00.000Z",
      modelIdentifier: "other-model",
      pipelineVersion: "vision-v2-phase-4.9",
      promptVersion: "vision-v2-schema-9",
      visionSchemaVersion: 9,
      qualificationVersion: "qualification-v1",
    },
  })), "model_identifier_mismatch");
});

test("mismatched vision schema fails", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    contextMode: PRODUCTION_CONTEXT_MODE,
    scenarioId: undefined,
    trustedMappingContext: {
      generationId: "gen-1",
      revision: 1,
      createdAt: "2000-01-01T00:00:00.000Z",
      updatedAt: "2000-01-01T00:00:00.000Z",
      imageRevision: 1,
      wardrobeItemRevision: 1,
      analysisId: "analysis-1",
      analysisKind: "initial_analysis",
      completedAt: "2000-01-01T00:00:00.000Z",
      modelIdentifier: "gpt-4o-mini",
      pipelineVersion: "vision-v2-phase-4.9",
      promptVersion: "vision-v2-schema-9",
      visionSchemaVersion: 8,
      qualificationVersion: "qualification-v1",
    },
  })), "vision_schema_version_mismatch");
});

test("mismatched qualification version fails", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    contextMode: PRODUCTION_CONTEXT_MODE,
    scenarioId: undefined,
    trustedMappingContext: {
      generationId: "gen-1",
      revision: 1,
      createdAt: "2000-01-01T00:00:00.000Z",
      updatedAt: "2000-01-01T00:00:00.000Z",
      imageRevision: 1,
      wardrobeItemRevision: 1,
      analysisId: "analysis-1",
      analysisKind: "initial_analysis",
      completedAt: "2000-01-01T00:00:00.000Z",
      modelIdentifier: "gpt-4o-mini",
      pipelineVersion: "vision-v2-phase-4.9",
      promptVersion: "vision-v2-schema-9",
      visionSchemaVersion: 9,
      qualificationVersion: "qualification-v0",
    },
  })), "qualification_version_mismatch");
});

test("unsupported persistence schema fails", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    persistenceSchemaVersion: 99,
  })), "unsupported_persistence_schema");
});

test("invalid image revision fails in production context", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    contextMode: PRODUCTION_CONTEXT_MODE,
    scenarioId: undefined,
    trustedMappingContext: {
      generationId: "gen-1",
      revision: 1,
      createdAt: "2000-01-01T00:00:00.000Z",
      updatedAt: "2000-01-01T00:00:00.000Z",
      imageRevision: -1,
      wardrobeItemRevision: 1,
      analysisId: "analysis-1",
      analysisKind: "initial_analysis",
      completedAt: "2000-01-01T00:00:00.000Z",
      modelIdentifier: "gpt-4o-mini",
      pipelineVersion: "vision-v2-phase-4.9",
      promptVersion: "vision-v2-schema-9",
      visionSchemaVersion: 9,
      qualificationVersion: "qualification-v1",
    },
  })), "trustedMappingContext.imageRevision_invalid");
});

test("invalid wardrobe item revision fails", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    contextMode: PRODUCTION_CONTEXT_MODE,
    scenarioId: undefined,
    trustedMappingContext: {
      generationId: "gen-1",
      revision: 1,
      createdAt: "2000-01-01T00:00:00.000Z",
      updatedAt: "2000-01-01T00:00:00.000Z",
      imageRevision: 1,
      wardrobeItemRevision: -2,
      analysisId: "analysis-1",
      analysisKind: "initial_analysis",
      completedAt: "2000-01-01T00:00:00.000Z",
      modelIdentifier: "gpt-4o-mini",
      pipelineVersion: "vision-v2-phase-4.9",
      promptVersion: "vision-v2-schema-9",
      visionSchemaVersion: 9,
      qualificationVersion: "qualification-v1",
    },
  })), "trustedMappingContext.wardrobeItemRevision_invalid");
});

test("empty generationId fails", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    contextMode: PRODUCTION_CONTEXT_MODE,
    scenarioId: undefined,
    trustedMappingContext: {
      generationId: "  ",
      revision: 1,
      createdAt: "2000-01-01T00:00:00.000Z",
      updatedAt: "2000-01-01T00:00:00.000Z",
      imageRevision: 1,
      wardrobeItemRevision: 1,
      analysisId: "analysis-1",
      analysisKind: "initial_analysis",
      completedAt: "2000-01-01T00:00:00.000Z",
      modelIdentifier: "gpt-4o-mini",
      pipelineVersion: "vision-v2-phase-4.9",
      promptVersion: "vision-v2-schema-9",
      visionSchemaVersion: 9,
      qualificationVersion: "qualification-v1",
    },
  })), "trustedMappingContext.generationId_empty");
});

test("non-UTC timestamp fails", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    observationProvenance: {
      observedAt: "2000-01-01T00:00:00+02:00",
      modelVersion: "gpt-4o-mini",
      sourceReference: "fixture://test/view_1",
    },
  })), "observedAt_non_utc_timestamp");
});

test("absolute path rejected in production context", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    contextMode: PRODUCTION_CONTEXT_MODE,
    scenarioId: undefined,
    trustedMappingContext: {
      generationId: "gen-1",
      revision: 1,
      createdAt: "2000-01-01T00:00:00.000Z",
      updatedAt: "2000-01-01T00:00:00.000Z",
      imageRevision: 1,
      wardrobeItemRevision: 1,
      storagePath: "C:\\\\Users\\\\secret\\\\image.jpg",
      analysisId: "analysis-1",
      analysisKind: "initial_analysis",
      completedAt: "2000-01-01T00:00:00.000Z",
      modelIdentifier: "gpt-4o-mini",
      pipelineVersion: "vision-v2-phase-4.9",
      promptVersion: "vision-v2-schema-9",
      visionSchemaVersion: 9,
      qualificationVersion: "qualification-v1",
    },
  })), "absolute_path_rejected");
});

test("signed URL rejected", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    contextMode: PRODUCTION_CONTEXT_MODE,
    scenarioId: undefined,
    trustedMappingContext: {
      generationId: "gen-1",
      revision: 1,
      createdAt: "2000-01-01T00:00:00.000Z",
      updatedAt: "2000-01-01T00:00:00.000Z",
      imageRevision: 1,
      wardrobeItemRevision: 1,
      storagePath: "https://example.com/x?X-Goog-Signature=abc",
      analysisId: "analysis-1",
      analysisKind: "initial_analysis",
      completedAt: "2000-01-01T00:00:00.000Z",
      modelIdentifier: "gpt-4o-mini",
      pipelineVersion: "vision-v2-phase-4.9",
      promptVersion: "vision-v2-schema-9",
      visionSchemaVersion: 9,
      qualificationVersion: "qualification-v1",
    },
  })), "secret_or_signed_url_rejected");
});

test("empty observation evidence is allowed", () => {
  const prepared = prepareQualifiedVisionPersistenceMapperInput(baseInput({
    observationEvidence: [],
  }));
  assert.equal(prepared.analysisProjection.observationEvidence.length, 0);
});

test("family-only identity result preserved", () => {
  const prepared = prepareQualifiedVisionPersistenceMapperInput(baseInput({
    identityQualification: {
      candidates: [],
      selectedCanonicalType: null,
      state: "insufficient_evidence",
      topMargin: null,
    },
    qualifiedIdentityEvidence: [],
    familyIdentity: {
      candidates: [{family: "top", confidence: 0.8}],
      confidence: 0.8,
      reasonCodes: [],
      resolvedFamily: "top",
      state: "confirmed",
      subtypeCandidates: [],
      subtypeResolved: false,
    },
  }));
  assert.equal(prepared.analysisProjection.familyIdentity.resolvedFamily, "top");
  assert.equal(
    prepared.analysisProjection.identityQualification.selectedCanonicalType,
    null);
});

test("invalid input assessment projected with valid=false", () => {
  const prepared = prepareQualifiedVisionPersistenceMapperInput(baseInput({
    inputAssessment: "insufficient_visual_information",
  }));
  assert.equal(prepared.analysisProjection.inputAssessmentValid, false);
});

test("physical multi-view conflict preserved", () => {
  const prepared = prepareQualifiedVisionPersistenceMapperInput(baseInput({
    multiPhotoAssessment: baseMultiPhoto({
      physicalIdentity: "conflictingSubjects",
      semanticAgreement: "compatible",
      sameItemViews: false,
      permitsIdentityPromotion: false,
      reasonCodes: ["binding_different_physical_items"],
    }),
  }));
  assert.equal(
    prepared.analysisProjection.multiPhotoAssessment.permitsIdentityPromotion,
    false);
});

test("capability evidence with and without support is preserved unfiltered", () => {
  const prepared = prepareQualifiedVisionPersistenceMapperInput(baseInput({
    capabilityEvidence: [
      baseCapability(),
      baseCapability({
        id: "capability:test:capabilities.traction",
        property: "capabilities.traction",
        value: null,
        valueState: "not_applicable",
        method: "capability_inference:traction.explicit_non_footwear",
      }),
    ],
  }));
  assert.equal(prepared.analysisProjection.capabilityEvidence.length, 2);
});

test("duplicate evidence id fails", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    observationEvidence: [
      baseObservation(),
      baseObservation({property: "visual.observations.hasHood", value: true}),
    ],
  })), "duplicate_evidence_id:observation:test:visual.coverage");
});

test("resolvedProfile and machineEvidence authority fields rejected", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    resolvedProfile: {itemId: "x"},
  })), "forbidden_authority_field:resolvedProfile");
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    machineEvidence: [{id: "x"}],
  })), "forbidden_authority_field:machineEvidence");
});

test("repository and CAS fields rejected", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    casExpectedRevision: 3,
  })), "forbidden_authority_field:casExpectedRevision");
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    repositorySnapshot: {},
  })), "forbidden_authority_field:repositorySnapshot");
});

test("knowledge base evidence rejected", () => {
  throwsCode(() => prepareQualifiedVisionPersistenceMapperInput(baseInput({
    capabilityEvidence: [baseCapability({
      id: "kb-prior:boots:capabilities.warmth",
      source: "knowledge_base_prior",
    })],
  })), "knowledge_base_evidence_forbidden_in_mapper_input");
});

test("output is immutable and deterministic", () => {
  const first = prepareQualifiedVisionPersistenceMapperInput(baseInput());
  const second = prepareQualifiedVisionPersistenceMapperInput(baseInput());
  assert.deepEqual(first, second);
  assert.throws(() => {
    first.analysisProjection.analysisId = "mutated";
  }, TypeError);
  assert.equal(
    crypto.createHash("sha256").update(canonicalBytes(first)).digest("hex"),
    crypto.createHash("sha256").update(canonicalBytes(second)).digest("hex"),
  );
});

test("8/8 mapper input oracle parity", () => {
  const report = runQualifiedVisionPersistenceMapperInputParity();
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.deterministic, true);
  assert.equal(report.parityStatus, "orchestration_ready");
  assert.equal(
    report.offlinePortReadinessVerdict,
    "mapper_input_builder_ready_for_offline_node_port");
  assert.equal(
    report.productionRevisionVerdict,
    "trusted_revision_contract_required_for_production");
  for (const scenario of report.scenarios) {
    assert.equal(scenario.passed, true, scenario.scenarioId);
    assert.equal(scenario.fieldParity.analysisProjection, true);
    assert.equal(scenario.fieldParity.observationEvidence, true);
    assert.equal(scenario.fieldParity.identity, true);
    assert.equal(scenario.fieldParity.family, true);
    assert.equal(scenario.fieldParity.capability, true);
    assert.equal(scenario.fieldParity.multiPhoto, true);
    assert.equal(scenario.fieldParity.mappingContext, true);
  }
});

test("orchestration manifest is byte-identical on rewrite", () => {
  const report = runQualifiedVisionPersistenceMapperInputParity();
  const first = updateMapperInputOrchestrationManifest(report, {
    manifestPath: manifestOut,
  });
  const second = updateMapperInputOrchestrationManifest(report, {
    manifestPath: manifestOut,
  });
  assert.deepEqual(first, second);
  assert.equal(
    fs.readFileSync(manifestOut, "utf8"),
    `${JSON.stringify(
      buildQualifiedVisionPersistenceMapperInputParityEntry(report),
      null,
      2,
    )}\n`,
  );
  assert.equal(STAGE_ID, "PrepareQualifiedVisionPersistenceMapperInput");
  assert.equal(STAGE_VERSION, "qualified-vision-persistence-mapper-input-v1");
  assert.ok(FORBIDDEN_AUTHORITY_FIELDS.includes("resolvedProfile"));
});

test("prepare stage remains production isolated", () => {
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.equal(production.includes("PrepareQualifiedVisionPersistenceMapperInput"),
    false);
  assert.equal(production.includes(
    "prepare_qualified_vision_persistence_mapper_input"), false);
  assert.equal(production.includes("mapQualifiedVisionPersistence"), false);
  assert.equal(fs.existsSync(path.join(__dirname,
    "qualified_vision_persistence_mapper.js")), true);
  assert.equal(fs.existsSync(path.join(__dirname,
    "backend_qualified_vision_persistence_mapper_parity.js")), true);
  const source = fs.readFileSync(path.join(__dirname,
    "prepare_qualified_vision_persistence_mapper_input.js"), "utf8");
  assert.equal(/require\(["']firebase/.test(source), false);
  assert.equal(/from ["']firebase/.test(source), false);
  assert.equal(/admin\.firestore|getFirestore|FieldValue/.test(source), false);
  assert.equal(/Date\.now\(|randomUUID\(|Math\.random\(/.test(source), false);
});
