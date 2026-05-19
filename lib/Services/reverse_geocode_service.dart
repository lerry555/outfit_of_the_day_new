import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Open-Meteo reverse geocoding — zdieľané s počasím (bez nového native SDK).
abstract final class ReverseGeocodeService {
  ReverseGeocodeService._();

  /// Rozšírený výsledok pre ladenie (name / admin úrovne).
  static Future<ReverseGeocodeResolution?> resolveCityLabelWithDetails(
    double latitude,
    double longitude,
  ) async {
    try {
      final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/reverse', {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'language': 'sk',
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint('[REVERSE_GEO] http status=${response.statusCode} body=${response.body.length > 200 ? '${response.body.substring(0, 200)}…' : response.body}');
        return null;
      }
      final raw = jsonDecode(response.body);
      if (raw is! Map<String, dynamic>) return null;
      final results = raw['results'];
      if (results is! List || results.isEmpty) {
        debugPrint('[REVERSE_GEO] empty results raw=$raw');
        return null;
      }
      final rawFirst = results.first;
      if (rawFirst is! Map<String, dynamic>) return null;
      final m = rawFirst;

      String? pick(String key) {
        final v = m[key];
        if (v == null) return null;
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }

      final name = pick('name');
      final admin2 = pick('admin2');
      final admin1 = pick('admin1');
      final admin3 = pick('admin3');
      final country = pick('country');

      final chosen = name ?? admin3 ?? admin2 ?? admin1;

      final debugLine =
          'name=$name admin1=$admin1 admin2=$admin2 admin3=$admin3 country=$country chosen=$chosen';

      return ReverseGeocodeResolution(
        cityLabel: chosen,
        debugLine: debugLine,
      );
    } catch (e, st) {
      debugPrint('[REVERSE_GEO] failed $e $st');
      return null;
    }
  }

  /// Krátke meno miesta (napr. „Martin“, „Bratislava“).
  static Future<String?> cityNameFromLatLon(double latitude, double longitude) async {
    final r = await resolveCityLabelWithDetails(latitude, longitude);
    return r?.cityLabel;
  }
}

/// Výsledok reverzného geokódovania (Open-Meteo prvý záznam).
class ReverseGeocodeResolution {
  const ReverseGeocodeResolution({
    required this.cityLabel,
    required this.debugLine,
  });

  final String? cityLabel;
  final String debugLine;
}
