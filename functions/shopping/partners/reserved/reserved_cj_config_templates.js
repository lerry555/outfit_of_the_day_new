"use strict";

const {
  ADAPTER_KEY,
  ADAPTER_VERSION,
  DISPLAY_NAME,
  EXPECTED_CURRENCY,
  KNOWN_MERCHANT_DOMAINS,
  MARKET,
  PARTNER_ID,
  PRODUCTION_SYNC_STATUS,
} = require("./reserved_cj_constants");
const {CJ_CONFIG_KEYS} = require("../cj/cj_auth_contract");
const {DEFAULT_RIGHTS_STATE} = require("./rights_and_preflight");
const {PARTNER_STATUS} = require("../partner_config");

function buildReservedPublicPartnerTemplate() {
  return Object.freeze({
    partnerId: PARTNER_ID,
    displayName: DISPLAY_NAME,
    publicStoreName: DISPLAY_NAME,
    status: PARTNER_STATUS.DISABLED,
    market: MARKET,
    currency: EXPECTED_CURRENCY,
    allowedDomains: [...KNOWN_MERCHANT_DOMAINS],
    capabilities: [],
    adapterKey: ADAPTER_KEY,
    adapterVersion: ADAPTER_VERSION,
    note: "Not surfaced until live adapter approval after sample + rights",
  });
}

function buildReservedPrivatePartnerTemplate() {
  return Object.freeze({
    partnerId: PARTNER_ID,
    adapterKey: ADAPTER_KEY,
    adapterVersion: ADAPTER_VERSION,
    status: "DISABLED_PENDING_ACCESS",
    productionSyncStatus: PRODUCTION_SYNC_STATUS,
    market: MARKET,
    expectedCurrency: EXPECTED_CURRENCY,
    authMethod: "cj_bearer_pat",
    secretRef: CJ_CONFIG_KEYS.personalAccessTokenSecretRef,
    [CJ_CONFIG_KEYS.companyId]: null,
    [CJ_CONFIG_KEYS.websiteIdPid]: null,
    [CJ_CONFIG_KEYS.reservedAdvertiserCompanyId]: null,
    baseUrl: null,
    feedMode: "UNKNOWN",
    feedUrlPlaceholder: null,
    productSearchEndpoint: "https://ads.api.cj.com/query",
    rateLimit: null,
    syncCadence: null,
    checkpoint: null,
    rights: {...DEFAULT_RIGHTS_STATE},
    allowedDomains: [...KNOWN_MERCHANT_DOMAINS],
    cjTrackingDomains: null,
  });
}

module.exports = {
  buildReservedPrivatePartnerTemplate,
  buildReservedPublicPartnerTemplate,
};
