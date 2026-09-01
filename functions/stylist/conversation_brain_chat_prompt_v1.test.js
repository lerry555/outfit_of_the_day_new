"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildChatSystemPrompt,
  buildConversationBrainChatSystemPrompt,
} = require("./chat_prompts");
const {routeStylistRequest} = require("./ai_router");

test("opted-in ordinary chat routes through the Conversation Brain V1 registry role", () => {
  const route = routeStylistRequest({
    message: "A tie prvé by sa hodili aj k rifliam?",
    history: [],
    mode: "chat",
    weatherContext: null,
    clientContext: {conversationBrainVersion: "brain_v1"},
  });
  assert.equal(route.modelId, "gpt-5.6-terra");
  assert.equal(route.pipeline, "conversation_brain_v1");
  assert.equal(route.brainVersion, "brain_v1");
  assert.equal(route.tier, "brain_v1");
  assert.equal(route.webSearchEnabled, true);
  assert.equal(route.reasoningEffort, "low");
});

test("older client without opt-in keeps the settled context clarification route and legacy prompt tier", () => {
  const route = routeStylistRequest({
    message: "Čo si mám obliecť?",
    history: [],
    mode: "chat",
    weatherContext: null,
    clientContext: null,
  });
  assert.equal(route.modelId, "gpt-4o");
  assert.equal(route.pipeline, "context_clarification");
  assert.equal(route.brainVersion, null);
  assert.notEqual(route.tier, "brain_v1");
  assert.doesNotMatch(buildChatSystemPrompt(route.tier), /jeden súvislý osobný stylista OOTD/);
});

test("Brain V1 synthetic prompt tier always resolves to the one full Brain prompt", () => {
  const canonical = buildConversationBrainChatSystemPrompt();
  assert.equal(buildChatSystemPrompt("brain_v1"), canonical);
  assert.notEqual(buildChatSystemPrompt("fast"), canonical);
  assert.notEqual(buildChatSystemPrompt("premium"), canonical);
});

test("Brain V1 prompt owns continuity and can repair parser misses only from explicit user evidence", () => {
  const prompt = buildChatSystemPrompt("brain_v1");
  assert.match(prompt, /jeden súvislý osobný stylista OOTD/);
  assert.match(prompt, /Krátke follow-upy/);
  assert.match(prompt, /„za aké\?“/);
  assert.match(prompt, /Opravu používateľa prirodzene prijmi/);
  assert.match(prompt, /semanticGrounding/);
  assert.match(prompt, /user_explicit/);
  assert.match(prompt, /doslovný úsek userovej správy/i);
  assert.match(prompt, /"výlet", "cesta", "niekam", "von"/);
  assert.match(prompt, /GPS je systémový fakt/);
  assert.match(prompt, /Plný outfit vyberá appka/);
  assert.match(prompt, /OUTFIT EDIT PLAN/);
  assert.match(prompt, /outfit_edit_plan_v1/);
  assert.match(prompt, /všetky zmeny jedného user turnu/i);
  assert.match(prompt, /constraints\.color=red/);
  assert.match(prompt, /intent=none a NESMIE meniť outfit/);
  assert.match(prompt, /VÝSTUP — VÝHRADNE JSON/);
});
