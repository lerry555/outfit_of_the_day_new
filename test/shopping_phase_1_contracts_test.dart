import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/shopping/shopping_phase_1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';

const eur20 = ShoppingMoney(amountMinor: 2000, currency: 'EUR');
const eur30 = ShoppingMoney(amountMinor: 3000, currency: 'EUR');
const eur39 = ShoppingMoney(amountMinor: 3900, currency: 'EUR');
const eur42 = ShoppingMoney(amountMinor: 4200, currency: 'EUR');
const eur45 = ShoppingMoney(amountMinor: 4500, currency: 'EUR');
const eur49 = ShoppingMoney(amountMinor: 4900, currency: 'EUR');
const eur50 = ShoppingMoney(amountMinor: 5000, currency: 'EUR');
const eur55 = ShoppingMoney(amountMinor: 5500, currency: 'EUR');

const navy = ColorProfileV2(
  primary: SemanticColorV2(family: 'navy'),
  metalTone: 'none',
  hardwareTone: 'none',
);

CatalogOffer offer(
  String id, {
  String variantId = 'navy',
  ShoppingMoney price = eur50,
  List<PublicPromotion> promotions = const [],
  CatalogAvailability availability = CatalogAvailability.available,
  CatalogLifecycleState lifecycle = CatalogLifecycleState.active,
}) => CatalogOffer(
  offerId: id,
  variantId: variantId,
  partnerId: 'store-$id',
  partnerListingId: 'listing-$id',
  url: 'https://store-$id.example/products/$id',
  regularPrice: price,
  promotions: promotions,
  overallAvailability: availability,
  lifecycleState: lifecycle,
);

SizeAvailability size(
  String offerId,
  String key,
  CatalogAvailability availability, {
  int? quantity,
  QuantityReliability reliability = QuantityReliability.unknown,
}) => SizeAvailability(
  offerId: offerId,
  normalizedSizeKey: key,
  partnerSizeLabel: key,
  sizeSystem: 'INTL',
  availability: availability,
  exactQuantity: quantity,
  quantityReliability: reliability,
);

WishlistItem wish({
  Set<String> sizes = const {'M'},
  String? preferredSize = 'M',
  ShoppingMoney target = eur20,
}) => WishlistItem(
  wishlistItemId: 'wish-1',
  variantId: 'navy',
  selectedSizeKeys: sizes,
  preferredSizeKey: preferredSize,
  targetPrice: target,
  priceMonitoringEnabled: true,
  sizeMonitoringEnabled: true,
);

void main() {
  group('catalog entity separation and identity', () {
    test('product excludes variant, offer, and size facts', () {
      const product = CatalogProduct(
        productId: 'hoodie-model',
        brand: 'Nike',
        normalizedModelIdentity: 'club-hoodie',
        canonicalType: 'hoodie',
        canonicalFamily: 'top',
        identityEvidence: CatalogIdentityEvidence(
          manufacturerModelId: 'CLUB-1',
        ),
      );
      final variant = CatalogProductVariant(
        variantId: 'hoodie-navy',
        productId: product.productId,
        exactColorName: 'Navy',
        colorProfile: navy,
        identityEvidence: CatalogIdentityEvidence(manufacturerSku: 'CLUB-1-NV'),
      );
      expect(product.productId, variant.productId);
      expect(variant.colorProfile.primary.family, 'navy');
      expect(offer('one').variantId, 'navy');
      expect(size('one', 'M', CatalogAvailability.available).offerId, 'one');
    });

    test(
      'strong evidence can merge but names and visual similarity cannot',
      () {
        const left = CatalogProduct(
          productId: 'left',
          brand: 'Nike',
          normalizedModelIdentity: 'club hoodie',
          canonicalType: 'hoodie',
          canonicalFamily: 'top',
          identityEvidence: CatalogIdentityEvidence(gtin: '123'),
        );
        const right = CatalogProduct(
          productId: 'right',
          brand: 'Nike',
          normalizedModelIdentity: 'club hoodie',
          canonicalType: 'hoodie',
          canonicalFamily: 'top',
          identityEvidence: CatalogIdentityEvidence(gtin: '123'),
        );
        const weak = CatalogProduct(
          productId: 'weak',
          brand: 'Nike',
          normalizedModelIdentity: 'club hoodie',
          canonicalType: 'hoodie',
          canonicalFamily: 'top',
          identityEvidence: CatalogIdentityEvidence(),
        );
        expect(CatalogIdentityPolicy.mayMergeProducts(left, right), isTrue);
        expect(CatalogIdentityPolicy.mayMergeProducts(left, weak), isFalse);
      },
    );

    test('variant identity needs variant strong evidence', () {
      const left = CatalogProductVariant(
        variantId: 'navy-a',
        productId: 'p',
        exactColorName: 'Navy',
        colorProfile: navy,
        identityEvidence: CatalogIdentityEvidence(manufacturerSku: 'NVY-1'),
      );
      const right = CatalogProductVariant(
        variantId: 'navy-b',
        productId: 'p',
        exactColorName: 'Navy',
        colorProfile: navy,
        identityEvidence: CatalogIdentityEvidence(manufacturerSku: 'NVY-1'),
      );
      const weak = CatalogProductVariant(
        variantId: 'blue-lookalike',
        productId: 'p',
        exactColorName: 'Blue',
        colorProfile: navy,
        identityEvidence: CatalogIdentityEvidence(),
      );
      expect(CatalogIdentityPolicy.mayMergeVariants(left, right), isTrue);
      expect(CatalogIdentityPolicy.mayMergeVariants(left, weak), isFalse);
    });
  });

  group('money and public effective price', () {
    test('compares minor units and rejects currency mismatch', () {
      expect(eur45 < eur50, isTrue);
      expect(
        () => eur50.compareTo(
          const ShoppingMoney(amountMinor: 5000, currency: 'USD'),
        ),
        throwsArgumentError,
      );
    });

    test('public sale and coupon qualify while retaining coupon code', () {
      final sale = EffectivePricePolicy.resolve(
        offer(
          'sale',
          promotions: const [PublicPromotion.publicSale(price: eur45)],
        ),
      );
      final coupon = EffectivePricePolicy.resolve(
        offer(
          'coupon',
          promotions: const [
            PublicPromotion.publicCoupon(price: eur45, code: 'NIKE10'),
          ],
        ),
      );
      expect(sale.price, eur45);
      expect(sale.requiresPublicCoupon, isFalse);
      expect(coupon.price, eur45);
      expect(coupon.requiresPublicCoupon, isTrue);
      expect(coupon.couponCode, 'NIKE10');
    });

    test('member and bundle promotions never lower normal effective price', () {
      final member = EffectivePricePolicy.resolve(
        offer(
          'member',
          price: eur55,
          promotions: const [PublicPromotion.memberOnly(price: eur45)],
        ),
      );
      final bundle = EffectivePricePolicy.resolve(
        offer(
          'bundle',
          price: eur30,
          promotions: const [
            PublicPromotion.bundle(price: eur20, description: '2+1 free'),
          ],
        ),
      );
      expect(member.price, eur55);
      expect(bundle.price, eur30);
    });
  });

  group('best exact-variant offer', () {
    test('chooses cheapest valid public exact-variant offer', () {
      final result = BestOfferResolver.resolve(
        variantId: 'navy',
        offers: [
          offer('a', price: eur49),
          offer('b', price: eur42),
          offer(
            'c',
            price: eur45,
            promotions: const [
              PublicPromotion.publicCoupon(price: eur39, code: 'SAVE'),
            ],
          ),
        ],
        sizes: [
          size('a', 'M', CatalogAvailability.available),
          size('b', 'M', CatalogAvailability.available),
          size('c', 'M', CatalogAvailability.available),
        ],
        request: BestOfferRequest(
          selectedSizeKeys: {'M'},
          preferredSizeKey: 'M',
        ),
      );
      expect(result!.offer.offerId, 'c');
      expect(result.effectivePrice.price, eur39);
      expect(result.effectivePrice.couponCode, 'SAVE');
    });

    test('never uses a white variant price or stock for navy', () {
      final result = BestOfferResolver.resolve(
        variantId: 'navy',
        offers: [
          offer('navy', price: eur49),
          offer('white', variantId: 'white', price: eur39),
        ],
        sizes: [
          size('navy', 'M', CatalogAvailability.available),
          size('white', 'M', CatalogAvailability.available),
        ],
        request: BestOfferRequest(
          selectedSizeKeys: {'M'},
          preferredSizeKey: 'M',
        ),
      );
      expect(result!.offer.offerId, 'navy');
      expect(result.effectivePrice.price, eur49);
    });

    test(
      'preferred size outranks secondary-size price when not available now',
      () {
        final result = BestOfferResolver.resolve(
          variantId: 'navy',
          offers: [
            offer('m', price: eur49),
            offer('l', price: eur39),
          ],
          sizes: [
            size('m', 'M', CatalogAvailability.unavailable),
            size('l', 'L', CatalogAvailability.available),
          ],
          request: BestOfferRequest(
            selectedSizeKeys: {'M', 'L'},
            preferredSizeKey: 'M',
          ),
        );
        expect(result!.offer.offerId, 'm');
        expect(result.selectedSizeKey, 'M');
        expect(result.purchasableForSelectedSize, isFalse);
      },
    );

    test(
      'available now excludes unavailable preferred size and accepts selected alternative',
      () {
        final result = BestOfferResolver.resolve(
          variantId: 'navy',
          offers: [
            offer('m', price: eur49),
            offer('l', price: eur42),
          ],
          sizes: [
            size('m', 'M', CatalogAvailability.unavailable),
            size('l', 'L', CatalogAvailability.available),
          ],
          request: BestOfferRequest(
            selectedSizeKeys: {'M', 'L'},
            preferredSizeKey: 'M',
            availableNow: true,
          ),
        );
        expect(result!.offer.offerId, 'l');
        expect(result.selectedSizeKey, 'L');
        expect(result.purchasableForSelectedSize, isTrue);
      },
    );

    test(
      'desired unavailable size remains recommendable unless available now',
      () {
        final relaxed = BestOfferResolver.resolve(
          variantId: 'navy',
          offers: [offer('m')],
          sizes: [size('m', 'M', CatalogAvailability.unavailable)],
          request: BestOfferRequest(
            selectedSizeKeys: {'M'},
            preferredSizeKey: 'M',
          ),
        );
        final now = BestOfferResolver.resolve(
          variantId: 'navy',
          offers: [offer('m')],
          sizes: [size('m', 'M', CatalogAvailability.unavailable)],
          request: BestOfferRequest(
            selectedSizeKeys: {'M'},
            preferredSizeKey: 'M',
            availableNow: true,
          ),
        );
        expect(relaxed, isNotNull);
        expect(relaxed!.purchasableForSelectedSize, isFalse);
        expect(now, isNull);
      },
    );
  });

  group('shopping query, constraints, and pool', () {
    const navyConstraint = ShoppingConstraint(
      field: ShoppingConstraintField.color,
      operator: ShoppingConstraintOperator.equals,
      value: 'navy',
      strength: ConstraintStrength.hard,
      source: ConstraintSource.explicitUser,
      absolute: true,
    );
    const priceConstraint = ShoppingConstraint(
      field: ShoppingConstraintField.maxPrice,
      operator: ShoppingConstraintOperator.atMost,
      value: eur30,
      strength: ConstraintStrength.hard,
      source: ConstraintSource.explicitUser,
    );

    test('explicit hard constraints diagnose rather than silently relax', () {
      const query = ShoppingQuery(
        queryId: 'q',
        sessionId: 's',
        intent: ShoppingIntent.browseNew,
        constraints: [navyConstraint, priceConstraint],
      );
      final diagnostic = ShoppingConstraintDiagnostics.forZeroExactResults(
        query,
      );
      expect(diagnostic.exactResultCount, 0);
      expect(
        diagnostic.blockingConstraints,
        containsAll([navyConstraint, priceConstraint]),
      );
      expect(navyConstraint.mayRelaxOnlyAfterUserChoice, isTrue);
    });

    test(
      'result pool show-more consumes unseen candidates and rejects remain excluded',
      () {
        const pool = ShoppingResultPool(
          queryRevision: 1,
          catalogRevision: 'catalog-1',
          orderedCandidateIds: ['a', 'b', 'c'],
        );
        final afterShow = pool.markShown(pool.unseen(limit: 2)).reject('c');
        expect(pool.unseen(limit: 2), ['a', 'b']);
        expect(afterShow.unseen(limit: 3), isEmpty);
        expect(afterShow.shownCandidateIds, {'a', 'b'});
        expect(afterShow.rejectedCandidateIds, {'c'});
      },
    );
  });

  group('wishlist state transitions and gold eligibility', () {
    test('price target transitions exactly at the threshold', () {
      final item = wish();
      var state = WishlistTrackingState.initial(item);
      final baseline = WishlistTrackingEvaluator.evaluateKnownSnapshot(
        item: item,
        previous: state,
        effectivePublicPrice: eur50,
        selectedSizeAvailability: const {'M': CatalogAvailability.unavailable},
        freshness: const CatalogFreshness(),
      );
      state = baseline.state;
      expect(baseline.events, isEmpty);

      final at21 = WishlistTrackingEvaluator.evaluateKnownSnapshot(
        item: item,
        previous: state,
        effectivePublicPrice: const ShoppingMoney(
          amountMinor: 2100,
          currency: 'EUR',
        ),
        selectedSizeAvailability: const {'M': CatalogAvailability.unavailable},
        freshness: const CatalogFreshness(),
      );
      expect(at21.events, isEmpty);

      final at20 = WishlistTrackingEvaluator.evaluateKnownSnapshot(
        item: item,
        previous: at21.state,
        effectivePublicPrice: eur20,
        selectedSizeAvailability: const {'M': CatalogAvailability.unavailable},
        freshness: const CatalogFreshness(),
      );
      expect(at20.events.single.type, WishlistEventType.priceTargetSatisfied);
      expect(at20.goldEligible, isTrue);

      final at18 = WishlistTrackingEvaluator.evaluateKnownSnapshot(
        item: item,
        previous: at20.state,
        effectivePublicPrice: const ShoppingMoney(
          amountMinor: 1800,
          currency: 'EUR',
        ),
        selectedSizeAvailability: const {'M': CatalogAvailability.unavailable},
        freshness: const CatalogFreshness(),
      );
      expect(at18.events, isEmpty);

      final at22 = WishlistTrackingEvaluator.evaluateKnownSnapshot(
        item: item,
        previous: at18.state,
        effectivePublicPrice: const ShoppingMoney(
          amountMinor: 2200,
          currency: 'EUR',
        ),
        selectedSizeAvailability: const {'M': CatalogAvailability.unavailable},
        freshness: const CatalogFreshness(),
      );
      expect(at22.events.single.type, WishlistEventType.priceTargetUnsatisfied);
      expect(at22.goldEligible, isFalse);

      final at19 = WishlistTrackingEvaluator.evaluateKnownSnapshot(
        item: item,
        previous: at22.state,
        effectivePublicPrice: const ShoppingMoney(
          amountMinor: 1900,
          currency: 'EUR',
        ),
        selectedSizeAvailability: const {'M': CatalogAvailability.unavailable},
        freshness: const CatalogFreshness(),
      );
      expect(at19.events.single.type, WishlistEventType.priceTargetSatisfied);
      expect(at19.goldEligible, isTrue);
    });

    test(
      'initial satisfied price and available size establish a silent baseline',
      () {
        final item = wish();
        final baseline = WishlistTrackingEvaluator.evaluateKnownSnapshot(
          item: item,
          previous: WishlistTrackingState.initial(item),
          effectivePublicPrice: const ShoppingMoney(
            amountMinor: 1800,
            currency: 'EUR',
          ),
          selectedSizeAvailability: const {'M': CatalogAvailability.available},
          freshness: const CatalogFreshness(),
        );
        expect(baseline.state.priceState, WishlistPriceState.satisfied);
        expect(baseline.state.sizeStates['M'], WishlistSizeState.available);
        expect(baseline.events, isEmpty);
      },
    );

    test('selected size transitions only and unavailable is not gold', () {
      final item = wish();
      final available = WishlistTrackingEvaluator.evaluateKnownSnapshot(
        item: item,
        previous: const WishlistTrackingState(
          priceState: WishlistPriceState.unsatisfied,
          sizeStates: {'M': WishlistSizeState.unavailable},
        ),
        effectivePublicPrice: eur50,
        selectedSizeAvailability: const {'M': CatalogAvailability.available},
        freshness: const CatalogFreshness(),
      );
      final unavailable = WishlistTrackingEvaluator.evaluateKnownSnapshot(
        item: item,
        previous: available.state,
        effectivePublicPrice: eur50,
        selectedSizeAvailability: const {'M': CatalogAvailability.unavailable},
        freshness: const CatalogFreshness(),
      );
      expect(available.events.single.type, WishlistEventType.sizeAvailable);
      expect(available.goldEligible, isTrue);
      expect(unavailable.events.single.type, WishlistEventType.sizeUnavailable);
      expect(unavailable.goldEligible, isFalse);
    });

    test('failed refresh is stale only and manufactures no transition', () {
      const state = WishlistTrackingState(
        priceState: WishlistPriceState.satisfied,
        sizeStates: {'M': WishlistSizeState.available},
      );
      final result = WishlistTrackingEvaluator.markRefreshFailure(
        previous: state,
      );
      expect(result.state.priceState, WishlistPriceState.satisfied);
      expect(result.state.sizeStates['M'], WishlistSizeState.available);
      expect(result.state.freshness.stale, isTrue);
      expect(result.events, isEmpty);
      expect(result.goldEligible, isFalse);
    });

    test('unknown selected-size data never becomes unavailable', () {
      final item = wish();
      final result = WishlistTrackingEvaluator.evaluateKnownSnapshot(
        item: item,
        previous: const WishlistTrackingState(
          priceState: WishlistPriceState.unsatisfied,
          sizeStates: {'M': WishlistSizeState.available},
        ),
        effectivePublicPrice: eur50,
        selectedSizeAvailability: const {'M': CatalogAvailability.unknown},
        freshness: const CatalogFreshness(stale: true),
      );
      expect(result.state.sizeStates['M'], WishlistSizeState.unknown);
      expect(result.events, isEmpty);
      expect(result.goldEligible, isFalse);
    });

    test('all simultaneous positive target events qualify without a cap', () {
      final events = List.generate(
        30,
        (index) => WishlistEvent(
          type: WishlistEventType.priceTargetSatisfied,
          wishlistItemId: 'wish-$index',
        ),
      );
      expect(
        events.where((event) => event.qualifiesForGoldHighlight),
        hasLength(30),
      );
    });
  });

  group('low stock, lifecycle, and independence', () {
    test('only reliable exact quantity can claim exact low-stock count', () {
      final exact = size(
        'a',
        'M',
        CatalogAvailability.available,
        quantity: 3,
        reliability: QuantityReliability.exact,
      );
      final generic = size('a', 'L', CatalogAvailability.available);
      expect(exact.canClaimExactQuantity, isTrue);
      expect(exact.hasInformationalStockUrgency, isTrue);
      expect(generic.canClaimExactQuantity, isFalse);
      expect(generic.hasInformationalStockUrgency, isFalse);
    });

    test('low stock does not create a wishlist success event', () {
      final item = wish();
      final result = WishlistTrackingEvaluator.evaluateKnownSnapshot(
        item: item,
        previous: const WishlistTrackingState(
          priceState: WishlistPriceState.unsatisfied,
          sizeStates: {'M': WishlistSizeState.available},
        ),
        effectivePublicPrice: eur50,
        selectedSizeAvailability: const {'M': CatalogAvailability.available},
        freshness: const CatalogFreshness(),
      );
      expect(result.events, isEmpty);
      expect(result.goldEligible, isFalse);
    });

    test('one active cross-store offer prevents discontinued variant', () {
      expect(
        CatalogIdentityPolicy.variantLifecycle([
          offer('gone', lifecycle: CatalogLifecycleState.discontinued),
          offer('live'),
        ]),
        CatalogLifecycleState.active,
      );
      expect(
        CatalogIdentityPolicy.variantLifecycle([]),
        CatalogLifecycleState.unknownOrStale,
      );
      expect(
        CatalogIdentityPolicy.variantLifecycle([
          offer('a', lifecycle: CatalogLifecycleState.discontinued),
        ]),
        CatalogLifecycleState.discontinued,
      );
      expect(
        CatalogIdentityPolicy.variantLifecycle([
          offer('unknown', availability: CatalogAvailability.unknown),
        ]),
        CatalogLifecycleState.unknownOrStale,
      );
      expect(
        CatalogIdentityPolicy.variantLifecycle([
          offer('returned', availability: CatalogAvailability.available),
        ]),
        CatalogLifecycleState.active,
      );
    });

    test('generation eligibility defaults existing items to eligible', () {
      expect(
        GenerationEligibilityContract.effectiveStatus(null),
        GenerationEligibilityStatus.eligible,
      );
      expect(
        GenerationEligibilityContract.effectiveStatus(
          const GenerationEligibilityContract(
            status: GenerationEligibilityStatus.pendingValidImage,
          ),
        ),
        GenerationEligibilityStatus.pendingValidImage,
      );
    });

    test('wishlist contract contains no wardrobe lifecycle linkage', () {
      final item = wish();
      expect(item.variantId, 'navy');
      expect(item.wishlistItemId, 'wish-1');
      expect(item.targetPrice, eur20);
    });
  });
}
