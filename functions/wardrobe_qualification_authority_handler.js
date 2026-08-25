"use strict";

/**
 * Unexported callable/handler wrapper for qualification authority.
 * Not registered in functions/index.js.
 */

const {
  decodeCallableAuthContext,
  assertCallableRequestOwnership,
} = require("./wardrobe_authority_callable_auth");
const {
  mapEndpointStatusToHttps,
  toCallableErrorPayload,
} = require("./wardrobe_authority_error_mapping");
const {
  fingerprint,
  safeLogFields,
  redactValue,
} = require("./wardrobe_authority_redaction");
const {
  assertWardrobeAuthorityExportReady,
  phase9bExportReadinessState,
} = require("./wardrobe_authority_export_gate");
const {
  RUNTIME_POLICIES,
} = require("./trusted_vision_result_provenance");

const HANDLER_ID = "WardrobeQualificationAuthorityHandler";
const HANDLER_VERSION = "wardrobe-qualification-authority-handler-v1";

/**
 * @param {{
 *   dependencyFactory: {get: Function},
 *   logger?: {info?: Function, error?: Function, warn?: Function},
 *   exportReadinessState?: object,
 * }} options
 */
function createQualificationAuthorityHandler(options) {
  if (!options || typeof options.dependencyFactory?.get !== "function") {
    fail("dependency_factory_required");
  }
  const logger = options.logger || {info() {}, error() {}, warn() {}};

  async function handle(data, runtimeContext) {
    const started = Date.now();
    // Export gate: always fail-closed in this phase if someone tries to export.
    try {
      assertWardrobeAuthorityExportReady(
        options.exportReadinessState || phase9bExportReadinessState());
    } catch (gateError) {
      // Handlers may exist unexported; gate blocks production export path only
      // when enforceExportGate is true.
      if (options.enforceExportGate === true) {
        return errorResponse("failed-precondition", gateError.message, started);
      }
    }

    let deps;
    try {
      deps = options.dependencyFactory.get();
    } catch (error) {
      logger.error(safeLogFields({
        operationKind: "authority",
        status: "internal",
        reasonCode: error.message,
        durationMs: Date.now() - started,
      }));
      return errorResponse("internal", "dependency_construction_failed", started);
    }

    const decoded = decodeCallableAuthContext(runtimeContext, deps.config);
    let uid;
    try {
      uid = assertCallableRequestOwnership(data || {}, decoded);
    } catch (error) {
      const status = error.status ||
        (String(error.message).includes("unauthenticated") ?
          "unauthenticated" : "forbidden");
      const mapped = mapEndpointStatusToHttps(status, error.message);
      logger.warn?.(safeLogFields({
        operationKind: "authority",
        status,
        reasonCode: error.message,
        durationMs: Date.now() - started,
      }));
      return errorResponse(mapped.code, mapped.message, started);
    }

    if (decoded.appCheck.warning) {
      logger.warn?.(safeLogFields({
        operationKind: "authority",
        status: "app_check_warning",
        reasonCode: decoded.appCheck.reasonCode,
        itemFingerprint: fingerprint(data && data.itemId),
        durationMs: Date.now() - started,
      }));
    }

    // assignedAt is exclusively server-owned via trusted serverClock.
    // Never accept client data.assignedAt or legacy deps.assignedAt here.
    const endpointResult = await deps.handleQualificationAuthorityEndpoint(
      data,
      {
        authContext: {
          authenticated: true,
          uid,
          tokenVerified: decoded.auth.tokenVerified,
          emulatorVerified: decoded.auth.emulatorVerified,
          appCheckPresent: decoded.auth.appCheckPresent,
          appCheckVerified: decoded.auth.appCheckVerified,
          authType: "firebase_auth",
        },
        store: deps.store,
        storageMetadataClient: deps.storageMetadataClient,
        visionClient: deps.visionClient,
        serverClock: deps.serverClock,
        scenarioId: data.offlineScenarioId || options.defaultScenarioId,
        fixtureRoot: options.fixtureRoot,
        provenancePolicy: deps.provenancePolicy ||
          RUNTIME_POLICIES.fixtureOnly,
      },
    );

    const mapped = mapEndpointStatusToHttps(
      endpointResult.status, endpointResult.reasonCode);
    logger.info(safeLogFields({
      operationKind: "authority",
      status: endpointResult.status,
      reasonCode: endpointResult.reasonCode,
      itemFingerprint: fingerprint(endpointResult.itemId),
      generationFingerprint: fingerprint(endpointResult.generationId || ""),
      durationMs: Date.now() - started,
      action: data && data.action,
    }));

    if (mapped.isError) {
      return errorResponse(mapped.code, mapped.message, started, endpointResult);
    }
    return successResponse(endpointResult, started);
  }

  return Object.freeze({
    handlerId: HANDLER_ID,
    handlerVersion: HANDLER_VERSION,
    productionExport: false,
    handle,
  });
}

function successResponse(endpointResult, started) {
  return Object.freeze({
    ok: true,
    handlerId: HANDLER_ID,
    handlerVersion: HANDLER_VERSION,
    durationMs: Date.now() - started,
    result: redactValue({
      status: endpointResult.status,
      reasonCode: endpointResult.reasonCode,
      itemId: endpointResult.itemId,
      generationId: endpointResult.generationId,
      analysisId: endpointResult.analysisId,
      repositoryStatus: endpointResult.repositoryStatus,
      previousProfileRevision: endpointResult.previousProfileRevision,
      resultingProfileRevision: endpointResult.resultingProfileRevision,
      wroteProfile: endpointResult.wroteProfile,
      idempotent: endpointResult.idempotent,
      retryable: endpointResult.retryable,
      authorityInitialized: endpointResult.authorityInitialized,
      qualificationSummary: endpointResult.qualificationSummary,
    }),
  });
}

function errorResponse(code, message, started, endpointResult = null) {
  return Object.freeze({
    ok: false,
    handlerId: HANDLER_ID,
    handlerVersion: HANDLER_VERSION,
    durationMs: Date.now() - started,
    error: toCallableErrorPayload({code, message}),
    result: endpointResult ? redactValue({
      status: endpointResult.status,
      reasonCode: endpointResult.reasonCode,
      itemId: endpointResult.itemId,
      idempotent: endpointResult.idempotent,
    }) : null,
  });
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  HANDLER_ID,
  HANDLER_VERSION,
  createQualificationAuthorityHandler,
};
