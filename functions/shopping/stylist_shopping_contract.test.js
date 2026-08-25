"use strict";
const assert=require("node:assert/strict"); const test=require("node:test");
const c=require("./stylist_shopping_contract");
test("ambiguous wardrobe request clarifies and explicit shopping starts",()=>{
 assert.equal(c.classifyShoppingUtterance("Ukáž mi niečo k týmto nohaviciam.").action,c.ACTIONS.CLARIFY_SOURCE);
 assert.equal(c.classifyShoppingUtterance("Chcem si kúpiť mikinu.").action,c.ACTIONS.START);
});
test("query patches keep explicit constraint strength and never inject weather",()=>{
 const p=c.buildQueryPatch("Chcem Nike mikinu bez zipsu do 50 € a teraz.");
 assert.equal(p.availableNow,true); assert.equal(p.constraints.length,4);
 assert.equal(p.constraints.find(x=>x.field==="canonicalType").value,"hoodie");
 assert.equal(p.constraints.find(x=>x.field==="maxPrice").value.amountMinor,5000);
 assert.equal(p.constraints.some(x=>x.field==="weather"),false);
});
test("show flows, price clarification, and session rejection stay session scoped",()=>{
 assert.equal(c.classifyShoppingUtterance("Ukáž ďalšie",{sessionId:"s"}).action,c.ACTIONS.SHOW_MORE);
 assert.equal(c.classifyShoppingUtterance("Je to drahé.",{sessionId:"s"}).action,c.ACTIONS.ASK_PRICE);
 assert.equal(c.classifyShoppingUtterance("Ani jedna sa mi nepáči.",{presentedVariantIds:["v"]}).rejectPresented,true);
});
test("AI action validation rejects invented catalog facts and IDs",()=>{
 assert.equal(c.validateAiShoppingAction({type:c.ACTIONS.FOCUS,variantId:"v"},["v"]).valid,true);
 assert.equal(c.validateAiShoppingAction({type:c.ACTIONS.FOCUS,variantId:"x"},["v"]).code,"UNKNOWN_CANDIDATE");
 assert.equal(c.validateAiShoppingAction({type:c.ACTIONS.FOCUS,variantId:"v",price:1},["v"]).code,"CATALOG_FACT_FORGERY");
});
test("references and wishlist offer remain typed contracts",()=>{
 const items=[{variantId:"a",brand:"Nike"},{variantId:"b",brand:"Adidas"}];
 assert.equal(c.resolveReference("tá druhá",items),"b");
 assert.equal(c.resolveReference("Nike mikina",items),"a");
 const offer=c.wishlistOffer("a",["M"]); assert.equal(offer.persistenceContract,"WISHLIST_V2"); assert.equal(offer.requiresUserTargetPrice,true);
});
test("Wardrobe gap canonical tokens remain structured",()=>{
 assert.equal(c.canonicalTypeFromText("formal_shoes"),"formal_shoes");
 assert.equal(c.canonicalTypeFromText("rain_jacket"),"rain_jacket");
});
