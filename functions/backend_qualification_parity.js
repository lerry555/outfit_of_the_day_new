"use strict";

const fs = require("fs");
const path = require("path");
const {
  validateQualificationInput,
  validateQualificationReference,
} = require("./backend_qualification_contract");

const PARITY_KINDS = Object.freeze({
  BYTE_IDENTICAL: "byte_identical",
  SEMANTICALLY_IDENTICAL: "semantically_identical",
  INTENTIONAL_DIFFERENCE: "intentional_difference",
  FAILURE: "failure",
});

function loadGoldenManifest(manifestPath) {
  const absolute = path.resolve(manifestPath);
  const manifest = readJson(absolute);
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    throw new Error("golden_manifest_invalid");
  }
  if (manifest.manifestVersion !== 1) {
    throw new Error("golden_manifest_version_unsupported");
  }
  if (!Array.isArray(manifest.fixtures)) {
    throw new Error("golden_manifest_fixtures_invalid");
  }
  const catalogPath = path.resolve(path.dirname(absolute),
    String(manifest.sourceCatalog || ""));
  const catalog = readJson(catalogPath);
  if (!Array.isArray(catalog)) throw new Error("source_catalog_invalid");
  const catalogById = new Map(catalog.map((item) => [String(item.id), item]));
  const ids = new Set();
  const fixtures = manifest.fixtures.map((entry) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new Error("golden_fixture_invalid");
    }
    const id = String(entry.id || "");
    if (!id || ids.has(id)) throw new Error("golden_fixture_id_invalid");
    ids.add(id);
    const scenario = catalogById.get(id);
    if (!scenario) throw new Error(`golden_fixture_catalog_missing:${id}`);
    const goldenStatus = entry.goldenStatus;
    if (!["pending_dart_export", "ready"].includes(goldenStatus)) {
      throw new Error(`golden_fixture_status_invalid:${id}`);
    }
    if (goldenStatus === "pending_dart_export" &&
        (typeof entry.pendingReason !== "string" ||
         !entry.pendingReason.trim())) {
      throw new Error(`golden_fixture_pending_reason_required:${id}`);
    }
    let qualificationInput = null;
    let dartReference = null;
    if (goldenStatus === "ready") {
      qualificationInput = readJson(path.resolve(path.dirname(absolute),
        entry.qualificationInput));
      dartReference = readJson(path.resolve(path.dirname(absolute),
        entry.dartReference));
      const inputErrors = validateQualificationInput(qualificationInput);
      const referenceErrors = validateQualificationReference(dartReference);
      if (inputErrors.length || referenceErrors.length) {
        throw new Error(`golden_fixture_contract_invalid:${id}:` +
          [...inputErrors, ...referenceErrors].join(","));
      }
    }
    return Object.freeze({
      id,
      goldenStatus,
      pendingReason: goldenStatus === "pending_dart_export" ?
        entry.pendingReason : null,
      scenario: deepFreeze(structuredClone(scenario)),
      qualificationInput: qualificationInput && deepFreeze(qualificationInput),
      dartReference: dartReference && deepFreeze(dartReference),
    });
  });
  return Object.freeze({
    manifestVersion: manifest.manifestVersion,
    fixtureContractVersion: manifest.fixtureContractVersion,
    fixtures: Object.freeze(fixtures),
  });
}

function compareParity(expected, actual, {
  intentionalDifferences = [],
} = {}) {
  const expectedErrors = validateQualificationReference(expected);
  const actualErrors = validateQualificationReference(actual);
  if (expectedErrors.length || actualErrors.length) {
    return failure("contract_validation_failed", {
      expectedErrors,
      actualErrors,
    });
  }

  const expectedRaw = JSON.stringify(expected);
  const actualRaw = JSON.stringify(actual);
  if (expectedRaw === actualRaw) {
    return result(PARITY_KINDS.BYTE_IDENTICAL, []);
  }

  const normalizedExpected = normalizeReference(expected);
  const normalizedActual = normalizeReference(actual);
  const differences = diff(normalizedExpected, normalizedActual);
  if (differences.length === 0) {
    return result(PARITY_KINDS.SEMANTICALLY_IDENTICAL, []);
  }

  const declarations = validateIntentionalDifferences(intentionalDifferences);
  if (declarations.errors.length) {
    return failure("intentional_difference_declaration_invalid", {
      errors: declarations.errors,
      differences,
    });
  }
  const uncovered = differences.filter((difference) =>
    !declarations.paths.has(difference.path));
  if (uncovered.length === 0) {
    return result(PARITY_KINDS.INTENTIONAL_DIFFERENCE, differences, {
      intentionalDifferences,
    });
  }
  return failure("parity_difference", {differences, uncovered});
}

function compareFixtureParity(fixture, actual, options) {
  if (!fixture || fixture.goldenStatus !== "ready" ||
      fixture.dartReference == null) {
    return failure("golden_fixture_not_ready", {
      fixtureId: fixture && fixture.id,
    });
  }
  return compareParity(fixture.dartReference, actual, options);
}

function assertParity(expected, actual, options) {
  const report = compareParity(expected, actual, options);
  if (report.kind === PARITY_KINDS.FAILURE) {
    const error = new Error(`qualification_parity_failed:${report.reasonCode}`);
    error.report = report;
    throw error;
  }
  return report;
}

function normalizeReference(value) {
  const clone = structuredClone(value);
  for (const property of [
    "observationEvidence",
    "capabilityEvidence",
    "machineEvidence",
  ]) {
    clone[property] = clone[property]
      .map((item) => ({
        ...item,
        supportingEvidenceIds: [...item.supportingEvidenceIds].sort(),
      }))
      .sort(compareEvidence);
  }
  clone.omittedReasons = [...new Set(clone.omittedReasons)].sort();
  return canonicalize(clone);
}

function compareEvidence(left, right) {
  return String(left.id).localeCompare(String(right.id)) ||
    String(left.property).localeCompare(String(right.property));
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort()
      .map((key) => [key, canonicalize(value[key])]));
  }
  return value;
}

function diff(expected, actual, currentPath = "$") {
  if (Object.is(expected, actual)) return [];
  if (Array.isArray(expected) && Array.isArray(actual)) {
    const output = [];
    const length = Math.max(expected.length, actual.length);
    for (let index = 0; index < length; index++) {
      output.push(...diff(expected[index], actual[index],
        `${currentPath}[${index}]`));
    }
    return output;
  }
  if (isObject(expected) && isObject(actual)) {
    const keys = [...new Set([
      ...Object.keys(expected),
      ...Object.keys(actual),
    ])].sort();
    return keys.flatMap((key) =>
      diff(expected[key], actual[key], `${currentPath}.${key}`));
  }
  return [{path: currentPath, expected, actual}];
}

function validateIntentionalDifferences(declarations) {
  const paths = new Set();
  const errors = [];
  declarations.forEach((item, index) => {
    if (!isObject(item) ||
        typeof item.path !== "string" || !item.path.startsWith("$.") ||
        typeof item.reason !== "string" || !item.reason.trim() ||
        typeof item.decisionReference !== "string" ||
        !item.decisionReference.trim()) {
      errors.push(`intentionalDifferences.${index}.invalid`);
      return;
    }
    paths.add(item.path);
  });
  return {paths, errors};
}

function result(kind, differences, extra = {}) {
  return Object.freeze({kind, differences, ...extra});
}

function failure(reasonCode, extra) {
  return result(PARITY_KINDS.FAILURE, extra.differences || [], {
    reasonCode,
    ...extra,
  });
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
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

module.exports = {
  PARITY_KINDS,
  assertParity,
  compareFixtureParity,
  compareParity,
  loadGoldenManifest,
  normalizeReference,
};
