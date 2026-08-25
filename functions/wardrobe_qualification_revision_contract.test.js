"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  BACKEND_ONLY_FIELDS,
  CLIENT_MAY_SEND,
  CONTRACT_ID,
  CONTRACT_VERSION,
  CONTRACT_VERSION_NUMBER,
  EDIT_CLASSES,
  FORBIDDEN_CLIENT_AUTHORITY_FIELDS,
  GENERATION_ID_PREFIX,
  MIGRATION_CLASSES,
  WRITE_DECISIONS,
  buildGenerationId,
  buildRevisionContext,
  canonicalizeRevisionIdentity,
  classifyLegacyMigration,
  compareRevisions,
  decodeRevisionContext,
  editInvalidationFor,
  evaluateWriteDecision,
  toSourceSnapshot,
} = require("./wardrobe_qualification_revision_contract");

const root = path.resolve(__dirname, "..");

function baseParts(overrides = {}) {
  return {
    itemId: "item-1",
    imageRevision: 2,
    wardrobeItemRevision: 5,
    sourceStoragePath: "wardrobe/u/item.jpg",
    sourceObjectGeneration: "1700000000000000",
    uploadGeneration: "1700000000000000",
    sourceObjectMetageneration: "1",
    sourceImageSha256:
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    sourceUpdatedAt: "2026-07-29T10:00:00.000Z",
    expectedProfileRevision: 3,
    ...overrides,
  };
}

function ctx(overrides = {}) {
  return buildRevisionContext(baseParts(overrides));
}

test("contract constants", () => {
  assert.equal(CONTRACT_ID, "TrustedRevisionContract");
  assert.equal(CONTRACT_VERSION,
    "wardrobe-qualification-revision-context-v1");
  assert.equal(CONTRACT_VERSION_NUMBER, 1);
  assert.ok(CLIENT_MAY_SEND.includes("itemId"));
  assert.ok(BACKEND_ONLY_FIELDS.includes("generationId"));
  assert.ok(FORBIDDEN_CLIENT_AUTHORITY_FIELDS.includes("imageRevision"));
});

test("exact matching current context is write_allowed", () => {
  const proposed = ctx();
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: proposed,
    currentProfileRevision: 3,
  });
  assert.equal(result.decision, WRITE_DECISIONS.writeAllowed);
});

test("duplicate same-generation retry is idempotent_noop", () => {
  const proposed = ctx();
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: proposed,
    currentProfileRevision: 3,
    sameGenerationAlreadyApplied: true,
  });
  assert.equal(result.decision, WRITE_DECISIONS.idempotentNoop);
  assert.equal(result.reasonCode, "identical_generation_already_applied");
});

test("newer image revision is stale_image", () => {
  const current = ctx({imageRevision: 2});
  const proposed = ctx({imageRevision: 3});
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: current,
    currentProfileRevision: 3,
  });
  assert.equal(result.decision, WRITE_DECISIONS.staleImage);
});

test("older image revision is stale_image", () => {
  const current = ctx({imageRevision: 3});
  const proposed = ctx({imageRevision: 2});
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: current,
    currentProfileRevision: 3,
  });
  assert.equal(result.decision, WRITE_DECISIONS.staleImage);
  assert.equal(result.reasonCode, "older_image_revision");
});

test("different storage path is stale_image", () => {
  const current = ctx();
  const proposed = ctx({sourceStoragePath: "wardrobe/u/other.jpg"});
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: current,
    currentProfileRevision: 3,
  });
  assert.equal(result.decision, WRITE_DECISIONS.staleImage);
  assert.equal(result.reasonCode, "image_identity_mismatch");
});

test("different object generation is newer_generation_exists", () => {
  const current = ctx();
  const proposed = ctx({
    sourceObjectGeneration: "1800000000000000",
    uploadGeneration: "1800000000000000",
  });
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: current,
    currentProfileRevision: 3,
  });
  assert.equal(result.decision, WRITE_DECISIONS.newerGenerationExists);
});

test("higher wardrobe item revision is stale_item_revision", () => {
  const current = ctx({wardrobeItemRevision: 5});
  const proposed = ctx({wardrobeItemRevision: 6});
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: current,
    currentProfileRevision: 3,
  });
  assert.equal(result.decision, WRITE_DECISIONS.staleItemRevision);
});

test("matching wardrobe item revision allows write", () => {
  const proposed = ctx({wardrobeItemRevision: 5});
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: proposed,
    currentProfileRevision: 3,
  });
  assert.equal(result.decision, WRITE_DECISIONS.writeAllowed);
});

test("item deleted", () => {
  const result = evaluateWriteDecision({
    itemExists: false,
    sourceObjectExists: true,
    proposed: ctx(),
    currentAuthority: ctx(),
    currentProfileRevision: 3,
  });
  assert.equal(result.decision, WRITE_DECISIONS.itemDeleted);
});

test("source missing", () => {
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: false,
    proposed: ctx(),
    currentAuthority: ctx(),
    currentProfileRevision: 3,
  });
  assert.equal(result.decision, WRITE_DECISIONS.sourceMissing);
});

test("existing newer profile revision conflicts", () => {
  const proposed = ctx({expectedProfileRevision: 2});
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: proposed,
    currentProfileRevision: 3,
  });
  assert.equal(result.decision, WRITE_DECISIONS.revisionConflict);
  assert.equal(result.reasonCode, "newer_profile_revision_exists");
});

test("same profile revision allows write", () => {
  const proposed = ctx({expectedProfileRevision: 3});
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: proposed,
    currentProfileRevision: 3,
  });
  assert.equal(result.decision, WRITE_DECISIONS.writeAllowed);
});

test("invalid generationId rejected by decoder", () => {
  const valid = ctx();
  assert.throws(() => decodeRevisionContext({
    ...valid,
    generationId: "wqrev:v1:deadbeef",
  }), /generation_id_binding_mismatch/);
});

test("tampered context rejected", () => {
  const valid = ctx();
  assert.throws(() => decodeRevisionContext({
    ...valid,
    imageRevision: 99,
  }), /generation_id_binding_mismatch/);
});

test("user correction during analysis preserves write", () => {
  const proposed = ctx();
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: proposed,
    currentProfileRevision: 3,
    userCorrectionChanged: true,
  });
  assert.equal(result.decision, WRITE_DECISIONS.writeAllowed);
  assert.equal(result.reasonCode, "user_correction_preserved_on_machine_write");
});

test("unrelated edit does not invalidate", () => {
  const proposed = ctx();
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: proposed,
    currentProfileRevision: 3,
    editClass: EDIT_CLASSES.unrelatedField,
  });
  assert.equal(result.decision, WRITE_DECISIONS.writeAllowed);
  assert.deepEqual(editInvalidationFor(EDIT_CLASSES.unrelatedField), {
    bumpImageRevision: false,
    bumpWardrobeItemRevision: false,
    bumpProfileRevision: false,
    invalidateInFlightAnalysis: false,
  });
});

test("derivative image completion does not bump image revision", () => {
  const policy = editInvalidationFor(EDIT_CLASSES.derivativeCompletion);
  assert.equal(policy.bumpImageRevision, false);
  assert.equal(policy.invalidateInFlightAnalysis, false);
  const proposed = ctx();
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: proposed,
    currentProfileRevision: 3,
    editClass: EDIT_CLASSES.derivativeCompletion,
  });
  assert.equal(result.decision, WRITE_DECISIONS.writeAllowed);
});

test("re-analysis same image allowed", () => {
  const proposed = ctx();
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: proposed,
    currentProfileRevision: 3,
    editClass: EDIT_CLASSES.reanalysisSameImage,
  });
  assert.equal(result.decision, WRITE_DECISIONS.writeAllowed);
  assert.equal(
    editInvalidationFor(EDIT_CLASSES.reanalysisSameImage).bumpImageRevision,
    false,
  );
});

test("concurrent image replacement is stale", () => {
  const current = ctx({
    imageRevision: 3,
    sourceObjectGeneration: "1900000000000000",
    uploadGeneration: "1900000000000000",
  });
  const proposed = ctx({
    imageRevision: 2,
    sourceObjectGeneration: "1700000000000000",
    uploadGeneration: "1700000000000000",
  });
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: current,
    currentProfileRevision: 3,
  });
  assert.ok([
    WRITE_DECISIONS.staleImage,
    WRITE_DECISIONS.newerGenerationExists,
  ].includes(result.decision));
});

test("out-of-order analysis completion is stale or conflict", () => {
  const proposed = ctx({expectedProfileRevision: 3});
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: proposed,
    currentProfileRevision: 4,
  });
  assert.equal(result.decision, WRITE_DECISIONS.revisionConflict);
  assert.equal(result.reasonCode, "newer_profile_revision_exists");
});

test("migration legacy item with storagePath is lazy_init_ready", () => {
  const result = classifyLegacyMigration({
    storagePath: "wardrobe/u/item.jpg",
    cleanStoragePath: "wardrobe_clean/u/item.png",
    productStoragePath: "wardrobe_product/u/item.png",
    sourceObjectExists: true,
  });
  assert.equal(result.class, MIGRATION_CLASSES.lazyInitReady);
  assert.equal(result.reanalysisRequired, false);
  assert.equal(result.lazyInitAllowed, true);
  assert.equal(result.proposedBootstrap.imageRevision, 1);
});

test("product-source item without storagePath is fail-closed", () => {
  const result = classifyLegacyMigration({
    storagePath: null,
    productStoragePath: "wardrobe_product/u/item.png",
  });
  assert.equal(result.class, MIGRATION_CLASSES.productSourceOnly);
  assert.equal(result.failClosed, true);
  assert.equal(result.lazyInitAllowed, false);
});

test("missing storagePath is fail-closed", () => {
  const result = classifyLegacyMigration({storagePath: ""});
  assert.equal(result.class, MIGRATION_CLASSES.missingStoragePath);
  assert.equal(result.failClosed, true);
});

test("deterministic generationId", () => {
  const first = buildGenerationId(baseParts());
  const second = buildGenerationId(baseParts());
  assert.equal(first, second);
  assert.ok(first.startsWith(GENERATION_ID_PREFIX));
  assert.equal(first.length, GENERATION_ID_PREFIX.length + 64);
});

test("canonical serialization is stable and documented", () => {
  const first = canonicalizeRevisionIdentity(baseParts());
  const second = canonicalizeRevisionIdentity(baseParts());
  assert.equal(first, second);
  assert.equal(first.endsWith("\n"), true);
  const parsed = JSON.parse(first.trim());
  assert.deepEqual(Object.keys(parsed), [
    "imageRevision",
    "itemId",
    "sourceObjectGeneration",
    "sourceStoragePath",
    "uploadGeneration",
  ]);
  const digest = crypto.createHash("sha256").update(first, "utf8").digest("hex");
  assert.equal(buildGenerationId(baseParts()), `${GENERATION_ID_PREFIX}${digest}`);
});

test("immutable output", () => {
  const context = ctx();
  assert.ok(Object.isFrozen(context));
  assert.throws(() => {
    context.imageRevision = 99;
  });
  const decision = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed: context,
    currentAuthority: context,
    currentProfileRevision: 3,
  });
  assert.ok(Object.isFrozen(decision));
});

test("forged client revisions rejected", () => {
  assert.throws(() => decodeRevisionContext({
    ...ctx(),
    forgedByClient: true,
  }), /revision_context_unknown_field:forgedByClient|forged_client_revisions_rejected/);
  assert.throws(() => decodeRevisionContext({
    contractVersion: 1,
    itemId: "item-1",
    imageRevision: 1,
    wardrobeItemRevision: 1,
    uploadGeneration: "1",
    sourceStoragePath: "wardrobe/u/a.jpg",
    sourceObjectGeneration: "1",
    sourceUpdatedAt: "2026-07-29T10:00:00.000Z",
    generationId: buildGenerationId({
      itemId: "item-1",
      imageRevision: 1,
      sourceStoragePath: "wardrobe/u/a.jpg",
      sourceObjectGeneration: "1",
      uploadGeneration: "1",
    }),
    clientAuthority: true,
  }), /unknown_field|forged_client/);
});

test("strict decoder rejects derivative paths and bad versions", () => {
  assert.throws(() => buildRevisionContext(baseParts({
    sourceStoragePath: "wardrobe_clean/u/x.png",
  })), /derivative_path_forbidden|must_be_wardrobe_source_path/);
  assert.throws(() => decodeRevisionContext({
    ...ctx(),
    contractVersion: 2,
  }), /contract_version_unsupported/);
});

test("uploadGeneration must bind to sourceObjectGeneration", () => {
  assert.throws(() => buildRevisionContext(baseParts({
    uploadGeneration: "999",
    sourceObjectGeneration: "1700000000000000",
  })), /upload_generation_binding_mismatch/);
});

test("toSourceSnapshot matches repository WardrobeItemSourceSnapshot shape", () => {
  const snapshot = toSourceSnapshot(ctx());
  assert.deepEqual(Object.keys(snapshot).sort(), [
    "imageHash",
    "imageRevision",
    "storagePath",
    "uploadGeneration",
    "wardrobeItemRevision",
  ].sort());
});

test("compareRevisions ordering", () => {
  assert.equal(compareRevisions(1, 1), 0);
  assert.equal(compareRevisions(1, 2), -1);
  assert.equal(compareRevisions(3, 2), 1);
});

test("edit invalidation matrix summary", () => {
  assert.equal(
    editInvalidationFor(EDIT_CLASSES.imageChanging).invalidateInFlightAnalysis,
    true,
  );
  assert.equal(
    editInvalidationFor(EDIT_CLASSES.classificationMetadata)
      .bumpWardrobeItemRevision,
    true,
  );
  assert.equal(
    editInvalidationFor(EDIT_CLASSES.userCorrection).preserveOnMachineWrite,
    true,
  );
  assert.equal(
    editInvalidationFor(EDIT_CLASSES.machineProfileWrite).bumpProfileRevision,
    true,
  );
});

test("null expectedProfileRevision for first create", () => {
  const proposed = ctx({expectedProfileRevision: null});
  const result = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: true,
    proposed,
    currentAuthority: proposed,
    currentProfileRevision: null,
  });
  assert.equal(result.decision, WRITE_DECISIONS.writeAllowed);
});

test("production isolation", () => {
  const production = [
    "functions/index.js",
    "functions/vision_v2_shadow.js",
  ].map((item) => fs.readFileSync(path.join(root, item), "utf8")).join("\n");
  assert.equal(production.includes("wardrobe_qualification_revision_contract"),
    false);
  assert.equal(production.includes("evaluateWriteDecision"), false);
  const source = fs.readFileSync(path.join(
    root, "functions/wardrobe_qualification_revision_contract.js"), "utf8");
  assert.doesNotMatch(source,
    /require\(["']firebase|firebase-admin|Date\.now\(|Math\.random\(/);
});
