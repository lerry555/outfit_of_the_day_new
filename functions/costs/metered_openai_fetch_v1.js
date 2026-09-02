"use strict";

const {randomUUID} = require("node:crypto");
const {hashValue, openAiUsageV1} = require("./ai_usage_v1");

// Meter at the transport boundary before any output validation. The original
// Response is untouched; callers retain their existing parsing/error behavior.
function createMeteredOpenAiFetchV1({fetchImpl, recordUsage, logger = console}) {
  return async function meteredFetch(url, init, {uid, feature, model}) {
    const started = Date.now();
    let response;
    let json;
    try {
      response = await fetchImpl(url, init);
      try { json = await response.clone().json(); } catch (_) { /* unknown usage */ }
      return response;
    } finally {
      const responseModel = typeof json?.model === "string" ? json.model.slice(0, 100) : model;
      try {
        await recordUsage({eventId: randomUUID(), provider: "openai", feature,
          userKey: hashValue(uid), model: responseModel,
          providerStatus: response?.status ?? null, latencyMs: Date.now() - started,
          ...openAiUsageV1({model: responseModel, usage: json?.usage})});
      } catch (_) {
        logger.warn?.("AI_USAGE_RECORD_FAILED", {feature});
      }
    }
  };
}

module.exports = {createMeteredOpenAiFetchV1};
