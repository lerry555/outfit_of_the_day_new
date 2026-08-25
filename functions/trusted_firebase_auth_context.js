"use strict";

/**
 * Trusted Firebase Auth context decoder (offline / emulator-ready).
 *
 * Pure / sync. Does not call Firebase Admin. Production endpoints must inject
 * a verified auth context; clients cannot supply uid as authority.
 * Capture-auth token handoff is explicitly rejected as a production path.
 */

const AUTH_CONTRACT = "TrustedFirebaseAuthContext/v1";
const AUTH_DECODER_ID = "TrustedFirebaseAuthContextDecoder";
const AUTH_DECODER_VERSION = "trusted-firebase-auth-context-decoder-v1";

const AUTH_STATUSES = Object.freeze({
  authenticated: "authenticated",
  unauthenticated: "unauthenticated",
  forbidden: "forbidden",
  malformed: "malformed_auth_context",
});

/**
 * @param {object|null|undefined} raw
 * @returns {Readonly<object>}
 */
function decodeTrustedFirebaseAuthContext(raw) {
  if (raw == null) {
    return authFailure(AUTH_STATUSES.unauthenticated, "unauthenticated");
  }
  if (typeof raw !== "object" || Array.isArray(raw)) {
    return authFailure(AUTH_STATUSES.malformed, "auth_context_not_object");
  }
  if (raw.captureAuthHandoff === true || raw.debugCaptureToken != null ||
      raw.captureAuthToken != null) {
    return authFailure(AUTH_STATUSES.forbidden,
      "capture_auth_handoff_rejected_as_production_auth");
  }
  if (raw.authenticated !== true) {
    return authFailure(AUTH_STATUSES.unauthenticated, "unauthenticated");
  }
  if (typeof raw.uid !== "string" || !raw.uid.trim()) {
    return authFailure(AUTH_STATUSES.malformed, "auth_uid_missing");
  }
  if (raw.tokenVerified !== true && raw.emulatorVerified !== true) {
    return authFailure(AUTH_STATUSES.malformed, "auth_not_server_verified");
  }
  const appCheckPresent = raw.appCheckPresent === true;
  const appCheckVerified = raw.appCheckVerified === true;
  return deepFreeze({
    contractVersion: 1,
    authContract: AUTH_CONTRACT,
    status: AUTH_STATUSES.authenticated,
    reasonCode: "auth_ok",
    uid: raw.uid.trim(),
    tokenVerified: raw.tokenVerified === true,
    emulatorVerified: raw.emulatorVerified === true,
    appCheckPresent,
    appCheckVerified,
    // Characterization only in this phase — App Check not required to proceed.
    appCheckRequired: false,
    authType: typeof raw.authType === "string" && raw.authType.trim() ?
      raw.authType.trim() : "firebase_auth",
  });
}

/**
 * Assert request payload does not spoof uid / revisions.
 * @param {object} payload
 * @param {object} authContext decoded authenticated context
 */
function assertPayloadAuthOwnership(payload, authContext) {
  if (authContext.status !== AUTH_STATUSES.authenticated) {
    fail(authContext.reasonCode || "unauthenticated");
  }
  if (payload == null || typeof payload !== "object" || Array.isArray(payload)) {
    fail("payload_not_object");
  }
  if (Object.prototype.hasOwnProperty.call(payload, "uid")) {
    fail("client_uid_spoof_rejected");
  }
  for (const field of [
    "imageRevision",
    "wardrobeItemRevision",
    "uploadGeneration",
    "generationId",
    "qualificationAuthority",
    "sourceObjectGeneration",
    "expectedProfileRevision",
    "machineEvidence",
    "storageBucket",
  ]) {
    if (Object.prototype.hasOwnProperty.call(payload, field)) {
      fail(`client_authority_field_rejected:${field}`);
    }
  }
  return authContext.uid;
}

function assertItemOwner(document, uid) {
  if (document == null) fail("item_not_found");
  const owner = document.ownerUid ?? document.uid ?? document.userId;
  if (owner != null && owner !== uid) fail("forbidden_wrong_owner");
  // Wardrobe docs live under users/{uid}/wardrobe/{itemId}; path ownership is
  // enforced by the endpoint when constructing the store key from auth uid.
  return true;
}

function authFailure(status, reasonCode) {
  return deepFreeze({
    contractVersion: 1,
    authContract: AUTH_CONTRACT,
    status,
    reasonCode,
    uid: null,
    tokenVerified: false,
    emulatorVerified: false,
    appCheckPresent: false,
    appCheckVerified: false,
    appCheckRequired: false,
    authType: null,
  });
}

function deepFreeze(value) {
  if (value == null || typeof value !== "object") return value;
  if (Object.isFrozen(value)) return value;
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  AUTH_CONTRACT,
  AUTH_DECODER_ID,
  AUTH_DECODER_VERSION,
  AUTH_STATUSES,
  assertItemOwner,
  assertPayloadAuthOwnership,
  decodeTrustedFirebaseAuthContext,
};
