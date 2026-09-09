import 'package:flutter_test/flutter_test.dart';

import '../lib/models/stylist_chat_progress.dart';

void main() {
  test('Stylist progress uses one calm stable user-facing status', () {
    final labels = StylistChatProgressPhase.values
        .map((phase) => phase.labelSk)
        .toList(growable: false);

    expect(labels.every((label) => label == 'Pripravujem odpoveď…'), isTrue);
    expect(labels.toSet(), <String>{'Pripravujem odpoveď…'});
  });

  test('Stylist progress contract keeps the expected internal pipeline order', () {
    expect(StylistChatProgressPhase.values, <StylistChatProgressPhase>[
      StylistChatProgressPhase.resolvingContext,
      StylistChatProgressPhase.checkingWeather,
      StylistChatProgressPhase.thinkingWithContext,
      StylistChatProgressPhase.analyzingWardrobe,
      StylistChatProgressPhase.buildingOutfit,
      StylistChatProgressPhase.finalizing,
    ]);
  });

  test('user-facing progress never leaks implementation/debug language', () {
    final combined = StylistChatProgressPhase.values
        .map((phase) => phase.labelSk.toLowerCase())
        .join(' ');

    for (final forbidden in <String>[
      'gpt',
      'validator',
      'candidate',
      'kontext',
      'počasie',
      'satnik',
      'šatník',
      'vyhodnocujem',
      'kontrolujem',
    ]) {
      expect(combined, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
