"use strict";

const PARTNER_ERROR = Object.freeze({
  AUTH_ERROR: "AUTH_ERROR",
  RATE_LIMITED: "RATE_LIMITED",
  PARTNER_UNAVAILABLE: "PARTNER_UNAVAILABLE",
  TIMEOUT: "TIMEOUT",
  INVALID_PAYLOAD: "INVALID_PAYLOAD",
  SCHEMA_CHANGED: "SCHEMA_CHANGED",
  INVALID_MONEY: "INVALID_MONEY",
  INVALID_URL: "INVALID_URL",
  IDENTITY_CONFLICT: "IDENTITY_CONFLICT",
  UNSUPPORTED_PROMOTION: "UNSUPPORTED_PROMOTION",
  PARTIAL_SYNC_FAILED: "PARTIAL_SYNC_FAILED",
  FATAL_CONFIGURATION: "FATAL_CONFIGURATION",
});

const RETRYABLE_ERRORS = Object.freeze(new Set([
  PARTNER_ERROR.RATE_LIMITED,
  PARTNER_ERROR.PARTNER_UNAVAILABLE,
  PARTNER_ERROR.TIMEOUT,
]));

function createPartnerError(code, message, details = {}) {
  if (!Object.values(PARTNER_ERROR).includes(code)) {
    throw new Error("partner_error_code_invalid");
  }
  const error = new Error(message || code);
  error.code = code;
  error.retryable = RETRYABLE_ERRORS.has(code);
  Object.assign(error, details);
  return error;
}

function classifyHttpStatus(status, {retryAfterMs} = {}) {
  if (status === 401 || status === 403) {
    return createPartnerError(PARTNER_ERROR.AUTH_ERROR, "partner_auth_error", {
      httpStatus: status,
    });
  }
  if (status === 429) {
    return createPartnerError(PARTNER_ERROR.RATE_LIMITED, "partner_rate_limited", {
      httpStatus: status,
      retryAfterMs: retryAfterMs == null ? null : retryAfterMs,
    });
  }
  if (status >= 500) {
    return createPartnerError(
      PARTNER_ERROR.PARTNER_UNAVAILABLE,
      "partner_unavailable",
      {httpStatus: status},
    );
  }
  return createPartnerError(
    PARTNER_ERROR.INVALID_PAYLOAD,
    "partner_unexpected_http_status",
    {httpStatus: status},
  );
}

function isRetryableError(error) {
  if (!error) return false;
  if (error.retryable === true) return true;
  if (error.retryable === false) return false;
  return RETRYABLE_ERRORS.has(error.code);
}

module.exports = {
  PARTNER_ERROR,
  RETRYABLE_ERRORS,
  classifyHttpStatus,
  createPartnerError,
  isRetryableError,
};
