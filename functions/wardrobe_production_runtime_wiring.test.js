"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  createWardrobeAuthorityProductionDependencies,
} = require("./wardrobe_authority_production_dependencies");
const {
  createQualificationAuthorityHandler,
} = require("./wardrobe_qualification_authority_handler");
const {
  createRevisionLifecycleHandler,
} = require("./wardrobe_revision_lifecycle_handler");
const {
  validateWardrobeAuthorityProductionConfig,
} = require("./wardrobe_authority_production_config");
const {
  resolveAppCheckPolicy,
  APP_CHECK_MODES,
} = require("./wardrobe_authority_app_check_policy");
const {
  assertWardrobeAuthorityExportReady,
  evaluateWardrobeAuthorityExportReadiness,
  phase9bExportReadinessState,
} = require("./wardrobe_authority_export_gate");
const {
  createAdminStorageMetadataClient,
  createFakeAdminStorageMetadataSource,
} = require("./wardrobe_admin_storage_metadata_client");
const {
  createTrustedVisionProductionAnalysisClient,
} = require("./trusted_vision_production_analysis_client");
const {
  createFakeTrustedVisionAnalysisClient,
} = require("./trusted_vision_analysis_client");
const {
  createFakeStorageMetadataClient,
} = require("./trusted_storage_metadata_adapter");
const {
  runBackendQualificationOrchestrationParity,
} = require("./wardrobe_backend_qualification_orchestrator");
const {
  OPERATION_KINDS,
} = require("./wardrobe_revision_lifecycle_mutation_service");
const {
  buildGenerationId,
} = require("./wardrobe_qualification_revision_contract");
const {AUTHORITY_KEY} = require("./wardrobe_profile_firestore_repository");
const {redactValue, safeLogFields} = require("./wardrobe_authority_redaction");
const {
  mapEndpointStatusToHttps,
} = require("./wardrobe_authority_error_mapping");
const {
  RUNTIME_POLICIES,
} = require("./trusted_vision_result_provenance");

const root = path.resolve(__dirname, "..");
const CLOCK = "2026-08-04T11:00:00.000Z";
const PATH = "wardrobe/user-1/item.jpg";
const GEN = "1700000000000000";
const SCENARIO = "front_only_garment";

function validConfig(overrides = {}) {
  return {
    environmentMode: "test",
    projectId: "outfit-of-the-day-test",
    storageBucket: "outfit-of-the-day-test.appspot.com",
    region: "us-east1",
    visionSchemaVersion: 9,
    modelIdentifier: "gpt-4o-mini",
    promptVersion: "vision-v2-schema-9",
    qualificationVersion: "qualification-v1",
    revisionContractVersion: "wardrobe-qualification-revision-context-v1",
    persistenceSchemaVersion: 1,
    appCheckMode: APP_CHECK_MODES.disabledForEmulatorOnly,
    ...overrides,
  };
}

function runtimeAuth(overrides = {}) {
  return {
    auth: {uid: "user-1", token: {sub: "user-1"}},
    tokenVerified: true,
    emulatorVerified: true,
    appCheckPresent: true,
    appCheckVerified: true,
    ...overrides,
  };
}

function authorityDoc() {
  const generationId = buildGenerationId({
    itemId: "item-1",
    imageRevision: 1,
    sourceStoragePath: PATH,
    sourceObjectGeneration: GEN,
    uploadGeneration: GEN,
  });
  return {
    name: "Tank",
    storagePath: PATH,
    [AUTHORITY_KEY]: {
      contractVersion: 1,
      imageRevision: 1,
      wardrobeItemRevision: 1,
      uploadGeneration: GEN,
      generationId,
      sourceStoragePath: PATH,
      sourceObjectGeneration: GEN,
      sourceObjectMetageneration: "1",
      sourceImageSha256: null,
      sourceUpdatedAt: CLOCK,
      assignedAt: CLOCK,
    },
  };
}

function buildFactory(extra = {}) {
  return createWardrobeAuthorityProductionDependencies({
    config: validConfig(extra.config),
    memoryDocs: {
      "users/user-1/wardrobe/item-1": extra.doc || authorityDoc(),
    },
    fakeStorageByPath: {
      [PATH]: {
        generation: GEN,
        metageneration: "1",
        size: "100",
        contentType: "image/jpeg",
        updated: "2026-07-29T10:00:00.000Z",
        md5Hash: "abc=",
      },
    },
    visionClient: createFakeTrustedVisionAnalysisClient(),
    serverClock: () => CLOCK,
    provenancePolicy: RUNTIME_POLICIES.fixtureOnly,
    ...extra,
  });
}

// --- Config ---

test("config valid", () => {
  const cfg = validateWardrobeAuthorityProductionConfig(validConfig());
  assert.equal(cfg.region, "us-east1");
});

test("config accepts explicit firebasestorage.app bucket", () => {
  const bucket = "outfitoftheday-4d401.firebasestorage.app";
  const cfg = validateWardrobeAuthorityProductionConfig(
    validConfig({storageBucket: bucket}));
  assert.equal(cfg.storageBucket, bucket);
});

test("config missing project/bucket", () => {
  assert.throws(() => validateWardrobeAuthorityProductionConfig(
    validConfig({projectId: ""})), /projectId_empty/);
  assert.throws(() => validateWardrobeAuthorityProductionConfig(
    validConfig({storageBucket: undefined})), /storageBucket_empty/);
  assert.throws(() => validateWardrobeAuthorityProductionConfig(
    validConfig({storageBucket: ""})), /storageBucket_empty/);
});

test("config rejects malformed storage bucket", () => {
  assert.throws(() => validateWardrobeAuthorityProductionConfig(
    validConfig({storageBucket: "gs://bucket/path"})),
  /storageBucket_invalid/);
});

test("config unsupported versions", () => {
  assert.throws(() => validateWardrobeAuthorityProductionConfig(
    validConfig({visionSchemaVersion: 8})), /vision_schema_version_mismatch/);
});

test("config placeholder identity forbidden", () => {
  assert.throws(() => validateWardrobeAuthorityProductionConfig(
    validConfig({projectId: "developer-TODO"})),
  /production_config_placeholder_identity_forbidden/);
});

test("config wrong environment forbids silent app check disable in prod", () => {
  assert.throws(() => resolveAppCheckPolicy({
    environmentMode: "production",
    appCheckMode: APP_CHECK_MODES.disabledForEmulatorOnly,
  }), /app_check_disabled_forbidden_in_production/);
});

// --- Factory ---

test("factory lazy construction", () => {
  const factory = buildFactory();
  assert.equal(factory.peekConstructed(), false);
  const deps = factory.get();
  assert.equal(factory.peekConstructed(), true);
  assert.equal(factory.get(), deps);
  assert.ok(Object.isFrozen(deps));
});

test("factory passes exact configured bucket to metadata client", () => {
  const bucket = "outfitoftheday-4d401.firebasestorage.app";
  const factory = createWardrobeAuthorityProductionDependencies({
    config: validConfig({storageBucket: bucket}),
    memoryDocs: {},
    adminStorageGetMetadata: async () => null,
    visionClient: createFakeTrustedVisionAnalysisClient(),
  });
  assert.equal(factory.get().storageMetadataClient.bucketName, bucket);
});

test("factory no credential at import", () => {
  // Requiring this module must not throw / touch credentials.
  assert.equal(typeof createWardrobeAuthorityProductionDependencies, "function");
});

// --- Auth / App Check / Wrapper ---

test("wrapper valid callable auth", async () => {
  const factory = buildFactory();
  const handler = createQualificationAuthorityHandler({
    dependencyFactory: factory,
    defaultScenarioId: SCENARIO,
  });
  const result = await handler.handle({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
    serverClock: () => CLOCK,
  }, runtimeAuth());
  assert.equal(result.ok, true, JSON.stringify(result.error));
  assert.equal(result.result.status, "mutation_applied");
});

test("wrapper unauthenticated", async () => {
  const handler = createQualificationAuthorityHandler({
    dependencyFactory: buildFactory(),
  });
  const result = await handler.handle({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
  }, {});
  assert.equal(result.ok, false);
  assert.equal(result.error.code, "unauthenticated");
});

test("wrapper payload uid spoof", async () => {
  const handler = createQualificationAuthorityHandler({
    dependencyFactory: buildFactory(),
  });
  const result = await handler.handle({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
    uid: "hacker",
  }, runtimeAuth());
  assert.equal(result.ok, false);
  assert.equal(result.error.code, "permission-denied");
});

test("wrapper payload revisions rejected", async () => {
  const handler = createQualificationAuthorityHandler({
    dependencyFactory: buildFactory(),
  });
  const result = await handler.handle({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
    imageRevision: 1,
  }, runtimeAuth());
  assert.equal(result.ok, false);
});

test("wrapper payload token rejected", async () => {
  const handler = createQualificationAuthorityHandler({
    dependencyFactory: buildFactory(),
  });
  const result = await handler.handle({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
  }, {...runtimeAuth(), rawIdToken: "eyJhbGciOi.fake.sig"});
  assert.equal(result.ok, false);
});

test("wrapper client storage bucket rejected", async () => {
  const handler = createQualificationAuthorityHandler({
    dependencyFactory: buildFactory(),
  });
  const result = await handler.handle({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
    storageBucket: "attacker.appspot.com",
  }, runtimeAuth());
  assert.equal(result.ok, false);
  assert.equal(result.error.code, "permission-denied");
});

test("wrapper App Check valid production", async () => {
  const factory = buildFactory({
    config: validConfig({
      environmentMode: "production",
      appCheckMode: APP_CHECK_MODES.required,
    }),
  });
  const handler = createQualificationAuthorityHandler({
    dependencyFactory: factory,
    defaultScenarioId: SCENARIO,
  });
  const result = await handler.handle({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
    serverClock: () => CLOCK,
  }, runtimeAuth());
  assert.equal(result.ok, true, JSON.stringify(result.error));
});

test("wrapper App Check missing production", async () => {
  const factory = buildFactory({
    config: validConfig({
      environmentMode: "production",
      appCheckMode: APP_CHECK_MODES.required,
    }),
  });
  const handler = createQualificationAuthorityHandler({
    dependencyFactory: factory,
  });
  const result = await handler.handle({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
  }, runtimeAuth({appCheckPresent: false, appCheckVerified: false}));
  assert.equal(result.ok, false);
  assert.equal(result.error.code, "permission-denied");
});

test("wrapper emulator App Check policy", () => {
  const policy = resolveAppCheckPolicy({
    environmentMode: "emulator",
    appCheckMode: APP_CHECK_MODES.disabledForEmulatorOnly,
  });
  assert.equal(policy.enforce, false);
});

test("wrapper idempotent result", async () => {
  const factory = buildFactory();
  const handler = createQualificationAuthorityHandler({
    dependencyFactory: factory,
    defaultScenarioId: SCENARIO,
  });
  const req = {
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
    serverClock: () => CLOCK,
  };
  const first = await handler.handle(req, runtimeAuth());
  assert.equal(first.ok, true, JSON.stringify(first.error));
  const second = await handler.handle(req, runtimeAuth());
  assert.ok(["idempotent_noop", "mutation_applied", "revision_conflict"]
    .includes(second.result.status), second.result.reasonCode);
});

test("wrapper internal error redaction / no stack", async () => {
  const mapped = mapEndpointStatusToHttps("repository_failed", "boom");
  assert.equal(mapped.code, "internal");
  const redacted = redactValue({
    uid: "user-1",
    token: "secret",
    stack: "Error\n at foo",
    signedUrl: "https://storage.googleapis.com/x?X-Goog-Signature=1",
  });
  assert.notEqual(redacted.uid, "user-1");
  assert.equal(redacted.token, "[REDACTED]");
  assert.equal(redacted.signedUrl, "[REDACTED]");
  const log = safeLogFields({
    status: "ok",
    reasonCode: "x",
    uid: "should-not-appear",
  });
  assert.equal(log.uid, undefined);
});

test("lifecycle handler metadata edit", async () => {
  const factory = buildFactory();
  const handler = createRevisionLifecycleHandler({
    dependencyFactory: factory,
  });
  const result = await handler.handle({
    contractVersion: 1,
    operationKind: OPERATION_KINDS.applyClassificationMetadataEdit,
    itemId: "item-1",
    assignedAt: CLOCK,
    expectedWardrobeItemRevision: 1,
    patch: {name: "Renamed"},
  }, runtimeAuth());
  assert.equal(result.ok, true, JSON.stringify(result.error));
  assert.equal(result.result.resultingWardrobeItemRevision, 2);
});

// --- Storage live adapter boundary ---

test("storage valid metadata via admin client", async () => {
  const client = createAdminStorageMetadataClient({
    getMetadata: createFakeAdminStorageMetadataSource({
      [PATH]: {
        generation: GEN,
        metageneration: "2",
        size: "10",
        contentType: "image/jpeg",
        updated: "2026-07-29T10:00:00.000Z",
        md5Hash: "x=",
        crc32c: "y=",
      },
    }),
    bucketName: "bucket",
  });
  const meta = await client.getMetadata(PATH);
  assert.equal(meta.generation, GEN);
  assert.equal(meta.md5Hash, "x=");
});

test("storage ignores trusted Admin mediaLink but never exposes it", async () => {
  const client = createAdminStorageMetadataClient({
    getMetadata: async () => ({
      generation: GEN,
      metageneration: "2",
      size: "10",
      contentType: "image/jpeg",
      updated: "2026-07-29T10:00:00.000Z",
      md5Hash: "x=",
      crc32c: "y=",
      mediaLink: "https://storage.googleapis.com/download/storage/v1/b/x/o/y",
    }),
    bucketName: "outfitoftheday-4d401.firebasestorage.app",
  });
  const meta = await client.getMetadata(PATH);
  assert.equal(meta.generation, GEN);
  assert.equal(Object.prototype.hasOwnProperty.call(meta, "mediaLink"), false);
});

test("storage metadata client preserves the exact source path", async () => {
  let observedPath = null;
  const client = createAdminStorageMetadataClient({
    getMetadata: async (storagePath) => {
      observedPath = storagePath;
      return null;
    },
    bucketName: "outfitoftheday-4d401.firebasestorage.app",
  });
  assert.equal(await client.getMetadata(PATH), null);
  assert.equal(observedPath, PATH);
});

test("storage missing / malformed / no signed URL", async () => {
  const client = createAdminStorageMetadataClient({
    getMetadata: createFakeAdminStorageMetadataSource({}),
  });
  assert.equal(await client.getMetadata(PATH), null);
  await assert.rejects(() => createAdminStorageMetadataClient({
    getMetadata: async () => ({
      generation: GEN,
      signedUrl: "https://x",
    }),
  }).getMetadata(PATH), /storage_download_or_signed_url_rejected/);
  for (const forbidden of [
    {downloadURL: "https://client.invalid/download"},
    {downloadToken: "firebase-download-token"},
  ]) {
    await assert.rejects(() => createAdminStorageMetadataClient({
      getMetadata: async () => ({generation: GEN, ...forbidden}),
    }).getMetadata(PATH), /storage_download_or_signed_url_rejected/);
  }
});

// --- Vision adapter ---

test("vision rejects client URL and supports fixture transport", async () => {
  const client = createTrustedVisionProductionAnalysisClient({
    fixtureTransport: async () => {
      const parser = JSON.parse(fs.readFileSync(path.join(root,
        "test/fixtures/backend_qualification/parser",
        `${SCENARIO}.parser.json`), "utf8"));
      return {scenarioId: SCENARIO, parser};
    },
  });
  await assert.rejects(() => client.analyzeCurrentSource({
    itemId: "item-1",
    sourceStoragePath: PATH,
    imageUrl: "https://example.com/x.jpg",
  }), /client_media_rejected/);
  const ok = await client.analyzeCurrentSource({
    itemId: "item-1",
    sourceStoragePath: PATH,
    scenarioId: SCENARIO,
  });
  assert.equal(ok.provenance.liveModel, false);
  assert.equal(client.liveModelCalls, 0);
});

test("vision model/prompt/schema mismatch", async () => {
  const client = createTrustedVisionProductionAnalysisClient({
    readObjectBytes: async () => ({
      buffer: Buffer.from("abc"),
      contentType: "image/jpeg",
    }),
    fetchImpl: async () => ({ok: true, json: async () => ({})}),
    getApiKey: () => "test-key",
  });
  await assert.rejects(() => client.analyzeCurrentSource({
    itemId: "i",
    sourceStoragePath: PATH,
    expectedModel: "gpt-5",
  }), /vision_model_mismatch/);
});

test("vision transport failure", async () => {
  const client = createTrustedVisionProductionAnalysisClient({
    readObjectBytes: async () => ({
      buffer: Buffer.from("abc"),
      contentType: "image/jpeg",
    }),
    fetchImpl: async () => {
      throw new Error("network");
    },
    getApiKey: () => "test-key",
  });
  await assert.rejects(() => client.analyzeCurrentSource({
    itemId: "i",
    sourceStoragePath: PATH,
  }), /vision_transport_failure/);
});

// --- Export gate ---

test("export gate clears rules baseline blocker after 9C-R merge", () => {
  const {
    phase9cRExportReadinessState,
  } = require("./wardrobe_authority_export_gate");
  const readiness = evaluateWardrobeAuthorityExportReadiness(
    phase9cRExportReadinessState());
  assert.equal(readiness.ready, false);
  assert.ok(!readiness.blockers.includes("security_rules_baseline_missing"));
  assert.ok(readiness.blockers.includes("client_write_path_cutover_pending"));
  assert.throws(() => assertWardrobeAuthorityExportReady(
    phase9cRExportReadinessState()), /export_blocked/);
});

test("export gate clears cutover blocker after 10A", () => {
  const {
    phase10aExportReadinessState,
  } = require("./wardrobe_authority_export_gate");
  const readiness = evaluateWardrobeAuthorityExportReadiness(
    phase10aExportReadinessState());
  assert.equal(readiness.ready, false);
  assert.ok(!readiness.blockers.includes("security_rules_baseline_missing"));
  assert.ok(!readiness.blockers.includes("client_write_path_cutover_pending"));
  assert.ok(readiness.blockers.includes("migration_required"));
  assert.ok(readiness.blockers.includes("deployment_pending"));
});

test("legacy phase9b state still reports missing rules baseline", () => {
  const readiness = evaluateWardrobeAuthorityExportReadiness(
    phase9bExportReadinessState());
  assert.equal(readiness.ready, false);
  assert.ok(readiness.blockers.includes("security_rules_baseline_missing"));
});

test("enforceExportGate on handler", async () => {
  const handler = createQualificationAuthorityHandler({
    dependencyFactory: buildFactory(),
    enforceExportGate: true,
  });
  const result = await handler.handle({
    contractVersion: 1,
    itemId: "item-1",
    action: "analyze_current_source",
  }, runtimeAuth());
  assert.equal(result.ok, false);
  assert.equal(result.error.code, "failed-precondition");
});

// --- E2E runtime with production dependency graph + fakes ---

test("runtime E2E 8/8 orchestrator parity preserved", () => {
  const report = runBackendQualificationOrchestrationParity();
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.parityStatus, "orchestration_ready_offline");
});

test("runtime E2E authority through handler for ready scenarios sample", async () => {
  const scenarios = [
    "front_only_garment",
    "cropped_upper",
    "fabric_detail_only",
  ];
  for (const scenarioId of scenarios) {
    const factory = buildFactory();
    const handler = createQualificationAuthorityHandler({
      dependencyFactory: factory,
      defaultScenarioId: scenarioId,
    });
    const result = await handler.handle({
      contractVersion: 1,
      itemId: "item-1",
      action: "analyze_current_source",
      serverClock: () => CLOCK,
    }, runtimeAuth());
    if (scenarioId === "fabric_detail_only") {
      assert.equal(result.ok, false);
      assert.equal(result.result.status, "mapping_failed");
    } else {
      assert.equal(result.ok, true, `${scenarioId}:${JSON.stringify(result.error)}`);
      assert.equal(result.result.status, "mutation_applied");
    }
  }
});

test("production dependencies are wired lazily without handler bypass", () => {
  const index = fs.readFileSync(path.join(root, "functions/index.js"), "utf8");
  for (const needle of [
    "wardrobe_qualification_authority_handler",
    "wardrobe_revision_lifecycle_handler",
    "createQualificationAuthorityHandler",
    "createRevisionLifecycleHandler",
  ]) {
    assert.equal(index.includes(needle), false, needle);
  }
  assert.equal(index.includes("wardrobe_authority_production_dependencies"),
    true);
  assert.match(index, /Disabled mode returns before `\.get\(\)`/);
});
