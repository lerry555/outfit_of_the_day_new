"use strict";

const COLLECTION = "wardrobeAuthorityShadowLeases";
const STORE_ID = "WardrobeAdminControlledWriteLeaseStore/v1";

function createAdminControlledWriteLeaseStore({firestore}) {
  if (!firestore || typeof firestore.runTransaction !== "function") {
    throw new Error("controlled_write_lease_firestore_required");
  }
  return Object.freeze({storeId: STORE_ID,
    async consumeAtomically(leaseId, callback) {
      if (typeof leaseId !== "string" || !leaseId.trim()) {
        return denied("controlled_write_lease_invalid");
      }
      const ref = firestore.collection(COLLECTION).doc(leaseId);
      try {
        return await firestore.runTransaction(async (transaction) => {
          const snapshot = await transaction.get(ref);
          if (!snapshot.exists) return denied("controlled_write_lease_missing");
          const decision = callback(snapshot.data());
          if (decision && decision.next) {
            transaction.set(ref, decision.next, {merge: false});
          }
          return decision && (decision.result || decision);
        });
      } catch (_) { return denied("controlled_write_lease_invalid"); }
    }});
}
function denied(reasonCode) { return Object.freeze({ok: false,
  contractId: "ControlledWriteSingleUseLease/v1", reasonCode}); }
module.exports = {COLLECTION, STORE_ID, createAdminControlledWriteLeaseStore};
