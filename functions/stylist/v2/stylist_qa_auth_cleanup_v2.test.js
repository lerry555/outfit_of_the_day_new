"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  deleteQaAuthUserSelf,
  exchangeQaCustomToken,
  runQaCleanupV2,
} = require("./stylist_qa_auth_cleanup_v2");

function response(status, json) {
  return {ok: status >= 200 && status < 300, status, json: async () => json};
}

test("custom-token exchange retains the in-memory cleanup token set", async () => {
  let body = null;
  const tokens = await exchangeQaCustomToken({
    apiKey: "api-key-secret",
    customToken: "custom-token-secret",
    fetchImpl: async (_url, options) => {
      body = JSON.parse(options.body);
      return response(200, {
        idToken: "id-token-secret",
        refreshToken: "refresh-token-secret",
        localId: "synthetic-uid",
        expiresIn: "3600",
      });
    },
  });
  assert.deepEqual(tokens, {
    idToken: "id-token-secret",
    refreshToken: "refresh-token-secret",
    localId: "synthetic-uid",
    expiresIn: "3600",
  });
  assert.deepEqual(body, {token: "custom-token-secret", returnSecureToken: true});
});

test("self-delete succeeds with the current QA user's ID token", async () => {
  const calls = [];
  const result = await deleteQaAuthUserSelf({
    apiKey: "api-key-secret",
    authTokens: {idToken: "id-token-secret", refreshToken: "refresh-token-secret"},
    fetchImpl: async (url, options) => {
      calls.push({url, body: JSON.parse(options.body)});
      return response(200, {});
    },
  });
  assert.deepEqual(result, {deleted: true, deleteAttempts: 1, tokenRefreshed: false});
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].body, {idToken: "id-token-secret"});
});

test("INVALID_ID_TOKEN refreshes once and retries delete once", async () => {
  const calls = [];
  const result = await deleteQaAuthUserSelf({
    apiKey: "api-key-secret",
    authTokens: {idToken: "stale-id-secret", refreshToken: "refresh-token-secret"},
    fetchImpl: async (url, options) => {
      calls.push({url, body: options.body});
      if (calls.length === 1) return response(400, {error: {message: "INVALID_ID_TOKEN"}});
      if (calls.length === 2) return response(200, {id_token: "fresh-id-secret"});
      return response(200, {});
    },
  });
  assert.deepEqual(result, {deleted: true, deleteAttempts: 2, tokenRefreshed: true});
  assert.equal(calls.length, 3);
  assert.match(calls[1].url, /securetoken\.googleapis\.com/);
  assert.deepEqual(JSON.parse(calls[2].body), {idToken: "fresh-id-secret"});
});

test("refresh failure fails safely without a second delete", async () => {
  const calls = [];
  await assert.rejects(deleteQaAuthUserSelf({
    apiKey: "api-key-secret",
    authTokens: {idToken: "stale-id-secret", refreshToken: "refresh-token-secret"},
    fetchImpl: async (url) => {
      calls.push(url);
      return calls.length === 1 ? response(400, {error: {message: "INVALID_ID_TOKEN"}}) :
        response(400, {error: {message: "INVALID_REFRESH_TOKEN"}});
    },
  }), /qa_token_refresh_PROVIDER_REJECTED:400/);
  assert.equal(calls.length, 2);
});

test("non-token delete failure fails without refresh or retry", async () => {
  let calls = 0;
  await assert.rejects(deleteQaAuthUserSelf({
    apiKey: "api-key-secret",
    authTokens: {idToken: "id-token-secret", refreshToken: "refresh-token-secret"},
    fetchImpl: async () => {
      calls += 1;
      return response(500, {error: {message: "INTERNAL_ERROR"}});
    },
  }), /qa_auth_self_delete_PROVIDER_REJECTED:500/);
  assert.equal(calls, 1);
});

test("normal cleanup contains no Auth enumeration path", () => {
  for (const file of ["stylist_qa_auth_cleanup_v2.js", "stylist_production_smoke_v2.js"]) {
    const source = fs.readFileSync(path.join(__dirname, file), "utf8");
    assert.doesNotMatch(source, /listUsers|deleteUser\s*\(/);
  }
});

test("token values never appear in emitted errors or source logging", async () => {
  const secrets = ["id-token-secret", "refresh-token-secret", "api-key-secret"];
  let errorText = "";
  try {
    await deleteQaAuthUserSelf({
      apiKey: secrets[2],
      authTokens: {idToken: secrets[0], refreshToken: secrets[1]},
      fetchImpl: async () => response(403, {error: {message: `DENIED ${secrets.join(" ")}`}}),
    });
  } catch (error) {
    errorText = String(error);
  }
  for (const secret of secrets) assert.doesNotMatch(errorText, new RegExp(secret));
  const source = fs.readFileSync(path.join(__dirname, "stylist_qa_auth_cleanup_v2.js"), "utf8");
  assert.doesNotMatch(source, /console\.(?:log|info|warn|error)/);
});

test("Firestore cleanup executes even when Auth self-delete fails", async () => {
  let firestoreCalls = 0;
  let authCalls = 0;
  await assert.rejects(runQaCleanupV2({
    firestoreCleanup: async () => { firestoreCalls += 1; },
    authCleanup: async () => { authCalls += 1; throw new Error("auth failure"); },
  }), /qa_cleanup_failed_auth/);
  assert.equal(firestoreCalls, 1);
  assert.equal(authCalls, 1);
});

test("Auth cleanup executes after an earlier QA assertion failure", async () => {
  let authCalls = 0;
  let primaryError = null;
  try {
    throw new Error("qa assertion failed");
  } catch (error) {
    primaryError = error;
  } finally {
    await runQaCleanupV2({
      firestoreCleanup: async () => {},
      authCleanup: async () => { authCalls += 1; return {deleted: true}; },
    });
  }
  assert.equal(primaryError.message, "qa assertion failed");
  assert.equal(authCalls, 1);
});
