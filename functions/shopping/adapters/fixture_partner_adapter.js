"use strict";

const {
  AVAILABILITY,
  CONTRACT_VERSION,
  LIFECYCLE,
  assertText,
  decodeMoney,
  normalizeAllowedDomains,
  normalizeAvailability,
  normalizeIdentityEvidence,
  normalizeLifecycle,
  normalizePromotions,
  normalizeSize,
  stableId,
  validateOfferUrl,
} = require("../catalog_contract");

const ADAPTER_KEY = "fixture_partner_catalog";
const ADAPTER_VERSION = "1";

/**
 * Local-only adapter. Raw `fixture*` field names are intentionally translated
 * here and never persisted, which prevents partner schema leakage.
 */
function createFixturePartnerAdapter(config) {
  const partner = {
    partnerId: assertText(config.partnerId, "partner_id"),
    publicStoreName: assertText(config.publicStoreName, "partner_public_name"),
    status: config.status || "ACTIVE",
    allowedDomains: normalizeAllowedDomains(config.allowedDomains),
    adapterKey: ADAPTER_KEY,
    adapterVersion: ADAPTER_VERSION,
    capabilities: [...new Set(config.capabilities || [])].sort(),
  };

  return {
    partner,
    capabilities() {
      return new Set(partner.capabilities);
    },
    normalize(raw) {
      if (!raw || typeof raw !== "object") {
        throw new Error("shopping_catalog_invalid_fixture_record");
      }
      const productEvidence = normalizeIdentityEvidence(raw.fixtureProductEvidence);
      const variantEvidence = normalizeIdentityEvidence(raw.fixtureVariantEvidence);
      const productCandidateId = stableId(
        "product",
        `${partner.partnerId}:${assertText(raw.fixtureProductRef, "fixture_product_ref")}`,
      );
      const variantCandidateId = stableId(
        "variant",
        `${partner.partnerId}:${assertText(raw.fixtureVariantRef, "fixture_variant_ref")}`,
      );
      const offerId = stableId(
        "offer",
        `${partner.partnerId}:${assertText(raw.fixtureListingRef, "fixture_listing_ref")}`,
      );
      const regularPrice = decodeMoney(raw.fixtureRegularPrice, "regular_price");
      const offer = {
        offerId,
        variantId: variantCandidateId,
        partnerId: partner.partnerId,
        partnerListingId: assertText(raw.fixtureListingRef, "fixture_listing_ref"),
        url: validateOfferUrl(raw.fixtureUrl, partner.allowedDomains),
        regularPrice,
        promotions: normalizePromotions(raw.fixturePromotions, regularPrice.currency),
        overallAvailability: normalizeAvailability(
          raw.fixtureOfferAvailability,
          "offer_availability",
        ),
        lifecycleState: normalizeLifecycle(raw.fixtureLifecycle),
        lastVerifiedAt: raw.fixtureObservedAt || null,
      };
      return {
        contractVersion: CONTRACT_VERSION,
        product: {
          candidateId: productCandidateId,
          brand: assertText(raw.fixtureBrand, "brand"),
          normalizedModelIdentity: assertText(
            raw.fixtureModelIdentity,
            "model_identity",
          ),
          canonicalType: assertText(raw.fixtureCanonicalType, "canonical_type"),
          canonicalFamily: assertText(
            raw.fixtureCanonicalFamily,
            "canonical_family",
          ),
          identityEvidence: productEvidence,
          lifecycleState: LIFECYCLE.ACTIVE,
        },
        variant: {
          candidateId: variantCandidateId,
          productCandidateId,
          exactColorName: assertText(raw.fixtureColorName, "color_name"),
          exactColorCode: raw.fixtureColorCode || null,
          colorProfile: normalizeColorProfile(raw.fixtureColorProfile),
          identityEvidence: variantEvidence,
          fit: raw.fixtureFit || null,
          material: raw.fixtureMaterial || null,
          pattern: raw.fixturePattern || null,
          styles: Array.isArray(raw.fixtureStyles) ? [...raw.fixtureStyles] : [],
          // Extensible, normalized catalog facts for Phase 1's `detail`
          // constraint field. Unknown keys remain unknown; none are inferred.
          detailAttributes: normalizeDetailAttributes(raw.fixtureDetailAttributes),
          warmth: normalizeScale(raw.fixtureWarmth, "warmth"),
          formality: normalizeScale(raw.fixtureFormality, "formality"),
          lifecycleState: LIFECYCLE.ACTIVE,
        },
        offer,
        sizes: Array.isArray(raw.fixtureSizes) ?
          raw.fixtureSizes.map((size) => normalizeSize(size, offerId)) : [],
        freshness: {
          sourceObservedAt: raw.fixtureObservedAt || null,
          receivedAt: raw.fixtureReceivedAt || raw.fixtureObservedAt || null,
          lastSuccessfulVerificationAt: raw.fixtureObservedAt || null,
          stale: false,
        },
      };
    },
  };
}

function normalizeDetailAttributes(raw) {
  if (raw == null) return {};
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("shopping_catalog_invalid_detail_attributes");
  }
  const result = {};
  for (const [key, value] of Object.entries(raw)) {
    const normalizedKey = assertText(key, "detail_attribute_key");
    if (typeof value !== "string" && typeof value !== "boolean" &&
        typeof value !== "number") {
      throw new Error("shopping_catalog_invalid_detail_attribute_value");
    }
    result[normalizedKey] = value;
  }
  return result;
}

function normalizeScale(value, field) {
  if (value == null) return null;
  if (!Number.isInteger(value) || value < 1 || value > 10) {
    throw new Error(`shopping_catalog_invalid_${field}`);
  }
  return value;
}

function normalizeColorProfile(raw) {
  if (!raw || typeof raw !== "object") {
    throw new Error("shopping_catalog_invalid_color_profile");
  }
  const primary = raw.primary;
  if (!primary || typeof primary !== "object") {
    throw new Error("shopping_catalog_invalid_primary_color");
  }
  return {
    primary: {
      family: assertText(primary.family, "primary_color_family"),
      hex: primary.hex || null,
      proportion: primary.proportion == null ? null : primary.proportion,
    },
    secondary: raw.secondary || null,
    accents: Array.isArray(raw.accents) ? raw.accents : [],
    metalTone: raw.metalTone || "unknown",
    hardwareTone: raw.hardwareTone || "unknown",
  };
}

module.exports = {
  ADAPTER_KEY,
  ADAPTER_VERSION,
  createFixturePartnerAdapter,
};
