import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/utils/bottom_family_guidance.dart';
import 'package:outfitofTheDay/utils/footwear_family_guidance.dart';
import 'package:outfitofTheDay/utils/stylist_swap_request.dart';
import 'package:outfitofTheDay/utils/stylist_semantic_activity.dart';
import 'package:outfitofTheDay/utils/stylist_outfit_directive_guard.dart';
import 'package:outfitofTheDay/Services/stylist_chat_service.dart';

String _read(String path) => File(path).readAsStringSync();

String _scope(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $startMarker');
  expect(
    end,
    greaterThan(start),
    reason: 'Missing $endMarker after $startMarker',
  );
  return source.substring(start, end);
}

void main() {
  test(
    'Brain V1 client is explicit opt-in and forwards bounded raw history',
    () {
      final service = _read('lib/Services/stylist_chat_service.dart');
      final screen = _read('lib/screens/stylist_chat_screen.dart');

      expect(
        service,
        contains("static const conversationBrainVersion = 'brain_v1';"),
      );
      expect(
        service,
        contains("'conversationBrainVersion': conversationBrainVersion"),
      );
      expect(service, contains("'history': history"));
      expect(screen, contains('static const int _historyLimit = 8;'));
      expect(screen, contains('_buildHistoryForBackend()'));
      expect(screen, contains('_runHybridOutfitGeneration('));
    },
  );

  test('web research stays public-only and authoritative app context wins', () {
    final web = _read('functions/stylist/openai_responses_web_search_v1.js');
    final safePublicScope = _scope(
      web,
      'function safePublicResearchContext(raw)',
      'function extractPublicResearchContextFromResponse(json)',
    );

    expect(web, contains('tools: [{type: "web_search"'));
    expect(web, contains('tool_choice: "auto"'));
    expect(web, contains('max_tool_calls: 3'));
    expect(
      web,
      contains(
        'const contentType = role === "assistant" ? "output_text" : "input_text";',
      ),
    );
    expect(web, contains('const publicContext = callCount > 0 ?'));

    for (final privateKey in <String>[
      'locationLabel',
      'gps',
      'wardrobe',
      'preference',
    ]) {
      expect(
        safePublicScope.toLowerCase(),
        isNot(contains(privateKey.toLowerCase())),
        reason:
            'Public research allowlist must not gain $privateKey authority.',
      );
    }

    final merged = StylistChatService.resolvedEventContextFromData(
      <String, dynamic>{
        'eventContext': <String, dynamic>{
          'performer': 'User performer',
          'eventStartHour': 20,
          'dressCode': <String, dynamic>{'id': 'user_code'},
        },
        'webResearch': <String, dynamic>{
          'used': true,
          'publicContext': <String, dynamic>{
            'performer': 'Web performer',
            'eventStartHour': 19,
            'eventEndHour': 23,
            'dressCode': <String, dynamic>{'id': 'web_code'},
          },
        },
      },
    );

    expect(merged, isNotNull);
    expect(merged!['performer'], 'User performer');
    expect(merged['eventStartHour'], 20);
    expect(merged['eventEndHour'], 23);
    expect((merged['dressCode'] as Map)['id'], 'user_code');
  });

  test(
    'active V2 outfit path freezes candidates and fails closed by exact ID',
    () {
      final outfitService = _read(
        'lib/Services/stylist_chat_outfit_service.dart',
      );
      final activeGenerate = _scope(
        outfitService,
        '  Future<StylistChatOutfitResult?> generateForEvent({',
        '  static bool _matchesRequestedBottomV2(',
      );
      final frozenClient = _read(
        'lib/Services/stylist_frozen_candidate_decision_service.dart',
      );
      final frozenResolve = _scope(
        frozenClient,
        '  Future<StylistFrozenCandidateDecisionResultV1> resolve({',
        '  static Map<String, dynamic> _candidatePayload(',
      );

      expect(
        activeGenerate,
        contains('NativeWardrobeV2Runtime.resolveAll(wardrobe)'),
      );
      expect(activeGenerate, contains('V2FlexibleCandidateMatrix.generate('));
      expect(
        activeGenerate,
        contains('StylistFrozenCandidateDecisionServiceV1()'),
      );
      expect(activeGenerate, contains('.resolve('));
      expect(
        activeGenerate,
        contains('candidate.candidateId == selectedId'),
        reason:
            'The accepted outfit must be resolved by exact frozen candidateId.',
      );
      expect(
        activeGenerate,
        contains('StylistFrozenDecisionRejectedExceptionV1('),
      );
      expect(activeGenerate, isNot(contains('matrix.first')));
      expect(activeGenerate, isNot(contains('generated.first')));

      expect(
        frozenClient,
        contains(".httpsCallable('resolveStylistFrozenCandidatesV1')"),
      );
      expect(frozenClient, contains("'frozenCandidates': candidates"));
      expect(frozenResolve, contains('rejectAllFallback'));
      expect(frozenResolve, isNot(contains('candidates.first')));
    },
  );

  test('server validator owns safety and Brain cannot replace frozen selection', () {
    final authority = _read('functions/stylist/frozen_stylist_authority_v1.js');

    expect(
      authority,
      contains('const owned = itemIds.every((id) => ownedItemIds.has(id));'),
    );
    expect(
      authority,
      contains(
        'const eligible = deterministicPassed && owned && violationCodes.length === 0',
      ),
    );
    expect(
      authority,
      contains(
        'candidates.find((candidate) => candidate.candidateId === selectedCandidateId)',
      ),
    );
    expect(authority, contains('selected_candidate_outside_frozen_set'));
    expect(authority, contains('selected_candidate_failed_hard_constraints'));
    expect(
      authority,
      contains(
        'Never transmit candidate or item IDs to a user-facing explanation model.',
      ),
    );
    expect(
      authority,
      contains(
        'const explanationClient = useBrain ? brainExplanationClient : legacyExplanationClient;',
      ),
      reason:
          'Brain V1 must remain opt-in while old clients retain legacy explanation transport.',
    );
  });

  test(
    'model roles and progress UX preserve the frozen authority boundary',
    () {
      final registry = _read('functions/stylist/ai_model_registry.js');
      final progress = _read('lib/models/stylist_chat_progress.dart');
      final screen = _read('lib/screens/stylist_chat_screen.dart');
      final outfitService = _read(
        'lib/Services/stylist_chat_outfit_service.dart',
      );

      expect(registry, contains('webModelId: "gpt-5.6-terra"'));
      expect(registry, contains('webMaxTokens: 900'));
      expect(registry, contains('searchContextSize: "low"'));
      expect(registry, contains('reasoningEffort: "low"'));
      expect(registry, contains('id: "gpt-5.4-mini"'));

      for (final phase in <String>[
        'resolvingContext',
        'checkingWeather',
        'thinkingWithContext',
        'analyzingWardrobe',
        'buildingOutfit',
        'finalizing',
      ]) {
        expect(progress, contains(phase));
      }
      expect(screen, contains('onProgress: _setSendingProgress'));
      expect(
        outfitService,
        contains('StylistChatProgressCallback? onProgress'),
      );
      expect(
        progress.toLowerCase(),
        isNot(contains('candidateid')),
        reason: 'Progress transport must never become a selection authority.',
      );
    },
  );
  test(
    'conversation plan statements cannot silently authorize outfit generation',
    () {
      final signals = _read('lib/utils/stylist_conversation_signals.dart');
      final screen = _read('lib/screens/stylist_chat_screen.dart');
      final prompts = _read('functions/stylist/chat_prompts.js');
      final server = _read('functions/index.js');

      expect(signals, contains('isContextOnlyPlanStatement'));
      expect(signals, contains('ideme'));
      expect(signals, contains('porad'));
      expect(
        screen,
        contains('generation_suppressed reason=context_only_plan'),
      );
      expect(screen, contains("'currentOutfit': currentOutfit"));
      expect(server, contains('clientContext.currentOutfit'));
      expect(
        server,
        contains(r'currentOutfit=${JSON.stringify(currentOutfit)}'),
      );
      expect(prompts, contains('samotné oznámenie plánu alebo aktivity'));
      expect(
        prompts,
        contains(
          'Samotné sufficient grounding NIKDY neoprávňuje generate_outfit',
        ),
      );
      expect(prompts, contains('NIKDY nepripisuj používateľovi'));
      expect(prompts, contains('nesmieš ho v ďalšej odpovedi'));
      expect(prompts, contains('NIE automaticky prechádzka'));
    },
  );

  test('manual chat regressions keep local weather and quality guardrails', () {
    final screen = _read('lib/screens/stylist_chat_screen.dart');
    final weatherTip = _read('lib/utils/stylist_weather_tip.dart');
    final policy = _read(
      'lib/domain/wardrobe_v2/outfit_suitability_policy_v2.dart',
    );
    final matrix = _read(
      'lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart',
    );

    expect(screen, contains("lower.contains('počas')"));
    expect(screen, contains('requestedSwap: swapRequest'));
    final service = _read('lib/Services/stylist_chat_outfit_service.dart');
    final adapters = _read('lib/domain/wardrobe_v2/wardrobe_v2_adapters.dart');
    expect(service, contains('allowCrossFamilySameSlot: true'));
    expect(
      service,
      isNot(contains('allowCrossFamilySameSlot: requestedSwap.bottomFamily')),
      reason: 'Explicit single-slot swaps must be global, not bottom-only.',
    );
    expect(matrix, contains('bool allowCrossFamilySameSlot = false'));
    final swapScope = matrix.substring(
      matrix.indexOf('abstract final class V2FlexibleSwapOrchestrator'),
    );
    expect(
      swapScope,
      contains('FunctionalSuitabilityEvaluatorV1.assessCandidate'),
    );
    expect(swapScope, contains('requiredOccasions: const <String>{}'));
    expect(
      swapScope,
      isNot(contains('requiredOccasions: context.requiredOccasions')),
    );
    expect(screen, contains('swapDisplayItems'));
    expect(screen, contains('_currentOutfitItems'));
    expect(screen, contains('explicit_swap_rejected reason=multi_item_delta'));
    expect(
      adapters,
      contains('candidate.canonicalFamily != replaced.canonicalFamily &&'),
    );
    expect(adapters, contains('!allowCrossFamilySameSlot'));
    expect(weatherTip, contains('snapshot.mainChipTempC'));
    expect(policy, contains('tempC >= 28'));
    expect(policy, contains("type.contains('jean') || type.contains('denim')"));
    expect(matrix, contains('repeatedNonNeutralPrimary'));
    expect(
      matrix,
      isNot(contains("'primaryColorHarmony': repeatedPrimary ? 0.8 : 0")),
    );
  });

  test('swap parser keeps rejection polarity global across clothing slots', () {
    final hotJeans = StylistSwapRequest.parse('v rifliach mi bude teplo');
    expect(hotJeans, isNotNull);
    expect(hotJeans!.slot, StylistSwapSlot.bottom);
    expect(hotJeans.bottomFamily, isNull);
    expect(hotJeans.thermalPreference, StylistSwapThermalPreference.cooler);

    expect(StylistSwapRequest.parse('Nebude mi v rifliach teplo?'), isNull);

    final shorts = StylistSwapRequest.parse('nechcem rifle, daj kratasy');
    expect(shorts, isNotNull);
    expect(shorts!.slot, StylistSwapSlot.bottom);
    expect(shorts.bottomFamily, BottomFamily.shorts);

    final jeans = StylistSwapRequest.parse('kratasy nechcem, daj rifle');
    expect(jeans, isNotNull);
    expect(jeans!.bottomFamily, BottomFamily.jeans);

    final top = StylistSwapRequest.parse('toto tricko mi nesedi');
    expect(top, isNotNull);
    expect(top!.slot, StylistSwapSlot.top);

    final shoes = StylistSwapRequest.parse('tieto topanky ma tlacia');
    expect(shoes, isNotNull);
    expect(shoes!.slot, StylistSwapSlot.shoes);
    expect(shoes.shoeFamily, isNull);

    final boots = StylistSwapRequest.parse('tenisky ma tlacia, daj cizmy');
    expect(boots, isNotNull);
    expect(boots!.slot, StylistSwapSlot.shoes);
    expect(boots.shoeFamily, FootwearFamily.boots);

    final outer = StylistSwapRequest.parse('v tej bunde mi bude teplo');
    expect(outer, isNotNull);
    expect(outer!.slot, StylistSwapSlot.outerwear);
    expect(outer.thermalPreference, StylistSwapThermalPreference.cooler);

    final coldTop = StylistSwapRequest.parse('v tomto tricku mi bude zima');
    expect(coldTop, isNotNull);
    expect(coldTop!.slot, StylistSwapSlot.top);
    expect(coldTop.thermalPreference, StylistSwapThermalPreference.warmer);

    final directJeans = StylistSwapRequest.parse('daj mi rifle');
    expect(directJeans, isNotNull);
    expect(directJeans!.bottomFamily, BottomFamily.jeans);

    final bareShorts = StylistSwapRequest.parse('kratasy');
    expect(bareShorts, isNotNull);
    expect(bareShorts!.bottomFamily, BottomFamily.shorts);

    final replaceJeans = StylistSwapRequest.parse('vymen mi rifle');
    expect(replaceJeans, isNotNull);
    expect(replaceJeans!.slot, StylistSwapSlot.bottom);
    expect(replaceJeans.bottomFamily, isNull);

    final replaceWithShorts = StylistSwapRequest.parse(
      'vymen rifle za kratasy',
    );
    expect(replaceWithShorts, isNotNull);
    expect(replaceWithShorts!.bottomFamily, BottomFamily.shorts);

    final whichShorts = StylistSwapRequest.parse('ktore kratasy si mam dat?');
    expect(whichShorts, isNotNull);
    expect(whichShorts!.slot, StylistSwapSlot.bottom);
    expect(whichShorts.bottomFamily, BottomFamily.shorts);

    final whichTop = StylistSwapRequest.parse('ake tricko si mam dat?');
    expect(whichTop, isNotNull);
    expect(whichTop!.slot, StylistSwapSlot.top);

    final whichShoes = StylistSwapRequest.parse('ktore topanky si mam obut?');
    expect(whichShoes, isNotNull);
    expect(whichShoes!.slot, StylistSwapSlot.shoes);

    expect(StylistSwapRequest.parse('preco rifle a nie kratasy?'), isNull);
  });

  test(
    'generic destination movement is not silently relabelled as walking',
    () {
      expect(
        StylistSemanticActivity.resolveExplicit('idem von do mesta'),
        isNull,
      );
      expect(StylistSemanticActivity.resolveExplicit('idem do lesa'), isNull);
      expect(
        StylistSemanticActivity.resolveExplicit('idem na prechadzku po meste'),
        'city_walk',
      );
      expect(
        StylistSemanticActivity.resolveExplicit('idem na prechadzku do lesa'),
        'nature_walk',
      );
    },
  );
  test(
    'Brain owns canonical atomic outfit edits while legacy swap stays fallback-only',
    () {
      final prompts = _read('functions/stylist/chat_prompts.js');
      final server = _read('functions/index.js');
      final screen = _read('lib/screens/stylist_chat_screen.dart');
      final service = _read('lib/Services/stylist_chat_outfit_service.dart');
      final plan = _read('lib/domain/wardrobe_v2/outfit_edit_plan_v1.dart');
      final executor = _read(
        'lib/domain/wardrobe_v2/outfit_edit_executor_v1.dart',
      );
      final delta = _read('lib/domain/wardrobe_v2/outfit_edit_delta_v1.dart');
      final frozenAuthority = _read(
        'functions/stylist/frozen_stylist_authority_v1.js',
      );
      final native = _read(
        'lib/domain/wardrobe_v2/native_outfit_engine_v2.dart',
      );

      expect(prompts, contains('outfitEditPlan'));
      expect(prompts, contains('outfit_edit_plan_v1'));
      expect(prompts, contains('Všetky zmeny jedného user turnu'));
      expect(prompts, contains('constraints.color=red'));
      expect(prompts, contains('add bottom constraints.family=shorts'));
      expect(prompts, contains('nikdy skin_base/termoprádlo'));
      expect(server, contains('sanitizeOutfitEditPlanV1'));
      expect(screen, contains('StylistOutfitEditRoutingV1.resolve'));
      expect(screen, contains('final swapRequest = editRouting.legacySwap'));
      expect(plan, contains('OutfitEditActionV1'));
      expect(plan, contains('OutfitEditThermalV1'));
      expect(executor, contains('restoreCurrent'));
      expect(executor, contains('_cartesianProduct'));
      expect(executor, contains('V2FlexibleOutfitScorer.score'));
      expect(executor, contains('candidateSatisfiesCreatePlan'));
      expect(executor, isNot(contains('candidate.item.occasionFit')));
      expect(delta, contains('beforeIds'));
      expect(delta, contains('afterIds'));
      expect(delta, contains('followUpTextSk'));
      expect(service, contains('atomic_outfit_edit_unavailable'));
      expect(service, contains('candidates: editCandidates'));
      expect(service, contains("focusSlot: expectedFocusSlot ?? ''"));
      expect(service, contains('finalExplanation: editDelta.followUpTextSk'));
      expect(screen, contains('changedAfterItemIds.contains'));
      expect(frozenAuthority, isNot(contains('selected.presentationItems[0]')));
      expect(screen, contains('brain_locked_swap'));
      expect(screen, contains('outfitUpdateSlot'));
      expect(service, contains('lockedSelection: true'));
      expect(service, contains("presentationMode: 'focused_item'"));
      expect(native, contains('optionalUpperLayerRequested'));
      expect(native, contains('user_requested_backup_layer'));
      expect(
        screen,
        contains('additive_layer_rejected reason=non_additive_delta'),
      );
      expect(screen, contains('_brainPreservesCurrentOutfitForLayer'));
      expect(service, contains('locked_additive_layer'));
      expect(service, contains('required_user_layer_unavailable'));
      expect(service, contains('_preferNovelFullOutfitCandidates'));
      expect(service, contains('_addRequiredUpperLayerToFrozenCurrent'));
      expect(
        service,
        contains("const {'hoodie', 'zip_hoodie', 'sweatshirt'}.contains(type)"),
      );
    },
  );

  test(
    'Stylist has one shared thermal target instead of a chat-only duplicate',
    () {
      final service = _read('lib/Services/stylist_chat_outfit_service.dart');
      final policy = _read(
        'lib/domain/wardrobe_v2/outfit_suitability_policy_v2.dart',
      );

      expect(service, contains('OutfitSuitabilityPolicyV2.targetMeanWarmth('));
      expect(service, contains('weather.tempC'));
      expect(service, isNot(contains('weather.tempC <= 14 ? 6.0')));
      expect(policy, contains('static double targetMeanWarmth'));
    },
  );

  test(
    'frozen explanation receives user intent and presentation mode without changing selection',
    () {
      final authority = _read(
        'functions/stylist/frozen_stylist_authority_v1.js',
      );
      final brain = _read('functions/stylist/conversation_brain_v1.js');

      expect(authority, contains('locked_selection'));
      expect(authority, contains('presentationMode'));
      expect(authority, contains('userIntentContext'));
      expect(brain, contains('focused_item'));
      expect(brain, contains('concise_full'));
      expect(brain, contains('Samotné „idem do mesta“ NIE JE prechádzka'));
      expect(brain, contains('Počasie nie je povinná fráza'));
      expect(brain, contains('focused_item: JEDNA krátka prirodzená veta'));
      expect(authority, contains('deterministicFocused'));
    },
  );

  test('explicit additive layer cannot collapse into a top swap', () {
    final repaired = StylistOutfitDirectiveGuard.repair(
      rawDirective: <String, dynamic>{
        'scope': 'single_slot',
        'slot': 'top',
        'family': 'none',
        'extraLayer': 'none',
        'layerFamily': 'none',
        'presentation': 'focused_item',
      },
      userText: 'ukáž mi celý outfit a pridaj mi do neho aj mikinu',
      hasCurrentOutfit: true,
    );

    expect(repaired, isNotNull);
    expect(repaired!['scope'], 'full_outfit');
    expect(repaired['slot'], 'none');
    expect(repaired['preserveCurrentOutfit'], isTrue);
    expect(repaired['extraLayer'], 'required_upper_layer');
    expect(repaired['layerFamily'], 'hoodie');
    expect(repaired['presentation'], 'concise_full');

    final replacement = StylistOutfitDirectiveGuard.repair(
      rawDirective: <String, dynamic>{'scope': 'single_slot', 'slot': 'top'},
      userText: 'vymeň tričko za mikinu',
      hasCurrentOutfit: true,
    );
    expect(replacement!['scope'], 'single_slot');
    expect(replacement['slot'], 'top');
  });

  test('single-slot display prefers the actually changed item copy', () {
    final screen = _read('lib/screens/stylist_chat_screen.dart');
    expect(
      screen,
      contains('final focusedReply = fallbackReply ?? brainReply;'),
    );
    expect(
      screen,
      contains(
        "fallbackReply != null ? 'local_swap_fallback' : 'brain_locked_swap'",
      ),
    );
  });
}
