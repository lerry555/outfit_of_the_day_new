"use strict";

const {defineSecret} = require("firebase-functions/params");

const OPENAI_SECRET_NAME = "OPENAI_API_KEY";
const ANTHROPIC_SECRET_NAME = "ANTHROPIC_API_KEY";
const OPENAI_API_KEY_SECRET = defineSecret(OPENAI_SECRET_NAME);
const ANTHROPIC_API_KEY_SECRET = defineSecret(ANTHROPIC_SECRET_NAME);

function resolveBoundSecret(secret, failureCode) {
  if (!secret || typeof secret.value !== "function") fail(failureCode);
  let value;
  try { value = secret.value(); } catch (_) { fail(failureCode); }
  if (typeof value !== "string" || !value.trim()) fail(failureCode);
  return value.trim();
}

function resolveOpenAISecret(secret = OPENAI_API_KEY_SECRET) {
  return resolveBoundSecret(secret, "openai_secret_unavailable");
}

function resolveAnthropicSecret(secret = ANTHROPIC_API_KEY_SECRET) {
  return resolveBoundSecret(secret, "anthropic_secret_unavailable");
}

function fail(code) { const error = new Error(code); error.code = code; throw error; }

module.exports = {
  OPENAI_SECRET_NAME,
  ANTHROPIC_SECRET_NAME,
  OPENAI_API_KEY_SECRET,
  ANTHROPIC_API_KEY_SECRET,
  resolveOpenAISecret,
  resolveAnthropicSecret,
};
