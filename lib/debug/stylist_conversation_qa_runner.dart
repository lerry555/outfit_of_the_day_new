import 'package:flutter/foundation.dart';

import '../data/conversation_decision.dart';
import '../utils/conversation_reasoner.dart';
import '../utils/stylist_destination_parser.dart';
import 'stylist_qa_runtime.dart';

/// Očakávané rozhodnutie reasonera.
typedef ConversationExpected = ConversationAction;

class ConversationQaCase {
  const ConversationQaCase({
    required this.label,
    required this.prompt,
    required this.expected,
    required this.category,
    this.gpsCity = 'Martin, Slovakia',
  });

  final String label;
  final String prompt;
  final ConversationExpected expected;
  final String category;
  final String? gpsCity;
}

class ConversationQaCaseResult {
  const ConversationQaCaseResult({
    required this.testCase,
    required this.decision,
    required this.pass,
    required this.reason,
  });

  final ConversationQaCase testCase;
  final ConversationDecision decision;
  final bool pass;
  final String reason;
}

class StylistConversationQaSummary {
  const StylistConversationQaSummary({
    required this.total,
    required this.passed,
    required this.failed,
    required this.categoryCounts,
    required this.failureReasonCounts,
  });

  final int total;
  final int passed;
  final int failed;
  final Map<String, ({int passed, int total})> categoryCounts;
  final Map<String, int> failureReasonCounts;

  String formatHeader() {
    final b = StringBuffer()
      ..writeln('Cases: $total')
      ..writeln('Passed: $passed')
      ..writeln('Failed: $failed');
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

class StylistConversationQaRunResult {
  const StylistConversationQaRunResult({
    required this.results,
    required this.summary,
    required this.meta,
  });

  final List<ConversationQaCaseResult> results;
  final StylistConversationQaSummary summary;
  final StylistQaRunMeta meta;

  List<ConversationQaCaseResult> get failures =>
      results.where((r) => !r.pass).toList(growable: false);

  String fullText() {
    final b = StringBuffer()
      ..writeln(meta.formatReportPreamble('STYLIST CONVERSATION QA REPORT (M10)'))
      ..writeln(summary.formatHeader());
    final fails = failures;
    if (fails.isEmpty) {
      b.writeln('\nVšetky scenáre prešli.');
      return b.toString();
    }
    b.writeln('');
    for (final f in fails) {
      b.writeln('FAIL:');
      b.writeln('- label: ${f.testCase.label}');
      b.writeln('- prompt: ${f.testCase.prompt.replaceAll('\n', ' ')}');
      b.writeln('- expected: ${f.testCase.expected.label}');
      b.writeln('- decision: ${f.decision.action.label}');
      b.writeln('- reason: ${f.decision.reason}');
      b.writeln('- missing: ${f.decision.missingInformation.label}');
      b.writeln(
        '- clarification: ${f.decision.clarificationQuestionSk ?? '—'}',
      );
      b.writeln('- qa_reason: ${f.reason}');
      b.writeln('');
    }
    b.writeln('Top failure reasons:');
    final sorted = summary.failureReasonCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
      b.writeln('- ${e.key}: ${e.value}');
    }
    return b.toString().trimRight();
  }
}

abstract final class StylistConversationQaRunner {
  static const _outfit = ', potrebujem outfit.';
  static const _time = ' o 9:00';

  static String _p(String core) => '$core$_outfit';

  static String _pg(String core) {
    if (RegExp(r'(?:o|okolo)\s*\d', caseSensitive: false).hasMatch(core)) {
      return '$core$_outfit';
    }
    return '$core$_time$_outfit';
  }

  static bool _outdoorHasResolvableLocation(String activity) {
    if (RegExp(r'(?:o|okolo)\s*\d', caseSensitive: false).hasMatch(activity)) {
      return true;
    }
    if (StylistDestinationParser.broadRegionInConversation(activity) != null) {
      return false;
    }
    final city = StylistDestinationParser.inferCityCandidate(activity);
    return StylistDestinationParser.isConfidentResolvableCity(city);
  }

  static ConversationQaCase _c(
    String label,
    String prompt,
    ConversationAction expected,
    String category, {
    String? gps,
  }) =>
      ConversationQaCase(
        label: label,
        prompt: prompt,
        expected: expected,
        category: category,
        gpsCity: gps ?? 'Martin, Slovakia',
      );

  static List<ConversationQaCase> allCases() => [
        ...outdoorNeedsLocationCases(),
        ...routineLocalCases(),
        ...destinationCountryCases(),
        ...destinationCityCases(),
        ...poiCases(),
        ...typoCases(),
        ...timeCases(),
        ...concertCases(),
        ...passthroughCases(),
        ...edgeCases(),
        ...continentalCases(),
      ];

  static List<ConversationQaCase> outdoorNeedsLocationCases() {
    const activities = [
      'na túru',
      'na turu',
      'na turistiku',
      'na hory',
      'do hôr',
      'na ferraty',
      'na hubovanie',
      'na ryby',
      'stanovať',
      'na safari',
      'na lyžovačku',
      'na lyzovacku',
      'na rafting',
      'na pláž',
      'na plaz',
      'na kúpanie',
      'na kupanie',
      'na výlet',
      'na vylet',
      'do prírody',
      'do prirody',
      'na trail',
      'do kopcov',
      'na bicykel',
      'na beh',
      'na stanovanie',
      'na kempovanie',
      'na lezenie',
      'na skaly',
      'na vodopády',
      'na kajak',
      'na surf',
      'na šnorchlovanie',
      'Zajtra chceme ísť na túru',
      'Zajtra ideme na turistiku',
      'V sobotu pôjdeme do hôr',
      'Chceme ísť na ferraty',
      'Ideme zbierať huby',
      'Ideme na lyžovačku',
      'Plánujeme stanovať',
      'Ideme na rafting',
      'Ideme na pláž',
      'Ideme sa kúpať v mori',
      'Ideme na výlet do prírody',
      'Ideme na trail',
      'Ideme do Tatier',
      'Ideme do tatier',
      'Na víkend ideme na túru',
      'Na vikend ideme na turu',
      'Chcem outfit na túru zajtra',
      'Potrebujem outfit na hory',
      'Ideme na turistiku v Alpách',
      'Ideme na pešiu túru',
      'Ideme na dlhú túru',
      'Ideme na krátku túru',
      'Ideme na horskú túru',
      'Ideme na zimnú túru',
      'Ideme na letnú túru',
      'Ideme na rodinnú túru',
      'Ideme na piknik v prírode',
      'Ideme na outdoor aktivitu',
      'Ideme na trek',
      'Ideme hiking',
      'Ideme na mushroom picking',
      'Ideme na fishing trip',
      'Ideme na camping',
      'Ideme na beach day',
      'Ideme na ski trip',
      'Ideme na snowboarding',
      'Ideme na ferratu',
      'Ideme na via ferratu',
      'Ideme na horolezectvo',
      'Ideme na skalné mesto',
      'Ideme na národný park',
      'Ideme do narodneho parku',
      'Ideme na okruh okolo jazera',
      'Ideme na prechádzku v lese',
      'Ideme na prechadzku v lese',
      'Ideme na horskú chatu',
      'Ideme na chatu v horách',
      'Ideme na rozhľadňu',
      'Ideme na rozhladnu',
      'Ideme na cyklotúru',
      'Ideme na cykloturu',
      'Ideme na maratón v prírode',
      'Ideme na maraton v prirode',
      'Ideme na orientačný beh',
      'Ideme na orientacny beh',
      'Ideme na biatlon',
      'Ideme na bežeckú trať v lese',
      'Ideme na bezecsku trat v lese',
      'Ideme na opálenie na pláži',
      'Ideme na opalenie na plazi',
      'Ideme na paddleboard',
      'Ideme na windsurfing',
      'Ideme na kitesurfing',
      'Ideme na jazero',
      'Ideme na rieku',
      'Ideme na kanoe',
      'Ideme na splav',
      'Ideme na výstup na vrch',
      'Ideme na vystup na vrch',
      'Ideme na sedlo',
      'Ideme na hrebeň',
      'Ideme na hreben',
      'Ideme na skialp',
      'Ideme na skitour',
      'Ideme na freeride',
      'Ideme na backcountry',
      'Ideme na horsku turistiku',
      'Ideme na horsku turistiku zajtra',
      'Ideme na jednodňovú túru',
      'Ideme na jednodnovu turu',
      'Ideme na viacdňovú túru',
      'Ideme na viacdnovu turu',
      'Ideme na pútnické miesto v horách',
      'Ideme na pútnicke miesto v horach',
      'Ideme na výlet loďou',
      'Ideme na vylet lodiou',
      'Ideme na pozorovanie vtákov',
      'Ideme na pozorovanie vtakov',
      'Ideme na fotenie v prírode',
      'Ideme na fotenie v prirode',
      'Ideme na piknik na lúke',
      'Ideme na piknik na luke',
      'Ideme na lúku',
      'Ideme na luku',
      'Ideme na lúky',
      'Ideme na lúky v horách',
      'Ideme na lúky v horach',
      'Ideme na horskú lúku',
      'Ideme na horsku luku',
      'Ideme na meadow walk',
      'Ideme na forest bath',
      'Ideme na bushcraft',
      'Ideme na survival trip',
      'Ideme na outdoor teambuilding',
      'Ideme na teambuilding v prírode',
      'Ideme na teambuilding v prirode',
      'Ideme na firemný výlet do prírody',
      'Ideme na firemny vylet do prirody',
      'Ideme na školný výlet do prírody',
      'Ideme na skolny vylet do prirody',
      'Ideme na rodinný výlet do prírody',
      'Ideme na rodinny vylet do prirody',
      'Ideme na výlet s deťmi do prírody',
      'Ideme na vylet s detmi do prirody',
      'Ideme na piknik s rodinou v prírode',
      'Ideme na piknik s rodinou v prirode',
      'Ideme na grilovačku v prírode',
      'Ideme na grilovacku v prirode',
      'Ideme na opekačku v lese',
      'Ideme na opejacku v lese',
      'Ideme na stanovú chatu',
      'Ideme na stanovu chatu',
      'Ideme na bivak',
      'Ideme na bivak v horách',
      'Ideme na bivak v horach',
      'Ideme na outdoor festival v prírode',
      'Ideme na outdoor festival v prirode',
      'Ideme na horský festival',
      'Ideme na horsky festival',
      'Ideme na trail running',
      'Ideme na ultra trail',
      'Ideme na skyrunning',
      'Ideme na nordic walking v lese',
      'Ideme na nordic walking v lese',
      'Ideme na snowshoeing',
      'Ideme na bežky v lese',
      'Ideme na bežky v lese',
      'Ideme na bezky v lese',
      'Ideme na bežkovanie v lese',
      'Ideme na bezkovanie v lese',
      'Ideme na bežkovanie',
      'Ideme na bezkovanie',
      'Ideme na zimnú turistiku',
      'Ideme na zimnu turistiku',
      'Ideme na letnú turistiku',
      'Ideme na letnu turistiku',
      'Ideme na jarnú turistiku',
      'Ideme na jarnu turistiku',
      'Ideme na jesennú turistiku',
      'Ideme na jesennu turistiku',
      'Ideme na jesenné hubovanie',
      'Ideme na jesenne hubovanie',
      'Ideme na jarné hubovanie',
      'Ideme na jarne hubovanie',
      'Ideme na zber húb',
      'Ideme na zber hub',
      'Ideme na hriby',
      'Ideme na huby v lese',
      'Ideme na huby v lese',
      'Ideme na rybolov na jazere',
      'Ideme na rybolov na jazere v horách',
      'Ideme na rybolov na jazere v horach',
      'Ideme na ryby na jazere',
      'Ideme na ryby na jazere v horách',
      'Ideme na ryby na jazere v horach',
      'Ideme na plávanie v jazere',
      'Ideme na plávanie v jazere v horách',
      'Ideme na plavanie v jazere',
      'Ideme na plavanie v jazere v horach',
      'Ideme na kúpanie v jazere',
      'Ideme na kupanie v jazere',
      'Ideme na kúpanie v rieke',
      'Ideme na kupanie v rieke',
      'Ideme na kúpanie v mori',
      'Ideme na kupanie v mori',
      'Ideme na kúpanie na jazere',
      'Ideme na kupanie na jazere',
      'Ideme na kúpanie na pláži',
      'Ideme na kupanie na plazi',
      'Ideme na kúpanie na pláži v Chorvátsku',
      'Ideme na kupanie na plazi v Chorvatsku',
      'Ideme na pláž v Chorvátsku',
      'Ideme na plaz v Chorvatsku',
      'Ideme na pláž v Taliansku',
      'Ideme na plaz v Taliansku',
      'Ideme na pláž v Španielsku',
      'Ideme na plaz v Spanielsku',
      'Ideme na pláž v Grécku',
      'Ideme na plaz v Grecku',
      'Ideme na pláž v Egypte',
      'Ideme na plaz v Egypte',
      'Ideme na pláž v Thajsku',
      'Ideme na plaz v Thajsku',
      'Ideme na pláž v Bali',
      'Ideme na plaz v Bali',
      'Ideme na pláž na Maldivách',
      'Ideme na plaz na Maldivach',
      'Ideme na pláž na Seychelách',
      'Ideme na plaz na Seychelach',
      'Ideme na pláž na Mauríciu',
      'Ideme na plaz na Mauriciu',
      'Ideme na pláž na Zanzibare',
      'Ideme na plaz na Zanzibare',
      'Ideme na pláž na Havaji',
      'Ideme na plaz na Havaji',
      'Ideme na pláž v Kalifornii',
      'Ideme na plaz v Kalifornii',
      'Ideme na pláž na Floride',
      'Ideme na plaz na Floride',
      'Ideme na pláž v Sydney',
      'Ideme na plaz v Sydney',
      'Ideme na pláž v Rio',
      'Ideme na plaz v Rio',
      'Ideme na pláž v Cape Town',
      'Ideme na plaz v Cape Town',
      'Ideme na pláž v Dubaji',
      'Ideme na plaz v Dubaji',
      'Ideme na pláž v Dubaji o 10:00',
      'Ideme na plaz v Dubaji o 10:00',
    ];
    return [
      for (var i = 0; i < activities.length; i++)
        () {
          final activity = activities[i];
          final hasLoc = _outdoorHasResolvableLocation(activity);
          return _c(
            'outdoor_${i + 1}',
            hasLoc
                ? _pg('Zajtra ideme $activity')
                : _p('Zajtra ideme $activity'),
            hasLoc ? ConversationAction.generate : ConversationAction.clarify,
            'outdoor_needs_location',
          );
        }(),
    ];
  }

  static List<ConversationQaCase> routineLocalCases() {
    const routines = [
      'do práce',
      'do prace',
      'do roboty',
      'do kancelárie',
      'do kancelarie',
      'do školy',
      'do skoly',
      'na obed',
      'na večeru',
      'na veceru',
      'do reštaurácie',
      'do restauracie',
      'na nákupy',
      'na nakupy',
      'do obchodu',
      'na stretnutie',
      'do fitka',
      'do posilňovne',
      'do posilovne',
      'do gymu',
      'k lekárovi',
      'k lekarovi',
      'na úrad',
      'na urad',
      'do práce v centre',
      'do prace v centre',
      'na obed v centre',
      'do kina',
      'do divadla',
      'na kávu',
      'na kavu',
      'na drink',
      'na rande v meste',
      'do práce v Martine',
      'do prace v Martine',
      'na obed v Martine',
      'do školy v Martine',
      'do skoly v Martine',
      'do fitka v Martine',
      'do posilovne v Martine',
      'na nákupy v Martine',
      'na nakupy v Martine',
      'do obchodu v Martine',
      'na stretnutie v Martine',
      'k lekárovi v Martine',
      'k lekarovi v Martine',
      'na úrad v Martine',
      'na urad v Martine',
      'do kancelárie v Martine',
      'do kancelarie v Martine',
      'do roboty v Martine',
      'na večeru v Martine',
      'na veceru v Martine',
      'do reštaurácie v Martine',
      'do restauracie v Martine',
      'na kávu v Martine',
      'na kavu v Martine',
      'na drink v Martine',
      'na rande v Martine',
      'do práce ráno',
      'do prace rano',
      'na obed dnes',
      'do školy dnes',
      'do skoly dnes',
      'do fitka dnes večer',
      'do posilovne dnes vecer',
      'na nákupy dnes',
      'na nakupy dnes',
      'do obchodu dnes',
      'na stretnutie dnes',
      'k lekárovi dnes',
      'k lekarovi dnes',
      'na úrad dnes',
      'na urad dnes',
      'do kancelárie dnes',
      'do kancelarie dnes',
      'do roboty dnes',
      'na večeru dnes',
      'na veceru dnes',
      'do reštaurácie dnes',
      'do restauracie dnes',
      'na kávu dnes',
      'na kavu dnes',
      'na drink dnes',
      'na rande dnes',
      'do práce zajtra',
      'do prace zajtra',
      'na obed zajtra',
      'do školy zajtra',
      'do skoly zajtra',
      'do fitka zajtra',
      'do posilovne zajtra',
      'na nákupy zajtra',
      'na nakupy zajtra',
      'do obchodu zajtra',
      'na stretnutie zajtra',
      'k lekárovi zajtra',
      'k lekarovi zajtra',
      'na úrad zajtra',
      'na urad zajtra',
      'do kancelárie zajtra',
      'do kancelarie zajtra',
      'do roboty zajtra',
      'na večeru zajtra',
      'na veceru zajtra',
      'do reštaurácie zajtra',
      'do restauracie zajtra',
      'na kávu zajtra',
      'na kavu zajtra',
      'na drink zajtra',
      'na rande zajtra',
      'do práce v Bratislave',
      'do prace v Bratislave',
      'na obed v Bratislave',
      'do školy v Bratislave',
      'do skoly v Bratislave',
      'do fitka v Bratislave',
      'do posilovne v Bratislave',
      'na nákupy v Bratislave',
      'na nakupy v Bratislave',
      'do obchodu v Bratislave',
      'na stretnutie v Bratislave',
      'k lekárovi v Bratislave',
      'k lekarovi v Bratislave',
      'na úrad v Bratislave',
      'na urad v Bratislave',
      'do kancelárie v Bratislave',
      'do kancelarie v Bratislave',
      'do roboty v Bratislave',
      'na večeru v Bratislave',
      'na veceru v Bratislave',
      'do reštaurácie v Bratislave',
      'do restauracie v Bratislave',
      'na kávu v Bratislave',
      'na kavu v Bratislave',
      'na drink v Bratislave',
      'na rande v Bratislave',
      'do práce v Košiciach',
      'do prace v Kosiciach',
      'na obed v Košiciach',
      'do školy v Košiciach',
      'do skoly v Kosiciach',
      'do fitka v Košiciach',
      'do posilovne v Kosiciach',
      'na nákupy v Košiciach',
      'na nakupy v Kosiciach',
      'do obchodu v Košiciach',
      'na stretnutie v Košiciach',
      'k lekárovi v Košiciach',
      'k lekarovi v Kosiciach',
      'na úrad v Košiciach',
      'na urad v Kosiciach',
      'do kancelárie v Košiciach',
      'do kancelarie v Kosiciach',
      'do roboty v Košiciach',
      'na večeru v Košiciach',
      'na veceru v Kosiciach',
      'do reštaurácie v Košiciach',
      'do restauracie v Kosiciach',
      'na kávu v Košiciach',
      'na kavu v Kosiciach',
      'na drink v Košiciach',
      'na rande v Košiciach',
      'do práce v Žiline',
      'do prace v Ziline',
      'na obed v Žiline',
      'do školy v Žiline',
      'do skoly v Ziline',
      'do fitka v Žiline',
      'do posilovne v Ziline',
      'na nákupy v Žiline',
      'na nakupy v Ziline',
      'do obchodu v Žiline',
      'na stretnutie v Žiline',
      'k lekárovi v Žiline',
      'k lekarovi v Ziline',
      'na úrad v Žiline',
      'na urad v Ziline',
      'do kancelárie v Žiline',
      'do kancelarie v Ziline',
      'do roboty v Žiline',
      'na večeru v Žiline',
      'na veceru v Ziline',
      'do reštaurácie v Žiline',
      'do restauracie v Ziline',
      'na kávu v Žiline',
      'na kavu v Ziline',
      'na drink v Žiline',
      'na rande v Žiline',
    ];
    return [
      for (var i = 0; i < routines.length; i++)
        _c(
          'routine_${i + 1}',
          _pg('Idem ${routines[i]}'),
          ConversationAction.generate,
          'routine_local',
        ),
    ];
  }

  static List<ConversationQaCase> destinationCountryCases() {
    const countries = [
      'do USA',
      'do Nórska',
      'do Talianska',
      'do Španielska',
      'do Francúzska',
      'do Nemecka',
      'do Rakúska',
      'do Česka',
      'do Poľska',
      'do Chorvátska',
      'do Grécka',
      'do Turecka',
      'do Egypta',
      'do Kanady',
      'do Mexika',
      'do Brazílie',
      'do Japonska',
      'do Číny',
      'do Indie',
      'do Thajska',
      'do Vietnamu',
      'do Austrálie',
      'do Nového Zélandu',
      'do Južnej Afriky',
      'do Kene',
      'do Maroka',
      'do SAE',
      'do Izraela',
      'do Južnej Kórey',
      'na Maldivy',
      'na Filipíny',
      'do Portugalska',
      'do Írska',
      'do Veľkej Británie',
      'do Holandska',
      'do Belgicka',
      'do Švajčiarska',
      'do Ruska',
      'do Ukrajiny',
      'do Švédska',
      'do Fínska',
    ];
    return [
      for (var i = 0; i < countries.length; i++)
        _c(
          'country_${i + 1}',
          _pg('Zajtra ideme ${countries[i]}'),
          ConversationAction.clarify,
          'destination_country',
        ),
    ];
  }

  static List<ConversationQaCase> destinationCityCases() {
    const cities = [
      ('do Osla', 'Oslo'),
      ('do Prahy', 'Praha'),
      ('do Viedne', 'Viedeň'),
      ('do Budapešti', 'Budapešť'),
      ('do Londýna', 'London'),
      ('do Paríža', 'Paríž'),
      ('do Ríma', 'Rím'),
      ('do Madridu', 'Madrid'),
      ('do Barcelony', 'Barcelona'),
      ('do Berlína', 'Berlín'),
      ('do Mníchova', 'Mníchov'),
      ('do Zürichu', 'Zürich'),
      ('do Stockholmu', 'Stockholm'),
      ('do Kodane', 'Kodaň'),
      ('do Helsínk', 'Helsinki'),
      ('do Reykjavíku', 'Reykjavik'),
      ('do Dubaja', 'Dubaj'),
      ('do Istanbulu', 'Istanbul'),
      ('do Atén', 'Atény'),
      ('do Lisabonu', 'Lisabon'),
      ('do Washingtonu', 'Washington'),
      ('do New Yorku', 'New York'),
      ('do Los Angeles', 'Los Angeles'),
      ('do Miami', 'Miami'),
      ('do Toronta', 'Toronto'),
      ('do Vancouveru', 'Vancouver'),
      ('do Mexico City', 'Mexico City'),
      ('do Rio de Janeiro', 'Rio de Janeiro'),
      ('do Buenos Aires', 'Buenos Aires'),
      ('do Santiaga', 'Santiago'),
      ('do Limy', 'Lima'),
      ('do Bogoty', 'Bogotá'),
      ('do Tokia', 'Tokio'),
      ('do Soulu', 'Soul'),
      ('do Pekingu', 'Peking'),
      ('do Šanghaja', 'Šanghaj'),
      ('do Bangkoku', 'Bangkok'),
      ('do Hanoja', 'Hanoi'),
      ('do Singapuru', 'Singapur'),
      ('do Sydney', 'Sydney'),
      ('do Melbourne', 'Melbourne'),
      ('do Aucklandu', 'Auckland'),
      ('do Cape Townu', 'Cape Town'),
      ('do Nairobi', 'Nairobi'),
      ('do Marrakeshu', 'Marrakesh'),
      ('do Káhiry', 'Káhira'),
      ('do Tel Avivu', 'Tel Aviv'),
      ('do Bratislavy', 'Bratislava'),
      ('do Košíc', 'Košice'),
      ('do Žiliny', 'Žilina'),
      ('do Popradu', 'Poprad'),
      ('do Banskej Bystrice', 'Banská Bystrica'),
      ('do Trnavy', 'Trnava'),
      ('do Nitry', 'Nitra'),
      ('do Trenčína', 'Trenčín'),
      ('do Prešova', 'Prešov'),
      ('do Martina', 'Martin'),
    ];
    return [
      for (var i = 0; i < cities.length; i++)
        _c(
          'city_${cities[i].$2}',
          _pg('Zajtra ideme ${cities[i].$1}'),
          ConversationAction.generate,
          'destination_city',
        ),
    ];
  }

  static List<ConversationQaCase> poiCases() => [
        _c('Zoo bez mesta', _p('Idem do Zoo'), ConversationAction.clarify, 'poi'),
        _c('Zoo Bojnice', _pg('Idem do Zoo Bojnice'), ConversationAction.generate, 'poi'),
        _c('Zoo Praha', _pg('Idem do Zoo Praha'), ConversationAction.generate, 'poi'),
        _c('Aquapark bez mesta', _p('Idem do aquaparku'), ConversationAction.clarify, 'poi'),
        _c('Aquapark Poprad', _pg('Do aquaparku v Poprade'), ConversationAction.generate, 'poi'),
        _c('Disneyland bez mesta', _p('Idem do Disneylandu'), ConversationAction.clarify, 'poi'),
        _c('Disneyland Paris', _pg('Idem do Disneyland Paris'), ConversationAction.generate, 'poi'),
        _c('Tatralandia bez mesta', _p('Idem do Tatralandie'), ConversationAction.clarify, 'poi'),
        _c('Tatralandia LM', _pg('Idem do Tatralandia Liptovský Mikuláš'), ConversationAction.generate, 'poi'),
        _c('Aupark bez mesta', _p('Idem do Auparku'), ConversationAction.clarify, 'poi'),
        _c('Aupark BA', _pg('Idem do Auparku v Bratislave'), ConversationAction.generate, 'poi'),
        _c('VinWonders', _p('Idem do VinWonders'), ConversationAction.clarify, 'poi'),
        _c('Legoland', _p('Idem do Legolandu'), ConversationAction.clarify, 'poi'),
        _c('Universal Studios', _p('Idem do Universal Studios'), ConversationAction.clarify, 'poi'),
        _c('Zoo Bratislava', _pg('Idem do Zoo Bratislava'), ConversationAction.generate, 'poi'),
        _c('Zoo v Prahe', _pg('Idem do zoo v Prahe'), ConversationAction.generate, 'poi'),
        _c('Zábavný park', _p('Idem do zábavného parku'), ConversationAction.clarify, 'poi'),
        _c('Theme park', _p('Idem do theme parku'), ConversationAction.clarify, 'poi'),
        _c('Safari park bez mesta', _p('Idem do safari parku'), ConversationAction.clarify, 'poi'),
        _c('Safari park v Keni', _pg('Idem na safari v Nairobi'), ConversationAction.generate, 'poi'),
      ];

  static List<ConversationQaCase> typoCases() => [
        _c('turu typo', _p('Zajtra ideme na turu'), ConversationAction.clarify, 'typos'),
        _c('túru', _p('Idem na túru'), ConversationAction.clarify, 'typos'),
        _c('lyzovacka', _p('Idem na lyzovacku'), ConversationAction.clarify, 'typos'),
        _c('lyžovačka', _p('Idem na lyžovačku'), ConversationAction.clarify, 'typos'),
        _c('hubi', _p('Idem na hubi'), ConversationAction.clarify, 'typos'),
        _c('huby', _p('Idem na huby'), ConversationAction.clarify, 'typos'),
        _c('ferraty typo', _p('Idem na ferraty'), ConversationAction.clarify, 'typos'),
        _c('ferratu', _p('Idem na ferratu'), ConversationAction.clarify, 'typos'),
        _c('turistiku ascii', _p('Idem na turistiku'), ConversationAction.clarify, 'typos'),
        _c('prace ascii', _pg('Idem do prace'), ConversationAction.generate, 'typos'),
        _c('skoly ascii', _pg('Idem do skoly'), ConversationAction.generate, 'typos'),
        _c('restauracie', _pg('Idem do restauracie'), ConversationAction.generate, 'typos'),
        _c('posilovne', _pg('Idem do posilovne'), ConversationAction.generate, 'typos'),
        _c('nakupy', _pg('Idem na nakupy'), ConversationAction.generate, 'typos'),
        _c('kavu', _pg('Idem na kavu'), ConversationAction.generate, 'typos'),
        _c('veceru', _pg('Idem na veceru'), ConversationAction.generate, 'typos'),
        _c('zoo case', _p('Idem do zoo'), ConversationAction.clarify, 'typos'),
        _c('ZOO caps', _p('Idem do ZOO'), ConversationAction.clarify, 'typos'),
        _c('vylet ascii', _p('Idem na vylet'), ConversationAction.clarify, 'typos'),
        _c('priroda ascii', _p('Idem do prirody'), ConversationAction.clarify, 'typos'),
        _c('plaz ascii', _p('Idem na plaz'), ConversationAction.clarify, 'typos'),
        _c('kupanie ascii', _p('Idem na kupanie'), ConversationAction.clarify, 'typos'),
        _c('bezky', _p('Idem na bezky'), ConversationAction.clarify, 'typos'),
        _c('bezkovanie', _p('Idem na bezkovanie'), ConversationAction.clarify, 'typos'),
        _c('kancelarie', _pg('Idem do kancelarie'), ConversationAction.generate, 'typos'),
        _c('lekar', _pg('Idem k lekarovi'), ConversationAction.generate, 'typos'),
        _c('urad', _pg('Idem na urad'), ConversationAction.generate, 'typos'),
        _c('robot', _pg('Idem do roboty'), ConversationAction.generate, 'typos'),
        _c('fitko', _pg('Idem do fitka'), ConversationAction.generate, 'typos'),
        _c('gym', _pg('Idem do gymu'), ConversationAction.generate, 'typos'),
        _c('obed', _pg('Idem na obed'), ConversationAction.generate, 'typos'),
        _c('kino', _pg('Idem do kina'), ConversationAction.generate, 'typos'),
        _c('divadlo', _pg('Idem do divadla'), ConversationAction.generate, 'typos'),
        _c('koncert typo', _pg('Idem na koncert'), ConversationAction.generate, 'typos'),
        _c('Oslo typo', _pg('Idem do Osla'), ConversationAction.generate, 'typos'),
        _c('Prahy', _pg('Idem do Prahy'), ConversationAction.generate, 'typos'),
        _c('Viedne', _pg('Idem do Viedne'), ConversationAction.generate, 'typos'),
      ];

  static List<ConversationQaCase> timeCases() => [
        for (final p in [
          'Idem na koncert',
          'Idem na festival',
          'Idem na svadbu',
          'Idem na ples',
          'Idem na oslavu',
          'Idem na party',
          'Idem na gala',
          'Idem na interview',
          'Idem na meeting',
          'Idem na prezentáciu',
          'Idem na prezentaciu',
          'Idem na konferenciu',
          'Idem na workshop',
          'Idem na školenie',
          'Idem na skolenie',
          'Idem na teambuilding',
          'Idem na firemnú akciu',
          'Idem na firemnu akciu',
          'Idem na rodinnú oslavu',
          'Idem na rodinnu oslavu',
          'Idem na narodeniny',
          'Idem na promóciu',
          'Idem na promociu',
          'Idem na stužkovú',
          'Idem na stuzkovu',
        ])
          _c(
            'time_${p.hashCode.abs()}',
            _p(p),
            ConversationAction.clarify,
            'time_missing',
          ),
      ];

  static List<ConversationQaCase> concertCases() => [
        _c('koncert GPS', _pg('Idem na koncert'), ConversationAction.generate, 'concert'),
        _c('koncert vonku', _p('Idem na koncert vonku'), ConversationAction.clarify, 'concert'),
        _c('koncert amfik', _p('Idem na koncert na amfiteátri'), ConversationAction.clarify, 'concert'),
        _c('koncert hala', _pg('Idem na koncert v hale'), ConversationAction.generate, 'concert'),
        _c('koncert Bratislava', _pg('Idem na koncert v Bratislave'), ConversationAction.generate, 'concert'),
        _c('koncert Praha', _pg('Idem na koncert v Prahe'), ConversationAction.generate, 'concert'),
        _c('festival GPS', _pg('Idem na festival'), ConversationAction.generate, 'concert'),
        _c('festival vonku', _p('Idem na festival vonku'), ConversationAction.clarify, 'concert'),
        _c('festival amfik', _p('Idem na festival na amfiteátri'), ConversationAction.clarify, 'concert'),
        _c('festival hala', _pg('Idem na festival v hale'), ConversationAction.generate, 'concert'),
        _c('festival Bratislava', _pg('Idem na festival v Bratislave'), ConversationAction.generate, 'concert'),
        _c('festival Praha', _pg('Idem na festival v Prahe'), ConversationAction.generate, 'concert'),
        _c('divadlo GPS', _pg('Idem do divadla'), ConversationAction.generate, 'concert'),
        _c('kino GPS', _pg('Idem do kina'), ConversationAction.generate, 'concert'),
        _c('opera GPS', _pg('Idem na operu'), ConversationAction.generate, 'concert'),
        _c('balet GPS', _pg('Idem na balet'), ConversationAction.generate, 'concert'),
        _c('galéria GPS', _pg('Idem do galérie'), ConversationAction.generate, 'concert'),
        _c('múzeum GPS', _pg('Idem do múzea'), ConversationAction.generate, 'concert'),
        _c('klub GPS', _pg('Idem do klubu'), ConversationAction.generate, 'concert'),
        _c('koncert performer', _p('Idem na koncert, hrá Rytmus'), ConversationAction.clarify, 'concert'),
      ];

  static List<ConversationQaCase> passthroughCases() => [
        _c('ahoj', 'Ahoj', ConversationAction.passthrough, 'passthrough'),
        _c('dakujem', 'Ďakujem', ConversationAction.passthrough, 'passthrough'),
        _c('ako sa mas', 'Ako sa máš?', ConversationAction.passthrough, 'passthrough'),
        _c('co je nove', 'Čo je nové?', ConversationAction.passthrough, 'passthrough'),
        _c('pomoc', 'Potrebujem pomoc', ConversationAction.passthrough, 'passthrough'),
        _c('info', 'Ako to funguje?', ConversationAction.passthrough, 'passthrough'),
        _c('empty', '   ', ConversationAction.passthrough, 'passthrough'),
        _c('emoji', '👋', ConversationAction.passthrough, 'passthrough'),
        _c('weather q', 'Aké je počasie?', ConversationAction.passthrough, 'passthrough'),
        _c('wardrobe q', 'Koľko mám kusov v šatníku?', ConversationAction.passthrough, 'passthrough'),
        _c('fashion tip', 'Čo je teraz v móde?', ConversationAction.passthrough, 'passthrough'),
        _c('color advice', 'Sedí mi modrá?', ConversationAction.passthrough, 'passthrough'),
        _c('thanks outfit', 'Ďakujem za outfit', ConversationAction.passthrough, 'passthrough'),
        _c('nice', 'Super, páči sa mi to', ConversationAction.passthrough, 'passthrough'),
        _c('change topic', 'Zmenme tému', ConversationAction.passthrough, 'passthrough'),
        _c('hello en', 'Hello', ConversationAction.passthrough, 'passthrough'),
      ];

  static List<ConversationQaCase> edgeCases() => [
        _c(
          'tura flagship',
          _p('Zajtra chceme ísť na túru'),
          ConversationAction.clarify,
          'edge',
        ),
        _c(
          'outfit bez aktivity',
          _pg('Potrebujem outfit na zajtra'),
          ConversationAction.generate,
          'edge',
        ),
        _c(
          'rande GPS',
          _pg('Mám rande večer'),
          ConversationAction.generate,
          'edge',
        ),
        _c(
          'USA city',
          _pg('Idem do USA do New Yorku'),
          ConversationAction.generate,
          'edge',
        ),
        _c(
          'Taliansko Rím',
          _pg('Idem do Talianska do Ríma'),
          ConversationAction.generate,
          'edge',
        ),
        _c(
          'letisko vague',
          _p('Idem na letisko'),
          ConversationAction.clarify,
          'edge',
        ),
        _c(
          'letisko Praha',
          _pg('Idem na letisko v Prahe'),
          ConversationAction.generate,
          'edge',
        ),
        _c(
          'region Toskansko',
          _p('Idem do Toskánska'),
          ConversationAction.clarify,
          'edge',
        ),
        _c(
          'outfit local dnes',
          _pg('Čo si mám obliecť dnes?'),
          ConversationAction.generate,
          'edge',
        ),
        _c(
          'outfit local teraz',
          _pg('Čo na seba teraz?'),
          ConversationAction.generate,
          'edge',
        ),
        _c(
          'hory s mestom',
          _pg('Idem na túru vo Vysokých Tatrách'),
          ConversationAction.generate,
          'edge',
        ),
        _c(
          'hory bez mesta',
          _p('Idem na túru v horách'),
          ConversationAction.clarify,
          'edge',
        ),
        _c(
          'pláž Chorvátsko bez mesta',
          _p('Idem na pláž v Chorvátsku'),
          ConversationAction.clarify,
          'edge',
        ),
        _c(
          'pláž Split',
          _pg('Idem na pláž v Splite'),
          ConversationAction.generate,
          'edge',
        ),
        _c(
          'safari Kenya',
          _pg('Idem na safari v Nairobi'),
          ConversationAction.generate,
          'edge',
        ),
        _c(
          'safari vague',
          _p('Idem na safari'),
          ConversationAction.clarify,
          'edge',
        ),
        _c(
          'cesta bez cieľa',
          _p('Idem na cestu'),
          ConversationAction.clarify,
          'edge',
        ),
        _c(
          'dovolenka bez miesta',
          _p('Idem na dovolenku'),
          ConversationAction.clarify,
          'edge',
        ),
        _c(
          'dovolenka Bali',
          _pg('Idem na dovolenku na Bali'),
          ConversationAction.generate,
          'edge',
        ),
        _c(
          'služobka',
          _p('Idem na služobnú cestu'),
          ConversationAction.clarify,
          'edge',
        ),
        _c(
          'služobka Berlin',
          _pg('Idem na služobnú cestu do Berlína'),
          ConversationAction.generate,
          'edge',
        ),
      ];

  static List<ConversationQaCase> continentalCases() {
    const rows = <(String, String, ConversationAction)>[
      ('Africa safari vague', 'Idem na safari', ConversationAction.clarify),
      ('Africa safari Nairobi', 'Idem na safari v Nairobi o 8:00', ConversationAction.generate),
      ('Africa Cape Town', 'Idem do Cape Townu o 9:00', ConversationAction.generate),
      ('Asia Tokyo', 'Idem do Tokia o 9:00', ConversationAction.generate),
      ('Asia Bangkok beach', 'Idem na pláž v Bangkoku o 10:00', ConversationAction.generate),
      ('Asia Bali trip', 'Idem na dovolenku na Bali o 9:00', ConversationAction.generate),
      ('Asia Singapore work', 'Idem do práce v Singapure o 8:00', ConversationAction.generate),
      ('Asia Hanoi tour', 'Idem na túru v Hanoji', ConversationAction.clarify),
      ('Asia Seoul', 'Idem do Soulu o 9:00', ConversationAction.generate),
      ('Asia Mumbai', 'Idem do Mumbai o 9:00', ConversationAction.generate),
      ('Europe Oslo', 'Idem do Osla o 9:00', ConversationAction.generate),
      ('Europe Alps ski', 'Idem na lyžovačku v Alpách', ConversationAction.clarify),
      ('Europe Alps Chamonix', 'Idem na lyžovačku v Chamonix o 9:00', ConversationAction.generate),
      ('Europe Paris', 'Idem do Paríža o 9:00', ConversationAction.generate),
      ('Europe London', 'Idem do Londýna o 9:00', ConversationAction.generate),
      ('Europe Rome', 'Idem do Ríma o 9:00', ConversationAction.generate),
      ('Europe Berlin', 'Idem do Berlína o 9:00', ConversationAction.generate),
      ('Europe Vienna', 'Idem do Viedne o 9:00', ConversationAction.generate),
      ('Europe Prague', 'Idem do Prahy o 9:00', ConversationAction.generate),
      ('Europe Budapest', 'Idem do Budapešti o 9:00', ConversationAction.generate),
      ('NA NYC', 'Idem do New Yorku o 9:00', ConversationAction.generate),
      ('NA LA', 'Idem do Los Angeles o 9:00', ConversationAction.generate),
      ('NA Miami beach', 'Idem na pláž v Miami o 10:00', ConversationAction.generate),
      ('NA Toronto', 'Idem do Toronta o 9:00', ConversationAction.generate),
      ('NA Vancouver hike', 'Idem na túru v Vancouveri o 9:00', ConversationAction.generate),
      ('SA Rio', 'Idem do Rio de Janeiro o 9:00', ConversationAction.generate),
      ('SA Buenos Aires', 'Idem do Buenos Aires o 9:00', ConversationAction.generate),
      ('SA Santiago', 'Idem do Santiaga o 9:00', ConversationAction.generate),
      ('SA Lima', 'Idem do Limy o 9:00', ConversationAction.generate),
      ('SA Bogota', 'Idem do Bogoty o 9:00', ConversationAction.generate),
      ('Oceania Sydney', 'Idem do Sydney o 9:00', ConversationAction.generate),
      ('Oceania Melbourne', 'Idem do Melbourne o 9:00', ConversationAction.generate),
      ('Oceania Auckland', 'Idem do Aucklandu o 9:00', ConversationAction.generate),
      ('Oceania NZ hike', 'Idem na túru na Novom Zélande', ConversationAction.clarify),
      ('Antarctica trip', 'Idem na expedíciu na Antarktídu', ConversationAction.clarify),
      ('Arctic trip', 'Idem na expedíciu na Arktídu', ConversationAction.clarify),
      ('Middle East Dubai', 'Idem do Dubaja o 9:00', ConversationAction.generate),
      ('Middle East Tel Aviv', 'Idem do Tel Avivu o 9:00', ConversationAction.generate),
      ('Middle East Cairo', 'Idem do Káhiry o 9:00', ConversationAction.generate),
      ('Caribbean beach', 'Idem na pláž na Karibik', ConversationAction.clarify),
      ('Caribbean Jamaica', 'Idem na pláž na Jamajke o 10:00', ConversationAction.generate),
    ];
    return [
      for (final row in rows)
        _c(row.$1, _pg(row.$2), row.$3, 'continental'),
    ];
  }

  static ConversationQaCaseResult evaluateCase(ConversationQaCase testCase) {
    final decision = ConversationReasoner.evaluate(
      conversation: testCase.prompt,
      latestMessage: testCase.prompt,
      gpsCityLabel: testCase.gpsCity,
    );
    final pass = decision.action == testCase.expected;
    final reason = pass
        ? 'ok'
        : 'expected_${testCase.expected.label}_got_${decision.action.label}';
    return ConversationQaCaseResult(
      testCase: testCase,
      decision: decision,
      pass: pass,
      reason: reason,
    );
  }

  static StylistConversationQaRunResult runAll({bool emitLogs = true}) {
    final startedAt = DateTime.now();
    final qaRunId = StylistQaAppSession.newQaRunId();
    final cases = allCases();

    if (emitLogs && kDebugMode) {
      debugPrint(
        'STYLIST CONVERSATION QA START { '
        'cases=${cases.length}, '
        'startedAt=${startedAt.toIso8601String()}, '
        'appRunId=${StylistQaAppSession.appRunId}, '
        'qaRunId=$qaRunId }',
      );
      _logSampleSelfCheck();
    }

    final results = <ConversationQaCaseResult>[];
    for (final testCase in cases) {
      results.add(evaluateCase(testCase));
    }

    final finishedAt = DateTime.now();
    final durationMs = finishedAt.difference(startedAt).inMilliseconds;

    final byCategory = <String, List<ConversationQaCaseResult>>{};
    for (var i = 0; i < cases.length; i++) {
      byCategory.putIfAbsent(cases[i].category, () => []).add(results[i]);
    }
    final failureReasonCounts = <String, int>{};
    for (final r in results.where((r) => !r.pass)) {
      failureReasonCounts[r.reason] = (failureReasonCounts[r.reason] ?? 0) + 1;
    }
    final passed = results.where((r) => r.pass).length;
    final failed = results.length - passed;
    final summary = StylistConversationQaSummary(
      total: results.length,
      passed: passed,
      failed: failed,
      categoryCounts: byCategory.map(
        (k, v) => MapEntry(
          k,
          (passed: v.where((r) => r.pass).length, total: v.length),
        ),
      ),
      failureReasonCounts: failureReasonCounts,
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
        'STYLIST CONVERSATION QA END { '
        'passed=$passed, '
        'failed=$failed, '
        'durationMs=$durationMs, '
        'qaRunId=$qaRunId }',
      );
    }

    return StylistConversationQaRunResult(
      results: results,
      summary: summary,
      meta: meta,
    );
  }

  /// Debug self-check — overí flagship scenár túry (rovnaký reasoner ako chat).
  static void _logSampleSelfCheck() {
    const prompt = 'ahoj zajtra chceme ist na turu, potrebujem outfit';
    final decision = ConversationReasoner.evaluate(
      conversation: prompt,
      latestMessage: prompt,
      gpsCityLabel: 'Martin, Slovakia',
    );
    debugPrint(
      'STYLIST CONVERSATION QA SAMPLE { '
      'prompt="$prompt", '
      'decision=${decision.action.label}, '
      'missing=${decision.missingInformation.label} }',
    );
  }
}
