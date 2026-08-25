"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {
  canonicalBytes,
  diff,
} = require("./backend_provider_oracle_parity");
const {
  PROVIDER_ID,
  PROVIDER_VERSION,
  attestFraming,
  decodeFramingOracle,
} = require("./vision_framing_attestor");

const DEFAULT_MANIFEST = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification/backend_framing_attestor_oracle_manifest.json");
const PROVIDER_SOURCE = path.resolve(__dirname,
  "vision_framing_attestor.js");

function runFramingAttestorParity({
  manifestPath = DEFAULT_MANIFEST,
} = {}) {
  const manifest = readJson(manifestPath);
  validateManifest(manifest);
  const fixtureRoot = path.dirname(path.dirname(manifestPath));
  const scenarios = [];
  for (const entry of manifest.fixtures.filter((item) =>
    item.status === "ready")) {
    const oraclePath = path.resolve(fixtureRoot, entry.oraclePath);
    const bytes = fs.readFileSync(oraclePath);
    if (sha256(bytes) !== entry.oracleSha256) {
      throw new Error(`framing_oracle_sha_mismatch:${entry.scenarioId}`);
    }
    const raw = JSON.parse(bytes);
    const oracle = decodeFramingOracle(raw);
    if (oracle.scenarioId !== entry.scenarioId ||
        oracle.invocations.length !== entry.invocationCount) {
      throw new Error(`framing_oracle_binding_mismatch:${entry.scenarioId}`);
    }
    const invocationReports = oracle.invocations.map((invocation) => {
      if (sha256(canonicalBytes(invocation.providerInput)) !==
          invocation.providerInputSha256) {
        throw new Error(`framing_input_sha_mismatch:${entry.scenarioId}`);
      }
      const actual = attestFraming(invocation.providerInput);
      const differences = diff(invocation.providerOutput, actual);
      return deepFreeze({
        viewId: invocation.viewId,
        passed: differences.length === 0,
        differences,
        outputSha256: sha256(canonicalBytes(actual)),
      });
    });
    const passed = invocationReports.every((item) => item.passed);
    scenarios.push(deepFreeze({
      scenarioId: entry.scenarioId,
      passed,
      invocationCount: invocationReports.length,
      invocations: invocationReports,
      outputSha256: sha256(canonicalBytes(
        invocationReports.map((item) => item.outputSha256))),
    }));
  }
  scenarios.sort((left, right) =>
    left.scenarioId.localeCompare(right.scenarioId));
  const passed = scenarios.filter((item) => item.passed).length;
  return deepFreeze({
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    scenarioCount: scenarios.length,
    invocationCount: scenarios.reduce(
      (sum, item) => sum + item.invocationCount, 0),
    passedScenarios: passed,
    failedScenarios: scenarios.length - passed,
    parityStatus: passed === 8 && scenarios.length === 8 ?
      "parity_ready" : "parity_failed",
    scenarios,
  });
}

function buildFramingAttestorParityEntry(report) {
  if (!report || report.providerId !== PROVIDER_ID) {
    throw new Error("framing_parity_report_invalid");
  }
  return {
    providerId: PROVIDER_ID,
    providerVersion: PROVIDER_VERSION,
    dartProviderSource:
      "lib/domain/wardrobe_profile/vision_framing_attestation.dart",
    nodeProviderSource: "functions/vision_framing_attestor.js",
    inputContract: "framing_attestor_oracle.invocations.input/v1",
    outputContract: "VisionFramingAttestationReport/v1",
    oracleContractVersion: 1,
    scenarioCount: report.scenarioCount,
    invocationCount: report.invocationCount,
    passedScenarios: report.passedScenarios,
    failedScenarios: report.failedScenarios,
    parityStatus: report.parityStatus,
    canonicalImplementationSha256: sha256(
      fs.readFileSync(PROVIDER_SOURCE)),
    dependencyVersions: {
      framingAttestorOracleContract: 1,
    },
    outputSha256ByScenario: Object.fromEntries(report.scenarios.map(
      (item) => [item.scenarioId, item.outputSha256])),
  };
}

function validateManifest(value) {
  if (!value || value.manifestVersion !== 1 ||
      value.oracleContractVersion !== 1 ||
      value.providerId !== PROVIDER_ID ||
      value.providerVersion !== PROVIDER_VERSION ||
      !Array.isArray(value.fixtures)) {
    throw new Error("framing_oracle_manifest_invalid");
  }
  if (value.fixtures.filter((item) => item.status === "ready").length !== 8 ||
      value.fixtures.some((item) =>
        !["ready", "source_missing"].includes(item.status))) {
    throw new Error("framing_oracle_manifest_status_invalid");
  }
}
function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}
function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}
function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    Object.values(value).forEach(deepFreeze);
  }
  return value;
}

module.exports = {
  DEFAULT_MANIFEST,
  buildFramingAttestorParityEntry,
  runFramingAttestorParity,
};
