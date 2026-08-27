"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildChatSystemPrompt,
  buildConversationBrainChatSystemPrompt,
} = require("./chat_prompts");
const {routeStylistRequest} = require("./ai_router");

test("ordinary chat routes through the Conversation Brain V1 registry role", () => {
  const route = routeStylistRequest({
    message: "A tie prvé by sa hodili aj k rifliam?",
    history: [],
    mode: "chat",
    weatherContext: null,
    clientContext: null,
  });
  assert.equal(route.modelId, "gpt-4o");
  assert.equal(route.pipeline, "conversation_brain_v1");
});

test("Brain V1 uses one full conversational prompt even when legacy tier signal differs", () => {
  const canonical = buildConversationBrainChatSystemPrompt();
  assert.equal(buildChatSystemPrompt("fast"), canonical);
  assert.equal(buildChatSystemPrompt("standard"), canonical);
  assert.equal(buildChatSystemPrompt("premium"), canonical);
});

test("Brain V1 prompt owns multi-turn continuity without weakening grounding", () => {
  const prompt = buildChatSystemPrompt("fast");
  assert.match(prompt, /jeden súvislý osobný stylista OOTD/);
  assert.match(prompt, /Krátke follow-upy/);
  assert.match(prompt, /„za aké\?“/);
  assert.match(prompt, /Opravu používateľa prirodzene prijmi/);
  assert.match(prompt, /groundingStatus = needs_grounding/);
  assert.match(prompt, /GPS je systémový fakt/);
  assert.match(prompt, /Plný outfit vyberá appka/);
  assert.match(prompt, /VÝSTUP — VÝHRADNE JSON/);
});
