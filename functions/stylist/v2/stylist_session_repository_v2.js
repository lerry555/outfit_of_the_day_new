"use strict";

const {isDeepStrictEqual} = require("node:util");
const {
  bootstrapExistingChatV2,
  clone,
  createEmptySessionStateV2,
  validateStylistSessionStateV2,
} = require("./stylist_session_state_v2");

const SESSION_SCHEMA_VERSION = 2;
const TURN_RECEIPT_SCHEMA_VERSION = 1;

class StylistSessionRepositoryV2Error extends Error {
  constructor(code, message = code, details = {}) {
    super(message);
    this.name = "StylistSessionRepositoryV2Error";
    this.code = code;
    this.details = details;
  }
}

function requiredId(value, label) {
  const text = String(value || "").trim();
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(text)) {
    throw new StylistSessionRepositoryV2Error("SESSION_MALFORMED", `invalid_${label}`);
  }
  return text;
}

function toMillis(value) {
  if (value == null) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value?.toMillis === "function") return value.toMillis();
  throw new StylistSessionRepositoryV2Error("SESSION_MALFORMED", "invalid_timestamp");
}

function validateIdentity(uid, chatId) {
  return {
    uid: requiredId(uid, "owner_uid"),
    chatId: requiredId(chatId, "chat_id"),
  };
}

function normalizeBootstrapState(chatId, bootstrapState) {
  const state = validateStylistSessionStateV2(bootstrapState || createEmptySessionStateV2(chatId));
  if (state.chatId !== chatId) {
    throw new StylistSessionRepositoryV2Error("SESSION_MALFORMED", "bootstrap_chat_id_mismatch");
  }
  return clone(state);
}

function encodeSessionDocument({uid, state, createdAt, updatedAt}) {
  const validated = validateStylistSessionStateV2(state);
  return {
    schemaVersion: SESSION_SCHEMA_VERSION,
    ownerUid: uid,
    chatId: validated.chatId,
    revision: validated.revision,
    state: clone(validated),
    createdAt: new Date(createdAt),
    updatedAt: new Date(updatedAt),
  };
}

function decodeSessionDocument(data, {uid, chatId}) {
  if (!data || data.schemaVersion !== SESSION_SCHEMA_VERSION || data.ownerUid !== uid ||
      data.chatId !== chatId || !data.state) {
    throw new StylistSessionRepositoryV2Error("SESSION_MALFORMED");
  }
  const state = validateStylistSessionStateV2(data.state);
  if (state.chatId !== chatId || state.revision !== data.revision) {
    throw new StylistSessionRepositoryV2Error("SESSION_MALFORMED", "session_envelope_mismatch");
  }
  return {
    state: clone(state),
    createdAt: toMillis(data.createdAt),
    updatedAt: toMillis(data.updatedAt),
  };
}

function encodeTurnReceipt({uid, chatId, turnId, result, resultingSessionRevision, createdAt}) {
  return {
    schemaVersion: TURN_RECEIPT_SCHEMA_VERSION,
    ownerUid: uid,
    chatId,
    turnId,
    resultingSessionRevision,
    result: clone(result),
    createdAt: new Date(createdAt),
  };
}

function decodeTurnReceipt(data, {uid, chatId, turnId}) {
  if (!data || data.schemaVersion !== TURN_RECEIPT_SCHEMA_VERSION || data.ownerUid !== uid ||
      data.chatId !== chatId || data.turnId !== turnId || !Number.isSafeInteger(data.resultingSessionRevision) ||
      !data.result) {
    throw new StylistSessionRepositoryV2Error("TURN_RECEIPT_MALFORMED");
  }
  return {
    result: clone(data.result),
    resultingSessionRevision: data.resultingSessionRevision,
    createdAt: toMillis(data.createdAt),
  };
}

function validateCommitInput({chatId, turnId, expectedRevision, nextState, result}) {
  requiredId(turnId, "turn_id");
  if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
    throw new StylistSessionRepositoryV2Error("SESSION_MALFORMED", "invalid_expected_revision");
  }
  const validated = validateStylistSessionStateV2(nextState);
  if (validated.chatId !== chatId) {
    throw new StylistSessionRepositoryV2Error("SESSION_MALFORMED", "next_state_chat_id_mismatch");
  }
  if (validated.revision !== expectedRevision + 1) {
    throw new StylistSessionRepositoryV2Error("SESSION_CONFLICT", "next_state_revision_mismatch");
  }
  if (!result || result.turnId !== turnId || result.resultingSessionRevision !== validated.revision) {
    throw new StylistSessionRepositoryV2Error("TURN_RECEIPT_MALFORMED", "result_revision_or_turn_mismatch");
  }
  const replay = validated.replay?.turns?.find((entry) => entry.turnId === turnId);
  if (!replay || !isDeepStrictEqual(replay.result, result)) {
    throw new StylistSessionRepositoryV2Error(
      "TURN_RECEIPT_MALFORMED",
      "next_state_must_contain_exact_turn_replay",
    );
  }
  return clone(validated);
}

function createMemoryStylistSessionRepositoryV2({now = () => Date.now()} = {}) {
  const sessions = new Map();
  const receipts = new Map();
  const sessionKey = (uid, chatId) => `${uid}\u0000${chatId}`;
  const receiptKey = (uid, chatId, turnId) => `${uid}\u0000${chatId}\u0000${turnId}`;

  const api = {
    async get({uid, chatId}) {
      ({uid, chatId} = validateIdentity(uid, chatId));
      const data = sessions.get(sessionKey(uid, chatId));
      return data ? decodeSessionDocument(data, {uid, chatId}) : null;
    },

    async ensure({uid, chatId, bootstrapState = null}) {
      ({uid, chatId} = validateIdentity(uid, chatId));
      const key = sessionKey(uid, chatId);
      const existing = sessions.get(key);
      if (existing) return {created: false, ...decodeSessionDocument(existing, {uid, chatId})};
      const state = normalizeBootstrapState(chatId, bootstrapState);
      const timestamp = now();
      const encoded = encodeSessionDocument({uid, state, createdAt: timestamp, updatedAt: timestamp});
      sessions.set(key, encoded);
      return {created: true, ...decodeSessionDocument(encoded, {uid, chatId})};
    },

    async ensureFromLegacy({uid, chatId, bootstrapInput}) {
      const state = bootstrapExistingChatV2({...clone(bootstrapInput || {}), chatId});
      return api.ensure({uid, chatId, bootstrapState: state});
    },

    async commitTurn({uid, chatId, turnId, expectedRevision, nextState, result}) {
      ({uid, chatId} = validateIdentity(uid, chatId));
      turnId = requiredId(turnId, "turn_id");
      const priorReceipt = receipts.get(receiptKey(uid, chatId, turnId));
      if (priorReceipt) {
        const decoded = decodeTurnReceipt(priorReceipt, {uid, chatId, turnId});
        return {replayed: true, result: decoded.result, resultingSessionRevision: decoded.resultingSessionRevision};
      }
      const key = sessionKey(uid, chatId);
      const stored = sessions.get(key);
      if (!stored) throw new StylistSessionRepositoryV2Error("SESSION_NOT_FOUND");
      const current = decodeSessionDocument(stored, {uid, chatId});
      if (current.state.revision !== expectedRevision) {
        throw new StylistSessionRepositoryV2Error("SESSION_CONFLICT");
      }
      const validatedNext = validateCommitInput({chatId, turnId, expectedRevision, nextState, result});
      const timestamp = now();
      const encoded = encodeSessionDocument({
        uid,
        state: validatedNext,
        createdAt: current.createdAt ?? timestamp,
        updatedAt: timestamp,
      });
      const receipt = encodeTurnReceipt({
        uid,
        chatId,
        turnId,
        result,
        resultingSessionRevision: validatedNext.revision,
        createdAt: timestamp,
      });
      sessions.set(key, encoded);
      receipts.set(receiptKey(uid, chatId, turnId), receipt);
      return {replayed: false, result: clone(result), resultingSessionRevision: validatedNext.revision};
    },

    dump() {
      return {
        sessions: clone([...sessions.values()]),
        receipts: clone([...receipts.values()]),
      };
    },
  };
  return api;
}

function createFirestoreStylistSessionRepositoryV2(db, {now = () => Date.now()} = {}) {
  if (!db || typeof db.collection !== "function" || typeof db.runTransaction !== "function") {
    throw new Error("stylist_session_v2_firestore_repository_requires_admin_firestore");
  }

  function refs(uid, chatId, turnId = null) {
    const sessionRef = db.collection("users").doc(uid).collection("stylistSessionsV2").doc(chatId);
    return {
      sessionRef,
      turnRef: turnId ? sessionRef.collection("turns").doc(turnId) : null,
    };
  }

  const api = {
    async get({uid, chatId}) {
      ({uid, chatId} = validateIdentity(uid, chatId));
      const {sessionRef} = refs(uid, chatId);
      const snapshot = await sessionRef.get();
      return snapshot.exists ? decodeSessionDocument(snapshot.data(), {uid, chatId}) : null;
    },

    async ensure({uid, chatId, bootstrapState = null}) {
      ({uid, chatId} = validateIdentity(uid, chatId));
      const state = normalizeBootstrapState(chatId, bootstrapState);
      const {sessionRef} = refs(uid, chatId);
      return db.runTransaction(async (transaction) => {
        const existing = await transaction.get(sessionRef);
        if (existing.exists) {
          return {created: false, ...decodeSessionDocument(existing.data(), {uid, chatId})};
        }
        const timestamp = now();
        const encoded = encodeSessionDocument({uid, state, createdAt: timestamp, updatedAt: timestamp});
        transaction.create(sessionRef, encoded);
        return {created: true, ...decodeSessionDocument(encoded, {uid, chatId})};
      });
    },

    async ensureFromLegacy({uid, chatId, bootstrapInput}) {
      const state = bootstrapExistingChatV2({...clone(bootstrapInput || {}), chatId});
      return api.ensure({uid, chatId, bootstrapState: state});
    },

    async commitTurn({uid, chatId, turnId, expectedRevision, nextState, result}) {
      ({uid, chatId} = validateIdentity(uid, chatId));
      turnId = requiredId(turnId, "turn_id");
      const {sessionRef, turnRef} = refs(uid, chatId, turnId);
      return db.runTransaction(async (transaction) => {
        const priorTurn = await transaction.get(turnRef);
        if (priorTurn.exists) {
          const decoded = decodeTurnReceipt(priorTurn.data(), {uid, chatId, turnId});
          return {replayed: true, result: decoded.result, resultingSessionRevision: decoded.resultingSessionRevision};
        }
        const validatedNext = validateCommitInput({chatId, turnId, expectedRevision, nextState, result});
        const snapshot = await transaction.get(sessionRef);
        if (!snapshot.exists) throw new StylistSessionRepositoryV2Error("SESSION_NOT_FOUND");
        const current = decodeSessionDocument(snapshot.data(), {uid, chatId});
        if (current.state.revision !== expectedRevision) {
          throw new StylistSessionRepositoryV2Error("SESSION_CONFLICT");
        }
        const timestamp = now();
        transaction.set(sessionRef, encodeSessionDocument({
          uid,
          state: validatedNext,
          createdAt: current.createdAt ?? timestamp,
          updatedAt: timestamp,
        }));
        transaction.create(turnRef, encodeTurnReceipt({
          uid,
          chatId,
          turnId,
          result,
          resultingSessionRevision: validatedNext.revision,
          createdAt: timestamp,
        }));
        return {replayed: false, result: clone(result), resultingSessionRevision: validatedNext.revision};
      });
    },
  };
  return api;
}

module.exports = {
  SESSION_SCHEMA_VERSION,
  TURN_RECEIPT_SCHEMA_VERSION,
  StylistSessionRepositoryV2Error,
  createFirestoreStylistSessionRepositoryV2,
  createMemoryStylistSessionRepositoryV2,
  decodeSessionDocument,
  decodeTurnReceipt,
  encodeSessionDocument,
  encodeTurnReceipt,
  validateCommitInput,
};
