"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {
  validateQualificationInput,
  validateQualificationReference,
} = require("./backend_qualification_contract");
const {
  canonicalBytes,
  diff,
} = require("./backend_provider_oracle_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  UPSTREAM_PROVIDER_ID,
  UPSTREAM_PROVIDER_VERSION,
  inferCapabilities,
} = require("./wardrobe_capability_inference_provider");

const FIXTURE_ROOT = path.resolve(__dirname, "../test/fixtures");
const GOLDEN_MANIFEST = path.join(
  FIXTURE_ROOT, "backend_qualification_golden_manifest.json");
const ORACLE_MANIFEST = path.join(
  FIXTURE_ROOT,
  "backend_qualification/backend_provider_oracle_manifest.json");
const PROVIDER_SOURCE = path.resolve(
  __dirname, "wardrobe_capability_inference_provider.js");
const DART_PROVIDER_SOURCE = "lib/domain/wardrobe_profile/" +
  "wardrobe_capability_inference_provider.dart";

function runCapabilityProviderParity({
  goldenManifestPath = GOLDEN_MANIFEST,
  oracleManifestPath = ORACLE_MANIFEST,
} = {}) {
  const goldenManifest = readJson(goldenManifestPath);
  const oracleManifest = readJson(oracleManifestPath);
  validateManifests(goldenManifest, oracleManifest);
  const goldenById = new Map(goldenManifest.fixtures
    .filter((item) => item.goldenStatus === "ready")
    .map((item) => [item.id, item]));
  const scenarios = [];
  for (const oracleEntry of oracleManifest.fixtures
    .filter((item) => item.status === "ready")) {
    const goldenEntry = goldenById.get(oracleEntry.scenarioId);
    if (!goldenEntry) {
      throw new Error(`capability_golden_missing:${oracleEntry.scenarioId}`);
    }
    scenarios.push(runScenario(oracleEntry, goldenEntry, {
      fixtureRoot: path.dirname(goldenManifestPath),
    }));
  }
  scenarios.sort((left, right) =>
    left.scenarioId.localeCompare(right.scenarioId));
  const passed = scenarios.filter((item) => item.passed).length;
  return deepFreeze({
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    upstreamProviderId: UPSTREAM_PROVIDER_ID,
    upstreamProviderVersion: UPSTREAM_PROVIDER_VERSION,
    scenarioCount: scenarios.length,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    parityStatus: passed === 8 && scenarios.length === 8 ?
      "parity_ready" : "parity_failed",
    deterministicInputs: true,
    scenarios,
  });
}

function runScenario(oracleEntry, goldenEntry, {fixtureRoot}) {
  const scenarioId = oracleEntry.scenarioId;
  const oraclePath = path.resolve(fixtureRoot, oracleEntry.oraclePath);
  const inputPath = path.resolve(fixtureRoot, goldenEntry.qualificationInput);
  const goldenPath = path.resolve(fixtureRoot, goldenEntry.dartReference);
  const oracleBytes = fs.readFileSync(oraclePath);
  const inputBytes = fs.readFileSync(inputPath);
  const goldenBytes = fs.readFileSync(goldenPath);
  if (sha256(oracleBytes) !== oracleEntry.oracleSha256) {
    throw new Error(`oracle_sha256_mismatch:${scenarioId}`);
  }
  const oracle = JSON.parse(oracleBytes);
  const input = JSON.parse(inputBytes);
  const golden = JSON.parse(goldenBytes);
  validateBinding(scenarioId, oracleEntry, oracle, input, golden, {
    inputSha256: sha256(inputBytes),
    goldenSha256: sha256(goldenBytes),
  });

  const providerInput = buildProviderInput(oracle, input);
  const inputBefore = canonicalBytes(providerInput);
  const runtimeOutput = inferCapabilities(providerInput);
  if (!canonicalBytes(providerInput).equals(inputBefore)) {
    throw new Error(`capability_input_mutated:${scenarioId}`);
  }
  const actual = projectCapabilityEvidence(runtimeOutput);
  const expected = projectCapabilityEvidence(golden.capabilityEvidence);
  const structuralDifferences = structuralDiff(expected, actual);
  const semanticDifferences = diff(expected, actual)
    .map((item) => classifyDifference(item));
  const canonicalDifferences = diff(
    canonicalize(expected), canonicalize(actual))
    .map((item) => classifyDifference(item));
  const differences = uniqueDifferences([
    ...structuralDifferences,
    ...semanticDifferences,
    ...canonicalDifferences,
  ]);
  return deepFreeze({
    scenarioId,
    passed: differences.length === 0,
    structuralPassed: structuralDifferences.length === 0,
    semanticPassed: semanticDifferences.length === 0,
    canonicalPassed: canonicalDifferences.length === 0,
    differences,
    invocationCount: 1,
    viewCount: oracle.orderedViewProvenance.length,
    outputCount: actual.length,
    outputSha256: sha256(canonicalBytes(actual)),
    oracleSha256: sha256(oracleBytes),
    qualificationInputSha256: sha256(inputBytes),
    dartGoldenSha256: sha256(goldenBytes),
  });
}

function buildProviderInput(oracle, qualificationInput) {
  const observationEvidence = structuredClone(oracle.providerOutput)
    .sort((left, right) => left.id.localeCompare(right.id));
  return {
    oracleContractVersion: oracle.oracleContractVersion,
    upstreamProviderId: oracle.providerId,
    upstreamProviderVersion: oracle.providerVersion,
    qualificationInputContractVersion: qualificationInput.contractVersion,
    providerVersion: PROVIDER_VERSION,
    analysisId: qualificationInput.analysisId,
    observedAt: qualificationInput.observedAt,
    sourceReference: oracle.providerInput.sourceReference,
    observationEvidence,
  };
}

function projectCapabilityEvidence(evidence) {
  if (!Array.isArray(evidence)) {
    throw new Error("capability_projection_input_invalid");
  }
  return evidence.map((item, index) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error(`capability_projection_item_invalid:${index}`);
    }
    const projected = {};
    for (const key of [
      "id",
      "property",
      "value",
      "valueState",
      "source",
      "nature",
      "confidence",
      "method",
      "supportingEvidenceIds",
    ]) {
      if (!Object.hasOwn(item, key)) {
        throw new Error(`capability_projection_field_missing:${index}:${key}`);
      }
      projected[key] = structuredClone(item[key]);
    }
    return projected;
  });
}

function validateBinding(
    scenarioId, entry, oracle, input, golden,
    {inputSha256, goldenSha256}) {
  if (oracle.scenarioId !== scenarioId || golden.fixtureId !== scenarioId) {
    throw new Error(`scenario_binding_mismatch:${scenarioId}`);
  }
  if (oracle.oracleContractVersion !== 1 ||
      oracle.providerId !== UPSTREAM_PROVIDER_ID ||
      oracle.providerVersion !== UPSTREAM_PROVIDER_VERSION) {
    throw new Error(`upstream_contract_mismatch:${scenarioId}`);
  }
  if (oracle.providerInputSha256 !== entry.providerInputSha256 ||
      oracle.providerOutputSha256 !== entry.providerOutputSha256) {
    throw new Error(`oracle_inner_hash_binding_mismatch:${scenarioId}`);
  }
  // The outer byte hash authenticates the oracle file and the manifest binds
  // its inner output hash. Re-encoding decoded JSON here would collapse Dart
  // `1.0` to JavaScript `1`, so it is intentionally not used as a byte check.
  if (inputSha256 !== oracle.sourceQualificationInputSha256) {
    throw new Error(`qualification_input_sha256_mismatch:${scenarioId}`);
  }
  if (goldenSha256 !== oracle.sourceDartReferenceGoldenSha256 ||
      goldenSha256 !== entry.sourceGoldenSha256) {
    throw new Error(`dart_golden_sha256_mismatch:${scenarioId}`);
  }
  const inputErrors = validateQualificationInput(input);
  if (inputErrors.length) {
    throw new Error(`qualification_input_invalid:${scenarioId}:` +
      inputErrors.join(","));
  }
  const referenceErrors = validateQualificationReference(golden);
  if (referenceErrors.length) {
    throw new Error(`dart_reference_invalid:${scenarioId}:` +
      referenceErrors.join(","));
  }
  if (golden.producerVersion !== "qualification-v1") {
    throw new Error(`qualification_producer_version_mismatch:${scenarioId}`);
  }
  if (input.analysisId !== oracle.providerInput.analysisId) {
    throw new Error(`analysis_id_mismatch:${scenarioId}`);
  }
  if (input.observedAt !== oracle.providerInput.observedAt) {
    throw new Error(`observed_at_mismatch:${scenarioId}`);
  }
  const callSiteObservationEvidence = structuredClone(oracle.providerOutput)
    .sort((left, right) => left.id.localeCompare(right.id));
  if (diff(golden.observationEvidence, callSiteObservationEvidence).length) {
    throw new Error(`observation_projection_mismatch:${scenarioId}`);
  }
}

function validateManifests(goldenManifest, oracleManifest) {
  if (!goldenManifest || goldenManifest.manifestVersion !== 1 ||
      goldenManifest.fixtureContractVersion !== 1 ||
      !Array.isArray(goldenManifest.fixtures)) {
    throw new Error("golden_manifest_invalid");
  }
  if (!oracleManifest || oracleManifest.manifestVersion !== 1 ||
      oracleManifest.oracleContractVersion !== 1 ||
      oracleManifest.providerId !== UPSTREAM_PROVIDER_ID ||
      oracleManifest.providerVersion !== UPSTREAM_PROVIDER_VERSION ||
      !Array.isArray(oracleManifest.fixtures)) {
    throw new Error("oracle_manifest_invalid");
  }
  const readyOracles = oracleManifest.fixtures
    .filter((item) => item.status === "ready");
  const readyGoldens = goldenManifest.fixtures
    .filter((item) => item.goldenStatus === "ready");
  if (readyOracles.length !== 8 || readyGoldens.length !== 8) {
    throw new Error("capability_ready_fixture_count_invalid");
  }
}

function buildCapabilityProviderParityEntry(report) {
  if (!report || report.providerId !== PROVIDER_ID) {
    throw new Error("capability_parity_report_invalid");
  }
  return {
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    dartProviderSource: DART_PROVIDER_SOURCE,
    nodeProviderSource:
      "functions/wardrobe_capability_inference_provider.js",
    inputContract: "capability_provider_binding/v1",
    outputContract: "List<ProfileEvidence>/capability_projection_v1",
    oracleContractVersion: 1,
    scenarioCount: report.scenarioCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    parityStatus: report.parityStatus,
    canonicalImplementationSha256: sha256(
      fs.readFileSync(PROVIDER_SOURCE)),
    dependencyVersions: {
      backendQualificationInputContract: 1,
      backendQualificationReferenceContract: 1,
      upstreamProviderOracleContract: 1,
      upstreamProviderVersion: UPSTREAM_PROVIDER_VERSION,
    },
    outputSha256ByScenario: Object.fromEntries(report.scenarios.map(
      (item) => [item.scenarioId, item.outputSha256])),
  };
}

function structuralDiff(expected, actual, currentPath = "$") {
  if (Array.isArray(expected) && Array.isArray(actual)) {
    if (expected.length !== actual.length) {
      return [difference(currentPath, expected.length, actual.length,
        "ordering_mismatch", "output_shape")];
    }
    return expected.flatMap((item, index) =>
      structuralDiff(item, actual[index], `${currentPath}[${index}]`));
  }
  if (isObject(expected) && isObject(actual)) {
    const expectedKeys = Object.keys(expected).sort();
    const actualKeys = Object.keys(actual).sort();
    if (JSON.stringify(expectedKeys) !== JSON.stringify(actualKeys)) {
      return [difference(currentPath, expectedKeys, actualKeys,
        "missing_field", "output_shape")];
    }
    return expectedKeys.flatMap((key) =>
      structuralDiff(expected[key], actual[key], `${currentPath}.${key}`));
  }
  if (typeof expected !== typeof actual ||
      Array.isArray(expected) !== Array.isArray(actual) ||
      (expected === null) !== (actual === null)) {
    return [difference(currentPath, typeOf(expected), typeOf(actual),
      "decision_mismatch", "output_shape")];
  }
  return [];
}

function classifyDifference(item) {
  const jsonPath = item.jsonPath;
  let mismatchType = item.mismatchType;
  let possibleSourceCategory = "provider_semantics";
  if (jsonPath.endsWith(".supportingEvidenceIds")) {
    mismatchType = "evidence_link_mismatch";
    possibleSourceCategory = "evidence_provenance";
  } else if (jsonPath.endsWith(".valueState")) {
    mismatchType = "decision_mismatch";
  } else if (jsonPath.includes("observedAt")) {
    mismatchType = "timestamp_mismatch";
    possibleSourceCategory = "fixture_binding";
  } else if (jsonPath.toLowerCase().includes("version")) {
    mismatchType = "version_mismatch";
    possibleSourceCategory = "contract_binding";
  }
  return difference(jsonPath, item.expected, item.actual,
    mismatchType, possibleSourceCategory);
}

function difference(
    jsonPath, expected, actual, mismatchType, possibleSourceCategory) {
  return Object.freeze({
    jsonPath,
    expected,
    actual,
    mismatchType,
    possibleSourceCategory,
  });
}
function uniqueDifferences(items) {
  const seen = new Set();
  return items.filter((item) => {
    const key = JSON.stringify(item);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (isObject(value)) {
    return Object.fromEntries(Object.keys(value).sort()
      .map((key) => [key, canonicalize(value[key])]));
  }
  return Object.is(value, -0) ? 0 : value;
}
function typeOf(value) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}
function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
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
  GOLDEN_MANIFEST,
  ORACLE_MANIFEST,
  buildCapabilityProviderParityEntry,
  buildProviderInput,
  projectCapabilityEvidence,
  runCapabilityProviderParity,
};
