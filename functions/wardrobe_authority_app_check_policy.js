"use strict";

/**
 * App Check policy for wardrobe authority production handlers.
 */

const APP_CHECK_POLICY_ID = "WardrobeAuthorityAppCheckPolicy";
const APP_CHECK_POLICY_VERSION = "wardrobe-authority-app-check-policy-v1";

const APP_CHECK_MODES = Object.freeze({
  required: "required",
  optionalWithWarning: "optional_with_warning",
  disabledForEmulatorOnly: "disabled_for_emulator_only",
});

/**
 * Production default is required. Emulator may disable only when explicitly
 * configured — never silent disable in production.
 */
function resolveAppCheckPolicy(config) {
  const environment = config && config.environmentMode;
  const mode = config && config.appCheckMode;
  if (environment === "production") {
    if (mode == null || mode === APP_CHECK_MODES.required) {
      return Object.freeze({
        mode: APP_CHECK_MODES.required,
        enforce: true,
        warnOnMissing: false,
        environment,
        rationale: "production_default_requires_app_check",
      });
    }
    if (mode === APP_CHECK_MODES.disabledForEmulatorOnly) {
      fail("app_check_disabled_forbidden_in_production");
    }
    if (mode === APP_CHECK_MODES.optionalWithWarning) {
      return Object.freeze({
        mode,
        enforce: false,
        warnOnMissing: true,
        environment,
        rationale: "explicit_optional_with_warning",
      });
    }
    fail(`app_check_mode_unsupported:${mode}`);
  }
  if (environment === "emulator" || environment === "test") {
    if (mode === APP_CHECK_MODES.disabledForEmulatorOnly || mode == null) {
      return Object.freeze({
        mode: APP_CHECK_MODES.disabledForEmulatorOnly,
        enforce: false,
        warnOnMissing: false,
        environment,
        rationale: environment === "test" ?
          "test_only_disable" : "emulator_only_disable",
      });
    }
    if (mode === APP_CHECK_MODES.required) {
      return Object.freeze({
        mode,
        enforce: true,
        warnOnMissing: false,
        environment,
        rationale: "emulator_explicit_required",
      });
    }
    if (mode === APP_CHECK_MODES.optionalWithWarning) {
      return Object.freeze({
        mode,
        enforce: false,
        warnOnMissing: true,
        environment,
        rationale: "emulator_optional_with_warning",
      });
    }
  }
  fail("app_check_environment_unresolved");
}

/**
 * Telemetry-safe App Check status: valid | missing | invalid.
 * Never includes token material.
 */
function resolveAppCheckStatus(appCheckContext) {
  const present = !!(appCheckContext && appCheckContext.appCheckPresent);
  const verified = !!(appCheckContext && appCheckContext.appCheckVerified);
  if (!present) return "missing";
  if (!verified) return "invalid";
  return "valid";
}

function evaluateAppCheck(policy, appCheckContext) {
  const present = !!(appCheckContext && appCheckContext.appCheckPresent);
  const verified = !!(appCheckContext && appCheckContext.appCheckVerified);
  const status = resolveAppCheckStatus(appCheckContext);
  if (policy.enforce) {
    if (!present || !verified) {
      return Object.freeze({
        ok: false,
        reasonCode: present ?
          "app_check_required_invalid" : "app_check_required_missing",
        warning: false,
        status,
      });
    }
    return Object.freeze({
      ok: true,
      reasonCode: "app_check_ok",
      warning: false,
      status,
    });
  }
  if (policy.warnOnMissing && (!present || !verified)) {
    return Object.freeze({
      ok: true,
      reasonCode: present ?
        "app_check_invalid_warning" : "app_check_missing_warning",
      warning: true,
      status,
    });
  }
  return Object.freeze({
    ok: true,
    reasonCode: "app_check_not_enforced",
    warning: false,
    status,
  });
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  APP_CHECK_MODES,
  APP_CHECK_POLICY_ID,
  APP_CHECK_POLICY_VERSION,
  evaluateAppCheck,
  resolveAppCheckPolicy,
  resolveAppCheckStatus,
};
