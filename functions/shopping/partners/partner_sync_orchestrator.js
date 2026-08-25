"use strict";

const {CONTRACT_VERSION} = require("../catalog_contract");
const {SNAPSHOT_SCOPE} = require("../catalog_sync_service");
const {
  CHANGESET_SOURCES,
  normalizeCatalogChangeSet,
} = require("../monitoring/catalog_change_set");
const {
  WISHLIST_CHANGESET_MAX_VARIANTS_V1,
} = require("../monitoring/wishlist_monitoring_constants");
const {
  assertPartnerAdapter,
  assertSyncModeSupported,
  SYNC_MODE,
} = require("./partner_adapter_contract");
const {PARTNER_CAPABILITY, hasCapability} = require("./partner_capabilities");
const {PARTNER_STATUS, projectPublicPartner} = require("./partner_config");
const {createPartnerError, isRetryableError, PARTNER_ERROR} =
  require("./partner_errors");
const {createRateLimiter} = require("./partner_rate_limit");
const {
  PARTNER_RETRY_POLICY_V1,
  withPartnerRetry,
} = require("./partner_retry");
const {
  RAW_PAYLOAD_RETENTION_POLICY_V1,
  sanitizeFailureSample,
} = require("./partner_raw_retention");
const {redactPrivateConfig} = require("./partner_secrets");

const REAL_PARTNER_API_REQUESTS = 0;
const PARTNER_POLLING_COUNT = 0;
const AFFILIATE_RANKING_INPUT_COUNT = 0;

/**
 * Persist one normalized catalog page (product/variant/offer/sizes).
 * Reuses Phase 2 repository identity merge — no competing PartnerProduct truth.
 */
async function persistNormalizedRecords({
  repository,
  publicPartner,
  records,
  seenOfferIds,
  changedVariantIds,
  changedOfferIds,
  changedSizeIds,
}) {
  let productsWritten = 0;
  let variantsWritten = 0;
  let offersWritten = 0;
  let sizesWritten = 0;
  let rejected = 0;

  await repository.upsertPartner(publicPartner);

  for (const record of records) {
    try {
      const productId = await repository.resolveProduct(record.product);
      const {candidateId: _pc, ...productFields} = record.product;
      await repository.upsertProduct({
        ...productFields,
        productId,
        freshness: record.freshness,
      });
      productsWritten++;

      const variantId = await repository.resolveVariant(record.variant);
      const {
        candidateId: _vc,
        productCandidateId: _pci,
        ...variantFields
      } = record.variant;
      await repository.upsertVariant({
        ...variantFields,
        variantId,
        productId,
        freshness: record.freshness,
        imageCandidates: record.imageCandidates || null,
        imageStatus: record.imageStatus || null,
      });
      variantsWritten++;

      await repository.upsertOffer({
        ...record.offer,
        variantId,
        freshness: record.freshness,
      });
      await repository.upsertSizes(record.offer.offerId, record.sizes);
      seenOfferIds.add(record.offer.offerId);
      changedVariantIds.add(variantId);
      changedOfferIds.add(record.offer.offerId);
      for (const size of record.sizes || []) {
        changedSizeIds.add(`${record.offer.offerId}:${size.normalizedSizeKey}`);
      }
      offersWritten++;
      sizesWritten += (record.sizes || []).length;
    } catch (error) {
      rejected++;
      throw error;
    }
  }

  return {
    productsWritten,
    variantsWritten,
    offersWritten,
    sizesWritten,
    rejected,
  };
}

/**
 * Partner sync orchestrator — adapter-neutral.
 * Flow: config → adapter → page fetch → validate/normalize → persist →
 * checkpoint → finalize → CatalogChangeSet → optional Phase 7 fanout hook.
 *
 * Does NOT call real partners unless adapter transport does (tests use mocks).
 * Does NOT schedule polling (PARTNER_POLLING_COUNT = 0).
 */
async function runPartnerSync({
  adapter,
  publicConfig,
  privateConfig,
  repository,
  mode,
  runId,
  now = new Date().toISOString(),
  checkpointStore,
  onCatalogChangeSet,
  sleep,
  random = Math.random,
  metricsSink,
} = {}) {
  assertPartnerAdapter(adapter);
  assertSyncModeSupported(adapter, mode);
  if (!repository) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_sync_repository_required",
    );
  }
  if (!runId) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_sync_run_id_required",
    );
  }

  const validation = adapter.validateConfiguration({
    publicConfig,
    privateConfig,
  });
  const publicPartner = projectPublicPartner(
    validation?.publicConfig || publicConfig || adapter.publicConfig?.() ||
      adapter.partner,
  );
  if (publicPartner.status === PARTNER_STATUS.DISABLED) {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_disabled",
    );
  }

  const rateLimiter = createRateLimiter(
    privateConfig?.rateLimit || validation?.privateConfig?.rateLimit || {},
  );
  const caps = adapter.capabilities();
  const maxPages = rateLimiter.config.maxPagesPerRun;
  const pageSize = rateLimiter.config.pageSize;

  let checkpoint = null;
  if (checkpointStore && typeof checkpointStore.load === "function") {
    checkpoint = await checkpointStore.load(publicPartner.partnerId);
  } else if (privateConfig?.checkpoint) {
    checkpoint = privateConfig.checkpoint;
  }

  const metrics = {
    partnerId: publicPartner.partnerId,
    adapterVersion: publicPartner.adapterVersion,
    syncRunId: runId,
    mode,
    pages: 0,
    recordsFetched: 0,
    recordsAccepted: 0,
    recordsRejected: 0,
    productsChanged: 0,
    variantsChanged: 0,
    offersChanged: 0,
    sizesChanged: 0,
    retries: 0,
    rateLimitWaits: 0,
    schemaErrors: 0,
    durationMs: 0,
    checkpoint: null,
    catalogRevision: null,
    fanoutChangedVariantCount: 0,
    realPartnerApiRequests: REAL_PARTNER_API_REQUESTS,
    partnerPollingCount: PARTNER_POLLING_COUNT,
    affiliateRankingInputCount: AFFILIATE_RANKING_INPUT_COUNT,
    privateConfigRedacted: redactPrivateConfig(privateConfig),
  };

  const startedAtMs = Date.now();
  const seenOfferIds = new Set();
  const changedVariantIds = new Set();
  const changedOfferIds = new Set();
  const changedSizeIds = new Set();
  const failureSamples = [];
  let completenessGuaranteed = false;
  let productsWritten = 0;
  let variantsWritten = 0;
  let offersWritten = 0;
  let sizesWritten = 0;

  const run = {
    contractVersion: CONTRACT_VERSION,
    runId,
    partnerId: publicPartner.partnerId,
    adapterVersion: publicPartner.adapterVersion,
    snapshotScope: mode === SYNC_MODE.FULL ?
      SNAPSHOT_SCOPE.FULL : SNAPSHOT_SCOPE.PARTIAL,
    mode,
    scope: {
      market: publicPartner.market,
      currency: publicPartner.currency,
    },
    startedAt: now,
    status: "RUNNING",
    checkpointBefore: checkpoint,
  };
  await repository.beginSyncRun(run);

  try {
    let pageToken = checkpoint?.pageToken || checkpoint?.cursor || null;
    let pages = 0;
    const seenPageTokens = new Set();

    for (;;) {
      if (pages >= maxPages) {
        throw createPartnerError(
          PARTNER_ERROR.PARTIAL_SYNC_FAILED,
          "partner_sync_max_pages_exceeded",
        );
      }
      if (pageToken != null) {
        const tokenKey = String(pageToken);
        if (seenPageTokens.has(tokenKey)) {
          throw createPartnerError(
            PARTNER_ERROR.INVALID_PAYLOAD,
            "partner_sync_duplicate_page_token",
          );
        }
        seenPageTokens.add(tokenKey);
      }

      await rateLimiter.acquire({sleep});
      metrics.rateLimitWaits = rateLimiter.stats().waits;

      const page = await withPartnerRetry(
        async () => {
          if (mode === SYNC_MODE.FULL) {
            return adapter.fetchFullSnapshot({
              pageToken,
              pageSize,
              checkpoint,
              privateConfig,
            });
          }
          return adapter.fetchIncremental({
            pageToken,
            pageSize,
            checkpoint,
            privateConfig,
          });
        },
        {
          policy: PARTNER_RETRY_POLICY_V1,
          isRetryable: isRetryableError,
          sleep: sleep || ((ms) => new Promise((r) => setTimeout(r, ms))),
          random,
          onRetry: () => {
            metrics.retries += 1;
          },
        },
      );

      pages += 1;
      metrics.pages = pages;

      if (!page || typeof page !== "object") {
        throw createPartnerError(
          PARTNER_ERROR.INVALID_PAYLOAD,
          "partner_sync_page_invalid",
        );
      }

      const rawRecords = Array.isArray(page.records) ? page.records : null;
      if (!rawRecords) {
        throw createPartnerError(
          PARTNER_ERROR.INVALID_PAYLOAD,
          "partner_sync_page_records_required",
        );
      }
      if (rawRecords.length > pageSize) {
        throw createPartnerError(
          PARTNER_ERROR.INVALID_PAYLOAD,
          "partner_sync_page_exceeds_page_size",
        );
      }

      metrics.recordsFetched += rawRecords.length;

      // Normalize entire page before persistence (SHOP-002 parity).
      const normalized = [];
      for (const raw of rawRecords) {
        try {
          normalized.push(normalizeRawPartnerRecord(adapter, raw, {now}));
        } catch (error) {
          metrics.recordsRejected += 1;
          if (error.code === PARTNER_ERROR.SCHEMA_CHANGED ||
              error.code === "SCHEMA_CHANGED") {
            metrics.schemaErrors += 1;
          }
          if (failureSamples.length <
              RAW_PAYLOAD_RETENTION_POLICY_V1.maxFailureSamplesPerRun) {
            failureSamples.push(sanitizeFailureSample(raw));
          }
          throw error;
        }
      }

      const writeStats = await persistNormalizedRecords({
        repository,
        publicPartner: {
          partnerId: publicPartner.partnerId,
          publicStoreName: publicPartner.publicStoreName,
          status: publicPartner.status,
          allowedDomains: publicPartner.allowedDomains,
          adapterKey: publicPartner.adapterKey,
          adapterVersion: publicPartner.adapterVersion,
          capabilities: publicPartner.capabilities,
          market: publicPartner.market,
          currency: publicPartner.currency,
        },
        records: normalized,
        seenOfferIds,
        changedVariantIds,
        changedOfferIds,
        changedSizeIds,
      });

      productsWritten += writeStats.productsWritten;
      variantsWritten += writeStats.variantsWritten;
      offersWritten += writeStats.offersWritten;
      sizesWritten += writeStats.sizesWritten;
      metrics.recordsAccepted += normalized.length;

      // Checkpoint advances ONLY after durable page persistence.
      const nextCheckpoint = adapter.buildCheckpoint({
        previous: checkpoint,
        page,
        pageIndex: pages,
        mode,
        persistedCount: normalized.length,
        now,
      });
      checkpoint = nextCheckpoint;
      if (checkpointStore && typeof checkpointStore.save === "function") {
        await checkpointStore.save(publicPartner.partnerId, checkpoint);
      }

      if (page.completenessGuaranteed === true) {
        completenessGuaranteed = true;
      }

      const nextToken = page.nextPageToken == null ? null : page.nextPageToken;
      if (!nextToken || page.done === true) {
        if (mode === SYNC_MODE.FULL && page.completenessGuaranteed !== false) {
          // Explicit completeness: adapter must set completenessGuaranteed true
          // on final FULL page to authorize discontinue-missing.
          completenessGuaranteed = page.completenessGuaranteed === true;
        }
        break;
      }
      pageToken = nextToken;
    }

    const disappearance = adapter.classifyDisappearance({
      mode,
      completenessGuaranteed,
      failed: false,
    });

    if (disappearance === "MAY_DISCONTINUE_MISSING_OFFERS" &&
        mode === SYNC_MODE.FULL &&
        completenessGuaranteed === true) {
      const discontinued = await repository.discontinueMissingPartnerOffers(
        publicPartner.partnerId,
        seenOfferIds,
      );
      for (const variantId of discontinued) changedVariantIds.add(variantId);
    }

    for (const variantId of changedVariantIds) {
      await repository.updateVariantLifecycle(variantId);
      await repository.regenerateProjection(variantId);
    }

    const catalogRevision = `rev_${runId}_${changedVariantIds.size}`;
    metrics.catalogRevision = catalogRevision;
    metrics.checkpoint = checkpoint;
    metrics.productsChanged = productsWritten;
    metrics.variantsChanged = changedVariantIds.size;
    metrics.offersChanged = changedOfferIds.size;
    metrics.sizesChanged = changedSizeIds.size;
    metrics.durationMs = Date.now() - startedAtMs;

    const result = {
      completedAt: now,
      productsWritten,
      variantsWritten,
      offersWritten,
      sizesWritten,
      changedVariantIds: [...changedVariantIds].sort(),
      changedOfferIds: [...changedOfferIds].sort(),
      changedSizeIds: [...changedSizeIds].sort(),
      catalogRevision,
      successfulVerificationAt: now,
      checkpointAfter: checkpoint,
      fetchedCount: metrics.recordsFetched,
      acceptedCount: metrics.recordsAccepted,
      rejectedCount: metrics.recordsRejected,
      mode,
      adapterVersion: publicPartner.adapterVersion,
      failureSamples,
    };
    await repository.completeSyncRun(runId, result);

    let changeSet = null;
    const changeSetChunks = [];
    if (result.changedVariantIds.length) {
      const chunkSize = WISHLIST_CHANGESET_MAX_VARIANTS_V1;
      for (let i = 0; i < result.changedVariantIds.length; i += chunkSize) {
        const variantChunk = result.changedVariantIds.slice(i, i + chunkSize);
        // Offer/size IDs are included on the first chunk only to avoid
        // unbounded expansion; variant IDs remain the fanout authority.
        const chunk = normalizeCatalogChangeSet({
          source: CHANGESET_SOURCES.CATALOG_SYNC,
          syncRunId: i === 0 ? runId : `${runId}__chunk_${Math.floor(i / chunkSize)}`,
          catalogRevision: i === 0 ?
            catalogRevision : `${catalogRevision}__chunk_${Math.floor(i / chunkSize)}`,
          successfulVerificationAt: now,
          changedVariantIds: variantChunk,
          changedOfferIds: i === 0 ? result.changedOfferIds : [],
          changedSizeIds: i === 0 ? result.changedSizeIds : [],
        });
        changeSetChunks.push(chunk);
        if (typeof onCatalogChangeSet === "function") {
          await onCatalogChangeSet(chunk);
        }
      }
      changeSet = changeSetChunks[0];
      metrics.fanoutChangedVariantCount = result.changedVariantIds.length;
      metrics.changeSetChunkCount = changeSetChunks.length;
    }

    if (typeof metricsSink === "function") metricsSink(metrics);

    return {
      runId,
      ...result,
      changeSet,
      changeSetChunks,
      metrics,
      capabilitiesUsed: {
        pagination: hasCapability(caps, PARTNER_CAPABILITY.PAGINATION),
        full: mode === SYNC_MODE.FULL,
        incremental: mode === SYNC_MODE.INCREMENTAL,
      },
    };
  } catch (error) {
    metrics.durationMs = Date.now() - startedAtMs;
    metrics.recordsRejected = Math.max(
      metrics.recordsRejected, metrics.recordsFetched - metrics.recordsAccepted,
    );
    await repository.failSyncRun(runId, error.code || error.message ||
      "partner_sync_failed");
    const staleVariants = await repository.markPartnerCatalogStale(
      publicPartner.partnerId,
    );
    for (const variantId of staleVariants) {
      await repository.regenerateProjection(variantId);
    }
    if (typeof metricsSink === "function") metricsSink(metrics);
    // Failed sync MUST NOT emit a completing CatalogChangeSet / Wishlist fanout.
    throw error;
  }
}

function normalizeRawPartnerRecord(adapter, raw, {now}) {
  if (!raw || typeof raw !== "object") {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_PAYLOAD,
      "partner_raw_record_invalid",
    );
  }
  // Prefer atomic normalizeRecord when adapters provide it (synthetic fixtures).
  if (typeof adapter.normalizeRecord === "function") {
    return adapter.normalizeRecord(raw, {now});
  }
  const product = adapter.normalizeProduct(raw, {now});
  const variant = adapter.normalizeVariant(raw, {product, now});
  const promotions = adapter.normalizePromotions(raw, {now});
  const offer = adapter.normalizeOffer(raw, {variant, promotions, now});
  const sizes = adapter.normalizeSizes(raw, {offer, now});
  const images = adapter.normalizeImages(raw, {now});
  return {
    contractVersion: CONTRACT_VERSION,
    product,
    variant,
    offer,
    sizes,
    imageCandidates: images.candidates,
    imageStatus: images.imageStatus,
    freshness: {
      sourceObservedAt: raw.observedAt || now,
      receivedAt: now,
      lastSuccessfulVerificationAt: now,
      stale: false,
    },
  };
}

/**
 * In-memory checkpoint store for tests / local qualification.
 */
function createMemoryCheckpointStore() {
  const map = new Map();
  return {
    async load(partnerId) {
      return map.get(partnerId) || null;
    },
    async save(partnerId, checkpoint) {
      map.set(partnerId, checkpoint ? {...checkpoint} : null);
    },
    dump() {
      return Object.fromEntries(map.entries());
    },
  };
}

module.exports = {
  AFFILIATE_RANKING_INPUT_COUNT,
  PARTNER_POLLING_COUNT,
  REAL_PARTNER_API_REQUESTS,
  createMemoryCheckpointStore,
  normalizeRawPartnerRecord,
  persistNormalizedRecords,
  runPartnerSync,
};
