import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/calendar_outfit_service.dart';
import 'package:outfitofTheDay/Services/calendar_weather_resolver.dart';
import 'package:outfitofTheDay/Services/hourly_weather_service.dart';

OutfitWeatherDaySnapshot _hourly({
  required DateTime date,
  required bool fromOpenMeteo,
  int tempC = 18,
  bool willRain = false,
  bool isWindy = false,
}) {
  return OutfitWeatherDaySnapshot(
    cityName: 'Žilina',
    date: date,
    morningTempC: tempC - 2,
    noonTempC: tempC,
    eveningTempC: tempC - 1,
    minTempC: tempC - 3,
    maxTempC: tempC + 1,
    willRain: willRain,
    rainTimeText: willRain ? 'poobedie' : null,
    outfitWhyWeatherNote: '',
    morningRainSegment: false,
    afternoonRainSegment: willRain,
    eveningRainSegment: false,
    isWindy: isWindy,
    summaryText: '',
    fromOpenMeteo: fromOpenMeteo,
    mainChipTempC: tempC,
    mainChipBasis: fromOpenMeteo ? 'current_api' : 'fallback',
    mainChipHour: 12,
    briefingMorningCondition: '',
    briefingAfternoonCondition: '',
    briefingEveningCondition: '',
  );
}

class _FakeHourlyWeatherService extends HourlyWeatherService {
  _FakeHourlyWeatherService(this._onFetch);

  final OutfitWeatherDaySnapshot Function({
    required String city,
    required DateTime date,
  })
  _onFetch;

  String? lastCity;
  DateTime? lastDate;

  @override
  Future<OutfitWeatherDaySnapshot> getWeatherForCityAndDate({
    required String city,
    required DateTime date,
  }) async {
    lastCity = city;
    lastDate = date;
    return _onFetch(city: city, date: date);
  }
}

class _ThrowingHourlyWeatherService extends HourlyWeatherService {
  @override
  Future<OutfitWeatherDaySnapshot> getWeatherForCityAndDate({
    required String city,
    required DateTime date,
  }) async {
    throw Exception('open-meteo unavailable');
  }
}

void main() {
  group('CalendarWeatherMapper labels from provenance only', () {
    test('fromOpenMeteo == true → Predpoveď even for a distant date', () {
      final date = DateTime(2026, 8, 17).add(const Duration(days: 20));
      final mapped = CalendarWeatherMapper.fromHourlySnapshot(
        _hourly(date: date, fromOpenMeteo: true, tempC: 21, willRain: true),
      );

      expect(mapped.sourceLabel, CalendarWeatherMapper.forecastLabel);
      expect(mapped.forecastAvailable, isTrue);
      expect(mapped.tempC, 21);
      expect(mapped.isRainy, isTrue);
      expect(mapped.isWindy, isFalse);
    });

    test('fromOpenMeteo == false → Odhad even for today (0–5 day window)', () {
      final today = DateTime.now();
      final mapped = CalendarWeatherMapper.fromHourlySnapshot(
        _hourly(
          date: DateTime(today.year, today.month, today.day),
          fromOpenMeteo: false,
          tempC: 12,
          isWindy: true,
        ),
      );

      expect(mapped.sourceLabel, CalendarWeatherMapper.estimateLabel);
      expect(mapped.forecastAvailable, isFalse);
      expect(mapped.tempC, 12);
      expect(mapped.isWindy, isTrue);
      expect(mapped.sourceLabel, isNot(CalendarWeatherMapper.forecastLabel));
    });

    test('seasonal fallback date is always Odhad, never Predpoveď', () {
      final near = DateTime.now();
      final far = near.add(const Duration(days: 40));

      for (final date in [near, far]) {
        final mapped = CalendarWeatherMapper.fromFallbackDate(date);
        expect(mapped.sourceLabel, CalendarWeatherMapper.estimateLabel);
        expect(mapped.forecastAvailable, isFalse);
      }
    });
  });

  group('CalendarWeatherResolver', () {
    test('maps HourlyWeatherService Open-Meteo result for the requested date', () async {
      final date = DateTime(2026, 9, 3);
      final fake = _FakeHourlyWeatherService(
        ({required city, required date}) => _hourly(
          date: date,
          fromOpenMeteo: true,
          tempC: 16,
          willRain: true,
          isWindy: true,
        ),
      );
      final resolver = CalendarWeatherResolver(
        weatherService: fake,
        ensureLocationResolved: () async {},
        resolvedCityLabel: () => 'Žilina',
      );

      final resolved = await resolver.resolveForDate(date);

      expect(fake.lastCity, 'Žilina');
      expect(fake.lastDate, DateTime(2026, 9, 3));
      expect(resolved.sourceLabel, 'Predpoveď');
      expect(resolved.forecastAvailable, isTrue);
      expect(resolved.tempC, 16);
      expect(resolved.isRainy, isTrue);
      expect(resolved.isWindy, isTrue);
      expect(resolved.fromOpenMeteo, isTrue);
      expect(resolved.cityLabel, 'Žilina');
      expect(resolved.dateKey, '2026-09-03');
    });

    test('uses default city when location label is empty', () async {
      final fake = _FakeHourlyWeatherService(
        ({required city, required date}) =>
            _hourly(date: date, fromOpenMeteo: true),
      );
      final resolver = CalendarWeatherResolver(
        weatherService: fake,
        ensureLocationResolved: () async {},
        resolvedCityLabel: () => '  ',
      );

      await resolver.resolveForDate(DateTime(2026, 8, 17));

      expect(fake.lastCity, HourlyWeatherService.defaultWeatherCityShortLabel);
    });

    test('synthetic HourlyWeatherService fallback is labeled Odhad', () async {
      final resolver = CalendarWeatherResolver(
        weatherService: _FakeHourlyWeatherService(
          ({required city, required date}) => _hourly(
            date: date,
            fromOpenMeteo: false,
            tempC: 9,
          ),
        ),
        ensureLocationResolved: () async {},
        resolvedCityLabel: () => 'Martin',
      );

      final resolved = await resolver.resolveForDate(DateTime.now());

      expect(resolved.sourceLabel, 'Odhad');
      expect(resolved.forecastAvailable, isFalse);
      expect(resolved.tempC, 9);
    });

    test('exception falls back to seasonal estimate, not Predpoveď', () async {
      final resolver = CalendarWeatherResolver(
        weatherService: _ThrowingHourlyWeatherService(),
        ensureLocationResolved: () async {},
        resolvedCityLabel: () => 'Žilina',
      );

      final resolved = await resolver.resolveForDate(DateTime.now());

      expect(resolved.sourceLabel, 'Odhad');
      expect(resolved.forecastAvailable, isFalse);
    });
  });

  group('Calendar generation uses the resolved snapshot', () {
    test('compositionRequestFor maps the displayed snapshot, not a synthetic recompute', () {
      final displayed = CalendarWeatherMapper.fromHourlySnapshot(
        _hourly(
          date: DateTime(2026, 8, 17),
          fromOpenMeteo: true,
          tempC: 7,
          willRain: true,
          isWindy: true,
        ),
      );

      final request = CalendarOutfitService.compositionRequestFor(displayed);

      expect(request.tempC, displayed.tempC);
      expect(request.tempC, 7);
      expect(request.weatherProtectionRequired, isTrue);
      expect(request.eveningTempC, displayed.eveningTempC);
      expect(request.feelsLikeC, isNull);
      expect(request.activityType, isEmpty);
    });

    test('live Calendar paths do not call DateWeatherService.getWeatherForDate', () {
      final screen = File('lib/screens/calendar_outfit_screen.dart').readAsStringSync();
      final service = File('lib/Services/calendar_outfit_service.dart').readAsStringSync();
      final resolver = File('lib/Services/calendar_weather_resolver.dart').readAsStringSync();

      expect(screen.contains('DateWeatherService.getWeatherForDate'), isFalse);
      expect(service.contains('DateWeatherService.getWeatherForDate'), isFalse);
      expect(resolver.contains('DateWeatherService.getWeatherForDate'), isFalse);
      expect(screen.contains('diffDays'), isFalse);
      expect(resolver.contains('diffDays'), isFalse);
    });
  });
}
