import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/trip_destination_weather.dart';
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

  TripPlanInput plan({
    required Set<TripKind> kinds,
    int destinationDays = 5,
    String destination = 'Berlin',
  }) {
    return TripPlanInput(
      destinationText: destination,
      tripKinds: kinds,
      transport: TripTransport.plane,
      travelStyles: const {},
      outboundDeparture: DateTime(2026, 7, 1, 6),
      outboundArrival: DateTime(2026, 7, 1, 10),
      returnDeparture: DateTime(2026, 7, destinationDays, 18),
      returnArrival: DateTime(2026, 7, destinationDays, 22),
    );
  }

  List<TripResolvedDayWeather> resolvedDays(
    int n, {
    int high = 22,
    int low = 16,
    int? coldDay,
    int? rainDay,
    bool rainAll = false,
  }) {
    return [
      for (var i = 0; i < n; i++)
        TripResolvedDayWeather(
          date: DateTime(2026, 7, i + 1),
          highTempC: i == coldDay ? 6 : high,
          lowTempC: i == coldDay ? 2 : low,
          conditionSk: i == rainDay || rainAll ? 'Dážď' : 'Jasno',
          forecastAvailable: true,
          sourceLabelSk: 'Predpoveď',
          isRainy: i == rainDay || rainAll,
          isWindy: false,
        ),
    ];
  }

  TripPackingPlaceholderResult generate({
    required TripPlanInput input,
    required List<Map<String, dynamic>> wardrobe,
    List<TripResolvedDayWeather>? weather,
  }) {
    return TripPackingService.composePlaceholderPlanForTest(
      input: input,
      wardrobeDocs: wardrobe,
      ontology: ontology,
      destinationWeather: weather,
    );
  }

  Set<String> idsOn(TripPackingPlaceholderResult result, int day) =>
      result.destinationDailyPlans[day].pieces.map((p) => p.id).toSet();

  Set<String> luggageIds(TripPackingPlaceholderResult result) =>
      result.luggageItems.map((p) => p.id).toSet();

  List<Map<String, dynamic>> cityCore({
    List<Map<String, dynamic>> extras = const [],
  }) => [
    doc(
      id: 'tee',
      name: 'Tričko',
      canonicalType: 't_shirt',
      formality: 2,
      warmth: 2,
    ),
    doc(
      id: 'jeans',
      name: 'Rifle',
      canonicalType: 'jeans',
      formality: 3,
      warmth: 4,
    ),
    ...extras,
  ];

  test('reusable footwear covers five city days with one pair', () {
    final result = generate(
      input: plan(kinds: {TripKind.cityBreak}, destinationDays: 5),
      weather: resolvedDays(5),
      wardrobe: cityCore(
        extras: [
          for (var i = 1; i <= 5; i++)
            doc(
              id: 'shoe-$i',
              name: 'Tenisky $i',
              canonicalType: 'sneakers',
              formality: 2,
              warmth: 3,
            ),
        ],
      ),
    );
    expect(result.destinationDailyPlans, hasLength(5));
    final shoes = luggageIds(result).where((id) => id.startsWith('shoe-'));
    expect(shoes, hasLength(1));
    for (var day = 0; day < 5; day++) {
      expect(
        idsOn(result, day).intersection(shoes.toSet()),
        hasLength(1),
      );
    }
  });

  test('one suitable layer is reused across several cold rainy days', () {
    final result = generate(
      input: plan(kinds: {TripKind.cityBreak}, destinationDays: 5),
      weather: resolvedDays(5, high: 8, low: 2, rainAll: true),
      wardrobe: cityCore(
        extras: [
          doc(
            id: 'sneakers',
            name: 'Tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
          for (var i = 1; i <= 3; i++)
            doc(
              id: 'shell-$i',
              name: 'Pláštenka $i',
              canonicalType: 'rain_jacket',
              formality: 3,
              warmth: 4,
            ),
        ],
      ),
    );
    final layers = luggageIds(result).where((id) => id.startsWith('shell-'));
    expect(layers, hasLength(1));
    for (var day = 0; day < 5; day++) {
      expect(idsOn(result, day).intersection(layers.toSet()), hasLength(1));
    }
  });

  test('compatible bottoms are reused rather than packed per day', () {
    final result = generate(
      input: plan(kinds: {TripKind.cityBreak}, destinationDays: 5),
      weather: resolvedDays(5),
      wardrobe: [
        doc(
          id: 'tee',
          name: 'Tričko',
          canonicalType: 't_shirt',
          formality: 2,
          warmth: 2,
        ),
        doc(
          id: 'sneakers',
          name: 'Tenisky',
          canonicalType: 'sneakers',
          formality: 2,
          warmth: 3,
        ),
        for (var i = 1; i <= 4; i++)
          doc(
            id: 'bottom-$i',
            name: 'Nohavice $i',
            canonicalType: 'jeans',
            formality: 3,
            warmth: 4,
          ),
      ],
    );
    final bottoms = luggageIds(result).where((id) => id.startsWith('bottom-'));
    expect(bottoms.length, lessThan(5));
    expect(bottoms, isNotEmpty);
    for (var day = 0; day < 5; day++) {
      expect(idsOn(result, day).intersection(bottoms.toSet()), hasLength(1));
    }
  });

  test('seven-day trip with enough tops does not collapse to one top', () {
    final result = generate(
      input: plan(kinds: {TripKind.cityBreak}, destinationDays: 7),
      weather: resolvedDays(7),
      wardrobe: [
        doc(
          id: 'jeans',
          name: 'Rifle',
          canonicalType: 'jeans',
          formality: 3,
          warmth: 4,
        ),
        doc(
          id: 'sneakers',
          name: 'Tenisky',
          canonicalType: 'sneakers',
          formality: 2,
          warmth: 3,
        ),
        for (var i = 1; i <= 7; i++)
          doc(
            id: 'top-$i',
            name: 'Tričko $i',
            canonicalType: 't_shirt',
            formality: 2,
            warmth: 2,
          ),
      ],
    );
    final tops = luggageIds(result).where((id) => id.startsWith('top-'));
    expect(tops.length, greaterThan(1));
    expect(tops.length, lessThan(7));
  });

  test('scarce wardrobe reuses the only valid top rather than failing', () {
    final result = generate(
      input: plan(kinds: {TripKind.cityBreak}, destinationDays: 7),
      weather: resolvedDays(7),
      wardrobe: cityCore(
        extras: [
          doc(
            id: 'sneakers',
            name: 'Tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
        ],
      ),
    );
    expect(result.destinationDailyPlans, hasLength(7));
    for (var day = 0; day < 7; day++) {
      expect(idsOn(result, day), contains('tee'));
    }
    expect(luggageIds(result), contains('tee'));
    expect(
      result.missingItems.where((m) => m.nameSk.contains('vrchný')),
      isEmpty,
    );
  });

  test('one hiking overlay day still packs hiking footwear', () {
    final result = generate(
      input: plan(
        kinds: {TripKind.cityBreak, TripKind.hiking},
        destinationDays: 5,
      ),
      weather: resolvedDays(5),
      wardrobe: cityCore(
        extras: [
          doc(
            id: 'sneakers',
            name: 'Tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
          doc(
            id: 'hike-shoes',
            name: 'Turistická obuv',
            canonicalType: 'hiking_shoes',
            formality: 2,
            warmth: 5,
          ),
        ],
      ),
    );
    expect(luggageIds(result), contains('hike-shoes'));
    expect(idsOn(result, 4), contains('hike-shoes'));
    expect(idsOn(result, 4), isNot(contains('sneakers')));
    expect(idsOn(result, 0), contains('sneakers'));
  });

  test('one business overlay day still packs formal pieces', () {
    final result = generate(
      input: plan(
        kinds: {TripKind.cityBreak, TripKind.business},
        destinationDays: 5,
      ),
      weather: resolvedDays(5),
      wardrobe: [
        doc(
          id: 'tee',
          name: 'Tričko',
          canonicalType: 't_shirt',
          formality: 2,
          warmth: 2,
        ),
        doc(
          id: 'shirt',
          name: 'Košeľa',
          canonicalType: 'dress_shirt',
          formality: 7,
          warmth: 3,
        ),
        doc(
          id: 'jeans',
          name: 'Rifle',
          canonicalType: 'jeans',
          formality: 3,
          warmth: 4,
        ),
        doc(
          id: 'trousers',
          name: 'Nohavice',
          canonicalType: 'trousers',
          formality: 6,
          warmth: 4,
        ),
        doc(
          id: 'sneakers',
          name: 'Tenisky',
          canonicalType: 'sneakers',
          formality: 2,
          warmth: 3,
        ),
        doc(
          id: 'loafers',
          name: 'Mokasíny',
          canonicalType: 'loafers',
          formality: 6,
          warmth: 3,
        ),
      ],
    );
    expect(idsOn(result, 0), contains('shirt'));
    expect(idsOn(result, 0), contains('trousers'));
    expect(idsOn(result, 0), contains('loafers'));
    expect(idsOn(result, 0), isNot(contains('tee')));
    expect(luggageIds(result), containsAll(['shirt', 'trousers', 'loafers']));
    expect(idsOn(result, 1), contains('tee'));
  });

  test('one rainy cold day keeps its protective layer', () {
    final result = generate(
      input: plan(kinds: {TripKind.cityBreak}, destinationDays: 5),
      weather: resolvedDays(5, rainDay: 4, coldDay: 4),
      wardrobe: cityCore(
        extras: [
          doc(
            id: 'sneakers',
            name: 'Tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
          doc(
            id: 'shell',
            name: 'Pláštenka',
            canonicalType: 'rain_jacket',
            formality: 3,
            warmth: 4,
          ),
        ],
      ),
    );
    expect(luggageIds(result), contains('shell'));
    expect(idsOn(result, 4), contains('shell'));
    expect(idsOn(result, 0), isNot(contains('shell')));
  });

  test('hiking shoe is not replaced by a reusable city sneaker', () {
    final result = generate(
      input: plan(
        kinds: {TripKind.cityBreak, TripKind.hiking},
        destinationDays: 7,
      ),
      weather: resolvedDays(7),
      wardrobe: cityCore(
        extras: [
          doc(
            id: 'sneakers',
            name: 'Tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
          doc(
            id: 'hike-shoes',
            name: 'Turistická obuv',
            canonicalType: 'hiking_shoes',
            formality: 2,
            warmth: 5,
          ),
        ],
      ),
    );
    expect(luggageIds(result), containsAll(['sneakers', 'hike-shoes']));
    expect(idsOn(result, 6), contains('hike-shoes'));
    expect(idsOn(result, 6), isNot(contains('sneakers')));
    for (var day = 0; day < 6; day++) {
      expect(idsOn(result, day), contains('sneakers'));
      expect(idsOn(result, day), isNot(contains('hike-shoes')));
    }
  });

  test('casual reusable top cannot replace a business-valid top', () {
    final result = generate(
      input: plan(
        kinds: {TripKind.cityBreak, TripKind.business},
        destinationDays: 5,
      ),
      weather: resolvedDays(5),
      wardrobe: cityCore(
        extras: [
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
          doc(
            id: 'sneakers',
            name: 'Tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
        ],
      ),
    );
    expect(idsOn(result, 0), contains('shirt'));
    expect(idsOn(result, 0), isNot(contains('tee')));
    expect(luggageIds(result), contains('shirt'));
  });

  test('warm-weather bottom is not reused on the cold day', () {
    final result = generate(
      input: plan(kinds: {TripKind.cityBreak}, destinationDays: 7),
      weather: resolvedDays(7, high: 28, low: 18, coldDay: 6),
      wardrobe: [
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
        doc(
          id: 'jeans',
          name: 'Rifle',
          canonicalType: 'jeans',
          formality: 3,
          warmth: 4,
        ),
        doc(
          id: 'sneakers',
          name: 'Tenisky',
          canonicalType: 'sneakers',
          formality: 2,
          warmth: 3,
        ),
      ],
    );
    expect(luggageIds(result), containsAll(['shorts', 'jeans']));
    expect(idsOn(result, 6), contains('jeans'));
    expect(idsOn(result, 6), isNot(contains('shorts')));
    expect(idsOn(result, 0), contains('shorts'));
  });

  test('travel-worn destination piece is listed once in luggage', () {
    final result = generate(
      input: plan(kinds: {TripKind.cityBreak}, destinationDays: 5),
      weather: resolvedDays(5),
      wardrobe: cityCore(
        extras: [
          doc(
            id: 'sneakers',
            name: 'Tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
        ],
      ),
    );
    final luggage = result.luggageItems.map((p) => p.id).toList();
    expect(luggage.toSet(), hasLength(luggage.length));
    final travelIds = result.travelOutboundPieces.map((p) => p.id).toSet();
    for (final id in travelIds) {
      expect(luggage.where((x) => x == id).length, lessThanOrEqualTo(1));
    }
    expect(travelIds.intersection(luggageIds(result)), isNotEmpty);
  });

  test('same input wardrobe and weather yield identical packing', () {
    final input = plan(kinds: {TripKind.cityBreak}, destinationDays: 5);
    final weather = resolvedDays(5);
    final wardrobe = cityCore(
      extras: [
        doc(
          id: 'sneakers',
          name: 'Tenisky',
          canonicalType: 'sneakers',
          formality: 2,
          warmth: 3,
        ),
        doc(
          id: 'tee-b',
          name: 'Tričko B',
          canonicalType: 't_shirt',
          formality: 2,
          warmth: 2,
        ),
      ],
    );
    final a = generate(input: input, wardrobe: wardrobe, weather: weather);
    final b = generate(input: input, wardrobe: wardrobe, weather: weather);
    expect(
      a.luggageItems.map((p) => p.id).toList(),
      b.luggageItems.map((p) => p.id).toList(),
    );
    expect(
      [
        for (final day in a.destinationDailyPlans)
          day.pieces.map((p) => p.id).toList(),
      ],
      [
        for (final day in b.destinationDailyPlans)
          day.pieces.map((p) => p.id).toList(),
      ],
    );
  });

  test('coverage reduces a naive per-day union without dropping coverage', () {
    final result = generate(
      input: plan(kinds: {TripKind.cityBreak}, destinationDays: 5),
      weather: resolvedDays(5, high: 10, low: 4, rainAll: true),
      wardrobe: [
        for (var i = 1; i <= 5; i++)
          doc(
            id: 'top-$i',
            name: 'Tričko $i',
            canonicalType: 't_shirt',
            formality: 2,
            warmth: 3,
          ),
        for (var i = 1; i <= 4; i++)
          doc(
            id: 'bottom-$i',
            name: 'Rifle $i',
            canonicalType: 'jeans',
            formality: 3,
            warmth: 4,
          ),
        for (var i = 1; i <= 3; i++)
          doc(
            id: 'shoe-$i',
            name: 'Tenisky $i',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
        for (var i = 1; i <= 3; i++)
          doc(
            id: 'layer-$i',
            name: 'Bunda $i',
            canonicalType: 'rain_jacket',
            formality: 3,
            warmth: 4,
          ),
      ],
    );
    expect(
      luggageIds(result).where((id) => id.startsWith('top-')).length,
      lessThan(5),
    );
    expect(
      luggageIds(result).where((id) => id.startsWith('bottom-')).length,
      lessThan(4),
    );
    expect(
      luggageIds(result).where((id) => id.startsWith('shoe-')).length,
      1,
    );
    expect(
      luggageIds(result).where((id) => id.startsWith('layer-')).length,
      1,
    );
    for (var day = 0; day < 5; day++) {
      final ids = idsOn(result, day);
      expect(ids.where((id) => id.startsWith('top-')), hasLength(1));
      expect(ids.where((id) => id.startsWith('bottom-')), hasLength(1));
      expect(ids.where((id) => id.startsWith('shoe-')), hasLength(1));
      expect(ids.where((id) => id.startsWith('layer-')), hasLength(1));
    }
  });

  test('uncovered weather layer is reported instead of invented', () {
    final result = generate(
      input: plan(kinds: {TripKind.cityBreak}, destinationDays: 3),
      weather: resolvedDays(3, rainDay: 1, coldDay: 1),
      wardrobe: cityCore(
        extras: [
          doc(
            id: 'sneakers',
            name: 'Tenisky',
            canonicalType: 'sneakers',
            formality: 2,
            warmth: 3,
          ),
        ],
      ),
    );
    expect(
      result.missingItems.map((m) => m.nameSk),
      contains('ochranná / zateplená vrstva'),
    );
    expect(result.luggageItems.where((p) => p.id == 'invented-shell'), isEmpty);
  });

  test('live trip coverage file stays isolated from global Style Preferences', () {
    const files = [
      'lib/domain/trip/trip_packing_coverage.dart',
      'lib/Services/trip_packing_service.dart',
    ];
    for (final path in files) {
      final src = File(path).readAsStringSync();
      expect(src.contains('UserStylePreferencesReader'), isFalse, reason: path);
      expect(src.contains('StylePreferenceTasteScorer'), isFalse, reason: path);
      expect(src.contains('stylePreferences/main'), isFalse, reason: path);
    }
  });
}
