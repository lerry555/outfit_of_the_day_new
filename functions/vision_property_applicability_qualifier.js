"use strict";

const {
  decodeProviderInput: decodeObservationBundle,
} = require("./vision_observation_evidence_provider");

const PROVIDER_ID = "VisionPropertyApplicabilityQualifier";
const PROVIDER_VERSION = "applicability-v1";
const ORACLE_CONTRACT_VERSION = 1;

const GARMENT_ONLY = new Set([
  "coverage",
  "hasHood",
  "frontClosure",
  "visibleBulk",
  "necklineShape",
  "visiblePocketStructure",
]);
const FOOTWEAR_ONLY = new Set([
  "footwearConstruction",
  "footwearFastening",
  "soleProfile",
  "visibleTread",
  "footwearUpperHeight",
]);
const SHARED = new Set([
  "surfaceAppearance",
  "visibleStretchCue",
  "sportyCues",
  "formalCues",
]);
const PROPERTY_ORDER = Object.freeze([
  "coverage",
  "hasHood",
  "frontClosure",
  "visibleBulk",
  "surfaceAppearance",
  "necklineShape",
  "visiblePocketStructure",
  "visibleStretchCue",
  "sportyCues",
  "formalCues",
  "footwearConstruction",
  "footwearFastening",
  "soleProfile",
  "visibleTread",
  "footwearUpperHeight",
]);
const SUBJECT_DOMAINS = new Set([
  "garment_upper",
  "garment_lower",
  "garment_outerwear",
  "footwear",
  "accessory",
  "unknown",
  "mixed",
]);

function decodeApplicabilityInput(value) {
  if (!isObject(value)) fail("applicability_input_invalid");
  const bundle = decodeObservationBundle(value.bundle);
  if (!isObject(value.subject) ||
      !SUBJECT_DOMAINS.has(value.subject.subjectDomain)) {
    fail("applicability_subject_domain_invalid");
  }
  return deepFreeze({
    bundle,
    subject: {
      subjectDomain: value.subject.subjectDomain,
    },
  });
}

function qualifyApplicability(inputValue) {
  const input = decodeApplicabilityInput(inputValue);
  const qualifiedBundle = {
    analysisId: input.bundle.analysisId,
    modelVersion: input.bundle.modelVersion,
    sourceReference: input.bundle.sourceReference,
    observedAt: input.bundle.observedAt,
    quality: structuredClone(input.bundle.quality),
  };
  const properties = {};
  for (const property of PROPERTY_ORDER) {
    if (!Object.hasOwn(input.bundle, property)) continue;
    const state = applicabilityState(property, input.subject.subjectDomain);
    properties[property] = {
      property,
      state,
      subjectDomain: input.subject.subjectDomain,
      reasonCodes: [state === "applicable" ?
        "property_applicable_to_subject_domain" :
        state === "notApplicable" ?
          "property_not_applicable_to_subject_domain" :
          "subject_domain_does_not_authorize_property"],
    };
    qualifiedBundle[property] = state === "applicable" ?
      structuredClone(input.bundle[property]) :
      {state: "not_applicable", confidence: 1};
  }
  return deepFreeze({qualifiedBundle, properties});
}

function decodeApplicabilityOracle(value) {
  if (!isObject(value) ||
      value.oracleContractVersion !== ORACLE_CONTRACT_VERSION) {
    fail("applicability_oracle_contract_invalid");
  }
  if (value.providerId !== PROVIDER_ID) fail("applicability_provider_invalid");
  if (value.providerVersion !== PROVIDER_VERSION) {
    fail("applicability_version_invalid");
  }
  if (typeof value.scenarioId !== "string" || !value.scenarioId ||
      !Array.isArray(value.invocations) || value.invocations.length === 0) {
    fail("applicability_oracle_root_invalid");
  }
  return deepFreeze({
    scenarioId: value.scenarioId,
    invocations: value.invocations.map((item, index) => {
      if (!isObject(item) || item.viewIndex !== index ||
          typeof item.viewId !== "string" ||
          !isObject(item.providerOutput)) {
        fail(`applicability_invocation_invalid:${index}`);
      }
      return {
        viewIndex: item.viewIndex,
        viewId: item.viewId,
        providerInput: decodeApplicabilityInput(item.providerInput),
        providerOutput: structuredClone(item.providerOutput),
      };
    }),
  });
}

function applicabilityState(property, domain) {
  if (domain === "unknown" || domain === "mixed") {
    return SHARED.has(property) ? "uncertain" : "notApplicable";
  }
  if (property === "hasHood" || property === "necklineShape") {
    return ["garment_upper", "garment_outerwear"].includes(domain) ?
      "applicable" : "notApplicable";
  }
  if (GARMENT_ONLY.has(property)) {
    return domain.startsWith("garment_") ? "applicable" : "notApplicable";
  }
  if (FOOTWEAR_ONLY.has(property)) {
    return domain === "footwear" ? "applicable" : "notApplicable";
  }
  return SHARED.has(property) ? "applicable" : "uncertain";
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
  ORACLE_CONTRACT_VERSION,
  PROPERTY_ORDER,
  PROVIDER_ID,
  PROVIDER_VERSION,
  decodeApplicabilityInput,
  decodeApplicabilityOracle,
  qualifyApplicability,
};
