import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'airport_record.dart';
import 'destination_search_service.dart';

/// Lokálny OurAirports JSON (assets/data/airports.json) + vyhľadávanie.
abstract final class AirportRepository {
  AirportRepository._();

  static const _assetPath = 'assets/data/airports.json';

  static List<AirportRecord>? _cache;
  static Map<String, AirportRecord>? _byIata;
  static Future<void>? _loadFuture;
  static String? _loadFailureMessage;

  /// Ak sa [ensureLoaded] nepodarí, text pre používateľa (SK). Inak `null`.
  static String? get loadFailureMessage => _loadFailureMessage;

  static Future<void> ensureLoaded() async {
    if (_cache != null) return;
    _loadFuture ??= _performLoad();
    await _loadFuture;
  }

  static Future<void> _performLoad() async {
    debugPrint('[AIRPORT_REPO] load start path=$_assetPath');
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final list = decoded['airports'] as List<dynamic>? ?? const [];
      final out = <AirportRecord>[];
      final map = <String, AirportRecord>{};
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        final a = AirportRecord.fromJson(e);
        if (a.iata.length != 3) continue;
        out.add(a);
        map[a.iata] = a;
      }
      _cache = out;
      _byIata = map;
      _loadFailureMessage = null;
      debugPrint(
        '[AIRPORT_REPO] loaded count=${out.length} BTS=${map.containsKey('BTS')}',
      );
    } catch (e, st) {
      debugPrint('[AIRPORT_REPO] load FAILED: $e\n$st');
      _loadFailureMessage =
          'Nepodarilo sa načítať databázu letísk (súbor assets). Skús znova spustiť aplikáciu alebo preinštaluj ju.';
      _cache = [];
      _byIata = {};
    }
  }

  static AirportRecord? byIata(String? code) {
    if (code == null) return null;
    final k = code.trim().toUpperCase();
    if (k.length != 3) return null;
    return _byIata?[k];
  }

  /// Vyhľadávanie podľa IATA / mesta / názvu / krajiny; väčšie komerčné letiská skôr.
  static Future<List<AirportRecord>> search(String query, {int limit = 14}) async {
    await ensureLoaded();
    final all = _cache!;
    final qRaw = query.trim();
    if (qRaw.length < 2) return const [];

    final norm = DestinationSearchService.normalizeQuery(qRaw);
    if (norm.length < 2) return const [];

    final tokens = norm.split(RegExp(r'\s+')).where((t) => t.length >= 2).toList();
    if (tokens.isEmpty && norm.length >= 2) {
      tokens.add(norm);
    }

    final scored = <({AirportRecord a, double score})>[];

    for (final a in all) {
      final s = _scoreAirport(a, norm, tokens, qRaw);
      if (s > 0) scored.add((a: a, score: s));
    }

    scored.sort((x, y) {
      final c = y.score.compareTo(x.score);
      if (c != 0) return c;
      final t = typeRank(x.a).compareTo(typeRank(y.a));
      if (t != 0) return t;
      return x.a.iata.compareTo(y.a.iata);
    });

    final out = scored.take(limit).map((e) => e.a).toList(growable: false);
    if (kDebugMode) {
      final top = out.take(5).map((a) => a.iata).join(',');
      debugPrint(
        '[AIRPORT_REPO] search q="$qRaw" norm="$norm" matches=${scored.length} '
        'returned=${out.length} top=[$top] hasBTS=${out.any((a) => a.iata == 'BTS')}',
      );
    }
    return out;
  }

  static int typeRank(AirportRecord a) => a.isLargeHub ? 0 : 1;

  static double _scoreAirport(
    AirportRecord a,
    String normFull,
    List<String> tokens,
    String qRaw,
  ) {
    final iata = a.iata.toLowerCase();
    final city = DestinationSearchService.normalizeQuery(a.city);
    final name = DestinationSearchService.normalizeQuery(a.name);
    final country = DestinationSearchService.normalizeQuery(a.country);
    final iso = a.isoCountry.toLowerCase();

    var score = 0.0;

    final q3 = normFull.length == 3 ? normFull : '';
    if (q3.isNotEmpty && iata == q3) {
      score += 1e9;
    } else if (normFull.length >= 2 && iata.startsWith(normFull)) {
      score += 5e5;
    }

    if (city == normFull) score += 8e5;
    if (name == normFull) score += 6e5;

    if (city.contains(normFull)) score += 2e5;
    if (name.contains(normFull)) score += 1.5e5;
    if (country.contains(normFull) || iso == normFull) score += 8e4;

    for (final t in tokens) {
      if (t.length < 2) continue;
      if (iata.contains(t)) score += 50000;
      if (city.contains(t)) score += 40000;
      if (name.contains(t)) score += 35000;
      if (country.contains(t)) score += 15000;
    }

    final paren = RegExp(r'\(([A-Za-z]{3})\)\s*$').firstMatch(qRaw.trim());
    if (paren != null) {
      final inParen = paren.group(1)!.toUpperCase();
      if (inParen == a.iata) score += 2e9;
    }

    if (a.isLargeHub) score += 1200;
    return score;
  }

  /// Najlepší jednoznačný odhad z voľného textu (ak je príliš nejednoznačné, vráti null).
  static Future<AirportRecord?> resolveBest(String text) async {
    final t = text.trim();
    if (t.isEmpty) return null;

    final direct = byIata(t.toUpperCase());
    if (direct != null) return direct;

    final paren = RegExp(r'\(([A-Za-z]{3})\)').firstMatch(t);
    if (paren != null) {
      final fromParen = byIata(paren.group(1));
      if (fromParen != null) return fromParen;
    }

    final hits = await search(t, limit: 4);
    if (hits.isEmpty) return null;
    if (hits.length == 1) return hits.first;

    final top = hits.first;
    final second = hits[1];
    final n = DestinationSearchService.normalizeQuery(t);
    final s1 = _scoreAirport(top, n, n.split(RegExp(r'\s+')).where((x) => x.length >= 2).toList(), t);
    final s2 = _scoreAirport(second, n, n.split(RegExp(r'\s+')).where((x) => x.length >= 2).toList(), t);
    if (s1 >= s2 * 1.35) return top;
    return null;
  }
}
