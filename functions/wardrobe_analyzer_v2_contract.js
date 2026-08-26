"use strict";
const {artifact, canonicalDefinition} = require("./wardrobe_ontology_v2");
const TONES = new Set(artifact.enums.metalTones);
function validateAnalyzerV2(raw) {
  const errors=[]; if (!raw || typeof raw!=="object" || Array.isArray(raw)) return {ok:false,errors:["root.object_required"],value:null};
  for (const [k,v] of [["contractVersion","wardrobe-analyzer-v2"],["taxonomyVersion",artifact.taxonomyVersion]]) if (raw[k]!==v) errors.push(`${k}.invalid`);
  const type=raw.identity?.canonicalType; if (!canonicalDefinition(type)) errors.push("identity.canonicalType.unknown");
  const candidates=raw.identity?.candidateTypes; if (!Array.isArray(candidates)||candidates.length>3||candidates.some((x)=>!canonicalDefinition(x.canonicalType)||typeof x.confidence!=="number"||x.confidence<0||x.confidence>1)) errors.push("identity.candidateTypes.invalid");
  if (typeof raw.identity?.confidence!=="number"||raw.identity.confidence<0||raw.identity.confidence>1) errors.push("identity.confidence.invalid");
  const cp=raw.observed?.colorProfile; if (!cp||typeof cp!=="object"||!cp.primary||typeof cp.primary.family!=="string"||!Array.isArray(cp.accents)||!TONES.has(cp.metalTone)||!TONES.has(cp.hardwareTone)) errors.push("observed.colorProfile.invalid");
  const allowed=new Set(canonicalDefinition(type)?.allowedAttributes||[]); const attrs=raw.observed?.attributes;
  if (!attrs||typeof attrs!=="object"||Array.isArray(attrs)||Object.keys(attrs).some((key)=>!allowed.has(key))) errors.push("observed.attributes.invalid");
  if (!raw.inferred||!Number.isInteger(raw.inferred.formality)||raw.inferred.formality<1||raw.inferred.formality>10||!Array.isArray(raw.inferred.styles)||!Array.isArray(raw.inferred.occasionFit)) errors.push("inferred.invalid");
  const warmthRange=canonicalDefinition(type)?.warmthRange;
  if (!Number.isInteger(raw.inferred?.warmth)||
      raw.inferred.warmth<1||raw.inferred.warmth>10) {
    errors.push("inferred.warmth.invalid");
  } else if (warmthRange &&
      (raw.inferred.warmth<warmthRange.min||
       raw.inferred.warmth>warmthRange.max)) {
    errors.push("inferred.warmth.out_of_type_range");
  }
  if (!raw.evidence||!Array.isArray(raw.evidence.visibleRegions)||typeof raw.evidence.fieldConfidence!=="object"||Object.values(raw.evidence.fieldConfidence||{}).some((value)=>typeof value!=="number"||value<0||value>1)) errors.push("evidence.invalid");
  return {ok:errors.length===0,errors:[...new Set(errors)].sort(),value:errors.length?null:raw};
}
function buildGeminiResponseSchema() {
  return require("./clothing_vision/gemini_wardrobe_analyzer_v2_transport")
    .buildGeminiWardrobeAnalyzerV2Schema();
}
module.exports={validateAnalyzerV2,buildGeminiResponseSchema};
