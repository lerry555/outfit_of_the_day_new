from pathlib import Path


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)

bridge_path = Path("functions/stylist/v2/stylist_production_bridge_v2.js")
bridge = bridge_path.read_text(encoding="utf-8")
bridge = replace_once(
    bridge,
    'const {createOpenAiStylistModelPortV2} = require("./openai_stylist_model_port_v2");\n',
    'const {createOpenAiStylistModelPortV2} = require("./openai_stylist_model_port_v2");\nconst {createStylistFastChatV2, isFastChatEligibleV2} = require("./stylist_fast_chat_v2");\n',
    "fast-chat import",
)
bridge = replace_once(
    bridge,
    '  modelFactory = null, wardrobeToolFactory = null, shoppingToolFactory = null} = {}) {',
    '  modelFactory = null, fastChatFactory = null, wardrobeToolFactory = null, shoppingToolFactory = null} = {}) {',
    "handler signature",
)
bridge = replace_once(
    bridge,
    '    if (!sessionId || !turnId || !message) return failClosedResponse("Tomu úplne nerozumiem 😄 Skús mi napísať, čo riešiš s outfitom.");\n\n    try {',
    '    if (!sessionId || !turnId || !message) return failClosedResponse("Tomu úplne nerozumiem 😄 Skús mi napísať, čo riešiš s outfitom.");\n    const turnStartedAt = Date.now();\n\n    try {',
    "turn timer",
)

anchor = '''      const wardrobeTool = wardrobeToolFactory ? wardrobeToolFactory({uid}) : createFirestoreWardrobeToolV2({db, uid});
      const locationResolver = locationOverride || createOpenMeteoLocationResolverV2({fetchImpl});
      const weatherTool = weatherOverride || createOpenMeteoWeatherToolV2({fetchImpl, clock});
      const shoppingTool = shoppingToolFactory ? shoppingToolFactory({uid}) : createShoppingToolV2({uid, orchestrator: catalogOrchestrator});
      const stylistModel = modelFactory ? modelFactory({uid, turnId}) : createOpenAiStylistModelPortV2({
        userStylePreferences: safeMap(data?.userStylePreferences),
        executeStructured: createOpenAiSimpleAgentExecutorV1({
          fetchImpl, resolveOpenAISecret, logger, feature: "stylist_v2", cacheScope: `${uid}:stylist-v2`,
          recordUsage: (event) => recordUsage({...event, userKey: hashValue(uid), requestKey: hashValue([uid, turnId, "v2"])}),
        }),
      });
'''
replacement = '''      const executeStructured = modelFactory ? null : createOpenAiSimpleAgentExecutorV1({
        fetchImpl, resolveOpenAISecret, logger, feature: "stylist_v2", cacheScope: `${uid}:stylist-v2`,
        recordUsage: (event) => recordUsage({...event, userKey: hashValue(uid), requestKey: hashValue([uid, turnId, "v2"])}),
      });
      const fastChat = fastChatFactory ? fastChatFactory({uid, turnId}) :
        (executeStructured ? createStylistFastChatV2({executeStructured}) : null);
      if (fastChat && isFastChatEligibleV2({
        message,
        state: existing?.state || null,
        currentOutfitItemIds: uniqueIds(data?.currentOutfitItemIds, 12),
        shoppingActive,
      })) {
        const fastStartedAt = Date.now();
        const fastResult = await fastChat.turn({message, history: data?.history});
        const response = {
          ok: true, simpleAgent: true, v2: true, failClosed: false, contractVersion: 2,
          modelPath: "stylist_v2_fast_chat", sessionId, sessionRevision: existing?.state?.revision ?? 0,
          reply: fastResult.reply, stylistComment: fastResult.reply,
          resultingOutfitItemIds: [], displayItemIds: [], resultingOutfitItems: [], displayItems: [],
          outfitChanged: false, quickReplyMode: "none", quickReplyPrompt: null, action: "chat",
        };
        logger?.info?.("STYLIST_V2_TURN_LATENCY", {
          path: "fast_chat",
          totalMs: Date.now() - turnStartedAt,
          modelPathMs: Date.now() - fastStartedAt,
        });
        await writeJobResult({db, admin, uid, notifyJobId, result: response});
        await sendPushBestEffort({db, admin, uid, notifyJobId, chatId: clean(data?.chatId, 160), result: response});
        return response;
      }

      const wardrobeTool = wardrobeToolFactory ? wardrobeToolFactory({uid}) : createFirestoreWardrobeToolV2({db, uid});
      const locationResolver = locationOverride || createOpenMeteoLocationResolverV2({fetchImpl});
      const weatherTool = weatherOverride || createOpenMeteoWeatherToolV2({fetchImpl, clock});
      const shoppingTool = shoppingToolFactory ? shoppingToolFactory({uid}) : createShoppingToolV2({uid, orchestrator: catalogOrchestrator});
      const stylistModel = modelFactory ? modelFactory({uid, turnId}) : createOpenAiStylistModelPortV2({
        userStylePreferences: safeMap(data?.userStylePreferences),
        executeStructured,
      });
'''
bridge = replace_once(bridge, anchor, replacement, "executor + fast route")
bridge = replace_once(
    bridge,
    '''      const result = await engine.resolveTurn({
        uid,
        request,
        bootstrapInput: existing ? null : {
          currentOutfitItemIds: currentIds,
          persistedSelectionReasonsByItemId: persistedReasonsByItemId,
          knownExplicitDurableChoices: {},
        },
      });
      const response = await legacyCompatibleResponse({result, sessionId, wardrobeTool});
''',
    '''      const engineStartedAt = Date.now();
      const result = await engine.resolveTurn({
        uid,
        request,
        bootstrapInput: existing ? null : {
          currentOutfitItemIds: currentIds,
          persistedSelectionReasonsByItemId: persistedReasonsByItemId,
          knownExplicitDurableChoices: {},
        },
      });
      const engineMs = Date.now() - engineStartedAt;
      const materializeStartedAt = Date.now();
      const response = await legacyCompatibleResponse({result, sessionId, wardrobeTool});
      logger?.info?.("STYLIST_V2_TURN_LATENCY", {
        path: "agent",
        totalMs: Date.now() - turnStartedAt,
        engineMs,
        materializeMs: Date.now() - materializeStartedAt,
        action: result.action,
      });
''',
    "agent telemetry",
)
bridge = replace_once(
    bridge,
    '      logger?.warn?.("STYLIST_V2_FAIL_CLOSED", {code: clean(error?.code || error?.message, 120)});',
    '      logger?.warn?.("STYLIST_V2_FAIL_CLOSED", {code: clean(error?.code || error?.message, 120), totalMs: Date.now() - turnStartedAt});',
    "fail telemetry",
)
bridge_path.write_text(bridge, encoding="utf-8")

model_path = Path("functions/stylist/v2/openai_stylist_model_port_v2.js")
model = model_path.read_text(encoding="utf-8")
model = replace_once(model, 'const FINAL_REASONING = "medium";', 'const FINAL_REASONING = "low";', "ordinary final reasoning")
model = replace_once(model, '          maxOutputTokens: phase === "plan" ? 1200 : 1800,', '          maxOutputTokens: phase === "plan" ? 1200 : 1400,', "final token ceiling")
model_path.write_text(model, encoding="utf-8")

test_path = Path("functions/stylist/v2/stylist_model_payload_efficiency_v2.test.js")
test_text = test_path.read_text(encoding="utf-8")
test_text = replace_once(test_text, '  assert.equal(call.reasoningEffort, "medium");', '  assert.equal(call.reasoningEffort, "low");', "reasoning expectation")
test_path.write_text(test_text, encoding="utf-8")

print("stylist latency patch applied")
