import 'catalog_models.dart';
import 'shopping_money.dart';

enum WishlistPriceState { unknown, unsatisfied, satisfied }

enum WishlistSizeState { unknown, unavailable, available }

enum WishlistEventType {
  priceTargetSatisfied,
  priceTargetUnsatisfied,
  sizeAvailable,
  sizeUnavailable,
}

class WishlistItem {
  WishlistItem({
    required this.wishlistItemId,
    required this.variantId,
    required this.selectedSizeKeys,
    required this.targetPrice,
    required this.priceMonitoringEnabled,
    required this.sizeMonitoringEnabled,
    this.preferredSizeKey,
    this.createdAt,
    this.updatedAt,
  }) : assert(
         preferredSizeKey == null ||
             selectedSizeKeys.contains(preferredSizeKey),
       );

  final String wishlistItemId, variantId;
  final Set<String> selectedSizeKeys;
  final String? preferredSizeKey;
  final ShoppingMoney targetPrice;
  final bool priceMonitoringEnabled, sizeMonitoringEnabled;
  final DateTime? createdAt, updatedAt;
}

class WishlistEvent {
  const WishlistEvent({
    required this.type,
    required this.wishlistItemId,
    this.sizeKey,
  });

  final WishlistEventType type;
  final String wishlistItemId;
  final String? sizeKey;

  bool get qualifiesForGoldHighlight =>
      type == WishlistEventType.priceTargetSatisfied ||
      type == WishlistEventType.sizeAvailable;
}

class WishlistTrackingState {
  const WishlistTrackingState({
    required this.priceState,
    required this.sizeStates,
    this.freshness = const CatalogFreshness(),
  });

  final WishlistPriceState priceState;
  final Map<String, WishlistSizeState> sizeStates;
  final CatalogFreshness freshness;

  factory WishlistTrackingState.initial(WishlistItem item) =>
      WishlistTrackingState(
        priceState: WishlistPriceState.unknown,
        sizeStates: {
          for (final size in item.selectedSizeKeys)
            size: WishlistSizeState.unknown,
        },
      );
}

class WishlistTrackingEvaluation {
  const WishlistTrackingEvaluation({required this.state, required this.events});

  final WishlistTrackingState state;
  final List<WishlistEvent> events;

  bool get goldEligible =>
      events.any((event) => event.qualifiesForGoldHighlight);
}

abstract final class WishlistTrackingEvaluator {
  /// A failed refresh changes freshness only. It never changes a target state.
  static WishlistTrackingEvaluation markRefreshFailure({
    required WishlistTrackingState previous,
  }) => WishlistTrackingEvaluation(
    state: WishlistTrackingState(
      priceState: previous.priceState,
      sizeStates: previous.sizeStates,
      freshness: previous.freshness.markRefreshFailure(),
    ),
    events: const [],
  );

  static WishlistTrackingEvaluation evaluateKnownSnapshot({
    required WishlistItem item,
    required WishlistTrackingState previous,
    required ShoppingMoney? effectivePublicPrice,
    required Map<String, CatalogAvailability> selectedSizeAvailability,
    required CatalogFreshness freshness,
  }) {
    final events = <WishlistEvent>[];
    final nextPrice = _priceState(item, effectivePublicPrice);
    if (previous.priceState != WishlistPriceState.unknown &&
        nextPrice != previous.priceState) {
      events.add(
        WishlistEvent(
          wishlistItemId: item.wishlistItemId,
          type: nextPrice == WishlistPriceState.satisfied
              ? WishlistEventType.priceTargetSatisfied
              : WishlistEventType.priceTargetUnsatisfied,
        ),
      );
    }
    final nextSizes = <String, WishlistSizeState>{};
    for (final key in item.selectedSizeKeys) {
      final next = _sizeState(selectedSizeAvailability[key]);
      final old = previous.sizeStates[key] ?? WishlistSizeState.unknown;
      nextSizes[key] = next;
      if (old == WishlistSizeState.unknown ||
          next == WishlistSizeState.unknown) {
        continue;
      }
      if (old != next) {
        events.add(
          WishlistEvent(
            wishlistItemId: item.wishlistItemId,
            sizeKey: key,
            type: next == WishlistSizeState.available
                ? WishlistEventType.sizeAvailable
                : WishlistEventType.sizeUnavailable,
          ),
        );
      }
    }
    return WishlistTrackingEvaluation(
      state: WishlistTrackingState(
        priceState: nextPrice,
        sizeStates: nextSizes,
        freshness: freshness,
      ),
      events: List.unmodifiable(events),
    );
  }

  static WishlistPriceState _priceState(
    WishlistItem item,
    ShoppingMoney? price,
  ) {
    if (price == null) {
      return WishlistPriceState.unknown;
    }
    if (price.currency != item.targetPrice.currency) {
      return WishlistPriceState.unknown;
    }
    return price <= item.targetPrice
        ? WishlistPriceState.satisfied
        : WishlistPriceState.unsatisfied;
  }

  static WishlistSizeState _sizeState(CatalogAvailability? availability) =>
      switch (availability) {
        CatalogAvailability.available => WishlistSizeState.available,
        CatalogAvailability.unavailable => WishlistSizeState.unavailable,
        CatalogAvailability.unknown || null => WishlistSizeState.unknown,
      };
}
