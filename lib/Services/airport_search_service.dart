import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'destination_search_service.dart';

/// Letisko — GeoNames cez Open-Meteo; výsledky len AIRP/AIRB/AIRH.
class AirportSuggestion {
  final String name;
  final String country;
  final String? adminCity;
  final double latitude;
  final double longitude;
  final String featureCode;
  final int? population;

  const AirportSuggestion({
    required this.name,
    required this.country,
    this.adminCity,
    required this.latitude,
    required this.longitude,
    required this.featureCode,
    this.population,
  });

  /// Horný riadok (prefer. slovenské názvy pre známe letiská).
  String get primaryLine => AirportSearchService.displayPrimaryLine(this);

  /// Druhý riadok: mesto, krajina (lokalizované z API).
  String get secondaryLine {
    final city = (adminCity ?? '').trim();
    if (city.isNotEmpty) return '$city, $country';
    return country;
  }

  String get routeShortLabel {
    final code = AirportSearchService.resolveIata(this);
    if (code != null && code.isNotEmpty) return code;
    final short = name.split(',').first.trim();
    return short.length > 28 ? '${short.substring(0, 26)}…' : short;
  }
}

abstract final class AirportSearchService {
  AirportSearchService._();

  static const _host = 'geocoding-api.open-meteo.com';
  static const _path = '/v1/search';

  static const _airportFeatures = {'AIRP', 'AIRB', 'AIRH'};

  /// Ďalšie dotazy podľa prefixu (API pri krátkych reťazcoch vracia málo fuzzy výsledkov).
  static const Map<String, List<String>> _prefixBoostQueries = {
    'br': ['Bratislava Airport', 'Brussels Airport'],
    'bra': ['Bratislava Airport', 'Brno Airport'],
    'brat': ['Bratislava', 'Bratislava Airport'],
    'brati': ['Bratislava Airport'],
    'bru': ['Brussels Airport'],
    'hur': ['Hurghada International Airport', 'Hurghada'],
    'hurg': ['Hurghada International Airport'],
    'hurgh': ['Hurghada'],
    'hurgha': ['Hurghada'],
    'vi': ['Vienna International Airport'],
    'vie': ['Vienna International Airport'],
    'vienn': ['Vienna'],
    'vied': ['Vienna International Airport'],
    'vienna': ['Vienna International Airport'],
    'pra': ['Prague Airport'],
    'par': ['Paris Charles de Gaulle Airport', 'Paris Orly Airport'],
    'bu': ['Budapest Airport'],
    'war': ['Warsaw Chopin Airport'],
    'lo': ['London Heathrow Airport', 'London'],
    'lon': ['London Heathrow Airport', 'London Gatwick Airport'],
    'lond': ['London Heathrow Airport', 'London'],
    'mil': ['Milan Malpensa Airport', 'Milan'],
    'mun': ['Munich Airport'],
    'rim': ['Rome Fiumicino Airport'],
    'rome': ['Rome Fiumicino Airport'],
    'ven': ['Venice Marco Polo Airport', 'Venice'],
    'ben': ['Venice Marco Polo Airport'],
  };

  /// Slovenské/prechyľné aliasy miest → anglický dotaz pre geocoder.
  static const Map<String, String> _skCityAliasQuery = {
    'londyn': 'London',
    'london': 'London',
    'vieden': 'Vienna',
    'vienna': 'Vienna',
    'pariz': 'Paris',
    'benatky': 'Venice',
    'benatk': 'Venice',
    'rim': 'Rome',
    'milano': 'Milan',
    'mnichov': 'Munich',
  };

  static const List<String> _londonMetroAirportQueries = [
    'London Heathrow Airport',
    'London Gatwick Airport',
    'London Stansted Airport',
    'London Luton Airport',
    'London City Airport',
  ];

  static const Map<String, String> _iataHintQueries = {
    'bts': 'Bratislava Airport',
    'vie': 'Vienna International Airport',
    'hrg': 'Hurghada International Airport',
    'ssh': 'Sharm El Sheikh Airport',
    'mxp': 'Milan Malpensa Airport',
    'fco': 'Rome Fiumicino Airport',
    'bcn': 'Barcelona Airport',
    'mad': 'Madrid Airport',
    'cdg': 'Paris Charles de Gaulle Airport',
    'ory': 'Paris Orly Airport',
    'lhr': 'London Heathrow Airport',
    'lgw': 'London Gatwick Airport',
    'stn': 'London Stansted Airport',
    'ltn': 'London Luton Airport',
    'lcy': 'London City Airport',
    'ams': 'Amsterdam Schiphol Airport',
    'fra': 'Frankfurt Airport',
    'muc': 'Munich Airport',
    'prg': 'Prague Airport',
    'bud': 'Budapest Airport',
    'waw': 'Warsaw Chopin Airport',
    'dxb': 'Dubai International Airport',
    'ayt': 'Antalya Airport',
    'pmi': 'Palma Mallorca Airport',
    'tfs': 'Tenerife South Airport',
    'cta': 'Catania Airport',
    'nap': 'Naples Airport',
    'zag': 'Zagreb Airport',
    'beg': 'Belgrade Airport',
    'otp': 'Bucharest Otopeni Airport',
    'sof': 'Sofia Airport',
    'ath': 'Athens Airport',
    'lis': 'Lisbon Airport',
    'arn': 'Stockholm Arlanda Airport',
    'osl': 'Oslo Gardermoen Airport',
    'cph': 'Copenhagen Airport',
    'krk': 'Krakow Airport',
    'ktw': 'Katowice Airport',
    'gdn': 'Gdansk Airport',
    'mla': 'Malta Airport',
    'bru': 'Brussels Airport',
    'edi': 'Edinburgh Airport',
    'man': 'Manchester Airport',
    'dub': 'Dublin Airport',
    'her': 'Heraklion Airport',
    'skg': 'Thessaloniki Airport',
    'ist': 'Istanbul Airport',
    'saw': 'Istanbul Sabiha Gokcen Airport',
    'kef': 'Keflavik Airport',
    'rjk': 'Rijeka Airport',
    'spu': 'Split Airport',
    'dbv': 'Dubrovnik Airport',
  };

  static const Map<String, String> _iataByNormalizedFragment = {
    'bratislava airport': 'BTS',
    'stefanik': 'BTS',
    'schwechat': 'VIE',
    'vienna international': 'VIE',
    'hurghada international': 'HRG',
    'sharm el-sheikh': 'SSH',
    'sharm el sheikh': 'SSH',
    'malpensa': 'MXP',
    'fiumicino': 'FCO',
    'heathrow': 'LHR',
    'gatwick': 'LGW',
    'stansted': 'STN',
    'luton': 'LTN',
    'london city': 'LCY',
    'schiphol': 'AMS',
    'frankfurt airport': 'FRA',
    'frankfurt main': 'FRA',
    'barcelona airport': 'BCN',
    'el prat': 'BCN',
    'charles de gaulle': 'CDG',
    'milan malpensa': 'MXP',
    'dubai international': 'DXB',
    'antalya airport': 'AYT',
    'naples airport': 'NAP',
    'catania': 'CTA',
    'catania airport': 'CTA',
    'fontanarossa': 'CTA',
    'palma': 'PMI',
    'tenerife south': 'TFS',
    'reina sofia': 'TFS',
    'vaclav havel': 'PRG',
    'ferihegy': 'BUD',
    'chopin': 'WAW',
  };

  /// Primárny titulok pre konkrétne IATA (SK kde dáva zmysel).
  static const Map<String, String> _displayTitleByIata = {
    'BTS': 'Letisko M. R. Štefánika',
    'HRG': 'Hurghada International Airport',
    'VIE': 'Viedenské medzinárodné letisko',
    'PRG': 'Letisko Václava Havla',
    'BUD': 'Letisko Feriházy',
  };

  static String displayPrimaryLine(AirportSuggestion a) {
    final code = resolveIata(a);
    final title = (code != null ? _displayTitleByIata[code] : null) ?? a.name;
    if (code != null && code.isNotEmpty) {
      return '$code — $title';
    }
    return title;
  }

  static String? resolveIata(AirportSuggestion a) {
    final paren = RegExp(r'\(([A-Z]{3})\)');
    final m = paren.firstMatch(a.name);
    if (m != null) return m.group(1);

    final n = DestinationSearchService.normalizeQuery(a.name);
    for (final e in _iataByNormalizedFragment.entries) {
      if (n.contains(e.key)) return e.value;
    }
    return null;
  }

  static Future<List<AirportSuggestion>> search(String query) async {
    final normalized = DestinationSearchService.normalizeQuery(query);
    if (normalized.length < 2) return const [];

    final queries = <String>{query.trim()};

    final hint = _iataHintQueries[normalized];
    if (hint != null) queries.add(hint);

    final aliasCity = _skCityAliasQuery[normalized];
    if (aliasCity != null) {
      queries.add(aliasCity);
      queries.add('$aliasCity airport');
    }
    for (final e in _skCityAliasQuery.entries) {
      final k = e.key;
      if (normalized.length >= 2 &&
          (normalized.startsWith(k) || (k.startsWith(normalized) && normalized.length >= 3))) {
        queries.add(e.value);
        queries.add('${e.value} airport');
        if (e.value == 'London') queries.addAll(_londonMetroAirportQueries);
        if (e.value == 'Vienna') {
          queries.add('Vienna International Airport');
          queries.add('Vienna Airport');
        }
      }
    }

    for (final e in _prefixBoostQueries.entries) {
      final k = e.key;
      if (normalized.length >= 2 &&
          (normalized.startsWith(k) || k.startsWith(normalized) || normalized == k)) {
        queries.addAll(e.value);
      }
    }

    final suggestsLondon = normalized.startsWith('lon') ||
        normalized.contains('london') ||
        aliasCity == 'London';
    if (suggestsLondon) {
      queries.addAll(_londonMetroAirportQueries);
    }

    final suggestsVienna =
        aliasCity == 'Vienna' || normalized.startsWith('vie') || normalized.startsWith('vied');
    if (suggestsVienna) {
      queries.add('Vienna International Airport');
      queries.add('Vienna Airport');
    }

    final merged = <String, AirportSuggestion>{};
    for (final q in queries) {
      final batch = await _fetchAirports(q.trim());
      for (final a in batch) {
        final key = '${a.latitude.toStringAsFixed(5)}:${a.longitude.toStringAsFixed(5)}';
        merged[key] = a;
      }
    }

    final list = merged.values.toList()
      ..sort((a, b) => _scoreAirport(a, normalized).compareTo(_scoreAirport(b, normalized)));

    final out = list.reversed.take(18).toList();
    debugPrint(
      '[AIRPORT_SEARCH] query=$query normalized=$normalized results=${out.map((a) => displayPrimaryLine(a)).join(' | ')}',
    );
    return out;
  }

  static const Set<String> _majorHubIata = {
    'LHR',
    'LGW',
    'STN',
    'LTN',
    'LCY',
    'VIE',
    'BTS',
    'CDG',
    'ORY',
    'AMS',
    'FRA',
    'MUC',
    'BCN',
    'MXP',
    'FCO',
    'PRG',
    'BUD',
    'WAW',
    'DXB',
  };

  static double _scoreAirport(AirportSuggestion a, String q) {
    final nName = DestinationSearchService.normalizeQuery(a.name);
    final nCity = DestinationSearchService.normalizeQuery(a.adminCity ?? '');
    final nCountry = DestinationSearchService.normalizeQuery(a.country);
    final iata = resolveIata(a);

    double score = 0;

    if (iata != null) {
      final iq = DestinationSearchService.normalizeQuery(iata);
      if (iq == q) score += 620;
      else if (iq.startsWith(q)) score += 560;
      else if (q.length >= 2 && iq.startsWith(q.substring(0, math.min(q.length, iq.length)))) {
        score += 240;
      }
      if (_majorHubIata.contains(iata)) score += 72;
    }

    if (nCity.isNotEmpty) {
      if (nCity.startsWith(q)) score += 410;
      else if (nCity.contains(q)) score += 140;
    }

    if (nName.startsWith(q)) score += 200;
    else if (_wordPrefix(nName, q)) score += 165;
    else if (nName.contains(q)) score += 88;

    if (nCountry.startsWith(q) || nCountry.contains(q)) score += 28;

    final pop = a.population ?? 0;
    if (pop > 0) {
      score += math.min(88, math.log(pop + 1) * 6.5);
    }

    if (a.featureCode == 'AIRP') score += 20;

    score -= math.min(22, nName.length / 28);

    final blob = '$nName $nCity $nCountry';
    if (blob.contains('bratislava')) score += 88;
    if (blob.contains('hurghada')) score += 88;
    if (blob.contains('london') && (q.startsWith('lon') || q.contains('london') || q.contains('lond'))) {
      score += 45;
    }

    return score;
  }

  static bool _wordPrefix(String normalized, String q) {
    if (normalized.startsWith(q)) return true;
    for (final w in normalized.split(RegExp(r'[\s\-]+'))) {
      if (w.startsWith(q)) return true;
    }
    return false;
  }

  static Future<List<AirportSuggestion>> _fetchAirports(String query) async {
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

    final out = <AirportSuggestion>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] as String?)?.trim();
      final country = (item['country'] as String?)?.trim();
      final lat = (item['latitude'] as num?)?.toDouble();
      final lon = (item['longitude'] as num?)?.toDouble();
      final fc = (item['feature_code'] as String?)?.trim();
      final pop = (item['population'] as num?)?.toInt();
      if (name == null || country == null || lat == null || lon == null || fc == null) {
        continue;
      }
      if (!_airportFeatures.contains(fc)) continue;
      final admin = (item['admin1'] as String?)?.trim();
      out.add(
        AirportSuggestion(
          name: name,
          country: country,
          adminCity: admin?.isEmpty ?? true ? null : admin,
          latitude: lat,
          longitude: lon,
          featureCode: fc,
          population: pop,
        ),
      );
    }
    return out;
  }
}
