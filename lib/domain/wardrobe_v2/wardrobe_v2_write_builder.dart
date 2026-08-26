import 'wardrobe_item_v2.dart';
import 'wardrobe_ontology_v2.dart';
import 'season_compatibility_v2.dart';

/// Produces the authoritative V2 portion of an Add Clothing write. Legacy
/// compatibility fields may coexist in the outer document during cutover.
abstract final class WardrobeV2WriteBuilder {
  static WardrobeItemV2 fromAnalyzerAndKb({
    required WardrobeOntologyV2 ontology,
    required Map<String, dynamic> analyzer,
    Map<String, dynamic> existing = const {},
    Set<String> manuallyEditedFields = const {},
  }) {
    final identity = analyzer['identity'] is Map
        ? Map<String, dynamic>.from(analyzer['identity'] as Map)
        : analyzer;
    final canonical =
        (identity['canonicalType'] ?? analyzer['canonicalType'] ?? '')
            .toString();
    final definition = ontology.definition(canonical);
    if (definition == null) {
      throw StateError('v2_unknown_canonical_type:$canonical');
    }
    final observed = analyzer['observed'] is Map
        ? Map<String, dynamic>.from(analyzer['observed'] as Map)
        : analyzer;
    final inferred = analyzer['inferred'] is Map
        ? Map<String, dynamic>.from(analyzer['inferred'] as Map)
        : analyzer;
    final evidence = analyzer['evidence'] is Map
        ? Map<String, dynamic>.from(analyzer['evidence'] as Map)
        : const <String, dynamic>{};
    final overrides = {
      ...(existing['userOverrideFields'] as List? ?? const []).map(
        (x) => x.toString(),
      ),
      ...manuallyEditedFields,
    };
    dynamic chosen(String field, dynamic analyzed) =>
        overrides.contains(field) ? existing[field] : analyzed;
    final colors = chosen('colorProfile', observed['colorProfile']);
    final colorMap = colors is Map
        ? Map<String, dynamic>.from(colors)
        : <String, dynamic>{};
    final primary = colorMap['primary'] is Map
        ? Map<String, dynamic>.from(colorMap['primary'] as Map)
        : {
            'family':
                ((existing['colors'] is List &&
                            (existing['colors'] as List).isNotEmpty)
                        ? (existing['colors'] as List).first
                        : 'unknown')
                    .toString(),
          };
    final sources = <String, dynamic>{
      ...(existing['fieldSources'] is Map
          ? Map<String, dynamic>.from(existing['fieldSources'] as Map)
          : {}),
    };
    final confidence = <String, dynamic>{
      ...(existing['fieldConfidence'] is Map
          ? Map<String, dynamic>.from(existing['fieldConfidence'] as Map)
          : {}),
    };
    for (final field in overrides) {
      sources[field] = 'user_correction';
      confidence[field] = 1.0;
    }
    sources.addAll({
      'canonicalType': 'visual_ai',
      'canonicalFamily': 'knowledge_base',
      'bodySlots': 'knowledge_base',
      'layerPosition': 'knowledge_base',
      'outfitFunctions': 'knowledge_base',
    });
    if (overrides.contains('canonicalType')) {
      sources['canonicalType'] = 'user_correction';
    }
    final evidenceConfidence = evidence['fieldConfidence'] is Map
        ? Map<String, dynamic>.from(evidence['fieldConfidence'] as Map)
        : const <String, dynamic>{};
    final analyzedWarmth = chosen('warmth', inferred['warmth']);
    final warmth =
        (analyzedWarmth as num?)?.toInt() ?? definition.warmthTypical ?? 5;
    if ((definition.warmthMin != null && warmth < definition.warmthMin!) ||
        (definition.warmthMax != null && warmth > definition.warmthMax!)) {
      throw StateError('v2_warmth_out_of_type_range:$canonical');
    }
    final analyzedSeasons = chosen('seasons', inferred['seasons']);
    final resolvedSeasons = overrides.contains('seasons')
        ? List<String>.from(analyzedSeasons as List? ?? const [])
        : (analyzedSeasons is List && analyzedSeasons.isNotEmpty
              ? List<String>.from(analyzedSeasons)
              : SeasonCompatibilityV2.derive(
                  canonicalType: canonical,
                  canonicalFamily: definition.canonicalFamily,
                  layerPosition: definition.defaultLayerPosition,
                  warmth: warmth,
                  outfitFunctions: definition.outfitFunctions,
                  attributes: Map<String, dynamic>.from(
                    chosen('attributes', observed['attributes']) as Map? ??
                        const {},
                  ),
                ));
    if (!overrides.contains('warmth')) {
      sources['warmth'] = analyzedWarmth is num
          ? 'visual_ai'
          : 'knowledge_base';
      confidence['warmth'] = analyzedWarmth is num
          ? (evidenceConfidence['warmth'] as num?)?.toDouble() ?? 0.0
          : 1.0;
    }
    if (!overrides.contains('seasons')) {
      sources['seasons'] = 'system';
      confidence['seasons'] = 1.0;
    }
    confidence.addAll({
      'canonicalType': (identity['confidence'] as num?)?.toDouble() ?? .0,
      'canonicalFamily': 1.0,
      'bodySlots': 1.0,
      'layerPosition': 1.0,
      'outfitFunctions': 1.0,
      ...evidenceConfidence,
    });
    return WardrobeItemV2(
      canonicalType: canonical,
      canonicalFamily: definition.canonicalFamily,
      bodySlots: definition.defaultBodySlots,
      layerPosition: definition.defaultLayerPosition,
      outfitFunctions: definition.outfitFunctions,
      uiProjection: definition.uiProjection,
      accessoryGroup: definition.accessoryGroup,
      multiplicity: definition.multiplicity,
      colorProfile: ColorProfileV2.fromMap({
        ...colorMap,
        'primary': primary,
        'accents': colorMap['accents'] ?? const [],
        'metalTone': colorMap['metalTone'] ?? 'unknown',
        'hardwareTone': colorMap['hardwareTone'] ?? 'unknown',
      }),
      formality:
          (chosen('formality', inferred['formality']) as num?)?.toInt() ?? 5,
      styles: List<String>.from(
        chosen('styles', inferred['styles']) as List? ?? const [],
      ),
      occasionFit: List<String>.from(
        chosen('occasionFit', inferred['occasionFit']) as List? ?? const [],
      ),
      seasons: resolvedSeasons,
      warmth: warmth,
      attributes: Map<String, dynamic>.from(
        chosen('attributes', observed['attributes']) as Map? ?? const {},
      ),
      fieldSources: sources,
      fieldConfidence: confidence,
      userOverrideFields: overrides.toList()..sort(),
      analyzerProvenance: Map<String, dynamic>.from(
        analyzer['analyzerProvenance'] as Map? ?? const {},
      ),
      setMembership: existing['setMembership'] is Map
          ? SetMembershipV2.fromMap(
              Map<String, dynamic>.from(existing['setMembership'] as Map),
            )
          : null,
    );
  }
}
