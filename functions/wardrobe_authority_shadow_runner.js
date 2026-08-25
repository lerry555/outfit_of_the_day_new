"use strict";

/**
 * Shadow / no-write runner for wardrobe qualification authority.
 * Never mutates Firestore documents. Production composition accepts injected I/O.
 */

const {
  AUTH_STATUSES,
  assertPayloadAuthOwnership,
  decodeTrustedFirebaseAuthContext,
} = require("./trusted_firebase_auth_context");
const {
  AUTHORITY_KEY,
  ENVELOPE_KEY,
  persistMappedWardrobeProfile,
  createMemoryTransactionalStore,
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
const {fingerprint} = require("./wardrobe_authority_redaction");
const {
  AUTHORITY_MODES,
} = require("./wardrobe_authority_runtime_mode");
const {
  RUNTIME_POLICIES,
  validateTrustedVisionResultForRuntime,
} = require("./trusted_vision_result_provenance");
const {evaluateControlledShadowPolicy} =
  require("./controlled_shadow_activation_policy");
const {consumeSingleUseShadowLease} = require("./single_use_shadow_lease");

const SHADOW_ID = "WardrobeQualificationAuthorityShadowRunner";
const SHADOW_VERSION = "wardrobe-qualification-authority-shadow-v1";
const RESULT_CONTRACT = "WardrobeQualificationAuthorityShadowResult/v1";
const ACTION_KIND = Object.freeze({analyze_current_source: "initial_analysis",
  reanalyze_current_source: "reanalysis"});

/**
 * Create a store proxy that rejects any writePatch (zero-write proof).
 */
function createZeroWriteStoreProxy(store) {
  return {
    async runTransaction(userId, wardrobeItemId, callback) {
      return store.runTransaction(userId, wardrobeItemId, async (ctx) => {
        const decision = await callback(ctx);
        if (decision && decision.writePatch) {
          const err = new Error("shadow_write_forbidden");
          err.code = "shadow_write_forbidden";
          throw err;
        }
        return decision;
      });
    },
    async _get(userId, wardrobeItemId) {
      return store._get(userId, wardrobeItemId);
    },
    _dump() {
      return store._dump ? store._dump() : null;
    },
  };
}

/**
 * @param {object} rawRequest
 * @param {object} deps
 */
async function runQualificationAuthorityShadow(rawRequest, deps) {
  shadowLog(deps, "shadow_request_started", {status: "started"});
  const auth = decodeTrustedFirebaseAuthContext(deps && deps.authContext);
  if (auth.status !== AUTH_STATUSES.authenticated) {
    return shadowResult({
      status: auth.status === AUTH_STATUSES.forbidden ? "forbidden" :
        "unauthenticated",
      reasonCode: auth.reasonCode,
      mode: AUTHORITY_MODES.shadow,
    });
  }

  let uid;
  try {
    uid = assertPayloadAuthOwnership(rawRequest, auth);
  } catch (error) {
    return shadowResult({
      status: "forbidden",
      reasonCode: error.message,
      mode: AUTHORITY_MODES.shadow,
    });
  }

  const itemId = rawRequest && rawRequest.itemId;
  if (!itemId || typeof itemId !== "string") {
    return shadowResult({
      status: "invalid_contract",
      reasonCode: "itemId_required",
      mode: AUTHORITY_MODES.shadow,
    });
  }

  if (deps.requireControlledShadowPolicy === true) {
    if (auth.appCheckVerified !== true) return shadowResult({
      status: "shadow_blocked", reasonCode: "app_check_required_missing",
      mode: AUTHORITY_MODES.shadow, itemId});
    const policy = evaluateControlledShadowPolicy(deps.shadowPolicy,
      rawRequest, {uid, mode: "shadow", now: deps.serverNow});
    if (!policy.ok) return shadowResult({status: "shadow_blocked",
      reasonCode: policy.reasonCode, mode: AUTHORITY_MODES.shadow, itemId});
    const lease = await consumeSingleUseShadowLease({leaseId: policy.leaseId,
      invocationId: deps.invocationId || "invocation-unresolved",
      now: deps.serverNow}, deps.shadowLeaseStore);
    if (!lease.ok) return shadowResult({status: "shadow_blocked",
      reasonCode: lease.reasonCode, mode: AUTHORITY_MODES.shadow, itemId});
  }

  const costGate = deps.costGate;
  let costLease = null;
  if (costGate && typeof costGate.begin === "function") {
    costLease = costGate.begin({uid, itemId, viewCount: deps.viewCount});
    if (!costLease.ok) {
      shadowLog(deps, "shadow_gate_blocked", {status: "blocked",
        reasonCode: costLease.reasonCode});
      return shadowResult({
        status: "resource_exhausted",
        reasonCode: costLease.reasonCode,
        mode: AUTHORITY_MODES.shadow,
        itemId,
        retryable: true,
      });
    }
  }

  try {
    const store = createZeroWriteStoreProxy(deps.store);
    const beforeDump = deps.store._dump ? JSON.stringify(deps.store._dump()) : null;
    let document;
    try {
      document = await store._get(uid, itemId);
    } catch (_) {
      return shadowResult({
        status: "internal",
        reasonCode: "wardrobe_document_read_failed",
        mode: AUTHORITY_MODES.shadow,
        itemId,
        retryable: true,
      });
    }
    if (document == null) {
      return shadowResult({
        status: "item_not_found",
        reasonCode: "wardrobe_item_not_found",
        mode: AUTHORITY_MODES.shadow,
        itemId,
      });
    }

    const assignedAt = deps.assignedAt || "2026-01-01T00:00:00.000Z";
    let wouldInitializeAuthority = false;
    let migrationClass = null;
    let simulatedAuthority = document[AUTHORITY_KEY] || null;

    if (simulatedAuthority == null) {
      const classification = classifyLazyMigrationCandidate(document, true);
      migrationClass = classification.class;
      if (classification.class === LAZY_MIGRATION_CLASSES.eligibleUserSource) {
        wouldInitializeAuthority = true;
        // Simulate authority in-memory only — never write.
        const path = String(document.storagePath || "");
        simulatedAuthority = {
          imageRevision: 1,
          wardrobeItemRevision: 1,
          sourceStoragePath: path,
          uploadGeneration: "1",
          sourceObjectGeneration: "1",
          generationId: `shadow-sim:${itemId}:1`,
          contractVersion: 1,
          assignedAt,
        };
      } else {
        return shadowResult({
          status: "shadow_blocked",
          reasonCode: classification.class,
          mode: AUTHORITY_MODES.shadow,
          itemId,
          wouldInitializeAuthority: false,
          migrationClass,
          wroteProfile: false,
          wouldWriteProfile: false,
        });
      }
    } else {
      migrationClass = LAZY_MIGRATION_CLASSES.alreadyInitialized;
    }

    const storageClient = deps.storageMetadataClient;
    let sourceSnapshot;
    try {
      sourceSnapshot = await fetchTrustedSourceObjectSnapshot({
        uid,
        itemId,
        sourceStoragePath: simulatedAuthority.sourceStoragePath,
        storageMetadataClient: storageClient,
      });
    } catch (error) {
      return shadowResult({
        status: "source_missing",
        reasonCode: error.message,
        mode: AUTHORITY_MODES.shadow,
        itemId,
        wouldInitializeAuthority,
        migrationClass,
      });
    }
    if (!sourceSnapshot.exists) {
      return shadowResult({
        status: "source_missing",
        reasonCode: "source_object_missing",
        mode: AUTHORITY_MODES.shadow,
        itemId,
        wouldInitializeAuthority,
        migrationClass,
      });
    }
    const maxImageSizeBytes = Number.isInteger(deps.maxImageSizeBytes) ?
      deps.maxImageSizeBytes : 10 * 1024 * 1024;
    if (!new Set(["image/jpeg", "image/png", "image/webp"])
      .has(sourceSnapshot.contentType)) {
      return shadowResult({status: "source_missing",
        reasonCode: "source_content_type_invalid", mode: AUTHORITY_MODES.shadow,
        itemId, wouldInitializeAuthority, migrationClass});
    }
    if (!Number.isInteger(sourceSnapshot.sizeBytes) ||
        sourceSnapshot.sizeBytes > maxImageSizeBytes) {
      return shadowResult({status: "source_missing",
        reasonCode: "source_image_too_large", mode: AUTHORITY_MODES.shadow,
        itemId, wouldInitializeAuthority, migrationClass});
    }
    if (!wouldInitializeAuthority &&
        String(simulatedAuthority.sourceObjectGeneration) !==
          String(sourceSnapshot.generation)) {
      return shadowResult({status: "source_missing",
        reasonCode: "source_generation_mismatch", mode: AUTHORITY_MODES.shadow,
        itemId, wouldInitializeAuthority, migrationClass});
    }
    shadowLog(deps, "shadow_storage_validated", {status: "ok"});
    // Bind simulated generation to trusted snapshot when initializing.
    if (wouldInitializeAuthority) {
      simulatedAuthority = {
        ...simulatedAuthority,
        uploadGeneration: String(sourceSnapshot.generation),
        sourceObjectGeneration: String(sourceSnapshot.generation),
        sourceObjectMetageneration: sourceSnapshot.metageneration,
        sourceImageSha256: sourceSnapshot.sha256,
      };
    }

    if (typeof deps.resolveOpenAISecret === "function") {
      try { deps.resolveOpenAISecret(); } catch (_) {
        return shadowResult({status: "invalid_parser_result",
          reasonCode: "openai_secret_unavailable", mode: AUTHORITY_MODES.shadow,
          itemId, wouldInitializeAuthority, migrationClass, wroteProfile: false,
          wouldWriteProfile: false});
      }
    }

    const analysisKind = mapShadowAnalysisKind(rawRequest.action);
    const viewId = "view_1";
    const identity = allocateServerAnalysisIdentity({itemId,
      generationId: revisionGenerationId(itemId, simulatedAuthority,
        sourceSnapshot, assignedAt), analysisKind,
      serverAttemptId: `shadow-runtime-v1:${analysisKind}`,
      primaryViewIndex: 0, views: [{index: 0, viewId,
        sourceStoragePath: simulatedAuthority.sourceStoragePath,
        generation: sourceSnapshot.generation}]});
    const visionClient = deps.visionClient;
    if (!visionClient || typeof visionClient.analyzeCurrentSource !== "function") {
      throw new Error("production_vision_client_required");
    }
    let visionResult;
    try {
      visionResult = await visionClient.analyzeCurrentSource({
        itemId,
        sourceStoragePath: simulatedAuthority.sourceStoragePath,
        analysisId: identity.rootAnalysisId,
        observedAt: assignedAt,
      });
    } catch (error) {
      shadowLog(deps, "shadow_request_failed", {status: "failed",
        reasonCode: error.message});
      return shadowResult({
        status: "invalid_parser_result",
        reasonCode: error.message,
        mode: AUTHORITY_MODES.shadow,
        itemId,
        wouldInitializeAuthority,
        migrationClass,
      });
    }
    const provenanceValidation = validateTrustedVisionResultForRuntime(
      visionResult, {
        policy: deps.provenancePolicy || RUNTIME_POLICIES.fixtureOnly,
      });
    if (!provenanceValidation.ok) {
      return shadowResult({
        status: "invalid_parser_result",
        reasonCode: provenanceValidation.reasonCode,
        mode: AUTHORITY_MODES.shadow,
        itemId,
        wouldInitializeAuthority,
        migrationClass,
      });
    }
    shadowLog(deps, "shadow_vision_completed", {status: "ok"});

    const revisionContext = buildRevisionContext({
      itemId,
      imageRevision: simulatedAuthority.imageRevision,
      wardrobeItemRevision: simulatedAuthority.wardrobeItemRevision,
      sourceStoragePath: simulatedAuthority.sourceStoragePath,
      sourceObjectGeneration: simulatedAuthority.sourceObjectGeneration,
      uploadGeneration: simulatedAuthority.uploadGeneration,
      sourceObjectMetageneration: simulatedAuthority.sourceObjectMetageneration,
      sourceImageSha256: simulatedAuthority.sourceImageSha256 ||
        sourceSnapshot.sha256,
      sourceUpdatedAt: simulatedAuthority.sourceUpdatedAt || assignedAt,
      expectedProfileRevision: currentProfileRevision(document),
    });

    let orchestration;
    try {
      const artifacts = artifactIntegrity();
      const expectedRuntime = {parserContractVersion: 1,
        parserVersion: "vision_v2_parser_v1", visionSchemaVersion: 9,
        promptVersion: "vision-v2-schema-9", modelIdentifier: "gpt-4o-mini",
        pipelineVersion: "vision-v2-phase-4.9",
        qualificationVersion: "qualification-v1",
        provenanceSource: "trusted_server_media", itemId,
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
      shadowLog(deps, "shadow_handoff_built", {status: "ok"});
      orchestration = (deps.runRuntimeOrchestrator ||
        runLiveParserBackendQualification)(handoff, {expectedRuntime});
      if (!orchestration || orchestration.status !== "qualified") {
        throw new Error(orchestration && orchestration.status ||
          "runtime_orchestrator_invalid_result");
      }
      shadowLog(deps, "shadow_runtime_orchestration_completed", {status: "ok"});
    } catch (error) {
      shadowLog(deps, "shadow_request_failed", {status: "failed",
        reasonCode: error.message});
      return shadowResult({
        status: "qualification_failed",
        reasonCode: error.message,
        mode: AUTHORITY_MODES.shadow,
        itemId,
        wouldInitializeAuthority,
        migrationClass,
        analysisId: identity.rootAnalysisId,
        generationFingerprint: fingerprint(revisionContext.generationId),
      });
    }

    const mapperResult = orchestration.mapperResult;
    let simulatedRepositoryStatus = "not_evaluated";
    let wouldWriteProfile = false;
    if (mapperResult.status === "mapped" && mapperResult.envelope) {
      const seedDoc = structuredClone(document);
      if (wouldInitializeAuthority) {
        seedDoc[AUTHORITY_KEY] = simulatedAuthority;
      }
      const disposable = createMemoryTransactionalStore({
        [`users/${uid}/wardrobe/${itemId}`]: seedDoc,
      });
      try {
        const sim = await persistMappedWardrobeProfile({
          contractVersion: 1,
          userId: uid,
          wardrobeItemId: itemId,
          backendAssignedAt: assignedAt,
          sourceObjectSnapshot: sourceSnapshot,
          revisionContext,
          mappedEnvelope: mapperResult.envelope,
          expectedProfileRevision: currentProfileRevision(document),
        }, disposable);
        simulatedRepositoryStatus = sim.status;
        wouldWriteProfile = sim.wroteProfile === true;
      } catch (error) {
        simulatedRepositoryStatus = `simulate_failed:${error.message}`;
      }
    } else {
      simulatedRepositoryStatus = mapperResult.status;
    }

    const afterDump = deps.store._dump ? JSON.stringify(deps.store._dump()) : null;
    if (beforeDump != null && afterDump != null && beforeDump !== afterDump) {
      return shadowResult({
        status: "internal",
        reasonCode: "shadow_store_mutated",
        mode: AUTHORITY_MODES.shadow,
        itemId,
      });
    }

    shadowLog(deps, "shadow_simulation_completed", {status: "ok"});
    return shadowResult({
      status: "shadow_ok",
      reasonCode: "shadow_evaluation_complete",
      mode: AUTHORITY_MODES.shadow,
      itemId,
      analysisId: orchestration.rootAnalysisId,
      generationFingerprint: fingerprint(revisionContext.generationId),
      mapperStatus: mapperResult.status,
      simulatedRepositoryStatus,
      wouldInitializeAuthority,
      wouldWriteProfile,
      wroteProfile: false,
      authorityInitialized: false,
      migrationClass,
      paritySummary: Object.freeze({
        mapperStatus: mapperResult.status,
        omittedCount: (mapperResult.omittedEvidenceReasonCodes || []).length,
        machineEvidenceCount: mapperResult.envelope ?
          mapperResult.envelope.machineEvidence.length : 0,
      }),
      retryable: false,
    });
  } finally {
    if (costLease && typeof costLease.release === "function") {
      costLease.release();
    }
  }
}

function mapShadowAnalysisKind(action) {
  const kind = ACTION_KIND[action];
  if (!kind) throw new Error(`shadow_action_invalid:${String(action)}`);
  return kind;
}

function revisionGenerationId(itemId, authority, snapshot, assignedAt) {
  return buildRevisionContext({itemId, imageRevision: authority.imageRevision,
    wardrobeItemRevision: authority.wardrobeItemRevision,
    sourceStoragePath: authority.sourceStoragePath,
    sourceObjectGeneration: snapshot.generation,
    uploadGeneration: snapshot.generation,
    sourceObjectMetageneration: snapshot.metageneration,
    sourceImageSha256: snapshot.sha256,
    sourceUpdatedAt: authority.sourceUpdatedAt || assignedAt,
    expectedProfileRevision: null}).generationId;
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

function shadowLog(deps, event, fields) {
  deps && deps.logger && deps.logger.info && deps.logger.info(event,
    Object.freeze({status: fields.status, reasonCode: fields.reasonCode || null}));
}

function currentProfileRevision(document) {
  const envelope = document && document[ENVELOPE_KEY];
  if (!envelope || !envelope.metadata) return null;
  return Number.isInteger(envelope.metadata.revision) ?
    envelope.metadata.revision : null;
}

function shadowResult(fields) {
  return Object.freeze({
    resultContract: RESULT_CONTRACT,
    shadowId: SHADOW_ID,
    shadowVersion: SHADOW_VERSION,
    status: fields.status,
    mode: fields.mode || AUTHORITY_MODES.shadow,
    reasonCode: fields.reasonCode || null,
    itemId: fields.itemId || null,
    analysisId: fields.analysisId || null,
    generationFingerprint: fields.generationFingerprint || null,
    mapperStatus: fields.mapperStatus || null,
    simulatedRepositoryStatus: fields.simulatedRepositoryStatus || null,
    wouldInitializeAuthority: fields.wouldInitializeAuthority === true,
    wouldWriteProfile: fields.wouldWriteProfile === true,
    wroteProfile: false,
    authorityInitialized: false,
    migrationClass: fields.migrationClass || null,
    paritySummary: fields.paritySummary || null,
    retryable: fields.retryable === true,
  });
}

module.exports = {
  SHADOW_ID,
  SHADOW_VERSION,
  RESULT_CONTRACT,
  ACTION_KIND,
  artifactIntegrity,
  createZeroWriteStoreProxy,
  mapShadowAnalysisKind,
  runQualificationAuthorityShadow,
};
