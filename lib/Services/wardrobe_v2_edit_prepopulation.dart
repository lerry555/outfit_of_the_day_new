import '../data/clothing_knowledge_base.dart';
import '../domain/wardrobe_v2/wardrobe_ontology_v2.dart';
import '../domain/wardrobe_v2/wardrobe_v1_retirement.dart';
import 'color_naming_service.dart';
import 'wardrobe_v2_user_override.dart';

/// Pure V2 -> edit-form presentation projection.
///
/// It never creates persistence fields. Category labels come from the KB and
/// display colors come from semantic [colorProfile] roles.
class WardrobeV2EditPrepopulation {
  const WardrobeV2EditPrepopulation({
    required this.canonicalType,
    required this.name,
    required this.brand,
    required this.mainCategory,
    required this.category,
    required this.subcategory,
    required this.displayColors,
    required this.patterns,
    required this.styles,
    required this.seasons,
    required this.fit,
    required this.formality,
    required this.warmth,
    required this.attributes,
  });

  final String canonicalType;
  final String name;
  final String brand;
  final String? mainCategory;
  final String? category;
  final String? subcategory;
  final List<String> displayColors;
  final List<String> patterns;
  final List<String> styles;
  final List<String> seasons;
  final String? fit;
  final int? formality;
  final int? warmth;
  final Map<String, dynamic> attributes;

  static WardrobeV2EditPrepopulation fromDocument(
    Map<String, dynamic> document,
  ) {
    final canonical = (document['canonicalType'] ?? '').toString().trim();
    if (canonical.isEmpty) {
      throw const FormatException('missing_v2_canonical_type');
    }
    final kb = ClothingKnowledgeBase.findByCanonicalType(canonical);
    if (kb == null) {
      throw FormatException('unknown_v2_canonical_type:$canonical');
    }
    final colors = displayColorsFromProfile(document['colorProfile']);
    if (colors.isEmpty) {
      throw const FormatException('missing_v2_display_color');
    }
    List<String> strings(String key) =>
        (document[key] as List? ?? const []).map((e) => e.toString()).toList();
    int? integer(String key) => document[key] is num
        ? (document[key] as num).round()
        : int.tryParse((document[key] ?? '').toString());

    return WardrobeV2EditPrepopulation(
      canonicalType: canonical,
      name: (document['name'] ?? '').toString().trim(),
      brand: (document['brand'] ?? '').toString().trim(),
      mainCategory: kb.mainCategory,
      category: kb.category,
      subcategory: kb.subcategory,
      displayColors: List.unmodifiable(colors),
      patterns: List.unmodifiable(strings('patterns')),
      styles: List.unmodifiable(strings('styles')),
      seasons: List.unmodifiable(strings('seasons')),
      fit: document['fit']?.toString(),
      formality: integer('formality'),
      warmth: integer('warmth'),
      attributes: Map.unmodifiable(
        Map<String, dynamic>.from(document['attributes'] as Map? ?? const {}),
      ),
    );
  }

  /// Color families in V2 role order: primary, secondary, accents.
  static List<String> colorFamiliesFromProfile(dynamic colorProfile) {
    final profile = colorProfile is Map
        ? Map<String, dynamic>.from(colorProfile)
        : const <String, dynamic>{};
    return <String>[
      if (profile['primary'] is Map)
        (profile['primary'] as Map)['family']?.toString() ?? '',
      if (profile['secondary'] is Map)
        (profile['secondary'] as Map)['family']?.toString() ?? '',
      if (profile['accents'] is List)
        ...(profile['accents'] as List).whereType<Map>().map(
          (entry) => entry['family']?.toString() ?? '',
        ),
    ].where((value) => value.trim().isNotEmpty).toList();
  }

  static List<String> displayColorsFromProfile(dynamic colorProfile) {
    return ColorNamingService.instance.normalizeDisplayColors(
      colorFamiliesFromProfile(colorProfile),
    );
  }
}

abstract final class WardrobeV2EditPersistence {
  static const _v2Keys = <String>{
    'ontologyVersion',
    'taxonomyVersion',
    'kbVersion',
    'canonicalType',
    'canonicalFamily',
    'bodySlots',
    'layerPosition',
    'outfitFunctions',
    'uiProjection',
    'accessoryGroup',
    'multiplicity',
    'colorProfile',
    'formality',
    'styles',
    'occasionFit',
    'seasons',
    'warmth',
    'attributes',
    'setMembership',
    'fieldSources',
    'fieldConfidence',
    'userOverrideFields',
    'analyzerProvenance',
  };

  static Map<String, dynamic> authoritativePayloadFromDocument(
    Map<String, dynamic> document,
  ) {
    if ((document['canonicalType'] ?? '').toString().trim().isEmpty) {
      throw const FormatException('missing_v2_canonical_type');
    }
    final result = <String, dynamic>{
      for (final key in _v2Keys)
        if (document.containsKey(key)) key: document[key],
    };
    result.putIfAbsent('kbVersion', () => WardrobeOntologyV2Values.kbVersion);
    return WardrobeV1Retirement.stripRetiredFields(result);
  }

  static Map<String, dynamic> applyBrandEdit({
    required Map<String, dynamic> payload,
    required String originalBrand,
    required String editedBrand,
  }) {
    final result = Map<String, dynamic>.from(payload);
    if (editedBrand == originalBrand) return result;
    final overrides = {
      ...(result['userOverrideFields'] as List? ?? const []).map(
        (value) => value.toString(),
      ),
      'brand',
    }.toList()..sort();
    final sources = Map<String, dynamic>.from(
      result['fieldSources'] as Map? ?? const {},
    )..['brand'] = 'user_correction';
    final confidence = Map<String, dynamic>.from(
      result['fieldConfidence'] as Map? ?? const {},
    )..['brand'] = 1.0;
    return result
      ..['userOverrideFields'] = overrides
      ..['fieldSources'] = sources
      ..['fieldConfidence'] = confidence;
  }

  /// Applies explicit type/color corrections onto an existing V2 payload.
  static WardrobeV2UserOverrideResult applyIdentityOverride({
    required Map<String, dynamic> payload,
    required WardrobeOntologyV2 ontology,
    bool typeEdited = false,
    bool colorEdited = false,
    String? selectedSubcategory,
    String? selectedCategory,
    List<String> selectedDisplayColors = const [],
    String? currentCanonicalType,
  }) {
    return WardrobeV2UserOverride.apply(
      original: payload,
      ontology: ontology,
      typeEdited: typeEdited,
      colorEdited: colorEdited,
      selectedSubcategory: selectedSubcategory,
      selectedCategory: selectedCategory,
      selectedDisplayColors: selectedDisplayColors,
      currentCanonicalType: currentCanonicalType,
    );
  }
}
