"use strict";

const SELECTOR_MODEL = "gpt-5.6-terra";
const SELECTOR_REASONING_EFFORT = "medium";

const SELECTOR_SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  required: ["selectedItemIds", "selectionReasons", "compromises", "missingWardrobeNeeds"],
  properties: {
    selectedItemIds: {type: "array", minItems: 1, maxItems: 12, items: {type: "string"}},
    selectionReasons: {
      type: "array", minItems: 1, maxItems: 12,
      items: {
        type: "object", additionalProperties: false, required: ["itemId", "reason"],
        properties: {itemId: {type: "string"}, reason: {type: "string"}},
      },
    },
    compromises: {type: "array", maxItems: 8, items: {type: "string"}},
    missingWardrobeNeeds: {type: "array", maxItems: 8, items: {type: "string"}},
  },
});

function selectorPromptV2() {
  return [
    "Si špecializovaný OUTFIT SELECTOR. Dostaneš malý selection contract a reálne kandidáty zo šatníka.",
    "Tvojou jedinou úlohou je vybrať finálne item IDs a ku každému zapísať stručný konkrétny dôvod.",
    "Nevlastníš konverzáciu, nepíšeš používateľskú odpoveď a nemeníš autorizovaný edit scope.",
    "Použi iba candidateItems[].id. Pri edit_outfit zachovaj všetky retainItemIds a meň iba autorizovaný rozsah.",
    "Metadata sú autoritatívne pre ne-vizuálne fakty: typ, body slots, layer position, warmth, formality, sezónu, funkciu a bezpečnostné atribúty.",
    "Obrázky sú doplnkový vizuálny dôkaz pre strih, siluetu, textúru, paletu a vizuálnu súdržnosť. Neodvodzuj z nich nepremokavosť, priľnavosť, teplotu ani inú nedoloženú vlastnosť.",
    "Nie každý kandidát musí mať obrázok. Chýbajúci obrázok nie je negatívny signál a kandidáta nevylučuje.",
    "Posudzuj outfit ako celok: účel, explicitné obmedzenia, počasie a bezpečnosť, tepelnú a praktickú vhodnosť, siluetu a proporcie, vrstvenie, formálnosť, paletu a potom malé detaily.",
    "Nevytváraj pravidlá pre konkrétne pomenované scenáre. Aplikuj všeobecné módne a situačné princípy na dodaný kontext.",
    "Ak ideálny kus chýba, vyber najlepší bezpečný dostupný výsledok, pomenuj kompromis a missingWardrobeNeeds. Nevymýšľaj kusy ani vlastnosti.",
    "Dôvod musí vysvetľovať skutočné rozhodnutie v kontexte celku, nie iba zopakovať názov alebo farbu.",
  ].join("\n");
}

function selectorInputV2(selectionContext, feedback = null) {
  const imageContent = [];
  for (const evidence of selectionContext.visualEvidence || []) {
    imageContent.push({type: "input_text", text: `Vizuálny dôkaz pre itemId ${evidence.id}:`});
    imageContent.push({type: "input_image", image_url: evidence.imageUrl, detail: "low"});
  }
  return [
    {role: "system", content: [{type: "input_text", text: selectorPromptV2()}]},
    {role: "user", content: [
      {type: "input_text", text: JSON.stringify({
        ...selectionContext.selection,
        qualityFeedback: feedback || null,
      })},
      ...imageContent,
    ]},
  ];
}

function createOpenAiOutfitSelectorV2({executeStructured, logger = console} = {}) {
  if (typeof executeStructured !== "function") throw new TypeError("selector_executor_required");
  return Object.freeze({
    async select(selectionContext, {feedback = null, attempt = 1} = {}) {
      const startedAt = Date.now();
      try {
        return await executeStructured({
          model: SELECTOR_MODEL,
          reasoningEffort: SELECTOR_REASONING_EFFORT,
          schema: SELECTOR_SCHEMA,
          schemaName: "stylist_v2_outfit_selection",
          maxOutputTokens: 1000,
          input: selectorInputV2(selectionContext, feedback),
        }, {modelAttempt: attempt});
      } finally {
        logger?.info?.("STYLIST_V2_SELECTOR_LATENCY", {
          model: SELECTOR_MODEL,
          reasoningEffort: SELECTOR_REASONING_EFFORT,
          attempt,
          candidateCount: selectionContext.selection?.candidateItems?.length || 0,
          visualEvidenceCount: selectionContext.visualEvidence?.length || 0,
          durationMs: Date.now() - startedAt,
        });
      }
    },
  });
}

module.exports = {
  SELECTOR_MODEL,
  SELECTOR_REASONING_EFFORT,
  SELECTOR_SCHEMA,
  createOpenAiOutfitSelectorV2,
  selectorInputV2,
  selectorPromptV2,
};
