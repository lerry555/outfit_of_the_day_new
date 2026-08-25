"use strict";

/**
 * Minimal task→provider routing for clothing vision only.
 * Explicit config only — no silent per-request Gemini→OpenAI fallback.
 */

const TASK_CLOTHING_VISION_ANALYZER = "CLOTHING_VISION_ANALYZER";

const PROVIDERS = Object.freeze({
  GEMINI: "GEMINI",
  OPENAI_LEGACY: "OPENAI_LEGACY",
});

const DEFAULT_PROVIDER = PROVIDERS.GEMINI;

/**
 * @param {{
 *   env?: NodeJS.ProcessEnv,
 *   overrideProvider?: string|null,
 * }} [options]
 */
function resolveClothingVisionProvider(options = {}) {
  const env = options.env || process.env;
  const raw =
    options.overrideProvider != null && String(options.overrideProvider).trim() !== ""
      ? String(options.overrideProvider).trim()
      : String(env.CLOTHING_VISION_PROVIDER || DEFAULT_PROVIDER).trim();
  const normalized = raw.toUpperCase().replace(/-/g, "_");
  if (normalized === PROVIDERS.GEMINI || normalized === "GOOGLE_GEMINI") {
    return PROVIDERS.GEMINI;
  }
  if (
    normalized === PROVIDERS.OPENAI_LEGACY ||
    normalized === "OPENAI" ||
    normalized === "GPT4O_MINI_LEGACY"
  ) {
    return PROVIDERS.OPENAI_LEGACY;
  }
  const err = new Error(`clothing_vision_provider_unsupported:${raw}`);
  err.code = "clothing_vision_provider_unsupported";
  throw err;
}

function getClothingVisionTaskConfig(options = {}) {
  const provider = resolveClothingVisionProvider(options);
  return Object.freeze({
    task: TASK_CLOTHING_VISION_ANALYZER,
    provider,
    allowsAutomaticCrossProviderFallback: false,
    note:
      "Provider switching is explicit via CLOTHING_VISION_PROVIDER / kill-switch only.",
  });
}

module.exports = {
  TASK_CLOTHING_VISION_ANALYZER,
  PROVIDERS,
  DEFAULT_PROVIDER,
  resolveClothingVisionProvider,
  getClothingVisionTaskConfig,
};
