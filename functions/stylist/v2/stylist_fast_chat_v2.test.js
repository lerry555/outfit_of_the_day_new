"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  FAST_CHAT_MODEL,
  FAST_CHAT_REASONING,
  createStylistFastChatV2,
  isFastChatEligibleV2,
} = require("./stylist_fast_chat_v2");

function emptyState() {
  return {
    currentOutfit: {itemIds: []},
    conversationMemory: {pendingQuestion: null, pendingAction: null},
  };
}

test("generic fashion knowledge uses the fast chat route", () => {
  assert.equal(isFastChatEligibleV2({message: "Aké farby sa hodia k modrej?", state: emptyState()}), true);
  assert.equal(isFastChatEligibleV2({message: "Môžem kombinovať čiernu s hnedou?", state: emptyState()}), true);
});

test("personal outfit, live context and pending turns never use fast chat", () => {
  assert.equal(isFastChatEligibleV2({message: "Zajtra mi vyber outfit do Tatier", state: emptyState()}), false);
  assert.equal(isFastChatEligibleV2({message: "Aké topánky si mám dať na túru?", state: emptyState()}), false);
  assert.equal(isFastChatEligibleV2({message: "Aké farby sa hodia k modrej?", state: {...emptyState(), currentOutfit: {itemIds: ["shirt"]}}}), false);
  assert.equal(isFastChatEligibleV2({message: "Aké farby sa hodia k modrej?", state: {...emptyState(), conversationMemory: {pendingQuestion: {field: "destination"}, pendingAction: null}}}), false);
  assert.equal(isFastChatEligibleV2({message: "Aké farby sa hodia k modrej?", state: emptyState(), shoppingActive: true}), false);
});

test("fast chat performs one compact Luna low structured call", async () => {
  let callCount = 0;
  let captured;
  const port = createStylistFastChatV2({
    executeStructured: async (input, meta) => {
      callCount += 1;
      captured = {input, meta};
      return {reply: "K modrej veľmi dobre funguje biela, sivá aj béžová. Ak chceš výraznejší kontrast, skús oranžový detail."};
    },
  });
  const result = await port.turn({
    message: "Aké farby sa hodia k modrej?",
    history: [{role: "user", content: "Mám rád jednoduché kombinácie."}],
  });

  assert.equal(callCount, 1);
  assert.equal(captured.input.model, FAST_CHAT_MODEL);
  assert.equal(captured.input.model, "gpt-5.6-luna");
  assert.equal(captured.input.reasoningEffort, FAST_CHAT_REASONING);
  assert.equal(captured.input.reasoningEffort, "low");
  assert.ok(captured.input.maxOutputTokens <= 420);
  assert.equal(captured.input.schemaName, "stylist_v2_fast_chat");
  assert.equal(captured.meta.modelAttempt, 1);
  assert.ok(captured.input.messages[0].content.length < 900);
  const payload = JSON.parse(captured.input.messages[1].content);
  assert.equal(payload.message, "Aké farby sa hodia k modrej?");
  assert.equal(payload.recentHistory.length, 1);
  assert.match(result.reply, /modrej/i);
});
