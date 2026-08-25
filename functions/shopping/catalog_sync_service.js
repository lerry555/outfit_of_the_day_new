"use strict";

const {CONTRACT_VERSION} = require("./catalog_contract");

const SNAPSHOT_SCOPE = Object.freeze({
  FULL: "FULL",
  PARTIAL: "PARTIAL",
});

async function syncFixtureSnapshot({
  adapter,
  rawRecords,
  repository,
  snapshotScope,
  runId,
  now = new Date().toISOString(),
}) {
  if (!adapter || !repository) {
    throw new Error("shopping_catalog_sync_dependencies_required");
  }
  if (!Object.values(SNAPSHOT_SCOPE).includes(snapshotScope)) {
    throw new Error("shopping_catalog_invalid_snapshot_scope");
  }
  const records = Array.isArray(rawRecords) ? rawRecords : null;
  if (!records) throw new Error("shopping_catalog_snapshot_records_required");

  const run = {
    contractVersion: CONTRACT_VERSION,
    runId,
    partnerId: adapter.partner.partnerId,
    snapshotScope,
    startedAt: now,
    status: "RUNNING",
    recordCount: records.length,
  };
  await repository.beginSyncRun(run);
  try {
    // Normalize the complete snapshot before changing catalog truth. A malformed
    // record therefore only creates a failed run, never a partial catalog write.
    const normalized = records.map((record) => adapter.normalize(record));
    await repository.upsertPartner(adapter.partner);
    const changedVariants = new Set();
    const seenOfferIds = new Set();
    let productsWritten = 0;
    let variantsWritten = 0;
    let offersWritten = 0;
    let sizesWritten = 0;

    for (const record of normalized) {
      const productId = await repository.resolveProduct(record.product);
      const {candidateId: ignoredProductCandidate, ...productFields} = record.product;
      await repository.upsertProduct({
        ...productFields,
        productId,
        freshness: record.freshness,
      });
      productsWritten++;

      const variantId = await repository.resolveVariant(record.variant);
      const {
        candidateId: ignoredVariantCandidate,
        productCandidateId: ignoredProductCandidateId,
        ...variantFields
      } = record.variant;
      await repository.upsertVariant({
        ...variantFields,
        variantId,
        productId,
        freshness: record.freshness,
      });
      variantsWritten++;

      await repository.upsertOffer({
        ...record.offer,
        variantId,
        freshness: record.freshness,
      });
      await repository.upsertSizes(record.offer.offerId, record.sizes);
      seenOfferIds.add(record.offer.offerId);
      changedVariants.add(variantId);
      offersWritten++;
      sizesWritten += record.sizes.length;
    }

    if (snapshotScope === SNAPSHOT_SCOPE.FULL) {
      const discontinuedVariants = await repository.discontinueMissingPartnerOffers(
        adapter.partner.partnerId,
        seenOfferIds,
      );
      for (const variantId of discontinuedVariants) changedVariants.add(variantId);
    }

    for (const variantId of changedVariants) {
      await repository.updateVariantLifecycle(variantId);
      await repository.regenerateProjection(variantId);
    }

    const result = {
      completedAt: now,
      productsWritten,
      variantsWritten,
      offersWritten,
      sizesWritten,
      changedVariantIds: [...changedVariants].sort(),
      changedOfferIds: [...seenOfferIds].sort(),
      changedSizeIds: [],
      catalogRevision: `rev_${runId}_${changedVariants.size}`,
      successfulVerificationAt: now,
    };
    await repository.completeSyncRun(runId, result);
    return {runId, ...result};
  } catch (error) {
    await repository.failSyncRun(runId, error.message || "shopping_catalog_sync_failed");
    const staleVariants = await repository.markPartnerCatalogStale(
      adapter.partner.partnerId,
    );
    for (const variantId of staleVariants) {
      await repository.regenerateProjection(variantId);
    }
    throw error;
  }
}

module.exports = {
  SNAPSHOT_SCOPE,
  syncFixtureSnapshot,
};
