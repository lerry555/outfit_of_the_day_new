"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  buildFamilyIdentityInputParityEntry,
  runFamilyIdentityInputParity,
} = require("./backend_family_identity_input_parity");
const {
  FORBIDDEN_AUTHORITY_FIELDS,
  STAGE_ID,
  STAGE_VERSION,
  expandFamilyCandidates,
  normalizeObservationValue,
  prepareVisionFamilyIdentityInput,
} = require("./prepare_vision_family_identity_input");
const {
  loadAllowedCanonicalTypes,
} = require("./backend_identity_qualification_input_parity");
const {canonicalBytes} = require("./backend_provider_oracle_parity");

const root = path.resolve(__dirname, "..");
const taxonomyPath = path.join(root, "lib/data/clothing_knowledge_base.dart");
const familyTaxonomyPath = path.join(root,
  "lib/domain/wardrobe_profile/vision_family_identity.dart");
const allowed = loadAllowedCanonicalTypes(taxonomyPath);
const familyTaxonomySha256 = sha256(fs.readFileSync(familyTaxonomyPath));

function baseSubject(overrides = {}) {
  return {
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
    ...overrides,
  };
}

function baseObservations(overrides = {}) {
  return {
    coverage: {
      state: "observed",
      value: "partial",
      confidence: 0.85,
      visibilityScope: "complete",
      visibleRegions: ["full_silhouette"],
    },
    hasHood: {state: "not_visible", confidence: 0.95, visibilityScope: "not_visible"},
    frontClosure: {state: "not_applicable", confidence: 0.95},
    visibleBulk: {
      state: "observed",
      value: "low",
      confidence: 0.8,
      visibilityScope: "complete",
      visibleRegions: ["full_silhouette"],
    },
    surfaceAppearance: {
      state: "observed",
      value: "smooth",
      confidence: 0.85,
      visibilityScope: "complete",
      visibleRegions: ["full_silhouette"],
    },
    necklineShape: {
      state: "observed",
      value: "scoop",
      confidence: 0.8,
      visibilityScope: "complete",
      visibleRegions: ["neckline"],
    },
    visiblePocketStructure: {
      state: "observed",
      value: "none",
      confidence: 0.95,
      visibilityScope: "complete",
      visibleRegions: ["full_silhouette"],
    },
    visibleStretchCue: {state: "unknown", confidence: 0.5},
    sportyCues: {
      state: "observed",
      value: "low",
      confidence: 0.8,
      visibilityScope: "complete",
      visibleRegions: ["full_silhouette"],
    },
    formalCues: {
      state: "observed",
      value: "low",
      confidence: 0.8,
      visibilityScope: "complete",
      visibleRegions: ["full_silhouette"],
    },
    footwearConstruction: {state: "not_applicable", confidence: 0.95},
    footwearFastening: {state: "not_applicable", confidence: 0.95},
    soleProfile: {state: "not_applicable", confidence: 0.95},
    visibleTread: {state: "not_applicable", confidence: 0.95},
    footwearUpperHeight: {state: "not_applicable", confidence: 0.95},
    ...overrides,
  };
}

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
      definingObservations: ["coverage"],
      supportingObservations: ["formalCues"],
    }],
    subjectAssessment: baseSubject(),
    quality: {
      clarity: "high",
      occlusion: "none",
      backgroundInterference: "low",
      itemFullyVisible: true,
    },
    observations: baseObservations(),
    ...overrides,
  };
}

function prepareArgs(overrides = {}) {
  return {
    responses: [baseResponse()],
    multiViewSubjectBinding: null,
    identityQualificationReport: {
      selectedCanonicalType: null,
      state: "insufficient_evidence",
    },
    allowedCanonicalTypes: allowed,
    familyTaxonomySha256,
    expectedFamilyTaxonomySha256: familyTaxonomySha256,
    ...overrides,
  };
}

test("prepare stage constants", () => {
  assert.equal(STAGE_ID, "PrepareVisionFamilyIdentityInput");
  assert.equal(STAGE_VERSION, "family-identity-input-v1");
});

test("empty candidates expand to empty list", () => {
  assert.deepEqual(expandFamilyCandidates([
    baseResponse({identityCandidates: []}),
  ]), []);
});

test("one candidate expands with confidence only", () => {
  const result = expandFamilyCandidates([baseResponse()]);
  assert.deepEqual(result, [{canonicalType: "t_shirt", confidence: 0.8}]);
});

test("multiple candidates preserve response order", () => {
  const result = expandFamilyCandidates([
    baseResponse({
      identityCandidates: [
        {canonicalType: "hoodie", confidence: 0.5},
        {canonicalType: "t_shirt", confidence: 0.9},
      ],
    }),
  ]);
  assert.deepEqual(result.map((item) => item.canonicalType),
    ["hoodie", "t_shirt"]);
});

test("unknown canonical key fails closed", () => {
  assert.throws(() => prepareVisionFamilyIdentityInput(prepareArgs({
    responses: [baseResponse({
      identityCandidates: [{canonicalType: "not_a_real_type", confidence: 0.5}],
    })],
  })), /unknown_canonical_key/);
});

test("duplicate candidate fails closed", () => {
  assert.throws(() => prepareVisionFamilyIdentityInput(prepareArgs({
    responses: [baseResponse({
      identityCandidates: [
        {canonicalType: "t_shirt", confidence: 0.5},
        {canonicalType: "t_shirt", confidence: 0.6},
      ],
    })],
  })), /duplicate_candidate/);
});

test("null resolvedCanonicalSubtype projects from identity report", () => {
  const result = prepareVisionFamilyIdentityInput(prepareArgs({
    identityQualificationReport: {
      selectedCanonicalType: null,
      state: "insufficient_evidence",
    },
  }));
  assert.equal(result.resolvedCanonicalSubtype, null);
});

test("supported selected subtype projects from identity report", () => {
  const result = prepareVisionFamilyIdentityInput(prepareArgs({
    identityQualificationReport: {
      selectedCanonicalType: "boots",
      state: "supported",
    },
  }));
  assert.equal(result.resolvedCanonicalSubtype, "boots");
});

test("insufficient identity result keeps subtype null", () => {
  const result = prepareVisionFamilyIdentityInput(prepareArgs({
    identityQualificationReport: {
      selectedCanonicalType: null,
      state: "insufficient_evidence",
    },
  }));
  assert.equal(result.resolvedCanonicalSubtype, null);
  assert.equal(result.inputAssessment, "valid_single_item");
});

test("invalid identity report still projects selected subtype field", () => {
  const result = prepareVisionFamilyIdentityInput(prepareArgs({
    identityQualificationReport: {
      selectedCanonicalType: null,
      state: "invalid_input",
    },
  }));
  assert.equal(result.resolvedCanonicalSubtype, null);
});

test("physical different-items binding forces ambiguous assessment", () => {
  const result = prepareVisionFamilyIdentityInput(prepareArgs({
    responses: [
      baseResponse({analysisId: "a"}),
      baseResponse({
        analysisId: "b",
        sourceReference: "fixture://test/view_2",
        identityCandidates: [{canonicalType: "jeans", confidence: 0.7}],
      }),
    ],
    multiViewSubjectBinding: {
      contractVersion: 1,
      physicalIdentityClaim: "different_physical_items",
      reasonCodes: [],
    },
  }));
  assert.equal(result.inputAssessment, "ambiguous_subject");
  assert.equal(result.identityCandidates.length, 2);
});

test("undeclared multi-view binding fails closed for promotion", () => {
  const result = prepareVisionFamilyIdentityInput(prepareArgs({
    responses: [
      baseResponse({analysisId: "a"}),
      baseResponse({
        analysisId: "b",
        sourceReference: "fixture://test/view_2",
        identityCandidates: [],
      }),
    ],
    multiViewSubjectBinding: {
      contractVersion: 1,
      physicalIdentityClaim: "undeclared",
      reasonCodes: [],
    },
  }));
  assert.equal(result.inputAssessment, "ambiguous_subject");
});

test("invalid subject framing still projects system subject", () => {
  const result = prepareVisionFamilyIdentityInput(prepareArgs({
    responses: [baseResponse({
      subjectAssessment: baseSubject({
        framingClass: "detail_only",
        framingAttestations: {
          cropIndicators: ["extreme_crop"],
          localDetailOnly: true,
          primarySilhouetteContinuous: false,
          subjectOrientation: "unknown",
          visibleBoundaries: [],
          visibleItemExtent: "local",
        },
      }),
    })],
  }));
  assert.equal(result.subjectAssessment.permitsFamily, false);
  assert.equal(result.hasWholeItemSilhouette, false);
});

test("valid broad silhouette remains eligible", () => {
  const result = prepareVisionFamilyIdentityInput(prepareArgs());
  assert.equal(result.hasWholeItemSilhouette, true);
});

test("local detail-only silhouette is ineligible", () => {
  const result = prepareVisionFamilyIdentityInput(prepareArgs({
    responses: [baseResponse({
      subjectAssessment: baseSubject({
        framingClass: "detail_only",
        framingAttestations: {
          cropIndicators: [],
          localDetailOnly: true,
          primarySilhouetteContinuous: false,
          subjectOrientation: "unknown",
          visibleBoundaries: [],
          visibleItemExtent: "local",
        },
      }),
    })],
  }));
  assert.equal(result.hasWholeItemSilhouette, false);
});

test("partial cropped silhouette is ineligible when not whole/broad", () => {
  const result = prepareVisionFamilyIdentityInput(prepareArgs({
    responses: [baseResponse({
      subjectAssessment: baseSubject({
        framingClass: "partial_item",
        framingAttestations: {
          cropIndicators: ["top_crop"],
          localDetailOnly: false,
          primarySilhouetteContinuous: true,
          subjectOrientation: "front",
          visibleBoundaries: ["left", "right"],
          visibleItemExtent: "indeterminate",
        },
      }),
    })],
  }));
  assert.equal(result.hasWholeItemSilhouette, false);
});

test("missing raw observations fail closed", () => {
  const response = baseResponse();
  delete response.observations;
  assert.throws(() => prepareVisionFamilyIdentityInput(prepareArgs({
    responses: [response],
  })), /observations_required/);
});

test("duplicate observation property fails closed", () => {
  // Object keys cannot duplicate in JSON; simulate via unknown property path
  // and ensure unknown observation keys are rejected.
  assert.throws(() => prepareVisionFamilyIdentityInput(prepareArgs({
    responses: [baseResponse({
      observations: {
        ...baseObservations(),
        notAProperty: {state: "unknown", confidence: 0},
      },
    })],
  })), /unknown_observation_property/);
});

test("taxonomy SHA mismatch fails closed", () => {
  assert.throws(() => prepareVisionFamilyIdentityInput(prepareArgs({
    familyTaxonomySha256:
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    expectedFamilyTaxonomySha256:
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  })), /taxonomy_sha_mismatch/);
});

test("forged client family authority fields are rejected", () => {
  for (const field of FORBIDDEN_AUTHORITY_FIELDS) {
    assert.throws(() => prepareVisionFamilyIdentityInput({
      ...prepareArgs(),
      [field]: field === "hasWholeItemSilhouette" ? true : {},
    }), new RegExp(`forged_client_authority_field:${field}`));
  }
});

test("non-observed observation values normalize to Dart factories", () => {
  assert.deepEqual(
    normalizeObservationValue({state: "not_applicable", confidence: 0.95}, "x"),
    {state: "not_applicable", confidence: 1});
  assert.deepEqual(
    normalizeObservationValue({
      state: "not_visible",
      confidence: 0.95,
      visibilityScope: "not_visible",
    }, "y"),
    {state: "not_visible", confidence: 0, visibilityScope: "not_visible"});
  assert.deepEqual(
    normalizeObservationValue({state: "unknown", confidence: 0.5}, "z"),
    {state: "unknown", confidence: 0});
});

test("DTO serialization is deterministic", () => {
  const first = prepareVisionFamilyIdentityInput(prepareArgs());
  const second = prepareVisionFamilyIdentityInput(prepareArgs());
  assert.equal(sha256(canonicalBytes(first)), sha256(canonicalBytes(second)));
});

test("8/8 family oracle providerInput parity", () => {
  const report = runFamilyIdentityInputParity();
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.deterministic, true);
  assert.equal(report.parityStatus, "orchestration_ready");
  for (const scenario of report.scenarios) {
    assert.equal(scenario.passed, true, scenario.scenarioId);
    assert.equal(scenario.fieldParity.identityCandidates, true);
    assert.equal(scenario.fieldParity.observations, true);
    assert.equal(scenario.fieldParity.resolvedCanonicalSubtype, true);
    assert.equal(scenario.fieldParity.inputAssessment, true);
    assert.equal(scenario.fieldParity.subjectAssessment, true);
    assert.equal(scenario.fieldParity.hasWholeItemSilhouette, true);
  }
});

test("parity entry metadata is orchestration-scoped", () => {
  const report = runFamilyIdentityInputParity();
  const entry = buildFamilyIdentityInputParityEntry(report);
  assert.equal(entry.kind, "orchestration_stage");
  assert.equal(entry.passedScenarios, 8);
  assert.equal(Object.keys(entry.outputSha256ByScenario).length, 8);
  assert.equal(entry.familyOracleBinding, "vision-family-identity-resolver-v1");
});

test("prepare stage is absent from production entry points", () => {
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production,
    /prepare_vision_family_identity_input|PrepareVisionFamilyIdentityInput/);
  assert.doesNotMatch(production,
    /VisionFamilyIdentityResolver|vision_family_identity_resolver|resolveVisionFamilyIdentity/);
  assert.doesNotMatch(
    fs.readFileSync(path.join(__dirname,
      "prepare_vision_family_identity_input.js"), "utf8"),
    /firebase|firestore|persistence|QualifiedVisionPersistenceMapper/);
});

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
