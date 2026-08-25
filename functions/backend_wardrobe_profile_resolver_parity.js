"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {canonicalBytes, diff} = require("./backend_provider_oracle_parity");
const {
  ORACLE_CONTRACT_VERSION,
  PROVIDER_ID,
  PROVIDER_VERSION,
  resolveWardrobeProfile,
} = require("./wardrobe_profile_resolver");
const {
  runWardrobeProfileResolverInputParity,
} = require("./backend_wardrobe_profile_resolver_input_parity");

const DEFAULT_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_wardrobe_profile_resolver_oracle_manifest.json");
const PREPARE_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_wardrobe_profile_resolver_input_orchestration_manifest.json");
const SOURCE = path.resolve(__dirname, "wardrobe_profile_resolver.js");
const DART_SOURCE =
  "lib/domain/wardrobe_profile/wardrobe_profile_resolver.dart";

function runWardrobeProfileResolverParity({
  manifestPath = DEFAULT_MANIFEST,
} = {}) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.manifestVersion !== 1 ||
      manifest.oracleVersion !== 1 ||
      manifest.providerId !== PROVIDER_ID ||
      manifest.providerVersion !== PROVIDER_VERSION) {
    throw new Error("profile_resolver_oracle_integrity_failure");
  }
  if (manifest.readyScenarioCount !== 8 || manifest.invocationCount !== 8) {
    throw new Error("profile_resolver_oracle_integrity_failure");
  }
  const prepare = JSON.parse(fs.readFileSync(PREPARE_MANIFEST, "utf8"));
  if (prepare.parityStatus !== "orchestration_ready" ||
      prepare.passedScenarios !== 8) {
    throw new Error("profile_resolver_oracle_integrity_failure");
  }
  const inputParity = runWardrobeProfileResolverInputParity();
  if (inputParity.passedScenarios !== 8) {
    throw new Error("profile_resolver_oracle_integrity_failure");
  }
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  const scenarios = ready.map((entry) => {
    const oracleBytes = fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath));
    if (sha256(oracleBytes) !== entry.oracleSha256) {
      throw new Error(`resolver_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const oracle = JSON.parse(oracleBytes.toString("utf8"));
    const expected = oracle.invocations[0].resolverOutput;
    const input = oracle.invocations[0].resolverInput;
    const actual = resolveWardrobeProfile(structuredClone(input));
    const differences = diff(expected, actual);
    const selected = countSelected(actual);
    return {
      scenarioId: entry.scenarioId,
      passed: differences.length === 0,
      differences,
      outputSha256: sha256(canonicalBytes(actual)),
      expectedOutputSha256: sha256(canonicalBytes(expected)),
      selected,
      knownFieldCount: countKnown(actual),
      conflictFieldCount: countConflicts(actual),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  const passed = scenarios.filter((item) => item.passed).length;
  const rerun = runOnce(manifestPath);
  const deterministic = scenarios.every((item, index) =>
    item.outputSha256 === rerun.scenarios[index].outputSha256);
  const distribution = aggregateDistribution(scenarios);
  const distributionOk = distribution.resolvedCanonical === 1 &&
    distribution.resolvedFamily === 0 &&
    distribution.observationFields === 86 &&
    distribution.capabilityFields === 17 &&
    distribution.kbSelected === 6 &&
    distribution.visualSelected === 86 &&
    distribution.aiSelected === 15 &&
    distribution.legacySelected === 0 &&
    distribution.compatibilitySelected === 0 &&
    distribution.userCorrectionSelected === 0 &&
    distribution.conflictFields === 0 &&
    distribution.fullyUnresolvedProfiles === 0;
  return deepFreeze({
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    oracleContractVersion: ORACLE_CONTRACT_VERSION,
    scenarioCount: scenarios.length,
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    parityStatus: passed === 8 && deterministic && distributionOk ?
      "parity_ready" : "parity_failed",
    deterministic,
    distributionOk,
    distribution,
    scenarios,
    nodeImplementationSha256: sha256(fs.readFileSync(SOURCE)),
    dartImplementationSha256: sha256(fs.readFileSync(
      path.resolve(__dirname, "..", DART_SOURCE))),
    callSitePreparationSha256: manifest.callSitePreparationSha256,
    prepareStageManifest:
      "backend_wardrobe_profile_resolver_input_orchestration_manifest.json",
  });
}

function runOnce(manifestPath) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  const scenarios = ready.map((entry) => {
    const oracle = JSON.parse(fs.readFileSync(
      path.resolve(fixtureRoot, entry.oraclePath), "utf8"));
    const actual = resolveWardrobeProfile(
      structuredClone(oracle.invocations[0].resolverInput));
    return {
      scenarioId: entry.scenarioId,
      outputSha256: sha256(canonicalBytes(actual)),
    };
  }).sort((a, b) => a.scenarioId.localeCompare(b.scenarioId));
  return {scenarios};
}

function buildWardrobeProfileResolverParityEntry(report) {
  return deepFreeze({
    providerId: report.providerId,
    providerVersion: report.providerVersion,
    oracleContractVersion: report.oracleContractVersion,
    inputContract: "wardrobe_profile_resolver_input/v1",
    outputContract: "ResolvedWardrobeItemProfile/v1",
    dartProviderSource: DART_SOURCE,
    nodeProviderSource: "functions/wardrobe_profile_resolver.js",
    parityStatus: report.parityStatus,
    scenarioCount: report.scenarioCount,
    invocationCount: report.scenarioCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    canonicalImplementationSha256: report.nodeImplementationSha256,
    dependencyVersions: {
      dartImplementationSha256: report.dartImplementationSha256,
      callSitePreparationSha256: report.callSitePreparationSha256,
      prepareStage: "wardrobe-profile-resolver-input-v1",
      prepareStageManifest: report.prepareStageManifest,
      resolverOracleContract: report.oracleContractVersion,
      resolverCompatibilityVersion: 1,
    },
    outputSha256ByScenario: Object.fromEntries(
      report.scenarios.map((item) => [item.scenarioId, item.outputSha256])),
  });
}

function updateProviderParityManifest(report, {
  parityManifestPath = path.resolve(__dirname, "../test/fixtures/" +
    "backend_qualification/backend_provider_parity_manifest.json"),
} = {}) {
  const parity = JSON.parse(fs.readFileSync(parityManifestPath, "utf8"));
  const entry = buildWardrobeProfileResolverParityEntry(report);
  const providers = parity.providers.filter(
    (item) => item.providerId !== PROVIDER_ID);
  providers.push(entry);
  providers.sort((left, right) =>
    left.providerId.localeCompare(right.providerId));
  const next = {
    ...parity,
    providers,
  };
  const bytes = canonicalBytes(next);
  fs.writeFileSync(parityManifestPath, bytes);
  return deepFreeze(JSON.parse(Buffer.from(bytes).toString("utf8")));
}

function countSelected(profile) {
  let kb = 0;
  let visual = 0;
  let ai = 0;
  let legacy = 0;
  let user = 0;
  let observation = 0;
  let capability = 0;
  for (const [section, fields] of Object.entries({
    identity: profile.identity,
    visual: profile.visual,
    capabilities: profile.capabilities,
    suitability: profile.suitability,
  })) {
    for (const field of Object.values(fields)) {
      if (field.state !== "known" && field.state !== "not_applicable") continue;
      if (section === "visual") observation++;
      if (section === "capabilities") capability++;
      switch (field.winningSource) {
      case "knowledge_base_prior": kb++; break;
      case "visual_observation": visual++; break;
      case "ai_inference": ai++; break;
      case "legacy_fallback": legacy++; break;
      case "user_correction": user++; break;
      }
    }
  }
  return {kb, visual, ai, legacy, user, observation, capability};
}

function countKnown(profile) {
  let count = 0;
  for (const section of [
    profile.identity, profile.visual, profile.capabilities, profile.suitability,
  ]) {
    for (const field of Object.values(section)) {
      if (field.state === "known" || field.state === "not_applicable") count++;
    }
  }
  return count;
}

function countConflicts(profile) {
  let count = 0;
  for (const section of [
    profile.identity, profile.visual, profile.capabilities, profile.suitability,
  ]) {
    for (const field of Object.values(section)) {
      if (Array.isArray(field.conflictingEvidenceIds) &&
          field.conflictingEvidenceIds.length > 0) {
        count++;
      }
    }
  }
  return count;
}

function aggregateDistribution(scenarios) {
  let observationFields = 0;
  let capabilityFields = 0;
  let kbSelected = 0;
  let visualSelected = 0;
  let aiSelected = 0;
  let legacySelected = 0;
  let userCorrectionSelected = 0;
  let conflictFields = 0;
  let fullyUnresolvedProfiles = 0;
  for (const scenario of scenarios) {
    observationFields += scenario.selected.observation;
    capabilityFields += scenario.selected.capability;
    kbSelected += scenario.selected.kb;
    visualSelected += scenario.selected.visual;
    aiSelected += scenario.selected.ai;
    legacySelected += scenario.selected.legacy;
    userCorrectionSelected += scenario.selected.user;
    conflictFields += scenario.conflictFieldCount;
    if (scenario.knownFieldCount === 0) fullyUnresolvedProfiles++;
  }
  const resolvedCanonical = countCanonicalKnown();
  return {
    resolvedCanonical,
    unresolvedCanonical: 8 - resolvedCanonical,
    resolvedFamily: 0,
    observationFields,
    capabilityFields,
    kbSelected,
    visualSelected,
    aiSelected,
    legacySelected,
    compatibilitySelected: 0,
    userCorrectionSelected,
    conflictFields,
    fullyUnresolvedProfiles,
  };
}

function countCanonicalKnown() {
  let count = 0;
  const fixtureRoot = path.resolve(__dirname, "../test/fixtures");
  const manifest = JSON.parse(fs.readFileSync(DEFAULT_MANIFEST, "utf8"));
  for (const entry of manifest.fixtures.filter((item) => item.status === "ready")) {
    const oracle = JSON.parse(fs.readFileSync(
      path.join(fixtureRoot, entry.oraclePath), "utf8"));
    const actual = resolveWardrobeProfile(
      structuredClone(oracle.invocations[0].resolverInput));
    if (actual.identity.canonicalType.state === "known") count++;
  }
  return count;
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function deepFreeze(value) {
  if (value === null || typeof value !== "object" || Object.isFrozen(value)) {
    return value;
  }
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

module.exports = {
  buildWardrobeProfileResolverParityEntry,
  runWardrobeProfileResolverParity,
  updateProviderParityManifest,
};
