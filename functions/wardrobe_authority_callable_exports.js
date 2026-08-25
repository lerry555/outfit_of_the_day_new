"use strict";

/**
 * Callable export builders for wardrobeRevisionLifecycle +
 * wardrobeQualificationAuthority.
 *
 * Default runtime mode: disabled. Shadow / controlled_write via config only.
 */

const functions = require("firebase-functions");
const {
  AUTHORITY_MODES,
  DEFAULT_MODE,
  resolveWardrobeAuthorityMode,
} = require("./wardrobe_authority_runtime_mode");
const {
  createWardrobeAuthorityCostGate,
} = require("./wardrobe_authority_cost_gate");
const {
  createWardrobeAuthorityCohortPolicy,
} = require("./wardrobe_authority_cohort_policy");
const {
  runQualificationAuthorityShadow,
} = require("./wardrobe_authority_shadow_runner");
const {
  createQualificationAuthorityHandler,
} = require("./wardrobe_qualification_authority_handler");
const {
  createRevisionLifecycleHandler,
} = require("./wardrobe_revision_lifecycle_handler");
const {
  fingerprint,
  safeLogFields,
  redactValue,
} = require("./wardrobe_authority_redaction");
const {
  RUNTIME_POLICIES,
} = require("./trusted_vision_result_provenance");
const {OPENAI_API_KEY_SECRET} = require("./openai_secret_binding");
const {WARDROBE_SHADOW_POLICY_SECRET} =
  require("./controlled_shadow_policy_config");
const {WARDROBE_CONTROLLED_WRITE_POLICY_SECRET} =
  require("./controlled_write_policy_config");
const {evaluateControlledWritePolicy} =
  require("./controlled_write_activation_policy");
const {consumeControlledWriteLease} =
  require("./controlled_write_single_use_lease");

const CALLABLE_NAMES = Object.freeze({
  lifecycle: "wardrobeRevisionLifecycle",
  authority: "wardrobeQualificationAuthority",
});

const SHADOW_LIFECYCLE_ALLOWED = Object.freeze([
  // Shadow/disabled: no mutations. Controlled write allow-list:
  "initialize_user_photo_authority",
  "request_same_image_reanalysis",
]);

const CONTROLLED_LIFECYCLE_BLOCKED = Object.freeze([
  "apply_classification_metadata_edit",
  "apply_user_correction",
  "record_derivative_completion",
]);

/**
 * Static foundation check for registering exports in index.js.
 * Does NOT require migration/deploy approval — those remain deploy blockers.
 * Flutter App Check init is tracked as a deploy blocker, not export-code block.
 */
function isWardrobeAuthorityStaticExportAllowed(state = {}) {
  return state.productionRuntimeWiringReady === true &&
    state.appCheckPolicyApproved === true &&
    state.firestoreRulesBaselineMerged === true &&
    state.firestoreRulesEmulatorTested === true &&
    state.lifecycleClientWritePathsReady === true;
}

function phase10bStaticExportState(overrides = {}) {
  return {
    productionRuntimeWiringReady: true,
    appCheckPolicyApproved: true,
    firestoreRulesBaselineMerged: true,
    firestoreRulesEmulatorTested: true,
    lifecycleClientWritePathsReady: true,
    // Deploy blocker historically — Flutter App Check now initialized (10C/10D).
    flutterAppCheckInitialized: true,
    migrationPolicyApproved: false,
    deploymentConfigApproved: false,
    ...overrides,
  };
}

function readModeFromEnv(env = process.env) {
  return resolveWardrobeAuthorityMode(
    env.WARDROBE_AUTHORITY_MODE || env.wardrobe_authority_mode || DEFAULT_MODE);
}

function readCohortFromEnv(env = process.env) {
  const raw = env.WARDROBE_AUTHORITY_COHORT_UIDS || "";
  const allowlistedUids = String(raw)
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  return createWardrobeAuthorityCohortPolicy({allowlistedUids});
}

/**
 * Build Gen1 onCall handlers. Inject dependencyFactory for tests.
 */
function buildWardrobeAuthorityCallables(options = {}) {
  const functionsApi = options.functions || functions;
  const region = options.region || "us-east1";
  const logger = options.logger || {info() {}, warn() {}, error() {}};
  const modeResolver = options.resolveMode || (() => readModeFromEnv());
  const cohort = options.cohortPolicy || readCohortFromEnv();
  const costGate = options.costGate || createWardrobeAuthorityCostGate();
  const dependencyFactory = options.dependencyFactory;

  const lifecycleHandler = createRevisionLifecycleHandler({
    dependencyFactory: dependencyFactory || {
      get() {
        throw new Error("dependency_factory_required");
      },
    },
    logger,
    enforceExportGate: false,
    exportReadinessState: options.exportReadinessState,
  });

  const authorityHandler = createQualificationAuthorityHandler({
    dependencyFactory: dependencyFactory || {
      get() {
        throw new Error("dependency_factory_required");
      },
    },
    logger,
    enforceExportGate: false,
    exportReadinessState: options.exportReadinessState,
  });

  const lifecycleCallable = functionsApi
    .region(region)
    .runWith({timeoutSeconds: 60, memory: "512MB"})
    .https.onCall(async (data, context) => {
      const modeInfo = modeResolver();
      const mode = modeInfo.mode;
      if (mode === AUTHORITY_MODES.disabled) {
        throw new functionsApi.https.HttpsError(
          "failed-precondition",
          "wardrobe_authority_mode_disabled",
        );
      }
      if (mode === AUTHORITY_MODES.shadow) {
        throw new functionsApi.https.HttpsError(
          "failed-precondition",
          "lifecycle_mutations_disabled_in_shadow",
        );
      }
      // controlled_write
      const uid = context.auth && context.auth.uid;
      const cohortEval = cohort.evaluate({uid, mode});
      if (!cohortEval.ok) {
        throw new functionsApi.https.HttpsError(
          "permission-denied",
          cohortEval.reasonCode,
        );
      }
      const op = data && data.operationKind;
      if (CONTROLLED_LIFECYCLE_BLOCKED.includes(op)) {
        throw new functionsApi.https.HttpsError(
          "failed-precondition",
          `lifecycle_op_blocked_until_cutover_confirmed:${op}`,
        );
      }
      if (!SHADOW_LIFECYCLE_ALLOWED.includes(op)) {
        throw new functionsApi.https.HttpsError(
          "invalid-argument",
          `lifecycle_op_not_allowlisted:${op}`,
        );
      }
      const result = await lifecycleHandler.handle(data, {
        auth: context.auth,
        app: context.app,
        appCheckPresent: !!(context.app),
        appCheckVerified: !!(context.app),
      });
      if (result.ok === false) {
        throw new functionsApi.https.HttpsError(
          result.error && result.error.code || "internal",
          result.error && result.error.message || "lifecycle_failed",
        );
      }
      return redactValue(result);
    });

  const authorityCallable = functionsApi
    .region(region)
    .runWith({timeoutSeconds: 120, memory: "1GB",
      secrets: [OPENAI_API_KEY_SECRET, WARDROBE_SHADOW_POLICY_SECRET,
        WARDROBE_CONTROLLED_WRITE_POLICY_SECRET]})
    .https.onCall(async (data, context) => {
      const modeInfo = modeResolver();
      let mode = modeInfo.mode;
      if (mode === AUTHORITY_MODES.disabled) {
        throw new functionsApi.https.HttpsError(
          "failed-precondition",
          "wardrobe_authority_mode_disabled",
        );
      }
      const uid = context.auth && context.auth.uid;
      if (mode === AUTHORITY_MODES.controlledWrite) {
        const cohortEval = cohort.evaluate({uid, mode});
        if (!cohortEval.ok) {
          throw new functionsApi.https.HttpsError(
            "permission-denied", cohortEval.reasonCode);
        }
      }

      if (mode === AUTHORITY_MODES.shadow) {
        if (!dependencyFactory || typeof dependencyFactory.get !== "function") {
          throw new functionsApi.https.HttpsError(
            "failed-precondition",
            "dependency_factory_required",
          );
        }
        const deps = dependencyFactory.get({mode});
        const shadow = await runQualificationAuthorityShadow(data, {
          authContext: {
            authenticated: !!(context.auth && context.auth.uid),
            uid,
            tokenVerified: true,
            emulatorVerified: false,
            appCheckPresent: !!(context.app),
            appCheckVerified: !!(context.app),
            authType: "firebase_auth",
          },
          store: deps.store,
          storageMetadataClient: deps.storageMetadataClient,
          visionClient: deps.visionClient,
          assignedAt: deps.assignedAt,
          costGate,
          logger,
          requireControlledShadowPolicy: true,
          shadowPolicy: deps.shadowPolicy,
          shadowLeaseStore: deps.shadowLeaseStore,
          serverNow: deps.serverNow,
          invocationId: context.rawRequest && context.rawRequest.id ||
            (typeof deps.invocationIdFactory === "function" ?
              deps.invocationIdFactory() : "invocation-unresolved"),
          provenancePolicy: RUNTIME_POLICIES.productionShadow,
        });
        logger.info?.(safeLogFields({
          operationKind: "authority_shadow",
          status: shadow.status,
          reasonCode: shadow.reasonCode,
          itemFingerprint: fingerprint(shadow.itemId),
          generationFingerprint: shadow.generationFingerprint,
        }));
        if (shadow.status === "unauthenticated" ||
            shadow.status === "forbidden") {
          throw new functionsApi.https.HttpsError(
            shadow.status === "unauthenticated" ?
              "unauthenticated" : "permission-denied",
            shadow.reasonCode || shadow.status,
          );
        }
        if (shadow.status === "resource_exhausted") {
          throw new functionsApi.https.HttpsError(
            "resource-exhausted",
            shadow.reasonCode || "rate_limited",
          );
        }
        return redactValue({
          ok: true,
          mode: AUTHORITY_MODES.shadow,
          result: shadow,
        });
      }

      // controlled_write authority — not enabled as default; still require cohort
      if (!uid) {
        throw new functionsApi.https.HttpsError(
          "unauthenticated", "auth_required");
      }
      if (!context.app) {
        throw new functionsApi.https.HttpsError(
          "failed-precondition", "app_check_required_missing");
      }
      for (const field of ["uid", "allowedUid", "allowedItemId", "allowedAction",
        "policy", "lease", "leaseId", "validFrom", "expiresAt",
        "maxAcceptedRequests", "expectedMode"]) {
        if (data && Object.prototype.hasOwnProperty.call(data, field)) {
          throw new functionsApi.https.HttpsError(
            "invalid-argument", `forbidden_request_field:${field}`);
        }
      }
      if (!dependencyFactory || typeof dependencyFactory.get !== "function") {
        throw new functionsApi.https.HttpsError(
          "failed-precondition", "dependency_factory_required");
      }
      let controlledDeps;
      try { controlledDeps = dependencyFactory.get({mode}); } catch (error) {
        throw new functionsApi.https.HttpsError("failed-precondition",
          String(error.message || "controlled_write_policy_missing"));
      }
      const policy = evaluateControlledWritePolicy(
        controlledDeps.controlledWritePolicy, data || {}, {uid, mode,
          now: controlledDeps.serverNow, sourceGenerationFingerprint: null});
      if (!policy.ok) {
        throw new functionsApi.https.HttpsError(
          "permission-denied", policy.reasonCode);
      }
      const lease = await consumeControlledWriteLease({leaseId: policy.leaseId,
        policyFingerprint: policy.policyFingerprint,
        allowedUid: policy._policy.allowedUid,
        allowedItemId: policy._policy.allowedItemId,
        allowedAction: policy._policy.allowedAction,
        now: controlledDeps.serverNow,
        invocationId: context.rawRequest && context.rawRequest.id ||
          (typeof controlledDeps.invocationIdFactory === "function" ?
            controlledDeps.invocationIdFactory() : "invocation-unresolved")},
      controlledDeps.controlledWriteLeaseStore);
      if (!lease.ok) {
        throw new functionsApi.https.HttpsError(
          "failed-precondition", lease.reasonCode);
      }
      const costLease = costGate && typeof costGate.begin === "function" ?
        costGate.begin({uid, itemId: data && data.itemId}) : null;
      if (costLease && !costLease.ok) {
        throw new functionsApi.https.HttpsError(
          "resource-exhausted", costLease.reasonCode || "rate_limited");
      }
      let result;
      try {
        result = await authorityHandler.handle(data, {
          auth: context.auth,
          app: context.app,
          appCheckPresent: !!(context.app),
          appCheckVerified: !!(context.app),
        });
      } finally {
        if (costLease && typeof costLease.release === "function") {
          costLease.release();
        }
      }
      if (result.ok === false) {
        throw new functionsApi.https.HttpsError(
          result.error && result.error.code || "internal",
          result.error && result.error.message || "authority_failed",
        );
      }
      return redactValue(result);
    });

  return Object.freeze({
    callableNames: CALLABLE_NAMES,
    defaultMode: DEFAULT_MODE,
    lifecycleCallable,
    authorityCallable,
  });
}

module.exports = {
  CALLABLE_NAMES,
  SHADOW_LIFECYCLE_ALLOWED,
  CONTROLLED_LIFECYCLE_BLOCKED,
  isWardrobeAuthorityStaticExportAllowed,
  phase10bStaticExportState,
  readModeFromEnv,
  readCohortFromEnv,
  buildWardrobeAuthorityCallables,
};
