"use strict";

// Admin claim repair for users/{uid}.fcmTokens.
// Lookup: collectionGroup-free query
//   users where fcmTokens array-contains token
// Single-field array-contains is auto-indexed. No reverse token index:
// expected owner cardinality per token is tiny (stale logout leftovers).
// Race: transactions cannot query, so owners are loaded first then re-read
// by id. Perfect global atomicity is not possible with the flat array
// schema; a later successful claim repairs leftover dual ownership.

const crypto = require("crypto");

const MIN_TOKEN_LENGTH = 32;
const MAX_TOKEN_LENGTH = 4096;
const MAX_OWNER_DOCS = 50;

class ClaimFcmTokenError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function tokenFingerprint(token) {
  return crypto.createHash("sha256").update(token).digest("hex").slice(0, 12);
}

function normalizeToken(raw) {
  if (typeof raw !== "string") {
    throw new ClaimFcmTokenError("invalid-argument", "invalid_token");
  }
  const token = raw.trim();
  if (!token ||
      token.length < MIN_TOKEN_LENGTH ||
      token.length > MAX_TOKEN_LENGTH ||
      /\s/.test(token)) {
    throw new ClaimFcmTokenError("invalid-argument", "invalid_token");
  }
  return token;
}

function createClaimFcmTokenService({
  db,
  FieldValue,
  logger = {warn() {}},
}) {
  if (!db || !FieldValue) {
    throw new Error("claim_fcm_token_dependencies_required");
  }

  async function findOtherOwnerIds(uid, token) {
    const ownersSnap = await db.collection("users")
      .where("fcmTokens", "array-contains", token)
      .limit(MAX_OWNER_DOCS)
      .get();
    return ownersSnap.docs
      .map((doc) => doc.id)
      .filter((id) => id && id !== uid);
  }

  async function applyClaim(uid, token) {
    const otherIds = await findOtherOwnerIds(uid, token);
    await db.runTransaction(async (tx) => {
      const currentRef = db.collection("users").doc(uid);
      const otherRefs = otherIds.map((id) => db.collection("users").doc(id));
      // Firestore requires all transaction reads before writes.
      await tx.get(currentRef);
      for (const ref of otherRefs) {
        await tx.get(ref);
      }
      for (const ref of otherRefs) {
        tx.set(ref, {fcmTokens: FieldValue.arrayRemove(token)}, {merge: true});
      }
      tx.set(
          currentRef,
          {fcmTokens: FieldValue.arrayUnion(token)},
          {merge: true},
      );
    });
    return otherIds.length;
  }

  async function claimForUid(uid, rawToken) {
    if (!uid) {
      throw new ClaimFcmTokenError("unauthenticated", "unauthenticated");
    }
    const token = normalizeToken(rawToken);
    const fingerprint = tokenFingerprint(token);

    // Query-then-transaction: Firestore transactions cannot contain queries.
    // A concurrent claimant missing from the snapshot can still dual-own
    // briefly. One bounded follow-up pass repairs leftovers visible after
    // commit. A later successful claim also repairs any residual race.
    let otherOwnerCount = await applyClaim(uid, token);
    const leftover = await findOtherOwnerIds(uid, token);
    if (leftover.length) {
      otherOwnerCount += await applyClaim(uid, token);
    }

    if (otherOwnerCount > 0) {
      logger.warn("claimFcmToken repaired stale owners", {
        tokenFingerprint: fingerprint,
        otherOwnerCount,
      });
    }
    return {ok: true};
  }

  return {claimForUid, normalizeToken, tokenFingerprint};
}

function createClaimFcmTokenHandler({
  db,
  FieldValue,
  logger,
  httpsError,
}) {
  const service = createClaimFcmTokenService({db, FieldValue, logger});
  return async function claimFcmToken(data, context) {
    const uid = context && context.auth && context.auth.uid;
    if (!uid) {
      throw httpsError("unauthenticated", "unauthenticated");
    }
    try {
      const token = data && typeof data === "object" ? data.token : data;
      return await service.claimForUid(uid, token);
    } catch (error) {
      if (error instanceof ClaimFcmTokenError) {
        throw httpsError(error.code, error.message);
      }
      throw error;
    }
  };
}

module.exports = {
  ClaimFcmTokenError,
  createClaimFcmTokenHandler,
  createClaimFcmTokenService,
  normalizeToken,
  tokenFingerprint,
};
