"use strict";

/**
 * Production Gemini API key binding (server-side only).
 * Mirrors OpenAI secret pattern without importing benchmark modules.
 */

const {defineSecret} = require("firebase-functions/params");

const SECRET_NAME = "GEMINI_API_KEY";
const CONTRACT_ID = "GeminiSecretBinding/v1";
const GEMINI_API_KEY_SECRET = defineSecret(SECRET_NAME);

function resolveGeminiSecret(secret = GEMINI_API_KEY_SECRET) {
  if (!secret || typeof secret.value !== "function") {
    fail("gemini_secret_unavailable");
  }
  let value;
  try {
    value = secret.value();
  } catch (_) {
    fail("gemini_secret_unavailable");
  }
  if (typeof value !== "string" || value.trim() === "") {
    fail("gemini_secret_unavailable");
  }
  return value.trim();
}

/**
 * Dev/test helper: prefer injected getter, then env, then secret param.
 * @param {() => string} [getApiKey]
 */
function resolveGeminiApiKey(getApiKey) {
  if (typeof getApiKey === "function") {
    const v = getApiKey();
    if (typeof v === "string" && v.trim()) return v.trim();
    fail("gemini_api_key_missing");
  }
  const env = process.env.GEMINI_API_KEY;
  if (typeof env === "string" && env.trim()) return env.trim();
  return resolveGeminiSecret();
}

function fail(code) {
  const error = new Error(code);
  error.code = code;
  throw error;
}

module.exports = {
  CONTRACT_ID,
  SECRET_NAME,
  GEMINI_API_KEY_SECRET,
  resolveGeminiSecret,
  resolveGeminiApiKey,
};
