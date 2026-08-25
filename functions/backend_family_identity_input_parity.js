"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  CONTRACT_VERSION,
  STAGE_ID,
  STAGE_VERSION,
  prepareVisionFamilyIdentityInput,
} = require("./prepare_vision_family_identity_input");
const {
  loadAllowedCanonicalTypes,
} = require("./backend_identity_qualification_input_parity");

const DEFAULT_FAMILY_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_family_identity_oracle_manifest.json");
const DEFAULT_IDENTITY_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_identity_qualification_oracle_manifest.json");
const SOURCE = path.resolve(__dirname,
  "prepare_vision_family_identity_input.js");
const TAXONOMY_SOURCE = path.resolve(__dirname,
  "../lib/data/clothing_knowledge_base.dart");
const FAMILY_TAXONOMY_SOURCE = path.resolve(__dirname,
  "../lib/domain/wardrobe_profile/vision_family_identity.dart");
const DART_SOURCE =
  "lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart";

function runFamilyIdentityInputParity({
  familyManifestPath = DEFAULT_FAMILY_MANIFEST,
  identityManifestPath = DEFAULT_IDENTITY_MANIFEST,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(familyManifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== "VisionFamilyIdentityResolver" ||
      manifest.providerVersion !== "vision-family-identity-resolver-v1") {
    throw new Error("family_input_oracle_integrity_failure");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  if (ready.length !== 8) {
    throw new Error("family_input_oracle_integrity_failure");
  }
  const identityManifest = JSON.parse(
    fs.readFileSync(identityManifestPath, "utf8"));
  if (identityManifest.providerId !== "VisionIdentityQualification" ||
      identityManifest.readyScenarioCount !== 8) {
    throw new Error("family_input_oracle_integrity_failure");
  }
  const fixtureRoot = path.dirname(path.dirname(familyManifestPath));
  const allowedCanonicalTypes = loadAllowedCanonicalTypes(TAXONOMY_SOURCE);
  const familyTaxonomySha256 = sha256(fs.readFileSync(FAMILY_TAXONOMY_SOURCE));
  if (familyTaxonomySha256 !== manifest.taxonomyRegistrySha256 ||
      familyTaxonomySha256 !== manifest.providerImplementationSha256) {
    throw new Error("family_taxonomy_sha_integrity_failure");
  }
  const identityById = new Map(
    identityManifest.fixtures.filter((item) => item.status === "ready")
      .map((item) => [item.scenarioId, item]));
  const scenarios = ready.map((entry) => {
    const oracleBytes = fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(oracleBytes) !== entry.oracleSha256) {
      throw new Error(`family_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = JSON.parse(oracleBytes.toString("utf8"));
    if (!Array.isArray(oracle.invocations) || oracle.invocations.length !== 1) {
      throw new Error(`family_invocation_count_invalid:${entry.scenarioId}`);
    }
    const expected = oracle.invocations[0].providerInput;
    const parserPath = path.join(fixtureRoot, "backend_qualification",
      "parser", `${entry.scenarioId}.parser.json`);
    const parserBytes = fs.readFileSync(parserPath);
    if (sha256(parserBytes) !== entry.sourceParserFixtureSha256) {
      throw new Error(`parser_sha_mismatch:${entry.scenarioId}`);
    }
    const parser = JSON.parse(parserBytes.toString("utf8"));
    const identityEntry = identityById.get(entry.scenarioId);
    if (!identityEntry) {
      throw new Error(`identity_oracle_missing:${entry.scenarioId}`);
    }
    const identityOracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, identityEntry.oraclePath), "utf8"));
    const identityReport =
      identityOracle.invocations[0].providerOutput.report;
    const prepared = prepareVisionFamilyIdentityInput({
      responses: parser.views.map((view) => view.response),
      multiViewSubjectBinding: parser.multiViewSubjectBinding ?? null,
      identityQualificationReport: {
        selectedCanonicalType: identityReport.selectedCanonicalType ?? null,
        state: identityReport.state,
      },
      allowedCanonicalTypes,
      familyTaxonomySha256,
      expectedFamilyTaxonomySha256: manifest.taxonomyRegistrySha256,
    });
    const differences = diff(expected, prepared);
    const fieldParity = {
      identityCandidates: diff(expected.identityCandidates,
        prepared.identityCandidates).length === 0,
      observations: diff(expected.observations,
        prepared.observations).length === 0,
      resolvedCanonicalSubtype:
        expected.resolvedCanonicalSubtype ===
          prepared.resolvedCanonicalSubtype,
      inputAssessment: expected.inputAssessment === prepared.inputAssessment,
      subjectAssessment: diff(expected.subjectAssessment,
        prepared.subjectAssessment).length === 0,
      hasWholeItemSilhouette:
        expected.hasWholeItemSilhouette === prepared.hasWholeItemSilhouette,
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
  const rerun = runFamilyIdentityInputParityOnce({
    familyManifestPath,
    identityManifestPath,
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
    familyTaxonomySha256,
    nodeImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dartCallSiteSha256: manifest.callSitePreparationSha256,
  });
}

function runFamilyIdentityInputParityOnce({
  familyManifestPath,
  identityManifestPath,
}) {
  const manifest = JSON.parse(fs.readFileSync(familyManifestPath, "utf8"));
  const identityManifest = JSON.parse(
    fs.readFileSync(identityManifestPath, "utf8"));
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const fixtureRoot = path.dirname(path.dirname(familyManifestPath));
  const allowedCanonicalTypes = loadAllowedCanonicalTypes(TAXONOMY_SOURCE);
  const familyTaxonomySha256 = sha256(fs.readFileSync(FAMILY_TAXONOMY_SOURCE));
  const identityById = new Map(
    identityManifest.fixtures.filter((item) => item.status === "ready")
      .map((item) => [item.scenarioId, item]));
  const scenarios = ready.map((entry) => {
    const oracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath), "utf8"));
    const parser = JSON.parse(fs.readFileSync(path.join(fixtureRoot,
      "backend_qualification", "parser",
      `${entry.scenarioId}.parser.json`), "utf8"));
    const identityOracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, identityById.get(entry.scenarioId).oraclePath),
      "utf8"));
    const identityReport =
      identityOracle.invocations[0].providerOutput.report;
    const prepared = prepareVisionFamilyIdentityInput({
      responses: parser.views.map((view) => view.response),
      multiViewSubjectBinding: parser.multiViewSubjectBinding ?? null,
      identityQualificationReport: {
        selectedCanonicalType: identityReport.selectedCanonicalType ?? null,
        state: identityReport.state,
      },
      allowedCanonicalTypes,
      familyTaxonomySha256,
      expectedFamilyTaxonomySha256: manifest.taxonomyRegistrySha256,
    });
    return {
      scenarioId: entry.scenarioId,
      outputSha256: sha256(canonicalBytes(prepared)),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  return {scenarios};
}

function buildFamilyIdentityInputParityEntry(report) {
  return {
    stageId: report.stageId,
    stageVersion: report.stageVersion,
    contractVersion: report.contractVersion,
    kind: "orchestration_stage",
    dartSource: DART_SOURCE,
    nodeSource: "functions/prepare_vision_family_identity_input.js",
    inputContract: "prepare_vision_family_identity_input/v1",
    outputContract: "BackendFamilyIdentityInput/v1",
    familyOracleBinding: "vision-family-identity-resolver-v1",
    identityOracleBinding: "vision-identity-qualification-v1",
    scenarioCount: report.scenarioCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    parityStatus: report.parityStatus,
    deterministic: report.deterministic,
    nodeImplementationSha256: report.nodeImplementationSha256,
    dartCallSiteSha256: report.dartCallSiteSha256,
    familyTaxonomySha256: report.familyTaxonomySha256,
    outputSha256ByScenario: Object.fromEntries(report.scenarios.map(
      (item) => [item.scenarioId, item.outputSha256])),
  };
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

module.exports = {
  buildFamilyIdentityInputParityEntry,
  runFamilyIdentityInputParity,
};
