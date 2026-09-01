from pathlib import Path
import re

ROOT = Path('.')


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


def write(path, text):
    (ROOT / path).write_text(text, encoding='utf-8')


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly 1 match, got {count}')
    return text.replace(old, new, 1)


def regex_once(text, pattern, repl, label, flags=0):
    out, count = re.subn(pattern, repl, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly 1 regex match, got {count}')
    return out


# ---------------------------------------------------------------------------
# 1) Conversation Brain contract: additive layer is a hard user mutation.
# ---------------------------------------------------------------------------
path = 'functions/stylist/chat_prompts.js'
s = read(path)
s = replace_once(
    s,
    '  `\\"preserveOtherSlots\\":true,\\"extraLayer\\":\\"none\\",\\"presentation\\":\\"normal\\"}}\\n` +',
    '  `\\"preserveOtherSlots\\":true,\\"preserveCurrentOutfit\\":false,` +\n'
    '  `\\"extraLayer\\":\\"none\\",\\"layerFamily\\":\\"none\\",\\"presentation\\":\\"normal\\"}}\\n` +',
    'Brain directive JSON shape',
)
s = replace_once(
    s,
    '  `- family používaj iba ak user rodinu naozaj určil: shorts|jeans|pants|joggers|sneakers|boots|sandals|formal_shoes; inak none.\\n` +\n'
    '  `- extraLayer=optional_upper_layer iba keď user explicitne chce pridať záložnú vrstvu navrch/pre prípad chladu. Nevyvodzuj ju iba z večera alebo mesta.\\n` +\n'
    '  `- Ak user povie „ukáž celý outfit a pridaj niečo navrch“, je to full_outfit + optional_upper_layer + concise_full, nie single-slot swap.\\n` +',
    '  `- family používaj iba ak user rodinu naozaj určil: shorts|jeans|pants|joggers|sneakers|boots|sandals|formal_shoes; inak none.\\n` +\n'
    '  `- Ak user prikáže PRIDAŤ/DÁŤ/PRIhodiť vrstvu do outfitu, extraLayer=required_upper_layer. Je to tvrdá požiadavka používateľa, nie odporúčanie podľa počasia. Nesmieš ju zrušiť vetou typu „nebudeš ju potrebovať“.\\n` +\n'
    '  `- layerFamily používaj pre explicitný druh pridávanej vrstvy: hoodie|sweater|jacket|coat|blazer|cardigan; inak none. Slovenské „mikina“ mapuj na hoodie (zahŕňa mikinu, hoodie aj mikinu na zips).\\n` +\n'
    '  `- Keď currentOutfit existuje a user chce celý EXISTUJÚCI outfit ukázať s pridanou vrstvou, scope=full_outfit, preserveCurrentOutfit=true, extraLayer=required_upper_layer a presentation=concise_full. Základ outfitu sa NESMIE pregenerovať.\\n` +\n'
    '  `- Ak user povie „ukáž celý outfit a pridaj mi do neho aj mikinu“, je to full_outfit + preserveCurrentOutfit=true + required_upper_layer + layerFamily=hoodie + concise_full.\\n` +',
    'Brain additive-layer rules',
)
write(path, s)


# ---------------------------------------------------------------------------
# 2) Server sanitizer must preserve the new fields; old optional token remains
#    accepted only for compatibility with an in-flight older Brain response.
# ---------------------------------------------------------------------------
path = 'functions/index.js'
s = read(path)
pattern = r'function sanitizeStylistOutfitDirective\(raw\) \{.*?\n\}\n\n(?=// An LLM may interpret known context)'
replacement = '''function sanitizeStylistOutfitDirective(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const allowedScopes = new Set(["none", "full_outfit", "single_slot"]);
  const allowedSlots = new Set(["none", "top", "bottom", "shoes", "outerwear"]);
  const allowedFamilies = new Set([
    "none", "shorts", "jeans", "pants", "joggers",
    "sneakers", "boots", "sandals", "formal_shoes",
  ]);
  const allowedExtraLayers = new Set([
    "none", "required_upper_layer", "optional_upper_layer",
  ]);
  const allowedLayerFamilies = new Set([
    "none", "hoodie", "sweater", "jacket", "coat", "blazer", "cardigan",
  ]);
  const allowedPresentations = new Set(["normal", "concise_full", "focused_item"]);
  const pick = (value, allowed, fallback) => {
    const normalized = String(value || "").trim().toLowerCase();
    return allowed.has(normalized) ? normalized : fallback;
  };
  const scope = pick(raw.scope, allowedScopes, "none");
  const slot = scope === "single_slot" ?
    pick(raw.slot, allowedSlots, "none") : "none";
  const family = scope === "single_slot" ?
    pick(raw.family, allowedFamilies, "none") : "none";
  const extraLayer = pick(raw.extraLayer, allowedExtraLayers, "none");
  const layerFamily = extraLayer !== "none" ?
    pick(raw.layerFamily, allowedLayerFamilies, "none") : "none";
  const presentation = pick(
    raw.presentation,
    allowedPresentations,
    scope === "single_slot" ? "focused_item" : "normal",
  );
  return Object.freeze({
    scope,
    slot,
    family,
    preserveOtherSlots: scope === "single_slot" ? raw.preserveOtherSlots !== false : false,
    preserveCurrentOutfit:
      scope === "full_outfit" && raw.preserveCurrentOutfit === true,
    extraLayer,
    layerFamily,
    presentation,
  });
}

'''
s = regex_once(s, pattern, replacement, 'directive sanitizer', flags=re.S)
write(path, s)


# ---------------------------------------------------------------------------
# 3) Explanation voice: follow-ups do not re-teach weather/the whole outfit.
#    Focused one-slot edits need no second expensive language-model call.
# ---------------------------------------------------------------------------
path = 'functions/stylist/conversation_brain_v1.js'
s = read(path)
s = replace_once(
    s,
    '    "- focused_item: odpovedz ako živý stylista na userRequest. Zameraj sa na kúsok vo focusSlot, povedz napr. „Zvolil by som tieto čierne šortky, pretože…“. NIKDY nepíš technické formulácie typu „vymenil som spodok/slot“. Stačí 1–2 prirodzené vety.",\n'
    '    "- concise_full: používateľ už outfit videl alebo si ho práve nechal upraviť. Neopakuj celý dlhý rozbor. Stačí 1–2 vety, ktoré potvrdia podstatnú zmenu/požiadavku; karty pod správou ukážu kúsky.",\n'
    '    "- normal: pri prvom odporúčaní daj stručné 2–4 vety, nie katalógový odsek.",',
    '    "- focused_item: JEDNA krátka prirodzená veta. Povedz iba ktorý kúsok odporúčaš k už existujúcemu outfitu. Neopakuj teplotu, dážď, mesto ani opis ostatných kúskov, pokiaľ sa na ne user výslovne nepýta. NIKDY nepíš technické formulácie typu „vymenil som spodok/slot“.",\n'
    '    "- concise_full: používateľ už outfit videl alebo si ho práve nechal upraviť. Max 1–2 krátke vety. Potvrď iba požadovanú zmenu a neprepisuj znovu počasie ani katalógový opis každého kúsku.",\n'
    '    "- normal: pri prvom odporúčaní max 2–3 stručné vety. Nevysvetľuj osobitne každý kus; povedz len to, čo je pre rozhodnutie užitočné.",',
    'explanation mode budgets',
)
s = replace_once(
    s,
    '    "- Ak userFacingContext.weather obsahuje teplotu, pri odporúčaní ju uveď explicitne aspoň raz (napr. „pri 25 °C“); dážď/vietor spomeň, keď menia voľbu. Nikdy nepoužívaj inú teplotu.",',
    '    "- Počasie nie je povinná fráza. V normal režime ho spomeň najviac raz a iba keď reálne vysvetľuje voľbu. Vo focused_item a concise_full ho NEOPAKUJ, ak sa user nepýta na počasie alebo sa podmienky práve nezmenili. Ak teplotu uvedieš, musí byť presne z userFacingContext.weather.",',
    'weather repetition rule',
)
s = replace_once(
    s,
    '''  if (!model || model.provider !== "openai") {
    throw new Error("conversation_brain_model_unavailable");
  }
  return Object.freeze({
    model: model.id,
    max_tokens: Math.min(Number(model.maxTokens) || 700, 700),
''',
    '''  if (!model || model.provider !== "openai") {
    throw new Error("conversation_brain_model_unavailable");
  }
  const presentationMode = text(canonicalPayload && canonicalPayload.presentationMode, 40);
  const tokenBudget = presentationMode === "focused_item" ? 120 :
    presentationMode === "concise_full" ? 220 : 420;
  return Object.freeze({
    model: model.id,
    max_tokens: Math.min(Number(model.maxTokens) || tokenBudget, tokenBudget),
''',
    'dynamic explanation token budget',
)
write(path, s)


path = 'functions/stylist/frozen_stylist_authority_v1.js'
s = read(path)
start = s.index('function deterministicExplanation(decision, normalized = null) {')
end = s.index('\nfunction isUserFacingExplanationSafe', start)
new_det = '''function deterministicExplanation(decision, normalized = null) {
  if (decision.action === "reject_all") {
    return "Z toho, čo máš, ti teraz nechcem nasilu potvrdiť nevhodnú kombináciu.";
  }
  const selected = normalized && Array.isArray(normalized.frozenCandidates) ?
    normalized.frozenCandidates.find((candidate) =>
      candidate.candidateId === decision.selectedCandidateId) : null;
  if (!selected) return "Vybral som ti najlepšiu dostupnú možnosť z tvojho šatníka.";

  if (normalized.presentationMode === "focused_item") {
    const focused = selected.presentationItems.find((item) =>
      normalized.focusSlot && item.slot === normalized.focusSlot) ||
      selected.presentationItems[0];
    return focused && focused.name ?
      `Zvolil by som ${focused.name} — k zvyšku outfitu mi sedia najlepšie.` :
      "Zvolil by som túto možnosť — k zvyšku outfitu mi sedí najlepšie.";
  }
  if (normalized.presentationMode === "concise_full") {
    return "Jasné — outfit som upravil podľa tvojej požiadavky a zvyšok som zbytočne nemenil.";
  }

  const sentences = [];
  const itemList = listUserFacingItems(selected.presentationItems);
  if (itemList) sentences.push(`Vybral som ${itemList}.`);
  const firstCompromise = selected.compromiseDetails && selected.compromiseDetails[0];
  if (firstCompromise) {
    const itemName = cleanText(firstCompromise.itemName, 120) || "jeden kúsok";
    const ideal = cleanText(firstCompromise.idealReplacementDescription, 180);
    sentences.push(ideal ?
      `${itemName} je kompromis; ideálnejšia náhrada by bola ${ideal}.` :
      `${itemName} je tu najlepší dostupný kompromis.`);
  }
  return sentences.slice(0, 2).join(" ") ||
    "Vybral som ti najlepšiu dostupnú kombináciu z tvojho šatníka.";
}
'''
s = s[:start] + new_det + s[end:]
old = '''      const useBrain = brainRequested(data);
      const explanationClient = useBrain ? brainExplanationClient : legacyExplanationClient;
      const explanationResult = await explanationClient.run(explanationPayload(normalized, decision));
      const explanationValid = explanationResult.ok &&
        isUserFacingExplanationSafe(explanationResult.value.explanation);
      const explanation = explanationValid ? explanationResult.value.explanation :
        deterministicExplanation(decision, normalized);
      return Object.freeze({
'''
new = '''      const useBrain = brainRequested(data);
      const deterministicFocused = useBrain && normalized.presentationMode === "focused_item";
      const explanationClient = useBrain ? brainExplanationClient : legacyExplanationClient;
      const explanationResult = deterministicFocused ? null :
        await explanationClient.run(explanationPayload(normalized, decision));
      const explanationValid = deterministicFocused ||
        (explanationResult.ok && isUserFacingExplanationSafe(explanationResult.value.explanation));
      const explanation = deterministicFocused ? deterministicExplanation(decision, normalized) :
        explanationValid ? explanationResult.value.explanation :
          deterministicExplanation(decision, normalized);
      return Object.freeze({
'''
s = replace_once(s, old, new, 'focused explanation bypass')
s = replace_once(
    s,
    '''        explanationFallback: !explanationValid,
        decisionProviderFailure,
        explanationProviderFailure: explanationValid ? null :
          explanationResult.ok ? "explanation_user_facing_contract_invalid" :
            explanationResult.failureCode || "explanation_provider_failure",
''',
    '''        explanationFallback: !explanationValid,
        decisionProviderFailure,
        explanationProviderFailure: explanationValid ? null :
          explanationResult && explanationResult.ok ? "explanation_user_facing_contract_invalid" :
            explanationResult && explanationResult.failureCode || "explanation_provider_failure",
''',
    'nullable explanation provider result',
)
write(path, s)


# ---------------------------------------------------------------------------
# 4) Cross-chat diversity: read recent full outfit fingerprints from Firestore.
# ---------------------------------------------------------------------------
path = 'lib/Services/stylist_chat_store.dart'
s = read(path)
anchor = '''  Future<void> renameChat(String chatId, String title) async {
'''
method = '''  /// Last full outfit cards across recent threads. Used only as a soft
  /// diversity memory: safety and suitability still outrank novelty.
  Future<List<Set<String>>> loadRecentFullOutfitItemIdSets({
    int limitChats = 5,
  }) async {
    final col = _col;
    if (col == null) return const <Set<String>>[];
    final snap = await col
        .orderBy('updatedAt', descending: true)
        .limit(limitChats.clamp(1, 10))
        .get();
    final out = <Set<String>>[];
    for (final doc in snap.docs) {
      final rawMessages = doc.data()['messages'];
      if (rawMessages is! List) continue;
      for (final raw in rawMessages.reversed) {
        if (raw is! Map || raw['isUser'] == true) continue;
        final suggested = raw['suggestedItems'];
        if (suggested is! List || suggested.length < 3) continue;
        final ids = suggested
            .whereType<Map>()
            .map((item) => (item['id'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        if (ids.length >= 3) {
          out.add(Set<String>.unmodifiable(ids));
          break;
        }
      }
    }
    return List<Set<String>>.unmodifiable(out);
  }

'''
s = replace_once(s, anchor, method + anchor, 'recent outfit history method')
write(path, s)


# ---------------------------------------------------------------------------
# 5) V2 service: preserve frozen base + add one REQUIRED compatible layer;
#    filter exact recent full-outfit repeats when another valid candidate exists.
# ---------------------------------------------------------------------------
path = 'lib/Services/stylist_chat_outfit_service.dart'
s = read(path)
if "import '../domain/wardrobe_v2/wardrobe_v2_resolver.dart';" not in s:
    s = replace_once(
        s,
        "import '../domain/wardrobe_v2/wardrobe_v2_adapters.dart';\n",
        "import '../domain/wardrobe_v2/wardrobe_v2_adapters.dart';\nimport '../domain/wardrobe_v2/wardrobe_v2_resolver.dart';\n",
        'resolved wardrobe import',
    )
s = replace_once(
    s,
    '''    StylistSwapRequest? requestedSwap,
    bool optionalUpperLayerRequested = false,
    String presentationMode = 'normal',
''',
    '''    StylistSwapRequest? requestedSwap,
    bool optionalUpperLayerRequested = false,
    bool preserveCurrentOutfit = false,
    String requiredUpperLayerFamily = '',
    List<Set<String>> recentOutfitItemIdSets = const <Set<String>>[],
    String presentationMode = 'normal',
''',
    'service additive params',
)
# Required family restricts only optional upper-layer candidates, never core tops.
s = replace_once(
    s,
    '''        .where((item) {
          if (requestedBottomFamily == null) return true;
          if (!item.item.bodySlots.contains('lower_body')) return true;
          return _matchesRequestedBottomV2(item.item, requestedBottomFamily);
        })
        .toList(growable: false);
''',
    '''        .where((item) {
          if (requestedBottomFamily == null) return true;
          if (!item.item.bodySlots.contains('lower_body')) return true;
          return _matchesRequestedBottomV2(item.item, requestedBottomFamily);
        })
        .where((item) {
          if (requiredUpperLayerFamily.trim().isEmpty) return true;
          final isOptionalUpperLayer =
              const {'mid', 'outer', 'shell'}.contains(item.item.layerPosition) &&
              item.item.bodySlots.contains('upper_body');
          if (!isOptionalUpperLayer) return true;
          return _matchesRequiredUpperLayerFamily(
            item.item.canonicalType,
            requiredUpperLayerFamily,
          );
        })
        .toList(growable: false);
''',
    'required layer family filtering',
)
# Ensure current matrix actually carries a requested layer when starting from scratch.
s = replace_once(
    s,
    '''    if (matrix.isEmpty) return null;

    onProgress?.call(StylistChatProgressPhase.finalizing);
''',
    '''    if (matrix.isEmpty) return null;
    final matrixWithRequiredLayer = requiredUpperLayerFamily.trim().isEmpty
        ? matrix
        : matrix
              .where(
                (candidate) => candidate.outfit.items.any(
                  (item) =>
                      const {'mid', 'outer', 'shell'}.contains(item.item.layerPosition) &&
                      item.item.bodySlots.contains('upper_body') &&
                      _matchesRequiredUpperLayerFamily(
                        item.item.canonicalType,
                        requiredUpperLayerFamily,
                      ),
                ),
              )
              .toList(growable: false);
    if (requiredUpperLayerFamily.trim().isNotEmpty &&
        matrixWithRequiredLayer.isEmpty &&
        !preserveCurrentOutfit) {
      throw const StylistFrozenDecisionRejectedExceptionV1(
        <String>['required_user_layer_unavailable'],
        explanation:
            'V šatníku som nenašiel vhodnú požadovanú vrstvu, takže ju nechcem potichu vynechať.',
      );
    }

    onProgress?.call(StylistChatProgressPhase.finalizing);
''',
    'required layer matrix guard',
)
# Replace selection branch with additive branch before swap/normal choice.
s = replace_once(
    s,
    '''    if (requestedSwap != null && previousOutfitItemIds.isNotEmpty) {
      final currentDocs = wardrobe.where((raw) {
''',
    '''    if (preserveCurrentOutfit &&
        requiredUpperLayerFamily.trim().isNotEmpty &&
        previousOutfitItemIds.isNotEmpty) {
      final current = _reconstructFrozenCurrentOutfit(
        wardrobe: wardrobe,
        previousOutfitItemIds: previousOutfitItemIds,
        context: context,
      );
      if (current == null) {
        throw const StylistFrozenDecisionRejectedExceptionV1(
          <String>['current_outfit_restore_failed'],
          explanation:
              'Aktuálny outfit sa mi nepodarilo bezpečne obnoviť, preto ti ho nechcem potichu prehádzať.',
        );
      }
      selected = _addRequiredUpperLayerToFrozenCurrent(
        current: current,
        wardrobe: resolved,
        context: context,
        requiredFamily: requiredUpperLayerFamily,
      );
      if (selected == null) {
        throw const StylistFrozenDecisionRejectedExceptionV1(
          <String>['required_user_layer_unavailable'],
          explanation:
              'K tomuto outfitu som v šatníku nenašiel vhodnú požadovanú vrstvu. Zvyšok outfitu som preto nezmenil.',
        );
      }
      final lockedCandidate = V2FlexibleCandidate(
        candidateId: 'locked_additive_layer',
        outfit: selected,
        score: 0,
        scoreBreakdown: const <String, double>{},
      );
      final lockedExplanation =
          await const StylistFrozenCandidateDecisionServiceV1().resolve(
        candidates: <V2FlexibleCandidate>[lockedCandidate],
        resolvedContext: frozenResolvedContext,
        lockedSelection: true,
        presentationMode: 'concise_full',
        userRequest: userRequest,
      );
      if (!lockedExplanation.selected) {
        throw StylistFrozenDecisionRejectedExceptionV1(
          lockedExplanation.reasonCodes,
          explanation: lockedExplanation.explanation,
        );
      }
      finalExplanation = lockedExplanation.explanation.trim().isEmpty
          ? null
          : lockedExplanation.explanation.trim();
    } else if (requestedSwap != null && previousOutfitItemIds.isNotEmpty) {
      final currentDocs = wardrobe.where((raw) {
''',
    'additive layer selection branch',
)
# Normal decision pool softly suppresses exact recent full-outfit repeats.
s = replace_once(
    s,
    '''    } else {
      final decision = await const StylistFrozenCandidateDecisionServiceV1()
          .resolve(
            candidates: matrix,
''',
    '''    } else {
      final decisionPool = _preferNovelFullOutfitCandidates(
        requiredUpperLayerFamily.trim().isEmpty ? matrix : matrixWithRequiredLayer,
        recentOutfitItemIdSets,
      );
      final decision = await const StylistFrozenCandidateDecisionServiceV1()
          .resolve(
            candidates: decisionPool,
''',
    'novel decision pool',
)
s = replace_once(
    s,
    '''      final accepted = matrix
          .where((candidate) => candidate.candidateId == selectedId)
''',
    '''      final accepted = decisionPool
          .where((candidate) => candidate.candidateId == selectedId)
''',
    'accepted from decision pool',
)
# Insert helpers before existing bottom matcher.
anchor = '''  static bool _matchesRequestedBottomV2(
'''
helpers = r'''  static List<V2FlexibleCandidate> _preferNovelFullOutfitCandidates(
    List<V2FlexibleCandidate> candidates,
    List<Set<String>> recentSets,
  ) {
    if (candidates.length <= 1 || recentSets.isEmpty) return candidates;
    bool repeated(V2FlexibleCandidate candidate) {
      final ids = candidate.outfit.items.map((item) => item.itemId).toSet();
      return recentSets.any(
        (recent) => recent.length == ids.length && recent.containsAll(ids),
      );
    }
    final novel = candidates.where((candidate) => !repeated(candidate)).toList();
    return novel.isEmpty ? candidates : List<V2FlexibleCandidate>.unmodifiable(novel);
  }

  static bool _matchesRequiredUpperLayerFamily(
    String canonicalType,
    String family,
  ) {
    final type = canonicalType.trim().toLowerCase();
    return switch (family.trim().toLowerCase()) {
      'hoodie' => const {'hoodie', 'zip_hoodie', 'sweatshirt'}.contains(type),
      'sweater' => type.contains('sweater') || type.contains('pullover'),
      'cardigan' => type.contains('cardigan'),
      'blazer' => type.contains('blazer') || type.contains('suit_jacket'),
      'coat' => type.contains('coat') || type.contains('trench'),
      'jacket' =>
        type.contains('jacket') || type.contains('parka') || type.contains('windbreaker'),
      _ => true,
    };
  }

  static V2FlexibleOutfitResult? _reconstructFrozenCurrentOutfit({
    required List<Map<String, dynamic>> wardrobe,
    required Set<String> previousOutfitItemIds,
    required V2CandidateMatrixContext context,
  }) {
    final resolved = NativeWardrobeV2Runtime.resolveAll(wardrobe)
        .where((item) => previousOutfitItemIds.contains(item.itemId))
        .toList(growable: false);
    if (resolved.length != previousOutfitItemIds.length) return null;
    final hasOnePiece = resolved.any((item) => item.item.bodySlots.contains('full_body'));
    final compositionItems = <OutfitCompositionItemV2>[];
    for (final value in resolved) {
      final item = value.item;
      final String group;
      final CompositionRoleV2 role;
      final bool required;
      if (item.bodySlots.contains('feet')) {
        group = 'footwear'; role = CompositionRoleV2.core; required = true;
      } else if (item.bodySlots.contains('full_body')) {
        group = 'full_body_core'; role = CompositionRoleV2.core; required = true;
      } else if (item.bodySlots.contains('lower_body') &&
          !item.bodySlots.contains('upper_body')) {
        group = 'lower_body_core'; role = CompositionRoleV2.core; required = true;
      } else if (const {'mid', 'outer', 'shell'}.contains(item.layerPosition)) {
        group = 'layer_${item.layerPosition}';
        role = CompositionRoleV2.conditional; required = false;
      } else if (item.bodySlots.contains('upper_body')) {
        group = 'upper_body_core'; role = CompositionRoleV2.core; required = true;
      } else {
        group = item.accessoryGroup ?? 'finishing';
        role = CompositionRoleV2.finishing; required = false;
      }
      compositionItems.add(
        OutfitCompositionItemV2(
          itemId: value.itemId,
          item: item,
          role: role,
          compositionGroup: group,
          required: required,
          selectionReason: 'restore_frozen_current',
        ),
      );
    }
    final composition = OutfitCompositionV2(
      template: hasOnePiece ? OutfitTemplateV2.onePiece : OutfitTemplateV2.separates,
      items: compositionItems,
    );
    if (composition.compatibilityErrors().isNotEmpty) return null;
    final result = V2FlexibleOutfitResult.fromComposition(
      composition,
      weatherProtectionRequired: context.weatherProtectionRequired,
      minimumFormality: context.minimumFormality,
      requiredFunctions: context.requiredFunctions,
      displayByItemId: {for (final value in resolved) value.itemId: value.raw},
    );
    return result.validate().isEmpty ? result : null;
  }

  static V2FlexibleOutfitResult? _addRequiredUpperLayerToFrozenCurrent({
    required V2FlexibleOutfitResult current,
    required Iterable<ResolvedWardrobeItemV2> wardrobe,
    required V2CandidateMatrixContext context,
    required String requiredFamily,
  }) {
    final currentIds = current.items.map((item) => item.itemId).toSet();
    V2FlexibleOutfitResult? best;
    var bestScore = double.negativeInfinity;
    for (final candidate in wardrobe) {
      if (currentIds.contains(candidate.itemId)) continue;
      final item = candidate.item;
      if (!item.bodySlots.contains('upper_body') ||
          !const {'mid', 'outer', 'shell'}.contains(item.layerPosition) ||
          !_matchesRequiredUpperLayerFamily(item.canonicalType, requiredFamily)) {
        continue;
      }
      if (OutfitSuitabilityPolicyV2.isPhysicallyUnsuitable(
        item,
        tempC: OutfitSuitabilityPolicyV2.effectiveTempC(
          tempC: context.tempC,
          feelsLikeC: context.feelsLikeC,
        ),
        seasonKey: context.seasonKey,
        isRainy: context.isRainy || context.weatherProtectionRequired,
        activityType: context.activityType,
      )) {
        continue;
      }
      final composition = OutfitCompositionV2(
        template: current.template,
        items: <OutfitCompositionItemV2>[
          ...current.toComposition().items,
          OutfitCompositionItemV2(
            itemId: candidate.itemId,
            item: item,
            role: CompositionRoleV2.conditional,
            compositionGroup: 'layer_user_required',
            required: true,
            selectionReason: 'user_required_additive_layer',
          ),
        ],
      );
      if (composition.compatibilityErrors().isNotEmpty) continue;
      final next = V2FlexibleOutfitResult.fromComposition(
        composition,
        weatherProtectionRequired: context.weatherProtectionRequired,
        minimumFormality: context.minimumFormality,
        requiredFunctions: context.requiredFunctions,
        displayByItemId: <String, Map<String, dynamic>>{
          for (final existing in current.items) existing.itemId: existing.display,
          candidate.itemId: candidate.raw,
        },
      );
      if (next.validate().isNotEmpty) continue;
      final breakdown = V2FlexibleOutfitScorer.score(next, context);
      final score = breakdown.values.fold(0.0, (a, b) => a + b);
      if (score > bestScore) {
        bestScore = score;
        best = next;
      }
    }
    return best;
  }

  @visibleForTesting
  static bool requiredLayerFamilyMatchesForTest(String canonicalType, String family) =>
      _matchesRequiredUpperLayerFamily(canonicalType, family);

'''
s = replace_once(s, anchor, helpers + anchor, 'V2 additive helpers')
write(path, s)


# ---------------------------------------------------------------------------
# 6) Client orchestration + hard UI delta guard + cross-chat memory.
# ---------------------------------------------------------------------------
path = 'lib/screens/stylist_chat_screen.dart'
s = read(path)
# Add state near existing outfit state.
s = replace_once(
    s,
    '''  Set<String> _lastOutfitItemIds = const {};
''',
    '''  Set<String> _lastOutfitItemIds = const {};
  List<Set<String>> _recentOutfitItemIdSets = const <Set<String>>[];
  bool _recentOutfitHistoryLoaded = false;
''',
    'recent outfit state',
)
# Replace helper.
s = replace_once(
    s,
    '''  bool _brainRequestsOptionalUpperLayer(Map<String, dynamic> response) {
    final directive = _brainOutfitDirective(response);
    return _brainDirectiveValue(directive, 'extraLayer', 'none') ==
        'optional_upper_layer';
  }

''',
    '''  bool _brainRequiresUpperLayer(Map<String, dynamic> response) {
    final directive = _brainOutfitDirective(response);
    return const {'required_upper_layer', 'optional_upper_layer'}.contains(
      _brainDirectiveValue(directive, 'extraLayer', 'none'),
    );
  }

  String _brainRequiredUpperLayerFamily(Map<String, dynamic> response) {
    final directive = _brainOutfitDirective(response);
    return _brainDirectiveValue(directive, 'layerFamily', 'none');
  }

  bool _brainPreservesCurrentOutfitForLayer(Map<String, dynamic> response) {
    final directive = _brainOutfitDirective(response);
    if (directive == null || !_brainRequiresUpperLayer(response)) return false;
    // Structural invariant: adding a requested layer to a visible full outfit
    // is additive even if the model forgot the boolean flag.
    return _brainDirectiveValue(directive, 'scope', 'none') == 'full_outfit' &&
        _conversationAlreadyHasOutfitCards();
  }

''',
    'Brain layer helpers',
)
# Replace all old helper calls.
s = s.replace('_brainRequestsOptionalUpperLayer(response)', '_brainRequiresUpperLayer(response)')
# Add ensure-history methods before _runHybrid.
anchor = '''  Future<void> _runHybridOutfitGeneration({
'''
methods = '''  Future<void> _ensureRecentOutfitHistory() async {
    if (_recentOutfitHistoryLoaded) return;
    try {
      _recentOutfitItemIdSets = await _chatStore.loadRecentFullOutfitItemIdSets();
    } catch (_) {
      _recentOutfitItemIdSets = const <Set<String>>[];
    } finally {
      _recentOutfitHistoryLoaded = true;
    }
  }

  void _rememberRecentOutfit(Set<String> ids) {
    if (ids.length < 3) return;
    final next = <Set<String>>[Set<String>.unmodifiable(ids)];
    for (final prior in _recentOutfitItemIdSets) {
      if (prior.length == ids.length && prior.containsAll(ids)) continue;
      next.add(prior);
      if (next.length >= 5) break;
    }
    _recentOutfitItemIdSets = List<Set<String>>.unmodifiable(next);
  }

'''
s = replace_once(s, anchor, methods + anchor, 'recent history helpers')
# Extend run signature.
s = replace_once(
    s,
    '''    StylistSwapRequest? requestedSwap,
    bool optionalUpperLayerRequested = false,
    String presentationMode = 'normal',
  }) async {
''',
    '''    StylistSwapRequest? requestedSwap,
    bool optionalUpperLayerRequested = false,
    bool preserveCurrentOutfit = false,
    String requiredUpperLayerFamily = '',
    String presentationMode = 'normal',
  }) async {
''',
    'client run additive params',
)
# Load recent memory and pass new params.
s = replace_once(
    s,
    '''    _setSendingProgress(StylistChatProgressPhase.analyzingWardrobe);
    StylistChatOutfitResult? outfitResult;
''',
    '''    if (requestedSwap == null && !preserveCurrentOutfit) {
      await _ensureRecentOutfitHistory();
    }
    _setSendingProgress(StylistChatProgressPhase.analyzingWardrobe);
    StylistChatOutfitResult? outfitResult;
''',
    'ensure recent history before full generation',
)
s = replace_once(
    s,
    '''        requestedSwap: requestedSwap,
        optionalUpperLayerRequested: optionalUpperLayerRequested,
        presentationMode: presentationMode,
        userRequest: userText,
''',
    '''        requestedSwap: requestedSwap,
        optionalUpperLayerRequested: optionalUpperLayerRequested,
        preserveCurrentOutfit: preserveCurrentOutfit,
        requiredUpperLayerFamily: requiredUpperLayerFamily == 'none'
            ? ''
            : requiredUpperLayerFamily,
        recentOutfitItemIdSets: _recentOutfitItemIdSets,
        presentationMode: presentationMode,
        userRequest: userText,
''',
    'pass additive service params',
)
# Add hard additive delta guard immediately after nextIds.
s = replace_once(
    s,
    '''    final nextIds = suggestedItems
        .map((e) => (e['id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    if (requestedSwap != null && previousIds.isNotEmpty) {
''',
    '''    final nextIds = suggestedItems
        .map((e) => (e['id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    if (preserveCurrentOutfit && previousIds.isNotEmpty) {
      final added = nextIds.difference(previousIds);
      final removed = previousIds.difference(nextIds);
      if (removed.isNotEmpty || added.length != 1) {
        debugPrint(
          'STYLIST CHAT additive_layer_rejected reason=non_additive_delta '
          'added=$added removed=$removed',
        );
        setState(() {
          _messages.add(
            const StylistChatMessage(
              text:
                  'Vrstva sa mi nepodarila pridať bez zmeny zvyšku outfitu, takže pôvodný outfit nechávam tak.',
              isUser: false,
            ),
          );
          _isSending = false;
        });
        _scrollToBottom();
        return;
      }
    }

    if (requestedSwap != null && previousIds.isNotEmpty) {
''',
    'client additive delta guard',
)
# Remember full outfit after accepted result.
s = replace_once(
    s,
    '''    _lastOutfitItemIds = nextIds;
    _currentOutfitItems = List<Map<String, dynamic>>.unmodifiable(
''',
    '''    _lastOutfitItemIds = nextIds;
    if (requestedSwap == null) _rememberRecentOutfit(nextIds);
    _currentOutfitItems = List<Map<String, dynamic>>.unmodifiable(
''',
    'remember accepted full outfit',
)
# Full generate call receives preserve/family. There are multiple full calls; replace
# every occurrence of the two-line layer/presentation tail that is NOT swap-safe.
old_tail = '''        optionalUpperLayerRequested: _brainRequiresUpperLayer(response),
        presentationMode: _brainPresentationMode(response),
'''
new_tail = '''        optionalUpperLayerRequested: _brainRequiresUpperLayer(response),
        preserveCurrentOutfit: _brainPreservesCurrentOutfitForLayer(response),
        requiredUpperLayerFamily: _brainRequiredUpperLayerFamily(response),
        presentationMode: _brainPresentationMode(response),
'''
# The swap call must not preserve as additive; update only subsequent full calls by
# first replacing all, then restore the explicit swap block based on its nearby marker.
s = s.replace(old_tail, new_tail)
s = s.replace(
    '''        requestedBottomFamily: swapRequest.slot == StylistSwapSlot.bottom
            ? swapRequest.bottomFamily
            : null,
        optionalUpperLayerRequested: _brainRequiresUpperLayer(response),
        preserveCurrentOutfit: _brainPreservesCurrentOutfitForLayer(response),
        requiredUpperLayerFamily: _brainRequiredUpperLayerFamily(response),
        presentationMode: _brainPresentationMode(response),
''',
    '''        requestedBottomFamily: swapRequest.slot == StylistSwapSlot.bottom
            ? swapRequest.bottomFamily
            : null,
        optionalUpperLayerRequested: false,
        presentationMode: _brainPresentationMode(response),
''',
    1,
)
write(path, s)


# ---------------------------------------------------------------------------
# 7) Regression tests already executed by Brain CI.
# ---------------------------------------------------------------------------
path = 'test/brain_v1_v2_offline_bundle_test.dart'
s = read(path)
s = replace_once(
    s,
    "    expect(prompts, contains('extraLayer=optional_upper_layer'));",
    "    expect(prompts, contains('extraLayer=required_upper_layer'));\n"
    "    expect(prompts, contains('preserveCurrentOutfit=true'));\n"
    "    expect(prompts, contains('layerFamily=hoodie'));",
    'offline directive expectation',
)
s = replace_once(
    s,
    '''    expect(native, contains('user_requested_backup_layer'));
  });
''',
    '''    expect(native, contains('user_requested_backup_layer'));
    expect(screen, contains('additive_layer_rejected reason=non_additive_delta'));
    expect(screen, contains('_brainPreservesCurrentOutfitForLayer'));
    expect(service, contains('locked_additive_layer'));
    expect(service, contains('required_user_layer_unavailable'));
    expect(service, contains('_preferNovelFullOutfitCandidates'));
    expect(service, contains('_addRequiredUpperLayerToFrozenCurrent'));
    expect(
      service,
      contains("const {'hoodie', 'zip_hoodie', 'sweatshirt'}.contains(type)"),
    );
  });
''',
    'offline additive expectations',
)
s = replace_once(
    s,
    '''    expect(brain, contains('Samotné „idem do mesta“ NIE JE prechádzka'));
  });
''',
    '''    expect(brain, contains('Samotné „idem do mesta“ NIE JE prechádzka'));
    expect(brain, contains('Počasie nie je povinná fráza'));
    expect(brain, contains('focused_item: JEDNA krátka prirodzená veta'));
    expect(authority, contains('deterministicFocused'));
  });
''',
    'offline concise explanation expectations',
)
write(path, s)


path = 'functions/stylist/frozen_stylist_authority_v1.test.js'
s = read(path)
append = r'''

test("focused Brain follow-up is deterministic, concise and does not spend an explanation call", async () => {
  const calls = [];
  const authority = createFrozenStylistAuthority({
    resolveOpenAISecret: () => "openai-test",
    resolveAnthropicSecret: () => "anthropic-test",
    execute: async (call) => { calls.push(call); throw new Error("focused mode should not call provider"); },
  });
  const result = await authority.resolve({
    data: {
      contractVersion: 1,
      conversationBrainVersion: "brain_v1",
      decisionMode: "locked_selection",
      presentationMode: "focused_item",
      focusSlot: "bottom",
      userRequest: "radšej by som si dal kraťasy",
      resolvedContext: {weather: "21C rain=false"},
      frozenCandidates: [{
        candidateId: "locked",
        itemIds: ["top", "shorts", "shoes"],
        presentationItems: [
          {itemId: "top", name: "sivé tričko", canonicalType: "t_shirt", primaryColor: "gray", slot: "top"},
          {itemId: "shorts", name: "čierne šortky", canonicalType: "casual_shorts", primaryColor: "black", slot: "bottom"},
          {itemId: "shoes", name: "biele tenisky", canonicalType: "sneakers", primaryColor: "white", slot: "shoes"},
        ],
        hardConstraintEvidence: {deterministicPassed: true, violationCodes: []},
        compromiseClassification: {level: "none", reasonCodes: []},
      }],
    },
    ownedItemIds: new Set(["top", "shorts", "shoes"]),
  });
  assert.equal(calls.length, 0);
  assert.equal(result.action, "select_candidate");
  assert.match(result.explanation, /čierne šortky/);
  assert.doesNotMatch(result.explanation, /21|°C|počas/i);
});
'''
if 'focused Brain follow-up is deterministic' not in s:
    s = s.rstrip() + append + '\n'
write(path, s)


# Prompt unit regression.
path = 'functions/stylist/chat_prompts.test.js'
s = read(path)
if 'required_upper_layer' not in s:
    s = s.rstrip() + '''\n\ntest("Brain additive layer contract is explicit and hard", () => {\n  const prompt = buildChatSystemPrompt({tier: "brain_v1"});\n  assert.match(prompt, /required_upper_layer/);\n  assert.match(prompt, /preserveCurrentOutfit=true/);\n  assert.match(prompt, /layerFamily=hoodie/);\n  assert.match(prompt, /Nesmieš ju zrušiť/);\n});\n'''
write(path, s)

print('Brain follow-up hardening patch prepared.')
