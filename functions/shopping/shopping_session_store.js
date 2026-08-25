"use strict";

const crypto = require("crypto");

const SESSION_SCHEMA_VERSION = 1;
const MAX_SESSION_POOL_CANDIDATES = 500;
const MAX_OPERATION_RECEIPTS = 24;

class ShoppingSessionStoreError extends Error {
  constructor(code, message = code) {
    super(message);
    this.code = code;
  }
}

function createMemoryShoppingSessionStore({now = () => Date.now()} = {}) {
  const sessions = new Map();
  const idempotency = new Map();
  return {
    now,
    async get(id) { return clone(sessions.get(id) || null); },
    async put(session) {
      const normalized = normalizeSession(session);
      sessions.set(normalized.sessionId, clone(normalized));
      return clone(normalized);
    },
    async getIdempotency(uid, key) { return idempotency.get(`${uid}:${key}`) || null; },
    async putIdempotency(uid, key, sessionId) { idempotency.set(`${uid}:${key}`, sessionId); },
    async createSession({session, idempotencyKey = null}) {
      const idKey = idempotencyKey && `${session.ownerUid}:${idempotencyKey}`;
      const existingId = idKey && idempotency.get(idKey);
      const existing = existingId && sessions.get(existingId);
      if (existing && !isExpired(existing, now())) return {created: false, session: clone(existing)};
      const normalized = normalizeSession(session);
      sessions.set(normalized.sessionId, clone(normalized));
      if (idKey) idempotency.set(idKey, normalized.sessionId);
      return {created: true, session: clone(normalized)};
    },
    async mutate(sessionId, {ownerUid, expectedVersion = null, operationId = null, operationType = null}, mutate) {
      const session = sessions.get(sessionId);
      if (!session) throw new ShoppingSessionStoreError("SESSION_NOT_FOUND");
      validateStoredSession(session);
      if (session.ownerUid !== ownerUid) throw new ShoppingSessionStoreError("SESSION_FORBIDDEN");
      if (isExpired(session, now())) throw new ShoppingSessionStoreError("SESSION_EXPIRED");
      if (expectedVersion != null && session.version !== expectedVersion) {
        throw new ShoppingSessionStoreError("SESSION_CONFLICT");
      }
      const receipt = getReceipt(session, operationId, operationType);
      if (receipt) return {session: clone(session), result: clone(receipt.result), replayed: true};
      const outcome = await mutate(clone(session));
      const next = normalizeSession({...outcome.session, version: session.version + 1, updatedAt: now()});
      if (operationId) next.operationReceipts = appendReceipt(
        next.operationReceipts, operationId, operationType, outcome.result);
      sessions.set(sessionId, clone(next));
      return {session: clone(next), result: clone(outcome.result), replayed: false};
    },
    dump() { return structuredClone([...sessions.values()]); },
  };
}

function createFirestoreShoppingSessionStore(db, {now = () => Date.now()} = {}) {
  if (!db || typeof db.collection !== "function" || typeof db.runTransaction !== "function") {
    throw new Error("shopping_session_firestore_store_requires_admin_firestore");
  }
  const sessions = db.collection("shoppingSessions");
  const idempotency = db.collection("shoppingSessionIdempotency");
  return {
    now,
    async get(sessionId) {
      const snapshot = await sessions.doc(sessionId).get();
      return snapshot.exists ? decodeSession(snapshot.data()) : null;
    },
    async put(session) {
      const normalized = normalizeSession(session);
      await sessions.doc(normalized.sessionId).set(encodeSession(normalized));
      return normalized;
    },
    async getIdempotency(uid, key) {
      const snapshot = await idempotency.doc(idempotencyDocumentId(uid, key)).get();
      if (!snapshot.exists) return null;
      const value = snapshot.data();
      const expiry = value?.expiresAt == null ? null : toMillis(value.expiresAt);
      return value?.ownerUid === uid && typeof value.sessionId === "string" &&
        (expiry == null || expiry > now()) ? value.sessionId : null;
    },
    async putIdempotency(uid, key, sessionId) {
      await idempotency.doc(idempotencyDocumentId(uid, key)).set({
        ownerUid: uid, sessionId, updatedAt: new Date(now()), expiresAt: new Date(now()),
      });
    },
    async createSession({session, idempotencyKey = null}) {
      const normalized = normalizeSession(session);
      const sessionRef = sessions.doc(normalized.sessionId);
      const mappingRef = idempotencyKey ?
        idempotency.doc(idempotencyDocumentId(normalized.ownerUid, idempotencyKey)) : null;
      return db.runTransaction(async (transaction) => {
        if (mappingRef) {
          const mapping = await transaction.get(mappingRef);
          if (mapping.exists) {
            const existingRef = sessions.doc(String(mapping.data()?.sessionId || ""));
            const existing = await transaction.get(existingRef);
            if (existing.exists) {
              const decoded = decodeSession(existing.data());
              if (!isExpired(decoded, now()) && decoded.ownerUid === normalized.ownerUid) {
                return {created: false, session: decoded};
              }
            }
          }
        }
        transaction.create(sessionRef, encodeSession(normalized));
        if (mappingRef) {
          transaction.set(mappingRef, {
            ownerUid: normalized.ownerUid,
            sessionId: normalized.sessionId,
            updatedAt: new Date(now()),
            expiresAt: new Date(normalized.expiresAt),
          });
        }
        return {created: true, session: normalized};
      });
    },
    async mutate(sessionId, {ownerUid, expectedVersion = null, operationId = null, operationType = null}, mutate) {
      const sessionRef = sessions.doc(sessionId);
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(sessionRef);
        if (!snapshot.exists) throw new ShoppingSessionStoreError("SESSION_NOT_FOUND");
        const session = decodeSession(snapshot.data());
        if (session.ownerUid !== ownerUid) throw new ShoppingSessionStoreError("SESSION_FORBIDDEN");
        if (isExpired(session, now())) throw new ShoppingSessionStoreError("SESSION_EXPIRED");
        if (expectedVersion != null && session.version !== expectedVersion) {
          throw new ShoppingSessionStoreError("SESSION_CONFLICT");
        }
        const receipt = getReceipt(session, operationId, operationType);
        if (receipt) return {session, result: receipt.result, replayed: true};
        const outcome = await mutate(clone(session));
        const next = normalizeSession({
          ...outcome.session,
          version: session.version + 1,
          updatedAt: now(),
          operationReceipts: operationId ? appendReceipt(
            outcome.session.operationReceipts,
            operationId,
            operationType,
            outcome.result,
          ) : outcome.session.operationReceipts,
        });
        transaction.set(sessionRef, encodeSession(next));
        return {session: next, result: outcome.result, replayed: false};
      });
    },
  };
}

function normalizeSession(session) {
  validateStoredSession(session);
  const pool = session.pool || {};
  if (pool.orderedCandidateIds.length > MAX_SESSION_POOL_CANDIDATES) {
    throw new ShoppingSessionStoreError("RESULT_POOL_TOO_LARGE");
  }
  const initialPresentedCandidateIds = boundedIds(
    session.initialPresentedCandidateIds ?? pool.shownCandidateIds,
    "initial_presented_candidate_ids",
  );
  if (!initialPresentedCandidateIds.every((id) => pool.orderedCandidateIds.includes(id))) {
    throw new ShoppingSessionStoreError("SESSION_MALFORMED");
  }
  return {
    schemaVersion: SESSION_SCHEMA_VERSION,
    sessionId: requiredText(session.sessionId, "session_id"),
    ownerUid: requiredText(session.ownerUid, "owner_uid"),
    status: "ACTIVE",
    createdAt: numericTime(session.createdAt, "created_at"),
    updatedAt: numericTime(session.updatedAt ?? session.createdAt, "updated_at"),
    expiresAt: numericTime(session.expiresAt, "expires_at"),
    version: Number.isSafeInteger(session.version) ? session.version : 0,
    query: clone(session.query),
    searchMeta: sanitizeSearchMeta(session.searchMeta || session.searchResult),
    pool: {
      queryId: requiredText(pool.queryId, "pool_query_id"),
      queryRevision: number(pool.queryRevision, "pool_query_revision"),
      catalogRevision: requiredText(pool.catalogRevision, "pool_catalog_revision"),
      orderedCandidateIds: boundedIds(pool.orderedCandidateIds, "pool_ordered_candidate_ids"),
      shownCandidateIds: boundedIds(pool.shownCandidateIds, "pool_shown_candidate_ids"),
      rejectedCandidateIds: boundedIds(pool.rejectedCandidateIds, "pool_rejected_candidate_ids"),
      cursor: number(pool.cursor, "pool_cursor"),
    },
    initialPresentedCandidateIds,
    focusedVariantId: nullableId(session.focusedVariantId),
    focusedOfferId: nullableId(session.focusedOfferId),
    interactionState: sanitizeInteractionState(session.interactionState),
    operationReceipts: sanitizeReceipts(session.operationReceipts),
  };
}

function encodeSession(session) {
  const safe = normalizeSession(session);
  return {...safe, createdAt: new Date(safe.createdAt), updatedAt: new Date(safe.updatedAt), expiresAt: new Date(safe.expiresAt)};
}
function decodeSession(data) {
  if (!data || typeof data !== "object") throw new ShoppingSessionStoreError("SESSION_MALFORMED");
  try {
    return normalizeSession({
      ...data,
      createdAt: toMillis(data.createdAt),
      updatedAt: toMillis(data.updatedAt),
      expiresAt: toMillis(data.expiresAt),
    });
  } catch (error) {
    if (error instanceof ShoppingSessionStoreError) throw error;
    throw new ShoppingSessionStoreError("SESSION_MALFORMED");
  }
}
function sanitizeSearchMeta(value) {
  if (!value || typeof value !== "object") throw new ShoppingSessionStoreError("SESSION_MALFORMED");
  return {
    queryId: requiredText(value.queryId, "search_query_id"),
    queryRevision: number(value.queryRevision, "search_query_revision"),
    catalogRevision: requiredText(value.catalogRevision, "search_catalog_revision"),
    completeness: requiredText(value.completeness, "search_completeness"),
    exactResultCount: value.exactResultCount == null ? null : number(value.exactResultCount, "exact_result_count"),
    diagnostics: value.diagnostics == null ? null : clone(value.diagnostics),
  };
}
function sanitizeInteractionState(value) {
  if (value == null) return null;
  if (typeof value !== "object" || Array.isArray(value)) throw new ShoppingSessionStoreError("SESSION_MALFORMED");
  const allowed = ["activeClarification", "shoppingNeeds", "pendingWishlistOfferVariantId"];
  return Object.fromEntries(Object.entries(value).filter(([key]) => allowed.includes(key)));
}
function sanitizeReceipts(value) {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new ShoppingSessionStoreError("SESSION_MALFORMED");
  return value.slice(-MAX_OPERATION_RECEIPTS).map((item) => ({
    operationId: requiredText(item.operationId, "operation_id"),
    operationType: requiredText(item.operationType, "operation_type"),
    result: clone(item.result),
  }));
}
function appendReceipt(receipts, operationId, operationType, result) {
  return [...sanitizeReceipts(receipts), {
    operationId: requiredText(operationId, "operation_id"),
    operationType: requiredText(operationType, "operation_type"),
    result: clone(result),
  }].slice(-MAX_OPERATION_RECEIPTS);
}
function getReceipt(session, operationId, operationType) {
  if (!operationId) return null;
  return (session.operationReceipts || []).find((item) =>
    item.operationId === operationId && item.operationType === operationType) || null;
}
function validateStoredSession(session) {
  if (!session || typeof session !== "object" || !session.query || !session.pool) {
    throw new ShoppingSessionStoreError("SESSION_MALFORMED");
  }
  requiredText(session.sessionId, "session_id");
  requiredText(session.ownerUid, "owner_uid");
  if (!Array.isArray(session.pool.orderedCandidateIds) ||
      !Array.isArray(session.pool.shownCandidateIds) ||
      !Array.isArray(session.pool.rejectedCandidateIds)) {
    throw new ShoppingSessionStoreError("SESSION_MALFORMED");
  }
}
function boundedIds(values, label) {
  if (!Array.isArray(values) || values.length > MAX_SESSION_POOL_CANDIDATES) {
    throw new ShoppingSessionStoreError("SESSION_MALFORMED");
  }
  return [...new Set(values.map((value) => requiredText(value, label)))];
}
function requiredText(value, label) {
  const text = String(value || "");
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(text)) throw new ShoppingSessionStoreError("SESSION_MALFORMED", `invalid_${label}`);
  return text;
}
function nullableId(value) { return value == null ? null : requiredText(value, "reference_id"); }
function number(value, label) {
  if (!Number.isSafeInteger(value) || value < 0) throw new ShoppingSessionStoreError("SESSION_MALFORMED", `invalid_${label}`);
  return value;
}
function numericTime(value, label) {
  if (!Number.isFinite(value) || value < 0) throw new ShoppingSessionStoreError("SESSION_MALFORMED", `invalid_${label}`);
  return Number(value);
}
function toMillis(value) {
  if (typeof value === "number") return value;
  if (value instanceof Date) return value.getTime();
  if (value && typeof value.toMillis === "function") return value.toMillis();
  throw new ShoppingSessionStoreError("SESSION_MALFORMED");
}
function isExpired(session, now) { return session.expiresAt <= now; }
function idempotencyDocumentId(uid, key) {
  return crypto.createHash("sha256").update(`${uid}\u0000${key}`).digest("base64url");
}
function clone(value) { return value == null ? null : structuredClone(value); }

module.exports = {
  SESSION_SCHEMA_VERSION,
  MAX_SESSION_POOL_CANDIDATES,
  MAX_OPERATION_RECEIPTS,
  ShoppingSessionStoreError,
  createMemoryShoppingSessionStore,
  createFirestoreShoppingSessionStore,
};
