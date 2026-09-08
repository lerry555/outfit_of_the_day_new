"use strict";

const STYLIST_SESSION_V2_PATH = "users/{uid}/stylistSessionsV2/{chatId}";
const STYLIST_SESSION_TURN_V2_PATH = "users/{uid}/stylistSessionsV2/{chatId}/turns/{turnId}";

function intendedClientAccessV2({operation, authenticatedUid, pathUid, resourceKind = "session"}) {
  if (!authenticatedUid || authenticatedUid !== pathUid) return false;
  if (resourceKind === "turn") return false;
  if (resourceKind !== "session") return false;
  if (operation === "get" || operation === "list") return true;
  return false;
}

module.exports = {
  STYLIST_SESSION_TURN_V2_PATH,
  STYLIST_SESSION_V2_PATH,
  intendedClientAccessV2,
};
