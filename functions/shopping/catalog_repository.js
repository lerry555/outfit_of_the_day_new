"use strict";

const {
  LIFECYCLE,
  effectivePublicPrice,
  productIdentityKeys,
  variantIdentityKeys,
} = require("./catalog_contract");

const COLLECTIONS = Object.freeze({
  partners: "catalogPartners",
  products: "catalogProducts",
  variants: "catalogVariants",
  offers: "catalogOffers",
  projections: "catalogSearchVariants",
  identityIndex: "catalogIdentityIndex",
  integrations: "partnerIntegrations",
  syncStates: "catalogSyncStates",
  syncRuns: "catalogSyncRuns",
});

function clone(value) {
  return structuredClone(value);
}

/**
 * In-memory implementation used by deterministic sync tests. Its public
 * methods deliberately mirror the Firestore repository.
 */
function createMemoryCatalogRepository() {
  const collections = Object.fromEntries(
    Object.values(COLLECTIONS).map((name) => [name, new Map()]),
  );
  const sizes = new Map();

  function identityKey(kind, key) {
    return `${kind}:${key}`;
  }

  return {
    async upsertPartner(partner) {
      collections[COLLECTIONS.partners].set(partner.partnerId, clone(partner));
    },
    async resolveProduct(entity) {
      return resolveIdentity(
        "product",
        productIdentityKeys(entity.identityEvidence),
        entity.candidateId,
      );
    },
    async resolveVariant(entity) {
      return resolveIdentity(
        "variant",
        variantIdentityKeys(entity.identityEvidence),
        entity.candidateId,
      );
    },
    async upsertProduct(product) {
      collections[COLLECTIONS.products].set(product.productId, clone(product));
    },
    async upsertVariant(variant) {
      collections[COLLECTIONS.variants].set(variant.variantId, clone(variant));
    },
    async upsertOffer(offer) {
      collections[COLLECTIONS.offers].set(offer.offerId, clone(offer));
    },
    async upsertSizes(offerId, values) {
      for (const value of values) {
        sizes.set(`${offerId}:${value.normalizedSizeKey}`, clone(value));
      }
    },
    async regenerateProjection(variantId) {
      const variant = collections[COLLECTIONS.variants].get(variantId);
      if (!variant) return;
      const product = collections[COLLECTIONS.products].get(variant.productId);
      const activeOffers = [...collections[COLLECTIONS.offers].values()]
        .filter((offer) => offer.variantId === variantId)
        .filter((offer) => offer.lifecycleState !== LIFECYCLE.DISCONTINUED);
      collections[COLLECTIONS.projections].set(
        variantId,
        buildSearchProjection({variant, product, activeOffers}),
      );
    },
    async discontinueMissingPartnerOffers(partnerId, seenOfferIds) {
      const changedVariants = new Set();
      for (const offer of collections[COLLECTIONS.offers].values()) {
        if (offer.partnerId !== partnerId || seenOfferIds.has(offer.offerId)) continue;
        if (offer.lifecycleState !== LIFECYCLE.DISCONTINUED) {
          offer.lifecycleState = LIFECYCLE.DISCONTINUED;
          changedVariants.add(offer.variantId);
        }
      }
      return [...changedVariants];
    },
    async markPartnerCatalogStale(partnerId) {
      const changedVariants = new Set();
      for (const offer of collections[COLLECTIONS.offers].values()) {
        if (offer.partnerId !== partnerId) continue;
        offer.freshness = {...(offer.freshness || {}), stale: true};
        changedVariants.add(offer.variantId);
      }
      return [...changedVariants];
    },
    async updateVariantLifecycle(variantId) {
      const variant = collections[COLLECTIONS.variants].get(variantId);
      if (!variant) return;
      const offers = [...collections[COLLECTIONS.offers].values()]
        .filter((offer) => offer.variantId === variantId);
      variant.lifecycleState = calculateVariantLifecycle(offers);
    },
    async beginSyncRun(run) {
      collections[COLLECTIONS.syncRuns].set(run.runId, clone(run));
      const previous = collections[COLLECTIONS.syncStates].get(run.partnerId) || {};
      collections[COLLECTIONS.syncStates].set(run.partnerId, {
        ...previous,
        partnerId: run.partnerId,
        status: "RUNNING",
        lastAttemptAt: run.startedAt,
      });
    },
    async completeSyncRun(runId, state) {
      const run = collections[COLLECTIONS.syncRuns].get(runId);
      Object.assign(run, clone(state), {status: "COMPLETED"});
      collections[COLLECTIONS.syncStates].set(run.partnerId, {
        partnerId: run.partnerId,
        status: "COMPLETED",
        lastSuccessfulRunId: runId,
        lastSuccessfulAt: state.completedAt,
      });
    },
    async failSyncRun(runId, error) {
      const run = collections[COLLECTIONS.syncRuns].get(runId);
      Object.assign(run, {status: "FAILED", errorCode: error, completedAt: new Date().toISOString()});
      const previous = collections[COLLECTIONS.syncStates].get(run.partnerId) || {};
      collections[COLLECTIONS.syncStates].set(run.partnerId, {
        ...previous,
        partnerId: run.partnerId,
        status: "FAILED",
        lastAttemptAt: run.startedAt,
        lastFailureCode: error,
      });
    },
    dump() {
      return {
        partners: dump(COLLECTIONS.partners),
        products: dump(COLLECTIONS.products),
        variants: dump(COLLECTIONS.variants),
        offers: dump(COLLECTIONS.offers),
        projections: dump(COLLECTIONS.projections),
        syncStates: dump(COLLECTIONS.syncStates),
        syncRuns: dump(COLLECTIONS.syncRuns),
        sizes: Object.fromEntries([...sizes.entries()].map(([key, value]) => [key, clone(value)])),
      };
    },
    get(collection, id) {
      const value = collections[collection]?.get(id);
      return value == null ? null : clone(value);
    },
  };

  function resolveIdentity(kind, keys, fallbackId) {
    for (const key of keys) {
      const existing = collections[COLLECTIONS.identityIndex].get(identityKey(kind, key));
      if (existing) return existing.entityId;
    }
    for (const key of keys) {
      collections[COLLECTIONS.identityIndex].set(identityKey(kind, key), {
        entityId: fallbackId,
      });
    }
    return fallbackId;
  }

  function dump(name) {
    return Object.fromEntries(
      [...collections[name].entries()].map(([key, value]) => [key, clone(value)]),
    );
  }
}

/// Optional Admin Firestore implementation. It is never invoked by fixtures
/// unless a backend explicitly supplies an Admin Firestore instance.
function createFirestoreCatalogRepository(db) {
  if (!db || typeof db.collection !== "function") {
    throw new Error("shopping_catalog_firestore_repository_requires_db");
  }
  return {
    async upsertPartner(partner) {
      await db.collection(COLLECTIONS.partners).doc(partner.partnerId).set(partner, {merge: true});
    },
    async resolveProduct(entity) {
      return resolveFirestoreIdentity(db, "product", productIdentityKeys(entity.identityEvidence), entity.candidateId);
    },
    async resolveVariant(entity) {
      return resolveFirestoreIdentity(db, "variant", variantIdentityKeys(entity.identityEvidence), entity.candidateId);
    },
    async upsertProduct(product) {
      await db.collection(COLLECTIONS.products).doc(product.productId).set(product, {merge: true});
    },
    async upsertVariant(variant) {
      await db.collection(COLLECTIONS.variants).doc(variant.variantId).set(variant, {merge: true});
    },
    async upsertOffer(offer) {
      await db.collection(COLLECTIONS.offers).doc(offer.offerId).set(offer, {merge: true});
    },
    async upsertSizes(offerId, values) {
      const batch = db.batch();
      for (const value of values) {
        batch.set(
          db.collection(COLLECTIONS.offers).doc(offerId).collection("sizes").doc(value.normalizedSizeKey),
          value,
          {merge: true},
        );
      }
      if (values.length) await batch.commit();
    },
    async regenerateProjection(variantId) {
      const variantSnapshot = await db.collection(COLLECTIONS.variants).doc(variantId).get();
      if (!variantSnapshot.exists) return;
      const variant = variantSnapshot.data();
      const productSnapshot = await db.collection(COLLECTIONS.products).doc(variant.productId).get();
      const offerSnapshot = await db.collection(COLLECTIONS.offers)
        .where("variantId", "==", variantId).get();
      const activeOffers = offerSnapshot.docs.map((doc) => doc.data())
        .filter((offer) => offer.lifecycleState !== LIFECYCLE.DISCONTINUED);
      await db.collection(COLLECTIONS.projections).doc(variantId).set(
        buildSearchProjection({
          variant,
          product: productSnapshot.exists ? productSnapshot.data() : null,
          activeOffers,
        }),
        {merge: true},
      );
    },
    async discontinueMissingPartnerOffers(partnerId, seenOfferIds) {
      const snapshot = await db.collection(COLLECTIONS.offers)
        .where("partnerId", "==", partnerId).get();
      const changedVariants = new Set();
      const batch = db.batch();
      for (const doc of snapshot.docs) {
        if (seenOfferIds.has(doc.id) || doc.data().lifecycleState === LIFECYCLE.DISCONTINUED) continue;
        batch.set(doc.ref, {lifecycleState: LIFECYCLE.DISCONTINUED}, {merge: true});
        changedVariants.add(doc.data().variantId);
      }
      if (changedVariants.size) await batch.commit();
      return [...changedVariants];
    },
    async markPartnerCatalogStale(partnerId) {
      const snapshot = await db.collection(COLLECTIONS.offers)
        .where("partnerId", "==", partnerId).get();
      const batch = db.batch();
      const changedVariants = new Set();
      for (const doc of snapshot.docs) {
        const offer = doc.data();
        batch.set(doc.ref, {
          freshness: {...(offer.freshness || {}), stale: true},
        }, {merge: true});
        changedVariants.add(offer.variantId);
      }
      if (changedVariants.size) await batch.commit();
      return [...changedVariants];
    },
    async updateVariantLifecycle(variantId) {
      const snapshot = await db.collection(COLLECTIONS.offers)
        .where("variantId", "==", variantId).get();
      const lifecycleState = calculateVariantLifecycle(snapshot.docs.map((doc) => doc.data()));
      await db.collection(COLLECTIONS.variants).doc(variantId).set({lifecycleState}, {merge: true});
    },
    async beginSyncRun(run) {
      await db.collection(COLLECTIONS.syncRuns).doc(run.runId).set(run);
      await db.collection(COLLECTIONS.syncStates).doc(run.partnerId).set({
        partnerId: run.partnerId, status: "RUNNING", lastAttemptAt: run.startedAt,
      }, {merge: true});
    },
    async completeSyncRun(runId, state) {
      const run = await db.collection(COLLECTIONS.syncRuns).doc(runId).get();
      const partnerId = run.data().partnerId;
      await db.collection(COLLECTIONS.syncRuns).doc(runId).set({...state, status: "COMPLETED"}, {merge: true});
      await db.collection(COLLECTIONS.syncStates).doc(partnerId).set({
        partnerId, status: "COMPLETED", lastSuccessfulRunId: runId,
        lastSuccessfulAt: state.completedAt,
      }, {merge: true});
    },
    async failSyncRun(runId, error) {
      const run = await db.collection(COLLECTIONS.syncRuns).doc(runId).get();
      const partnerId = run.data().partnerId;
      await db.collection(COLLECTIONS.syncRuns).doc(runId).set({
        status: "FAILED", errorCode: error, completedAt: new Date().toISOString(),
      }, {merge: true});
      await db.collection(COLLECTIONS.syncStates).doc(partnerId).set({
        partnerId, status: "FAILED", lastFailureCode: error,
      }, {merge: true});
    },
  };
}

async function resolveFirestoreIdentity(db, kind, keys, fallbackId) {
  for (const key of keys) {
    const ref = db.collection(COLLECTIONS.identityIndex).doc(`${kind}__${encodeURIComponent(key)}`);
    const snapshot = await ref.get();
    if (snapshot.exists) return snapshot.data().entityId;
  }
  const batch = db.batch();
  for (const key of keys) {
    batch.set(
      db.collection(COLLECTIONS.identityIndex).doc(`${kind}__${encodeURIComponent(key)}`),
      {entityId: fallbackId, kind, evidenceKey: key},
      {merge: true},
    );
  }
  if (keys.length) await batch.commit();
  return fallbackId;
}

function calculateVariantLifecycle(offers) {
  if (!offers.length) return LIFECYCLE.UNKNOWN_OR_STALE;
  const active = offers.filter((offer) => offer.lifecycleState !== LIFECYCLE.DISCONTINUED);
  if (!active.length) return LIFECYCLE.DISCONTINUED;
  if (active.some((offer) => offer.overallAvailability === "AVAILABLE")) {
    return LIFECYCLE.ACTIVE;
  }
  if (active.every((offer) => offer.overallAvailability === "UNAVAILABLE")) {
    return LIFECYCLE.UNAVAILABLE;
  }
  return LIFECYCLE.UNKNOWN_OR_STALE;
}

function buildSearchProjection({variant, product, activeOffers}) {
  return {
    projectionVersion: 1,
    variantId: variant.variantId,
    productId: variant.productId,
    canonicalType: product?.canonicalType || null,
    canonicalFamily: product?.canonicalFamily || null,
    brand: product?.brand || null,
    exactColorName: variant.exactColorName,
    colorFamilies: [variant.colorProfile?.primary?.family].filter(Boolean),
    fit: variant.fit || null,
    material: variant.material || null,
    pattern: variant.pattern || null,
    styles: variant.styles || [],
    activeOfferIds: activeOffers.map((offer) => offer.offerId).sort(),
    freshness: {
      stale: activeOffers.length > 0 &&
        activeOffers.every((offer) => offer.freshness?.stale === true),
    },
    // Intentionally no "from" price: price and availability are offer/size
    // scoped and must be resolved by the exact Variant request.
    offerSummaryScope: "variant_offer_not_size_specific",
  };
}

module.exports = {
  COLLECTIONS,
  buildSearchProjection,
  calculateVariantLifecycle,
  createFirestoreCatalogRepository,
  createMemoryCatalogRepository,
};
