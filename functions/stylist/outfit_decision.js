/**
 * Parse and normalize AI outfit decision fields (Phase 2b / Brain V1).
 *
 * Deterministic context remains the authority for known facts. Brain V1 may
 * resolve a locally-unparsed *activity* only when it supplies a canonical value
 * plus verbatim evidence that is present in recent user-authored text carried
 * by outfitContextState. This lets natural Slovak phrasing work without turning
 * the model into an unchecked source of facts.
 */

const VALID_RISKS = new Set(["low", "medium", "high"]);

const MATERIAL_IMPACT_FIELDS = new Set([
  "terrain", "environment", "route", "footwear", "footwear_family",
  "weather_protection", "protection_layering", "formality", "dress_code",
  "venue", "outfit_acceptability", "time", "hour", "location", "destination",
  "activity", "activity_type", "outing_type", "trip_type", "trip_scope",
  "duration", "trip_length", "number_of_days", "indoor_outdoor", "intensity",
]);

const CANONICAL_SEMANTIC_ACTIVITIES = new Set([
  "hike", "nature_walk", "city_walk", "dinner", "travel", "work", "gym",
  "run", "cycling", "barbecue", "mushroom", "date", "cinema", "concert",
  "wedding", "funeral", "interview", "zoo",
]);

const ACTIVITY_FIELD_ALIASES = new Set([
  "activity", "activity_type", "outing_type",
]);

function normalizeImpactField(value) {
  return String(value || "").trim().toLowerCase()
    .replace(/[\s-]+/g, "_");
}

function normalizeEvidenceText(value) {
  return String(value || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}+/gu, "")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
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

function parseSemanticGrounding(parsed) {
  const raw = parsed?.semanticGrounding;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const activity = raw.activity;
  if (!activity || typeof activity !== "object" || Array.isArray(activity)) {
    return null;
  }
  const value = normalizeImpactField(activity.value);
  const evidence = String(activity.evidence || "").trim();
  const source = String(activity.source || "").trim().toLowerCase();
  if (!CANONICAL_SEMANTIC_ACTIVITIES.has(value) ||
      source !== "user_explicit" || evidence.length < 2) {
    return null;
  }
  return {activity: {value, evidence, source}};
}

function evidenceIsUserAuthored(evidence, state) {
  const needle = normalizeEvidenceText(evidence);
  if (needle.length < 2 || !state || typeof state !== "object") return false;
  const evidenceTexts = Array.isArray(state.semanticEvidenceTexts) ?
    state.semanticEvidenceTexts : [];
  return evidenceTexts.some((text) => {
    const haystack = normalizeEvidenceText(text);
    return haystack.length > 0 && haystack.includes(needle);
  });
}

// A semantic resolver must never upgrade a bare generic outing into a specific
// activity. Longer evidence can still include "výlet" when it also explicitly
// says what the user will do (e.g. "výlet na bicykli").
function evidenceIsBareGenericTrip(evidence) {
  const text = normalizeEvidenceText(evidence);
  if (!text) return true;
  const words = text.split(" ").filter(Boolean);
  const generic = new Set([
    "ja", "my", "idem", "ideme", "pojdem", "pojdeme", "chcem", "chceme",
    "chystam", "chystame", "sa", "na", "do", "von", "prec", "niekam",
    "zajtra", "dnes", "pozajtra", "vylet", "vyletik", "cesta", "cestu",
    "nejaky", "nejaku", "asi", "potom",
  ]);
  return words.length > 0 && words.every((word) => generic.has(word));
}

function applySemanticGroundingToState(state, decision) {
  if (!state || typeof state !== "object") return [];
  const activity = decision?.semanticGrounding?.activity;
  if (!activity) return [];

  const unresolved = groundingFields(state);
  if (!unresolved.some((field) => ACTIVITY_FIELD_ALIASES.has(field))) return [];
  if (!evidenceIsUserAuthored(activity.evidence, state) ||
      evidenceIsBareGenericTrip(activity.evidence)) {
    return [];
  }

  state.activityHint = activity.value;
  // Existing eventContext transport exposes `occasion` to the Flutter client.
  // For Brain V1 this also carries an evidence-verified canonical activity so
  // the client can reconcile its stale local unknown without weakening the
  // candidate/validator authority.
  state.occasion = activity.value;
  if (decision.eventContext && typeof decision.eventContext === "object") {
    decision.eventContext.occasion = activity.value;
  }

  const remaining = unresolved.filter((field) => !ACTIVITY_FIELD_ALIASES.has(field));
  state.unresolvedMaterialFields = remaining;
  state.groundingStatus = remaining.length === 0 ? "sufficient" : "needs_grounding";
  // This request-local flag only prevents the old correction fallback from
  // asking again after the corrected activity is now explicitly grounded.
  if (remaining.length === 0) state.userCorrectionDetected = false;
  return ["activity"];
}

/**
 * @param {Object|null} parsed
 * @returns {{
 *   confidence: number|null,
 *   decisionRisk: string|null,
 *   assumptions: string[],
 *   clarifyReason: string|null,
 *   impactFields: string[],
 *   semanticGrounding: Object|null,
 *   eventContext: Object|null,
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

  const clarifyReason = String(parsed?.clarifyReason || "").trim() || null;

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
    semanticGrounding: parseSemanticGrounding(parsed),
    eventContext:
      parsed?.eventContext && typeof parsed.eventContext === "object" ?
        parsed.eventContext : null,
  };
}

/**
 * @param {string} action
 * @param {Object} decision
 * @param {Object|boolean} clarificationState
 * @returns {string}
 */
function resolveOutfitAction(action, decision, clarificationState) {
  const semanticResolvedFields =
    applySemanticGroundingToState(clarificationState, decision);

  if (requiresGroundingClarification(clarificationState) &&
      action !== "stop" && action !== "show_items") {
    return "clarify";
  }
  if (action !== "clarify") return action;

  // Only semantic grounding may turn a conservative model `clarify` into a
  // non-question after it has proven the requested fact from user-authored
  // evidence. Ordinary material clarification behavior remains unchanged.
  if (semanticResolvedFields.length > 0 &&
      !requiresGroundingClarification(clarificationState)) {
    return "chat";
  }

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
  return hasNewMaterialTarget ? "clarify" : "chat";
}

module.exports = {
  parseOutfitDecisionFields,
  resolveOutfitAction,
  requiresGroundingClarification,
  groundingFields,
  applySemanticGroundingToState,
  evidenceIsUserAuthored,
  evidenceIsBareGenericTrip,
  CANONICAL_SEMANTIC_ACTIVITIES,
  MATERIAL_IMPACT_FIELDS,
};
