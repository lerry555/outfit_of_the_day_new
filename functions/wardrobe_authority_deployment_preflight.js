"use strict";

/**
 * M11.1 Phase 10D — Deployment preflight (read-only).
 * Does not deploy, enforce, migrate, or invoke live backends.
 */

const fs = require("node:fs");
const path = require("node:path");

const {
  CALLABLE_NAMES,
  isWardrobeAuthorityStaticExportAllowed,
  phase10bStaticExportState,
} = require("./wardrobe_authority_callable_exports");
const {
  DEFAULT_MODE,
  AUTHORITY_MODES,
} = require("./wardrobe_authority_runtime_mode");
const {
  evaluateWardrobeAuthorityExportReadiness,
  phase10dExportReadinessState,
} = require("./wardrobe_authority_export_gate");
const {
  BACKEND_CONTRACT_GRAPH,
} = require("./backend_provider_dependency_graph");
const {
  APP_CHECK_MODES,
  resolveAppCheckPolicy,
} = require("./wardrobe_authority_app_check_policy");

const PREFLIGHT_ID = "WardrobeAuthorityDeploymentPreflight";
const PREFLIGHT_VERSION = "wardrobe-authority-deployment-preflight-v1";

const EXPECTED_PROJECT_ID = "outfitoftheday-4d401";
const EXPECTED_ANDROID_PACKAGE = "com.krist.outfitoftheday";
const EXPECTED_REGION = "us-east1";

const STAGE1_RULES_CLI =
  "firebase deploy --only firestore:rules --project outfitoftheday-4d401";
// Quote the --only value. On Windows PowerShell, an unquoted comma makes an
// ArrayLiteral and Firebase CLI reports "No function matches given --only
// filters" even when the exports exist locally.
const STAGE2_FUNCTIONS_CLI =
  "firebase deploy --only " +
  "\"functions:wardrobeRevisionLifecycle," +
  "functions:wardrobeQualificationAuthority\" " +
  "--project outfitoftheday-4d401";
const STAGE2_FUNCTIONS_CLI_SEQUENTIAL = Object.freeze([
  "firebase deploy --only functions:wardrobeRevisionLifecycle " +
    "--project outfitoftheday-4d401",
  "firebase deploy --only functions:wardrobeQualificationAuthority " +
    "--project outfitoftheday-4d401",
]);

/**
 * @param {{
 *   rootDir?: string,
 *   consoleAppCheckRegistered?: boolean,
 *   consoleEnforcementEnabled?: boolean,
 * }} [options]
 */
function evaluateWardrobeAuthorityDeploymentPreflight(options = {}) {
  const root = options.rootDir || path.resolve(__dirname, "..");
  const findings = [];
  const blockers = [];

  // --- Project / alias ---
  const firebaserc = JSON.parse(
    fs.readFileSync(path.join(root, ".firebaserc"), "utf8"));
  const defaultProject = firebaserc.projects && firebaserc.projects.default;
  const aliasProject = firebaserc.projects && firebaserc.projects.outfitoftheday;
  if (defaultProject !== EXPECTED_PROJECT_ID ||
      aliasProject !== EXPECTED_PROJECT_ID) {
    blockers.push("firebase_project_alias_mismatch");
    findings.push({
      id: "project_alias",
      ok: false,
      detail: `default=${defaultProject} alias=${aliasProject}`,
    });
  } else {
    findings.push({
      id: "project_alias",
      ok: true,
      detail: EXPECTED_PROJECT_ID,
    });
  }

  // --- Firestore rules baseline ---
  const firebaseJson = JSON.parse(
    fs.readFileSync(path.join(root, "firebase.json"), "utf8"));
  const rulesPath = firebaseJson.firestore && firebaseJson.firestore.rules;
  const rulesAbs = rulesPath ? path.join(root, rulesPath) : null;
  const rulesOk = rulesPath === "firestore.rules" &&
    rulesAbs && fs.existsSync(rulesAbs);
  if (!rulesOk) {
    blockers.push("firestore_rules_baseline_not_deployable");
    findings.push({id: "firestore_rules", ok: false, detail: rulesPath});
  } else {
    const rulesText = fs.readFileSync(rulesAbs, "utf8");
    const hasBoundary =
      rulesText.includes("qualificationAuthority") &&
      rulesText.includes("wardrobeProfile");
    if (!hasBoundary) {
      blockers.push("firestore_rules_boundary_missing");
      findings.push({id: "firestore_rules", ok: false, detail: "boundary"});
    } else {
      findings.push({
        id: "firestore_rules",
        ok: true,
        detail: "firestore.rules deployable baseline with wardrobe boundary",
      });
    }
  }

  // --- Callable names / duplicates / default mode ---
  const indexPath = path.join(root, "functions", "index.js");
  const indexText = fs.readFileSync(indexPath, "utf8");
  const lifeCount = (indexText.match(
    /^\s*exports\.wardrobeRevisionLifecycle\s*=/gm) || []).length;
  const authCount = (indexText.match(
    /^\s*exports\.wardrobeQualificationAuthority\s*=/gm) || []).length;
  const namesOk =
    CALLABLE_NAMES.lifecycle === "wardrobeRevisionLifecycle" &&
    CALLABLE_NAMES.authority === "wardrobeQualificationAuthority" &&
    lifeCount === 1 &&
    authCount === 1;
  if (!namesOk) {
    blockers.push("callable_export_names_or_duplicates_invalid");
    findings.push({
      id: "callable_exports",
      ok: false,
      detail: `life=${lifeCount} auth=${authCount}`,
    });
  } else {
    findings.push({
      id: "callable_exports",
      ok: true,
      detail: `${CALLABLE_NAMES.lifecycle},${CALLABLE_NAMES.authority}`,
    });
  }

  if (DEFAULT_MODE !== AUTHORITY_MODES.disabled) {
    blockers.push("default_mode_not_disabled");
    findings.push({id: "default_mode", ok: false, detail: DEFAULT_MODE});
  } else {
    findings.push({
      id: "default_mode",
      ok: true,
      detail: "disabled",
    });
  }

  const staticOk = isWardrobeAuthorityStaticExportAllowed(
    phase10bStaticExportState({flutterAppCheckInitialized: true}));
  findings.push({
    id: "static_export_gate",
    ok: staticOk,
    detail: staticOk ? "allowed" : "blocked",
  });
  if (!staticOk) blockers.push("static_export_gate_failed");

  // --- Runtime shape (region / memory / timeout; no secrets required for disabled) ---
  const exportsSrc = fs.readFileSync(
    path.join(root, "functions", "wardrobe_authority_callable_exports.js"),
    "utf8");
  const regionOk = exportsSrc.includes(`"${EXPECTED_REGION}"`) ||
    exportsSrc.includes(`'${EXPECTED_REGION}'`);
  const lifecycleRuntime =
    exportsSrc.includes("timeoutSeconds: 60") &&
    exportsSrc.includes('memory: "512MB"');
  const authorityRuntime =
    exportsSrc.includes("timeoutSeconds: 120") &&
    exportsSrc.includes('memory: "1GB"');
  const noSecretsOnAuthorityCallables =
    !/runWith\(\{[^}]*secrets/s.test(exportsSrc);
  if (!regionOk || !lifecycleRuntime || !authorityRuntime) {
    blockers.push("callable_runtime_config_incomplete");
    findings.push({
      id: "callable_runtime",
      ok: false,
      detail: `region=${regionOk} life=${lifecycleRuntime} auth=${authorityRuntime}`,
    });
  } else {
    findings.push({
      id: "callable_runtime",
      ok: true,
      detail:
        `${EXPECTED_REGION}; lifecycle 60s/512MB; authority 120s/1GB; ` +
        `secrets_declared=${!noSecretsOnAuthorityCallables}`,
    });
  }
  // Disabled-mode Stage 2 does not require OpenAI secrets.
  findings.push({
    id: "secrets_for_disabled_stage",
    ok: true,
    detail: "no wardrobe-authority secrets required while mode=disabled",
  });

  // --- App Check (Console registration confirmed by operator; enforcement off) ---
  const consoleRegistered = options.consoleAppCheckRegistered !== false;
  const enforcementOn = options.consoleEnforcementEnabled === true;
  const prodPolicy = resolveAppCheckPolicy({
    environmentMode: "production",
    appCheckMode: APP_CHECK_MODES.required,
  });
  const emulatorPolicy = resolveAppCheckPolicy({
    environmentMode: "emulator",
    appCheckMode: APP_CHECK_MODES.disabledForEmulatorOnly,
  });
  if (!consoleRegistered) {
    blockers.push("firebase_app_check_console_registration_pending");
  }
  if (enforcementOn) {
    blockers.push("app_check_enforcement_must_remain_off_for_stage2");
  }
  findings.push({
    id: "app_check_console",
    ok: consoleRegistered && !enforcementOn,
    detail:
      `android=${EXPECTED_ANDROID_PACKAGE}; play_integrity; ` +
      `registered=${consoleRegistered}; enforcement=${enforcementOn}`,
  });
  findings.push({
    id: "app_check_server_policy",
    ok: prodPolicy.enforce === true && emulatorPolicy.enforce === false,
    detail:
      `production=${prodPolicy.mode}; emulator=${emulatorPolicy.mode}`,
  });

  // --- Import-time safety (registration IIFE must not invoke live deps) ---
  const liveDepsWiredLazy =
    indexText.includes("wardrobe_authority_production_dependencies") &&
    indexText.includes("Disabled mode returns before `.get()`");
  const noTopLevelAuthorityInvoke =
    !/runQualificationAuthorityShadow\(/.test(
      indexText.slice(indexText.indexOf("registerWardrobeAuthorityCallables")));
  findings.push({
    id: "import_time_safety",
    ok: liveDepsWiredLazy && lifeCount === 1,
    detail: liveDepsWiredLazy ?
      "live dependencies wired lazily behind disabled gate" :
      "lazy live dependency wiring missing",
  });
  if (!liveDepsWiredLazy) blockers.push("lazy_live_dependency_wiring_missing");

  // --- Graph / gate ---
  const readiness = evaluateWardrobeAuthorityExportReadiness(
    phase10dExportReadinessState());
  if (readiness.blockers.includes(
    "firebase_app_check_console_registration_pending")) {
    blockers.push("export_gate_still_has_console_app_check_blocker");
  }
  if (readiness.blockers.includes("flutter_app_check_initialization_pending")) {
    blockers.push("export_gate_still_has_flutter_app_check_blocker");
  }
  findings.push({
    id: "export_gate_phase10d",
    ok: !readiness.blockers.includes(
      "firebase_app_check_console_registration_pending"),
    detail: readiness.blockers.join(","),
  });

  const appCheckNode = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "FlutterFirebaseAppCheck");
  const authH = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "WardrobeQualificationAuthorityHandler");
  const lifeH = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "WardrobeRevisionLifecycleHandler");
  const switchNode = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "ProductionAuthoritySwitch");

  const graphOk =
    appCheckNode &&
    appCheckNode.status === "client_app_check_ready" &&
    !(appCheckNode.blockers || []).includes(
      "firebase_app_check_console_registration_pending") &&
    authH && authH.status === "handler_export_ready" &&
    authH.defaultMode === "disabled" &&
    lifeH && lifeH.status === "handler_export_ready" &&
    lifeH.defaultMode === "disabled" &&
    switchNode && switchNode.status === "not_started" &&
    !(switchNode.blockers || []).includes(
      "firebase_app_check_console_registration_pending");
  if (!graphOk) blockers.push("dependency_graph_preflight_mismatch");
  findings.push({id: "dependency_graph", ok: !!graphOk, detail: "phase10d"});

  const uniqueBlockers = [...new Set(blockers)];
  const readyForManualApproval = uniqueBlockers.length === 0;

  return Object.freeze({
    preflightId: PREFLIGHT_ID,
    preflightVersion: PREFLIGHT_VERSION,
    verdict: readyForManualApproval ?
      "deployment_preflight_ready_for_manual_approval" :
      "deployment_preflight_blocked",
    projectId: EXPECTED_PROJECT_ID,
    androidPackage: EXPECTED_ANDROID_PACKAGE,
    region: EXPECTED_REGION,
    defaultMode: DEFAULT_MODE,
    callableNames: CALLABLE_NAMES,
    stage1RulesCli: STAGE1_RULES_CLI,
    stage2FunctionsCli: STAGE2_FUNCTIONS_CLI,
    stage2FunctionsCliSequential: STAGE2_FUNCTIONS_CLI_SEQUENTIAL,
    deployFilterFailureRootCause:
      "powershell_unquoted_comma_only_filter_not_missing_exports",
    exactFunctionsToDeploy: Object.freeze([
      CALLABLE_NAMES.lifecycle,
      CALLABLE_NAMES.authority,
    ]),
    readyForManualApproval,
    deployPerformed: false,
    enforcementEnabled: false,
    shadowEnabled: false,
    controlledWriteEnabled: false,
    findings: Object.freeze(findings),
    blockers: Object.freeze(uniqueBlockers),
    remainingDeployBlockers: Object.freeze([
      "manual_deployment_approval",
      "rules_deploy_pending",
      "functions_deploy_pending",
      "shadow_validation_pending",
      "controlled_write_approval_pending",
      "migration_required",
    ]),
  });
}

module.exports = {
  PREFLIGHT_ID,
  PREFLIGHT_VERSION,
  EXPECTED_PROJECT_ID,
  EXPECTED_ANDROID_PACKAGE,
  EXPECTED_REGION,
  STAGE1_RULES_CLI,
  STAGE2_FUNCTIONS_CLI,
  STAGE2_FUNCTIONS_CLI_SEQUENTIAL,
  evaluateWardrobeAuthorityDeploymentPreflight,
};
