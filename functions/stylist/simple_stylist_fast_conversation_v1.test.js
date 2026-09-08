"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  FAST_CONVERSATION_MODEL,
  FAST_CONVERSATION_REASONING_EFFORT,
  buildFastConversationInputV1,
  validateFastConversationDecisionV1,
  createFastConversationRouterV1,
} = require("./simple_stylist_fast_conversation_v1");
const {createOpenAiSimpleAgentExecutorV1} = require("./simple_stylist_agent_v1");

const full = {
  route: "full_stylist",
  stylistComment: "",
  quickReplyMode: "none",
  weatherContextKey: "none",
  shoppingHandoff: "none",
  shoppingNeedText: "",
  shoppingNeedLabel: "",
};

test("fast input uses Luna low and contains no wardrobe inventory", () => {
  const input = buildFastConversationInputV1({
    message: "nemám také topánky",
    history: [{role: "assistant", content: "Na mokrý terén potrebuješ turistickú obuv."}],
    currentOutfitItemIds: ["opaque-a", "opaque-b"],
    shoppingEnabled: true,
  });
  assert.equal(input.model, FAST_CONVERSATION_MODEL);
  assert.equal(input.reasoningEffort, FAST_CONVERSATION_REASONING_EFFORT);
  assert.equal(input.maxOutputTokens, 700);
  const payload = JSON.parse(input.messages[1].content);
  assert.deepEqual(payload.wardrobeV2, []);
  assert.equal(payload.hasCurrentOutfit, true);
  assert.ok(!input.messages[1].content.includes("opaque-a"));
});

test("missing gear can produce a model-routed shopping permission handoff", () => {
  const result = validateFastConversationDecisionV1({
    route: "fast_reply",
    stylistComment: "",
    quickReplyMode: "none",
    weatherContextKey: "none",
    shoppingHandoff: "ask_permission",
    shoppingNeedText: "turistické topánky",
    shoppingNeedLabel: "vhodná turistická obuv",
  });
  assert.equal(result.valid, true);
});

test("disabled shopping uses a real yes-no question rather than a fake store claim", () => {
  const result = validateFastConversationDecisionV1({
    route: "fast_reply",
    stylistComment: "Chceš, aby som ti poradil, akú turistickú obuv hľadať?",
    quickReplyMode: "yes_no",
    weatherContextKey: "none",
    shoppingHandoff: "none",
    shoppingNeedText: "",
    shoppingNeedLabel: "",
  });
  assert.equal(result.valid, true);
});

test("full route cannot answer or mutate shopping state", () => {
  assert.equal(validateFastConversationDecisionV1(full).valid, true);
  assert.equal(validateFastConversationDecisionV1({...full,
    stylistComment: "Vybral som outfit."}).valid, false);
  assert.equal(validateFastConversationDecisionV1({...full,
    shoppingHandoff: "ask_permission", shoppingNeedText: "topánky",
    shoppingNeedLabel: "topánky"}).valid, false);
});

test("invalid fast output falls back to full stylist without a second router call", async () => {
  let calls = 0;
  const router = createFastConversationRouterV1({logger: {}, executeModel: async () => {
    calls += 1;
    return {...full, route: "unknown"};
  }});
  const result = await router.resolve({message: "vyber outfit"});
  assert.equal(calls, 1);
  assert.equal(result.route, "full_stylist");
});

test("shared transport honors fast model limits, schema name and usage feature", async () => {
  const bodies = [];
  const events = [];
  const execute = createOpenAiSimpleAgentExecutorV1({
    feature: "stylist_fast_conversation",
    resolveOpenAISecret: () => "test-key",
    recordUsage: async (event) => events.push(event),
    fetchImpl: async (_, init) => {
      bodies.push(JSON.parse(init.body));
      return {ok: true, status: 200, json: async () => ({
        model: FAST_CONVERSATION_MODEL,
        output_text: JSON.stringify(full),
        usage: {input_tokens: 50, output_tokens: 20,
          input_tokens_details: {cached_tokens: 0, cache_write_tokens: 0}},
      })};
    },
  });
  await execute(buildFastConversationInputV1({message: "ahoj"}));
  assert.equal(bodies[0].model, FAST_CONVERSATION_MODEL);
  assert.equal(bodies[0].reasoning.effort, "low");
  assert.equal(bodies[0].max_output_tokens, 700);
  assert.equal(bodies[0].text.format.name, "simple_stylist_fast_conversation_v1");
  assert.equal(events[0].feature, "stylist_fast_conversation");
});

test("callable routes before the full wardrobe query and preserves the Sol fallback", () => {
  const index = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
  const start = index.indexOf("exports.stylistSimpleAgentV1");
  const end = index.indexOf("exports.stylistChat", start);
  const scope = index.slice(start, end);
  const route = scope.indexOf("fastStylistConversationForUserV1");
  const fullWardrobe = scope.indexOf('.collection("wardrobe").limit(200).get()');
  const fullStylist = scope.indexOf("simpleStylistAgentForUserV1(uid, requestId).resolve");
  assert.ok(route >= 0 && fullWardrobe > route && fullStylist > fullWardrobe);
  assert.ok(scope.includes("loadCurrentOutfitDocsForFastPathV1"));
  assert.ok(scope.includes("handleStylistShoppingTurn"));
});

test("mobile sends shopping state through the ordinary simple-agent call", () => {
  const source = fs.readFileSync(path.join(__dirname, "..", "..", "lib",
    "screens", "stylist_chat_screen.dart"), "utf8");
  const start = source.indexOf("Future<void> _sendMessage() async");
  const end = source.indexOf("Future<void> _showImageSourceSheet()", start);
  const scope = source.slice(start, end);
  assert.ok(scope.includes("shoppingContext: _shoppingState.toApiPayload()"));
  assert.ok(scope.includes("shoppingEnabled: ShoppingUiFeatureFlags.mayExposeCatalog"));
  assert.ok(scope.includes("_handleShoppingResponse(response)"));
});
