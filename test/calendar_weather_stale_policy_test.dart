import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/calendar_outfit_service.dart';
import 'package:outfitofTheDay/Services/calendar_weather_resolver.dart';
import 'package:outfitofTheDay/Services/calendar_weather_stale_policy.dart';
import 'package:outfitofTheDay/Services/hourly_weather_service.dart';
import 'package:outfitofTheDay/models/calendar_outfit_models.dart';

CalendarGenerationWeather _weather({
  required int tempC,
  bool isRainy = false,
  bool isWindy = false,
  bool? fromOpenMeteo,
  String? cityLabel,
  DateTime? fetchedAt,
  String? dateKey,
}) {
  return CalendarGenerationWeather(
    tempC: tempC,
    isRainy: isRainy,
    isWindy: isWindy,
    fromOpenMeteo: fromOpenMeteo,
    cityLabel: cityLabel,
    fetchedAt: fetchedAt,
    dateKey: dateKey,
  );
}

void main() {
  group('CalendarWeatherStalePolicy', () {
    test('20°C dry → 21°C dry is not stale', () {
      final result = CalendarWeatherStalePolicy.evaluate(
        saved: _weather(tempC: 20, cityLabel: 'Martin', fromOpenMeteo: true),
        current: _weather(tempC: 21, cityLabel: 'Martin', fromOpenMeteo: true),
      );

      expect(result.comparable, isTrue);
      expect(result.isStale, isFalse);
      expect(result.reasons, isEmpty);
    });

    test('materially colder weather is stale', () {
      final result = CalendarWeatherStalePolicy.evaluate(
        saved: _weather(tempC: 22, cityLabel: 'Martin'),
        current: _weather(tempC: 12, cityLabel: 'Martin'),
      );

      expect(result.isStale, isTrue);
      expect(
        result.reasons,
        contains(CalendarWeatherStaleReason.temperature),
      );
    });

    test('dry → rain is stale', () {
      final result = CalendarWeatherStalePolicy.evaluate(
        saved: _weather(tempC: 18, isRainy: false, cityLabel: 'Martin'),
        current: _weather(tempC: 18, isRainy: true, cityLabel: 'Martin'),
      );

      expect(result.isStale, isTrue);
      expect(result.reasons, contains(CalendarWeatherStaleReason.rain));
    });

    test('calm → wind is stale', () {
      final result = CalendarWeatherStalePolicy.evaluate(
        saved: _weather(tempC: 18, isWindy: false, cityLabel: 'Martin'),
        current: _weather(tempC: 18, isWindy: true, cityLabel: 'Martin'),
      );

      expect(result.isStale, isTrue);
      expect(result.reasons, contains(CalendarWeatherStaleReason.wind));
    });

    test('Odhad → Predpoveď with same clothing weather is not stale', () {
      final result = CalendarWeatherStalePolicy.evaluate(
        saved: _weather(
          tempC: 19,
          fromOpenMeteo: false,
          cityLabel: 'Martin',
        ),
        current: _weather(
          tempC: 19,
          fromOpenMeteo: true,
          cityLabel: 'Martin',
        ),
      );

      expect(result.isStale, isFalse);
    });

    test('Martin → London is stale even if temperatures match', () {
      final result = CalendarWeatherStalePolicy.evaluate(
        saved: _weather(tempC: 16, cityLabel: 'Martin'),
        current: _weather(tempC: 16, cityLabel: 'London'),
      );

      expect(result.isStale, isTrue);
      expect(result.reasons, contains(CalendarWeatherStaleReason.location));
    });

    test('Martin and Martin, Slovakia are the same location', () {
      final result = CalendarWeatherStalePolicy.evaluate(
        saved: _weather(tempC: 16, cityLabel: 'Martin'),
        current: _weather(tempC: 16, cityLabel: 'Martin, Slovakia'),
      );

      expect(result.isStale, isFalse);
    });

    test('fetchedAt alone does not make an outfit stale', () {
      final result = CalendarWeatherStalePolicy.evaluate(
        saved: _weather(
          tempC: 18,
          cityLabel: 'Martin',
          fetchedAt: DateTime.utc(2026, 8, 1),
        ),
        current: _weather(
          tempC: 18,
          cityLabel: 'Martin',
          fetchedAt: DateTime.utc(2026, 8, 17),
        ),
      );

      expect(result.isStale, isFalse);
    });
  });

  group('legacy Calendar documents', () {
    test('missing clothing fields are unknown, not stale', () {
      expect(CalendarGenerationWeather.tryFromSavedJson(null), isNull);
      expect(CalendarGenerationWeather.tryFromSavedJson(const {}), isNull);
      expect(
        CalendarGenerationWeather.tryFromSavedJson(const {'tempC': 18}),
        isNull,
      );

      final result = CalendarWeatherStalePolicy.evaluate(
        saved: CalendarGenerationWeather.tryFromSavedJson(const {
          'sourceLabel': 'Predpoveď',
        }),
        current: _weather(tempC: 18, cityLabel: 'London'),
      );

      expect(result.comparable, isFalse);
      expect(result.isStale, isFalse);
    });

    test('legacy clothing-only snapshot still compares without crashing', () {
      final saved = CalendarGenerationWeather.tryFromSavedJson(const {
        'tempC': 20,
        'isRainy': false,
        'isWindy': false,
        'sourceLabel': 'Predpoveď',
      });
      expect(saved, isNotNull);

      final same = CalendarWeatherStalePolicy.evaluate(
        saved: saved,
        current: _weather(tempC: 21, fromOpenMeteo: true, cityLabel: 'Martin'),
      );
      expect(same.isStale, isFalse);

      final colder = CalendarWeatherStalePolicy.evaluate(
        saved: saved,
        current: _weather(tempC: 10, fromOpenMeteo: true, cityLabel: 'Martin'),
      );
      expect(colder.isStale, isTrue);
    });

    test('CalendarOutfitDay.fromFirestore reads incomplete docs', () {
      final missingWeather = CalendarOutfitDay.fromFirestore(
        dateKey: '2026-08-17',
        data: const {
          'generationSource': 'calendar',
          'outfitItems': [
            {'typeKey': 'top', 'label': 'Tričko'},
          ],
        },
      );
      expect(missingWeather.generationWeather, isNull);
      expect(missingWeather.outfitItems, isNotEmpty);

      final emptyWeather = CalendarOutfitDay.fromFirestore(
        dateKey: '2026-08-17',
        data: const {
          'weatherSnapshot': <String, dynamic>{},
          'outfitItems': <Map<String, dynamic>>[],
        },
      );
      expect(emptyWeather.generationWeather, isNull);
      expect(emptyWeather.weatherSnapshot.sourceLabel, isNotEmpty);
    });
  });

  group('regenerate persistence', () {
    test('current resolved weather is what gets persisted and clears stale', () {
      final date = DateTime(2026, 8, 17);
      final current = CalendarWeatherMapper.fromHourlySnapshot(
        OutfitWeatherDaySnapshot(
          cityName: 'London',
          date: date,
          morningTempC: 11,
          noonTempC: 13,
          eveningTempC: 12,
          minTempC: 10,
          maxTempC: 14,
          willRain: true,
          rainTimeText: 'poobedie',
          outfitWhyWeatherNote: '',
          morningRainSegment: false,
          afternoonRainSegment: true,
          eveningRainSegment: false,
          isWindy: true,
          summaryText: '',
          fromOpenMeteo: true,
          mainChipTempC: 13,
          mainChipBasis: 'current_api',
          mainChipHour: 12,
          briefingMorningCondition: '',
          briefingAfternoonCondition: '',
          briefingEveningCondition: '',
        ),
        cityLabel: 'London',
        fetchedAt: DateTime.utc(2026, 8, 17, 10),
      );

      final payload = current.toJson();
      expect(payload['tempC'], 13);
      expect(payload['isRainy'], isTrue);
      expect(payload['isWindy'], isTrue);
      expect(payload['fromOpenMeteo'], isTrue);
      expect(payload['cityLabel'], 'London');
      expect(payload['dateKey'], '2026-08-17');
      expect(payload['fetchedAt'], isNotEmpty);
      expect(payload['sourceLabel'], 'Predpoveď');

      final saved = CalendarGenerationWeather.tryFromSavedJson(
        payload.cast<String, dynamic>(),
      );
      final afterWrite = CalendarWeatherStalePolicy.evaluate(
        saved: saved,
        current: CalendarGenerationWeather.fromSnapshot(current),
      );
      expect(afterWrite.isStale, isFalse);

      final request = CalendarOutfitService.compositionRequestFor(current);
      expect(request.tempC, 13);
      expect(request.weatherProtectionRequired, isTrue);
    });

    test('live Calendar refresh reuses generateAndSaveDay, never auto-runs', () {
      final screen = File(
        'lib/screens/calendar_outfit_screen.dart',
      ).readAsStringSync();
      final service = File(
        'lib/Services/calendar_outfit_service.dart',
      ).readAsStringSync();

      expect(screen.contains('_onRefreshStaleOutfit'), isTrue);
      expect(screen.contains('generateAndSaveDay'), isTrue);
      expect(screen.contains('NativeOutfitEngineV2'), isFalse);
      expect(service.contains('NativeOutfitEngineV2.compose'), isTrue);
      expect(service.contains('weatherSnapshot.toJson()'), isTrue);
      expect(
        screen.contains('_weatherFuture = _weatherResolver.resolveForDate'),
        isTrue,
      );
      expect(
        File('lib/screens/calendar_outfit_screen.dart').readAsStringSync().contains(
          'generateAndSaveDay',
        ),
        isTrue,
      );
      final locationHandler = _extractMethod(
        screen,
        '_onLocationCityChanged',
      );
      expect(locationHandler.contains('generateAndSaveDay'), isFalse);
      expect(locationHandler.contains('_onRefreshStaleOutfit'), isFalse);
      expect(screen.contains('Vymeniť kúsok napojíme v ďalšom kroku.'), isTrue);
      expect(screen.contains('Pridať vrstvu napojíme v ďalšom kroku.'), isTrue);
    });
  });
}

String _extractMethod(String source, String name) {
  final start = source.indexOf('void $name');
  expect(start, isNonNegative, reason: 'missing $name');
  final brace = source.indexOf('{', start);
  var depth = 0;
  for (var i = brace; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return source.substring(start);
}
