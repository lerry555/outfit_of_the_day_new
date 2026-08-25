import '../constants/app_constants.dart';
import '../data/clothing_knowledge_base.dart';
import '../domain/wardrobe_v2/wardrobe_ontology_v2.dart';
import 'color_naming_service.dart';

/// Field policy for explicit Add/Edit type and color corrections.
///
/// Recompute on type override (structural identity from ontology):
/// `canonicalType`, `canonicalFamily`, `bodySlots`, `layerPosition`,
/// `outfitFunctions`, `uiProjection`, `accessoryGroup`, `multiplicity`.
///
/// Preserve (independent of type unless structurally incompatible):
/// `colorProfile` (unless color is also overridden), `attributes`, `styles`,
/// `seasons`, `occasionFit`, `patterns`, `brand`, `name`, `setMembership`,
/// `analyzerProvenance`, `ontologyVersion`, `taxonomyVersion`, `kbVersion`.
/// Warmth/formality stay when still inside the new type's ontology range;
/// otherwise they snap to that type's typical value.
///
/// Explicitly override: `canonicalType` (via UI subcategory), `colorProfile`.
///
/// Unknown/unsafe: do not invent a canonical type when UI subcategory maps to
/// mixed families or body slots. Preserve the prior identity instead.
abstract final class WardrobeV2UserOverride {
  static const Set<String> recomputedOnTypeOverride = {
    'canonicalType',
    'canonicalFamily',
    'bodySlots',
    'layerPosition',
    'outfitFunctions',
    'uiProjection',
    'accessoryGroup',
    'multiplicity',
  };

  static const Set<String> preservedOnTypeOverride = {
    'colorProfile',
    'attributes',
    'styles',
    'seasons',
    'occasionFit',
    'setMembership',
    'analyzerProvenance',
    'ontologyVersion',
    'taxonomyVersion',
    'kbVersion',
  };

  static const Set<String> explicitlyOverridable = {
    'canonicalType',
    'colorProfile',
    'brand',
  };

  static WardrobeV2UserOverrideResult apply({
    required Map<String, dynamic> original,
    required WardrobeOntologyV2 ontology,
    bool typeEdited = false,
    bool colorEdited = false,
    String? selectedSubcategory,
    String? selectedCategory,
    List<String> selectedDisplayColors = const [],
    String? currentCanonicalType,
  }) {
    if (!typeEdited && !colorEdited) {
      return WardrobeV2UserOverrideResult(
        payload: Map<String, dynamic>.from(original),
      );
    }

    final result = _clone(original);
    var typeApplied = false;
    String? unresolved;
    if (typeEdited) {
      final resolved = canonicalTypeForUiSelection(
        ontology: ontology,
        subcategory: selectedSubcategory ?? '',
        category: selectedCategory,
        currentCanonicalType: currentCanonicalType,
      );
      if (resolved == null) {
        unresolved = selectedSubcategory == null || selectedSubcategory.isEmpty
            ? 'missing_ui_subcategory'
            : 'unambiguous_mapping_unavailable:$selectedSubcategory';
      } else {
        _applyTypeIdentity(result, ontology.definition(resolved)!);
        typeApplied = true;
      }
    }

    var colorApplied = false;
    if (colorEdited) {
      colorApplied = _applyColorProfile(result, selectedDisplayColors);
    }

    if (typeApplied || colorApplied) {
      _recordCorrections(
        result,
        typeApplied: typeApplied,
        colorApplied: colorApplied,
      );
    }

    return WardrobeV2UserOverrideResult(
      payload: result,
      typeOverrideApplied: typeApplied,
      colorOverrideApplied: colorApplied,
      unresolvedTypeReason: unresolved,
    );
  }

  /// Maps a production type picker key to a V2 canonical type without guessing
  /// across incompatible families or body slots.
  static String? canonicalTypeForUiSelection({
    required WardrobeOntologyV2 ontology,
    required String subcategory,
    String? category,
    String? currentCanonicalType,
  }) {
    final sub = subcategory.trim();
    if (sub.isEmpty) return null;

    var candidates = ontology.types.values
        .where((type) => type.uiProjection['subcategory'] == sub)
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    final categoryKey = (category ?? '').trim();
    if (categoryKey.isNotEmpty) {
      final narrowed = candidates
          .where((type) => type.uiProjection['category'] == categoryKey)
          .toList(growable: false);
      if (narrowed.length == 1) return narrowed.single.canonicalType;
      if (narrowed.isNotEmpty) candidates = narrowed;
    }

    if (candidates.length == 1) return candidates.single.canonicalType;

    final current = (currentCanonicalType ?? '').trim();
    if (current.isNotEmpty &&
        candidates.any((type) => type.canonicalType == current)) {
      return current;
    }

    final roots = candidates
        .where((type) => type.parentType == null)
        .toList(growable: false);
    if (roots.length == 1) return roots.single.canonicalType;

    final aliasHits = candidates.where((type) {
      final haystack = <String>[
        type.canonicalType,
        ...type.aliases,
      ].map(_norm).toSet();
      return haystack.contains(_norm(sub)) ||
          haystack.contains(_norm(subCategoryLabels[sub] ?? ''));
    }).toList(growable: false);
    if (aliasHits.length == 1) return aliasHits.single.canonicalType;

    if (!_structurallyCompatible(candidates)) return null;

    final kb = ClothingKnowledgeBase.findByAlias(sub);
    if (kb != null &&
        candidates.any((type) => type.canonicalType == kb.canonicalType)) {
      return kb.canonicalType;
    }
    return null;
  }

  static bool listsEqual(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

class WardrobeV2UserOverrideResult {
  const WardrobeV2UserOverrideResult({
    required this.payload,
    this.typeOverrideApplied = false,
    this.colorOverrideApplied = false,
    this.unresolvedTypeReason,
  });

  final Map<String, dynamic> payload;
  final bool typeOverrideApplied;
  final bool colorOverrideApplied;
  final String? unresolvedTypeReason;
}

void _applyTypeIdentity(Map<String, dynamic> payload, WardrobeTypeV2 type) {
  payload['canonicalType'] = type.canonicalType;
  payload['canonicalFamily'] = type.canonicalFamily;
  payload['bodySlots'] = List<String>.from(type.defaultBodySlots);
  payload['layerPosition'] = type.defaultLayerPosition;
  payload['outfitFunctions'] = List<String>.from(type.outfitFunctions);
  payload['uiProjection'] = Map<String, dynamic>.from(type.uiProjection);
  payload['accessoryGroup'] = type.accessoryGroup;
  payload['multiplicity'] = Map<String, dynamic>.from(type.multiplicity);
  payload['warmth'] = _adjustLevel(
    payload['warmth'],
    type.warmthMin,
    type.warmthMax,
    type.warmthTypical,
  );
  payload['formality'] = _adjustLevel(
    payload['formality'],
    type.formalityMin,
    type.formalityMax,
    type.formalityTypical,
  );
}

bool _applyColorProfile(
  Map<String, dynamic> payload,
  List<String> selectedDisplayColors,
) {
  final naming = ColorNamingService.instance;
  final families = <String>[];
  final hexes = <String?>[];
  for (final raw in naming.normalizeDisplayColors(selectedDisplayColors)) {
    final family = naming.canonicalFamilyFromDisplay(raw);
    if (family == null || family.isEmpty) continue;
    families.add(family);
    hexes.add(naming.hexForDisplay(raw));
  }
  if (families.isEmpty) return false;

  final original = payload['colorProfile'] is Map
      ? Map<String, dynamic>.from(payload['colorProfile'] as Map)
      : <String, dynamic>{};
  final proportions = _colorProportions(families.length);
  Map<String, dynamic> swatch(int index) => {
    'family': families[index],
    if (hexes[index] != null) 'hex': hexes[index],
    'proportion': proportions[index],
  };

  payload['colorProfile'] = {
    'primary': swatch(0),
    'secondary': families.length > 1 ? swatch(1) : null,
    'accents': [
      for (var i = 2; i < families.length; i++) swatch(i),
    ],
    'metalTone': original['metalTone'] ?? 'unknown',
    'hardwareTone': original['hardwareTone'] ?? 'unknown',
  };
  return true;
}

void _recordCorrections(
  Map<String, dynamic> payload, {
  required bool typeApplied,
  required bool colorApplied,
}) {
  final overrides = {
    ...(payload['userOverrideFields'] as List? ?? const []).map(
      (value) => value.toString(),
    ),
    if (typeApplied) 'canonicalType',
    if (colorApplied) 'colorProfile',
  }.toList()..sort();
  final sources = Map<String, dynamic>.from(
    payload['fieldSources'] as Map? ?? const {},
  );
  final confidence = Map<String, dynamic>.from(
    payload['fieldConfidence'] as Map? ?? const {},
  );
  if (typeApplied) {
    sources['canonicalType'] = 'user_correction';
    sources['canonicalFamily'] = 'knowledge_base';
    sources['bodySlots'] = 'knowledge_base';
    sources['layerPosition'] = 'knowledge_base';
    sources['outfitFunctions'] = 'knowledge_base';
    confidence['canonicalType'] = 1.0;
    confidence['canonicalFamily'] = 1.0;
    confidence['bodySlots'] = 1.0;
    confidence['layerPosition'] = 1.0;
  }
  if (colorApplied) {
    sources['colorProfile'] = 'user_correction';
    confidence['colorProfile'] = 1.0;
  }
  payload['userOverrideFields'] = overrides;
  payload['fieldSources'] = sources;
  payload['fieldConfidence'] = confidence;
}

bool _structurallyCompatible(List<WardrobeTypeV2> candidates) {
  if (candidates.isEmpty) return false;
  final family = candidates.first.canonicalFamily;
  final slots = candidates.first.defaultBodySlots.join('|');
  return candidates.every(
    (type) =>
        type.canonicalFamily == family &&
        type.defaultBodySlots.join('|') == slots,
  );
}

int _adjustLevel(dynamic current, int? min, int? max, int? typical) {
  final parsed = current is num
      ? current.round()
      : int.tryParse((current ?? '').toString());
  if (min == null || max == null) return parsed ?? typical ?? 5;
  if (parsed != null && parsed >= min && parsed <= max) return parsed;
  return typical ?? parsed?.clamp(min, max) ?? min;
}

List<double> _colorProportions(int count) {
  if (count <= 1) return const [1.0];
  if (count == 2) return const [0.7, 0.3];
  final accentShare = 0.15 / (count - 2);
  return [0.6, 0.25, ...List<double>.filled(count - 2, accentShare)];
}

Map<String, dynamic> _clone(Map<String, dynamic> original) {
  return Map<String, dynamic>.from(original);
}

String _norm(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s-]+'), '_')
    .replaceAll('á', 'a')
    .replaceAll('ä', 'a')
    .replaceAll('č', 'c')
    .replaceAll('ď', 'd')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ľ', 'l')
    .replaceAll('ň', 'n')
    .replaceAll('ó', 'o')
    .replaceAll('ô', 'o')
    .replaceAll('š', 's')
    .replaceAll('ť', 't')
    .replaceAll('ú', 'u')
    .replaceAll('ý', 'y')
    .replaceAll('ž', 'z');
