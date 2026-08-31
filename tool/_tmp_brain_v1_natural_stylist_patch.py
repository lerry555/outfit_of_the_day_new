from pathlib import Path
import re

ROOT = Path(".")
EXPECTED_EXPERIMENT = "9123bfe828bd3cb1293d3da45931b06784781386"
EXPECTED_MASTER = "00bd52fa20f1e5b281d66850758c465dc2b00098"

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

def write(path, text):
    (ROOT / path).write_text(text, encoding="utf-8")

def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly 1 match, got {count}")
    return text.replace(old, new, 1)

def replace_regex_once(text, pattern, repl, label, flags=0):
    new_text, count = re.subn(pattern, repl, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly 1 regex match, got {count}")
    return new_text

# 1) Brain structured outfit directive.
path = "functions/stylist/chat_prompts.js"
s = read(path)
s = replace_once(
    s,
    '`"showItemIds":[],\\"eventContext\\":{},\\"excludeItemKeywords\\":[]}\\\\n` +',
    '`"showItemIds":[],\\"eventContext\\":{},\\"excludeItemKeywords\\":[],` +\n' +
    '  `\\"outfitDirective\\":{\\"scope\\":\\"none\\",\\"slot\\":\\"none\\",\\"family\\":\\"none\\",` +\n' +
    '  `\\"preserveOtherSlots\\":true,\\"extraLayer\\":\\"none\\",\\"presentation\\":\\"normal\\"}}\\\\n` +',
    "brain JSON output directive",
)
anchor = (
    '  `- generate_outfit použi iba keď používateľ významovo žiada zostaviť/odporučiť outfit alebo oblečenie, prijme ponuku na jeho zostavenie, prípadne explicitne mení už zobrazený outfit.\\\\n` +\n'
)
directive_rules = (
    anchor +
    '  `- OUTFIT DIRECTIVE je štruktúrovaný význam userovej poslednej požiadavky, nie módne rozhodnutie. Vždy ho vyplň.\\\\n` +\n' +
    '  `- scope=none pri obyčajnom rozhovore, vysvetlení alebo porovnaní („prečo rifle a nie kraťasy?“). Taká otázka NESMIE sama meniť outfit.\\\\n` +\n' +
    '  `- scope=full_outfit keď user žiada prvý/celý/nový outfit. presentation=normal pri prvom odporúčaní; presentation=concise_full keď už outfit vidí a chce ho iba znovu ukázať alebo zobraziť po úprave.\\\\n` +\n' +
    '  `- scope=single_slot keď user chce vybrať alebo vymeniť presne jeden slot („ktoré kraťasy?“, „iné topánky“, „zmeň tričko“). slot=top|bottom|shoes|outerwear, preserveOtherSlots=true, presentation=focused_item.\\\\n` +\n' +
    '  `- family používaj iba ak user rodinu naozaj určil: shorts|jeans|pants|joggers|sneakers|boots|sandals|formal_shoes; inak none.\\\\n` +\n' +
    '  `- extraLayer=optional_upper_layer iba keď user explicitne chce pridať záložnú vrstvu navrch/pre prípad chladu. Nevyvodzuj ju iba z večera alebo mesta.\\\\n` +\n' +
    '  `- Ak user povie „ukáž celý outfit a pridaj niečo navrch“, je to full_outfit + optional_upper_layer + concise_full, nie single-slot swap.\\\\n` +\n' +
    '  `- Ak user povie „ktoré kraťasy si mám dať?“, je to generate_outfit + single_slot(bottom, shorts) + focused_item. Odpoveď má znieť ako rada stylistu, nie ako interná operácia.\\\\n` +\n'
)
s = replace_once(s, anchor, directive_rules, "insert Brain directive rules")
write(path, s)

# 2) Backend directive sanitize/forward + current recommendation metadata.
path = "functions/index.js"
s = read(path)
helper_anchor = (
    "// An LLM may interpret known context but never becomes a source of new\n"
    "// resolved facts. This keeps GPT-4o's Track-U authority limited to\n"
    "// ask/proceed/action framing; deterministic app state remains fact authority.\n"
)
helper = '''function sanitizeStylistOutfitDirective(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const allowedScopes = new Set(["none", "full_outfit", "single_slot"]);
  const allowedSlots = new Set(["none", "top", "bottom", "shoes", "outerwear"]);
  const allowedFamilies = new Set([
    "none", "shorts", "jeans", "pants", "joggers",
    "sneakers", "boots", "sandals", "formal_shoes",
  ]);
  const allowedExtraLayers = new Set(["none", "optional_upper_layer"]);
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
    extraLayer,
    presentation,
  });
}

'''
s = replace_once(s, helper_anchor, helper + helper_anchor, "insert directive sanitizer")

old = '''    const currentOutfit = Array.isArray(clientContext.currentOutfit)?
      clientContext.currentOutfit.slice(0, 6).map((raw) => {
        if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
        const item = {};
        for (const key of ["name", "type", "color"]) {
          const value = String(raw[key] || "").trim().slice(0, 120);
          if (value) item[key] = value;
        }
        return Object.keys(item).length ? item : null;
      }).filter(Boolean) : [];
'''
new = old + '''    const currentOutfitDecision =
      clientContext.currentOutfitDecision &&
      typeof clientContext.currentOutfitDecision === "object" &&
      !Array.isArray(clientContext.currentOutfitDecision) ?
        {
          recommendedByStylist: clientContext.currentOutfitDecision.recommendedByStylist === true,
          usedCompromise: clientContext.currentOutfitDecision.usedCompromise === true,
          rationale: String(clientContext.currentOutfitDecision.rationale || "")
            .trim().slice(0, 500),
        } :
        null;
'''
s = replace_once(s, old, new, "currentOutfitDecision formatter")
s = replace_once(
    s,
    '''    if (currentOutfit.length) {
      parts.push(`currentOutfit=${JSON.stringify(currentOutfit)}`);
    }
''',
    '''    if (currentOutfit.length) {
      parts.push(`currentOutfit=${JSON.stringify(currentOutfit)}`);
    }
    if (currentOutfitDecision && currentOutfitDecision.recommendedByStylist) {
      parts.push(`currentOutfitDecision=${JSON.stringify(currentOutfitDecision)}`);
    }
''',
    "emit currentOutfitDecision",
)
s = replace_once(
    s,
    '''        const excludeItemKeywords = Array.isArray(parsed?.excludeItemKeywords)?
          parsed.excludeItemKeywords
            .map((v) => String(v || "").trim())
            .filter(Boolean) :
          [];

        let suggestedIds = [];
''',
    '''        const excludeItemKeywords = Array.isArray(parsed?.excludeItemKeywords)?
          parsed.excludeItemKeywords
            .map((v) => String(v || "").trim())
            .filter(Boolean) :
          [];
        const outfitDirective = sanitizeStylistOutfitDirective(parsed?.outfitDirective);

        let suggestedIds = [];
''',
    "parse outfit directive",
)
s = replace_once(
    s,
    '''          eventContext,
          excludeItemKeywords,
          confidence,
''',
    '''          eventContext,
          excludeItemKeywords,
          outfitDirective,
          confidence,
''',
    "return outfit directive",
)
write(path, s)

# 3) Frozen authority: locked explanation mode + presentation semantics.
path = "functions/stylist/frozen_stylist_authority_v1.js"
s = read(path)
s = replace_once(
    s,
    '''  for (const key of ["activity", "occasion", "environment", "weather", "formality", "terrain"]) {
    const text = cleanText(source[key]);
    if (text) context[key] = text;
  }
''',
    '''  for (const key of ["activity", "occasion", "environment", "weather", "formality", "terrain"]) {
    const text = cleanText(source[key]);
    if (text) context[key] = text;
  }
  const userIntentContext = cleanText(source.userIntentContext, 600);
  if (userIntentContext) context.userIntentContext = userIntentContext;
''',
    "safe user intent context",
)
s = replace_once(
    s,
    '''    byId.set(itemId, Object.freeze({itemId, name, canonicalType, primaryColor}));
''',
    '''    const slot = ["top", "bottom", "shoes", "outerwear"].includes(cleanText(raw.slot, 24)) ?
      cleanText(raw.slot, 24) : "";
    byId.set(itemId, Object.freeze({itemId, name, canonicalType, primaryColor, slot}));
''',
    "presentation slot",
)
s = replace_once(
    s,
    '''  return Object.freeze({resolvedContext: safeContext(data.resolvedContext), frozenCandidates: Object.freeze(candidates)});
}
''',
    '''  const decisionMode = cleanText(data.decisionMode, 40) === "locked_selection" ?
    "locked_selection" : "select_candidate";
  const presentationMode = ["normal", "focused_item", "concise_full"].includes(
    cleanText(data.presentationMode, 40),
  ) ? cleanText(data.presentationMode, 40) : "normal";
  const focusSlot = ["top", "bottom", "shoes", "outerwear"].includes(
    cleanText(data.focusSlot, 24),
  ) ? cleanText(data.focusSlot, 24) : "";
  const userRequest = cleanText(data.userRequest, 600);
  return Object.freeze({
    resolvedContext: safeContext(data.resolvedContext),
    frozenCandidates: Object.freeze(candidates),
    decisionMode,
    presentationMode,
    focusSlot,
    userRequest,
  });
}
''',
    "normalize locked presentation fields",
)
s = replace_once(
    s,
    '''    userFacingSelectedOutfit: selected ? selected.presentationItems.map((item) => ({
      name: item.name, canonicalType: item.canonicalType, primaryColor: item.primaryColor,
    })) : [],
    userFacingContext: normalized.resolvedContext,
''',
    '''    userFacingSelectedOutfit: selected ? selected.presentationItems.map((item) => ({
      name: item.name, canonicalType: item.canonicalType, primaryColor: item.primaryColor,
      slot: item.slot,
    })) : [],
    userFacingContext: normalized.resolvedContext,
    presentationMode: normalized.presentationMode,
    focusSlot: normalized.focusSlot,
    userRequest: normalized.userRequest,
''',
    "explanation payload presentation mode",
)
old_resolve = '''      const eligible = normalized.frozenCandidates.filter((candidate) => candidate.eligible);
      let decision = eligible.length ? null : rejectAll("no_valid_frozen_candidates");
      let decisionProviderFailure = null;
      if (!decision) {
        const result = await decisionClient.run({
'''
new_resolve = '''      const eligible = normalized.frozenCandidates.filter((candidate) => candidate.eligible);
      let decision = null;
      let decisionProviderFailure = null;
      if (normalized.decisionMode === "locked_selection") {
        if (normalized.frozenCandidates.length !== 1 || eligible.length !== 1) {
          decision = rejectAll("locked_selection_invalid");
        } else {
          const selected = eligible[0];
          decision = Object.freeze({
            action: "select_candidate",
            selectedCandidateId: selected.candidateId,
            requestedAction: "select_candidate",
            requestedSelectedCandidateId: selected.candidateId,
            requestedDecisionAccepted: true,
            reasonCodes: Object.freeze([]),
          });
        }
      } else if (!eligible.length) {
        decision = rejectAll("no_valid_frozen_candidates");
      }
      if (!decision) {
        const result = await decisionClient.run({
'''
s = replace_once(s, old_resolve, new_resolve, "locked selection bypass")
write(path, s)

# 4) Conversation Brain explanation modes.
path = "functions/stylist/conversation_brain_v1.js"
s = read(path)
anchor = (
    '    "- Pri select_candidate pomenuj iba kúsky z userFacingSelectedOutfit. Vysvetli konkrétne, prečo kombinácia funguje pre situáciu, počasie alebo dress code.",\n'
)
addition = anchor + '''    "- presentationMode riadi ROZSAH odpovede, nikdy samotný výber kúskov.",
    "- focused_item: odpovedz ako živý stylista na userRequest. Zameraj sa na kúsok vo focusSlot, povedz napr. „Zvolil by som tieto čierne šortky, pretože…“. NIKDY nepíš technické formulácie typu „vymenil som spodok/slot“. Stačí 1–2 prirodzené vety.",
    "- concise_full: používateľ už outfit videl alebo si ho práve nechal upraviť. Neopakuj celý dlhý rozbor. Stačí 1–2 vety, ktoré potvrdia podstatnú zmenu/požiadavku; karty pod správou ukážu kúsky.",
    "- normal: pri prvom odporúčaní daj stručné 2–4 vety, nie katalógový odsek.",
    "- userFacingContext.userIntentContext obsahuje iba userove vlastné slová k použitiu outfitu. Aktivitu typu prechádzka, stretnutie, večera a pod. smieš pomenovať len ak je v tomto kontexte explicitne podložená. Samotné „idem do mesta“ NIE JE prechádzka ani stretnutie.",
'''
s = replace_once(s, anchor, addition, "explanation presentation rules")
s = replace_once(
    s,
    '    "- Vráť 2–5 prirodzených viet, pokiaľ situácia nepotrebuje menej.",\n',
    '    "- Dĺžku riaď presentationMode; prirodzenosť a presnosť sú dôležitejšie než pevný počet viet.",\n',
    "explanation length mode",
)
write(path, s)

# 5) Dart frozen transport.
path = "lib/Services/stylist_frozen_candidate_decision_service.dart"
s = read(path)
s = replace_once(
    s,
    '''  Future<StylistFrozenCandidateDecisionResultV1> resolve({
    required List<V2FlexibleCandidate> candidates,
    required Map<String, dynamic> resolvedContext,
  }) async {
''',
    '''  Future<StylistFrozenCandidateDecisionResultV1> resolve({
    required List<V2FlexibleCandidate> candidates,
    required Map<String, dynamic> resolvedContext,
    bool lockedSelection = false,
    String presentationMode = 'normal',
    String focusSlot = '',
    String userRequest = '',
  }) async {
''',
    "Dart frozen resolve signature",
)
s = replace_once(
    s,
    '''            'resolvedContext': resolvedContext,
            'frozenCandidates': candidates
''',
    '''            'resolvedContext': resolvedContext,
            'decisionMode': lockedSelection ? 'locked_selection' : 'select_candidate',
            'presentationMode': presentationMode,
            if (focusSlot.trim().isNotEmpty) 'focusSlot': focusSlot.trim(),
            if (userRequest.trim().isNotEmpty) 'userRequest': userRequest.trim(),
            'frozenCandidates': candidates
''',
    "Dart frozen request metadata",
)
s = replace_once(
    s,
    '''              'primaryColor': item.item.colorProfile.primary.family,
            },
''',
    '''              'primaryColor': item.item.colorProfile.primary.family,
              'slot': _presentationSlot(item),
            },
''',
    "Dart candidate slot",
)
s = replace_once(
    s,
    '''  static String _presentationName(V2FlexibleOutfitItem item) {
''',
    '''  static String _presentationSlot(V2FlexibleOutfitItem item) {
    if (item.item.bodySlots.contains('feet')) return 'shoes';
    if (item.item.layerPosition == 'outer' || item.item.layerPosition == 'shell') {
      return 'outerwear';
    }
    if (item.item.bodySlots.contains('lower_body') &&
        !item.item.bodySlots.contains('upper_body')) {
      return 'bottom';
    }
    if (item.item.bodySlots.contains('upper_body')) return 'top';
    return '';
  }

  static String _presentationName(V2FlexibleOutfitItem item) {
''',
    "Dart presentation slot helper",
)
write(path, s)

# 6) Shared V2 context + engine optional upper layer.
path = "lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart"
s = read(path)
s = replace_once(
    s,
    '''    this.wetGroundRisk = false,
  });
''',
    '''    this.wetGroundRisk = false,
    this.optionalUpperLayerRequested = false,
  });
''',
    "matrix optional layer ctor",
)
s = replace_once(
    s,
    '''  final bool wetGroundRisk;
''',
    '''  final bool wetGroundRisk;
  final bool optionalUpperLayerRequested;
''',
    "matrix optional layer field",
)
s = replace_once(
    s,
    '''            formalityFloor: [
              context.decisionFormalityFloor,
''',
    '''            optionalUpperLayerRequested: context.optionalUpperLayerRequested,
            formalityFloor: [
              context.decisionFormalityFloor,
''',
    "matrix pass optional layer",
)
write(path, s)

path = "lib/domain/wardrobe_v2/native_outfit_engine_v2.dart"
s = read(path)
s = replace_once(
    s,
    '''    this.forbiddenCanonicalTypes = const {},
  });
  final bool weatherProtectionRequired, preferOnePiece;
''',
    '''    this.forbiddenCanonicalTypes = const {},
    this.optionalUpperLayerRequested = false,
  });
  final bool weatherProtectionRequired, preferOnePiece, optionalUpperLayerRequested;
''',
    "native optional layer field",
)
layer_loop = '''    for (final layer in ['skin_base', 'mid', 'outer', 'shell']) {
      final candidate = pick(
        (x) =>
            x.item.layerPosition == layer &&
            !isSelected(selected, x.itemId) &&
            (layer == 'skin_base' || isUpperLayer(x)),
        rank: layerWarmthRank,
      );
      if (candidate != null && wantsLayer(layer, candidate)) {
        add(
          candidate,
          CompositionRoleV2.conditional,
          'layer_$layer',
          false,
          'weather_or_function',
        );
      }
    }

'''
layer_new = layer_loop + '''    // Explicit backup-layer intent is global and slot-based. If ordinary
    // weather logic did not already add an upper layer, choose one light,
    // physically suitable mid/outer/shell option and no more.
    if (request.optionalUpperLayerRequested &&
        !selected.any(
          (item) =>
              const {'mid', 'outer', 'shell'}.contains(item.item.layerPosition) &&
              item.item.bodySlots.contains('upper_body'),
        )) {
      final backupLayer = pick(
        (x) =>
            const {'mid', 'outer', 'shell'}.contains(x.item.layerPosition) &&
            isUpperLayer(x) &&
            !isSelected(selected, x.itemId),
        rank: layerWarmthRank,
        allowUnsafeFallback: false,
      );
      if (backupLayer != null) {
        add(
          backupLayer,
          CompositionRoleV2.conditional,
          'layer_user_backup',
          false,
          'user_requested_backup_layer',
        );
      }
    }

'''
s = replace_once(s, layer_loop, layer_new, "native optional backup layer")
write(path, s)

# 7) Outfit service: centralized comfort + semantic layer + locked phrasing.
path = "lib/Services/stylist_chat_outfit_service.dart"
s = read(path)
s = replace_once(
    s,
    "import '../domain/wardrobe_v2/outfit_composition_v2.dart';\n",
    "import '../domain/wardrobe_v2/outfit_composition_v2.dart';\n"
    "import '../domain/wardrobe_v2/outfit_suitability_policy_v2.dart';\n",
    "service import suitability policy",
)
s = replace_once(
    s,
    '''    StylistSwapRequest? requestedSwap,
    StylistChatOutfitDebugCollector? debugCollector,
''',
    '''    StylistSwapRequest? requestedSwap,
    bool optionalUpperLayerRequested = false,
    String presentationMode = 'normal',
    String userRequest = '',
    StylistChatOutfitDebugCollector? debugCollector,
''',
    "service generation semantic params",
)
s = replace_once(
    s,
    '''      wetGroundRisk: wetGroundMuddy,
    );
''',
    '''      wetGroundRisk: wetGroundMuddy,
      optionalUpperLayerRequested: optionalUpperLayerRequested,
    );
''',
    "service context optional layer",
)
s = replace_once(
    s,
    '''          wetGroundRisk: context.wetGroundRisk,
        ),
''',
    '''          wetGroundRisk: context.wetGroundRisk,
          optionalUpperLayerRequested: context.optionalUpperLayerRequested,
        ),
''',
    "service fallback optional layer",
)
s = replace_regex_once(
    s,
    r'''              final targetWarmth = weather\.tempC <= 5
                  \? 8\.0
                  : weather\.tempC <= 14
                  \? 6\.0
                  : weather\.tempC >= 26
                  \? 2\.0
                  : 4\.0;''',
    '''              final targetWarmth =
                  OutfitSuitabilityPolicyV2.targetMeanWarmth(weather.tempC);''',
    "central comfort target",
)
insert_anchor = '''    V2FlexibleOutfitResult? selected;
    String? finalExplanation;
    List<String> rejectAllReasonCodes = const <String>[];
'''
insert_new = insert_anchor + '''    final frozenResolvedContext = <String, dynamic>{
      'activity': outfitIntent.activityType,
      'occasion': occasionProfile.label,
      'environment': event.locationLabel,
      'weather':
          '${weather.tempC}C rain=${weather.isRainy} '
          'wind=${weather.isWindy} wetGround=$wetGroundMuddy '
          'antecedentRain=$antecedentPrecipitation',
      'formality': occasionProfile.dressCode.id,
      'terrain': terrain.name,
      if ((conversationHint ?? '').trim().isNotEmpty)
        'userIntentContext': conversationHint!.trim(),
      'relevantKnownTimingFacts': <String, String>{
        'eventDate':
            '${event.date.year.toString().padLeft(4, '0')}-'
            '${event.date.month.toString().padLeft(2, '0')}-'
            '${event.date.day.toString().padLeft(2, '0')}',
        'dayRelation': _dayRelation(event.date),
        if (event.eventStartHour != null)
          'eventStartHourLocal': event.eventStartHour.toString(),
      },
    };
'''
s = replace_once(s, insert_anchor, insert_new, "shared frozen context")
s = replace_once(
    s,
    '''          activityType: context.activityType,
        ),
''',
    '''          activityType: context.activityType,
          optionalUpperLayerRequested: context.optionalUpperLayerRequested,
        ),
''',
    "current outfit native request optional layer",
)
old_block = '''      final decision = await const StylistFrozenCandidateDecisionServiceV1()
          .resolve(
            candidates: matrix,
            resolvedContext: <String, dynamic>{
              'activity': outfitIntent.activityType,
              'occasion': occasionProfile.label,
              'environment': event.locationLabel,
              'weather':
                  '${weather.tempC}C rain=${weather.isRainy} '
                  'wind=${weather.isWindy} wetGround=$wetGroundMuddy '
                  'antecedentRain=$antecedentPrecipitation',
              'formality': occasionProfile.dressCode.id,
              'terrain': terrain.name,
              'relevantKnownTimingFacts': <String, String>{
                'eventDate':
                    '${event.date.year.toString().padLeft(4, '0')}-'
                    '${event.date.month.toString().padLeft(2, '0')}-'
                    '${event.date.day.toString().padLeft(2, '0')}',
                'dayRelation': _dayRelation(event.date),
                if (event.eventStartHour != null)
                  'eventStartHourLocal': event.eventStartHour.toString(),
              },
            },
          );
'''
new_block = '''      final decision = await const StylistFrozenCandidateDecisionServiceV1()
          .resolve(
            candidates: matrix,
            resolvedContext: frozenResolvedContext,
            presentationMode: presentationMode,
            userRequest: userRequest,
          );
'''
s = replace_once(s, old_block, new_block, "normal frozen resolve modes")
swap_end_anchor = '''        selected = requireExplicitStylistSwapReplacementV1(
          V2FlexibleSwapOrchestrator.replace(
            current: current,
            itemId: target.itemId,
            wardrobe: resolved,
            context: context,
            // Any explicit one-slot swap may consider another compatible
            // family in the same body slot. This is a global swap invariant,
            // not a bottom/shorts exception; every other displayed item stays
            // frozen and the normal suitability guards still apply.
            allowCrossFamilySameSlot: true,
            requireCoolerReplacement:
                requestedSwap.thermalPreference ==
                StylistSwapThermalPreference.cooler,
            requireWarmerReplacement:
                requestedSwap.thermalPreference ==
                StylistSwapThermalPreference.warmer,
          ),
        );
      }
    } else {
'''
swap_end_new = '''        selected = requireExplicitStylistSwapReplacementV1(
          V2FlexibleSwapOrchestrator.replace(
            current: current,
            itemId: target.itemId,
            wardrobe: resolved,
            context: context,
            // Any explicit one-slot swap may consider another compatible
            // family in the same body slot. This is a global swap invariant,
            // not a bottom/shorts exception; every other displayed item stays
            // frozen and the normal suitability guards still apply.
            allowCrossFamilySameSlot: true,
            requireCoolerReplacement:
                requestedSwap.thermalPreference ==
                StylistSwapThermalPreference.cooler,
            requireWarmerReplacement:
                requestedSwap.thermalPreference ==
                StylistSwapThermalPreference.warmer,
          ),
        );
        final lockedCandidate = V2FlexibleCandidate(
          candidateId: 'locked_swap',
          outfit: selected,
          score: 0,
          scoreBreakdown: const <String, double>{},
        );
        final lockedExplanation =
            await const StylistFrozenCandidateDecisionServiceV1().resolve(
          candidates: <V2FlexibleCandidate>[lockedCandidate],
          resolvedContext: frozenResolvedContext,
          lockedSelection: true,
          presentationMode: 'focused_item',
          focusSlot: requestedSwap.slot.name,
          userRequest: userRequest,
        );
        if (lockedExplanation.selected &&
            lockedExplanation.explanation.trim().isNotEmpty) {
          finalExplanation = lockedExplanation.explanation.trim();
        }
      }
    } else {
'''
s = replace_once(s, swap_end_anchor, swap_end_new, "locked swap Brain explanation")
write(path, s)

# 8) Client: structured directive + natural swap copy + recommendation state.
path = "lib/screens/stylist_chat_screen.dart"
s = read(path)
s = replace_once(
    s,
    "import '../utils/bottom_family_guidance.dart';\n",
    "import '../utils/bottom_family_guidance.dart';\n"
    "import '../utils/footwear_family_guidance.dart';\n",
    "screen footwear family import",
)
s = replace_once(
    s,
    '''  /// Job that produced this assistant turn. Used to dedupe notification hydration.
  final String? sourceJobId;
''',
    '''  /// Job that produced this assistant turn. Used to dedupe notification hydration.
  final String? sourceJobId;

  /// Structural marker for a one-slot outfit edit. Persisted so reopening a
  /// chat never has to infer state from user-facing wording.
  final String? outfitUpdateSlot;
''',
    "message outfit update field",
)
s = replace_once(
    s,
    '''    this.ephemeral = false,
    this.sourceJobId,
  });
''',
    '''    this.ephemeral = false,
    this.sourceJobId,
    this.outfitUpdateSlot,
  });
''',
    "message ctor metadata",
)
s = replace_once(
    s,
    '''  StylistChatMessage copyWith({String? sourceJobId}) {
''',
    '''  StylistChatMessage copyWith({String? sourceJobId, String? outfitUpdateSlot}) {
''',
    "message copyWith signature",
)
s = replace_once(
    s,
    '''      sourceJobId: sourceJobId ?? this.sourceJobId,
    );
''',
    '''      sourceJobId: sourceJobId ?? this.sourceJobId,
      outfitUpdateSlot: outfitUpdateSlot ?? this.outfitUpdateSlot,
    );
''',
    "message copyWith metadata",
)
s = replace_once(
    s,
    '''      if (sourceJobId != null && sourceJobId!.isNotEmpty)
        'sourceJobId': sourceJobId,
    };
''',
    '''      if (sourceJobId != null && sourceJobId!.isNotEmpty)
        'sourceJobId': sourceJobId,
      if (outfitUpdateSlot != null && outfitUpdateSlot!.isNotEmpty)
        'outfitUpdateSlot': outfitUpdateSlot,
    };
''',
    "message persist metadata",
)
s = replace_once(
    s,
    '''      sourceJobId: sourceJobId.isEmpty ? null : sourceJobId,
    );
''',
    '''      sourceJobId: sourceJobId.isEmpty ? null : sourceJobId,
      outfitUpdateSlot: (map['outfitUpdateSlot'] ?? '').toString().trim().isEmpty
          ? null
          : (map['outfitUpdateSlot'] ?? '').toString().trim(),
    );
''',
    "message restore metadata",
)
s = replace_once(
    s,
    '''  List<Map<String, dynamic>> _currentOutfitItems = const <Map<String, dynamic>>[];
''',
    '''  List<Map<String, dynamic>> _currentOutfitItems = const <Map<String, dynamic>>[];
  bool _currentOutfitUsedCompromise = false;
  String _currentOutfitDecisionRationale = '';
''',
    "current recommendation metadata",
)
handle_anchor = '''  Future<void> _handleAssistantResponse({
'''
helpers = '''  Map<String, dynamic>? _brainOutfitDirective(
    Map<String, dynamic> response,
  ) {
    final raw = response['outfitDirective'];
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  String _brainDirectiveValue(
    Map<String, dynamic>? directive,
    String key,
    String fallback,
  ) {
    final value = directive?[key]?.toString().trim().toLowerCase() ?? '';
    return value.isEmpty ? fallback : value;
  }

  StylistSwapRequest? _swapRequestForTurn(
    Map<String, dynamic> response,
    String userText,
  ) {
    final directive = _brainOutfitDirective(response);
    if (directive != null) {
      if (_brainDirectiveValue(directive, 'scope', 'none') != 'single_slot') {
        return null;
      }
      final slot = switch (_brainDirectiveValue(directive, 'slot', 'none')) {
        'top' => StylistSwapSlot.top,
        'bottom' => StylistSwapSlot.bottom,
        'shoes' => StylistSwapSlot.shoes,
        'outerwear' => StylistSwapSlot.outerwear,
        _ => null,
      };
      if (slot == null) return null;
      final family = _brainDirectiveValue(directive, 'family', 'none');
      final bottomFamily = slot == StylistSwapSlot.bottom
          ? switch (family) {
              'shorts' => BottomFamily.shorts,
              'jeans' => BottomFamily.jeans,
              'pants' => BottomFamily.pants,
              'joggers' => BottomFamily.joggers,
              _ => null,
            }
          : null;
      final shoeFamily = slot == StylistSwapSlot.shoes
          ? switch (family) {
              'sneakers' => FootwearFamily.sneakers,
              'boots' => FootwearFamily.boots,
              'sandals' => FootwearFamily.sandals,
              'formal_shoes' => FootwearFamily.formal,
              _ => null,
            }
          : null;
      return StylistSwapRequest(
        slot: slot,
        bottomFamily: bottomFamily,
        shoeFamily: shoeFamily,
      );
    }
    return StylistSwapRequest.parse(userText);
  }

  bool _brainRequestsOptionalUpperLayer(Map<String, dynamic> response) {
    final directive = _brainOutfitDirective(response);
    return _brainDirectiveValue(directive, 'extraLayer', 'none') ==
        'optional_upper_layer';
  }

  String _brainPresentationMode(Map<String, dynamic> response) {
    final directive = _brainOutfitDirective(response);
    final value = _brainDirectiveValue(directive, 'presentation', 'normal');
    return const {'normal', 'focused_item', 'concise_full'}.contains(value)
        ? value
        : 'normal';
  }

'''
s = replace_once(s, handle_anchor, helpers + handle_anchor, "screen Brain directive helpers")
s = replace_once(
    s,
    '''    final swapRequest = StylistSwapRequest.parse(userText);
''',
    '''    final swapRequest = _swapRequestForTurn(response, userText);
''',
    "screen directive swap authority",
)
s = replace_once(
    s,
    '''        requestedBottomFamily: swapRequest.slot == StylistSwapSlot.bottom
            ? swapRequest.bottomFamily
            : null,
      );
''',
    '''        requestedBottomFamily: swapRequest.slot == StylistSwapSlot.bottom
            ? swapRequest.bottomFamily
            : null,
        optionalUpperLayerRequested: _brainRequestsOptionalUpperLayer(response),
        presentationMode: _brainPresentationMode(response),
      );
''',
    "explicit swap semantic generation params",
)
s = replace_once(
    s,
    '''        forceDifferent: _shouldForceDifferentOutfit(userText),
        requestedBottomFamily: _resolveRequestedBottomFamily(userText),
      );
      return;
    }

    if (action == 'chat' &&
''',
    '''        forceDifferent: _shouldForceDifferentOutfit(userText),
        requestedBottomFamily: _resolveRequestedBottomFamily(userText),
        optionalUpperLayerRequested: _brainRequestsOptionalUpperLayer(response),
        presentationMode: _brainPresentationMode(response),
      );
      return;
    }

    if (action == 'chat' &&
''',
    "main generate semantic params",
)
s = replace_once(
    s,
    '''          forceDifferent: _shouldForceDifferentOutfit(userText),
          requestedBottomFamily: _resolveRequestedBottomFamily(userText),
        );
        return;
      }
    }

    if (action == 'chat' && _shouldAutoGenerateOutfitAfterChat()) {
''',
    '''          forceDifferent: _shouldForceDifferentOutfit(userText),
          requestedBottomFamily: _resolveRequestedBottomFamily(userText),
          optionalUpperLayerRequested: _brainRequestsOptionalUpperLayer(response),
          presentationMode: _brainPresentationMode(response),
        );
        return;
      }
    }

    if (action == 'chat' && _shouldAutoGenerateOutfitAfterChat()) {
''',
    "explicit show semantic params",
)
s = replace_once(
    s,
    '''        forceDifferent: _shouldForceDifferentOutfit(userText),
        requestedBottomFamily: _resolveRequestedBottomFamily(userText),
      );
      return;
    }

    if (action == 'chat' && _userAsksAboutWeather(userText)) {
''',
    '''        forceDifferent: _shouldForceDifferentOutfit(userText),
        requestedBottomFamily: _resolveRequestedBottomFamily(userText),
        optionalUpperLayerRequested: _brainRequestsOptionalUpperLayer(response),
        presentationMode: _brainPresentationMode(response),
      );
      return;
    }

    if (action == 'chat' && _userAsksAboutWeather(userText)) {
''',
    "auto generation semantic params",
)
s = replace_once(
    s,
    '''    BottomFamily? requestedBottomFamily,
    StylistSwapRequest? requestedSwap,
  }) async {
''',
    '''    BottomFamily? requestedBottomFamily,
    StylistSwapRequest? requestedSwap,
    bool optionalUpperLayerRequested = false,
    String presentationMode = 'normal',
  }) async {
''',
    "hybrid signature semantic params",
)
s = replace_once(
    s,
    '''        requestedBottomFamily: requestedBottomFamily,
        requestedSwap: requestedSwap,
        onProgress: _setSendingProgress,
''',
    '''        requestedBottomFamily: requestedBottomFamily,
        requestedSwap: requestedSwap,
        optionalUpperLayerRequested: optionalUpperLayerRequested,
        presentationMode: presentationMode,
        userRequest: userText,
        onProgress: _setSendingProgress,
''',
    "hybrid service semantic params",
)
s = replace_once(
    s,
    '''    final wardrobeAnalysis = outfitResult.wardrobeAnalysis;

    final previousIds = _lastOutfitItemIds;
''',
    '''    final wardrobeAnalysis = outfitResult.wardrobeAnalysis;
    _currentOutfitUsedCompromise = wardrobeAnalysis.usedCompromise;
    _currentOutfitDecisionRationale =
        (outfitResult.finalExplanation ?? '').trim();

    final previousIds = _lastOutfitItemIds;
''',
    "store current recommendation state",
)
old_swap_display = '''      final shortReply = _shortSwapReply(
        suggestedItems: suggestedItems,
        slot: swapSlot,
      );
      if (shortReply != null && swapDisplayItems.isNotEmpty) {
        debugPrint(
          'STYLIST CHAT reply_source=local_swap_${swapSlot.name} '
          'display_items=${swapDisplayItems.length}',
        );
        setState(() {
          _messages.add(
            StylistChatMessage(
              text: shortReply,
              isUser: false,
              suggestedItems: swapDisplayItems,
            ),
          );
          _isSending = false;
        });
'''
new_swap_display = '''      final brainReply =
          StylistUdrClientRoutingV1.frozenExplanationForDisplay(
            outfitResult.finalExplanation,
          );
      final fallbackReply = _shortSwapReply(
        suggestedItems: suggestedItems,
        slot: swapSlot,
      );
      final focusedReply = brainReply ?? fallbackReply;
      if (focusedReply != null && swapDisplayItems.isNotEmpty) {
        debugPrint(
          'STYLIST CHAT reply_source='
          '${brainReply != null ? 'brain_locked_swap' : 'local_swap_fallback'} '
          'slot=${swapSlot.name} display_items=${swapDisplayItems.length}',
        );
        setState(() {
          _messages.add(
            StylistChatMessage(
              text: focusedReply,
              isUser: false,
              suggestedItems: swapDisplayItems,
              outfitUpdateSlot: swapSlot.name,
            ),
          );
          _isSending = false;
        });
'''
s = replace_once(s, old_swap_display, new_swap_display, "natural swap reply")

start = s.index("  String? _shortSwapReply({")
end = s.index("\n  /// Krátke vysvetlenie, keď sa kvôli zladeniu", start)
new_func = '''  String? _shortSwapReply({
    required List<Map<String, dynamic>> suggestedItems,
    required StylistSwapSlot slot,
  }) {
    const slotOrderFor = <StylistSwapSlot, int>{
      StylistSwapSlot.top: 0,
      StylistSwapSlot.outerwear: 1,
      StylistSwapSlot.bottom: 2,
      StylistSwapSlot.shoes: 3,
    };
    final changed = suggestedItems
        .where((item) => _stylistWearSlotOrder(item) == slotOrderFor[slot])
        .firstOrNull;
    if (changed == null) return null;
    final changedName = (changed['name'] ?? '').toString().trim();
    if (changedName.isEmpty) return null;
    final changedPhrase = SlovakOutfitInstrumental.accusative(changedName);
    return 'Zvolil by som $changedPhrase — z dostupných možností mi k '
        'tomuto outfitu dáva najväčší zmysel.';
  }
'''
s = s[:start] + new_func + s[end:]
s = replace_once(
    s,
    '''      final lower = message.text.toLowerCase();
      final looksLikePartialSwap =
          lower.contains('vymenil som') ||
          lower.contains('prehodil som') ||
          lower.contains('dal som ti');
''',
    '''      final lower = message.text.toLowerCase();
      final looksLikePartialSwap =
          (message.outfitUpdateSlot?.isNotEmpty ?? false) ||
          lower.contains('vymenil som') ||
          lower.contains('prehodil som') ||
          lower.contains('dal som ti');
''',
    "structural partial swap reconstruction",
)
s = replace_once(
    s,
    '''      if (currentOutfit.isNotEmpty) 'currentOutfit': currentOutfit,
      if (lat != null) 'latitude': lat,
''',
    '''      if (currentOutfit.isNotEmpty) ...{
        'currentOutfit': currentOutfit,
        'currentOutfitDecision': <String, dynamic>{
          'recommendedByStylist': true,
          'usedCompromise': _currentOutfitUsedCompromise,
          if (_currentOutfitDecisionRationale.isNotEmpty)
            'rationale': _currentOutfitDecisionRationale,
        },
      },
      if (lat != null) 'latitude': lat,
''',
    "client recommendation metadata",
)
write(path, s)

# 9) Regression tests.
path = "test/brain_v1_v2_offline_bundle_test.dart"
s = read(path)
insert = r'''
  test('Brain owns outfit edit scope while engine keeps one-slot and layer invariants', () {
    final prompts = _read('functions/stylist/chat_prompts.js');
    final server = _read('functions/index.js');
    final screen = _read('lib/screens/stylist_chat_screen.dart');
    final service = _read('lib/Services/stylist_chat_outfit_service.dart');
    final native = _read('lib/domain/wardrobe_v2/native_outfit_engine_v2.dart');

    expect(prompts, contains('outfitDirective'));
    expect(prompts, contains('scope=single_slot'));
    expect(prompts, contains('extraLayer=optional_upper_layer'));
    expect(server, contains('sanitizeStylistOutfitDirective'));
    expect(screen, contains('_swapRequestForTurn(response, userText)'));
    expect(screen, contains('brain_locked_swap'));
    expect(screen, contains('outfitUpdateSlot'));
    expect(service, contains('lockedSelection: true'));
    expect(service, contains("presentationMode: 'focused_item'"));
    expect(native, contains('optionalUpperLayerRequested'));
    expect(native, contains('user_requested_backup_layer'));
  });

  test('Stylist has one shared thermal target instead of a chat-only duplicate', () {
    final service = _read('lib/Services/stylist_chat_outfit_service.dart');
    final policy = _read(
      'lib/domain/wardrobe_v2/outfit_suitability_policy_v2.dart',
    );

    expect(
      service,
      contains('OutfitSuitabilityPolicyV2.targetMeanWarmth(weather.tempC)'),
    );
    expect(service, isNot(contains('weather.tempC <= 14 ? 6.0')));
    expect(policy, contains('static double targetMeanWarmth'));
  });

  test('frozen explanation receives user intent and presentation mode without changing selection', () {
    final authority = _read('functions/stylist/frozen_stylist_authority_v1.js');
    final brain = _read('functions/stylist/conversation_brain_v1.js');

    expect(authority, contains('locked_selection'));
    expect(authority, contains('presentationMode'));
    expect(authority, contains('userIntentContext'));
    expect(brain, contains('focused_item'));
    expect(brain, contains('concise_full'));
    expect(brain, contains('Samotné „idem do mesta“ NIE JE prechádzka'));
  });
'''
pos = s.rfind("\n}")
if pos < 0:
    raise RuntimeError("test file closing brace missing")
s = s[:pos] + insert + s[pos:]
write(path, s)

path = "functions/stylist/frozen_stylist_authority_v1.test.js"
s = read(path)
append = r'''

test("locked selection request preserves presentation semantics without opening candidate choice", () => {
  const raw = request();
  raw.decisionMode = "locked_selection";
  raw.presentationMode = "focused_item";
  raw.focusSlot = "bottom";
  raw.userRequest = "ktoré kraťasy si mám dať?";
  raw.resolvedContext.userIntentContext = "idem večer do mesta";
  raw.frozenCandidates[0].presentationItems[1].slot = "bottom";
  const normalized = normalizeRequest(raw, owned);
  assert.equal(normalized.decisionMode, "locked_selection");
  assert.equal(normalized.presentationMode, "focused_item");
  assert.equal(normalized.focusSlot, "bottom");
  assert.equal(normalized.userRequest, "ktoré kraťasy si mám dať?");
  assert.equal(normalized.resolvedContext.userIntentContext, "idem večer do mesta");
  assert.equal(normalized.frozenCandidates[0].presentationItems[1].slot, "bottom");
});
'''
if append.strip() not in s:
    s = s.rstrip() + append + "\n"
write(path, s)

print("Natural Stylist architecture patch applied.")
