"use strict";

/**
 * Offline Wardrobe Revision Lifecycle Mutation Service / v1
 *
 * Pure-ish transactional mutations for qualificationAuthority revision
 * assignment and related lifecycle patches. Injectable store + Storage
 * metadata client. Not wired to production Cloud Function entry points.
 *
 * Does not change qualification/mapper/repository write semantics.
 */

const {
  AUTHORITY_KEY,
  ENVELOPE_KEY,
  createMemoryTransactionalStore,
} = require("./wardrobe_profile_firestore_repository");
const {
  buildRevisionContext,
  classifyLegacyMigration,
  MIGRATION_CLASSES,
} = require("./wardrobe_qualification_revision_contract");
const {
  decodeTrustedSourceObjectSnapshot,
} = require("./trusted_source_object_snapshot");
const {
  fetchTrustedSourceObjectSnapshot,
} = require("./trusted_storage_metadata_adapter");

const SERVICE_ID = "WardrobeRevisionLifecycleMutationService";
const SERVICE_VERSION = "wardrobe-revision-lifecycle-mutation-service-v1";
const REQUEST_CONTRACT = "WardrobeRevisionLifecycleMutationRequest/v1";
const RESULT_CONTRACT = "WardrobeRevisionLifecycleMutationResult/v1";

const MAX_REVISION = Number.MAX_SAFE_INTEGER;

const OPERATION_KINDS = Object.freeze({
  initializeUserPhotoAuthority: "initialize_user_photo_authority",
  applyClassificationMetadataEdit: "apply_classification_metadata_edit",
  applyUserCorrection: "apply_user_correction",
  recordDerivativeCompletion: "record_derivative_completion",
  requestSameImageReanalysis: "request_same_image_reanalysis",
});

const MUTATION_STATUS = Object.freeze({
  mutationApplied: "mutation_applied",
  idempotentNoop: "idempotent_noop",
  itemDeleted: "item_deleted",
  authorityAlreadyInitialized: "authority_already_initialized",
  authorityMissing: "authority_missing",
  sourceMissing: "source_missing",
  sourceMismatch: "source_mismatch",
  productSourceNotSupported: "product_source_not_supported",
  staleItemRevision: "stale_item_revision",
  invalidPatch: "invalid_patch",
  invalidContract: "invalid_contract",
  forbiddenField: "forbidden_field",
  revisionOverflow: "revision_overflow",
  mutationConflict: "mutation_conflict",
  missingStoragePath: "missing_storage_path",
  unknownOperation: "unknown_operation",
});

const CLASSIFICATION_ALLOW_LIST = Object.freeze([
  "name",
  "brand",
  "canonicalType",
  "canonicalFamily",
  "bodySlots",
  "layerPosition",
  "outfitFunctions",
  "uiProjection",
  "accessoryGroup",
  "multiplicity",
  "colorProfile",
  "styles",
  "patterns",
  "seasons",
  "occasionFit",
  "warmth",
  "formality",
  "attributes",
  "setMembership",
  "fieldSources",
  "fieldConfidence",
  "userOverrideFields",
  "analyzerProvenance",
  "ontologyVersion",
  "taxonomyVersion",
  "kbVersion",
  "logo_prominence",
  "fit",
  "occasions",
  "activities",
  "terrain",
  "visual_description",
  "visual_identity",
  "identity_confidence",
  "confidence",
]);

const CLASSIFICATION_FORBIDDEN = Object.freeze([
  "storagePath",
  "cleanImageUrl",
  "cutoutImageUrl",
  "cleanStoragePath",
  "productImageUrl",
  "productStoragePath",
  "originalImageUrl",
  "imageUrl",
  "qualificationAuthority",
  "wardrobeProfile",
  "machineEvidence",
  "mapperProvenance",
  "imageRevision",
  "wardrobeItemRevision",
  "uploadGeneration",
  "generationId",
  "sourceObjectGeneration",
  "processing",
  "imageVersion",
  "wearCount",
  "isSharable",
  "isClean",
  "userCorrections",
]);

const DERIVATIVE_CLEAN_FIELDS = Object.freeze([
  "cleanImageUrl",
  "cutoutImageUrl",
  "cleanStoragePath",
  "cleanUpdatedAt",
  "isClean",
]);

const DERIVATIVE_PRODUCT_FIELDS = Object.freeze([
  "productImageUrl",
  "productStoragePath",
  "productUpdatedAt",
]);

const FORBIDDEN_CLIENT_REVISION_FIELDS = Object.freeze([
  "imageRevision",
  "wardrobeItemRevision",
  "uploadGeneration",
  "generationId",
  "sourceObjectGeneration",
  "currentProfileRevision",
  "expectedProfileRevision",
  "qualificationAuthority",
  "machineEvidence",
  "mapperProvenance",
  "clientAuthority",
  "forgedByClient",
]);

const CORRECTION_PROPERTIES = Object.freeze([
  "family",
  "canonicalType",
  "colors",
  "patterns",
  "styles",
  "fit",
  "warmth",
  "formality",
  "layerRole",
  "mobility",
  "breathability",
  "windProtection",
  "rainProtection",
  "walkingComfort",
  "traction",
  "seasons",
  "occasions",
  "activities",
  "terrain",
]);

const LAZY_MIGRATION_CLASSES = Object.freeze({
  eligibleUserSource: "eligible_user_source",
  productSourceOnly: "product_source_only",
  missingStoragePath: "missing_storage_path",
  missingSourceObject: "missing_source_object",
  alreadyInitialized: "already_initialized",
  conflictingAuthority: "conflicting_authority",
});

/**
 * @param {object} rawRequest
 * @param {{
 *   store: {runTransaction: Function, _get?: Function},
 *   storageMetadataClient?: object,
 *   assignedAt?: string,
 * }} deps
 */
async function applyRevisionLifecycleMutation(rawRequest, deps) {
  if (deps == null || typeof deps !== "object" || deps.store == null) {
    fail("mutation_deps_store_required");
  }
  let request;
  try {
    request = decodeMutationRequest(rawRequest);
  } catch (error) {
    return mutationResult({
      status: MUTATION_STATUS.invalidContract,
      reasonCode: error.message,
      operationKind: isObject(rawRequest) ? rawRequest.operationKind : null,
      itemId: isObject(rawRequest) ? textOrNull(rawRequest.itemId) : null,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    });
  }

  return deps.store.runTransaction(
    request.uid,
    request.itemId,
    async (txState) => await runMutationInsideTransaction(txState, request, deps),
  );
}

async function runMutationInsideTransaction(txState, request, deps) {
  if (!txState.exists) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.itemDeleted,
      reasonCode: "wardrobe_item_not_found",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  const document = structuredClone(txState.data || {});
  switch (request.operationKind) {
  case OPERATION_KINDS.initializeUserPhotoAuthority:
    return await initializeUserPhotoAuthority(document, request, deps);
  case OPERATION_KINDS.applyClassificationMetadataEdit:
    return applyClassificationMetadataEdit(document, request);
  case OPERATION_KINDS.applyUserCorrection:
    return applyUserCorrection(document, request);
  case OPERATION_KINDS.recordDerivativeCompletion:
    return recordDerivativeCompletion(document, request);
  case OPERATION_KINDS.requestSameImageReanalysis:
    return requestSameImageReanalysis(document, request, deps);
  default:
    return noWrite(mutationResult({
      status: MUTATION_STATUS.unknownOperation,
      reasonCode: `unknown_operation:${request.operationKind}`,
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }
}

async function initializeUserPhotoAuthority(document, request, deps) {
  const existing = document[AUTHORITY_KEY];
  if (existing != null) {
    if (isConflictingAuthority(existing)) {
      return noWrite(mutationResult({
        status: MUTATION_STATUS.mutationConflict,
        reasonCode: "conflicting_authority",
        operationKind: request.operationKind,
        itemId: request.itemId,
        previousImageRevision: numberOrNull(existing.imageRevision),
        resultingImageRevision: numberOrNull(existing.imageRevision),
        previousWardrobeItemRevision: numberOrNull(existing.wardrobeItemRevision),
        resultingWardrobeItemRevision: numberOrNull(existing.wardrobeItemRevision),
        generationId: textOrNull(existing.generationId),
        authorityInitialized: true,
        documentPatched: false,
        idempotent: false,
        retryable: false,
      }));
    }
    if (request.idempotencyKey &&
        existing.lastAppliedMutation &&
        existing.lastAppliedMutation.idempotencyKey === request.idempotencyKey) {
      return noWrite(mutationResult({
        status: MUTATION_STATUS.idempotentNoop,
        reasonCode: "identical_initialization_already_applied",
        operationKind: request.operationKind,
        itemId: request.itemId,
        previousImageRevision: existing.imageRevision,
        resultingImageRevision: existing.imageRevision,
        previousWardrobeItemRevision: existing.wardrobeItemRevision,
        resultingWardrobeItemRevision: existing.wardrobeItemRevision,
        generationId: existing.generationId,
        authorityInitialized: true,
        documentPatched: false,
        idempotent: true,
        retryable: false,
      }));
    }
    return noWrite(mutationResult({
      status: MUTATION_STATUS.authorityAlreadyInitialized,
      reasonCode: "authority_already_initialized",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: existing.imageRevision,
      resultingImageRevision: existing.imageRevision,
      previousWardrobeItemRevision: existing.wardrobeItemRevision,
      resultingWardrobeItemRevision: existing.wardrobeItemRevision,
      generationId: existing.generationId,
      authorityInitialized: true,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  const storagePath = textOrNull(document.storagePath);
  const migration = classifyLegacyMigration({
    storagePath,
    productStoragePath: textOrNull(document.productStoragePath),
    cleanStoragePath: textOrNull(document.cleanStoragePath),
    sourceObjectExists: true,
  });
  if (migration.class === MIGRATION_CLASSES.productSourceOnly) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.productSourceNotSupported,
      reasonCode: "product_source_not_supported",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }
  if (migration.class === MIGRATION_CLASSES.missingStoragePath ||
      storagePath == null) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.missingStoragePath,
      reasonCode: "missing_storage_path",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  let snapshot;
  try {
    snapshot = await resolveSourceSnapshot(request, deps, storagePath);
  } catch (error) {
    const code = error && error.message ? error.message : "source_missing";
    if (code === "source_object_missing" || code.includes("source_object_missing")) {
      return noWrite(mutationResult({
        status: MUTATION_STATUS.sourceMissing,
        reasonCode: "source_object_missing",
        operationKind: request.operationKind,
        itemId: request.itemId,
        previousImageRevision: null,
        resultingImageRevision: null,
        previousWardrobeItemRevision: null,
        resultingWardrobeItemRevision: null,
        generationId: null,
        authorityInitialized: false,
        documentPatched: false,
        idempotent: false,
        retryable: false,
      }));
    }
    return noWrite(mutationResult({
      status: MUTATION_STATUS.sourceMismatch,
      reasonCode: code,
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  if (!snapshot.exists || snapshot.generation == null) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.sourceMissing,
      reasonCode: "source_object_missing",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }
  if (snapshot.sourceStoragePath !== storagePath) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.sourceMismatch,
      reasonCode: "path_mismatch",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }
  if (request.expectedUploadGeneration != null &&
      request.expectedUploadGeneration !== snapshot.generation) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.sourceMismatch,
      reasonCode: "generation_mismatch",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  const assignedAt = requireTrustedClock(request.assignedAt, deps.assignedAt);
  let context;
  try {
    context = buildRevisionContext({
      itemId: request.itemId,
      imageRevision: 1,
      wardrobeItemRevision: 1,
      sourceStoragePath: snapshot.sourceStoragePath,
      sourceObjectGeneration: snapshot.generation,
      uploadGeneration: snapshot.generation,
      sourceObjectMetageneration: snapshot.metageneration,
      sourceImageSha256: snapshot.sha256,
      sourceUpdatedAt: assignedAt,
      expectedProfileRevision: null,
    });
  } catch (error) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.invalidContract,
      reasonCode: error.message,
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  const authority = {
    contractVersion: 1,
    imageRevision: context.imageRevision,
    wardrobeItemRevision: context.wardrobeItemRevision,
    uploadGeneration: context.uploadGeneration,
    generationId: context.generationId,
    sourceStoragePath: context.sourceStoragePath,
    sourceObjectGeneration: context.sourceObjectGeneration,
    sourceObjectMetageneration: context.sourceObjectMetageneration,
    sourceImageSha256: context.sourceImageSha256,
    sourceUpdatedAt: context.sourceUpdatedAt,
    assignedAt,
    lastAppliedMutation: request.idempotencyKey == null ? null : {
      idempotencyKey: request.idempotencyKey,
      operationKind: request.operationKind,
      appliedAt: assignedAt,
    },
  };

  return {
    writePatch: {[AUTHORITY_KEY]: authority},
    result: mutationResult({
      status: MUTATION_STATUS.mutationApplied,
      reasonCode: "authority_initialized",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: 1,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: 1,
      generationId: context.generationId,
      authorityInitialized: true,
      documentPatched: true,
      idempotent: false,
      retryable: false,
    }),
  };
}

function applyClassificationMetadataEdit(document, request) {
  const authority = document[AUTHORITY_KEY];
  if (authority == null) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.authorityMissing,
      reasonCode: "authority_missing",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }
  if (isConflictingAuthority(authority)) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.mutationConflict,
      reasonCode: "malformed_current_authority",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: numberOrNull(authority.imageRevision),
      resultingImageRevision: numberOrNull(authority.imageRevision),
      previousWardrobeItemRevision: numberOrNull(authority.wardrobeItemRevision),
      resultingWardrobeItemRevision: numberOrNull(authority.wardrobeItemRevision),
      generationId: textOrNull(authority.generationId),
      authorityInitialized: true,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  if (request.idempotencyKey &&
      authority.lastAppliedMutation &&
      authority.lastAppliedMutation.idempotencyKey === request.idempotencyKey) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.idempotentNoop,
      reasonCode: "identical_mutation_already_applied",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: true,
      retryable: false,
    }));
  }

  if (request.expectedWardrobeItemRevision != null &&
      request.expectedWardrobeItemRevision !== authority.wardrobeItemRevision) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.staleItemRevision,
      reasonCode: "wardrobe_item_revision_mismatch",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: true,
    }));
  }

  const patchCheck = validateClassificationPatch(request.patch);
  if (patchCheck.error) {
    return noWrite(mutationResult({
      status: patchCheck.status,
      reasonCode: patchCheck.error,
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  const nextItemRevision = authority.wardrobeItemRevision + 1;
  if (nextItemRevision > MAX_REVISION) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.revisionOverflow,
      reasonCode: "revision_overflow",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  const assignedAt = requireTrustedClock(request.assignedAt, null);
  const nextAuthority = {
    ...authority,
    wardrobeItemRevision: nextItemRevision,
    lastAppliedMutation: request.idempotencyKey == null ? authority.lastAppliedMutation :
      {
        idempotencyKey: request.idempotencyKey,
        operationKind: request.operationKind,
        appliedAt: assignedAt,
      },
  };

  const writePatch = {
    ...patchCheck.patch,
    [AUTHORITY_KEY]: nextAuthority,
    updatedAt: assignedAt,
  };
  // Preserve wardrobeProfile / userCorrections untouched (not in writePatch).

  return {
    writePatch,
    result: mutationResult({
      status: MUTATION_STATUS.mutationApplied,
      reasonCode: "classification_metadata_edit_applied",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: nextItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: true,
      idempotent: false,
      retryable: false,
      analysisInvalidated: true,
    }),
  };
}

function applyUserCorrection(document, request) {
  const authority = document[AUTHORITY_KEY];
  if (authority == null) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.authorityMissing,
      reasonCode: "authority_missing",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }
  if (isConflictingAuthority(authority)) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.mutationConflict,
      reasonCode: "malformed_current_authority",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: numberOrNull(authority.imageRevision),
      resultingImageRevision: numberOrNull(authority.imageRevision),
      previousWardrobeItemRevision: numberOrNull(authority.wardrobeItemRevision),
      resultingWardrobeItemRevision: numberOrNull(authority.wardrobeItemRevision),
      generationId: textOrNull(authority.generationId),
      authorityInitialized: true,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  if (request.idempotencyKey &&
      authority.lastAppliedMutation &&
      authority.lastAppliedMutation.idempotencyKey === request.idempotencyKey) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.idempotentNoop,
      reasonCode: "identical_mutation_already_applied",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: true,
      retryable: false,
    }));
  }

  if (request.expectedWardrobeItemRevision != null &&
      request.expectedWardrobeItemRevision !== authority.wardrobeItemRevision) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.staleItemRevision,
      reasonCode: "wardrobe_item_revision_mismatch",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: true,
    }));
  }

  const correctionCheck = validateCorrection(request.correction);
  if (correctionCheck.error) {
    return noWrite(mutationResult({
      status: correctionCheck.status,
      reasonCode: correctionCheck.error,
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  const nextItemRevision = authority.wardrobeItemRevision + 1;
  if (nextItemRevision > MAX_REVISION) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.revisionOverflow,
      reasonCode: "revision_overflow",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  if (request.forgedMachineEvidence === true) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.forbiddenField,
      reasonCode: "forbidden_field:machineEvidence",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  const assignedAt = requireTrustedClock(request.assignedAt, null);
  const existingEnvelope = isObject(document[ENVELOPE_KEY]) ?
    structuredClone(document[ENVELOPE_KEY]) : null;

  const envelope = existingEnvelope == null ? {
    metadata: {
      schemaVersion: 1,
      revision: null,
      status: "corrections_only",
    },
    source: {
      imageRevision: authority.imageRevision,
      wardrobeItemRevision: nextItemRevision,
      storagePath: authority.sourceStoragePath,
      uploadGeneration: authority.uploadGeneration,
    },
    analysis: null,
    machineEvidence: [],
    userCorrections: {},
  } : existingEnvelope;

  if (!isObject(envelope.userCorrections)) envelope.userCorrections = {};
  const property = correctionCheck.correction.property;
  envelope.userCorrections[property] = {
    ...correctionCheck.correction,
    correctedAt: assignedAt,
  };
  // Preserve machineEvidence exactly when present.
  if (existingEnvelope != null) {
    envelope.machineEvidence = existingEnvelope.machineEvidence;
    envelope.metadata = existingEnvelope.metadata;
    envelope.analysis = existingEnvelope.analysis;
    envelope.source = {
      ...existingEnvelope.source,
      wardrobeItemRevision: nextItemRevision,
    };
  }

  const nextAuthority = {
    ...authority,
    wardrobeItemRevision: nextItemRevision,
    lastAppliedMutation: request.idempotencyKey == null ? authority.lastAppliedMutation :
      {
        idempotencyKey: request.idempotencyKey,
        operationKind: request.operationKind,
        appliedAt: assignedAt,
        mutationMeta: {
          kind: "user_correction",
          property,
        },
      },
  };

  return {
    writePatch: {
      [AUTHORITY_KEY]: nextAuthority,
      [ENVELOPE_KEY]: envelope,
      updatedAt: assignedAt,
    },
    result: mutationResult({
      status: MUTATION_STATUS.mutationApplied,
      reasonCode: "user_correction_applied",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: nextItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: true,
      idempotent: false,
      retryable: false,
    }),
  };
}

function recordDerivativeCompletion(document, request) {
  const authority = document[AUTHORITY_KEY] ?? null;
  const previousImage = authority ? authority.imageRevision : null;
  const previousItem = authority ? authority.wardrobeItemRevision : null;
  const generationId = authority ? authority.generationId : null;

  const kind = request.derivativeKind;
  if (kind !== "clean" && kind !== "product") {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.invalidPatch,
      reasonCode: "invalid_derivative_kind",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: previousImage,
      resultingImageRevision: previousImage,
      previousWardrobeItemRevision: previousItem,
      resultingWardrobeItemRevision: previousItem,
      generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  const allowed = kind === "clean" ?
    DERIVATIVE_CLEAN_FIELDS : DERIVATIVE_PRODUCT_FIELDS;
  const patch = request.patch || {};
  for (const key of Object.keys(patch)) {
    if (!allowed.includes(key)) {
      if (key === "storagePath" || key === "qualificationAuthority" ||
          key === "wardrobeProfile" || key === "imageRevision" ||
          key === "wardrobeItemRevision") {
        return noWrite(mutationResult({
          status: MUTATION_STATUS.forbiddenField,
          reasonCode: `forbidden_field:${key}`,
          operationKind: request.operationKind,
          itemId: request.itemId,
          previousImageRevision: previousImage,
          resultingImageRevision: previousImage,
          previousWardrobeItemRevision: previousItem,
          resultingWardrobeItemRevision: previousItem,
          generationId,
          authorityInitialized: false,
          documentPatched: false,
          idempotent: false,
          retryable: false,
        }));
      }
      return noWrite(mutationResult({
        status: MUTATION_STATUS.invalidPatch,
        reasonCode: `derivative_field_not_allowed:${key}`,
        operationKind: request.operationKind,
        itemId: request.itemId,
        previousImageRevision: previousImage,
        resultingImageRevision: previousImage,
        previousWardrobeItemRevision: previousItem,
        resultingWardrobeItemRevision: previousItem,
        generationId,
        authorityInitialized: false,
        documentPatched: false,
        idempotent: false,
        retryable: false,
      }));
    }
  }

  const pathField = kind === "clean" ? "cleanStoragePath" : "productStoragePath";
  const storagePath = textOrNull(patch[pathField]);
  if (storagePath != null) {
    const prefix = kind === "clean" ? "wardrobe_clean/" : "wardrobe_product/";
    if (!storagePath.startsWith(prefix) ||
        storagePath.includes("://") ||
        storagePath.includes("..")) {
      return noWrite(mutationResult({
        status: MUTATION_STATUS.invalidPatch,
        reasonCode: "invalid_derivative_namespace",
        operationKind: request.operationKind,
        itemId: request.itemId,
        previousImageRevision: previousImage,
        resultingImageRevision: previousImage,
        previousWardrobeItemRevision: previousItem,
        resultingWardrobeItemRevision: previousItem,
        generationId,
        authorityInitialized: false,
        documentPatched: false,
        idempotent: false,
        retryable: false,
      }));
    }
  }

  const assignedAt = requireTrustedClock(request.assignedAt, null);
  const writePatch = {...patch, updatedAt: assignedAt};
  if (kind === "clean" && Object.prototype.hasOwnProperty.call(patch, "cleanStoragePath")) {
    writePatch.processing = {
      ...(isObject(document.processing) ? document.processing : {}),
      cutout: "done",
    };
  }
  if (kind === "product" &&
      Object.prototype.hasOwnProperty.call(patch, "productStoragePath")) {
    writePatch.processing = {
      ...(isObject(document.processing) ? document.processing : {}),
      product: "done",
    };
  }

  return {
    writePatch,
    result: mutationResult({
      status: MUTATION_STATUS.mutationApplied,
      reasonCode: "derivative_completion_recorded",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: previousImage,
      resultingImageRevision: previousImage,
      previousWardrobeItemRevision: previousItem,
      resultingWardrobeItemRevision: previousItem,
      generationId,
      authorityInitialized: false,
      documentPatched: true,
      idempotent: false,
      retryable: false,
      analysisInvalidated: false,
    }),
  };
}

function requestSameImageReanalysis(document, request, deps) {
  const authority = document[AUTHORITY_KEY];
  if (authority == null) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.authorityMissing,
      reasonCode: "authority_missing",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: null,
      resultingImageRevision: null,
      previousWardrobeItemRevision: null,
      resultingWardrobeItemRevision: null,
      generationId: null,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }
  if (isConflictingAuthority(authority)) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.mutationConflict,
      reasonCode: "malformed_current_authority",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: numberOrNull(authority.imageRevision),
      resultingImageRevision: numberOrNull(authority.imageRevision),
      previousWardrobeItemRevision: numberOrNull(authority.wardrobeItemRevision),
      resultingWardrobeItemRevision: numberOrNull(authority.wardrobeItemRevision),
      generationId: textOrNull(authority.generationId),
      authorityInitialized: true,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    }));
  }

  if (request.expectedImageRevision != null &&
      request.expectedImageRevision !== authority.imageRevision) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.sourceMismatch,
      reasonCode: "image_revision_mismatch",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: true,
    }));
  }
  if (request.expectedWardrobeItemRevision != null &&
      request.expectedWardrobeItemRevision !== authority.wardrobeItemRevision) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.staleItemRevision,
      reasonCode: "wardrobe_item_revision_mismatch",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: true,
    }));
  }

  if (request.expectedUploadGeneration != null &&
      request.expectedUploadGeneration !== authority.uploadGeneration) {
    return noWrite(mutationResult({
      status: MUTATION_STATUS.sourceMismatch,
      reasonCode: "stale_source_snapshot",
      operationKind: request.operationKind,
      itemId: request.itemId,
      previousImageRevision: authority.imageRevision,
      resultingImageRevision: authority.imageRevision,
      previousWardrobeItemRevision: authority.wardrobeItemRevision,
      resultingWardrobeItemRevision: authority.wardrobeItemRevision,
      generationId: authority.generationId,
      authorityInitialized: false,
      documentPatched: false,
      idempotent: false,
      retryable: true,
    }));
  }

  // Optional live binding check via injected Storage client (offline fake).
  if (deps.storageMetadataClient != null) {
    // Sync validation path uses pre-decoded snapshot if provided.
  }
  if (request.sourceObjectSnapshot != null) {
    try {
      const snapshot = decodeTrustedSourceObjectSnapshot(
        request.sourceObjectSnapshot);
      if (!snapshot.exists ||
          snapshot.sourceStoragePath !== authority.sourceStoragePath ||
          snapshot.generation !== authority.uploadGeneration) {
        return noWrite(mutationResult({
          status: MUTATION_STATUS.sourceMismatch,
          reasonCode: "stale_source_snapshot",
          operationKind: request.operationKind,
          itemId: request.itemId,
          previousImageRevision: authority.imageRevision,
          resultingImageRevision: authority.imageRevision,
          previousWardrobeItemRevision: authority.wardrobeItemRevision,
          resultingWardrobeItemRevision: authority.wardrobeItemRevision,
          generationId: authority.generationId,
          authorityInitialized: false,
          documentPatched: false,
          idempotent: false,
          retryable: true,
        }));
      }
    } catch (error) {
      return noWrite(mutationResult({
        status: MUTATION_STATUS.sourceMismatch,
        reasonCode: error.message,
        operationKind: request.operationKind,
        itemId: request.itemId,
        previousImageRevision: authority.imageRevision,
        resultingImageRevision: authority.imageRevision,
        previousWardrobeItemRevision: authority.wardrobeItemRevision,
        resultingWardrobeItemRevision: authority.wardrobeItemRevision,
        generationId: authority.generationId,
        authorityInitialized: false,
        documentPatched: false,
        idempotent: false,
        retryable: false,
      }));
    }
  }

  return noWrite(mutationResult({
    status: MUTATION_STATUS.mutationApplied,
    reasonCode: "same_image_reanalysis_context_ready",
    operationKind: request.operationKind,
    itemId: request.itemId,
    previousImageRevision: authority.imageRevision,
    resultingImageRevision: authority.imageRevision,
    previousWardrobeItemRevision: authority.wardrobeItemRevision,
    resultingWardrobeItemRevision: authority.wardrobeItemRevision,
    generationId: authority.generationId,
    authorityInitialized: false,
    documentPatched: false,
    idempotent: false,
    retryable: false,
    reanalysisContext: Object.freeze({
      imageRevision: authority.imageRevision,
      wardrobeItemRevision: authority.wardrobeItemRevision,
      sourceStoragePath: authority.sourceStoragePath,
      uploadGeneration: authority.uploadGeneration,
      generationId: authority.generationId,
      expectedProfileRevision: currentProfileRevision(document),
    }),
  }));
}

/**
 * Lazy-migration classification reused by initialize path.
 */
function classifyLazyMigrationCandidate(document, sourceObjectExists) {
  if (document[AUTHORITY_KEY] != null) {
    if (isConflictingAuthority(document[AUTHORITY_KEY])) {
      return deepFreeze({
        class: LAZY_MIGRATION_CLASSES.conflictingAuthority,
        initializeAllowed: false,
      });
    }
    return deepFreeze({
      class: LAZY_MIGRATION_CLASSES.alreadyInitialized,
      initializeAllowed: false,
    });
  }
  const migration = classifyLegacyMigration({
    storagePath: textOrNull(document.storagePath),
    productStoragePath: textOrNull(document.productStoragePath),
    cleanStoragePath: textOrNull(document.cleanStoragePath),
    sourceObjectExists: sourceObjectExists !== false,
  });
  if (migration.class === MIGRATION_CLASSES.productSourceOnly) {
    return deepFreeze({
      class: LAZY_MIGRATION_CLASSES.productSourceOnly,
      initializeAllowed: false,
    });
  }
  if (migration.class === MIGRATION_CLASSES.missingStoragePath) {
    return deepFreeze({
      class: LAZY_MIGRATION_CLASSES.missingStoragePath,
      initializeAllowed: false,
    });
  }
  if (migration.class === MIGRATION_CLASSES.sourceObjectMissing ||
      sourceObjectExists === false) {
    return deepFreeze({
      class: LAZY_MIGRATION_CLASSES.missingSourceObject,
      initializeAllowed: false,
    });
  }
  return deepFreeze({
    class: LAZY_MIGRATION_CLASSES.eligibleUserSource,
    initializeAllowed: true,
    operationKind: OPERATION_KINDS.initializeUserPhotoAuthority,
  });
}

async function resolveSourceSnapshot(request, deps, storagePath) {
  if (request.sourceObjectSnapshot != null) {
    // Trusted backend may inject already-fetched snapshot (tests / future endpoint).
    return decodeTrustedSourceObjectSnapshot(request.sourceObjectSnapshot);
  }
  if (deps.storageMetadataClient == null) {
    fail("storage_metadata_client_required");
  }
  return fetchTrustedSourceObjectSnapshot({
    uid: request.uid,
    itemId: request.itemId,
    sourceStoragePath: storagePath,
    storageMetadataClient: deps.storageMetadataClient,
  });
}

function decodeMutationRequest(raw) {
  if (!isObject(raw)) fail("mutation_request_not_object");
  if (raw.contractVersion !== 1) fail("mutation_request_contract_unsupported");
  for (const field of FORBIDDEN_CLIENT_REVISION_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(raw, field)) {
      fail(`forged_client_revisions_rejected:${field}`);
    }
  }
  if (raw.trustedActorContext == null ||
      typeof raw.trustedActorContext !== "object" ||
      Array.isArray(raw.trustedActorContext)) {
    fail("trusted_actor_context_required");
  }
  const uid = requireNonEmpty(
    raw.trustedActorContext.uid ?? raw.uid, "uid");
  if (raw.uid != null && raw.uid !== uid) fail("uid_actor_mismatch");
  const itemId = requireNonEmpty(raw.itemId, "itemId");
  const operationKind = requireNonEmpty(raw.operationKind, "operationKind");
  if (!Object.values(OPERATION_KINDS).includes(operationKind)) {
    fail(`unknown_operation:${operationKind}`);
  }
  const assignedAt = raw.assignedAt == null ? null :
    requireUtc(raw.assignedAt, "assignedAt");
  const idempotencyKey = raw.idempotencyKey == null ? null :
    requireNonEmpty(raw.idempotencyKey, "idempotencyKey");

  return Object.freeze({
    contractVersion: 1,
    requestContract: REQUEST_CONTRACT,
    operationKind,
    uid,
    itemId,
    assignedAt,
    idempotencyKey,
    expectedWardrobeItemRevision: raw.expectedWardrobeItemRevision == null ?
      null : requireNonNegativeInt(raw.expectedWardrobeItemRevision,
        "expectedWardrobeItemRevision"),
    expectedImageRevision: raw.expectedImageRevision == null ? null :
      requireNonNegativeInt(raw.expectedImageRevision, "expectedImageRevision"),
    expectedUploadGeneration: raw.expectedUploadGeneration == null ? null :
      requireGeneration(raw.expectedUploadGeneration, "expectedUploadGeneration"),
    patch: raw.patch == null ? null : requireObject(raw.patch, "patch"),
    correction: raw.correction == null ? null :
      requireObject(raw.correction, "correction"),
    derivativeKind: raw.derivativeKind == null ? null :
      requireNonEmpty(raw.derivativeKind, "derivativeKind"),
    sourceObjectSnapshot: raw.sourceObjectSnapshot ?? null,
    forgedMachineEvidence: raw.forgedMachineEvidence === true,
    trustedActorContext: Object.freeze({
      uid,
      authType: requireNonEmpty(
        raw.trustedActorContext.authType || "backend_admin", "authType"),
    }),
  });
}

function validateClassificationPatch(patch) {
  if (!isObject(patch) || Object.keys(patch).length === 0) {
    return {error: "classification_patch_empty", status: MUTATION_STATUS.invalidPatch};
  }
  const cleaned = {};
  for (const key of Object.keys(patch)) {
    if (CLASSIFICATION_FORBIDDEN.includes(key)) {
      return {
        error: `forbidden_field:${key}`,
        status: MUTATION_STATUS.forbiddenField,
      };
    }
    if (!CLASSIFICATION_ALLOW_LIST.includes(key)) {
      return {
        error: `unrelated_field:${key}`,
        status: MUTATION_STATUS.invalidPatch,
      };
    }
    cleaned[key] = patch[key];
  }
  return {patch: cleaned};
}

function validateCorrection(correction) {
  if (!isObject(correction)) {
    return {error: "correction_not_object", status: MUTATION_STATUS.invalidPatch};
  }
  for (const key of Object.keys(correction)) {
    if (["machineEvidence", "mapperProvenance", "qualificationAuthority",
      "imageRevision", "wardrobeItemRevision", "metadata"].includes(key)) {
      return {
        error: `forbidden_field:${key}`,
        status: MUTATION_STATUS.forbiddenField,
      };
    }
  }
  const property = requireNonEmpty(correction.property, "correction.property");
  if (!CORRECTION_PROPERTIES.includes(property)) {
    return {
      error: `correction_property_not_allowed:${property}`,
      status: MUTATION_STATUS.invalidPatch,
    };
  }
  const action = requireNonEmpty(correction.action, "correction.action");
  if (!["set", "cleared", "rejected"].includes(action)) {
    return {
      error: "correction_action_invalid",
      status: MUTATION_STATUS.invalidPatch,
    };
  }
  const id = requireNonEmpty(correction.id, "correction.id");
  const method = requireNonEmpty(correction.method, "correction.method");
  return {
    correction: {
      id,
      property,
      action,
      value: action === "set" ? correction.value : null,
      rejectedValue: action === "rejected" ? correction.rejectedValue : null,
      method,
    },
  };
}

function isConflictingAuthority(authority) {
  if (!isObject(authority)) return true;
  if (authority.contractVersion !== 1) return true;
  if (!Number.isInteger(authority.imageRevision) ||
      !Number.isInteger(authority.wardrobeItemRevision)) {
    return true;
  }
  if (typeof authority.uploadGeneration !== "string" ||
      !/^\d+$/.test(authority.uploadGeneration)) {
    return true;
  }
  if (typeof authority.sourceStoragePath !== "string" ||
      !authority.sourceStoragePath.startsWith("wardrobe/")) {
    return true;
  }
  if (typeof authority.generationId !== "string" ||
      !authority.generationId.startsWith("wqrev:v1:")) {
    return true;
  }
  return false;
}

function currentProfileRevision(document) {
  const envelope = document[ENVELOPE_KEY];
  if (!isObject(envelope) || !isObject(envelope.metadata)) return null;
  const revision = envelope.metadata.revision;
  return Number.isInteger(revision) ? revision : null;
}

function mutationResult(fields) {
  const result = {
    contractVersion: 1,
    resultContract: RESULT_CONTRACT,
    status: fields.status,
    reasonCode: fields.reasonCode,
    operationKind: fields.operationKind ?? null,
    itemId: fields.itemId ?? null,
    previousImageRevision: fields.previousImageRevision ?? null,
    resultingImageRevision: fields.resultingImageRevision ?? null,
    previousWardrobeItemRevision: fields.previousWardrobeItemRevision ?? null,
    resultingWardrobeItemRevision: fields.resultingWardrobeItemRevision ?? null,
    generationId: fields.generationId ?? null,
    authorityInitialized: fields.authorityInitialized === true,
    documentPatched: fields.documentPatched === true,
    idempotent: fields.idempotent === true,
    retryable: fields.retryable === true,
  };
  if (fields.analysisInvalidated != null) {
    result.analysisInvalidated = fields.analysisInvalidated === true;
  }
  if (fields.reanalysisContext != null) {
    result.reanalysisContext = fields.reanalysisContext;
  }
  return deepFreeze(result);
}

function noWrite(result) {
  return {writePatch: null, result};
}

function requireTrustedClock(requestClock, depsClock) {
  const value = requestClock ?? depsClock;
  if (value == null) fail("trusted_clock_required");
  return requireUtc(value, "assignedAt");
}

function requireGeneration(value, label) {
  const text = requireNonEmpty(value, label);
  if (!/^\d+$/.test(text)) fail(`${label}_invalid`);
  return text;
}

function requireUtc(value, label) {
  const text = requireNonEmpty(value, label);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(text)) {
    fail(`${label}_non_utc_timestamp`);
  }
  return text;
}

function requireNonEmpty(value, label) {
  if (typeof value !== "string" || !value.trim()) fail(`${label}_empty`);
  return value.trim();
}

function requireNonNegativeInt(value, label) {
  if (!Number.isInteger(value) || value < 0) fail(`${label}_invalid`);
  return value;
}

function requireObject(value, label) {
  if (!isObject(value)) fail(`${label}_not_object`);
  return value;
}

function textOrNull(value) {
  if (value == null) return null;
  if (typeof value !== "string") return null;
  const text = value.trim();
  return text || null;
}

function numberOrNull(value) {
  return Number.isInteger(value) ? value : null;
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
  AUTHORITY_KEY,
  CLASSIFICATION_ALLOW_LIST,
  CLASSIFICATION_FORBIDDEN,
  CORRECTION_PROPERTIES,
  ENVELOPE_KEY,
  FORBIDDEN_CLIENT_REVISION_FIELDS,
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
  decodeMutationRequest,
};
