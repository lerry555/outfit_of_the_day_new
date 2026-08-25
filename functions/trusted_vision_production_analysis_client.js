"use strict";

/**
 * Production TrustedVisionAnalysisClient adapter.
 *
 * Existing HTTPS Vision handlers require client imageUrl — rejected here.
 * Server-owned media access: Admin Storage bytes → data URL for model transport.
 * Uses vision_v2_shadow prompt/parser/model/schema without changing them.
 * Tests inject fake transport; no live OpenAI by default.
 */

const crypto = require("node:crypto");
const {
  MODEL_VERSION,
  SCHEMA_VERSION,
  buildVisionV2Prompt,
  buildVisionV2ResponseFormat,
  parseVisionV2Response,
} = require("./vision_v2_shadow");
const {
  CLIENT_CONTRACT,
  CLIENT_ID,
  validateParserFixture,
} = require("./trusted_vision_analysis_client");
const {fingerprint} = require("./wardrobe_authority_redaction");

const PRODUCTION_CLIENT_ID = "TrustedVisionProductionAnalysisClient";
const PRODUCTION_CLIENT_VERSION =
  "trusted-vision-production-analysis-client-v1";
const PROMPT_VERSION = "vision-v2-schema-9";

/**
 * @param {{
 *   fetchImpl?: Function,
 *   getApiKey?: Function,
 *   readObjectBytes?: (path: string) => Promise<{buffer: Buffer, contentType: string}>,
 *   canonicalTypes?: string[],
 *   allowFixtureTransport?: boolean,
 *   fixtureTransport?: Function,
 *   logger?: {error: Function, info?: Function},
 * }} options
 */
function createTrustedVisionProductionAnalysisClient(options = {}) {
  const logger = options.logger || {error() {}, info() {}};
  const canonicalTypes = Array.isArray(options.canonicalTypes) &&
    options.canonicalTypes.length ?
    [...options.canonicalTypes] : ["tank_top"];
  const liveModelCallsRef = {count: 0};

  return Object.freeze({
    clientId: PRODUCTION_CLIENT_ID,
    clientVersion: PRODUCTION_CLIENT_VERSION,
    clientContract: CLIENT_CONTRACT,
    modelIdentifier: MODEL_VERSION,
    promptVersion: PROMPT_VERSION,
    visionSchemaVersion: SCHEMA_VERSION,
    get liveModelCalls() {
      return liveModelCallsRef.count;
    },

    async analyzeCurrentSource(request) {
      if (request == null || typeof request !== "object") {
        fail("vision_client_request_not_object");
      }
      rejectClientMedia(request);
      const itemId = requireNonEmpty(request.itemId, "itemId");
      const sourceStoragePath = requireNonEmpty(
        request.sourceStoragePath, "sourceStoragePath");
      if (!sourceStoragePath.startsWith("wardrobe/") ||
          sourceStoragePath.includes("://")) {
        fail("vision_source_storage_path_invalid");
      }

      if (typeof options.fixtureTransport === "function") {
        const fixtureResult = await options.fixtureTransport(request);
        validateParserFixture(fixtureResult.parser, fixtureResult.scenarioId);
        return Object.freeze({
          contractVersion: 1,
          clientContract: CLIENT_CONTRACT,
          scenarioId: fixtureResult.scenarioId,
          itemId,
          parser: fixtureResult.parser,
          provenance: Object.freeze({
            source: "trusted_fixture_transport",
            liveModel: false,
            sourceStoragePathFingerprint: fingerprint(sourceStoragePath),
            modelIdentifier: MODEL_VERSION,
            promptVersion: PROMPT_VERSION,
            visionSchemaVersion: SCHEMA_VERSION,
          }),
        });
      }

      if (typeof options.readObjectBytes !== "function") {
        fail("vision_server_media_accessor_required");
      }
      const apiKey = typeof options.getApiKey === "function" ?
        options.getApiKey() : null;
      if (!apiKey) fail("vision_api_key_missing");
      const media = await options.readObjectBytes(sourceStoragePath);
      if (media == null || !Buffer.isBuffer(media.buffer) ||
          media.buffer.length === 0) {
        fail("vision_source_media_missing");
      }
      const contentType = media.contentType || "image/jpeg";
      const dataUrl =
        `data:${contentType};base64,${media.buffer.toString("base64")}`;

      const analysisId = request.analysisId ||
        `wqvis:${crypto.createHash("sha256")
          .update(`${itemId}:${sourceStoragePath}`).digest("hex").slice(0, 24)}`;
      const observedAt = request.observedAt || "1970-01-01T00:00:00.000Z";
      const prompt = buildVisionV2Prompt(canonicalTypes);
      const requestBody = {
        model: MODEL_VERSION,
        temperature: 0,
        response_format: buildVisionV2ResponseFormat(canonicalTypes),
        messages: [
          {role: "system", content: prompt},
          {role: "user", content: [
            {type: "text", text: "Analyze the visible item using the exact schema."},
            {type: "image_url", image_url: {url: dataUrl}},
          ]},
        ],
      };

      if (request.expectedModel && request.expectedModel !== MODEL_VERSION) {
        fail("vision_model_mismatch");
      }
      if (request.expectedPromptVersion &&
          request.expectedPromptVersion !== PROMPT_VERSION) {
        fail("vision_prompt_mismatch");
      }
      if (request.expectedSchemaVersion != null &&
          request.expectedSchemaVersion !== SCHEMA_VERSION) {
        fail("vision_schema_mismatch");
      }

      const fetchImpl = options.fetchImpl;
      if (typeof fetchImpl !== "function") {
        fail("vision_transport_required");
      }
      liveModelCallsRef.count += 1;
      let response;
      try {
        response = await fetchImpl("https://api.openai.com/v1/chat/completions", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${apiKey}`,
          },
          body: JSON.stringify(requestBody),
        });
      } catch (error) {
        logger.error("[VISION_PRODUCTION][transport]", {
          reason: "transport_failure",
          itemFingerprint: fingerprint(itemId),
        });
        fail("vision_transport_failure");
      }

      if (!response || !response.ok) {
        const status = response && response.status;
        const retryable = [429, 502, 503, 504].includes(status);
        const err = new Error(`vision_upstream_error:${status || "unknown"}`);
        err.retryable = retryable;
        err.status = status;
        throw err;
      }
      const data = await response.json();
      const text = data && data.choices && data.choices[0] &&
        data.choices[0].message && data.choices[0].message.content;
      const parsed = parseVisionV2Response(text, {
        allowedCanonicalTypes: canonicalTypes,
        analysisId,
        sourceReference: `gs://server/${sourceStoragePath}`,
        observedAt,
        modelVersion: MODEL_VERSION,
      });
      if (!parsed.ok) {
        fail(`invalid_parser_result:${(parsed.errors || []).join(",")}`);
      }

      const parser = {
        fixtureContractVersion: 1,
        fixtureId: request.scenarioId || itemId,
        captureDataset: "production_runtime_v1",
        views: [{
          response: parsed.value,
        }],
      };

      return Object.freeze({
        contractVersion: 1,
        clientContract: CLIENT_CONTRACT,
        scenarioId: request.scenarioId || itemId,
        itemId,
        parser,
        provenance: Object.freeze({
          source: "trusted_server_media",
          liveModel: true,
          sourceStoragePathFingerprint: fingerprint(sourceStoragePath),
          modelIdentifier: MODEL_VERSION,
          promptVersion: PROMPT_VERSION,
          visionSchemaVersion: SCHEMA_VERSION,
        }),
      });
    },
  });
}

function rejectClientMedia(request) {
  for (const key of [
    "imageUrl", "signedUrl", "downloadURL", "downloadToken",
    "imageBytes", "base64", "clientMediaUrl",
    "apiKey", "openaiApiKey",
  ]) {
    if (request[key] != null) fail(`client_media_rejected:${key}`);
  }
}

function requireNonEmpty(value, label) {
  if (typeof value !== "string" || !value.trim()) fail(`${label}_empty`);
  return value.trim();
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  PRODUCTION_CLIENT_ID,
  PRODUCTION_CLIENT_VERSION,
  PROMPT_VERSION,
  createTrustedVisionProductionAnalysisClient,
};
