import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

enum DestinationGranularity {
  locality,
  adminRegion,
  country,
  continent,
  airport,
  other,
  unknown,
}

class DestinationSuggestion {
  final int? geonameId;
  final String displayName;
  final String name;
  final String country;
  final String? countryCode;
  final String? adminRegion;
  final double latitude;
  final double longitude;
  final int? population;
  final String? featureCode;

  const DestinationSuggestion({
    this.geonameId,
    required this.displayName,
    required this.name,
    required this.country,
    this.countryCode,
    this.adminRegion,
    required this.latitude,
    required this.longitude,
    this.population,
    this.featureCode,
  });

  DestinationGranularity get granularity =>
      DestinationSearchService.granularityForFeatureCode(featureCode);

  bool get weatherSpecific =>
      granularity == DestinationGranularity.locality ||
      granularity == DestinationGranularity.airport;
}

/// Provider-driven global location search.
///
/// There are intentionally no country/city/resort/airport name boosts here.
/// Ranking is based only on how the provider result matches the user's query,
/// population and generic GeoNames feature classes.
abstract final class DestinationSearchService {
  DestinationSearchService._();

  static const _host = 'geocoding-api.open-meteo.com';
  static const _path = '/v1/search';

  static Future<List<DestinationSuggestion>> search(String query) async {
    final trimmed = query.trim();
    final normalized = normalizeQuery(trimmed);
    if (normalized.length < 2) return const [];

    final batch = await _fetchGeocoding(trimmed);
    if (batch.isEmpty) return const [];
    final ranked = List<DestinationSuggestion>.from(batch)
      ..sort((a, b) => _score(b, normalized).compareTo(_score(a, normalized)));
    return ranked.take(12).toList(growable: false);
  }

  static DestinationGranularity granularityForFeatureCode(String? raw) {
    final code = (raw ?? '').trim().toUpperCase();
    if (code.isEmpty) return DestinationGranularity.unknown;
    if (code.startsWith('PPL')) return DestinationGranularity.locality;
    if (code.startsWith('ADM')) return DestinationGranularity.adminRegion;
    if (code.startsWith('PCL')) return DestinationGranularity.country;
    if (code == 'CONT') return DestinationGranularity.continent;
    if (code.startsWith('AIR')) return DestinationGranularity.airport;
    return DestinationGranularity.other;
  }

  static String normalizeQuery(String value) {
    const diacritics = {
      'á': 'a',
      'ä': 'a',
      'à': 'a',
      'â': 'a',
      'č': 'c',
      'ć': 'c',
      'ď': 'd',
      'é': 'e',
      'ě': 'e',
      'ë': 'e',
      'è': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ľ': 'l',
      'ĺ': 'l',
      'ń': 'n',
      'ň': 'n',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'ò': 'o',
      'ř': 'r',
      'ŕ': 'r',
      'š': 's',
      'ś': 's',
      'ť': 't',
      'ú': 'u',
      'ů': 'u',
      'ü': 'u',
      'ù': 'u',
      'ý': 'y',
      'ž': 'z',
      'ź': 'z',
      'ż': 'z',
    };
    final lower = value.toLowerCase().trim();
    final out = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      out.write(diacritics[ch] ?? ch);
    }
    return out.toString();
  }

  static Future<List<DestinationSuggestion>> _fetchGeocoding(String query) async {
    final uri = Uri.https(_host, _path, {
      'name': query,
      'count': '50',
      'language': 'sk',
      'format': 'json',
    });
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 7));
      if (res.statusCode != 200) return const [];
      final json = jsonDecode(res.body);
      final raw = json is Map<String, dynamic> ? json['results'] : null;
      if (raw is! List) return const [];

      final out = <DestinationSuggestion>[];
      final seen = <String>{};
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final id = (item['id'] as num?)?.toInt();
        final name = (item['name'] as String?)?.trim();
        final country = (item['country'] as String?)?.trim();
        final countryCode = (item['country_code'] as String?)?.trim().toUpperCase();
        final lat = (item['latitude'] as num?)?.toDouble();
        final lon = (item['longitude'] as num?)?.toDouble();
        if (name == null || name.isEmpty || lat == null || lon == null) continue;
        final safeCountry = country ?? '';
        final admin = (item['admin1'] as String?)?.trim();
        final pop = (item['population'] as num?)?.toInt();
        final fc = (item['feature_code'] as String?)?.trim();
        final displayParts = <String>[
          name,
          if (admin != null && admin.isNotEmpty && admin != name) admin,
          if (safeCountry.isNotEmpty) safeCountry,
        ];
        final suggestion = DestinationSuggestion(
          geonameId: id,
          displayName: displayParts.join(', '),
          name: name,
          country: safeCountry,
          countryCode: countryCode,
          adminRegion: admin,
          latitude: lat,
          longitude: lon,
          population: pop,
          featureCode: fc,
        );
        final key = id?.toString() ??
            '${name.toLowerCase()}:${lat.toStringAsFixed(4)}:${lon.toStringAsFixed(4)}';
        if (seen.add(key)) out.add(suggestion);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static double _score(DestinationSuggestion item, String query) {
    final name = normalizeQuery(item.name);
    final admin = normalizeQuery(item.adminRegion ?? '');
    final country = normalizeQuery(item.country);
    final code = normalizeQuery(item.countryCode ?? '');
    final display = normalizeQuery(item.displayName);
    var score = 0.0;

    if (name == query) {
      score += 240;
    } else if (name.startsWith(query)) {
      score += 170;
    } else if (_wordStartsWith(name, query)) {
      score += 125;
    } else if (name.contains(query)) {
      score += 70;
    }

    if (admin == query) {
      score += 45;
    } else if (admin.startsWith(query)) {
      score += 32;
    }
    if (country == query || code == query) score += 35;
    if (display.startsWith(query)) score += 20;

    final pop = item.population ?? 0;
    if (pop > 0) score += math.min(80, math.log(pop + 1) * 8);
    score += _featureWeight(item.granularity);
    return score;
  }

  static bool _wordStartsWith(String value, String query) {
    if (value.startsWith(query)) return true;
    return value
        .split(RegExp(r'\s+|-'))
        .where((part) => part.isNotEmpty)
        .any((part) => part.startsWith(query));
  }

  static double _featureWeight(DestinationGranularity granularity) =>
      switch (granularity) {
        DestinationGranularity.locality => 45,
        DestinationGranularity.airport => 18,
        DestinationGranularity.adminRegion => 10,
        DestinationGranularity.country => 4,
        DestinationGranularity.continent => 0,
        DestinationGranularity.other => 6,
        DestinationGranularity.unknown => 0,
      };
}
