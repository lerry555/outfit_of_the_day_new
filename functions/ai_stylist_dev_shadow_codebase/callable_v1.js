"use strict";

const {createSmokeInferenceBudget} = require("./inference_budget_v1");
const {runControlledDevShadowSmoke} = require("./smoke_orchestration_v1");

const CALLABLE_NAME = "aiStylistDevShadowSmoke";
const ENABLED_MODE = "single_smoke_enabled";
const FIXTURE_ID = "ootd_dev_shadow_minimal_v1";

function createDevShadowSmokeHandler({
  functionsApi,
  modeResolver,
  providerFactory,
  runIdFactory,
  logger = {info() {}, warn() {}, error() {}},
} = {}) {
  if (!functionsApi || !functionsApi.https ||
      typeof functionsApi.https.HttpsError !== "function" ||
      typeof modeResolver !== "function" || typeof providerFactory !== "function" ||
      typeof runIdFactory !== "function") {
    throw new Error("smoke_handler_dependencies_missing");
  }
  return async (data, context) => {
    if (modeResolver() !== ENABLED_MODE) {
      throw new functionsApi.https.HttpsError(
        "failed-precondition", "ai_stylist_dev_shadow_disabled");
    }
    if (!context || !context.auth || !context.auth.uid) {
      throw new functionsApi.https.HttpsError("unauthenticated", "auth_required");
    }
    if (!context.app) {
      throw new functionsApi.https.HttpsError(
        "failed-precondition", "app_check_required");
    }
    if (!context.auth.token || context.auth.token.aiStylistDevShadow !== true) {
      throw new functionsApi.https.HttpsError(
        "permission-denied", "developer_shadow_claim_required");
    }
    assertSmokeRequest(data, functionsApi);

    const runId = safeRunId(runIdFactory());
    const budget = createSmokeInferenceBudget();
    const providers = providerFactory({budget});
    if (!providers || providers.mode !== "real_dev_shadow" ||
        providers.fallbackProviderCallsEnabled !== false) {
      throw new functionsApi.https.HttpsError(
        "failed-precondition", "real_dev_shadow_factory_not_ready");
    }
    const legacyResult = Object.freeze({
      selectedCandidateId: "legacy-fixture-outfit",
      explanation: "Legacy fixture remains authoritative.",
      persistenceRevision: "unchanged",
    });
    let result;
    try {
      result = await runControlledDevShadowSmoke({
        runId, providers, budget, legacyResult,
      });
    } catch (error) {
      logger.error("ai_stylist_dev_shadow_smoke_failed", {
        runId,
        reasonCode: safeReason(error),
        authority: "shadow",
      });
      throw new functionsApi.https.HttpsError(
        "internal", "ai_stylist_dev_shadow_smoke_failed");
    }
    for (const event of result.trace) {
      logger.info("ai_stylist_dev_shadow_stage", event);
    }
    return result;
  };
}

function assertSmokeRequest(data, functionsApi) {
  const allowed = ["contractVersion", "fixtureId", "confirmNonAuthoritative"];
  if (!data || typeof data !== "object" || Array.isArray(data) ||
      Object.keys(data).some((key) => !allowed.includes(key)) ||
      data.contractVersion !== 1 || data.fixtureId !== FIXTURE_ID ||
      data.confirmNonAuthoritative !== true) {
    throw new functionsApi.https.HttpsError(
      "invalid-argument", "dev_shadow_fixture_request_invalid");
  }
}
function safeRunId(value) {
  const candidate = String(value || "").trim();
  if (!/^[a-zA-Z0-9_-]{8,80}$/.test(candidate)) {
    throw new Error("smoke_run_id_invalid");
  }
  return candidate;
}
function safeReason(error) {
  const code = String(error && (error.code || error.message) || "unknown");
  return /^[a-z0-9_:-]{1,120}$/i.test(code) ? code : "redacted_failure";
}

module.exports = {
  CALLABLE_NAME,
  ENABLED_MODE,
  FIXTURE_ID,
  createDevShadowSmokeHandler,
};
