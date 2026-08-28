import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/models/outfit_context_state.dart';
import 'package:outfitofTheDay/models/stylist_resolved_location.dart';
import 'package:outfitofTheDay/utils/stylist_travel_context.dart';

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

    test('car mention plus outfit does not silently mean outfit for the car', () {
      const text =
          'Za pol hodinu idem autom do Berlína, potrebujem outfit.';
      final travel = StylistTravelContextResolver.resolve(text);

      expect(travel.transportMode, StylistTransportMode.road);
      expect(travel.outfitRequestPresent, isTrue);
      expect(travel.transitOutfitExplicit, isFalse);
      expect(travel.scope, StylistTravelScope.unknown);
      expect(travel.scopeNeedsClarification, isTrue);
      expect(travel.departureOffsetMinutes, 30);
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

    test('explicit car-only outfit is transit', () {
      final travel = StylistTravelContextResolver.resolve(
        'Potrebujem pohodlný outfit do auta, po príchode idem rovno do hotela.',
      );

      expect(travel.transportMode, StylistTransportMode.road);
      expect(travel.transitOutfitExplicit, isTrue);
      expect(travel.scope, StylistTravelScope.transit);
      expect(travel.scopeNeedsClarification, isFalse);
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

    test('arrival and departure timing are extracted by meaning, not airport names', () {
      final travel = StylistTravelContextResolver.resolve(
        'Odlet máme o 9:20 a pristávame okolo 12:45. Čo do lietadla?',
      );
      expect(travel.transportMode, StylistTransportMode.air);
      expect(travel.departureHourLocal, 9);
      expect(travel.arrivalHourLocal, 12);
      expect(travel.arrivalWeatherCouldHelp, isTrue);
    });

    test('generic outing is not silently upgraded to transit', () {
      final travel = StylistTravelContextResolver.resolve(
        'Zajtra ideme na výlet a potrebujem outfit.',
      );
      expect(travel.transitOutfitExplicit, isFalse);
      expect(travel.scope, StylistTravelScope.none);
    });
  });
}
