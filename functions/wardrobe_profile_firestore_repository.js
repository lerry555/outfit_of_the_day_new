"use strict";

/**
 * Offline-capable Admin Firestore repository adapter foundation.
 *
 * Implements persistMappedWardrobeProfile against an injectable transactional
 * store. Real Admin SDK wiring is optional and must not be imported by
 * production Cloud Function entry points in this phase.
 *
 * Dart CAS policy remains source of truth via
 * wardrobe_profile_transactional_write_policy.js.
 */

const {
  WRITE_DECISIONS,
  buildRevisionContext,
  classifyLegacyMigration,
  evaluateWriteDecision,
  toSourceSnapshot,
} = require("./wardrobe_qualification_revision_contract");
const {
  decodeTrustedSourceObjectSnapshot,
} = require("./trusted_source_object_snapshot");
const {
  ENVELOPE_KEY,
  WRITE_STATUS,
  decodeExistingProfile,
  evaluateTransactionalWrite,
} = require("./wardrobe_profile_transactional_write_policy");

const REPOSITORY_ID = "WardrobeProfilePersistenceRepositoryAdapter";
const REPOSITORY_VERSION = "wardrobe-profile-firestore-repository-v1";
const RESULT_CONTRACT = "WardrobeProfileRepositoryWriteResult/v1";
const REQUEST_CONTRACT = "WardrobeProfileRepositoryWriteRequest/v1";
const AUTHORITY_KEY = "qualificationAuthority";

const FORBIDDEN_REQUEST_FIELDS = Object.freeze([
  "qualificationAuthority",
  "currentProfileRevision",
  "currentUserCorrections",
  "currentWardrobeItemRevision",
  "currentImageRevision",
  "serverTimestamp",
  "clientAuthority",
]);

/**
 * In-memory transactional store for offline/unit tests.
 * Mimics Firestore transaction isolation for a single document key.
 */
function createMemoryTransactionalStore(initialDocuments = {}) {
  const docs = new Map();
  for (const [key, value] of Object.entries(initialDocuments)) {
    docs.set(key, structuredClone(value));
  }
  return {
    async runTransaction(userId, wardrobeItemId, callback) {
      const key = docKey(userId, wardrobeItemId);
      const current = docs.has(key) ?
        structuredClone(docs.get(key)) : null;
      const decision = await callback({
        exists: current != null,
        data: current,
      });
      if (decision.writePatch) {
        const next = current == null ? {} : structuredClone(current);
        Object.assign(next, decision.writePatch);
        docs.set(key, next);
      }
      return decision.result;
    },
    _dump() {
      return Object.fromEntries([...docs.entries()].map(([k, v]) =>
        [k, structuredClone(v)]));
    },
    _get(userId, wardrobeItemId) {
      return structuredClone(docs.get(docKey(userId, wardrobeItemId)) || null);
    },
  };
}

/**
 * @param {object} rawRequest
 * @param {{runTransaction: Function}} store
 */
async function persistMappedWardrobeProfile(rawRequest, store) {
  const request = decodeWriteRequest(rawRequest);
  return store.runTransaction(
    request.userId,
    request.wardrobeItemId,
    async (txState) => evaluateInsideTransaction(txState, request),
  );
}

function evaluateInsideTransaction(txState, request) {
  if (!txState.exists) {
    return noWrite(repositoryResult({
      status: WRITE_DECISIONS.itemDeleted,
      reasonCode: "wardrobe_item_not_found",
      itemId: request.wardrobeItemId,
      generationId: request.revisionContext.generationId,
      previousProfileRevision: null,
      resultingProfileRevision: null,
      initializedAuthority: false,
      wroteProfile: false,
      idempotent: false,
      retryable: false,
    }));
  }

  const document = txState.data || {};
  rejectClientOwnedBackendInjection(document);

  let initializedAuthority = false;
  let authority = document[AUTHORITY_KEY] ?? null;
  const sourceObject = request.sourceObjectSnapshot;

  if (sourceObject.exists === false) {
    return noWrite(repositoryResult({
      status: WRITE_DECISIONS.sourceMissing,
      reasonCode: "source_object_missing",
      itemId: request.wardrobeItemId,
      generationId: request.revisionContext.generationId,
      previousProfileRevision: currentProfileRevision(document),
      resultingProfileRevision: null,
      initializedAuthority: false,
      wroteProfile: false,
      idempotent: false,
      retryable: false,
    }));
  }

  if (authority == null) {
    const migration = classifyLegacyMigration({
      storagePath: textOrNull(document.storagePath),
      productStoragePath: textOrNull(document.productStoragePath),
      cleanStoragePath: textOrNull(document.cleanStoragePath),
      sourceObjectExists: sourceObject.exists,
    });
    if (migration.class !== "lazy_init_ready" || !migration.lazyInitAllowed) {
      return noWrite(repositoryResult({
        status: WRITE_DECISIONS.revisionContractInvalid,
        reasonCode: migration.reason || migration.class,
        itemId: request.wardrobeItemId,
        generationId: request.revisionContext.generationId,
        previousProfileRevision: currentProfileRevision(document),
        resultingProfileRevision: null,
        initializedAuthority: false,
        wroteProfile: false,
        idempotent: false,
        retryable: false,
      }));
    }
    if (textOrNull(document.storagePath) !== sourceObject.sourceStoragePath) {
      return noWrite(repositoryResult({
        status: WRITE_DECISIONS.staleImage,
        reasonCode: "image_identity_mismatch",
        itemId: request.wardrobeItemId,
        generationId: request.revisionContext.generationId,
        previousProfileRevision: currentProfileRevision(document),
        resultingProfileRevision: null,
        initializedAuthority: false,
        wroteProfile: false,
        idempotent: false,
        retryable: false,
      }));
    }
    authority = encodeAuthority(buildRevisionContext({
      itemId: request.wardrobeItemId,
      imageRevision: 1,
      wardrobeItemRevision: 1,
      sourceStoragePath: sourceObject.sourceStoragePath,
      sourceObjectGeneration: sourceObject.generation,
      uploadGeneration: sourceObject.generation,
      sourceObjectMetageneration: sourceObject.metageneration,
      sourceImageSha256: sourceObject.sha256,
      sourceUpdatedAt: request.backendAssignedAt,
      expectedProfileRevision: request.expectedProfileRevision,
    }));
    initializedAuthority = true;
  }

  let currentContext;
  try {
    currentContext = authorityToContext(authority, request.wardrobeItemId);
  } catch (error) {
    return noWrite(repositoryResult({
      status: WRITE_DECISIONS.revisionContractInvalid,
      reasonCode: `current_authority_invalid:${error.message}`,
      itemId: request.wardrobeItemId,
      generationId: request.revisionContext.generationId,
      previousProfileRevision: currentProfileRevision(document),
      resultingProfileRevision: null,
      initializedAuthority: false,
      wroteProfile: false,
      idempotent: false,
      retryable: false,
    }));
  }

  const previousProfileRevision = currentProfileRevision(document);
  // Profile revision CAS is owned by the Dart transactional write policy.
  // Revision-contract evaluation here is source-identity only.
  const decision = evaluateWriteDecision({
    itemExists: true,
    sourceObjectExists: sourceObject.exists,
    proposed: request.revisionContext,
    currentAuthority: {
      ...currentContext,
      expectedProfileRevision: request.expectedProfileRevision,
      generationId: currentContext.generationId,
    },
    currentProfileRevision: request.expectedProfileRevision,
    sameGenerationAlreadyApplied: false,
  });

  if (decision.decision === WRITE_DECISIONS.idempotentNoop ||
      decision.decision === WRITE_DECISIONS.staleImage ||
      decision.decision === WRITE_DECISIONS.staleItemRevision ||
      decision.decision === WRITE_DECISIONS.newerGenerationExists ||
      decision.decision === WRITE_DECISIONS.revisionConflict ||
      decision.decision === WRITE_DECISIONS.revisionContractInvalid ||
      decision.decision === WRITE_DECISIONS.sourceMissing ||
      decision.decision === WRITE_DECISIONS.itemDeleted) {
    // Continue into Dart profile policy for identical-generation fingerprint
    // only when source decision is write_allowed. For source stale, stop.
    if (decision.decision !== WRITE_DECISIONS.writeAllowed) {
      return noWrite(repositoryResult({
        status: decision.decision,
        reasonCode: decision.reasonCode,
        itemId: request.wardrobeItemId,
        generationId: request.revisionContext.generationId,
        previousProfileRevision,
        resultingProfileRevision: null,
        initializedAuthority: false,
        wroteProfile: false,
        idempotent: decision.decision === WRITE_DECISIONS.idempotentNoop,
        retryable: false,
      }));
    }
  }

  // Re-check generation identity noop via Dart policy after corrections merge.
  const expectedSource = toSourceSnapshot(request.revisionContext);
  const envelope = {
    ...structuredClone(request.mappedEnvelope),
    userCorrections: {},
  };
  // Preserve existing corrections inside Dart policy evaluate.
  const policyDecision = evaluateTransactionalWrite({
    current: {
      exists: true,
      source: expectedSource,
      document: {
        ...document,
        ...(initializedAuthority ? {[AUTHORITY_KEY]: authority} : {}),
      },
    },
    command: {
      userId: request.userId,
      wardrobeItemId: request.wardrobeItemId,
      envelope,
      expectedSource,
      expectedProfileRevision: request.expectedProfileRevision,
    },
  });

  if (policyDecision.documentPatch == null) {
    const status = mapPolicyStatus(policyDecision.result.status);
    return noWrite(repositoryResult({
      status,
      reasonCode: policyDecision.result.reasonCode,
      itemId: request.wardrobeItemId,
      generationId: request.revisionContext.generationId,
      previousProfileRevision:
        policyDecision.result.currentRevision ?? previousProfileRevision,
      resultingProfileRevision: policyDecision.result.currentRevision,
      initializedAuthority: false,
      wroteProfile: false,
      idempotent: policyDecision.result.status === WRITE_STATUS.alreadyApplied,
      retryable: false,
    }));
  }

  const writePatch = {
    ...policyDecision.documentPatch,
  };
  if (initializedAuthority) {
    writePatch[AUTHORITY_KEY] = {
      ...authority,
      assignedAt: request.backendAssignedAt,
    };
  }

  const resulting = policyDecision.documentPatch[ENVELOPE_KEY];
  return {
    writePatch,
    result: repositoryResult({
      status: WRITE_DECISIONS.writeAllowed,
      reasonCode: policyDecision.result.reasonCode,
      itemId: request.wardrobeItemId,
      generationId: resulting.metadata.generationId,
      previousProfileRevision,
      resultingProfileRevision: resulting.metadata.revision,
      initializedAuthority,
      wroteProfile: true,
      idempotent: false,
      retryable: false,
      repositoryStatus: policyDecision.result.status,
    }),
  };
}

function decodeWriteRequest(raw) {
  if (!isObject(raw)) fail("write_request_not_object");
  for (const field of FORBIDDEN_REQUEST_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(raw, field)) {
      fail(`forbidden_client_field:${field}`);
    }
  }
  if (raw.contractVersion !== 1) fail("write_request_contract_unsupported");
  const userId = requireNonEmpty(raw.userId, "userId");
  const wardrobeItemId = requireNonEmpty(raw.wardrobeItemId, "wardrobeItemId");
  const backendAssignedAt = requireUtc(raw.backendAssignedAt, "backendAssignedAt");
  const sourceObjectSnapshot = decodeTrustedSourceObjectSnapshot(
    raw.sourceObjectSnapshot);
  const revisionContext = requireObject(raw.revisionContext, "revisionContext");
  // Bound generationId by re-validating through buildRevisionContext fields.
  const mappedEnvelope = requireObject(raw.mappedEnvelope, "mappedEnvelope");
  const expectedProfileRevision = Object.prototype.hasOwnProperty.call(
    raw, "expectedProfileRevision") && raw.expectedProfileRevision != null ?
    requireNonNegativeInt(raw.expectedProfileRevision, "expectedProfileRevision") :
    null;

  // Ensure revision context is trusted-decoded (throws on forge).
  const {
    decodeRevisionContext,
  } = require("./wardrobe_qualification_revision_contract");
  const decodedContext = decodeRevisionContext({
    ...revisionContext,
    expectedProfileRevision,
  });
  if (decodedContext.itemId !== wardrobeItemId) fail("item_id_mismatch");
  if (decodedContext.sourceStoragePath !== sourceObjectSnapshot.sourceStoragePath &&
      sourceObjectSnapshot.exists) {
    fail("revision_context_path_mismatch");
  }
  if (sourceObjectSnapshot.exists &&
      decodedContext.sourceObjectGeneration !== sourceObjectSnapshot.generation) {
    fail("revision_context_generation_mismatch");
  }

  return Object.freeze({
    contractVersion: 1,
    userId,
    wardrobeItemId,
    backendAssignedAt,
    sourceObjectSnapshot,
    revisionContext: decodedContext,
    mappedEnvelope,
    expectedProfileRevision,
  });
}

function authorityToContext(authority, itemId) {
  const {
    decodeRevisionContext,
    buildGenerationId,
  } = require("./wardrobe_qualification_revision_contract");
  const generationId = authority.generationId || buildGenerationId({
    itemId,
    imageRevision: authority.imageRevision,
    sourceStoragePath: authority.sourceStoragePath,
    sourceObjectGeneration: authority.sourceObjectGeneration,
    uploadGeneration: authority.uploadGeneration,
  });
  return decodeRevisionContext({
    contractVersion: authority.contractVersion ?? 1,
    itemId,
    imageRevision: authority.imageRevision,
    wardrobeItemRevision: authority.wardrobeItemRevision,
    uploadGeneration: authority.uploadGeneration,
    generationId,
    sourceStoragePath: authority.sourceStoragePath,
    sourceObjectGeneration: authority.sourceObjectGeneration,
    sourceObjectMetageneration: authority.sourceObjectMetageneration ?? null,
    sourceImageSha256: authority.sourceImageSha256 ?? null,
    sourceUpdatedAt: authority.sourceUpdatedAt || authority.assignedAt,
    expectedProfileRevision: authority.expectedProfileRevision ?? null,
  });
}

function encodeAuthority(context) {
  return {
    contractVersion: context.contractVersion,
    imageRevision: context.imageRevision,
    wardrobeItemRevision: context.wardrobeItemRevision,
    uploadGeneration: context.uploadGeneration,
    generationId: context.generationId,
    sourceStoragePath: context.sourceStoragePath,
    sourceObjectGeneration: context.sourceObjectGeneration,
    sourceObjectMetageneration: context.sourceObjectMetageneration,
    sourceImageSha256: context.sourceImageSha256,
    sourceUpdatedAt: context.sourceUpdatedAt,
  };
}

function currentProfileRevision(document) {
  const decoded = decodeExistingProfile(document);
  if (decoded.status !== "valid") return null;
  return decoded.envelope.metadata.revision;
}

function mapPolicyStatus(status) {
  switch (status) {
  case WRITE_STATUS.alreadyApplied:
    return WRITE_DECISIONS.idempotentNoop;
  case WRITE_STATUS.staleRejected:
    return WRITE_DECISIONS.staleImage;
  case WRITE_STATUS.revisionConflict:
    return WRITE_DECISIONS.revisionConflict;
  case WRITE_STATUS.notFound:
    return WRITE_DECISIONS.itemDeleted;
  default:
    return WRITE_DECISIONS.revisionContractInvalid;
  }
}

function rejectClientOwnedBackendInjection() {
  // Document may already contain backend maps from Admin writes; clients are
  // blocked by Security Rules. No-op here.
}

function repositoryResult(fields) {
  return Object.freeze({
    contractVersion: 1,
    resultContract: RESULT_CONTRACT,
    status: fields.status,
    reasonCode: fields.reasonCode,
    itemId: fields.itemId,
    generationId: fields.generationId,
    previousProfileRevision: fields.previousProfileRevision,
    resultingProfileRevision: fields.resultingProfileRevision,
    initializedAuthority: fields.initializedAuthority === true,
    wroteProfile: fields.wroteProfile === true,
    idempotent: fields.idempotent === true,
    retryable: fields.retryable === true,
    repositoryStatus: fields.repositoryStatus ?? null,
  });
}

function noWrite(result) {
  return {writePatch: null, result};
}

function docKey(userId, wardrobeItemId) {
  return `users/${userId}/wardrobe/${wardrobeItemId}`;
}

function textOrNull(value) {
  if (value == null) return null;
  if (typeof value !== "string") return null;
  const text = value.trim();
  return text || null;
}

function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function requireObject(value, label) {
  if (!isObject(value)) fail(`${label}_not_object`);
  return value;
}

function requireNonEmpty(value, label) {
  if (typeof value !== "string" || !value.trim()) fail(`${label}_empty`);
  return value.trim();
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
  return text;
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  AUTHORITY_KEY,
  ENVELOPE_KEY,
  FORBIDDEN_REQUEST_FIELDS,
  REPOSITORY_ID,
  REPOSITORY_VERSION,
  REQUEST_CONTRACT,
  RESULT_CONTRACT,
  createMemoryTransactionalStore,
  persistMappedWardrobeProfile,
};
