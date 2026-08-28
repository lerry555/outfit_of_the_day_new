import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/Services/stylist_travel_request_enricher.dart';
import 'package:outfitofTheDay/models/outfit_context_state.dart';
import 'package:outfitofTheDay/models/stylist_resolved_location.dart';
import 'package:outfitofTheDay/utils/stylist_travel_context.dart';
import 'package:outfitofTheDay/utils/stylist_travel_endpoints.dart';

void main() {
  group('StylistTravelContextResolver', () {
    test('transit outfit is semantic and independent of destination name', () {
      for (final destination in <String>[
        'USA',
        'Poľska',
        'Japonska',
        'Nového Zélandu',
        'Qwertystanu',
      ]) {
        final text =
            'V pondelok letím do $destination a neviem čo si mám obliecť do lietadla.';
        final travel = StylistTravelContextResolver.resolve(text);
        expect(travel.scope, StylistTravelScope.transit, reason: destination);
        expect(travel.transportMode, StylistTransportMode.air, reason: destination);
        expect(travel.transitOutfitExplicit, isTrue, reason: destination);
        expect(
          travel.destinationRequiredForPrimaryOutfit,
          isFalse,
          reason: destination,
        );

        final state = OutfitContextState.buildFrom(
          conversation: text,
          latestUserText: text,
          gpsCityLabel: 'Martin',
        );
        expect(state.activityHint, 'travel', reason: destination);
        expect(state.travelScope, 'transit', reason: destination);
        expect(state.unresolvedMaterialFields, isEmpty, reason: destination);
        expect(state.groundingStatus, 'sufficient', reason: destination);
      }
    });

    test('transport mention plus outfit does not silently mean transit', () {
      const cases = <String, StylistTransportMode>{
        'Za pol hodinu idem autom do Berlína, potrebujem outfit.':
            StylistTransportMode.road,
        'Zajtra idem vlakom do Prahy, potrebujem outfit.':
            StylistTransportMode.rail,
        'V pondelok letím do Londýna, potrebujem outfit.':
            StylistTransportMode.air,
        'Ráno idem trajektom na druhú stranu, potrebujem outfit.':
            StylistTransportMode.sea,
      };
      for (final entry in cases.entries) {
        final travel = StylistTravelContextResolver.resolve(entry.key);
        expect(travel.transportMode, entry.value, reason: entry.key);
        expect(travel.outfitRequestPresent, isTrue, reason: entry.key);
        expect(travel.transitOutfitExplicit, isFalse, reason: entry.key);
        expect(travel.scope, StylistTravelScope.unknown, reason: entry.key);
        expect(travel.scopeNeedsClarification, isTrue, reason: entry.key);
      }
    });

    test('ambiguous road trip asks purpose even when destination is provider verified', () {
      const text =
          'Za pol hodinu idem autom do Berlína, potrebujem outfit.';
      const berlin = StylistResolvedLocation(
        evidence: 'Berlína',
        query: 'Berlin',
        displayName: 'Berlin, Germany',
        weatherLabel: 'Berlin',
        country: 'Germany',
        latitude: 52.52,
        longitude: 13.405,
        granularity: StylistResolvedLocationGranularity.locality,
      );

      final state = OutfitContextState.buildFrom(
        conversation: text,
        latestUserText: text,
        gpsCityLabel: 'Martin',
        resolvedLocation: berlin,
        preferProviderLocation: true,
      );

      expect(state.activityLocationLabel, 'Berlin');
      expect(state.travelScope, 'unknown');
      expect(state.travelScopeNeedsClarification, isTrue);
      expect(state.unresolvedMaterialFields, ['trip_scope']);
      expect(state.groundingStatus, 'needs_grounding');
    });

    test('explicit transit wording works for every supported transport family', () {
      const cases = <String, StylistTransportMode>{
        'Potrebujem pohodlný outfit do auta, po príchode idem do hotela.':
            StylistTransportMode.road,
        'Čo si mám obliecť do vlaku?': StylistTransportMode.rail,
        'Čo si mám obliecť do lietadla?': StylistTransportMode.air,
        'Potrebujem outfit na trajekt.': StylistTransportMode.sea,
      };
      for (final entry in cases.entries) {
        final travel = StylistTravelContextResolver.resolve(entry.key);
        expect(travel.transportMode, entry.value, reason: entry.key);
        expect(travel.transitOutfitExplicit, isTrue, reason: entry.key);
        expect(travel.scope, StylistTravelScope.transit, reason: entry.key);
        expect(travel.scopeNeedsClarification, isFalse, reason: entry.key);
      }
    });

    test('explicit destination activity makes travel destination-scoped', () {
      final travel = StylistTravelContextResolver.resolve(
        'Idem autom do Berlína na koncert a potrebujem outfit.',
      );

      expect(travel.transportMode, StylistTransportMode.road);
      expect(travel.transitOutfitExplicit, isFalse);
      expect(travel.destinationUseExplicit, isTrue);
      expect(travel.scope, StylistTravelScope.destination);
      expect(travel.destinationRequiredForPrimaryOutfit, isTrue);
    });

    test('transit plus arrival activity becomes mixed', () {
      final travel = StylistTravelContextResolver.resolve(
        'Chcem outfit do auta a po príchode idem rovno na koncert.',
      );

      expect(travel.transitOutfitExplicit, isTrue);
      expect(travel.destinationUseExplicit, isTrue);
      expect(travel.scope, StylistTravelScope.mixed);
    });

    test('destination outfit keeps destination material at the scope layer', () {
      final travel = StylistTravelContextResolver.resolve(
        'V pondelok cestujem niekam preč a chcem vedieť čo si mám obliecť na mieste.',
      );

      expect(travel.scope, StylistTravelScope.destination);
      expect(travel.transitOutfitExplicit, isFalse);
      expect(travel.destinationRequiredForPrimaryOutfit, isTrue);
    });

    test('arrival and departure timing preserve minutes', () {
      final travel = StylistTravelContextResolver.resolve(
        'Odlietame o 15:35 a pristávame okolo 17:10. Čo do lietadla?',
      );
      expect(travel.transportMode, StylistTransportMode.air);
      expect(travel.departureHourLocal, 15);
      expect(travel.departureMinuteLocal, 35);
      expect(travel.arrivalHourLocal, 17);
      expect(travel.arrivalMinuteLocal, 10);
      expect(travel.arrivalWeatherCouldHelp, isTrue);
    });

    test('relative departure supports compound offsets', () {
      final travel = StylistTravelContextResolver.resolve(
        'Za 1 hodinu 20 minút vyrážam autom, potrebujem outfit do auta.',
      );
      expect(travel.departureOffsetMinutes, 80);
      expect(travel.transportMode, StylistTransportMode.road);
    });

    test('generic outing is not silently upgraded to transit', () {
      final travel = StylistTravelContextResolver.resolve(
        'Zajtra ideme na výlet a potrebujem outfit.',
      );
      expect(travel.transitOutfitExplicit, isFalse);
      expect(travel.scope, StylistTravelScope.none);
    });
  });

  group('travel endpoint extraction', () {
    test('origin and destination are generic provider queries, not whitelists', () {
      for (final text in <String>[
        'Odlietam z Bratislavy do Londýna o 15:00.',
        'Idem z Martina do Berlína autom.',
        'Cestujem from Porto to Madrid o 9:30.',
      ]) {
        final endpoints = StylistTravelEndpointsExtractor.extract(text);
        expect(endpoints.origin, isNotNull, reason: text);
        expect(endpoints.destination, isNotNull, reason: text);
      }
      final flight = StylistTravelEndpointsExtractor.extract(
        'Odlietam z Bratislavy do Londýna o 15:00.',
      );
      expect(flight.origin!.query, 'Bratislavy');
      expect(flight.destination!.query, 'Londýna');
    });
  });

  group('derived travel timing', () {
    test('all supported transport modes can derive a rough duration', () {
      const distanceKm = 1000.0;
      for (final mode in <StylistTransportMode>[
        StylistTransportMode.road,
        StylistTransportMode.rail,
        StylistTransportMode.air,
        StylistTransportMode.sea,
      ]) {
        final minutes = StylistTravelRequestEnricher.estimateTravelDurationMinutes(
          mode,
          distanceKm,
        );
        expect(minutes, isNotNull, reason: mode.name);
        expect(minutes!, greaterThan(30), reason: mode.name);
        expect(
          StylistTravelRequestEnricher.estimateTravelUncertaintyMinutes(
            mode,
            minutes,
          ),
          greaterThan(0),
          reason: mode.name,
        );
      }
    });

    test('flight example applies timezone shift after duration estimate', () {
      // Rough Bratislava -> London distance. 15:00 at UTC+2 is 13:00 UTC.
      final duration = StylistTravelRequestEnricher.estimateTravelDurationMinutes(
        StylistTransportMode.air,
        1280,
      )!;
      final departureUtc = StylistTravelRequestEnricher.localWallClockToUtc(
        date: DateTime(2026, 8, 31),
        hour: 15,
        minute: 0,
        utcOffsetMinutes: 120,
      );
      final arrivalUtc = departureUtc.add(Duration(minutes: duration));
      final londonWallClock = arrivalUtc.add(const Duration(minutes: 60)).toUtc();

      expect(departureUtc.hour, 13);
      expect(duration, inInclusiveRange(150, 210));
      expect(londonWallClock.hour, inInclusiveRange(16, 17));
    });

    test('road estimate remains available through compatibility helper', () {
      final generic = StylistTravelRequestEnricher.estimateTravelDurationMinutes(
        StylistTransportMode.road,
        500,
      );
      final legacy = StylistTravelRequestEnricher.estimateRoadDurationMinutes(500);
      expect(legacy, generic);
    });
  });
}
