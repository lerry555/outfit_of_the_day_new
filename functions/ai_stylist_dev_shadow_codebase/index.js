"use strict";

const crypto = require("node:crypto");
const functions = require("firebase-functions");
const {defineString} = require("firebase-functions/params");
const {
  OPENAI_API_KEY_SECRET,
  ANTHROPIC_API_KEY_SECRET,
  resolveOpenAISecret,
  resolveAnthropicSecret,
} = require("./secret_bindings_v1");
const {
  createRealDevShadowProviderFactory,
  createNoRetryFetchExecutor,
} = require("./provider_factory_v1");
const {
  CALLABLE_NAME,
  createDevShadowSmokeHandler,
} = require("./callable_v1");

const DEV_SHADOW_MODE = defineString("OOTD_AI_STYLIST_DEV_SHADOW_MODE", {
  default: "disabled",
  description: "Fail-closed gate for one controlled AI Stylist dev-shadow smoke.",
});
const execute = createNoRetryFetchExecutor();

const handler = createDevShadowSmokeHandler({
  functionsApi: functions,
  modeResolver: () => DEV_SHADOW_MODE.value(),
  providerFactory: ({budget}) => createRealDevShadowProviderFactory({
    budget,
    execute,
    resolveOpenAISecret,
    resolveAnthropicSecret,
  }),
  runIdFactory: () => `dev-shadow-${crypto.randomUUID()}`,
  logger: functions.logger,
});

exports[CALLABLE_NAME] = functions
  .region("us-east1")
  .runWith({
    timeoutSeconds: 120,
    memory: "512MB",
    secrets: [OPENAI_API_KEY_SECRET, ANTHROPIC_API_KEY_SECRET],
  })
  .https.onCall(handler);
