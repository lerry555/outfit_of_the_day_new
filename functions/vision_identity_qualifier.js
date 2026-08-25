"use strict";

/**
 * Node port of Dart VisionIdentityQualifier.qualify.
 * Pure / sync / deterministic. Not imported by production entry points.
 */

const {
  minimumDefiningSupportsFor,
} = require("./canonical_observation_consistency_validator");

const PROVIDER_ID = "VisionIdentityQualification";
const PROVIDER_VERSION = "vision-identity-qualification-v1";
const ORACLE_CONTRACT_VERSION = 1;
const METHOD_TAG = "safe_identity_v1";

const COMPATIBILITY_LEVELS = new Set([
  "strong", "compatible", "uncertain", "conflicting",
]);
const COMPATIBILITY_CAP = Object.freeze({
  strong: 0.85,
  compatible: 0.65,
  uncertain: 0.35,
  conflicting: 0.0,
});
const IDENTITY_STATES = Object.freeze({
  confirmed: "confirmed",
  supported: "supported",
  ambiguous: "ambiguous",
  insufficientEvidence: "insufficient_evidence",
  conflicting: "conflicting",
});

function qualifyVisionIdentity(rawInput) {
  const input = decodeIdentityQualificationInput(rawInput);
  const byId = new Map(input.consistency.results.map((item) =>
    [item.identityEvidenceId, item]));
  const assessments = input.identityEvidence.map((item) => {
    const result = byId.get(item.id);
    const level = result?.compatibilityLevel ?? "uncertain";
    const compatibilityCap = COMPATIBILITY_CAP[level];
    const declared = input.declaredByEvidenceId[item.id] ?? {
      defining: [],
      supporting: [],
    };
    const definingSupports = result?.definingEvidence ?? [];
    const acceptedSupporting = (result?.supportingOnlyEvidence ?? [])
      .filter((path) => declared.supporting.includes(observationName(path)))
      .slice()
      .sort();
    const acceptedDefining = definingSupports
      .filter((path) => declared.defining.includes(observationName(path)))
      .slice()
      .sort();
    const rejectedSupporting = declared.supporting
      .filter((name) => !(result?.supportingOnlyEvidence ?? [])
        .some((path) => observationName(path) === name))
      .slice()
      .sort();
    const rejectedDefining = declared.defining
      .filter((name) => !definingSupports
        .some((path) => observationName(path) === name))
      .slice()
      .sort();
    const minimumDefining = minimumDefiningSupportsFor(String(item.value));
    const hasRequiredDefining = acceptedDefining.length >= minimumDefining;
    const semanticCap = hasRequiredDefining ? 1.0 : 0.49;
    const totalDeclared = new Set([
      ...declared.defining,
      ...declared.supporting,
    ]).size;
    const declaredSupportCap = item.confidence > 0.70 && totalDeclared < 2 ?
      0.60 : 1.0;
    const cap = Math.min(compatibilityCap, semanticCap, declaredSupportCap);
    const confidence = item.confidence < cap ? item.confidence : cap;
    let state;
    if (level === "conflicting") {
      state = IDENTITY_STATES.conflicting;
    } else if (level === "uncertain") {
      state = IDENTITY_STATES.insufficientEvidence;
    } else if (!hasRequiredDefining) {
      state = IDENTITY_STATES.insufficientEvidence;
    } else if (level === "strong" && confidence >= 0.70) {
      state = IDENTITY_STATES.confirmed;
    } else if (confidence >= 0.50) {
      state = IDENTITY_STATES.supported;
    } else {
      state = IDENTITY_STATES.insufficientEvidence;
    }
    const reasons = [
      `consistency:${level}`,
      `semantic_defining:${acceptedDefining.length}/${minimumDefining}`,
    ];
    if (rejectedSupporting.length > 0) {
      reasons.push(`rejected_declared_supports:${rejectedSupporting.length}`);
    }
    if (rejectedDefining.length > 0) {
      reasons.push(`rejected_declared_defining:${rejectedDefining.length}`);
    }
    if ((result?.reasonCodes ?? []).includes("missing_signature_coverage")) {
      reasons.push("missing_signature_coverage");
    }
    if (!hasRequiredDefining) {
      reasons.push("missing_required_defining_support");
    }
    reasons.sort();
    return {
      evidence: item,
      confidence,
      state,
      supporting: acceptedSupporting,
      defining: acceptedDefining,
      declaredDefining: [...declared.defining],
      declaredSupporting: [...declared.supporting],
      rejectedSupporting,
      rejectedDefining,
      missing: [...(result?.missingDefiningEvidence ?? [])],
      missingSignature: (result?.reasonCodes ?? [])
        .includes("missing_signature_coverage"),
      reasons,
    };
  });

  const viable = assessments
    .filter((item) => input.inputIsValid &&
      (item.state === IDENTITY_STATES.confirmed ||
        item.state === IDENTITY_STATES.supported))
    .slice()
    .sort((left, right) => {
      const state = identityStateRank(right.state) -
        identityStateRank(left.state);
      if (state !== 0) return state;
      const defining = right.defining.length - left.defining.length;
      if (defining !== 0) return defining;
      const confidence = right.confidence - left.confidence;
      if (confidence !== 0) return confidence;
      return String(left.evidence.value).localeCompare(
        String(right.evidence.value));
    });
  const topMargin = viable.length >= 2 ?
    viable[0].confidence - viable[1].confidence : null;
  const ambiguous = viable.length >= 2 &&
    viable[0].evidence.value !== viable[1].evidence.value &&
    identityStateRank(viable[0].state) ===
      identityStateRank(viable[1].state) &&
    topMargin < 0.10;
  const selected = ambiguous || viable.length === 0 ? null : viable[0];
  let overallState;
  if (!input.inputIsValid) {
    overallState = IDENTITY_STATES.insufficientEvidence;
  } else if (ambiguous) {
    overallState = IDENTITY_STATES.ambiguous;
  } else if (selected != null) {
    overallState = selected.state;
  } else if (assessments.some((item) =>
    item.state === IDENTITY_STATES.conflicting)) {
    overallState = IDENTITY_STATES.conflicting;
  } else {
    overallState = IDENTITY_STATES.insufficientEvidence;
  }

  const qualifiedIdentityEvidence = assessments.map((assessment) => {
    const active = input.inputIsValid &&
      selected != null &&
      selected.evidence.id === assessment.evidence.id;
    const level = byId.get(assessment.evidence.id)?.compatibilityLevel ??
      "uncertain";
    const supportCount = new Set([
      ...assessment.supporting,
      ...assessment.defining,
    ]).size;
    return encodeEvidence({
      id: `${assessment.evidence.id}:qualified`,
      property: assessment.evidence.property,
      value: assessment.evidence.value,
      source: assessment.evidence.source,
      nature: assessment.evidence.nature,
      confidence: assessment.confidence,
      verified: false,
      active,
      method: `${assessment.evidence.method}:` +
        `consistency_${level}:` +
        `support_${supportCount}:` +
        `${active ? "qualified" : "deactivated"}:` +
        `semantic_${assessment.state}:` +
        `defining_${assessment.defining.length}:` +
        METHOD_TAG,
      createdAt: assessment.evidence.createdAt,
      modelVersion: assessment.evidence.modelVersion,
      sourceReference: assessment.evidence.id,
      valueState: assessment.evidence.valueState,
    });
  }).sort((left, right) => left.id.localeCompare(right.id));

  const candidates = assessments.map((item) => ({
    canonicalType: String(item.evidence.value),
    rawConfidence: item.evidence.confidence,
    qualifiedConfidence: item.confidence,
    state: ambiguous &&
      (item.state === IDENTITY_STATES.confirmed ||
        item.state === IDENTITY_STATES.supported) ?
      IDENTITY_STATES.ambiguous : item.state,
    usedDefiningSupports: item.defining,
    usedSupportingObservations: item.supporting,
    modelDeclaredDefining: item.declaredDefining,
    modelDeclaredSupporting: item.declaredSupporting,
    rejectedSupportingObservations: item.rejectedSupporting,
    rejectedDefiningObservations: item.rejectedDefining,
    missingDefiningEvidence: item.missing,
    missingSignatureCoverage: item.missingSignature,
    reasonCodes: item.reasons,
  })).sort((left, right) =>
    left.canonicalType.localeCompare(right.canonicalType));

  return deepFreeze({
    qualifiedIdentityEvidence,
    report: {
      state: overallState,
      selectedCanonicalType: selected == null ?
        null : String(selected.evidence.value),
      topMargin,
      candidates,
    },
  });
}

function decodeIdentityQualificationInput(value) {
  if (!isObject(value)) fail("identity_input_invalid");
  if (value.contractVersion != null && value.contractVersion !== 1) {
    fail("identity_contract_version_invalid");
  }
  if (value.providerVersion != null &&
      value.providerVersion !== PROVIDER_VERSION) {
    fail("identity_provider_version_invalid");
  }
  if (value.qualificationVersion != null &&
      value.qualificationVersion !== PROVIDER_VERSION) {
    fail("identity_qualification_version_invalid");
  }
  if (typeof value.inputIsValid !== "boolean") {
    fail("identity_input_is_valid_invalid");
  }
  if (!Array.isArray(value.identityEvidence)) {
    fail("identity_evidence_invalid");
  }
  if (!isObject(value.consistency) || !Array.isArray(value.consistency.results)) {
    fail("identity_consistency_invalid");
  }
  if (!isObject(value.declaredByEvidenceId)) {
    fail("identity_declared_by_invalid");
  }
  if (value.taxonomyRegistrySha256 != null) {
    if (typeof value.taxonomyRegistrySha256 !== "string" ||
        !/^[a-f0-9]{64}$/.test(value.taxonomyRegistrySha256)) {
      fail("taxonomy_sha_invalid");
    }
    if (value.expectedTaxonomyRegistrySha256 != null &&
        value.taxonomyRegistrySha256 !==
          value.expectedTaxonomyRegistrySha256) {
      fail("taxonomy_sha_mismatch");
    }
  }
  const seenIds = new Set();
  const identityEvidence = value.identityEvidence.map((item, index) => {
    const evidence = decodeIdentityEvidence(item, index);
    if (seenIds.has(evidence.id)) {
      fail(`duplicate_evidence_id:${evidence.id}`);
    }
    seenIds.add(evidence.id);
    return evidence;
  });
  const declaredByEvidenceId = {};
  for (const [key, entry] of Object.entries(value.declaredByEvidenceId)) {
    if (typeof key !== "string" || key.trim() === "") {
      fail("declared_key_invalid");
    }
    if (!isObject(entry) ||
        !Array.isArray(entry.defining) ||
        !Array.isArray(entry.supporting) ||
        entry.defining.some((name) => typeof name !== "string") ||
        entry.supporting.some((name) => typeof name !== "string")) {
      fail(`declared_entry_invalid:${key}`);
    }
    declaredByEvidenceId[key] = {
      defining: [...entry.defining],
      supporting: [...entry.supporting],
    };
  }
  const consistency = {
    results: value.consistency.results.map(decodeConsistencyResult),
    identityConflict: value.consistency.identityConflict === true,
    candidateGap: value.consistency.candidateGap ?? "unavailable",
    competingCanonicalTypes:
      Array.isArray(value.consistency.competingCanonicalTypes) ?
        [...value.consistency.competingCanonicalTypes] : [],
    decisionRelevantDifferences:
      Array.isArray(value.consistency.decisionRelevantDifferences) ?
        [...value.consistency.decisionRelevantDifferences] : [],
    neededEvidence: Array.isArray(value.consistency.neededEvidence) ?
      [...value.consistency.neededEvidence] : [],
  };
  return deepFreeze({
    identityEvidence,
    consistency,
    declaredByEvidenceId,
    inputIsValid: value.inputIsValid,
  });
}

function decodeIdentityEvidence(value, index) {
  if (!isObject(value)) fail(`identity_evidence_item_invalid:${index}`);
  if (typeof value.id !== "string" || value.id.trim() === "") {
    fail(`identity_evidence_id_invalid:${index}`);
  }
  if (value.property !== "identity.canonicalType") {
    fail(`identity_evidence_property_invalid:${index}`);
  }
  if (typeof value.value !== "string" || value.value.trim() === "") {
    fail(`identity_evidence_value_invalid:${index}`);
  }
  const valueState = value.valueState ?? "known";
  if (valueState !== "known") fail(`identity_evidence_value_state_invalid:${index}`);
  if (typeof value.confidence !== "number" || !Number.isFinite(value.confidence) ||
      value.confidence < 0 || value.confidence > 1) {
    fail(`identity_evidence_confidence_invalid:${index}`);
  }
  if (value.source !== "ai_inference") {
    fail(`identity_evidence_source_invalid:${index}`);
  }
  if (value.nature !== "inferred") {
    fail(`identity_evidence_nature_invalid:${index}`);
  }
  if (typeof value.method !== "string" || value.method.trim() === "") {
    fail(`identity_evidence_method_invalid:${index}`);
  }
  if (typeof value.createdAt !== "string" || value.createdAt.trim() === "") {
    fail(`identity_evidence_created_at_invalid:${index}`);
  }
  return deepFreeze({
    id: value.id,
    property: value.property,
    value: value.value,
    valueState,
    source: value.source,
    nature: value.nature,
    confidence: value.confidence,
    verified: value.verified === true,
    active: value.active !== false,
    method: value.method,
    createdAt: value.createdAt,
    modelVersion: value.modelVersion ?? null,
    sourceReference: value.sourceReference ?? null,
  });
}

function decodeConsistencyResult(value) {
  if (!isObject(value) || typeof value.identityEvidenceId !== "string") {
    fail("consistency_result_invalid");
  }
  requireEnum(value.compatibilityLevel, COMPATIBILITY_LEVELS,
    "compatibility_level_invalid");
  return deepFreeze({
    identityEvidenceId: value.identityEvidenceId,
    candidateCanonicalType: value.candidateCanonicalType,
    identitySource: value.identitySource,
    identityConfidence: value.identityConfidence,
    compatibilityLevel: value.compatibilityLevel,
    score: value.score,
    supportingEvidence: [...(value.supportingEvidence ?? [])],
    definingEvidence: [...(value.definingEvidence ?? [])],
    supportingOnlyEvidence: [...(value.supportingOnlyEvidence ?? [])],
    conflictingEvidence: [...(value.conflictingEvidence ?? [])],
    missingExpectedEvidence: [...(value.missingExpectedEvidence ?? [])],
    missingDefiningEvidence: [...(value.missingDefiningEvidence ?? [])],
    reasonCodes: [...(value.reasonCodes ?? [])],
    neededEvidence: [...(value.neededEvidence ?? [])],
  });
}

function encodeEvidence(item) {
  const result = {
    id: item.id,
    property: item.property,
    value: item.value,
    source: item.source,
    nature: item.nature,
    confidence: item.confidence,
    verified: item.verified === true,
    active: item.active !== false,
    method: item.method,
    createdAt: item.createdAt,
  };
  if (item.valueState && item.valueState !== "known") {
    result.valueState = item.valueState;
  }
  if (item.modelVersion != null) result.modelVersion = item.modelVersion;
  if (item.sourceReference != null) {
    result.sourceReference = item.sourceReference;
  }
  return result;
}

function decodeIdentityOracle(value) {
  if (!isObject(value)) fail("identity_oracle_invalid");
  if (value.oracleVersion !== ORACLE_CONTRACT_VERSION &&
      value.oracleContractVersion !== ORACLE_CONTRACT_VERSION) {
    fail("identity_oracle_version_invalid");
  }
  if (value.providerId !== PROVIDER_ID) fail("identity_provider_id_invalid");
  if (value.providerVersion !== PROVIDER_VERSION) {
    fail("identity_provider_version_invalid");
  }
  requireText(value.scenarioId, "identity_scenario_id_required");
  if (!Array.isArray(value.invocations) || value.invocations.length === 0) {
    fail("identity_invocations_invalid");
  }
  const invocations = value.invocations.map((item, index) => {
    if (!isObject(item)) fail(`identity_invocation_invalid:${index}`);
    requireText(item.invocationId, "identity_invocation_id_required");
    if (!isObject(item.providerInput) || !isObject(item.providerOutput)) {
      fail(`identity_invocation_payload_invalid:${index}`);
    }
    return {
      invocationId: item.invocationId,
      providerInput: decodeIdentityQualificationInput(item.providerInput),
      providerOutput: structuredClone(item.providerOutput),
    };
  });
  return deepFreeze({
    scenarioId: value.scenarioId,
    invocations,
  });
}

function identityStateRank(state) {
  if (state === IDENTITY_STATES.confirmed) return 2;
  if (state === IDENTITY_STATES.supported) return 1;
  return 0;
}

function observationName(propertyPath) {
  const parts = String(propertyPath).split(".");
  return parts[parts.length - 1];
}

function requireText(value, reason) {
  if (typeof value !== "string" || value.trim() === "") fail(reason);
  return value;
}

function requireEnum(value, allowed, reason) {
  if (typeof value !== "string" || !allowed.has(value)) fail(reason);
  return value;
}

function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    Object.values(value).forEach(deepFreeze);
  }
  return value;
}

function fail(reason) {
  throw new Error(reason);
}

module.exports = {
  IDENTITY_STATES,
  ORACLE_CONTRACT_VERSION,
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeIdentityOracle,
  decodeIdentityQualificationInput,
  qualifyVisionIdentity,
};
