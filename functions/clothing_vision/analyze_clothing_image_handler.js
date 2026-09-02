"use strict";

const {hashValue} = require("../costs/ai_usage_v1");

const crypto = require("node:crypto");

/**
 * HTTPS handler for analyzeClothingImage — Gemini primary, OpenAI legacy kill-switch.
 */

const {
  getClothingVisionTaskConfig,
  PROVIDERS,
} = require("./model_task_registry");
const {
  resolveOwnedWardrobeStoragePath,
} = require("./storage_ownership");
const {
  createGeminiClothingAnalyzerClient,
} = require("./gemini_clothing_analyzer_client");
const {
  validateProductionGeminiOutput,
  createKbIndex,
} = require("./production_output_validator");
const {
  adaptToProductionClientResponse,
} = require("./production_response_adapter");
const {validateAnalyzerV2} = require("../wardrobe_analyzer_v2_contract");
const {normalizeGeminiWardrobeAnalyzerV2Transport} = require("./gemini_wardrobe_analyzer_v2_transport");
const {adaptAnalyzerV2ToClientResponse} = require("./production_response_adapter_v2");
const {
  runOpenAiLegacyClothingAnalysis,
} = require("./openai_legacy_clothing_analyzer");
const {
  resolveAppCheckPolicy,
  evaluateAppCheck,
  resolveAppCheckStatus,
  APP_CHECK_MODES,
} = require("../wardrobe_authority_app_check_policy");

function httpError(status, message, code) {
  const err = new Error(message);
  err.httpStatus = status;
  err.code = code || message;
  return err;
}

/**
 * @param {{
 *   admin: import("firebase-admin"),
 *   logger: {info: Function, error: Function, warn?: Function},
 *   getOpenAiKey: () => string|null,
 *   getGeminiApiKey?: () => string,
 *   fetchImpl?: Function,
 *   env?: NodeJS.ProcessEnv,
 *   kbIndex?: object,
 *   geminiClient?: object,
 *   readStorageBytes?: (path: string) => Promise<{buffer: Buffer, contentType: string}>,
 *   providerOverride?: string|null,
 * }} deps
 */
function createAnalyzeClothingImageHandler(deps) {
  const logger = deps.logger || {info() {}, error() {}, warn() {}};
  const env = deps.env || process.env;
  // The legacy/V1 validator is the only consumer of the knowledge-base index.
  // Keep it lazy so Firebase can load this module while deploying unrelated
  // functions (for example stylistChat) without requiring vision build artifacts.
  let kbIndex = deps.kbIndex || null;
  function getKbIndex() {
    if (!kbIndex) kbIndex = createKbIndex();
    return kbIndex;
  }

  async function authorizeRequest(req) {
    const header = String(req.headers.authorization || "");
    if (!header.startsWith("Bearer ")) {
      throw httpError(401, "Authentication required.", "auth_required");
    }
    try {
      const decoded = await deps.admin.auth().verifyIdToken(header.slice(7));
      if (!decoded || !decoded.uid) {
        throw httpError(401, "Invalid auth token.", "auth_invalid");
      }
      return {uid: decoded.uid};
    } catch (e) {
      if (e.httpStatus) throw e;
      throw httpError(401, "Invalid auth token.", "auth_invalid");
    }
  }

  async function enforceAppCheck(req) {
    const environmentMode = String(
      env.CLOTHING_VISION_ENVIRONMENT ||
        (env.FUNCTIONS_EMULATOR === "true"
          ? "emulator"
          : (env.GCLOUD_PROJECT ? "production" : "test")),
    );
    // Prefer explicit mode. Initial Gemini rollout owner decision:
    // optional_with_warning (Auth + Storage ownership still mandatory).
    const configuredMode = env.CLOTHING_VISION_APP_CHECK_MODE ||
      APP_CHECK_MODES.optionalWithWarning;
    let policy;
    try {
      policy = resolveAppCheckPolicy({
        environmentMode: environmentMode === "production" ? "production" :
          (environmentMode === "emulator" ? "emulator" : "test"),
        appCheckMode: configuredMode === "required" ? APP_CHECK_MODES.required :
          configuredMode === "disabled_for_emulator_only" ?
            APP_CHECK_MODES.disabledForEmulatorOnly :
            APP_CHECK_MODES.optionalWithWarning,
      });
    } catch (_) {
      policy = resolveAppCheckPolicy({
        environmentMode: "test",
        appCheckMode: APP_CHECK_MODES.optionalWithWarning,
      });
    }

    const appCheckHeader = req.headers["x-firebase-appcheck"] ||
      req.headers["X-Firebase-AppCheck"];
    let appCheckContext = {appCheckPresent: false, appCheckVerified: false};
    if (appCheckHeader) {
      try {
        await deps.admin.appCheck().verifyToken(String(appCheckHeader));
        appCheckContext = {appCheckPresent: true, appCheckVerified: true};
      } catch (_) {
        appCheckContext = {appCheckPresent: true, appCheckVerified: false};
      }
    }
    const decision = evaluateAppCheck(policy, appCheckContext);
    const appCheckStatus = decision.status ||
      resolveAppCheckStatus(appCheckContext);
    if (!decision.ok) {
      throw httpError(401, "App Check required.", "app_check_required");
    }
    if (decision.warning && logger.warn) {
      logger.warn("analyzeClothingImage App Check soft warning", {
        mode: policy.mode,
        reasonCode: decision.reasonCode,
        appCheckStatus,
      });
    }
    return {policy, appCheckContext, decision, appCheckStatus};
  }

  async function readOwnedImage(storagePath) {
    if (typeof deps.readStorageBytes === "function") {
      return deps.readStorageBytes(storagePath);
    }
    const bucket = deps.admin.storage().bucket();
    const file = bucket.file(storagePath);
    const [buffer] = await file.download();
    let contentType = "image/jpeg";
    try {
      const [metadata] = await file.getMetadata();
      if (metadata && metadata.contentType) contentType = metadata.contentType;
    } catch (_) {
      // default jpeg
    }
    return {buffer, contentType};
  }

  return async function analyzeClothingImageHandler(req, res) {
    if (req.method !== "POST") {
      return res.status(405).send("Metóda nie je povolená. Použite POST.");
    }

    try {
      const auth = await authorizeRequest(req);
      const appCheck = await enforceAppCheck(req);

      const body = req.body || {};
      const useV2 = body.contractVersion === "wardrobe-analyzer-v2";
      // Prefer storagePath; imageUrl only if it maps to owned wardrobe object.
      const storagePath = resolveOwnedWardrobeStoragePath({
        uid: auth.uid,
        storagePath: body.storagePath,
        imageUrl: body.imageUrl,
        allowedBuckets: [
          env.FIREBASE_STORAGE_BUCKET,
          env.STORAGE_BUCKET,
        ].filter(Boolean),
      });

      const task = getClothingVisionTaskConfig({
        env,
        overrideProvider: deps.providerOverride,
      });

      const media = await readOwnedImage(storagePath);
      if (!media || !Buffer.isBuffer(media.buffer) || media.buffer.length === 0) {
        throw httpError(404, "Image not found.", "image_not_found");
      }
      const mimeType = (media.contentType && String(media.contentType).startsWith("image/")) ?
        media.contentType : "image/jpeg";
      const imageBase64 = media.buffer.toString("base64");
      const requestFingerprint = crypto.randomUUID();

      const requestTelemetryBase = {
        requestFingerprint,
        appCheckStatus: appCheck.appCheckStatus,
        appCheckMode: appCheck.policy.mode,
        clothingVisionProvider: task.provider,
      };

      if (task.provider === PROVIDERS.OPENAI_LEGACY) {
        const dataUrl = `data:${mimeType};base64,${imageBase64}`;
        const legacy = await runOpenAiLegacyClothingAnalysis({
          imageDataUrl: dataUrl,
          getApiKey: deps.getOpenAiKey,
          fetchImpl: deps.fetchImpl,
        });
        logger.info("analyzeClothingImage telemetry", {
          ...legacy.telemetry,
          ...requestTelemetryBase,
          success: true,
        });
        return res.status(200).send(legacy.response);
      }

      // GEMINI primary path — no automatic OpenAI fallback.
      const gemini = deps.geminiClient || createGeminiClothingAnalyzerClient({
        getApiKey: deps.getGeminiApiKey,
        fetchImpl: deps.fetchImpl,
        contractVersion: useV2 ? "wardrobe-analyzer-v2" : null,
        logger,
        recordUsage: deps.recordUsage ? (event) => deps.recordUsage({
          ...event, userKey: hashValue(auth.uid),
        }) : undefined,
      });

      let geminiResult;
      try {
        geminiResult = await gemini.analyze({
          mimeType,
          imageBase64,
        });
      } catch (e) {
        logger.error("analyzeClothingImage gemini failure", {
          code: e.code || e.message,
          httpStatus: e.httpStatus || null,
          upstreamError: e.upstreamError || null,
          ...requestTelemetryBase,
          telemetry: e.telemetry || null,
          success: false,
        });
        const status = e.httpStatus || 502;
        return res.status(status).send(
          `Clothing analysis failed (${e.code || e.message}).`,
        );
      }

      const domainResult = useV2 ? normalizeGeminiWardrobeAnalyzerV2Transport(
        geminiResult.parsed,
        {analyzerVersion: gemini.analyzerVersion, modelVersion: gemini.modelId},
      ) : geminiResult.parsed;
      const validated = useV2 ? validateAnalyzerV2(domainResult) :
        validateProductionGeminiOutput(geminiResult.parsed, {kbIndex: getKbIndex()});
      if (!validated.ok) {
        logger.error("analyzeClothingImage validation failed", {
          errors: validated.errors,
          parserStatus: validated.parserStatus,
          ...requestTelemetryBase,
          success: false,
        });
        return res.status(502).send(
          `Clothing analysis validation failed (${validated.parserStatus}).`,
        );
      }

      const responseMeta = {
        provider: "GEMINI",
        modelId: gemini.modelId,
        promptVersion: gemini.promptVersion,
        promptHash: gemini.promptHash,
        analyzerVersion: gemini.analyzerVersion,
        validationNotes: validated.notes,
        telemetry: geminiResult.telemetry,
      };
      const adapted = useV2 ? adaptAnalyzerV2ToClientResponse(validated.value, {
        provenance: responseMeta,
      }) : adaptToProductionClientResponse(validated.value, responseMeta);

      if ((validated.sanitizationActions || []).length > 0) {
        logger.info("clothing vision validation sanitization", {
          event: "clothing_vision_validation_sanitization",
          schemaVersion: 1,
          requestFingerprint,
          analyzerVersion: gemini.analyzerVersion,
          provider: "GEMINI",
          model: gemini.modelId,
          promptVersion: gemini.promptVersion,
          promptHash: gemini.promptHash,
          parserStatus: validated.parserStatus,
          actions: validated.sanitizationActions,
        });
      }

      logger.info("analyzeClothingImage telemetry", {
        ...geminiResult.telemetry,
        validationNotes: validated.notes || [],
        ...requestTelemetryBase,
        success: true,
      });

      return res.status(200).send(adapted);
    } catch (error) {
      const status = error.httpStatus || 500;
      if (status >= 500) {
        logger.error("analyzeClothingImage error", {
          code: error.code || error.message,
        });
      }
      return res.status(status).send(
        error.message || "Chyba servera pri analýze obrázka.",
      );
    }
  };
}

module.exports = {
  createAnalyzeClothingImageHandler,
};
