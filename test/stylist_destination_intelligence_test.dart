import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/data/parsed_destination.dart';
import 'package:outfitofTheDay/utils/stylist_destination_parser.dart';

void main() {
  group('StylistDestinationIntelligence — typy destinácií', () {
    test('city — konkrétne mesto', () {
      final p = StylistDestinationParser.parseDestination(
        'Zajtra idem do Washingtonu, potrebujem outfit.',
      );
      expect(p.type, DestinationType.city);
      expect(p.needsClarification, isFalse);
      expect(p.weatherCity, 'Washington');
    });

    test('country — USA bez mesta', () {
      final p = StylistDestinationParser.parseDestination(
        'Zajtra ideme do USA, potrebujem outfit.',
      );
      expect(p.type, DestinationType.country);
      expect(p.needsClarification, isTrue);
      expect(p.weatherCity, isNull);
      expect(p.clarificationQuestionSk, contains('mesta'));
    });

    test('country — Nórsko bez mesta', () {
      final p = StylistDestinationParser.parseDestination(
        'Ideme do Nórska, potrebujem outfit.',
      );
      expect(p.type, DestinationType.country);
      expect(p.needsClarification, isTrue);
      expect(p.weatherCity, isNull);
    });

    test('region — Toskánsko bez mesta', () {
      final p = StylistDestinationParser.parseDestination(
        'Ideme do Toskánska, potrebujem outfit.',
      );
      expect(p.type, DestinationType.region);
      expect(p.needsClarification, isTrue);
      expect(p.clarificationQuestionSk, contains('Toskánsku'));
    });

    test('pointOfInterest bez mesta — ZOO', () {
      final p = StylistDestinationParser.parseDestination(
        'Idem do ZOO, potrebujem outfit.',
      );
      expect(p.type, DestinationType.pointOfInterest);
      expect(p.needsClarification, isTrue);
      expect(p.weatherCity, isNull);
      expect(p.clarificationQuestionSk, contains('meste'));
    });

    test('pointOfInterest s mestom — Zoo Praha', () {
      final p = StylistDestinationParser.parseDestination(
        'Ideme do Zoo Praha, potrebujem outfit.',
      );
      expect(
        p.type,
        anyOf(DestinationType.pointOfInterest, DestinationType.city),
      );
      expect(p.needsClarification, isFalse);
      expect(p.weatherCity, 'Praha');
    });

    test('venue bez mesta — nákupné centrum', () {
      final p = StylistDestinationParser.parseDestination(
        'Ideme do nákupného centra, potrebujem outfit.',
      );
      expect(
        p.type,
        anyOf(DestinationType.venue, DestinationType.pointOfInterest),
      );
      expect(p.needsClarification, isTrue);
    });

    test('venue bez mesta — Aupark ako neznámy názov', () {
      final p = StylistDestinationParser.parseDestination(
        'Idem do Auparku, potrebujem outfit.',
      );
      expect(
        p.type,
        anyOf(DestinationType.pointOfInterest, DestinationType.venue),
      );
      expect(p.needsClarification, isTrue);
    });

    test('airport bez špecifikácie', () {
      final p = StylistDestinationParser.parseDestination(
        'Zajtra idem na letisko, potrebujem outfit.',
      );
      expect(p.type, DestinationType.airport);
      expect(p.needsClarification, isTrue);
      expect(p.clarificationQuestionSk, contains('letisko'));
    });

    test('airport s mestom', () {
      final p = StylistDestinationParser.parseDestination(
        'Idem na letisko v Prahe, potrebujem outfit.',
      );
      expect(p.type, DestinationType.airport);
      expect(p.needsClarification, isFalse);
      expect(p.weatherCity, 'Praha');
    });

    test('unknown — neznámy názov', () {
      final p = StylistDestinationParser.parseDestination(
        'Ideme do VinWonders, potrebujem outfit.',
      );
      expect(p.needsClarification, isTrue);
      expect(p.weatherCity, isNull);
    });

    test('none — žiadna cestovná destinácia', () {
      final p = StylistDestinationParser.parseDestination(
        'Potrebujem outfit na rande.',
      );
      expect(p.type, DestinationType.none);
      expect(p.needsClarification, isFalse);
    });

    test('country + city — USA a New York', () {
      final p = StylistDestinationParser.parseDestination(
        'Ideme do USA do New Yorku, potrebujem outfit.',
      );
      expect(p.needsClarification, isFalse);
      expect(p.weatherCity, 'New York');
    });

    test('inferFromConversation nevracia krajinu ako mesto', () {
      expect(
        StylistDestinationParser.inferFromConversation(
          'Ideme do Nórska, potrebujem outfit.',
        ),
        isNull,
      );
    });

    test('inferFromConversation nevracia ZOO ako mesto', () {
      expect(
        StylistDestinationParser.inferFromConversation(
          'Idem do ZOO, potrebujem outfit.',
        ),
        isNull,
      );
    });

    test('do satnika is wardrobe, not a travel POI', () {
      final p = StylistDestinationParser.parseDestination(
        'Pozri do satnika. Navrhni outfit okolo bielej klasickej koselie.',
      );
      expect(p.needsClarification, isFalse);
      expect(p.hasTravelDestination, isFalse);
      expect(p.type, DestinationType.none);
    });

    test('košeľa with diacritics is not a travel destination', () {
      final p = StylistDestinationParser.parseDestination(
        'Navrhni outfit okolo bielej klasickej košele na dnes o 18:00.',
      );
      expect(p.hasTravelDestination, isFalse);
      expect(p.type, DestinationType.none);
    });

    test('real city destination still parses', () {
      final p = StylistDestinationParser.parseDestination(
        'Idem do Washingtonu, potrebujem outfit.',
      );
      expect(p.hasTravelDestination, isTrue);
      expect(p.weatherCity, isNotNull);
    });
  });
}
