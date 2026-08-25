"use strict";
const {validateAnalyzerV2}=require("../wardrobe_analyzer_v2_contract");
const {enrichIdentity,applyAnalyzerResult,validateWardrobeItemV2,artifact}=require("../wardrobe_ontology_v2");
function adaptAnalyzerV2ToWardrobeItem(parsed,{existingItem={},provenance={}}={}){
  const checked=validateAnalyzerV2(parsed);if(!checked.ok){const e=new Error("analyzer_v2_invalid");e.code="analyzer_v2_invalid";e.details=checked.errors;throw e;}
  const base={ontologyVersion:artifact.ontologyVersion,taxonomyVersion:artifact.taxonomyVersion,kbVersion:artifact.kbVersion,...enrichIdentity(parsed.identity.canonicalType),colorProfile:parsed.observed.colorProfile,formality:parsed.inferred.formality,styles:parsed.inferred.styles,occasionFit:parsed.inferred.occasionFit,seasons:[],warmth:parsed.inferred.warmth,attributes:parsed.observed.attributes||{},setMembership:existingItem.setMembership??null,fieldSources:{canonicalType:"visual_ai"},fieldConfidence:{canonicalType:parsed.identity.confidence,...parsed.evidence.fieldConfidence},userOverrideFields:[...(existingItem.userOverrideFields||[])],analyzerProvenance:{analyzerVersion:parsed.analyzerVersion,analyzerProvider:"google",analyzerModel:parsed.modelVersion,analyzerPromptVersion:provenance.promptVersion||null,analyzerPromptHash:provenance.promptHash||null,taxonomyVersion:artifact.taxonomyVersion,ontologyVersion:artifact.ontologyVersion,kbVersion:artifact.kbVersion}};
  const merged=applyAnalyzerResult({...base,...existingItem},parsed);const valid=validateWardrobeItemV2(merged,{strict:false});if(!valid.ok){const e=new Error("wardrobe_item_v2_invalid");e.code="wardrobe_item_v2_invalid";e.details=valid.errors;throw e;}return merged;
}
function adaptAnalyzerV2ToClientResponse(parsed,{provenance={}}={}){
  const wardrobeV2=adaptAnalyzerV2ToWardrobeItem(parsed,{provenance});
  const colors=[wardrobeV2.colorProfile.primary,wardrobeV2.colorProfile.secondary]
    .filter(Boolean).map(x=>x.family).filter(Boolean);
  return {
    contractVersion:"wardrobe-analyzer-v2",
    canonical_type:wardrobeV2.canonicalType,
    canonicalType:wardrobeV2.canonicalType,
    type:wardrobeV2.canonicalType,
    type_pretty:wardrobeV2.canonicalType,
    colors,
    styles:wardrobeV2.styles,
    patterns:parsed.observed.patterns||[],
    seasons:wardrobeV2.seasons,
    fit:parsed.observed.fit||"unknown",
    formality:wardrobeV2.formality,
    occasion_fit:wardrobeV2.occasionFit,
    material_feel:parsed.observed.materialAppearance||"unknown",
    warmth_level:wardrobeV2.warmth,
    confidence:Math.round(parsed.identity.confidence*100),
    identity_confidence:parsed.identity.confidence,
    analyzerVersion:wardrobeV2.analyzerProvenance.analyzerVersion,
    analyzerProvider:wardrobeV2.analyzerProvenance.analyzerProvider,
    analyzerModel:wardrobeV2.analyzerProvenance.analyzerModel,
    analyzerPromptVersion:wardrobeV2.analyzerProvenance.analyzerPromptVersion,
    analyzerPromptHash:wardrobeV2.analyzerProvenance.analyzerPromptHash,
    wardrobeV2,
  };
}
module.exports={adaptAnalyzerV2ToWardrobeItem,adaptAnalyzerV2ToClientResponse};
