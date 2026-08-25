"use strict";

/**
 * Stable Functions error mapping for wardrobe authority handlers.
 */

const ERROR_MAP_ID = "WardrobeAuthorityErrorMapping";
const ERROR_MAP_VERSION = "wardrobe-authority-error-mapping-v1";

const HttpsErrorCodes = Object.freeze({
  unauthenticated: "unauthenticated",
  permissionDenied: "permission-denied",
  invalidArgument: "invalid-argument",
  notFound: "not-found",
  failedPrecondition: "failed-precondition",
  aborted: "aborted",
  alreadyExists: "already-exists",
  resourceExhausted: "resource-exhausted",
  unavailable: "unavailable",
  internal: "internal",
});

const STATUS_TO_CODE = Object.freeze({
  unauthenticated: HttpsErrorCodes.unauthenticated,
  forbidden: HttpsErrorCodes.permissionDenied,
  invalid_contract: HttpsErrorCodes.invalidArgument,
  invalid_argument: HttpsErrorCodes.invalidArgument,
  item_not_found: HttpsErrorCodes.notFound,
  item_deleted: HttpsErrorCodes.notFound,
  authority_missing: HttpsErrorCodes.failedPrecondition,
  source_missing: HttpsErrorCodes.failedPrecondition,
  product_source_not_supported: HttpsErrorCodes.failedPrecondition,
  stale_image: HttpsErrorCodes.aborted,
  stale_item_revision: HttpsErrorCodes.aborted,
  newer_generation_exists: HttpsErrorCodes.aborted,
  revision_conflict: HttpsErrorCodes.aborted,
  mutation_conflict: HttpsErrorCodes.aborted,
  idempotent_noop: null, // success path, not an error
  mutation_applied: null,
  authority_already_initialized: null,
  mapping_failed: HttpsErrorCodes.failedPrecondition,
  qualification_failed: HttpsErrorCodes.failedPrecondition,
  invalid_parser_result: HttpsErrorCodes.failedPrecondition,
  repository_failed: HttpsErrorCodes.internal,
  internal_contract_mismatch: HttpsErrorCodes.internal,
  revision_overflow: HttpsErrorCodes.resourceExhausted,
  unavailable: HttpsErrorCodes.unavailable,
});

function mapEndpointStatusToHttps(status, reasonCode) {
  if (status == null) {
    return {
      isError: true,
      code: HttpsErrorCodes.internal,
      message: "internal",
    };
  }
  if (!Object.prototype.hasOwnProperty.call(STATUS_TO_CODE, status)) {
    return {
      isError: true,
      code: HttpsErrorCodes.internal,
      message: reasonCode || "internal",
    };
  }
  const code = STATUS_TO_CODE[status];
  if (code == null) {
    return {isError: false, code: null, message: reasonCode || status};
  }
  return {
    isError: true,
    code,
    message: reasonCode || status,
  };
}

function toCallableErrorPayload(mapping) {
  return Object.freeze({
    code: mapping.code,
    message: mapping.message,
    // Never include stack / sensitive diagnostics.
  });
}

module.exports = {
  ERROR_MAP_ID,
  ERROR_MAP_VERSION,
  HttpsErrorCodes,
  STATUS_TO_CODE,
  mapEndpointStatusToHttps,
  toCallableErrorPayload,
};
