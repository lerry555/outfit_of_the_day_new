"use strict";

const {
  ADAPTER_KEY: FIXTURE_KEY,
  createFixturePartnerAdapter,
} = require("../adapters/fixture_partner_adapter");
const {
  ADAPTER_KEY: GENERIC_HTTP_KEY,
  createGenericHttpPartnerAdapterSkeleton,
} = require("./generic_http_adapter_skeleton");
const {
  ADAPTER_KEY: PARTNER_A_KEY,
  createSyntheticPartnerAAdapter,
} = require("./synthetic/partner_a");
const {
  ADAPTER_KEY: PARTNER_B_KEY,
  createSyntheticPartnerBAdapter,
} = require("./synthetic/partner_b");
const {
  ADAPTER_KEY: PARTNER_C_KEY,
  createSyntheticPartnerCAdapter,
} = require("./synthetic/partner_c");
const {
  ADAPTER_KEY: RESERVED_CJ_KEY,
  createReservedCjAdapter,
} = require("./reserved/reserved_cj_adapter");
const {PARTNER_ID: RESERVED_SK_ID} = require("./reserved/reserved_cj_constants");
const {createPartnerError, PARTNER_ERROR} = require("./partner_errors");

const REGISTRY = Object.freeze({
  [FIXTURE_KEY]: ({config}) => createFixturePartnerAdapter(config),
  [PARTNER_A_KEY]: (opts) => createSyntheticPartnerAAdapter(opts),
  [PARTNER_B_KEY]: (opts) => createSyntheticPartnerBAdapter(opts),
  [PARTNER_C_KEY]: (opts) => createSyntheticPartnerCAdapter(opts),
  [GENERIC_HTTP_KEY]: (opts) => createGenericHttpPartnerAdapterSkeleton(opts),
  [RESERVED_CJ_KEY]: (opts) => createReservedCjAdapter(opts),
});

function listRegisteredAdapterKeys() {
  return Object.keys(REGISTRY).sort();
}

function createPartnerAdapter(adapterKey, options = {}) {
  const factory = REGISTRY[adapterKey];
  if (!factory) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_adapter_not_registered",
    );
  }
  return factory(options);
}

/** Owner-selected first partner (Phase 8B). Live sync still DISABLED. */
const OWNER_APPROVED_FIRST_PARTNER_ID = RESERVED_SK_ID;
const FIRST_REAL_PARTNER_STATUS =
  "RESERVED_SK_CJ_ONBOARDING_READY_FOR_OWNER_ACTION";
const ALTERNATE_PARTNER = Object.freeze({
  partnerId: "sinsay_sk",
  network: "tradedoubler",
  note: "Alternate only — do not switch unless Reserved/CJ route invalid",
});

module.exports = {
  ALTERNATE_PARTNER,
  FIRST_REAL_PARTNER_STATUS,
  OWNER_APPROVED_FIRST_PARTNER_ID,
  createPartnerAdapter,
  listRegisteredAdapterKeys,
};
