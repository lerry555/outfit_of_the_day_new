"use strict";

const {
  bootstrapExistingChatV2,
  clone,
  createEmptySessionStateV2,
  validateStylistSessionStateV2,
} = require("./stylist_session_state_v2");
const {
  StylistSessionRepositoryV2Error,
  decodeSessionDocument,
  decodeTurnReceipt,
  encodeSessionDocument,
  encodeTurnReceipt,
  validateCommitInput,
} = require("./stylist_session_repository_v2");

function requiredId(value, label) {
  const text = String(value || "").trim();
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(text)) {
    throw new StylistSessionRepositoryV2Error("SESSION_MALFORMED", `invalid_${label}`);
  }
  return text;
}

function validateIdentity(uid, chatId) {
  return {
    uid: requiredId(uid, "owner_uid"),
    chatId: requiredId(chatId, "chat_id"),
  };
}

function normalizeBootstrapState(chatId, bootstrapState) {
  const state = validateStylistSessionStateV2(
    bootstrapState || createEmptySessionStateV2(chatId),
  );
  if (state.chatId !== chatId) {
    throw new StylistSessionRepositoryV2Error(
      "SESSION_MALFORMED",
      "bootstrap_chat_id_mismatch",
    );
  }
  return clone(state);
}

function serverOnlySessionPathV2(uid, chatId, turnId = null) {
  ({uid, chatId} = validateIdentity(uid, chatId));
  const base = `stylistSessionsV2Server/${uid}/sessions/${chatId}`;
  return turnId ? `${base}/turns/${requiredId(turnId, "turn_id")}` : base;
}

function createServerOnlyFirestoreStylistSessionRepositoryV2(
  db,
  {now = () => Date.now()} = {},
) {
  if (!db || typeof db.collection !== "function" || typeof db.runTransaction !== "function") {
    throw new Error("stylist_session_v2_server_only_repository_requires_admin_firestore");
  }

  function refs(uid, chatId, turnId = null) {
    ({uid, chatId} = validateIdentity(uid, chatId));
    const sessionRef = db
      .collection("stylistSessionsV2Server")
      .doc(uid)
      .collection("sessions")
      .doc(chatId);
    return {
      sessionRef,
      turnRef: turnId ? sessionRef.collection("turns").doc(requiredId(turnId, "turn_id")) : null,
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
          return {
            created: false,
            ...decodeSessionDocument(existing.data(), {uid, chatId}),
          };
        }
        const timestamp = now();
        const encoded = encodeSessionDocument({
          uid,
          state,
          createdAt: timestamp,
          updatedAt: timestamp,
        });
        transaction.create(sessionRef, encoded);
        return {
          created: true,
          ...decodeSessionDocument(encoded, {uid, chatId}),
        };
      });
    },

    async ensureFromLegacy({uid, chatId, bootstrapInput}) {
      const state = bootstrapExistingChatV2({
        ...clone(bootstrapInput || {}),
        chatId,
      });
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
          return {
            replayed: true,
            result: decoded.result,
            resultingSessionRevision: decoded.resultingSessionRevision,
          };
        }

        const validatedNext = validateCommitInput({
          chatId,
          turnId,
          expectedRevision,
          nextState,
          result,
        });
        const snapshot = await transaction.get(sessionRef);
        if (!snapshot.exists) {
          throw new StylistSessionRepositoryV2Error("SESSION_NOT_FOUND");
        }
        const current = decodeSessionDocument(snapshot.data(), {uid, chatId});
        if (current.state.revision !== expectedRevision) {
          throw new StylistSessionRepositoryV2Error("SESSION_CONFLICT");
        }

        const timestamp = now();
        transaction.set(
          sessionRef,
          encodeSessionDocument({
            uid,
            state: validatedNext,
            createdAt: current.createdAt ?? timestamp,
            updatedAt: timestamp,
          }),
        );
        transaction.create(
          turnRef,
          encodeTurnReceipt({
            uid,
            chatId,
            turnId,
            result,
            resultingSessionRevision: validatedNext.revision,
            createdAt: timestamp,
          }),
        );
        return {
          replayed: false,
          result: clone(result),
          resultingSessionRevision: validatedNext.revision,
        };
      });
    },
  };

  return api;
}

module.exports = {
  createServerOnlyFirestoreStylistSessionRepositoryV2,
  serverOnlySessionPathV2,
};
