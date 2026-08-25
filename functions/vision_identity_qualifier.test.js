"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildIdentityQualificationParityEntry,
  runIdentityQualificationParity,
} = require("./backend_identity_qualification_parity");
const {
  IDENTITY_STATES,
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeIdentityQualificationInput,
  qualifyVisionIdentity,
} = require("./vision_identity_qualifier");
const {
  runIdentityQualificationInputParity,
} = require("./backend_identity_qualification_input_parity");

const root = path.resolve(__dirname, "..");

function baseEvidence(overrides = {}) {
  return {
    id: "vision-identity:analysis:t_shirt",
    property: "identity.canonicalType",
    value: "t_shirt",
    source: "ai_inference",
    nature: "inferred",
    confidence: 0.8,
    verified: false,
    active: true,
    method: "vision_v2_identity_candidate",
    createdAt: "2000-01-01T00:00:00.000Z",
    modelVersion: "gpt-4o-mini",
    sourceReference: "fixture://x",
    ...overrides,
  };
}

function consistencyResult(overrides = {}) {
  return {
    identityEvidenceId: "vision-identity:analysis:t_shirt",
    candidateCanonicalType: "t_shirt",
    identitySource: "ai_inference",
    identityConfidence: 0.8,
    compatibilityLevel: "compatible",
    score: 2,
    supportingEvidence: ["visual.observations.visibleBulk"],
    definingEvidence: ["visual.coverage"],
    supportingOnlyEvidence: ["visual.observations.visibleBulk"],
    conflictingEvidence: [],
    missingExpectedEvidence: [],
    missingDefiningEvidence: [],
    reasonCodes: ["supports:visual.coverage=partial"],
    neededEvidence: [],
    ...overrides,
  };
}

function input(overrides = {}) {
  return {
    identityEvidence: [baseEvidence()],
    consistency: {
      results: [consistencyResult()],
      identityConflict: false,
      candidateGap: "unavailable",
      competingCanonicalTypes: ["t_shirt"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
    declaredByEvidenceId: {
      "vision-identity:analysis:t_shirt": {
        defining: ["coverage"],
        supporting: ["visibleBulk"],
      },
    },
    inputIsValid: true,
    ...overrides,
  };
}

test("provider identity", () => {
  assert.equal(PROVIDER_ID, "VisionIdentityQualification");
  assert.equal(PROVIDER_VERSION, "vision-identity-qualification-v1");
});

test("invalid input fails closed", () => {
  assert.throws(() => decodeIdentityQualificationInput(null),
    /identity_input_invalid/);
  assert.throws(() => decodeIdentityQualificationInput({
    ...input(),
    inputIsValid: "yes",
  }), /identity_input_is_valid_invalid/);
});

test("no identity evidence yields insufficient overall state", () => {
  const output = qualifyVisionIdentity(input({
    identityEvidence: [],
    consistency: {
      results: [],
      identityConflict: false,
      candidateGap: "unavailable",
      competingCanonicalTypes: [],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
    declaredByEvidenceId: {},
  }));
  assert.equal(output.report.state, IDENTITY_STATES.insufficientEvidence);
  assert.equal(output.report.selectedCanonicalType, null);
  assert.deepEqual(output.qualifiedIdentityEvidence, []);
});

test("one weak candidate stays insufficient", () => {
  const output = qualifyVisionIdentity(input({
    identityEvidence: [baseEvidence({confidence: 0.2})],
    consistency: {
      results: [consistencyResult({
        compatibilityLevel: "uncertain",
        definingEvidence: [],
        supportingOnlyEvidence: [],
      })],
      identityConflict: false,
      candidateGap: "unavailable",
      competingCanonicalTypes: ["t_shirt"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
  }));
  assert.equal(output.report.candidates[0].state,
    IDENTITY_STATES.insufficientEvidence);
  assert.equal(output.report.selectedCanonicalType, null);
});

test("one supported candidate selects canonical", () => {
  const output = qualifyVisionIdentity(input({
    identityEvidence: [baseEvidence({confidence: 0.8})],
    consistency: {
      results: [consistencyResult({compatibilityLevel: "compatible"})],
      identityConflict: false,
      candidateGap: "unavailable",
      competingCanonicalTypes: ["t_shirt"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
  }));
  assert.equal(output.report.state, IDENTITY_STATES.supported);
  assert.equal(output.report.selectedCanonicalType, "t_shirt");
  assert.equal(output.qualifiedIdentityEvidence[0].active, true);
});

test("one confirmed candidate requires strong + confidence >= 0.70", () => {
  const output = qualifyVisionIdentity(input({
    identityEvidence: [baseEvidence({confidence: 0.9})],
    consistency: {
      results: [consistencyResult({compatibilityLevel: "strong"})],
      identityConflict: false,
      candidateGap: "unavailable",
      competingCanonicalTypes: ["t_shirt"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
  }));
  assert.equal(output.report.state, IDENTITY_STATES.confirmed);
  assert.equal(output.report.candidates[0].state, IDENTITY_STATES.confirmed);
});

test("multiple compatible candidates pick higher confidence", () => {
  const left = baseEvidence({
    id: "vision-identity:analysis:hoodie",
    value: "hoodie",
    confidence: 0.52,
  });
  const right = baseEvidence({
    id: "vision-identity:analysis:t_shirt",
    value: "t_shirt",
    confidence: 0.9,
  });
  const output = qualifyVisionIdentity(input({
    identityEvidence: [left, right],
    consistency: {
      results: [
        consistencyResult({
          identityEvidenceId: left.id,
          candidateCanonicalType: "hoodie",
          compatibilityLevel: "compatible",
          definingEvidence: ["visual.observations.hasHood"],
          supportingOnlyEvidence: [],
        }),
        consistencyResult({
          identityEvidenceId: right.id,
          candidateCanonicalType: "t_shirt",
          compatibilityLevel: "compatible",
        }),
      ],
      identityConflict: false,
      candidateGap: "small",
      competingCanonicalTypes: ["hoodie", "t_shirt"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
    declaredByEvidenceId: {
      [left.id]: {defining: ["hasHood"], supporting: []},
      [right.id]: {defining: ["coverage"], supporting: ["visibleBulk"]},
    },
  }));
  assert.equal(output.report.selectedCanonicalType, "t_shirt");
  assert.equal(
    output.qualifiedIdentityEvidence.find((item) =>
      item.value === "t_shirt").active, true);
  assert.equal(
    output.qualifiedIdentityEvidence.find((item) =>
      item.value === "hoodie").active, false);
});

test("ambiguous tie when margin < 0.10 and same state rank", () => {
  const left = baseEvidence({
    id: "vision-identity:analysis:hoodie",
    value: "hoodie",
    confidence: 0.62,
  });
  const right = baseEvidence({
    id: "vision-identity:analysis:t_shirt",
    value: "t_shirt",
    confidence: 0.6,
  });
  const output = qualifyVisionIdentity(input({
    identityEvidence: [left, right],
    consistency: {
      results: [
        consistencyResult({
          identityEvidenceId: left.id,
          candidateCanonicalType: "hoodie",
          compatibilityLevel: "compatible",
          definingEvidence: ["visual.observations.hasHood"],
          supportingOnlyEvidence: [],
        }),
        consistencyResult({
          identityEvidenceId: right.id,
          candidateCanonicalType: "t_shirt",
          compatibilityLevel: "compatible",
        }),
      ],
      identityConflict: false,
      candidateGap: "none",
      competingCanonicalTypes: ["hoodie", "t_shirt"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
    declaredByEvidenceId: {
      [left.id]: {defining: ["hasHood"], supporting: []},
      [right.id]: {defining: ["coverage"], supporting: ["visibleBulk"]},
    },
  }));
  assert.equal(output.report.state, IDENTITY_STATES.ambiguous);
  assert.equal(output.report.selectedCanonicalType, null);
  assert.ok(output.report.topMargin != null && output.report.topMargin < 0.10);
});

test("conflicting candidate surfaces overall conflicting when no viable", () => {
  const output = qualifyVisionIdentity(input({
    consistency: {
      results: [consistencyResult({compatibilityLevel: "conflicting"})],
      identityConflict: true,
      candidateGap: "unavailable",
      competingCanonicalTypes: ["t_shirt"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
  }));
  assert.equal(output.report.candidates[0].state, IDENTITY_STATES.conflicting);
  assert.equal(output.report.state, IDENTITY_STATES.conflicting);
});

test("unknown canonical uses minimumDefining 0 and still qualifies by caps",
  () => {
    const output = qualifyVisionIdentity(input({
      identityEvidence: [baseEvidence({
        value: "totally_unknown_type",
        confidence: 0.9,
      })],
      consistency: {
        results: [consistencyResult({
          candidateCanonicalType: "totally_unknown_type",
          compatibilityLevel: "uncertain",
          reasonCodes: ["signature_not_covered", "missing_signature_coverage"],
          definingEvidence: [],
          supportingOnlyEvidence: [],
        })],
        identityConflict: false,
        candidateGap: "unavailable",
        competingCanonicalTypes: ["totally_unknown_type"],
        decisionRelevantDifferences: [],
        neededEvidence: [],
      },
    }));
    assert.equal(output.report.candidates[0].state,
      IDENTITY_STATES.insufficientEvidence);
    assert.equal(output.report.candidates[0].missingSignatureCoverage, true);
  });

test("duplicate evidence ID fails closed", () => {
  assert.throws(() => decodeIdentityQualificationInput(input({
    identityEvidence: [baseEvidence(), baseEvidence()],
  })), /duplicate_evidence_id/);
});

test("missing declaredByEvidenceId defaults to empty supports", () => {
  const output = qualifyVisionIdentity(input({
    identityEvidence: [baseEvidence({
      id: "vision-identity:analysis:hoodie",
      value: "hoodie",
      confidence: 0.9,
    })],
    consistency: {
      results: [consistencyResult({
        identityEvidenceId: "vision-identity:analysis:hoodie",
        candidateCanonicalType: "hoodie",
        compatibilityLevel: "compatible",
        definingEvidence: ["visual.observations.hasHood"],
        supportingOnlyEvidence: [],
      })],
      identityConflict: false,
      candidateGap: "unavailable",
      competingCanonicalTypes: ["hoodie"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
    declaredByEvidenceId: {},
  }));
  assert.equal(output.report.candidates[0].modelDeclaredDefining.length, 0);
  assert.ok(output.report.candidates[0].reasonCodes
    .includes("missing_required_defining_support"));
});

test("empty defining and supporting observations are preserved", () => {
  const output = qualifyVisionIdentity(input({
    declaredByEvidenceId: {
      "vision-identity:analysis:t_shirt": {defining: [], supporting: []},
    },
  }));
  assert.deepEqual(output.report.candidates[0].modelDeclaredDefining, []);
  assert.deepEqual(output.report.candidates[0].modelDeclaredSupporting, []);
});

test("confidence boundaries around supported threshold", () => {
  const below = qualifyVisionIdentity(input({
    identityEvidence: [baseEvidence({confidence: 0.49})],
  }));
  assert.equal(below.report.selectedCanonicalType, null);
  const exact = qualifyVisionIdentity(input({
    identityEvidence: [baseEvidence({confidence: 0.5})],
  }));
  assert.equal(exact.report.state, IDENTITY_STATES.supported);
  const above = qualifyVisionIdentity(input({
    identityEvidence: [baseEvidence({confidence: 0.51})],
  }));
  assert.equal(above.report.state, IDENTITY_STATES.supported);
});

test("confirmed boundary at 0.70 with strong consistency", () => {
  const below = qualifyVisionIdentity(input({
    identityEvidence: [baseEvidence({confidence: 0.69})],
    consistency: {
      results: [consistencyResult({compatibilityLevel: "strong"})],
      identityConflict: false,
      candidateGap: "unavailable",
      competingCanonicalTypes: ["t_shirt"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
  }));
  assert.equal(below.report.candidates[0].state, IDENTITY_STATES.supported);
  const exact = qualifyVisionIdentity(input({
    identityEvidence: [baseEvidence({confidence: 0.7})],
    consistency: {
      results: [consistencyResult({compatibilityLevel: "strong"})],
      identityConflict: false,
      candidateGap: "unavailable",
      competingCanonicalTypes: ["t_shirt"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
  }));
  assert.equal(exact.report.candidates[0].state, IDENTITY_STATES.confirmed);
});

test("inputIsValid false blocks otherwise strong candidate", () => {
  const output = qualifyVisionIdentity(input({
    identityEvidence: [baseEvidence({confidence: 0.95})],
    consistency: {
      results: [consistencyResult({compatibilityLevel: "strong"})],
      identityConflict: false,
      candidateGap: "unavailable",
      competingCanonicalTypes: ["t_shirt"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
    inputIsValid: false,
  }));
  assert.equal(output.report.state, IDENTITY_STATES.insufficientEvidence);
  assert.equal(output.report.selectedCanonicalType, null);
  assert.equal(output.qualifiedIdentityEvidence[0].active, false);
  assert.match(output.qualifiedIdentityEvidence[0].method, /deactivated/);
});

test("selected evidence activates; others remain inactive", () => {
  const left = baseEvidence({
    id: "vision-identity:analysis:a",
    value: "boots",
    confidence: 0.7,
  });
  const right = baseEvidence({
    id: "vision-identity:analysis:b",
    value: "sneakers",
    confidence: 0.51,
  });
  const output = qualifyVisionIdentity(input({
    identityEvidence: [left, right],
    consistency: {
      results: [
        consistencyResult({
          identityEvidenceId: left.id,
          candidateCanonicalType: "boots",
          compatibilityLevel: "strong",
          definingEvidence: ["visual.observations.footwearUpperHeight"],
          supportingOnlyEvidence: [],
        }),
        consistencyResult({
          identityEvidenceId: right.id,
          candidateCanonicalType: "sneakers",
          compatibilityLevel: "compatible",
          definingEvidence: ["visual.observations.footwearConstruction"],
          supportingOnlyEvidence: [],
        }),
      ],
      identityConflict: false,
      candidateGap: "small",
      competingCanonicalTypes: ["boots", "sneakers"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
    declaredByEvidenceId: {
      [left.id]: {defining: ["footwearUpperHeight"], supporting: []},
      [right.id]: {defining: ["footwearConstruction"], supporting: []},
    },
  }));
  const active = output.qualifiedIdentityEvidence.filter((item) => item.active);
  assert.equal(active.length, 1);
  assert.equal(active[0].value, "boots");
});

test("candidate reports are ordered by canonical type", () => {
  const left = baseEvidence({
    id: "vision-identity:analysis:z",
    value: "zip_hoodie",
    confidence: 0.2,
  });
  const right = baseEvidence({
    id: "vision-identity:analysis:a",
    value: "boots",
    confidence: 0.2,
  });
  const output = qualifyVisionIdentity(input({
    identityEvidence: [left, right],
    consistency: {
      results: [
        consistencyResult({
          identityEvidenceId: left.id,
          candidateCanonicalType: "zip_hoodie",
          compatibilityLevel: "uncertain",
          definingEvidence: [],
          supportingOnlyEvidence: [],
        }),
        consistencyResult({
          identityEvidenceId: right.id,
          candidateCanonicalType: "boots",
          compatibilityLevel: "uncertain",
          definingEvidence: [],
          supportingOnlyEvidence: [],
        }),
      ],
      identityConflict: false,
      candidateGap: "unavailable",
      competingCanonicalTypes: ["boots", "zip_hoodie"],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
    declaredByEvidenceId: {
      [left.id]: {defining: [], supporting: []},
      [right.id]: {defining: [], supporting: []},
    },
  }));
  assert.deepEqual(
    output.report.candidates.map((item) => item.canonicalType),
    ["boots", "zip_hoodie"]);
});

test("null selectedCanonicalType and topMargin are explicit", () => {
  const output = qualifyVisionIdentity(input({
    identityEvidence: [],
    consistency: {
      results: [],
      identityConflict: false,
      candidateGap: "unavailable",
      competingCanonicalTypes: [],
      decisionRelevantDifferences: [],
      neededEvidence: [],
    },
    declaredByEvidenceId: {},
  }));
  assert.equal(Object.hasOwn(output.report, "selectedCanonicalType"), true);
  assert.equal(output.report.selectedCanonicalType, null);
  assert.equal(Object.hasOwn(output.report, "topMargin"), true);
  assert.equal(output.report.topMargin, null);
});

test("taxonomy SHA mismatch fails closed", () => {
  assert.throws(() => decodeIdentityQualificationInput(input({
    taxonomyRegistrySha256:
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    expectedTaxonomyRegistrySha256:
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  })), /taxonomy_sha_mismatch/);
});

test("deterministic DTO serialization", () => {
  const first = qualifyVisionIdentity(input());
  const second = qualifyVisionIdentity(input());
  assert.equal(sha256(canonicalBytes(first)), sha256(canonicalBytes(second)));
});

test("prepare-stage remains orchestration_ready for integration", () => {
  const prepare = runIdentityQualificationInputParity();
  assert.equal(prepare.parityStatus, "orchestration_ready");
  assert.equal(prepare.passedScenarios, 8);
});

test("8/8 identity oracle providerOutput parity", () => {
  const report = runIdentityQualificationParity();
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.passedInvocations, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.deterministic, true);
  assert.equal(report.parityStatus, "parity_ready");
  for (const scenario of report.scenarios) {
    assert.equal(scenario.passed, true, scenario.scenarioId);
    for (const invocation of scenario.invocations) {
      assert.equal(invocation.fieldParity.report, true);
      assert.equal(invocation.fieldParity.qualifiedIdentityEvidence, true);
      assert.equal(invocation.fieldParity.status, true);
      assert.equal(invocation.fieldParity.selectedCanonicalType, true);
    }
  }
});

test("parity entry is stable and byte-identical on rerun", () => {
  const first = buildIdentityQualificationParityEntry(
    runIdentityQualificationParity());
  const second = buildIdentityQualificationParityEntry(
    runIdentityQualificationParity());
  assert.equal(first.parityStatus, "parity_ready");
  assert(canonicalBytes(first).equals(canonicalBytes(second)));
});

test("provider remains production isolated", () => {
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production, /vision_identity_qualifier/);
  assert.doesNotMatch(production, /qualifyVisionIdentity/);
  assert.doesNotMatch(
    fs.readFileSync(path.join(__dirname, "vision_identity_qualifier.js"),
      "utf8"),
    /firebase|firestore|persistence|QualifiedVisionPersistenceMapper|VisionFamilyIdentityResolver|KnowledgeBase/);
});

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
