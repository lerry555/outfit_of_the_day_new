import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/calendar_outfit_ownership.dart';
import 'package:outfitofTheDay/Services/calendar_weather_stale_policy.dart';
import 'package:outfitofTheDay/Services/date_weather_service.dart';
import 'package:outfitofTheDay/Services/home_daily_outfit_cache_service.dart';
import 'package:outfitofTheDay/Services/outfit_generation_service.dart';
import 'package:outfitofTheDay/models/calendar_outfit_models.dart';

final _now = DateTime(2026, 8, 17);
final _today = DateTime(2026, 8, 17);
final _tomorrow = DateTime(2026, 8, 18);
final _future = DateTime(2026, 8, 25);

HomeDailyOutfitCacheDocument _daily({
  String dateKey = '2026-08-17',
  String topLabel = 'Home top',
  List<Map<String, dynamic>>? items,
  List<String>? itemIds,
}) {
  return HomeDailyOutfitCacheDocument(
    dateKey: dateKey,
    itemIds: itemIds ?? const ['home-top'],
    items: items ??
        [
          {
            'type': 'top',
            'label': topLabel,
            'wardrobeItemId': 'home-top',
            'imageUrl': 'https://example.com/top.png',
          },
        ],
    reasonText: 'Home reason',
    weatherSignature: '20|0|0|let|0|0|0|-999|-999|-999|',
    wardrobeSignature: '1:home-top',
    source: 'ai_generated',
    userModified: false,
  );
}

CalendarOutfitDay _calendarDay({
  String dateKey = '2026-08-17',
  String label = 'Calendar top',
  int tempC = 20,
}) {
  return CalendarOutfitDay(
    dateKey: dateKey,
    weatherSnapshot: DateWeatherSnapshot(
      tempC: tempC,
      isRainy: false,
      isWindy: false,
      seasonLabel: 'Leto',
      seasonKey: 'let',
      forecastAvailable: true,
      sourceLabel: 'Predpoveď',
      summarySubtitle: 'Leto • $tempC°C • jasno',
      fromOpenMeteo: true,
      cityLabel: 'Martin',
      dateKey: dateKey,
    ),
    generationWeather: CalendarGenerationWeather(
      tempC: tempC,
      isRainy: false,
      isWindy: false,
      fromOpenMeteo: true,
      cityLabel: 'Martin',
      dateKey: dateKey,
    ),
    outfitItems: [
      CalendarOutfitItem(
        type: OutfitWearType.top,
        label: label,
        productImageUrl: null,
        cutoutImageUrl: null,
        cleanImageUrl: null,
        originalImageUrl: null,
        imageUrl: null,
        itemId: 'cal-top',
      ),
    ],
    generationSource: 'calendar',
    source: CalendarOutfitSource.calendar,
  );
}

void main() {
  group('CalendarOutfitOwnership today/tomorrow', () {
    test('today: daily + calendar → display daily, no overwrite', () {
      final result = CalendarOutfitOwnership.resolve(
        date: _today,
        now: _now,
        daily: _daily(topLabel: 'Home tee'),
        calendar: _calendarDay(label: 'Calendar tee'),
      );

      expect(result.source, CalendarOutfitSource.homeDaily);
      expect(result.hasOutfit, isTrue);
      expect(result.day!.outfitItems.first.label, 'Home tee');
      expect(result.calendarDocumentShadowed, isTrue);
      expect(result.allowsCalendarWrite, isFalse);
      expect(result.allowsCalendarStaleRefresh, isFalse);
    });

    test('tomorrow: Home daily exists → display daily', () {
      final result = CalendarOutfitOwnership.resolve(
        date: _tomorrow,
        now: _now,
        daily: _daily(dateKey: '2026-08-18', topLabel: 'Tomorrow home'),
        calendar: null,
      );

      expect(result.source, CalendarOutfitSource.homeDaily);
      expect(result.day!.outfitItems.first.label, 'Tomorrow home');
      expect(result.allowsCalendarStaleRefresh, isFalse);
    });

    test('today: no daily, calendar exists → display calendar', () {
      final result = CalendarOutfitOwnership.resolve(
        date: _today,
        now: _now,
        daily: null,
        calendar: _calendarDay(label: 'Only calendar'),
      );

      expect(result.source, CalendarOutfitSource.calendar);
      expect(result.day!.outfitItems.first.label, 'Only calendar');
      expect(result.calendarDocumentShadowed, isFalse);
      expect(result.allowsCalendarWrite, isTrue);
      expect(result.allowsCalendarStaleRefresh, isTrue);
    });

    test('today: no daily, no calendar → empty generate state', () {
      final result = CalendarOutfitOwnership.resolve(
        date: _today,
        now: _now,
        daily: null,
        calendar: null,
      );

      expect(result.source, CalendarOutfitSource.none);
      expect(result.hasOutfit, isFalse);
      expect(result.allowsCalendarWrite, isTrue);
      expect(result.allowsCalendarStaleRefresh, isFalse);
    });
  });

  group('future dates stay on Calendar', () {
    test('accidental daily doc is ignored', () {
      final result = CalendarOutfitOwnership.resolve(
        date: _future,
        now: _now,
        daily: _daily(dateKey: '2026-08-25', topLabel: 'Should ignore'),
        calendar: _calendarDay(
          dateKey: '2026-08-25',
          label: 'Planned calendar',
        ),
      );

      expect(result.source, CalendarOutfitSource.calendar);
      expect(result.day!.outfitItems.first.label, 'Planned calendar');
      expect(result.calendarDocumentShadowed, isFalse);
      expect(result.allowsCalendarStaleRefresh, isTrue);
    });
  });

  group('invalid daily falls back to Calendar', () {
    test('empty daily document is ignored', () {
      final invalid = HomeDailyOutfitCacheDocument(
        dateKey: '2026-08-17',
        itemIds: const [],
        items: const [],
        reasonText: '',
        weatherSignature: '',
        wardrobeSignature: '',
        source: 'ai_generated',
        userModified: false,
      );

      final result = CalendarOutfitOwnership.resolve(
        date: _today,
        now: _now,
        daily: invalid,
        calendar: _calendarDay(label: 'Fallback calendar'),
      );

      expect(result.source, CalendarOutfitSource.calendar);
      expect(result.day!.outfitItems.first.label, 'Fallback calendar');
    });

    test('Home parser rejects a malformed daily map', () {
      final parsed = HomeDailyOutfitCacheService.parseDocument(
        '2026-08-17',
        const {
          'items': 'not-a-list',
          'itemIds': 3,
        },
      );
      expect(parsed, isNull);

      final result = CalendarOutfitOwnership.resolve(
        date: _today,
        now: _now,
        daily: parsed,
        calendar: _calendarDay(label: 'Safe calendar'),
      );
      expect(result.source, CalendarOutfitSource.calendar);
    });
  });

  group('source awareness', () {
    test('HOME_DAILY disables Calendar overwrite and stale refresh', () {
      final result = CalendarOutfitOwnership.resolve(
        date: _today,
        now: _now,
        daily: _daily(),
        calendar: _calendarDay(tempC: 8),
      );

      expect(result.source, CalendarOutfitSource.homeDaily);
      expect(result.allowsCalendarWrite, isFalse);
      expect(result.allowsCalendarStaleRefresh, isFalse);

      final stale = CalendarWeatherStalePolicy.evaluate(
        saved: result.day!.generationWeather,
        current: const CalendarGenerationWeather(
          tempC: 8,
          isRainy: true,
          isWindy: true,
          cityLabel: 'London',
        ),
      );
      expect(result.day!.generationWeather, isNull);
      expect(stale.isStale, isFalse);
    });

    test('Calendar-owned stale outfit still allows Phase 2 refresh', () {
      final calendar = _calendarDay(tempC: 22);
      final result = CalendarOutfitOwnership.resolve(
        date: _today,
        now: _now,
        daily: null,
        calendar: calendar,
      );

      expect(result.source, CalendarOutfitSource.calendar);
      expect(result.allowsCalendarStaleRefresh, isTrue);

      final stale = CalendarWeatherStalePolicy.evaluate(
        saved: result.day!.generationWeather,
        current: const CalendarGenerationWeather(
          tempC: 10,
          isRainy: false,
          isWindy: false,
          cityLabel: 'Martin',
        ),
      );
      expect(stale.isStale, isTrue);
    });
  });

  group('adapter', () {
    test('maps Home cache items into Calendar preview fields', () {
      final day = CalendarDailyOutfitAdapter.toCalendarDay(
        dateKey: '2026-08-17',
        daily: _daily(),
      );
      expect(day, isNotNull);
      expect(day!.source, CalendarOutfitSource.homeDaily);
      expect(day.outfitItems.first.itemId, 'home-top');
      expect(day.outfitItems.first.label, 'Home top');
      expect(day.outfitItems.first.imageUrl, 'https://example.com/top.png');
      expect(day.reason, 'Home reason');
      expect(day.generationWeather, isNull);
    });
  });
}
