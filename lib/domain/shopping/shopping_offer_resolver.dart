import 'catalog_models.dart';
import 'shopping_money.dart';

class EffectivePublicPrice {
  const EffectivePublicPrice({
    required this.price,
    required this.requiresPublicCoupon,
    this.couponCode,
  });

  final ShoppingMoney price;
  final bool requiresPublicCoupon;
  final String? couponCode;
}

abstract final class EffectivePricePolicy {
  /// Returns the lowest single-item public price only.
  ///
  /// Membership and bundle promotions are intentionally ignored.
  static EffectivePublicPrice resolve(CatalogOffer offer) {
    var best = EffectivePublicPrice(
      price: offer.regularPrice,
      requiresPublicCoupon: false,
    );
    for (final promotion in offer.promotions) {
      if (promotion.kind != PromotionKind.publicSale &&
          promotion.kind != PromotionKind.publicCoupon) {
        continue;
      }
      final candidate = EffectivePublicPrice(
        price: promotion.price,
        requiresPublicCoupon: promotion.kind == PromotionKind.publicCoupon,
        couponCode: promotion.code,
      );
      if (candidate.price < best.price) best = candidate;
    }
    return best;
  }
}

class BestOfferRequest {
  BestOfferRequest({
    this.selectedSizeKeys = const {},
    this.preferredSizeKey,
    this.availableNow = false,
    this.maxPrice,
  }) : assert(
         preferredSizeKey == null ||
             selectedSizeKeys.contains(preferredSizeKey),
       );

  final Set<String> selectedSizeKeys;
  final String? preferredSizeKey;
  final bool availableNow;
  final ShoppingMoney? maxPrice;
}

class BestOfferResolution {
  const BestOfferResolution({
    required this.offer,
    required this.effectivePrice,
    required this.sizeAvailability,
    required this.selectedSizeKey,
    required this.purchasableForSelectedSize,
  });

  final CatalogOffer offer;
  final EffectivePublicPrice effectivePrice;
  final SizeAvailability? sizeAvailability;
  final String? selectedSizeKey;
  final bool purchasableForSelectedSize;
}

abstract final class BestOfferResolver {
  static BestOfferResolution? resolve({
    required String variantId,
    required Iterable<CatalogOffer> offers,
    required Iterable<SizeAvailability> sizes,
    required BestOfferRequest request,
  }) {
    final allSizes = sizes.where((size) => size.offerId.isNotEmpty).toList();
    final candidates = <_Candidate>[];
    for (final offer in offers) {
      if (offer.variantId != variantId ||
          offer.lifecycleState == CatalogLifecycleState.discontinued) {
        continue;
      }
      final price = EffectivePricePolicy.resolve(offer);
      if (request.maxPrice != null && price.price > request.maxPrice!) continue;
      final offeredSizes = allSizes.where(
        (size) => size.offerId == offer.offerId,
      );
      final sizeChoice = _chooseSize(offeredSizes, request);
      final isPurchasable =
          offer.overallAvailability == CatalogAvailability.available &&
          (request.selectedSizeKeys.isEmpty ||
              sizeChoice?.availability == CatalogAvailability.available);
      if (request.availableNow && !isPurchasable) continue;
      candidates.add(
        _Candidate(
          offer: offer,
          price: price,
          size: sizeChoice,
          purchasable: isPurchasable,
          preferenceRank: _preferenceRank(sizeChoice, request),
        ),
      );
    }
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) {
      if (left.preferenceRank != right.preferenceRank) {
        return left.preferenceRank.compareTo(right.preferenceRank);
      }
      if (left.purchasable != right.purchasable) {
        return left.purchasable ? -1 : 1;
      }
      return left.price.price.compareTo(right.price.price);
    });
    final winner = candidates.first;
    return BestOfferResolution(
      offer: winner.offer,
      effectivePrice: winner.price,
      sizeAvailability: winner.size,
      selectedSizeKey: winner.size?.normalizedSizeKey,
      purchasableForSelectedSize: winner.purchasable,
    );
  }

  static SizeAvailability? _chooseSize(
    Iterable<SizeAvailability> available,
    BestOfferRequest request,
  ) {
    if (request.selectedSizeKeys.isEmpty) return null;
    final selected = available
        .where(
          (size) => request.selectedSizeKeys.contains(size.normalizedSizeKey),
        )
        .toList();
    if (selected.isEmpty) return null;
    selected.sort((left, right) {
      final leftRank = _sizeRank(left, request);
      final rightRank = _sizeRank(right, request);
      if (leftRank != rightRank) return leftRank.compareTo(rightRank);
      return left.normalizedSizeKey.compareTo(right.normalizedSizeKey);
    });
    return selected.first;
  }

  static int _preferenceRank(
    SizeAvailability? size,
    BestOfferRequest request,
  ) => size == null ? 0 : _sizeRank(size, request);

  static int _sizeRank(SizeAvailability size, BestOfferRequest request) {
    if (size.normalizedSizeKey == request.preferredSizeKey) return 0;
    return 1;
  }
}

class _Candidate {
  const _Candidate({
    required this.offer,
    required this.price,
    required this.size,
    required this.purchasable,
    required this.preferenceRank,
  });

  final CatalogOffer offer;
  final EffectivePublicPrice price;
  final SizeAvailability? size;
  final bool purchasable;
  final int preferenceRank;
}
