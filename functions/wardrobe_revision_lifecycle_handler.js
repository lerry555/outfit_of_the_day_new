"use strict";

/**
 * Unexported callable/handler wrapper for revision lifecycle mutations.
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

const HANDLER_ID = "WardrobeRevisionLifecycleHandler";
const HANDLER_VERSION = "wardrobe-revision-lifecycle-handler-v1";

function createRevisionLifecycleHandler(options) {
  if (!options || typeof options.dependencyFactory?.get !== "function") {
    fail("dependency_factory_required");
  }
  const logger = options.logger || {info() {}, error() {}, warn() {}};

  async function handle(data, runtimeContext) {
    const started = Date.now();
    try {
      assertWardrobeAuthorityExportReady(
        options.exportReadinessState || phase9bExportReadinessState());
    } catch (gateError) {
      if (options.enforceExportGate === true) {
        return errorResponse("failed-precondition", gateError.message, started);
      }
    }

    let deps;
    try {
      deps = options.dependencyFactory.get();
    } catch (error) {
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
      return errorResponse(mapped.code, mapped.message, started);
    }

    const endpointResult = await deps.handleRevisionLifecycleEndpoint(data, {
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
      assignedAt: data.assignedAt || deps.assignedAt,
    });

    const mapped = mapEndpointStatusToHttps(
      endpointResult.status, endpointResult.reasonCode);
    logger.info(safeLogFields({
      operationKind: endpointResult.operationKind || "lifecycle",
      status: endpointResult.status,
      reasonCode: endpointResult.reasonCode,
      itemFingerprint: fingerprint(endpointResult.itemId),
      generationFingerprint: fingerprint(endpointResult.generationId || ""),
      durationMs: Date.now() - started,
    }));

    if (mapped.isError) {
      return errorResponse(mapped.code, mapped.message, started, endpointResult);
    }
    return Object.freeze({
      ok: true,
      handlerId: HANDLER_ID,
      handlerVersion: HANDLER_VERSION,
      durationMs: Date.now() - started,
      result: redactValue({
        status: endpointResult.status,
        reasonCode: endpointResult.reasonCode,
        operationKind: endpointResult.operationKind,
        itemId: endpointResult.itemId,
        generationId: endpointResult.generationId,
        previousImageRevision: endpointResult.previousImageRevision,
        resultingImageRevision: endpointResult.resultingImageRevision,
        previousWardrobeItemRevision:
          endpointResult.previousWardrobeItemRevision,
        resultingWardrobeItemRevision:
          endpointResult.resultingWardrobeItemRevision,
        authorityInitialized: endpointResult.authorityInitialized,
        documentPatched: endpointResult.documentPatched,
        idempotent: endpointResult.idempotent,
        retryable: endpointResult.retryable,
      }),
    });
  }

  return Object.freeze({
    handlerId: HANDLER_ID,
    handlerVersion: HANDLER_VERSION,
    productionExport: false,
    handle,
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
  createRevisionLifecycleHandler,
};
