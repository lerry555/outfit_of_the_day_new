import 'package:flutter/foundation.dart';

/// Shopping UI remains opt-in for release builds until real catalog partners
/// are approved. Debug builds automatically enable fixture shopping so local
/// Brain/Stylist QA cannot render action buttons that silently do nothing.
abstract final class ShoppingUiFeatureFlags {
  static const enabled = bool.fromEnvironment(
    'SHOPPING_UI_ENABLED',
    defaultValue: kDebugMode,
  );

  static const fixtureMode = bool.fromEnvironment(
    'SHOPPING_FIXTURE_MODE',
    defaultValue: kDebugMode,
  );

  /// Optional tighter gate for Wishlist V2 list / notification opens.
  /// Defaults true so it does not block when SHOP-014 catalog exposure is on;
  /// set `--dart-define=WISHLIST_V2_LIST_ENABLED=false` to hide the list only.
  static const wishlistV2ListEnabled = bool.fromEnvironment(
    'WISHLIST_V2_LIST_ENABLED',
    defaultValue: true,
  );

  /// SHOP-014: release builds still require both explicit flags. In debug,
  /// their defaults are true and fixture mode keeps external offer opens safe.
  static bool get mayExposeCatalog => enabled && fixtureMode;

  /// Wishlist list / deep-links: never weaker than [mayExposeCatalog].
  static bool get mayExposeWishlistV2 =>
      mayExposeCatalog && wishlistV2ListEnabled;
}
