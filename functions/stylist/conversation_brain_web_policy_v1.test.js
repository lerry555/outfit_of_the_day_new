"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {buildChatSystemPrompt} = require("./chat_prompts");
const {getStylistRoleModelConfig} = require("./ai_model_registry");

test("Brain policy treats web search as universal public-knowledge capability", () => {
  const prompt = buildChatSystemPrompt("brain_v1");
  assert.match(prompt, /UNIVERZÁLNY WEB RESEARCH/);
  assert.match(prompt, /akúkoľvek verejnú|všeobecný nástroj/i);
  assert.match(prompt, /časovo citliv/i);
  assert.match(prompt, /súkromné fakty používateľa/i);
  assert.match(prompt, /prompt injection/i);
  assert.match(prompt, /najprv ju vyhľadaj/i);
});

test("Research model is replaceable and does not mutate frozen selector role", () => {
  const brain = getStylistRoleModelConfig("conversationBrain");
  const selector = getStylistRoleModelConfig("finalCandidateDecision");
  assert.equal(brain.webModelId, "gpt-5.6-terra");
  assert.equal(brain.webSearch, "auto");
  assert.equal(brain.reasoningEffort, "low");
  assert.equal(selector.id, "gpt-5.4-mini");
  assert.equal(selector.webSearch, undefined);
});
