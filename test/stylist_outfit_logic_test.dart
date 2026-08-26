import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/Services/hourly_weather_service.dart';
import 'package:outfitofTheDay/Services/outfit_generation_service.dart';
import 'package:outfitofTheDay/data/event_dress_code.dart';
import 'package:outfitofTheDay/models/outfit_context_state.dart';
import 'package:outfitofTheDay/models/stylist_trip_window.dart';
import 'package:outfitofTheDay/utils/bottom_family_guidance.dart';
import 'package:outfitofTheDay/utils/event_clarification.dart';
import 'package:outfitofTheDay/utils/footwear_family_guidance.dart';
import 'package:outfitofTheDay/utils/stylist_city_suggester.dart';
import 'package:outfitofTheDay/utils/slovak_city_locative.dart';
import 'package:outfitofTheDay/utils/slovak_outfit_instrumental.dart';
import 'package:outfitofTheDay/utils/stylist_activity_terrain.dart';
import 'package:outfitofTheDay/utils/stylist_weather_adjustment.dart';
import 'package:outfitofTheDay/utils/stylist_day_parser.dart';
import 'package:outfitofTheDay/utils/dress_code_resolver.dart';
import 'package:outfitofTheDay/utils/stylist_destination_parser.dart';
import 'package:outfitofTheDay/Services/outfit_generation_service.dart';
import 'package:outfitofTheDay/data/outfit_intent.dart';
import 'package:outfitofTheDay/data/stylist_intent.dart';
import 'package:outfitofTheDay/utils/outfit_intent_scorer.dart';
import 'package:outfitofTheDay/utils/outfit_intent_builder.dart';
import 'package:outfitofTheDay/utils/stylist_intent_resolver.dart';
import 'package:outfitofTheDay/utils/stylist_chat_candidate_pipeline.dart';
import 'package:outfitofTheDay/utils/stylist_intent_matrix_generator.dart';
import 'package:outfitofTheDay/utils/stylist_occasion_guidance.dart';
import 'package:outfitofTheDay/utils/stylist_swap_request.dart';
import 'package:outfitofTheDay/utils/stylist_conversation_signals.dart';
import 'package:outfitofTheDay/utils/stylist_weather_tip.dart';
import 'package:outfitofTheDay/utils/wardrobe_gap_analysis.dart';
import 'package:outfitofTheDay/utils/layer_harmony_guard.dart';
import 'package:outfitofTheDay/utils/trip_weather_analyzer.dart';
import 'package:outfitofTheDay/utils/stylist_trip_parser.dart';

/// Deterministické testy pre logiku stylistu: výber rodiny spodku podľa
/// sezóny/počasia, počasie na celý výlet (text bez bundy/vymysleného času),
/// parsovanie dní a miest a dress-code pravidlá pre šortky.
void main() {
  OutfitWeatherSnapshot weather({
    required int tempC,
    required String season,
    bool rain = false,
    bool wind = false,
  }) {
    return OutfitWeatherSnapshot(
      tempC: tempC,
      isRainy: rain,
      isWindy: wind,
      seasonKey: season,
    );
  }

  OutfitWeatherDaySnapshot daySnapshot({
    required int temp,
    bool willRain = false,
    bool morningRain = false,
    bool afternoonRain = false,
    bool eveningRain = false,
    bool fromApi = true,
    String? rainTimeText,
  }) {
    return OutfitWeatherDaySnapshot(
      cityName: 'Mníchov',
      date: DateTime(2026, 7, 1),
      morningTempC: temp,
      noonTempC: temp,
      eveningTempC: temp,
      minTempC: temp - 2,
      maxTempC: temp + 2,
      willRain: willRain,
      rainTimeText: rainTimeText,
      outfitWhyWeatherNote: '',
      morningRainSegment: morningRain,
      afternoonRainSegment: afternoonRain,
      eveningRainSegment: eveningRain,
      isWindy: false,
      summaryText: '',
      fromOpenMeteo: fromApi,
      mainChipTempC: temp,
      mainChipBasis: 'test',
      mainChipHour: 12,
      briefingMorningCondition: '',
      briefingAfternoonCondition: '',
      briefingEveningCondition: '',
    );
  }

  group('Výber spodku podľa sezóny a počasia (computeBottomFamilyGuidance)', () {
    test('Leto, 19 °C → preferované sú kraťasy, nie dlhé nohavice', () {
      final g = computeBottomFamilyGuidance(
        weather: weather(tempC: 19, season: 'let'),
      );
      expect(g.preferredFamilies, contains('shorts'));
      expect(g.preferredFamilies, isNot(contains('pants')));
      expect(g.preferredFamilies, isNot(contains('jeans')));
    });

    test('Leto, 17 °C (hranica) → stále kraťasy preferované', () {
      final g = computeBottomFamilyGuidance(
        weather: weather(tempC: 17, season: 'let'),
      );
      expect(g.preferredFamilies, contains('shorts'));
    });

    test('Leto, 16 °C → už chladnejšie, preferované nohavice/rifle', () {
      final g = computeBottomFamilyGuidance(
        weather: weather(tempC: 16, season: 'let'),
      );
      expect(g.preferredFamilies, contains('pants'));
      expect(g.preferredFamilies, isNot(contains('shorts')));
    });

    test('Jar, 19 °C → kraťasy aj nohavice (žiadne letné zúženie)', () {
      final g = computeBottomFamilyGuidance(
        weather: weather(tempC: 19, season: 'jar'),
      );
      expect(g.preferredFamilies, contains('shorts'));
      expect(g.preferredFamilies, contains('pants'));
    });

    test('Horúčava 28 °C → kraťasy preferované, rifle neodporúčané', () {
      final g = computeBottomFamilyGuidance(
        weather: weather(tempC: 28, season: 'let'),
      );
      expect(g.preferredFamilies, contains('shorts'));
      expect(g.discouragedFamilies, contains('jeans'));
    });

    test('Zima/chlad 10 °C → kraťasy neodporúčané', () {
      final g = computeBottomFamilyGuidance(
        weather: weather(tempC: 10, season: 'zim'),
      );
      expect(g.discouragedFamilies, contains('shorts'));
      expect(g.preferredFamilies, contains('pants'));
    });

    test('Dážd v lete nemení preferenciu kraťasov', () {
      final dry = computeBottomFamilyGuidance(
        weather: weather(tempC: 19, season: 'let'),
      );
      final rainy = computeBottomFamilyGuidance(
        weather: weather(tempC: 19, season: 'let', rain: true),
      );
      expect(rainy.preferredFamilies, dry.preferredFamilies);
    });
  });

  group('Klasifikácia rodiny spodku (classifyBottomFamily)', () {
    test('šortky → shorts', () {
      expect(
        classifyBottomFamily({'name': 'Čierne šortky', 'canonical_type': 'shorts'}),
        BottomFamily.shorts,
      );
    });

    test('rifle → jeans', () {
      expect(
        classifyBottomFamily({'name': 'Modré rifle', 'subCategoryKey': 'rifle'}),
        BottomFamily.jeans,
      );
    });

    test('nohavice → pants', () {
      expect(
        classifyBottomFamily({'name': 'Sivé nohavice', 'canonical_type': 'pants'}),
        BottomFamily.pants,
      );
    });
  });

  group('Počasie na výlet (TripWeatherAnalyzer)', () {
    test('Bez známeho času: žiadna bunda ani "udalosť", pri daždi dáždnik', () {
      final trip = TripWeatherAnalyzer.analyze(
        day: daySnapshot(temp: 19, willRain: true),
        window: const StylistTripWindow(),
        timeKnown: false,
      );
      final advisory = trip.advisorySk.toLowerCase();
      expect(advisory, isNot(contains('bund')));
      expect(advisory, isNot(contains('udalost')));
      expect(advisory, contains('dážd'));
    });

    test('Bez známeho času: žiadne tvrdenia o pred/počas udalosti', () {
      final trip = TripWeatherAnalyzer.analyze(
        day: daySnapshot(temp: 19, willRain: false),
        window: const StylistTripWindow(),
        timeKnown: false,
      );
      expect(trip.rainBeforeEvent, isFalse);
      expect(trip.rainDuringEvent, isFalse);
      expect(trip.rainOnReturn, isFalse);
    });

    test('So známym časom a ranným dažďom: dáždnik, nikdy bunda', () {
      final trip = TripWeatherAnalyzer.analyze(
        day: daySnapshot(temp: 19, willRain: true, morningRain: true),
        window: const StylistTripWindow(tripStartHour: 8, eventStartHour: 14),
        timeKnown: true,
      );
      final advisory = trip.advisorySk.toLowerCase();
      expect(advisory, isNot(contains('bund')));
      expect(advisory, contains('dážd'));
    });

    test('tempAtHour: presná hodina z hourly mapy, nie ranný priemer', () {
      final hourly = List<int?>.filled(24, null);
      hourly[5] = 12;
      hourly[8] = 17;
      final day = OutfitWeatherDaySnapshot(
        cityName: 'Martin',
        date: DateTime(2026, 7, 5),
        morningTempC: 17,
        noonTempC: 22,
        eveningTempC: 18,
        minTempC: 10,
        maxTempC: 24,
        willRain: true,
        rainTimeText: '7:00',
        outfitWhyWeatherNote: '',
        morningRainSegment: true,
        afternoonRainSegment: false,
        eveningRainSegment: false,
        isWindy: false,
        summaryText: '',
        fromOpenMeteo: true,
        mainChipTempC: 22,
        mainChipBasis: 'test',
        mainChipHour: null,
        briefingMorningCondition: '',
        briefingAfternoonCondition: '',
        briefingEveningCondition: '',
        hourlyTempCByLocalHour: hourly,
      );
      expect(TripWeatherAnalyzer.tempAtHour(day, 5), 12);
      expect(TripWeatherAnalyzer.tempAtHour(day, 8), 17);
    });
  });

  group('StylistTripWindow.hasExplicitTime', () {
    test('prázdne okno → false', () {
      expect(const StylistTripWindow().hasExplicitTime, isFalse);
    });

    test('so začiatkom udalosti → true', () {
      expect(
        const StylistTripWindow(eventStartHour: 10).hasExplicitTime,
        isTrue,
      );
    });
  });

  group('Dress code – povolenie šortiek (EventDressCodeSpec.allowShorts)', () {
    test('Casual pri 19 °C → šortky povolené', () {
      expect(EventDressCodeSpec.casual.allowShorts(19), isTrue);
    });

    test('Casual pri 17 °C → šortky povolené (mierne letné počasie)', () {
      expect(EventDressCodeSpec.casual.allowShorts(17), isTrue);
    });

    test('Casual pri 14 °C → šortky nepovolené (chladno)', () {
      expect(EventDressCodeSpec.casual.allowShorts(14), isFalse);
    });

    test('Turistika vonku pri 17 °C → šortky povolené', () {
      final hike = EventDressCodeCatalog.archetypes
          .firstWhere((a) => a.id == 'hike')
          .spec;
      expect(hike.allowShorts(17), isTrue);
    });
  });

  group('SlovakCityLocative', () {
    test('fixCityDeclensionInText opraví pri/v + nominatív', () {
      expect(
        SlovakCityLocative.fixCityDeclensionInText(
          'prechádzku v horách pri Martin.',
        ),
        'prechádzku v horách pri Martine.',
      );
      expect(
        SlovakCityLocative.fixCityDeclensionInText('v Martin okolo 15:00'),
        'v Martine okolo 15:00',
      );
    });
  });

  group('EventClarification – čas pred outfitom', () {
    test('prechádzka do hory bez času → pýta sa o koľkej', () {
      final msg = EventClarification.missingMessage(
        'cauko chcem sa ist prejst do hory a neviem co na seba',
        gpsCityLabel: 'Martin',
      );
      expect(msg, isNotNull);
      expect(msg!.toLowerCase(), contains('koľkej'));
    });

    test('prechádzka s o 14 → čas OK', () {
      final msg = EventClarification.missingMessage(
        'chcem do hory o 14',
        gpsCityLabel: 'Martin',
      );
      expect(msg, isNull);
    });

    test('teraz → čas OK bez otázky', () {
      final msg = EventClarification.missingMessage(
        'chcem sa ist teraz prejst',
        gpsCityLabel: 'Martin',
      );
      expect(msg, isNull);
    });

    test('preklep prechsdzku + zajtra → pýta sa o koľkej', () {
      final msg = EventClarification.missingMessage(
        'Ahoj, zajtra chcem ist na prechsdzku po horach, co si mm dat na seba?',
        gpsCityLabel: 'Martin',
      );
      expect(msg, isNotNull);
      expect(msg!.toLowerCase(), contains('koľkej'));
    });

    test('typo prechsdzku rozpozná outfit request', () {
      expect(
        StylistDestinationParser.userWantsOutfitFromWardrobe(
          'zajtra prechsdzku po horach co si dat na seba',
        ),
        isTrue,
      );
    });
  });

  group('StylistWeatherAdjustment', () {
    test('wetGround o 4:00 → −4 °C oproti mestu', () {
      expect(
        StylistWeatherAdjustment.adjustActivityTempC(
          rawTempC: 16,
          terrain: StylistActivityTerrain.wetGround,
          hourLocal: 4,
        ),
        12,
      );
    });

    test('mesto → bez úpravy', () {
      expect(
        StylistWeatherAdjustment.adjustActivityTempC(
          rawTempC: 16,
          terrain: StylistActivityTerrain.urban,
          hourLocal: 4,
        ),
        16,
      );
    });
  });

  group('StylistActivityTerrainClassifier', () {
    test('huby → wetGround', () {
      expect(
        StylistActivityTerrainClassifier.classify(
          conversationText: 'zajtra rano na huby',
        ),
        StylistActivityTerrain.wetGround,
      );
    });
  });

  group('Antecedent precipitation for terrain', () {
    test('forest after prior rain requires closed footwear even if start is dry', () {
      expect(
        StylistWeatherTipBuilder.wetGroundNeedsClosedFootwear(
          snapshot: daySnapshot(temp: 20, willRain: false),
          now: DateTime(2026, 8, 26, 9),
          terrain: StylistActivityTerrain.wetGround,
          eventHour: 13,
          antecedentPrecipitation: true,
        ),
        isTrue,
      );
    });

    test('dry forest receives no artificial wet-ground restriction', () {
      expect(
        StylistWeatherTipBuilder.wetGroundNeedsClosedFootwear(
          snapshot: daySnapshot(temp: 20, willRain: false),
          now: DateTime(2026, 8, 26, 9),
          terrain: StylistActivityTerrain.wetGround,
          eventHour: 13,
          antecedentPrecipitation: false,
        ),
        isFalse,
      );
    });
  });

  group('Parser dňa (StylistDayParser.resolveDate)', () {
    final now = DateTime(2026, 6, 30); // utorok

    test('"v stredu" → najbližšia streda (1. júl)', () {
      final d = StylistDayParser.resolveDate('stretneme sa v stredu', now: now);
      expect(d, DateTime(2026, 7, 1));
    });

    test('"pozajtra" → +2 dni', () {
      final d = StylistDayParser.resolveDate('pozajtra idem von', now: now);
      expect(d, DateTime(2026, 7, 2));
    });

    test('bez dňa → null', () {
      expect(StylistDayParser.resolveDate('chcem nejaky outfit', now: now), isNull);
    });
  });

  group('Univerzálna výmena kusu (StylistSwapRequest)', () {
    test('"skús iné tričko" → slot vrch', () {
      final r = StylistSwapRequest.parse('skús iné tričko');
      expect(r?.slot, StylistSwapSlot.top);
    });

    test('"vymeň topánky" → slot obuv', () {
      final r = StylistSwapRequest.parse('vymeň topánky');
      expect(r?.slot, StylistSwapSlot.shoes);
    });

    test('"daj iné tenisky" → slot obuv s rodinou sneakers', () {
      final r = StylistSwapRequest.parse('daj iné tenisky');
      expect(r?.slot, StylistSwapSlot.shoes);
      expect(r?.shoeFamily, FootwearFamily.sneakers);
    });

    test('"vymeň bundu" → slot vrchná vrstva', () {
      final r = StylistSwapRequest.parse('vymeň bundu');
      expect(r?.slot, StylistSwapSlot.outerwear);
    });

    test('"radšej kraťasy" → slot spodok s rodinou shorts', () {
      final r = StylistSwapRequest.parse('radšej kraťasy');
      expect(r?.slot, StylistSwapSlot.bottom);
      expect(r?.bottomFamily, BottomFamily.shorts);
    });

    test('"iné nohavice" → slot spodok (bez konkrétnej rodiny)', () {
      final r = StylistSwapRequest.parse('iné nohavice');
      expect(r?.slot, StylistSwapSlot.bottom);
      expect(r?.bottomFamily, isNull);
    });

    test('"chcem ísť do mnichova" → žiadna výmena', () {
      expect(StylistSwapRequest.parse('chcem ist do mnichova'), isNull);
    });

    test('"zmen mi tričko" → slot vrch', () {
      final r = StylistSwapRequest.parse('zmen mi tričko');
      expect(r?.slot, StylistSwapSlot.top);
    });
  });

  group('Skloňovanie kúskov (SlovakOutfitInstrumental)', () {
    test('akuzatív: stredný rod/množné číslo = nominatív (malé prvé písmeno)', () {
      expect(
        SlovakOutfitInstrumental.accusative('Bordové tričko s krátkym rukávom'),
        'bordové tričko s krátkym rukávom',
      );
      expect(
        SlovakOutfitInstrumental.accusative('Čierne šortky'),
        'čierne šortky',
      );
      expect(
        SlovakOutfitInstrumental.accusative('Biele fashion tenisky'),
        'biele fashion tenisky',
      );
    });

    test('akuzatív: ženský rod jednotného čísla (bunda → bundu)', () {
      expect(
        SlovakOutfitInstrumental.accusative('Čierna bunda'),
        'čiernu bundu',
      );
    });

    test('inštrumentál ostáva pre frázu "ladí s …"', () {
      expect(
        SlovakOutfitInstrumental.phrase('Čierne šortky'),
        'čiernymi šortkami',
      );
    });

    test('predložka s/so podľa začiatočného písmena', () {
      expect(SlovakOutfitInstrumental.sSo('čiernymi šortkami'), 's');
      expect(SlovakOutfitInstrumental.sSo('sivými teniskami'), 'so');
    });
  });

  group('Destinácia z konverzácie (StylistDestinationParser)', () {
    test('"do hory sa prejsť" → nie je mesto', () {
      expect(
        StylistDestinationParser.inferFromConversation(
          'teraz pojdem vonku trosku do hory sa prejst',
        ),
        isNull,
      );
    });

    test('"v Martine sa idem prejsť" → Martin', () {
      expect(
        StylistDestinationParser.inferFromConversation(
          'v Martine sa idem prejst do hory',
        ),
        'Martin',
      );
    });

    test('"hory" / "Hory sa" → nie sú platné destinácie', () {
      expect(StylistDestinationParser.isPlausibleDestination('hory'), isFalse);
      expect(StylistDestinationParser.isPlausibleDestination('Hory sa'), isFalse);
    });

    test('needsDestinationForOutfit — GPS mesto stačí, nepýtame sa', () {
      expect(
        StylistDestinationParser.needsDestinationForOutfit(
          conversationText: 'chcem outfit na prechádzku von',
          gpsCityLabel: 'Martin, Slovensko',
        ),
        isFalse,
      );
    });

    test('hasOutfitGenerationContext — GPS + čas stačí', () {
      expect(
        StylistDestinationParser.hasOutfitGenerationContext(
          conversationText: 'teraz idem von',
          hourLocal: 15,
          gpsCityLabel: 'Martin',
        ),
        isTrue,
      );
    });

    test('hasOutfitGenerationContext — explicitné mesto má prednosť', () {
      expect(
        StylistDestinationParser.hasOutfitGenerationContext(
          conversationText: 'idem do Žiliny o 18',
          hourLocal: 18,
          inferredDestination: 'Žilina',
          gpsCityLabel: 'Martin',
        ),
        isTrue,
      );
    });

    test('"čo si mám obliecť dnes do práce" → nie je mesto', () {
      expect(
        StylistDestinationParser.inferFromConversation(
          'čo si mám obliecť dnes do práce',
        ),
        isNull,
      );
    });

    test('"idem do roboty" → nie je mesto', () {
      expect(
        StylistDestinationParser.inferFromConversation('idem do roboty'),
        isNull,
      );
    });

    test('"idem do Žiliny" → Žilina', () {
      expect(
        StylistDestinationParser.inferFromConversation('idem do Žiliny'),
        'Žilina',
      );
    });

    test('"idem do hory" → nie je mesto', () {
      expect(
        StylistDestinationParser.inferFromConversation('idem do hory'),
        isNull,
      );
    });

    test('"idem do školy" → nie je mesto', () {
      expect(
        StylistDestinationParser.inferFromConversation('idem do školy'),
        isNull,
      );
    });

    test('"Idem do Washingtonu." → Washington (čistý názov)', () {
      expect(
        StylistDestinationParser.inferFromConversation('Idem do Washingtonu.'),
        'Washington',
      );
    });

    test('"Idem do Washingtonu, potrebujem outfit." → Washington', () {
      expect(
        StylistDestinationParser.inferFromConversation(
          'Idem do Washingtonu, potrebujem outfit.',
        ),
        'Washington',
      );
    });

    test('"Idem do Washingtonu potrebujem outfit" (bez čiarky) → Washington', () {
      expect(
        StylistDestinationParser.inferFromConversation(
          'Idem do Washingtonu potrebujem outfit',
        ),
        'Washington',
      );
    });

    test('"Budeme vo Washingtone okolo 16:00." → Washington', () {
      expect(
        StylistDestinationParser.inferFromConversation(
          'Budeme vo Washingtone okolo 16:00.',
        ),
        'Washington',
      );
    });

    test('"Zajtra sme v Bratislave." → Bratislava', () {
      expect(
        StylistDestinationParser.inferFromConversation(
          'Zajtra sme v Bratislave.',
        ),
        'Bratislava',
      );
    });

    test('dvojslovné mesto s veľkým písmenom ostáva ("do Santa Barbara")', () {
      expect(
        StylistDestinationParser.inferFromConversation(
          'Idem do Santa Barbara',
        ),
        'Santa Barbara',
      );
    });

    test('slovo za mestom sa neprilepí ("v Galway som spokojný")', () {
      expect(
        StylistDestinationParser.inferFromConversation(
          'v Galway som spokojný',
        ),
        'Galway, Ireland',
      );
    });
  });

  group('Krajina/región vs mesto (StylistDestinationParser)', () {
    test('"ahoj zajtra ideme do USA potrebujem outfit" → clarify, blok flow', () {
      const text = 'ahoj zajtra ideme do USA potrebujem outfit';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isTrue);
      expect(StylistDestinationParser.broadRegionInConversation(text), 'USA');
      expect(StylistDestinationParser.inferFromConversation(text), isNull);
    });

    test('"ideme do USA, budeme sa prechádzať po meste" → clarify city', () {
      const text = 'ideme do USA, budeme sa prechádzať po meste';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isTrue);
      expect(StylistDestinationParser.broadRegionInConversation(text), 'USA');
      expect(StylistDestinationParser.inferFromConversation(text), isNull);
    });

    test('"ideme do USA do New Yorku" → prepustiť, city=New York', () {
      const text = 'ideme do USA do New Yorku';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isFalse);
      expect(StylistDestinationParser.broadRegionInConversation(text), 'USA');
      expect(
        StylistDestinationParser.inferFromConversation(text),
        'New York',
      );
    });

    test('"ideme do Talianska" → clarify city', () {
      const text = 'ideme do Talianska';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isTrue);
      expect(
        StylistDestinationParser.broadRegionInConversation(text),
        'Taliansko',
      );
      expect(StylistDestinationParser.inferFromConversation(text), isNull);
    });

    test('"ideme do Ríma" → prepustiť', () {
      const text = 'ideme do Ríma';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isFalse);
      expect(
        StylistDestinationParser.inferFromConversation(text),
        'Rím',
      );
    });

    test('"Ideme do USA" → clarify, žiadny outfit', () {
      const text = 'Ideme do USA';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isTrue);
      expect(StylistDestinationParser.broadRegionInConversation(text), 'USA');
      expect(StylistDestinationParser.inferFromConversation(text), isNull);
    });

    test('reálna veta z bugu → clarify (USA nie je mesto)', () {
      const text =
          'ahoj zajtra ideme do USA tak potrebujem nejaký outfit, '
          'budeme sa len tak prechádzať po meste';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isTrue);
      expect(StylistDestinationParser.broadRegionInConversation(text), 'USA');
      expect(StylistDestinationParser.inferFromConversation(text), isNull);
    });

    test('"Ideme do Ameriky" → clarify, žiadny outfit', () {
      const text = 'Ideme do Ameriky';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isTrue);
      expect(
        StylistDestinationParser.broadRegionInConversation(text),
        'Amerika',
      );
      expect(StylistDestinationParser.inferFromConversation(text), isNull);
    });

    test('"Ideme do Talianska" → clarify, žiadny outfit', () {
      const text = 'Ideme do Talianska';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isTrue);
      expect(
        StylistDestinationParser.broadRegionInConversation(text),
        'Taliansko',
      );
      expect(StylistDestinationParser.inferFromConversation(text), isNull);
    });

    test('"Ideme do Washingtonu" → city=Washington, môže generovať', () {
      const text = 'Ideme do Washingtonu';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isFalse);
      expect(
        StylistDestinationParser.inferFromConversation(text),
        'Washington',
      );
      expect(StylistDestinationParser.broadRegionInConversation(text), isNull);
    });

    test('"Ideme do New Yorku" → city=New York, môže generovať', () {
      const text = 'Ideme do New Yorku';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isFalse);
      expect(
        StylistDestinationParser.inferFromConversation(text),
        'New York',
      );
      expect(StylistDestinationParser.broadRegionInConversation(text), isNull);
    });

    test('"Ideme do Bratislavy" → city=Bratislava, môže generovať', () {
      const text = 'Ideme do Bratislavy';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isFalse);
      expect(
        StylistDestinationParser.inferFromConversation(text),
        'Bratislava',
      );
      expect(StylistDestinationParser.broadRegionInConversation(text), isNull);
    });

    test('krajina + konkrétne mesto → generuje (mesto vyhráva)', () {
      const text = 'Ideme do USA, konkrétne do New Yorku';
      expect(StylistDestinationParser.shouldBlockForBroadRegion(text), isFalse);
      expect(StylistDestinationParser.broadRegionInConversation(text), 'USA');
      expect(
        StylistDestinationParser.inferFromConversation(text),
        'New York',
      );
    });

    test('otázka na mesto obsahuje názov krajiny', () {
      expect(
        StylistDestinationParser.broadRegionCityQuestion('USA'),
        'Do ktorého mesta v USA idete? '
        'Počasie sa môže veľmi líšiť podľa mesta.',
      );
    });

    test('isBroadRegion rozlíši krajinu od mesta', () {
      expect(StylistDestinationParser.isBroadRegion('USA'), isTrue);
      expect(StylistDestinationParser.isBroadRegion('Taliansko'), isTrue);
      expect(StylistDestinationParser.isBroadRegion('Washington'), isFalse);
      expect(StylistDestinationParser.isBroadRegion('Bratislava'), isFalse);
    });
  });

  group('Dress code archetypy (DressCodeResolver)', () {
    test('generic trip does not become hiking after city context is supplied', () {
      final spec = DressCodeResolver.resolve(
        conversationText:
            'zajtra ideme na vylet Wasntom a prechadzka po meste',
      );

      expect(spec.id, isNot('hike'));
    });

    test('„čo si mám obliecť dnes do práce“ → work / formality >= 5', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'čo si mám obliecť dnes do práce',
      );
      expect(spec.id, 'work');
      expect(spec.formalityTarget, greaterThanOrEqualTo(5));
      expect(spec.labelSk, isNot('voľný čas'));
    });

    test('„večer idem na svadbu“ → wedding / formality >= 8 / shorts excluded', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'večer idem na svadbu',
      );
      expect(spec.id, 'wedding');
      expect(spec.formalityTarget, greaterThanOrEqualTo(8));
      expect(spec.allowShorts(28), isFalse);
    });

    test('„idem na pohovor“ → interview / formality >= 7 / shorts excluded', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem na pohovor',
      );
      expect(spec.id, 'interview');
      expect(spec.formalityTarget, greaterThanOrEqualTo(7));
      expect(spec.allowShorts(28), isFalse);
    });

    test('„idem na pohreb“ → funeral / formality >= 8 / shorts excluded', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem na pohreb',
      );
      expect(spec.id, 'funeral');
      expect(spec.formalityTarget, greaterThanOrEqualTo(8));
      expect(spec.allowShorts(28), isFalse);
    });

    test('„idem na oslavu“ → celebration / formality >= 6', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem na oslavu',
      );
      expect(spec.id, 'celebration');
      expect(spec.formalityTarget, greaterThanOrEqualTo(6));
      expect(spec.labelSk, isNot('voľný čas'));
    });
  });

  group('Príležitosť má prednosť pred teplotou (StylistOccasionGuidance)', () {
    test('Svadba pri 28 °C → šortky vylúčené, preferované nohavice', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'večer idem na svadbu',
        tempC: 28,
      );
      final profile = StylistOccasionProfile(dressCode: spec, tempC: 28);
      final g = StylistOccasionGuidance.bottomGuidanceFor(
        weather: weather(tempC: 28, season: 'let'),
        profile: profile,
      );
      expect(g.allowedFamilies, isNot(contains('shorts')));
      expect(g.discouragedFamilies, contains('shorts'));
      expect(g.preferredFamilies.first, 'pants');
    });

    test('Práca pri 28 °C → šortky znevýhodnené, nie preferované', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'čo si mám obliecť dnes do práce',
        tempC: 28,
      );
      final profile = StylistOccasionProfile(dressCode: spec, tempC: 28);
      final g = StylistOccasionGuidance.bottomGuidanceFor(
        weather: weather(tempC: 28, season: 'let'),
        profile: profile,
      );
      expect(g.discouragedFamilies, contains('shorts'));
      expect(g.preferredFamilies, isNot(contains('shorts')));
      expect(g.preferredFamilies, contains('jeans'));
    });

    test('Turistika → rifle znevýhodnené, nohavice/joggers preferované', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem do hory',
      );
      final profile = StylistOccasionProfile(dressCode: spec, tempC: 18);
      final g = StylistOccasionGuidance.bottomGuidanceFor(
        weather: weather(tempC: 18, season: 'let'),
        profile: profile,
      );
      expect(g.discouragedFamilies, contains('jeans'));
      expect(g.preferredFamilies, contains('pants'));
      expect(g.preferredFamilies, contains('joggers'));
      expect(g.preferredFamilies, isNot(contains('jeans')));
      expect(g.allowedFamilies, contains('jeans'));
    });

    test('Svadba pri 28 °C → sandále vylúčené, elegantná obuv preferovaná', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem na svadbu',
        tempC: 28,
      );
      final profile = StylistOccasionProfile(dressCode: spec, tempC: 28);
      final g = StylistOccasionGuidance.footwearGuidanceFor(
        weather: weather(tempC: 28, season: 'let'),
        profile: profile,
      );
      expect(g.allowedFamilies, isNot(contains('sandals')));
      expect(g.discouragedFamilies, contains('sandals'));
      expect(g.preferredFamilies.first, 'formal_shoes');
    });

    test('Pohovor pri 26 °C → šortky úplne vylúčené (formality >= 7)', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem na pohovor',
        tempC: 26,
      );
      final profile = StylistOccasionProfile(dressCode: spec, tempC: 26);
      final g = StylistOccasionGuidance.bottomGuidanceFor(
        weather: weather(tempC: 26, season: 'let'),
        profile: profile,
      );
      expect(g.allowedFamilies, isNot(contains('shorts')));
      expect(g.discouragedFamilies, contains('shorts'));
    });

    test('finalReviewOccasionPayload obsahuje label, aktivitu, formálnosť, venue', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem na svadbu',
        tempC: 28,
      );
      final profile = StylistOccasionProfile(dressCode: spec, tempC: 28);
      final payload = StylistOccasionGuidance.finalReviewOccasionPayload(
        profile: profile,
        compromiseNotes: const ['hike_jeans_compromise'],
      );
      expect(payload['occasionLabel'], 'svadba');
      expect(payload['activityType'], 'wedding');
      expect(payload['formalityTarget'], greaterThanOrEqualTo(8));
      expect(payload['venueType'], 'indoor_formal');
      expect(payload['compromiseNotes'], contains('hike_jeans_compromise'));
    });

    test('finalReviewOccasionPayload bez kompromisov neposiela compromiseNotes', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem do hory',
      );
      final profile = StylistOccasionProfile(dressCode: spec, tempC: 18);
      final payload = StylistOccasionGuidance.finalReviewOccasionPayload(
        profile: profile,
      );
      expect(payload['activityType'], 'hike');
      expect(payload['venueType'], 'outdoor');
      expect(payload.containsKey('compromiseNotes'), isFalse);
    });

    test('explainOutfitPayloadFor obsahuje occasion, guidance a hike kompromis', () {
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem do hory',
      );
      final profile = StylistOccasionProfile(dressCode: spec, tempC: 18);
      final preview = OutfitPreview(
        top: OutfitPreviewItem(
          type: OutfitWearType.top,
          item: const {'name': 'Tričko', 'canonical_type': 'tshirt'},
          label: 'Tričko',
          imageUrl: null,
        ),
        bottom: OutfitPreviewItem(
          type: OutfitWearType.bottom,
          item: const {'name': 'Rifle', 'canonical_type': 'jeans'},
          label: 'Rifle',
          imageUrl: null,
        ),
        shoes: OutfitPreviewItem(
          type: OutfitWearType.shoes,
          item: const {'name': 'Tenisky', 'canonical_type': 'sneakers'},
          label: 'Tenisky',
          imageUrl: null,
        ),
        outerwear: null,
      );
      final payload = StylistOccasionGuidance.explainOutfitPayloadFor(
        profile: profile,
        preview: preview,
        weather: weather(tempC: 18, season: 'let'),
      );
      expect(payload['occasionContext'], isA<Map>());
      expect(payload['bottomGuidance'], isA<Map>());
      expect(payload['footwearGuidance'], isA<Map>());
      final occasion = payload['occasionContext'] as Map;
      expect(occasion['compromiseNotes'], contains('hike_jeans_compromise'));
    });
  });

  group('Dažď a aktivita (StylistWeatherTipBuilder + terrain)', () {
    OutfitWeatherDaySnapshot rainyAfternoon() {
      return OutfitWeatherDaySnapshot(
        cityName: 'Martin',
        date: DateTime(2026, 6, 30),
        morningTempC: 18,
        noonTempC: 20,
        eveningTempC: 18,
        minTempC: 16,
        maxTempC: 22,
        willRain: true,
        rainTimeText: '13:00-16:00',
        outfitWhyWeatherNote: '',
        morningRainSegment: false,
        afternoonRainSegment: true,
        eveningRainSegment: false,
        isWindy: false,
        summaryText: '',
        fromOpenMeteo: true,
        mainChipTempC: 20,
        mainChipBasis: 'test',
        mainChipHour: 14,
        briefingMorningCondition: '',
        briefingAfternoonCondition: '',
        briefingEveningCondition: '',
      );
    }

    test('mestská prechádzka o 16:50 po daždi → žiadna rada (minulosť irelevantná)', () {
      final advice = StylistWeatherTipBuilder.rainAdviceForNow(
        snapshot: rainyAfternoon(),
        now: DateTime(2026, 6, 30, 16, 50),
        eventHour: 14,
        terrain: StylistActivityTerrain.urban,
      );
      expect(advice, isNull);
    });

    test('hory o 16:50 po daždi → mokrá pôda + uzavretá obuv', () {
      final advice = StylistWeatherTipBuilder.rainAdviceForNow(
        snapshot: rainyAfternoon(),
        now: DateTime(2026, 6, 30, 16, 50),
        terrain: StylistActivityTerrain.wetGround,
      );
      expect(advice, isNotNull);
      expect(advice!.toLowerCase(), contains('mokro'));
      expect(advice.toLowerCase(), contains('tenisk'));
    });

    test('mesto — teraz prší → dáždnik', () {
      final advice = StylistWeatherTipBuilder.rainAdviceForNow(
        snapshot: rainyAfternoon(),
        now: DateTime(2026, 6, 30, 14, 0),
        terrain: StylistActivityTerrain.urban,
      );
      expect(advice, isNotNull);
      expect(advice!.toLowerCase(), contains('teraz'));
    });

    test('bez návratu + večerný dážď → spomenie večer', () {
      final snap = OutfitWeatherDaySnapshot(
        cityName: 'Martin',
        date: DateTime(2026, 6, 30),
        morningTempC: 18,
        noonTempC: 22,
        eveningTempC: 17,
        minTempC: 16,
        maxTempC: 24,
        willRain: true,
        rainTimeText: '19:00-21:00',
        outfitWhyWeatherNote: '',
        morningRainSegment: false,
        afternoonRainSegment: false,
        eveningRainSegment: true,
        isWindy: false,
        summaryText: '',
        fromOpenMeteo: true,
        mainChipTempC: 22,
        mainChipBasis: 'test',
        mainChipHour: 14,
        briefingMorningCondition: '',
        briefingAfternoonCondition: '',
        briefingEveningCondition: '',
      );
      final advice = StylistWeatherTipBuilder.rainAdviceForNow(
        snapshot: snap,
        now: DateTime(2026, 6, 30, 14, 0),
        eventHour: 14,
        terrain: StylistActivityTerrain.urban,
        returnTimeKnown: false,
      );
      expect(advice, isNotNull);
      expect(advice!.toLowerCase(), contains('večer'));
    });

    test('klasifikácia: do hory → wetGround, prechádzka v meste → urban', () {
      expect(
        StylistActivityTerrainClassifier.classify(
          conversationText: 'idem sa prejst do hory',
        ),
        StylistActivityTerrain.wetGround,
      );
      expect(
        StylistActivityTerrainClassifier.classify(
          conversationText: 'prechadzka v meste',
        ),
        StylistActivityTerrain.urban,
      );
    });

    test('naturalDaySummarySk — jedna veta, nie zoznam segmentov', () {
      final summary = StylistWeatherTipBuilder.naturalDaySummarySk(
        snapshot: rainyAfternoon(),
        locationLabel: 'Martin',
        isTomorrow: true,
        terrain: StylistActivityTerrain.wetGround,
      );
      expect(summary, isNotNull);
      expect(summary!, isNot(contains('ráno, okolo obeda a večer')));
      expect(summary, contains('16–22'));
    });
  });

  group('Konverzačné signály (StylistConversationSignals)', () {
    test('„no" nie je odmietnutie dážďa — je to áno', () {
      expect(
        StylistConversationSignals.userDeclinedRainAdvice('no'),
        isFalse,
      );
      expect(
        StylistConversationSignals.userDeclinedRainAdvice('no ukáž outfit'),
        isFalse,
      );
    });

    test('explicitné odmietnutie dážďa', () {
      expect(
        StylistConversationSignals.userDeclinedRainAdvice(
          'nechcem riešiť dážď',
        ),
        isTrue,
      );
    });

    test('userExplicitlyWantsOutfitShown', () {
      expect(
        StylistConversationSignals.userExplicitlyWantsOutfitShown(
          'ved mi ukaz ten outfit nie?',
        ),
        isTrue,
      );
    });
  });

  group('OutfitContextState – Fáza 2', () {
    test('zajtra do hory → remote aktivita, lokalita neznáma', () {
      final state = OutfitContextState.buildFrom(
        conversation: 'Zajtra idem do hory.',
        gpsCityLabel: 'Martin',
      );
      expect(state.remoteActivityPlanned, isTrue);
      expect(state.activityLocationKnown, isFalse);
      expect(state.hourExplicit, isFalse);
      expect(state.routineLocalOutfit, isFalse);
      expect(state.groundingStatus, 'needs_grounding');
      expect(state.unresolvedMaterialFields, contains('destination'));
    });

    test('vágny výlet nepreberie GPS ani turistiku ako event fakt', () {
      final state = OutfitContextState.buildFrom(
        conversation:
            'ahoj zajtra chceme ist na vylet, budem potrebovat pomoc s vyberom outfitu',
        latestUserText:
            'ahoj zajtra chceme ist na vylet, budem potrebovat pomoc s vyberom outfitu',
        gpsCityLabel: 'Martin',
      );
      expect(state.activityLocationKnown, isFalse);
      expect(state.activityLocationLabel, isNull);
      expect(state.gpsDefaultCity, 'Martin');
      expect(state.groundingStatus, 'needs_grounding');
      expect(state.unresolvedMaterialFields, containsAll(['destination', 'activity']));
    });

    test('oprava nepovýši predošlý predpoklad Martina alebo prechádzky na fakt', () {
      final state = OutfitContextState.buildFrom(
        conversation:
            'ahoj zajtra chceme ist na vylet\nkde som tvrdil ze idem na prechadzku okolo Martina?',
        latestUserText: 'kde som tvrdil ze idem na prechadzku okolo Martina?',
        gpsCityLabel: 'Martin',
      );
      expect(state.userCorrectionDetected, isTrue);
      expect(state.activityLocationLabel, isNull);
      expect(state.groundingStatus, 'needs_grounding');
      expect(state.unresolvedMaterialFields, containsAll(['destination', 'activity']));
    });

    test('konkrétna horská turistika s časom je uzemnená', () {
      final state = OutfitContextState.buildFrom(
        conversation:
            'Zajtra ideme do Tatier na turistiku, vyrážame o 8:00 a budeme tam asi 6 hodín.',
        latestUserText:
            'Zajtra ideme do Tatier na turistiku, vyrážame o 8:00 a budeme tam asi 6 hodín.',
        gpsCityLabel: 'Martin',
      );
      expect(state.activityLocationKnown, isTrue);
      expect(state.activityLocationLabel, 'Tatry');
      expect(state.hourLocal, 8);
      expect(state.groundingStatus, 'sufficient');
    });

    test('viacdňová cesta nie je ticho zredukovaná na lokálny outfit', () {
      final state = OutfitContextState.buildFrom(
        conversation: 'Ideme na tri dni do Prahy.',
        latestUserText: 'Ideme na tri dni do Prahy.',
        gpsCityLabel: 'Martin',
      );
      expect(state.remoteActivityPlanned, isTrue);
      expect(state.groundingStatus, 'needs_grounding');
      expect(state.unresolvedMaterialFields, contains('trip_scope'));
    });

    test('zajtra do mesta v Martine → lokalita známa', () {
      final state = OutfitContextState.buildFrom(
        conversation: 'Zajtra idem do mesta v Martine.',
        gpsCityLabel: 'Martin',
      );
      expect(state.activityLocationKnown, isTrue);
      expect(state.activityLocationLabel, 'Martin');
    });

    test('čo si mám obliecť dnes → rutinný lokálny outfit', () {
      final state = OutfitContextState.buildFrom(
        conversation: 'Čo si mám obliecť dnes?',
        gpsCityLabel: 'Martin',
      );
      expect(state.routineLocalOutfit, isTrue);
      expect(state.activityLocationKnown, isTrue);
    });

    test('zajtra o 15 do mesta → čas explicitný', () {
      final state = OutfitContextState.buildFrom(
        conversation: 'Zajtra o 15:00 idem na hodinu do mesta.',
        gpsCityLabel: 'Martin',
      );
      expect(state.hourExplicit, isTrue);
      expect(state.hourLocal, 15);
    });

    test('dlhá aktivita parsuje eventové časové okno, nie iba štart', () {
      final window = StylistTripParser.parseFromConversation(
        'Zajtra o 8:00 ideme na turistiku asi na 6 hodín.',
      );
      expect(window.eventStartHour, 8);
      expect(window.tripEndHour, 14);
      expect(window.tripEndEstimated, isFalse);
    });

    test('mergeFromAiResponse doplní confidence a eventContext', () {
      final merged = const OutfitContextState().mergeFromAiResponse(
        eventContext: {
          'hourLocal': 4,
          'locationLabel': 'Martin',
          'occasion': 'huby',
        },
        confidence: 0.92,
        decisionRisk: 'low',
        impactFields: const [],
      );
      expect(merged.hourLocal, 4);
      expect(merged.lastConfidence, 0.92);
      expect(merged.lastDecisionRisk, 'low');
      expect(merged.activityLocationLabel, 'Martin');
    });

    test('withClarifyRoundUsed sa posiela v API payload', () {
      final state = const OutfitContextState().withClarifyRoundUsed(true);
      expect(state.toApiPayload()['clarifyRoundUsed'], isTrue);
    });
  });

  OutfitIntent outfitIntentFor({
    required String conversationText,
    required OutfitWeatherSnapshot weather,
    bool wetGroundMuddy = false,
  }) {
    final stylistIntent = StylistIntentResolver.resolve(
      conversationText: conversationText,
      tempC: weather.tempC,
    );
    final spec = DressCodeResolver.resolve(
      conversationText: conversationText,
      tempC: weather.tempC,
    );
    final profile = StylistOccasionProfile(dressCode: spec, tempC: weather.tempC);
    final bottomGuidance = StylistOccasionGuidance.bottomGuidanceFor(
      weather: weather,
      profile: profile,
    );
    final footwearGuidance = StylistOccasionGuidance.footwearGuidanceFor(
      weather: weather,
      profile: profile,
      wetGroundMuddy: wetGroundMuddy,
    );
    return OutfitIntentBuilder.build(
      stylistIntent: stylistIntent,
      dressCode: spec,
      bottomGuidance: bottomGuidance,
      footwearGuidance: footwearGuidance,
      wetGroundMuddy: wetGroundMuddy,
    );
  }

  OutfitPreview previewWith({
    required String bottomName,
    required String bottomCanonical,
    required String shoesName,
    required String shoesCanonical,
    String topName = 'Tričko',
    String topCanonical = 't_shirt',
  }) {
    return OutfitPreview(
      top: OutfitPreviewItem(
        type: OutfitWearType.top,
        item: {'name': topName, 'canonical_type': topCanonical},
        label: topName,
        imageUrl: null,
      ),
      bottom: OutfitPreviewItem(
        type: OutfitWearType.bottom,
        item: {'name': bottomName, 'canonical_type': bottomCanonical},
        label: bottomName,
        imageUrl: null,
      ),
      shoes: OutfitPreviewItem(
        type: OutfitWearType.shoes,
        item: {'name': shoesName, 'canonical_type': shoesCanonical},
        label: shoesName,
        imageUrl: null,
      ),
      outerwear: null,
    );
  }

  group('StylistIntent katalóg (M1a)', () {
    test('„večer idem na svadbu“ → elegantný, reprezentatívny', () {
      final intent = StylistIntentResolver.resolve(
        conversationText: 'večer idem na svadbu',
      );
      expect(intent.activityType, 'wedding');
      expect(intent.primaryImpressions, containsAll([
        ImpressionTag.elegantny,
        ImpressionTag.reprezentativny,
      ]));
      expect(intent.impressionSummarySk, contains('elegantne'));
    });

    test('„idem na pohreb“ → decentný, nenápadný', () {
      final intent = StylistIntentResolver.resolve(
        conversationText: 'idem na pohreb',
      );
      expect(intent.activityType, 'funeral');
      expect(intent.primaryImpressions, containsAll([
        ImpressionTag.decentny,
        ImpressionTag.nenapadny,
      ]));
    });

    test('„idem na pohovor“ → profesionálny, upravený', () {
      final intent = StylistIntentResolver.resolve(
        conversationText: 'idem na pohovor',
      );
      expect(intent.activityType, 'interview');
      expect(intent.primaryImpressions, containsAll([
        ImpressionTag.profesionalny,
        ImpressionTag.upraveny,
      ]));
    });

    test('„idem na turistiku“ → praktický, funkčný', () {
      final intent = StylistIntentResolver.resolve(
        conversationText: 'idem na turistiku',
      );
      expect(intent.activityType, 'hike');
      expect(intent.primaryImpressions, containsAll([
        ImpressionTag.prakticky,
        ImpressionTag.funkcny,
      ]));
    });

    test('„grilovačka u kamarátov“ → pohodlný, uvoľnený', () {
      final intent = StylistIntentResolver.resolve(
        conversationText: 'grilovačka u kamarátov',
      );
      expect(intent.activityType, 'barbecue');
      expect(intent.primaryImpressions, containsAll([
        ImpressionTag.pohodlny,
        ImpressionTag.uvolneny,
      ]));
    });

    test('„večer mám rande“ → upravený, sympatický', () {
      final intent = StylistIntentResolver.resolve(
        conversationText: 'večer mám rande',
      );
      expect(intent.activityType, 'date');
      expect(intent.primaryImpressions, containsAll([
        ImpressionTag.upraveny,
        ImpressionTag.sympaticky,
      ]));
    });
  });

  group('OutfitIntent builder (M1b/M1c)', () {
    test('Svadba → šortky forbidden, nohavice preferred, elegantná obuv', () {
      final intent = outfitIntentFor(
        conversationText: 'večer idem na svadbu',
        weather: weather(tempC: 28, season: 'let'),
      );
      expect(intent.activityType, 'wedding');
      expect(intent.bottomForbidden, contains('shorts'));
      expect(intent.bottomPreferred.first, 'pants');
      expect(intent.footwearPreferred.first, 'formal_shoes');
      expect(intent.footwearForbidden, contains('sandals'));
      expect(intent.nonNegotiables, contains('bottom_shorts_forbidden'));
      expect(intent.nonNegotiables, contains('formal_closed_footwear_preferred'));
    });

    test('Turistika → nohavice/joggers preferred, rifle discouraged, tenisky', () {
      final intent = outfitIntentFor(
        conversationText: 'idem do hory',
        weather: weather(tempC: 18, season: 'let'),
      );
      expect(intent.activityType, 'hike');
      expect(intent.bottomPreferred, containsAll(['pants', 'joggers']));
      expect(intent.bottomPreferred, isNot(contains('jeans')));
      expect(intent.footwearPreferred, contains('sneakers'));
      expect(intent.footwearForbidden, contains('sandals'));
      expect(intent.nonNegotiables, contains('hike_jeans_discouraged'));
    });

    test('Hubovanie → praktická uzavretá obuv, wet ground aware', () {
      final intent = outfitIntentFor(
        conversationText: 'idem na huby',
        weather: weather(tempC: 16, season: 'let'),
        wetGroundMuddy: true,
      );
      expect(intent.activityType, 'mushroom');
      expect(intent.footwearPreferred, contains('sneakers'));
      expect(intent.footwearForbidden, contains('sandals'));
      expect(intent.nonNegotiables, contains('wet_ground_closed_footwear'));
      expect(intent.nonNegotiables, contains('mushroom_practical_footwear'));
    });

    test('Pohovor → šortky forbidden, nohavice + uzavretá obuv', () {
      final intent = outfitIntentFor(
        conversationText: 'idem na pohovor',
        weather: weather(tempC: 26, season: 'let'),
      );
      expect(intent.activityType, 'interview');
      expect(intent.bottomForbidden, contains('shorts'));
      expect(intent.bottomPreferred, contains('pants'));
      expect(intent.footwearPreferred.first, 'formal_shoes');
      expect(intent.nonNegotiables, contains('bottom_shorts_forbidden'));
    });

    test('Práca → rifle/nohavice preferred, šortky discouraged', () {
      final intent = outfitIntentFor(
        conversationText: 'čo si mám obliecť dnes do práce',
        weather: weather(tempC: 28, season: 'let'),
      );
      expect(intent.activityType, 'work');
      expect(intent.bottomPreferred, contains('jeans'));
      expect(intent.bottomPreferred, contains('pants'));
      expect(intent.bottomForbidden, contains('shorts'));
      expect(intent.nonNegotiables, contains('bottom_shorts_forbidden'));
    });

    test('Grilovačka pri teple → pohodlný casual, šortky povolené', () {
      final intent = outfitIntentFor(
        conversationText: 'grilovačka u kamarátov',
        weather: weather(tempC: 28, season: 'let'),
      );
      expect(intent.activityType, 'barbecue');
      expect(intent.bottomForbidden, isNot(contains('shorts')));
      expect(intent.bottomPreferred, contains('shorts'));
      expect(intent.topPreference, 'casual_top');
      expect(intent.nonNegotiables, contains('barbecue_comfort_first'));
    });

    test('„Idem na grilovačku“ → barbecue, šortky v poole', () {
      final intent = outfitIntentFor(
        conversationText: 'Idem na grilovačku',
        weather: weather(tempC: 26, season: 'let'),
      );
      expect(intent.activityType, 'barbecue');
      expect(intent.bottomForbidden, isNot(contains('shorts')));
      expect(intent.bottomPreferred, contains('shorts'));
    });

    test('preferred a forbidden sú vždy disjunktné', () {
      final prompts = [
        ('večer idem na svadbu', weather(tempC: 28, season: 'let'), false),
        ('idem na pohovor', weather(tempC: 26, season: 'let'), false),
        ('idem do hory', weather(tempC: 18, season: 'let'), false),
        ('idem na huby', weather(tempC: 16, season: 'let'), true),
        ('čo si mám obliecť dnes do práce', weather(tempC: 28, season: 'let'), false),
        ('grilovačka u kamarátov', weather(tempC: 28, season: 'let'), false),
      ];
      for (final (prompt, w, wet) in prompts) {
        final intent = outfitIntentFor(
          conversationText: prompt,
          weather: w,
          wetGroundMuddy: wet,
        );
        expect(
          intent.bottomPreferred.toSet().intersection(intent.bottomForbidden.toSet()),
          isEmpty,
          reason: 'bottom overlap for: $prompt',
        );
        expect(
          intent.footwearPreferred.toSet().intersection(intent.footwearForbidden.toSet()),
          isEmpty,
          reason: 'footwear overlap for: $prompt',
        );
      }
    });

    test('Svadba → iba formal_shoes preferred, sneakers nie forbidden', () {
      final intent = outfitIntentFor(
        conversationText: 'večer idem na svadbu',
        weather: weather(tempC: 28, season: 'let'),
      );
      expect(intent.footwearPreferred, ['formal_shoes']);
      expect(intent.footwearForbidden, isNot(contains('sneakers')));
      expect(intent.footwearForbidden, isNot(contains('formal_shoes')));
    });

    test('Turistika pri mokrom teréne → shorts nie sú preferred', () {
      final intent = outfitIntentFor(
        conversationText: 'idem do hory',
        weather: weather(tempC: 22, season: 'let'),
        wetGroundMuddy: true,
      );
      expect(intent.bottomPreferred, isNot(contains('shorts')));
    });
  });

  group('OutfitIntent scorer (M2)', () {
    test('Svadba + šortky → vyradené cez non-negotiable', () {
      final intent = outfitIntentFor(
        conversationText: 'večer idem na svadbu',
        weather: weather(tempC: 28, season: 'let'),
      );
      final shortsOutfit = previewWith(
        bottomName: 'Kraťasy',
        bottomCanonical: 'shorts',
        shoesName: 'Lodičky',
        shoesCanonical: 'formal_shoes',
        topName: 'Košeľa',
        topCanonical: 'shirt',
      );
      final pantsOutfit = previewWith(
        bottomName: 'Nohavice',
        bottomCanonical: 'pants',
        shoesName: 'Lodičky',
        shoesCanonical: 'formal_shoes',
        topName: 'Košeľa',
        topCanonical: 'shirt',
      );
      final shortsScore = OutfitIntentScorer.evaluate(
        preview: shortsOutfit,
        intent: intent,
        baseScore: 0.8,
      );
      final pantsScore = OutfitIntentScorer.evaluate(
        preview: pantsOutfit,
        intent: intent,
        baseScore: 0.8,
      );
      expect(shortsScore.isExcluded, isTrue);
      expect(shortsScore.violatedNonNegotiables, isNotEmpty);
      expect(pantsScore.isExcluded, isFalse);
      expect(pantsScore.finalScore, greaterThan(shortsScore.finalScore));
    });

    test('Pohovor + šortky → vyradené', () {
      final intent = outfitIntentFor(
        conversationText: 'idem na pohovor',
        weather: weather(tempC: 26, season: 'let'),
      );
      final score = OutfitIntentScorer.evaluate(
        preview: previewWith(
          bottomName: 'Kraťasy',
          bottomCanonical: 'shorts',
          shoesName: 'Lodičky',
          shoesCanonical: 'formal_shoes',
        ),
        intent: intent,
        baseScore: 0.9,
      );
      expect(score.isExcluded, isTrue);
    });

    test('Turistika → joggers vyhrajú nad rifle', () {
      final intent = outfitIntentFor(
        conversationText: 'idem do hory',
        weather: weather(tempC: 18, season: 'let'),
      );
      final jeansScore = OutfitIntentScorer.evaluate(
        preview: previewWith(
          bottomName: 'Rifle',
          bottomCanonical: 'jeans',
          shoesName: 'Tenisky',
          shoesCanonical: 'sneakers',
        ),
        intent: intent,
        baseScore: 0.85,
      );
      final joggersScore = OutfitIntentScorer.evaluate(
        preview: previewWith(
          bottomName: 'Tepláky',
          bottomCanonical: 'joggers',
          shoesName: 'Tenisky',
          shoesCanonical: 'sneakers',
        ),
        intent: intent,
        baseScore: 0.85,
      );
      expect(joggersScore.finalScore, greaterThan(jeansScore.finalScore));
      expect(jeansScore.intentPenalty, greaterThan(0));
    });

    test('Hubovanie + sandále → vyradené pri mokrej pôde', () {
      final intent = outfitIntentFor(
        conversationText: 'idem na huby',
        weather: weather(tempC: 16, season: 'let'),
        wetGroundMuddy: true,
      );
      final sandalsScore = OutfitIntentScorer.evaluate(
        preview: previewWith(
          bottomName: 'Nohavice',
          bottomCanonical: 'pants',
          shoesName: 'Sandále',
          shoesCanonical: 'sandals',
        ),
        intent: intent,
        baseScore: 0.9,
      );
      final sneakersScore = OutfitIntentScorer.evaluate(
        preview: previewWith(
          bottomName: 'Nohavice',
          bottomCanonical: 'pants',
          shoesName: 'Tenisky',
          shoesCanonical: 'sneakers',
        ),
        intent: intent,
        baseScore: 0.9,
      );
      expect(sandalsScore.isExcluded, isTrue);
      expect(sneakersScore.isExcluded, isFalse);
      expect(sneakersScore.finalScore, greaterThan(sandalsScore.finalScore));
    });

    test('Práca → nohavice/rifle pred šortkami', () {
      final intent = outfitIntentFor(
        conversationText: 'čo si mám obliecť dnes do práce',
        weather: weather(tempC: 28, season: 'let'),
      );
      final shortsScore = OutfitIntentScorer.evaluate(
        preview: previewWith(
          bottomName: 'Kraťasy',
          bottomCanonical: 'shorts',
          shoesName: 'Tenisky',
          shoesCanonical: 'sneakers',
          topName: 'Polo',
          topCanonical: 'polo_shirt',
        ),
        intent: intent,
        baseScore: 0.95,
      );
      final jeansScore = OutfitIntentScorer.evaluate(
        preview: previewWith(
          bottomName: 'Rifle',
          bottomCanonical: 'jeans',
          shoesName: 'Tenisky',
          shoesCanonical: 'sneakers',
          topName: 'Polo',
          topCanonical: 'polo_shirt',
        ),
        intent: intent,
        baseScore: 0.85,
      );
      expect(shortsScore.isExcluded, isTrue);
      expect(jeansScore.isExcluded, isFalse);
      expect(jeansScore.finalScore, greaterThan(0.8));
    });

    test('Grilovačka → pohodlný casual outfit ostáva povolený', () {
      final intent = outfitIntentFor(
        conversationText: 'grilovačka u kamarátov',
        weather: weather(tempC: 28, season: 'let'),
      );
      final casualScore = OutfitIntentScorer.evaluate(
        preview: previewWith(
          bottomName: 'Kraťasy',
          bottomCanonical: 'shorts',
          shoesName: 'Tenisky',
          shoesCanonical: 'sneakers',
          topName: 'Tričko',
          topCanonical: 't_shirt',
        ),
        intent: intent,
        baseScore: 0.9,
      );
      expect(casualScore.isExcluded, isFalse);
      expect(casualScore.matchedIntent, contains('barbecue_comfort_first'));
      expect(casualScore.finalScore, greaterThan(0.9));
    });

    test('Svadba + tenisky a tričko → penalizácia mimo preferred', () {
      final intent = outfitIntentFor(
        conversationText: 'večer idem na svadbu',
        weather: weather(tempC: 22, season: 'let'),
      );
      final formalOutfit = OutfitIntentScorer.evaluate(
        preview: previewWith(
          bottomName: 'Nohavice',
          bottomCanonical: 'pants',
          shoesName: 'Oxfordky',
          shoesCanonical: 'formal_shoes',
          topName: 'Košeľa',
          topCanonical: 'shirt',
        ),
        intent: intent,
        baseScore: 0.8,
      );
      final casualOutfit = OutfitIntentScorer.evaluate(
        preview: previewWith(
          bottomName: 'Nohavice',
          bottomCanonical: 'pants',
          shoesName: 'Tenisky',
          shoesCanonical: 'sneakers',
          topName: 'Tričko',
          topCanonical: 't_shirt',
        ),
        intent: intent,
        baseScore: 0.8,
      );
      expect(formalOutfit.intentPenalty, lessThan(casualOutfit.intentPenalty));
      expect(formalOutfit.finalScore, greaterThan(casualOutfit.finalScore));
      expect(
        casualOutfit.matchedIntent.any(
          (tag) =>
              tag.startsWith('footwear_not_preferred:') ||
              tag.startsWith('top_eligibility:') ||
              tag == 'top_compromise',
        ) ||
            casualOutfit.matchedIntent.contains('top_compromise') ||
            casualOutfit.matchedIntent.any(
              (tag) => tag.startsWith('top_eligibility:'),
            ),
        isTrue,
      );
    });
  });

  group('Wardrobe gap analysis', () {
    test('svadba bez košele: tričko compromise + gap shirt', () {
      final intent = OutfitIntent(
        activityType: 'wedding',
        idealSummarySk: '',
        bottomPreferred: const ['pants'],
        bottomForbidden: const ['shorts'],
        footwearPreferred: const ['formal_shoes'],
        footwearForbidden: const [],
        topPreference: 'shirt_or_blouse',
      );
      final wardrobe = [
        {
          'id': 'tee1',
          'name': 'Čisté tričko',
          'canonical_type': 't_shirt',
          'layer_role': 'main_top',
        },
        {
          'id': 'p1',
          'canonical_type': 'pants',
          'layer_role': 'bottom',
          'name': 'Nohavice',
        },
        {
          'id': 's1',
          'canonical_type': 'sneakers',
          'layer_role': 'footwear',
          'name': 'Tenisky',
        },
      ];
      final previews = OutfitGenerationService.generateCandidatePreviews(
        wardrobeItems: wardrobe,
        weather: weather(tempC: 22, season: 'let'),
        outfitIntent: intent,
        limit: 2,
      );
      expect(previews, isNotEmpty);
      final analysis = WardrobeGapAnalysis.analyze(
        wardrobe: wardrobe,
        intent: intent,
        preview: previews.first,
        weather: weather(tempC: 22, season: 'let'),
      );
      expect(analysis.usedCompromise, isTrue);
      expect(
        analysis.missingItems.any((g) => g.category == 'shirt'),
        isTrue,
      );
      expect(analysis.compromiseItems, isNotEmpty);
    });
  });

  group('ItemEligibility — top', () {
    OutfitIntent intentFor({
      required String activityType,
      required String topPreference,
    }) {
      return OutfitIntent(
        activityType: activityType,
        idealSummarySk: '',
        bottomPreferred: const [],
        bottomForbidden: const [],
        footwearPreferred: const [],
        footwearForbidden: const [],
        topPreference: topPreference,
      );
    }

    test('svadba: košeľa preferred, tričko compromise', () {
      final intent = intentFor(
        activityType: 'wedding',
        topPreference: 'shirt_or_blouse',
      );
      expect(
        OutfitIntentScorer.classifyTopEligibility(
          item: {'name': 'Košeľa', 'canonical_type': 'shirt'},
          intent: intent,
        ).eligibility,
        ItemEligibility.preferred,
      );
      expect(
        OutfitIntentScorer.classifyTopEligibility(
          item: {'name': 'Tričko', 'canonical_type': 't_shirt'},
          intent: intent,
        ).eligibility,
        ItemEligibility.compromise,
      );
    });

    test('práca: polo preferred, tričko compromise, tielko forbidden', () {
      final intent = intentFor(
        activityType: 'work',
        topPreference: 'polo_or_shirt',
      );
      expect(
        OutfitIntentScorer.classifyTopEligibility(
          item: {'name': 'Polo', 'canonical_type': 'polo'},
          intent: intent,
        ).eligibility,
        ItemEligibility.preferred,
      );
      expect(
        OutfitIntentScorer.classifyTopEligibility(
          item: {'name': 'Tričko', 'canonical_type': 't_shirt'},
          intent: intent,
        ).eligibility,
        ItemEligibility.compromise,
      );
      expect(
        OutfitIntentScorer.classifyTopEligibility(
          item: {
            'name': 'Tielko',
            'subCategory': 'tielko',
            'layer_role': 'main_top',
          },
          intent: intent,
        ).eligibility,
        ItemEligibility.forbidden,
      );
    });

    test('pohovor: grafické tričko forbidden', () {
      final intent = intentFor(
        activityType: 'interview',
        topPreference: 'shirt_or_blouse',
      );
      expect(
        OutfitIntentScorer.classifyTopEligibility(
          item: {'name': 'Logo tričko', 'canonical_type': 't_shirt'},
          intent: intent,
        ).eligibility,
        ItemEligibility.forbidden,
      );
    });
  });

  group('Intent-first matrix (M3)', () {
    IntentMatrixWavePlan planFor(String conversationText) {
      final snap = weather(tempC: 20, season: 'leto');
      final intent = outfitIntentFor(
        conversationText: conversationText,
        weather: snap,
      );
      final spec = DressCodeResolver.resolve(
        conversationText: conversationText,
        tempC: snap.tempC,
      );
      final profile =
          StylistOccasionProfile(dressCode: spec, tempC: snap.tempC);
      final bottomGuidance = StylistOccasionGuidance.bottomGuidanceFor(
        weather: snap,
        profile: profile,
      );
      final footwearGuidance = StylistOccasionGuidance.footwearGuidanceFor(
        weather: snap,
        profile: profile,
      );
      return StylistIntentMatrixGenerator.planWaves(
        intent: intent,
        bottomGuidance: bottomGuidance,
        footwearGuidance: footwearGuidance,
      );
    }

    test('svadba → pants preferred, jeans fallback, shorts nie v pláne', () {
      final plan = planFor('idem na svadbu');
      expect(plan.bottomPreferred, contains('pants'));
      expect(plan.bottomPreferred, isNot(contains('shorts')));
      expect(plan.bottomFallback, contains('jeans'));
      expect(
        [
          ...plan.bottomPreferred,
          ...plan.bottomFallback,
          ...plan.bottomCompromise,
        ],
        isNot(contains('shorts')),
      );
      expect(plan.footwearPreferred, contains('formal_shoes'));
    });

    test('turistika → pants pred joggers, jeans fallback, shorts compromise', () {
      final plan = planFor('ideme na turistiku do Tatier');
      expect(plan.bottomPreferred.indexOf('pants'),
          lessThan(plan.bottomPreferred.indexOf('joggers')));
      expect(plan.bottomPreferred, contains('pants'));
      expect(plan.bottomPreferred, contains('joggers'));
      expect(plan.bottomFallback, contains('jeans'));
      expect(plan.bottomCompromise, contains('shorts'));
    });

    test('grilovačka → shorts preferred', () {
      final plan = planFor('grilovačka u kamarátov');
      expect(plan.bottomPreferred.first, 'shorts');
    });

    test('compromise sa preskočí keď existuje preferred šatník (M3c)', () {
      final snap = weather(tempC: 20, season: 'leto');
      final intent = outfitIntentFor(
        conversationText: 'idem na svadbu',
        weather: snap,
      );
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem na svadbu',
        tempC: snap.tempC,
      );
      final profile =
          StylistOccasionProfile(dressCode: spec, tempC: snap.tempC);
      final bottomGuidance = StylistOccasionGuidance.bottomGuidanceFor(
        weather: snap,
        profile: profile,
      );
      final footwearGuidance = StylistOccasionGuidance.footwearGuidanceFor(
        weather: snap,
        profile: profile,
      );
      final plan = StylistIntentMatrixGenerator.planWaves(
        intent: intent,
        bottomGuidance: bottomGuidance,
        footwearGuidance: footwearGuidance,
      );
      final wardrobe = [
        {
          'id': 'p1',
          'canonical_type': 'pants',
          'name': 'Nohavice',
          'layer_role': 'bottom',
        },
        {
          'id': 's1',
          'canonical_type': 'formal_shoes',
          'name': 'Oxfordky',
          'layer_role': 'shoes',
        },
      ];
      expect(
        StylistIntentMatrixGenerator.preferredOutfitPossible(
          wardrobe: wardrobe,
          plan: plan,
          intent: intent,
          excludedItemIds: const {},
        ),
        isTrue,
      );
    });

    test('diversity penalizuje opakovaný vrch (M3d)', () {
      final preview = previewWith(
        bottomName: 'Nohavice',
        bottomCanonical: 'pants',
        shoesName: 'Oxfordky',
        shoesCanonical: 'formal_shoes',
        topName: 'Čierne tričko',
        topCanonical: 't_shirt',
      );
      preview.top.item['id'] = 'top-black';
      final penalty = StylistIntentMatrixGenerator.diversityPenaltyForPreview(
        preview: preview,
        usedTopIds: {'top-black'},
        usedBottomIds: {},
        usedFootwearIds: {},
      );
      expect(penalty, greaterThan(0));
    });
  });

  group('Intent-first matrix pools (M4)', () {
    test('preferred vlna nájde spodok aj keď chýba formálna obuv', () {
      final snap = weather(tempC: 22, season: 'let');
      final intent = outfitIntentFor(
        conversationText: 'idem na svadbu',
        weather: snap,
      );
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem na svadbu',
        tempC: snap.tempC,
      );
      final profile = StylistOccasionProfile(dressCode: spec, tempC: snap.tempC);
      final plan = StylistIntentMatrixGenerator.planWaves(
        intent: intent,
        bottomGuidance: StylistOccasionGuidance.bottomGuidanceFor(
          weather: snap,
          profile: profile,
        ),
        footwearGuidance: StylistOccasionGuidance.footwearGuidanceFor(
          weather: snap,
          profile: profile,
        ),
      );
      final wardrobe = [
        {
          'id': 'p1',
          'canonical_type': 'pants',
          'name': 'Nohavice',
          'layer_role': 'bottom',
          'categoryKey': 'bottoms',
        },
        {
          'id': 's1',
          'canonical_type': 'sneakers',
          'name': 'Tenisky',
          'layer_role': 'footwear',
          'categoryKey': 'shoes',
        },
      ];
      final pools = StylistIntentMatrixGenerator.resolveWavePoolsForTest(
        wave: MatrixGenerationWave.preferred,
        plan: plan,
        wardrobe: wardrobe,
        bottomForbidden: intent.bottomForbidden.toSet(),
        footwearForbidden: intent.footwearForbidden.toSet(),
        excludedItemIds: const {},
      );
      expect(pools.bottomIds, contains('p1'));
      expect(pools.footwearIds, contains('s1'));
    });
  });

  group('Candidate pipeline (M4)', () {
    OutfitPreview previewAt({
      required String topId,
      required String bottomId,
      required String shoeId,
      String topName = 'Top',
      String bottomName = 'Bottom',
      String shoeName = 'Shoes',
    }) {
      return OutfitPreview(
        top: OutfitPreviewItem(
          type: OutfitWearType.top,
          item: {
            'id': topId,
            'name': topName,
            'canonical_type': 't_shirt',
          },
          label: topName,
          imageUrl: null,
        ),
        bottom: OutfitPreviewItem(
          type: OutfitWearType.bottom,
          item: {
            'id': bottomId,
            'name': bottomName,
            'canonical_type': 'pants',
          },
          label: bottomName,
          imageUrl: null,
        ),
        shoes: OutfitPreviewItem(
          type: OutfitWearType.shoes,
          item: {
            'id': shoeId,
            'name': shoeName,
            'canonical_type': 'sneakers',
          },
          label: shoeName,
          imageUrl: null,
        ),
        outerwear: null,
      );
    }

    String topId(OutfitPreview preview) =>
        OutfitGenerationService.wardrobeItemId(preview.top.item);
    String bottomId(OutfitPreview preview) =>
        OutfitGenerationService.wardrobeItemId(preview.bottom.item);
    String shoeId(OutfitPreview preview) =>
        OutfitGenerationService.wardrobeItemId(preview.shoes.item);

    ScoredOutfitCandidate scored({
      required OutfitPreview preview,
      required int matrixIndex,
      required double finalScore,
      double comfort = 0.8,
    }) {
      return ScoredOutfitCandidate(
        preview: preview,
        comfort: comfort,
        finalScore: finalScore,
        intentBonus: 1,
        intentPenalty: 0,
        baseScore: comfort,
        ids: {topId(preview), bottomId(preview), shoeId(preview)},
        signature: OutfitGenerationService.combinationSignature(
          preview.top.item,
          preview.bottom.item,
          preview.shoes.item,
          preview.outerwear?.item,
        ),
        matrixIndex: matrixIndex,
      );
    }

    test('6 matrix kandidátov → 4 do final review bez comfort pásma', () {
      final matrix = <OutfitPreview>[
        for (var i = 0; i < 6; i++)
          previewAt(
            topId: 'top$i',
            bottomId: 'bottom$i',
            shoeId: 'shoe$i',
            topName: 'Top $i',
          ),
      ];
      final scoredCandidates = [
        for (var i = 0; i < 6; i++)
          scored(
            preview: matrix[i],
            matrixIndex: i,
            finalScore: 1.0 - i * 0.05,
            comfort: 0.9 - i * 0.02,
          ),
      ];

      final result = StylistChatCandidatePipeline.selectForFinalReview(
        matrixPreviews: matrix,
        scoredCandidates: scoredCandidates,
      );

      expect(result.matrixGenerated, 6);
      expect(result.afterFiltering, 6);
      expect(result.forFinalReview.length, 4);
      expect(result.forFinalReview.first.matrixIndex, 0);
    });

    test('duplicate_items sa zaloguje a neposiela sa do final review', () {
      final p1 = previewAt(topId: 't1', bottomId: 'b1', shoeId: 's1');
      final p2 = previewAt(topId: 't1', bottomId: 'b1', shoeId: 's1');
      final p3 = previewAt(topId: 't2', bottomId: 'b2', shoeId: 's2');
      final matrix = [p1, p2, p3];
      final scoredCandidates = [
        scored(preview: p1, matrixIndex: 0, finalScore: 1.0),
        scored(preview: p2, matrixIndex: 1, finalScore: 0.95),
        scored(preview: p3, matrixIndex: 2, finalScore: 0.9),
      ];

      final result = StylistChatCandidatePipeline.selectForFinalReview(
        matrixPreviews: matrix,
        scoredCandidates: scoredCandidates,
      );

      expect(result.afterFiltering, 2);
      expect(result.forFinalReview.length, 2);
    });
  });

  group('Matrix space (M6)', () {
    List<OutfitPreview> matrixFor({
      required String conversationText,
      required List<Map<String, dynamic>> wardrobe,
      required OutfitWeatherSnapshot weather,
      bool wetGroundMuddy = false,
    }) {
      final stylistIntent = StylistIntentResolver.resolve(
        conversationText: conversationText,
        tempC: weather.tempC,
      );
      final spec = DressCodeResolver.resolve(
        conversationText: conversationText,
        tempC: weather.tempC,
      );
      final profile =
          StylistOccasionProfile(dressCode: spec, tempC: weather.tempC);
      final bottomGuidance = StylistOccasionGuidance.bottomGuidanceFor(
        weather: weather,
        profile: profile,
      );
      final footwearGuidance = StylistOccasionGuidance.footwearGuidanceFor(
        weather: weather,
        profile: profile,
        wetGroundMuddy: wetGroundMuddy,
      );
      final outfitIntent = OutfitIntentBuilder.build(
        stylistIntent: stylistIntent,
        dressCode: spec,
        bottomGuidance: bottomGuidance,
        footwearGuidance: footwearGuidance,
        wetGroundMuddy: wetGroundMuddy,
      );
      final bottomInventory = bottomFamilyInventoryFromWardrobe(wardrobe);
      final footwearInventory = footwearFamilyInventoryFromWardrobe(wardrobe);
      final preferredBottomExists =
          bottomInventory.hasPreferred(bottomGuidance);
      final preferredFootwearExists =
          footwearInventory.hasPreferred(footwearGuidance);

      return StylistIntentMatrixGenerator.generateCandidates(
        wardrobe: wardrobe,
        weather: weather,
        outfitIntent: outfitIntent,
        bottomGuidance: bottomGuidance,
        footwearGuidance: footwearGuidance,
        excludedItemIds: const {},
        preferredBottomExists: preferredBottomExists,
        preferredFootwearExists: preferredFootwearExists,
        isPreferredBottom: preferredBottomExists
            ? (p) => !previewHasDiscouragedBottom(
                  preview: p,
                  guidance: bottomGuidance,
                )
            : null,
        isPreferredFootwear: preferredFootwearExists
            ? (p) => !previewHasDiscouragedFootwear(
                  preview: p,
                  guidance: footwearGuidance,
                )
            : null,
        isDiscouragedBottom: (p) => previewHasDiscouragedBottom(
          preview: p,
          guidance: bottomGuidance,
        ),
        isDiscouragedFootwear: (p) => previewHasDiscouragedFootwear(
          preview: p,
          guidance: footwearGuidance,
        ),
        passesLayerHarmony: (p) => previewPassesLayerHarmonyGuard(
          preview: p,
          tempC: weather.tempC,
          log: false,
        ),
      );
    }

    test('formal shoes v intent poole sú aj v shoes poole', () {
      final formal = {
        'id': 'fs1',
        'canonical_type': 'formal_shoes',
        'name': 'Oxford',
        'layer_role': 'footwear',
        'categoryKey': 'shoes',
      };
      expect(isFootwearWardrobeItem(formal), isTrue);

      final snap = weather(tempC: 20, season: 'jese');
      final intent = outfitIntentFor(
        conversationText: 'idem na svadbu',
        weather: snap,
      );
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem na svadbu',
        tempC: snap.tempC,
      );
      final profile =
          StylistOccasionProfile(dressCode: spec, tempC: snap.tempC);
      final footwearGuidance = StylistOccasionGuidance.footwearGuidanceFor(
        weather: snap,
        profile: profile,
      );
      final plan = StylistIntentMatrixGenerator.planWaves(
        intent: intent,
        bottomGuidance: StylistOccasionGuidance.bottomGuidanceFor(
          weather: snap,
          profile: profile,
        ),
        footwearGuidance: footwearGuidance,
      );
      final wardrobe = [
        formal,
        {
          'id': 'p1',
          'canonical_type': 'pants',
          'layer_role': 'bottom',
          'name': 'Nohavice',
        },
        {
          'id': 't1',
          'canonical_type': 'shirt',
          'layer_role': 'main_top',
          'name': 'Košeľa',
        },
      ];
      final pools = StylistIntentMatrixGenerator.resolveWavePoolsForTest(
        wave: MatrixGenerationWave.preferred,
        plan: plan,
        wardrobe: wardrobe,
        bottomForbidden: intent.bottomForbidden.toSet(),
        footwearForbidden: intent.footwearForbidden.toSet(),
        excludedItemIds: const {},
      );
      expect(pools.footwearIds, contains('fs1'));

      final previews = OutfitGenerationService.generateCandidatePreviews(
        wardrobeItems: wardrobe,
        weather: snap,
        allowedShoeItemIds: pools.footwearIds,
        allowedBottomItemIds: pools.bottomIds,
        limit: 2,
      );
      expect(
        previews.any(
          (p) => OutfitGenerationService.wardrobeItemId(p.shoes.item) == 'fs1',
        ),
        isTrue,
      );
    });

    test('svadba bez použiteľných formal shoes → pants + sneakers fallback', () {
      final snap = weather(tempC: 22, season: 'let');
      final wardrobe = [
        {
          'id': 'p1',
          'canonical_type': 'pants',
          'layer_role': 'bottom',
          'name': 'Nohavice',
          'categoryKey': 'bottoms',
        },
        {
          'id': 's1',
          'canonical_type': 'sneakers',
          'layer_role': 'footwear',
          'name': 'Tenisky',
          'categoryKey': 'shoes',
        },
        {
          'id': 't1',
          'canonical_type': 'shirt',
          'layer_role': 'main_top',
          'name': 'Košeľa',
        },
        {
          'id': 't2',
          'canonical_type': 't_shirt',
          'layer_role': 'main_top',
          'name': 'Tričko',
        },
      ];
      final candidates = matrixFor(
        conversationText: 'idem na svadbu',
        wardrobe: wardrobe,
        weather: snap,
      );
      expect(candidates, isNotEmpty);
      expect(
        candidates.every(
          (p) => OutfitGenerationService.wardrobeItemId(p.top.item) == 't1',
        ),
        isTrue,
      );
      expect(
        candidates.any(
          (p) =>
              OutfitGenerationService.wardrobeItemId(p.bottom.item) == 'p1' &&
              OutfitGenerationService.wardrobeItemId(p.shoes.item) == 's1',
        ),
        isTrue,
      );
    });

    test('hike bez pants/joggers → jeans fallback, nie shorts', () {
      final snap = weather(tempC: 18, season: 'jese', rain: true);
      final wardrobe = [
        {
          'id': 'j1',
          'canonical_type': 'jeans',
          'layer_role': 'bottom',
          'name': 'Rifle',
        },
        {
          'id': 'sh1',
          'canonical_type': 'shorts',
          'layer_role': 'bottom',
          'name': 'Šortky',
        },
        {
          'id': 'b1',
          'canonical_type': 'boots',
          'layer_role': 'footwear',
          'name': 'Čižmy',
        },
        {
          'id': 't1',
          'canonical_type': 't_shirt',
          'layer_role': 'main_top',
          'name': 'Tričko 1',
        },
        {
          'id': 't2',
          'canonical_type': 't_shirt',
          'layer_role': 'main_top',
          'name': 'Tričko 2',
        },
      ];
      final candidates = matrixFor(
        conversationText: 'idem na túru',
        wardrobe: wardrobe,
        weather: snap,
        wetGroundMuddy: true,
      );
      expect(candidates, isNotEmpty);
      expect(
        candidates.every(
          (p) =>
              classifyBottomFamily(p.bottom.item) != BottomFamily.shorts,
        ),
        isTrue,
      );
      expect(
        candidates.any(
          (p) => OutfitGenerationService.wardrobeItemId(p.bottom.item) == 'j1',
        ),
        isTrue,
      );
    });

    test('grilovačka: generuje outfit so šortkami', () {
      final snap = weather(tempC: 26, season: 'let');
      final wardrobe = [
        {
          'id': 't1',
          'name': 'Čisté biele tričko',
          'canonical_type': 't_shirt',
          'layer_role': 'main_top',
        },
        {
          'id': 'sh1',
          'name': 'Tmavé šortky',
          'canonical_type': 'shorts',
          'layer_role': 'bottom',
        },
        {
          'id': 'sn1',
          'name': 'Biele tenisky',
          'canonical_type': 'sneakers',
          'layer_role': 'footwear',
        },
      ];
      final candidates = matrixFor(
        conversationText: 'Idem na grilovačku',
        wardrobe: wardrobe,
        weather: snap,
      );
      expect(candidates, isNotEmpty);
      expect(
        candidates.any(
          (p) =>
              OutfitGenerationService.wardrobeItemId(p.bottom.item) == 'sh1',
        ),
        isTrue,
      );
    });

    test('diversity pri 1 bottom + 1 shoes vytvorí viac top variantov', () {
      final snap = weather(tempC: 22, season: 'let');
      final wardrobe = [
        {
          'id': 'b1',
          'canonical_type': 'pants',
          'layer_role': 'bottom',
          'name': 'Nohavice',
        },
        {
          'id': 's1',
          'canonical_type': 'sneakers',
          'layer_role': 'footwear',
          'name': 'Tenisky',
        },
        for (var i = 1; i <= 4; i++)
          {
            'id': 't$i',
            'canonical_type': 't_shirt',
            'layer_role': 'main_top',
            'name': 'Tričko $i',
          },
      ];
      final candidates = matrixFor(
        conversationText: 'idem do práce',
        wardrobe: wardrobe,
        weather: snap,
      );
      final topIds = candidates
          .map((p) => OutfitGenerationService.wardrobeItemId(p.top.item))
          .toSet();
      expect(candidates.length, greaterThanOrEqualTo(4));
      expect(topIds.length, greaterThanOrEqualTo(2));
    });

    test('svadba: sivé nohavice nie sú discouraged_bottom podľa OutfitIntent', () {
      final snap = weather(tempC: 22, season: 'let');
      final intent = outfitIntentFor(
        conversationText: 'idem na svadbu',
        weather: snap,
      );
      final wardrobe = [
        {
          'id': 'p1',
          'canonical_type': 'pants',
          'layer_role': 'bottom',
          'name': 'Sivé nohavice',
          'categoryKey': 'bottoms',
        },
        {
          'id': 's1',
          'canonical_type': 'sneakers',
          'layer_role': 'footwear',
          'name': 'Tenisky',
        },
        {
          'id': 't1',
          'canonical_type': 'shirt',
          'layer_role': 'main_top',
          'name': 'Košeľa',
        },
        {
          'id': 't2',
          'canonical_type': 't_shirt',
          'layer_role': 'main_top',
          'name': 'Tričko',
        },
      ];
      final previews = OutfitGenerationService.generateCandidatePreviews(
        wardrobeItems: wardrobe,
        weather: snap,
        bottomPreferredFamilies: intent.bottomPreferred,
        bottomForbiddenFamilies: intent.bottomForbidden,
        footwearPreferredFamilies: intent.footwearPreferred,
        footwearForbiddenFamilies: intent.footwearForbidden,
        topPreference: intent.topPreference,
        activityType: intent.activityType,
        logMatrixPoolDebug: true,
        limit: 4,
      );
      expect(previews, isNotEmpty);
      expect(
        previews.every(
          (p) =>
              OutfitGenerationService.wardrobeItemId(p.bottom.item) == 'p1',
        ),
        isTrue,
      );
      expect(
        classifyBottomFamily(previews.first.bottom.item),
        BottomFamily.pants,
      );
    });

    test('svadba: formal mimo matrix shoe pool neblokuje sneakers', () {
      final snap = weather(tempC: 22, season: 'let');
      final spec = DressCodeResolver.resolve(
        conversationText: 'idem na svadbu',
        tempC: snap.tempC,
      );
      final profile =
          StylistOccasionProfile(dressCode: spec, tempC: snap.tempC);
      final footwearGuidance = StylistOccasionGuidance.footwearGuidanceFor(
        weather: snap,
        profile: profile,
      );
      final wardrobe = [
        {
          'id': 'fs1',
          'canonical_type': 'formal_shoes',
          'layer_role': 'footwear',
          'name': 'Oxford',
        },
        {
          'id': 'sn1',
          'canonical_type': 'sneakers',
          'layer_role': 'footwear',
          'name': 'Tenisky',
        },
        {
          'id': 'p1',
          'canonical_type': 'pants',
          'layer_role': 'bottom',
          'name': 'Nohavice',
        },
        for (var i = 1; i <= 4; i++)
          {
            'id': 't$i',
            'canonical_type': 'shirt',
            'layer_role': 'main_top',
            'name': 'Košeľa $i',
          },
      ];
      final previews = OutfitGenerationService.generateCandidatePreviews(
        wardrobeItems: wardrobe,
        weather: snap,
        allowedShoeItemIds: {'sn1'},
        allowedBottomItemIds: {'p1'},
        preferredFootwearExists: true,
        footwearGuidance: footwearGuidance,
        bottomPreferredFamilies: const ['pants'],
        bottomForbiddenFamilies: const ['shorts', 'joggers', 'other'],
        isDiscouragedFootwear: (p) => previewHasDiscouragedFootwear(
          preview: p,
          guidance: footwearGuidance,
        ),
        logMatrixPoolDebug: true,
        limit: 4,
      );
      expect(previews, isNotEmpty);
      expect(
        previews.every(
          (p) => OutfitGenerationService.wardrobeItemId(p.shoes.item) == 'sn1',
        ),
        isTrue,
      );
    });

    test('matrix nekompiluje duplicitné core outfity s rôznym outer', () {
      final snap = weather(tempC: 16, season: 'jese');
      final wardrobe = [
        {
          'id': 't1',
          'canonical_type': 'shirt',
          'layer_role': 'main_top',
          'name': 'Košeľa',
        },
        {
          'id': 'p1',
          'canonical_type': 'pants',
          'layer_role': 'bottom',
          'name': 'Nohavice',
        },
        {
          'id': 's1',
          'canonical_type': 'sneakers',
          'layer_role': 'footwear',
          'name': 'Tenisky',
        },
        {
          'id': 'o1',
          'canonical_type': 'blazer',
          'layer_role': 'outer_layer',
          'name': 'Sako',
        },
        {
          'id': 'o2',
          'canonical_type': 'jacket',
          'layer_role': 'outer_layer',
          'name': 'Bunda',
        },
      ];
      final previews = OutfitGenerationService.generateCandidatePreviews(
        wardrobeItems: wardrobe,
        weather: snap,
        logMatrixPoolDebug: true,
        limit: 6,
      );
      final coreSigs = previews
          .map(
            (p) => OutfitGenerationService.coreCombinationSignature(
              p.top.item,
              p.bottom.item,
              p.shoes.item,
            ),
          )
          .toList();
      expect(coreSigs.toSet().length, coreSigs.length);
    });

    test('topPreference shirt_or_blouse uprednostní košeľu pred basic tričkom', () {
      final shirt = {
        'id': 'shirt1',
        'name': 'Biela košeľa',
        'canonical_type': 'shirt',
        'layer_role': 'main_top',
      };
      final tee = {
        'id': 'tee1',
        'name': 'Čierne basic tričko',
        'canonical_type': 't_shirt',
        'layer_role': 'main_top',
        'colors': ['black'],
      };
      expect(
        OutfitIntentScorer.topPoolScoreAdjustment(
          topPreference: 'shirt_or_blouse',
          item: shirt,
          activityType: 'work',
        ),
        greaterThan(
          OutfitIntentScorer.topPoolScoreAdjustment(
            topPreference: 'shirt_or_blouse',
            item: tee,
            activityType: 'work',
          ),
        ),
      );

      final snap = weather(tempC: 20, season: 'jese');
      final wardrobe = [
        shirt,
        tee,
        {
          'id': 'p1',
          'canonical_type': 'pants',
          'layer_role': 'bottom',
          'name': 'Nohavice',
        },
        {
          'id': 's1',
          'canonical_type': 'sneakers',
          'layer_role': 'footwear',
          'name': 'Tenisky',
        },
      ];
      final pools = OutfitGenerationService.collectGenerationPools(
        wardrobeItems: wardrobe,
        weather: snap,
        topPreference: 'shirt_or_blouse',
        activityType: 'work',
      );
      expect(pools, isNotNull);
      expect(
        OutfitGenerationService.wardrobeItemId(pools!.tops.first),
        'shirt1',
      );
      final poolTopIds = pools.tops
          .map(OutfitGenerationService.wardrobeItemId)
          .toList();
      final teeIdx = poolTopIds.indexOf('tee1');
      final shirtIdx = poolTopIds.indexOf('shirt1');
      if (teeIdx >= 0) {
        expect(shirtIdx, lessThan(teeIdx));
      }

      final previews = OutfitGenerationService.generateCandidatePreviews(
        wardrobeItems: wardrobe,
        weather: snap,
        topPreference: 'shirt_or_blouse',
        activityType: 'work',
        limit: 4,
      );
      expect(previews, isNotEmpty);
      expect(
        OutfitGenerationService.wardrobeItemId(previews.first.top.item),
        'shirt1',
      );
    });
  });

  group('Návrh mesta pri preklepe (StylistCitySuggester)', () {
    test('"Norinberg" → navrhne "Norimberg"', () {
      expect(StylistCitySuggester.suggestCorrection('Norinberg'), 'Norimberg');
    });

    test('Známe mesto "Mníchov" → žiadny návrh (netreba opravovať)', () {
      expect(StylistCitySuggester.suggestCorrection('Mníchov'), isNull);
    });

    test('Nezmysel → žiadny návrh', () {
      expect(StylistCitySuggester.suggestCorrection('xyzqwerty'), isNull);
    });
  });
}
