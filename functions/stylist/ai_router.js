const {getModelConfig, getStylistRoleModelConfig} = require("./ai_model_registry");
const {
  buildServerRequestSignals,
  decideTierFromSignals,
} = require("./ai_routing_policy");
const {CONVERSATION_BRAIN_VERSION} = require("./conversation_brain_persona_v1");

/**
 * Route a stylist chat request to the appropriate AI tier and model.
 *
 * Brain V1 is explicitly client-opted-in. This lets the experiment callable
 * be deployed under the existing function name without silently moving older
 * app builds away from the settled context/clarification model.
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
  const brainOptIn = mode === "chat" &&
    String(input?.clientContext?.conversationBrainVersion || "").trim() ===
      CONVERSATION_BRAIN_VERSION;

  // Non-opted-in clients keep the settled GPT-4o context/clarification route.
  // The experiment build opts into the replaceable Conversation Brain role.
  // Vision remains isolated for this phase; Track D/R use their dedicated
  // frozen-candidate callable rather than this router.
  const modelConfig = mode === "chat" ?
    getStylistRoleModelConfig(brainOptIn ? "conversationBrain" : "contextClarification") :
    getModelConfig(tier);

  return {
    tier,
    modelId: modelConfig.id,
    maxTokens: modelConfig.maxTokens,
    temperature: modelConfig.temperature,
    pipeline: mode === "explain_outfit" ?
      "legacy_explain" : mode === "rate_photo" ? "vision" :
        brainOptIn ? "conversation_brain_v1" : "context_clarification",
    brainVersion: brainOptIn ? CONVERSATION_BRAIN_VERSION : null,
    confidence,
    reason,
    signals,
  };
}

module.exports = {
  routeStylistRequest,
};
