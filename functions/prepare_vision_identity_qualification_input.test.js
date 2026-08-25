"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  buildIdentityQualificationInputParityEntry,
  loadAllowedCanonicalTypes,
  runIdentityQualificationInputParity,
} = require("./backend_identity_qualification_input_parity");
const {
  FORBIDDEN_AUTHORITY_FIELDS,
  STAGE_ID,
  STAGE_VERSION,
  assessMultiPhotoConsistency,
  materializeVisionIdentityEvidence,
  prepareVisionIdentityQualificationInput,
} = require("./prepare_vision_identity_qualification_input");
const {canonicalBytes} = require("./backend_provider_oracle_parity");

const root = path.resolve(__dirname, "..");
const taxonomyPath = path.join(root, "lib/data/clothing_knowledge_base.dart");
const allowed = loadAllowedCanonicalTypes(taxonomyPath);

function baseResponse(overrides = {}) {
  return {
    analysisId: "fixture:test:view_1",
    observedAt: "2000-01-01T00:00:00.000Z",
    modelVersion: "gpt-4o-mini",
    sourceReference: "fixture://test/view_1",
    schemaVersion: 9,
    inputAssessment: "valid_single_item",
    identityCandidates: [{
      canonicalType: "t_shirt",
      confidence: 0.8,
      definingObservations: ["coverage", "visibleBulk"],
      supportingObservations: ["formalCues"],
    }],
    subjectAssessment: {
      subjectCountEstimate: 1,
      cardinalityState: "single_item_supported",
      primarySubjectPresent: true,
      sameItemConsistency: "same_item_supported",
      subjectDomain: "garment_upper",
      framingClass: "full_item",
      reasonCodes: [],
      framingAttestations: {
        cropIndicators: [],
        localDetailOnly: false,
        primarySilhouetteContinuous: true,
        subjectOrientation: "front",
        visibleBoundaries: ["top", "bottom", "left", "right"],
        visibleItemExtent: "whole",
      },
    },
    quality: {
      clarity: "high",
      occlusion: "none",
      backgroundInterference: "low",
      itemFullyVisible: true,
    },
    ...overrides,
  };
}

function prepareArgs(overrides = {}) {
  return {
    responses: [baseResponse()],
    multiViewSubjectBinding: null,
    observationEvidence: [],
    allowedCanonicalTypes: allowed,
    ...overrides,
  };
}

test("prepare stage constants", () => {
  assert.equal(STAGE_ID, "PrepareVisionIdentityQualificationInput");
  assert.equal(STAGE_VERSION, "identity-qualification-input-v1");
});

test("empty candidates materialize empty evidence", () => {
  const result = materializeVisionIdentityEvidence({
    responses: [baseResponse({identityCandidates: []})],
    allowedCanonicalTypes: allowed,
  });
  assert.deepEqual(result.identityEvidence, []);
  assert.deepEqual(result.declaredByEvidenceId, {});
});

test("one valid candidate materializes deterministic evidence", () => {
  const result = materializeVisionIdentityEvidence({
    responses: [baseResponse()],
    allowedCanonicalTypes: allowed,
  });
  assert.equal(result.identityEvidence.length, 1);
  assert.equal(result.identityEvidence[0].id,
    "vision-identity:fixture:test:view_1:t_shirt");
  assert.equal(result.identityEvidence[0].method,
    "vision_v2_identity_candidate");
  assert.equal(result.identityEvidence[0].property, "identity.canonicalType");
  assert.equal(result.identityEvidence[0].source, "ai_inference");
  assert.equal(result.identityEvidence[0].nature, "inferred");
  assert.equal(result.identityEvidence[0].active, true);
  assert.equal(result.identityEvidence[0].verified, false);
  assert.deepEqual(
    result.declaredByEvidenceId[result.identityEvidence[0].id].defining,
    ["coverage", "visibleBulk"]);
});

test("multiple candidates are ordered by evidence id", () => {
  const response = baseResponse({
    identityCandidates: [
      {
        canonicalType: "hoodie",
        confidence: 0.5,
        definingObservations: ["hasHood"],
        supportingObservations: [],
      },
      {
        canonicalType: "t_shirt",
        confidence: 0.9,
        definingObservations: ["coverage"],
        supportingObservations: [],
      },
    ],
  });
  const result = materializeVisionIdentityEvidence({
    responses: [response],
    allowedCanonicalTypes: allowed,
  });
  assert.deepEqual(result.identityEvidence.map((item) => item.value),
    ["hoodie", "t_shirt"]);
});

test("duplicate canonical candidate keeps stable string keys", () => {
  const response = baseResponse({
    identityCandidates: [
      {
        canonicalType: "t_shirt",
        confidence: 0.4,
        definingObservations: ["b", "a"],
        supportingObservations: ["z"],
      },
      {
        canonicalType: "t_shirt",
        confidence: 0.9,
        definingObservations: ["coverage"],
        supportingObservations: [],
      },
    ],
  });
  const result = materializeVisionIdentityEvidence({
    responses: [response],
    allowedCanonicalTypes: allowed,
  });
  assert.equal(result.identityEvidence.length, 2);
  assert.equal(result.identityEvidence[0].id, result.identityEvidence[1].id);
  assert.deepEqual(
    result.declaredByEvidenceId[result.identityEvidence[0].id].defining,
    ["coverage"]);
});

test("unknown canonical key fails closed", () => {
  assert.throws(() => materializeVisionIdentityEvidence({
    responses: [baseResponse({
      identityCandidates: [{
        canonicalType: "not_a_real_type",
        confidence: 0.5,
        definingObservations: [],
        supportingObservations: [],
      }],
    })],
    allowedCanonicalTypes: allowed,
  }), /unknown_canonical_key/);
});

test("confidence 0 and 1 are preserved", () => {
  for (const confidence of [0, 1]) {
    const result = materializeVisionIdentityEvidence({
      responses: [baseResponse({
        identityCandidates: [{
          canonicalType: "t_shirt",
          confidence,
          definingObservations: [],
          supportingObservations: [],
        }],
      })],
      allowedCanonicalTypes: allowed,
    });
    assert.equal(result.identityEvidence[0].confidence, confidence);
  }
});

test("missing defining/supporting observations default to empty sorted lists",
  () => {
    const result = materializeVisionIdentityEvidence({
      responses: [baseResponse({
        identityCandidates: [{
          canonicalType: "t_shirt",
          confidence: 0.5,
        }],
      })],
      allowedCanonicalTypes: allowed,
    });
    const declared = result.declaredByEvidenceId[result.identityEvidence[0].id];
    assert.deepEqual(declared.defining, []);
    assert.deepEqual(declared.supporting, []);
  });

test("evidence IDs do not URI-encode analysisId components", () => {
  const result = materializeVisionIdentityEvidence({
    responses: [baseResponse({
      analysisId: "fixture:current_pipeline_capture_v1:x:view_1",
    })],
    allowedCanonicalTypes: allowed,
  });
  assert.equal(result.identityEvidence[0].id,
    "vision-identity:fixture:current_pipeline_capture_v1:x:view_1:t_shirt");
  assert.equal(result.identityEvidence[0].id.includes("%"), false);
});

test("declaredByEvidenceId sorts defining and supporting names", () => {
  const result = materializeVisionIdentityEvidence({
    responses: [baseResponse({
      identityCandidates: [{
        canonicalType: "t_shirt",
        confidence: 0.5,
        definingObservations: ["visibleBulk", "coverage", "coverage"],
        supportingObservations: ["sportyCues", "formalCues"],
      }],
    })],
    allowedCanonicalTypes: allowed,
  });
  const declared = result.declaredByEvidenceId[result.identityEvidence[0].id];
  assert.deepEqual(declared.defining, ["coverage", "visibleBulk"]);
  assert.deepEqual(declared.supporting, ["formalCues", "sportyCues"]);
});

test("parser invalid sets inputIsValid false", () => {
  const prepared = prepareVisionIdentityQualificationInput(prepareArgs({
    responses: [baseResponse({inputAssessment: "ambiguous_subject"})],
  }));
  assert.equal(prepared.inputIsValid, false);
});

test("permitsCanonical false blocks validity", () => {
  const prepared = prepareVisionIdentityQualificationInput(prepareArgs({
    responses: [baseResponse({
      subjectAssessment: {
        ...baseResponse().subjectAssessment,
        subjectDomain: "mixed",
      },
    })],
  }));
  assert.equal(prepared.inputIsValid, false);
});

test("no whole-item silhouette blocks validity", () => {
  const prepared = prepareVisionIdentityQualificationInput(prepareArgs({
    responses: [baseResponse({
      subjectAssessment: {
        ...baseResponse().subjectAssessment,
        framingAttestations: {
          ...baseResponse().subjectAssessment.framingAttestations,
          localDetailOnly: true,
          visibleItemExtent: "local",
        },
      },
    })],
  }));
  assert.equal(prepared.inputIsValid, false);
});

test("physical identity conflict blocks promotion", () => {
  const assessment = assessMultiPhotoConsistency([
    {
      cardinalityState: "single_item_supported",
      sameItemConsistency: "same_item_supported",
      subjectDomain: "garment_upper",
      framingClass: "full_item",
      primarySubjectPresent: true,
      subjectCountEstimate: 1,
      reasonCodes: [],
    },
    {
      cardinalityState: "single_item_supported",
      sameItemConsistency: "same_item_supported",
      subjectDomain: "garment_upper",
      framingClass: "full_item",
      primarySubjectPresent: true,
      subjectCountEstimate: 1,
      reasonCodes: [],
    },
  ], {physicalIdentityClaim: "different_physical_items"});
  assert.equal(assessment.permitsIdentityPromotion, false);
  assert.equal(assessment.physicalIdentity, "conflictingSubjects");
});

test("semantic conflict blocks promotion even with same physical item", () => {
  const assessment = assessMultiPhotoConsistency([
    {
      cardinalityState: "single_item_supported",
      sameItemConsistency: "same_item_supported",
      subjectDomain: "garment_upper",
      framingClass: "full_item",
      primarySubjectPresent: true,
      subjectCountEstimate: 1,
      reasonCodes: [],
    },
    {
      cardinalityState: "single_item_supported",
      sameItemConsistency: "same_item_supported",
      subjectDomain: "footwear",
      framingClass: "full_item",
      primarySubjectPresent: true,
      subjectCountEstimate: 1,
      reasonCodes: [],
    },
  ], {physicalIdentityClaim: "same_physical_item"});
  assert.equal(assessment.semanticAgreement, "conflicting");
  assert.equal(assessment.permitsIdentityPromotion, false);
});

test("undeclared multi-view binding fails closed", () => {
  const assessment = assessMultiPhotoConsistency([
    {
      cardinalityState: "single_item_supported",
      sameItemConsistency: "same_item_supported",
      subjectDomain: "garment_upper",
      framingClass: "full_item",
      primarySubjectPresent: true,
      subjectCountEstimate: 1,
      reasonCodes: [],
    },
    {
      cardinalityState: "single_item_supported",
      sameItemConsistency: "same_item_supported",
      subjectDomain: "garment_upper",
      framingClass: "full_item",
      primarySubjectPresent: true,
      subjectCountEstimate: 1,
      reasonCodes: [],
    },
  ], {physicalIdentityClaim: "undeclared"});
  assert.equal(assessment.physicalIdentity, "sameItemUncertain");
  assert.equal(assessment.permitsIdentityPromotion, false);
});

test("explicit samePhysicalItem enables promotion when semantic consistent",
  () => {
    const assessment = assessMultiPhotoConsistency([
      {
        cardinalityState: "single_item_supported",
        sameItemConsistency: "same_item_supported",
        subjectDomain: "garment_upper",
        framingClass: "full_item",
        primarySubjectPresent: true,
        subjectCountEstimate: 1,
        reasonCodes: [],
      },
      {
        cardinalityState: "single_item_supported",
        sameItemConsistency: "same_item_supported",
        subjectDomain: "garment_upper",
        framingClass: "full_item",
        primarySubjectPresent: true,
        subjectCountEstimate: 1,
        reasonCodes: [],
      },
    ], {physicalIdentityClaim: "same_physical_item"});
    assert.equal(assessment.permitsIdentityPromotion, true);
  });

test("explicit differentPhysicalItems blocks promotion", () => {
  const assessment = assessMultiPhotoConsistency([
    {
      cardinalityState: "single_item_supported",
      sameItemConsistency: "same_item_supported",
      subjectDomain: "garment_upper",
      framingClass: "full_item",
      primarySubjectPresent: true,
      subjectCountEstimate: 1,
      reasonCodes: [],
    },
    {
      cardinalityState: "single_item_supported",
      sameItemConsistency: "same_item_supported",
      subjectDomain: "garment_upper",
      framingClass: "full_item",
      primarySubjectPresent: true,
      subjectCountEstimate: 1,
      reasonCodes: [],
    },
  ], {physicalIdentityClaim: "different_physical_items"});
  assert.equal(assessment.permitsIdentityPromotion, false);
});

test("taxonomy SHA mismatch fails closed", () => {
  assert.throws(() => prepareVisionIdentityQualificationInput(prepareArgs({
    taxonomyRegistrySha256:
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    expectedTaxonomyRegistrySha256:
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  })), /taxonomy_sha_mismatch/);
});

test("forged client authority fields are rejected", () => {
  for (const field of FORBIDDEN_AUTHORITY_FIELDS) {
    assert.throws(() => prepareVisionIdentityQualificationInput({
      ...prepareArgs(),
      [field]: field === "inputIsValid" ? true : [],
    }), new RegExp(`forged_client_authority_field:${field}`));
  }
});

test("DTO serialization is deterministic", () => {
  const first = prepareVisionIdentityQualificationInput(prepareArgs());
  const second = prepareVisionIdentityQualificationInput(prepareArgs());
  assert.equal(sha256(canonicalBytes(first)), sha256(canonicalBytes(second)));
});

test("8/8 identity oracle providerInput parity", () => {
  const report = runIdentityQualificationInputParity();
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.deterministic, true);
  assert.equal(report.parityStatus, "orchestration_ready");
  for (const scenario of report.scenarios) {
    assert.equal(scenario.passed, true, scenario.scenarioId);
    assert.equal(scenario.fieldParity.identityEvidence, true);
    assert.equal(scenario.fieldParity.declaredByEvidenceId, true);
    assert.equal(scenario.fieldParity.consistency, true);
    assert.equal(scenario.fieldParity.inputIsValid, true);
  }
});

test("parity entry metadata is orchestration-scoped", () => {
  const report = runIdentityQualificationInputParity();
  const entry = buildIdentityQualificationInputParityEntry(report);
  assert.equal(entry.kind, "orchestration_stage");
  assert.equal(entry.passedScenarios, 8);
  assert.equal(Object.keys(entry.outputSha256ByScenario).length, 8);
});

test("prepare stage is absent from production entry points", () => {
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production,
    /prepare_vision_identity_qualification_input|PrepareVisionIdentityQualificationInput/);
  assert.doesNotMatch(
    fs.readFileSync(path.join(__dirname,
      "prepare_vision_identity_qualification_input.js"), "utf8"),
    /firebase|firestore|persistence|QualifiedVisionPersistenceMapper/);
});

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
