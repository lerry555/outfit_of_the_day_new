"use strict";

/**
 * Offline Wardrobe Qualification Authority Endpoint boundary / v1
 *
 * Wires auth → Storage adapter → lifecycle lazy init → fake Vision →
 * offline orchestrator → mapper → repository. Not exported from production
 * Functions entry points. No live OpenAI / Firestore / Storage I/O.
 */

const {
  AUTH_STATUSES,
  assertPayloadAuthOwnership,
  decodeTrustedFirebaseAuthContext,
} = require("./trusted_firebase_auth_context");
const {
  AUTHORITY_KEY,
  ENVELOPE_KEY,
  createMemoryTransactionalStore,
  persistMappedWardrobeProfile,
} = require("./wardrobe_profile_firestore_repository");
const {
  classifyLazyMigrationCandidate,
  LAZY_MIGRATION_CLASSES,
} = require("./wardrobe_revision_lifecycle_mutation_service");
const {
  fetchTrustedSourceObjectSnapshot,
} = require("./trusted_storage_metadata_adapter");
const {
  buildRevisionContext,
} = require("./wardrobe_qualification_revision_contract");
const {
} = require("./trusted_vision_analysis_client");
const {allocateServerAnalysisIdentity, sourceGenerationFingerprint} =
  require("./server_analysis_identity");
const {buildTrustedVisionQualificationInput} =
  require("./trusted_vision_qualification_input");
const {runLiveParserBackendQualification} =
  require("./live_parser_backend_qualification_orchestrator");
const {loadCanonicalResolverStructuredTaxonomyArtifact} =
  require("./canonical_resolver_structured_taxonomy_loader");
const {loadVisionCanonicalFamilyRegistryArtifact} =
  require("./vision_canonical_family_registry_loader");
const {loadClothingKnowledgeBasePriorArtifact} =
  require("./clothing_knowledge_base_prior_loader");
const {
  RUNTIME_POLICIES,
  validateTrustedVisionResultForRuntime,
} = require("./trusted_vision_result_provenance");

const ENDPOINT_ID = "WardrobeQualificationAuthorityEndpoint";
const ENDPOINT_VERSION = "wardrobe-qualification-authority-endpoint-v1";
const REQUEST_CONTRACT = "WardrobeQualificationAuthorityRequest/v1";
const RESULT_CONTRACT = "WardrobeQualificationAuthorityResult/v1";

const ACTIONS = Object.freeze({
  analyzeCurrentSource: "analyze_current_source",
  reanalyzeCurrentSource: "reanalyze_current_source",
});

/**
 * @param {object} rawRequest
 * @param {object} deps
 */
async function handleQualificationAuthorityEndpoint(rawRequest, deps) {
  const auth = decodeTrustedFirebaseAuthContext(deps && deps.authContext);
  if (auth.status !== AUTH_STATUSES.authenticated) {
    return authorityResult({
      status: auth.status === AUTH_STATUSES.forbidden ? "forbidden" :
        "unauthenticated",
      reasonCode: auth.reasonCode,
    });
  }

  let uid;
  try {
    uid = assertPayloadAuthOwnership(rawRequest, auth);
  } catch (error) {
    return authorityResult({
      status: "forbidden",
      reasonCode: error.message,
    });
  }

  let request;
  try {
    request = decodeAuthorityRequest(rawRequest);
  } catch (error) {
    return authorityResult({
      status: "invalid_contract",
      reasonCode: error.message,
      itemId: rawRequest && rawRequest.itemId,
    });
  }

  const store = deps.store;
  if (store == null || typeof store.runTransaction !== "function" ||
      typeof store._get !== "function") {
    return authorityResult({
      status: "internal_contract_mismatch",
      reasonCode: "store_required",
      itemId: request.itemId,
    });
  }

  let document;
  try {
    document = await store._get(uid, request.itemId);
  } catch (_) {
    return authorityResult({
      status: "repository_failed",
      reasonCode: "wardrobe_document_read_failed",
      itemId: request.itemId,
      retryable: true,
    });
  }
  if (document == null) {
    return authorityResult({
      status: "item_not_found",
      reasonCode: "wardrobe_item_not_found",
      itemId: request.itemId,
    });
  }

  let assignedAt;
  try {
    assignedAt = requireUtc(resolveServerAssignedAt(deps), "assignedAt");
  } catch (error) {
    return authorityResult({
      status: "internal_contract_mismatch",
      reasonCode: error && error.message || "server_clock_required",
      itemId: request.itemId,
    });
  }
  const storageClient = deps.storageMetadataClient;
  if (storageClient == null) {
    return authorityResult({
      status: "internal_contract_mismatch",
      reasonCode: "storage_metadata_client_required",
      itemId: request.itemId,
    });
  }

  let authorityInitialized = false;
  let workingDoc = document;
  if (workingDoc[AUTHORITY_KEY] == null) {
    const classification = classifyLazyMigrationCandidate(workingDoc, true);
    if (classification.class === LAZY_MIGRATION_CLASSES.productSourceOnly) {
      return authorityResult({
        status: "product_source_not_supported",
        reasonCode: "product_source_not_supported",
        itemId: request.itemId,
      });
    }
    if (classification.class !== LAZY_MIGRATION_CLASSES.eligibleUserSource) {
      return authorityResult({
        status: classification.class ===
          LAZY_MIGRATION_CLASSES.missingStoragePath ?
          "source_missing" : "authority_missing",
        reasonCode: classification.class,
        itemId: request.itemId,
      });
    }
    // Defer authority initialization to persistMappedWardrobeProfile. The
    // repository will create authority + profile in one final transaction.
    workingDoc = {...workingDoc, [AUTHORITY_KEY]: {
      contractVersion: 1, imageRevision: 1, wardrobeItemRevision: 1,
      sourceStoragePath: String(workingDoc.storagePath),
      uploadGeneration: null, sourceObjectGeneration: null,
      sourceObjectMetageneration: null, sourceImageSha256: null,
      sourceUpdatedAt: assignedAt, assignedAt,
    }};
  }

  const authority = workingDoc[AUTHORITY_KEY];
  if (authority == null) {
    return authorityResult({
      status: "authority_missing",
      reasonCode: "authority_missing",
      itemId: request.itemId,
    });
  }

  let sourceSnapshot;
  try {
    sourceSnapshot = await fetchTrustedSourceObjectSnapshot({
      uid,
      itemId: request.itemId,
      sourceStoragePath: authority.sourceStoragePath,
      storageMetadataClient: storageClient,
    });
  } catch (error) {
    const code = error.message || "source_missing";
    return authorityResult({
      status: code.includes("missing") ? "source_missing" : "source_missing",
      reasonCode: code,
      itemId: request.itemId,
      generationId: authority.generationId,
    });
  }

  if (!sourceSnapshot.exists) {
    return authorityResult({
      status: "source_missing",
      reasonCode: "source_object_missing",
      itemId: request.itemId,
      generationId: authority.generationId,
    });
  }
  if (sourceSnapshot.sourceStoragePath !== authority.sourceStoragePath ||
      (authority.uploadGeneration != null &&
       sourceSnapshot.generation !== authority.uploadGeneration)) {
    return authorityResult({
      status: "stale_image",
      reasonCode: sourceSnapshot.generation !== authority.uploadGeneration ?
        "newer_generation_exists" : "path_mismatch",
      itemId: request.itemId,
      generationId: authority.generationId,
    });
  }

  if (authority.uploadGeneration == null) {
    workingDoc = {...workingDoc, [AUTHORITY_KEY]: {
      ...authority,
      uploadGeneration: sourceSnapshot.generation,
      sourceObjectGeneration: sourceSnapshot.generation,
      sourceObjectMetageneration: sourceSnapshot.metageneration,
      sourceImageSha256: sourceSnapshot.sha256,
    }};
    authorityInitialized = true;
  }
  const effectiveAuthority = workingDoc[AUTHORITY_KEY];

  const analysisKind = request.action === ACTIONS.reanalyzeCurrentSource ?
    "reanalysis" : "initial_analysis";
  const provisionalRevision = buildRevisionContext({
    itemId: request.itemId,
    imageRevision: effectiveAuthority.imageRevision,
    wardrobeItemRevision: effectiveAuthority.wardrobeItemRevision,
    sourceStoragePath: effectiveAuthority.sourceStoragePath,
    sourceObjectGeneration: effectiveAuthority.sourceObjectGeneration,
    uploadGeneration: effectiveAuthority.uploadGeneration,
    sourceObjectMetageneration: effectiveAuthority.sourceObjectMetageneration,
    sourceImageSha256: effectiveAuthority.sourceImageSha256 || sourceSnapshot.sha256,
    sourceUpdatedAt: effectiveAuthority.sourceUpdatedAt || assignedAt,
    expectedProfileRevision: currentProfileRevision(document),
  });
  const viewId = "view_1";
  const identity = allocateServerAnalysisIdentity({itemId: request.itemId,
    generationId: provisionalRevision.generationId, analysisKind,
    serverAttemptId: `controlled-write-runtime-v1:${analysisKind}`,
    primaryViewIndex: 0, views: [{index: 0, viewId,
      sourceStoragePath: effectiveAuthority.sourceStoragePath,
      generation: sourceSnapshot.generation}]});
  const visionClient = deps.visionClient || createFakeTrustedVisionAnalysisClient();
  let visionResult;
  try {
    visionResult = await visionClient.analyzeCurrentSource({
      itemId: request.itemId,
      sourceStoragePath: effectiveAuthority.sourceStoragePath,
      scenarioId: deps.scenarioId || request.offlineScenarioId,
      analysisId: identity.rootAnalysisId,
      observedAt: assignedAt,
    });
  } catch (error) {
    return authorityResult({
      status: "invalid_parser_result",
      reasonCode: error.message,
      itemId: request.itemId,
      generationId: authority.generationId,
    });
  }
  const provenanceValidation = validateTrustedVisionResultForRuntime(
    visionResult, {
      policy: deps.provenancePolicy || RUNTIME_POLICIES.fixtureOnly,
    });
  if (!provenanceValidation.ok) {
    return authorityResult({
      status: "invalid_parser_result",
      reasonCode: provenanceValidation.reasonCode,
      itemId: request.itemId,
      generationId: authority.generationId,
    });
  }

  let revisionContext;
  try {
    revisionContext = buildRevisionContext({
      itemId: request.itemId,
      imageRevision: effectiveAuthority.imageRevision,
      wardrobeItemRevision: effectiveAuthority.wardrobeItemRevision,
      sourceStoragePath: effectiveAuthority.sourceStoragePath,
      sourceObjectGeneration: effectiveAuthority.sourceObjectGeneration,
      uploadGeneration: effectiveAuthority.uploadGeneration,
      sourceObjectMetageneration: effectiveAuthority.sourceObjectMetageneration,
      sourceImageSha256: effectiveAuthority.sourceImageSha256,
      sourceUpdatedAt: effectiveAuthority.sourceUpdatedAt || assignedAt,
      expectedProfileRevision: currentProfileRevision(workingDoc),
    });
  } catch (error) {
    return authorityResult({
      status: "internal_contract_mismatch",
      reasonCode: error.message,
      itemId: request.itemId,
    });
  }

  let orchestration;
  try {
    const artifacts = artifactIntegrity();
    const expectedRuntime = {parserContractVersion: 1,
      parserVersion: "vision_v2_parser_v1", visionSchemaVersion: 9,
      promptVersion: "vision-v2-schema-9", modelIdentifier: "gpt-4o-mini",
      pipelineVersion: "vision-v2-phase-4.9",
      qualificationVersion: "qualification-v1",
      provenanceSource: "trusted_server_media", itemId: request.itemId,
      generationId: revisionContext.generationId, artifactIntegrity: artifacts};
    const response = structuredClone(visionResult.parser.views[0].response);
    response.analysisId = identity.rootAnalysisId;
    const ordering = {contractVersion: 1, primaryViewIndex: 0,
      orderedViews: [{index: 0, viewId,
        sourceGenerationFingerprint: sourceGenerationFingerprint(
          sourceSnapshot.sourceStoragePath, sourceSnapshot.generation),
        sourceReference: response.sourceReference,
        orientation: response.subjectAssessment.framingAttestations
          .subjectOrientation}]};
    const attestation = {contractVersion: 1, parserContractVersion: 1,
      parserVersion: "vision_v2_parser_v1", visionSchemaVersion: 9,
      promptVersion: "vision-v2-schema-9", modelIdentifier: "gpt-4o-mini",
      pipelineVersion: "vision-v2-phase-4.9",
      qualificationVersion: "qualification-v1",
      strictParserValidationPassed: true, provenance: {
        source: "trusted_server_media", liveModel: true,
        serverOwnedSourceReference: true}};
    const handoff = buildTrustedVisionQualificationInput({
      serverAnalysisIdentity: identity,
      trustedParserResult: {views: [{viewId, response}],
        multiViewSubjectBinding: null}, trustedParserAttestation: attestation,
      trustedSourceSnapshots: [sourceSnapshot],
      trustedRevisionContext: revisionContext, trustedViewOrdering: ordering,
      artifactIntegrity: artifacts, expectedRuntime});
    orchestration = (deps.runRuntimeOrchestrator ||
      runLiveParserBackendQualification)(handoff, {expectedRuntime,
      persistenceRevision: (currentProfileRevision(document) ?? 0) + 1});
    if (!orchestration || orchestration.status !== "qualified") {
      throw new Error(orchestration && orchestration.status ||
        "runtime_orchestrator_invalid_result");
    }
  } catch (error) {
    return authorityResult({
      status: "qualification_failed",
      reasonCode: error.message,
      itemId: request.itemId,
      generationId: revisionContext.generationId,
      analysisId: identity.rootAnalysisId,
    });
  }

  const mapperResult = orchestration.mapperResult;
  if (mapperResult.status === "invalidInput") {
    return authorityResult({
      status: "mapping_failed",
      reasonCode: mapperResult.reasonCode || "invalidInput",
      itemId: request.itemId,
      generationId: revisionContext.generationId,
      analysisId: orchestration.analysisId,
      qualificationSummary: {
        mapperStatus: mapperResult.status,
        omittedCount: (mapperResult.omittedEvidenceReasonCodes || []).length,
      },
    });
  }
  if (mapperResult.status !== "mapped" || mapperResult.envelope == null) {
    return authorityResult({
      status: "mapping_failed",
      reasonCode: mapperResult.reasonCode || mapperResult.status,
      itemId: request.itemId,
      generationId: revisionContext.generationId,
      analysisId: orchestration.analysisId,
    });
  }

  let repositoryResult;
  try {
    repositoryResult = await persistMappedWardrobeProfile({
      contractVersion: 1,
      userId: uid,
      wardrobeItemId: request.itemId,
      backendAssignedAt: assignedAt,
      sourceObjectSnapshot: sourceSnapshot,
      revisionContext,
      mappedEnvelope: mapperResult.envelope,
      expectedProfileRevision: currentProfileRevision(workingDoc),
    }, store);
  } catch (error) {
    return authorityResult({
      status: "repository_failed",
      reasonCode: error.message,
      itemId: request.itemId,
      generationId: revisionContext.generationId,
      analysisId: orchestration.analysisId,
    });
  }

  return authorityResult({
    status: mapRepositoryStatus(repositoryResult.status),
    reasonCode: repositoryResult.reasonCode,
    itemId: request.itemId,
    generationId: repositoryResult.generationId || revisionContext.generationId,
    analysisId: orchestration.analysisId,
    repositoryStatus: repositoryResult.status,
    previousProfileRevision: repositoryResult.previousProfileRevision,
    resultingProfileRevision: repositoryResult.resultingProfileRevision,
    wroteProfile: repositoryResult.wroteProfile === true,
    idempotent: repositoryResult.idempotent === true,
    retryable: false,
    authorityInitialized,
    qualificationSummary: Object.freeze({
      mapperStatus: mapperResult.status,
      machineEvidenceCount:
        mapperResult.envelope.machineEvidence.length,
      omittedCount: (mapperResult.omittedEvidenceReasonCodes || []).length,
      resolvedCanonicalType:
        orchestration.resolvedProfile &&
        orchestration.resolvedProfile.identity &&
        orchestration.resolvedProfile.identity.canonicalType &&
        orchestration.resolvedProfile.identity.canonicalType.value != null ?
          String(orchestration.resolvedProfile.identity.canonicalType.value) :
          null,
    }),
  });
}

function decodeAuthorityRequest(raw) {
  if (raw == null || typeof raw !== "object" || Array.isArray(raw)) {
    fail("request_not_object");
  }
  if (raw.contractVersion !== 1) fail("request_contract_unsupported");
  const itemId = requireNonEmpty(raw.itemId, "itemId");
  const action = requireNonEmpty(raw.action, "action");
  if (!Object.values(ACTIONS).includes(action)) {
    fail(`unknown_action:${action}`);
  }
  for (const field of [
    "uid", "imageRevision", "wardrobeItemRevision", "uploadGeneration",
    "generationId", "qualificationAuthority", "machineEvidence",
    "mapperContext", "expectedProfileRevision", "signedUrl", "imageBytes",
    "sourceObjectGeneration",
  ]) {
    if (Object.prototype.hasOwnProperty.call(raw, field)) {
      fail(`forbidden_request_field:${field}`);
    }
  }
  return Object.freeze({
    contractVersion: 1,
    requestContract: REQUEST_CONTRACT,
    itemId,
    action,
    offlineScenarioId: raw.offlineScenarioId ?? null,
  });
}

function resolveServerAssignedAt(deps) {
  if (!deps || typeof deps.serverClock !== "function") {
    fail("server_clock_required");
  }
  let value;
  try {
    value = deps.serverClock();
  } catch (_) {
    fail("server_clock_invalid");
  }
  if (value == null) fail("server_clock_invalid");
  return value;
}

function artifactIntegrity() {
  const taxonomy = loadCanonicalResolverStructuredTaxonomyArtifact();
  const family = loadVisionCanonicalFamilyRegistryArtifact();
  const kb = loadClothingKnowledgeBasePriorArtifact();
  return Object.freeze({contractVersion: 1,
    canonicalFamilyArtifactSha256: family.contentSha256,
    structuredTaxonomyArtifactSha256: taxonomy.contentSha256,
    knowledgeBaseArtifactSha256: kb.contentSha256,
    canonicalFamilyArtifactVersion: family.artifactVersion,
    structuredTaxonomyArtifactVersion: taxonomy.artifactVersion,
    knowledgeBaseArtifactVersion: kb.artifactVersion});
}

function currentProfileRevision(document) {
  const envelope = document && document[ENVELOPE_KEY];
  if (!envelope || !envelope.metadata) return null;
  return Number.isInteger(envelope.metadata.revision) ?
    envelope.metadata.revision : null;
}

function mapInitStatus(status) {
  if (status === "product_source_not_supported") {
    return "product_source_not_supported";
  }
  if (status === "source_missing" || status === "missing_storage_path") {
    return "source_missing";
  }
  return status;
}

function mapRepositoryStatus(status) {
  switch (status) {
  case "write_allowed":
    return "mutation_applied";
  case "idempotent_noop":
    return "idempotent_noop";
  case "stale_image":
    return "stale_image";
  case "stale_item_revision":
    return "stale_item_revision";
  case "newer_generation_exists":
    return "newer_generation_exists";
  case "revision_conflict":
    return "revision_conflict";
  case "item_deleted":
    return "item_not_found";
  case "source_missing":
    return "source_missing";
  default:
    return "repository_failed";
  }
}

function authorityResult(fields) {
  return Object.freeze({
    contractVersion: 1,
    resultContract: RESULT_CONTRACT,
    endpointId: ENDPOINT_ID,
    endpointVersion: ENDPOINT_VERSION,
    status: fields.status,
    reasonCode: fields.reasonCode,
    itemId: fields.itemId ?? null,
    generationId: fields.generationId ?? null,
    analysisId: fields.analysisId ?? null,
    repositoryStatus: fields.repositoryStatus ?? null,
    previousProfileRevision: fields.previousProfileRevision ?? null,
    resultingProfileRevision: fields.resultingProfileRevision ?? null,
    wroteProfile: fields.wroteProfile === true,
    idempotent: fields.idempotent === true,
    retryable: fields.retryable === true,
    authorityInitialized: fields.authorityInitialized === true,
    qualificationSummary: fields.qualificationSummary ?? null,
  });
}

function requireNonEmpty(value, label) {
  if (typeof value !== "string" || !value.trim()) fail(`${label}_empty`);
  return value.trim();
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
  ACTIONS,
  ENDPOINT_ID,
  ENDPOINT_VERSION,
  REQUEST_CONTRACT,
  RESULT_CONTRACT,
  createMemoryTransactionalStore,
  handleQualificationAuthorityEndpoint,
};
