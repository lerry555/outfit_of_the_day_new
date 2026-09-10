"use strict";

// Keep every existing Gen1 export untouched. V2 is added beside the legacy
// entrypoints so rollback is only a client/function-name switch.
const legacy = require("./index");
module.exports = legacy;

const functions = require("firebase-functions");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {
  OPENAI_API_KEY_SECRET,
  resolveOpenAISecret,
} = require("./stylist/ai_stylist_role_secret_binding_v1");
const {
  createStylistChatV2Handler,
} = require("./stylist/v2/stylist_production_bridge_one_brain_v2");
const {
  createServerOnlyFirestoreStylistSessionRepositoryV2,
} = require("./stylist/v2/server_only_stylist_session_repository_v2");

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

module.exports.stylistChatV2 = functions
  .region("us-east1")
  .runWith({
    timeoutSeconds: 120,
    memory: "512MB",
    secrets: [OPENAI_API_KEY_SECRET],
  })
  .https.onCall(createStylistChatV2Handler({
    db,
    admin,
    logger,
    fetchImpl: fetch,
    resolveOpenAISecret,
    // Production canonical memory lives outside /users/**. The currently
    // deployed legacy Firestore rules allow owner writes to most user
    // subcollections, so this top-level Admin-only path is fail-closed even
    // before a rules deployment is available.
    sessionRepository: createServerOnlyFirestoreStylistSessionRepositoryV2(db),
  }));
