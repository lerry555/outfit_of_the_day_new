"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const path = require("node:path");

const {
  evaluateWardrobeAuthorityDeploymentPreflight,
  STAGE1_RULES_CLI,
  STAGE2_FUNCTIONS_CLI,
  STAGE2_FUNCTIONS_CLI_SEQUENTIAL,
  EXPECTED_PROJECT_ID,
} = require("./wardrobe_authority_deployment_preflight");
const {
  evaluateWardrobeAuthorityExportReadiness,
  phase10dExportReadinessState,
  phase10cExportReadinessState,
} = require("./wardrobe_authority_export_gate");
const {
  BACKEND_CONTRACT_GRAPH,
} = require("./backend_provider_dependency_graph");
const {
  DEFAULT_MODE,
} = require("./wardrobe_authority_runtime_mode");

const ROOT = path.resolve(__dirname, "..");

test("phase10d clears Console App Check blocker", () => {
  const r = evaluateWardrobeAuthorityExportReadiness(
    phase10dExportReadinessState());
  assert.equal(r.ready, false);
  assert.ok(!r.blockers.includes(
    "firebase_app_check_console_registration_pending"));
  assert.ok(!r.blockers.includes(
    "flutter_app_check_initialization_pending"));
  assert.ok(r.blockers.includes("manual_deployment_approval"));
  assert.ok(r.blockers.includes("shadow_validation_pending"));
  assert.ok(r.blockers.includes("migration_required"));
  assert.ok(r.blockers.includes("deployment_pending"));
  // Historical 10C still documents prior Console blocker.
  const legacy = evaluateWardrobeAuthorityExportReadiness(
    phase10cExportReadinessState());
  assert.ok(legacy.blockers.includes(
    "firebase_app_check_console_registration_pending"));
});

test("graph App Check console registration cleared; handlers disabled", () => {
  const appCheck = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "FlutterFirebaseAppCheck");
  const authH = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "WardrobeQualificationAuthorityHandler");
  const lifeH = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "WardrobeRevisionLifecycleHandler");
  const switchNode = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "ProductionAuthoritySwitch");
  assert.equal(appCheck.status, "client_app_check_ready");
  assert.deepEqual([...appCheck.blockers], []);
  assert.ok(!appCheck.blockers.includes(
    "firebase_app_check_console_registration_pending"));
  assert.equal(authH.status, "handler_export_ready");
  assert.equal(authH.defaultMode, "disabled");
  assert.equal(lifeH.status, "handler_export_ready");
  assert.equal(lifeH.defaultMode, "disabled");
  assert.equal(switchNode.status, "not_started");
  assert.ok(!switchNode.blockers.includes(
    "firebase_app_check_console_registration_pending"));
  assert.deepEqual([...switchNode.blockers], [
    "controlled_write_canary_retry_pending",
    "controlled_write_production_activation_approval_pending",
  ]);
});

test("deployment preflight ready for manual approval", () => {
  const result = evaluateWardrobeAuthorityDeploymentPreflight({
    rootDir: ROOT,
    consoleAppCheckRegistered: true,
    consoleEnforcementEnabled: false,
  });
  assert.equal(
    result.verdict,
    "deployment_preflight_ready_for_manual_approval",
  );
  assert.equal(result.readyForManualApproval, true);
  assert.equal(result.projectId, EXPECTED_PROJECT_ID);
  assert.equal(result.defaultMode, DEFAULT_MODE);
  assert.equal(result.defaultMode, "disabled");
  assert.deepEqual([...result.exactFunctionsToDeploy], [
    "wardrobeRevisionLifecycle",
    "wardrobeQualificationAuthority",
  ]);
  assert.equal(result.stage1RulesCli, STAGE1_RULES_CLI);
  assert.equal(result.stage2FunctionsCli, STAGE2_FUNCTIONS_CLI);
  assert.ok(result.stage2FunctionsCli.includes('"'));
  assert.equal(
    result.deployFilterFailureRootCause,
    "powershell_unquoted_comma_only_filter_not_missing_exports",
  );
  assert.equal(result.deployPerformed, false);
  assert.equal(result.enforcementEnabled, false);
  assert.equal(result.shadowEnabled, false);
  assert.equal(result.controlledWriteEnabled, false);
  assert.deepEqual([...result.blockers], []);
  for (const f of result.findings) {
    assert.equal(f.ok, true, `${f.id}: ${f.detail}`);
  }
});

test("preflight fails closed if Console enforcement already on", () => {
  const result = evaluateWardrobeAuthorityDeploymentPreflight({
    rootDir: ROOT,
    consoleAppCheckRegistered: true,
    consoleEnforcementEnabled: true,
  });
  assert.equal(result.verdict, "deployment_preflight_blocked");
  assert.ok(result.blockers.includes(
    "app_check_enforcement_must_remain_off_for_stage2"));
});

test("Stage2 CLI quoting + sequential fallback documented", () => {
  assert.match(STAGE2_FUNCTIONS_CLI, /"/);
  assert.match(STAGE2_FUNCTIONS_CLI, /wardrobeRevisionLifecycle/);
  assert.match(STAGE2_FUNCTIONS_CLI, /wardrobeQualificationAuthority/);
  assert.equal(STAGE2_FUNCTIONS_CLI_SEQUENTIAL.length, 2);
  assert.ok(!STAGE2_FUNCTIONS_CLI_SEQUENTIAL[0].includes(","));
  assert.ok(!STAGE2_FUNCTIONS_CLI_SEQUENTIAL[1].includes(","));
});
