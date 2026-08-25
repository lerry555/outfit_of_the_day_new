"use strict";

/**
 * Production-ready generic HTTP partner adapter skeleton.
 * Not bound to any retailer. Does not make live retailer requests unless
 * an owner-approved baseUrl + secrets are injected (tests use mock HTTP).
 *
 * REAL_PARTNER_API_REQUESTS for qualification remains 0 when using mocks.
 */

const {PARTNER_CAPABILITY} = require("./partner_capabilities");
const {createBasePartnerAdapter} = require("./partner_normalize");
const {createPartnerError, PARTNER_ERROR} = require("./partner_errors");
const {resolvePartnerSecret} = require("./partner_secrets");
const {fetchJson} = require("./http/mock_partner_http");

const ADAPTER_KEY = "generic_http_partner_skeleton";
const ADAPTER_VERSION = "1";

function createGenericHttpPartnerAdapterSkeleton({
  publicConfig,
  mapResponseToRecords,
  fetchImpl,
  getSecret,
} = {}) {
  if (!publicConfig || typeof mapResponseToRecords !== "function") {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "generic_http_adapter_config_required",
    );
  }

  const capabilities = normalizeCaps(publicConfig.capabilities);

  return createBasePartnerAdapter({
    publicConfig: {
      ...publicConfig,
      adapterKey: publicConfig.adapterKey || ADAPTER_KEY,
      adapterVersion: publicConfig.adapterVersion || ADAPTER_VERSION,
      capabilities,
    },
    privateConfigDefaults: {
      authMethod: "bearer",
      secretRef: publicConfig.secretRef || "SHOPPING_PARTNER_SECRET_SLOT_A",
      rateLimit: publicConfig.rateLimit || {
        pageSize: 100,
        requestsPerSecond: 2,
        requestsPerMinute: 60,
      },
    },
    async fetchPage({pageToken, pageSize, privateConfig, mode}) {
      const baseUrl = privateConfig?.baseUrl;
      if (!baseUrl) {
        throw createPartnerError(
          PARTNER_ERROR.FATAL_CONFIGURATION,
          "partner_base_url_required",
        );
      }
      // Hard block: refuse arbitrary client-supplied URLs outside private config.
      let parsed;
      try {
        parsed = new URL(baseUrl);
      } catch (_) {
        throw createPartnerError(
          PARTNER_ERROR.FATAL_CONFIGURATION,
          "partner_base_url_invalid",
        );
      }
      if (parsed.protocol !== "https:" && parsed.hostname !== "127.0.0.1" &&
          parsed.hostname !== "localhost") {
        // Allow http only for local mock harness qualification.
        throw createPartnerError(
          PARTNER_ERROR.FATAL_CONFIGURATION,
          "partner_base_url_requires_https",
        );
      }

      let token = null;
      if (privateConfig?.secretRef || getSecret) {
        token = resolvePartnerSecret({
          secretRef: privateConfig.secretRef,
          getSecret: getSecret || (() => privateConfig._resolvedSecrets?.apiKey),
        });
      }

      const url = new URL("/catalog", baseUrl);
      url.searchParams.set("mode", mode);
      url.searchParams.set("pageSize", String(pageSize));
      if (pageToken) url.searchParams.set("pageToken", String(pageToken));

      const json = await fetchJson(url.toString(), {
        headers: token ? {authorization: `Bearer ${token}`} : {},
        fetchImpl,
      });

      if (!json || typeof json !== "object") {
        throw createPartnerError(
          PARTNER_ERROR.INVALID_PAYLOAD,
          "partner_http_empty_body",
        );
      }
      if (json.schemaVersion != null && Number(json.schemaVersion) !== 1) {
        throw createPartnerError(
          PARTNER_ERROR.SCHEMA_CHANGED,
          "partner_http_schema_changed",
        );
      }

      const records = mapResponseToRecords(json);
      return {
        records,
        nextPageToken: json.nextPageToken || null,
        done: json.done === true || !json.nextPageToken,
        completenessGuaranteed: mode === "FULL" &&
          (json.done === true || !json.nextPageToken) &&
          json.completenessGuaranteed === true,
      };
    },
  });
}

function normalizeCaps(raw) {
  const list = Array.isArray(raw) ? [...raw] : [];
  if (!list.includes(PARTNER_CAPABILITY.PAGINATION)) {
    list.push(PARTNER_CAPABILITY.PAGINATION);
  }
  return list;
}

module.exports = {
  ADAPTER_KEY,
  ADAPTER_VERSION,
  createGenericHttpPartnerAdapterSkeleton,
};
