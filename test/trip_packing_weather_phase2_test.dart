import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/calendar_weather_resolver.dart';
import 'package:outfitofTheDay/Services/trip_destination_weather.dart';
import 'package:outfitofTheDay/Services/trip_packing_service.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_ontology_v2.dart';

class _FakeTripWeatherSource implements TripDestinationWeatherSource {
  int fetchCount = 0;
  final List<(double, double)> coordCalls = [];
  bool throwOnFetch = false;
  Map<String, TripOpenMeteoDay> Function(
    double latitude,
    double longitude,
    List<DateTime> dates,
  )?
  handler;

  @override
  Future<Map<String, TripOpenMeteoDay>> fetchRealForecastDays({
    required double latitude,
    required double longitude,
    required List<DateTime> dates,
    String? locationLabel,
  }) async {
    fetchCount += 1;
    coordCalls.add((latitude, longitude));
    if (throwOnFetch) {
      throw Exception('open-meteo-timeout');
    }
    return handler?.call(latitude, longitude, dates) ?? {};
  }
}

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
  }) {
    final def = ontology.definition(canonicalType)!;
    return {
      'id': id,
      'name': name,
      'imageUrl': 'https://example.test/$id.png',
      'ontologyVersion': WardrobeOntologyV2Values.ontologyVersion,
      'taxonomyVersion': WardrobeOntologyV2Values.taxonomyVersion,
      'kbVersion': WardrobeOntologyV2Values.kbVersion,
      'canonicalType': canonicalType,
      'canonicalFamily': def.canonicalFamily,
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
    };
  }

  List<Map<String, dynamic>> wardrobeCore() => [
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
    doc(
      id: 'sneakers',
      name: 'Tenisky',
      canonicalType: 'sneakers',
      formality: 2,
      warmth: 3,
    ),
    doc(
      id: 'sandals',
      name: 'Sandále',
      canonicalType: 'sandals',
      formality: 2,
      warmth: 2,
    ),
    doc(
      id: 'parka',
      name: 'Zimná bunda',
      canonicalType: 'winter_jacket',
      formality: 3,
      warmth: 9,
    ),
    doc(
      id: 'hike-jacket',
      name: 'Turistická bunda',
      canonicalType: 'hiking_jacket',
      formality: 2,
      warmth: 6,
    ),
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
      id: 'loafers',
      name: 'Mokasíny',
      canonicalType: 'loafers',
      formality: 6,
      warmth: 3,
    ),
    doc(
      id: 'chelsea',
      name: 'Chelsea',
      canonicalType: 'chelsea_boots',
      formality: 6,
      warmth: 5,
    ),
    doc(
      id: 'hike-shoes',
      name: 'Turistická obuv',
      canonicalType: 'hiking_shoes',
      formality: 2,
      warmth: 5,
    ),
  ];

  TripPlanInput plan({
    required Set<TripKind> kinds,
    required double lat,
    required double lon,
    String destination = 'Berlin',
    Set<TripTravelStyle> styles = const {},
  }) {
    return TripPlanInput(
      destinationText: destination,
      destinationLatitude: lat,
      destinationLongitude: lon,
      tripKinds: kinds,
      transport: TripTransport.plane,
      travelStyles: styles,
      outboundDeparture: DateTime(2026, 7, 1, 6),
      outboundArrival: DateTime(2026, 7, 1, 10),
      returnDeparture: DateTime(2026, 7, 4, 18),
      returnArrival: DateTime(2026, 7, 4, 22),
    );
  }

  TripOpenMeteoDay realDay(
    DateTime date, {
    required int high,
    required int low,
    bool rain = false,
    bool wind = false,
    String condition = 'Oblačno',
  }) {
    return TripOpenMeteoDay(
      date: date,
      highTempC: high,
      lowTempC: low,
      conditionSk: condition,
      isRainy: rain,
      isWindy: wind,
    );
  }

  Map<String, TripOpenMeteoDay> daysFor(
    List<DateTime> dates, {
    required int high,
    required int low,
    bool rain = false,
    bool wind = false,
    String condition = 'Oblačno',
  }) {
    return {
      for (final date in dates)
        CalendarWeatherMapper.dateKey(date): realDay(
          date,
          high: high,
          low: low,
          rain: rain,
          wind: wind,
          condition: condition,
        ),
    };
  }

  Future<TripPackingPlaceholderResult> generate({
    required TripPlanInput input,
    required _FakeTripWeatherSource source,
    List<Map<String, dynamic>>? wardrobe,
  }) {
    return TripPackingService.composePlaceholderPlanWithWeatherSourceForTest(
      input: input,
      wardrobeDocs: wardrobe ?? wardrobeCore(),
      weatherSource: source,
      ontology: ontology,
    );
  }

  test('real destination weather reaches outfits and is not the synthetic heuristic', () async {
    final source = _FakeTripWeatherSource()
      ..handler = (lat, lon, dates) =>
          daysFor(dates, high: 4, low: -2, condition: 'Sneženie');
    final input = plan(kinds: {TripKind.cityBreak}, lat: 52.52, lon: 13.405);
    final result = await generate(input: input, source: source);
    expect(source.fetchCount, 1);
    expect(source.coordCalls.single.$1, 52.52);
    expect(source.coordCalls.single.$2, 13.405);
    final day = result.destinationDailyPlans.first;
    expect(day.weatherHighC, 4);
    expect(day.weatherLowC, -2);
    expect(day.weatherSourceLabelSk, CalendarWeatherMapper.forecastLabel);
    expect(day.weatherForecastAvailable, isTrue);
    final synthetic = TripPackingService.syntheticWeatherForContextForTest(
      warmBeach: false,
      cityTrip: true,
      destinationText: 'Berlin',
      dayIndex: 0,
    );
    expect(day.weatherHighC, isNot(synthetic.$1));
  });

  test('unavailable Open-Meteo day uses existing synthetic fallback as Odhad', () async {
    final source = _FakeTripWeatherSource()..handler = (_, __, ___) => {};
    final input = plan(kinds: {TripKind.cityBreak}, lat: 52.52, lon: 13.405);
    final result = await generate(input: input, source: source);
    final synthetic = TripPackingService.syntheticWeatherForContextForTest(
      warmBeach: false,
      cityTrip: true,
      destinationText: 'Berlin',
      dayIndex: 0,
    );
    final day = result.destinationDailyPlans.first;
    expect(day.weatherHighC, synthetic.$1);
    expect(day.weatherLowC, synthetic.$2);
    expect(day.weatherSourceLabelSk, CalendarWeatherMapper.estimateLabel);
    expect(day.weatherForecastAvailable, isFalse);
  });

  test('API failure still generates a packing plan from fallback', () async {
    final source = _FakeTripWeatherSource()..throwOnFetch = true;
    final input = plan(kinds: {TripKind.cityBreak}, lat: 52.52, lon: 13.405);
    final result = await generate(input: input, source: source);
    expect(result.destinationDailyPlans, isNotEmpty);
    expect(result.hadWardrobeCandidates, isTrue);
    expect(
      result.destinationDailyPlans.first.weatherSourceLabelSk,
      CalendarWeatherMapper.estimateLabel,
    );
  });

  test('different destination coordinates receive their own weather', () async {
    final source = _FakeTripWeatherSource()
      ..handler = (lat, lon, dates) {
        if (lat > 50) {
          return daysFor(dates, high: 3, low: -1);
        }
        return daysFor(dates, high: 31, low: 24, condition: 'Jasno');
      };
    final berlin = await generate(
      input: plan(kinds: {TripKind.cityBreak}, lat: 52.52, lon: 13.405),
      source: source,
    );
    final malaga = await generate(
      input: plan(
        kinds: {TripKind.beach},
        lat: 36.72,
        lon: -4.42,
        destination: 'Malaga',
      ),
      source: source,
    );
    expect(berlin.destinationDailyPlans.first.weatherHighC, 3);
    expect(malaga.destinationDailyPlans.first.weatherHighC, 31);
    expect(source.coordCalls.map((c) => c.$1).toSet(), {52.52, 36.72});
  });

  test('cold real low temperature includes a warm layer', () async {
    final source = _FakeTripWeatherSource()
      ..handler = (lat, lon, dates) => daysFor(dates, high: 6, low: 1);
    final result = await generate(
      input: plan(kinds: {TripKind.cityBreak}, lat: 52.52, lon: 13.405),
      source: source,
    );
    final ids = result.destinationDailyPlans.first.pieces.map((p) => p.id);
    expect(ids, contains('parka'));
  });

  test('hot real weather avoids a heavy outer layer', () async {
    final source = _FakeTripWeatherSource()
      ..handler = (lat, lon, dates) =>
          daysFor(dates, high: 33, low: 24, condition: 'Jasno');
    final result = await generate(
      input: plan(
        kinds: {TripKind.beach},
        lat: 36.72,
        lon: -4.42,
        destination: 'Malaga',
      ),
      source: source,
    );
    final ids = result.destinationDailyPlans.first.pieces.map((p) => p.id);
    expect(ids, isNot(contains('parka')));
    expect(ids, contains('tee'));
  });

  test('rain prefers closed footwear over open sandals', () async {
    final source = _FakeTripWeatherSource()
      ..handler = (lat, lon, dates) =>
          daysFor(dates, high: 18, low: 12, rain: true, condition: 'Dážď');
    final result = await generate(
      input: plan(kinds: {TripKind.cityBreak}, lat: 52.52, lon: 13.405),
      source: source,
    );
    final ids = result.destinationDailyPlans.first.pieces.map((p) => p.id);
    expect(ids, contains('chelsea'));
    expect(ids, isNot(contains('sandals')));
  });

  test('business formality remains while rain prefers a closed formal boot', () async {
    final source = _FakeTripWeatherSource()
      ..handler = (lat, lon, dates) =>
          daysFor(dates, high: 16, low: 11, rain: true, condition: 'Dážď');
    final result = await generate(
      input: plan(kinds: {TripKind.business}, lat: 52.52, lon: 13.405),
      source: source,
    );
    final ids = result.destinationDailyPlans.first.pieces.map((p) => p.id);
    expect(ids, contains('shirt'));
    expect(ids, contains('trousers'));
    expect(ids, contains('chelsea'));
    expect(ids, isNot(contains('sandals')));
    expect(ids, isNot(contains('tee')));
  });

  test('hiking suitability still beats elegant style when weather is rainy', () async {
    final source = _FakeTripWeatherSource()
      ..handler = (lat, lon, dates) =>
          daysFor(dates, high: 14, low: 8, rain: true, condition: 'Dážď');
    final result = await generate(
      input: plan(
        kinds: {TripKind.hiking},
        lat: 49.2,
        lon: 20.2,
        styles: {TripTravelStyle.elegant},
      ),
      source: source,
    );
    final ids = result.destinationDailyPlans.first.pieces.map((p) => p.id);
    expect(ids, contains('hike-shoes'));
    expect(ids, isNot(contains('loafers')));
  });

  test('weather resolver is called once per destination window, not per wardrobe item', () async {
    final source = _FakeTripWeatherSource()
      ..handler = (lat, lon, dates) => daysFor(dates, high: 12, low: 6);
    await generate(
      input: plan(kinds: {TripKind.cityBreak}, lat: 52.52, lon: 13.405),
      source: source,
    );
    expect(source.fetchCount, 1);
    expect(source.coordCalls, hasLength(1));
  });

  test('missing destination coordinates never call Open-Meteo and stay on fallback', () {
    final result = TripPackingService.composePlaceholderPlanForTest(
      input: TripPlanInput(
        destinationText: 'Berlin',
        tripKinds: {TripKind.cityBreak},
        transport: TripTransport.plane,
        outboundDeparture: DateTime(2026, 7, 1, 6),
        outboundArrival: DateTime(2026, 7, 1, 10),
        returnDeparture: DateTime(2026, 7, 4, 18),
        returnArrival: DateTime(2026, 7, 4, 22),
      ),
      wardrobeDocs: wardrobeCore(),
      ontology: ontology,
    );
    expect(
      result.destinationDailyPlans.first.weatherSourceLabelSk,
      CalendarWeatherMapper.estimateLabel,
    );
  });

  test('Trip weather path stays isolated from global Style Preferences', () {
    const files = [
      'lib/Services/trip_destination_weather.dart',
      'lib/Services/trip_packing_service.dart',
      'lib/domain/trip/trip_intent_policy.dart',
    ];
    for (final path in files) {
      final src = File(path).readAsStringSync();
      expect(src.contains('UserStylePreferencesReader'), isFalse, reason: path);
      expect(src.contains('StylePreferenceTasteScorer'), isFalse, reason: path);
    }
  });
}
