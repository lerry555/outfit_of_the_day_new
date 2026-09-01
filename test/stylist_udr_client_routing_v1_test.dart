import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_chat_outfit_service.dart';
import 'package:outfitofTheDay/Services/stylist_frozen_candidate_decision_service.dart';
import 'package:outfitofTheDay/Services/stylist_udr_client_routing_v1.dart';

void main() {
  test('GPT-4o context actions control clarification, proceed, and stop', () {
    expect(
      StylistUdrClientRoutingV1.normalizeContextAction('ask_clarification'),
      'clarify',
    );
    expect(
      StylistUdrClientRoutingV1.normalizeContextAction('proceed'),
      'generate_outfit',
    );
    expect(StylistUdrClientRoutingV1.normalizeContextAction('stop'), 'stop');
  });

  test('frozen authority explanation is displayed unchanged', () {
    const explanation =
        'Toto je najlepšia dostupná kombinácia; nie je to ideálne riešenie.';
    expect(
      StylistUdrClientRoutingV1.frozenExplanationForDisplay(explanation),
      explanation,
    );
    expect(StylistUdrClientRoutingV1.frozenExplanationForDisplay('  '), isNull);
  });

  test('reject_all remains fail closed', () {
    const result = StylistFrozenCandidateDecisionResultV1.rejectAllFallback;
    expect(result.rejectAll, isTrue);
    expect(result.selected, isFalse);
    expect(result.selectedCandidateId, isNull);
  });

  test('explicit swap rejection remains fail closed', () {
    expect(
      () => requireExplicitStylistSwapReplacementV1(null),
      throwsA(isA<StylistFrozenDecisionRejectedExceptionV1>()),
    );
  });

  test('Brain V1 ordinary turn uses simple agent before legacy UDR code', () {
    final source = File(
      'lib/screens/stylist_chat_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final start = source.indexOf('Future<void> _sendMessage() async');
    final end = source.indexOf('Future<void> _showImageSourceSheet()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final ordinaryTurn = source.substring(start, end);
    expect(ordinaryTurn, contains('_stylistSimpleAgentService.sendTurn'));
    expect(ordinaryTurn, contains('_handleSimpleAgentResponse(response)'));
    expect(
      ordinaryTurn,
      isNot(contains('StylistUdrClientRoutingV1.normalizeContextAction')),
    );
    expect(
      ordinaryTurn,
      isNot(contains('_blockIfConversationNeedsClarification')),
    );
    expect(ordinaryTurn, isNot(contains('_runHybridOutfitGeneration(')));
    expect(ordinaryTurn, isNot(contains('outfitDirective')));

    // Rollback-only legacy implementation remains compiled for non-simple
    // transports, but cannot be reached from the ordinary Brain V1 turn.
    expect(
      source,
      contains('StylistUdrClientRoutingV1.normalizeContextAction'),
    );
    expect(source, contains("if (effectiveAction == 'generate_outfit')"));
    expect(source, contains('await _runHybridOutfitGeneration('));
    expect(
      source,
      contains('StylistUdrClientRoutingV1.frozenExplanationForDisplay'),
    );
    expect(source, contains('STYLIST UDR legacy_fallback_invoked=false'));
  });
}
