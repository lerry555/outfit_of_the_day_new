"use strict";

const {hashValue} = require("../costs/ai_usage_v1");

function cachedText(text) {
  return [{type: "input_text", text, prompt_cache_breakpoint: {mode: "explicit"}}];
}

function safeObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

// Only rearrange the trusted, normalized model input. Inventory stays user
// DATA, not developer instructions. Nothing is summarized or dropped.
//
// Legacy simple-agent callers store the inventory at payload.wardrobeV2.
// Stylist V2 stores it at payload.toolResults.wardrobeItems. Keep both shapes
// supported, but cache the inventory only once so a payload optimization cannot
// turn `undefined` into an iterable runtime crash.
function buildCachedSimpleAgentInputV1(input, cacheScope = "") {
  const payload = JSON.parse(input.messages[1].content);
  const toolResults = safeObject(payload.toolResults);
  const hasLegacyWardrobe = Array.isArray(payload.wardrobeV2);
  const hasV2Wardrobe = Array.isArray(toolResults.wardrobeItems);
  const sourceWardrobe = hasLegacyWardrobe ? payload.wardrobeV2 :
    hasV2Wardrobe ? toolResults.wardrobeItems : [];
  const wardrobe = [...sourceWardrobe]
    .sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

  const turn = {...payload};
  delete turn.wardrobeV2;
  if (payload.toolResults && typeof payload.toolResults === "object" &&
      !Array.isArray(payload.toolResults)) {
    const {wardrobeItems, ...otherToolResults} = payload.toolResults;
    turn.toolResults = otherToolResults;
  }

  // Preserve the path expected by each system prompt. Old simple-agent prompts
  // refer to wardrobeV2; V2 prompts refer to toolResults.wardrobeItems.
  const wardrobePayload = hasLegacyWardrobe ? {wardrobeV2: wardrobe} :
    {toolResults: {wardrobeItems: wardrobe}};
  const wardrobeText = JSON.stringify(wardrobePayload);
  const system = input.messages[0].content;
  return {
    input: [
      {role: "developer", content: cachedText(system)},
      {role: "user", content: cachedText(wardrobeText)},
      {role: "user", content: JSON.stringify(turn)},
    ],
    prompt_cache_options: {mode: "explicit", ttl: "30m"},
    // No UID/wardrobe text is exposed in the routing key. Actual prefix bytes,
    // not item counts or this key, determine cache validity at the provider.
    prompt_cache_key: `ootd-simple-v1:${hashValue(cacheScope || wardrobeText).slice(0, 40)}`,
  };
}

module.exports = {buildCachedSimpleAgentInputV1};
