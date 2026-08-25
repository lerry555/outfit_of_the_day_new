"use strict";

/**
 * Production Gemini clothing analyzer client.
 * Owns request construction, retries, truncation recovery.
 * Does NOT import benchmark runtime modules.
 */

const {
  getClothingAnalyzerGeminiPromptV1,
  MODEL_ID,
  ANALYZER_VERSION,
} = require("./prompts/clothing_analyzer_gemini_v1");
const {buildProductionGeminiResponseSchema} = require("./production_schema");
const {getClothingAnalyzerGeminiPromptV2} = require("./prompts/clothing_analyzer_gemini_v2");
const {resolveGeminiApiKey} = require("./gemini_secret_binding");

const DEFAULT_ENDPOINT_BASE = "https://generativelanguage.googleapis.com/v1beta";
const DEFAULT_MAX_OUTPUT_TOKENS = 2000;
const TRUNCATION_RECOVERY_MAX_OUTPUT_TOKENS = 4000;
const DEFAULT_TEMPERATURE = 0;
const DEFAULT_THINKING_BUDGET = 0;

// Rough Flash estimate for telemetry only (not billing source of truth).
const EST_INPUT_PER_MTOK = 0.30;
const EST_OUTPUT_PER_MTOK = 2.50;

function fail(code, extra = {}) {
  const err = new Error(code);
  err.code = code;
  Object.assign(err, extra);
  throw err;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function sanitizedUpstreamError(response) {
  let raw = "";
  try { raw = await response.text(); } catch (_) { return null; }
  try {
    const body = JSON.parse(raw);
    const error = body && body.error || {};
    return {
      status: Number(error.code || response.status) || response.status,
      statusName: String(error.status || "").slice(0, 80) || null,
      message: String(error.message || "").replace(/key=[^&\s]+/gi, "key=[REDACTED]").slice(0, 800) || null,
      fieldViolations: Array.isArray(error.details) ? error.details.flatMap((d) =>
        Array.isArray(d.fieldViolations) ? d.fieldViolations.map((v) => ({field:String(v.field||"").slice(0,240),description:String(v.description||"").slice(0,400)})) : []) : [],
    };
  } catch (_) {
    return {status: response.status, statusName: null, message: raw.slice(0, 400), fieldViolations: []};
  }
}

function estimateCostUsd(usage) {
  if (!usage) return null;
  const input = Number(usage.promptTokenCount || 0);
  const output = Number(usage.candidatesTokenCount || 0);
  if (!Number.isFinite(input) || !Number.isFinite(output)) return null;
  return Number(
    ((input / 1e6) * EST_INPUT_PER_MTOK + (output / 1e6) * EST_OUTPUT_PER_MTOK)
      .toFixed(6),
  );
}

function extractTextFromGeminiResponse(data) {
  const parts = data && data.candidates && data.candidates[0] &&
    data.candidates[0].content && data.candidates[0].content.parts;
  if (!Array.isArray(parts)) return "";
  return parts.map((p) => (p && p.text) || "").join("").trim();
}

function getFinishReason(data) {
  return data && data.candidates && data.candidates[0] &&
    data.candidates[0].finishReason || null;
}

function isTruncatedResponse(data, text) {
  const reason = String(getFinishReason(data) || "").toUpperCase();
  if (reason === "MAX_TOKENS" || reason === "LENGTH") return true;
  const trimmed = String(text || "").trim();
  if (!trimmed) return false;
  // Incomplete JSON heuristics
  if (trimmed.startsWith("{") && !trimmed.endsWith("}")) return true;
  try {
    JSON.parse(trimmed);
    return false;
  } catch (_) {
    const open = (trimmed.match(/{/g) || []).length;
    const close = (trimmed.match(/}/g) || []).length;
    return open > close;
  }
}

function buildGeminiAnalyzeRequestBody({
  prompt,
  mimeType,
  base64,
  maxOutputTokens = DEFAULT_MAX_OUTPUT_TOKENS,
  temperature = DEFAULT_TEMPERATURE,
  thinkingBudget = DEFAULT_THINKING_BUDGET,
  schema = buildProductionGeminiResponseSchema(),
}) {
  if (typeof prompt !== "string" || !prompt) fail("gemini_prompt_required");
  if (typeof mimeType !== "string" || !mimeType.startsWith("image/")) {
    fail("gemini_image_mime_required");
  }
  if (typeof base64 !== "string" || base64.length < 32) {
    fail("gemini_image_bytes_required");
  }
  const body = {
    contents: [
      {
        role: "user",
        parts: [
          {text: prompt},
          {inlineData: {mimeType, data: base64}},
        ],
      },
    ],
    generationConfig: {
      temperature,
      maxOutputTokens,
      responseMimeType: "application/json",
      responseJsonSchema: schema,
      thinkingConfig: {thinkingBudget},
    },
  };
  return body;
}

/**
 * @param {{
 *   getApiKey?: () => string,
 *   fetchImpl?: Function,
 *   endpointBase?: string,
 *   sleepImpl?: Function,
 * }} [options]
 */
function createGeminiClothingAnalyzerClient(options = {}) {
  const fetchImpl = options.fetchImpl || fetch;
  const endpointBase = options.endpointBase || DEFAULT_ENDPOINT_BASE;
  const sleepImpl = options.sleepImpl || sleep;
  const useV2 = options.contractVersion === "wardrobe-analyzer-v2";
  const promptMeta = useV2 ? getClothingAnalyzerGeminiPromptV2() :
    getClothingAnalyzerGeminiPromptV1();
  const responseSchema = useV2 ? promptMeta.responseSchema :
    buildProductionGeminiResponseSchema();

  return Object.freeze({
    provider: "GEMINI",
    modelId: MODEL_ID,
    analyzerVersion: promptMeta.analyzerVersion || ANALYZER_VERSION,
    promptVersion: promptMeta.promptVersion,
    promptHash: promptMeta.promptHash,
    defaults: Object.freeze({
      temperature: DEFAULT_TEMPERATURE,
      thinkingBudget: DEFAULT_THINKING_BUDGET,
      maxOutputTokens: DEFAULT_MAX_OUTPUT_TOKENS,
      truncationRecoveryMaxOutputTokens: TRUNCATION_RECOVERY_MAX_OUTPUT_TOKENS,
    }),

    buildRequestBody: buildGeminiAnalyzeRequestBody,

    /**
     * @param {{
     *   mimeType: string,
     *   imageBase64: string,
     *   maxAttemptsOnRateLimit?: number,
     * }} request
     */
    async analyze(request) {
      const started = Date.now();
      let retryCount = 0;
      let truncationRecovered = false;
      let maxOutputTokens = DEFAULT_MAX_OUTPUT_TOKENS;
      const maxRateLimitAttempts = request.maxAttemptsOnRateLimit == null ?
        3 : Number(request.maxAttemptsOnRateLimit);

      const apiKey = resolveGeminiApiKey(options.getApiKey);
      const url =
        `${endpointBase}/models/${encodeURIComponent(MODEL_ID)}:generateContent` +
        `?key=${encodeURIComponent(apiKey)}`;

      async function once(tokens) {
        const body = buildGeminiAnalyzeRequestBody({
          prompt: promptMeta.prompt,
          mimeType: request.mimeType,
          base64: request.imageBase64,
          maxOutputTokens: tokens,
          schema: responseSchema,
        });
        const response = await fetchImpl(url, {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify(body),
        });
        return response;
      }

      let lastData = null;
      let lastText = "";
      let attempt = 0;

      while (attempt < maxRateLimitAttempts) {
        attempt += 1;
        let response;
        try {
          response = await once(maxOutputTokens);
        } catch (e) {
          fail("gemini_transport_failure", {cause: e});
        }

        if (response.status === 429 || response.status >= 500) {
          retryCount += 1;
          if (attempt >= maxRateLimitAttempts) {
            fail(`gemini_upstream_${response.status}`, {
              httpStatus: response.status,
              retryable: true,
            });
          }
          const backoff = Math.min(4000, 300 * (2 ** (attempt - 1)));
          await sleepImpl(backoff);
          continue;
        }

        if (!response.ok) {
          const upstreamError = await sanitizedUpstreamError(response);
          fail(`gemini_upstream_${response.status}`, {
            httpStatus: response.status,
            retryable: false,
            upstreamError,
          });
        }

        lastData = await response.json();
        lastText = extractTextFromGeminiResponse(lastData);

        if (isTruncatedResponse(lastData, lastText)) {
          if (!truncationRecovered &&
              maxOutputTokens < TRUNCATION_RECOVERY_MAX_OUTPUT_TOKENS) {
            truncationRecovered = true;
            retryCount += 1;
            maxOutputTokens = TRUNCATION_RECOVERY_MAX_OUTPUT_TOKENS;
            // Exactly one truncation escalation — then parse path continues.
            let recoveryResponse;
            try {
              recoveryResponse = await once(maxOutputTokens);
            } catch (e) {
              fail("gemini_transport_failure", {cause: e});
            }
            if (recoveryResponse.status === 429 || recoveryResponse.status >= 500) {
              // Bounded single backoff then fail — do not ladder truncation further.
              retryCount += 1;
              await sleepImpl(500);
              try {
                recoveryResponse = await once(maxOutputTokens);
              } catch (e) {
                fail("gemini_transport_failure", {cause: e});
              }
            }
            if (!recoveryResponse.ok) {
              fail(`gemini_upstream_${recoveryResponse.status}`, {
                httpStatus: recoveryResponse.status,
              });
            }
            lastData = await recoveryResponse.json();
            lastText = extractTextFromGeminiResponse(lastData);
          }
        }
        break;
      }

      let parsed = null;
      let parserStatus = "ok";
      try {
        parsed = JSON.parse(lastText);
      } catch (_) {
        parserStatus = isTruncatedResponse(lastData, lastText) ?
          "truncated_json" : "malformed_json";
        parsed = null;
      }

      const usage = lastData && lastData.usageMetadata ? {
        promptTokenCount: lastData.usageMetadata.promptTokenCount ?? null,
        candidatesTokenCount: lastData.usageMetadata.candidatesTokenCount ?? null,
        totalTokenCount: lastData.usageMetadata.totalTokenCount ?? null,
      } : null;

      const telemetry = {
        provider: "GEMINI",
        model: MODEL_ID,
        analyzerVersion: promptMeta.analyzerVersion || ANALYZER_VERSION,
        promptVersion: promptMeta.promptVersion,
        promptHash: promptMeta.promptHash,
        inputTokens: usage && usage.promptTokenCount,
        outputTokens: usage && usage.candidatesTokenCount,
        estimatedCostUsd: estimateCostUsd(usage),
        latencyMs: Date.now() - started,
        retryCount,
        parserStatus,
        success: parserStatus === "ok" && parsed != null,
        truncationRecovered,
        finishReason: getFinishReason(lastData),
        maxOutputTokensUsed: maxOutputTokens,
      };

      if (parserStatus !== "ok" || parsed == null) {
        const err = new Error(parserStatus);
        err.code = parserStatus;
        err.telemetry = telemetry;
        throw err;
      }

      return {
        parsed,
        telemetry,
        promptMeta,
      };
    },
  });
}

module.exports = {
  DEFAULT_ENDPOINT_BASE,
  DEFAULT_MAX_OUTPUT_TOKENS,
  TRUNCATION_RECOVERY_MAX_OUTPUT_TOKENS,
  DEFAULT_TEMPERATURE,
  DEFAULT_THINKING_BUDGET,
  buildGeminiAnalyzeRequestBody,
  createGeminiClothingAnalyzerClient,
  isTruncatedResponse,
  extractTextFromGeminiResponse,
  estimateCostUsd,
  sanitizedUpstreamError,
};
