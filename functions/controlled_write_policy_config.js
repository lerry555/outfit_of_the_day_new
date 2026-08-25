"use strict";

const {defineSecret} = require("firebase-functions/params");
const {decodeControlledWritePolicy} = require("./controlled_write_activation_policy");

const SECRET_NAME = "WARDROBE_CONTROLLED_WRITE_POLICY";
const CONTRACT_ID = "ControlledWritePolicyConfiguration/v1";
const WARDROBE_CONTROLLED_WRITE_POLICY_SECRET = defineSecret(SECRET_NAME);

function resolveControlledWritePolicy(secret = WARDROBE_CONTROLLED_WRITE_POLICY_SECRET) {
  if (!secret || typeof secret.value !== "function") fail("controlled_write_policy_missing");
  let raw;
  try { raw = secret.value(); } catch (_) { fail("controlled_write_policy_missing"); }
  if (typeof raw !== "string" || !raw.trim()) fail("controlled_write_policy_missing");
  let parsed;
  try { parsed = JSON.parse(raw); } catch (_) { fail("controlled_write_policy_invalid"); }
  return decodeControlledWritePolicy(parsed);
}

function controlledWritePolicyAvailability(secret) {
  try { const policy = resolveControlledWritePolicy(secret);
    return Object.freeze({available: true, contractId: CONTRACT_ID,
      secretName: SECRET_NAME, enabled: policy.enabled,
      reasonCode: "controlled_write_policy_config_ready"});
  } catch (error) { return Object.freeze({available: false,
    contractId: CONTRACT_ID, secretName: SECRET_NAME,
    reasonCode: error.message || "controlled_write_policy_invalid"}); }
}
function fail(code) { const error = new Error(code); error.code = code; throw error; }

module.exports = {CONTRACT_ID, SECRET_NAME, WARDROBE_CONTROLLED_WRITE_POLICY_SECRET,
  controlledWritePolicyAvailability, resolveControlledWritePolicy};
