import 'date_weather_service.dart';
import 'home_daily_outfit_cache_service.dart';
import '../models/calendar_outfit_models.dart';
import 'outfit_generation_service.dart';

/// Where the Calendar UI got the outfit currently on screen.
/// Not shown to the user.
enum CalendarOutfitSource {
  homeDaily,
  calendar,
  none,
}

class CalendarDayResolution {
  const CalendarDayResolution({
    required this.source,
    this.day,
    this.calendarDocumentShadowed = false,
  });

  final CalendarOutfitSource source;
  final CalendarOutfitDay? day;

  /// True when today/tomorrow has both a Home daily outfit and a Calendar doc.
  /// The Calendar doc is left untouched (legacy/secondary).
  final bool calendarDocumentShadowed;

  bool get hasOutfit =>
      day != null && day!.outfitItems.isNotEmpty;

  bool get allowsCalendarWrite => source != CalendarOutfitSource.homeDaily;

  bool get allowsCalendarStaleRefresh =>
      source == CalendarOutfitSource.calendar && hasOutfit;

  static const empty = CalendarDayResolution(
    source: CalendarOutfitSource.none,
  );
}

/// Today/tomorrow read ownership. Future dates stay on `calendar_outfits`.
abstract final class CalendarOutfitOwnership {
  static bool isHomeCanonicalDate(DateTime date, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final selected = DateTime(date.year, date.month, date.day);
    final diff = selected.difference(today).inDays;
    return diff == 0 || diff == 1;
  }

  static CalendarDayResolution resolve({
    required DateTime date,
    required DateTime now,
    HomeDailyOutfitCacheDocument? daily,
    CalendarOutfitDay? calendar,
  }) {
    final calendarDay =
        (calendar != null && calendar.outfitItems.isNotEmpty) ? calendar : null;

    if (!isHomeCanonicalDate(date, now: now)) {
      if (calendarDay == null) return CalendarDayResolution.empty;
      return CalendarDayResolution(
        source: CalendarOutfitSource.calendar,
        day: calendarDay,
      );
    }

    final homeDay = CalendarDailyOutfitAdapter.toCalendarDay(
      dateKey: _dateKey(date),
      daily: daily,
    );
    if (homeDay != null) {
      return CalendarDayResolution(
        source: CalendarOutfitSource.homeDaily,
        day: homeDay,
        calendarDocumentShadowed: calendarDay != null,
      );
    }
    if (calendarDay == null) return CalendarDayResolution.empty;
    return CalendarDayResolution(
      source: CalendarOutfitSource.calendar,
      day: calendarDay,
    );
  }

  static String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// Maps a Home `daily_outfits` document into Calendar presentation.
/// Isolated Calendar-side adapter; does not write Home data.
abstract final class CalendarDailyOutfitAdapter {
  static CalendarOutfitDay? toCalendarDay({
    required String dateKey,
    HomeDailyOutfitCacheDocument? daily,
  }) {
    if (daily == null) return null;
    try {
      final items = <CalendarOutfitItem>[];
      for (final raw in daily.items) {
        items.add(_itemFromHomeMap(raw));
      }
      if (items.isEmpty) {
        for (final id in daily.itemIds) {
          if (id.trim().isEmpty) continue;
          items.add(
            CalendarOutfitItem(
              type: OutfitWearType.top,
              label: 'Kúsok',
              productImageUrl: null,
              cutoutImageUrl: null,
              cleanImageUrl: null,
              originalImageUrl: null,
              imageUrl: null,
              itemId: id,
            ),
          );
        }
      }
      if (items.isEmpty) return null;
      final reason = daily.reasonText.trim();
      return CalendarOutfitDay(
        dateKey: dateKey,
        weatherSnapshot: _placeholderWeather,
        generationWeather: null,
        outfitItems: items,
        generationSource: 'home_daily',
        source: CalendarOutfitSource.homeDaily,
        updatedAt: daily.updatedAt,
        reason: reason.isEmpty ? null : reason,
      );
    } catch (_) {
      return null;
    }
  }

  static CalendarOutfitItem _itemFromHomeMap(Map<String, dynamic> raw) {
    return CalendarOutfitItem.fromMap({
      ...raw,
      'typeKey': raw['typeKey'] ?? raw['type'],
      'itemId': raw['itemId'] ?? raw['wardrobeItemId'] ?? raw['id'],
      'label': raw['label'] ?? raw['itemName'] ?? raw['name'],
    });
  }

  /// Home daily docs do not store Calendar weather provenance. The live chip
  /// still uses Phase 1 resolved weather; this placeholder is not displayed.
  static const _placeholderWeather = DateWeatherSnapshot(
    tempC: 0,
    isRainy: false,
    isWindy: false,
    seasonLabel: '',
    seasonKey: '',
    forecastAvailable: false,
    sourceLabel: '',
    summarySubtitle: '',
  );
}
