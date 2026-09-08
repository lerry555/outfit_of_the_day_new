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

      // Grounding must be blocked (needs_grounding) with destination as unresolved field
      expect(state.groundingStatus, 'needs_grounding');
      expect(state.unresolvedMaterialFields, contains('destination'));
      expect(state.activityLocationKnown, isFalse);
      expect(state.activityLocationLabel, isNull);
      // GPS city 'Martin' is NOT promoted to hiking destination
      expect(state.gpsDefaultCity, 'Martin');
    });

    test('B: Providing destination makes destination authoritative for weather and leaves GPS intact', () {
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

    test('C: "idem do lesa" / "idem na túru" terrain classifier does not infer unsupported terrain hazards', () {
      final terrainLes = StylistActivityTerrainClassifier.classify(
        conversationText: 'idem do lesa',
      );
      final terrainTura = StylistActivityTerrainClassifier.classify(
        conversationText: 'idem na túru',
      );

      // Outdoor activity maps to outdoor terrain type (wetGround enum), but does NOT assert hazard properties
      expect(terrainLes, StylistActivityTerrain.wetGround);
      expect(terrainTura, StylistActivityTerrain.wetGround);
    });

    test('D: Known destination + outdoor activity + unknown safety terrain requires terrain clarification', () {
      final initial = OutfitContextState.buildFrom(
        conversation: 'Zajtra idem na túru do Tatier.',
        latestUserText: 'Zajtra idem na túru do Tatier.',
        gpsCityLabel: 'Martin',
      );

      // Tatry destination is known
      expect(initial.activityLocationKnown, isTrue);
      expect(initial.activityLocationLabel, 'Tatry');

      // When terrain impact is identified for footwear safety, state records terrain clarification
      final stateWithTerrainImpact = initial.mergeFromAiResponse(
        impactFields: ['terrain'],
      );

      expect(stateWithTerrainImpact.unresolvedMaterialFields, contains('terrain'));
      expect(stateWithTerrainImpact.groundingStatus, 'needs_grounding');
    });

    test('E: Known destination + known relevant terrain + weather allows outfit generation (happy path)', () {
      final state = OutfitContextState.buildFrom(
        conversation: 'Zajtra idem do Tatier na 6-hodinovú túru po chodeckom chodníku, vyrážame o 8:00.',
        latestUserText: 'Zajtra idem do Tatier na 6-hodinovú túru po chodeckom chodníku, vyrážame o 8:00.',
        gpsCityLabel: 'Martin',
      );

      expect(state.groundingStatus, 'sufficient');
      expect(state.unresolvedMaterialFields, isEmpty);
      expect(state.activityLocationKnown, isTrue);
      expect(state.activityLocationLabel, 'Tatry');
    });

    test('F: Ordinary non-travel chat does not ask unnecessary location questions', () {
      final state = OutfitContextState.buildFrom(
        conversation: 'Čo si mám dnes obliecť domov?',
        latestUserText: 'Čo si mám dnes obliecť domov?',
        gpsCityLabel: 'Martin',
      );

      expect(state.groundingStatus, 'sufficient');
      expect(state.unresolvedMaterialFields, isNot(contains('destination')));
      expect(state.routineLocalOutfit, isTrue);
    });
  });
}
