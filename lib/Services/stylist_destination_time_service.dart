import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class _TimeZoneCacheEntry {
  final String? timezoneId;
  final int? fallbackMinutes;
  final DateTime fetchedAt;

  const _TimeZoneCacheEntry({
    required this.timezoneId,
    required this.fallbackMinutes,
    required this.fetchedAt,
  });
}

/// Provider-backed timezone helper for travel timing.
///
/// The provider supplies the IANA timezone for verified coordinates. The local
/// timezone database then evaluates the offset for the actual travel instant,
/// so daylight-saving changes are respected instead of reusing today's offset.
/// No location names are hard-coded here.
abstract final class StylistDestinationTimeService {
  static const Duration _ttl = Duration(hours: 12);
  static final Map<String, _TimeZoneCacheEntry> _cache = {};
  static bool _tzInitialized = false;

  static Future<int?> utcOffsetMinutes({
    required double latitude,
    required double longitude,
    DateTime? atUtc,
  }) async {
    final instant = (atUtc ?? DateTime.now()).toUtc();
    final metadata = await _metadata(latitude, longitude);
    if (metadata == null) return null;

    final timezoneId = metadata.timezoneId?.trim();
    if (timezoneId != null && timezoneId.isNotEmpty) {
      try {
        _ensureTimeZones();
        final location = tz.getLocation(timezoneId);
        final local = tz.TZDateTime.from(instant, location);
        return local.timeZoneOffset.inMinutes;
      } catch (_) {
        // Fall through to the provider's current offset only for near-now use.
      }
    }

    final fallback = metadata.fallbackMinutes;
    if (fallback == null) return null;
    if (instant.difference(DateTime.now().toUtc()).abs() >
        const Duration(days: 2)) {
      // A current offset is unsafe across a possible DST boundary.
      return null;
    }
    return fallback;
  }

  static Future<_TimeZoneCacheEntry?> _metadata(
    double latitude,
    double longitude,
  ) async {
    final key =
        '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _ttl) {
      return cached;
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
      final timezoneId = (decoded['timezone'] ?? '').toString().trim();
      final seconds = decoded['utc_offset_seconds'];
      int? fallbackMinutes;
      if (seconds is num) {
        final value = (seconds.toDouble() / 60).round();
        if (value >= -14 * 60 && value <= 14 * 60) fallbackMinutes = value;
      }
      if (timezoneId.isEmpty && fallbackMinutes == null) return null;
      final entry = _TimeZoneCacheEntry(
        timezoneId: timezoneId.isEmpty ? null : timezoneId,
        fallbackMinutes: fallbackMinutes,
        fetchedAt: DateTime.now(),
      );
      _cache[key] = entry;
      return entry;
    } catch (_) {
      return null;
    }
  }

  static void _ensureTimeZones() {
    if (_tzInitialized) return;
    tzdata.initializeTimeZones();
    _tzInitialized = true;
  }
}
