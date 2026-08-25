"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  PROVIDER_FAILURE,
  NORMALIZED_REASON,
  normalizeProviderFailure,
} = require("./role_transport_v1");
const {runControlledDevShadowSmoke} = require("./smoke_orchestration_v1");

function response(status, error, providerCallNumber = 1) {
  return {status, json: {error}, providerCallNumber};
}

test("provider failures expose only allow-listed diagnostics", () => {
  const cases = [
    [response(400, {type: "invalid_request_error", code: "invalid_json_schema", param: "response_format"}), PROVIDER_FAILURE.structuredOutputInvalid, NORMALIZED_REASON.invalidJsonSchema],
    [response(400, {type: "invalid_request_error", code: "invalid_parameter", param: "max_tokens"}), PROVIDER_FAILURE.contractInvalid, NORMALIZED_REASON.modelParameterIncompatible],
    [response(400, {type: "invalid_request_error", param: "request"}), PROVIDER_FAILURE.contractInvalid, NORMALIZED_REASON.invalidRequest],
    [response(404, {type: "invalid_request_error", code: "model_not_found"}), PROVIDER_FAILURE.modelUnavailable, NORMALIZED_REASON.modelNotFound],
    [response(401, {type: "authentication_error", code: "invalid_api_key"}), PROVIDER_FAILURE.authenticationUnavailable, NORMALIZED_REASON.authenticationFailed],
    [response(403, {type: "permission_error", code: "access_denied"}), PROVIDER_FAILURE.accessDenied, NORMALIZED_REASON.accessDenied],
    [response(429, {type: "rate_limit_error", code: "rate_limit_exceeded"}), PROVIDER_FAILURE.rateLimited, NORMALIZED_REASON.rateLimited],
    [response(503, {type: "server_error", code: "provider_unavailable"}), PROVIDER_FAILURE.providerUnavailable, NORMALIZED_REASON.transportFailure],
  ];
  for (const [input, failureCode, normalizedReason] of cases) {
    const result = normalizeProviderFailure(input);
    assert.equal(result.failureCode, failureCode);
    assert.equal(result.providerCallNumber, 1);
    assert.equal(result.providerDiagnostics.httpStatus, input.status);
    assert.equal(result.providerDiagnostics.normalizedReason, normalizedReason);
    assert.deepEqual(Object.keys(result.providerDiagnostics).sort(), [
      "httpStatus", "normalizedReason", "offendingParameter", "providerErrorCode", "providerErrorType",
    ]);
  }
});

test("timeout and malformed provider envelopes fail closed without raw data", () => {
  const timeout = normalizeProviderFailure({name: "AbortError", providerCallNumber: 2,
    message: "Bearer synthetic-credential-material-should-never-appear"});
  assert.equal(timeout.failureCode, PROVIDER_FAILURE.timeout);
  assert.equal(timeout.providerDiagnostics.normalizedReason, NORMALIZED_REASON.timeout);

  const malformed = normalizeProviderFailure({status: 400,
    json: {error: "synthetic-credential-material-should-never-appear"},
    body: "Authorization: Bearer synthetic-credential-material-should-never-appear"});
  assert.equal(malformed.failureCode, PROVIDER_FAILURE.contractInvalid);
  assert.equal(malformed.providerDiagnostics.normalizedReason, NORMALIZED_REASON.invalidRequest);
  assert.equal(JSON.stringify(malformed).includes("synthetic-credential-material"), false);
  assert.equal(JSON.stringify(malformed).includes("Authorization"), false);
});

test("shadow trace preserves diagnostics but never raw provider messages", async () => {
  const providerResult = normalizeProviderFailure(response(400, {
    type: "invalid_request_error", code: "invalid_json_schema", param: "response_format",
    message: "schema rejected; Authorization: Bearer synthetic-credential-material-should-never-appear",
  }));
  const result = await runControlledDevShadowSmoke({
    runId: "diagnostic-trace-v1",
    providers: {contextClient: {run: async () => providerResult}},
    budget: {snapshot: () => ({totalDispatches: 1})},
    legacyResult: {selectedCandidateId: "legacy", persistenceRevision: "unchanged"},
  });
  const trace = result.trace[0];
  assert.equal(trace.providerDiagnostics.normalizedReason, NORMALIZED_REASON.invalidJsonSchema);
  assert.equal(trace.providerDiagnostics.offendingParameter, "response_format");
  assert.equal(JSON.stringify(trace).includes("synthetic-credential-material"), false);
  assert.equal(JSON.stringify(trace).includes("Authorization"), false);
  assert.equal(result.authoritative, false);
  assert.equal(result.shadowResult.persistenceWrites, 0);
});
