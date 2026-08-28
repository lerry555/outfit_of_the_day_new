import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('semantic authority files contain no named-entity decision patches', () {
    const files = <String>[
      'lib/utils/stylist_semantic_activity.dart',
      'lib/utils/stylist_travel_context.dart',
      'lib/utils/activity_traits_inferencer.dart',
      'lib/utils/event_clarification.dart',
      'lib/utils/dress_code_resolver.dart',
      'lib/data/event_dress_code.dart',
      'lib/models/outfit_context_state.dart',
    ];

    final banned = RegExp(
      r'\b(?:usa|tatry|tatransk\w*|disneyland|legoland|tatralandia|rytmus|elan|acdc|metallica|nightwish)\b',
      caseSensitive: false,
    );

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(
        banned.hasMatch(source),
        isFalse,
        reason: '$path must use generic semantic types, not named entities',
      );
    }
  });
}
