import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_chat_service.dart';

String _read(String path) => File(path).readAsStringSync();

String _scope(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $startMarker');
  expect(end, greaterThan(start), reason: 'Missing $endMarker after $startMarker');
  return source.substring(start, end);
}

void main() {
  test('Brain V1 client is explicit opt-in and forwards bounded raw history', () {
    final service = _read('lib/Services/stylist_chat_service.dart');
    final screen = _read('lib/screens/stylist_chat_screen.dart');

    expect(
      service,
      contains("static const conversationBrainVersion = 'brain_v1';"),
    );
    expect(service, contains("'conversationBrainVersion': conversationBrainVersion"));
    expect(service, contains("'history': history"));
    expect(screen, contains('static const int _historyLimit = 8;'));
    expect(screen, contains('_buildHistoryForBackend()'));
    expect(screen, contains('_runHybridOutfitGeneration('));
  });

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
    expect(web, contains('const contentType = role === "assistant" ? "output_text" : "input_text";'));
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
        reason: 'Public research allowlist must not gain $privateKey authority.',
      );
    }

    final merged = StylistChatService.resolvedEventContextFromData(<String, dynamic>{
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
    });

    expect(merged, isNotNull);
    expect(merged!['performer'], 'User performer');
    expect(merged['eventStartHour'], 20);
    expect(merged['eventEndHour'], 23);
    expect((merged['dressCode'] as Map)['id'], 'user_code');
  });

  test('active V2 outfit path freezes candidates and fails closed by exact ID', () {
    final outfitService = _read('lib/Services/stylist_chat_outfit_service.dart');
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

    expect(activeGenerate, contains('NativeWardrobeV2Runtime.resolveAll(wardrobe)'));
    expect(activeGenerate, contains('V2FlexibleCandidateMatrix.generate('));
    expect(activeGenerate, contains('StylistFrozenCandidateDecisionServiceV1()'));
    expect(activeGenerate, contains('.resolve('));
    expect(
      activeGenerate,
      contains('candidate.candidateId == selectedId'),
      reason: 'The accepted outfit must be resolved by exact frozen candidateId.',
    );
    expect(activeGenerate, contains('StylistFrozenDecisionRejectedExceptionV1('));
    expect(activeGenerate, isNot(contains('matrix.first')));
    expect(activeGenerate, isNot(contains('generated.first')));

    expect(frozenClient, contains(".httpsCallable('resolveStylistFrozenCandidatesV1')"));
    expect(frozenClient, contains("'frozenCandidates': candidates"));
    expect(frozenResolve, contains('rejectAllFallback'));
    expect(frozenResolve, isNot(contains('candidates.first')));
  });

  test('server validator owns safety and Brain cannot replace frozen selection', () {
    final authority = _read('functions/stylist/frozen_stylist_authority_v1.js');

    expect(authority, contains('const owned = itemIds.every((id) => ownedItemIds.has(id));'));
    expect(
      authority,
      contains('const eligible = deterministicPassed && owned && violationCodes.length === 0'),
    );
    expect(
      authority,
      contains('candidates.find((candidate) => candidate.candidateId === selectedCandidateId)'),
    );
    expect(authority, contains('selected_candidate_outside_frozen_set'));
    expect(authority, contains('selected_candidate_failed_hard_constraints'));
    expect(
      authority,
      contains('Never transmit candidate or item IDs to a user-facing explanation model.'),
    );
    expect(
      authority,
      contains('const explanationClient = useBrain ? brainExplanationClient : legacyExplanationClient;'),
      reason: 'Brain V1 must remain opt-in while old clients retain legacy explanation transport.',
    );
  });

  test('model roles and progress UX preserve the frozen authority boundary', () {
    final registry = _read('functions/stylist/ai_model_registry.js');
    final progress = _read('lib/models/stylist_chat_progress.dart');
    final screen = _read('lib/screens/stylist_chat_screen.dart');
    final outfitService = _read('lib/Services/stylist_chat_outfit_service.dart');

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
    expect(outfitService, contains('StylistChatProgressCallback? onProgress'));
    expect(
      progress.toLowerCase(),
      isNot(contains('candidateid')),
      reason: 'Progress transport must never become a selection authority.',
    );
  });
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
    final adapters = _read(
      'lib/domain/wardrobe_v2/wardrobe_v2_adapters.dart',
    );
    expect(service, contains('allowCrossFamilySameSlot: true'));
    expect(
      service,
      isNot(contains('allowCrossFamilySameSlot: requestedSwap.bottomFamily')),
      reason: 'Explicit single-slot swaps must be global, not bottom-only.',
    );
    expect(matrix, contains('bool allowCrossFamilySameSlot = false'));
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
}
