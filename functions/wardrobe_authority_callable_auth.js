"use strict";

/**
 * Callable/runtime Auth + App Check adapter for wardrobe authority handlers.
 */

const {
  AUTH_STATUSES,
  assertPayloadAuthOwnership,
  decodeTrustedFirebaseAuthContext,
} = require("./trusted_firebase_auth_context");
const {
  evaluateAppCheck,
  resolveAppCheckPolicy,
} = require("./wardrobe_authority_app_check_policy");

const ADAPTER_ID = "WardrobeAuthorityCallableAuthAdapter";
const ADAPTER_VERSION = "wardrobe-authority-callable-auth-adapter-v1";

/**
 * Build trusted auth context from a Firebase callable `context`-like object.
 * @param {object} runtimeContext
 * @param {object} config validated production config
 */
function decodeCallableAuthContext(runtimeContext, config) {
  if (runtimeContext == null || typeof runtimeContext !== "object") {
    return {
      auth: decodeTrustedFirebaseAuthContext(null),
      appCheck: {ok: false, reasonCode: "runtime_context_missing", warning: false},
      policy: null,
    };
  }
  if (runtimeContext.rawIdToken != null ||
      runtimeContext.idToken != null ||
      runtimeContext.captureAuthToken != null) {
    return {
      auth: decodeTrustedFirebaseAuthContext({
        authenticated: false,
        captureAuthHandoff: true,
      }),
      appCheck: {ok: false, reasonCode: "token_in_runtime_rejected", warning: false},
      policy: null,
    };
  }

  const authRaw = {
    authenticated: !!(runtimeContext.auth && runtimeContext.auth.uid),
    uid: runtimeContext.auth && runtimeContext.auth.uid,
    tokenVerified: runtimeContext.tokenVerified === true ||
      !!(runtimeContext.auth && runtimeContext.auth.token),
    emulatorVerified: runtimeContext.emulatorVerified === true ||
      config.environmentMode === "emulator" ||
      config.environmentMode === "test",
    appCheckPresent: runtimeContext.appCheckPresent === true ||
      !!(runtimeContext.app && runtimeContext.app.appId),
    appCheckVerified: runtimeContext.appCheckVerified === true ||
      !!(runtimeContext.app && runtimeContext.appAlreadyVerified === true),
    authType: "firebase_auth",
  };

  const auth = decodeTrustedFirebaseAuthContext(authRaw);
  const policy = resolveAppCheckPolicy(config);
  const appCheck = evaluateAppCheck(policy, auth);
  return Object.freeze({auth, appCheck, policy});
}

function assertCallableRequestOwnership(payload, decoded) {
  if (decoded.auth.status !== AUTH_STATUSES.authenticated) {
    const err = new Error(decoded.auth.reasonCode || "unauthenticated");
    err.status = "unauthenticated";
    throw err;
  }
  if (!decoded.appCheck.ok) {
    const err = new Error(decoded.appCheck.reasonCode);
    err.status = "forbidden";
    throw err;
  }
  return assertPayloadAuthOwnership(payload, decoded.auth);
}

module.exports = {
  ADAPTER_ID,
  ADAPTER_VERSION,
  assertCallableRequestOwnership,
  decodeCallableAuthContext,
};
