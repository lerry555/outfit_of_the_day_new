import '../wardrobe_v2/flexible_outfit_result_v2.dart';
import 'user_style_preferences.dart';

/// Canonical Home/Stylist taste sets. Empty means "no personalization".
class StylePreferenceTaste {
  const StylePreferenceTaste({
    this.favoriteColors = const <String>{},
    this.avoidedColors = const <String>{},
    this.preferredStyles = const <String>{},
    this.favoriteBrands = const <String>{},
  });

  static const empty = StylePreferenceTaste();

  final Set<String> favoriteColors;
  final Set<String> avoidedColors;
  final Set<String> preferredStyles;
  final Set<String> favoriteBrands;

  bool get isEmpty =>
      favoriteColors.isEmpty &&
      avoidedColors.isEmpty &&
      preferredStyles.isEmpty &&
      favoriteBrands.isEmpty;

  factory StylePreferenceTaste.fromPreferences(UserStylePreferences prefs) {
    if (prefs.isEmpty) return empty;
    return StylePreferenceTaste(
      favoriteColors: prefs.favoriteColors
          .map(UserStylePreferences.canonicalColor)
          .where((value) => value.isNotEmpty)
          .toSet(),
      avoidedColors: prefs.avoidedColors
          .map(UserStylePreferences.canonicalColor)
          .where((value) => value.isNotEmpty)
          .toSet(),
      preferredStyles: prefs.preferredStyles
          .map(UserStylePreferences.canonicalStyle)
          .where((value) => value.isNotEmpty)
          .toSet(),
      favoriteBrands: prefs.favoriteBrands
          .map(UserStylePreferences.canonicalBrand)
          .where((value) => value.isNotEmpty)
          .toSet(),
    );
  }
}

/// Subordinate taste scoring for already-valid V2 outfits.
///
/// Weights stay inside [OutfitSuitabilityPolicyV2.lightPenalty] (±2.5) so
/// weather (`-8`), core (`-20`) and major suitability (`-12`) always dominate.
abstract final class StylePreferenceTasteScorer {
  static const double favoriteColorBonus = 0.8;
  static const double avoidedColorPenalty = -2.0;
  static const double preferredStyleBonus = 0.5;
  static const double favoriteBrandBonus = 0.25;
  static const double maxAbsScore = 2.5;

  /// Common V2 color families mapped onto the saved-preference palette.
  static const Map<String, String> relatedColorFamilies = <String, String>{
    'navy': 'blue',
    'denim': 'blue',
    'teal': 'blue',
    'burgundy': 'red',
    'maroon': 'red',
    'wine': 'red',
    'charcoal': 'gray',
    'silver': 'gray',
    'olive': 'green',
    'khaki': 'green',
    'cream': 'beige',
    'tan': 'beige',
    'camel': 'beige',
  };

  static double score({
    required V2FlexibleOutfitResult outfit,
    required StylePreferenceTaste taste,
  }) {
    if (taste.isEmpty) return 0;
    var total = 0.0;
    if (_hasColorOverlap(outfit, taste.favoriteColors)) {
      total += favoriteColorBonus;
    }
    if (_hasColorOverlap(outfit, taste.avoidedColors)) {
      total += avoidedColorPenalty;
    }
    if (taste.preferredStyles.isNotEmpty &&
        outfit.items.any(
          (piece) => piece.item.styles
              .map(UserStylePreferences.canonicalStyle)
              .any(taste.preferredStyles.contains),
        )) {
      total += preferredStyleBonus;
    }
    if (taste.favoriteBrands.isNotEmpty &&
        outfit.items.any((piece) {
          final brand = _brandOf(piece.display);
          return brand.isNotEmpty && taste.favoriteBrands.contains(brand);
        })) {
      total += favoriteBrandBonus;
    }
    if (total > maxAbsScore) return maxAbsScore;
    if (total < -maxAbsScore) return -maxAbsScore;
    return total;
  }

  static bool _hasColorOverlap(
    V2FlexibleOutfitResult outfit,
    Set<String> wanted,
  ) {
    if (wanted.isEmpty) return false;
    for (final piece in outfit.items) {
      final families = <String>[
        piece.item.colorProfile.primary.family,
        if (piece.item.colorProfile.secondary != null)
          piece.item.colorProfile.secondary!.family,
        ...piece.item.colorProfile.accents.map((color) => color.family),
      ];
      for (final family in families) {
        if (wanted.contains(_matchKey(family))) return true;
      }
    }
    return false;
  }

  static String _matchKey(String family) {
    final canonical = UserStylePreferences.canonicalColor(family);
    return relatedColorFamilies[canonical] ?? canonical;
  }

  static String _brandOf(Map<String, dynamic> display) {
    final raw = display['brand'] ?? display['Brand'];
    if (raw == null) return '';
    return UserStylePreferences.canonicalBrand(raw.toString());
  }
}

/// Natural Home copy when taste actually moved the ranking. Never emits
/// field names or score math.
abstract final class StylePreferenceExplain {
  static String? naturalHint({
    required StylePreferenceTaste taste,
    required V2FlexibleOutfitResult outfit,
    required double tasteScore,
  }) {
    if (taste.isEmpty || tasteScore.abs() < 0.4) return null;
    if (tasteScore > 0 &&
        StylePreferenceTasteScorer._hasColorOverlap(
          outfit,
          taste.favoriteColors,
        )) {
      return 'Držal som sa skôr tvojich obľúbených farebných tónov.';
    }
    if (tasteScore < 0) return null;
    if (taste.preferredStyles.isNotEmpty &&
        outfit.items.any(
          (piece) => piece.item.styles
              .map(UserStylePreferences.canonicalStyle)
              .any(taste.preferredStyles.contains),
        )) {
      return 'Držal som sa skôr štýlu, ktorý máš rád.';
    }
    return null;
  }
}
