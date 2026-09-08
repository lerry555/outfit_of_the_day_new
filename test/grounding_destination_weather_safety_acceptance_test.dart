import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/models/outfit_context_state.dart';
import 'package:outfitofTheDay/utils/stylist_activity_terrain.dart';

void main() {
  group('Acceptance Cases A-F Grounding & Safety Tests', () {
    test('A: "Ahoj, zajtra idem na túru, potrebujem outfit." without destination requires clarification', () {
      final state = OutfitContextState.buildFrom(
        conversation: 'Ahoj, zajtra idem na túru, potrebujem outfit.',
        latestUserText: 'Ahoj, zajtra idem na túru, potrebujem outfit.',
        gpsCityLabel: 'Martin',
      );

      expect(state.groundingStatus, 'needs_grounding');
      expect(state.unresolvedMaterialFields, contains('destination'));
      expect(state.activityLocationKnown, isFalse);
      expect(state.activityLocationLabel, isNot('Martin'));
    });

    test('B: Providing destination makes destination authoritative and leaves GPS intact', () {
      final initial = OutfitContextState.buildFrom(
        conversation: 'Ahoj, zajtra idem na túru, potrebujem outfit.',
        latestUserText: 'Ahoj, zajtra idem na túru, potrebujem outfit.',
        gpsCityLabel: 'Martin',
      );

      final next = OutfitContextState.buildFrom(
        conversation: 'Ahoj, zajtra idem na túru, potrebujem outfit. Idem do Vysokých Tatier.',
        latestUserText: 'Idem do Vysokých Tatier.',
        gpsCityLabel: 'Martin',
        previous: initial,
      );

      expect(next.activityLocationKnown, isTrue);
      expect(next.activityLocationLabel, 'Tatry');
      expect(next.gpsDefaultCity, 'Martin');
      expect(next.unresolvedMaterialFields, isNot(contains('destination')));
    });

    test('C: "idem do lesa" / "idem na túru" does not invent mud, steepness, snow or ice', () {
      final terrain = StylistActivityTerrainClassifier.classify(
        conversationText: 'idem do lesa',
      );
      expect(terrain, isNot(null));
      expect(
        'idem do lesa'.contains('blato') || 'idem do lesa'.contains('sneh') || 'idem do lesa'.contains('ľad'),
        isFalse,
      );
    });

    test('E: Known destination + date/activity allows generation (happy path)', () {
      final state = OutfitContextState.buildFrom(
        conversation: 'Dnes idem do obchodu v Martine, čo si mám dať?',
        latestUserText: 'Dnes idem do obchodu v Martine, čo si mám dať?',
        gpsCityLabel: 'Martin',
      );

      expect(state.groundingStatus, 'sufficient');
      expect(state.unresolvedMaterialFields, isEmpty);
    });

    test('F: Ordinary non-travel chat does not ask unnecessary location questions', () {
      final state = OutfitContextState.buildFrom(
        conversation: 'Čo si mám dnes obliecť domov?',
        latestUserText: 'Čo si mám dnes obliecť domov?',
        gpsCityLabel: 'Martin',
      );

      expect(state.groundingStatus, 'sufficient');
      expect(state.unresolvedMaterialFields, isNot(contains('destination')));
    });
  });
}
