"use strict";

const {
  AVAILABILITY,
  CONTRACT_VERSION,
  LIFECYCLE,
  PROMOTION_KIND,
  QUANTITY_RELIABILITY,
  assertText,
  decodeMoney,
  normalizeAvailability,
  normalizeIdentityEvidence,
  normalizeLifecycle,
  normalizePromotions,
  normalizeSize,
  stableId,
  validateOfferUrl,
} = require("../catalog_contract");
const {createPartnerError, PARTNER_ERROR} = require("./partner_errors");
const {
  normalizePartnerImageCandidates,
} = require("./partner_images");
const {classifyDisappearanceDefault} = require("./partner_adapter_contract");

/**
 * Shared helpers for production-shaped synthetic adapters.
 * Maps RAW partner DTO → existing catalog contract (no PartnerProduct truth).
 */
function buildCatalogRecordFromRaw(partner, raw, {now} = {}) {
  if (!raw || typeof raw !== "object") {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_PAYLOAD,
      "partner_raw_record_invalid",
    );
  }
  if (raw.__schemaDrift === true) {
    throw createPartnerError(
      PARTNER_ERROR.SCHEMA_CHANGED,
      "partner_schema_changed",
    );
  }

  const productEvidence = normalizeIdentityEvidence(raw.productEvidence || {});
  const variantEvidence = normalizeIdentityEvidence(raw.variantEvidence || {});
  const productRef = assertText(raw.partnerProductId, "partner_product_id");
  const variantRef = assertText(raw.partnerVariantId, "partner_variant_id");
  const listingRef = assertText(raw.partnerListingId, "partner_listing_id");

  const productCandidateId = stableId(
    "product", `${partner.partnerId}:${productRef}`,
  );
  const variantCandidateId = stableId(
    "variant", `${partner.partnerId}:${variantRef}`,
  );
  const offerId = stableId(
    "offer", `${partner.partnerId}:${listingRef}`,
  );

  let regularPrice;
  try {
    regularPrice = decodeMoney(raw.regularPrice, "regular_price");
  } catch (error) {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_MONEY,
      error.message || "invalid_money",
    );
  }

  let promotions;
  try {
    promotions = normalizePromotions(raw.promotions, regularPrice.currency, {
      now,
    });
  } catch (error) {
    if (/promotion_kind|unsupported/i.test(error.message || "")) {
      throw createPartnerError(
        PARTNER_ERROR.UNSUPPORTED_PROMOTION,
        error.message,
      );
    }
    throw createPartnerError(
      PARTNER_ERROR.INVALID_PAYLOAD,
      error.message || "invalid_promotions",
    );
  }

  let url;
  try {
    url = validateOfferUrl(raw.url, partner.allowedDomains);
  } catch (error) {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_URL,
      error.message || "invalid_url",
    );
  }

  const offer = {
    offerId,
    variantId: variantCandidateId,
    partnerId: partner.partnerId,
    partnerListingId: listingRef,
    url,
    regularPrice,
    promotions,
    overallAvailability: normalizeAvailability(
      raw.offerAvailability, "offer_availability",
    ),
    lifecycleState: normalizeLifecycle(raw.lifecycle),
    lastVerifiedAt: raw.observedAt || now || null,
    market: partner.market || null,
  };

  const sizes = Array.isArray(raw.sizes) ?
    raw.sizes.map((size) => normalizePartnerSize(size, offerId)) : [];

  const images = normalizePartnerImageCandidates(raw.images, {
    allowedDomains: partner.allowedDomains,
  });

  return {
    contractVersion: CONTRACT_VERSION,
    product: {
      candidateId: productCandidateId,
      brand: assertText(raw.brand, "brand"),
      normalizedModelIdentity: assertText(raw.modelIdentity, "model_identity"),
      canonicalType: assertText(raw.canonicalType, "canonical_type"),
      canonicalFamily: assertText(raw.canonicalFamily, "canonical_family"),
      identityEvidence: productEvidence,
      lifecycleState: LIFECYCLE.ACTIVE,
    },
    variant: {
      candidateId: variantCandidateId,
      productCandidateId,
      exactColorName: assertText(raw.colorName, "color_name"),
      exactColorCode: raw.colorCode || null,
      colorProfile: normalizeColorProfile(raw.colorProfile),
      identityEvidence: variantEvidence,
      fit: raw.fit || null,
      material: raw.material || null,
      pattern: raw.pattern || null,
      styles: Array.isArray(raw.styles) ? [...raw.styles] : [],
      detailAttributes: {},
      warmth: null,
      formality: null,
      lifecycleState: LIFECYCLE.ACTIVE,
    },
    offer,
    sizes,
    imageCandidates: images.candidates,
    imageStatus: images.imageStatus,
    freshness: {
      sourceObservedAt: raw.observedAt || now || null,
      receivedAt: now || raw.observedAt || null,
      lastSuccessfulVerificationAt: raw.observedAt || now || null,
      stale: false,
    },
  };
}

function normalizePartnerSize(raw, offerId) {
  // Missing size data → UNKNOWN (never invent UNAVAILABLE).
  if (raw == null || typeof raw !== "object") {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_PAYLOAD,
      "partner_size_invalid",
    );
  }
  const availability = raw.availability == null ?
    AVAILABILITY.UNKNOWN :
    normalizeAvailability(raw.availability, "size_availability");

  let exactQuantity = null;
  let quantityReliability = QUANTITY_RELIABILITY.UNKNOWN;
  if (raw.exactQuantity != null) {
    if (raw.quantityReliability !== QUANTITY_RELIABILITY.EXACT) {
      // Unreliable quantity omitted — do not invent.
      exactQuantity = null;
      quantityReliability = QUANTITY_RELIABILITY.UNKNOWN;
    } else {
      exactQuantity = raw.exactQuantity;
      quantityReliability = QUANTITY_RELIABILITY.EXACT;
    }
  } else if (raw.lowStockSignal === true) {
    quantityReliability = QUANTITY_RELIABILITY.PARTNER_LOW_STOCK_SIGNAL;
  }

  return normalizeSize({
    normalizedSizeKey: raw.normalizedSizeKey,
    partnerSizeLabel: raw.partnerSizeLabel || raw.normalizedSizeKey,
    sizeSystem: raw.sizeSystem || "UNKNOWN",
    availability,
    exactQuantity,
    quantityReliability,
    observedAt: raw.observedAt || null,
  }, offerId);
}

function normalizeColorProfile(raw) {
  if (!raw || typeof raw !== "object") {
    return {
      primary: {family: "unknown", hex: null, proportion: null},
      secondary: null,
      accents: [],
      metalTone: "unknown",
      hardwareTone: "unknown",
    };
  }
  const primary = raw.primary || {};
  return {
    primary: {
      family: String(primary.family || "unknown"),
      hex: primary.hex || null,
      proportion: primary.proportion == null ? null : primary.proportion,
    },
    secondary: raw.secondary || null,
    accents: Array.isArray(raw.accents) ? raw.accents : [],
    metalTone: raw.metalTone || "unknown",
    hardwareTone: raw.hardwareTone || "unknown",
  };
}

function createBasePartnerAdapter({
  publicConfig,
  privateConfigDefaults = {},
  fetchPage,
}) {
  const partner = {
    partnerId: publicConfig.partnerId,
    publicStoreName: publicConfig.publicStoreName || publicConfig.displayName,
    displayName: publicConfig.displayName || publicConfig.publicStoreName,
    status: publicConfig.status || "ACTIVE",
    market: publicConfig.market,
    currency: publicConfig.currency || null,
    allowedDomains: publicConfig.allowedDomains,
    adapterKey: publicConfig.adapterKey,
    adapterVersion: publicConfig.adapterVersion,
    capabilities: [...publicConfig.capabilities],
  };
  const capSet = new Set(partner.capabilities);

  return {
    partner,
    publicConfig() {
      return {...partner};
    },
    partnerId() {
      return partner.partnerId;
    },
    capabilities() {
      return new Set(capSet);
    },
    validateConfiguration({publicConfig: pub, privateConfig: priv} = {}) {
      const {validatePartnerConfiguration} = require("./partner_config");
      return validatePartnerConfiguration({
        publicConfig: pub || partner,
        privateConfig: {
          partnerId: partner.partnerId,
          adapterKey: partner.adapterKey,
          adapterVersion: partner.adapterVersion,
          ...privateConfigDefaults,
          ...(priv || {}),
        },
      });
    },
    async fetchFullSnapshot(args) {
      return fetchPage({...args, mode: "FULL"});
    },
    async fetchIncremental(args) {
      return fetchPage({...args, mode: "INCREMENTAL"});
    },
    normalizeProduct(raw, ctx) {
      return buildCatalogRecordFromRaw(partner, raw, ctx).product;
    },
    normalizeVariant(raw, ctx) {
      return buildCatalogRecordFromRaw(partner, raw, ctx).variant;
    },
    normalizeOffer(raw, ctx) {
      return buildCatalogRecordFromRaw(partner, raw, ctx).offer;
    },
    normalizeSizes(raw, ctx) {
      return buildCatalogRecordFromRaw(partner, raw, ctx).sizes;
    },
    normalizePromotions(raw, ctx) {
      const record = buildCatalogRecordFromRaw(partner, raw, ctx);
      return record.offer.promotions;
    },
    normalizeImages(raw) {
      return normalizePartnerImageCandidates(raw.images, {
        allowedDomains: partner.allowedDomains,
      });
    },
    normalizeRecord(raw, ctx) {
      return buildCatalogRecordFromRaw(partner, raw, ctx);
    },
    buildCheckpoint({previous, page, pageIndex, mode, now}) {
      return {
        cursor: page.nextPageToken || null,
        pageToken: page.nextPageToken || null,
        mode,
        updatedAt: now,
        lastPersistedPage: pageIndex,
        previousCursor: previous?.cursor || null,
      };
    },
    classifyDisappearance(args) {
      return classifyDisappearanceDefault(args);
    },
  };
}

module.exports = {
  PROMOTION_KIND,
  QUANTITY_RELIABILITY,
  buildCatalogRecordFromRaw,
  createBasePartnerAdapter,
  normalizeColorProfile,
  normalizePartnerSize,
};
