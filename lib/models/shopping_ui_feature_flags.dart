/// Shopping UI is deliberately opt-in until real catalog partners are approved.
///
/// Local/widget qualification enables it with:
/// `--dart-define=SHOPPING_UI_ENABLED=true --dart-define=SHOPPING_FIXTURE_MODE=true`.
abstract final class ShoppingUiFeatureFlags {
  static const enabled = bool.fromEnvironment(
    'SHOPPING_UI_ENABLED',
    defaultValue: false,
  );

  static const fixtureMode = bool.fromEnvironment(
    'SHOPPING_FIXTURE_MODE',
    defaultValue: false,
  );

  /// Optional tighter gate for Wishlist V2 list / notification opens.
  /// Defaults true so it does not block when SHOP-014 catalog exposure is on;
  /// set `--dart-define=WISHLIST_V2_LIST_ENABLED=false` to hide the list only.
  static const wishlistV2ListEnabled = bool.fromEnvironment(
    'WISHLIST_V2_LIST_ENABLED',
    defaultValue: true,
  );

  /// SHOP-014: both shopping flags must be true before any catalog UI.
  static bool get mayExposeCatalog => enabled && fixtureMode;

  /// Wishlist list / deep-links: never weaker than [mayExposeCatalog].
  static bool get mayExposeWishlistV2 =>
      mayExposeCatalog && wishlistV2ListEnabled;
}
