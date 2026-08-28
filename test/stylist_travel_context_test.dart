import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/models/outfit_context_state.dart';
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

    test('destination outfit still keeps destination material', () {
      final state = OutfitContextState.buildFrom(
        conversation:
            'V pondelok cestujem do Qwertystanu a chcem vedieť čo si mám obliecť na mieste.',
        latestUserText:
            'V pondelok cestujem do Qwertystanu a chcem vedieť čo si mám obliecť na mieste.',
        gpsCityLabel: 'Martin',
      );

      expect(state.travelScope, 'destination');
      expect(state.transitOutfitExplicit, isFalse);
      expect(state.unresolvedMaterialFields, contains('destination'));
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
