"use strict";

// Brain V2 entrypoint. Re-export every legacy Cloud Function unchanged, then
// add the isolated Sol agent callable. This keeps the large legacy index.js
// physically untouched while the experiment is evaluated.
const legacyExports = require("./index");
const functions = require("firebase-functions");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {
  OPENAI_API_KEY_SECRET,
  resolveOpenAISecret,
} = require("./stylist/ai_stylist_role_secret_binding_v1");
const {
  createSolAgentV2Handler,
} = require("./stylist/sol_agent_v2");

if (!admin.apps.length) admin.initializeApp();

const db = admin.firestore();

const stylistAgentV2 = functions
  .region("us-east1")
  .runWith({
    timeoutSeconds: 70,
    memory: "512MB",
    secrets: [OPENAI_API_KEY_SECRET],
  })
  .https.onCall(createSolAgentV2Handler({
    db,
    fetchImpl: fetch,
    resolveOpenAISecret,
    logger,
    serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
    httpsError: (code, message) => new functions.https.HttpsError(code, message),
  }));

module.exports = {
  ...legacyExports,
  stylistAgentV2,
};
