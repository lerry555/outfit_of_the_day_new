"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  CONTRACT_VERSION,
  STAGE_ID,
  STAGE_VERSION,
  prepareVisionIdentityQualificationInput,
} = require("./prepare_vision_identity_qualification_input");

const DEFAULT_IDENTITY_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_identity_qualification_oracle_manifest.json");
const DEFAULT_CONSISTENCY_ROOT = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/provider_oracles/canonical_consistency_v1");
const SOURCE = path.resolve(__dirname,
  "prepare_vision_identity_qualification_input.js");
const TAXONOMY_SOURCE = path.resolve(__dirname,
  "../lib/data/clothing_knowledge_base.dart");
const DART_SOURCE =
  "lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart";

function runIdentityQualificationInputParity({
  identityManifestPath = DEFAULT_IDENTITY_MANIFEST,
  consistencyOracleRoot = DEFAULT_CONSISTENCY_ROOT,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(identityManifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== "VisionIdentityQualification" ||
      manifest.providerVersion !== "vision-identity-qualification-v1") {
    throw new Error("identity_input_oracle_integrity_failure");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) {
    throw new Error("identity_input_oracle_integrity_failure");
  }
  const fixtureRoot = path.dirname(path.dirname(identityManifestPath));
  const allowedCanonicalTypes = loadAllowedCanonicalTypes(TAXONOMY_SOURCE);
  const taxonomyRegistrySha256 = manifest.taxonomyRegistrySha256;
  const scenarios = ready.map((entry) => {
    const oracleBytes = fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(oracleBytes) !== entry.oracleSha256) {
      throw new Error(`identity_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = JSON.parse(oracleBytes.toString("utf8"));
    if (!Array.isArray(oracle.invocations) || oracle.invocations.length !== 1) {
      throw new Error(`identity_invocation_count_invalid:${entry.scenarioId}`);
    }
    const expected = oracle.invocations[0].providerInput;
    const parserPath = path.join(fixtureRoot, "backend_qualification",
      "parser", `${entry.scenarioId}.parser.json`);
    const parserBytes = fs.readFileSync(parserPath);
    if (sha256(parserBytes) !== entry.sourceParserFixtureSha256) {
      throw new Error(`parser_sha_mismatch:${entry.scenarioId}`);
    }
    const parser = JSON.parse(parserBytes.toString("utf8"));
    const consistencyOracle = JSON.parse(fs.readFileSync(path.join(
      consistencyOracleRoot, `${entry.scenarioId}.oracle.json`), "utf8"));
    const prepared = prepareVisionIdentityQualificationInput({
      responses: parser.views.map((view) => view.response),
      multiViewSubjectBinding: parser.multiViewSubjectBinding ?? null,
      observationEvidence: consistencyOracle.providerInput.observationEvidence,
      allowedCanonicalTypes,
      taxonomyRegistrySha256,
      expectedTaxonomyRegistrySha256: taxonomyRegistrySha256,
    });
    const differences = diff(expected, prepared);
    const fieldParity = {
      identityEvidence: diff(expected.identityEvidence,
        prepared.identityEvidence).length === 0,
      declaredByEvidenceId: diff(expected.declaredByEvidenceId,
        prepared.declaredByEvidenceId).length === 0,
      consistency: diff(expected.consistency, prepared.consistency)
        .length === 0,
      inputIsValid: expected.inputIsValid === prepared.inputIsValid,
    };
    return {
      scenarioId: entry.scenarioId,
      passed: differences.length === 0,
      differences,
      fieldParity,
      outputSha256: sha256(canonicalBytes(prepared)),
      expectedInputSha256: sha256(canonicalBytes(expected)),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  const passed = scenarios.filter((item) => item.passed).length;
  const rerun = runIdentityQualificationInputParityOnce({
    identityManifestPath,
    consistencyOracleRoot,
  });
  const deterministic = scenarios.every((item, index) =>
    item.outputSha256 === rerun.scenarios[index].outputSha256);
  return deepFreeze({
    stageId: STAGE_ID,
    stageVersion: STAGE_VERSION,
    contractVersion: CONTRACT_VERSION,
    scenarioCount: scenarios.length,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    parityStatus: passed === 8 && deterministic ?
      "orchestration_ready" : "parity_failed",
    deterministic,
    scenarios,
    taxonomyRegistrySha256,
    nodeImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dartCallSiteSha256: manifest.callSitePreparationSha256,
  });
}

function runIdentityQualificationInputParityOnce({
  identityManifestPath,
  consistencyOracleRoot,
}) {
  const manifest = JSON.parse(fs.readFileSync(identityManifestPath, "utf8"));
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const fixtureRoot = path.dirname(path.dirname(identityManifestPath));
  const allowedCanonicalTypes = loadAllowedCanonicalTypes(TAXONOMY_SOURCE);
  const taxonomyRegistrySha256 = manifest.taxonomyRegistrySha256;
  const scenarios = ready.map((entry) => {
    const oracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath), "utf8"));
    const parser = JSON.parse(fs.readFileSync(path.join(fixtureRoot,
      "backend_qualification", "parser",
      `${entry.scenarioId}.parser.json`), "utf8"));
    const consistencyOracle = JSON.parse(fs.readFileSync(path.join(
      consistencyOracleRoot, `${entry.scenarioId}.oracle.json`), "utf8"));
    const prepared = prepareVisionIdentityQualificationInput({
      responses: parser.views.map((view) => view.response),
      multiViewSubjectBinding: parser.multiViewSubjectBinding ?? null,
      observationEvidence: consistencyOracle.providerInput.observationEvidence,
      allowedCanonicalTypes,
      taxonomyRegistrySha256,
      expectedTaxonomyRegistrySha256: taxonomyRegistrySha256,
    });
    return {
      scenarioId: entry.scenarioId,
      outputSha256: sha256(canonicalBytes(prepared)),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  return {scenarios};
}

function buildIdentityQualificationInputParityEntry(report) {
  return {
    stageId: report.stageId,
    stageVersion: report.stageVersion,
    contractVersion: report.contractVersion,
    kind: "orchestration_stage",
    dartSource: DART_SOURCE,
    nodeSource: "functions/prepare_vision_identity_qualification_input.js",
    inputContract: "prepare_vision_identity_qualification_input/v1",
    outputContract: "BackendIdentityQualificationInput/v1",
    identityOracleBinding: "vision-identity-qualification-v1",
    scenarioCount: report.scenarioCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    parityStatus: report.parityStatus,
    deterministic: report.deterministic,
    nodeImplementationSha256: report.nodeImplementationSha256,
    dartCallSiteSha256: report.dartCallSiteSha256,
    taxonomyRegistrySha256: report.taxonomyRegistrySha256,
    outputSha256ByScenario: Object.fromEntries(report.scenarios.map(
      (item) => [item.scenarioId, item.outputSha256])),
  };
}

function loadAllowedCanonicalTypes(taxonomyPath) {
  const source = fs.readFileSync(taxonomyPath, "utf8");
  const matches = [...source.matchAll(/canonicalType:\s*'([^']+)'/g)]
    .map((item) => item[1]);
  if (matches.length === 0) fail("taxonomy_allow_list_empty");
  return [...new Set(matches)].sort();
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
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
  buildIdentityQualificationInputParityEntry,
  loadAllowedCanonicalTypes,
  runIdentityQualificationInputParity,
};
