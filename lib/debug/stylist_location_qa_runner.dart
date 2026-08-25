import 'package:flutter/foundation.dart';

import '../data/parsed_destination.dart';
import '../utils/stylist_destination_parser.dart';
import 'stylist_qa_runtime.dart';

/// Očakávané rozhodnutie lokálnej location logiky (early gate v [_sendMessage]).
enum LocationExpected {
  needsCityClarification,
  canGenerate,
}

extension LocationExpectedLabel on LocationExpected {
  String get label => switch (this) {
        LocationExpected.needsCityClarification => 'needsCityClarification',
        LocationExpected.canGenerate => 'canGenerate',
      };
}

/// Typ detekovanej destinácie v texte (M9).
enum LocationDetectedType {
  broadRegion,
  city,
  pointOfInterest,
  venue,
  airport,
  address,
  region,
  unknown,
  none,
}

extension LocationDetectedTypeLabel on LocationDetectedType {
  String get label => switch (this) {
        LocationDetectedType.broadRegion => 'broad_region',
        LocationDetectedType.city => 'city',
        LocationDetectedType.pointOfInterest => 'point_of_interest',
        LocationDetectedType.venue => 'venue',
        LocationDetectedType.airport => 'airport',
        LocationDetectedType.address => 'address',
        LocationDetectedType.region => 'region',
        LocationDetectedType.unknown => 'unknown',
        LocationDetectedType.none => 'none',
      };

  static LocationDetectedType fromDestinationType(DestinationType type) =>
      switch (type) {
        DestinationType.none => LocationDetectedType.none,
        DestinationType.city => LocationDetectedType.city,
        DestinationType.country => LocationDetectedType.broadRegion,
        DestinationType.region => LocationDetectedType.region,
        DestinationType.pointOfInterest =>
          LocationDetectedType.pointOfInterest,
        DestinationType.venue => LocationDetectedType.venue,
        DestinationType.airport => LocationDetectedType.airport,
        DestinationType.address => LocationDetectedType.address,
        DestinationType.ambiguous || DestinationType.unknown =>
          LocationDetectedType.unknown,
      };
}

/// Jeden QA prípad — krajina/región/POI/mesto/letisko…
class LocationQaCase {
  const LocationQaCase({
    required this.label,
    required this.prompt,
    required this.expected,
    this.category = 'unspecified',
  });

  final String label;
  final String prompt;
  final LocationExpected expected;
  final String category;
}

/// Výsledok jedného QA prípadu.
class LocationQaCaseResult {
  const LocationQaCaseResult({
    required this.testCase,
    required this.actual,
    required this.pass,
    this.detectedDestination,
    required this.detectedType,
    required this.reason,
  });

  final LocationQaCase testCase;
  final LocationExpected actual;
  final bool pass;
  final String? detectedDestination;
  final LocationDetectedType detectedType;
  final String reason;
}

/// Súhrn celého behu.
class StylistLocationQaSummary {
  const StylistLocationQaSummary({
    required this.total,
    required this.passed,
    required this.failed,
    required this.countryTotal,
    required this.countryBlocked,
    required this.cityTotal,
    required this.cityAllowed,
    required this.failureReasonCounts,
    this.categoryCounts = const {},
  });

  final int total;
  final int passed;
  final int failed;
  final int countryTotal;
  final int countryBlocked;
  final int cityTotal;
  final int cityAllowed;
  final Map<String, int> failureReasonCounts;
  final Map<String, ({int passed, int total})> categoryCounts;

  String formatHeader() {
    final b = StringBuffer()
      ..writeln('Cases: $total')
      ..writeln('Passed: $passed')
      ..writeln('Failed: $failed')
      ..writeln('Countries blocked: $countryBlocked/$countryTotal')
      ..writeln('Resolvable locations allowed: $cityAllowed/$cityTotal');
    if (categoryCounts.isNotEmpty) {
      b.writeln('By category:');
      final sorted = categoryCounts.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final e in sorted) {
        b.writeln('- ${e.key}: ${e.value.passed}/${e.value.total}');
      }
    }
    return b.toString().trimRight();
  }
}

class StylistLocationQaRunResult {
  const StylistLocationQaRunResult({
    required this.results,
    required this.summary,
    required this.meta,
  });

  final List<LocationQaCaseResult> results;
  final StylistLocationQaSummary summary;
  final StylistQaRunMeta meta;

  List<LocationQaCaseResult> get failures =>
      results.where((r) => !r.pass).toList(growable: false);

  String fullText() {
    final b = StringBuffer()
      ..writeln(meta.formatReportPreamble('STYLIST LOCATION QA REPORT (M9)'))
      ..writeln(summary.formatHeader());
    final fails = failures;
    if (fails.isEmpty) {
      b.writeln('\nVšetky prípady prešli.');
      return b.toString();
    }
    b.writeln('');
    for (final f in fails) {
      b.writeln('FAIL:');
      b.writeln('- label: ${f.testCase.label}');
      b.writeln('- prompt: ${f.testCase.prompt.replaceAll('\n', ' ')}');
      b.writeln('- expected: ${f.testCase.expected.label}');
      b.writeln('- actual: ${f.actual.label}');
      b.writeln('- detectedDestination: ${f.detectedDestination ?? '—'}');
      b.writeln('- detectedType: ${f.detectedType.label}');
      b.writeln('- reason: ${f.reason}');
      b.writeln('');
    }
    b.writeln('Top failure reasons:');
    final sorted = summary.failureReasonCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted) {
      b.writeln('- ${entry.key}: ${entry.value}');
    }
    return b.toString().trimRight();
  }
}

/// Deterministický QA runner — testuje iba lokálnu location logiku
/// ([StylistDestinationParser.shouldBlockForBroadRegion] + [inferFromConversation]),
/// bez AI, weather a outfit generation.
abstract final class StylistLocationQaRunner {
  static const _countryPromptSuffix =
      ', potrebujem outfit.\nBudeme sa tam prechádzať po meste.';

  static String _countryPrompt(String placePhrase) =>
      'Zajtra ideme $placePhrase$_countryPromptSuffix';

  static String _cityPrompt(String declinedPlace) =>
      'Zajtra ideme do $declinedPlace, potrebujem outfit.\n'
      'Budeme sa tam prechádzať po meste.';

  static List<LocationQaCase> countryCases() => [
        LocationQaCase(
          label: 'USA',
          prompt: _countryPrompt('do USA'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Amerika',
          prompt: _countryPrompt('do Ameriky'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Európa',
          prompt: _countryPrompt('do Európy'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Nórsko (Nórska)',
          prompt: _countryPrompt('do Nórska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Nórsko (Norska ASCII)',
          prompt: _countryPrompt('do Norska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Švédsko',
          prompt: _countryPrompt('do Švédska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Fínsko',
          prompt: _countryPrompt('do Fínska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Dánsko',
          prompt: _countryPrompt('do Dánska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Island',
          prompt: _countryPrompt('na Island'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Taliansko',
          prompt: _countryPrompt('do Talianska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Španielsko',
          prompt: _countryPrompt('do Španielska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Francúzsko',
          prompt: _countryPrompt('do Francúzska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Nemecko',
          prompt: _countryPrompt('do Nemecka'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Rakúsko',
          prompt: _countryPrompt('do Rakúska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Česko',
          prompt: _countryPrompt('do Česka'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Slovensko',
          prompt: _countryPrompt('po Slovensku'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Poľsko',
          prompt: _countryPrompt('do Poľska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Chorvátsko',
          prompt: _countryPrompt('do Chorvátska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Grécko',
          prompt: _countryPrompt('do Grécka'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Turecko',
          prompt: _countryPrompt('do Turecka'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Egypt',
          prompt: _countryPrompt('do Egypta'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Maroko',
          prompt: _countryPrompt('do Maroka'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Keňa',
          prompt: _countryPrompt('do Kene'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Južná Afrika',
          prompt: _countryPrompt('do Južnej Afriky'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Kanada',
          prompt: _countryPrompt('do Kanady'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Mexiko',
          prompt: _countryPrompt('do Mexika'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Brazília',
          prompt: _countryPrompt('do Brazílie'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Argentína',
          prompt: _countryPrompt('do Argentíny'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Čile',
          prompt: _countryPrompt('do Čile'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Peru',
          prompt: _countryPrompt('do Peru'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Kolumbia',
          prompt: _countryPrompt('do Kolumbie'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Japonsko',
          prompt: _countryPrompt('do Japonska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Čína',
          prompt: _countryPrompt('do Číny'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'India',
          prompt: _countryPrompt('do Indie'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Thajsko',
          prompt: _countryPrompt('do Thajska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Vietnam',
          prompt: _countryPrompt('do Vietnamu'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Indonézia',
          prompt: _countryPrompt('do Indonézie'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Austrália',
          prompt: _countryPrompt('do Austrálie'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Nový Zéland',
          prompt: _countryPrompt('na Nový Zéland'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'SAE',
          prompt: _countryPrompt('do SAE'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Spojené arabské emiráty',
          prompt: _countryPrompt('do Spojených arabských emirátov'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Emiráty',
          prompt: _countryPrompt('do Emirátov'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Izrael',
          prompt: _countryPrompt('do Izraela'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Južná Kórea',
          prompt: _countryPrompt('do Južnej Kórey'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Maldivy',
          prompt: _countryPrompt('na Maldivy'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Filipíny',
          prompt: _countryPrompt('na Filipíny'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Portugalsko',
          prompt: _countryPrompt('do Portugalska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Írsko',
          prompt: _countryPrompt('do Írska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Veľká Británia',
          prompt: _countryPrompt('do Veľkej Británie'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Británia',
          prompt: _countryPrompt('do Británie'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Holandsko',
          prompt: _countryPrompt('do Holandska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Belgicko',
          prompt: _countryPrompt('do Belgicka'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Švajčiarsko',
          prompt: _countryPrompt('do Švajčiarska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Rusko',
          prompt: _countryPrompt('do Ruska'),
          expected: LocationExpected.needsCityClarification,
        ),
        LocationQaCase(
          label: 'Ukrajina',
          prompt: _countryPrompt('do Ukrajiny'),
          expected: LocationExpected.needsCityClarification,
        ),
      ];

  static List<LocationQaCase> cityCases() => [
        LocationQaCase(
          label: 'Washington',
          prompt: _cityPrompt('Washingtonu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'New York',
          prompt: _cityPrompt('New Yorku'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Los Angeles',
          prompt: _cityPrompt('Los Angeles'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Miami',
          prompt: _cityPrompt('Miami'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Toronto',
          prompt: _cityPrompt('Toronta'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Vancouver',
          prompt: _cityPrompt('Vancouveru'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Mexico City',
          prompt: _cityPrompt('Mexico City'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Rio de Janeiro',
          prompt: _cityPrompt('Rio de Janeiro'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'São Paulo',
          prompt: _cityPrompt('São Paule'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Buenos Aires',
          prompt: _cityPrompt('Buenos Aires'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Santiago',
          prompt: _cityPrompt('Santiaga'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Lima',
          prompt: _cityPrompt('Lima'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Bogotá',
          prompt: _cityPrompt('Bogoty'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'London',
          prompt: _cityPrompt('Londýna'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Paris',
          prompt: _cityPrompt('Paríža'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Rím',
          prompt: _cityPrompt('Ríma'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Milan',
          prompt: _cityPrompt('Milána'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Madrid',
          prompt: _cityPrompt('Madridu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Barcelona',
          prompt: _cityPrompt('Barcelony'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Lisabon',
          prompt: _cityPrompt('Lisabonu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Viedeň',
          prompt: _cityPrompt('Viedne'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Praha',
          prompt: _cityPrompt('Prahy'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Bratislava',
          prompt: _cityPrompt('Bratislavy'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Košice',
          prompt: _cityPrompt('Košíc'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Budapešť',
          prompt: _cityPrompt('Budapešti'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Berlín',
          prompt: _cityPrompt('Berlína'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Mníchov',
          prompt: _cityPrompt('Mníchova'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Amsterdam',
          prompt: _cityPrompt('Amsterdamu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Brusel',
          prompt: _cityPrompt('Bruselu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Zürich',
          prompt: _cityPrompt('Zürichu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Oslo',
          prompt: _cityPrompt('Osla'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Stockholm',
          prompt: _cityPrompt('Stockholmu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Kodaň',
          prompt: _cityPrompt('Kodane'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Helsinki',
          prompt: _cityPrompt('Helsínk'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Reykjavik',
          prompt: _cityPrompt('Reykjavíku'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Dublin',
          prompt: _cityPrompt('Dublinu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Atény',
          prompt: _cityPrompt('Atén'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Istanbul',
          prompt: _cityPrompt('Istanbulu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Dubaj',
          prompt: _cityPrompt('Dubaja'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Tel Aviv',
          prompt: _cityPrompt('Tel Avivu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Káhira',
          prompt: _cityPrompt('Káhiry'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Marrakesh',
          prompt: _cityPrompt('Marrakeshu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Cape Town',
          prompt: _cityPrompt('Cape Townu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Nairobi',
          prompt: _cityPrompt('Nairobi'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Tokio',
          prompt: _cityPrompt('Tokia'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Soul',
          prompt: _cityPrompt('Soulu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Peking',
          prompt: _cityPrompt('Pekingu'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Šanghaj',
          prompt: _cityPrompt('Šanghaja'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Bangkok',
          prompt: _cityPrompt('Bangkoku'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Hanoi',
          prompt: _cityPrompt('Hanoja'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Singapur',
          prompt: _cityPrompt('Singapuru'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Sydney',
          prompt: _cityPrompt('Sydney'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Melbourne',
          prompt: _cityPrompt('Melbourne'),
          expected: LocationExpected.canGenerate,
        ),
        LocationQaCase(
          label: 'Auckland',
          prompt: _cityPrompt('Aucklandu'),
          expected: LocationExpected.canGenerate,
        ),
      ];

  static const _outfitSuffix =
      ', potrebujem outfit.\nBudeme sa tam prechádzať po meste.';

  static String _travelPrompt(String core) => '$core$_outfitSuffix';

  static List<LocationQaCase> regionCases() => [
        LocationQaCase(
          label: 'Toskánsko',
          prompt: _travelPrompt('Zajtra ideme do Toskánska'),
          expected: LocationExpected.needsCityClarification,
          category: 'regions',
        ),
        LocationQaCase(
          label: 'Bavorsko',
          prompt: _travelPrompt('Ideme do Bavorska'),
          expected: LocationExpected.needsCityClarification,
          category: 'regions',
        ),
        LocationQaCase(
          label: 'Kalifornia',
          prompt: _travelPrompt('Letíme do Kalifornie'),
          expected: LocationExpected.needsCityClarification,
          category: 'regions',
        ),
        LocationQaCase(
          label: 'Florida',
          prompt: _travelPrompt('Ideme na Floridu'),
          expected: LocationExpected.needsCityClarification,
          category: 'regions',
        ),
        LocationQaCase(
          label: 'Sicília',
          prompt: _travelPrompt('Dovolenka na Sicílii'),
          expected: LocationExpected.needsCityClarification,
          category: 'regions',
        ),
        LocationQaCase(
          label: 'Skandinávia',
          prompt: _travelPrompt('Cestujeme do Škandinávie'),
          expected: LocationExpected.needsCityClarification,
          category: 'regions',
        ),
        LocationQaCase(
          label: 'Provence',
          prompt: _travelPrompt('Ideme do Provence'),
          expected: LocationExpected.needsCityClarification,
          category: 'regions',
        ),
        LocationQaCase(
          label: 'Alpy',
          prompt: _travelPrompt('Zajtra ideme do Álp'),
          expected: LocationExpected.needsCityClarification,
          category: 'regions',
        ),
        LocationQaCase(
          label: 'Balkán',
          prompt: _travelPrompt('Na Balkán'),
          expected: LocationExpected.needsCityClarification,
          category: 'regions',
        ),
        LocationQaCase(
          label: 'Patagónia',
          prompt: _travelPrompt('Letíme do Patagónie'),
          expected: LocationExpected.needsCityClarification,
          category: 'regions',
        ),
      ];

  static List<LocationQaCase> poiWithoutCityCases() => [
        LocationQaCase(
          label: 'ZOO',
          prompt: _travelPrompt('Idem do ZOO'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
        LocationQaCase(
          label: 'Zoo lowercase',
          prompt: _travelPrompt('Ideme do zoo'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
        LocationQaCase(
          label: 'VinWonders',
          prompt: _travelPrompt('Ideme do VinWonders'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
        LocationQaCase(
          label: 'Universal Studios',
          prompt: _travelPrompt('Ideme do Universal Studios'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
        LocationQaCase(
          label: 'Disneyland',
          prompt: _travelPrompt('Zajtra do Disneylandu'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
        LocationQaCase(
          label: 'Tatralandia',
          prompt: _travelPrompt('Ideme do Tatralandie'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
        LocationQaCase(
          label: 'Aquapark',
          prompt: _travelPrompt('Ideme do aquaparku'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
        LocationQaCase(
          label: 'Neznámy hotel',
          prompt: _travelPrompt('Ubytovanie v hoteli Grand Palace'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
        LocationQaCase(
          label: 'Neznámy festival',
          prompt: _travelPrompt('Ideme na festival Sunshine Waves'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
        LocationQaCase(
          label: 'Neznámy park',
          prompt: _travelPrompt('Prechádzka v parku Green Valley'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
        LocationQaCase(
          label: 'Six Flags',
          prompt: _travelPrompt('Ideme do Six Flags'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
        LocationQaCase(
          label: 'Legoland',
          prompt: _travelPrompt('Ideme do Legolandu'),
          expected: LocationExpected.needsCityClarification,
          category: 'poi_without_city',
        ),
      ];

  static List<LocationQaCase> poiWithCityCases() => [
        LocationQaCase(
          label: 'Zoo Praha',
          prompt: _travelPrompt('Ideme do Zoo Praha'),
          expected: LocationExpected.canGenerate,
          category: 'poi_with_city',
        ),
        LocationQaCase(
          label: 'Disneyland Paris',
          prompt: _travelPrompt('Ideme do Disneyland Paris'),
          expected: LocationExpected.canGenerate,
          category: 'poi_with_city',
        ),
        LocationQaCase(
          label: 'Tatralandia LM',
          prompt: _travelPrompt('Ideme do Tatralandia Liptovský Mikuláš'),
          expected: LocationExpected.canGenerate,
          category: 'poi_with_city',
        ),
        LocationQaCase(
          label: 'Zoo Bratislava',
          prompt: _travelPrompt('Ideme do Zoo Bratislava'),
          expected: LocationExpected.canGenerate,
          category: 'poi_with_city',
        ),
        LocationQaCase(
          label: 'Aquapark Poprad',
          prompt: _travelPrompt('Do aquaparku v Poprade'),
          expected: LocationExpected.canGenerate,
          category: 'poi_with_city',
        ),
        LocationQaCase(
          label: 'VinWonders Dubaj',
          prompt: _travelPrompt('Do VinWonders v Dubaji'),
          expected: LocationExpected.canGenerate,
          category: 'poi_with_city',
        ),
        LocationQaCase(
          label: 'Park v Košiciach',
          prompt: _travelPrompt('Prechádzka v parku v Košiciach'),
          expected: LocationExpected.canGenerate,
          category: 'poi_with_city',
        ),
        LocationQaCase(
          label: 'Zoo v Prahe',
          prompt: _travelPrompt('Ideme do zoo v Prahe'),
          expected: LocationExpected.canGenerate,
          category: 'poi_with_city',
        ),
        LocationQaCase(
          label: 'Festival v Brne',
          prompt: _travelPrompt('Ideme na festival v Brne'),
          expected: LocationExpected.canGenerate,
          category: 'poi_with_city',
        ),
        LocationQaCase(
          label: 'Hotel v Dubaji',
          prompt: _travelPrompt('Ubytovanie v hoteli v Dubaji'),
          expected: LocationExpected.canGenerate,
          category: 'poi_with_city',
        ),
      ];

  static List<LocationQaCase> venueWithoutCityCases() => [
        LocationQaCase(
          label: 'Aupark',
          prompt: _travelPrompt('Idem do Auparku'),
          expected: LocationExpected.needsCityClarification,
          category: 'venue_without_city',
        ),
        LocationQaCase(
          label: 'Nákupné centrum',
          prompt: _travelPrompt('Ideme do nákupného centra'),
          expected: LocationExpected.needsCityClarification,
          category: 'venue_without_city',
        ),
        LocationQaCase(
          label: 'Obchodné centrum',
          prompt: _travelPrompt('Nakupovanie v obchodnom centre'),
          expected: LocationExpected.needsCityClarification,
          category: 'venue_without_city',
        ),
        LocationQaCase(
          label: 'Shopping mall',
          prompt: _travelPrompt('Ideme do shopping mall'),
          expected: LocationExpected.needsCityClarification,
          category: 'venue_without_city',
        ),
        LocationQaCase(
          label: 'Outlet centrum',
          prompt: _travelPrompt('Ideme do outlet centra'),
          expected: LocationExpected.needsCityClarification,
          category: 'venue_without_city',
        ),
        LocationQaCase(
          label: 'Nákupák',
          prompt: _travelPrompt('Ideme do nákupáku'),
          expected: LocationExpected.needsCityClarification,
          category: 'venue_without_city',
        ),
        LocationQaCase(
          label: 'Palladium',
          prompt: _travelPrompt('Ideme do Palladia'),
          expected: LocationExpected.needsCityClarification,
          category: 'venue_without_city',
        ),
        LocationQaCase(
          label: 'Avion',
          prompt: _travelPrompt('Nakupovanie v Avione'),
          expected: LocationExpected.needsCityClarification,
          category: 'venue_without_city',
        ),
      ];

  static List<LocationQaCase> venueWithCityCases() => [
        LocationQaCase(
          label: 'Aupark Bratislava',
          prompt: _travelPrompt('Ideme do Auparku v Bratislave'),
          expected: LocationExpected.canGenerate,
          category: 'venue_with_city',
        ),
        LocationQaCase(
          label: 'Nákupné centrum Košice',
          prompt: _travelPrompt('Do nákupného centra v Košiciach'),
          expected: LocationExpected.canGenerate,
          category: 'venue_with_city',
        ),
        LocationQaCase(
          label: 'OC Danubia',
          prompt: _travelPrompt('Nákup v OC Danubia Bratislava'),
          expected: LocationExpected.canGenerate,
          category: 'venue_with_city',
        ),
        LocationQaCase(
          label: 'Mall v Prahe',
          prompt: _travelPrompt('Ideme do mall v Prahe'),
          expected: LocationExpected.canGenerate,
          category: 'venue_with_city',
        ),
        LocationQaCase(
          label: 'Outlet v Paríži',
          prompt: _travelPrompt('Outlet v Paríži'),
          expected: LocationExpected.canGenerate,
          category: 'venue_with_city',
        ),
        LocationQaCase(
          label: 'Nákupák Žilina',
          prompt: _travelPrompt('Do nákupáku v Žiline'),
          expected: LocationExpected.canGenerate,
          category: 'venue_with_city',
        ),
      ];

  static List<LocationQaCase> airportWithoutCityCases() => [
        LocationQaCase(
          label: 'Na letisko',
          prompt: _travelPrompt('Zajtra idem na letisko'),
          expected: LocationExpected.needsCityClarification,
          category: 'airport_without_city',
        ),
        LocationQaCase(
          label: 'Do letiska',
          prompt: _travelPrompt('Odchádzam do letiska'),
          expected: LocationExpected.needsCityClarification,
          category: 'airport_without_city',
        ),
        LocationQaCase(
          label: 'Na airport',
          prompt: _travelPrompt('Idem na airport'),
          expected: LocationExpected.needsCityClarification,
          category: 'airport_without_city',
        ),
        LocationQaCase(
          label: 'K letisku',
          prompt: _travelPrompt('Zajtra k letisku'),
          expected: LocationExpected.needsCityClarification,
          category: 'airport_without_city',
        ),
        LocationQaCase(
          label: 'Letisko bez mena',
          prompt: _travelPrompt('Potrebujem outfit, idem na letisko ráno'),
          expected: LocationExpected.needsCityClarification,
          category: 'airport_without_city',
        ),
        LocationQaCase(
          label: 'Na letisko večer',
          prompt: _travelPrompt('Večer idem na letisko'),
          expected: LocationExpected.needsCityClarification,
          category: 'airport_without_city',
        ),
      ];

  static List<LocationQaCase> airportWithCityCases() => [
        LocationQaCase(
          label: 'Letisko Viedeň',
          prompt: _travelPrompt('Letím na letisko Viedeň'),
          expected: LocationExpected.canGenerate,
          category: 'airport_with_city',
        ),
        LocationQaCase(
          label: 'Letisko v Prahe',
          prompt: _travelPrompt('Idem na letisko v Prahe'),
          expected: LocationExpected.canGenerate,
          category: 'airport_with_city',
        ),
        LocationQaCase(
          label: 'Letisko Bratislava',
          prompt: _travelPrompt('Na letisko Bratislava'),
          expected: LocationExpected.canGenerate,
          category: 'airport_with_city',
        ),
        LocationQaCase(
          label: 'Airport London',
          prompt: _travelPrompt('Do airport London'),
          expected: LocationExpected.canGenerate,
          category: 'airport_with_city',
        ),
        LocationQaCase(
          label: 'Letisko v Dubaji',
          prompt: _travelPrompt('Na letisko v Dubaji'),
          expected: LocationExpected.canGenerate,
          category: 'airport_with_city',
        ),
        LocationQaCase(
          label: 'Letisko Košice',
          prompt: _travelPrompt('Na letisko v Košiciach'),
          expected: LocationExpected.canGenerate,
          category: 'airport_with_city',
        ),
      ];

  static List<LocationQaCase> unknownDestinationCases() => [
        LocationQaCase(
          label: 'Mystery Place',
          prompt: _travelPrompt('Ideme do Mystery Place'),
          expected: LocationExpected.needsCityClarification,
          category: 'unknown_destinations',
        ),
        LocationQaCase(
          label: 'Blue Lagoon',
          prompt: _travelPrompt('Plávanie v Blue Lagoon'),
          expected: LocationExpected.needsCityClarification,
          category: 'unknown_destinations',
        ),
        LocationQaCase(
          label: 'Crystal Dome',
          prompt: _travelPrompt('Koncert v Crystal Dome'),
          expected: LocationExpected.needsCityClarification,
          category: 'unknown_destinations',
        ),
        LocationQaCase(
          label: 'Sunset Bay',
          prompt: _travelPrompt('Dovolenka v Sunset Bay'),
          expected: LocationExpected.needsCityClarification,
          category: 'unknown_destinations',
        ),
        LocationQaCase(
          label: 'Horizon Resort',
          prompt: _travelPrompt('Do Horizon Resort'),
          expected: LocationExpected.needsCityClarification,
          category: 'unknown_destinations',
        ),
        LocationQaCase(
          label: 'Star Arena',
          prompt: _travelPrompt('Ideme do Star Arena'),
          expected: LocationExpected.needsCityClarification,
          category: 'unknown_destinations',
        ),
        LocationQaCase(
          label: 'Ocean World',
          prompt: _travelPrompt('Navštívime Ocean World'),
          expected: LocationExpected.needsCityClarification,
          category: 'unknown_destinations',
        ),
        LocationQaCase(
          label: 'Golden Gate Park',
          prompt: _travelPrompt('Prechádzka v Golden Gate Park'),
          expected: LocationExpected.needsCityClarification,
          category: 'unknown_destinations',
        ),
      ];

  static List<LocationQaCase> extraCityCases() => [
        LocationQaCase(
          label: 'Cape Town',
          prompt: _cityPrompt('Cape Townu'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Nairobi',
          prompt: _cityPrompt('Nairobi'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Marrakesh',
          prompt: _cityPrompt('Marrakeshu'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Káhira',
          prompt: _cityPrompt('Káhiry'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Tel Aviv',
          prompt: _cityPrompt('Tel Avivu'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Dubaj',
          prompt: _cityPrompt('Dubaja'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Istanbul',
          prompt: _cityPrompt('Istanbulu'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Atény',
          prompt: _cityPrompt('Atén'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Reykjavik',
          prompt: _cityPrompt('Reykjavíku'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Oslo',
          prompt: _cityPrompt('Oslo'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Kodaň',
          prompt: _cityPrompt('Kodane'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Stockholm',
          prompt: _cityPrompt('Stockholmu'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Helsinki',
          prompt: _cityPrompt('Helsínk'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Zürich',
          prompt: _cityPrompt('Zürichu'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
        LocationQaCase(
          label: 'Brusel',
          prompt: _cityPrompt('Bruselu'),
          expected: LocationExpected.canGenerate,
          category: 'cities',
        ),
      ];

  static List<LocationQaCase> allCases() => [
        ...countryCases()
            .map((c) => LocationQaCase(
                  label: c.label,
                  prompt: c.prompt,
                  expected: c.expected,
                  category: 'countries',
                )),
        ...cityCases()
            .map((c) => LocationQaCase(
                  label: c.label,
                  prompt: c.prompt,
                  expected: c.expected,
                  category: 'cities',
                )),
        ...regionCases(),
        ...poiWithoutCityCases(),
        ...poiWithCityCases(),
        ...venueWithoutCityCases(),
        ...venueWithCityCases(),
        ...airportWithoutCityCases(),
        ...airportWithCityCases(),
        ...unknownDestinationCases(),
        ...extraCityCases(),
      ];

  /// Rovnaká logika ako early gate v Stylist Chat [_sendMessage] (M9).
  static LocationQaCaseResult evaluateCase(LocationQaCase testCase) {
    final prompt = testCase.prompt;
    final parsed = StylistDestinationParser.parseDestination(prompt);
    final blocked =
        parsed.needsClarification && parsed.hasTravelDestination;
    final weatherCity = parsed.weatherCity;

    final actual = blocked
        ? LocationExpected.needsCityClarification
        : LocationExpected.canGenerate;

    final detectedType =
        LocationDetectedTypeLabel.fromDestinationType(parsed.type);

    final detectedDestination =
        parsed.normalizedName ?? parsed.parentLocation ?? parsed.extractedPhrase;

    final pass = switch (testCase.expected) {
      LocationExpected.needsCityClarification => blocked,
      LocationExpected.canGenerate => !blocked && weatherCity != null,
    };

    final reason = pass
        ? 'ok'
        : _failureReason(
            expected: testCase.expected,
            blocked: blocked,
            parsed: parsed,
            weatherCity: weatherCity,
          );

    return LocationQaCaseResult(
      testCase: testCase,
      actual: actual,
      pass: pass,
      detectedDestination: detectedDestination,
      detectedType: detectedType,
      reason: reason,
    );
  }

  static String _failureReason({
    required LocationExpected expected,
    required bool blocked,
    required ParsedDestination parsed,
    required String? weatherCity,
  }) {
    if (expected == LocationExpected.needsCityClarification) {
      if (!parsed.hasTravelDestination) return 'no_travel_destination_detected';
      if (weatherCity != null) return 'city_false_positive_should_clarify';
      if (!blocked) return 'destination_not_blocked';
      return 'clarification_expected_${parsed.type.label}';
    }
    if (blocked) return 'unexpected_block_${parsed.type.label}';
    if (weatherCity == null) return 'missing_weather_city';
    if (StylistDestinationParser.isBroadRegion(weatherCity)) {
      return 'country_used_as_city';
    }
    return 'unknown_fail_${parsed.type.label}';
  }

  static StylistLocationQaRunResult runAll({bool emitLogs = true}) {
    final startedAt = DateTime.now();
    final qaRunId = StylistQaAppSession.newQaRunId();
    final cases = allCases();

    if (emitLogs && kDebugMode) {
      debugPrint(
        'STYLIST LOCATION QA START { '
        'cases=${cases.length}, '
        'startedAt=${startedAt.toIso8601String()}, '
        'appRunId=${StylistQaAppSession.appRunId}, '
        'qaRunId=$qaRunId }',
      );
    }

    final results = <LocationQaCaseResult>[];
    for (final testCase in cases) {
      results.add(evaluateCase(testCase));
    }

    final finishedAt = DateTime.now();
    final durationMs = finishedAt.difference(startedAt).inMilliseconds;

    final failureReasonCounts = <String, int>{};
    for (final r in results.where((r) => !r.pass)) {
      failureReasonCounts[r.reason] =
          (failureReasonCounts[r.reason] ?? 0) + 1;
    }

    final byCategory = <String, List<LocationQaCaseResult>>{};
    for (var i = 0; i < cases.length; i++) {
      final cat = cases[i].category;
      byCategory.putIfAbsent(cat, () => []).add(results[i]);
    }

    final countryResults = byCategory['countries'] ?? const [];
    final cityResults = [
      ...(byCategory['cities'] ?? const []),
      ...(byCategory['poi_with_city'] ?? const []),
      ...(byCategory['venue_with_city'] ?? const []),
      ...(byCategory['airport_with_city'] ?? const []),
    ];

    final passed = results.where((r) => r.pass).length;
    final failed = results.length - passed;
    final summary = StylistLocationQaSummary(
      total: results.length,
      passed: passed,
      failed: failed,
      countryTotal: countryResults.length,
      countryBlocked: countryResults.where((r) => r.pass).length,
      cityTotal: cityResults.length,
      cityAllowed: cityResults.where((r) => r.pass).length,
      failureReasonCounts: failureReasonCounts,
      categoryCounts: byCategory.map(
        (k, v) => MapEntry(
          k,
          (passed: v.where((r) => r.pass).length, total: v.length),
        ),
      ),
    );
    final meta = StylistQaRunMeta(
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMs: durationMs,
      appRunId: StylistQaAppSession.appRunId,
      qaRunId: qaRunId,
    );

    if (emitLogs && kDebugMode) {
      debugPrint(
        'STYLIST LOCATION QA END { '
        'passed=$passed, '
        'failed=$failed, '
        'durationMs=$durationMs, '
        'qaRunId=$qaRunId }',
      );
    }

    return StylistLocationQaRunResult(
      results: results,
      summary: summary,
      meta: meta,
    );
  }
}
