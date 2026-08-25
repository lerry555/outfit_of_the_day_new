import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/trip_packing_service.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_ontology_v2.dart';

void main() {
  late WardrobeOntologyV2 ontology;

  setUpAll(() {
    ontology = WardrobeOntologyV2.fromJsonString(
      File('assets/data/wardrobe_ontology_v2.json').readAsStringSync(),
    );
  });

  Map<String, dynamic> doc({
    required String id,
    required String name,
    required String canonicalType,
    required int formality,
    required int warmth,
    SetMembershipV2? setMembership,
  }) {
    final def = ontology.definition(canonicalType);
    expect(def, isNotNull, reason: 'unknown canonicalType $canonicalType');
    return {
      'id': id,
      'name': name,
      'imageUrl': 'https://example.test/$id.png',
      'ontologyVersion': WardrobeOntologyV2Values.ontologyVersion,
      'taxonomyVersion': WardrobeOntologyV2Values.taxonomyVersion,
      'kbVersion': WardrobeOntologyV2Values.kbVersion,
      'canonicalType': canonicalType,
      'canonicalFamily': def!.canonicalFamily,
      'bodySlots': def.defaultBodySlots,
      'layerPosition': def.defaultLayerPosition,
      'outfitFunctions': def.outfitFunctions,
      'colorProfile': const ColorProfileV2(
        primary: SemanticColorV2(family: 'navy'),
        metalTone: 'none',
        hardwareTone: 'none',
      ).toMap(),
      'formality': formality,
      'styles': const <String>[],
      'occasionFit': const <String>[],
      'seasons': const <String>[],
      'warmth': warmth,
      'attributes': const <String, dynamic>{},
      'fieldSources': const {'canonicalType': 'visual_ai'},
      'fieldConfidence': const {'canonicalType': 0.9},
      'userOverrideFields': const <String>[],
      if (setMembership != null) 'setMembership': setMembership.toMap(),
    };
  }

  List<Map<String, dynamic>> coreSeparates({
    required Map<String, dynamic> upper,
    required Map<String, dynamic> lower,
    required List<Map<String, dynamic>> shoes,
    List<Map<String, dynamic>> extra = const [],
  }) => [upper, lower, ...shoes, ...extra];

  TripPlanInput plan({
    required Set<TripKind> kinds,
    Set<TripTravelStyle> styles = const {},
    String destination = 'Berlin',
    DateTime? arrival,
    DateTime? returnDeparture,
  }) {
    final start = arrival ?? DateTime(2026, 7, 1, 10);
    final end = returnDeparture ?? DateTime(2026, 7, 4, 18);
    return TripPlanInput(
      destinationText: destination,
      tripKinds: kinds,
      transport: TripTransport.plane,
      travelStyles: styles,
      outboundDeparture: DateTime(2026, 7, 1, 6),
      outboundArrival: start,
      returnDeparture: end,
      returnArrival: DateTime(2026, 7, 4, 22),
    );
  }

  TripPackingPlaceholderResult generate({
    required TripPlanInput input,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    return TripPackingService.composePlaceholderPlanForTest(
      input: input,
      wardrobeDocs: wardrobe,
      ontology: ontology,
    );
  }

  Set<String> idsOn(TripPackingPlaceholderResult result, int day) =>
      result.destinationDailyPlans[day].pieces.map((p) => p.id).toSet();

  test('hiking prefers ontology outdoor footwear over fashion sneakers', () {
    final result = generate(
      input: plan(kinds: {TripKind.hiking}),
      wardrobe: coreSeparates(
        upper: doc(
          id: 'tee',
          name: 'Tričko',
          canonicalType: 't_shirt',
          formality: 2,
          warmth: 2,
        ),
        lower: doc(
          id: 'jeans',
          name: 'Rifle',
          canonicalType: 'jeans',
          formality: 3,
          warmth: 4,
        ),
        shoes: [
          doc(
            id: 'shoe-fashion',
            name: 'Fashion tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
          doc(
            id: 'shoe-hike',
            name: 'Turistická obuv',
            canonicalType: 'hiking_shoes',
            formality: 2,
            warmth: 5,
          ),
        ],
      ),
    );
    expect(result.destinationDailyPlans, isNotEmpty);
    expect(idsOn(result, 0), contains('shoe-hike'));
    expect(idsOn(result, 0), isNot(contains('shoe-fashion')));
    expect(result.luggageItems.map((p) => p.id), contains('shoe-hike'));
  });

  test('hiking fallback uses closed shoes and surfaces missing outdoor footwear', () {
    final result = generate(
      input: plan(kinds: {TripKind.hiking}),
      wardrobe: coreSeparates(
        upper: doc(
          id: 'tee',
          name: 'Tričko',
          canonicalType: 't_shirt',
          formality: 2,
          warmth: 2,
        ),
        lower: doc(
          id: 'jeans',
          name: 'Rifle',
          canonicalType: 'jeans',
          formality: 3,
          warmth: 4,
        ),
        shoes: [
          doc(
            id: 'shoe-open',
            name: 'Sandále',
            canonicalType: 'sandals',
            formality: 2,
            warmth: 2,
          ),
          doc(
            id: 'shoe-fashion',
            name: 'Tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
        ],
      ),
    );
    expect(idsOn(result, 0), contains('shoe-fashion'));
    expect(idsOn(result, 0), isNot(contains('shoe-open')));
    expect(
      result.missingItems.map((m) => m.nameSk),
      contains('turistická / outdoorová obuv'),
    );
  });

  test('business prefers V2 formality-appropriate pieces over casual ones', () {
    final result = generate(
      input: plan(kinds: {TripKind.business}),
      wardrobe: coreSeparates(
        upper: doc(
          id: 'tee',
          name: 'Tričko',
          canonicalType: 't_shirt',
          formality: 2,
          warmth: 2,
        ),
        lower: doc(
          id: 'jeans',
          name: 'Rifle',
          canonicalType: 'jeans',
          formality: 3,
          warmth: 4,
        ),
        shoes: [
          doc(
            id: 'shoe-fashion',
            name: 'Tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
          doc(
            id: 'shoe-loafers',
            name: 'Mokasíny',
            canonicalType: 'loafers',
            formality: 6,
            warmth: 3,
          ),
        ],
        extra: [
          doc(
            id: 'shirt',
            name: 'Košeľa',
            canonicalType: 'dress_shirt',
            formality: 7,
            warmth: 3,
          ),
          doc(
            id: 'trousers',
            name: 'Nohavice',
            canonicalType: 'trousers',
            formality: 6,
            warmth: 4,
          ),
        ],
      ),
    );
    final ids = idsOn(result, 0);
    expect(ids, contains('shirt'));
    expect(ids, contains('trousers'));
    expect(ids, contains('shoe-loafers'));
    expect(ids, isNot(contains('tee')));
    expect(ids, isNot(contains('jeans')));
  });

  test('warm beach prefers hot-weather pieces and skips a heavy outer layer', () {
    final result = generate(
      input: plan(kinds: {TripKind.beach}, destination: 'Malaga'),
      wardrobe: coreSeparates(
        upper: doc(
          id: 'parka',
          name: 'Zimná bunda',
          canonicalType: 'winter_jacket',
          formality: 3,
          warmth: 9,
        ),
        lower: doc(
          id: 'jeans',
          name: 'Rifle',
          canonicalType: 'jeans',
          formality: 3,
          warmth: 4,
        ),
        shoes: [
          doc(
            id: 'boots',
            name: 'Čižmy',
            canonicalType: 'boots',
            formality: 4,
            warmth: 7,
          ),
          doc(
            id: 'sandals',
            name: 'Sandále',
            canonicalType: 'sandals',
            formality: 2,
            warmth: 2,
          ),
        ],
        extra: [
          doc(
            id: 'tee',
            name: 'Tričko',
            canonicalType: 't_shirt',
            formality: 2,
            warmth: 2,
          ),
          doc(
            id: 'shorts',
            name: 'Kraťasy',
            canonicalType: 'shorts',
            formality: 2,
            warmth: 2,
          ),
        ],
      ),
    );
    final ids = idsOn(result, 0);
    expect(ids, contains('tee'));
    expect(ids, contains('shorts'));
    expect(ids, contains('sandals'));
    expect(ids, isNot(contains('parka')));
    expect(ids, isNot(contains('boots')));
    expect(
      result.destinationDailyPlans.every(
        (day) => !day.pieces.any((p) => p.id == 'parka'),
      ),
      isTrue,
    );
  });

  test('trip-local elegant travel style ranks a more formal valid alternative', () {
    final wardrobe = coreSeparates(
      upper: doc(
        id: 'tee',
        name: 'Tričko',
        canonicalType: 't_shirt',
        formality: 2,
        warmth: 3,
      ),
      lower: doc(
        id: 'jeans',
        name: 'Rifle',
        canonicalType: 'jeans',
        formality: 3,
        warmth: 4,
      ),
      shoes: [
        doc(
          id: 'sneakers',
          name: 'Tenisky',
          canonicalType: 'sneakers',
          formality: 2,
          warmth: 3,
        ),
      ],
      extra: [
        doc(
          id: 'shirt',
          name: 'Košeľa',
          canonicalType: 'dress_shirt',
          formality: 7,
          warmth: 3,
        ),
      ],
    );
    final elegant = generate(
      input: plan(
        kinds: {TripKind.cityBreak},
        styles: {TripTravelStyle.elegant},
      ),
      wardrobe: wardrobe,
    );
    final comfy = generate(
      input: plan(
        kinds: {TripKind.cityBreak},
        styles: {TripTravelStyle.comfy},
      ),
      wardrobe: wardrobe,
    );
    expect(idsOn(elegant, 0), contains('shirt'));
    expect(idsOn(comfy, 0), contains('tee'));
  });

  test('hiking suitability beats elegant travel style on footwear', () {
    final result = generate(
      input: plan(
        kinds: {TripKind.hiking},
        styles: {TripTravelStyle.elegant},
      ),
      wardrobe: coreSeparates(
        upper: doc(
          id: 'shirt',
          name: 'Košeľa',
          canonicalType: 'dress_shirt',
          formality: 7,
          warmth: 3,
        ),
        lower: doc(
          id: 'trousers',
          name: 'Nohavice',
          canonicalType: 'trousers',
          formality: 6,
          warmth: 4,
        ),
        shoes: [
          doc(
            id: 'loafers',
            name: 'Mokasíny',
            canonicalType: 'loafers',
            formality: 6,
            warmth: 3,
          ),
          doc(
            id: 'shoe-hike',
            name: 'Turistická obuv',
            canonicalType: 'hiking_shoes',
            formality: 2,
            warmth: 5,
          ),
        ],
      ),
    );
    expect(idsOn(result, 0), contains('shoe-hike'));
    expect(idsOn(result, 0), isNot(contains('loafers')));
  });

  test('set partner applies only among equally suitable candidates', () {
    const set = SetMembershipV2(setId: 'set-1', setType: 'matching_set');
    final result = generate(
      input: plan(kinds: {TripKind.hiking}),
      wardrobe: coreSeparates(
        upper: doc(
          id: 'tee',
          name: 'Tričko',
          canonicalType: 't_shirt',
          formality: 2,
          warmth: 2,
          setMembership: set,
        ),
        lower: doc(
          id: 'jeans',
          name: 'Rifle v sete',
          canonicalType: 'jeans',
          formality: 3,
          warmth: 4,
          setMembership: set,
        ),
        shoes: [
          doc(
            id: 'shoe-fashion',
            name: 'Tenisky v sete',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
            setMembership: set,
          ),
          doc(
            id: 'shoe-hike',
            name: 'Turistická obuv',
            canonicalType: 'hiking_shoes',
            formality: 2,
            warmth: 5,
          ),
          doc(
            id: 'shoe-hike-set',
            name: 'Turistická obuv v sete',
            canonicalType: 'hiking_shoes',
            formality: 2,
            warmth: 5,
            setMembership: set,
          ),
        ],
        extra: [
          doc(
            id: 'pants-hike',
            name: 'Turistické nohavice',
            canonicalType: 'hiking_pants',
            formality: 2,
            warmth: 4,
          ),
          doc(
            id: 'pants-hike-set',
            name: 'Turistické nohavice v sete',
            canonicalType: 'hiking_pants',
            formality: 2,
            warmth: 4,
            setMembership: set,
          ),
        ],
      ),
    );
    final ids = idsOn(result, 0);
    expect(ids, contains('shoe-hike-set'));
    expect(ids, isNot(contains('shoe-fashion')));
    expect(ids, contains('pants-hike-set'));
    expect(ids, isNot(contains('jeans')));
  });

  test('equally suitable candidates still rotate across destination days', () {
    final result = generate(
      input: plan(kinds: {TripKind.cityBreak}),
      wardrobe: coreSeparates(
        upper: doc(
          id: 'tee-a',
          name: 'Tričko A',
          canonicalType: 't_shirt',
          formality: 2,
          warmth: 3,
        ),
        lower: doc(
          id: 'jeans',
          name: 'Rifle',
          canonicalType: 'jeans',
          formality: 3,
          warmth: 4,
        ),
        shoes: [
          doc(
            id: 'sneakers',
            name: 'Tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
        ],
        extra: [
          doc(
            id: 'tee-b',
            name: 'Tričko B',
            canonicalType: 't_shirt',
            formality: 2,
            warmth: 3,
          ),
          doc(
            id: 'tee-c',
            name: 'Tričko C',
            canonicalType: 't_shirt',
            formality: 2,
            warmth: 3,
          ),
        ],
      ),
    );
    expect(result.destinationDailyPlans.length, greaterThanOrEqualTo(3));
    final tops = [
      for (var i = 0; i < 3; i++)
        idsOn(result, i).intersection({'tee-a', 'tee-b', 'tee-c'}).single,
    ];
    expect(tops.toSet(), hasLength(3));
  });

  test('live trip files stay isolated from global Style Preferences', () {
    const files = [
      'lib/Services/trip_packing_service.dart',
      'lib/domain/trip/trip_intent_policy.dart',
      'lib/domain/trip/trip_packing_coverage.dart',
      'lib/screens/trip_packing_screen.dart',
    ];
    for (final path in files) {
      final src = File(path).readAsStringSync();
      expect(src.contains('UserStylePreferencesReader'), isFalse, reason: path);
      expect(src.contains('StylePreferenceTasteScorer'), isFalse, reason: path);
      expect(
        src.contains('class StylePreferenceTaste') ||
            src.contains('StylePreferenceTaste.'),
        isFalse,
        reason: path,
      );
      expect(src.contains('stylePreferences/main'), isFalse, reason: path);
    }
  });
}
