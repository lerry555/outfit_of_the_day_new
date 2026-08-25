"use strict";

const {defineSecret} = require("firebase-functions/params");
const {decodeControlledShadowPolicy} =
  require("./controlled_shadow_activation_policy");

const SECRET_NAME = "WARDROBE_SHADOW_POLICY";
const CONTRACT_ID = "ControlledShadowPolicyConfiguration/v1";
const WARDROBE_SHADOW_POLICY_SECRET = defineSecret(SECRET_NAME);

/** Lazy runtime-only resolver. Never log or return the raw secret payload. */
function resolveControlledShadowPolicy(
  secret = WARDROBE_SHADOW_POLICY_SECRET,
) {
  if (!secret || typeof secret.value !== "function") {
    fail("shadow_policy_secret_unavailable");
  }
  let raw;
  try { raw = secret.value(); } catch (_) {
    fail("shadow_policy_secret_unavailable");
  }
  if (typeof raw !== "string" || !raw.trim()) {
    fail("shadow_policy_secret_unavailable");
  }
  let parsed;
  try { parsed = JSON.parse(raw); } catch (_) {
    fail("shadow_policy_json_invalid");
  }
  return decodeControlledShadowPolicy(parsed);
}

function controlledShadowPolicyAvailability(secret) {
  try {
    const policy = resolveControlledShadowPolicy(secret);
    return Object.freeze({available: true, contractId: CONTRACT_ID,
      secretName: SECRET_NAME, enabled: policy.enabled,
      reasonCode: "shadow_policy_config_ready"});
  } catch (error) {
    return Object.freeze({available: false, contractId: CONTRACT_ID,
      secretName: SECRET_NAME,
      reasonCode: error.code || error.message || "shadow_policy_config_invalid"});
  }
}

function fail(code) {
  const error = new Error(code); error.code = code; throw error;
}

module.exports = {CONTRACT_ID, SECRET_NAME, WARDROBE_SHADOW_POLICY_SECRET,
  controlledShadowPolicyAvailability, resolveControlledShadowPolicy};
