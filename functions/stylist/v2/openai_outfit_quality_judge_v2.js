"use strict";

const {balancedVisualEvidenceV2, imageUrlV2} = require("./stylist_selection_context_v2");

const JUDGE_MODEL = "gpt-5.6-terra";
const JUDGE_REASONING_EFFORT = "medium";
const JUDGE_VISUAL_EVIDENCE_LIMIT = 16;

const JUDGE_SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  required: ["verdict", "problems", "retryGuidance"],
  properties: {
    verdict: {type: "string", enum: ["pass", "retry"]},
    problems: {type: "array", maxItems: 10, items: {type: "string"}},
    retryGuidance: {type: ["string", "null"]},
  },
});

function judgePromptV2() {
  return [
    "Si OUTFIT QUALITY JUDGE. Nevyberáš ani nemeníš item IDs. Kontroluješ návrh Selectora proti rovnakému selection contractu.",
    "Vráť pass iba ak je návrh použiteľný ako celý outfit a dôvody sú pravdivé vzhľadom na autoritatívne metadata.",
    "Kontroluj všeobecne: splnenie explicitných obmedzení a edit scope, účel a bezpečnosť, počasie, tepelnú a praktickú vhodnosť, vrstvenie, siluetu a proporcie, formálnosť, paletu, vizuálnu súdržnosť a zbytočnú redundanciu.",
    "Osobitne odmietni dôvod, ktorý opisuje iný kus, inú farbu, inú vrstvu alebo inú funkciu než vybrané itemId. Metadata majú prednosť pri ne-vizuálnych faktoch.",
    "Obrázky sú iba doplnkový dôkaz pre vzhľad. Chýbajúci obrázok kandidáta nie je chyba. Nevymýšľaj technické vlastnosti z obrázka.",
    "Nevynucuj osobný vkus ani pravidlo pre jeden pomenovaný scenár. retry použi pri materiálnej chybe, nie pri rovnocennej estetickej alternatíve.",
    "Pri retry daj krátke actionable retryGuidance bez navrhovania konkrétnych nových IDs. Pri pass musí byť retryGuidance null.",
  ].join("\n");
}

function judgeVisualEvidenceV2(selectionContext, selection, limit = JUDGE_VISUAL_EVIDENCE_LIMIT) {
  const boundedLimit = Number.isSafeInteger(limit) && limit >= 0 ?
    Math.min(limit, JUDGE_VISUAL_EVIDENCE_LIMIT) : JUDGE_VISUAL_EVIDENCE_LIMIT;
  const selectedIds = [...new Set(Array.isArray(selection?.selectedItemIds) ?
    selection.selectedItemIds.filter((id) => typeof id === "string" && id) : [])];
  const candidateItems = Array.isArray(selectionContext?.candidateItems) ? selectionContext.candidateItems : [];
  const candidateById = new Map(candidateItems.map((item) => [item?.id, item]));
  const evidence = [];
  const seen = new Set();
  const add = (id, imageUrl) => {
    if (!id || !imageUrl || seen.has(id) || evidence.length >= boundedLimit) return;
    seen.add(id);
    evidence.push({id, imageUrl});
  };

  // The Selector can choose any metadata candidate, including one outside its
  // bounded image sample. Re-resolve selected images from the raw candidate
  // lineage so every available selected visual reaches the Judge first.
  for (const id of selectedIds) add(id, imageUrlV2(candidateById.get(id)));

  // The Selector's balanced sample is the best existing pool of alternatives.
  for (const entry of selectionContext?.visualEvidence || []) add(entry?.id, entry?.imageUrl);

  // Keep a bounded structural fallback for contexts built with a smaller or
  // empty Selector visual budget.
  for (const entry of balancedVisualEvidenceV2(candidateItems, [], boundedLimit)) {
    add(entry.id, entry.imageUrl);
  }
  return evidence;
}

function judgeInputV2(selectionContext, selection) {
  const selected = new Set(Array.isArray(selection?.selectedItemIds) ? selection.selectedItemIds : []);
  const orderedEvidence = judgeVisualEvidenceV2(selectionContext, selection);
  const imageContent = [];
  for (const evidence of orderedEvidence) {
    imageContent.push({type: "input_text", text:
      `${selected.has(evidence.id) ? "Vybraný" : "Alternatívny"} vizuálny dôkaz pre itemId ${evidence.id}:`});
    imageContent.push({type: "input_image", image_url: evidence.imageUrl, detail: "low"});
  }
  return [
    {role: "system", content: [{type: "input_text", text: judgePromptV2()}]},
    {role: "user", content: [
      {type: "input_text", text: JSON.stringify({contract: selectionContext.selection, selection})},
      ...imageContent,
    ]},
  ];
}

function createOpenAiOutfitQualityJudgeV2({executeStructured, logger = console} = {}) {
  if (typeof executeStructured !== "function") throw new TypeError("judge_executor_required");
  return Object.freeze({
    async judge(selectionContext, selection) {
      const startedAt = Date.now();
      try {
        return await executeStructured({
          model: JUDGE_MODEL,
          reasoningEffort: JUDGE_REASONING_EFFORT,
          schema: JUDGE_SCHEMA,
          schemaName: "stylist_v2_outfit_quality_judgment",
          maxOutputTokens: 700,
          input: judgeInputV2(selectionContext, selection),
        }, {modelAttempt: 1});
      } finally {
        logger?.info?.("STYLIST_V2_JUDGE_LATENCY", {
          model: JUDGE_MODEL,
          reasoningEffort: JUDGE_REASONING_EFFORT,
          selectedItemCount: selection?.selectedItemIds?.length || 0,
          durationMs: Date.now() - startedAt,
        });
      }
    },
  });
}

module.exports = {
  JUDGE_MODEL,
  JUDGE_REASONING_EFFORT,
  JUDGE_SCHEMA,
  JUDGE_VISUAL_EVIDENCE_LIMIT,
  createOpenAiOutfitQualityJudgeV2,
  judgeInputV2,
  judgePromptV2,
  judgeVisualEvidenceV2,
};
