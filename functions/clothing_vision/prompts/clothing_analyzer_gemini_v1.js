"use strict";

/**
 * Production Gemini clothing analyzer prompt v1.
 *
 * Behavioral baseline derived from production_prompt_gemini_v2
 * (SHA e7ceec8e7f86d24305962acca9251e87b6567056f130913b98582b5e27defbc5),
 * adapted to the live OOTD production analyzer contract (not the blind wire schema).
 */

const crypto = require("node:crypto");

const PROMPT_VERSION = "clothing_analyzer_gemini_v1";
const ANALYZER_VERSION = "clothing-vision-gemini-v1";
const MODEL_ID = "gemini-3.5-flash";

const PROMPT_TEXT = `
You are analyzing a single photograph of one clothing item for the OOTD wardrobe app.

Use ONLY visual evidence in the provided image. Do not invent details that are not visually supportable. Prefer abstaining over fabrication.

Return ONE JSON object matching the required production schema. Include ALL required keys. No markdown. No code fences. No extra properties.

Behavioral rules:
- Classify the COMPLETE visible garment, not an isolated region (e.g. not bodice alone).
- Prefer the most specific accurate canonical_type ONLY when visually justified.
- A correct broader/parent type is preferable to an unsupported wrong child/sibling type.
- Garment identity determines category semantics, NOT whether the item is visually outermost in the photo.
- Bottoms (jeans, pants, skirts, etc.) remain bottoms even if they are the outermost garment on the legs.
- One-piece garments (dress, jumpsuit, romper, swimsuit one-piece families) must remain one-piece identity — do not reclassify them as tops merely because the upper portion dominates the frame.
- layer_role describes how the garment is typically worn in an outfit stack/body placement for this app. It is NOT the same as broad garment category. Do not equate "outermost pixels" with outerwear identity.
- material_feel may describe OBSERVABLE characteristics only (knit, ribbed, woven, fuzzy, smooth, sheer, structured, denim-like, etc.).
- Do NOT infer exact fiber chemistry (e.g. 100% cotton, polyester, wool, elastane) from appearance alone. Only mention fiber if literally readable on a label in the image.
- brand must NOT be guessed from style similarity. Set brand to "" unless branding is clearly visible/readable.
- visual_identity: only when a strong readable logo/crest/text identity is visible with high confidence; otherwise "".
- Do not convert uncertainty into fabricated specificity.
- All production-required fields must be returned.

canonical_type: English snake_case wardrobe type key (e.g. t_shirt, jeans, denim_jacket, midi_skirt, summer_dress). Use null only if truly unknown.
type / type_pretty / primary_type: short Slovak human labels for UI.
secondary_type: alternate Slovak label when ambiguous, else "".
colors: Slovak color names from the allowed list only.
styles, patterns, seasons: from allowed lists only. patterns is [] or one value.
layer_role: one of base_layer, mid_layer, outer_layer, bottom, footwear, accessory.
  Examples: t-shirt → base_layer; hoodie/sweater → mid_layer; coat/jacket → outer_layer; jeans/skirt → bottom; sneakers → footwear.
warmth_level: integer 1–10 (1 very light, 10 very warm).
formality: integer 1–10 (1 beach/home, 10 formal).
confidence: integer 0–100 for primary garment identity.
fit / vibe / logo_prominence: use "unknown" when unsure.
occasion_fit: allowed values only, or [].
material_feel: short observable phrase, or "unknown".
identity_slot: tops | outerwear | bottoms | one_piece | footwear | accessories — garment identity/body placement, NOT outermost-pixel logic. Used for validation only.
`.trim();

function hashPrompt(text) {
  return crypto.createHash("sha256").update(String(text), "utf8").digest("hex");
}

const PROMPT_HASH = hashPrompt(PROMPT_TEXT);

function getClothingAnalyzerGeminiPromptV1() {
  return Object.freeze({
    promptVersion: PROMPT_VERSION,
    promptHash: PROMPT_HASH,
    analyzerVersion: ANALYZER_VERSION,
    modelId: MODEL_ID,
    prompt: PROMPT_TEXT,
  });
}

module.exports = {
  PROMPT_VERSION,
  PROMPT_HASH,
  ANALYZER_VERSION,
  MODEL_ID,
  PROMPT_TEXT,
  hashPrompt,
  getClothingAnalyzerGeminiPromptV1,
};
