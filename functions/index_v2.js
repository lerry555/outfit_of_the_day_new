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
} = require("./stylist/v2/stylist_production_bridge_v2");

if (!admin.apps.length) admin.initializeApp();

module.exports.stylistChatV2 = functions
  .region("us-east1")
  .runWith({
    timeoutSeconds: 120,
    memory: "512MB",
    secrets: [OPENAI_API_KEY_SECRET],
  })
  .https.onCall(createStylistChatV2Handler({
    db: admin.firestore(),
    admin,
    logger,
    fetchImpl: fetch,
    resolveOpenAISecret,
  }));
