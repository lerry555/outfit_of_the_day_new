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
  // Brain V1 owns every ordinary Stylist chat turn. The selected model is a
  // registry value so we can A/B architecture and model strength separately.
  // Vision remains on its isolated route for this phase; Track D/R still run
  // through the frozen-candidate authority rather than this router.
  const modelConfig = mode === "chat" ?
    getStylistRoleModelConfig("conversationBrain") : getModelConfig(tier);

  return {
    tier,
    modelId: modelConfig.id,
    maxTokens: modelConfig.maxTokens,
    temperature: modelConfig.temperature,
    pipeline: mode === "explain_outfit" ?
      "legacy_explain" : mode === "rate_photo" ? "vision" : "conversation_brain_v1",
    confidence,
    reason,
    signals,
  };
}

module.exports = {
  routeStylistRequest,
};
