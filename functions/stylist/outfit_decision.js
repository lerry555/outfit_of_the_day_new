/**
 * Parse and normalize AI outfit decision fields (Phase 2b).
 */

const VALID_RISKS = new Set(["low", "medium", "high"]);

const MATERIAL_IMPACT_FIELDS = new Set([
  "terrain", "environment", "route", "footwear", "footwear_family",
  "weather_protection", "protection_layering", "formality", "dress_code",
  "venue", "outfit_acceptability", "time", "hour", "location", "destination",
  "activity", "activity_type", "outing_type", "trip_type", "trip_scope",
  "duration", "trip_length", "number_of_days", "indoor_outdoor", "intensity",
]);

function normalizeImpactField(value) {
  return String(value || "").trim().toLowerCase()
    .replace(/[\s-]+/g, "_");
}

function groundingFields(state) {
  if (!state || typeof state !== "object") return [];
  return Array.isArray(state.unresolvedMaterialFields) ?
    state.unresolvedMaterialFields.map(normalizeImpactField).filter(Boolean) : [];
}

function requiresGroundingClarification(state) {
  return state && typeof state === "object" &&
    (state.groundingStatus === "needs_grounding" || groundingFields(state).length > 0);
}

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
  if (requiresGroundingClarification(clarificationState) &&
      action !== "stop" && action !== "show_items") {
    return "clarify";
  }
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
  const requested = [
    ...(Array.isArray(decision?.impactFields) ? decision.impactFields : []),
    ...groundingFields(state),
  ];
  const hasNewMaterialTarget = requested
    .map(normalizeImpactField)
    .some((field) => MATERIAL_IMPACT_FIELDS.has(field) && !previouslyAsked.has(field));
  // A malformed or repeated question is allowed to remain a non-decisive chat
  // response. It must never silently authorize an outfit based on an unknown.
  return hasNewMaterialTarget ? "clarify" : "chat";
}

module.exports = {
  parseOutfitDecisionFields,
  resolveOutfitAction,
  requiresGroundingClarification,
  groundingFields,
  MATERIAL_IMPACT_FIELDS,
};
