const {getModelConfig, getStylistRoleModelConfig} = require("./ai_model_registry");
const {
  buildServerRequestSignals,
  decideTierFromSignals,
} = require("./ai_routing_policy");

/**
 * Route a stylist chat request to the appropriate AI tier and model.
 *
 * @param {Object} input
 * @param {string} input.message
 * @param {Array} input.history
 * @param {string} input.mode
 * @param {Object|null} input.weatherContext
 * @param {Object|null} input.clientContext
 * @returns {Object} RoutingDecision
 */
function routeStylistRequest(input) {
  const mode = String(input.mode || "chat").trim() || "chat";
  const signals = buildServerRequestSignals(input);
  const {tier, confidence, reason} = decideTierFromSignals(signals, mode);
  // Track U made GPT-4o the sole Stylist context/clarification authority.
  // Vision remains on its isolated legacy transport; Track D/R run through
  // their dedicated frozen-decision callable rather than this chat router.
  const modelConfig = mode === "chat" ?
    getStylistRoleModelConfig("contextClarification") : getModelConfig(tier);

  return {
    tier,
    modelId: modelConfig.id,
    maxTokens: modelConfig.maxTokens,
    temperature: modelConfig.temperature,
    pipeline: mode === "explain_outfit" ? "legacy_explain" : mode === "rate_photo" ? "vision" : "context_clarification",
    confidence,
    reason,
    signals,
  };
}

module.exports = {
  routeStylistRequest,
};
