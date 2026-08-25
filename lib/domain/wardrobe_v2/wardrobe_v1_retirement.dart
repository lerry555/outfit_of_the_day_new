/// Versioned V1 field boundary for new Wardrobe V2 persistence writes.
///
/// The machine-readable cleanup artifact mirrors this set. Historical outfit
/// payload decoders are intentionally outside this wardrobe-document boundary.
abstract final class WardrobeV1Retirement {
  static const artifactVersion = 'wardrobe-v2-v1-retirement-cleanup-v1';

  static const retiredWardrobeFieldPaths = <String>{
    'canonical_type',
    'type',
    'type_pretty',
    'primary_type',
    'secondary_type',
    'mainGroup',
    'mainGroupKey',
    'category',
    'categoryKey',
    'subCategory',
    'subCategoryKey',
    'layerRole',
    'layer_role',
    'stylingLayerRole',
    'warmth_level',
    'warmthLevel',
    'colors',
    'baseColors',
    'colorHex',
    'occasion_fit',
    'analyzerVersion',
    'analyzerProvider',
    'analyzerModel',
    'analyzerPromptVersion',
    'analyzerPromptHash',
  };

  static Map<String, dynamic> stripRetiredFields(Map<String, dynamic> input) {
    final result = Map<String, dynamic>.from(input);
    for (final field in retiredWardrobeFieldPaths) {
      result.remove(field);
    }
    return result;
  }
}
