"use strict";

class QaAuthCleanupError extends Error {
  constructor(code, status = null) {
    super(status == null ? code : `${code}:${status}`);
    this.name = "QaAuthCleanupError";
    this.code = code;
    this.status = status;
  }
}

function requiredText(value, code) {
  const text = typeof value === "string" ? value.trim() : "";
  if (!text) throw new QaAuthCleanupError(code);
  return text;
}

function providerCode(json) {
  const value = String(json?.error?.message || "").trim().toUpperCase();
  if (value.startsWith("INVALID_ID_TOKEN")) return "INVALID_ID_TOKEN";
  if (value.startsWith("TOKEN_EXPIRED")) return "INVALID_ID_TOKEN";
  if (value.startsWith("USER_NOT_FOUND")) return "USER_NOT_FOUND";
  return "PROVIDER_REJECTED";
}

async function readJson(response) {
  try {
    return await response.json();
  } catch (_) {
    return {};
  }
}

async function exchangeQaCustomToken({apiKey, customToken, fetchImpl = fetch} = {}) {
  apiKey = requiredText(apiKey, "qa_api_key_required");
  customToken = requiredText(customToken, "qa_custom_token_required");
  if (typeof fetchImpl !== "function") throw new QaAuthCleanupError("qa_fetch_required");
  const response = await fetchImpl(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({token: customToken, returnSecureToken: true}),
    },
  );
  const json = await readJson(response);
  if (!response?.ok) {
    throw new QaAuthCleanupError(`qa_token_exchange_${providerCode(json)}`, response?.status ?? null);
  }
  return Object.freeze({
    idToken: requiredText(json.idToken, "qa_id_token_missing"),
    refreshToken: requiredText(json.refreshToken, "qa_refresh_token_missing"),
    localId: typeof json.localId === "string" ? json.localId.trim() : "",
    expiresIn: typeof json.expiresIn === "string" ? json.expiresIn.trim() : "",
  });
}

async function refreshQaIdToken({apiKey, refreshToken, fetchImpl = fetch} = {}) {
  apiKey = requiredText(apiKey, "qa_api_key_required");
  refreshToken = requiredText(refreshToken, "qa_refresh_token_required");
  if (typeof fetchImpl !== "function") throw new QaAuthCleanupError("qa_fetch_required");
  const response = await fetchImpl(
    `https://securetoken.googleapis.com/v1/token?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: new URLSearchParams({grant_type: "refresh_token", refresh_token: refreshToken}).toString(),
    },
  );
  const json = await readJson(response);
  if (!response?.ok) {
    throw new QaAuthCleanupError(`qa_token_refresh_${providerCode(json)}`, response?.status ?? null);
  }
  return requiredText(json.id_token, "qa_refreshed_id_token_missing");
}

async function deleteQaAuthUserSelf({apiKey, authTokens, fetchImpl = fetch} = {}) {
  apiKey = requiredText(apiKey, "qa_api_key_required");
  if (typeof fetchImpl !== "function") throw new QaAuthCleanupError("qa_fetch_required");
  let idToken = requiredText(authTokens?.idToken, "qa_id_token_required");
  const refreshToken = requiredText(authTokens?.refreshToken, "qa_refresh_token_required");
  let refreshed = false;
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    const response = await fetchImpl(
      `https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({idToken}),
      },
    );
    const json = await readJson(response);
    if (response?.ok && response.status === 200) {
      return Object.freeze({deleted: true, deleteAttempts: attempt, tokenRefreshed: refreshed});
    }
    const code = providerCode(json);
    if (attempt === 1 && code === "INVALID_ID_TOKEN") {
      idToken = await refreshQaIdToken({apiKey, refreshToken, fetchImpl});
      refreshed = true;
      continue;
    }
    throw new QaAuthCleanupError(`qa_auth_self_delete_${code}`, response?.status ?? null);
  }
  throw new QaAuthCleanupError("qa_auth_self_delete_exhausted");
}

async function runQaCleanupV2({firestoreCleanup, authCleanup} = {}) {
  if (typeof firestoreCleanup !== "function" || typeof authCleanup !== "function") {
    throw new QaAuthCleanupError("qa_cleanup_steps_required");
  }
  let firestoreError = null;
  let authError = null;
  let authResult = null;
  try {
    await firestoreCleanup();
  } catch (error) {
    firestoreError = error;
  }
  try {
    authResult = await authCleanup();
  } catch (error) {
    authError = error;
  }
  if (firestoreError || authError) {
    const parts = [];
    if (firestoreError) parts.push("firestore");
    if (authError) parts.push("auth");
    throw new QaAuthCleanupError(`qa_cleanup_failed_${parts.join("_")}`);
  }
  return Object.freeze({ok: true, auth: authResult});
}

module.exports = {
  QaAuthCleanupError,
  deleteQaAuthUserSelf,
  exchangeQaCustomToken,
  refreshQaIdToken,
  runQaCleanupV2,
};
