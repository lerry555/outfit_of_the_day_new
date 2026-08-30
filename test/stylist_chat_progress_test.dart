import 'package:flutter_test/flutter_test.dart';

import '../lib/models/stylist_chat_progress.dart';

void main() {
  test('Stylist progress phases expose distinct Slovak labels', () {
    final labels = StylistChatProgressPhase.values
        .map((phase) => phase.labelSk)
        .toList(growable: false);

    expect(labels.every((label) => label.trim().isNotEmpty), isTrue);
    expect(labels.toSet().length, StylistChatProgressPhase.values.length);
  });

  test('Stylist progress contract keeps the expected pipeline order', () {
    expect(
      StylistChatProgressPhase.values,
      <StylistChatProgressPhase>[
        StylistChatProgressPhase.resolvingContext,
        StylistChatProgressPhase.checkingWeather,
        StylistChatProgressPhase.thinkingWithContext,
        StylistChatProgressPhase.analyzingWardrobe,
        StylistChatProgressPhase.buildingOutfit,
        StylistChatProgressPhase.finalizing,
      ],
    );
  });

  test('progress labels describe work without leaking internal model details', () {
    final combined = StylistChatProgressPhase.values
        .map((phase) => phase.labelSk.toLowerCase())
        .join(' ');

    expect(combined, isNot(contains('gpt')));
    expect(combined, isNot(contains('candidateid')));
    expect(combined, isNot(contains('validator')));
  });
}
