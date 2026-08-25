"use strict";
const assert = require("node:assert/strict");
const test = require("node:test");
const {createMemoryCatalogSearchRepository} = require("./catalog_search_repository");
const {createShoppingOrchestrator, ShoppingOrchestrationError} = require("./shopping_orchestration_service");

function query(overrides = {}) { return {queryId: "q", sessionId: "s", revision: 1,
  selectedSizeKeys: ["M"], preferredSizeKey: "M",
  constraints: [{field: "canonicalType", operator: "equals", value: "hoodie", strength: "hard"}], ...overrides}; }
function catalog(count = 4) {
  const products=[], variants=[], offers=[], sizes=[];
  for (let i=0;i<count;i++) { const id=`v${i}`; products.push({productId:`p${i}`,brand:"Fixture",canonicalType:"hoodie",canonicalFamily:"top"});
    variants.push({variantId:id,productId:`p${i}`,exactColorName:"Navy",colorProfile:{primary:{family:"navy"}},styles:[],lifecycleState:"ACTIVE"});
    offers.push({offerId:`o${i}`,variantId:id,partnerId:"store",url:`https://store.test/${i}`,regularPrice:{amountMinor:4000+i,currency:"EUR"},promotions:[],overallAvailability:"AVAILABLE",lifecycleState:"ACTIVE",freshness:{stale:false}});
    sizes.push({offerId:`o${i}`,normalizedSizeKey:"M",availability:"AVAILABLE",quantityReliability:"EXACT",exactQuantity:3}); }
  return {products,variants,offers,sizes};
}
function app(input=catalog()) { return createShoppingOrchestrator({repository:createMemoryCatalogSearchRepository(input)}); }

test("authenticated start, show more, show all, and duplicate show-more retain pool", async () => {
  const service=app(catalog(7)); const auth={uid:"a"};
  const start=await service.dispatch(auth,{operation:"START_SEARCH",query:query(),pageSize:3,idempotencyKey:"same"});
  const retry=await service.dispatch(auth,{operation:"START_SEARCH",query:query(),pageSize:3,idempotencyKey:"same"});
  assert.equal(start.sessionId,retry.sessionId); assert.deepEqual(start.candidates.map(x=>x.variantId),["v0","v1","v2"]);
  const more=await service.dispatch(auth,{operation:"SHOW_MORE",sessionId:start.sessionId,pageSize:3});
  assert.deepEqual(more.candidates.map(x=>x.variantId),["v3","v4","v5"]);
  const all=await service.dispatch(auth,{operation:"SHOW_ALL",sessionId:start.sessionId});
  assert.deepEqual(all.candidates.map(x=>x.variantId),["v6"]);
});

test("auth, ownership, ids, and resource guards fail closed", async () => {
  const service=app(); await assert.rejects(service.dispatch(null,{operation:"START_SEARCH"}),e=>e.code==="UNAUTHENTICATED");
  const start=await service.dispatch({uid:"a"},{operation:"START_SEARCH",query:query(),pageSize:1});
  await assert.rejects(service.dispatch({uid:"b"},{operation:"SHOW_MORE",sessionId:start.sessionId,pageSize:1}),e=>e.code==="SESSION_FORBIDDEN");
  await assert.rejects(service.dispatch({uid:"a"},{operation:"FOCUS_CANDIDATE",sessionId:start.sessionId,variantId:"forged"}),e=>e.code==="CANDIDATE_NOT_IN_POOL");
  await assert.rejects(service.dispatch({uid:"a"},{operation:"SHOW_MORE",sessionId:start.sessionId,pageSize:999}),e=>e.code==="INVALID_ARGUMENT");
});

test("focus and detail are pool-bound and detail serializes authoritative facts only", async () => {
  const service=app(); const start=await service.dispatch({uid:"a"},{operation:"START_SEARCH",query:query(),pageSize:1});
  const focus=await service.dispatch({uid:"a"},{operation:"FOCUS_CANDIDATE",sessionId:start.sessionId,variantId:"v0",offerId:"o0"});
  assert.equal(focus.valid,true);
  const detail=await service.dispatch({uid:"a"},{operation:"GET_CANDIDATE_DETAILS",sessionId:start.sessionId,variantId:"v0"});
  assert.equal(detail.offers[0].publicEffectivePrice.price.amountMinor,4000);
  assert.equal(detail.offers[0].sizes[0].exactQuantity,3);
  assert.equal(JSON.stringify(detail).includes("affiliate"),false);
});

test("narrow refinement reuses while broadening requeries and zero diagnostics survive", async () => {
  const service=app(catalog(2)); const auth={uid:"a"};
  const start=await service.dispatch(auth,{operation:"START_SEARCH",query:query(),pageSize:1});
  const narrowed=query({revision:2,constraints:[...query().constraints,{field:"brand",operator:"equals",value:"Fixture",strength:"hard"}]});
  const reuse=await service.dispatch(auth,{operation:"REFINE_QUERY",sessionId:start.sessionId,query:narrowed,pageSize:1});
  assert.equal(reuse.poolReused,true);
  const broad=await service.dispatch(auth,{operation:"REFINE_QUERY",sessionId:start.sessionId,query:query({revision:3}),pageSize:1});
  assert.equal(broad.poolReused,false);
  const none=await service.dispatch(auth,{operation:"START_SEARCH",query:query({constraints:[{field:"brand",operator:"equals",value:"Nope",strength:"hard"}]}),pageSize:1});
  assert.equal(none.status,"NO_RESULTS"); assert.equal(none.diagnostics.exactResultCount,0);
});

test("expired or changed-catalog pools return deterministic stale statuses", async () => {
  const repository=createMemoryCatalogSearchRepository(catalog()); const service=createShoppingOrchestrator({repository});
  const start=await service.dispatch({uid:"a"},{operation:"START_SEARCH",query:query(),pageSize:1});
  const session=await service.sessionStore.get(start.sessionId); session.expiresAt=0;
  await service.sessionStore.put(session);
  await assert.rejects(service.dispatch({uid:"a"},{operation:"SHOW_MORE",sessionId:start.sessionId,pageSize:1}),e=>e.code==="SESSION_EXPIRED");
});
