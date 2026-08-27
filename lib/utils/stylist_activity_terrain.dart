import 'stylist_semantic_activity.dart';

/// Typ povrchu / aktivity — ovplyvňuje, či má zmysel spomínať minulý dážď
/// (mokrá tráva/hlina) alebo len aktuálne a budúce počasie (mestská prechádzka).
enum StylistActivityTerrain {
  wetGround,
  urban,
}

class StylistActivityTerrainClassifier {
  const StylistActivityTerrainClassifier._();

  /// Kanonická aktivita je primárna autorita. Voľný text je iba fallback na
  /// explicitné fyzické povrchy, nie ďalší samostatný slovník aktivít.
  static StylistActivityTerrain classify({
    String? conversationText,
    String? occasion,
    String? groundedActivityType,
  }) {
    final grounded = StylistSemanticActivity.canonicalize(groundedActivityType) ??
        StylistSemanticActivity.resolveExplicit(groundedActivityType ?? '');
    if (grounded != null) return _terrainFor(grounded);

    final blob = '${conversationText ?? ''} ${occasion ?? ''}';
    final semantic = StylistSemanticActivity.resolveExplicit(blob);
    if (semantic != null) return _terrainFor(semantic);

    final text = StylistSemanticActivity.normalize(blob);
    if (RegExp(
      r'\b(?:blat\w*|hlin\w*|trav\w*|luk\w*|trail\w*|les\w*|prirod\w*|hor\w*)\b',
    ).hasMatch(text)) {
      return StylistActivityTerrain.wetGround;
    }
    return StylistActivityTerrain.urban;
  }

  static StylistActivityTerrain _terrainFor(String activity) {
    if (StylistSemanticActivity.isOutdoor(activity)) {
      return StylistActivityTerrain.wetGround;
    }
    return StylistActivityTerrain.urban;
  }
}
