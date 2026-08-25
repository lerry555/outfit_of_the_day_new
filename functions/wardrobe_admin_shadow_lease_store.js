"use strict";

const COLLECTION = "wardrobeAuthorityShadowLeases";
const STORE_ID = "WardrobeAdminShadowLeaseStore/v1";

/** Admin-SDK-only control-plane adapter. Construction performs no I/O. */
function createAdminShadowLeaseStore({firestore}) {
  if (!firestore || typeof firestore.runTransaction !== "function") {
    throw new Error("shadow_lease_firestore_required");
  }
  return Object.freeze({
    storeId: STORE_ID,
    async read(leaseId) {
      if (typeof leaseId !== "string" || !leaseId.trim()) {
        return denied("shadow_lease_id_invalid");
      }
      try {
        const snapshot = await firestore.collection(COLLECTION).doc(leaseId).get();
        return snapshot.exists ? Object.freeze({ok: true, lease: snapshot.data()}) :
          denied("shadow_lease_missing");
      } catch (_) {
        return denied("shadow_lease_read_failed");
      }
    },
    async consumeAtomically(leaseId, callback) {
      if (typeof leaseId !== "string" || !leaseId.trim()) {
        return denied("shadow_lease_id_invalid");
      }
      const ref = firestore.collection(COLLECTION).doc(leaseId);
      try {
        return await firestore.runTransaction(async (transaction) => {
          const snapshot = await transaction.get(ref);
          if (!snapshot.exists) return denied("shadow_lease_missing");
          const decision = callback(snapshot.data());
          if (decision && decision.next) {
            transaction.set(ref, decision.next, {merge: false});
          }
          return decision && (decision.result || decision);
        });
      } catch (error) {
        if (error && /^shadow_lease_/.test(error.message || "")) throw error;
        return denied("shadow_lease_transaction_failed");
      }
    },
  });
}

function denied(reasonCode) {
  return Object.freeze({ok: false, contractId: "SingleUseShadowLease/v1",
    reasonCode});
}

module.exports = {COLLECTION, STORE_ID, createAdminShadowLeaseStore};
