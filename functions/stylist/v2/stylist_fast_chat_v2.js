"use strict";

const FAST_CHAT_MODEL = "gpt-5.6-luna";
const FAST_CHAT_REASONING = "low";

const FAST_CHAT_SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  required: ["reply"],
  properties: {
    reply: {type: "string", minLength: 1, maxLength: 520},
  },
});

function clean(value, max = 1200) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function normalize(value) {
  return clean(value)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function recentHistory(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.slice(-6).map((entry) => ({
    role: entry?.role === "assistant" ? "assistant" : "user",
    content: clean(entry?.content, 700),
  })).filter((entry) => entry.content);
}

function hasCurrentOutfit(state, currentOutfitItemIds) {
  if (Array.isArray(currentOutfitItemIds) && currentOutfitItemIds.length) return true;
  return Array.isArray(state?.currentOutfit?.itemIds) && state.currentOutfit.itemIds.length > 0;
}

function isFastChatEligibleV2({message, state = null, currentOutfitItemIds = [], shoppingActive = false} = {}) {
  if (shoppingActive || hasCurrentOutfit(state, currentOutfitItemIds)) return false;
  if (state?.conversationMemory?.pendingQuestion || state?.conversationMemory?.pendingAction) return false;

  const text = normalize(message);
  if (!text || text.length > 420) return false;

  // Anything that can mutate/select a personal outfit or needs live context stays
  // on the authoritative agent path. Fast chat is intentionally narrow.
  const personalAction = /\b(outfit|oblecen|obliect|na seba|vyber mi|navrhni mi|zostav mi|vymen|nahrad|zmen|pridaj|odstran|ukaz mi|moj outfit|moje oblecenie|moj satnik|mojom satniku)\b/.test(text);
  const liveContext = /\b(dnes|zajtra|vecer|rano|poobede|pocasie|teplota|prsi|dazd|sneh|lad|blato|tura|turistika|hiking|svadba|pohovor|koncert|kino|vecera|rande|praca|kam idem|idem do|idem na)\b/.test(text);
  if (personalAction || liveContext) return false;

  // Match Slovak stems without requiring a word boundary immediately after
  // the stem: "farb" must match "farby/farba/farebný", "modr" -> "modrej".
  return /\b(farb|cier|biel|modr|zelen|cerven|ruz|hned|bezov|siv|zlt|oranz|fial|kombin|hodi sa|hodia sa|pasuje|lad|styl|strih|material|vzor|rozdiel|znamena|fashion|moda)/.test(text);
}

function fastChatSystemPromptV2() {
  return [
    "Si prirodzený osobný módny poradca v chate. Odpovedáš po slovensky.",
    "Odpovedz priamo a ľudsky, bez technických výrazov, interných krokov a bez formulárového tónu.",
    "Použi 2 až 5 krátkych viet. Píš gramaticky, s normálnou interpunkciou.",
    "Toto je všeobecná módna konzultácia: nevymýšľaj používateľov šatník, polohu, počasie ani konkrétny osobný outfit.",
    "Ak je užitočný krátky príklad kombinácie farieb alebo materiálov, uveď ho prirodzene v texte.",
    "Nevkladaj nákupnú ponuku ani otázku Áno/Nie, pokiaľ ju používateľ výslovne nepýta.",
  ].join("\n");
}

function createStylistFastChatV2({executeStructured}) {
  if (typeof executeStructured !== "function") throw new TypeError("fast_chat_executor_required");
  return Object.freeze({
    async turn({message, history = []}) {
      const raw = await executeStructured({
        model: FAST_CHAT_MODEL,
        reasoningEffort: FAST_CHAT_REASONING,
        schema: FAST_CHAT_SCHEMA,
        schemaName: "stylist_v2_fast_chat",
        maxOutputTokens: 420,
        messages: [
          {role: "system", content: fastChatSystemPromptV2()},
          {role: "user", content: JSON.stringify({message: clean(message, 900), recentHistory: recentHistory(history)})},
        ],
      }, {modelAttempt: 1});
      const reply = clean(raw?.reply, 520);
      if (!reply) throw new Error("stylist_fast_chat_empty_reply");
      return {reply};
    },
  });
}

module.exports = {
  FAST_CHAT_MODEL,
  FAST_CHAT_REASONING,
  FAST_CHAT_SCHEMA,
  createStylistFastChatV2,
  fastChatSystemPromptV2,
  isFastChatEligibleV2,
  normalize,
  recentHistory,
};
