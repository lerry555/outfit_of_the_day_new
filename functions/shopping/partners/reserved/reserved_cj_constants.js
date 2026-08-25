"use strict";

const PARTNER_ID = "reserved_sk";
const ADAPTER_KEY = "reserved_cj";
const ADAPTER_VERSION = "0.1.0-pending-sample";
const DISPLAY_NAME = "Reserved";
const MARKET = "SK";
const EXPECTED_CURRENCY = "EUR";
const NETWORK = "cj";

/** Public marketing domains — tracking/affiliate hosts remain SAMPLE_REQUIRED. */
const KNOWN_MERCHANT_DOMAINS = Object.freeze([
  "reserved.com",
  "www.reserved.com",
]);

/**
 * CJ tracking/deep-link host patterns often appear in affiliate feeds.
 * Exact hosts for Reserved SK: SAMPLE_REQUIRED from real feed.
 */
const CJ_TRACKING_DOMAIN_STATUS = "SAMPLE_REQUIRED";

const PRODUCTION_SYNC_STATUS = "DISABLED";
const FEED_PROFILE_STATUS = "PENDING_SAMPLE";

/** VIVnetworks join deep-link advertiser cid (secondary catalog). Confirm in CJ UI. */
const RESERVED_CJ_JOIN_CID_HINT = "6449422";
const RESERVED_CJ_JOIN_CID_STATUS = "REQUIRES_ACCOUNT_ACCESS";

module.exports = {
  ADAPTER_KEY,
  ADAPTER_VERSION,
  CJ_TRACKING_DOMAIN_STATUS,
  DISPLAY_NAME,
  EXPECTED_CURRENCY,
  FEED_PROFILE_STATUS,
  KNOWN_MERCHANT_DOMAINS,
  MARKET,
  NETWORK,
  PARTNER_ID,
  PRODUCTION_SYNC_STATUS,
  RESERVED_CJ_JOIN_CID_HINT,
  RESERVED_CJ_JOIN_CID_STATUS,
};
