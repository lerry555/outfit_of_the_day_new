"use strict";

/**
 * Explicit export-readiness gate. Fail-closed until blockers clear.
 * Must NOT be satisfied in this phase while Rules baseline is missing.
 */

const GATE_ID = "WardrobeAuthorityExportGate";
const GATE_VERSION = "wardrobe-authority-export-gate-v1";

const REQUIRED_CLEAR_BLOCKERS = Object.freeze([
  "security_rules_baseline_missing",
  "migration_required",
  "client_write_path_cutover_pending",
  "deployment_pending",
  "production_export_pending",
]);

/**
 * @param {{
 *   productionRuntimeWiringReady?: boolean,
 *   appCheckPolicyApproved?: boolean,
 *   firestoreRulesBaselineMerged?: boolean,
 *   firestoreRulesEmulatorTested?: boolean,
 *   migrationPolicyApproved?: boolean,
 *   lifecycleClientWritePathsReady?: boolean,
 *   deploymentConfigApproved?: boolean,
 *   blockers?: string[],
 * }} state
 */
function evaluateWardrobeAuthorityExportReadiness(state = {}) {
  const blockers = [];
  if (state.productionRuntimeWiringReady !== true) {
    blockers.push("production_runtime_wiring_incomplete");
  }
  if (state.appCheckPolicyApproved !== true) {
    blockers.push("app_check_policy_unapproved");
  }
  if (state.firestoreRulesBaselineMerged !== true ||
      state.firestoreRulesEmulatorTested !== true) {
    blockers.push("security_rules_baseline_missing");
  }
  if (state.migrationPolicyApproved !== true) {
    blockers.push("migration_required");
  }
  if (state.lifecycleClientWritePathsReady !== true) {
    blockers.push("client_write_path_cutover_pending");
  }
  if (state.deploymentConfigApproved !== true) {
    blockers.push("deployment_pending");
  }
  if (Array.isArray(state.blockers)) {
    for (const item of state.blockers) blockers.push(item);
  }
  const unique = [...new Set(blockers)];
  return Object.freeze({
    gateId: GATE_ID,
    gateVersion: GATE_VERSION,
    ready: unique.length === 0,
    productionExportAllowed: false, // hard-false this phase
    blockers: Object.freeze(unique),
  });
}

function assertWardrobeAuthorityExportReady(state) {
  const result = evaluateWardrobeAuthorityExportReadiness(state);
  // This phase always blocks export even if someone clears other flags.
  if (!result.ready || result.blockers.includes("security_rules_baseline_missing") ||
      result.productionExportAllowed !== true) {
    const err = new Error(
      `export_blocked:${result.blockers.join(",") || "security_rules_baseline_missing"}`);
    err.exportReadiness = result;
    throw err;
  }
  return result;
}

/** Default phase-9B state: wiring foundation ready, export blocked by Rules. */
function phase9bExportReadinessState(overrides = {}) {
  return {
    productionRuntimeWiringReady: true,
    appCheckPolicyApproved: true,
    firestoreRulesBaselineMerged: false,
    firestoreRulesEmulatorTested: false,
    migrationPolicyApproved: false,
    lifecycleClientWritePathsReady: false,
    deploymentConfigApproved: false,
    ...overrides,
  };
}

/**
 * Phase 5.3B-9C: discovery confirmed baseline absent in-repo.
 * Do NOT clear security_rules_baseline_missing until recovered baseline is
 * merged + emulator-tested.
 */
function phase9cExportReadinessState(overrides = {}) {
  return phase9bExportReadinessState({
    // Discovery completed; merge/emulator still false.
    firestoreRulesBaselineMerged: false,
    firestoreRulesEmulatorTested: false,
    ...overrides,
  });
}

/**
 * Phase 5.3B-9C-R: baseline recovered, boundary merged, emulator tested.
 * Clears only security_rules_baseline_missing; export remains blocked.
 */
function phase9cRExportReadinessState(overrides = {}) {
  return phase9bExportReadinessState({
    firestoreRulesBaselineMerged: true,
    firestoreRulesEmulatorTested: true,
    ...overrides,
  });
}

/**
 * Phase M11.1-10A: client write-path cutover wired.
 * Clears security_rules_baseline_missing + client_write_path_cutover_pending.
 */
function phase10aExportReadinessState(overrides = {}) {
  return phase9cRExportReadinessState({
    lifecycleClientWritePathsReady: true,
    ...overrides,
  });
}

/**
 * Phase M11.1-10B: static callable export foundation ready; deploy blocked.
 * Adds Flutter App Check + manual approval + shadow validation blockers.
 */
function phase10bExportReadinessState(overrides = {}) {
  return phase10aExportReadinessState({
    blockers: [
      "flutter_app_check_initialization_pending",
      "manual_deployment_approval",
      "shadow_validation_pending",
    ],
    ...overrides,
  });
}

/**
 * Phase M11.1-10C: Flutter App Check SDK initialized.
 * Clears flutter_app_check_initialization_pending; Console registration remains.
 */
function phase10cExportReadinessState(overrides = {}) {
  return phase10aExportReadinessState({
    blockers: [
      "firebase_app_check_console_registration_pending",
      "manual_deployment_approval",
      "shadow_validation_pending",
    ],
    ...overrides,
  });
}

/**
 * Phase M11.1-10D: Console App Check registration confirmed (manual).
 * Clears firebase_app_check_console_registration_pending.
 * Deploy still requires explicit manual approval; no enforcement/shadow yet.
 */
function phase10dExportReadinessState(overrides = {}) {
  return phase10aExportReadinessState({
    blockers: [
      "manual_deployment_approval",
      "shadow_validation_pending",
    ],
    ...overrides,
  });
}

module.exports = {
  GATE_ID,
  GATE_VERSION,
  REQUIRED_CLEAR_BLOCKERS,
  assertWardrobeAuthorityExportReady,
  evaluateWardrobeAuthorityExportReadiness,
  phase9bExportReadinessState,
  phase9cExportReadinessState,
  phase9cRExportReadinessState,
  phase10aExportReadinessState,
  phase10bExportReadinessState,
  phase10cExportReadinessState,
  phase10dExportReadinessState,
};
