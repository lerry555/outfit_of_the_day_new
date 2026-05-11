import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'date_weather_service.dart';

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
  final bool isWindy;
  final String summaryText;

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
    required this.isWindy,
    required this.summaryText,
  });
}

class HourlyWeatherService {
  static const String _defaultCity = 'Martin, Slovakia';
  static const double _martinSkLat = 49.0665;
  static const double _martinSkLon = 18.9210;

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
        return _fallbackSnapshot(cityName: resolvedCity, date: normalizedDate);
      }

      final weather = await _fetchHourlyWeatherForDate(
        latitude: geo.latitude,
        longitude: geo.longitude,
        date: normalizedDate,
      );
      if (weather == null || weather.points.isEmpty) {
        return _fallbackSnapshot(cityName: geo.displayName, date: normalizedDate);
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final isToday = normalizedDate == today;

      final morning = _tempAtHour(weather.points, 7);
      var noon = _tempAtHour(weather.points, 13);
      final evening = _tempAtHour(weather.points, 17);
      final currentTempC = weather.currentTemperatureC?.round();
      debugPrint('WEATHER CURRENT TEMP: $currentTempC');

      if (isToday && currentTempC != null) {
        if (noon == null || (noon - currentTempC).abs() > 8) {
          noon = currentTempC;
        }
      }

      final allTemps = weather.points
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

      final rainHour = weather.points.firstWhere(
        (h) =>
            (h.precipitationProbability ?? 0) >= 50 ||
            (h.precipitationMm ?? 0) > 0.2,
        orElse: () => const _HourlyPoint.empty(),
      );
      final willRain = rainHour.hasData;
      final rainTimeText = willRain ? 'okolo ${_hourLabel(rainHour.time!)}' : null;

      final isWindy =
      weather.points.any((h) => (h.windSpeedKmh ?? 0) >= 25);

      final summaryText = _buildSummaryText(
        morningTempC: morning,
        noonTempC: noon,
        eveningTempC: evening,
        minTempC: minTempC,
        maxTempC: maxTempC,
        willRain: willRain,
        rainTimeText: rainTimeText,
        isWindy: isWindy,
        currentTempC: isToday ? currentTempC : null,
      );
      debugPrint(
        'WEATHER SELECTED HOURS: morning=$morning noon=$noon evening=$evening rainTime=$rainTimeText windy=$isWindy',
      );
      debugPrint(
        'WEATHER FINAL SNAPSHOT: city=${geo.displayName} morning=$morning noon=$noon evening=$evening min=$minTempC max=$maxTempC rain=$willRain rainTime=$rainTimeText windy=$isWindy summary="$summaryText"',
      );

      return OutfitWeatherDaySnapshot(
        cityName: geo.displayName,
        date: normalizedDate,
        morningTempC: morning,
        noonTempC: noon,
        eveningTempC: evening,
        minTempC: minTempC,
        maxTempC: maxTempC,
        willRain: willRain,
        rainTimeText: rainTimeText,
        isWindy: isWindy,
        summaryText: summaryText,
      );
    } catch (_) {
      return _fallbackSnapshot(cityName: resolvedCity, date: normalizedDate);
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
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'temperature_2m',
      'hourly':
          'temperature_2m,precipitation_probability,precipitation,wind_speed_10m',
      'timezone': 'Europe/Bratislava',
      'forecast_days': '10',
      'start_date': day,
      'end_date': day,
    });
    debugPrint('WEATHER API URL: $uri');
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;

    final raw = jsonDecode(response.body);
    if (raw is! Map<String, dynamic>) return null;
    final current = raw['current'];
    final currentTemperatureC =
        current is Map<String, dynamic> ? (current['temperature_2m'] as num?)?.toDouble() : null;
    final hourly = raw['hourly'];
    if (hourly is! Map<String, dynamic>) return null;

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

    final len = times.length;
    final points = <_HourlyPoint>[];
    final selectedLocalDate = DateTime(date.year, date.month, date.day);
    for (var i = 0; i < len; i++) {
      final time = DateTime.tryParse(times[i]);
      if (time == null) continue;
      final localHourDate = DateTime(time.year, time.month, time.day);
      if (localHourDate != selectedLocalDate) continue;
      points.add(
        _HourlyPoint(
          time: time,
          temperatureC: i < temps.length ? temps[i] : null,
          precipitationProbability:
              i < precipitationProbabilities.length ? precipitationProbabilities[i] : null,
          precipitationMm: i < precipitation.length ? precipitation[i] : null,
          windSpeedKmh: i < windSpeed.length ? windSpeed[i] : null,
        ),
      );
    }
    return _HourlyWeatherPayload(
      points: points,
      currentTemperatureC: currentTemperatureC,
    );
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

  OutfitWeatherDaySnapshot _fallbackSnapshot({
    required String cityName,
    required DateTime date,
  }) {
    final fallback = DateWeatherService.getFallbackWeatherForDate(date);
    final summaryText = fallback.isRainy
        ? 'Ráno okolo ${fallback.tempC - 2}°C, cez obed približne ${fallback.tempC}°C. '
            'Večer môže pršať okolo 17:00.'
        : 'Ráno okolo ${fallback.tempC - 2}°C, cez obed približne ${fallback.tempC}°C. '
            'Večer by malo byť pokojné.';

    return OutfitWeatherDaySnapshot(
      cityName: cityName,
      date: date,
      morningTempC: fallback.tempC - 2,
      noonTempC: fallback.tempC,
      eveningTempC: fallback.tempC - 1,
      minTempC: fallback.tempC - 3,
      maxTempC: fallback.tempC + 1,
      willRain: fallback.isRainy,
      rainTimeText: fallback.isRainy ? 'okolo 17:00' : null,
      isWindy: fallback.isWindy,
      summaryText: summaryText,
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
    required bool willRain,
    required String? rainTimeText,
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
    if (eveningTempC != null && !willRain) {
      parts.add('večer okolo ${eveningTempC}°C');
    }
    if (minTempC != null && maxTempC != null) {
      parts.add('v rozmedzí ${minTempC}–${maxTempC}°C');
    }

    var sentence = parts.isEmpty ? 'Počasie sa môže meniť.' : '${parts.join(', ')}.';

    if (willRain) {
      final when = rainTimeText != null ? ' $rainTimeText' : '';
      sentence += ' Večer môže pršať$when.';
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

  const _HourlyPoint({
    required this.time,
    required this.temperatureC,
    required this.precipitationProbability,
    required this.precipitationMm,
    required this.windSpeedKmh,
  });

  const _HourlyPoint.empty()
      : time = null,
        temperatureC = null,
        precipitationProbability = null,
        precipitationMm = null,
        windSpeedKmh = null;

  bool get hasData => time != null;
}
