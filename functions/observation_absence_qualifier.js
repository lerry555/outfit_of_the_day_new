"use strict";

const {
  decodeProviderInput: decodeObservationBundle,
} = require("./vision_observation_evidence_provider");

const PROVIDER_ID = "ObservationAbsenceQualifier";
const PROVIDER_VERSION = "observation-absence-qualifier-v1";
const ORACLE_CONTRACT_VERSION = 1;

const PROPERTY_ORDER = Object.freeze([
  "coverage", "hasHood", "frontClosure", "visibleBulk",
  "surfaceAppearance", "necklineShape", "visiblePocketStructure",
  "visibleStretchCue", "sportyCues", "formalCues",
  "footwearConstruction", "footwearFastening", "soleProfile",
  "visibleTread", "footwearUpperHeight",
]);

const ABSENCE_AUDIT_ORDER = Object.freeze([
  "visiblePocketStructure", "hasHood", "frontClosure", "visibleStretchCue",
]);

const DISPOSITIONS = new Set([
  "unchanged", "qualified", "degradedToUnknown", "degradedToNotVisible",
  "conflict",
]);

const SCOPE_RANK = Object.freeze({
  complete: 3,
  sufficient: 2,
  partial: 1,
  not_visible: 0,
});

const POLICIES = Object.freeze({
  visiblePocketStructure: Object.freeze({
    property: "visiblePocketStructure",
    isAbsence: (value) => value === "none",
    isPositiveExistence: (value) => value !== "none",
    minimumSingleViewScope: "complete",
    minimumConsistentSufficientViews: 2,
    maximumAbsenceConfidence: 0.9,
    absenceCanBeObserved: true,
  }),
  hasHood: Object.freeze({
    property: "hasHood",
    isAbsence: (value) => value === false,
    isPositiveExistence: (value) => value === true,
    minimumSingleViewScope: "sufficient",
    minimumConsistentSufficientViews: 2,
    maximumAbsenceConfidence: 0.9,
    absenceCanBeObserved: true,
  }),
  frontClosure: Object.freeze({
    property: "frontClosure",
    isAbsence: (value) => value === "none",
    isPositiveExistence: (value) => value !== "none",
    minimumSingleViewScope: "sufficient",
    minimumConsistentSufficientViews: 2,
    maximumAbsenceConfidence: 0.9,
    absenceCanBeObserved: true,
  }),
  visibleStretchCue: Object.freeze({
    property: "visibleStretchCue",
    isAbsence: (value) => value === false,
    isPositiveExistence: (value) => value === true,
    minimumSingleViewScope: "complete",
    minimumConsistentSufficientViews: 2,
    maximumAbsenceConfidence: 0.9,
    absenceCanBeObserved: false,
  }),
});

function decodeAbsenceInput(value) {
  if (!isObject(value)) fail("absence_input_invalid");
  if (!Array.isArray(value.bundles) || value.bundles.length === 0) {
    fail("absence_bundles_empty");
  }
  const bundles = value.bundles.map((bundle, index) => {
    try {
      return decodeObservationBundle(bundle);
    } catch (error) {
      fail(`absence_bundle_invalid:${index}:${error.message}`);
    }
  });
  const analysisIds = new Set();
  for (const bundle of bundles) {
    if (analysisIds.has(bundle.analysisId)) {
      fail(`absence_duplicate_analysis_id:${bundle.analysisId}`);
    }
    analysisIds.add(bundle.analysisId);
  }
  return deepFreeze({bundles});
}

function decodeAbsenceOracle(value) {
  if (!isObject(value)) fail("absence_oracle_invalid");
  if (value.oracleVersion !== ORACLE_CONTRACT_VERSION &&
      value.oracleContractVersion !== ORACLE_CONTRACT_VERSION) {
    // Manifest uses oracleVersion; files use oracleVersion from exporter.
    if (value.oracleVersion !== 1) fail("absence_oracle_version_invalid");
  }
  if (value.providerId !== PROVIDER_ID) fail("absence_provider_id_invalid");
  if (value.providerVersion !== PROVIDER_VERSION) {
    fail("absence_provider_version_invalid");
  }
  requireText(value.scenarioId, "absence_scenario_id_required");
  if (!Array.isArray(value.invocations) || value.invocations.length === 0) {
    fail("absence_invocations_invalid");
  }
  const invocations = value.invocations.map((item, index) => {
    if (!isObject(item)) fail(`absence_invocation_invalid:${index}`);
    requireText(item.invocationId, "absence_invocation_id_required");
    if (!Number.isInteger(item.viewCount) || item.viewCount < 1) {
      fail(`absence_view_count_invalid:${item.invocationId}`);
    }
    if (!Array.isArray(item.orderedViewIds) ||
        item.orderedViewIds.length !== item.viewCount ||
        item.orderedViewIds.some((id) => typeof id !== "string" || !id)) {
      fail(`absence_ordered_view_ids_invalid:${item.invocationId}`);
    }
    if (new Set(item.orderedViewIds).size !== item.orderedViewIds.length) {
      fail(`absence_duplicate_view_id:${item.invocationId}`);
    }
    const providerInput = decodeAbsenceInput(item.providerInput);
    if (providerInput.bundles.length !== item.viewCount) {
      fail(`absence_bundle_view_count_mismatch:${item.invocationId}`);
    }
    if (!isObject(item.providerOutput)) {
      fail(`absence_provider_output_invalid:${item.invocationId}`);
    }
    return deepFreeze({
      invocationId: item.invocationId,
      viewCount: item.viewCount,
      orderedViewIds: [...item.orderedViewIds],
      providerInput,
      providerOutput: structuredClone(item.providerOutput),
      providerInputSha256: item.providerInputSha256,
      providerOutputSha256: item.providerOutputSha256,
    });
  });
  return deepFreeze({
    scenarioId: value.scenarioId,
    providerId: value.providerId,
    providerVersion: value.providerVersion,
    invocations,
  });
}

function qualifyAbsenceBundles(inputValue) {
  const input = decodeAbsenceInput(inputValue);
  const bundles = input.bundles;
  const pockets = qualifyProperty(POLICIES.visiblePocketStructure, bundles);
  const hood = qualifyProperty(POLICIES.hasHood, bundles);
  const closure = qualifyProperty(POLICIES.frontClosure, bundles);
  const stretch = qualifyProperty(POLICIES.visibleStretchCue, bundles);
  const primary = bundles[0];
  const qualifiedBundle = {
    analysisId: primary.analysisId,
    modelVersion: primary.modelVersion,
    sourceReference: primary.sourceReference,
    observedAt: primary.observedAt,
    quality: structuredClone(primary.quality),
  };
  const ordinary = {
    coverage: aggregateOrdinary(bundles.map((item) => item.coverage)),
    visibleBulk: aggregateOrdinary(bundles.map((item) => item.visibleBulk)),
    surfaceAppearance:
      aggregateOrdinary(bundles.map((item) => item.surfaceAppearance)),
    necklineShape: aggregateOrdinary(bundles.map((item) => item.necklineShape)),
    sportyCues: aggregateOrdinary(bundles.map((item) => item.sportyCues)),
    formalCues: aggregateOrdinary(bundles.map((item) => item.formalCues)),
    footwearConstruction:
      aggregateOrdinary(bundles.map((item) => item.footwearConstruction)),
    footwearFastening:
      aggregateOrdinary(bundles.map((item) => item.footwearFastening)),
    soleProfile: aggregateOrdinary(bundles.map((item) => item.soleProfile)),
    visibleTread: aggregateOrdinary(bundles.map((item) => item.visibleTread)),
    footwearUpperHeight:
      aggregateOrdinary(bundles.map((item) => item.footwearUpperHeight)),
  };
  for (const property of PROPERTY_ORDER) {
    if (property === "hasHood") {
      putObservation(qualifiedBundle, "hasHood", hood.qualified);
    } else if (property === "frontClosure") {
      putObservation(qualifiedBundle, "frontClosure", closure.qualified);
    } else if (property === "visiblePocketStructure") {
      putObservation(qualifiedBundle, "visiblePocketStructure",
        pockets.qualified);
    } else if (property === "visibleStretchCue") {
      putObservation(qualifiedBundle, "visibleStretchCue", stretch.qualified);
    } else if (Object.hasOwn(ordinary, property) &&
               ordinary[property] !== undefined) {
      putObservation(qualifiedBundle, property, ordinary[property]);
    }
  }
  return deepFreeze({
    qualifiedBundle,
    visiblePocketStructure: encodeAudit(pockets),
    hasHood: encodeAudit(hood),
    frontClosure: encodeAudit(closure),
    visibleStretchCue: encodeAudit(stretch),
  });
}

function qualifyProperty(policy, bundles) {
  const raw = [];
  for (const bundle of bundles) {
    if (Object.hasOwn(bundle, policy.property)) {
      raw.push(structuredClone(bundle[policy.property]));
    }
  }
  return qualify({policy, raw});
}

function qualify({policy, raw}) {
  const observed = raw.filter((item) => item.state === "observed");
  const positives = observed.filter(
    (item) => policy.isPositiveExistence(item.value));
  const negatives = observed.filter((item) => policy.isAbsence(item.value));

  if (positives.length > 0) {
    const values = new Set(positives.map((item) => item.value));
    if (values.size > 1) {
      return {
        property: policy.property,
        raw,
        qualified: unknownValue(),
        disposition: "conflict",
        reasonCodes: ["conflicting_positive_observations"],
      };
    }
    const winner = positives.reduce((left, right) =>
      left.confidence >= right.confidence ? left : right);
    return {
      property: policy.property,
      raw,
      qualified: structuredClone(winner),
      disposition: "qualified",
      reasonCodes: negatives.length === 0 ?
        ["positive_existence_observed"] :
        [
          "positive_existence_overrides_negative",
          "negative_absence_not_decisive",
        ],
    };
  }

  if (negatives.length === 0) {
    const allNotApplicable = raw.length > 0 &&
      raw.every((item) => item.state === "not_applicable");
    const allNotVisible = raw.length > 0 &&
      raw.every((item) => item.state === "not_visible");
    return {
      property: policy.property,
      raw,
      qualified: allNotApplicable ? notApplicableValue() :
        allNotVisible ? notVisibleValue() : unknownValue(),
      disposition: allNotApplicable ? "unchanged" :
        allNotVisible ? "degradedToNotVisible" : "unchanged",
      reasonCodes: [
        allNotApplicable ? "property_not_applicable" :
          allNotVisible ? "relevant_region_not_visible" :
            "no_observed_absence_evidence",
      ],
    };
  }

  if (!policy.absenceCanBeObserved) {
    return {
      property: policy.property,
      raw,
      qualified: unknownValue(),
      disposition: "degradedToUnknown",
      reasonCodes: ["absence_not_visually_provable"],
    };
  }

  const complete = negatives.filter((item) =>
    item.visibilityScope === "complete" &&
    SCOPE_RANK[item.visibilityScope] >=
      SCOPE_RANK[policy.minimumSingleViewScope]);
  const sufficient = negatives.filter((item) =>
    item.visibilityScope === "sufficient" ||
    item.visibilityScope === "complete");
  const canConfirm = complete.length > 0 ||
    sufficient.length >= policy.minimumConsistentSufficientViews;
  if (!canConfirm) {
    const noneVisible = negatives.every(
      (item) => item.visibilityScope === "not_visible");
    return {
      property: policy.property,
      raw,
      qualified: noneVisible ? notVisibleValue() : unknownValue(),
      disposition: noneVisible ?
        "degradedToNotVisible" : "degradedToUnknown",
      reasonCodes: [
        noneVisible ?
          "relevant_region_not_visible" :
          "insufficient_visibility_for_absence",
      ],
    };
  }

  const winner = negatives.reduce((left, right) =>
    left.confidence >= right.confidence ? left : right);
  const confidence = winner.confidence < policy.maximumAbsenceConfidence ?
    winner.confidence : policy.maximumAbsenceConfidence;
  const reasonCodes = [
    complete.length > 0 ?
      "complete_visibility_confirms_absence" :
      "multiple_sufficient_views_confirm_absence",
  ];
  if (confidence < winner.confidence) {
    reasonCodes.push("absence_confidence_calibrated");
  }
  return {
    property: policy.property,
    raw,
    qualified: observedValue({
      value: winner.value,
      confidence,
      visibilityScope: winner.visibilityScope,
    }),
    disposition: "qualified",
    reasonCodes,
  };
}

function aggregateOrdinary(input) {
  const values = input.filter((item) => item !== undefined);
  const observed = values.filter((item) => item.state === "observed");
  const distinct = new Set(observed.map((item) => item.value));
  if (distinct.size > 1) return unknownValue();
  if (observed.length > 0) {
    return structuredClone(observed.reduce((left, right) =>
      left.confidence >= right.confidence ? left : right));
  }
  if (values.some((item) => item.state === "unknown")) return unknownValue();
  if (values.some((item) => item.state === "not_visible")) {
    return notVisibleValue();
  }
  if (values.some((item) => item.state === "not_applicable")) {
    return notApplicableValue();
  }
  return undefined;
}

function encodeAudit(audit) {
  if (!DISPOSITIONS.has(audit.disposition)) {
    fail(`absence_disposition_invalid:${audit.property}`);
  }
  return {
    property: audit.property,
    raw: audit.raw.map(encodeObservation),
    qualified: encodeObservation(audit.qualified),
    disposition: audit.disposition,
    reasonCodes: [...audit.reasonCodes],
  };
}

function encodeObservation(value) {
  if (value.state === "observed") {
    const encoded = {
      state: "observed",
      value: value.value,
      confidence: value.confidence,
    };
    if (Object.hasOwn(value, "visibilityScope") &&
        value.visibilityScope != null) {
      encoded.visibilityScope = value.visibilityScope;
    }
    if (Object.hasOwn(value, "visibleRegions") &&
        Array.isArray(value.visibleRegions) &&
        value.visibleRegions.length > 0) {
      encoded.visibleRegions = [...value.visibleRegions].sort();
    }
    return encoded;
  }
  if (value.state === "unknown") {
    return {state: "unknown", confidence: 0};
  }
  if (value.state === "not_visible") {
    return {
      state: "not_visible",
      confidence: 0,
      visibilityScope: "not_visible",
    };
  }
  if (value.state === "not_applicable") {
    return {state: "not_applicable", confidence: 1};
  }
  fail(`absence_observation_state_invalid:${value.state}`);
}

function putObservation(bundle, property, value) {
  if (value === undefined) return;
  bundle[property] = encodeObservation(value);
}

function unknownValue() {
  return {state: "unknown", confidence: 0};
}
function notVisibleValue() {
  return {state: "not_visible", confidence: 0, visibilityScope: "not_visible"};
}
function notApplicableValue() {
  return {state: "not_applicable", confidence: 1};
}
function observedValue({value, confidence, visibilityScope}) {
  const result = {state: "observed", value, confidence};
  if (visibilityScope != null) result.visibilityScope = visibilityScope;
  return result;
}

function requireText(value, code) {
  if (typeof value !== "string" || value.length === 0) fail(code);
  return value;
}
function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function fail(code) {
  throw new Error(code);
}
function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    Object.values(value).forEach(deepFreeze);
  }
  return value;
}

module.exports = {
  PROVIDER_ID,
  PROVIDER_VERSION,
  ORACLE_CONTRACT_VERSION,
  ABSENCE_AUDIT_ORDER,
  POLICIES,
  decodeAbsenceInput,
  decodeAbsenceOracle,
  qualifyAbsenceBundles,
  qualify,
};
