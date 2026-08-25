"use strict";

const BACKEND_QUALIFICATION_INPUT_VERSION = 1;
const BACKEND_QUALIFICATION_REFERENCE_VERSION = 1;

const VALUE_STATES = new Set([
  "known",
  "unknown",
  "not_visible",
  "not_applicable",
]);

const QUALIFICATION_TIERS = new Set([
  "confirmed",
  "supported",
  "ambiguous",
  "insufficient_evidence",
  "invalid_input",
  "conflicting",
]);

function validateQualificationInput(value) {
  const errors = [];
  if (!isObject(value)) return ["input.root.invalid"];
  if (value.contractVersion !== BACKEND_QUALIFICATION_INPUT_VERSION) {
    errors.push("input.contractVersion.unsupported");
  }
  requireText(value.analysisId, "input.analysisId", errors);
  requireText(value.sourceReference, "input.sourceReference", errors);
  requireText(value.modelIdentifier, "input.modelIdentifier", errors);
  requirePositiveInteger(value.visionSchemaVersion,
    "input.visionSchemaVersion", errors);
  requireText(value.observedAt, "input.observedAt", errors);
  if (!isObject(value.quality)) errors.push("input.quality.invalid");
  if (!isObject(value.subjectAssessment)) {
    errors.push("input.subjectAssessment.invalid");
  }
  if (!isObject(value.observations)) errors.push("input.observations.invalid");
  if (!Array.isArray(value.identityCandidates)) {
    errors.push("input.identityCandidates.invalid");
  }
  if (!Array.isArray(value.validationErrors) ||
      !value.validationErrors.every(isText)) {
    errors.push("input.validationErrors.invalid");
  }
  if ("additionalResponses" in value) {
    if (!Array.isArray(value.additionalResponses)) {
      errors.push("input.additionalResponses.invalid");
    } else {
      value.additionalResponses.forEach((response, index) => {
        if (!isObject(response)) {
          errors.push(`input.additionalResponses.${index}.invalid`);
          return;
        }
        for (const property of [
          "analysisId",
          "sourceReference",
          "modelVersion",
          "observedAt",
        ]) {
          requireText(
            response[property],
            `input.additionalResponses.${index}.${property}`,
            errors,
          );
        }
        requirePositiveInteger(
          response.schemaVersion,
          `input.additionalResponses.${index}.schemaVersion`,
          errors,
        );
      });
    }
  }
  if ("resolvedProfile" in value) errors.push("input.resolvedProfile.forbidden");
  if ("machineEvidence" in value) errors.push("input.machineEvidence.forbidden");
  return errors.sort();
}

function validateQualificationReference(value) {
  const errors = [];
  if (!isObject(value)) return ["reference.root.invalid"];
  if (value.contractVersion !== BACKEND_QUALIFICATION_REFERENCE_VERSION) {
    errors.push("reference.contractVersion.unsupported");
  }
  requireText(value.fixtureId, "reference.fixtureId", errors);
  requireText(value.producer, "reference.producer", errors);
  requireText(value.producerVersion, "reference.producerVersion", errors);
  for (const property of [
    "observationEvidence",
    "capabilityEvidence",
    "machineEvidence",
    "omittedReasons",
  ]) {
    if (!Array.isArray(value[property])) {
      errors.push(`reference.${property}.invalid`);
    }
  }
  if (!isObject(value.identityQualification)) {
    errors.push("reference.identityQualification.invalid");
  } else if (!QUALIFICATION_TIERS.has(value.identityQualification.tier)) {
    errors.push("reference.identityQualification.tier.invalid");
  }
  if (!isObject(value.familyQualification)) {
    errors.push("reference.familyQualification.invalid");
  } else if (!QUALIFICATION_TIERS.has(value.familyQualification.tier)) {
    errors.push("reference.familyQualification.tier.invalid");
  }
  for (const [collectionName, collection] of [
    ["observationEvidence", value.observationEvidence],
    ["capabilityEvidence", value.capabilityEvidence],
    ["machineEvidence", value.machineEvidence],
  ]) {
    if (!Array.isArray(collection)) continue;
    collection.forEach((item, index) =>
      validateEvidence(item, `reference.${collectionName}.${index}`, errors));
  }
  if (Array.isArray(value.omittedReasons) &&
      !value.omittedReasons.every(isText)) {
    errors.push("reference.omittedReasons.item.invalid");
  }
  if ("resolvedProfile" in value) {
    errors.push("reference.resolvedProfile.forbidden");
  }
  return errors.sort();
}

function validateEvidence(value, path, errors) {
  if (!isObject(value)) {
    errors.push(`${path}.invalid`);
    return;
  }
  for (const property of ["id", "property", "source", "nature", "method"]) {
    requireText(value[property], `${path}.${property}`, errors);
  }
  if (!VALUE_STATES.has(value.valueState)) {
    errors.push(`${path}.valueState.invalid`);
  }
  if (typeof value.confidence !== "number" ||
      !Number.isFinite(value.confidence) ||
      value.confidence < 0 || value.confidence > 1) {
    errors.push(`${path}.confidence.invalid`);
  }
  if (!Array.isArray(value.supportingEvidenceIds) ||
      !value.supportingEvidenceIds.every(isText)) {
    errors.push(`${path}.supportingEvidenceIds.invalid`);
  }
  if (value.qualificationTier != null &&
      !QUALIFICATION_TIERS.has(value.qualificationTier)) {
    errors.push(`${path}.qualificationTier.invalid`);
  }
}

function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function isText(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function requireText(value, path, errors) {
  if (!isText(value)) errors.push(`${path}.required`);
}

function requirePositiveInteger(value, path, errors) {
  if (!Number.isInteger(value) || value <= 0) errors.push(`${path}.invalid`);
}

module.exports = {
  BACKEND_QUALIFICATION_INPUT_VERSION,
  BACKEND_QUALIFICATION_REFERENCE_VERSION,
  QUALIFICATION_TIERS,
  VALUE_STATES,
  validateQualificationInput,
  validateQualificationReference,
};
