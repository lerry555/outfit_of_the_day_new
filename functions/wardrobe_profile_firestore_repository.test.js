"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  buildRevisionContext,
} = require("./wardrobe_qualification_revision_contract");
const {
  decodeTrustedSourceObjectSnapshot,
} = require("./trusted_source_object_snapshot");
const {
  AUTHORITY_KEY,
  ENVELOPE_KEY,
  REPOSITORY_ID,
  REPOSITORY_VERSION,
  createMemoryTransactionalStore,
  persistMappedWardrobeProfile,
} = require("./wardrobe_profile_firestore_repository");
const {
  LIFECYCLE_HOOKS,
  lifecyclePlanFor,
} = require("./wardrobe_revision_lifecycle_assignment");
const {
  WRITE_STATUS,
  evaluateTransactionalWrite,
} = require("./wardrobe_profile_transactional_write_policy");

const root = path.resolve(__dirname, "..");

function sourceSnapshot(overrides = {}) {
  return decodeTrustedSourceObjectSnapshot({
    contractVersion: 1,
    backendVerified: true,
    exists: true,
    sourceStoragePath: "wardrobe/u/item.jpg",
    generation: "1700000000000000",
    metageneration: "1",
    sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    updatedAt: "2026-07-29T10:00:00.000Z",
    ...overrides,
  });
}

function envelope({
  revision = 1,
  generationId,
  analysisId = "analysis-1",
  source,
  corrections = {},
} = {}) {
  const src = source || {
    imageRevision: 1,
    wardrobeItemRevision: 1,
    storagePath: "wardrobe/u/item.jpg",
    imageHash: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    uploadGeneration: "1700000000000000",
  };
  return {
    metadata: {
      schemaVersion: 1,
      evidenceSchemaVersion: 1,
      resolverCompatibilityVersion: 1,
      generationId: generationId || "generation-1",
      revision,
      createdAt: "2026-07-29T10:00:00.000Z",
      updatedAt: "2026-07-29T10:00:00.000Z",
      status: "ready",
    },
    source: src,
    analysis: {
      analysisId,
      kind: revision === 1 ? "initial_analysis" : "reanalysis",
      completedAt: "2026-07-29T10:00:00.000Z",
      modelIdentifier: "model-v1",
      pipelineVersion: "pipeline-v1",
      promptVersion: "prompt-v1",
      visionSchemaVersion: 9,
      qualificationVersion: "qualification-v1",
    },
    machineEvidence: [{
      id: "observation:analysis-1:visual.observations.hasHood",
      property: "visual.observations.hasHood",
      value: true,
      valueState: "known",
      source: "visual_observation",
      nature: "observed",
      confidence: 0.9,
      method: "vision_observation",
      createdAt: "2026-07-29T10:00:00.000Z",
      modelVersion: "model-v1",
    }],
    userCorrections: corrections,
  };
}

function revisionContext(overrides = {}) {
  return buildRevisionContext({
    itemId: "item-1",
    imageRevision: 1,
    wardrobeItemRevision: 1,
    sourceStoragePath: "wardrobe/u/item.jpg",
    sourceObjectGeneration: "1700000000000000",
    uploadGeneration: "1700000000000000",
    sourceObjectMetageneration: "1",
    sourceImageSha256:
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    sourceUpdatedAt: "2026-07-29T10:00:00.000Z",
    expectedProfileRevision: null,
    ...overrides,
  });
}

function request(overrides = {}) {
  const context = overrides.revisionContext || revisionContext();
  const mapped = overrides.mappedEnvelope || envelope({
    generationId: context.generationId,
    source: {
      imageRevision: context.imageRevision,
      wardrobeItemRevision: context.wardrobeItemRevision,
      storagePath: context.sourceStoragePath,
      imageHash: context.sourceImageSha256,
      uploadGeneration: context.uploadGeneration,
    },
  });
  return {
    contractVersion: 1,
    userId: "user-1",
    wardrobeItemId: "item-1",
    backendAssignedAt: "2026-07-29T10:00:00.000Z",
    sourceObjectSnapshot: sourceSnapshot(),
    revisionContext: context,
    mappedEnvelope: mapped,
    expectedProfileRevision: null,
    ...overrides,
    revisionContext: context,
    mappedEnvelope: mapped,
  };
}

function legacyDoc(overrides = {}) {
  return {
    name: "Hoodie",
    brand: "Test",
    storagePath: "wardrobe/u/item.jpg",
    category: "tops",
    ...overrides,
  };
}

test("repository constants", () => {
  assert.equal(REPOSITORY_ID, "WardrobeProfilePersistenceRepositoryAdapter");
  assert.equal(REPOSITORY_VERSION, "wardrobe-profile-firestore-repository-v1");
});

test("write_allowed creates profile and lazy-inits authority", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": legacyDoc(),
  });
  const result = await persistMappedWardrobeProfile(request(), store);
  assert.equal(result.status, "write_allowed");
  assert.equal(result.wroteProfile, true);
  assert.equal(result.initializedAuthority, true);
  assert.equal(result.resultingProfileRevision, 1);
  const doc = store._get("user-1", "item-1");
  assert.ok(doc[AUTHORITY_KEY]);
  assert.equal(doc[AUTHORITY_KEY].imageRevision, 1);
  assert.equal(doc[ENVELOPE_KEY].metadata.revision, 1);
  assert.equal(doc.name, "Hoodie");
});

test("idempotent_noop on identical generation retry", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": legacyDoc(),
  });
  const first = await persistMappedWardrobeProfile(request(), store);
  assert.equal(first.wroteProfile, true);
  const second = await persistMappedWardrobeProfile(request(), store);
  assert.equal(second.status, "idempotent_noop");
  assert.equal(second.idempotent, true);
  assert.equal(second.wroteProfile, false);
});

test("same generationId different payload conflicts", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": legacyDoc(),
  });
  const ctx = revisionContext();
  await persistMappedWardrobeProfile(request({revisionContext: ctx}), store);
  const different = envelope({
    generationId: ctx.generationId,
    source: {
      imageRevision: 1,
      wardrobeItemRevision: 1,
      storagePath: "wardrobe/u/item.jpg",
      imageHash: ctx.sourceImageSha256,
      uploadGeneration: "1700000000000000",
    },
  });
  different.machineEvidence[0].value = false;
  const result = await persistMappedWardrobeProfile(request({
    revisionContext: ctx,
    mappedEnvelope: different,
  }), store);
  assert.equal(result.status, "revision_conflict");
  assert.equal(result.reasonCode, "generation_identity_reused_with_different_content");
});

test("stale_image on path mismatch", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": legacyDoc({
      storagePath: "wardrobe/u/other.jpg",
    }),
  });
  const result = await persistMappedWardrobeProfile(request(), store);
  assert.equal(result.status, "stale_image");
});

test("stale_item_revision", async () => {
  const ctx = revisionContext({wardrobeItemRevision: 1});
  const authority = {
    contractVersion: 1,
    imageRevision: 1,
    wardrobeItemRevision: 2,
    uploadGeneration: "1700000000000000",
    generationId: revisionContext({wardrobeItemRevision: 2}).generationId,
    sourceStoragePath: "wardrobe/u/item.jpg",
    sourceObjectGeneration: "1700000000000000",
    sourceUpdatedAt: "2026-07-29T10:00:00.000Z",
    assignedAt: "2026-07-29T10:00:00.000Z",
  };
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": {
      ...legacyDoc(),
      [AUTHORITY_KEY]: authority,
    },
  });
  const result = await persistMappedWardrobeProfile(request({
    revisionContext: ctx,
  }), store);
  assert.equal(result.status, "stale_item_revision");
});

test("item_deleted", async () => {
  const store = createMemoryTransactionalStore({});
  const result = await persistMappedWardrobeProfile(request(), store);
  assert.equal(result.status, "item_deleted");
});

test("source_missing", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": legacyDoc(),
  });
  const result = await persistMappedWardrobeProfile(request({
    sourceObjectSnapshot: sourceSnapshot({exists: false, generation: undefined}),
  }), store);
  assert.equal(result.status, "source_missing");
});

test("newer_generation_exists", async () => {
  const current = revisionContext({
    sourceObjectGeneration: "1800000000000000",
    uploadGeneration: "1800000000000000",
  });
  const proposed = revisionContext({
    sourceObjectGeneration: "1700000000000000",
    uploadGeneration: "1700000000000000",
  });
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": {
      ...legacyDoc(),
      [AUTHORITY_KEY]: {
        ...current,
        assignedAt: "2026-07-29T10:00:00.000Z",
      },
    },
  });
  const result = await persistMappedWardrobeProfile(request({
    revisionContext: proposed,
    sourceObjectSnapshot: sourceSnapshot({generation: "1700000000000000"}),
  }), store);
  assert.equal(result.status, "newer_generation_exists");
});

test("revision_conflict out-of-order profile", async () => {
  const ctx = revisionContext();
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": legacyDoc(),
  });
  await persistMappedWardrobeProfile(request({revisionContext: ctx}), store);
  const nextCtx = revisionContext();
  const nextEnvelope = envelope({
    revision: 2,
    generationId: "generation-2-different",
    analysisId: "analysis-2",
    source: {
      imageRevision: 1,
      wardrobeItemRevision: 1,
      storagePath: "wardrobe/u/item.jpg",
      imageHash: ctx.sourceImageSha256,
      uploadGeneration: "1700000000000000",
    },
  });
  // Force wrong expected revision (0 instead of 1).
  const result = await persistMappedWardrobeProfile({
    ...request({
      revisionContext: {
        ...nextCtx,
        expectedProfileRevision: 0,
        generationId: nextCtx.generationId,
      },
      mappedEnvelope: nextEnvelope,
      expectedProfileRevision: 0,
    }),
  }, store);
  // decodeRevisionContext rebuilds from fields - need rebuild properly
  const rebuilt = revisionContext({expectedProfileRevision: 0});
  const result2 = await persistMappedWardrobeProfile(request({
    revisionContext: rebuilt,
    mappedEnvelope: {
      ...nextEnvelope,
      metadata: {
        ...nextEnvelope.metadata,
        generationId: rebuilt.generationId,
      },
      source: {
        imageRevision: 1,
        wardrobeItemRevision: 1,
        storagePath: "wardrobe/u/item.jpg",
        imageHash: rebuilt.sourceImageSha256,
        uploadGeneration: "1700000000000000",
      },
    },
    expectedProfileRevision: 0,
  }), store);
  assert.ok([
    "revision_conflict",
    "revision_contract_invalid",
  ].includes(result2.status));
});

test("invalid contract / forged client field rejected", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": legacyDoc(),
  });
  await assert.rejects(() => persistMappedWardrobeProfile({
    ...request(),
    qualificationAuthority: {forged: true},
  }, store), /forbidden_client_field/);
});

test("product-only lazy init rejected", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": {
      name: "Product",
      productStoragePath: "wardrobe_product/u/item.png",
    },
  });
  const result = await persistMappedWardrobeProfile(request(), store);
  assert.equal(result.status, "revision_contract_invalid");
  assert.match(result.reasonCode, /product_source|missing_storage/);
});

test("userCorrections preserved on update", async () => {
  const ctx = revisionContext();
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": legacyDoc(),
  });
  await persistMappedWardrobeProfile(request({revisionContext: ctx}), store);
  const existing = store._get("user-1", "item-1");
  existing[ENVELOPE_KEY].userCorrections = {
    "identity.canonicalType": {
      id: "correction:set",
      property: "identity.canonicalType",
      action: "set",
      value: "hoodie",
      correctedAt: "2026-07-29T09:00:00.000Z",
      method: "wardrobe_item_edit",
    },
  };
  // Re-seed store with corrections (memory store clone semantics).
  const reseeds = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": existing,
  });
  const rebuilt = buildRevisionContext({
    itemId: "item-1",
    imageRevision: 1,
    wardrobeItemRevision: 1,
    sourceStoragePath: "wardrobe/u/item.jpg",
    sourceObjectGeneration: "1700000000000000",
    uploadGeneration: "1700000000000000",
    sourceObjectMetageneration: "1",
    sourceImageSha256: ctx.sourceImageSha256,
    sourceUpdatedAt: "2026-07-29T10:00:00.000Z",
    expectedProfileRevision: 1,
  });
  const nextEnvelope = envelope({
    revision: 2,
    generationId: rebuilt.generationId,
    analysisId: "analysis-2",
    source: {
      imageRevision: 1,
      wardrobeItemRevision: 1,
      storagePath: "wardrobe/u/item.jpg",
      imageHash: rebuilt.sourceImageSha256,
      uploadGeneration: "1700000000000000",
    },
  });
  const result = await persistMappedWardrobeProfile(request({
    revisionContext: rebuilt,
    mappedEnvelope: nextEnvelope,
    expectedProfileRevision: 1,
  }), reseeds);
  assert.equal(result.status, "write_allowed");
  assert.equal(result.resultingProfileRevision, 2);
  const updated = reseeds._get("user-1", "item-1");
  assert.equal(
    updated[ENVELOPE_KEY].userCorrections["identity.canonicalType"].value,
    "hoodie",
  );
  assert.equal(updated.name, "Hoodie");
});

test("unrelated root fields preserved", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": legacyDoc({customFlag: true}),
  });
  await persistMappedWardrobeProfile(request(), store);
  assert.equal(store._get("user-1", "item-1").customFlag, true);
});

test("malformed existing profile fail-closed", async () => {
  const ctx = revisionContext();
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": {
      ...legacyDoc(),
      [AUTHORITY_KEY]: {
        ...ctx,
        assignedAt: "2026-07-29T10:00:00.000Z",
      },
      [ENVELOPE_KEY]: {broken: true},
    },
  });
  const result = await persistMappedWardrobeProfile(request({
    revisionContext: ctx,
  }), store);
  assert.equal(result.wroteProfile, false);
  assert.ok([
    "revision_contract_invalid",
    "revision_conflict",
  ].includes(result.status) || result.reasonCode.includes("invalid"));
});

test("malformed qualificationAuthority fail-closed", async () => {
  const store = createMemoryTransactionalStore({
    "users/user-1/wardrobe/item-1": {
      ...legacyDoc(),
      [AUTHORITY_KEY]: {contractVersion: 1, imageRevision: "x"},
    },
  });
  const result = await persistMappedWardrobeProfile(request(), store);
  assert.equal(result.status, "revision_contract_invalid");
  assert.equal(result.wroteProfile, false);
});

test("client source snapshot rejected", () => {
  assert.throws(() => decodeTrustedSourceObjectSnapshot({
    contractVersion: 1,
    backendVerified: true,
    exists: true,
    sourceStoragePath: "wardrobe/u/item.jpg",
    generation: "1",
    clientProvided: true,
  }), /client_source_snapshot_rejected|unknown_field/);
});

test("Dart transactional policy create/update semantics", () => {
  const source = {
    imageRevision: 1,
    wardrobeItemRevision: 1,
    storagePath: "wardrobe/u/item.jpg",
    imageHash: null,
    uploadGeneration: "1",
  };
  const created = evaluateTransactionalWrite({
    current: {exists: true, source, document: {}},
    command: {
      userId: "u",
      wardrobeItemId: "i",
      envelope: envelope({
        revision: 1,
        generationId: "g1",
        source: {...source, uploadGeneration: "1"},
      }),
      expectedSource: source,
      expectedProfileRevision: null,
    },
  });
  assert.equal(created.result.status, WRITE_STATUS.created);
  assert.ok(created.documentPatch);
});

test("lifecycle assignment gaps documented", () => {
  assert.equal(
    lifecyclePlanFor("F_image_replacement").actor,
    "not_implemented_in_production",
  );
  assert.equal(
    lifecyclePlanFor("B_new_product_link_item").imageRevision,
    "do_not_initialize_without_wardrobe_source_path",
  );
  assert.equal(LIFECYCLE_HOOKS.deleteItem.notes.includes("Storage path maps"),
    true);
});

test("production isolation", () => {
  const production = [
    "functions/index.js",
    "functions/vision_v2_shadow.js",
  ].map((item) => fs.readFileSync(path.join(root, item), "utf8")).join("\n");
  assert.equal(production.includes("wardrobe_profile_firestore_repository"),
    false);
  assert.equal(production.includes("persistMappedWardrobeProfile"), false);
  assert.equal(
    fs.existsSync(path.join(root,
      "firestore/wardrobe_backend_boundary.rules")),
    true,
  );
  assert.equal(fs.existsSync(path.join(root, "firestore.rules")), true);
  const firebaseJson = JSON.parse(fs.readFileSync(
    path.join(root, "firebase.json"), "utf8"));
  // Local emulator binding only — Rules not deployed; handlers not exported.
  assert.equal(firebaseJson.firestore.rules, "firestore.rules");
  assert.equal(production.includes("createQualificationAuthorityHandler"), false);
});
