"use strict";

const {CLIENT_CONTRACT, validateParserFixture} =
  require("./trusted_vision_analysis_client");

const PROVENANCE_CONTRACT = "TrustedVisionResultProvenance/v1";
const VALIDATOR_ID = "TrustedVisionResultProvenanceValidator";
const VALIDATOR_VERSION = "trusted-vision-result-provenance-validator-v1";
const RUNTIME_POLICIES = Object.freeze({
  fixtureOnly: "fixture_only",
  productionShadow: "production_shadow",
  productionControlledWrite: "production_controlled_write",
});
const EXPECTED = Object.freeze({
  modelIdentifier: "gpt-4o-mini",
  promptVersion: "vision-v2-schema-9",
  visionSchemaVersion: 9,
  pipelineVersion: "vision-v2-phase-4.9",
  qualificationVersion: "qualification-v1",
  parserContractVersion: 1,
  fixturePromptVersion: "vision_v2_prompt_schema_9",
  fixturePipelineVersion: "vision_v2_phase_4_9",
  fixtureParserVersion: "vision_v2_parser_v1",
});
const FIXTURE_SOURCES = Object.freeze([
  "offline_parser_fixture", "trusted_fixture_transport",
]);
const PRODUCTION_SOURCE = "trusted_server_media";

function validateTrustedVisionResultForRuntime(result, options = {}) {
  const policy = options.policy;
  if (!Object.values(RUNTIME_POLICIES).includes(policy)) {
    return invalid("unknown_runtime_policy");
  }
  if (!isObject(result) || !isObject(result.provenance) ||
      !isObject(result.parser)) {
    return invalid("trusted_vision_provenance_missing");
  }
  if (result.clientContract !== CLIENT_CONTRACT) {
    return invalid("vision_client_contract_mismatch");
  }
  try {
    validateParserFixture(result.parser, result.scenarioId);
  } catch (_) {
    return invalid("strict_parser_validation_failed");
  }
  const expected = {...EXPECTED, ...(options.expectedVersions || {})};
  if (expected.pipelineVersion !== EXPECTED.pipelineVersion) {
    return invalid("pipeline_version_mismatch");
  }
  if (expected.qualificationVersion !== EXPECTED.qualificationVersion) {
    return invalid("qualification_version_mismatch");
  }
  if (result.parser.fixtureContractVersion !== expected.parserContractVersion) {
    return invalid("parser_contract_version_mismatch");
  }
  const provenance = result.provenance;
  if (typeof provenance.liveModel !== "boolean" ||
      typeof provenance.source !== "string") {
    return invalid("trusted_vision_provenance_malformed");
  }
  const productionPolicy = policy === RUNTIME_POLICIES.productionShadow ||
    policy === RUNTIME_POLICIES.productionControlledWrite;
  if (productionPolicy) {
    if (provenance.source !== PRODUCTION_SOURCE) {
      return invalid("production_trusted_source_required");
    }
    if (provenance.liveModel !== true) {
      return invalid("production_live_model_required");
    }
    if (provenance.modelIdentifier !== expected.modelIdentifier) {
      return invalid("model_identifier_mismatch");
    }
    if (provenance.promptVersion !== expected.promptVersion) {
      return invalid("prompt_version_mismatch");
    }
    if (provenance.visionSchemaVersion !== expected.visionSchemaVersion) {
      return invalid("vision_schema_version_mismatch");
    }
  } else {
    if (!FIXTURE_SOURCES.includes(provenance.source)) {
      return invalid("fixture_trusted_source_required");
    }
    if (provenance.liveModel !== false) {
      return invalid("fixture_live_model_forbidden");
    }
    const capture = result.parser.captureProvenance;
    if (isObject(capture)) {
      if (capture.modelIdentifier !== expected.modelIdentifier) {
        return invalid("model_identifier_mismatch");
      }
      if (capture.promptVersion !== expected.fixturePromptVersion ||
          capture.pipelineVersion !== expected.fixturePipelineVersion ||
          capture.visionSchemaVersion !== expected.visionSchemaVersion ||
          capture.parserVersion !== expected.fixtureParserVersion) {
        return invalid("fixture_version_mismatch");
      }
    } else if (provenance.source === "trusted_fixture_transport") {
      if (provenance.modelIdentifier !== expected.modelIdentifier ||
          provenance.promptVersion !== expected.promptVersion ||
          provenance.visionSchemaVersion !== expected.visionSchemaVersion) {
        return invalid("fixture_version_mismatch");
      }
    } else {
      return invalid("fixture_capture_provenance_missing");
    }
  }
  for (const view of result.parser.views) {
    const response = view.response;
    if (response.modelVersion !== expected.modelIdentifier) {
      return invalid("parser_model_version_mismatch");
    }
    if (response.schemaVersion !== expected.visionSchemaVersion) {
      return invalid("parser_schema_version_mismatch");
    }
    if (productionPolicy &&
        (typeof response.sourceReference !== "string" ||
         !response.sourceReference.startsWith("gs://server/"))) {
      return invalid("trusted_server_source_reference_required");
    }
  }
  return Object.freeze({
    ok: true,
    contract: PROVENANCE_CONTRACT,
    validatorId: VALIDATOR_ID,
    validatorVersion: VALIDATOR_VERSION,
    policy,
    executionEnvironment: productionPolicy ? "production" : "fixture",
    transport: productionPolicy ? "trusted_server_openai" : "fixture_transport",
    liveModel: provenance.liveModel,
    modelIdentifier: expected.modelIdentifier,
    promptVersion: productionPolicy ? expected.promptVersion :
      expected.fixturePromptVersion,
    visionSchemaVersion: expected.visionSchemaVersion,
    pipelineVersion: expected.pipelineVersion,
    qualificationVersion: expected.qualificationVersion,
    parserContractVersion: expected.parserContractVersion,
  });
}

function invalid(reasonCode) {
  return Object.freeze({ok: false, contract: PROVENANCE_CONTRACT,
    validatorId: VALIDATOR_ID, validatorVersion: VALIDATOR_VERSION,
    reasonCode});
}
function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

module.exports = {EXPECTED, PROVENANCE_CONTRACT, RUNTIME_POLICIES,
  VALIDATOR_ID, VALIDATOR_VERSION, validateTrustedVisionResultForRuntime};
