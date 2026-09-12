"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");
const {createStylistChatV2Handler} = require("./stylist_production_bridge_one_brain_v2");
const NOW = Date.parse("2026-09-12T08:00:00.000Z");
const items = [
  {id:"tee",category:"tops",bodySlots:["upper_body"],canonicalType:"t_shirt"},
  {id:"pants",category:"bottoms",bodySlots:["lower_body"],canonicalType:"pants"},
  {id:"shoes",category:"footwear",bodySlots:["feet"],canonicalType:"sneakers"},
];
function firstEnvelope(){return {kind:"final",pendingReplyDisposition:"none",statePatch:{context:{activity:{id:"hiking",label:"túra",source:"user"},date:{dateKey:"2026-09-14",source:"user"},environment:"outdoor",groundingRequirements:{weatherRequired:true,weatherLocationField:"destination",terrainRequiredFields:[]}}},result:{action:"chat",assistantText:"Poďme na to.",display:{kind:"none",itemIds:[]}}};}
function badPending(){return {kind:"final",pendingReplyDisposition:"none",statePatch:{},result:{action:"chat",assistantText:"Rozumiem.",display:{kind:"none",itemIds:[]}}};}
function repairedTools(){return {kind:"tool_request",pendingReplyDisposition:"answer",statePatch:{context:{groundingRequirements:{weatherRequired:true,weatherLocationField:"destination",terrainRequiredFields:[]}}},requests:[{tool:"location",query:"Alpy",targetField:"destination"},{tool:"wardrobe",scope:"full_relevant",category:null,editScope:null}]};}
function finalOutfit(){return {kind:"final",statePatch:{},result:{action:"generate_outfit",assistantText:"Jasné 😊 Do Álp by som išiel v praktických vrstvách z tvojho šatníka.",resultingOutfit:{itemIds:["tee","pants","shoes"],selectionReasonsByItemId:{tee:"vrch",pants:"spodok",shoes:"obuv"},compromises:[],missingWardrobeNeeds:[]},display:{kind:"outfit",itemIds:["tee","pants","shoes"]}}};}
function makeHandler(scripts, inputs=[]){
 const repository=createMemoryStylistSessionRepositoryV2({now:()=>NOW});
 return createStylistChatV2Handler({db:{},admin:{},logger:{warn(){},info(){}},resolveOpenAISecret:async()=>"unused",clock:()=>NOW,sessionRepository:repository,
  brainFactory:()=>({async brainTurn(input){inputs.push(JSON.parse(JSON.stringify(input)));return scripts.shift();}}),
  wardrobeToolFactory:()=>({async retrieve(){return items;},async materialize(ids,reasons={}){return ids.map(id=>({id,selectionReason:reasons[id]||null}));}}),
  locationResolver:{async resolve(){return {providerId:"openmeteo:alps",label:"Alpy, Švajčiarsko",lat:46.8,lng:8.2,source:"fake",granularity:"region"};}},
  weatherTool:{async getForecast({location,date,timeWindow}){return {locationProviderId:location.providerId,dateKey:date.dateKey,timeWindowKey:timeWindow.key,fetchedAt:"2026-09-12T08:00:00.000Z",source:"fake",snapshot:{representativeTempC:12}};}},
  shoppingToolFactory:()=>({async search(){return {candidateIds:[],appliedHardConstraints:[],reply:""};}})});
}
const common={history:[],currentOutfitItemIds:[],currentSelectionReasons:[],shoppingEnabled:false,clientContext:{}};
const auth={auth:{uid:"u"}};
test("real Switzerland -> Alps flow repairs one structural tools-stage error",async()=>{
 const scripts=[firstEnvelope(),badPending(),repairedTools(),finalOutfit()]; const inputs=[]; const handler=makeHandler(scripts,inputs);
 const first=await handler({...common,v2SessionId:"real",turnId:"t1",message:"ahoj za dva dni idem do švajčiarska na turu a neviem co si mam obliect"},auth);
 assert.equal(first.failClosed,false); assert.equal(first.action,"clarify"); assert.match(first.reply,/Kam približne/i);
 const second=await handler({...common,v2SessionId:"real",turnId:"t2",message:"do Alp"},auth);
 assert.notEqual(second.failClosed,true); assert.equal(second.modelPath,"stylist_v2_one_brain"); assert.equal(second.action,"generate_outfit");
 assert.deepEqual(second.resultingOutfitItemIds,["tee","pants","shoes"]); assert.equal(inputs.length,4);
 assert.equal(inputs[2].runtimeConstraints.structuralRepair.code,"REPAIRABLE_STRUCTURAL"); assert.equal(inputs[2].runtimeConstraints.structuralRepair.attempt,1); assert.equal(inputs[3].stage,"answer"); assert.equal(scripts.length,0);
});
test("a second invalid structural output still fail-closes",async()=>{
 const scripts=[firstEnvelope(),badPending(),badPending()]; const handler=makeHandler(scripts);
 const first=await handler({...common,v2SessionId:"bad",turnId:"b1",message:"zajtra idem do švajčiarska na turu potrebujem outfit"},auth); assert.equal(first.action,"clarify");
 const second=await handler({...common,v2SessionId:"bad",turnId:"b2",message:"do Alp"},auth); assert.equal(second.failClosed,true); assert.equal(scripts.length,0);
});
