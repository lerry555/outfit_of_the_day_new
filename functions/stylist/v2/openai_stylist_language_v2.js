"use strict";

const LANGUAGE_MODEL = "gpt-5.6-luna";
const LANGUAGE_REASONING_EFFORT = "low";

const LANGUAGE_SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  required: ["assistantText"],
  properties: {assistantText: {type: "string"}},
});

function clean(value, max = 700) {
  return typeof value === "string" ? value.replace(/\s+/g, " ").trim().slice(0, max) : "";
}

function languagePromptV2() {
  return [
    "Si posledná LANGUAGE fáza slovenského AI Stylistu. Outfitové IDs sú už zmrazené a nesmieš ich meniť ani vracať.",
    "Napíš iba stručnú prirodzenú odpoveď používateľovi, zvyčajne 2 až 4 úplné vety.",
    "Buď priamy, teplý a profesionálny. Nepíš v prvej osobe a nepoužívaj formulácie typu vybral som, zvolil som, myslím si alebo za mňa.",
    "Nepoužívaj em dash ani en dash ako konverzačnú interpunkciu. Použi bodku, čiarku, dvojbodku alebo zátvorku.",
    "Názvy, dôvody, kompromisy a počasie musia presne zodpovedať dodaným faktom. Nevymýšľaj vlastnosti ani vnútornú teplotu.",
    "Ak uvádzaš teplotný rozsah, píš ho slovensky vo formáte mínimum až maximum °C a zachovaj znamienko mínus.",
    "Nevypisuj mechanický zoznam všetkých kúskov, ak stačí vysvetliť logiku outfitu. Materiálny kompromis však pomenuj otvorene.",
  ].join("\n");
}

function formatTemperatureRangeSkV2(minimum, maximum) {
  const min = Number(minimum);
  const max = Number(maximum);
  if (!Number.isFinite(min) || !Number.isFinite(max)) return null;
  return `${Math.round(min)} až ${Math.round(max)} °C`;
}

function containsForbiddenLanguageV2(value) {
  const text = clean(value);
  return /[—–]/u.test(text) ||
    /\b(by som|vybral som|vybrala som|zvolil som|zvolila som|volím|vyberám|myslím si|za mňa)\b/iu.test(text);
}

function naturalListSkV2(values) {
  const items = values.filter(Boolean);
  if (items.length < 2) return items[0] || "";
  if (items.length === 2) return `${items[0]} a ${items[1]}`;
  return `${items.slice(0, -1).join(", ")} a ${items.at(-1)}`;
}

function sentenceFragmentV2(value) {
  return clean(value, 180).replace(/[.!?;:]+$/u, "");
}

function deterministicLanguageFallbackV2(selectionContext, frozenSelection) {
  const byId = new Map((selectionContext.candidateItems || []).map((item) => [item.id, item]));
  const names = frozenSelection.selectedItemIds.map((id) => clean(byId.get(id)?.name, 100)).filter(Boolean);
  const recommendation = names.length ? `Zvoľ ${naturalListSkV2(names)}.` :
    "Zvoľ najvhodnejšie dostupné kúsky zo svojho šatníka.";
  const weather = selectionContext.selection?.context?.weather?.snapshot || {};
  const range = formatTemperatureRangeSkV2(weather.minTempC, weather.maxTempC);
  const weatherSentence = range ? `Vonku má byť približne ${range}.` : "";
  const compromise = sentenceFragmentV2(frozenSelection.compromises?.[0]);
  return clean([recommendation, weatherSentence,
    compromise ? `Najväčší kompromis: ${compromise}.` : ""]
    .filter(Boolean).join(" "));
}

function createOpenAiStylistLanguageV2({executeStructured, logger = console} = {}) {
  if (typeof executeStructured !== "function") throw new TypeError("language_executor_required");
  return Object.freeze({
    async render(selectionContext, frozenSelection) {
      const startedAt = Date.now();
      try {
        const byId = new Map((selectionContext.candidateItems || []).map((item) => [item.id, item]));
        const facts = {
          action: selectionContext.selection?.action,
          intentSummary: selectionContext.selection?.intentSummary,
          context: selectionContext.selection?.context,
          selectedItems: frozenSelection.selectedItemIds.map((id) => ({
            id,
            name: byId.get(id)?.name || null,
            canonicalType: byId.get(id)?.canonicalType || null,
          })),
          selectionReasons: frozenSelection.selectionReasons,
          compromises: frozenSelection.compromises,
          missingWardrobeNeeds: frozenSelection.missingWardrobeNeeds,
        };
        const raw = await executeStructured({
          model: LANGUAGE_MODEL,
          reasoningEffort: LANGUAGE_REASONING_EFFORT,
          schema: LANGUAGE_SCHEMA,
          schemaName: "stylist_v2_language",
          maxOutputTokens: 500,
          messages: [
            {role: "system", content: languagePromptV2()},
            {role: "user", content: JSON.stringify(facts)},
          ],
        }, {modelAttempt: 1});
        const text = clean(raw?.assistantText);
        return text && !containsForbiddenLanguageV2(text) ? text :
          deterministicLanguageFallbackV2(selectionContext, frozenSelection);
      } catch (error) {
        logger?.warn?.("STYLIST_V2_LANGUAGE_FALLBACK", {code: clean(error?.code || error?.message, 120)});
        return deterministicLanguageFallbackV2(selectionContext, frozenSelection);
      } finally {
        logger?.info?.("STYLIST_V2_LANGUAGE_LATENCY", {
          model: LANGUAGE_MODEL,
          reasoningEffort: LANGUAGE_REASONING_EFFORT,
          durationMs: Date.now() - startedAt,
        });
      }
    },
  });
}

module.exports = {
  LANGUAGE_MODEL,
  LANGUAGE_REASONING_EFFORT,
  LANGUAGE_SCHEMA,
  containsForbiddenLanguageV2,
  createOpenAiStylistLanguageV2,
  deterministicLanguageFallbackV2,
  formatTemperatureRangeSkV2,
  languagePromptV2,
  naturalListSkV2,
};
