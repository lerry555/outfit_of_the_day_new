import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/briefing_weather_condition.dart';

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
  });
}

class HourlyWeatherService {
  static const String _defaultCity = 'Martin, Slovakia';

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
    final isFixedMartin =
        normalizedCityKey == 'martin' ||
        normalizedCityKey == 'martin, slovakia' ||
        normalizedCityKey == 'martin, slovensko';

    try {
      _GeoResult? geo;
      if (isFixedMartin) {
        debugPrint('WEATHER USING FIXED MARTIN SK COORDINATES');
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
        return _fallbackSnapshot(
          cityName: resolvedCity,
          date: normalizedDate,
          failureNote: 'geocode_null city=$resolvedCity',
        );
      }

      final weather = await _fetchHourlyWeatherForDate(
        latitude: geo.latitude,
        longitude: geo.longitude,
        date: normalizedDate,
      );
      if (weather == null) {
        debugPrint('WEATHER FALLBACK reason=fetch_null day=${_dateLabel(normalizedDate)}');
        return _fallbackSnapshot(
          cityName: geo.displayName,
          date: normalizedDate,
          failureNote: 'hourly_fetch_failed_http_or_json day=${_dateLabel(normalizedDate)}',
        );
      }
      if (weather.points.isEmpty) {
        debugPrint(
          'WEATHER FALLBACK reason=hourly_empty_after_parse day=${_dateLabel(normalizedDate)}',
        );
        return _fallbackSnapshot(
          cityName: geo.displayName,
          date: normalizedDate,
          failureNote:
              'hourly_empty_after_parse day=${_dateLabel(normalizedDate)} (check API params / time format)',
        );
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final isToday = normalizedDate == today;
      final isTomorrow = normalizedDate == today.add(const Duration(days: 1));

      final currentTempC = weather.currentTemperatureC?.round();
      debugPrint('WEATHER CURRENT TEMP: $currentTempC isToday=$isToday');

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

      final rainTimeParts = <String>[];
      if (rainMorning?.time != null) {
        rainTimeParts.add('ráno ${_hourLabel(rainMorning!.time!)}');
      }
      if (rainAfternoon?.time != null) {
        rainTimeParts.add('poobedie ${_hourLabel(rainAfternoon!.time!)}');
      }
      if (rainEvening?.time != null) {
        rainTimeParts.add('večer ${_hourLabel(rainEvening!.time!)}');
      }
      final rainTimeText = rainTimeParts.isEmpty ? null : rainTimeParts.join(', ');

      debugPrint(
        'WEATHER rain_segment morning=${rainMorning?.time} afternoon=${rainAfternoon?.time} '
        'evening=${rainEvening?.time}',
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

      debugPrint(
        'WEATHER briefing_segments mt=$mt at=$at et=$et '
        'rainSegMorning=$morningRainSeg rainSegAfternoon=$afternoonRainSeg rainSegEvening=$eveningRainSeg '
        'windSegMorning=$windMorning windSegAfternoon=$windAfternoon windSegEvening=$windEvening',
      );
      debugPrint(
        'WEATHER stylist_ux outfitWhy="${ux.outfitWhyWeatherNote}"',
      );

      debugPrint(
        'WEATHER dayparts: morning=$morning afternoonBlock=$afternoonBlock evening=$evening '
        'mainChip=$mainChipTempC ($mainChipBasis h=$mainChipHour) rainTime=$rainTimeText windy=$isWindy',
      );
      debugPrint(
        'WEATHER FINAL SNAPSHOT: city=${geo.displayName} isToday=$isToday morning=$morning afternoon=$afternoonBlock evening=$evening '
        'min=$minTempC max=$maxTempC rain=$willRain rainTime=$rainTimeText windy=$isWindy summary="$summaryText"',
      );

      debugPrint(
        'WEATHER OPEN_METEO_OK day=${_dateLabel(normalizedDate)} isToday=$isToday '
        'hourlyCount=${weather.points.length} mainChipTempC=$mainChipTempC '
        'mainChipBasis=$mainChipBasis mainChipHour=$mainChipHour '
        'morning=$morning afternoon=$afternoonBlock evening=$evening '
        'rainSegMorning=${rainMorning?.time} rainSegAfternoon=${rainAfternoon?.time} rainSegEvening=${rainEvening?.time} '
        'rainSegMorningB=$morningRainSeg rainSegAfternoonB=$afternoonRainSeg rainSegEveningB=$eveningRainSeg',
      );

      return OutfitWeatherDaySnapshot(
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
      );
    } catch (e) {
      debugPrint('WEATHER FALLBACK reason=exception $e');
      return _fallbackSnapshot(
        cityName: resolvedCity,
        date: normalizedDate,
        failureNote: 'exception ${e.toString()}',
      );
    }
  }

  Future<_GeoResult?> _geocodeCity(String city) async {
    final normalizedCity = city.trim();
    final lower = normalizedCity.toLowerCase();
    final hasCountryHint = lower.contains(',') || lower.contains('slovak') || lower.contains('slovensk');
    final queryName = (lower == 'martin' || !hasCountryHint)
        ? 'Martin, Slovakia'
        : normalizedCity;

    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': queryName,
      'count': '10',
      'language': 'sk',
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
    bool isSlovakResult(Map item) {
      final code = item['country_code']?.toString().toUpperCase().trim();
      final country = item['country']?.toString().toLowerCase().trim() ?? '';
      return code == 'SK' || country == 'slovakia' || country == 'slovensko';
    }

    final selected = maps.firstWhere(
      isSlovakResult,
      orElse: () => maps.first,
    );

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
      displayName: displayName.isEmpty ? _defaultCity : displayName,
    );
  }

  Future<_HourlyWeatherPayload?> _fetchHourlyWeatherForDate({
    required double latitude,
    required double longitude,
    required DateTime date,
  }) async {
    final day = _dateLabel(date);
    // Do NOT combine `forecast_days` with `start_date`/`end_date` — Open-Meteo returns 400.
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'temperature_2m',
      'hourly':
          'temperature_2m,precipitation_probability,precipitation,wind_speed_10m,weather_code',
      'timezone': 'Europe/Bratislava',
      'start_date': day,
      'end_date': day,
    });
    debugPrint('WEATHER API URL: $uri');
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
    final wantedDay = _dateLabel(date);
    final anchor = DateTime(date.year, date.month, date.day);

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
      final raw = times[i].trim();
      final m = _openMeteoHourlyTime.firstMatch(raw);
      if (m == null) continue;
      if (m.group(1) != wantedDay) continue;
      final hh = int.tryParse(m.group(2)!) ?? 0;
      final mm = int.tryParse(m.group(3) ?? '0') ?? 0;
      addPoint(i, DateTime(anchor.year, anchor.month, anchor.day, hh, mm));
    }

    if (points.isEmpty) {
      debugPrint(
        'WEATHER hourly_parse: prefix_match_empty wantedDay=$wantedDay rawLen=$len — trying legacy local-date filter',
      );
      final selectedLocalDate = DateTime(date.year, date.month, date.day);
      for (var i = 0; i < len; i++) {
        final time = DateTime.tryParse(times[i]);
        if (time == null) continue;
        final localHourDate = DateTime(time.year, time.month, time.day);
        if (localHourDate != selectedLocalDate) continue;
        addPoint(i, time);
      }
    }

    debugPrint(
      'WEATHER API_OK day=$wantedDay rawHourly=$len pointsParsed=${points.length} '
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
    final t = selected?.temperatureC;
    return t == null ? null : t.round();
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
    debugPrint(
      'WEATHER briefing_segments mt=$mt at=$at et=$et '
      'rainSegMorning=$morningRainSeg rainSegAfternoon=$afternoonRainSeg rainSegEvening=$eveningRainSeg (fallback)',
    );
    debugPrint(
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
      parts.add('Teraz je približne ${currentTempC}°C');
    }
    if (morningTempC != null) {
      parts.add('Ráno okolo ${morningTempC}°C');
    }
    if (noonTempC != null) {
      parts.add('cez obed približne ${noonTempC}°C');
    }
    if (eveningTempC != null && rainEvening == null) {
      parts.add('večer okolo ${eveningTempC}°C');
    }
    if (minTempC != null && maxTempC != null) {
      parts.add('v rozmedzí ${minTempC}–${maxTempC}°C');
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
