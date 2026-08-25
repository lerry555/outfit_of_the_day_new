"use strict";

const {defineSecret} = require("firebase-functions/params");

const SECRET_NAME = "OPENAI_API_KEY";
const CONTRACT_ID = "OpenAISecretBinding/v1";
const OPENAI_API_KEY_SECRET = defineSecret(SECRET_NAME);

function resolveOpenAISecret(secret = OPENAI_API_KEY_SECRET) {
  if (!secret || typeof secret.value !== "function") {
    fail("openai_secret_unavailable");
  }
  let value;
  try { value = secret.value(); } catch (_) { fail("openai_secret_unavailable"); }
  if (typeof value !== "string" || value.trim() === "") {
    fail("openai_secret_unavailable");
  }
  return value.trim();
}

function openAISecretAvailability(secret = OPENAI_API_KEY_SECRET) {
  try { resolveOpenAISecret(secret); return Object.freeze({available: true,
    contractId: CONTRACT_ID, secretName: SECRET_NAME}); } catch (_) {
    return Object.freeze({available: false, contractId: CONTRACT_ID,
      secretName: SECRET_NAME, reasonCode: "openai_secret_unavailable"});
  }
}

function fail(code) { const error = new Error(code); error.code = code; throw error; }

module.exports = {CONTRACT_ID, OPENAI_API_KEY_SECRET, SECRET_NAME,
  openAISecretAvailability, resolveOpenAISecret};
