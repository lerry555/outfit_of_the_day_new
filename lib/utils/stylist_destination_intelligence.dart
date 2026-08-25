import '../data/parsed_destination.dart';
import 'activity_traits_inferencer.dart';
import 'stylist_destination_parser.dart';

/// Typovo vedomá vrstva nad [StylistDestinationParser] — rozhoduje podľa
/// štruktúry frázy, nie podľa whitelistu konkrétnych POI.
abstract final class StylistDestinationIntelligence {
  /// Malý zoznam zložených názvov s mestom — optimalizácia, nie hlavná logika.
  static const Map<String, String> _compositeCityShortcuts = {
    'zoo praha': 'Praha',
    'zoo v praze': 'Praha',
    'disneyland paris': 'Paris',
    'disneyland paríž': 'Paris',
    'universal studios hollywood': 'Los Angeles',
    'tatralandia liptovský mikuláš': 'Liptovský Mikuláš',
    'tatralandia liptovsky mikulas': 'Liptovský Mikuláš',
  };

  /// Subnárodné regióny (nie krajiny) — katalóg, nie patch logika.
  static const Map<String, String> _subnationalRegions = {
    'toskánsko': 'Toskánsko',
    'toskansko': 'Toskánsko',
    'toscana': 'Toskánsko',
    'bavorsko': 'Bavorsko',
    'bavorsk': 'Bavorsko',
    'provence': 'Provence',
    'kalifornia': 'Kalifornia',
    'kaliforni': 'Kalifornia',
    'florida': 'Florida',
    'floride': 'Florida',
    'sicília': 'Sicília',
    'sicilia': 'Sicília',
    'sicílie': 'Sicília',
    'sicilie': 'Sicília',
    'lapónsko': 'Lapónsko',
    'laponsko': 'Lapónsko',
    'skandinávia': 'Skandinávia',
    'skandinavia': 'Skandinávia',
    'alpsk': 'Alpy',
    'pyreneje': 'Pyreneje',
    'balkán': 'Balkán',
    'balkan': 'Balkán',
    'karibik': 'Karibik',
    'stredomorie': 'Stredomorie',
    'andorr': 'Andorra',
    'katalánsko': 'Katalánsko',
    'katalansko': 'Katalánsko',
    'normandia': 'Normandia',
    'tasmánia': 'Tasmánia',
    'tasmania': 'Tasmánia',
    'queensland': 'Queensland',
    'patagónia': 'Patagónia',
    'patagonia': 'Patagónia',
    'patagónie': 'Patagónia',
    'patagonie': 'Patagónia',
    'toskánska': 'Toskánsko',
    'toskánsku': 'Toskánsko',
    'bavorska': 'Bavorsko',
    'bavorsku': 'Bavorsko',
    'kalifornie': 'Kalifornia',
    'kalifornii': 'Kalifornia',
    'sicílii': 'Sicília',
    'sicilii': 'Sicília',
    'sicíliou': 'Sicília',
    'škandinávie': 'Skandinávia',
    'skandinavie': 'Skandinávia',
    'álpy': 'Alpy',
    'alpy': 'Alpy',
    'alpách': 'Alpy',
    'alpach': 'Alpy',
    'álp': 'Alpy',
    'alp': 'Alpy',
  };

  static final RegExp _airportKeyword = RegExp(
    r'\b(letisko|airport|letiště|letiste|letisku|letiskom)\b',
    caseSensitive: false,
  );

  static final RegExp _vagueAirportPhrase = RegExp(
    r'\b(na|do|k)\s+letisk',
    caseSensitive: false,
  );

  static final RegExp _addressPattern = RegExp(
    r'\b(ulica|ul\.|ul\s|námestie|nám\.|namestie|nam\.|'
    r'číslo|cislo|č\.\s*\d|\d+\s+[a-záäčďéíĺľňóôřšťúýž])',
    caseSensitive: false,
  );

  static final RegExp _venueStructure = RegExp(
    r'\b(nákupné\s+centr|nákupného\s+centr|nákupného\s+centra|nakupneho\s+centra|'
    r'nakupne\s+centr|obchodné\s+centr|obchodného\s+centr|obchodného\s+centra|'
    r'obchodnom\s+centr|obchodnom\s+centre|obchodnom\s+centra|'
    r'shopping\s+cent|nákupák|nakupak|nákupáku|nakupaku|mall|outlet\s+centr)\b',
    caseSensitive: false,
  );

  static final RegExp _travelPrepositionPhrase = RegExp(
    r'(?:\bv|\bvo|\bdo|\bpri)\s+'
    r'([a-záäčďéíĺľňóôřšťúýž][a-záäčďéíĺľňóôřšťúýž-]{1,}'
    r'(?:\s+(?!do\b|na\b|v\b|vo\b|pri\b|od\b|a\b|so\b|s\b|'
    r'zajtra\b|dnes\b|budeme\b|idem\b|ideme\b|potrebujem\b)'
    r'[a-záäčďéíĺľňóôřšťúýž][a-záäčďéíĺľňóôřšťúýž-]{1,})?)',
    caseSensitive: false,
  );

  static ParsedDestination parse(
    String text, {
    Set<String> exclude = const <String>{},
  }) {
    final raw = text.trim();
    if (raw.isEmpty) return ParsedDestination.none();

    final blob = raw.toLowerCase();
    final excludeLower = exclude.map((e) => e.toLowerCase().trim()).toSet();

    if (!_mentionsTravelDestination(blob, raw)) {
      return ParsedDestination.none(rawText: raw);
    }

    // Rutinná aktivita v aktuálnom meste — „idem do práce“ nie je cestovná destinácia.
    if (_gpsSufficientRoutineActivity(raw)) {
      final country = StylistDestinationParser.broadRegionInConversation(raw);
      final region = _regionInConversation(blob);
      if (country == null && region == null && !_venueStructure.hasMatch(blob)) {
        final phrases = _extractPhrases(raw);
        final hasNamedPlace = phrases.any((phrase) {
          final normalized =
              StylistDestinationParser.normalizePlacePhrase(phrase);
          if (!StylistDestinationParser.isPlausibleDestination(normalized)) {
            return false;
          }
          final traits = ActivityTraitsInferencer.infer('idem do $normalized');
          return traits.poiDependent ||
              (!traits.routineLocal && !traits.venueBound);
        });
        if (!hasNamedPlace) {
          final city = StylistDestinationParser.inferCityCandidate(
            raw,
            exclude: exclude,
          );
          if (!StylistDestinationParser.isConfidentResolvableCity(city)) {
            return ParsedDestination.none(rawText: raw);
          }
        }
      }
    }

    // 1. Letisko — štrukturálna detekcia.
    final airport = _classifyAirport(raw, blob, excludeLower);
    if (airport != null) return airport;

    // 2. Adresa — štrukturálna detekcia.
    final address = _classifyAddress(raw, blob, excludeLower);
    if (address != null) return address;

    // 3. Krajina / región bez mesta.
    final country = StylistDestinationParser.broadRegionInConversation(raw);
    final region = _regionInConversation(blob);
    final cityCandidate = StylistDestinationParser.inferCityCandidate(
      raw,
      exclude: exclude,
    );
    final hasConfidentCity =
        StylistDestinationParser.isConfidentResolvableCity(cityCandidate);

    if (country != null && !hasConfidentCity) {
      return _countryNeedsCity(raw, country);
    }
    if (region != null && !hasConfidentCity) {
      return _regionNeedsCity(raw, region);
    }

    // 4. Jednoznačné mesto z inferencie (pred POI frázami — „Rio de Janeiro“).
    if (hasConfidentCity && cityCandidate != null) {
      return ParsedDestination(
        rawText: raw,
        normalizedName: cityCandidate,
        type: DestinationType.city,
        confidence: 0.92,
        reason: 'confident_city',
        needsClarification: false,
        extractedPhrase: cityCandidate,
        parentLocation: country ?? region,
      );
    }

    // 5. Extrahované frázy po predložke — POI/venue bez známeho mesta.
    final phrases = _extractPhrases(raw);
    for (final phrase in phrases) {
      final classified = _classifyPhrase(
        raw,
        phrase,
        excludeLower: excludeLower,
      );
      if (classified != null) return classified;
    }

    // 6. Holá odpoveď používateľa (1–2 slová) — mesto po doplňujúcej otázke.
    final bareCity = _bareCityReply(raw, excludeLower);
    if (bareCity != null) {
      return ParsedDestination(
        rawText: raw,
        normalizedName: bareCity,
        type: DestinationType.city,
        confidence: 0.85,
        reason: 'bare_city_reply',
        needsClarification: false,
        extractedPhrase: bareCity,
      );
    }

    return ParsedDestination(
      rawText: raw,
      type: DestinationType.unknown,
      confidence: 0.4,
      reason: 'unresolved_travel_destination',
      needsClarification: true,
      clarificationQuestionSk:
          'V ktorom meste alebo lokalite sa to nachádza?',
    );
  }

  static bool _mentionsTravelDestination(String blob, String raw) {
    if (StylistDestinationParser.broadRegionInConversation(raw) != null) {
      return true;
    }
    if (_regionInConversation(blob) != null) return true;
    if (RegExp(r'\bna\s+(sicílii|sicilii|floride|island|maldiv)', caseSensitive: false)
        .hasMatch(blob)) {
      return true;
    }
    if (_airportKeyword.hasMatch(blob)) return true;
    if (_addressPattern.hasMatch(blob)) return true;
    if (_travelPrepositionPhrase.hasMatch(raw)) {
      final phrases = _extractPhrases(raw);
      final anyRealPlace = phrases.any((phrase) {
        final normalized =
            StylistDestinationParser.normalizePlacePhrase(phrase);
        return StylistDestinationParser.isPlausibleDestination(normalized);
      });
      if (anyRealPlace) return true;
    }
    if (blob.contains('navštív') || blob.contains('navstiv')) return true;
    if (RegExp(
      r'\b(?:v|vo)\s+(?:hoteli|parku|komplexe|resorte|areáli|areali)\s+'
      r'[A-ZÁÄČĎÉÍĹĽŇÓÔŘŠŤÚÝŽ]',
      caseSensitive: false,
    ).hasMatch(raw)) {
      return true;
    }
    if (RegExp(r'\b(idem|ideme|cestuj|letí|letim|letíme|letime)\b').hasMatch(blob) &&
        RegExp(r'\b(do|v|vo|na|pri)\b').hasMatch(blob)) {
      return true;
    }
    return false;
  }

  /// Práca, obed, škola… — GPS mesto stačí. Kino/koncert/festival nie (môžu byť POI).
  static bool _gpsSufficientRoutineActivity(String raw) {
    final traits = ActivityTraitsInferencer.infer(raw);
    return traits.routineLocal &&
        !traits.outdoor &&
        !traits.travel &&
        !traits.poiDependent;
  }

  static String? _regionInConversation(String blob) {
    final entries = _subnationalRegions.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in entries) {
      final pattern = RegExp(
        r'(?:^|[^0-9a-záäčďéíĺľňóôřšťúýž])' +
            RegExp.escape(entry.key) +
            r'(?![0-9a-záäčďéíĺľňóôřšťúýž])',
        caseSensitive: false,
      );
      if (pattern.hasMatch(blob)) return entry.value;
    }
    return null;
  }

  static List<String> _extractPhrases(String text) {
    final out = <String>[];
    for (final m in _travelPrepositionPhrase.allMatches(text)) {
      final raw = (m.group(1) ?? '').trim();
      if (raw.length >= 2) out.add(raw);
    }
    final visitMatches = RegExp(
      r'\b(?:navštív\w*|navstiv\w*)\s+'
      r'([A-ZÁÄČĎÉÍĹĽŇÓÔŘŠŤÚÝŽa-záäčďéíĺľňóôřšťúýž][A-ZÁÄČĎÉÍĹĽŇÓÔŘŠŤÚÝŽa-záäčďéíĺľňóôřšťúýž-]{1,}'
      r'(?:\s+[A-ZÁÄČĎÉÍĹĽŇÓÔŘŠŤÚÝŽa-záäčďéíĺľňóôřšťúýž][A-ZÁÄČĎÉÍĹĽŇÓÔŘŠŤÚÝŽa-záäčďéíĺľňóôřšťúýž-]{1,})?)',
      caseSensitive: false,
    ).allMatches(text);
    for (final m in visitMatches) {
      final raw = (m.group(1) ?? '').trim();
      if (raw.length >= 2) out.add(raw);
    }
    final hostedPlace = RegExp(
      r'\b(?:v|vo)\s+(?:hoteli|parku|komplexe|resorte|areáli|areali)\s+'
      r'([A-ZÁÄČĎÉÍĹĽŇÓÔŘŠŤÚÝŽ][A-ZÁÄČĎÉÍĹĽŇÓÔŘŠŤÚÝŽa-záäčďéíĺľňóôřšťúýž-]{1,}'
      r'(?:\s+[A-ZÁÄČĎÉÍĹĽŇÓÔŘŠŤÚÝŽ][A-ZÁÄČĎÉÍĹĽŇÓÔŘŠŤÚÝŽa-záäčďéíĺľňóôřšťúýž-]{1,})?)',
      caseSensitive: false,
    ).allMatches(text);
    for (final m in hostedPlace) {
      final raw = (m.group(1) ?? '').trim();
      if (raw.length >= 2) out.add(raw);
    }
    return out;
  }

  static ParsedDestination? _classifyAirport(
    String raw,
    String blob,
    Set<String> excludeLower,
  ) {
    if (!_airportKeyword.hasMatch(blob)) return null;

    final city = StylistDestinationParser.inferCityCandidate(raw);
    if (StylistDestinationParser.isConfidentResolvableCity(city) &&
        city != null &&
        !excludeLower.contains(city.toLowerCase())) {
      return ParsedDestination(
        rawText: raw,
        normalizedName: city,
        embeddedCity: city,
        type: DestinationType.airport,
        confidence: 0.88,
        reason: 'airport_with_city',
        needsClarification: false,
        extractedPhrase: city,
      );
    }

    final hasSpecificAirport = RegExp(
      r'letisko\s+[a-záäčďéíĺľňóôřšťúýž]{3,}',
      caseSensitive: false,
    ).hasMatch(blob);

    if (_vagueAirportPhrase.hasMatch(blob) && !hasSpecificAirport) {
      return ParsedDestination(
        rawText: raw,
        type: DestinationType.airport,
        confidence: 0.9,
        reason: 'airport_unspecified',
        needsClarification: true,
        clarificationQuestionSk: 'Ktoré letisko máš na mysli?',
        extractedPhrase: 'letisko',
      );
    }

    if (!hasSpecificAirport) {
      return ParsedDestination(
        rawText: raw,
        type: DestinationType.airport,
        confidence: 0.75,
        reason: 'airport_needs_city',
        needsClarification: true,
        clarificationQuestionSk: 'Ktoré letisko máš na mysli?',
        extractedPhrase: 'letisko',
      );
    }

    return null;
  }

  static ParsedDestination? _classifyAddress(
    String raw,
    String blob,
    Set<String> excludeLower,
  ) {
    if (!_addressPattern.hasMatch(blob)) return null;

    final city = StylistDestinationParser.inferCityCandidate(raw);
    if (StylistDestinationParser.isConfidentResolvableCity(city) &&
        city != null &&
        !excludeLower.contains(city.toLowerCase())) {
      return ParsedDestination(
        rawText: raw,
        normalizedName: city,
        type: DestinationType.address,
        confidence: 0.8,
        reason: 'address_with_city',
        needsClarification: false,
        extractedPhrase: city,
      );
    }

    return ParsedDestination(
      rawText: raw,
      type: DestinationType.address,
      confidence: 0.55,
      reason: 'address_needs_city',
      needsClarification: true,
      clarificationQuestionSk:
          'V ktorom meste je tá adresa?',
    );
  }

  static ParsedDestination _countryNeedsCity(String raw, String country) {
    return ParsedDestination(
      rawText: raw,
      type: DestinationType.country,
      confidence: 0.95,
      reason: 'country_without_city',
      needsClarification: true,
      parentLocation: country,
      clarificationQuestionSk:
          StylistDestinationParser.broadRegionCityQuestion(country),
      extractedPhrase: country,
    );
  }

  static ParsedDestination _regionNeedsCity(String raw, String region) {
    final loc = _regionLocativePhrase(region);
    return ParsedDestination(
      rawText: raw,
      type: DestinationType.region,
      confidence: 0.93,
      reason: 'region_without_city',
      needsClarification: true,
      parentLocation: region,
      clarificationQuestionSk:
          'Do ktorého mesta $loc idete? Počasie sa môže veľmi líšiť podľa mesta.',
      extractedPhrase: region,
    );
  }

  static String _regionLocativePhrase(String region) {
    const custom = {
      'Toskánsko': 'v Toskánsku',
      'Bavorsko': 'v Bavorsku',
      'Provence': 'v Provence',
      'Kalifornia': 'v Kalifornii',
      'Florida': 'na Floride',
      'Sicília': 'na Sicílii',
      'Lapónsko': 'v Laponsku',
      'Skandinávia': 'v Škandinávii',
      'Alpy': 'v Alpách',
      'Pyreneje': 'v Pyrenejách',
      'Balkán': 'na Balkáne',
      'Karibik': 'v Karibiku',
      'Stredomorie': 'na Stredomorí',
      'Andorra': 'v Andorre',
      'Katalánsko': 'v Katalánsku',
      'Normandia': 'v Normandii',
      'Tasmánia': 'v Tasmánii',
      'Queensland': 'v Queenslande',
      'Patagónia': 'v Patagónii',
    };
    return custom[region] ?? 'v $region';
  }

  static ParsedDestination? _classifyPhrase(
    String raw,
    String phrase, {
    required Set<String> excludeLower,
  }) {
    final normalized = StylistDestinationParser.normalizePlacePhrase(phrase);
    final lower = normalized.toLowerCase();
    final blob = raw.toLowerCase();

    if (excludeLower.contains(lower)) return null;

    if (StylistDestinationParser.isBroadRegion(normalized) ||
        StylistDestinationParser.isBroadRegion(phrase)) {
      final cityInText = StylistDestinationParser.inferCityCandidate(raw);
      if (StylistDestinationParser.isConfidentResolvableCity(cityInText)) {
        return null;
      }
      final country = StylistDestinationParser.broadRegionInConversation(
            '$phrase $raw',
          ) ??
          normalized;
      return _countryNeedsCity(raw, country);
    }

    final region = _matchRegionPhrase(lower);
    if (region != null) {
      final cityInText = StylistDestinationParser.inferCityCandidate(raw);
      if (!StylistDestinationParser.isConfidentResolvableCity(cityInText)) {
        return _regionNeedsCity(raw, region);
      }
      return null;
    }

    if (!StylistDestinationParser.isPlausibleDestination(normalized)) {
      return null;
    }

    // Zložený názov s mestom (Zoo Praha, Disneyland Paris…).
    final embedded = _embeddedCity(normalized, lower);
    if (embedded != null && !excludeLower.contains(embedded.toLowerCase())) {
      final isVenue = _venueStructure.hasMatch(lower);
      return ParsedDestination(
        rawText: raw,
        normalizedName: embedded,
        embeddedCity: embedded,
        type: isVenue ? DestinationType.venue : DestinationType.pointOfInterest,
        confidence: 0.9,
        reason: 'named_place_with_city',
        needsClarification: false,
        extractedPhrase: normalized,
      );
    }

    // Jednoznačné mesto.
    if (StylistDestinationParser.isConfidentResolvableCity(normalized)) {
      return ParsedDestination(
        rawText: raw,
        normalizedName: normalized,
        type: DestinationType.city,
        confidence: 0.9,
        reason: 'phrase_is_city',
        needsClarification: false,
        extractedPhrase: normalized,
      );
    }

    // Neznámy pomenovaný objekt — všeobecný mechanizmus (nie whitelist).
    if (_isUnresolvedNamedPlace(normalized, lower)) {
      final isVenue = _venueStructure.hasMatch(lower) ||
          _venueStructure.hasMatch(blob);
      final type =
          isVenue ? DestinationType.venue : DestinationType.pointOfInterest;
      return ParsedDestination(
        rawText: raw,
        type: type,
        confidence: 0.82,
        reason: 'named_place_without_city',
        needsClarification: true,
        clarificationQuestionSk: isVenue
            ? 'V ktorom meste je ten $normalized?'
            : 'V ktorom meste sa $normalized nachádza?',
        extractedPhrase: normalized,
      );
    }

    return null;
  }

  static String? _matchRegionPhrase(String lower) {
    for (final entry in _subnationalRegions.entries) {
      if (lower == entry.key || lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  static String? _embeddedCity(String normalized, String lower) {
    for (final entry in _compositeCityShortcuts.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    final words = normalized.split(RegExp(r'\s+'));
    if (words.length < 2) return null;

    for (var start = 1; start < words.length; start++) {
      final tail = words.sublist(start).join(' ');
      final candidate = StylistDestinationParser.normalizePlacePhrase(tail);
      if (StylistDestinationParser.isConfidentResolvableCity(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static bool _isUnresolvedNamedPlace(String normalized, String lower) {
    if (lower.length < 2) return false;
    if (StylistDestinationParser.isBroadRegion(normalized)) return false;
    if (_matchRegionPhrase(lower) != null) return false;
    if (!StylistDestinationParser.isPlausibleDestination(normalized)) {
      return false;
    }
    // Krátke neznáme tokeny (ZOO, SIX) nie sú mestá.
    if (normalized.split(RegExp(r'\s+')).length == 1 &&
        lower.length <= 4 &&
        !StylistDestinationParser.isKnownCityShortcut(lower)) {
      return true;
    }
    // Viacslovný alebo dlhší vlastný názov bez rozpoznaného mesta.
    if (normalized.split(RegExp(r'\s+')).length >= 1) {
      return !StylistDestinationParser.isConfidentResolvableCity(normalized);
    }
    return false;
  }

  static String? _bareCityReply(String raw, Set<String> excludeLower) {
    final blob = raw.toLowerCase().trim();
    final words = blob.split(RegExp(r'\s+'));
    if (words.length > 2) return null;
    if (blob.length < 3) return null;
    if (!StylistDestinationParser.isPlausibleDestination(blob)) return null;
    if (StylistDestinationParser.isBroadRegion(blob)) return null;
    final result = StylistDestinationParser.normalizePlacePhrase(blob);
    if (excludeLower.contains(result.toLowerCase())) return null;
    if (!StylistDestinationParser.isConfidentResolvableCity(result)) {
      return null;
    }
    return result;
  }
}
