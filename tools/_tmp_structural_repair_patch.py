from pathlib import Path

engine = Path('functions/stylist/v2/stylist_one_brain_engine_v2.js')
text = engine.read_text(encoding='utf-8')
old = '''      const toolEnvelope = await callBrainV2(stylistBrain,\n        brainInputV2(request, workingState, "tools", emptyToolResults, runtimeConstraints));\n      runtimeConstraints.modelCallsRemaining -= 1;\n      validateToolDecisionEnvelopeV2(toolEnvelope, {...runtimeConstraints, pendingQuestion: pendingQuestionAtBrain});\n    const pendingDisposition = pendingReplyDispositionV2(toolEnvelope, pendingQuestionAtBrain);\n'''
new = '''      let toolEnvelope = await callBrainV2(stylistBrain,\n        brainInputV2(request, workingState, "tools", emptyToolResults, runtimeConstraints));\n      runtimeConstraints.modelCallsRemaining -= 1;\n      try {\n        validateToolDecisionEnvelopeV2(toolEnvelope, {...runtimeConstraints, pendingQuestion: pendingQuestionAtBrain});\n      } catch (error) {\n        if (!(error instanceof RepairableStructuralTurnError) ||\n            Number(error.maxFutureCorrectionAttempts || 0) < 1) throw error;\n        const repairConstraints = {\n          ...runtimeConstraints,\n          structuralRepair: {\n            attempt: 1,\n            code: error.code,\n            message: String(error.message || "repairable structural contract error").slice(0, 300),\n          },\n        };\n        toolEnvelope = await callBrainV2(stylistBrain,\n          brainInputV2(request, workingState, "tools", emptyToolResults, repairConstraints));\n        runtimeConstraints.modelCallsRemaining -= 1;\n        validateToolDecisionEnvelopeV2(toolEnvelope, {...repairConstraints, pendingQuestion: pendingQuestionAtBrain});\n      }\n    const pendingDisposition = pendingReplyDispositionV2(toolEnvelope, pendingQuestionAtBrain);\n'''
if old not in text:
    raise SystemExit('engine anchor not found')
engine.write_text(text.replace(old, new, 1), encoding='utf-8')

port = Path('functions/stylist/v2/openai_one_brain_model_port_v2.js')
text = port.read_text(encoding='utf-8')
anchor = '    "Ak runtimeConstraints.pendingReplyRequired=true, ďalšia správa NIE JE automaticky odpoveď na pendingQuestion. Rozlíš answer / skip / meta / unrelated a zapíš to do pendingReplyDisposition.",\n'
addition = anchor + '    "Ak runtimeConstraints.structuralRepair existuje, predchádzajúci TOOL-DECISION výstup porušil uvedený štrukturálny kontrakt. Oprav presne túto chybu, zachovaj zámer používateľa a session fakty a neotváraj novú otázku navyše.",\n'
if anchor not in text:
    raise SystemExit('prompt anchor not found')
port.write_text(text.replace(anchor, addition, 1), encoding='utf-8')

test = Path('functions/stylist/v2/stylist_structural_repair_followup_v2.test.js')
test.write_text(r'''"use strict";
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
 const first=await handler({...common,v2SessionId:"real",turnId:"t1",message:"ahoj za dva dni idem do svajciarska na turu a neviem co si mam obliect"},auth);
 assert.equal(first.failClosed,false); assert.equal(first.action,"clarify"); assert.equal(first.clarification.field,"destination");
 const second=await handler({...common,v2SessionId:"real",turnId:"t2",message:"do Alp"},auth);
 assert.notEqual(second.failClosed,true); assert.equal(second.modelPath,"stylist_v2_one_brain"); assert.equal(second.action,"generate_outfit");
 assert.deepEqual(second.resultingOutfitItemIds,["tee","pants","shoes"]); assert.equal(inputs.length,4);
 assert.equal(inputs[2].runtimeConstraints.structuralRepair.code,"REPAIRABLE_STRUCTURAL"); assert.equal(inputs[2].runtimeConstraints.structuralRepair.attempt,1); assert.equal(inputs[3].stage,"answer"); assert.equal(scripts.length,0);
});
test("a second invalid structural output still fail-closes",async()=>{
 const scripts=[firstEnvelope(),badPending(),badPending()]; const handler=makeHandler(scripts);
 const first=await handler({...common,v2SessionId:"bad",turnId:"b1",message:"zajtra idem do svajciarska na turu potrebujem outfit"},auth); assert.equal(first.action,"clarify");
 const second=await handler({...common,v2SessionId:"bad",turnId:"b2",message:"do Alp"},auth); assert.equal(second.failClosed,true); assert.equal(scripts.length,0);
});
''', encoding='utf-8')
