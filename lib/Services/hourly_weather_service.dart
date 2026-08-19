import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/briefing_weather_condition.dart';
import '../utils/home_debug_logging.dart';

import 'date_weather_service.dart';
import 'stylist_day_brief.dart';

class OutfitWeatherDaySnapshot {
  final String cityName;
  final DateTime date;
  final int? morningTempC;
  final int? noonTempC;
  final int? eveningTempC;
  final int? minTempC;
  final int? maxTempC;
  final bool willRain;
  final String? rainTimeText;
  /// Dlhší stylistický odstavec pre kartu „Prečo tento outfit?“ (skombinuje sa s dôvodom outfitu).
  final String outfitWhyWeatherNote;
  /// Rain in local windows 05–11 / 12–17 / 18–23 (independent of [willRain] wording).
  final bool morningRainSegment;
  final bool afternoonRainSegment;
  final bool eveningRainSegment;
  final bool isWindy;
  final String summaryText;
  /// True when built from Open-Meteo hourly data; false for deterministic fallback.
  final bool fromOpenMeteo;
  /// Hero chip + outfit line: today ≈ current / nearest hour; tomorrow ≈ daytime (12–15).
  final int mainChipTempC;
  /// Short tag for debug, e.g. `current_api`, `avg_12_15`, `fallback`.
  final String mainChipBasis;
  /// Local hour used when chip is tied to one clock hour; null when based on a range average.
  final int? mainChipHour;
  /// When [fromOpenMeteo] is false, why the service used deterministic fallback (for debugging).
  final String? openMeteoFailureNote;
  /// Krátke štítky počasia pod °C v „Prehľad dňa“ (Jasno, Dážď, …).
  final String briefingMorningCondition;
  final String briefingAfternoonCondition;
  final String briefingEveningCondition;
  /// Teploty z Open-Meteo po hodinách (index = lokálna hodina 0–23).
  final List<int?>? hourlyTempCByLocalHour;

  const OutfitWeatherDaySnapshot({
    required this.cityName,
    required this.date,
    required this.morningTempC,
    required this.noonTempC,
    required this.eveningTempC,
    required this.minTempC,
    required this.maxTempC,
    required this.willRain,
    required this.rainTimeText,
    required this.outfitWhyWeatherNote,
    required this.morningRainSegment,
    required this.afternoonRainSegment,
    required this.eveningRainSegment,
    required this.isWindy,
    required this.summaryText,
    required this.fromOpenMeteo,
    required this.mainChipTempC,
    required this.mainChipBasis,
    required this.mainChipHour,
    this.openMeteoFailureNote,
    required this.briefingMorningCondition,
    required this.briefingAfternoonCondition,
    required this.briefingEveningCondition,
    this.hourlyTempCByLocalHour,
  });

  /// Presná (alebo najbližšia) teplota v danej lokálnej hodine.
  int? tempAtLocalHour(int hour) {
    if (hour < 0 || hour > 23) return null;
    final map = hourlyTempCByLocalHour;
    if (map == null || map.length != 24) return null;
    final exact = map[hour];
    if (exact != null) return exact;
    int? nearest;
    var bestDist = 999;
    for (var h = 0; h < 24; h++) {
      final t = map[h];
      if (t == null) continue;
      final d = (h - hour).abs();
      if (d < bestDist) {
        bestDist = d;
        nearest = t;
      }
    }
    return nearest;
  }
}

class HourlyWeatherService {
  static const String _defaultCity = 'Martin, Slovakia';
  static const Duration _snapshotCacheTtl = Duration(minutes: 15);
  static final Map<String, _WeatherSnapshotCacheEntry> _snapshotCache =
      <String, _WeatherSnapshotCacheEntry>{};
  static final Map<String, Future<OutfitWeatherDaySnapshot>> _inFlightByCacheKey =
      <String, Future<OutfitWeatherDaySnapshot>>{};
  static final Map<String, Future<Map<String, OutfitWeatherDaySnapshot>>>
  _coordRangeInFlight =
      <String, Future<Map<String, OutfitWeatherDaySnapshot>>>{};

  static String _snapshotCacheKey(String cityKey, DateTime date) {
    return '$cityKey|${_dateLabelStatic(date)}';
  }

  static String _dateLabelStatic(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static OutfitWeatherDaySnapshot? _readSnapshotCache(String key) {
    final entry = _snapshotCache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.fetchedAt) >= _snapshotCacheTtl) {
      _snapshotCache.remove(key);
      return null;
    }
    return entry.snapshot;
  }

  static void _storeSnapshotCache(String key, OutfitWeatherDaySnapshot snapshot) {
    _snapshotCache[key] = _WeatherSnapshotCacheEntry(
      snapshot: snapshot,
      fetchedAt: DateTime.now(),
    );
  }

  /// Krátke označenie miesta zodpovedajúce [_defaultCity] (fallback GPS / trip prefill).
  static String get defaultWeatherCityShortLabel {
    final comma = _defaultCity.indexOf(',');
    if (comma <= 0) return _defaultCity.trim();
    return _defaultCity.substring(0, comma).trim();
  }
  static const double _martinSkLat = 49.0665;
  static const double _martinSkLon = 18.9210;
  /// Open-Meteo `hourly.time` is civil time for the requested timezone; match by date prefix
  /// so UTC `Z` rows are not dropped vs `DateTime(..., isUtc: false)` calendar compares.
  static final RegExp _openMeteoHourlyTime = RegExp(
    r'^(\d{4}-\d{2}-\d{2})T(\d{2})(?::(\d{2}))?',
  );

  Future<OutfitWeatherDaySnapshot> getWeatherForCityAndDate({
    required String city,
    required DateTime date,
  }) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final resolvedCity = city.trim().isEmpty ? _defaultCity : city.trim();
    final normalizedCityKey = resolvedCity.toLowerCase().trim();
    final cacheKey = _snapshotCacheKey(normalizedCityKey, normalizedDate);
    final cached = _readSnapshotCache(cacheKey);
    if (cached != null) {
      return cached;
    }
    final inFlight = _inFlightByCacheKey[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }
    final future = _fetchWeatherForCityAndDateImpl(
      cacheKey: cacheKey,
      normalizedDate: normalizedDate,
      resolvedCity: resolvedCity,
      normalizedCityKey: normalizedCityKey,
    );
    _inFlightByCacheKey[cacheKey] = future;
    future.whenComplete(() => _inFlightByCacheKey.remove(cacheKey));
    return future;
  }

  /// Real Open-Meteo days for explicit coordinates. One HTTP window per call.
  /// Days without hourly data are omitted so callers can apply their own fallback.
  /// Never geocodes a city name and never substitutes Home/Martin seasonal fallback.
  Future<Map<String, OutfitWeatherDaySnapshot>> getOpenMeteoForCoordinatesAndDates({
    required double latitude,
    required double longitude,
    required Iterable<DateTime> dates,
    String locationLabel = '',
  }) async {
    final wanted = <DateTime>{
      for (final date in dates) DateTime(date.year, date.month, date.day),
    }.toList()
      ..sort();
    if (wanted.isEmpty) return const {};
    final start = wanted.first;
    final end = wanted.last;
    final rangeKey =
        '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}|'
        '${_dateLabelStatic(start)}|${_dateLabelStatic(end)}';
    final inFlight = _coordRangeInFlight[rangeKey];
    if (inFlight != null) return inFlight;
    final future = _fetchOpenMeteoForCoordinatesAndDatesImpl(
      latitude: latitude,
      longitude: longitude,
      wanted: wanted,
      start: start,
      end: end,
      locationLabel: locationLabel,
    );
    _coordRangeInFlight[rangeKey] = future;
    future.whenComplete(() => _coordRangeInFlight.remove(rangeKey));
    return future;
  }

  Future<Map<String, OutfitWeatherDaySnapshot>>
  _fetchOpenMeteoForCoordinatesAndDatesImpl({
    required double latitude,
    required double longitude,
    required List<DateTime> wanted,
    required DateTime start,
    required DateTime end,
    required String locationLabel,
  }) async {
    final payload = await _fetchHourlyWeatherForDateRange(
      latitude: latitude,
      longitude: longitude,
      startDate: start,
      endDate: end,
    );
    if (payload == null || payload.points.isEmpty) return const {};
    final byDay = <String, List<_HourlyPoint>>{};
    for (final point in payload.points) {
      final time = point.time;
      if (time == null) continue;
      final key = _dateLabelStatic(time);
      (byDay[key] ??= <_HourlyPoint>[]).add(point);
    }
    final label = locationLabel.trim().isEmpty
        ? '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}'
        : locationLabel.trim();
    final out = <String, OutfitWeatherDaySnapshot>{};
    for (final date in wanted) {
      final key = _dateLabelStatic(date);
      final points = byDay[key];
      if (points == null || points.isEmpty) continue;
      out[key] = _snapshotForDestinationDay(
        locationLabel: label,
        date: date,
        points: points,
      );
    }
    return Map<String, OutfitWeatherDaySnapshot>.unmodifiable(out);
  }

  Future<OutfitWeatherDaySnapshot> _fetchWeatherForCityAndDateImpl({
    required String cacheKey,
    required DateTime normalizedDate,
    required String resolvedCity,
    required String normalizedCityKey,
  }) async {
    OutfitWeatherDaySnapshot rememberSnapshot(OutfitWeatherDaySnapshot snapshot) {
      _storeSnapshotCache(cacheKey, snapshot);
      return snapshot;
    }
    final isFixedMartin =
        normalizedCityKey == 'martin' ||
        normalizedCityKey == 'martin, slovakia' ||
        normalizedCityKey == 'martin, slovensko';

    try {
      _GeoResult? geo;
      if (isFixedMartin) {
        logVerboseHome('WEATHER USING FIXED MARTIN SK COORDINATES');
        geo = const _GeoResult(
          latitude: _martinSkLat,
          longitude: _martinSkLon,
          displayName: 'Martin, Slovensko',
        );
      } else {
        geo = await _geocodeCity(resolvedCity);
      }
      if (geo == null) {
        debugPrint('WEATHER FALLBACK reason=geocode_null city=$resolvedCity');
        return rememberSnapshot(_fallbackSnapshot(
          cityName: resolvedCity,
          date: normalizedDate,
          failureNote: 'geocode_null city=$resolvedCity',
        ));
      }

      final weather = await _fetchHourlyWeatherForDate(
        latitude: geo.latitude,
        longitude: geo.longitude,
        date: normalizedDate,
      );
      if (weather == null) {
        debugPrint('WEATHER FALLBACK reason=fetch_null day=${_dateLabel(normalizedDate)}');
        return rememberSnapshot(_fallbackSnapshot(
          cityName: geo.displayName,
          date: normalizedDate,
          failureNote: 'hourly_fetch_failed_http_or_json day=${_dateLabel(normalizedDate)}',
        ));
      }
      if (weather.points.isEmpty) {
        debugPrint(
          'WEATHER FALLBACK reason=hourly_empty_after_parse day=${_dateLabel(normalizedDate)}',
        );
        return rememberSnapshot(_fallbackSnapshot(
          cityName: geo.displayName,
          date: normalizedDate,
          failureNote:
              'hourly_empty_after_parse day=${_dateLabel(normalizedDate)} (check API params / time format)',
        ));
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final isToday = normalizedDate == today;
      final isTomorrow = normalizedDate == today.add(const Duration(days: 1));

      final currentTempC = weather.currentTemperatureC?.round();
      logVerboseHome('WEATHER CURRENT TEMP: $currentTempC isToday=$isToday');

      // Briefing windows: morning 7–9, afternoon 12–15, evening 18–21 (local hours).
      final morning = _meanTempInHourRange(weather.points, 7, 9) ??
          _tempAtHour(weather.points, 8) ??
          _tempAtHour(weather.points, 7);
      final afternoonBlock = _meanTempInHourRange(weather.points, 12, 15) ??
          _tempAtHour(weather.points, 13) ??
          _tempAtHour(weather.points, 14);
      final evening = _meanTempInHourRange(weather.points, 18, 21) ??
          _tempAtHour(weather.points, 19) ??
          _tempAtHour(weather.points, 17);

      // "Cez obed" line in summary: today may blend toward current; tomorrow stays daytime slot only.
      var noonForSummary = afternoonBlock;
      if (isToday && currentTempC != null) {
        if (noonForSummary == null || (noonForSummary - currentTempC).abs() > 8) {
          noonForSummary = currentTempC;
        }
      }

      var minMaxSource = isToday ? weather.points : _pointsLocalHourBetween(weather.points, 6, 21);
      var precipSource = isToday ? weather.points : _pointsLocalHourBetween(weather.points, 6, 21);
      var windSource = isToday ? weather.points : _pointsLocalHourBetween(weather.points, 6, 21);
      if (!isToday && minMaxSource.isEmpty) minMaxSource = weather.points;
      if (!isToday && precipSource.isEmpty) precipSource = weather.points;
      if (!isToday && windSource.isEmpty) windSource = weather.points;

      final allTemps = minMaxSource
          .map((h) => h.temperatureC)
          .whereType<double>()
          .toList(growable: false);
      final minTempC = allTemps.isEmpty
          ? null
          : allTemps.reduce((a, b) => a < b ? a : b).round();
      var maxTempC = allTemps.isEmpty
          ? null
          : allTemps.reduce((a, b) => a > b ? a : b).round();
      if (isToday && currentTempC != null) {
        maxTempC = maxTempC == null
            ? currentTempC
            : (maxTempC < currentTempC ? currentTempC : maxTempC);
      }

      // Rain per daypart only (no cross-segment reuse): 05–11, 12–17, 18–23 local.
      final rainMorning = _firstRainInLocalHourRange(precipSource, 5, 11);
      final rainAfternoon = _firstRainInLocalHourRange(precipSource, 12, 17);
      final rainEvening = _firstRainInLocalHourRange(precipSource, 18, 23);
      final willRain =
          rainMorning != null || rainAfternoon != null || rainEvening != null;

      final rainTimeText = _rainWindowsText(precipSource);

      logVerboseHome(
        'WEATHER rain_segment morning=${rainMorning?.time} afternoon=${rainAfternoon?.time} '
        'evening=${rainEvening?.time} windows=$rainTimeText',
      );

      final isWindy = windSource.any((h) => (h.windSpeedKmh ?? 0) >= 25);

      final summaryText = _buildSummaryText(
        morningTempC: morning,
        noonTempC: noonForSummary,
        eveningTempC: evening,
        minTempC: minTempC,
        maxTempC: maxTempC,
        rainMorning: rainMorning,
        rainAfternoon: rainAfternoon,
        rainEvening: rainEvening,
        isWindy: isWindy,
        currentTempC: isToday ? currentTempC : null,
      );

      late final int mainChipTempC;
      late final String mainChipBasis;
      int? mainChipHour;
      if (isToday) {
        if (currentTempC != null) {
          mainChipTempC = currentTempC;
          mainChipBasis = 'current_api';
          mainChipHour = now.hour;
        } else {
          final near = _tempAtHour(weather.points, now.hour);
          if (near != null) {
            mainChipTempC = near;
            mainChipBasis = 'nearest_hour';
            mainChipHour = now.hour;
          } else {
            mainChipTempC = afternoonBlock ?? morning ?? evening ?? 15;
            mainChipBasis = afternoonBlock != null ? 'afternoon_12_15' : 'hourly_fallback';
            mainChipHour = afternoonBlock != null ? null : 13;
          }
        }
      } else {
        final avg1215 = _meanTempInHourRange(weather.points, 12, 15);
        final h13 = _tempAtHour(weather.points, 13);
        final daytimePeak = _maxTempInHourRange(weather.points, 10, 17);
        if (avg1215 != null) {
          mainChipTempC = avg1215;
          mainChipBasis = 'avg_12_15';
          // Nominal center hour for logs / UX (range is 12–15).
          mainChipHour = 14;
        } else if (h13 != null) {
          mainChipTempC = h13;
          mainChipBasis = 'hour_13';
          mainChipHour = 13;
        } else if (daytimePeak != null) {
          mainChipTempC = daytimePeak;
          mainChipBasis = 'daytime_max_10_17';
          mainChipHour = null;
        } else {
          mainChipTempC = afternoonBlock ?? morning ?? evening ?? 15;
          mainChipBasis = 'sparse_fallback';
          mainChipHour = null;
        }
      }

      final mt = morning ?? afternoonBlock ?? mainChipTempC;
      final at = afternoonBlock ?? morning ?? mainChipTempC;
      final et = evening ?? afternoonBlock ?? mainChipTempC;
      final morningRainSeg = rainMorning != null && rainMorning.hasData;
      final afternoonRainSeg = rainAfternoon != null && rainAfternoon.hasData;
      final eveningRainSeg = rainEvening != null && rainEvening.hasData;
      final windMorning = _windStrongInRange(windSource, 5, 11);
      final windAfternoon = _windStrongInRange(windSource, 12, 17);
      final windEvening = _windStrongInRange(windSource, 18, 23);

      final wcMorning = _dominantWeatherCodeInRange(weather.points, 7, 9);
      final wcAfternoon = _dominantWeatherCodeInRange(weather.points, 12, 15);
      final wcEvening = _dominantWeatherCodeInRange(weather.points, 18, 21);

      final briefingMorningCondition = BriefingWeatherCondition.briefingUiSk(
        BriefingWeatherCondition.label(
          wmoCode: wcMorning,
          segmentRain: morningRainSeg,
          segmentWindy: windMorning,
          segment: BriefingDaySegment.morning,
        ),
      );
      final briefingAfternoonCondition = BriefingWeatherCondition.briefingUiSk(
        BriefingWeatherCondition.label(
          wmoCode: wcAfternoon,
          segmentRain: afternoonRainSeg,
          segmentWindy: windAfternoon,
          segment: BriefingDaySegment.afternoon,
        ),
      );
      final briefingEveningCondition = BriefingWeatherCondition.briefingUiSk(
        BriefingWeatherCondition.label(
          wmoCode: wcEvening,
          segmentRain: eveningRainSeg,
          segmentWindy: windEvening,
          segment: BriefingDaySegment.evening,
        ),
      );

      final ux = buildDayWeatherUx(
        date: normalizedDate,
        isTomorrow: isTomorrow,
        morningTempC: mt,
        afternoonTempC: at,
        eveningTempC: et,
        mainChipTempC: mainChipTempC,
        minTempC: minTempC,
        maxTempC: maxTempC,
        willRain: willRain,
        morningRain: morningRainSeg,
        afternoonRain: afternoonRainSeg,
        eveningRain: eveningRainSeg,
        isWindy: isWindy,
        windMorning: windMorning,
        windAfternoon: windAfternoon,
        windEvening: windEvening,
      );

      logVerboseHome(
        'WEATHER briefing_segments mt=$mt at=$at et=$et '
        'rainSegMorning=$morningRainSeg rainSegAfternoon=$afternoonRainSeg rainSegEvening=$eveningRainSeg '
        'windSegMorning=$windMorning windSegAfternoon=$windAfternoon windSegEvening=$windEvening',
      );
      logVerboseHome(
        'WEATHER stylist_ux outfitWhy="${ux.outfitWhyWeatherNote}"',
      );

      logVerboseHome(
        'WEATHER dayparts: morning=$morning afternoonBlock=$afternoonBlock evening=$evening '
        'mainChip=$mainChipTempC ($mainChipBasis h=$mainChipHour) rainTime=$rainTimeText windy=$isWindy',
      );
      logVerboseHome(
        'WEATHER FINAL SNAPSHOT: city=${geo.displayName} isToday=$isToday morning=$morning afternoon=$afternoonBlock evening=$evening '
        'min=$minTempC max=$maxTempC rain=$willRain rainTime=$rainTimeText windy=$isWindy summary="$summaryText"',
      );

      logVerboseHome(
        'WEATHER OPEN_METEO_OK day=${_dateLabel(normalizedDate)} isToday=$isToday '
        'hourlyCount=${weather.points.length} mainChipTempC=$mainChipTempC '
        'mainChipBasis=$mainChipBasis mainChipHour=$mainChipHour '
        'morning=$morning afternoon=$afternoonBlock evening=$evening '
        'rainSegMorning=${rainMorning?.time} rainSegAfternoon=${rainAfternoon?.time} rainSegEvening=${rainEvening?.time} '
        'rainSegMorningB=$morningRainSeg rainSegAfternoonB=$afternoonRainSeg rainSegEveningB=$eveningRainSeg',
      );

      final hourlyTempMap = _hourlyTempMap(weather.points);

      final snapshot = OutfitWeatherDaySnapshot(
        cityName: geo.displayName,
        date: normalizedDate,
        morningTempC: morning ?? afternoonBlock ?? mainChipTempC,
        noonTempC: afternoonBlock ?? morning ?? mainChipTempC,
        eveningTempC: evening ?? afternoonBlock ?? mainChipTempC,
        minTempC: minTempC,
        maxTempC: maxTempC,
        willRain: willRain,
        rainTimeText: rainTimeText,
        outfitWhyWeatherNote: ux.outfitWhyWeatherNote,
        morningRainSegment: morningRainSeg,
        afternoonRainSegment: afternoonRainSeg,
        eveningRainSegment: eveningRainSeg,
        isWindy: isWindy,
        summaryText: summaryText,
        fromOpenMeteo: true,
        mainChipTempC: mainChipTempC,
        mainChipBasis: mainChipBasis,
        mainChipHour: mainChipHour,
        openMeteoFailureNote: null,
        briefingMorningCondition: briefingMorningCondition,
        briefingAfternoonCondition: briefingAfternoonCondition,
        briefingEveningCondition: briefingEveningCondition,
        hourlyTempCByLocalHour: hourlyTempMap,
      );
      _storeSnapshotCache(cacheKey, snapshot);
      return snapshot;
    } catch (e) {
      debugPrint('WEATHER FALLBACK reason=exception $e');
      return rememberSnapshot(_fallbackSnapshot(
        cityName: resolvedCity,
        date: normalizedDate,
        failureNote: 'exception ${e.toString()}',
      ));
    }
  }

  Future<_GeoResult?> _geocodeCity(String city) async {
    final normalizedCity = city.trim();
    if (normalizedCity.isEmpty) return null;
    final lower = normalizedCity.toLowerCase();

    for (final query in _geocodeQueriesFor(normalizedCity, lower)) {
      final hit = await _geocodeSearch(query, lower);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Slovenské/české exonymá → názvy, ktoré pozná open-meteo geokóder.
  static const Map<String, List<String>> _exonyms = {
    'mníchov': ['Munich, Germany', 'München'],
    'mnichov': ['Munich, Germany', 'München'],
    'viedeň': ['Vienna, Austria', 'Wien'],
    'vieden': ['Vienna, Austria', 'Wien'],
    'norimberg': ['Nuremberg, Germany', 'Nürnberg'],
    'drážďany': ['Dresden, Germany'],
    'drazdany': ['Dresden, Germany'],
    'benátky': ['Venice, Italy', 'Venezia'],
    'benatky': ['Venice, Italy', 'Venezia'],
    'rím': ['Rome, Italy', 'Roma'],
    'rim': ['Rome, Italy', 'Roma'],
    'miláno': ['Milan, Italy', 'Milano'],
    'milano': ['Milan, Italy', 'Milano'],
    'paríž': ['Paris, France'],
    'pariz': ['Paris, France'],
    'londýn': ['London, United Kingdom'],
    'londyn': ['London, United Kingdom'],
    'varšava': ['Warsaw, Poland', 'Warszawa'],
    'varsava': ['Warsaw, Poland', 'Warszawa'],
    'krakov': ['Krakow, Poland', 'Kraków'],
    'budapešť': ['Budapest, Hungary'],
    'budapest': ['Budapest, Hungary'],
    'paríža': ['Paris, France'],
    'praha': ['Prague, Czechia', 'Praha'],
    'berlín': ['Berlin, Germany'],
    'atény': ['Athens, Greece'],
    'ateny': ['Athens, Greece'],
    'lisabon': ['Lisbon, Portugal'],
    'kodaň': ['Copenhagen, Denmark'],
    'kodan': ['Copenhagen, Denmark'],
  };

  List<String> _geocodeQueriesFor(String city, String lower) {
    if (lower == 'martin' ||
        lower == 'martin, slovensko' ||
        lower == 'martin, slovakia') {
      return const ['Martin, Slovakia'];
    }
    // Exonymá (Mníchov → Munich…). Skontrolujeme aj základný tvar bez koncovky.
    for (final entry in _exonyms.entries) {
      if (lower == entry.key || lower.startsWith('${entry.key},')) {
        return entry.value;
      }
    }
    if (lower.contains('galway')) {
      return const ['Galway, Ireland', 'Galway'];
    }
    if (lower.contains('dublin')) {
      return const ['Dublin, Ireland', 'Dublin'];
    }
    if (lower.contains('london')) {
      return const ['London, United Kingdom', 'London'];
    }
    if (lower.contains('žilin') || lower.contains('zilina')) {
      return const ['Žilina, Slovakia', 'Žilina'];
    }

    // Všeobecná snaha nájsť aj menšie obce: skúsime viac tvarov.
    final queries = <String>[];
    void add(String q) {
      final t = q.trim();
      if (t.isEmpty) return;
      if (!queries.map((e) => e.toLowerCase()).contains(t.toLowerCase())) {
        queries.add(t);
      }
    }

    add(city);
    add('$city, Slovakia');

    // Lokál → nominatív (napr. „Dolných Honoch“ → „Dolné Hony“,
    // „Vyšných Ružbachoch“ → „Vyšné Ružbachy“, „Žiline“ → „Žilina“).
    final nominative = _slovakLocativeToNominative(city);
    if (nominative.toLowerCase() != city.toLowerCase()) {
      add(nominative);
      add('$nominative, Slovakia');
    }

    // Bez diakritiky (geokóder niekedy lepšie matchuje ASCII).
    final ascii = _stripDiacritics(nominative);
    if (ascii.toLowerCase() != nominative.toLowerCase()) {
      add('$ascii, Slovakia');
      add(ascii);
    }

    return queries;
  }

  /// Veľmi jednoduchý prevod častých slovenských lokálových koncoviek na
  /// nominatív, aby sa dali geokódovať aj obce zadané v skloňovanom tvare.
  String _slovakLocativeToNominative(String city) {
    final words = city.trim().split(RegExp(r'\s+'));
    final out = words.map(_wordLocativeToNominative).toList();
    return out.join(' ');
  }

  String _wordLocativeToNominative(String word) {
    final lower = word.toLowerCase();
    String? base;
    // Prídavné mená v množnom lokáli: „dolných“ → „dolné“, „vyšných“ → „vyšné“.
    if (lower.endsWith('ných')) {
      base = '${word.substring(0, word.length - 4)}né';
    } else if (lower.endsWith('ých')) {
      base = '${word.substring(0, word.length - 3)}é';
    } else if (lower.endsWith('ích')) {
      base = '${word.substring(0, word.length - 3)}ie';
    }
    // Podstatné mená v množnom lokáli: „honoch“ → „hony“,
    // „ružbachoch“ → „ružbachy“, „tatrách“ → „tatry“.
    else if (lower.endsWith('och')) {
      base = '${word.substring(0, word.length - 3)}y';
    } else if (lower.endsWith('ách')) {
      base = '${word.substring(0, word.length - 3)}y';
    } else if (lower.endsWith('iach')) {
      base = '${word.substring(0, word.length - 4)}e';
    }
    // Jednotné číslo lokál: „Martine“ → „Martin“, „Trenčíne“ → „Trenčín“.
    else if (lower.endsWith('e') && word.length > 4) {
      base = word.substring(0, word.length - 1);
    }
    return base ?? word;
  }

  String _stripDiacritics(String input) {
    const map = {
      'á': 'a', 'ä': 'a', 'č': 'c', 'ď': 'd', 'é': 'e', 'í': 'i', 'ĺ': 'l',
      'ľ': 'l', 'ň': 'n', 'ó': 'o', 'ô': 'o', 'ŕ': 'r', 'š': 's', 'ť': 't',
      'ú': 'u', 'ý': 'y', 'ž': 'z',
      'Á': 'A', 'Ä': 'A', 'Č': 'C', 'Ď': 'D', 'É': 'E', 'Í': 'I', 'Ĺ': 'L',
      'Ľ': 'L', 'Ň': 'N', 'Ó': 'O', 'Ô': 'O', 'Ŕ': 'R', 'Š': 'S', 'Ť': 'T',
      'Ú': 'U', 'Ý': 'Y', 'Ž': 'Z',
    };
    final sb = StringBuffer();
    for (final ch in input.split('')) {
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }

  Future<_GeoResult?> _geocodeSearch(String queryName, String originalLower) async {
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': queryName,
      'count': '10',
      'language': 'en',
      'format': 'json',
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;

    final raw = jsonDecode(response.body);
    if (raw is! Map<String, dynamic>) return null;
    final results = raw['results'];
    if (results is! List || results.isEmpty) return null;
    final maps = results.whereType<Map>().toList(growable: false);
    if (maps.isEmpty) return null;

    bool isCountryCode(Map item, String code) {
      return item['country_code']?.toString().toUpperCase().trim() == code;
    }

    bool isSlovakResult(Map item) {
      final code = item['country_code']?.toString().toUpperCase().trim();
      final country = item['country']?.toString().toLowerCase().trim() ?? '';
      return code == 'SK' || country == 'slovakia' || country == 'slovensko';
    }

    final preferIe = originalLower.contains('galway') ||
        originalLower.contains('dublin') ||
        originalLower.contains('irsko') ||
        originalLower.contains('irsku') ||
        originalLower.contains('ireland');
    final preferGb = originalLower.contains('london') ||
        originalLower.contains('uk') ||
        originalLower.contains('anglick') ||
        originalLower.contains('britain');
    final preferSk = originalLower.contains('slovens') ||
        originalLower.contains('žilin') ||
        originalLower.contains('zilina') ||
        originalLower == 'martin' ||
        queryName.toLowerCase().contains('slovakia');

    Map selected;
    if (preferGb) {
      selected = maps.firstWhere(
        (m) => isCountryCode(m, 'GB'),
        orElse: () => maps.first,
      );
    } else if (preferIe) {
      selected = maps.firstWhere(
        (m) => isCountryCode(m, 'IE'),
        orElse: () => maps.first,
      );
    } else if (preferSk) {
      selected = maps.firstWhere(
        isSlovakResult,
        orElse: () => maps.first,
      );
    } else {
      selected = maps.first;
    }

    final latitude = (selected['latitude'] as num?)?.toDouble();
    final longitude = (selected['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;

    final name = selected['name']?.toString().trim();
    final country = selected['country']?.toString().trim();
    final countryCode = selected['country_code']?.toString().toUpperCase().trim();
    final countryLabel = (countryCode == 'SK' ||
            country?.toLowerCase() == 'slovakia' ||
            country?.toLowerCase() == 'slovensko')
        ? 'Slovensko'
        : country;
    final displayName = [
      if (name != null && name.isNotEmpty) name,
      if (countryLabel != null && countryLabel.isNotEmpty) countryLabel,
    ].join(', ');

    return _GeoResult(
      latitude: latitude,
      longitude: longitude,
      displayName: displayName.isEmpty ? queryName : displayName,
    );
  }

  Future<_HourlyWeatherPayload?> _fetchHourlyWeatherForDate({
    required double latitude,
    required double longitude,
    required DateTime date,
  }) {
    return _fetchHourlyWeatherForDateRange(
      latitude: latitude,
      longitude: longitude,
      startDate: date,
      endDate: date,
    );
  }

  Future<_HourlyWeatherPayload?> _fetchHourlyWeatherForDateRange({
    required double latitude,
    required double longitude,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    var start = DateTime(startDate.year, startDate.month, startDate.day);
    var end = DateTime(endDate.year, endDate.month, endDate.day);
    if (end.isBefore(start)) {
      final swap = start;
      start = end;
      end = swap;
    }
    final startLabel = _dateLabel(start);
    final endLabel = _dateLabel(end);
    // Do NOT combine `forecast_days` with `start_date`/`end_date` — Open-Meteo returns 400.
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'temperature_2m',
      'hourly':
          'temperature_2m,precipitation_probability,precipitation,wind_speed_10m,weather_code',
      'timezone': 'auto',
      'start_date': startLabel,
      'end_date': endLabel,
    });
    logVerboseHome('WEATHER API URL: $uri');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      debugPrint(
        'WEATHER FALLBACK reason=http_${response.statusCode} body_head=${response.body.length > 160 ? response.body.substring(0, 160) : response.body}',
      );
      return null;
    }

    final raw = jsonDecode(response.body);
    if (raw is! Map<String, dynamic>) {
      debugPrint('WEATHER FALLBACK reason=json_not_map_forecast_body');
      return null;
    }
    final current = raw['current'];
    final currentTemperatureC =
        current is Map<String, dynamic> ? (current['temperature_2m'] as num?)?.toDouble() : null;
    final hourly = raw['hourly'];
    if (hourly is! Map<String, dynamic>) {
      debugPrint('WEATHER FALLBACK reason=hourly_block_missing_or_invalid keys=${raw.keys.join(",")}');
      return null;
    }

    final times = (hourly['time'] as List?)?.map((v) => v.toString()).toList() ?? const <String>[];
    final temps = (hourly['temperature_2m'] as List?)?.map((v) => (v as num?)?.toDouble()).toList() ??
        const <double?>[];
    final precipitationProbabilities = (hourly['precipitation_probability'] as List?)
            ?.map((v) => (v as num?)?.toDouble())
            .toList() ??
        const <double?>[];
    final precipitation = (hourly['precipitation'] as List?)
            ?.map((v) => (v as num?)?.toDouble())
            .toList() ??
        const <double?>[];
    final windSpeed = (hourly['wind_speed_10m'] as List?)
            ?.map((v) => (v as num?)?.toDouble())
            .toList() ??
        const <double?>[];
    final weatherCodes = (hourly['weather_code'] as List?)
            ?.map((v) => (v as num?)?.toInt())
            .toList() ??
        const <int?>[];

    final len = times.length;
    final points = <_HourlyPoint>[];

    bool inWindow(String ymd) =>
        ymd.compareTo(startLabel) >= 0 && ymd.compareTo(endLabel) <= 0;

    DateTime? wallFromYmd(String ymd, int hh, int mm) {
      final parts = ymd.split('-');
      if (parts.length != 3) return null;
      final y = int.tryParse(parts[0]);
      final mo = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || mo == null || d == null) return null;
      return DateTime(y, mo, d, hh, mm);
    }

    void addPoint(int i, DateTime wall) {
      points.add(
        _HourlyPoint(
          time: wall,
          temperatureC: i < temps.length ? temps[i] : null,
          precipitationProbability:
              i < precipitationProbabilities.length ? precipitationProbabilities[i] : null,
          precipitationMm: i < precipitation.length ? precipitation[i] : null,
          windSpeedKmh: i < windSpeed.length ? windSpeed[i] : null,
          weatherCode: i < weatherCodes.length ? weatherCodes[i] : null,
        ),
      );
    }

    for (var i = 0; i < len; i++) {
      final rawTime = times[i].trim();
      final m = _openMeteoHourlyTime.firstMatch(rawTime);
      if (m == null) continue;
      final ymd = m.group(1)!;
      if (!inWindow(ymd)) continue;
      final hh = int.tryParse(m.group(2)!) ?? 0;
      final mm = int.tryParse(m.group(3) ?? '0') ?? 0;
      final wall = wallFromYmd(ymd, hh, mm);
      if (wall == null) continue;
      addPoint(i, wall);
    }

    if (points.isEmpty) {
      logVerboseHome(
        'WEATHER hourly_parse: prefix_match_empty start=$startLabel end=$endLabel rawLen=$len — trying legacy local-date filter',
      );
      for (var i = 0; i < len; i++) {
        final time = DateTime.tryParse(times[i]);
        if (time == null) continue;
        final localHourDate = DateTime(time.year, time.month, time.day);
        if (localHourDate.isBefore(start) || localHourDate.isAfter(end)) {
          continue;
        }
        addPoint(i, time);
      }
    }

    logVerboseHome(
      'WEATHER API_OK start=$startLabel end=$endLabel rawHourly=$len pointsParsed=${points.length} '
      'currentTemp=${currentTemperatureC?.toStringAsFixed(1)}',
    );

    return _HourlyWeatherPayload(
      points: points,
      currentTemperatureC: currentTemperatureC,
    );
  }

  int? _dominantWeatherCodeInRange(List<_HourlyPoint> pts, int minH, int maxH) {
    final codes = pts
        .where((p) {
          final h = p.time?.hour;
          return h != null && h >= minH && h <= maxH;
        })
        .map((p) => p.weatherCode)
        .whereType<int>()
        .toList(growable: false);
    if (codes.isEmpty) return null;
    final counts = <int, int>{};
    for (final c in codes) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  int? _tempAtHour(List<_HourlyPoint> hours, int hour) {
    _HourlyPoint? exact;
    for (final h in hours) {
      if (h.time?.hour == hour) {
        exact = h;
        break;
      }
    }
    final selected = exact ??
        (hours.isEmpty
            ? null
            : hours.reduce((a, b) {
                final da = (a.time?.hour ?? 0) - hour;
                final db = (b.time?.hour ?? 0) - hour;
                return da.abs() <= db.abs() ? a : b;
              }));
    return selected?.temperatureC?.round();
  }

  List<int?> _hourlyTempMap(List<_HourlyPoint> points) {
    final out = List<int?>.filled(24, null);
    for (final p in points) {
      final h = p.time?.hour;
      if (h != null && h >= 0 && h <= 23) {
        out[h] = p.temperatureC?.round();
      }
    }
    return out;
  }

  List<_HourlyPoint> _pointsLocalHourBetween(List<_HourlyPoint> hours, int minH, int maxH) {
    return hours.where((p) {
      final h = p.time?.hour;
      return h != null && h >= minH && h <= maxH;
    }).toList(growable: false);
  }

  int? _meanTempInHourRange(List<_HourlyPoint> hours, int minH, int maxH) {
    final sub = _pointsLocalHourBetween(hours, minH, maxH);
    final vals = sub.map((e) => e.temperatureC).whereType<double>().toList(growable: false);
    if (vals.isEmpty) return null;
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    return avg.round();
  }

  int? _maxTempInHourRange(List<_HourlyPoint> hours, int minH, int maxH) {
    final sub = _pointsLocalHourBetween(hours, minH, maxH);
    final vals = sub.map((e) => e.temperatureC).whereType<double>().toList(growable: false);
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a > b ? a : b).round();
  }

  bool _pointLooksRainy(_HourlyPoint p) {
    return (p.precipitationProbability ?? 0) >= 50 || (p.precipitationMm ?? 0) > 0.2;
  }

  String? _rainWindowsText(List<_HourlyPoint> pts) {
    final rainyHours = pts
        .where((p) => p.time != null && _pointLooksRainy(p))
        .map((p) => DateTime(
              p.time!.year,
              p.time!.month,
              p.time!.day,
              p.time!.hour,
            ))
        .toList()
      ..sort();
    if (rainyHours.isEmpty) return null;

    final windows = <({DateTime start, DateTime end})>[];
    var start = rainyHours.first;
    var end = start.add(const Duration(hours: 1));
    for (final hour in rainyHours.skip(1)) {
      final gap = hour.difference(end).inMinutes;
      // Merge adjacent rain and one-hour gaps so 13:00 + 15:00 reads as 13:00-16:00.
      if (gap <= 60) {
        final candidateEnd = hour.add(const Duration(hours: 1));
        if (candidateEnd.isAfter(end)) end = candidateEnd;
      } else {
        windows.add((start: start, end: end));
        start = hour;
        end = hour.add(const Duration(hours: 1));
      }
    }
    windows.add((start: start, end: end));

    final labels = windows
        .map((w) => '${_hourLabel(w.start)}-${_hourLabel(w.end)}')
        .toList(growable: false);
    if (labels.length == 1) return labels.single;
    if (labels.length == 2) return '${labels[0]} a ${labels[1]}';
    return '${labels.take(labels.length - 1).join(', ')} a ${labels.last}';
  }

  /// First chronologically rainy hour inside [minHInclusive, maxHInclusive] (local wall hour).
  _HourlyPoint? _firstRainInLocalHourRange(
    List<_HourlyPoint> pts,
    int minHInclusive,
    int maxHInclusive,
  ) {
    for (final p in pts) {
      final h = p.time?.hour;
      if (h == null) continue;
      if (h < minHInclusive || h > maxHInclusive) continue;
      if (_pointLooksRainy(p)) return p;
    }
    return null;
  }

  bool _windStrongInRange(
    List<_HourlyPoint> pts,
    int minHInclusive,
    int maxHInclusive, {
    double kmh = 25,
  }) {
    for (final p in pts) {
      final h = p.time?.hour;
      if (h == null) continue;
      if (h < minHInclusive || h > maxHInclusive) continue;
      if ((p.windSpeedKmh ?? 0) >= kmh) return true;
    }
    return false;
  }

  OutfitWeatherDaySnapshot _snapshotForDestinationDay({
    required String locationLabel,
    required DateTime date,
    required List<_HourlyPoint> points,
  }) {
    var minMaxSource = _pointsLocalHourBetween(points, 6, 21);
    if (minMaxSource.isEmpty) minMaxSource = points;
    final temps = minMaxSource
        .map((h) => h.temperatureC)
        .whereType<double>()
        .toList(growable: false);
    final minTempC = temps.isEmpty
        ? null
        : temps.reduce((a, b) => a < b ? a : b).round();
    final maxTempC = temps.isEmpty
        ? null
        : temps.reduce((a, b) => a > b ? a : b).round();
    final morning = _meanTempInHourRange(points, 7, 9) ?? _tempAtHour(points, 8);
    final afternoon =
        _meanTempInHourRange(points, 12, 15) ?? _tempAtHour(points, 13);
    final evening =
        _meanTempInHourRange(points, 18, 21) ?? _tempAtHour(points, 19);
    final rainMorning = _firstRainInLocalHourRange(minMaxSource, 5, 11);
    final rainAfternoon = _firstRainInLocalHourRange(minMaxSource, 12, 17);
    final rainEvening = _firstRainInLocalHourRange(minMaxSource, 18, 23);
    final willRain =
        rainMorning != null || rainAfternoon != null || rainEvening != null;
    final isWindy = minMaxSource.any((h) => (h.windSpeedKmh ?? 0) >= 25);
    final morningRainSeg = rainMorning != null && rainMorning.hasData;
    final afternoonRainSeg = rainAfternoon != null && rainAfternoon.hasData;
    final eveningRainSeg = rainEvening != null && rainEvening.hasData;
    final windMorning = _windStrongInRange(minMaxSource, 5, 11);
    final windAfternoon = _windStrongInRange(minMaxSource, 12, 17);
    final windEvening = _windStrongInRange(minMaxSource, 18, 23);
    final briefingAfternoonCondition = BriefingWeatherCondition.briefingUiSk(
      BriefingWeatherCondition.label(
        wmoCode: _dominantWeatherCodeInRange(points, 12, 15),
        segmentRain: afternoonRainSeg,
        segmentWindy: windAfternoon,
        segment: BriefingDaySegment.afternoon,
      ),
    );
    final mainChip = afternoon ?? maxTempC ?? morning ?? evening ?? 15;
    return OutfitWeatherDaySnapshot(
      cityName: locationLabel,
      date: date,
      morningTempC: morning ?? afternoon ?? mainChip,
      noonTempC: afternoon ?? morning ?? mainChip,
      eveningTempC: evening ?? afternoon ?? mainChip,
      minTempC: minTempC,
      maxTempC: maxTempC,
      willRain: willRain,
      rainTimeText: _rainWindowsText(minMaxSource),
      outfitWhyWeatherNote: '',
      morningRainSegment: morningRainSeg,
      afternoonRainSegment: afternoonRainSeg,
      eveningRainSegment: eveningRainSeg,
      isWindy: isWindy,
      summaryText: briefingAfternoonCondition,
      fromOpenMeteo: true,
      mainChipTempC: mainChip,
      mainChipBasis: 'destination_window',
      mainChipHour: afternoon != null ? 14 : null,
      openMeteoFailureNote: null,
      briefingMorningCondition: BriefingWeatherCondition.briefingUiSk(
        BriefingWeatherCondition.label(
          wmoCode: _dominantWeatherCodeInRange(points, 7, 9),
          segmentRain: morningRainSeg,
          segmentWindy: windMorning,
          segment: BriefingDaySegment.morning,
        ),
      ),
      briefingAfternoonCondition: briefingAfternoonCondition,
      briefingEveningCondition: BriefingWeatherCondition.briefingUiSk(
        BriefingWeatherCondition.label(
          wmoCode: _dominantWeatherCodeInRange(points, 18, 21),
          segmentRain: eveningRainSeg,
          segmentWindy: windEvening,
          segment: BriefingDaySegment.evening,
        ),
      ),
      hourlyTempCByLocalHour: _hourlyTempMap(points),
    );
  }

  OutfitWeatherDaySnapshot _fallbackSnapshot({
    required String cityName,
    required DateTime date,
    String? failureNote,
  }) {
    final fallback = DateWeatherService.getFallbackWeatherForDate(date);
    final mt = fallback.tempC - 2;
    final at = fallback.tempC;
    final et = fallback.tempC - 1;
    const morningRainSeg = false;
    final afternoonRainSeg = fallback.isRainy;
    const eveningRainSeg = false;
    final w = fallback.isWindy;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final isTomorrow = d == today.add(const Duration(days: 1));
    final minT = fallback.tempC - 3;
    final maxT = fallback.tempC + 1;
    final ux = buildDayWeatherUx(
      date: d,
      isTomorrow: isTomorrow,
      morningTempC: mt,
      afternoonTempC: at,
      eveningTempC: et,
      mainChipTempC: fallback.tempC,
      minTempC: minT,
      maxTempC: maxT,
      willRain: fallback.isRainy,
      morningRain: morningRainSeg,
      afternoonRain: afternoonRainSeg,
      eveningRain: eveningRainSeg,
      isWindy: w,
      windMorning: w,
      windAfternoon: w,
      windEvening: w,
    );
    logVerboseHome(
      'WEATHER briefing_segments mt=$mt at=$at et=$et '
      'rainSegMorning=$morningRainSeg rainSegAfternoon=$afternoonRainSeg rainSegEvening=$eveningRainSeg (fallback)',
    );
    logVerboseHome(
      'WEATHER stylist_ux fallback outfitWhy="${ux.outfitWhyWeatherNote}"',
    );
    final summaryText = fallback.isRainy
        ? 'Ráno okolo ${fallback.tempC - 2}°C, cez obed približne ${fallback.tempC}°C. '
            'Poobedie môže pršať okolo 17:00. Večer by malo byť pokojné.'
        : 'Ráno okolo ${fallback.tempC - 2}°C, cez obed približne ${fallback.tempC}°C. '
            'Večer by malo byť pokojné.';

    final briefingMorningCondition = BriefingWeatherCondition.briefingUiSk(
      BriefingWeatherCondition.fallback(
        segmentRain: morningRainSeg,
        segmentWindy: w,
        segment: BriefingDaySegment.morning,
      ),
    );
    final briefingAfternoonCondition = BriefingWeatherCondition.briefingUiSk(
      BriefingWeatherCondition.fallback(
        segmentRain: afternoonRainSeg,
        segmentWindy: w,
        segment: BriefingDaySegment.afternoon,
      ),
    );
    final briefingEveningCondition = BriefingWeatherCondition.briefingUiSk(
      BriefingWeatherCondition.fallback(
        segmentRain: eveningRainSeg,
        segmentWindy: w,
        segment: BriefingDaySegment.evening,
      ),
    );

    return OutfitWeatherDaySnapshot(
      cityName: cityName,
      date: date,
      morningTempC: fallback.tempC - 2,
      noonTempC: fallback.tempC,
      eveningTempC: fallback.tempC - 1,
      minTempC: fallback.tempC - 3,
      maxTempC: fallback.tempC + 1,
      willRain: fallback.isRainy,
      rainTimeText: fallback.isRainy ? 'poobedie okolo 17:00' : null,
      outfitWhyWeatherNote: ux.outfitWhyWeatherNote,
      morningRainSegment: morningRainSeg,
      afternoonRainSegment: afternoonRainSeg,
      eveningRainSegment: eveningRainSeg,
      isWindy: fallback.isWindy,
      summaryText: summaryText,
      fromOpenMeteo: false,
      mainChipTempC: fallback.tempC,
      mainChipBasis: 'fallback',
      mainChipHour: null,
      openMeteoFailureNote: failureNote,
      briefingMorningCondition: briefingMorningCondition,
      briefingAfternoonCondition: briefingAfternoonCondition,
      briefingEveningCondition: briefingEveningCondition,
    );
  }

  String _dateLabel(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _hourLabel(DateTime dateTime) {
    final h = dateTime.hour.toString().padLeft(2, '0');
    return '$h:00';
  }

  String _buildSummaryText({
    required int? morningTempC,
    required int? noonTempC,
    required int? eveningTempC,
    required int? minTempC,
    required int? maxTempC,
    required _HourlyPoint? rainMorning,
    required _HourlyPoint? rainAfternoon,
    required _HourlyPoint? rainEvening,
    required bool isWindy,
    required int? currentTempC,
  }) {
    final parts = <String>[];
    if (currentTempC != null) {
      parts.add('Teraz je približne $currentTempC°C');
    }
    if (morningTempC != null) {
      parts.add('Ráno okolo $morningTempC°C');
    }
    if (noonTempC != null) {
      parts.add('cez obed približne $noonTempC°C');
    }
    if (eveningTempC != null && rainEvening == null) {
      parts.add('večer okolo $eveningTempC°C');
    }
    if (minTempC != null && maxTempC != null) {
      parts.add('v rozmedzí $minTempC–$maxTempC°C');
    }

    var sentence = parts.isEmpty ? 'Počasie sa môže meniť.' : '${parts.join(', ')}.';

    if (rainMorning != null && rainMorning.hasData) {
      sentence += ' Ráno môže pršať okolo ${_hourLabel(rainMorning.time!)}.';
    }
    if (rainAfternoon != null && rainAfternoon.hasData) {
      sentence += ' Poobedie môže pršať okolo ${_hourLabel(rainAfternoon.time!)}.';
    }
    if (rainEvening != null && rainEvening.hasData) {
      sentence += ' Večer môže pršať okolo ${_hourLabel(rainEvening.time!)}.';
    }
    if (isWindy) {
      sentence += ' Očakávaj aj výraznejší vietor.';
    }
    return sentence.trim();
  }
}

class _WeatherSnapshotCacheEntry {
  const _WeatherSnapshotCacheEntry({
    required this.snapshot,
    required this.fetchedAt,
  });

  final OutfitWeatherDaySnapshot snapshot;
  final DateTime fetchedAt;
}

class _GeoResult {
  final double latitude;
  final double longitude;
  final String displayName;

  const _GeoResult({
    required this.latitude,
    required this.longitude,
    required this.displayName,
  });
}

class _HourlyWeatherPayload {
  final List<_HourlyPoint> points;
  final double? currentTemperatureC;

  const _HourlyWeatherPayload({
    required this.points,
    required this.currentTemperatureC,
  });
}

class _HourlyPoint {
  final DateTime? time;
  final double? temperatureC;
  final double? precipitationProbability;
  final double? precipitationMm;
  final double? windSpeedKmh;
  final int? weatherCode;

  const _HourlyPoint({
    required this.time,
    required this.temperatureC,
    required this.precipitationProbability,
    required this.precipitationMm,
    required this.windSpeedKmh,
    this.weatherCode,
  });

  bool get hasData => time != null;
}
