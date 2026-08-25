"use strict";

/**
 * Partner secret binding — Firebase Functions secrets (defineSecret) path.
 * Phase 8 does NOT introduce functions.config() usage.
 * No real partner secrets are required for generic qualification.
 */

const {defineSecret} = require("firebase-functions/params");
const {createPartnerError, PARTNER_ERROR} = require("./partner_errors");

const CONTRACT_ID = "ShoppingPartnerSecretBinding/v1";

/**
 * Named secret placeholders for future partners. Not bound to production
 * Functions exports until an owner-approved partner is selected.
 * Using defineSecret declares the Secret Manager contract without requiring
 * a deployed value during local qualification.
 */
const PARTNER_SECRET_SLOT_A = defineSecret("SHOPPING_PARTNER_SECRET_SLOT_A");
const PARTNER_SECRET_SLOT_B = defineSecret("SHOPPING_PARTNER_SECRET_SLOT_B");

const {
  CJ_PERSONAL_ACCESS_TOKEN_SECRET,
  CJ_PERSONAL_ACCESS_TOKEN_SECRET_NAME,
  CJ_SECRET_CONTRACT_ID,
  CJ_CONFIG_KEYS,
} = require("./cj/cj_auth_contract");

const NEW_LEGACY_FUNCTIONS_CONFIG_USAGE_COUNT = 0;

/**
 * Resolve a partner secret from an injected getter (tests) or Secret Manager.
 * Never logs the value. Never falls back to functions.config().
 */
function resolvePartnerSecret({
  secretRef,
  getSecret,
  secretParam,
} = {}) {
  if (typeof getSecret === "function") {
    const value = getSecret(secretRef);
    if (typeof value === "string" && value.trim()) return value.trim();
    throw createPartnerError(PARTNER_ERROR.AUTH_ERROR, "partner_secret_missing");
  }
  if (secretParam && typeof secretParam.value === "function") {
    try {
      const value = secretParam.value();
      if (typeof value === "string" && value.trim()) return value.trim();
    } catch (_) {
      throw createPartnerError(
        PARTNER_ERROR.AUTH_ERROR, "partner_secret_unavailable",
      );
    }
    throw createPartnerError(PARTNER_ERROR.AUTH_ERROR, "partner_secret_empty");
  }
  throw createPartnerError(
    PARTNER_ERROR.FATAL_CONFIGURATION,
    "partner_secret_resolver_unconfigured",
  );
}

/**
 * Build a redacted private diagnostics object — never includes secret values.
 */
function redactPrivateConfig(privateConfig) {
  if (!privateConfig || typeof privateConfig !== "object") return null;
  return {
    partnerId: privateConfig.partnerId || null,
    adapterKey: privateConfig.adapterKey || null,
    adapterVersion: privateConfig.adapterVersion || null,
    authMethod: privateConfig.authMethod || null,
    secretRef: privateConfig.secretRef || null,
    webhookSecretRef: privateConfig.webhookSecretRef || null,
    hasResolvedSecrets: Boolean(privateConfig._resolvedSecrets),
    rateLimit: privateConfig.rateLimit || null,
    checkpoint: privateConfig.checkpoint || null,
  };
}

module.exports = {
  CONTRACT_ID,
  NEW_LEGACY_FUNCTIONS_CONFIG_USAGE_COUNT,
  PARTNER_SECRET_SLOT_A,
  PARTNER_SECRET_SLOT_B,
  CJ_CONFIG_KEYS,
  CJ_PERSONAL_ACCESS_TOKEN_SECRET,
  CJ_PERSONAL_ACCESS_TOKEN_SECRET_NAME,
  CJ_SECRET_CONTRACT_ID,
  redactPrivateConfig,
  resolvePartnerSecret,
};
