"use strict";

/**
 * Integration-level rights states — separate from image content preflight.
 * Never set above UNKNOWN without owner/partner evidence.
 */
const DATA_USAGE_RIGHTS = Object.freeze({
  UNKNOWN: "UNKNOWN",
  PROMOTIONAL_DISPLAY_ALLOWED: "PROMOTIONAL_DISPLAY_ALLOWED",
  CATALOG_CACHE_ALLOWED: "CATALOG_CACHE_ALLOWED",
  RESTRICTED: "RESTRICTED",
});

const IMAGE_USAGE_RIGHTS = Object.freeze({
  UNKNOWN: "UNKNOWN",
  PROMOTIONAL_DISPLAY_ALLOWED: "PROMOTIONAL_DISPLAY_ALLOWED",
  TRANSFORM_ALLOWED: "TRANSFORM_ALLOWED",
  WARDROBE_REUSE_ALLOWED: "WARDROBE_REUSE_ALLOWED",
  RESTRICTED: "RESTRICTED",
});

const DEFAULT_RIGHTS_STATE = Object.freeze({
  dataUsage: DATA_USAGE_RIGHTS.UNKNOWN,
  imageUsage: IMAGE_USAGE_RIGHTS.UNKNOWN,
  updatedAt: null,
  evidence: "no_owner_terms_acceptance",
});

/**
 * Future OOTD image preflight contract (Phase later — AI_REQUEST_COUNT = 0 now).
 * Rights must pass independently of content classification.
 */
const OOTD_IMAGE_PREFLIGHT_CONTRACT = Object.freeze({
  contractId: "OOTDImagePreflight/v1",
  inputs: [
    "PartnerImageCandidate[]",
    "imageUsageRights",
    "partnerRoleHints",
  ],
  outputs: Object.freeze([
    "APPROVED_GARMENT_ONLY",
    "REJECTED_PERSON",
    "REJECTED_MANNEQUIN",
    "REJECTED_BODY_PART",
    "REJECTED_MULTIPLE_DOMINANT_GARMENTS",
    "UNKNOWN",
  ]),
  rules: Object.freeze({
    preflightDoesNotOverrideRights: true,
    noGenerativeReconstruction: true,
    partnerClaimsProductOnlyNotTrusted: true,
    aiRequestCountNow: 0,
  }),
});

const WARDROBE_IMAGE_ELIGIBILITY_STATUS = Object.freeze({
  status: "NOT_ELIGIBLE_UNTIL_RIGHTS_AND_PREFLIGHT",
  requires: [
    "IMAGE_USAGE_RIGHTS >= PROMOTIONAL_DISPLAY_ALLOWED (min for shopping display)",
    "WARDROBE_REUSE_ALLOWED for wardrobe auto-import",
    "APPROVED_GARMENT_ONLY from preflight",
  ],
});

module.exports = {
  DATA_USAGE_RIGHTS,
  DEFAULT_RIGHTS_STATE,
  IMAGE_USAGE_RIGHTS,
  OOTD_IMAGE_PREFLIGHT_CONTRACT,
  WARDROBE_IMAGE_ELIGIBILITY_STATUS,
};
