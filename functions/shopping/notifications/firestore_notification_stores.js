"use strict";

function createFirestoreWishlistTokenStore(db) {
  return {
    async getTokens(uid) {
      const snapshot = await db.collection("users").doc(uid).get();
      const values = snapshot.exists ? snapshot.data().fcmTokens : [];
      return Array.isArray(values) ?
        values.map((value) => String(value || "").trim()).filter(Boolean) : [];
    },
    async removeTokens(uid, tokens) {
      if (!tokens.length) return;
      const admin = require("firebase-admin");
      await db.collection("users").doc(uid).set({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokens),
      }, {merge: true});
    },
  };
}

function createFirestoreWishlistEventStore(db) {
  return {
    async filterPending(eventIds) {
      const result = [];
      for (const eventId of eventIds) {
        const snapshot = await db.collection("wishlistEvents").doc(eventId).get();
        if (!snapshot.exists) continue;
        const status = snapshot.data().delivery?.status;
        if (!["DELIVERED", "SKIPPED"].includes(status)) result.push(eventId);
      }
      return result;
    },
    async markDelivered(eventIds, receipt) {
      await update(eventIds, {
        status: "DELIVERED",
        acceptedAt: new Date(receipt.acceptedAt),
        acceptedDeviceCount: receipt.acceptedDeviceCount,
      });
    },
    async markSkipped(eventIds, reason) {
      await update(eventIds, {
        status: "SKIPPED",
        reason,
        completedAt: new Date(),
      });
    },
    async markFailed(eventIds, code) {
      const batch = db.batch();
      for (const eventId of eventIds) {
        const ref = db.collection("wishlistEvents").doc(eventId);
        batch.set(ref, {
          delivery: {
            status: "FAILED",
            lastErrorCode: code,
            lastAttemptAt: new Date(),
          },
        }, {merge: true});
      }
      if (eventIds.length) await batch.commit();
    },
  };
  async function update(eventIds, delivery) {
    const batch = db.batch();
    for (const eventId of eventIds) {
      batch.set(db.collection("wishlistEvents").doc(eventId), {delivery}, {merge: true});
    }
    if (eventIds.length) await batch.commit();
  }
}

module.exports = {
  createFirestoreWishlistEventStore,
  createFirestoreWishlistTokenStore,
};
