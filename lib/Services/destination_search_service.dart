import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

class DestinationSuggestion {
  final int? geonameId;
  final String displayName;
  final String name;
  final String country;
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
    this.adminRegion,
    required this.latitude,
    required this.longitude,
    this.population,
    this.featureCode,
  });
}

abstract final class DestinationSearchService {
  DestinationSearchService._();

  static const _host = 'geocoding-api.open-meteo.com';
  static const _path = '/v1/search';

  /// Pri 2 znakoch API vracia len „presné“ zhody — doplníme významné mestá / letoviská.
  static const Map<String, List<String>> _twoLetterExtraQueries = {
    'hu': ['Hurghada'],
    'lo': ['London', 'Lyon'],
    'pa': ['Paris', 'Palermo', 'Palma'],
    'ba': ['Barcelona', 'Bangkok', 'Bratislava', 'Bari'],
    'vi': ['Vienna', 'Vilnius'],
    'br': ['Brussels', 'Brno', 'Bratislava'],
    'mu': ['Munich', 'Mumbai'],
    'ma': ['Madrid', 'Malaga', 'Manchester'],
    'du': ['Dublin', 'Dubrovnik'],
    'be': ['Berlin', 'Bergen', 'Belfast'],
    'to': ['Toronto', 'Tokyo'],
    'mi': ['Milan', 'Miami'],
    'ri': ['Riga', 'Rimini'],
    'ze': ['Zermatt'],
    'je': ['Jerusalem'],
  };

  static const Map<String, String> _fallbackAliases = {
    'londyn': 'london',
    'rim': 'rome',
    'pariz': 'paris',
    'viden': 'vienna',
    'barcelona': 'barcelona',
    'hurghada': 'hurghada',
    'bratislava': 'bratislava',
    'budapest': 'budapest',
    'praha': 'prague',
  };

  static Future<List<DestinationSuggestion>> search(String query) async {
    final trimmed = query.trim();
    final normalized = normalizeQuery(trimmed);
    if (normalized.length < 2) return const [];

    final queries = <String>{trimmed};
    if (normalized.length == 2) {
      final extra = _twoLetterExtraQueries[normalized];
      if (extra != null) {
        queries.addAll(extra);
      }
    }

    final alias = _fallbackAliases[normalized];
    if (alias != null) {
      queries.add(alias);
    }

    final byId = <int, DestinationSuggestion>{};
    for (final q in queries) {
      final batch = await _fetchGeocoding(q);
      for (final s in batch) {
        final key = s.geonameId ?? _fallbackDedupeKey(s);
        byId[key] = s;
      }
    }

    if (byId.isEmpty) return const [];

    final ranked = byId.values.toList()
      ..sort((a, b) => _score(b, normalized).compareTo(_score(a, normalized)));
    return ranked.take(12).toList();
  }

  /// Fallback keď GeoNames ID chýba v objekte (nemalo by).
  static int _fallbackDedupeKey(DestinationSuggestion s) {
    final lat = (s.latitude * 1000).round();
    final lon = (s.longitude * 1000).round();
    return Object.hash(s.name, s.country, lat, lon);
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
    final res = await http.get(uri);
    if (res.statusCode != 200) return const [];
    final json = jsonDecode(res.body);
    final raw = (json is Map<String, dynamic> ? json['results'] : null);
    if (raw is! List) return const [];

    final out = <DestinationSuggestion>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final id = (item['id'] as num?)?.toInt();
      final name = (item['name'] as String?)?.trim();
      final country = (item['country'] as String?)?.trim();
      final lat = (item['latitude'] as num?)?.toDouble();
      final lon = (item['longitude'] as num?)?.toDouble();
      if (name == null || country == null || lat == null || lon == null) continue;
      final admin = (item['admin1'] as String?)?.trim();
      final pop = (item['population'] as num?)?.toInt();
      final fc = (item['feature_code'] as String?)?.trim();
      final display = admin != null && admin.isNotEmpty && admin != name
          ? '$name, $admin, $country'
          : '$name, $country';
      out.add(
        DestinationSuggestion(
          geonameId: id,
          displayName: display,
          name: name,
          country: country,
          adminRegion: admin,
          latitude: lat,
          longitude: lon,
          population: pop,
          featureCode: fc,
        ),
      );
    }
    return out;
  }

  static const _tourismHints = [
    'beach',
    'resort',
    'bay',
    'island',
    'coast',
    'national park',
    'plaza',
    'paris',
    'london',
    'barcelona',
    'dubai',
    'maldives',
    'bali',
    'phuket',
    'tenerife',
    'mallorca',
    'ibiza',
    'santorini',
    'mykonos',
    'hurghada',
    'sharm',
    'antalya',
    'monaco',
    'venice',
    'venezia',
    'florence',
    'firenze',
    'nice',
    'cannes',
    'capri',
  ];

  static double _score(DestinationSuggestion item, String q) {
    final nName = normalizeQuery(item.name);
    final nAdmin = normalizeQuery(item.adminRegion ?? '');
    final nCountry = normalizeQuery(item.country);
    final nDisplay = normalizeQuery(item.displayName);
    final fc = item.featureCode ?? '';

    var text = 0.0;
    if (nName == q) {
      text += 220;
    } else if (nName.startsWith(q)) {
      text += 160;
    } else if (_wordStartsWith(nName, q)) {
      text += 120;
    } else if (nName.contains(q)) {
      text += 70;
    }

    if (nAdmin == q) {
      text += 45;
    } else if (nAdmin.startsWith(q)) {
      text += 38;
    } else if (nAdmin.contains(q)) {
      text += 22;
    }

    if (nDisplay.startsWith(q)) {
      text += 28;
    } else if (nDisplay.contains(q)) {
      text += 12;
    }

    if (nCountry.startsWith(q) || nCountry.contains(q)) {
      text += 6;
    }

    final pop = item.population ?? 0;
    if (pop > 0) {
      text += math.min(85, math.log(pop + 1) * 9);
    }

    final feat = _featureWeight(fc);
    text += feat;

    if (fc.startsWith('AIR') || fc == 'RSTN' || fc == 'FY') {
      text -= 180;
    }

    final blob = '$nName $nAdmin $nDisplay';
    for (final h in _tourismHints) {
      if (blob.contains(h)) {
        text += 12;
        break;
      }
    }

    if (q.length >= 3 && nName.startsWith(q)) {
      text += 25;
    }

    return text;
  }

  static bool _wordStartsWith(String normalizedName, String q) {
    if (normalizedName.startsWith(q)) return true;
    final parts = normalizedName.split(RegExp(r'\s+|-'));
    for (final p in parts) {
      if (p.startsWith(q)) return true;
    }
    return false;
  }

  /// GeoNames P = obývané miesta; hlavné mestá a sidlá regiónov majú prednosť.
  static double _featureWeight(String fc) {
    switch (fc) {
      case 'PPLC':
        return 55;
      case 'PPLA':
      case 'PPLA2':
      case 'PPLA3':
      case 'PPLA4':
        return 42;
      case 'PPL':
      case 'PPLG':
        return 28;
      case 'PPLX':
      case 'PPLR':
      case 'PPLS':
      case 'PPLQ':
        return 8;
      case 'ADM1':
      case 'ADM2':
      case 'ADM3':
      case 'ADM4':
        return 5;
      default:
        if (fc.startsWith('PPL')) return 18;
        return 0;
    }
  }
}
