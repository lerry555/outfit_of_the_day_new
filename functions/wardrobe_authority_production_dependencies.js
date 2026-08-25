"use strict";

/**
 * Lazy production dependency factory for wardrobe authority runtime.
 * Does not initialize Admin SDK or read credentials at module import time.
 */

const {
  validateWardrobeAuthorityProductionConfig,
} = require("./wardrobe_authority_production_config");
const {
  createAdminStorageMetadataClient,
} = require("./wardrobe_admin_storage_metadata_client");
const {
  createAdminFirestoreTransactionalStore,
} = require("./wardrobe_admin_firestore_transactional_store");
const {
  createFakeStorageMetadataClient,
  fetchTrustedSourceObjectSnapshot,
} = require("./trusted_storage_metadata_adapter");
const {
  createTrustedVisionProductionAnalysisClient,
} = require("./trusted_vision_production_analysis_client");
const {
  createFakeTrustedVisionAnalysisClient,
} = require("./trusted_vision_analysis_client");
const {
  handleQualificationAuthorityEndpoint,
} = require("./wardrobe_qualification_authority_endpoint");
const {
  handleRevisionLifecycleEndpoint,
} = require("./wardrobe_revision_lifecycle_endpoint");
const {
  RUNTIME_POLICIES,
} = require("./trusted_vision_result_provenance");
const {AUTHORITY_MODES} = require("./wardrobe_authority_runtime_mode");

const FACTORY_ID = "WardrobeAuthorityProductionDependencies";
const FACTORY_VERSION = "wardrobe-authority-production-dependencies-v1";

/**
 * @param {object} options
 * @returns {Readonly<object>}
 */
function createWardrobeAuthorityProductionDependencies(options = {}) {
  let cached = null;

  function build() {
    if (cached) return cached;
    const config = validateWardrobeAuthorityProductionConfig(options.config);
    const store = createAdminFirestoreTransactionalStore(
      options.firestoreStoreOptions || {
        memoryDocs: options.memoryDocs || {},
      });

    let storageMetadataClient;
    if (options.storageMetadataClient) {
      storageMetadataClient = options.storageMetadataClient;
    } else if (options.adminStorageGetMetadata) {
      storageMetadataClient = createAdminStorageMetadataClient({
        getMetadata: options.adminStorageGetMetadata,
        bucketName: config.storageBucket,
      });
    } else if (options.fakeStorageByPath) {
      storageMetadataClient = createFakeStorageMetadataClient(
        options.fakeStorageByPath);
    } else {
      fail("storage_metadata_client_unresolved");
    }

    let visionClient;
    if (options.visionClient) {
      visionClient = options.visionClient;
    } else if (options.fetchImpl &&
        typeof options.resolveOpenAISecret === "function") {
      let liveClient = null;
      visionClient = Object.freeze({
        clientId: "LazyTrustedVisionProductionAnalysisClient",
        async analyzeCurrentSource(request) {
          if (!liveClient) liveClient = createTrustedVisionProductionAnalysisClient({
            fetchImpl: options.fetchImpl,
            getApiKey: options.resolveOpenAISecret,
            readObjectBytes: options.readObjectBytes,
            canonicalTypes: options.canonicalTypes,
            logger: options.logger,
          });
          return liveClient.analyzeCurrentSource(request);
        },
      });
    } else if (config.environmentMode === "test" ||
        config.environmentMode === "emulator") {
      visionClient = createFakeTrustedVisionAnalysisClient({
        scenarios: options.visionScenarios,
        fixtureRoot: options.fixtureRoot,
      });
    } else {
      fail("vision_client_unresolved_for_production");
    }

    const assignedAt = options.assignedAt || null;
    const provenancePolicy = options.provenancePolicy ||
      (config.environmentMode === "production" ?
        RUNTIME_POLICIES.productionControlledWrite :
        RUNTIME_POLICIES.fixtureOnly);
    const deps = Object.freeze({
      factoryId: FACTORY_ID,
      factoryVersion: FACTORY_VERSION,
      config,
      store,
      storageMetadataClient,
      visionClient,
      resolveOpenAISecret: typeof options.resolveOpenAISecret === "function" ?
        options.resolveOpenAISecret : null,
      shadowPolicy: null,
      shadowLeaseStore: null,
      controlledWritePolicy: null,
      controlledWriteLeaseStore: null,
      serverNow: null,
      serverClock: options.serverClock || null,
      invocationIdFactory: options.invocationIdFactory || null,
      logger: options.logger || null,
      assignedAt,
      provenancePolicy,
      fetchTrustedSourceObjectSnapshot,
      handleQualificationAuthorityEndpoint,
      handleRevisionLifecycleEndpoint,
      createdAtBinding: options.createdAtBinding || null,
    });
    cached = deps;
    return cached;
  }

  return Object.freeze({
    factoryId: FACTORY_ID,
    factoryVersion: FACTORY_VERSION,
    get(runtime = {}) {
      const deps = build();
      if (runtime.mode === AUTHORITY_MODES.controlledWrite) {
        if (typeof options.resolveControlledWritePolicy !== "function") {
          fail("controlled_write_policy_resolver_missing");
        }
        if (typeof options.createControlledWriteLeaseStore !== "function") {
          fail("controlled_write_lease_store_factory_missing");
        }
        const clock = options.serverClock || (() => new Date().toISOString());
        return Object.freeze({...deps,
          controlledWritePolicy: options.resolveControlledWritePolicy(),
          controlledWriteLeaseStore: options.createControlledWriteLeaseStore(),
          serverNow: clock(),
        });
      }
      if (runtime.mode !== AUTHORITY_MODES.shadow) return deps;
      if (typeof options.resolveShadowPolicy !== "function") {
        fail("shadow_policy_resolver_missing");
      }
      if (typeof options.createShadowLeaseStore !== "function") {
        fail("shadow_lease_store_factory_missing");
      }
      const clock = options.serverClock || (() => new Date().toISOString());
      return Object.freeze({...deps,
        shadowPolicy: options.resolveShadowPolicy(),
        shadowLeaseStore: options.createShadowLeaseStore(),
        serverNow: clock(),
      });
    },
    // Explicit non-evaluation at import: callers must invoke get().
    peekConstructed() {
      return cached != null;
    },
  });
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  FACTORY_ID,
  FACTORY_VERSION,
  createWardrobeAuthorityProductionDependencies,
};
