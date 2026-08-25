/**
 * Server-side heuristics for Stylist AI routing (Phase 1).
 * Phase 2 will merge client RequestSignals; for now we infer from message + history.
 */

const PLANNED_ACTIVITY_RE =
  /\b(hory|hore|horach|horami|turist|vylet|výlet|hub|hrib|prechadz|prechádz|sport|beh|bicykl|lyž|lyz|koncert|festival|rande|svadb|oslava|praca|práca|divadl|kino|zmrzlin|golf|tenis)\b/i;

const WANTS_OUTFIT_RE =
  /\b(outfit|obliec|obliecť|na seba|neviem co|neviem čo|satnik|šatník|ukaz|ukáž)\b/i;

const HOUR_RE =
  /(?:\b(o|okolo)\s*\d{1,2}(?::\d{2})?|\bteraz\b|\bhned\b|\bihned\b|\d{1,2}:\d{2}\b)/i;

const GREETING_ONLY_RE =
  /^(ahoj|cau|čau|dobr[ýy]\s+(de[nň]|rano|ráno)|hello|hi|zdravim|zdravím)\b[!.\s]*$/i;

const SWAP_RE =
  /\b(zmen|zmeň|vymen|vymeň|radsej|radšej|ine\b|iné\b)\b/i;

const SWAP_ITEM_RE =
  /\b(tričk|rifl|topánk|topank|bund|sortk|šortk|kratas|kraťas|nohavic|tenisk)\b/i;

const DRESS_CODE_AMBIGUOUS_RE =
  /\b(koncert|rande|date|divadl|svadb|oslava|gala)\b/i;

const VENUE_UNKNOWN_RE =
  /\bkoncert\b/i;

/**
 * @param {Object} input
 * @param {string} input.message
 * @param {Array<{role: string, content: string}>} input.history
 * @param {string} input.mode
 * @param {Object|null} input.weatherContext
 */
function buildServerRequestSignals(input) {
  const message = String(input.message || "").trim();
  const history = Array.isArray(input.history) ? input.history : [];
  const conversationBlob = [
    message,
    ...history.slice(-6).map((h) => String(h.content || "")),
  ]
    .join(" ")
    .toLowerCase();

  const wantsOutfit = WANTS_OUTFIT_RE.test(conversationBlob);
  const isPlannedActivity = PLANNED_ACTIVITY_RE.test(conversationBlob);
  const hasExplicitHour = HOUR_RE.test(conversationBlob);
  const isSimpleGreeting =
    GREETING_ONLY_RE.test(message) && !wantsOutfit && history.length <= 2;
  const isSwapOnly =
    SWAP_RE.test(message) && SWAP_ITEM_RE.test(conversationBlob);
  const dressCodeAmbiguous =
    DRESS_CODE_AMBIGUOUS_RE.test(conversationBlob) &&
    VENUE_UNKNOWN_RE.test(conversationBlob);
  const weatherRelevant =
    input.weatherContext?.fromOpenMeteo === true ||
    input.weatherContext?.willRain === true;
  const wetGroundHint =
    /\b(hory|hore|horach|les|luk|trav|hub|hrib|blat)\b/i.test(conversationBlob);

  let complexityScore = 0;
  if (isPlannedActivity) complexityScore += 3;
  if (wantsOutfit) complexityScore += 2;
  if (wantsOutfit && !hasExplicitHour) complexityScore += 2;
  if (weatherRelevant && isPlannedActivity) complexityScore += 2;
  if (wetGroundHint && input.weatherContext?.willRain) complexityScore += 2;
  if (dressCodeAmbiguous) complexityScore += 2;
  if (history.length > 4) complexityScore += 1;
  if (isSwapOnly) complexityScore -= 3;
  if (isSimpleGreeting) complexityScore -= 2;

  return {
    messageLength: message.length,
    historyLength: history.length,
    wantsOutfit,
    isPlannedActivity,
    hasExplicitHour,
    isSimpleGreeting,
    isSwapOnly,
    dressCodeAmbiguous,
    weatherRelevant,
    wetGroundHint,
    complexityScore,
  };
}

/**
 * @param {Object} signals
 * @param {string} mode
 * @returns {{ tier: string, confidence: number, reason: string }}
 */
function decideTierFromSignals(signals, mode) {
  if (mode === "rate_photo") {
    return {tier: "vision", confidence: 1, reason: "mode=rate_photo"};
  }
  if (mode === "explain_outfit") {
    return {tier: "standard", confidence: 1, reason: "mode=explain_outfit"};
  }

  if (signals.isSimpleGreeting) {
    return {tier: "fast", confidence: 0.95, reason: "simple_greeting"};
  }

  if (signals.isSwapOnly && signals.historyLength > 0) {
    return {tier: "fast", confidence: 0.85, reason: "swap_follow_up"};
  }

  if (signals.complexityScore >= 5) {
    return {
      tier: "premium",
      confidence: 0.9,
      reason: "high_complexity_score",
    };
  }

  if (
    signals.isPlannedActivity &&
    (signals.wantsOutfit || signals.dressCodeAmbiguous)
  ) {
    return {
      tier: "premium",
      confidence: 0.88,
      reason: "planned_activity_outfit",
    };
  }

  if (signals.wantsOutfit && !signals.hasExplicitHour) {
    return {
      tier: "premium",
      confidence: 0.8,
      reason: "outfit_missing_hour",
    };
  }

  if (signals.complexityScore >= 2) {
    return {tier: "standard", confidence: 0.75, reason: "medium_complexity"};
  }

  return {tier: "fast", confidence: 0.85, reason: "default_fast"};
}

module.exports = {
  buildServerRequestSignals,
  decideTierFromSignals,
};
