from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'expected block not found in {path}: {old[:140]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


# Backend wardrobe DTO: preserve derivative lineage; never turn a raw original
# into a fake product/cutout/clean image.
replace_once(
    'functions/stylist/v2/firestore_wardrobe_tool_v2.js',
    '''    accessoryGroup: text(item.accessoryGroup, 80).toLowerCase() || null,
    productImageUrl: text(item.productImageUrl, 2000),
    cutoutImageUrl: text(item.cutoutImageUrl, 2000),
    cleanImageUrl: text(item.cleanImageUrl, 2000),
    // Preserve both the current UI URL and the original source so materialized
    // chat cards can recover when a derivative object/token is broken.
    imageUrl: text(item.imageUrl || item.originalImageUrl, 2000),
    originalImageUrl: text(item.originalImageUrl, 2000),
    safety: {''',
    '''    accessoryGroup: text(item.accessoryGroup, 80).toLowerCase() || null,
    productImageUrl: text(item.productImageUrl, 2000),
    cutoutImageUrl: text(item.cutoutImageUrl, 2000),
    cleanImageUrl: text(item.cleanImageUrl, 2000),
    imageUrl: text(item.imageUrl || item.originalImageUrl, 2000),
    originalImageUrl: text(item.originalImageUrl, 2000),
    storagePath: text(item.storagePath, 1000),
    cleanStoragePath: text(item.cleanStoragePath, 1000),
    productStoragePath: text(item.productStoragePath, 1000),
    processing: {
      product: text(safeMap(item.processing).product || item["processing.product"], 40),
    },
    safety: {''',
)
replace_once(
    'functions/stylist/v2/firestore_wardrobe_tool_v2.js',
    '''function materializeStylistCardItemV2(item, reason = "") {
  // Chat cards currently do not retry after a network-image HTTP failure. The
  // original upload is the safest display fallback because it is independent
  // of later clean/cutout processing. Use imageUrl only when no original exists.
  const stableCardUrl = text(item?.originalImageUrl || item?.imageUrl, 2000);
  return {
    ...item,
    ...(stableCardUrl ? {
      cutoutImageUrl: stableCardUrl,
      cleanImageUrl: stableCardUrl,
      imageUrl: stableCardUrl,
    } : {}),
    ...(typeof reason === "string" && reason.trim() ?
      {stylistSelectionReason: reason.trim()} : {}),
  };
}''',
    '''function materializeStylistCardItemV2(item, reason = "") {
  // Recommendation cards preserve product/cutout/clean lineage. The Flutter
  // client can refresh stale Firebase URLs from storage paths; it must never
  // disguise a raw/person original as a product image.
  return {
    ...item,
    ...(typeof reason === "string" && reason.trim() ?
      {stylistSelectionReason: reason.trim()} : {}),
  };
}''',
)

replace_once(
    'functions/stylist/v2/stylist_wardrobe_cache_v2.test.js',
    '''test("stylist card materialization prefers original image over a broken derivative", () => {
  const item = {
    id: "pants",
    cutoutImageUrl: "https://storage.example/cutout-broken.png",
    cleanImageUrl: "https://storage.example/clean-broken.png",
    imageUrl: "https://storage.example/derived-broken.png",
    originalImageUrl: "https://storage.example/original-good.jpg",
  };

  const card = materializeStylistCardItemV2(item, "praktický spodný diel");
  assert.equal(card.cutoutImageUrl, item.originalImageUrl);
  assert.equal(card.cleanImageUrl, item.originalImageUrl);
  assert.equal(card.imageUrl, item.originalImageUrl);
  assert.equal(card.stylistSelectionReason, "praktický spodný diel");
});''',
    '''test("stylist card materialization preserves derivatives and never impersonates them with the raw original", () => {
  const item = {
    id: "pants",
    productImageUrl: "https://storage.example/product.png",
    cutoutImageUrl: "https://storage.example/cutout.png",
    cleanImageUrl: "https://storage.example/clean.png",
    imageUrl: "https://storage.example/original-person.jpg",
    originalImageUrl: "https://storage.example/original-person.jpg",
    storagePath: "wardrobe/user/pants.jpg",
    cleanStoragePath: "wardrobe_clean/user/pants.png",
    productStoragePath: "wardrobe_product/user/pants.png",
    processing: {product: "done"},
  };

  const card = materializeStylistCardItemV2(item, "praktický spodný diel");
  assert.equal(card.productImageUrl, item.productImageUrl);
  assert.equal(card.cutoutImageUrl, item.cutoutImageUrl);
  assert.equal(card.cleanImageUrl, item.cleanImageUrl);
  assert.equal(card.imageUrl, item.imageUrl);
  assert.equal(card.storagePath, item.storagePath);
  assert.equal(card.cleanStoragePath, item.cleanStoragePath);
  assert.equal(card.productStoragePath, item.productStoragePath);
  assert.equal(card.processing.product, "done");
  assert.equal(card.stylistSelectionReason, "praktický spodný diel");
});''',
)

# Fast ordinary model, stronger automatic escalation, compact model-only wardrobe.
replace_once(
    'functions/stylist/v2/openai_stylist_model_port_v2.js',
    '''const PLAN_MODEL = "gpt-5.6-luna";
const PLAN_REASONING = "low";
const FINAL_MODEL = "gpt-5.6-terra";
const FINAL_REASONING = "low";
const FINAL_REASONING_ESCALATED = "medium";''',
    '''const PLAN_MODEL = "gpt-5.6-luna";
const PLAN_REASONING = "low";
// Ordinary styling is latency-sensitive. Safety/formal turns automatically
// escalate to Terra medium.
const FINAL_MODEL = "gpt-5.6-luna";
const FINAL_REASONING = "medium";
const FINAL_ESCALATED_MODEL = "gpt-5.6-terra";
const FINAL_REASONING_ESCALATED = "medium";''',
)
replace_once(
    'functions/stylist/v2/openai_stylist_model_port_v2.js',
    '''function finalReasoningForInputV2(input) {
  const terrain = input?.session?.context?.terrain || {};
  const condition = clean(terrain.condition, 40).toLowerCase();
  const difficulty = clean(terrain.difficulty, 40).toLowerCase();
  const surface = clean(terrain.surface, 40).toLowerCase();
  const latest = normalizeIntentTextV2(input?.request?.latestUserInput);
  const safetySensitive = ["wet", "muddy", "snow", "ice"].includes(condition) ||
    ["steep", "technical"].includes(difficulty) || surface === "rock";
  const formalSensitive = /\\b(svadba|wedding|pohovor|interview|ples|pohreb|funeral|ceremonia)\\b/.test(latest);
  return safetySensitive || formalSensitive ? FINAL_REASONING_ESCALATED : FINAL_REASONING;
}''',
    '''function finalModelRoutingForInputV2(input) {
  const terrain = input?.session?.context?.terrain || {};
  const condition = clean(terrain.condition, 40).toLowerCase();
  const difficulty = clean(terrain.difficulty, 40).toLowerCase();
  const surface = clean(terrain.surface, 40).toLowerCase();
  const latest = normalizeIntentTextV2(input?.request?.latestUserInput);
  const safetySensitive = ["wet", "muddy", "snow", "ice"].includes(condition) ||
    ["steep", "technical"].includes(difficulty) || surface === "rock";
  const formalSensitive = /\\b(svadba|wedding|pohovor|interview|ples|pohreb|funeral|ceremonia)\\b/.test(latest);
  if (safetySensitive || formalSensitive) {
    return {model: FINAL_ESCALATED_MODEL, reasoningEffort: FINAL_REASONING_ESCALATED};
  }
  return {model: FINAL_MODEL, reasoningEffort: FINAL_REASONING};
}

function finalReasoningForInputV2(input) {
  return finalModelRoutingForInputV2(input).reasoningEffort;
}

function compactWardrobeItemForModelV2(raw) {
  const item = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const {
    productImageUrl, cutoutImageUrl, cleanImageUrl, imageUrl, originalImageUrl,
    storagePath, cleanStoragePath, productStoragePath, processing,
    ...semantic
  } = item;
  return semantic;
}

function compactWardrobeForModelV2(items) {
  return (Array.isArray(items) ? items : []).map(compactWardrobeItemForModelV2);
}

function shoppingQuickReplyPromptV2(needLabel, canonicalNeed) {
  const normalized = normalizeIntentTextV2(`${needLabel || ""} ${canonicalNeed || ""}`);
  if (/\\b(hiking|trekking|turist)/.test(normalized)) {
    return "Chceš, aby som ti vybral vhodnejšie turistické topánky?";
  }
  if (/\\b(shoe|shoes|boot|boots|sneaker|footwear|topank|obuv)/.test(normalized)) {
    return "Chceš, aby som ti vybral vhodnejšie topánky?";
  }
  return "Chceš, aby som ti vybral vhodnejší kúsok do šatníka?";
}''',
)
replace_once(
    'functions/stylist/v2/openai_stylist_model_port_v2.js',
    '''    statePatch.pendingAction = {type: "action", kind: "shopping", actionId};
    result.quickReplies = [
      {actionId: `${actionId}_yes`, label: "Áno"},
      {actionId: `${actionId}_no`, label: "Nie"},
    ];''',
    '''    statePatch.pendingAction = {type: "action", kind: "shopping", actionId};
    result.quickReplyPrompt = shoppingQuickReplyPromptV2(needLabel, canonicalNeed);
    result.quickReplies = [
      {actionId: `${actionId}_yes`, label: "Áno"},
      {actionId: `${actionId}_no`, label: "Nie"},
    ];''',
)
replace_once(
    'functions/stylist/v2/openai_stylist_model_port_v2.js',
    '''      const phase = input?.phase === "final" ? "final" : "plan";
      const wardrobeV2 = Array.isArray(input?.toolResults?.wardrobeItems) ? input.toolResults.wardrobeItems : [];
      const payload = {
        wardrobeV2,
        request: input.request,
        session: input.session,
        preflightResolution: input.preflightResolution,
        toolResults: input.toolResults,
        userStylePreferences,
      };
      const reasoningEffort = phase === "plan" ? PLAN_REASONING : finalReasoningForInputV2(input);
      const model = phase === "plan" ? PLAN_MODEL : FINAL_MODEL;''',
    '''      const phase = input?.phase === "final" ? "final" : "plan";
      const wardrobeV2 = Array.isArray(input?.toolResults?.wardrobeItems) ? input.toolResults.wardrobeItems : [];
      const modelWardrobe = compactWardrobeForModelV2(wardrobeV2);
      const payload = {
        request: input.request,
        session: input.session,
        preflightResolution: input.preflightResolution,
        toolResults: {
          ...(input.toolResults || {}),
          wardrobeItems: modelWardrobe,
        },
        userStylePreferences,
      };
      const finalRouting = finalModelRoutingForInputV2(input);
      const reasoningEffort = phase === "plan" ? PLAN_REASONING : finalRouting.reasoningEffort;
      const model = phase === "plan" ? PLAN_MODEL : finalRouting.model;''',
)
replace_once('functions/stylist/v2/openai_stylist_model_port_v2.js',
             '''  FINAL_MODEL,\n  FINAL_REASONING,''',
             '''  FINAL_ESCALATED_MODEL,\n  FINAL_MODEL,\n  FINAL_REASONING,''')
replace_once('functions/stylist/v2/openai_stylist_model_port_v2.js',
             '''  enforceHighConfidenceGrounding,\n  finalEnvelope,\n  finalReasoningForInputV2,''',
             '''  compactWardrobeForModelV2,\n  enforceHighConfidenceGrounding,\n  finalEnvelope,\n  finalModelRoutingForInputV2,\n  finalReasoningForInputV2,''')
replace_once('functions/stylist/v2/openai_stylist_model_port_v2.js',
             '''  shouldPreloadCurrentOutfitV2,\n  stripTrailingShoppingQuestionV2,''',
             '''  shoppingQuickReplyPromptV2,\n  shouldPreloadCurrentOutfitV2,\n  stripTrailingShoppingQuestionV2,''')

replace_once(
    'functions/stylist/v2/stylist_production_bridge_v2.js',
    '''        quickReplyMode: yesNo ? "yes_no" : "none",
        resultingOutfitItems: resultingItems,''',
    '''        quickReplyMode: yesNo ? "yes_no" : "none",
        quickReplyPrompt: yesNo ? clean(result.quickReplyPrompt, 240) || null : null,
        resultingOutfitItems: resultingItems,''',
)

replace_once(
    'functions/stylist/v2/stylist_help_first_contract_v2.test.js',
    '''  FINAL_MODEL,
  FINAL_REASONING,
  FINAL_REASONING_ESCALATED,
  finalReasoningForInputV2,''',
    '''  FINAL_ESCALATED_MODEL,
  FINAL_MODEL,
  FINAL_REASONING,
  FINAL_REASONING_ESCALATED,
  finalModelRoutingForInputV2,
  finalReasoningForInputV2,''',
)
replace_once(
    'functions/stylist/v2/stylist_help_first_contract_v2.test.js',
    '''test("golden: model routing uses cheap planner and low-reasoning Terra for ordinary final styling", () => {
  assert.equal(PLAN_MODEL, "gpt-5.6-luna");
  assert.equal(PLAN_REASONING, "low");
  assert.equal(FINAL_MODEL, "gpt-5.6-terra");
  assert.equal(FINAL_REASONING, "low");
  assert.equal(FINAL_REASONING_ESCALATED, "medium");
});

test("golden: safety-sensitive terrain escalates final reasoning to medium", () => {
  const session = clone(createEmptySessionStateV2("reasoning"));
  session.context.terrain = {surface: "rock", difficulty: "technical", condition: "wet"};
  const input = {request: {latestUserInput: "vyber mi outfit"}, session};
  assert.equal(finalReasoningForInputV2(input), "medium");

  session.context.terrain = {surface: null, difficulty: null, condition: null};
  assert.equal(finalReasoningForInputV2(input), "low");
});''',
    '''test("golden: model routing uses Luna medium for ordinary styling and keeps a cheap planner", () => {
  assert.equal(PLAN_MODEL, "gpt-5.6-luna");
  assert.equal(PLAN_REASONING, "low");
  assert.equal(FINAL_MODEL, "gpt-5.6-luna");
  assert.equal(FINAL_REASONING, "medium");
  assert.equal(FINAL_ESCALATED_MODEL, "gpt-5.6-terra");
  assert.equal(FINAL_REASONING_ESCALATED, "medium");
});

test("golden: safety-sensitive terrain escalates the final model to Terra medium", () => {
  const session = clone(createEmptySessionStateV2("reasoning"));
  session.context.terrain = {surface: "rock", difficulty: "technical", condition: "wet"};
  const input = {request: {latestUserInput: "vyber mi outfit"}, session};
  assert.deepEqual(finalModelRoutingForInputV2(input), {model: "gpt-5.6-terra", reasoningEffort: "medium"});
  assert.equal(finalReasoningForInputV2(input), "medium");

  session.context.terrain = {surface: null, difficulty: null, condition: null};
  assert.deepEqual(finalModelRoutingForInputV2(input), {model: "gpt-5.6-luna", reasoningEffort: "medium"});
  assert.equal(finalReasoningForInputV2(input), "medium");
});''',
)

Path('functions/stylist/v2/stylist_model_payload_efficiency_v2.test.js').write_text(r'''"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  createOpenAiStylistModelPortV2,
  finalEnvelope,
  shoppingQuickReplyPromptV2,
} = require("./openai_stylist_model_port_v2");

function baseInput() {
  return {
    phase: "final",
    request: {turnId: "turn-1", latestUserInput: "vyber mi outfit"},
    session: {context: {terrain: {surface: null, difficulty: null, condition: null}}, currentOutfit: {itemIds: [], selectionReasonsByItemId: {}}},
    preflightResolution: {},
    toolResults: {
      wardrobeItems: [{
        id: "shirt", name: "Tričko", canonicalType: "t_shirt", canonicalFamily: "tops",
        bodySlots: ["upper_body"], layerPosition: "base", warmth: 1, formality: 1,
        productImageUrl: "https://img.example/product.png", cutoutImageUrl: "https://img.example/cutout.png",
        cleanImageUrl: "https://img.example/clean.png", imageUrl: "https://img.example/person.jpg",
        originalImageUrl: "https://img.example/person.jpg", storagePath: "wardrobe/u/shirt.jpg",
        cleanStoragePath: "wardrobe_clean/u/shirt.png", productStoragePath: "wardrobe_product/u/shirt.png",
        processing: {product: "done"},
      }],
      weatherSnapshot: {summary: "mild"},
    },
  };
}

test("final model payload sends semantic wardrobe once and strips image transport fields", async () => {
  let call;
  const port = createOpenAiStylistModelPortV2({
    executeStructured: async (input) => {
      call = input;
      return {
        action: "chat", assistantText: "Jasné.", resultingOutfitItemIds: [], selectionReasons: [],
        displayKind: "none", displayItemIds: [], editReplaceItemIds: [], editRetainItemIds: [],
        editAllowedSlots: [], editAllowedCategories: [], editAllowRemovalOnly: false,
        clarificationField: null, clarificationQuestion: null, offerShopping: false,
        shoppingNeedLabel: null, shoppingNeedCanonicalType: null,
        shoppingHardConstraints: [], shoppingSoftPreferences: [],
      };
    },
  });
  await port.turn(baseInput());
  assert.equal(call.model, "gpt-5.6-luna");
  assert.equal(call.reasoningEffort, "medium");
  const payload = JSON.parse(call.messages[1].content);
  assert.equal(Object.hasOwn(payload, "wardrobeV2"), false);
  assert.equal(payload.toolResults.wardrobeItems.length, 1);
  const item = payload.toolResults.wardrobeItems[0];
  assert.equal(item.id, "shirt");
  for (const key of ["productImageUrl", "cutoutImageUrl", "cleanImageUrl", "imageUrl", "originalImageUrl", "storagePath", "cleanStoragePath", "productStoragePath", "processing"]) {
    assert.equal(Object.hasOwn(item, key), false, key);
  }
  assert.deepEqual(payload.toolResults.weatherSnapshot, {summary: "mild"});
});

test("shopping CTA is footwear-specific instead of anonymous yes/no buttons", () => {
  assert.equal(shoppingQuickReplyPromptV2("turistická obuv", "hiking_shoes"),
    "Chceš, aby som ti vybral vhodnejšie turistické topánky?");
  const envelope = finalEnvelope({
    action: "generate_outfit", assistantText: "Tenisky sú tu len kompromis. Chceš, aby som ti niečo vybral?",
    resultingOutfitItemIds: ["shirt"], selectionReasons: [{itemId: "shirt", reason: "ľahký vrch"}],
    displayKind: "outfit", displayItemIds: ["shirt"], editReplaceItemIds: [], editRetainItemIds: [],
    editAllowedSlots: [], editAllowedCategories: [], editAllowRemovalOnly: false,
    clarificationField: null, clarificationQuestion: null, offerShopping: true,
    shoppingNeedLabel: "turistická obuv", shoppingNeedCanonicalType: "hiking_shoes",
    shoppingHardConstraints: [], shoppingSoftPreferences: [],
  }, baseInput());
  assert.equal(envelope.result.quickReplyPrompt,
    "Chceš, aby som ti vybral vhodnejšie turistické topánky?");
  assert.doesNotMatch(envelope.result.assistantText, /Chceš/i);
});
''', encoding='utf-8')

# Flutter DTO keeps the CTA text.
replace_once('lib/Services/stylist_simple_agent_service_v1.dart',
             '''    required this.quickReplyMode,\n    required this.resultingOutfitItems,''',
             '''    required this.quickReplyMode,\n    required this.quickReplyPrompt,\n    required this.resultingOutfitItems,''')
replace_once('lib/Services/stylist_simple_agent_service_v1.dart',
             '''  final String quickReplyMode;\n  final List<Map<String, dynamic>> resultingOutfitItems;''',
             '''  final String quickReplyMode;\n  final String? quickReplyPrompt;\n  final List<Map<String, dynamic>> resultingOutfitItems;''')
replace_once('lib/Services/stylist_simple_agent_service_v1.dart',
             '''        quickReplyMode: 'none', resultingOutfitItems: const [], displayItems: const []);''',
             '''        quickReplyMode: 'none', quickReplyPrompt: null, resultingOutfitItems: const [], displayItems: const []);''')
replace_once(
    'lib/Services/stylist_simple_agent_service_v1.dart',
    '''    return StylistSimpleAgentResultV1(ok: true, failClosed: false, stylistComment: comment,
      resultingOutfitItemIds: List<String>.unmodifiable(resultIds), displayItemIds: List<String>.unmodifiable(displayIds),
      outfitChanged: data['outfitChanged'] as bool, quickReplyMode: data['quickReplyMode'] == 'yes_no' ? 'yes_no' : 'none',
      resultingOutfitItems:''',
    '''    final quickReplyPromptRaw = (data['quickReplyPrompt'] ?? '').toString().trim();
    return StylistSimpleAgentResultV1(ok: true, failClosed: false, stylistComment: comment,
      resultingOutfitItemIds: List<String>.unmodifiable(resultIds), displayItemIds: List<String>.unmodifiable(displayIds),
      outfitChanged: data['outfitChanged'] as bool, quickReplyMode: data['quickReplyMode'] == 'yes_no' ? 'yes_no' : 'none',
      quickReplyPrompt: quickReplyPromptRaw.isEmpty ? null : quickReplyPromptRaw,
      resultingOutfitItems:''',
)
replace_once('lib/Services/stylist_simple_agent_service_v1.dart',
             '''    'quickReplyMode': quickReplyMode, 'resultingOutfitItems': resultingOutfitItems, 'displayItems': displayItems,''',
             '''    'quickReplyMode': quickReplyMode, if (quickReplyPrompt != null) 'quickReplyPrompt': quickReplyPrompt,\n    'resultingOutfitItems': resultingOutfitItems, 'displayItems': displayItems,''')

# V2 server owns weather grounding. Remove the redundant Martin today+tomorrow
# network fetch that happened before every callable and was ignored server-side.
replace_once(
    'lib/screens/stylist_chat_screen.dart',
    '''      _setSendingProgress(StylistChatProgressPhase.checkingWeather);
      final weatherContext = await _simpleAgentWeatherContext();
      final clientContext = _simpleAgentClientContext();''',
    '''      // V2 resolves authoritative weather server-side from destination/eventLocation.
      // Fetching Martin today+tomorrow here was pure latency and was ignored by
      // the production bridge. Keep the legacy argument empty for compatibility.
      const weatherContext = <String, dynamic>{};
      final clientContext = _simpleAgentClientContext();''',
)
replace_once('lib/screens/stylist_chat_screen.dart',
             '''import '../widgets/stylist_quick_reply_buttons.dart';''',
             '''import '../widgets/stylist_quick_reply_buttons.dart';\nimport '../widgets/stylist_suggested_item_card.dart';''')
replace_once('lib/screens/stylist_chat_screen.dart',
             '''  final String quickReplyMode;\n\n  const StylistChatMessage({''',
             '''  final String quickReplyMode;\n  final String? quickReplyPrompt;\n\n  const StylistChatMessage({''')
replace_once('lib/screens/stylist_chat_screen.dart',
             '''    this.quickReplyMode = 'none',\n  });''',
             '''    this.quickReplyMode = 'none',\n    this.quickReplyPrompt,\n  });''')
replace_once('lib/screens/stylist_chat_screen.dart',
             '''      quickReplyMode: quickReplyMode,\n    );''',
             '''      quickReplyMode: quickReplyMode,\n      quickReplyPrompt: quickReplyPrompt,\n    );''')
replace_once('lib/screens/stylist_chat_screen.dart',
             '''      if (quickReplyMode == 'yes_no') 'quickReplyMode': quickReplyMode,\n    };''',
             '''      if (quickReplyMode == 'yes_no') 'quickReplyMode': quickReplyMode,\n      if (quickReplyPrompt != null && quickReplyPrompt!.trim().isNotEmpty)\n        'quickReplyPrompt': quickReplyPrompt,\n    };''')
replace_once('lib/screens/stylist_chat_screen.dart',
             '''      quickReplyMode: map['quickReplyMode'] == 'yes_no' ? 'yes_no' : 'none',\n    );''',
             '''      quickReplyMode: map['quickReplyMode'] == 'yes_no' ? 'yes_no' : 'none',\n      quickReplyPrompt: (map['quickReplyPrompt'] ?? '').toString().trim().isEmpty\n          ? null\n          : (map['quickReplyPrompt'] ?? '').toString().trim(),\n    );''')
replace_once(
    'lib/screens/stylist_chat_screen.dart',
    '''          quickReplyMode: response['quickReplyMode'] == 'yes_no'
              ? 'yes_no'
              : 'none',
        ),''',
    '''          quickReplyMode: response['quickReplyMode'] == 'yes_no'
              ? 'yes_no'
              : 'none',
          quickReplyPrompt: (response['quickReplyPrompt'] ?? '').toString().trim().isEmpty
              ? null
              : (response['quickReplyPrompt'] ?? '').toString().trim(),
        ),''',
)
replace_once('lib/screens/stylist_chat_screen.dart',
             '''                    StylistQuickReplyButtons(onSelected: onQuickReply!),''',
             '''                    StylistQuickReplyButtons(\n                      prompt: message.quickReplyPrompt,\n                      onSelected: onQuickReply!,\n                    ),''')

old_card = '''class _SuggestedItemCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _SuggestedItemCard({required this.item});

  String? _resolveImageUrl(Map<String, dynamic> item) {
    final cutout = (item['cutoutImageUrl'] ?? '').toString().trim();
    if (cutout.startsWith('http')) return cutout;
    final clean = (item['cleanImageUrl'] ?? '').toString().trim();
    if (clean.startsWith('http')) return clean;
    return getBestWardrobeImageUrlOrNull(item);
  }

  @override
  Widget build(BuildContext context) {
    const textPrimary = Color(0xFFF1F0EC);
    const textSecondary = Color(0xFFAAA59B);
    final label = (item['name'] ?? item['label'] ?? item['category'] ?? 'Kúsok')
        .toString();
    final imageUrl = _resolveImageUrl(item);

    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 78,
            width: double.infinity,
            child: imageUrl == null
                ? const Icon(Icons.checkroom, color: textSecondary, size: 22)
                : Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: textSecondary,
                      size: 20,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}'''
new_card = '''class _SuggestedItemCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _SuggestedItemCard({required this.item});

  @override
  Widget build(BuildContext context) => StylistSuggestedItemCard(item: item);
}'''
replace_once('lib/screens/stylist_chat_screen.dart', old_card, new_card)

replace_once('lib/widgets/stylist_quick_reply_buttons.dart',
             '''class StylistQuickReplyButtons extends StatelessWidget {\n  const StylistQuickReplyButtons({super.key, required this.onSelected});\n\n  final ValueChanged<String> onSelected;''',
             '''class StylistQuickReplyButtons extends StatelessWidget {\n  const StylistQuickReplyButtons({super.key, this.prompt, required this.onSelected});\n\n  final String? prompt;\n  final ValueChanged<String> onSelected;''')
replace_once(
    'lib/widgets/stylist_quick_reply_buttons.dart',
    '''        const Text(
          'Chceš, aby som ti pomohol vybrať vhodnejší kúsok do šatníka?',
          key: ValueKey('stylist-quick-reply-prompt'),
          style: TextStyle(
            color: secondaryText,
            fontSize: 13,
            height: 1.35,
          ),
        ),''',
    '''        Text(
          (prompt ?? '').trim().isNotEmpty
              ? prompt!.trim()
              : 'Chceš, aby som ti vybral vhodnejší kúsok do šatníka?',
          key: const ValueKey('stylist-quick-reply-prompt'),
          style: const TextStyle(
            color: secondaryText,
            fontSize: 13,
            height: 1.35,
          ),
        ),''',
)

Path('lib/utils/stylist_card_image_priority.dart').write_text(r'''import '../Services/clothing_analyzer_pipeline.dart';
import '../Services/product_link_v2_display_policy.dart';
import 'wardrobe_image_url_priority.dart';

class StylistCardImageCandidate {
  const StylistCardImageCandidate({required this.url, required this.kind, this.storagePath});
  final String url;
  final String kind;
  final String? storagePath;
}

bool _http(String value) => value.startsWith('http://') || value.startsWith('https://');

String? _pathFor(Map<String, dynamic> item, String key, String url) {
  final explicit = (item[key] ?? '').toString().trim();
  if (explicit.isNotEmpty) return explicit;
  return ClothingAnalyzerPipeline.storagePathFromFirebaseUrl(url);
}

/// Stylist cards are product-like recommendation surfaces. Raw imageUrl and
/// originalImageUrl are intentionally excluded because they can contain the
/// person who uploaded the garment.
List<StylistCardImageCandidate> stylistCardImageCandidates(Map<String, dynamic> item) {
  final out = <StylistCardImageCandidate>[];
  final seen = <String>{};
  final storagePath = (item['storagePath'] ?? '').toString().trim();
  final ownedV2 = isOwnedV2CanonicalStoragePath(storagePath);

  void add(String key, String kind, String storageKey, {bool product = false}) {
    final url = (item[key] ?? '').toString().trim();
    if (!_http(url) || seen.contains(url)) return;
    if (product && !canUseProductImageUrl(item)) return;
    if (!product && ownedV2 && !isOwnedV2SameSourceDisplayUrl(item: item, url: url)) return;
    seen.add(url);
    out.add(StylistCardImageCandidate(
      url: url,
      kind: kind,
      storagePath: _pathFor(item, storageKey, url),
    ));
  }

  add('productImageUrl', 'product', 'productStoragePath', product: true);
  add('cutoutImageUrl', 'cutout', 'cleanStoragePath');
  add('cleanImageUrl', 'clean', 'cleanStoragePath');
  return List<StylistCardImageCandidate>.unmodifiable(out);
}
''', encoding='utf-8')

Path('lib/widgets/stylist_suggested_item_card.dart').write_text(r'''import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../utils/stylist_card_image_priority.dart';

class StylistSuggestedItemCard extends StatefulWidget {
  const StylistSuggestedItemCard({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  State<StylistSuggestedItemCard> createState() => _StylistSuggestedItemCardState();
}

class _StylistSuggestedItemCardState extends State<StylistSuggestedItemCard> {
  late Future<List<String>> _urlsFuture;
  int _index = 0;
  final Set<int> _failed = <int>{};

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant StylistSuggestedItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.item['id'] ?? '').toString() != (widget.item['id'] ?? '').toString() ||
        oldWidget.item['productImageUrl'] != widget.item['productImageUrl'] ||
        oldWidget.item['cleanImageUrl'] != widget.item['cleanImageUrl'] ||
        oldWidget.item['cutoutImageUrl'] != widget.item['cutoutImageUrl']) {
      _reset();
    }
  }

  void _reset() {
    _index = 0;
    _failed.clear();
    _urlsFuture = _resolveFreshUrls();
  }

  Future<List<String>> _resolveFreshUrls() async {
    final candidates = stylistCardImageCandidates(widget.item);
    final urls = <String>[];
    for (final candidate in candidates) {
      var url = candidate.url;
      final path = candidate.storagePath?.trim() ?? '';
      if (path.isNotEmpty) {
        try {
          url = await FirebaseStorage.instance.ref(path).getDownloadURL()
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          continue;
        }
      }
      if ((url.startsWith('http://') || url.startsWith('https://')) && !urls.contains(url)) {
        urls.add(url);
      }
    }
    return List<String>.unmodifiable(urls);
  }

  void _advanceAfterFailure(int failedIndex, int length) {
    if (_failed.contains(failedIndex)) return;
    _failed.add(failedIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _index != failedIndex) return;
      if (failedIndex + 1 < length) setState(() => _index = failedIndex + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    const textPrimary = Color(0xFFF1F0EC);
    const textSecondary = Color(0xFFAAA59B);
    final label = (widget.item['name'] ?? widget.item['label'] ?? widget.item['category'] ?? 'Kúsok').toString();
    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 78,
            width: double.infinity,
            child: FutureBuilder<List<String>>(
              future: _urlsFuture,
              builder: (context, snapshot) {
                final urls = snapshot.data ?? const <String>[];
                if (urls.isEmpty || _index >= urls.length) {
                  return const Icon(Icons.checkroom, color: textSecondary, size: 24);
                }
                final currentIndex = _index;
                final url = urls[currentIndex];
                return Image.network(
                  url,
                  key: ValueKey('${widget.item['id'] ?? label}:$url'),
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) {
                    _advanceAfterFailure(currentIndex, urls.length);
                    return const Icon(Icons.checkroom, color: textSecondary, size: 24);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: const TextStyle(color: textPrimary, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.2)),
        ],
      ),
    );
  }
}
''', encoding='utf-8')

Path('test/stylist_card_image_priority_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/utils/stylist_card_image_priority.dart';

void main() {
  test('Stylist card keeps only product-like candidates and excludes raw original', () {
    final item = <String, dynamic>{
      'productImageUrl': 'https://example.test/product.png',
      'cutoutImageUrl': 'https://example.test/cutout.png',
      'cleanImageUrl': 'https://example.test/clean.png',
      'imageUrl': 'https://example.test/person.jpg',
      'originalImageUrl': 'https://example.test/person.jpg',
      'processing': <String, dynamic>{'product': 'done'},
    };
    final candidates = stylistCardImageCandidates(item);
    expect(candidates.map((e) => e.kind), ['product', 'cutout', 'clean']);
    expect(candidates.map((e) => e.url), isNot(contains(item['imageUrl'])));
    expect(candidates.map((e) => e.url), isNot(contains(item['originalImageUrl'])));
  });

  test('Stylist card has no raw-person fallback when derivatives are absent', () {
    final candidates = stylistCardImageCandidates(<String, dynamic>{
      'imageUrl': 'https://example.test/person.jpg',
      'originalImageUrl': 'https://example.test/person.jpg',
    });
    expect(candidates, isEmpty);
  });
}
''', encoding='utf-8')

Path('test/stylist_quick_reply_contract_test.dart').write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_simple_agent_service_v1.dart';
import 'package:outfitofTheDay/widgets/stylist_quick_reply_buttons.dart';

void main() {
  test('server shopping prompt survives callable DTO normalization', () {
    final result = StylistSimpleAgentResultV1.fromCallableData(<String, dynamic>{
      'simpleAgent': true,
      'failClosed': false,
      'stylistComment': 'Tenisky sú kompromis.',
      'resultingOutfitItemIds': <String>[], 'displayItemIds': <String>[],
      'resultingOutfitItems': <Map<String, dynamic>>[], 'displayItems': <Map<String, dynamic>>[],
      'outfitChanged': false, 'quickReplyMode': 'yes_no',
      'quickReplyPrompt': 'Chceš, aby som ti vybral vhodnejšie turistické topánky?',
    });
    expect(result.quickReplyPrompt, 'Chceš, aby som ti vybral vhodnejšie turistické topánky?');
    expect(result.toUiResponse()['quickReplyPrompt'], result.quickReplyPrompt);
  });

  testWidgets('shopping prompt is rendered with Ano/Nie controls', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StylistQuickReplyButtons(
      prompt: 'Chceš, aby som ti vybral vhodnejšie turistické topánky?', onSelected: (_) {},
    ))));
    expect(find.text('Chceš, aby som ti vybral vhodnejšie turistické topánky?'), findsOneWidget);
    expect(find.text('Áno'), findsOneWidget);
    expect(find.text('Nie'), findsOneWidget);
  });
}
''', encoding='utf-8')

# CI owns the new seams.
replace_once('.github/workflows/stylist-v2-ci.yml',
             '''      - 'lib/Services/stylist_simple_agent_service_v1.dart'\n      - 'test/stylist_simple_agent_fast_path_test.dart'\n      - 'firestore.rules' ''',
             '''      - 'lib/Services/stylist_simple_agent_service_v1.dart'\n      - 'lib/screens/stylist_chat_screen.dart'\n      - 'lib/widgets/stylist_quick_reply_buttons.dart'\n      - 'lib/widgets/stylist_suggested_item_card.dart'\n      - 'lib/utils/stylist_card_image_priority.dart'\n      - 'test/stylist_simple_agent_fast_path_test.dart'\n      - 'test/stylist_quick_reply_contract_test.dart'\n      - 'test/stylist_card_image_priority_test.dart'\n      - 'firestore.rules' ''')
replace_once('.github/workflows/stylist-v2-ci.yml',
             '''          functions/stylist/v2/stylist_location_wardrobe_plan_efficiency_v2.test.js\n      - name: Existing Stylist backend regression''',
             '''          functions/stylist/v2/stylist_location_wardrobe_plan_efficiency_v2.test.js\n          functions/stylist/v2/stylist_model_payload_efficiency_v2.test.js\n      - name: Existing Stylist backend regression''')
replace_once('.github/workflows/stylist-v2-ci.yml',
             '''          lib/Services/stylist_simple_agent_service_v1.dart\n          lib/screens/stylist_chat_screen.dart\n      - name: V2 client fast-path regression''',
             '''          lib/Services/stylist_simple_agent_service_v1.dart\n          lib/screens/stylist_chat_screen.dart\n          lib/widgets/stylist_quick_reply_buttons.dart\n          lib/widgets/stylist_suggested_item_card.dart\n          lib/utils/stylist_card_image_priority.dart\n      - name: V2 client fast-path regression''')
replace_once('.github/workflows/stylist-v2-ci.yml',
             '''      - name: Existing Stylist progress regression\n        run: flutter test test/stylist_chat_progress_test.dart''',
             '''      - name: V2 CTA and product-card image regressions\n        run: >-\n          flutter test\n          test/stylist_quick_reply_contract_test.dart\n          test/stylist_card_image_priority_test.dart\n      - name: Existing Stylist progress regression\n        run: flutter test test/stylist_chat_progress_test.dart''')

# Remove both temporary patch mechanisms from the final branch diff.
Path('.github/workflows/_tmp-patch-v2-card-cta-latency.yml').unlink(missing_ok=True)
Path('tool/patch_v2_card_cta_latency_temp.py').unlink(missing_ok=True)
