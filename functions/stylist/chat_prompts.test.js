"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildChatSystemPrompt,
  SET_CONTEXT_RULES,
} = require("./chat_prompts");

test("fast and premium prompts include set as a preference signal", () => {
  const fast = buildChatSystemPrompt("fast");
  const premium = buildChatSystemPrompt("premium");
  for (const prompt of [fast, premium, SET_CONTEXT_RULES]) {
    assert.match(prompt, /setId/);
    assert.match(prompt, /relationshipSource/);
    assert.match(prompt, /user_curated/);
    assert.match(prompt, /manufacturer_matching/);
    assert.match(prompt, /nie je povinné spolunosenie|nie je povinné/);
  }
});

test("fast and premium prompts include saved style preference precedence", () => {
  const fast = buildChatSystemPrompt("fast");
  const premium = buildChatSystemPrompt("premium");
  for (const prompt of [fast, premium]) {
    assert.match(prompt, /userStylePreferences/);
    assert.match(prompt, /aktuálna správa používateľa/);
    assert.match(prompt, /avoidedColors/);
  }
});

test("premium prompt keeps event facts grounded before outfit generation", () => {
  const prompt = buildChatSystemPrompt("premium");
  assert.match(prompt, /unresolvedMaterialFields/);
  assert.match(prompt, /semanticGrounding/);
  assert.match(prompt, /user_explicit/);
  assert.match(prompt, /GPS je systémový fakt/);
  assert.match(prompt, /Predošlé texty asistenta sú NEAUTORITATÍVNE/);
  assert.match(prompt, /„výlet“/);
  assert.match(prompt, /outfitTempC/);
});
