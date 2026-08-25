"use strict";

const {
  CHANGESET_SOURCES,
  WISHLIST_CHANGESET_MAX_VARIANTS_V1,
} = require("./wishlist_monitoring_constants");

/**
 * CatalogChangeSet → WishlistMonitoringEngine contract.
 * Offer/size IDs must be expanded to exact variantIds before fanout.
 */
function normalizeCatalogChangeSet(raw, {resolveVariantIds} = {}) {
  if (!raw || typeof raw !== "object") {
    throw new Error("catalog_changeset_required");
  }
  const source = String(raw.source || "");
  if (!Object.values(CHANGESET_SOURCES).includes(source)) {
    throw new Error("catalog_changeset_invalid_source");
  }
  const syncRunId = String(raw.syncRunId || "").trim();
  const catalogRevision = String(raw.catalogRevision || "").trim();
  if (!syncRunId || !catalogRevision) {
    throw new Error("catalog_changeset_identity_required");
  }
  let changedVariantIds = uniqueIds(raw.changedVariantIds);
  const changedOfferIds = uniqueIds(raw.changedOfferIds);
  const changedSizeIds = uniqueIds(raw.changedSizeIds);
  if ((changedOfferIds.length || changedSizeIds.length) &&
      typeof resolveVariantIds === "function") {
    const expanded = uniqueIds(resolveVariantIds({
      changedOfferIds,
      changedSizeIds,
      changedVariantIds,
    }));
    changedVariantIds = uniqueIds([...changedVariantIds, ...expanded]);
  }
  if (changedVariantIds.length > WISHLIST_CHANGESET_MAX_VARIANTS_V1) {
    throw new Error("catalog_changeset_too_large");
  }
  return {
    schemaVersion: 1,
    source,
    syncRunId,
    catalogRevision,
    successfulVerificationAt: raw.successfulVerificationAt == null ?
      null : String(raw.successfulVerificationAt),
    changedVariantIds,
    changedOfferIds,
    changedSizeIds,
  };
}

function uniqueIds(values) {
  if (!Array.isArray(values)) return [];
  return [...new Set(values.map((value) => String(value || "").trim())
    .filter((value) => /^[A-Za-z0-9_-]{1,128}$/.test(value)))];
}

module.exports = {
  CHANGESET_SOURCES,
  normalizeCatalogChangeSet,
};
