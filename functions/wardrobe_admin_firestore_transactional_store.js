"use strict";

/**
 * Admin Firestore transactional store adapter (injectable).
 * Wraps the same runTransaction shape used by the offline repository.
 */

const {
  createMemoryTransactionalStore,
} = require("./wardrobe_profile_firestore_repository");

const STORE_ID = "WardrobeAdminFirestoreTransactionalStore";
const STORE_VERSION = "wardrobe-admin-firestore-transactional-store-v1";
const READ_CONTRACT = "WardrobeDocumentReadStore/v1";

function createAdminFirestoreTransactionRunner({firestore}) {
  if (firestore == null || typeof firestore.runTransaction !== "function" ||
      typeof firestore.collection !== "function") {
    fail("admin_firestore_transaction_api_required");
  }
  return async (userId, wardrobeItemId, callback) => {
    const ref = firestore.collection("users").doc(userId)
      .collection("wardrobe").doc(wardrobeItemId);
    return firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      const decision = await callback({
        exists: snapshot.exists === true,
        data: snapshot.exists === true ? snapshot.data() : null,
      });
      if (decision && decision.writePatch) {
        transaction.set(ref, decision.writePatch, {merge: true});
      }
      return decision.result;
    });
  };
}

/**
 * Production-shaped store. Real Admin wiring is injected; tests use memory.
 * @param {{
 *   runTransaction?: Function,
 *   get?: Function,
 *   firestore?: object,
 *   memoryDocs?: Record<string, object>,
 * }} options
 */
function createAdminFirestoreTransactionalStore(options = {}) {
  if (typeof options.runTransaction === "function") {
    const read = resolveDocumentReader(options);
    return Object.freeze({
      storeId: STORE_ID,
      storeVersion: STORE_VERSION,
      readContract: READ_CONTRACT,
      runTransaction: options.runTransaction,
      _get: read ? async (userId, wardrobeItemId) =>
        normalizeWardrobeDocumentRead(await read(userId, wardrobeItemId)) :
        undefined,
    });
  }
  // Lazy test/emulator fallback — memory fake, never touches live Firestore.
  const memory = createMemoryTransactionalStore(options.memoryDocs || {});
  return Object.freeze({
    storeId: STORE_ID,
    storeVersion: STORE_VERSION,
    readContract: READ_CONTRACT,
    runTransaction: memory.runTransaction.bind(memory),
    _get: memory._get.bind(memory),
    _dump: memory._dump.bind(memory),
    _isMemoryFake: true,
  });
}

function resolveDocumentReader(options) {
  if (typeof options.get === "function") return options.get;
  const firestore = options.firestore;
  if (firestore == null || typeof firestore.collection !== "function") {
    return null;
  }
  return async (userId, wardrobeItemId) => {
    const ref = firestore.collection("users").doc(userId)
      .collection("wardrobe").doc(wardrobeItemId);
    return ref.get();
  };
}

async function normalizeWardrobeDocumentRead(value) {
  const resolved = await value;
  if (resolved == null) return null;
  if (!isObject(resolved) || Array.isArray(resolved)) {
    fail("wardrobe_document_read_invalid_result");
  }

  const looksLikeSnapshot =
    Object.prototype.hasOwnProperty.call(resolved, "exists") ||
    typeof resolved.data === "function";
  let document = resolved;
  if (looksLikeSnapshot) {
    if (typeof resolved.exists !== "boolean" ||
        typeof resolved.data !== "function") {
      fail("wardrobe_document_read_malformed_snapshot");
    }
    if (!resolved.exists) return null;
    document = resolved.data();
    if (document == null) {
      fail("wardrobe_document_read_snapshot_data_missing");
    }
  }

  if (!isPlainObject(document)) {
    fail("wardrobe_document_read_document_not_plain_object");
  }
  let cloned;
  try {
    cloned = structuredClone(document);
  } catch (_) {
    fail("wardrobe_document_read_clone_failed");
  }
  if (!isPlainObject(cloned)) {
    fail("wardrobe_document_read_clone_not_plain_object");
  }
  return deepFreeze(cloned);
}

function isObject(value) {
  return value !== null && typeof value === "object";
}

function isPlainObject(value) {
  if (!isObject(value) || Array.isArray(value)) return false;
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

function deepFreeze(value, seen = new Set()) {
  if (!isObject(value) || seen.has(value)) return value;
  seen.add(value);
  for (const item of Object.values(value)) deepFreeze(item, seen);
  return Object.freeze(value);
}

function fail(code) {
  const error = new Error(code);
  error.code = code;
  throw error;
}

module.exports = {
  STORE_ID,
  STORE_VERSION,
  READ_CONTRACT,
  createAdminFirestoreTransactionRunner,
  createAdminFirestoreTransactionalStore,
  normalizeWardrobeDocumentRead,
};
