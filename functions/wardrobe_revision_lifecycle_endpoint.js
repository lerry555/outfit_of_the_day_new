"use strict";

/**
 * Offline Wardrobe Revision Lifecycle Endpoint boundary / v1
 *
 * Not exported from production Functions entry points.
 */

const {
  AUTH_STATUSES,
  assertPayloadAuthOwnership,
  decodeTrustedFirebaseAuthContext,
} = require("./trusted_firebase_auth_context");
const {
  OPERATION_KINDS,
  applyRevisionLifecycleMutation,
  createMemoryTransactionalStore,
} = require("./wardrobe_revision_lifecycle_mutation_service");
const {
  createFakeStorageMetadataClient,
} = require("./trusted_storage_metadata_adapter");

const ENDPOINT_ID = "WardrobeRevisionLifecycleEndpoint";
const ENDPOINT_VERSION = "wardrobe-revision-lifecycle-endpoint-v1";
const REQUEST_CONTRACT = "WardrobeRevisionLifecycleEndpointRequest/v1";
const RESULT_CONTRACT = "WardrobeRevisionLifecycleEndpointResult/v1";

const ALLOWED_OPERATIONS = Object.freeze(Object.values(OPERATION_KINDS));

/**
 * @param {object} rawRequest
 * @param {{
 *   authContext: object,
 *   store: object,
 *   storageMetadataClient?: object,
 *   assignedAt?: string,
 * }} deps
 */
async function handleRevisionLifecycleEndpoint(rawRequest, deps) {
  const auth = decodeTrustedFirebaseAuthContext(deps && deps.authContext);
  if (auth.status !== AUTH_STATUSES.authenticated) {
    return endpointResult({
      status: auth.status === AUTH_STATUSES.forbidden ? "forbidden" :
        "unauthenticated",
      reasonCode: auth.reasonCode,
      operationKind: null,
      itemId: null,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    });
  }

  let uid;
  try {
    uid = assertPayloadAuthOwnership(rawRequest, auth);
  } catch (error) {
    return endpointResult({
      status: "forbidden",
      reasonCode: error.message,
      operationKind: null,
      itemId: null,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    });
  }

  if (rawRequest == null || typeof rawRequest !== "object" ||
      Array.isArray(rawRequest)) {
    return endpointResult({
      status: "invalid_contract",
      reasonCode: "request_not_object",
      operationKind: null,
      itemId: null,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    });
  }
  if (rawRequest.contractVersion !== 1) {
    return endpointResult({
      status: "invalid_contract",
      reasonCode: "request_contract_unsupported",
      operationKind: null,
      itemId: null,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    });
  }

  const operationKind = rawRequest.operationKind;
  if (!ALLOWED_OPERATIONS.includes(operationKind)) {
    return endpointResult({
      status: "invalid_contract",
      reasonCode: `unknown_operation:${operationKind}`,
      operationKind: operationKind || null,
      itemId: rawRequest.itemId || null,
      documentPatched: false,
      idempotent: false,
      retryable: false,
    });
  }

  const mutationRequest = {
    contractVersion: 1,
    operationKind,
    itemId: rawRequest.itemId,
    assignedAt: rawRequest.assignedAt || deps.assignedAt,
    idempotencyKey: rawRequest.idempotencyKey,
    expectedWardrobeItemRevision: rawRequest.expectedWardrobeItemRevision,
    expectedImageRevision: rawRequest.expectedImageRevision,
    expectedUploadGeneration: rawRequest.expectedUploadGeneration,
    patch: rawRequest.patch,
    correction: rawRequest.correction,
    derivativeKind: rawRequest.derivativeKind,
    sourceObjectSnapshot: rawRequest.sourceObjectSnapshot,
    trustedActorContext: {
      uid,
      authType: auth.authType || "firebase_auth",
    },
  };

  const result = await applyRevisionLifecycleMutation(mutationRequest, {
    store: deps.store,
    storageMetadataClient: deps.storageMetadataClient ||
      createFakeStorageMetadataClient({}),
    assignedAt: deps.assignedAt,
  });

  return endpointResult({
    status: result.status,
    reasonCode: result.reasonCode,
    operationKind: result.operationKind,
    itemId: result.itemId,
    generationId: result.generationId,
    previousImageRevision: result.previousImageRevision,
    resultingImageRevision: result.resultingImageRevision,
    previousWardrobeItemRevision: result.previousWardrobeItemRevision,
    resultingWardrobeItemRevision: result.resultingWardrobeItemRevision,
    authorityInitialized: result.authorityInitialized,
    documentPatched: result.documentPatched,
    idempotent: result.idempotent,
    retryable: result.retryable,
  });
}

function endpointResult(fields) {
  return Object.freeze({
    contractVersion: 1,
    resultContract: RESULT_CONTRACT,
    endpointId: ENDPOINT_ID,
    endpointVersion: ENDPOINT_VERSION,
    status: fields.status,
    reasonCode: fields.reasonCode,
    operationKind: fields.operationKind ?? null,
    itemId: fields.itemId ?? null,
    generationId: fields.generationId ?? null,
    previousImageRevision: fields.previousImageRevision ?? null,
    resultingImageRevision: fields.resultingImageRevision ?? null,
    previousWardrobeItemRevision: fields.previousWardrobeItemRevision ?? null,
    resultingWardrobeItemRevision: fields.resultingWardrobeItemRevision ?? null,
    authorityInitialized: fields.authorityInitialized === true,
    documentPatched: fields.documentPatched === true,
    idempotent: fields.idempotent === true,
    retryable: fields.retryable === true,
  });
}

module.exports = {
  ALLOWED_OPERATIONS,
  ENDPOINT_ID,
  ENDPOINT_VERSION,
  REQUEST_CONTRACT,
  RESULT_CONTRACT,
  createMemoryTransactionalStore,
  handleRevisionLifecycleEndpoint,
};
