"use strict";

const {assertText, normalizeAllowedDomains} = require("../catalog_contract");
const {normalizeCapabilities} = require("./partner_capabilities");
const {normalizeRateLimit} = require("./partner_rate_limit");
const {createPartnerError, PARTNER_ERROR} = require("./partner_errors");

const PARTNER_STATUS = Object.freeze({
  ACTIVE: "ACTIVE",
  DEGRADED: "DEGRADED",
  AUTH_ERROR: "AUTH_ERROR",
  SCHEMA_ERROR: "SCHEMA_ERROR",
  DISABLED: "DISABLED",
});

const PARTNER_HEALTH = Object.freeze({...PARTNER_STATUS});

/**
 * Public partner projection — safe for catalogPartners / client-readable paths.
 * Never includes credentials, endpoints, or secrets.
 */
function buildPublicPartnerConfig(raw) {
  if (!raw || typeof raw !== "object") {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_public_config_required",
    );
  }
  const partnerId = assertText(raw.partnerId, "partner_id");
  if (!/^[a-z0-9_]{2,64}$/.test(partnerId)) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_id_invalid_format",
    );
  }
  const status = String(raw.status || PARTNER_STATUS.ACTIVE).trim().toUpperCase();
  if (!Object.values(PARTNER_STATUS).includes(status)) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_status_invalid",
    );
  }
  const market = assertText(raw.market, "partner_market").toUpperCase();
  if (!/^[A-Z]{2,3}$/.test(market)) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_market_invalid",
    );
  }
  return Object.freeze({
    partnerId,
    displayName: assertText(raw.displayName || raw.publicStoreName, "partner_display_name"),
    publicStoreName: assertText(
      raw.publicStoreName || raw.displayName, "partner_public_name",
    ),
    status,
    market,
    currency: String(raw.currency || "").trim().toUpperCase() || null,
    allowedDomains: normalizeAllowedDomains(raw.allowedDomains),
    capabilities: normalizeCapabilities(raw.capabilities),
    adapterKey: assertText(raw.adapterKey, "adapter_key"),
    adapterVersion: assertText(raw.adapterVersion, "adapter_version"),
  });
}

/**
 * Private integration config — backend-only (partnerIntegrations / secrets).
 * Must never be written to client-readable collections or Flutter source.
 */
function buildPrivatePartnerConfig(raw, {secrets = null} = {}) {
  if (!raw || typeof raw !== "object") {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_private_config_required",
    );
  }
  const partnerId = assertText(raw.partnerId, "partner_id");
  const rateLimit = normalizeRateLimit(raw.rateLimit || {});
  const privateConfig = {
    partnerId,
    adapterKey: assertText(raw.adapterKey, "adapter_key"),
    adapterVersion: assertText(raw.adapterVersion, "adapter_version"),
    // Sensitive endpoint may be present; never project publicly.
    baseUrl: raw.baseUrl == null ? null : String(raw.baseUrl),
    authMethod: raw.authMethod == null ? null : String(raw.authMethod),
    secretRef: raw.secretRef == null ? null : String(raw.secretRef),
    webhookSecretRef: raw.webhookSecretRef == null ?
      null : String(raw.webhookSecretRef),
    rateLimit,
    operationalLimits: {
      maxPagesPerRun: rateLimit.maxPagesPerRun,
      pageSize: rateLimit.pageSize,
    },
    checkpoint: sanitizeCheckpoint(raw.checkpoint),
    rawPartnerConfig: sanitizeRawPartnerConfig(raw.rawPartnerConfig),
    // Injected resolved secrets for tests / runtime — never persist.
    _resolvedSecrets: secrets == null ? null : Object.freeze({...secrets}),
  };
  return privateConfig;
}

function sanitizeCheckpoint(raw) {
  if (raw == null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_checkpoint_invalid",
    );
  }
  return {
    cursor: raw.cursor == null ? null : String(raw.cursor),
    pageToken: raw.pageToken == null ? null : String(raw.pageToken),
    mode: raw.mode == null ? null : String(raw.mode),
    updatedAt: raw.updatedAt == null ? null : String(raw.updatedAt),
    lastPersistedPage: raw.lastPersistedPage == null ?
      null : Number(raw.lastPersistedPage),
  };
}

function sanitizeRawPartnerConfig(raw) {
  if (raw == null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_raw_config_invalid",
    );
  }
  // Strip credential-looking keys defensively.
  const out = {};
  for (const [key, value] of Object.entries(raw)) {
    const lower = key.toLowerCase();
    if (/(secret|password|token|apikey|api_key|credential)/.test(lower)) {
      continue;
    }
    out[key] = value;
  }
  return out;
}

function validatePartnerConfiguration({publicConfig, privateConfig}) {
  const pub = buildPublicPartnerConfig(publicConfig);
  const priv = buildPrivatePartnerConfig(privateConfig);
  if (pub.partnerId !== priv.partnerId) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_config_id_mismatch",
    );
  }
  if (pub.adapterKey !== priv.adapterKey) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_adapter_key_mismatch",
    );
  }
  if (pub.status === PARTNER_STATUS.DISABLED) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_disabled",
    );
  }
  return {publicConfig: pub, privateConfig: priv};
}

function projectPublicPartner(partner) {
  const {
    partnerId, displayName, publicStoreName, status, market, currency,
    allowedDomains, capabilities, adapterKey, adapterVersion,
  } = buildPublicPartnerConfig(partner);
  return {
    partnerId,
    displayName,
    publicStoreName,
    status,
    market,
    currency,
    allowedDomains,
    capabilities,
    adapterKey,
    adapterVersion,
  };
}

module.exports = {
  PARTNER_HEALTH,
  PARTNER_STATUS,
  buildPrivatePartnerConfig,
  buildPublicPartnerConfig,
  projectPublicPartner,
  sanitizeCheckpoint,
  validatePartnerConfiguration,
};
