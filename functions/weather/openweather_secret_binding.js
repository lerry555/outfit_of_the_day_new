"use strict";

const {defineSecret} = require("firebase-functions/params");

const SECRET_NAME = "OPENWEATHER_API_KEY";
const OPENWEATHER_API_KEY_SECRET = defineSecret(SECRET_NAME);

function resolveOpenWeatherSecret(secret = OPENWEATHER_API_KEY_SECRET) {
  let value;
  try {
    value = secret?.value?.();
  } catch (_) {
    value = "";
  }
  if (typeof value !== "string" || !value.trim()) {
    const error = new Error("openweather_secret_unavailable");
    error.code = "openweather_secret_unavailable";
    throw error;
  }
  return value.trim();
}

module.exports = {
  SECRET_NAME,
  OPENWEATHER_API_KEY_SECRET,
  resolveOpenWeatherSecret,
};
