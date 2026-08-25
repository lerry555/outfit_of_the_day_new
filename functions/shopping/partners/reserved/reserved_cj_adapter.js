"use strict";

const {PARTNER_CAPABILITY} = require("../partner_capabilities");
const {createPartnerError, PARTNER_ERROR} = require("../partner_errors");
const {classifyDisappearanceDefault, SYNC_MODE} =
  require("../partner_adapter_contract");
const {
  ADAPTER_KEY,
  ADAPTER_VERSION,
  DISPLAY_NAME,
  EXPECTED_CURRENCY,
  FEED_PROFILE_STATUS,
  KNOWN_MERCHANT_DOMAINS,
  MARKET,
  PARTNER_ID,
  PRODUCTION_SYNC_STATUS,
} = require("./reserved_cj_constants");
const {
  ReservedCjFeedProfile,
  isProductionMappingEnabled,
} = require("./reserved_cj_feed_profile");
const {
  buildReservedPrivatePartnerTemplate,
  buildReservedPublicPartnerTemplate,
} = require("./reserved_cj_config_templates");

/**
 * Reserved SK / CJ adapter skeleton.
 * Fail-closed: refuses production sync until feed profile confirmed from sample.
 */
function createReservedCjAdapter({
  allowProductionSync = false,
} = {}) {
  const publicConfig = {
    ...buildReservedPublicPartnerTemplate(),
    capabilities: [
      // Declared only as intended future capabilities — sync still blocked.
      PARTNER_CAPABILITY.FULL_CATALOG_SNAPSHOT,
      PARTNER_CAPABILITY.PRICE,
      PARTNER_CAPABILITY.CURRENCY,
      PARTNER_CAPABILITY.MARKET_SCOPE,
      PARTNER_CAPABILITY.STABLE_PARTNER_PRODUCT_ID,
      PARTNER_CAPABILITY.PAGINATION,
    ],
  };

  const partner = {
    partnerId: PARTNER_ID,
    publicStoreName: DISPLAY_NAME,
    displayName: DISPLAY_NAME,
    status: "DISABLED",
    market: MARKET,
    currency: EXPECTED_CURRENCY,
    allowedDomains: [...KNOWN_MERCHANT_DOMAINS],
    adapterKey: ADAPTER_KEY,
    adapterVersion: ADAPTER_VERSION,
    capabilities: [...publicConfig.capabilities],
  };

  function assertSampleConfirmed() {
    if (allowProductionSync && isProductionMappingEnabled()) return;
    const error = createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "RESERVED_FEED_PROFILE_UNCONFIRMED",
    );
    error.profileStatus = FEED_PROFILE_STATUS;
    error.productionSyncStatus = PRODUCTION_SYNC_STATUS;
    throw error;
  }

  return {
    partner,
    publicConfig() {
      return {...partner, ...publicConfig};
    },
    partnerId() {
      return PARTNER_ID;
    },
    capabilities() {
      return new Set(partner.capabilities);
    },
    feedProfile() {
      return ReservedCjFeedProfile;
    },
    productionSyncStatus() {
      return PRODUCTION_SYNC_STATUS;
    },
    validateConfiguration({publicConfig: pub, privateConfig: priv} = {}) {
      const template = buildReservedPrivatePartnerTemplate();
      const merged = {
        ...template,
        ...(priv || {}),
        partnerId: PARTNER_ID,
        adapterKey: ADAPTER_KEY,
        adapterVersion: ADAPTER_VERSION,
      };
      if (merged.status !== "DISABLED_PENDING_ACCESS" &&
          merged.productionSyncStatus !== "DISABLED") {
        // Even if caller tries to enable, refuse until sample gate.
        assertSampleConfirmed();
      }
      return {
        publicConfig: pub || publicConfig,
        privateConfig: merged,
      };
    },
    async fetchFullSnapshot() {
      assertSampleConfirmed();
      throw createPartnerError(
        PARTNER_ERROR.FATAL_CONFIGURATION,
        "reserved_live_fetch_not_authorized",
      );
    },
    async fetchIncremental() {
      assertSampleConfirmed();
      throw createPartnerError(
        PARTNER_ERROR.FATAL_CONFIGURATION,
        "reserved_incremental_not_authorized",
      );
    },
    normalizeProduct() {
      assertSampleConfirmed();
    },
    normalizeVariant() {
      assertSampleConfirmed();
    },
    normalizeOffer() {
      assertSampleConfirmed();
    },
    normalizeSizes() {
      assertSampleConfirmed();
    },
    normalizePromotions() {
      assertSampleConfirmed();
    },
    normalizeImages() {
      assertSampleConfirmed();
    },
    buildCheckpoint({previous, pageIndex, mode, now}) {
      return {
        cursor: null,
        pageToken: null,
        mode,
        updatedAt: now,
        lastPersistedPage: pageIndex,
        previousCursor: previous?.cursor || null,
      };
    },
    classifyDisappearance({mode, completenessGuaranteed, failed}) {
      // Until completeness confirmed: NEVER discontinue from absence.
      if (failed) return "PRESERVE_LAST_KNOWN_GOOD";
      if (mode === SYNC_MODE.FULL && completenessGuaranteed === true &&
          isProductionMappingEnabled()) {
        return classifyDisappearanceDefault({
          mode, completenessGuaranteed, failed,
        });
      }
      return "MUST_NOT_DISCONTINUE";
    },
  };
}

module.exports = {
  ADAPTER_KEY,
  ADAPTER_VERSION,
  createReservedCjAdapter,
};
