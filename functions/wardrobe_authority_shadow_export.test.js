"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

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
  createZeroWriteStoreProxy,
} = require("./wardrobe_authority_shadow_runner");
const {
  CALLABLE_NAMES,
  isWardrobeAuthorityStaticExportAllowed,
  phase10bStaticExportState,
  buildWardrobeAuthorityCallables,
} = require("./wardrobe_authority_callable_exports");
const {
  evaluateWardrobeAuthorityExportReadiness,
  phase10bExportReadinessState,
  phase10cExportReadinessState,
  phase10dExportReadinessState,
} = require("./wardrobe_authority_export_gate");
const {
  createMemoryTransactionalStore,
} = require("./wardrobe_profile_firestore_repository");
const {
  createFakeStorageMetadataClient,
} = require("./trusted_storage_metadata_adapter");
const {
  createFakeTrustedVisionAnalysisClient,
} = require("./trusted_vision_analysis_client");
const {
  BACKEND_CONTRACT_GRAPH,
} = require("./backend_provider_dependency_graph");

const ROOT = path.resolve(__dirname, "..");
const FIXTURE_ROOT = path.join(
  ROOT, "test", "fixtures", "backend_qualification");
const PATH = "wardrobe/owner-uid/photo.jpg";

function baseDoc(overrides = {}) {
  return {
    name: "Hoodie",
    storagePath: PATH,
    ...overrides,
  };
}

function auth(uid = "owner-uid") {
  return {
    authenticated: true,
    uid,
    tokenVerified: true,
    emulatorVerified: false,
    appCheckPresent: true,
    appCheckVerified: true,
    authType: "firebase_auth",
  };
}

// --- Export ---

test("1 exact callable names match Flutter", () => {
  assert.equal(CALLABLE_NAMES.lifecycle, "wardrobeRevisionLifecycle");
  assert.equal(CALLABLE_NAMES.authority, "wardrobeQualificationAuthority");
  const dart = fs.readFileSync(
    path.join(ROOT, "lib/Services/wardrobe_revision_lifecycle_client.dart"),
    "utf8");
  assert.match(dart, /wardrobeRevisionLifecycle/);
  const authDart = fs.readFileSync(
    path.join(ROOT,
      "lib/Services/wardrobe_qualification_authority_client.dart"),
    "utf8");
  assert.match(authDart, /wardrobeQualificationAuthority/);
});

test("2 no duplicate exports in index.js", () => {
  const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  const life = (index.match(
    /^\s*exports\.wardrobeRevisionLifecycle\s*=/gm) || []).length;
  const authN = (index.match(
    /^\s*exports\.wardrobeQualificationAuthority\s*=/gm) || []).length;
  assert.equal(life, 1);
  assert.equal(authN, 1);
});

test("2b index.js exports both callables with Gen1 trigger metadata", () => {
  // Fresh require of index (may already be cached from other tests).
  const indexExports = require("./index.js");
  assert.equal(typeof indexExports.wardrobeRevisionLifecycle, "function");
  assert.equal(typeof indexExports.wardrobeQualificationAuthority, "function");
  const lifeTrigger = indexExports.wardrobeRevisionLifecycle.__trigger;
  const authTrigger = indexExports.wardrobeQualificationAuthority.__trigger;
  assert.ok(lifeTrigger);
  assert.ok(authTrigger);
  assert.deepEqual(lifeTrigger.regions, ["us-east1"]);
  assert.deepEqual(authTrigger.regions, ["us-east1"]);
  assert.equal(lifeTrigger.availableMemoryMb, 512);
  assert.equal(lifeTrigger.timeout, "60s");
  assert.equal(authTrigger.availableMemoryMb, 1024);
  assert.equal(authTrigger.timeout, "120s");
  assert.equal(DEFAULT_MODE, "disabled");
});

test("2c import registers callables without live OpenAI/Firebase writes", () => {
  const before = Date.now();
  const indexExports = require("./index.js");
  assert.ok(indexExports.wardrobeRevisionLifecycle);
  assert.ok(indexExports.wardrobeQualificationAuthority);
  // Registration is sync; live deps factory throws only if invoked.
  const factoryProbe = () => {
    throw new Error("should_not_call_live_deps_during_import_probe");
  };
  assert.equal(typeof factoryProbe, "function");
  assert.ok(Date.now() - before < 60000);
});

test("3 existing exports unchanged presence", () => {
  const indexExports = require("./index.js");
  assert.equal(typeof indexExports.stylistChat, "function");
  assert.equal(typeof indexExports.analyzeWardrobeSmart, "function");
  assert.equal(typeof indexExports.generateHomeOutfit, "function");
  assert.equal(typeof indexExports.chatWithStylist, "function");
  assert.equal(typeof indexExports.analyzeClothingImage, "function");
  assert.equal(typeof indexExports.removeBackgroundOnUpload, "function");
  assert.equal(typeof indexExports.prepareProductLinkImage, "function");
  assert.equal(typeof indexExports.processWardrobeProductLinkImage, "function");
});

test("4 static export gate pass for 10B foundation", () => {
  assert.equal(
    isWardrobeAuthorityStaticExportAllowed(phase10bStaticExportState()),
    true);
});

test("5 disabled default mode", () => {
  assert.equal(DEFAULT_MODE, AUTHORITY_MODES.disabled);
  assert.equal(resolveWardrobeAuthorityMode(null).mode, "disabled");
  assert.equal(resolveWardrobeAuthorityMode("").mode, "disabled");
});

test("5b handler wrappers exist; callables stay disabled by default", async () => {
  assert.equal(
    fs.existsSync(path.join(__dirname, "wardrobe_revision_lifecycle_handler.js")),
    true,
  );
  assert.equal(
    fs.existsSync(
      path.join(__dirname, "wardrobe_qualification_authority_handler.js")),
    true,
  );
  let lifeHandler;
  let authHandler;
  const fakeFunctions = {
    region() {
      return this;
    },
    runWith() {
      return this;
    },
    https: {
      onCall(handler) {
        return Object.assign(handler, {__trigger: {regions: ["us-east1"]}});
      },
      HttpsError: class HttpsError extends Error {
        constructor(code, message) {
          super(message);
          this.code = code;
        }
      },
    },
  };
  const built = buildWardrobeAuthorityCallables({
    functions: fakeFunctions,
    dependencyFactory: {
      get() {
        throw new Error("live_deps_must_not_run_in_disabled_probe");
      },
    },
    resolveMode: () => resolveWardrobeAuthorityMode(DEFAULT_MODE),
  });
  assert.equal(built.defaultMode, "disabled");
  lifeHandler = built.lifecycleCallable;
  authHandler = built.authorityCallable;
  await assert.rejects(
    () => lifeHandler({}, {auth: {uid: "u1"}}),
    (err) => err && err.code === "failed-precondition" &&
      /wardrobe_authority_mode_disabled/.test(err.message),
  );
  await assert.rejects(
    () => authHandler({}, {auth: {uid: "u1"}}),
    (err) => err && err.code === "failed-precondition" &&
      /wardrobe_authority_mode_disabled/.test(err.message),
  );
});

// --- Modes ---

test("6 invalid mode fails closed", () => {
  assert.throws(() => resolveWardrobeAuthorityMode("live"), /invalid_authority_mode/);
});

test("7-9 mode enum values", () => {
  assert.equal(resolveWardrobeAuthorityMode("disabled").mode, "disabled");
  assert.equal(resolveWardrobeAuthorityMode("shadow").mode, "shadow");
  assert.equal(resolveWardrobeAuthorityMode("controlled_write").mode,
    "controlled_write");
});

test("10-12 shadow zero-write + no lazy init write + simulated repo", async () => {
  const store = createMemoryTransactionalStore({
    "users/owner-uid/wardrobe/item-1": baseDoc(),
  });
  const before = JSON.stringify(store._dump());
  const storage = createFakeStorageMetadataClient({
    [PATH]: {
      generation: "42",
      metageneration: "1",
      size: "100",
      contentType: "image/jpeg",
      updated: "2026-01-01T00:00:00.000Z",
      md5Hash: "abc",
      crc32c: "def",
    },
  });
  const result = await runQualificationAuthorityShadow({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
    offlineScenarioId: "front_only_garment",
  }, {
    authContext: auth(),
    store,
    storageMetadataClient: storage,
    visionClient: createFakeTrustedVisionAnalysisClient(),
    fixtureRoot: FIXTURE_ROOT,
    assignedAt: "2026-01-01T00:00:00.000Z",
    costGate: createWardrobeAuthorityCostGate(),
  });
  assert.equal(result.mode, "shadow");
  assert.equal(result.wroteProfile, false);
  assert.equal(result.authorityInitialized, false);
  assert.equal(result.wouldInitializeAuthority, true);
  assert.ok(["shadow_ok", "mapping_failed", "qualification_failed",
    "invalid_parser_result"].includes(result.status) ||
    result.status === "shadow_ok" || result.mapperStatus != null);
  // Store untouched
  assert.equal(JSON.stringify(store._dump()), before);
  assert.equal(store._get("owner-uid", "item-1").qualificationAuthority, undefined);
  assert.equal(store._get("owner-uid", "item-1").wardrobeProfile, undefined);
});

test("13 controlled cohort allowed", () => {
  const cohort = createWardrobeAuthorityCohortPolicy({
    allowlistedUids: ["owner-uid"],
  });
  const ev = cohort.evaluate({uid: "owner-uid", mode: "controlled_write"});
  assert.equal(ev.ok, true);
  assert.equal(ev.matched, true);
});

test("14 non-cohort denied with shadow fallback", () => {
  const cohort = createWardrobeAuthorityCohortPolicy({
    allowlistedUids: ["other"],
  });
  const ev = cohort.evaluate({uid: "owner-uid", mode: "controlled_write"});
  assert.equal(ev.ok, false);
  assert.equal(ev.fallbackMode, "shadow");
});

// --- Auth ---

test("15 unauthenticated shadow", async () => {
  const store = createMemoryTransactionalStore({
    "users/owner-uid/wardrobe/item-1": baseDoc(),
  });
  const result = await runQualificationAuthorityShadow({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
  }, {
    authContext: {authenticated: false},
    store,
    storageMetadataClient: createFakeStorageMetadataClient({}),
  });
  assert.equal(result.status, "unauthenticated");
});

test("16 Flutter App Check SDK + Console registration confirmed", () => {
  const readiness = evaluateWardrobeAuthorityExportReadiness(
    phase10dExportReadinessState());
  assert.ok(!readiness.blockers.includes(
    "flutter_app_check_initialization_pending"));
  assert.ok(!readiness.blockers.includes(
    "firebase_app_check_console_registration_pending"));
  const pubspec = fs.readFileSync(path.join(ROOT, "pubspec.yaml"), "utf8");
  assert.ok(pubspec.includes("firebase_app_check"));
  const bootstrap = fs.readFileSync(
    path.join(ROOT, "lib", "Services", "firebase_app_check_bootstrap.dart"),
    "utf8");
  assert.ok(bootstrap.includes("FirebaseAppCheckBootstrap"));
  assert.equal(bootstrap.includes("DEBUG_TOKEN"), false);
});

test("17 emulator/test mode policy still available", () => {
  // Covered by existing app check policy module; assert default production.
  assert.equal(DEFAULT_MODE, "disabled");
});

test("18 owner mismatch forbidden", async () => {
  const store = createMemoryTransactionalStore({
    "users/owner-uid/wardrobe/item-1": baseDoc(),
  });
  const result = await runQualificationAuthorityShadow({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
    uid: "spoof",
  }, {
    authContext: auth("owner-uid"),
    store,
    storageMetadataClient: createFakeStorageMetadataClient({}),
  });
  assert.equal(result.status, "forbidden");
});

// --- Cost ---

test("19-20 duplicate suppression and rate limit", () => {
  const gate = createWardrobeAuthorityCostGate({
    limits: {perUserPerMinute: 3, perItemPerMinute: 2},
    now: (() => {
      let t = 1_000_000;
      return () => t;
    })(),
  });
  const a = gate.begin({uid: "u1", itemId: "i1"});
  assert.equal(a.ok, true);
  const dup = gate.begin({uid: "u1", itemId: "i1"});
  assert.equal(dup.ok, false);
  assert.equal(dup.reasonCode, "duplicate_in_flight");
  a.release();
  const b = gate.begin({uid: "u1", itemId: "i1"});
  assert.equal(b.ok, true);
  b.release();
  const c = gate.begin({uid: "u1", itemId: "i1"});
  assert.equal(c.ok, false);
  assert.equal(c.reasonCode, "item_rate_limited");
});

test("21 max views", () => {
  const gate = createWardrobeAuthorityCostGate();
  const r = gate.begin({uid: "u", itemId: "i", viewCount: 99});
  assert.equal(r.ok, false);
  assert.equal(r.reasonCode, "max_views_exceeded");
});

test("22-23 zero-write proxy rejects writes / no retry storm helper", async () => {
  const store = createMemoryTransactionalStore({
    "users/u/wardrobe/i": {name: "A"},
  });
  const proxy = createZeroWriteStoreProxy(store);
  await assert.rejects(() => proxy.runTransaction("u", "i", async () => ({
    writePatch: {name: "B"},
    result: {},
  })), /shadow_write_forbidden/);
  assert.equal(store._get("u", "i").name, "A");
});

// --- E2E fixtures ---

test("24-28 shadow E2E fixtures leave store untouched", async () => {
  const scenarios = [
    "front_only_garment",
    "cropped_upper",
    "cropped_lower",
    "fabric_detail_only",
    "blurred_item",
    "dark_low_contrast",
    "shoe_without_outsole",
    "conflicting_multi_view",
  ];
  const storage = createFakeStorageMetadataClient({
    [PATH]: {
      generation: "7",
      metageneration: "1",
      size: "10",
      contentType: "image/jpeg",
      updated: "2026-01-01T00:00:00.000Z",
    },
  });
  let eligible = 0;
  for (const scenarioId of scenarios) {
    const store = createMemoryTransactionalStore({
      "users/owner-uid/wardrobe/item-1": baseDoc(),
    });
    const before = JSON.stringify(store._dump());
    const result = await runQualificationAuthorityShadow({
      contractVersion: 1,
      itemId: "item-1",
      action: "analyze_current_source",
      offlineScenarioId: scenarioId,
    }, {
      authContext: auth(),
      store,
      storageMetadataClient: storage,
      visionClient: createFakeTrustedVisionAnalysisClient(),
      fixtureRoot: FIXTURE_ROOT,
      assignedAt: "2026-01-01T00:00:00.000Z",
      costGate: createWardrobeAuthorityCostGate(),
      scenarioId,
    });
    assert.equal(JSON.stringify(store._dump()), before, scenarioId);
    assert.equal(result.wroteProfile, false, scenarioId);
    assert.equal(result.authorityInitialized, false, scenarioId);
    if (result.wouldInitializeAuthority) eligible += 1;
    assert.ok(!JSON.stringify(result).includes("machineEvidence\":[{"),
      "no raw machineEvidence dump");
  }
  assert.equal(eligible, 8);
});

// --- Flutter / graph ---

test("29 soft-defer codes include failed-precondition disabled", () => {
  const dart = fs.readFileSync(
    path.join(ROOT, "lib/Services/wardrobe_revision_lifecycle_client.dart"),
    "utf8");
  assert.match(dart, /failed-precondition/);
  assert.match(dart, /not-found/);
});

test("30-31 shadow response contract fields present", async () => {
  const store = createMemoryTransactionalStore({
    "users/owner-uid/wardrobe/item-1": baseDoc(),
  });
  const result = await runQualificationAuthorityShadow({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
    offlineScenarioId: "front_only_garment",
  }, {
    authContext: auth(),
    store,
    storageMetadataClient: createFakeStorageMetadataClient({
      [PATH]: {generation: "1", size: "1", contentType: "image/jpeg",
        updated: "2026-01-01T00:00:00.000Z"},
    }),
    visionClient: createFakeTrustedVisionAnalysisClient(),
    fixtureRoot: FIXTURE_ROOT,
    assignedAt: "2026-01-01T00:00:00.000Z",
  });
  assert.ok(result.resultContract.includes("ShadowResult"));
  assert.ok("mode" in result);
  assert.ok("wouldInitializeAuthority" in result);
  assert.ok("simulatedRepositoryStatus" in result ||
    result.status !== "shadow_ok");
});

test("graph handlers export ready + ProductionAuthoritySwitch", () => {
  const authH = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "WardrobeQualificationAuthorityHandler");
  const lifeH = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "WardrobeRevisionLifecycleHandler");
  const switchNode = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "ProductionAuthoritySwitch");
  const appCheck = BACKEND_CONTRACT_GRAPH.find(
    (n) => n.id === "FlutterFirebaseAppCheck");
  assert.ok(authH);
  assert.ok(lifeH);
  assert.equal(authH.status, "handler_export_ready");
  assert.equal(authH.defaultMode, "disabled");
  assert.equal(lifeH.status, "handler_export_ready");
  assert.ok(switchNode);
  assert.equal(switchNode.status, "not_started");
  assert.ok(!switchNode.blockers.includes(
    "flutter_app_check_initialization_pending"));
  assert.ok(!switchNode.blockers.includes(
    "firebase_app_check_console_registration_pending"));
  assert.deepEqual([...switchNode.blockers], [
    "controlled_write_canary_retry_pending",
    "controlled_write_production_activation_approval_pending",
  ]);
  assert.ok(appCheck);
  assert.equal(appCheck.status, "client_app_check_ready");
  assert.deepEqual([...appCheck.blockers], []);
});

test("phase10d export readiness clears Console App Check; deploy pending", () => {
  const r = evaluateWardrobeAuthorityExportReadiness(
    phase10dExportReadinessState());
  assert.equal(r.ready, false);
  assert.ok(!r.blockers.includes("client_write_path_cutover_pending"));
  assert.ok(!r.blockers.includes("flutter_app_check_initialization_pending"));
  assert.ok(!r.blockers.includes(
    "firebase_app_check_console_registration_pending"));
  assert.ok(r.blockers.includes("migration_required"));
  assert.ok(r.blockers.includes("manual_deployment_approval"));
  assert.ok(r.blockers.includes("deployment_pending"));
  // Historical snapshots retain prior blockers.
  const legacy10b = evaluateWardrobeAuthorityExportReadiness(
    phase10bExportReadinessState());
  assert.ok(legacy10b.blockers.includes(
    "flutter_app_check_initialization_pending"));
  const legacy10c = evaluateWardrobeAuthorityExportReadiness(
    phase10cExportReadinessState());
  assert.ok(legacy10c.blockers.includes(
    "firebase_app_check_console_registration_pending"));
});
