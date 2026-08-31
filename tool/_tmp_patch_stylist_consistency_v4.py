from pathlib import Path


def read(path):
    return Path(path).read_text(encoding='utf-8')


def write(path, text):
    Path(path).write_text(text, encoding='utf-8')


def replace_once(path, old, new):
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected 1 occurrence, got {count}: {old[:100]!r}')
    write(path, text.replace(old, new, 1))


# 1) Generic movement to a place is NOT walking activity evidence.
path = 'lib/utils/stylist_semantic_activity.dart'
replace_once(path, "static const String runtimeVersion = 'brain_v1_semantic_activity_v6';", "static const String runtimeVersion = 'brain_v1_semantic_activity_v7';")
replace_once(
    path,
    """    final walkingMovement = _has(\n      text,\n      r'\\b(?:prechadz\\w*|chod\\w*|popozer\\w*|pozriet\\w*|pozer\\w*|idem\\w*|ideme\\w*|ist\\w*|pojd\\w*|vyraz\\w*)\\b',\n    );\n    final explicitForestPath = _has(\n      text,\n      r'\\b(?:do|v|po)\\s+les\\w*\\b',\n    );\n    final cityWalkEvidence = cityPlaceIndex >= 0 && walkingMovement;\n    final natureWalkEvidence =\n        naturePlaceIndex >= 0 && (explicitForestPath || walkingMovement);\n""",
    """    // A destination verb (idem/ideme/ísť/pôjdeme) says WHERE the user is\n    // going, not HOW they will move there. Only explicit walking/sightseeing\n    // language may create a *_walk activity. This prevents generic city or\n    // forest outings from being rewritten as a made-up walk.\n    final explicitWalkingMovement = _has(\n      text,\n      r'\\b(?:prechadz\\w*|prej\\w*\\s+sa|krac\\w*|popozer\\w*|sightseeing\\w*|peso)\\b',\n    );\n    final cityWalkEvidence = cityPlaceIndex >= 0 && explicitWalkingMovement;\n    final natureWalkEvidence = naturePlaceIndex >= 0 && explicitWalkingMovement;\n""",
)
replace_once(
    path,
    """    if (cityWalkEvidence) return 'city_walk';\n    if (_has(text, r'\\bpo\\s+mete\\b') ||\n        _has(text, r'\\bpopozer\\w*\\s+mest\\w*\\b')) {\n      return 'city_walk';\n    }\n    if (natureWalkEvidence) return 'nature_walk';\n""",
    """    if (cityWalkEvidence) return 'city_walk';\n    // Keep the known typo-tolerant sightseeing phrase, but never let bare\n    // \"idem do mesta\" become a walk.\n    if (_has(text, r'\\bpopozer\\w*\\s+po\\s+(?:mete|mest\\w*)\\b') ||\n        _has(text, r'\\bpopozer\\w*\\s+mest\\w*\\b')) {\n      return 'city_walk';\n    }\n    if (natureWalkEvidence) return 'nature_walk';\n""",
)

# 2) A known generic urban outing is enough context for a casual recommendation
# without inventing a city walk activity.
path = 'lib/models/outfit_context_state.dart'
replace_once(
    path,
    """    final genericActivity =\n        activityHint == null ||\n        (activityHint == 'travel' && !travel.transitOutfitExplicit);\n    final destinationRequired = travel.travelMentioned\n""",
    """    final genericActivity =\n        activityHint == null ||\n        (activityHint == 'travel' && !travel.transitOutfitExplicit);\n    final genericUrbanOutingSufficient = _genericUrbanOutingSufficient(\n      conversation,\n    );\n    final destinationRequired = travel.travelMentioned\n""",
)
replace_once(
    path,
    """    } else if (remote && genericActivity) {\n      result.add('activity');\n    }\n""",
    """    } else if (\n      remote &&\n      genericActivity &&\n      !genericUrbanOutingSufficient\n    ) {\n      result.add('activity');\n    }\n""",
)
replace_once(
    path,
    """  static bool _isMultiDay(String value) => RegExp(\n""",
    """  static bool _genericUrbanOutingSufficient(String value) {\n    final text = StylistSemanticActivity.normalize(value);\n    // \"idem do mesta/centra\" is enough to style a generic urban outing, but\n    // it is deliberately NOT evidence of walking, dinner, a date, etc.\n    return RegExp(\n      r'\\b(?:do|v|na)\\s+(?:mest\\w*|centr\\w*)\\b',\n      caseSensitive: false,\n    ).hasMatch(text);\n  }\n\n  static bool _isMultiDay(String value) => RegExp(\n""",
)

# 3) Questions that ask WHICH garment to wear are single-slot recommendations,
# not whole-outfit regeneration. Explanatory questions remain non-swap.
path = 'lib/utils/stylist_swap_request.dart'
replace_once(
    path,
    """    final hasActionCue = _hasActionCue(norm);\n    if (_asksAboutExistingChoice(norm) && !hasActionCue) return null;\n""",
    """    final selectionQuestion = _selectionQuestion(norm);\n    if (selectionQuestion != null) return selectionQuestion;\n\n    final hasActionCue = _hasActionCue(norm);\n    if (_asksAboutExistingChoice(norm) && !hasActionCue) return null;\n""",
)
replace_once(
    path,
    """  static StylistSwapSlot? _singleMentionedSlot({\n""",
    """  static StylistSwapRequest? _selectionQuestion(String norm) {\n    final asksWhatToWear = RegExp(\n      r'\\b(?:ktor\\w*|ak\\w*|co)\\b.*\\b(?:si\\s+mam|mam\\s+si|mam)\\b.*\\b(?:dat|obliect|obut|vybrat)\\b',\n    ).hasMatch(norm);\n    if (!asksWhatToWear) return null;\n\n    final mentionsTop =\n        _containsAny(norm, _topWords) || RegExp(r'\\btop\\b').hasMatch(norm);\n    final mentionsBottom = _containsAny(norm, _bottomWords);\n    final mentionsShoes = _containsAny(norm, _shoeWords);\n    final mentionsOuter = _containsAny(norm, _outerWords);\n    final slot = _singleMentionedSlot(\n      top: mentionsTop,\n      bottom: mentionsBottom,\n      shoes: mentionsShoes,\n      outerwear: mentionsOuter,\n    );\n    if (slot == null) return null;\n\n    return StylistSwapRequest(\n      slot: slot,\n      bottomFamily:\n          slot == StylistSwapSlot.bottom ? StylistBottomRequest.parse(norm) : null,\n      shoeFamily:\n          slot == StylistSwapSlot.shoes ? _shoeFamilyFromText(norm) : null,\n    );\n  }\n\n  static StylistSwapSlot? _singleMentionedSlot({\n""",
)

# 4) Explicit one-slot swaps use structural/physical/full-outfit suitability.
# Item-level occasion tags are too strict for cross-family replacements and can
# hide perfectly valid owned alternatives before they are even scored.
path = 'lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart'
replace_once(
    path,
    """    final candidates = wardrobe\n        .where((x) => x.itemId != itemId)\n""",
    """    final source = wardrobe.toList(growable: false);\n    final candidates = source\n        .where((x) => x.itemId != itemId)\n""",
)
replace_once(
    path,
    """            minimumFormality: context.minimumFormality,\n            requiredOccasions: context.requiredOccasions,\n            requiredFunctions: target.item.outfitFunctions.toSet().intersection(\n              context.requiredFunctions,\n            ),\n            remainingOutfit: remaining,\n""",
    """            minimumFormality: context.minimumFormality,\n            // Do not reject a user-requested replacement solely because one\n            // item lacks an exact occasion/function tag. The completed outfit\n            // is evaluated below with physical + functional + suitability\n            // rules, which is the correct global authority for a swap.\n            requiredOccasions: const <String>{},\n            requiredFunctions: const <String>{},\n            remainingOutfit: remaining,\n""",
)
replace_once(
    path,
    """        if (next.validate().isNotEmpty) continue;\n        final score = V2FlexibleOutfitScorer.score(\n          next,\n          context,\n        ).values.fold(0.0, (a, b) => a + b);\n        if (score > bestScore) {\n""",
    """        if (next.validate().isNotEmpty) continue;\n        if (OutfitSuitabilityPolicyV2.isPhysicallyUnsuitable(\n          candidate.item,\n          tempC: OutfitSuitabilityPolicyV2.effectiveTempC(\n            tempC: context.tempC,\n            feelsLikeC: context.feelsLikeC,\n          ),\n          seasonKey: context.seasonKey,\n          isRainy: context.isRainy || context.weatherProtectionRequired,\n          activityType: context.activityType,\n        )) {\n          continue;\n        }\n        final functional = FunctionalSuitabilityEvaluatorV1.assessCandidate(\n          outfit: next,\n          source: source,\n          requirements: ActivityFunctionalRequirementsV1(\n            activityType: context.activityType,\n            outdoor: context.outdoor,\n            isRainy: context.isRainy || context.weatherProtectionRequired,\n            wetGroundRisk: context.wetGroundRisk,\n            minimumFormality: context.decisionFormalityFloor,\n            durationMinutes: context.activityDurationMinutes,\n            terrain: context.terrain,\n            tempC: OutfitSuitabilityPolicyV2.effectiveTempC(\n              tempC: context.tempC,\n              feelsLikeC: context.feelsLikeC,\n            ),\n          ),\n        );\n        if (!functional.selectable) continue;\n        final breakdown = V2FlexibleOutfitScorer.score(next, context);\n        breakdown['functionalCapability'] = functional.scoreAdjustment;\n        final score = breakdown.values.fold(0.0, (a, b) => a + b);\n        if (score > bestScore) {\n""",
)

# 5) UI state: keep the full outfit internally, but a one-slot request displays
# only the newly selected item. Enforce the one-slot delta instead of silently
# accepting a multi-item change.
path = 'lib/screens/stylist_chat_screen.dart'
replace_once(
    path,
    """  Set<String> _lastOutfitItemIds = const {};\n  Map<String, dynamic>? _cachedWeatherContext;\n""",
    """  Set<String> _lastOutfitItemIds = const {};\n  List<Map<String, dynamic>> _currentOutfitItems = const <Map<String, dynamic>>[];\n  Map<String, dynamic>? _cachedWeatherContext;\n""",
)
replace_once(
    path,
    """    if (_conversationAlreadyHasOutfitCards() && swapRequest != null) {\n      final event = _eventFromConversation(\n""",
    """    if (_conversationAlreadyHasOutfitCards() && swapRequest != null) {\n      // A reopened chat may have outfit cards while the ephemeral ID cache is\n      // empty. Rebuild the authoritative current outfit before a one-slot swap.\n      if (_lastOutfitItemIds.isEmpty) {\n        final restored = _resolvedCurrentOutfitItems();\n        final restoredIds = restored\n            .map((item) => (item['id'] ?? '').toString().trim())\n            .where((id) => id.isNotEmpty)\n            .toSet();\n        if (restoredIds.isNotEmpty) {\n          _currentOutfitItems = restored;\n          _lastOutfitItemIds = restoredIds;\n        }\n      }\n      final event = _eventFromConversation(\n""",
)
old = """    final previousIds = _lastOutfitItemIds;\n    final suggestedItems = _sortStylistSuggestedItems(\n      await _stylistChatOutfitService.suggestedItemsFromFlexibleOutfit(\n        outfitResult.flexibleOutfit,\n      ),\n    );\n    _lastOutfitItemIds = suggestedItems\n        .map((e) => (e['id'] ?? '').toString().trim())\n        .where((id) => id.isNotEmpty)\n        .toSet();\n\n    // Keď si používateľ výslovne vypýtal výmenu jedného kusu, nechceme znova\n    // opísať CELÝ outfit tými istými vetami (pôsobí to ako copy-paste). Dáme\n    // krátku, vecnú odpoveď zameranú na zmenený kúsok. Ak sa kvôli zladeniu\n    // muselo zmeniť viac kúskov, krátko to vysvetlíme (nie celý opis).\n    final swapSlot =\n        requestedSwap?.slot ??\n        (requestedBottomFamily != null ? StylistSwapSlot.bottom : null);\n    if (swapSlot != null) {\n      final keptCount = previousIds.intersection(_lastOutfitItemIds).length;\n      final onlyOneChanged =\n          previousIds.isNotEmpty && keptCount >= previousIds.length - 1;\n      final shortReply = onlyOneChanged\n          ? _shortSwapReply(suggestedItems: suggestedItems, slot: swapSlot)\n          : _multiChangeSwapReply(\n              suggestedItems: suggestedItems,\n              slot: swapSlot,\n            );\n      if (shortReply != null) {\n        debugPrint(\n          'STYLIST CHAT reply_source=local_swap_${swapSlot.name} '\n          'onlyOneChanged=$onlyOneChanged',\n        );\n        setState(() {\n          _messages.add(\n            StylistChatMessage(\n              text: shortReply,\n              isUser: false,\n              suggestedItems: suggestedItems,\n            ),\n          );\n          _isSending = false;\n        });\n        _scrollToBottom();\n        return;\n      }\n    }\n"""
new = """    final previousIds = _lastOutfitItemIds;\n    final suggestedItems = _sortStylistSuggestedItems(\n      await _stylistChatOutfitService.suggestedItemsFromFlexibleOutfit(\n        outfitResult.flexibleOutfit,\n      ),\n    );\n    final nextIds = suggestedItems\n        .map((e) => (e['id'] ?? '').toString().trim())\n        .where((id) => id.isNotEmpty)\n        .toSet();\n\n    if (requestedSwap != null && previousIds.isNotEmpty) {\n      final added = nextIds.difference(previousIds);\n      final removed = previousIds.difference(nextIds);\n      final strictSingleSlotDelta =\n          nextIds.length == previousIds.length &&\n          added.length == 1 &&\n          removed.length == 1;\n      if (!strictSingleSlotDelta) {\n        debugPrint(\n          'STYLIST CHAT explicit_swap_rejected reason=multi_item_delta '\n          'added=$added removed=$removed',\n        );\n        setState(() {\n          _messages.add(\n            const StylistChatMessage(\n              text:\n                  'Túto výmenu nechcem spraviť tak, že ti potichu zmením aj ďalšie kúsky. Skúsim radšej inú náhradu len za ten jeden kus.',\n              isUser: false,\n            ),\n          );\n          _isSending = false;\n        });\n        _scrollToBottom();\n        return;\n      }\n    }\n\n    _lastOutfitItemIds = nextIds;\n    _currentOutfitItems = List<Map<String, dynamic>>.unmodifiable(\n      suggestedItems.map((item) => Map<String, dynamic>.from(item)),\n    );\n\n    // An explicit one-slot request is a true local edit: every other item stays\n    // frozen internally, and the UI shows only the item the user asked about.\n    if (requestedSwap != null) {\n      final swapSlot = requestedSwap.slot;\n      const slotOrderFor = <StylistSwapSlot, int>{\n        StylistSwapSlot.top: 0,\n        StylistSwapSlot.outerwear: 1,\n        StylistSwapSlot.bottom: 2,\n        StylistSwapSlot.shoes: 3,\n      };\n      final swapDisplayItems = suggestedItems\n          .where((item) => _stylistWearSlotOrder(item) == slotOrderFor[swapSlot])\n          .toList(growable: false);\n      final shortReply = _shortSwapReply(\n        suggestedItems: suggestedItems,\n        slot: swapSlot,\n      );\n      if (shortReply != null && swapDisplayItems.isNotEmpty) {\n        debugPrint(\n          'STYLIST CHAT reply_source=local_swap_${swapSlot.name} '\n          'display_items=${swapDisplayItems.length}',\n        );\n        setState(() {\n          _messages.add(\n            StylistChatMessage(\n              text: shortReply,\n              isUser: false,\n              suggestedItems: swapDisplayItems,\n            ),\n          );\n          _isSending = false;\n        });\n        _scrollToBottom();\n        return;\n      }\n    }\n"""
replace_once(path, old, new)

# Replace current outfit context source with a full internal/reconstructed state.
replace_once(
    path,
    """  List<Map<String, String>> _currentDisplayedOutfitContext() {\n    String valueFor(Map<String, dynamic> item, List<String> keys) {\n""",
    """  List<Map<String, dynamic>> _resolvedCurrentOutfitItems() {\n    if (_currentOutfitItems.isNotEmpty) {\n      return _currentOutfitItems\n          .map((item) => Map<String, dynamic>.from(item))\n          .toList(growable: false);\n    }\n\n    var current = <Map<String, dynamic>>[];\n    for (final message in _messages) {\n      if (message.isUser || message.suggestedItems.isEmpty) continue;\n      final incoming = _sortStylistSuggestedItems(\n        message.suggestedItems\n            .map((item) => Map<String, dynamic>.from(item))\n            .toList(growable: false),\n      );\n      if (incoming.length >= 2) {\n        current = incoming;\n        continue;\n      }\n      if (current.isEmpty || incoming.length != 1) continue;\n      final lower = message.text.toLowerCase();\n      final looksLikePartialSwap =\n          lower.contains('vymenil som') ||\n          lower.contains('prehodil som') ||\n          lower.contains('dal som ti');\n      if (!looksLikePartialSwap) continue;\n      final replacement = incoming.single;\n      final slot = _stylistWearSlotOrder(replacement);\n      final index = current.indexWhere(\n        (item) => _stylistWearSlotOrder(item) == slot,\n      );\n      if (index >= 0) {\n        current[index] = replacement;\n      } else {\n        current.add(replacement);\n      }\n      current = _sortStylistSuggestedItems(current);\n    }\n    return current;\n  }\n\n  List<Map<String, String>> _currentDisplayedOutfitContext() {\n    String valueFor(Map<String, dynamic> item, List<String> keys) {\n""",
)
replace_once(
    path,
    """    for (final message in _messages.reversed) {\n      if (message.isUser || message.suggestedItems.isEmpty) continue;\n      return message.suggestedItems\n          .take(6)\n          .map((item) {\n""",
    """    final current = _resolvedCurrentOutfitItems();\n    if (current.isNotEmpty) {\n      return current\n          .take(6)\n          .map((item) {\n""",
)
replace_once(
    path,
    """          .where((item) => item.isNotEmpty)\n          .toList(growable: false);\n    }\n    return const <Map<String, String>>[];\n  }\n""",
    """          .where((item) => item.isNotEmpty)\n          .toList(growable: false);\n    }\n    return const <Map<String, String>>[];\n  }\n""",
)

# 6) Conversation and frozen-explanation behavior: stylist owns the choice,
# generic destinations are not activities, and the assistant cannot undermine
# its own recommendation without authoritative compromise evidence.
path = 'functions/stylist/chat_prompts.js'
replace_once(
    path,
    """  `- Ak Client context obsahuje currentOutfit, je to autoritatívny outfit PRÁVE ZOBRAZENÝ používateľovi. Pri follow-upe typu „prečo?“, „je to vhodné?“, „čo na tom nie je ideálne?“ NIKDY netvrď, že outfit alebo konkrétne kúsky nevidíš; odpovedaj o currentOutfit.\\n` +\n  `- Keď vysvetľuješ alebo odporúčaš konkrétny outfit a Weather context je dostupný, prirodzene spomeň iba relevantné počasie (najmä kanonickú teplotu a dážď/vietor, ak menia voľbu). Nevymýšľaj inú teplotu.\\n` +\n""",
    """  `- Ak Client context obsahuje currentOutfit, je to autoritatívny outfit PRÁVE ZOBRAZENÝ používateľovi. Pri follow-upe typu „prečo?“, „je to vhodné?“, „čo na tom nie je ideálne?“ NIKDY netvrď, že outfit alebo konkrétne kúsky nevidíš; odpovedaj o currentOutfit.\\n` +\n  `- AUTORSTVO: outfit, ktorý si odporučil ty/systém stylistu, NIKDY nepripisuj používateľovi slovami „si zvolil“, „vybral si“ a pod., pokiaľ ho používateľ naozaj explicitne nevybral. Hovor „odporúčam ti“, „vybral som ti“, „zvolil som“.\\n` +\n  `- KONZISTENTNOSŤ: keď je currentOutfit tvoje aktuálne odporúčanie, nesmieš ho v ďalšej odpovedi bez nového autoritatívneho faktu podkopať tvrdením, že nevybraná alternatíva je vlastne lepšia/príjemnejšia. Pri „prečo rifle a nie kraťasy?“ vysvetli, prečo aktuálny výber dáva zmysel; ak user preferuje inú prioritu, môžeš ponúknuť presný swap. Za lepšiu alternatívu ju označ iba ak autoritatívny kontext explicitne hovorí, že aktuálny kus je kompromis.\\n` +\n  `- „Idem do mesta/centra/lesa“ je cieľ alebo prostredie, NIE automaticky prechádzka. city_walk/nature_walk používaj iba pri explicitnej chôdzi, prechádzke alebo sightseeing význame. Nevymýšľaj aktivitu zo slovesa „idem“.\\n` +\n  `- Keď vysvetľuješ alebo odporúčaš konkrétny outfit a Weather context je dostupný, prirodzene spomeň iba relevantné počasie (najmä kanonickú teplotu a dážď/vietor, ak menia voľbu). Nevymýšľaj inú teplotu.\\n` +\n""",
)

path = 'functions/stylist/conversation_brain_v1.js'
replace_once(
    path,
    """    \"- Pri select_candidate pomenuj iba kúsky z userFacingSelectedOutfit. Vysvetli konkrétne, prečo kombinácia funguje pre situáciu, počasie alebo dress code.\",\n    \"- Ak userFacingContext.weather obsahuje teplotu/dážď/vietor, spomeň relevantné počasie prirodzene v používateľskom vysvetlení; nepoužívaj inú teplotu.\",\n""",
    """    \"- Pri select_candidate pomenuj iba kúsky z userFacingSelectedOutfit. Vysvetli konkrétne, prečo kombinácia funguje pre situáciu, počasie alebo dress code.\",\n    \"- Toto je TVOJE odporúčanie stylistu. Nikdy nepíš používateľovi „si zvolil“, „vybral si“ ani inú formuláciu, ktorá mu pripisuje tvoju voľbu, pokiaľ payload výslovne nehovorí, že ju zvolil používateľ. Použi „odporúčam ti“, „vybral som ti“ alebo „zvolil som“.\",\n    \"- Ak userFacingContext.weather obsahuje teplotu, pri odporúčaní ju uveď explicitne aspoň raz (napr. „pri 25 °C“); dážď/vietor spomeň, keď menia voľbu. Nikdy nepoužívaj inú teplotu.\",\n    \"- Neprotireč vlastnému uzavretému výberu: ak payload neoznačuje vybraný outfit/kus ako kompromis, netvrď, že nevybraná alternatíva by bola lepšia alebo príjemnejšia. Ak kompromis existuje, smieš ho pomenovať iba podľa userFacingCompromises.\",\n""",
)

# 7) Regression tests for the global invariants.
path = 'test/brain_v1_v2_offline_bundle_test.dart'
replace_once(
    path,
    """import 'package:outfitofTheDay/utils/stylist_swap_request.dart';\n""",
    """import 'package:outfitofTheDay/utils/stylist_swap_request.dart';\nimport 'package:outfitofTheDay/utils/stylist_semantic_activity.dart';\n""",
)
replace_once(
    path,
    """    expect(prompts, contains('samotné oznámenie plánu alebo aktivity'));\n    expect(prompts, contains('Samotné sufficient grounding NIKDY neoprávňuje generate_outfit'));\n""",
    """    expect(prompts, contains('samotné oznámenie plánu alebo aktivity'));\n    expect(prompts, contains('Samotné sufficient grounding NIKDY neoprávňuje generate_outfit'));\n    expect(prompts, contains('NIKDY nepripisuj používateľovi'));\n    expect(prompts, contains('nesmieš ho v ďalšej odpovedi'));\n    expect(prompts, contains('NIE automaticky prechádzka'));\n""",
)
replace_once(
    path,
    """    expect(matrix, contains('bool allowCrossFamilySameSlot = false'));\n""",
    """    expect(matrix, contains('bool allowCrossFamilySameSlot = false'));\n    final swapScope = matrix.substring(\n      matrix.indexOf('abstract final class V2FlexibleSwapOrchestrator'),\n    );\n    expect(swapScope, contains('FunctionalSuitabilityEvaluatorV1.assessCandidate'));\n    expect(swapScope, contains('requiredOccasions: const <String>{}'));\n    expect(swapScope, isNot(contains('requiredOccasions: context.requiredOccasions')));\n    expect(screen, contains('swapDisplayItems'));\n    expect(screen, contains('_currentOutfitItems'));\n    expect(screen, contains('explicit_swap_rejected reason=multi_item_delta'));\n""",
)
replace_once(
    path,
    """    final replaceWithShorts = StylistSwapRequest.parse(\n      'vymen rifle za kratasy',\n    );\n    expect(replaceWithShorts, isNotNull);\n    expect(replaceWithShorts!.bottomFamily, BottomFamily.shorts);\n  });\n}\n""",
    """    final replaceWithShorts = StylistSwapRequest.parse(\n      'vymen rifle za kratasy',\n    );\n    expect(replaceWithShorts, isNotNull);\n    expect(replaceWithShorts!.bottomFamily, BottomFamily.shorts);\n\n    final whichShorts = StylistSwapRequest.parse('ktore kratasy si mam dat?');\n    expect(whichShorts, isNotNull);\n    expect(whichShorts!.slot, StylistSwapSlot.bottom);\n    expect(whichShorts.bottomFamily, BottomFamily.shorts);\n\n    final whichTop = StylistSwapRequest.parse('ake tricko si mam dat?');\n    expect(whichTop, isNotNull);\n    expect(whichTop!.slot, StylistSwapSlot.top);\n\n    final whichShoes = StylistSwapRequest.parse('ktore topanky si mam obut?');\n    expect(whichShoes, isNotNull);\n    expect(whichShoes!.slot, StylistSwapSlot.shoes);\n\n    expect(StylistSwapRequest.parse('preco rifle a nie kratasy?'), isNull);\n  });\n\n  test('generic destination movement is not silently relabelled as walking', () {\n    expect(StylistSemanticActivity.resolveExplicit('idem von do mesta'), isNull);\n    expect(StylistSemanticActivity.resolveExplicit('idem do lesa'), isNull);\n    expect(\n      StylistSemanticActivity.resolveExplicit('idem na prechadzku po meste'),\n      'city_walk',\n    );\n    expect(\n      StylistSemanticActivity.resolveExplicit('idem na prechadzku do lesa'),\n      'nature_walk',\n    );\n  });\n}\n""",
)

# Update semantic tests that previously encoded the now-invalid assumption that
# destination movement alone means a walk.
path = 'test/stylist_semantic_activity_test.dart'
replace_once(
    path,
    """      expect(\n        StylistSemanticActivity.resolveExplicit('ideme do lesa'),\n        'nature_walk',\n      );\n""",
    """      expect(\n        StylistSemanticActivity.resolveExplicit('ideme do lesa'),\n        isNull,\n      );\n      expect(\n        StylistSemanticActivity.resolveExplicit('ideme na prechadzku do lesa'),\n        'nature_walk',\n      );\n""",
)
replace_once(
    path,
    """    test('city-centre inflections plus movement resolve to city walk', () {\n      for (final sample in <String>[\n        'Dnes idem do centra v Žiline',\n        'budeme chodiť po centre',\n        'pôjdeme centrom mesta',\n        'ideme do mestského centra',\n      ]) {\n        expect(\n          StylistSemanticActivity.resolveExplicit(sample),\n          'city_walk',\n          reason: sample,\n        );\n      }\n    });\n""",
    """    test('city walk requires explicit walking or sightseeing semantics', () {\n      for (final sample in <String>[\n        'prechádzame sa po centre',\n        'ideme na prechádzku centrom mesta',\n        'budeme popozerať mesto',\n      ]) {\n        expect(\n          StylistSemanticActivity.resolveExplicit(sample),\n          'city_walk',\n          reason: sample,\n        );\n      }\n      for (final sample in <String>[\n        'Dnes idem do centra v Žiline',\n        'ideme do mestského centra',\n        'ahoj idem von do mesta',\n      ]) {\n        expect(\n          StylistSemanticActivity.resolveExplicit(sample),\n          isNull,\n          reason: sample,\n        );\n      }\n    });\n""",
)
replace_once(
    path,
    """  test('plain city outing uses local semantics while a real trip stays remote', () {\n    const local = 'ahoj idem von do mesta, poraď mi s outfitom';\n    expect(StylistSemanticActivity.resolveExplicit(local), 'city_walk');\n""",
    """  test('plain city outing stays casual while a real trip stays remote', () {\n    const local = 'ahoj idem von do mesta, poraď mi s outfitom';\n    expect(StylistSemanticActivity.resolveExplicit(local), isNull);\n""",
)

path = 'test/stylist_conversation_grounding_eval_test.dart'
replace_once(
    path,
    """      expect(state.activityHint, 'city_walk');\n      expect(state.unresolvedMaterialFields, isEmpty);\n""",
    """      expect(state.activityHint, isNull);\n      expect(state.unresolvedMaterialFields, isEmpty);\n""",
)
replace_once(
    path,
    """            'Nie, nejdeme do mesta, ideme do lesa.',\n        latestUserText: 'Nie, nejdeme do mesta, ideme do lesa.',\n""",
    """            'Nie, nejdeme do mesta, ideme na prechádzku do lesa.',\n        latestUserText: 'Nie, nejdeme do mesta, ideme na prechádzku do lesa.',\n""",
)
replace_once(
    path,
    """            'Nie, nejdeme do mesta, ideme do lesa. '\n            'Ostávame pri Martine asi dve hodiny.',\n""",
    """            'Nie, nejdeme do mesta, ideme na prechádzku do lesa. '\n            'Ostávame pri Martine asi dve hodiny.',\n""",
)

print('stylist consistency v4 patch applied')
