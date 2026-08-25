"use strict";

/**
 * Trusted Wardrobe Qualification Revision Contract / v1
 *
 * Pure / sync / deterministic foundation for future CAS writes.
 * No Firestore, Storage I/O, network, Date.now, Math.random, or Firebase.
 *
 * Authority for image/item revisions is assigned by a future trusted
 * backend lifecycle. This module only validates, builds generationId,
 * and decides stale-write outcomes against already-trusted snapshots.
 */

const crypto = require("node:crypto");

const CONTRACT_ID = "TrustedRevisionContract";
const CONTRACT_VERSION = "wardrobe-qualification-revision-context-v1";
const CONTRACT_VERSION_NUMBER = 1;
const GENERATION_ID_PREFIX = "wqrev:v1:";

const WRITE_DECISIONS = Object.freeze({
  writeAllowed: "write_allowed",
  idempotentNoop: "idempotent_noop",
  staleImage: "stale_image",
  staleItemRevision: "stale_item_revision",
  itemDeleted: "item_deleted",
  sourceMissing: "source_missing",
  newerGenerationExists: "newer_generation_exists",
  revisionContractInvalid: "revision_contract_invalid",
  revisionConflict: "revision_conflict",
});

/** Maps to WardrobeProfileWriteStatus / reasonCode vocabulary where applicable. */
const REPOSITORY_REASON_CODES = Object.freeze({
  write_allowed: "source_revisions_match",
  idempotent_noop: "identical_generation_already_applied",
  stale_image: "image_revision_mismatch",
  stale_item_revision: "wardrobe_item_revision_mismatch",
  item_deleted: "wardrobe_item_not_found",
  source_missing: "source_object_missing",
  newer_generation_exists: "upload_generation_mismatch",
  revision_contract_invalid: "revision_contract_invalid",
  revision_conflict: "expected_profile_revision_mismatch",
});

const EDIT_CLASSES = Object.freeze({
  imageChanging: "image_changing_edit",
  classificationMetadata: "classification_metadata_edit",
  visualOnlyUi: "visual_only_ui_field",
  userCorrection: "user_correction",
  derivativeCompletion: "derivative_image_completion",
  unrelatedField: "unrelated_document_field",
  machineProfileWrite: "machine_profile_write",
  reanalysisSameImage: "reanalysis_same_image",
});

const EDIT_INVALIDATION = Object.freeze({
  [EDIT_CLASSES.imageChanging]: Object.freeze({
    bumpImageRevision: true,
    bumpWardrobeItemRevision: true,
    bumpProfileRevision: false,
    invalidateInFlightAnalysis: true,
  }),
  [EDIT_CLASSES.classificationMetadata]: Object.freeze({
    bumpImageRevision: false,
    bumpWardrobeItemRevision: true,
    bumpProfileRevision: false,
    invalidateInFlightAnalysis: true,
  }),
  [EDIT_CLASSES.visualOnlyUi]: Object.freeze({
    bumpImageRevision: false,
    bumpWardrobeItemRevision: false,
    bumpProfileRevision: false,
    invalidateInFlightAnalysis: false,
  }),
  [EDIT_CLASSES.userCorrection]: Object.freeze({
    bumpImageRevision: false,
    bumpWardrobeItemRevision: true,
    bumpProfileRevision: false,
    invalidateInFlightAnalysis: false,
    preserveOnMachineWrite: true,
  }),
  [EDIT_CLASSES.derivativeCompletion]: Object.freeze({
    bumpImageRevision: false,
    bumpWardrobeItemRevision: false,
    bumpProfileRevision: false,
    invalidateInFlightAnalysis: false,
  }),
  [EDIT_CLASSES.unrelatedField]: Object.freeze({
    bumpImageRevision: false,
    bumpWardrobeItemRevision: false,
    bumpProfileRevision: false,
    invalidateInFlightAnalysis: false,
  }),
  [EDIT_CLASSES.machineProfileWrite]: Object.freeze({
    bumpImageRevision: false,
    bumpWardrobeItemRevision: false,
    bumpProfileRevision: true,
    invalidateInFlightAnalysis: false,
  }),
  [EDIT_CLASSES.reanalysisSameImage]: Object.freeze({
    bumpImageRevision: false,
    bumpWardrobeItemRevision: false,
    bumpProfileRevision: true,
    invalidateInFlightAnalysis: false,
  }),
});

const CLIENT_MAY_SEND = Object.freeze([
  "itemId",
  "explicitUserAction",
  "sourceImageReference",
]);

const BACKEND_ONLY_FIELDS = Object.freeze([
  "imageRevision",
  "wardrobeItemRevision",
  "uploadGeneration",
  "generationId",
  "sourceObjectGeneration",
  "sourceObjectMetageneration",
  "sourceImageSha256",
  "sourceUpdatedAt",
  "expectedProfileRevision",
  "contractVersion",
  "qualificationAuthority",
  "machineEvidence",
  "mapperProvenance",
  "serverWriteMetadata",
]);

const FORBIDDEN_CLIENT_AUTHORITY_FIELDS = Object.freeze([
  ...BACKEND_ONLY_FIELDS,
]);

const MIGRATION_CLASSES = Object.freeze({
  alreadyInitialized: "already_initialized",
  lazyInitReady: "lazy_init_ready",
  missingStoragePath: "missing_storage_path",
  productSourceOnly: "product_source_only",
  sourceObjectMissing: "source_object_missing",
});

/**
 * @param {object} raw
 * @returns {Readonly<object>} WardrobeQualificationRevisionContext/v1
 */
function decodeRevisionContext(raw) {
  if (!isObject(raw)) fail("revision_context_not_object");
  rejectForbiddenClientForgery(raw);
  rejectUnknownFields(raw, KNOWN_CONTEXT_FIELDS, "revision_context");

  const contractVersion = requirePositiveInt(
    raw.contractVersion, "contractVersion");
  if (contractVersion !== CONTRACT_VERSION_NUMBER) {
    fail("contract_version_unsupported");
  }

  const itemId = requireNonEmpty(raw.itemId, "itemId");
  const imageRevision = requireNonNegativeInt(raw.imageRevision, "imageRevision");
  const wardrobeItemRevision = requireNonNegativeInt(
    raw.wardrobeItemRevision, "wardrobeItemRevision");
  const sourceStoragePath = requireStoragePath(
    raw.sourceStoragePath, "sourceStoragePath");
  const sourceObjectGeneration = requireGeneration(
    raw.sourceObjectGeneration, "sourceObjectGeneration");
  const uploadGeneration = requireGeneration(
    raw.uploadGeneration, "uploadGeneration");
  if (uploadGeneration !== sourceObjectGeneration) {
    fail("upload_generation_binding_mismatch");
  }

  const sourceObjectMetageneration = raw.sourceObjectMetageneration == null ?
    null :
    requireGeneration(raw.sourceObjectMetageneration,
      "sourceObjectMetageneration");
  const sourceImageSha256 = raw.sourceImageSha256 == null ?
    null :
    requireSha256Hex(raw.sourceImageSha256, "sourceImageSha256");
  const sourceUpdatedAt = requireUtc(raw.sourceUpdatedAt, "sourceUpdatedAt");
  const expectedProfileRevision = Object.prototype.hasOwnProperty.call(
    raw, "expectedProfileRevision") && raw.expectedProfileRevision != null ?
    requireNonNegativeInt(raw.expectedProfileRevision, "expectedProfileRevision") :
    null;

  const generationId = requireNonEmpty(raw.generationId, "generationId");
  const expectedGenerationId = buildGenerationId({
    itemId,
    imageRevision,
    sourceStoragePath,
    sourceObjectGeneration,
    uploadGeneration,
  });
  if (generationId !== expectedGenerationId) {
    fail("generation_id_binding_mismatch");
  }

  return deepFreeze({
    contractVersion,
    itemId,
    imageRevision,
    wardrobeItemRevision,
    uploadGeneration,
    generationId,
    sourceStoragePath,
    sourceObjectGeneration,
    sourceObjectMetageneration,
    sourceImageSha256,
    sourceUpdatedAt,
    expectedProfileRevision,
  });
}

/**
 * Build a validated context from trusted backend-assigned components.
 * Clients must not call this with forged revisions.
 */
function buildRevisionContext(parts) {
  const draft = {
    contractVersion: CONTRACT_VERSION_NUMBER,
    itemId: parts.itemId,
    imageRevision: parts.imageRevision,
    wardrobeItemRevision: parts.wardrobeItemRevision,
    uploadGeneration: parts.uploadGeneration ?? parts.sourceObjectGeneration,
    sourceStoragePath: parts.sourceStoragePath,
    sourceObjectGeneration: parts.sourceObjectGeneration,
    sourceObjectMetageneration: parts.sourceObjectMetageneration ?? null,
    sourceImageSha256: parts.sourceImageSha256 ?? null,
    sourceUpdatedAt: parts.sourceUpdatedAt,
    expectedProfileRevision: Object.prototype.hasOwnProperty.call(
      parts, "expectedProfileRevision") ?
      parts.expectedProfileRevision : null,
  };
  draft.generationId = buildGenerationId({
    itemId: draft.itemId,
    imageRevision: draft.imageRevision,
    sourceStoragePath: draft.sourceStoragePath,
    sourceObjectGeneration: draft.sourceObjectGeneration,
    uploadGeneration: draft.uploadGeneration,
  });
  return decodeRevisionContext(draft);
}

/**
 * Canonical serialization for generationId identity components.
 * Keys sorted lexicographically. No timestamps, UID, URLs, or random.
 */
function canonicalizeRevisionIdentity(identity) {
  const itemId = requireNonEmpty(identity.itemId, "itemId");
  const imageRevision = requireNonNegativeInt(
    identity.imageRevision, "imageRevision");
  const sourceStoragePath = requireStoragePath(
    identity.sourceStoragePath, "sourceStoragePath");
  const sourceObjectGeneration = requireGeneration(
    identity.sourceObjectGeneration, "sourceObjectGeneration");
  const uploadGeneration = requireGeneration(
    identity.uploadGeneration ?? identity.sourceObjectGeneration,
    "uploadGeneration");
  if (uploadGeneration !== sourceObjectGeneration) {
    fail("upload_generation_binding_mismatch");
  }
  const payload = {
    imageRevision,
    itemId,
    sourceObjectGeneration,
    sourceStoragePath,
    uploadGeneration,
  };
  return `${JSON.stringify(payload)}\n`;
}

function buildGenerationId(identity) {
  const canonical = canonicalizeRevisionIdentity(identity);
  const digest = crypto.createHash("sha256")
    .update(canonical, "utf8")
    .digest("hex");
  return `${GENERATION_ID_PREFIX}${digest}`;
}

function compareRevisions(left, right) {
  if (left === right) return 0;
  return left < right ? -1 : 1;
}

/**
 * Pure stale-write decision against a trusted current snapshot.
 *
 * @param {object} input
 * @returns {Readonly<{decision:string, reasonCode:string, repositoryReasonCode:string}>}
 */
function evaluateWriteDecision(input) {
  if (!isObject(input)) {
    return decision(WRITE_DECISIONS.revisionContractInvalid,
      "decision_input_not_object");
  }
  if (input.itemExists === false) {
    return decision(WRITE_DECISIONS.itemDeleted, "wardrobe_item_not_found");
  }
  if (input.sourceObjectExists === false) {
    return decision(WRITE_DECISIONS.sourceMissing, "source_object_missing");
  }

  let proposed;
  try {
    proposed = decodeRevisionContext(input.proposed);
  } catch (error) {
    return decision(WRITE_DECISIONS.revisionContractInvalid, error.message);
  }

  if (input.currentAuthority == null) {
    if (input.allowLegacyMissingAuthority === true) {
      return decision(WRITE_DECISIONS.revisionContractInvalid,
        "legacy_authority_not_initialized");
    }
    return decision(WRITE_DECISIONS.revisionContractInvalid,
      "trusted_source_snapshot_missing");
  }

  let current;
  try {
    current = decodeRevisionContext(input.currentAuthority);
  } catch (error) {
    return decision(WRITE_DECISIONS.revisionContractInvalid,
      `current_authority_invalid:${error.message}`);
  }

  if (proposed.itemId !== current.itemId) {
    return decision(WRITE_DECISIONS.revisionContractInvalid, "item_id_mismatch");
  }
  if (proposed.sourceStoragePath !== current.sourceStoragePath) {
    return decision(WRITE_DECISIONS.staleImage, "image_identity_mismatch");
  }
  if (proposed.sourceObjectGeneration !== current.sourceObjectGeneration ||
      proposed.uploadGeneration !== current.uploadGeneration) {
    return decision(WRITE_DECISIONS.newerGenerationExists,
      "upload_generation_mismatch");
  }
  if (proposed.imageRevision !== current.imageRevision) {
    if (proposed.imageRevision < current.imageRevision) {
      return decision(WRITE_DECISIONS.staleImage, "older_image_revision");
    }
    return decision(WRITE_DECISIONS.staleImage, "image_revision_mismatch");
  }
  if (proposed.wardrobeItemRevision !== current.wardrobeItemRevision) {
    if (proposed.wardrobeItemRevision < current.wardrobeItemRevision) {
      return decision(WRITE_DECISIONS.staleItemRevision,
        "older_wardrobe_item_revision");
    }
    return decision(WRITE_DECISIONS.staleItemRevision,
      "wardrobe_item_revision_mismatch");
  }
  if (proposed.generationId !== current.generationId) {
    return decision(WRITE_DECISIONS.revisionContractInvalid,
      "generation_id_mismatch_for_identical_source");
  }

  const currentProfileRevision = input.currentProfileRevision == null ?
    null : requireNonNegativeInt(input.currentProfileRevision,
      "currentProfileRevision");
  if (proposed.expectedProfileRevision !== currentProfileRevision) {
    if (currentProfileRevision != null &&
        proposed.expectedProfileRevision != null &&
        proposed.expectedProfileRevision < currentProfileRevision) {
      return decision(WRITE_DECISIONS.revisionConflict,
        "newer_profile_revision_exists");
    }
    return decision(WRITE_DECISIONS.revisionConflict,
      "expected_profile_revision_mismatch");
  }

  if (input.sameGenerationAlreadyApplied === true) {
    return decision(WRITE_DECISIONS.idempotentNoop,
      "identical_generation_already_applied");
  }

  if (input.userCorrectionChanged === true) {
    // Corrections are preserved by repository merge; they bump item revision
    // when written. Matching item revision means corrections were concurrent
    // without an item-revision bump, so write remains allowed.
    return decision(WRITE_DECISIONS.writeAllowed,
      "user_correction_preserved_on_machine_write");
  }

  if (input.editClass === EDIT_CLASSES.derivativeCompletion ||
      input.editClass === EDIT_CLASSES.visualOnlyUi ||
      input.editClass === EDIT_CLASSES.unrelatedField) {
    return decision(WRITE_DECISIONS.writeAllowed, "unrelated_or_derivative_edit");
  }

  if (input.editClass === EDIT_CLASSES.reanalysisSameImage) {
    return decision(WRITE_DECISIONS.writeAllowed, "reanalysis_same_image");
  }

  return decision(WRITE_DECISIONS.writeAllowed, "source_revisions_match");
}

function classifyLegacyMigration(item) {
  if (!isObject(item)) fail("legacy_item_not_object");
  if (item.authorityInitialized === true) {
    return deepFreeze({
      class: MIGRATION_CLASSES.alreadyInitialized,
      reanalysisRequired: false,
      lazyInitAllowed: false,
    });
  }
  const storagePath = textOrNull(item.storagePath);
  const productStoragePath = textOrNull(item.productStoragePath);
  const cleanStoragePath = textOrNull(item.cleanStoragePath);
  if (storagePath == null || storagePath.trim() === "") {
    if (productStoragePath != null && productStoragePath.trim() !== "") {
      return deepFreeze({
        class: MIGRATION_CLASSES.productSourceOnly,
        reanalysisRequired: false,
        lazyInitAllowed: false,
        failClosed: true,
        reason: "product_source_without_original_storage_path",
      });
    }
    return deepFreeze({
      class: MIGRATION_CLASSES.missingStoragePath,
      reanalysisRequired: false,
      lazyInitAllowed: false,
      failClosed: true,
      reason: "missing_storage_path",
    });
  }
  if (item.sourceObjectExists === false) {
    return deepFreeze({
      class: MIGRATION_CLASSES.sourceObjectMissing,
      reanalysisRequired: false,
      lazyInitAllowed: false,
      failClosed: true,
      reason: "source_object_missing",
    });
  }
  return deepFreeze({
    class: MIGRATION_CLASSES.lazyInitReady,
    reanalysisRequired: false,
    lazyInitAllowed: true,
    proposedBootstrap: Object.freeze({
      imageRevision: 1,
      wardrobeItemRevision: 1,
      sourceStoragePath: storagePath,
      // uploadGeneration/sourceObjectGeneration must be filled from Storage
      // metadata at assignment time; not inventable here.
      requiresStorageGenerationRead: true,
      cleanStoragePath,
      productStoragePath,
    }),
  });
}

function editInvalidationFor(editClass) {
  const policy = EDIT_INVALIDATION[editClass];
  if (policy == null) fail(`edit_class_unknown:${editClass}`);
  return policy;
}

function toSourceSnapshot(context) {
  const decoded = decodeRevisionContext(context);
  return deepFreeze({
    imageRevision: decoded.imageRevision,
    wardrobeItemRevision: decoded.wardrobeItemRevision,
    storagePath: decoded.sourceStoragePath,
    imageHash: decoded.sourceImageSha256,
    uploadGeneration: decoded.uploadGeneration,
  });
}

function decision(decisionCode, reasonCode) {
  return deepFreeze({
    decision: decisionCode,
    reasonCode,
    repositoryReasonCode:
      REPOSITORY_REASON_CODES[decisionCode] ?? reasonCode,
  });
}

const KNOWN_CONTEXT_FIELDS = Object.freeze([
  "contractVersion",
  "itemId",
  "imageRevision",
  "wardrobeItemRevision",
  "uploadGeneration",
  "generationId",
  "sourceStoragePath",
  "sourceObjectGeneration",
  "sourceObjectMetageneration",
  "sourceImageSha256",
  "sourceUpdatedAt",
  "expectedProfileRevision",
]);

function rejectUnknownFields(raw, allowed, label) {
  for (const key of Object.keys(raw)) {
    if (!allowed.includes(key)) fail(`${label}_unknown_field:${key}`);
  }
}

function rejectForbiddenClientForgery(raw) {
  if (raw.clientAuthority === true || raw.forgedByClient === true) {
    fail("forged_client_revisions_rejected");
  }
}

function requireStoragePath(value, label) {
  const text = requireNonEmpty(value, label);
  if (text.includes("://") || text.includes("\\") || text.includes("..")) {
    fail(`${label}_invalid`);
  }
  if (!text.startsWith("wardrobe/")) {
    fail(`${label}_must_be_wardrobe_source_path`);
  }
  if (text.startsWith("wardrobe_clean/") ||
      text.startsWith("wardrobe_product/")) {
    fail(`${label}_derivative_path_forbidden`);
  }
  return text;
}

function requireGeneration(value, label) {
  const text = requireNonEmpty(value, label);
  if (!/^\d+$/.test(text)) fail(`${label}_invalid`);
  return text;
}

function requireSha256Hex(value, label) {
  const text = requireNonEmpty(value, label).toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(text)) fail(`${label}_invalid`);
  return text;
}

function requireString(value, label) {
  if (typeof value !== "string") fail(`${label}_not_string`);
  return value;
}

function requireNonEmpty(value, label) {
  const text = requireString(value, label).trim();
  if (!text) fail(`${label}_empty`);
  return text;
}

function requirePositiveInt(value, label) {
  if (!Number.isInteger(value) || value <= 0) fail(`${label}_invalid`);
  return value;
}

function requireNonNegativeInt(value, label) {
  if (!Number.isInteger(value) || value < 0) fail(`${label}_invalid`);
  return value;
}

function requireUtc(value, label) {
  const text = requireNonEmpty(value, label);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(text)) {
    fail(`${label}_non_utc_timestamp`);
  }
  if (Number.isNaN(Date.parse(text))) fail(`${label}_invalid_timestamp`);
  return text;
}

function textOrNull(value) {
  if (value == null) return null;
  if (typeof value !== "string") return null;
  return value;
}

function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function deepFreeze(value) {
  if (value == null || typeof value !== "object") return value;
  if (Object.isFrozen(value)) return value;
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  BACKEND_ONLY_FIELDS,
  CLIENT_MAY_SEND,
  CONTRACT_ID,
  CONTRACT_VERSION,
  CONTRACT_VERSION_NUMBER,
  EDIT_CLASSES,
  EDIT_INVALIDATION,
  FORBIDDEN_CLIENT_AUTHORITY_FIELDS,
  GENERATION_ID_PREFIX,
  MIGRATION_CLASSES,
  REPOSITORY_REASON_CODES,
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
};
