"use strict";

const {assertText} = require("../catalog_contract");
const {PARTNER_CAPABILITY, hasCapability} = require("./partner_capabilities");
const {buildPublicPartnerConfig} = require("./partner_config");
const {createPartnerError, PARTNER_ERROR} = require("./partner_errors");

const SYNC_MODE = Object.freeze({
  FULL: "FULL",
  INCREMENTAL: "INCREMENTAL",
});

const REQUIRED_ADAPTER_METHODS = Object.freeze([
  "partnerId",
  "capabilities",
  "validateConfiguration",
  "fetchFullSnapshot",
  "fetchIncremental",
  "normalizeProduct",
  "normalizeVariant",
  "normalizeOffer",
  "normalizeSizes",
  "normalizePromotions",
  "normalizeImages",
  "buildCheckpoint",
  "classifyDisappearance",
]);

/**
 * Assert a production PartnerAdapter surface. Exact repository naming may wrap
 * these methods; factories should satisfy this contract for orchestration.
 */
function assertPartnerAdapter(adapter) {
  if (!adapter || typeof adapter !== "object") {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_adapter_required",
    );
  }
  for (const method of REQUIRED_ADAPTER_METHODS) {
    if (typeof adapter[method] !== "function") {
      throw createPartnerError(
        PARTNER_ERROR.FATAL_CONFIGURATION,
        `partner_adapter_missing_${method}`,
      );
    }
  }
  const partnerId = adapter.partnerId();
  assertText(partnerId, "partner_id");
  const caps = adapter.capabilities();
  if (!(caps instanceof Set) && !Array.isArray(caps)) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_adapter_capabilities_invalid",
    );
  }
  return adapter;
}

/**
 * Validate that requested sync mode is supported by declared capabilities.
 * Do not infer unsupported capability.
 */
function assertSyncModeSupported(adapter, mode) {
  const caps = adapter.capabilities();
  if (mode === SYNC_MODE.FULL) {
    if (!hasCapability(caps, PARTNER_CAPABILITY.FULL_CATALOG_SNAPSHOT)) {
      throw createPartnerError(
        PARTNER_ERROR.FATAL_CONFIGURATION,
        "partner_full_snapshot_unsupported",
      );
    }
  } else if (mode === SYNC_MODE.INCREMENTAL) {
    if (!hasCapability(caps, PARTNER_CAPABILITY.INCREMENTAL_UPDATES)) {
      throw createPartnerError(
        PARTNER_ERROR.FATAL_CONFIGURATION,
        "partner_incremental_unsupported",
      );
    }
  } else {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_sync_mode_invalid",
    );
  }
}

/**
 * Disappearance semantics:
 * FULL + completeness guarantee → may discontinue missing offers.
 * INCREMENTAL / PARTIAL → MUST NOT discontinue from absence.
 * Failed sync / timeout → MUST NOT discontinue.
 */
function classifyDisappearanceDefault({mode, completenessGuaranteed, failed}) {
  if (failed) return "PRESERVE_LAST_KNOWN_GOOD";
  if (mode === SYNC_MODE.FULL && completenessGuaranteed === true) {
    return "MAY_DISCONTINUE_MISSING_OFFERS";
  }
  return "MUST_NOT_DISCONTINUE";
}

function partnerPublicProjectionFromAdapter(adapter) {
  assertPartnerAdapter(adapter);
  if (adapter.publicConfig && typeof adapter.publicConfig === "function") {
    return buildPublicPartnerConfig(adapter.publicConfig());
  }
  if (adapter.partner) {
    return buildPublicPartnerConfig({
      ...adapter.partner,
      displayName: adapter.partner.displayName || adapter.partner.publicStoreName,
      market: adapter.partner.market || "XX",
      adapterKey: adapter.partner.adapterKey || "unknown",
      adapterVersion: adapter.partner.adapterVersion || "0",
    });
  }
  throw createPartnerError(
    PARTNER_ERROR.FATAL_CONFIGURATION,
    "partner_public_projection_unavailable",
  );
}

module.exports = {
  REQUIRED_ADAPTER_METHODS,
  SYNC_MODE,
  assertPartnerAdapter,
  assertSyncModeSupported,
  classifyDisappearanceDefault,
  partnerPublicProjectionFromAdapter,
};
