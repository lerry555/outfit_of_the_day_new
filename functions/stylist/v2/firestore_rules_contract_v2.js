"use strict";

const STYLIST_SESSION_V2_PATH = "users/{uid}/stylistSessionsV2/{chatId}";

function intendedClientAccessV2({operation, authenticatedUid, pathUid}) {
  if (!authenticatedUid || authenticatedUid !== pathUid) return false;
  if (operation === "get" || operation === "list") return true;
  // Phase 1 will express this server-write-only policy in production firestore.rules.
  return false;
}

module.exports = {STYLIST_SESSION_V2_PATH, intendedClientAccessV2};
