"use strict";

/**
 * Partner image-candidate contract (Phase 8).
 * Partner claims are HINTS only — never OOTD-approved garment imagery.
 * AI validation / person-mannequin removal is Phase 9+ (AI_REQUEST_COUNT = 0).
 */

const PARTNER_IMAGE_ROLE = Object.freeze({
  PRODUCT_ONLY: "PRODUCT_ONLY",
  FRONT: "FRONT",
  BACK: "BACK",
  DETAIL: "DETAIL",
  MODEL: "MODEL",
  LIFESTYLE: "LIFESTYLE",
  UNKNOWN: "UNKNOWN",
});

const IMAGE_STATUS = Object.freeze({
  NOT_AVAILABLE: "NOT_AVAILABLE",
  NEEDS_VALIDATION: "NEEDS_VALIDATION",
  // Future gate outcomes — not assigned by adapter alone:
  APPROVED_GARMENT_ONLY: "APPROVED_GARMENT_ONLY",
  REJECTED_PERSON_OR_MANNEQUIN: "REJECTED_PERSON_OR_MANNEQUIN",
  UNKNOWN: "UNKNOWN",
});

const PARTNER_PRODUCT_ONLY_TRUST_POLICY = Object.freeze({
  name: "PARTNER_PRODUCT_ONLY_TRUST_POLICY_V1",
  // partnerClaimsProductOnly=true is NEVER trusted as OOTD truth.
  trustPartnerProductOnlyClaim: false,
  adapterMayMarkOotdApproved: false,
});

const MODEL_MANNEQUIN_IMAGE_POLICY = Object.freeze({
  name: "MODEL_MANNEQUIN_IMAGE_POLICY_V1",
  allowAsFinalOotdImage: false,
  allowGenerativeReconstruction: false,
  allowPersonStripping: false,
});

const NO_IMAGE_POLICY = Object.freeze({
  name: "NO_IMAGE_POLICY_V1",
  variantRemainsCatalogValid: true,
  publicImageStatus: IMAGE_STATUS.NOT_AVAILABLE,
  wardrobeImportBlockedUntilVerified: true,
});

const AI_REQUEST_COUNT = 0;

/**
 * Normalize partner image candidates. Does NOT approve for Wardrobe/OOTD.
 */
function normalizePartnerImageCandidates(rawList, {allowedDomains} = {}) {
  if (rawList == null) {
    return {
      candidates: [],
      imageStatus: IMAGE_STATUS.NOT_AVAILABLE,
      ootdApproved: false,
    };
  }
  if (!Array.isArray(rawList)) {
    throw Object.assign(new Error("partner_images_invalid"), {
      code: "INVALID_PAYLOAD",
    });
  }
  const candidates = rawList.map((raw, index) =>
    normalizePartnerImageCandidate(raw, {index, allowedDomains}));
  const ordered = orderImageCandidates(candidates);
  return {
    candidates: ordered,
    imageStatus: ordered.length ?
      IMAGE_STATUS.NEEDS_VALIDATION : IMAGE_STATUS.NOT_AVAILABLE,
    // Adapter alone NEVER sets OOTD approval.
    ootdApproved: false,
  };
}

function normalizePartnerImageCandidate(raw, {index = 0, allowedDomains} = {}) {
  if (!raw || typeof raw !== "object") {
    throw Object.assign(new Error("partner_image_candidate_invalid"), {
      code: "INVALID_PAYLOAD",
    });
  }
  const url = String(raw.url || raw.reference || "").trim();
  if (!url) {
    throw Object.assign(new Error("partner_image_url_required"), {
      code: "INVALID_URL",
    });
  }
  let parsed;
  try {
    parsed = new URL(url);
  } catch (_) {
    throw Object.assign(new Error("partner_image_url_invalid"), {
      code: "INVALID_URL",
    });
  }
  if (parsed.protocol !== "https:") {
    throw Object.assign(new Error("partner_image_url_requires_https"), {
      code: "INVALID_URL",
    });
  }
  if (Array.isArray(allowedDomains) && allowedDomains.length) {
    const host = parsed.hostname.toLowerCase();
    const allowed = allowedDomains.some((domain) =>
      host === domain || host.endsWith(`.${domain}`));
    if (!allowed) {
      throw Object.assign(new Error("partner_image_url_domain_not_allowed"), {
        code: "INVALID_URL",
      });
    }
  }
  let role = String(raw.partnerRole || raw.role || PARTNER_IMAGE_ROLE.UNKNOWN)
    .trim().toUpperCase();
  if (!Object.values(PARTNER_IMAGE_ROLE).includes(role)) {
    role = PARTNER_IMAGE_ROLE.UNKNOWN;
  }
  return {
    url: parsed.toString(),
    partnerRole: role,
    partnerPosition: raw.partnerPosition == null ?
      index : Number(raw.partnerPosition),
    // Hint only — never trusted as OOTD truth.
    partnerClaimsProductOnly: raw.partnerClaimsProductOnly === true,
    width: raw.width == null ? null : Number(raw.width),
    height: raw.height == null ? null : Number(raw.height),
    mimeType: raw.mimeType == null ? null : String(raw.mimeType),
    // Explicit: not OOTD-approved by partner adapter.
    ootdApproved: false,
  };
}

function orderImageCandidates(candidates) {
  const rank = (c) => {
    if (c.partnerRole === PARTNER_IMAGE_ROLE.PRODUCT_ONLY ||
        c.partnerClaimsProductOnly) return 0;
    if (c.partnerRole === PARTNER_IMAGE_ROLE.FRONT) return 1;
    if (c.partnerRole === PARTNER_IMAGE_ROLE.BACK ||
        c.partnerRole === PARTNER_IMAGE_ROLE.DETAIL) return 2;
    if (c.partnerRole === PARTNER_IMAGE_ROLE.MODEL ||
        c.partnerRole === PARTNER_IMAGE_ROLE.LIFESTYLE) return 9;
    return 5;
  };
  return [...candidates].sort((a, b) => {
    const d = rank(a) - rank(b);
    if (d !== 0) return d;
    return (a.partnerPosition || 0) - (b.partnerPosition || 0);
  });
}

/**
 * Future boundary stub — Phase 8 does not call AI.
 * Interface only for Phase 9+ garment-only preflight.
 */
function createOotdImagePreflightBoundary() {
  return {
    contractId: "OOTDImagePreflight/v1",
    aiRequestCount: AI_REQUEST_COUNT,
    async evaluate(_candidate) {
      return {
        status: IMAGE_STATUS.NEEDS_VALIDATION,
        reason: "phase_8_preflight_not_implemented",
        aiRequestCount: AI_REQUEST_COUNT,
      };
    },
  };
}

module.exports = {
  AI_REQUEST_COUNT,
  IMAGE_STATUS,
  MODEL_MANNEQUIN_IMAGE_POLICY,
  NO_IMAGE_POLICY,
  PARTNER_IMAGE_ROLE,
  PARTNER_PRODUCT_ONLY_TRUST_POLICY,
  createOotdImagePreflightBoundary,
  normalizePartnerImageCandidate,
  normalizePartnerImageCandidates,
  orderImageCandidates,
};
