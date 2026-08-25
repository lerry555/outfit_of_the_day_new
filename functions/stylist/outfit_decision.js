/**
 * Parse and normalize AI outfit decision fields (Phase 2b).
 */

const VALID_RISKS = new Set(["low", "medium", "high"]);

/**
 * @param {Object|null} parsed
 * @returns {{
 *   confidence: number|null,
 *   decisionRisk: string|null,
 *   assumptions: string[],
 *   clarifyReason: string|null,
 *   impactFields: string[],
 * }}
 */
function parseOutfitDecisionFields(parsed) {
  const confidenceRaw = parsed?.confidence ?? parsed?.readiness;
  const confidence =
    typeof confidenceRaw === "number" && Number.isFinite(confidenceRaw) ?
      Math.max(0, Math.min(1, confidenceRaw)) :
      null;

  const riskRaw = String(parsed?.decisionRisk || "").trim().toLowerCase();
  const decisionRisk = VALID_RISKS.has(riskRaw) ? riskRaw : null;

  const assumptions = Array.isArray(parsed?.assumptions) ?
    parsed.assumptions
      .map((v) => String(v || "").trim())
      .filter(Boolean) :
    [];

  const clarifyReason =
    String(parsed?.clarifyReason || "").trim() || null;

  let impactFields = [];
  if (Array.isArray(parsed?.impactFields)) {
    impactFields = parsed.impactFields
      .map((v) => String(v || "").trim())
      .filter(Boolean);
  } else if (Array.isArray(parsed?.missingFields)) {
    impactFields = parsed.missingFields
      .map((v) => String(v || "").trim())
      .filter(Boolean);
  }

  return {
    confidence,
    decisionRisk,
    assumptions,
    clarifyReason,
    impactFields,
  };
}

/**
 * @param {string} action
 * @param {Object} decision
 * @param {Object|boolean} clarificationState
 * @returns {string}
 */
function resolveOutfitAction(action, decision, clarificationState) {
  if (action !== "clarify") return action;
  // Minimal Necessary Clarification has no arbitrary one-question ceiling.
  // It only blocks a repeated/non-material question; a distinct remaining
  // material uncertainty may legitimately require a second turn.
  const state = clarificationState && typeof clarificationState === "object" ?
    clarificationState : {};
  const previouslyAsked = new Set(
    Array.isArray(state.clarifiedMaterialFields) ?
      state.clarifiedMaterialFields.map((value) => String(value || "").trim()).filter(Boolean) :
      [],
  );
  const material = new Set([
    "terrain", "environment", "route", "footwear", "footwear_family",
    "weather_protection", "protection_layering", "formality", "dress_code",
    "venue", "outfit_acceptability", "time", "hour", "location", "destination",
  ]);
  const requested = Array.isArray(decision?.impactFields) ? decision.impactFields : [];
  const hasNewMaterialTarget = requested
    .map((value) => String(value || "").trim().toLowerCase())
    .some((field) => material.has(field) && !previouslyAsked.has(field));
  return hasNewMaterialTarget ? "clarify" : "generate_outfit";
}

module.exports = {
  parseOutfitDecisionFields,
  resolveOutfitAction,
};
