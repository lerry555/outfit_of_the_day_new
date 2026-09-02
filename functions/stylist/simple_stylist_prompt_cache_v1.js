"use strict";

const {hashValue} = require("../costs/ai_usage_v1");

function cachedText(text) {
  return [{type: "input_text", text, prompt_cache_breakpoint: {mode: "explicit"}}];
}

// Only rearrange the trusted, normalized model input. Inventory stays user
// DATA, not developer instructions. Nothing is summarized or dropped.
function buildCachedSimpleAgentInputV1(input, cacheScope = "") {
  const payload = JSON.parse(input.messages[1].content);
  const {wardrobeV2, ...turn} = payload;
  const wardrobe = [...wardrobeV2].sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  const wardrobeText = JSON.stringify({wardrobeV2: wardrobe});
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
