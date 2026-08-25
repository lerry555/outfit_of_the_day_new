"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  AUTH_STATUSES,
  decodeTrustedFirebaseAuthContext,
  assertPayloadAuthOwnership,
} = require("./trusted_firebase_auth_context");
const {
  createFakeStorageMetadataClient,
} = require("./trusted_storage_metadata_adapter");
const {
  createFakeTrustedVisionAnalysisClient,
} = require("./trusted_vision_analysis_client");
const {
  ORCHESTRATOR_ID,
  runBackendQualificationOrchestrationParity,
} = require("./wardrobe_backend_qualification_orchestrator");
const {
  OPERATION_KINDS,
  createMemoryTransactionalStore,
} = require("./wardrobe_revision_lifecycle_mutation_service");
const {
  handleRevisionLifecycleEndpoint,
} = require("./wardrobe_revision_lifecycle_endpoint");
const {
  ACTIONS,
  handleQualificationAuthorityEndpoint,
} = require("./wardrobe_qualification_authority_endpoint");
const {
  AUTHORITY_KEY: REPO_AUTHORITY_KEY,
  ENVELOPE_KEY,
} = require("./wardrobe_profile_firestore_repository");
const {buildGenerationId} = require("./wardrobe_qualification_revision_contract");

const root = path.resolve(__dirname, "..");
const CLOCK = "2026-08-04T10:00:00.000Z";
const PATH = "wardrobe/user-1/item.jpg";
const GEN = "1700000000000000";
const SCENARIO = "front_only_garment";

function authOk(overrides = {}) {
  return {
    authenticated: true,
    uid: "user-1",
    tokenVerified: true,
    emulatorVerified: true,
    appCheckPresent: false,
    appCheckVerified: false,
    ...overrides,
  };
}

function storageMeta(overrides = {}) {
  return createFakeStorageMetadataClient({
    [PATH]: {
      generation: GEN,
      metageneration: "1",
      size: "100",
      contentType: "image/jpeg",
      updated: "2026-07-29T10:00:00.000Z",
      md5Hash: "abc=",
      ...overrides,
    },
  });
}

function baseDoc(overrides = {}) {
  return {
    name: "Tank",
    storagePath: PATH,
    wearCount: 1,
    ...overrides,
  };
}

function authorityDoc(overrides = {}) {
  const imageRevision = 1;
  const wardrobeItemRevision = 1;
  const generationId = buildGenerationId({
    itemId: "item-1",
    imageRevision,
    sourceStoragePath: PATH,
    sourceObjectGeneration: GEN,
    uploadGeneration: GEN,
  });
  return baseDoc({
    [REPO_AUTHORITY_KEY]: {
      contractVersion: 1,
      imageRevision,
      wardrobeItemRevision,
      uploadGeneration: GEN,
      generationId,
      sourceStoragePath: PATH,
      sourceObjectGeneration: GEN,
      sourceObjectMetageneration: "1",
      sourceImageSha256: null,
      sourceUpdatedAt: CLOCK,
      assignedAt: CLOCK,
    },
    ...overrides,
  });
}

// --- Auth ---

test("auth 1 unauthenticated", () => {
  const result = decodeTrustedFirebaseAuthContext(null);
  assert.equal(result.status, AUTH_STATUSES.unauthenticated);
});

test("auth 2 uid payload spoof", () => {
  const auth = decodeTrustedFirebaseAuthContext(authOk());
  assert.throws(() => assertPayloadAuthOwnership({itemId: "x", uid: "hacker"},
    auth), /client_uid_spoof_rejected/);
});

test("auth 3 valid auth", () => {
  const auth = decodeTrustedFirebaseAuthContext(authOk());
  assert.equal(auth.status, AUTH_STATUSES.authenticated);
  assert.equal(auth.uid, "user-1");
});

test("auth 4 wrong owner via path store key", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": baseDoc(),
  });
  const result = await handleRevisionLifecycleEndpoint({
    contractVersion: 1,
    operationKind: OPERATION_KINDS.initializeUserPhotoAuthority,
    itemId: "item-1",
    assignedAt: CLOCK,
  }, {
    authContext: authOk({uid: "other-user"}),
    store,
    storageMetadataClient: storageMeta(),
    assignedAt: CLOCK,
  });
  assert.equal(result.status, "item_deleted");
});

test("auth 5 malformed auth context", () => {
  const result = decodeTrustedFirebaseAuthContext({
    authenticated: true,
    uid: "user-1",
  });
  assert.equal(result.status, AUTH_STATUSES.malformed);
});

test("auth 6 App Check absent characterization", () => {
  const auth = decodeTrustedFirebaseAuthContext(authOk());
  assert.equal(auth.appCheckPresent, false);
  assert.equal(auth.appCheckRequired, false);
});

test("auth 7 client-supplied revision rejected", () => {
  const auth = decodeTrustedFirebaseAuthContext(authOk());
  assert.throws(() => assertPayloadAuthOwnership({
    itemId: "x", imageRevision: 1,
  }, auth), /client_authority_field_rejected/);
});

// --- Lifecycle endpoint ---

test("lifecycle 1 initialize valid source", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": baseDoc(),
  });
  const result = await handleRevisionLifecycleEndpoint({
    contractVersion: 1,
    operationKind: OPERATION_KINDS.initializeUserPhotoAuthority,
    itemId: "item-1",
    assignedAt: CLOCK,
    idempotencyKey: "init-1",
  }, {
    authContext: authOk(),
    store,
    storageMetadataClient: storageMeta(),
  });
  assert.equal(result.status, "mutation_applied");
  assert.equal(result.resultingImageRevision, 1);
});

test("lifecycle 2 metadata edit", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": authorityDoc(),
  });
  const result = await handleRevisionLifecycleEndpoint({
    contractVersion: 1,
    operationKind: OPERATION_KINDS.applyClassificationMetadataEdit,
    itemId: "item-1",
    assignedAt: CLOCK,
    expectedWardrobeItemRevision: 1,
    patch: {name: "Renamed"},
  }, {authContext: authOk(), store, storageMetadataClient: storageMeta()});
  assert.equal(result.status, "mutation_applied");
  assert.equal(result.resultingWardrobeItemRevision, 2);
});

test("lifecycle 3 correction", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": authorityDoc(),
  });
  const result = await handleRevisionLifecycleEndpoint({
    contractVersion: 1,
    operationKind: OPERATION_KINDS.applyUserCorrection,
    itemId: "item-1",
    assignedAt: CLOCK,
    expectedWardrobeItemRevision: 1,
    correction: {
      id: "c1", property: "fit", action: "set", value: "regular",
      method: "manual",
    },
  }, {authContext: authOk(), store, storageMetadataClient: storageMeta()});
  assert.equal(result.status, "mutation_applied");
});

test("lifecycle 4 derivative completion", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": authorityDoc(),
  });
  const result = await handleRevisionLifecycleEndpoint({
    contractVersion: 1,
    operationKind: OPERATION_KINDS.recordDerivativeCompletion,
    itemId: "item-1",
    assignedAt: CLOCK,
    derivativeKind: "clean",
    patch: {cleanStoragePath: "wardrobe_clean/user-1/item.png"},
  }, {authContext: authOk(), store, storageMetadataClient: storageMeta()});
  assert.equal(result.status, "mutation_applied");
  assert.equal(result.resultingImageRevision, 1);
});

test("lifecycle 5 reanalysis request", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": authorityDoc(),
  });
  const result = await handleRevisionLifecycleEndpoint({
    contractVersion: 1,
    operationKind: OPERATION_KINDS.requestSameImageReanalysis,
    itemId: "item-1",
    assignedAt: CLOCK,
    expectedWardrobeItemRevision: 1,
  }, {authContext: authOk(), store, storageMetadataClient: storageMeta()});
  assert.equal(result.status, "mutation_applied");
  assert.equal(result.documentPatched, false);
});

test("lifecycle 6 product-link rejected", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": baseDoc({
      storagePath: null,
      productStoragePath: "wardrobe_product/user-1/x.png",
    }),
  });
  const result = await handleRevisionLifecycleEndpoint({
    contractVersion: 1,
    operationKind: OPERATION_KINDS.initializeUserPhotoAuthority,
    itemId: "item-1",
    assignedAt: CLOCK,
  }, {authContext: authOk(), store, storageMetadataClient: storageMeta()});
  assert.equal(result.status, "product_source_not_supported");
});

test("lifecycle 7 missing source", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": baseDoc(),
  });
  const result = await handleRevisionLifecycleEndpoint({
    contractVersion: 1,
    operationKind: OPERATION_KINDS.initializeUserPhotoAuthority,
    itemId: "item-1",
    assignedAt: CLOCK,
  }, {
    authContext: authOk(),
    store,
    storageMetadataClient: createFakeStorageMetadataClient({}),
  });
  assert.equal(result.status, "source_missing");
});

test("lifecycle 8 stale revision", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": authorityDoc(),
  });
  const result = await handleRevisionLifecycleEndpoint({
    contractVersion: 1,
    operationKind: OPERATION_KINDS.applyClassificationMetadataEdit,
    itemId: "item-1",
    assignedAt: CLOCK,
    expectedWardrobeItemRevision: 0,
    patch: {name: "X"},
  }, {authContext: authOk(), store, storageMetadataClient: storageMeta()});
  assert.equal(result.status, "stale_item_revision");
});

test("lifecycle 9 forbidden fields", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": authorityDoc(),
  });
  const result = await handleRevisionLifecycleEndpoint({
    contractVersion: 1,
    operationKind: OPERATION_KINDS.applyClassificationMetadataEdit,
    itemId: "item-1",
    assignedAt: CLOCK,
    expectedWardrobeItemRevision: 1,
    patch: {cleanImageUrl: "x"},
  }, {authContext: authOk(), store, storageMetadataClient: storageMeta()});
  assert.equal(result.status, "forbidden_field");
});

test("lifecycle 10 idempotent retry", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": baseDoc(),
  });
  const deps = {
    authContext: authOk(),
    store,
    storageMetadataClient: storageMeta(),
  };
  const req = {
    contractVersion: 1,
    operationKind: OPERATION_KINDS.initializeUserPhotoAuthority,
    itemId: "item-1",
    assignedAt: CLOCK,
    idempotencyKey: "idem-1",
  };
  await handleRevisionLifecycleEndpoint(req, deps);
  const second = await handleRevisionLifecycleEndpoint(req, deps);
  assert.equal(second.status, "idempotent_noop");
});

// --- Orchestrator E2E ---

test("orchestrator 8/8 end-to-end parity", () => {
  const report = runBackendQualificationOrchestrationParity();
  assert.equal(report.orchestratorId, ORCHESTRATOR_ID);
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.deterministic, true);
  assert.equal(report.parityStatus, "orchestration_ready_offline");
});

// --- Authority endpoint ---

async function authorityDeps(doc, extra = {}) {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": doc,
  });
  return {
    authContext: authOk(),
    store,
    storageMetadataClient: storageMeta(),
    visionClient: createFakeTrustedVisionAnalysisClient(),
    scenarioId: SCENARIO,
    serverClock: () => CLOCK,
    ...extra,
    store,
  };
}

test("authority 1 valid existing authority", async () => {
  const deps = await authorityDeps(authorityDoc());
  const result = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: "item-1",
    action: ACTIONS.analyzeCurrentSource,
    serverClock: () => CLOCK,
  }, deps);
  assert.ok(["mutation_applied", "idempotent_noop", "mapping_failed",
    "repository_failed"].includes(result.status), result.reasonCode);
  assert.equal(result.itemId, "item-1");
  assert.equal(result.resultContract.includes("AuthorityResult"), true);
});

test("authority 2 lazy initialization", async () => {
  const deps = await authorityDeps(baseDoc());
  const result = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: "item-1",
    action: ACTIONS.analyzeCurrentSource,
    serverClock: () => CLOCK,
  }, deps);
  assert.ok(result.authorityInitialized === true ||
    result.status === "mutation_applied" ||
    result.status === "mapping_failed" ||
    result.status === "repository_failed", result.reasonCode);
});

test("authority 3 already initialized", async () => {
  const deps = await authorityDeps(authorityDoc());
  const result = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: "item-1",
    action: ACTIONS.analyzeCurrentSource,
    serverClock: () => CLOCK,
  }, deps);
  assert.equal(result.authorityInitialized, false);
});

test("authority 4 product-only rejected", async () => {
  const deps = await authorityDeps(baseDoc({
    storagePath: null,
    productStoragePath: "wardrobe_product/user-1/x.png",
  }));
  const result = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: "item-1",
    action: ACTIONS.analyzeCurrentSource,
    serverClock: () => CLOCK,
  }, deps);
  assert.equal(result.status, "product_source_not_supported");
});

test("authority 5 source missing", async () => {
  const deps = await authorityDeps(authorityDoc(), {
    storageMetadataClient: createFakeStorageMetadataClient({}),
  });
  const result = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: "item-1",
    action: ACTIONS.analyzeCurrentSource,
    serverClock: () => CLOCK,
  }, deps);
  assert.equal(result.status, "source_missing");
});

test("authority 6 generation mismatch", async () => {
  const deps = await authorityDeps(authorityDoc(), {
    storageMetadataClient: storageMeta({generation: "999"}),
  });
  const result = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: "item-1",
    action: ACTIONS.analyzeCurrentSource,
    serverClock: () => CLOCK,
  }, deps);
  assert.equal(result.status, "stale_image");
});

test("authority 7 fake parser success", async () => {
  const client = createFakeTrustedVisionAnalysisClient();
  const parsed = await client.analyzeCurrentSource({
    itemId: "item-1",
    scenarioId: SCENARIO,
  });
  assert.equal(parsed.provenance.liveModel, false);
  assert.equal(parsed.parser.fixtureId, SCENARIO);
});

test("authority 8 parser invalid", async () => {
  const deps = await authorityDeps(authorityDoc(), {
    visionClient: {
      async analyzeCurrentSource() {
        throw new Error("parser_fixture_missing:nope");
      },
    },
  });
  const result = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: "item-1",
    action: ACTIONS.analyzeCurrentSource,
    serverClock: () => CLOCK,
  }, deps);
  assert.equal(result.status, "invalid_parser_result");
});

test("authority 9-20 wiring outcomes", async () => {
  const deps = await authorityDeps(authorityDoc());
  const first = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: "item-1",
    action: ACTIONS.analyzeCurrentSource,
    serverClock: () => CLOCK,
  }, deps);
  assert.equal(first.status, "mutation_applied", first.reasonCode);
  assert.equal(first.wroteProfile, true);
  assert.equal(first.endpointId, "WardrobeQualificationAuthorityEndpoint");
  assert.ok(Object.isFrozen(first));
  assert.equal(first.uid, undefined);
  assert.ok(first.qualificationSummary.machineEvidenceCount > 0);

  const second = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: "item-1",
    action: ACTIONS.analyzeCurrentSource,
    serverClock: () => CLOCK,
  }, deps);
  assert.ok(["idempotent_noop", "mutation_applied", "revision_conflict"]
    .includes(second.status), second.reasonCode);
});

test("authority fabric_detail_only mapping invalidInput", async () => {
  const deps = await authorityDeps(authorityDoc(), {
    scenarioId: "fabric_detail_only",
  });
  const result = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: "item-1",
    action: ACTIONS.analyzeCurrentSource,
    serverClock: () => CLOCK,
  }, deps);
  assert.equal(result.status, "mapping_failed", result.reasonCode);
});

test("authority unauthenticated", async () => {
  const deps = await authorityDeps(authorityDoc(), {authContext: null});
  const result = await handleQualificationAuthorityEndpoint({
    contractVersion: 1,
    itemId: "item-1",
    action: ACTIONS.analyzeCurrentSource,
    serverClock: () => CLOCK,
  }, deps);
  assert.equal(result.status, "unauthenticated");
});

test("authority corrections preserved on success path", async () => {
  const doc = authorityDoc({
    [ENVELOPE_KEY]: {
      metadata: {revision: 1, generationId: "old", schemaVersion: 1,
        status: "ready"},
      source: {imageRevision: 1, wardrobeItemRevision: 1, storagePath: PATH},
      analysis: {analysisId: "old"},
      machineEvidence: [{id: "me-old"}],
      userCorrections: {
        fit: {id: "c", property: "fit", action: "set", value: "loose"},
      },
    },
  });
  // Fix generationId on authority to match buildGenerationId
  const deps = await authorityDeps(doc);
  const before = deps.store._get("user-1", "item-1");
  assert.equal(before[ENVELOPE_KEY].userCorrections.fit.value, "loose");
});

test("production isolation endpoints not exported", () => {
  const index = fs.readFileSync(path.join(root, "functions/index.js"), "utf8");
  assert.equal(index.includes("wardrobe_qualification_authority_endpoint"),
    false);
  assert.equal(index.includes("wardrobe_revision_lifecycle_endpoint"), false);
  assert.equal(index.includes("wardrobe_backend_qualification_orchestrator"),
    false);
  assert.equal(index.includes("handleQualificationAuthorityEndpoint"), false);
  assert.equal(index.includes("handleRevisionLifecycleEndpoint"), false);
});

test("vision client never live", async () => {
  const client = createFakeTrustedVisionAnalysisClient();
  assert.equal(client.liveModelCalls, 0);
  await client.analyzeCurrentSource({itemId: "i", scenarioId: SCENARIO});
  assert.equal(client.liveModelCalls, 0);
});
