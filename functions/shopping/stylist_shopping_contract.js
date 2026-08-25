"use strict";

const ACTIONS = Object.freeze({
  CLARIFY_SOURCE: "SHOPPING_CLARIFY_SOURCE",
  START: "START_SHOPPING_SEARCH",
  REFINE: "REFINE_SHOPPING_SEARCH",
  SHOW_MORE: "SHOW_MORE_SHOPPING",
  SHOW_ALL: "SHOW_ALL_SHOPPING",
  FOCUS: "FOCUS_SHOPPING_PRODUCT",
  OFFER_WISHLIST: "OFFER_WISHLIST",
  WISHLIST_EDITOR: "WISHLIST_EDITOR",
  RETURN_WARDROBE: "RETURN_TO_WARDROBE_STYLIST",
  ASK_PRICE: "ASK_SHOPPING_MAX_PRICE",
  CLARIFY_STYLE: "SHOPPING_CLARIFY_STYLE",
  ASK_PERMISSION: "ASK_PERMISSION_TO_SHOP",
  UNSUPPORTED_CONSTRAINT: "UNSUPPORTED_STRUCTURED_CONSTRAINT",
  ADD_TO_WARDROBE: "ADD_TO_WARDROBE",
});

function classifyShoppingUtterance(text, context = {}) {
  const value = String(text || "").toLowerCase();
  if (/(chcem si kúpiť|chcem kupit|niečo nové|nieco nove|z obchodov|novú mikinu|novu mikinu|úplne nový outfit|uplne novy outfit)/.test(value)) {
    return {action: ACTIONS.START};
  }
  if (/(ukáž mi niečo k|ukaz mi nieco k)/.test(value) && !context.shoppingSourceConfirmed) {
    return {action: ACTIONS.CLARIFY_SOURCE};
  }
  if (/(ďalšie|dalsie|máš ešte|mas este)/.test(value) && context.sessionId) return {action: ACTIONS.SHOW_MORE};
  if (/(všetky|vsetky)/.test(value) && context.sessionId) return {action: ACTIONS.SHOW_ALL};
  if (/(drahé|drahe|lacnejšie|lacnejsie)/.test(value) && !extractEuro(value)) return {action: ACTIONS.ASK_PRICE};
  if (/(not my style|nie je môj štýl|nie je moj styl)/.test(value)) return {action: ACTIONS.CLARIFY_STYLE};
  if (/(ani jedna|žiadna sa mi nepáči|ziadna sa mi nepaci)/.test(value) && context.presentedVariantIds?.length) {
    return {action: ACTIONS.SHOW_MORE, rejectPresented: true};
  }
  return null;
}

function buildQueryPatch(text) {
  const value = String(text || "").toLowerCase();
  const constraints = [];
  const amount = extractEuro(value);
  const referencedGarmentOnly = /(k týmto|k tymto)\s+(nohaviciam|nohavice)/.test(value);
  const canonicalType = referencedGarmentOnly ? null : canonicalTypeFromText(value);
  if (canonicalType) constraints.push({field:"canonicalType", operator:"equals",
    value:canonicalType, strength:"hard", source:"explicitUser"});
  if (/(tmavomodr|navy)/.test(value)) constraints.push({field:"color",operator:"equals",
    value:"navy",strength:"hard",source:"explicitUser",absolute:true});
  if (amount != null) constraints.push({field:"maxPrice", operator:"atMost",
    value:{amountMinor: amount * 100, currency:"EUR"}, strength:"hard", source:"explicitUser"});
  if (/\bnike\b/.test(value)) constraints.push({field:"brand",operator:"equals",value:"Nike",strength:"hard",source:"explicitUser"});
  if (/(bez zipsu|without zipper)/.test(value)) constraints.push({field:"detail",operator:"excludes",value:{key:"zipper",value:true},strength:"hard",source:"explicitUser"});
  if (/(chcem oversized|must be oversized)/.test(value)) constraints.push({field:"fit",operator:"equals",value:"oversized",strength:"hard",source:"explicitUser"});
  if (/(môže byť oversized|moze byt oversized)/.test(value)) constraints.push({field:"fit",operator:"equals",value:"oversized",strength:"soft",source:"explicitUser"});
  if (/(teraz|dnes|skladom)/.test(value)) return {constraints, availableNow:true};
  return {constraints, availableNow:false};
}

function canonicalTypeFromText(value) {
  const normalizedToken = String(value || "").trim().toLowerCase();
  if (["shirt", "formal_shoes", "hiking_pants", "rain_jacket", "polo"].includes(normalizedToken)) {
    return normalizedToken;
  }
  if (/(mikinu|mikina|hoodie)/.test(value)) return "hoodie";
  if (/(košeľu|koselu|košeľa|kosela|shirt)/.test(value)) return "shirt";
  if (/(nohavice|trousers|pants)/.test(value)) return "trousers";
  if (/(bund[auy]|jacket)/.test(value)) return "jacket";
  if (/(topánky|topanky|shoes)/.test(value)) return "shoes";
  if (/(nový top|novy top|\btop\b)/.test(value)) return "top";
  return null;
}

function buildShoppingNeeds(text) {
  const value = String(text || "").toLowerCase();
  if (/(úplne nový outfit|uplne novy outfit|completely new outfit)/.test(value)) {
    return {mode:"COMPLETELY_NEW_OUTFIT", needs:[
      {slot:"top", canonicalType:null}, {slot:"bottom", canonicalType:null},
      {slot:"footwear", canonicalType:null},
    ], allowOwnedSimilarity:true};
  }
  const types = [];
  for (const part of value.split(/\+| a /)) {
    const type = canonicalTypeFromText(part);
    if (type && !types.includes(type)) types.push(type);
  }
  return {mode:types.length > 1 ? "MULTI_ITEM" : "SINGLE_ITEM",
    needs:types.map((canonicalType) => ({slot:null,canonicalType})),
    allowOwnedSimilarity:false};
}

function validateAiShoppingAction(action, allowedCandidates = []) {
  if (!action || !Object.values(ACTIONS).includes(action.type)) return {valid:false, code:"INVALID_ACTION"};
  if (action.variantId && !allowedCandidates.includes(action.variantId)) return {valid:false,code:"UNKNOWN_CANDIDATE"};
  const forbidden = ["price","store","url","coupon","availability","quantity","offerId"];
  if (forbidden.some((field) => Object.prototype.hasOwnProperty.call(action, field))) {
    return {valid:false,code:"CATALOG_FACT_FORGERY"};
  }
  return {valid:true};
}

function resolveReference(text, candidates) {
  const value=String(text||"").toLowerCase();
  const ordinal=value.match(/(prvá|prva|first|druhá|druha|second)/);
  if (ordinal) return candidates[/(druhá|druha|second)/.test(ordinal[0]) ? 1 : 0]?.variantId || null;
  const matches=candidates.filter((c)=> c.brand && value.includes(c.brand.toLowerCase()));
  if (matches.length===1) return matches[0].variantId;
  const nameMatches = candidates.filter((candidate) => {
    const name = String(candidate.displayName || "").toLowerCase().trim();
    return name.length >= 3 && value.includes(name);
  });
  if (nameMatches.length === 1) return nameMatches[0].variantId;
  const amount = value.match(/(\d+)(?:[,.](\d{1,2}))?\s*(?:€|eur)/i);
  if (amount) {
    const minor = Number(amount[1]) * 100 + Number((amount[2] || "").padEnd(2, "0"));
    const priceMatches = candidates.filter((candidate) => {
      const price = candidate.effectivePublicPrice?.price ||
        candidate.effectivePublicPrice;
      return price?.currency === "EUR" && price?.amountMinor === minor;
    });
    if (priceMatches.length === 1) return priceMatches[0].variantId;
  }
  return null;
}

function wishlistOffer(variantId, selectedSizeKeys = []) {
  return {type:ACTIONS.OFFER_WISHLIST,variantId,selectedSizeKeys,
    requiresUserTargetPrice:true,persistenceContract:"WISHLIST_V2",
    persistsOnlyAfterConfirmation:true};
}
function extractEuro(value) { const hit=String(value).match(/(?:do|max)\s*(\d+)\s*(?:€|eur)?/i); return hit ? Number(hit[1]) : null; }

module.exports={ACTIONS,buildQueryPatch,buildShoppingNeeds,canonicalTypeFromText,
  classifyShoppingUtterance,resolveReference,validateAiShoppingAction,wishlistOffer};
