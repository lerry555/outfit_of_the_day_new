/**
 * Parse and normalize AI outfit decision fields (Phase 2b / Brain V1).
 *
 * Deterministic context remains the authority for known facts. Brain V1 may
 * resolve a locally-unparsed *activity* only when it supplies a canonical value
 * plus verbatim evidence that is present in recent user-authored text carried
 * by outfitContextState. Unlisted but explicit activities use value `other`
 * together with a short user-grounded label; this avoids adding a new parser
 * branch for every real-world activity.
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
  "wedding", "funeral", "interview", "zoo", "other",
]);

const ACTIVITY_FIELD_ALIASES = new Set([
  "activity", "activity_type", "outing_type",
]);

function normalizeImpactField(value) {
  return String(value || "").trim().toLowerCase()
    .replace(/[\s-]+/g, "_");
}

function canonicalMaterialField(value) {
  const field = normalizeImpactField(value);
  if (field === "location") return "destination";
  if (ACTIVITY_FIELD_ALIASES.has(field)) return "activity";
  if (field === "hour") return "time";
  return field;
}

function materialFieldAlreadyGrounded(field, state) {
  if (!state || typeof state !== "object") return false;
  const canonical = canonicalMaterialField(field);
  if (canonical === "destination") {
    return state.activityLocationKnown === true;
  }
  if (canonical === "activity") {
    return Boolean(String(state.activityHint || state.occasion || "").trim());
  }
  if (canonical === "time") {
    return state.hourExplicit === true && Number.isInteger(state.hourLocal);
  }
  if (canonical === "trip_scope") {
    const travel = state.travelContext;
    if (!travel || typeof travel !== "object" || Array.isArray(travel)) return false;
    const scope = String(travel.scope || "").trim().toLowerCase();
    return travel.scopeNeedsClarification === false &&
      scope !== "" && scope !== "unknown";
  }
  return false;
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
  const label = String(activity.label || "").trim().slice(0, 80);
  if (!CANONICAL_SEMANTIC_ACTIVITIES.has(value) ||
      source !== "user_explicit" || evidence.length < 2) {
    return null;
  }
  if (value === "other" && label.length < 2) return null;
  return {activity: {value, evidence, source, ...(label ? {label} : {})}};
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

function evidenceIsBareGenericTrip(evidence) {
  const text = normalizeEvidenceText(evidence);
  if (!text) return true;
  const words = text.split(" ").filter(Boolean);
  const generic = new Set([
    "ja", "my", "idem", "ideme", "pojdem", "pojdeme", "chcem", "chceme",
    "chystam", "chystame", "sa", "na", "do", "von", "prec", "niekam",
    "zajtra", "dnes", "pozajtra", "vylet", "vyletik", "cesta", "cestu",
    "nejaky", "nejaku", "asi", "potom", "outfit", "potrebujem",
  ]);
  return words.length > 0 && words.every((word) => generic.has(word));
}

function providerLocationIsWeatherSpecific(state) {
  if (!state || typeof state !== "object") return false;
  const location = state.locationContext;
  if (!location || typeof location !== "object" || Array.isArray(location)) {
    return state.activityLocationKnown === true;
  }
  if (location.providerAuthorityEnabled !== true) {
    return state.activityLocationKnown === true;
  }
  return location.providerVerified === true &&
    location.needsMoreSpecificity !== true &&
    Boolean(String(location.weatherLabel || state.activityLocationLabel || "").trim());
}

function applySemanticGroundingToState(state, decision) {
  if (!state || typeof state !== "object") return [];
  const activity = decision?.semanticGrounding?.activity;
  if (!activity) return [];

  const unresolved = groundingFields(state);
  const activityUnknown = unresolved.some((field) => ACTIVITY_FIELD_ALIASES.has(field));
  const travel = state.travelContext && typeof state.travelContext === "object" &&
    !Array.isArray(state.travelContext) ? state.travelContext : {};
  const ambiguousTravelScope = unresolved.includes("trip_scope") &&
    travel.scopeNeedsClarification === true;
  if (!activityUnknown && !ambiguousTravelScope) return [];
  if (!evidenceIsUserAuthored(activity.evidence, state) ||
      evidenceIsBareGenericTrip(activity.evidence)) {
    return [];
  }

  state.activityHint = activity.value;
  if (activity.label) state.activityLabel = activity.label;
  state.occasion = activity.value;
  if (decision.eventContext && typeof decision.eventContext === "object") {
    decision.eventContext.occasion = activity.value;
    if (activity.label) decision.eventContext.activityLabel = activity.label;
  }

  const resolvedFields = ["activity"];
  let remaining = unresolved.filter((field) => !ACTIVITY_FIELD_ALIASES.has(field));
  if (ambiguousTravelScope && activity.value !== "travel") {
    remaining = remaining.filter((field) => field !== "trip_scope");
    resolvedFields.push("trip_scope");
    state.travelContext = {
      ...travel,
      scope: "destination",
      scopeNeedsClarification: false,
      destinationUseExplicit: true,
      destinationRequiredForPrimaryOutfit: true,
    };
    if (!providerLocationIsWeatherSpecific(state) && !remaining.includes("destination")) {
      remaining.push("destination");
    }
  }

  state.unresolvedMaterialFields = remaining;
  state.groundingStatus = remaining.length === 0 ? "sufficient" : "needs_grounding";
  if (remaining.length === 0) state.userCorrectionDetected = false;
  return resolvedFields;
}

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

  const semanticGrounding = parseSemanticGrounding(parsed);
  let eventContext =
    parsed?.eventContext && typeof parsed.eventContext === "object" &&
      !Array.isArray(parsed.eventContext) ? parsed.eventContext : null;
  if (semanticGrounding && parsed && typeof parsed === "object" &&
      !Array.isArray(parsed) && !eventContext) {
    eventContext = {};
    parsed.eventContext = eventContext;
  }

  return {
    confidence,
    decisionRisk,
    assumptions,
    clarifyReason,
    impactFields,
    semanticGrounding,
    eventContext,
  };
}

function resolveOutfitAction(action, decision, clarificationState) {
  const semanticResolvedFields =
    applySemanticGroundingToState(clarificationState, decision);

  if (requiresGroundingClarification(clarificationState) &&
      action !== "stop" && action !== "show_items") {
    return "clarify";
  }
  if (action !== "clarify") return action;

  const state = clarificationState && typeof clarificationState === "object" ?
    clarificationState : {};
  const previouslyAsked = new Set(
    Array.isArray(state.clarifiedMaterialFields) ?
      state.clarifiedMaterialFields
        .map((value) => canonicalMaterialField(value))
        .filter(Boolean) :
      [],
  );
  const resolvedNow = new Set(
    semanticResolvedFields.map(canonicalMaterialField).filter(Boolean),
  );
  const requested = [
    ...(Array.isArray(decision?.impactFields) ? decision.impactFields : []),
    ...groundingFields(state),
  ];
  const requestedMaterial = requested
    .map(normalizeImpactField)
    .filter((field) => MATERIAL_IMPACT_FIELDS.has(field));
  const hasNewMaterialTarget = requestedMaterial.some((field) => {
    const canonical = canonicalMaterialField(field);
    return !previouslyAsked.has(canonical) &&
      !resolvedNow.has(canonical) &&
      !materialFieldAlreadyGrounded(canonical, state);
  });

  // Semantic grounding removes only the facts it actually proved. If the Brain
  // simultaneously identified a DIFFERENT material uncertainty (for example
  // it understood "prednáška" but still needs to know whether the user is the
  // speaker or an attendee), preserve that clarification instead of silently
  // turning it into chat/generation.
  if (hasNewMaterialTarget) return "clarify";

  const allRequestedMaterialAlreadyHandled = requestedMaterial.length > 0 &&
    requestedMaterial.every((field) => {
      const canonical = canonicalMaterialField(field);
      return previouslyAsked.has(canonical) ||
        resolvedNow.has(canonical) ||
        materialFieldAlreadyGrounded(canonical, state);
    });
  const routineOutfitReady =
    state.groundingStatus !== "needs_grounding" &&
    state.routineLocalOutfit === true &&
    state.activityLocationKnown === true &&
    Boolean(String(state.activityHint || state.occasion || "").trim());

  // For a routine local outfit, GPS-backed location is already authoritative.
  // If the Brain nevertheless asks only for facts that are already grounded,
  // proceed instead of displaying another "kam sa chystáš?" loop.
  if (routineOutfitReady && allRequestedMaterialAlreadyHandled) {
    return "generate_outfit";
  }

  return "chat";
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
