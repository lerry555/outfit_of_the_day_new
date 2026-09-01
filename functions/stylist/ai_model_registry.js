/**
 * Central registry of AI models for Stylist Chat.
 * Swap premium model here in the future — handlers read config by tier only.
 */

/** @typedef {'fast' | 'standard' | 'premium' | 'vision'} StylistAiTier */

/**
 * @typedef {Object} StylistModelConfig
 * @property {string} id
 * @property {number} maxTokens
 * @property {number} temperature
 * @property {string[]} capabilities
 * @property {string} [notes]
 */

/** @type {Record<StylistAiTier, StylistModelConfig>} */
const STYLIST_MODEL_REGISTRY = {
  fast: {
    id: "gpt-4o-mini",
    maxTokens: 280,
    temperature: 0.55,
    capabilities: ["chat", "json"],
    notes: "Pozdravy, jednoduchý chat, show_items.",
  },
  standard: {
    id: "gpt-4.1-mini",
    maxTokens: 400,
    temperature: 0.55,
    capabilities: ["chat", "explain", "json"],
    notes: "Vysvetlenie outfitu, follow-up.",
  },
  premium: {
    // Same model as today; replace id here when upgrading to a stronger model.
    id: "gpt-4.1-mini",
    maxTokens: 600,
    temperature: 0.65,
    capabilities: ["chat", "planning", "json"],
    notes: "Plánovanie aktivít, viac podmienok, dress code.",
  },
  vision: {
    id: "gpt-4o-mini",
    maxTokens: 500,
    temperature: 0.65,
    capabilities: ["vision", "json"],
    notes: "Hodnotenie fotky outfitu.",
  },
};

// U/D/R responsibilities are separate from the legacy tier registry because
// Home/Calendar/Trip may still consume tier routing during their own migration.
// Brain V1 deliberately starts on the already-proven GPT-4o so the experiment
// measures the value of a single conversational owner before paying for a
// stronger model. Changing the brain model later is a one-line registry swap.
const STYLIST_ROLE_MODELS = Object.freeze({
  simpleAgent: Object.freeze({
    provider: "openai",
    id: "gpt-5.6-sol",
    maxTokens: 1600,
    reasoningEffort: "medium",
  }),
  conversationBrain: Object.freeze({
    // The legacy `id` remains the explanation transport model. Brain chat uses
    // `webModelId` through the Responses API so hosted tools can be optional.
    provider: "openai",
    id: "gpt-4o",
    maxTokens: 700,
    temperature: 0.3,
    webModelId: "gpt-5.6-terra",
    webMaxTokens: 900,
    webSearch: "auto",
    searchContextSize: "low",
    reasoningEffort: "low",
  }),
  contextClarification: Object.freeze({
    provider: "openai", id: "gpt-4o", maxTokens: 500, temperature: 0,
  }),
  finalCandidateDecision: Object.freeze({
    provider: "openai", id: "gpt-5.4-mini", maxTokens: 160, temperature: 0,
  }),
  explanation: Object.freeze({
    provider: "anthropic", id: "claude-sonnet-5", maxTokens: 500, temperature: 0,
  }),
});

/**
 * @param {StylistAiTier} tier
 * @returns {StylistModelConfig}
 */
function getModelConfig(tier) {
  return STYLIST_MODEL_REGISTRY[tier] || STYLIST_MODEL_REGISTRY.fast;
}

function getStylistRoleModelConfig(role) {
  return STYLIST_ROLE_MODELS[role] || null;
}

module.exports = {
  STYLIST_MODEL_REGISTRY,
  STYLIST_ROLE_MODELS,
  getModelConfig,
  getStylistRoleModelConfig,
};
