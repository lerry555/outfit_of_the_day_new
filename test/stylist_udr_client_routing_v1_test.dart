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

  test('production screen keeps local semantic gates off the UDR route', () {
    final source = File(
      'lib/screens/stylist_chat_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      source,
      contains('StylistUdrClientRoutingV1.normalizeContextAction'),
    );
    expect(
      source,
      contains("if (!_useAiClarifyFlow &&\n          !useShoppingTransport &&"),
    );
    expect(
      source,
      contains(
        "if (!_useAiClarifyFlow &&\n        _blockIfConversationNeedsClarification",
      ),
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
