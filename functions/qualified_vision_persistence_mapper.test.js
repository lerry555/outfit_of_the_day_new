"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildQualifiedVisionPersistenceMapperParityEntry,
  runQualifiedVisionPersistenceMapperParity,
  updateProviderParityManifest,
} = require("./backend_qualified_vision_persistence_mapper_parity");
const {
  CAPABILITY_SUPPORT_PROPERTIES,
  FIXTURE_CONTEXT_MODE,
  MACHINE_EVIDENCE_PROPERTIES,
  PERSISTENCE_EVIDENCE_VERSION,
  PERSISTENCE_SCHEMA_VERSION,
  PRODUCTION_CONTEXT_MODE,
  PROPERTY,
  PROVIDER_ID,
  PROVIDER_VERSION,
  RESOLVER_COMPATIBILITY_VERSION,
  makeId,
  mapQualifiedVisionPersistence,
} = require("./qualified_vision_persistence_mapper");

const root = path.resolve(__dirname, "..");
const ORACLE_DIR = path.join(
  root,
  "test/fixtures/backend_qualification/provider_oracles/" +
    "qualified_vision_persistence_mapper_v1",
);

function loadOracle(scenarioId) {
  return JSON.parse(fs.readFileSync(
    path.join(ORACLE_DIR, `${scenarioId}.oracle.json`), "utf8"));
}

function cloneInput(scenarioId, mutate) {
  const oracle = loadOracle(scenarioId);
  const input = {
    ...structuredClone(oracle.invocations[0].mapperInput),
    contextMode: FIXTURE_CONTEXT_MODE,
  };
  if (mutate) mutate(input);
  return input;
}

function map(scenarioId, mutate) {
  return mapQualifiedVisionPersistence(cloneInput(scenarioId, mutate));
}

function property(result, pathName) {
  return (result.envelope?.machineEvidence || [])
    .filter((item) => item.property === pathName);
}

function observation(overrides = {}) {
  return {
    id: "obs-test",
    property: PROPERTY.coverage,
    value: "full",
    valueState: "known",
    source: "visual_observation",
    nature: "observed",
    confidence: 0.9,
    method: "vision_observation",
    createdAt: "2000-01-01T00:00:00.000Z",
    modelVersion: "gpt-4o-mini",
    sourceReference: "fixture://test",
    active: true,
    verified: false,
    ...overrides,
  };
}

function capability(overrides = {}) {
  return {
    id: "cap-test",
    property: PROPERTY.warmth,
    value: 6,
    valueState: "known",
    source: "ai_inference",
    nature: "inferred",
    confidence: 0.8,
    method: "capability_inference:warmth.bulk_and_insulating_surface",
    createdAt: "2000-01-01T00:00:00.000Z",
    modelVersion: "capability-inference-v1",
    sourceReference: "fixture://test",
    active: true,
    verified: false,
    ...overrides,
  };
}

function throwsCode(fn, code) {
  assert.throws(fn, (error) => {
    assert.equal(error.message, code);
    return true;
  });
}

test("mapper constants", () => {
  assert.equal(PROVIDER_ID, "QualifiedVisionPersistenceMapper");
  assert.equal(PROVIDER_VERSION, "qualified-vision-persistence-mapper-v1");
  assert.equal(PERSISTENCE_SCHEMA_VERSION, 1);
  assert.equal(PERSISTENCE_EVIDENCE_VERSION, 1);
  assert.equal(RESOLVER_COMPATIBILITY_VERSION, 1);
  assert.ok(MACHINE_EVIDENCE_PROPERTIES.has(PROPERTY.family));
  assert.ok(Object.keys(CAPABILITY_SUPPORT_PROPERTIES).length > 0);
});

test("mapped family-only", () => {
  const result = map("front_only_garment");
  assert.equal(result.status, "mapped");
  assert.equal(property(result, PROPERTY.family).length, 1);
  assert.equal(property(result, PROPERTY.canonicalType).length, 0);
});

test("mapped canonical-only via mutation removing family", () => {
  const result = map("shoe_without_outsole", (input) => {
    input.analysisProjection.familyIdentity = {
      ...input.analysisProjection.familyIdentity,
      state: "ambiguous",
      resolvedFamily: null,
    };
  });
  assert.equal(result.status, "mapped");
  assert.equal(property(result, PROPERTY.family).length, 0);
  assert.equal(property(result, PROPERTY.canonicalType).length, 1);
});

test("mapped family + canonical", () => {
  const result = map("shoe_without_outsole");
  assert.equal(result.status, "mapped");
  assert.equal(property(result, PROPERTY.family).length, 1);
  assert.equal(property(result, PROPERTY.canonicalType).length, 1);
});

test("no persistable evidence", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.observationEvidence = [];
    input.analysisProjection.capabilityEvidence = [];
    input.analysisProjection.familyIdentity = {
      ...input.analysisProjection.familyIdentity,
      state: "insufficient_evidence",
      resolvedFamily: null,
    };
    input.analysisProjection.identityQualification = {
      ...input.analysisProjection.identityQualification,
      state: "insufficient_evidence",
      selectedCanonicalType: null,
    };
    input.analysisProjection.qualifiedIdentityEvidence = [];
  });
  assert.equal(result.status, "noPersistableEvidence");
  assert.equal(result.reasonCode, "no_qualified_evidence");
  assert.equal(result.envelope, undefined);
});

test("invalid input", () => {
  const result = map("fabric_detail_only");
  assert.equal(result.status, "invalidInput");
  assert.equal(result.reasonCode, "vision_input_not_valid");
  assert.equal(result.envelope, undefined);
});

test("incompatible input analysis/context mismatch", () => {
  const result = map("front_only_garment", (input) => {
    input.mappingContext.analysisId = "other-analysis";
  });
  assert.equal(result.status, "incompatibleInput");
  assert.equal(result.reasonCode, "analysis_id_mismatch");
});

test("mapping failure on conflicting duplicate observation", () => {
  const result = map("front_only_garment", (input) => {
    const first = input.analysisProjection.observationEvidence[0];
    input.analysisProjection.observationEvidence.push({
      ...first,
      id: `${first.id}:conflict`,
      value: first.value === "full" ? "partial" : "full",
      valueState: "known",
    });
  });
  assert.equal(result.status, "mappingFailure");
  assert.match(result.reasonCode, /^conflicting_observation:/);
});

test("unsupported family status is not persisted", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.familyIdentity = {
      ...input.analysisProjection.familyIdentity,
      state: "ambiguous",
      resolvedFamily: null,
    };
  });
  assert.equal(property(result, PROPERTY.family).length, 0);
});

test("unknown family key fails codec validation", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.familyIdentity = {
      ...input.analysisProjection.familyIdentity,
      state: "confirmed",
      resolvedFamily: "not_a_real_family",
      candidates: [{
        family: "not_a_real_family",
        confidence: 0.9,
        evidence: ["tier1:coverage"],
        canonicalCandidates: [],
        confidenceComponents: {},
      }],
    };
  });
  assert.equal(result.status, "mappingFailure");
  assert.match(result.reasonCode, /unknown_family_key/);
});

test("raw canonical without qualification is not persisted", () => {
  const result = map("front_only_garment");
  assert.equal(property(result, PROPERTY.canonicalType).length, 0);
  assert.equal(
    result.envelope.machineEvidence.some((item) => item.value === "tank_top"),
    false,
  );
});

test("canonical taxonomy conflict drops both identity assertions", () => {
  const result = map("shoe_without_outsole", (input) => {
    input.analysisProjection.familyIdentity = {
      ...input.analysisProjection.familyIdentity,
      state: "confirmed",
      resolvedFamily: "top",
      candidates: [{
        ...input.analysisProjection.familyIdentity.candidates[0],
        family: "top",
        evidence: ["tier1:coverage"],
      }],
    };
  });
  assert.equal(result.status, "mapped");
  assert.equal(property(result, PROPERTY.family).length, 0);
  assert.equal(property(result, PROPERTY.canonicalType).length, 0);
  assert.ok(result.omittedEvidenceReasonCodes.includes(
    "identity_omitted:cross_family_conflict"));
});

test("physical multi-view conflict omits identity", () => {
  const result = map("conflicting_multi_view");
  assert.equal(result.status, "mapped");
  assert.equal(property(result, PROPERTY.family).length, 0);
  assert.equal(property(result, PROPERTY.canonicalType).length, 0);
  assert.ok(result.omittedEvidenceReasonCodes.includes(
    "identity_omitted:multi_photo_physical_conflict"));
});

test("semantic conflict omit reason", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.multiPhotoAssessment = {
      ...input.analysisProjection.multiPhotoAssessment,
      permitsIdentityPromotion: false,
      physicalIdentity: "sameItemSupported",
      semanticAgreement: "conflict",
    };
  });
  assert.equal(property(result, PROPERTY.family).length, 0);
  assert.ok(result.omittedEvidenceReasonCodes.includes(
    "identity_omitted:multi_photo_semantic_conflict"));
});

test("missing whole-item silhouette blocks identity via family supports", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.observationEvidence =
      input.analysisProjection.observationEvidence.filter((item) =>
        item.property !== PROPERTY.coverage &&
        item.property !== PROPERTY.visibleBulk &&
        item.property !== PROPERTY.necklineShape);
  });
  assert.equal(property(result, PROPERTY.family).length, 0);
});

test("positive known observation", () => {
  const result = map("front_only_garment");
  const item = property(result, PROPERTY.coverage)[0];
  assert.equal(item.valueState, "known");
  assert.equal(item.value, "partial");
});

test("unknown observation", () => {
  const result = map("front_only_garment", (input) => {
    const target = input.analysisProjection.observationEvidence
      .find((item) => item.property === PROPERTY.visiblePocketStructure);
    target.value = null;
    target.valueState = "unknown";
  });
  const item = property(result, PROPERTY.visiblePocketStructure)[0];
  assert.equal(item.valueState, "unknown");
  assert.equal(item.value, null);
});

test("not_visible observation", () => {
  const result = map("front_only_garment");
  const item = property(result, PROPERTY.hasHood)[0];
  assert.equal(item.valueState, "not_visible");
  assert.equal(item.value, null);
});

test("not_applicable observation", () => {
  const result = map("front_only_garment");
  const item = property(result, PROPERTY.footwearConstruction)[0];
  assert.equal(item.valueState, "not_applicable");
  assert.equal(item.value, null);
});

test("blocked negative none is not known fact when input is non-value", () => {
  const result = map("front_only_garment", (input) => {
    const target = input.analysisProjection.observationEvidence
      .find((item) => item.property === PROPERTY.frontClosure);
    target.value = null;
    target.valueState = "unknown";
  });
  assert.equal(
    property(result, PROPERTY.frontClosure).some((item) =>
      item.valueState === "known" && item.value === "none"),
    false,
  );
});

test("blocked negative false is not known fact when input is non-value", () => {
  const result = map("front_only_garment", (input) => {
    const target = input.analysisProjection.observationEvidence
      .find((item) => item.property === PROPERTY.hasHood);
    target.value = null;
    target.valueState = "unknown";
  });
  assert.equal(
    property(result, PROPERTY.hasHood).some((item) =>
      item.valueState === "known" && item.value === false),
    false,
  );
});

test("valid positive full_zip", () => {
  const result = map("front_only_garment", (input) => {
    const target = input.analysisProjection.observationEvidence
      .find((item) => item.property === PROPERTY.frontClosure);
    target.value = "full_zip";
    target.valueState = "known";
  });
  assert.equal(property(result, PROPERTY.frontClosure)[0].value, "full_zip");
});

test("capability valid origin persists with supports", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.capabilityEvidence = [
      capability(),
      ...input.analysisProjection.capabilityEvidence,
    ];
  });
  const warmth = property(result, PROPERTY.warmth);
  assert.equal(warmth.length, 1);
  assert.equal(warmth[0].source, "ai_inference");
  assert.equal(warmth[0].nature, "inferred");
  assert.ok(warmth[0].supportingEvidenceIds.length >= 1);
  const ids = new Set(result.envelope.machineEvidence.map((item) => item.id));
  for (const supportId of warmth[0].supportingEvidenceIds) {
    assert.ok(ids.has(supportId), supportId);
  }
});

test("capability invalid source is omitted", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.capabilityEvidence = [
      capability({source: "knowledge_base_prior", id: "cap-bad-source"}),
    ];
  });
  assert.equal(property(result, PROPERTY.warmth).length, 0);
  assert.ok(result.omittedEvidenceReasonCodes.includes(
    `capability_omitted:${PROPERTY.warmth}`));
});

test("capability invalid nature is omitted", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.capabilityEvidence = [
      capability({nature: "observed", id: "cap-bad-nature"}),
    ];
  });
  assert.equal(property(result, PROPERTY.warmth).length, 0);
});

test("capability unknown reason/method is omitted", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.capabilityEvidence = [
      capability({
        method: "capability_inference:warmth.made_up_reason",
        id: "cap-unknown-reason",
      }),
    ];
  });
  assert.equal(property(result, PROPERTY.warmth).length, 0);
});

test("capability missing required support is omitted", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.observationEvidence =
      input.analysisProjection.observationEvidence.filter((item) =>
        item.property !== PROPERTY.visibleBulk);
    input.analysisProjection.capabilityEvidence = [capability()];
  });
  assert.equal(property(result, PROPERTY.warmth).length, 0);
});

test("capability valid support bridge", () => {
  const required =
    CAPABILITY_SUPPORT_PROPERTIES[
      "capability_inference:warmth.bulk_and_insulating_surface"];
  assert.deepEqual(required, ["visibleBulk", "surfaceAppearance"]);
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.capabilityEvidence = [capability()];
  });
  const warmth = property(result, PROPERTY.warmth)[0];
  assert.equal(warmth.supportingEvidenceIds.length, 2);
  assert.deepEqual(
    [...warmth.supportingEvidenceIds],
    [...warmth.supportingEvidenceIds].sort(),
  );
});

test("dangling support cannot appear for capability bridge", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.capabilityEvidence = [capability()];
  });
  const ids = new Set(result.envelope.machineEvidence.map((item) => item.id));
  for (const item of result.envelope.machineEvidence) {
    for (const supportId of item.supportingEvidenceIds || []) {
      assert.ok(ids.has(supportId), `dangling:${supportId}`);
    }
  }
});

test("duplicate identical evidence is deduplicated", () => {
  const result = map("front_only_garment", (input) => {
    const first = input.analysisProjection.observationEvidence[0];
    input.analysisProjection.observationEvidence.push({...first});
  });
  assert.equal(result.status, "mapped");
  const pathName = result.envelope.machineEvidence
    .find((item) => item.property.startsWith("visual.")).property;
  assert.equal(property(result, pathName).length, 1);
});

test("conflicting duplicate evidence fails", () => {
  const result = map("front_only_garment", (input) => {
    const first = input.analysisProjection.observationEvidence
      .find((item) => item.property === PROPERTY.coverage);
    input.analysisProjection.observationEvidence.push({
      ...first,
      id: `${first.id}:b`,
      value: "minimal",
      valueState: "known",
    });
  });
  assert.equal(result.status, "mappingFailure");
});

test("evidence ID encoding", () => {
  const analysisId = "fixture:current_pipeline_capture_v1:front_only_garment:view_1";
  assert.equal(
    makeId("family", analysisId, "top"),
    `family:${encodeURIComponent(analysisId).replace(/[!'()*]/g, (c) =>
      `%${c.charCodeAt(0).toString(16).toUpperCase()}`)}:top`,
  );
  assert.equal(
    makeId("observation", analysisId, PROPERTY.coverage),
    `observation:${encodeURIComponent(analysisId).replace(/[!'()*]/g, (c) =>
      `%${c.charCodeAt(0).toString(16).toUpperCase()}`)}:${encodeURIComponent(PROPERTY.coverage)}`,
  );
  const result = map("front_only_garment");
  for (const item of result.envelope.machineEvidence) {
    assert.equal(item.id.includes("2000-01-01"), false);
    assert.equal(/\b[0-9a-f]{8}-[0-9a-f]{4}\b/i.test(item.id), false);
  }
});

test("evidence ordering family canonical observations capabilities", () => {
  const result = map("front_only_garment", (input) => {
    input.analysisProjection.capabilityEvidence = [capability()];
  });
  const items = result.envelope.machineEvidence;
  const familyIndex = items.findIndex((item) => item.property === PROPERTY.family);
  const observationIndex = items.findIndex((item) =>
    item.property === PROPERTY.coverage);
  const capabilityIndex = items.findIndex((item) =>
    item.property === PROPERTY.warmth);
  assert.equal(familyIndex, 0);
  assert.ok(observationIndex > familyIndex);
  assert.ok(capabilityIndex > observationIndex);
});

test("supporting ID ordering is deterministic sorted", () => {
  const result = map("shoe_without_outsole");
  for (const item of result.envelope.machineEvidence) {
    const supports = item.supportingEvidenceIds || [];
    assert.deepEqual(supports, [...supports].sort());
    assert.equal(new Set(supports).size, supports.length);
  }
});

test("unsupported persistence version constants are locked to 1", () => {
  const result = map("front_only_garment");
  assert.equal(result.envelope.metadata.schemaVersion, 1);
  assert.equal(result.envelope.metadata.evidenceSchemaVersion, 1);
  assert.equal(result.envelope.metadata.resolverCompatibilityVersion, 1);
});

test("mismatched analysis/context provenance", () => {
  const model = map("front_only_garment", (input) => {
    input.mappingContext.modelIdentifier = "other-model";
  });
  assert.equal(model.status, "incompatibleInput");
  assert.equal(model.reasonCode, "model_identifier_mismatch");
  const schema = map("front_only_garment", (input) => {
    input.mappingContext.visionSchemaVersion = 99;
  });
  assert.equal(schema.status, "incompatibleInput");
  assert.equal(schema.reasonCode, "vision_schema_version_mismatch");
});

test("production context without trusted revisions fails closed", () => {
  throwsCode(() => mapQualifiedVisionPersistence(cloneInput(
    "front_only_garment",
    (input) => {
      input.contextMode = PRODUCTION_CONTEXT_MODE;
      delete input.trustedRevisionAuthority;
    },
  )), "trusted_revision_context_unavailable");
});

test("empty user corrections", () => {
  const result = map("front_only_garment");
  assert.deepEqual(result.envelope.userCorrections, {});
});

test("deterministic serialization", () => {
  const first = map("front_only_garment");
  const second = map("front_only_garment");
  assert.equal(
    crypto.createHash("sha256").update(canonicalBytes(first)).digest("hex"),
    crypto.createHash("sha256").update(canonicalBytes(second)).digest("hex"),
  );
});

test("immutable input/output", () => {
  const input = cloneInput("front_only_garment");
  const result = mapQualifiedVisionPersistence(input);
  assert.ok(Object.isFrozen(result));
  assert.ok(Object.isFrozen(result.envelope));
  assert.ok(Object.isFrozen(result.envelope.machineEvidence));
  assert.throws(() => {
    result.status = "hacked";
  });
});

test("strict decoder rejects forbidden authority fields", () => {
  throwsCode(() => mapQualifiedVisionPersistence({
    ...cloneInput("front_only_garment"),
    resolvedProfile: {},
  }), "forbidden_authority_field:resolvedProfile");
});

test("strict decoder rejects unknown evidence source", () => {
  throwsCode(() => map("front_only_garment", (input) => {
    input.analysisProjection.observationEvidence[0].source = "forged_source";
  }), "observationEvidence.source_invalid");
});

test("8/8 oracle output parity and expected distribution", () => {
  const report = runQualifiedVisionPersistenceMapperParity();
  assert.equal(report.parityStatus, "parity_ready");
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.deterministic, true);
  assert.equal(report.distributionOk, true);
  assert.deepEqual(report.distribution, {
    mapped: 7,
    invalidInput: 1,
    noPersistableEvidence: 0,
    incompatibleInput: 0,
    mappingFailure: 0,
    totalMachineEvidence: 110,
    familyEvidence: 4,
    canonicalEvidence: 1,
    observationEvidence: 105,
    capabilityEvidence: 0,
    omittedTotal: 13,
    omittedTraction: 6,
    omittedWalkingComfort: 6,
    omittedMultiPhotoPhysical: 1,
  });
});

test("prepare-stage integration remains 8/8 before mapper", () => {
  const {
    runQualifiedVisionPersistenceMapperInputParity,
  } = require("./backend_qualified_vision_persistence_mapper_input_parity");
  const prepare = runQualifiedVisionPersistenceMapperInputParity();
  assert.equal(prepare.passedScenarios, 8);
  assert.equal(prepare.parityStatus, "orchestration_ready");
});

test("parity manifest update is byte-identical on rewrite", () => {
  const report = runQualifiedVisionPersistenceMapperParity();
  assert.equal(report.parityStatus, "parity_ready");
  const first = updateProviderParityManifest(report);
  const second = updateProviderParityManifest(report);
  assert.deepEqual(first, second);
  assert.deepEqual(
    buildQualifiedVisionPersistenceMapperParityEntry(report).parityStatus,
    "parity_ready",
  );
  const manifest = JSON.parse(fs.readFileSync(path.join(
    root,
    "test/fixtures/backend_qualification/backend_provider_parity_manifest.json",
  ), "utf8"));
  assert.equal(manifest.providers.length, 13);
  assert.ok(manifest.providers.some((item) =>
    item.providerId === PROVIDER_ID && item.parityStatus === "parity_ready"));
});

test("production isolation", () => {
  const production = [
    "functions/index.js",
    "functions/vision_v2_shadow.js",
  ].map((item) => fs.readFileSync(path.join(root, item), "utf8")).join("\n");
  assert.equal(production.includes("qualified_vision_persistence_mapper"), false);
  assert.equal(production.includes("mapQualifiedVisionPersistence"), false);
  assert.equal(production.includes("QualifiedVisionPersistenceMapper"), false);
  const source = fs.readFileSync(path.join(
    root, "functions/qualified_vision_persistence_mapper.js"), "utf8");
  assert.doesNotMatch(source,
    /require\(["']firebase|firebase-admin|Date\.now\(|Math\.random\(/);
  assert.match(source, /firestoreTimestamp/);
});
