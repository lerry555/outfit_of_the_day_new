"use strict";

/**
 * Controlled-write cohort allow-list policy.
 * Without match → shadow or disabled (never uncontrolled write).
 */

const COHORT_ID = "WardrobeAuthorityCohortPolicy";
const COHORT_VERSION = "wardrobe-authority-cohort-policy-v1";

function createWardrobeAuthorityCohortPolicy(options = {}) {
  const allowUids = new Set(
    (options.allowlistedUids || []).map((u) => String(u)));
  const requireAllowlistForControlledWrite =
    options.requireAllowlistForControlledWrite !== false;

  function evaluate({uid, mode}) {
    const id = String(uid || "");
    if (mode !== "controlled_write") {
      return Object.freeze({
        ok: true,
        reasonCode: "cohort_not_required",
        cohortId: COHORT_ID,
        matched: false,
      });
    }
    if (!requireAllowlistForControlledWrite) {
      return Object.freeze({
        ok: true,
        reasonCode: "cohort_optional_disabled",
        cohortId: COHORT_ID,
        matched: true,
      });
    }
    if (!id || !allowUids.has(id)) {
      return Object.freeze({
        ok: false,
        reasonCode: "cohort_uid_not_allowlisted",
        cohortId: COHORT_ID,
        matched: false,
        fallbackMode: "shadow",
      });
    }
    return Object.freeze({
      ok: true,
      reasonCode: "cohort_matched",
      cohortId: COHORT_ID,
      matched: true,
    });
  }

  return Object.freeze({
    cohortId: COHORT_ID,
    cohortVersion: COHORT_VERSION,
    allowlistedCount: allowUids.size,
    evaluate,
  });
}

module.exports = {
  COHORT_ID,
  COHORT_VERSION,
  createWardrobeAuthorityCohortPolicy,
};
