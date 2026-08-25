import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/shopping/catalog_models.dart';
import 'package:outfitofTheDay/domain/shopping/shopping_money.dart';
import 'package:outfitofTheDay/domain/shopping/wishlist_tracking.dart';

WishlistPriceState _price(String raw) => switch (raw.toLowerCase()) {
  'satisfied' => WishlistPriceState.satisfied,
  'unsatisfied' => WishlistPriceState.unsatisfied,
  _ => WishlistPriceState.unknown,
};

WishlistSizeState _size(String raw) => switch (raw.toLowerCase()) {
  'available' => WishlistSizeState.available,
  'unavailable' => WishlistSizeState.unavailable,
  _ => WishlistSizeState.unknown,
};

WishlistEventType _eventType(String raw) => switch (raw) {
  'priceTargetSatisfied' || 'PRICE_TARGET_SATISFIED' =>
    WishlistEventType.priceTargetSatisfied,
  'priceTargetUnsatisfied' || 'PRICE_TARGET_UNSATISFIED' =>
    WishlistEventType.priceTargetUnsatisfied,
  'sizeAvailable' || 'SIZE_AVAILABLE' => WishlistEventType.sizeAvailable,
  'sizeUnavailable' || 'SIZE_UNAVAILABLE' => WishlistEventType.sizeUnavailable,
  _ => throw StateError('unknown event $raw'),
};

void main() {
  test('Dart oracle matches shared wishlist tracking parity fixtures', () {
    final file = File('test/fixtures/wishlist_tracking_parity_cases.json');
    final cases = (jsonDecode(file.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    expect(cases, isNotEmpty);

    for (final entry in cases) {
      // Discontinued evidence-preservation cases are Node-engine specific
      // extensions beyond the Phase 1 Dart snapshot evaluator.
      final id = entry['id']?.toString() ?? '';
      if (id.startsWith('discontinued_')) continue;

      final target = Map<String, dynamic>.from(entry['targetPrice'] as Map);
      final previous = Map<String, dynamic>.from(entry['previous'] as Map);
      final observation = Map<String, dynamic>.from(
        entry['observation'] as Map,
      );
      final sizeStates = Map<String, dynamic>.from(
        previous['sizeStates'] as Map? ?? const {},
      );
      final item = WishlistItem(
        wishlistItemId: entry['wishlistItemId']?.toString() ?? 'wish_parity',
        variantId: entry['variantId']?.toString() ?? 'variant_parity',
        selectedSizeKeys: sizeStates.keys.toSet(),
        preferredSizeKey: entry['preferredSizeKey']?.toString(),
        targetPrice: ShoppingMoney(
          amountMinor: target['amountMinor'] as int,
          currency: target['currency'] as String,
        ),
        priceMonitoringEnabled: true,
        sizeMonitoringEnabled: true,
      );

      if (observation['successful'] == false) {
        final result = WishlistTrackingEvaluator.markRefreshFailure(
          previous: WishlistTrackingState(
            priceState: _price(previous['priceState']?.toString() ?? 'unknown'),
            sizeStates: {
              for (final MapEntry(:key, :value) in sizeStates.entries)
                key: _size(value.toString()),
            },
          ),
        );
        expect(result.events, isEmpty, reason: id);
        expect(result.goldEligible, isFalse, reason: id);
        continue;
      }

      final observedSizes = Map<String, dynamic>.from(
        observation['sizeStates'] as Map? ?? const {},
      );
      final result = WishlistTrackingEvaluator.evaluateKnownSnapshot(
        item: item,
        previous: WishlistTrackingState(
          priceState: _price(previous['priceState']?.toString() ?? 'unknown'),
          sizeStates: {
            for (final MapEntry(:key, :value) in sizeStates.entries)
              key: _size(value.toString()),
          },
        ),
        effectivePublicPrice: observation['effectivePublicPrice'] == null
            ? null
            : ShoppingMoney(
                amountMinor:
                    (observation['effectivePublicPrice']
                        as Map)['amountMinor'] as int,
                currency:
                    (observation['effectivePublicPrice'] as Map)['currency']
                        as String,
              ),
        selectedSizeAvailability: {
          for (final key in item.selectedSizeKeys)
            key: switch (_size(observedSizes[key]?.toString() ?? 'unknown')) {
              WishlistSizeState.available => CatalogAvailability.available,
              WishlistSizeState.unavailable => CatalogAvailability.unavailable,
              WishlistSizeState.unknown => CatalogAvailability.unknown,
            },
        },
        freshness: const CatalogFreshness(),
      );

      final expected =
          ((entry['expectedEventTypes'] as List?) ?? const [])
              .map((value) => _eventType(value.toString()))
              .toList();
      expect(result.events.map((event) => event.type).toList(), expected,
          reason: id);
      expect(result.goldEligible, entry['expectedGold'] == true, reason: id);
    }
  });
}
