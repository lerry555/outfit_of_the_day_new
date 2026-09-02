"use strict";

const {createHash, randomUUID} = require("node:crypto");

// Public STANDARD USD / million-token rates checked 2026-09-02. Estimates,
// not invoices: exclude tax, currency conversion, cloud costs and discounts.
// https://developers.openai.com/api/docs/models/gpt-5.6-sol
// https://developers.openai.com/api/docs/guides/prompt-caching
// https://ai.google.dev/gemini-api/docs/pricing
const PRICE_VERSION = "standard-usd-2026-09-02";
const PRICES = Object.freeze({
  "gpt-5.6-sol": {input: 4, cached: 0.4, write: 5, output: 20},
  "gpt-5.6-terra": {input: 2, cached: 0.2, write: 2.5, output: 12},
  "gpt-5.6-luna": {input: 0.2, cached: 0.02, write: 0.25, output: 1.2},
  "gpt-4o-mini": {input: 0.15, cached: 0.075, write: 0.15, output: 0.6},
});

function hashValue(value) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function tokenCount(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : null;
}

function money(value) {
  return Number(value.toFixed(9));
}

function openAiUsageV1({model, usage, now = Date.now()}) {
  const inputTokens = tokenCount(usage?.input_tokens ?? usage?.prompt_tokens);
  const outputTokens = tokenCount(usage?.output_tokens ?? usage?.completion_tokens);
  const details = usage?.input_tokens_details ?? usage?.prompt_tokens_details;
  const cachedInputTokens = tokenCount(details?.cached_tokens);
  const explicitWrites = String(model).startsWith("gpt-5.6-");
  const cacheWriteTokens = explicitWrites ? tokenCount(details?.cache_write_tokens) : 0;
  const reasoningTokens = tokenCount(
    usage?.output_tokens_details?.reasoning_tokens ??
    usage?.completion_tokens_details?.reasoning_tokens,
  );
  const baseModel = Object.keys(PRICES).find((key) => model === key ||
    new RegExp(`^${key}-\\d{4}-\\d{2}-\\d{2}$`).test(model));
  // The 5.6 public launch rates are only promised through Nov 21. Do not keep
  // silently claiming these are current after that date.
  const price = explicitWrites && now >= Date.parse("2026-11-22T00:00:00Z") ?
    null : PRICES[baseModel];
  let estimatedCostUsd = null;
  let estimatedCostUsdMin = null;
  let estimatedCostUsdMax = null;
  const valid = inputTokens !== null && outputTokens !== null &&
    cachedInputTokens !== null && cachedInputTokens <= inputTokens &&
    (cacheWriteTokens === null || cacheWriteTokens <= inputTokens - cachedInputTokens);
  if (price && valid) {
    const remaining = inputTokens - cachedInputTokens;
    // Reasoning is ALREADY included in OpenAI output_tokens, never add it again.
    const base = cachedInputTokens * price.cached + outputTokens * price.output;
    if (cacheWriteTokens !== null) {
      estimatedCostUsd = money((base + cacheWriteTokens * price.write +
        (remaining - cacheWriteTokens) * price.input) / 1e6);
      estimatedCostUsdMin = estimatedCostUsdMax = estimatedCostUsd;
    } else {
      estimatedCostUsdMin = money((base + remaining * price.input) / 1e6);
      estimatedCostUsdMax = money((base + remaining * price.write) / 1e6);
    }
  }
  return {
    inputTokens, outputTokens, cachedInputTokens, cacheWriteTokens, reasoningTokens,
    usageComplete: valid && cacheWriteTokens !== null,
    estimatedCostUsd, estimatedCostUsdMin, estimatedCostUsdMax,
    priceVersion: PRICE_VERSION, currency: "USD",
  };
}

function geminiUsageV1(usage) {
  const inputTokens = tokenCount(usage?.promptTokenCount);
  const outputTokens = tokenCount(usage?.candidatesTokenCount);
  // Gemini omits optional zero counters. Unlike OpenAI, thoughts are separate
  // from candidatesTokenCount and are billed at the output rate.
  const cachedInputTokens = tokenCount(usage?.cachedContentTokenCount ?? 0);
  const reasoningTokens = tokenCount(usage?.thoughtsTokenCount ?? 0);
  const valid = inputTokens !== null && outputTokens !== null &&
    cachedInputTokens !== null && reasoningTokens !== null &&
    cachedInputTokens <= inputTokens;
  return {
    inputTokens, outputTokens, cachedInputTokens, reasoningTokens,
    usageComplete: valid,
    estimatedCostUsd: valid ? money(((inputTokens - cachedInputTokens) * 1.5 +
      cachedInputTokens * 0.15 + (outputTokens + reasoningTokens) * 9) / 1e6) : null,
    priceVersion: PRICE_VERSION, currency: "USD",
  };
}

function createAiUsageRecorderV1({db, logger = console, now = Date.now}) {
  return async function record(event) {
    // Callers supply only whitelisted counters/context, NEVER raw provider
    // responses, messages, photos, URLs, prompts or credentials.
    const entry = {...event, recordedAt: new Date(now())};
    logger.info?.("AI_USAGE_V1", entry);
    try {
      await db.collection("aiUsageEventsV1").doc(event.eventId || randomUUID()).create(entry);
    } catch (error) {
      if (error?.code !== 6 && error?.code !== "already-exists") {
        // Metering outages must not make a successfully paid request retry.
        logger.warn?.("AI_USAGE_PERSIST_FAILED", {eventId: event.eventId || null});
      }
    }
  };
}

module.exports = {PRICE_VERSION, hashValue, openAiUsageV1, geminiUsageV1,
  createAiUsageRecorderV1};
