"use strict";

/**
 * Production configuration validation for wardrobe authority runtime.
 */

const CONFIG_ID = "WardrobeAuthorityProductionConfig";
const CONFIG_VERSION = "wardrobe-authority-production-config-v1";

const REQUIRED_VERSIONS = Object.freeze({
  visionSchemaVersion: 9,
  modelIdentifier: "gpt-4o-mini",
  promptVersion: "vision-v2-schema-9",
  qualificationVersion: "qualification-v1",
  revisionContractVersion: "wardrobe-qualification-revision-context-v1",
  persistenceSchemaVersion: 1,
  authorityRequestContract: "WardrobeQualificationAuthorityRequest/v1",
  authorityResultContract: "WardrobeQualificationAuthorityResult/v1",
  lifecycleEndpointVersion: "wardrobe-revision-lifecycle-endpoint-v1",
  authorityEndpointVersion: "wardrobe-qualification-authority-endpoint-v1",
});

/**
 * @param {object} raw
 * @returns {Readonly<object>}
 */
function validateWardrobeAuthorityProductionConfig(raw) {
  if (raw == null || typeof raw !== "object" || Array.isArray(raw)) {
    fail("production_config_not_object");
  }
  const environmentMode = requireEnum(raw.environmentMode, "environmentMode",
    ["production", "emulator", "test"]);
  const projectId = requireNonEmpty(raw.projectId, "projectId");
  const storageBucket = requireNonEmpty(raw.storageBucket, "storageBucket");
  if (!/^[a-z0-9][a-z0-9._-]*\.(?:appspot\.com|firebasestorage\.app)$/i
    .test(storageBucket)) {
    fail("storageBucket_invalid");
  }
  if (/developer|localhost|example|TODO/i.test(projectId) ||
      /developer|localhost|example|TODO/i.test(storageBucket)) {
    fail("production_config_placeholder_identity_forbidden");
  }
  const region = requireNonEmpty(raw.region, "region");
  const visionSchemaVersion = requirePositiveInt(
    raw.visionSchemaVersion, "visionSchemaVersion");
  if (visionSchemaVersion !== REQUIRED_VERSIONS.visionSchemaVersion) {
    fail("vision_schema_version_mismatch");
  }
  const modelIdentifier = requireNonEmpty(
    raw.modelIdentifier, "modelIdentifier");
  if (modelIdentifier !== REQUIRED_VERSIONS.modelIdentifier) {
    fail("model_identifier_mismatch");
  }
  const promptVersion = requireNonEmpty(raw.promptVersion, "promptVersion");
  if (promptVersion !== REQUIRED_VERSIONS.promptVersion) {
    fail("prompt_version_mismatch");
  }
  const qualificationVersion = requireNonEmpty(
    raw.qualificationVersion, "qualificationVersion");
  if (qualificationVersion !== REQUIRED_VERSIONS.qualificationVersion) {
    fail("qualification_version_mismatch");
  }
  const revisionContractVersion = requireNonEmpty(
    raw.revisionContractVersion, "revisionContractVersion");
  if (revisionContractVersion !== REQUIRED_VERSIONS.revisionContractVersion) {
    fail("revision_contract_version_mismatch");
  }
  const persistenceSchemaVersion = requirePositiveInt(
    raw.persistenceSchemaVersion, "persistenceSchemaVersion");
  if (persistenceSchemaVersion !== REQUIRED_VERSIONS.persistenceSchemaVersion) {
    fail("persistence_schema_version_mismatch");
  }
  return Object.freeze({
    configId: CONFIG_ID,
    configVersion: CONFIG_VERSION,
    environmentMode,
    projectId,
    storageBucket,
    region,
    visionSchemaVersion,
    modelIdentifier,
    promptVersion,
    qualificationVersion,
    revisionContractVersion,
    persistenceSchemaVersion,
    authorityRequestContract: REQUIRED_VERSIONS.authorityRequestContract,
    authorityResultContract: REQUIRED_VERSIONS.authorityResultContract,
    lifecycleEndpointVersion: REQUIRED_VERSIONS.lifecycleEndpointVersion,
    authorityEndpointVersion: REQUIRED_VERSIONS.authorityEndpointVersion,
    appCheckMode: raw.appCheckMode ?? null,
    memory: raw.memory ?? "512MB",
    timeoutSeconds: Number.isInteger(raw.timeoutSeconds) ?
      raw.timeoutSeconds : 120,
  });
}

function requireEnum(value, label, allowed) {
  const text = requireNonEmpty(value, label);
  if (!allowed.includes(text)) fail(`${label}_invalid`);
  return text;
}

function requireNonEmpty(value, label) {
  if (typeof value !== "string" || !value.trim()) fail(`${label}_empty`);
  return value.trim();
}

function requirePositiveInt(value, label) {
  if (!Number.isInteger(value) || value <= 0) fail(`${label}_invalid`);
  return value;
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  CONFIG_ID,
  CONFIG_VERSION,
  REQUIRED_VERSIONS,
  validateWardrobeAuthorityProductionConfig,
};
