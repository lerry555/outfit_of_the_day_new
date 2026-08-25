"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  buildGenerationId,
} = require("./wardrobe_qualification_revision_contract");
const {
  createFakeStorageMetadataClient,
} = require("./trusted_storage_metadata_adapter");
const {
  AUTHORITY_KEY,
  CLASSIFICATION_ALLOW_LIST,
  ENVELOPE_KEY,
  LAZY_MIGRATION_CLASSES,
  MAX_REVISION,
  MUTATION_STATUS,
  OPERATION_KINDS,
  REQUEST_CONTRACT,
  RESULT_CONTRACT,
  SERVICE_ID,
  SERVICE_VERSION,
  applyRevisionLifecycleMutation,
  classifyLazyMigrationCandidate,
  createMemoryTransactionalStore,
} = require("./wardrobe_revision_lifecycle_mutation_service");

const root = path.resolve(__dirname, "..");
const CLOCK = "2026-08-04T09:00:00.000Z";
const PATH = "wardrobe/user-1/item.jpg";
const GEN = "1700000000000000";

function snapshot(overrides = {}) {
  return {
    contractVersion: 1,
    backendVerified: true,
    exists: true,
    sourceStoragePath: PATH,
    generation: GEN,
    metageneration: "1",
    sha256: null,
    md5Hash: "abc=",
    crc32c: null,
    sizeBytes: 100,
    contentType: "image/jpeg",
    updatedAt: "2026-07-29T10:00:00.000Z",
    ...overrides,
  };
}

function authority(overrides = {}) {
  const imageRevision = overrides.imageRevision ?? 1;
  const wardrobeItemRevision = overrides.wardrobeItemRevision ?? 1;
  const sourceStoragePath = overrides.sourceStoragePath ?? PATH;
  const uploadGeneration = overrides.uploadGeneration ?? GEN;
  const generationId = overrides.generationId ?? buildGenerationId({
    itemId: "item-1",
    imageRevision,
    sourceStoragePath,
    sourceObjectGeneration: uploadGeneration,
    uploadGeneration,
  });
  return {
    contractVersion: 1,
    imageRevision,
    wardrobeItemRevision,
    uploadGeneration,
    generationId,
    sourceStoragePath,
    sourceObjectGeneration: uploadGeneration,
    sourceObjectMetageneration: "1",
    sourceImageSha256: null,
    sourceUpdatedAt: CLOCK,
    assignedAt: CLOCK,
    ...overrides,
    generationId,
  };
}

function baseDoc(overrides = {}) {
  return {
    name: "Hoodie",
    storagePath: PATH,
    wearCount: 2,
    ...overrides,
  };
}

function request(kind, overrides = {}) {
  return {
    contractVersion: 1,
    operationKind: kind,
    itemId: "item-1",
    assignedAt: CLOCK,
    trustedActorContext: {uid: "user-1", authType: "backend_admin"},
    ...overrides,
  };
}

function fakeClient(meta = {}) {
  return createFakeStorageMetadataClient({
    [PATH]: {
      generation: GEN,
      metageneration: "1",
      size: "100",
      contentType: "image/jpeg",
      updated: "2026-07-29T10:00:00.000Z",
      md5Hash: "abc=",
      ...meta,
    },
  });
}

async function run(doc, req, depsExtra = {}) {
  const store = createMemoryTransactionalStore(
    doc == null ? {} : {"users/user-1/wardrobe/item-1": doc},
  );
  const result = await applyRevisionLifecycleMutation(req, {
    store,
    storageMetadataClient: fakeClient(),
    assignedAt: CLOCK,
    ...depsExtra,
  });
  return {result, store, doc: store._get("user-1", "item-1")};
}

test("service constants", () => {
  assert.equal(SERVICE_ID, "WardrobeRevisionLifecycleMutationService");
  assert.equal(SERVICE_VERSION,
    "wardrobe-revision-lifecycle-mutation-service-v1");
  assert.equal(REQUEST_CONTRACT,
    "WardrobeRevisionLifecycleMutationRequest/v1");
  assert.equal(RESULT_CONTRACT,
    "WardrobeRevisionLifecycleMutationResult/v1");
  assert.ok(CLASSIFICATION_ALLOW_LIST.includes("canonicalType"));
  assert.equal(CLASSIFICATION_ALLOW_LIST.includes("canonical_type"), false);
  assert.equal(CLASSIFICATION_ALLOW_LIST.includes("categoryKey"), false);
});

// --- Initialization ---

test("1 valid user-photo initialization", async () => {
  const {result, doc} = await run(baseDoc(), request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
    {idempotencyKey: "init-1"},
  ));
  assert.equal(result.status, MUTATION_STATUS.mutationApplied);
  assert.equal(result.resultingImageRevision, 1);
  assert.equal(result.resultingWardrobeItemRevision, 1);
  assert.equal(result.authorityInitialized, true);
  assert.equal(result.documentPatched, true);
  assert.equal(doc[AUTHORITY_KEY].uploadGeneration, GEN);
  assert.equal(doc[AUTHORITY_KEY].contractVersion, 1);
  assert.equal(doc.wearCount, 2);
  assert.match(result.generationId, /^wqrev:v1:/);
});

test("2 already initialized", async () => {
  const {result} = await run(baseDoc({[AUTHORITY_KEY]: authority()}), request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
  ));
  assert.equal(result.status, MUTATION_STATUS.authorityAlreadyInitialized);
  assert.equal(result.documentPatched, false);
});

test("3 missing item", async () => {
  const {result} = await run(null, request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
  ));
  assert.equal(result.status, MUTATION_STATUS.itemDeleted);
});

test("4 missing storagePath", async () => {
  const {result} = await run(baseDoc({storagePath: null}), request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
  ));
  assert.equal(result.status, MUTATION_STATUS.missingStoragePath);
});

test("5 product-only source", async () => {
  const {result} = await run(baseDoc({
    storagePath: null,
    productStoragePath: "wardrobe_product/user-1/x.png",
  }), request(OPERATION_KINDS.initializeUserPhotoAuthority));
  assert.equal(result.status, MUTATION_STATUS.productSourceNotSupported);
});

test("6 source missing", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": baseDoc(),
  });
  const result = await applyRevisionLifecycleMutation(
    request(OPERATION_KINDS.initializeUserPhotoAuthority),
    {
      store,
      storageMetadataClient: createFakeStorageMetadataClient({}),
      assignedAt: CLOCK,
    },
  );
  assert.equal(result.status, MUTATION_STATUS.sourceMissing);
});

test("7 generation mismatch", async () => {
  const {result} = await run(baseDoc(), request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
    {expectedUploadGeneration: "999"},
  ));
  assert.equal(result.status, MUTATION_STATUS.sourceMismatch);
  assert.equal(result.reasonCode, "generation_mismatch");
});

test("8 path mismatch", async () => {
  const {result} = await run(baseDoc(), request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
    {
      sourceObjectSnapshot: snapshot({
        sourceStoragePath: "wardrobe/user-1/other.jpg",
      }),
    },
  ));
  assert.equal(result.status, MUTATION_STATUS.sourceMismatch);
  assert.equal(result.reasonCode, "path_mismatch");
});

test("9 malformed current authority", async () => {
  const {result} = await run(baseDoc({
    [AUTHORITY_KEY]: {contractVersion: 1, imageRevision: "x"},
  }), request(OPERATION_KINDS.initializeUserPhotoAuthority));
  assert.equal(result.status, MUTATION_STATUS.mutationConflict);
});

test("10 idempotent retry", async () => {
  const first = await run(baseDoc(), request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
    {idempotencyKey: "init-retry"},
  ));
  const second = await run(first.doc, request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
    {idempotencyKey: "init-retry"},
  ));
  assert.equal(second.result.status, MUTATION_STATUS.idempotentNoop);
  assert.equal(second.result.idempotent, true);
});

// --- Metadata edit ---

test("11 valid classification edit", async () => {
  const {result, doc} = await run(baseDoc({
    [AUTHORITY_KEY]: authority(),
    [ENVELOPE_KEY]: {
      metadata: {revision: 1},
      machineEvidence: [{id: "m1"}],
      userCorrections: {canonicalType: {id: "c1", property: "canonicalType",
        action: "set", value: "hoodie"}},
    },
  }), request(OPERATION_KINDS.applyClassificationMetadataEdit, {
    expectedWardrobeItemRevision: 1,
    patch: {canonicalType: "hoodie", bodySlots: ["upper_body"]},
    idempotencyKey: "edit-1",
  }));
  assert.equal(result.status, MUTATION_STATUS.mutationApplied);
  assert.equal(doc.canonicalType, "hoodie");
  assert.deepEqual(doc.bodySlots, ["upper_body"]);
  assert.equal(doc[ENVELOPE_KEY].userCorrections.canonicalType.value, "hoodie");
  assert.equal(doc[ENVELOPE_KEY].machineEvidence[0].id, "m1");
});

test("12 forbidden field", async () => {
  const {result} = await run(baseDoc({[AUTHORITY_KEY]: authority()}), request(
    OPERATION_KINDS.applyClassificationMetadataEdit, {
      expectedWardrobeItemRevision: 1,
      patch: {cleanImageUrl: "https://x"},
    },
  ));
  assert.equal(result.status, MUTATION_STATUS.forbiddenField);
});

test("13 unrelated field", async () => {
  const {result} = await run(baseDoc({[AUTHORITY_KEY]: authority()}), request(
    OPERATION_KINDS.applyClassificationMetadataEdit, {
      expectedWardrobeItemRevision: 1,
      patch: {displayOnlyFlag: true},
    },
  ));
  assert.equal(result.status, MUTATION_STATUS.invalidPatch);
  assert.match(result.reasonCode, /unrelated_field/);
});

test("14 stale expected revision", async () => {
  const {result} = await run(baseDoc({[AUTHORITY_KEY]: authority()}), request(
    OPERATION_KINDS.applyClassificationMetadataEdit, {
      expectedWardrobeItemRevision: 0,
      patch: {name: "X"},
    },
  ));
  assert.equal(result.status, MUTATION_STATUS.staleItemRevision);
  assert.equal(result.retryable, true);
});

test("15 image revision unchanged", async () => {
  const {result} = await run(baseDoc({[AUTHORITY_KEY]: authority()}), request(
    OPERATION_KINDS.applyClassificationMetadataEdit, {
      expectedWardrobeItemRevision: 1,
      patch: {name: "X"},
    },
  ));
  assert.equal(result.previousImageRevision, 1);
  assert.equal(result.resultingImageRevision, 1);
});

test("16 item revision incremented", async () => {
  const {result, doc} = await run(baseDoc({[AUTHORITY_KEY]: authority()}),
    request(OPERATION_KINDS.applyClassificationMetadataEdit, {
      expectedWardrobeItemRevision: 1,
      patch: {name: "X"},
    }));
  assert.equal(result.previousWardrobeItemRevision, 1);
  assert.equal(result.resultingWardrobeItemRevision, 2);
  assert.equal(doc[AUTHORITY_KEY].wardrobeItemRevision, 2);
  assert.equal(doc[AUTHORITY_KEY].imageRevision, 1);
});

test("17 user corrections preserved", async () => {
  const {doc} = await run(baseDoc({
    [AUTHORITY_KEY]: authority(),
    [ENVELOPE_KEY]: {
      metadata: {revision: 3},
      machineEvidence: [],
      userCorrections: {fit: {id: "c", property: "fit", action: "set",
        value: "regular"}},
    },
  }), request(OPERATION_KINDS.applyClassificationMetadataEdit, {
    expectedWardrobeItemRevision: 1,
    patch: {brand: "Acme"},
  }));
  assert.equal(doc[ENVELOPE_KEY].userCorrections.fit.value, "regular");
  assert.equal(doc[ENVELOPE_KEY].metadata.revision, 3);
});

// --- User correction ---

test("18 valid correction", async () => {
  const {result, doc} = await run(baseDoc({
    [AUTHORITY_KEY]: authority(),
    [ENVELOPE_KEY]: {
      metadata: {revision: 2, generationId: "g"},
      machineEvidence: [{id: "me1", property: "canonicalType"}],
      userCorrections: {},
      source: {imageRevision: 1, wardrobeItemRevision: 1},
      analysis: {analysisId: "a1"},
    },
  }), request(OPERATION_KINDS.applyUserCorrection, {
    expectedWardrobeItemRevision: 1,
    correction: {
      id: "corr-1",
      property: "canonicalType",
      action: "set",
      value: "hoodie",
      method: "manual",
    },
    idempotencyKey: "corr-key",
  }));
  assert.equal(result.status, MUTATION_STATUS.mutationApplied);
  assert.equal(doc[ENVELOPE_KEY].userCorrections.canonicalType.value, "hoodie");
  assert.equal(doc[ENVELOPE_KEY].machineEvidence[0].id, "me1");
});

test("19 forbidden machineEvidence change", async () => {
  const {result} = await run(baseDoc({[AUTHORITY_KEY]: authority()}), request(
    OPERATION_KINDS.applyUserCorrection, {
      expectedWardrobeItemRevision: 1,
      correction: {
        id: "c", property: "canonicalType", action: "set", value: "x",
        method: "manual",
      },
      forgedMachineEvidence: true,
    },
  ));
  assert.equal(result.status, MUTATION_STATUS.forbiddenField);
});

test("19b forbidden machineEvidence on correction payload", async () => {
  const {result} = await run(baseDoc({
    [AUTHORITY_KEY]: authority(),
    [ENVELOPE_KEY]: {metadata: {}, machineEvidence: [], userCorrections: {}},
  }), request(OPERATION_KINDS.applyUserCorrection, {
    expectedWardrobeItemRevision: 1,
    correction: {
      id: "c", property: "canonicalType", action: "set", value: "x",
      method: "manual", machineEvidence: [],
    },
  }));
  assert.equal(result.status, MUTATION_STATUS.forbiddenField);
});

test("20 revision increment on correction", async () => {
  const {result} = await run(baseDoc({[AUTHORITY_KEY]: authority()}), request(
    OPERATION_KINDS.applyUserCorrection, {
      expectedWardrobeItemRevision: 1,
      correction: {
        id: "c", property: "styles", action: "set", value: ["casual"],
        method: "manual",
      },
    },
  ));
  assert.equal(result.resultingWardrobeItemRevision, 2);
  assert.equal(result.resultingImageRevision, 1);
});

test("21 machine profile preserved", async () => {
  const {doc} = await run(baseDoc({
    [AUTHORITY_KEY]: authority(),
    [ENVELOPE_KEY]: {
      metadata: {revision: 5},
      machineEvidence: [{id: "keep"}],
      analysis: {analysisId: "keep-a"},
      userCorrections: {},
      source: {},
    },
  }), request(OPERATION_KINDS.applyUserCorrection, {
    expectedWardrobeItemRevision: 1,
    correction: {
      id: "c", property: "fit", action: "set", value: "loose", method: "m",
    },
  }));
  assert.equal(doc[ENVELOPE_KEY].machineEvidence[0].id, "keep");
  assert.equal(doc[ENVELOPE_KEY].analysis.analysisId, "keep-a");
  assert.equal(doc[ENVELOPE_KEY].metadata.revision, 5);
});

test("22 duplicate correction retry", async () => {
  const first = await run(baseDoc({[AUTHORITY_KEY]: authority()}), request(
    OPERATION_KINDS.applyUserCorrection, {
      expectedWardrobeItemRevision: 1,
      idempotencyKey: "dup-corr",
      correction: {
        id: "c", property: "fit", action: "set", value: "slim", method: "m",
      },
    },
  ));
  const second = await run(first.doc, request(
    OPERATION_KINDS.applyUserCorrection, {
      expectedWardrobeItemRevision: 2,
      idempotencyKey: "dup-corr",
      correction: {
        id: "c", property: "fit", action: "set", value: "slim", method: "m",
      },
    },
  ));
  assert.equal(second.result.status, MUTATION_STATUS.idempotentNoop);
});

// --- Derivative ---

test("23 clean derivative completion", async () => {
  const {result, doc} = await run(baseDoc({[AUTHORITY_KEY]: authority()}),
    request(OPERATION_KINDS.recordDerivativeCompletion, {
      derivativeKind: "clean",
      patch: {
        cleanStoragePath: "wardrobe_clean/user-1/item.png",
        cleanImageUrl: "gs://bucket/wardrobe_clean/user-1/item.png",
        isClean: true,
      },
    }));
  assert.equal(result.status, MUTATION_STATUS.mutationApplied);
  assert.equal(result.resultingImageRevision, 1);
  assert.equal(result.resultingWardrobeItemRevision, 1);
  assert.equal(doc.cleanStoragePath, "wardrobe_clean/user-1/item.png");
  assert.equal(doc.processing.cutout, "done");
});

test("24 product derivative completion", async () => {
  const {result, doc} = await run(baseDoc({[AUTHORITY_KEY]: authority()}),
    request(OPERATION_KINDS.recordDerivativeCompletion, {
      derivativeKind: "product",
      patch: {
        productStoragePath: "wardrobe_product/user-1/item.png",
        productImageUrl: "gs://bucket/wardrobe_product/user-1/item.png",
      },
    }));
  assert.equal(result.status, MUTATION_STATUS.mutationApplied);
  assert.equal(doc.processing.product, "done");
});

test("25 invalid namespace", async () => {
  const {result} = await run(baseDoc({[AUTHORITY_KEY]: authority()}), request(
    OPERATION_KINDS.recordDerivativeCompletion, {
      derivativeKind: "clean",
      patch: {cleanStoragePath: "wardrobe/user-1/item.jpg"},
    },
  ));
  assert.equal(result.status, MUTATION_STATUS.invalidPatch);
  assert.equal(result.reasonCode, "invalid_derivative_namespace");
});

test("26 source image mutation rejected", async () => {
  const {result} = await run(baseDoc({[AUTHORITY_KEY]: authority()}), request(
    OPERATION_KINDS.recordDerivativeCompletion, {
      derivativeKind: "clean",
      patch: {
        cleanStoragePath: "wardrobe_clean/user-1/item.png",
        storagePath: "wardrobe/user-1/hacked.jpg",
      },
    },
  ));
  assert.equal(result.status, MUTATION_STATUS.forbiddenField);
});

test("27 derivative revisions unchanged", async () => {
  const {result} = await run(baseDoc({
    [AUTHORITY_KEY]: authority({wardrobeItemRevision: 4}),
  }), request(OPERATION_KINDS.recordDerivativeCompletion, {
    derivativeKind: "product",
    patch: {productStoragePath: "wardrobe_product/user-1/p.png"},
  }));
  assert.equal(result.previousWardrobeItemRevision, 4);
  assert.equal(result.resultingWardrobeItemRevision, 4);
  assert.equal(result.resultingImageRevision, 1);
});

// --- Re-analysis ---

test("28 same-image context", async () => {
  const {result} = await run(baseDoc({
    [AUTHORITY_KEY]: authority(),
    [ENVELOPE_KEY]: {metadata: {revision: 7}},
  }), request(OPERATION_KINDS.requestSameImageReanalysis, {
    expectedImageRevision: 1,
    expectedWardrobeItemRevision: 1,
    expectedUploadGeneration: GEN,
  }));
  assert.equal(result.status, MUTATION_STATUS.mutationApplied);
  assert.equal(result.documentPatched, false);
  assert.equal(result.reanalysisContext.expectedProfileRevision, 7);
  assert.equal(result.reanalysisContext.generationId,
    authority().generationId);
});

test("29 missing authority", async () => {
  const {result} = await run(baseDoc(), request(
    OPERATION_KINDS.requestSameImageReanalysis,
  ));
  assert.equal(result.status, MUTATION_STATUS.authorityMissing);
});

test("30 stale source snapshot", async () => {
  const {result} = await run(baseDoc({[AUTHORITY_KEY]: authority()}), request(
    OPERATION_KINDS.requestSameImageReanalysis, {
      expectedUploadGeneration: "1",
    },
  ));
  assert.equal(result.status, MUTATION_STATUS.sourceMismatch);
  assert.equal(result.reasonCode, "stale_source_snapshot");
});

test("31 reanalysis revisions unchanged", async () => {
  const {result, doc} = await run(baseDoc({
    [AUTHORITY_KEY]: authority({wardrobeItemRevision: 3}),
  }), request(OPERATION_KINDS.requestSameImageReanalysis, {
    expectedWardrobeItemRevision: 3,
  }));
  assert.equal(result.resultingWardrobeItemRevision, 3);
  assert.equal(result.resultingImageRevision, 1);
  assert.equal(doc[AUTHORITY_KEY].wardrobeItemRevision, 3);
});

// --- General ---

test("32 invalid contract", async () => {
  const {result} = await run(baseDoc(), {
    contractVersion: 99,
    operationKind: OPERATION_KINDS.initializeUserPhotoAuthority,
    itemId: "item-1",
    trustedActorContext: {uid: "user-1"},
  });
  assert.equal(result.status, MUTATION_STATUS.invalidContract);
});

test("33 unknown operation", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": baseDoc(),
  });
  // Bypass decode enum by forging after decode would fail — decode rejects.
  const result = await applyRevisionLifecycleMutation({
    contractVersion: 1,
    operationKind: "explode_item",
    itemId: "item-1",
    assignedAt: CLOCK,
    trustedActorContext: {uid: "user-1", authType: "backend_admin"},
  }, {store, storageMetadataClient: fakeClient()});
  assert.equal(result.status, MUTATION_STATUS.invalidContract);
  assert.match(result.reasonCode, /unknown_operation/);
});

test("34 immutable input/output", async () => {
  const {result} = await run(baseDoc(), request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
  ));
  assert.ok(Object.isFrozen(result));
  assert.throws(() => {
    result.status = "x";
  });
});

test("35 deterministic result", async () => {
  const a = await run(baseDoc(), request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
    {idempotencyKey: "det"},
  ));
  const b = await run(baseDoc(), request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
    {idempotencyKey: "det"},
  ));
  assert.equal(
    crypto.createHash("sha256").update(canonicalBytes(a.result)).digest("hex"),
    crypto.createHash("sha256").update(canonicalBytes(b.result)).digest("hex"),
  );
});

test("36 no DateTime.now/random authority", () => {
  const text = fs.readFileSync(path.join(root,
    "functions/wardrobe_revision_lifecycle_mutation_service.js"), "utf8");
  assert.equal(text.includes("Date.now"), false);
  assert.equal(text.includes("DateTime.now"), false);
  assert.equal(text.includes("Math.random"), false);
  assert.equal(text.includes("crypto.randomUUID"), false);
});

test("37 concurrent mutation conflict", async () => {
  const {result} = await run(baseDoc({
    [AUTHORITY_KEY]: authority({wardrobeItemRevision: 5}),
  }), request(OPERATION_KINDS.applyClassificationMetadataEdit, {
    expectedWardrobeItemRevision: 1,
    patch: {name: "race"},
  }));
  assert.equal(result.status, MUTATION_STATUS.staleItemRevision);
});

test("38 revision overflow", async () => {
  const {result} = await run(baseDoc({
    [AUTHORITY_KEY]: authority({wardrobeItemRevision: MAX_REVISION}),
  }), request(OPERATION_KINDS.applyClassificationMetadataEdit, {
    expectedWardrobeItemRevision: MAX_REVISION,
    patch: {name: "overflow"},
  }));
  assert.equal(result.status, MUTATION_STATUS.revisionOverflow);
});

test("39 forged client revisions rejected", async () => {
  const {result} = await run(baseDoc(), request(
    OPERATION_KINDS.initializeUserPhotoAuthority,
    {imageRevision: 1},
  ));
  assert.equal(result.status, MUTATION_STATUS.invalidContract);
  assert.match(result.reasonCode, /forged_client_revisions_rejected/);
});

test("40 lazy migration reuses initialization path", async () => {
  const candidate = classifyLazyMigrationCandidate(baseDoc(), true);
  assert.equal(candidate.class, LAZY_MIGRATION_CLASSES.eligibleUserSource);
  assert.equal(candidate.operationKind,
    OPERATION_KINDS.initializeUserPhotoAuthority);
  const {result} = await run(baseDoc(), request(candidate.operationKind));
  assert.equal(result.status, MUTATION_STATUS.mutationApplied);
  assert.equal(result.authorityInitialized, true);
});

test("production isolation", () => {
  const production = [
    "functions/index.js",
    "functions/vision_v2_shadow.js",
    "functions/wardrobe_profile_firestore_repository.js",
    "functions/qualified_vision_persistence_mapper.js",
  ].map((item) => fs.readFileSync(path.join(root, item), "utf8")).join("\n");
  assert.equal(
    production.includes("wardrobe_revision_lifecycle_mutation_service"),
    false,
  );
  assert.equal(
    production.includes("applyRevisionLifecycleMutation"),
    false,
  );
});

test("unrelated UX fields preserved on initialize", async () => {
  const {doc} = await run(baseDoc({
    name: "KeepMe",
    brand: "Brand",
    wearCount: 9,
    isSharable: true,
  }), request(OPERATION_KINDS.initializeUserPhotoAuthority));
  assert.equal(doc.name, "KeepMe");
  assert.equal(doc.brand, "Brand");
  assert.equal(doc.wearCount, 9);
  assert.equal(doc.isSharable, true);
});
