import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/models/shopping_ui_feature_flags.dart';
import 'package:outfitofTheDay/models/stylist_shopping_runtime.dart';

void main() {
  test('Shopping fixture UI is production-disabled by default', () {
    expect(ShoppingUiFeatureFlags.enabled, isFalse);
    expect(ShoppingUiFeatureFlags.fixtureMode, isFalse);
    expect(ShoppingUiFeatureFlags.mayExposeCatalog, isFalse);
    expect(ShoppingUiFeatureFlags.mayExposeWishlistV2, isFalse);
  });

  test('client distinguishes Shopping candidates from Wardrobe item maps', () {
    final attachment = StylistShoppingAttachment.fromMap({
      'kind': 'shopping_candidate',
      'candidate': {
        'variantId': 'v1',
        'effectivePublicPrice': {
          'price': {'amountMinor': 2000, 'currency': 'EUR'},
        },
      },
    });
    expect(attachment.kind, 'shopping_candidate');
    expect(attachment.payload['candidate'], isA<Map>());
  });

  test('unknown attachment kinds fail closed', () {
    expect(
      () => StylistShoppingAttachment.fromMap({'kind': 'forged_catalog_fact'}),
      throwsFormatException,
    );
  });

  test('session patch tracks only session-local Shopping state', () {
    final state = const StylistShoppingSessionState().applyPatch({
      'sessionId': 'opaque',
      'queryRevision': 2,
      'sessionVersion': 4,
      'catalogRevision': 'catalog-1',
      'presentedVariantIds': ['v1', 'v2'],
      'focusedVariantId': 'v1',
      'activeClarification': 'SHOPPING_MAX_PRICE',
    });
    expect(state.isActive, isTrue);
    expect(state.presentedVariantIds, ['v1', 'v2']);
    expect(state.sessionVersion, 4);
    expect(state.toApiPayload()['focusedVariantId'], 'v1');
  });

  test('nullable patch fields clear focus and clarification', () {
    final active = const StylistShoppingSessionState(
      sessionId: 'opaque',
      focusedVariantId: 'v1',
      activeClarification: 'SHOPPING_MAX_PRICE',
    );
    final cleared = active.applyPatch({
      'focusedVariantId': null,
      'activeClarification': null,
    });
    expect(cleared.focusedVariantId, isNull);
    expect(cleared.activeClarification, isNull);
  });

  test('Shopping turns bypass outfit clarification ownership', () {
    const state = StylistShoppingSessionState();
    expect(
      StylistShoppingClientRouting.shouldUseShoppingTransport(
        'Ukáž mi niečo k týmto nohaviciam.',
        state,
      ),
      isTrue,
    );
    expect(
      StylistShoppingClientRouting.shouldUseShoppingTransport(
        'Čo si mám obliecť do práce?',
        state,
      ),
      isFalse,
    );
  });

  test('active Shopping topic switch is recognized as normal Stylist', () {
    expect(
      StylistShoppingClientRouting.isNormalOutfitTopic(
        'Čo si mám zajtra obliecť do práce?',
      ),
      isTrue,
    );
  });
}
