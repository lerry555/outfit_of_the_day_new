"use strict";

const {defineSecret} = require("firebase-functions/params");

const OPENAI_API_KEY_SECRET = defineSecret("OPENAI_API_KEY");
const ANTHROPIC_API_KEY_SECRET = defineSecret("ANTHROPIC_API_KEY");

function resolve(secret, failureCode) {
  try {
    const value = secret && typeof secret.value === "function" ? secret.value() : "";
    if (typeof value === "string" && value.trim()) return value.trim();
  } catch (_) {
    // Never include a secret, provider body or error material in this path.
  }
  const error = new Error(failureCode);
  error.code = failureCode;
  throw error;
}

function resolveOpenAISecret(secret = OPENAI_API_KEY_SECRET) {
  return resolve(secret, "openai_secret_unavailable");
}

function resolveAnthropicSecret(secret = ANTHROPIC_API_KEY_SECRET) {
  return resolve(secret, "anthropic_secret_unavailable");
}

module.exports = {
  OPENAI_API_KEY_SECRET,
  ANTHROPIC_API_KEY_SECRET,
  resolveOpenAISecret,
  resolveAnthropicSecret,
};
