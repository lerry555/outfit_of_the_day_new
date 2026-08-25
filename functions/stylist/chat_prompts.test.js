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
