"use strict";

const {COLLECTIONS} = require("./catalog_repository");

/**
 * Projection-first reader. The projection provides the bounded Variant
 * universe; authoritative Variant, Offer, and Size documents supply final
 * constraint and purchasability facts. No partner raw payload is read.
 */
function createFirestoreCatalogSearchRepository(db, {scanLimit = 200} = {}) {
  if (!db || typeof db.collection !== "function") {
    throw new Error("shopping_search_firestore_repository_requires_db");
  }
  return {
    async readCompleteSnapshot() {
      const [projectionSnapshot, variantsSnapshot, productsSnapshot, offersSnapshot,
        sizesSnapshot, partnersSnapshot] =
        await Promise.all([
          db.collection(COLLECTIONS.projections).limit(scanLimit + 1).get(),
          db.collection(COLLECTIONS.variants).get(),
          db.collection(COLLECTIONS.products).get(),
          db.collection(COLLECTIONS.offers).get(),
          db.collectionGroup("sizes").get(),
          db.collection(COLLECTIONS.partners).get(),
        ]);
      const projectionDocs = projectionSnapshot.docs.map((doc) => doc.data());
      const complete = projectionDocs.length <= scanLimit;
      const allowedIds = new Set(projectionDocs.slice(0, scanLimit).map((doc) => doc.variantId));
      return {
        products: productsSnapshot.docs.map((doc) => doc.data()),
        variants: variantsSnapshot.docs.map((doc) => doc.data())
          .filter((variant) => allowedIds.has(variant.variantId)),
        offers: offersSnapshot.docs.map((doc) => doc.data())
          .filter((offer) => allowedIds.has(offer.variantId)),
        sizes: sizesSnapshot.docs.map((doc) => doc.data()),
        partners: partnersSnapshot.docs.map((doc) => doc.data()),
        scanLimit: complete ? Infinity : scanLimit,
        firestoreQueryCount: 6,
      };
    },
  };
}

function createMemoryCatalogSearchRepository(catalog, {scanLimit = Infinity} = {}) {
  const snapshot = structuredClone(catalog);
  return {
    async readCompleteSnapshot() {
      return {...structuredClone(snapshot), scanLimit, firestoreQueryCount: 0};
    },
  };
}

module.exports = {
  createFirestoreCatalogSearchRepository,
  createMemoryCatalogSearchRepository,
};
