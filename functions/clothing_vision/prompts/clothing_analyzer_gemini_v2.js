"use strict";
const crypto=require("crypto");
const {artifact}=require("../../wardrobe_ontology_v2");
const {buildGeminiWardrobeAnalyzerV2Schema}=require("../gemini_wardrobe_analyzer_v2_transport");
const MODEL_ID="gemini-3.5-flash", PROMPT_VERSION="clothing_analyzer_gemini_v2", ANALYZER_VERSION="clothing-vision-gemini-v2";
const canonicalTypes=artifact.items.map((item)=>item.canonicalType).join(", ");
const allowedAttributeKeys=[...new Set(artifact.items.flatMap((item)=>item.allowedAttributes||[]))].sort().join(", ");
const prompt=`You analyze one wardrobe item for OOTD. Use only visual evidence. Return the flat Gemini transport JSON supplied as the response schema. The server converts it to the provider-neutral wardrobe-analyzer-v2 domain contract.

Identity: analyze the complete item, choose canonicalType from the supplied taxonomy, and return up to three candidateTypes. Use the correct parent when subtype evidence is insufficient; never guess a sibling. Do not infer body slots, layer position, outfit functions, UI category, or multiplicity: those are deterministic KB responsibilities.

Observed fields: distinguish primary, secondary, and small accent colors by visual role. A small logo color is an accent, not automatically secondary. metalTone and hardwareTone describe visible metal appearance and are not textile colors. Report only observable pattern, material appearance, fit/silhouette, visual scale, and family-allowed attributes. Do not invent fiber or brand.

Inferred fields: formality and warmth are item-specific 1-10 estimates. styles and occasionFit use concise controlled terms. Uncertainty must lower confidence instead of fabricating specificity.

Allowed canonicalType values (use each list only as an allowlist): ${canonicalTypes}.
Allowed attribute keys (emit only visually supported keys valid for the chosen family): ${allowedAttributeKeys}.

Use an empty family/hex and proportion 0 when there is no secondary color. Return attributes as key/value pairs and fieldConfidence as field/confidence pairs. Evidence: provide compact visible region labels and field-level confidence numbers only. Do not provide hidden reasoning or chain-of-thought. Include every required property.`;
const PROMPT_HASH=crypto.createHash("sha256").update(prompt).digest("hex");
function getClothingAnalyzerGeminiPromptV2(){return Object.freeze({modelId:MODEL_ID,promptVersion:PROMPT_VERSION,promptHash:PROMPT_HASH,analyzerVersion:ANALYZER_VERSION,taxonomyVersion:artifact.taxonomyVersion,prompt,responseSchema:buildGeminiWardrobeAnalyzerV2Schema()});}
module.exports={MODEL_ID,PROMPT_VERSION,PROMPT_HASH,ANALYZER_VERSION,getClothingAnalyzerGeminiPromptV2};
