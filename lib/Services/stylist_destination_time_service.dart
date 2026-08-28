import 'dart:convert';

import 'package:http/http.dart' as http;

class _OffsetCacheEntry {
  final int minutes;
  final DateTime fetchedAt;

  const _OffsetCacheEntry(this.minutes, this.fetchedAt);
}

/// Small provider helper for converting a near-term derived arrival UTC time
/// into the destination's local clock. It contains no city/country names.
///
/// Open-Meteo is already the app's weather provider. We ask it for the timezone
/// of provider-verified coordinates and cache the answer. If the provider is
/// unavailable, callers simply keep arrival timing approximate and must not
/// invent a destination-local clock time.
abstract final class StylistDestinationTimeService {
  static const Duration _ttl = Duration(hours: 6);
  static final Map<String, _OffsetCacheEntry> _cache = {};

  static Future<int?> utcOffsetMinutes({
    required double latitude,
    required double longitude,
  }) async {
    final key =
        '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _ttl) {
      return cached.minutes;
    }

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'temperature_2m',
      'forecast_days': '1',
      'timezone': 'auto',
    });
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final seconds = decoded['utc_offset_seconds'];
      if (seconds is! num) return null;
      final minutes = (seconds.toDouble() / 60).round();
      if (minutes < -14 * 60 || minutes > 14 * 60) return null;
      _cache[key] = _OffsetCacheEntry(minutes, DateTime.now());
      return minutes;
    } catch (_) {
      return null;
    }
  }
}
