"use strict";

/**
 * CJ auth secret contract — names only. No real values.
 * Official: Personal Access Token + companyId (publisher CID).
 * No functions.config().
 */

const {defineSecret} = require("firebase-functions/params");

const CJ_SECRET_CONTRACT_ID = "CjPublisherAuthBinding/v1";

/** Secret Manager name for CJ Personal Access Token (Bearer). */
const CJ_PERSONAL_ACCESS_TOKEN_SECRET_NAME = "CJ_PERSONAL_ACCESS_TOKEN";
const CJ_PERSONAL_ACCESS_TOKEN_SECRET =
  defineSecret(CJ_PERSONAL_ACCESS_TOKEN_SECRET_NAME);

/**
 * Publisher company ID is not always a secret, but treat as private config.
 * Stored as private integration field `cjCompanyId`, not necessarily Secret Manager.
 */
const CJ_CONFIG_KEYS = Object.freeze({
  personalAccessTokenSecretRef: CJ_PERSONAL_ACCESS_TOKEN_SECRET_NAME,
  companyId: "cjCompanyId",
  websiteIdPid: "cjWebsiteId",
  reservedAdvertiserCompanyId: "reservedAdvertiserCompanyId",
});

const NEW_LEGACY_FUNCTIONS_CONFIG_USAGE_COUNT = 0;

module.exports = {
  CJ_CONFIG_KEYS,
  CJ_PERSONAL_ACCESS_TOKEN_SECRET,
  CJ_PERSONAL_ACCESS_TOKEN_SECRET_NAME,
  CJ_SECRET_CONTRACT_ID,
  NEW_LEGACY_FUNCTIONS_CONFIG_USAGE_COUNT,
};
