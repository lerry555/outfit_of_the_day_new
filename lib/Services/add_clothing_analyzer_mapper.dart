import 'dart:convert';

import '../constants/app_constants.dart';
import '../data/clothing_knowledge_base.dart';
import '../domain/wardrobe_v2/wardrobe_v1_retirement.dart';
import '../utils/ai_clothing_parser.dart';
import 'color_naming_service.dart';
import 'wardrobe_v2_edit_prepopulation.dart';

/// Deterministic Add Clothing interpretation of an `analyzeClothingImage`
/// wardrobe-analyzer-v2 JSON response.
///
/// When nested `wardrobeV2` has a KB-known `canonicalType`, the initial form
/// is a projection of that V2 identity. Nested [wardrobeV2] is still passed
/// through without mutation. Manual form edits are not written back to V2.
abstract final class AddClothingAnalyzerMapper {
  static const Set<String> serverV2IdentityKeys = {
    'canonicalType',
    'canonicalFamily',
    'bodySlots',
    'layerPosition',
    'colorProfile',
    'formality',
    'warmth',
    'attributes',
    'outfitFunctions',
    'uiProjection',
    'accessoryGroup',
    'multiplicity',
    'ontologyVersion',
    'taxonomyVersion',
    'kbVersion',
    'fieldSources',
    'fieldConfidence',
    'userOverrideFields',
    'analyzerProvenance',
    'setMembership',
    'occasionFit',
  };

  /// Client-owned overlays that Add currently persists on top of spread V2.
  static const Set<String> clientOverlayKeys = {
    'seasons',
    'styles',
    'patterns',
    'name',
    'brand',
  };

  /// V2 keys that current Add save also overwrites via hidden AI metadata.
  /// `warmth` is not in this set: hidden stores `warmth_level`, which is stripped.
  /// `formality` is no longer overlaid when authoritative V2 is present.
  static const Set<String> v2KeysCurrentlyOverlaidByClient = {
    'styles',
    'seasons',
  };

  /// Maps decoded analyzer JSON the same way `_fillWithAi` did inline.
  ///
  /// [existingAutoName] is the form auto-name at mapping time, used only as
  /// `AiClothingParser.mapType` `userName` fallback input.
  static AddClothingAnalyzerMapperResult map(
    Map<String, dynamic> response, {
    String existingAutoName = '',
  }) {
    final m = response;
    print('AI FULL RESPONSE: ${jsonEncode(m)}');

    final wardrobeV2Raw = m['wardrobeV2'];
    final wardrobeV2 = wardrobeV2Raw is Map<String, dynamic>
        ? wardrobeV2Raw
        : (wardrobeV2Raw is Map
              ? Map<String, dynamic>.from(wardrobeV2Raw)
              : null);
    final v2Canonical = (wardrobeV2?['canonicalType'] ?? '').toString().trim();
    final v2Kb = v2Canonical.isEmpty
        ? null
        : ClothingKnowledgeBase.findByCanonicalType(v2Canonical);
    final useV2Identity = v2Kb != null;

    final prettyType = (m['type_pretty'] ?? m['type'] ?? '').toString().trim();
    final rawType = (m['type'] ?? '').toString().trim();
    var canonical = useV2Identity
        ? v2Canonical
        : (m['canonical_type'] ?? '').toString().trim();
    final brandFromAi = recognizedBrandOrEmpty(m['brand']);
    final typeEvidence = '$rawType $prettyType'.toLowerCase();
    final canonicalLower = canonical.toLowerCase();

    if (!useV2Identity && canonicalLower == 'jacket') {
      final saysMikina =
          typeEvidence.contains('mikina') ||
          typeEvidence.contains('hoodie') ||
          typeEvidence.contains('sweatshirt');
      final saysHood =
          typeEvidence.contains('kapuc') || typeEvidence.contains('hood');

      if (saysMikina && saysHood) {
        print(
          'AI TYPE GUARD => overriding canonical "jacket" to "hoodie" '
          'because raw="$rawType", pretty="$prettyType"',
        );
        canonical = 'hoodie';
      } else if (saysMikina) {
        print(
          'AI TYPE GUARD => overriding canonical "jacket" to "sweatshirt" '
          'because raw="$rawType", pretty="$prettyType"',
        );
        canonical = 'sweatshirt';
      }
    } else if (useV2Identity) {
      final bridgeCanonical = (m['canonical_type'] ?? '').toString().trim();
      if (bridgeCanonical.isNotEmpty && bridgeCanonical != v2Canonical) {
        print(
          'AI TYPE GUARD skipped; wardrobeV2.canonicalType="$v2Canonical" '
          'bridge canonical_type="$bridgeCanonical" raw="$rawType" pretty="$prettyType"',
        );
      }
    }

    final colorsFromAi = toStringList(m['colors'] ?? m['color']);
    final stylesFromAi = toStringList(m['style'] ?? m['styles']);
    final patternsFromAi = toStringList(m['patterns'] ?? m['pattern']);
    final seasonsFromAi = toStringList(m['season'] ?? m['seasons']);
    final primaryTypeFromAi = (m['primary_type'] ?? '').toString().trim();
    final secondaryTypeFromAi = (m['secondary_type'] ?? '').toString().trim();
    final materialFeelFromAi = (m['material_feel'] ?? '').toString().trim();
    final vibeFromAi = (m['vibe'] ?? '').toString().trim();
    final visualDescFromAi = (m['visual_description'] ?? '').toString().trim();
    var layerRoleFromAi = (m['layer_role'] ?? '').toString().trim();
    int? warmthLevelFromAi;
    if (m['warmth_level'] != null) {
      final n = num.tryParse(m['warmth_level'].toString());
      if (n != null) warmthLevelFromAi = n.round().clamp(1, 10);
    }

    int? formalityFromAi;
    if (m['formality'] != null) {
      final n = num.tryParse(m['formality'].toString());
      if (n != null) formalityFromAi = n.round().clamp(1, 10);
    }

    final kbItem = useV2Identity
        ? v2Kb
        : ClothingKnowledgeBase.resolveClothingType(
            canonicalType: canonical,
            type: rawType,
            typePretty: prettyType,
            primaryType: primaryTypeFromAi,
          );
    String? kbTypeDisplayName;
    if (kbItem != null) {
      ClothingKnowledgeBase.logMatch(kbItem);
      layerRoleFromAi = kbItem.layerRole;
      if (!useV2Identity) {
        warmthLevelFromAi = kbItem.warmthDefault;
        formalityFromAi = kbItem.formalityDefault;
      }
      kbTypeDisplayName = kbItem.skName;
    } else {
      ClothingKnowledgeBase.logNoMatch(
        canonicalType: canonical,
        primaryType: primaryTypeFromAi,
        type: rawType,
        typePretty: prettyType,
      );
      kbTypeDisplayName = null;
    }

    String? nextMain;
    String? nextCat;
    String? nextSub;
    String? nextLayerRole;

    final aiLayerForMapping = kbItem == null && layerRoleFromAi.isNotEmpty
        ? layerRoleFromAi
        : null;

    if (useV2Identity) {
      nextMain = kbItem!.mainCategory;
      nextCat = kbItem.category;
      nextSub = kbItem.subcategory;
      nextLayerRole = kbItem.layerRole;
      print(
        'AI TYPE V2 IDENTITY => canonical="$canonical" => '
        'main="$nextMain", cat="$nextCat", sub="$nextSub", layer="$nextLayerRole"',
      );
    } else if (canonical.isNotEmpty &&
        canonical != 'sneakers' &&
        canonical != 'sneaker') {
      final mapped = AiClothingParser.fromCanonicalType(
        canonical,
        aiLayerRole: aiLayerForMapping,
      );
      if (mapped != null) {
        nextMain = mapped.mainGroupKey;
        nextCat = mapped.categoryKey;
        nextSub = mapped.subCategoryKey;
        nextLayerRole = mapped.layerRole;
      }
    }

    if (nextMain == null || nextCat == null || nextSub == null) {
      final mapped = AiClothingParser.mapType(
        AiParserInput(
          rawType: rawType,
          aiName: prettyType,
          userName: existingAutoName,
          seasons: seasonsFromAi,
          brand: brandFromAi,
        ),
      );

      if (mapped != null) {
        nextMain = mapped.mainGroupKey;
        nextCat = mapped.categoryKey;
        nextSub = mapped.subCategoryKey;
        if (kbItem == null) {
          nextLayerRole = AiClothingParser.resolveLayerRole(
            subCategoryKey: mapped.subCategoryKey,
            aiLayerRole: aiLayerForMapping,
          );
        }

        print(
          'AI TYPE FALLBACK OK => canonical="$canonical", raw="$rawType", pretty="$prettyType" => '
          'main="$nextMain", cat="$nextCat", sub="$nextSub", layer="$nextLayerRole"',
        );
      } else {
        print(
          'AI TYPE MAPPING FAILED => canonical="$canonical", raw="$rawType", pretty="$prettyType"',
        );
      }
    } else {
      print(
        'AI TYPE CANONICAL OK => canonical="$canonical" => '
        'main="$nextMain", cat="$nextCat", sub="$nextSub", layer="$nextLayerRole"',
      );
    }

    if (AiClothingParser.isTrackJacketSignal(
      canonicalType: canonical,
      primaryType: primaryTypeFromAi,
      rawType: rawType,
      prettyType: prettyType,
    )) {
      print(
        'AI TYPE TRACK_JACKET OK => canonical=$canonical primary=$primaryTypeFromAi '
        'sub=$nextSub layer_role=${aiLayerForMapping ?? nextLayerRole ?? ''}',
      );
    }

    List<String>? jacketSeasonsOverride;
    if (!useV2Identity &&
        JacketV2Classifier.shouldClassify(
          currentSub: nextSub,
          canonicalType: canonical,
          primaryType: primaryTypeFromAi,
          rawType: rawType,
          prettyType: prettyType,
        )) {
      final jacketV2 = JacketV2Classifier.classify(
        primaryType: primaryTypeFromAi,
        secondaryType: secondaryTypeFromAi,
        warmthLevel: warmthLevelFromAi,
        materialFeel: materialFeelFromAi,
        vibe: vibeFromAi,
        visualDescription: visualDescFromAi,
        rawType: rawType,
        prettyType: prettyType,
      );
      JacketV2Classifier.logDecision(
        primaryType: primaryTypeFromAi,
        secondaryType: secondaryTypeFromAi,
        warmthLevel: warmthLevelFromAi,
        materialFeel: materialFeelFromAi,
        vibe: vibeFromAi,
        result: jacketV2,
      );
      if (jacketV2 != null) {
        nextSub = jacketV2.subCategoryKey;
        nextCat = _findCategoryForSubKey(jacketV2.subCategoryKey);
        nextMain = _findMainGroupForCategory(nextCat);
        if (kbItem == null) {
          nextLayerRole = AiClothingParser.resolveLayerRole(
            subCategoryKey: jacketV2.subCategoryKey,
            aiLayerRole: aiLayerForMapping,
          );
        }
        jacketSeasonsOverride = jacketV2.seasons;
      }
    }

    if (useV2Identity) {
      nextLayerRole = kbItem?.layerRole ?? nextLayerRole;
      final v2Warmth = _boundedLevel(wardrobeV2?['warmth']);
      final v2Formality = _boundedLevel(wardrobeV2?['formality']);
      if (v2Warmth != null) warmthLevelFromAi = v2Warmth;
      if (v2Formality != null) formalityFromAi = v2Formality;
    } else if (kbItem != null) {
      nextLayerRole = kbItem.layerRole;
      warmthLevelFromAi = kbItem.warmthDefault;
      formalityFromAi = kbItem.formalityDefault;
    } else if (nextSub != null) {
      nextLayerRole = AiClothingParser.resolveLayerRole(
        subCategoryKey: nextSub,
        aiLayerRole: aiLayerForMapping,
      );
    }

    print('CHECKPOINT 1 => after _reachMilestone(2)');
    final filteredColors = useV2Identity
        ? WardrobeV2EditPrepopulation.displayColorsFromProfile(
            wardrobeV2?['colorProfile'],
          )
        : ColorNamingService.instance.normalizeDisplayColors(colorsFromAi);
    final normalizedStylesFromAi = _normalizeStylesList(stylesFromAi);
    final resolvedSubKeyForRules = nextSub ?? '';

    final fixedPatterns = _applyPatternRules(
      patternsFromAi: patternsFromAi,
      brand: brandFromAi,
      prettyType: prettyType,
      rawType: rawType,
      subCategoryKey: resolvedSubKeyForRules,
    );

    final fixedStyles = _applyStyleRules(
      stylesFromAi: normalizedStylesFromAi,
      brand: brandFromAi,
      subCategoryKey: resolvedSubKeyForRules,
      patterns: fixedPatterns,
    );
    print('CHECKPOINT 2 => styles/patterns done');
    print('CHECKPOINT 2A => nextSub=$nextSub');
    print('CHECKPOINT 2B => fixedPatterns=$fixedPatterns');
    print('CHECKPOINT 2C => fixedStyles=$fixedStyles');
    final filteredSeasonsRaw = seasonsFromAi
        .map((e) => e.toString().trim())
        .where((s) => allowedSeasons.contains(s))
        .toList();
    print('CHECKPOINT S1 => filteredSeasonsRaw=$filteredSeasonsRaw');

    var filteredSeasons = sanitizeSeasons(filteredSeasonsRaw);
    print(
      'CHECKPOINT S2 => filteredSeasons after first sanitize=$filteredSeasons',
    );

    final typeForSeason = nextSub ?? '';
    print('CHECKPOINT S3 => typeForSeason=$typeForSeason');

    if (jacketSeasonsOverride != null) {
      filteredSeasons = jacketSeasonsOverride;
      print(
        'CHECKPOINT JACKET V2 => seasons from classifier: $filteredSeasons',
      );
    } else if (typeForSeason == 'bunda_zimna') {
      print('CHECKPOINT DIRECT WINTER => forcing winter seasons');
      filteredSeasons = ['jeseň', 'zima'];
      print(
        'CHECKPOINT DX => after direct winter assign, filteredSeasons=$filteredSeasons',
      );
    } else {
      print('CHECKPOINT B1 => entering season branch chain');

      if (typeForSeason == 'tielko') {
        filteredSeasons = ['jar', 'leto'];
      } else if (typeForSeason == 'undershirt') {
        filteredSeasons = ['celoročne'];
      } else if (typeForSeason == 'tenisky_fashion' ||
          typeForSeason == 'tenisky_sportove' ||
          typeForSeason == 'tenisky_bezecke' ||
          typeForSeason == 'obuv_treningova') {
        filteredSeasons = ['jar', 'leto', 'jeseň'];
      } else if (typeForSeason == 'bunda_prechodna' ||
          typeForSeason == 'bunda_riflova' ||
          typeForSeason == 'bunda_kozena' ||
          typeForSeason == 'bunda_bomber' ||
          typeForSeason == 'trenchcoat' ||
          typeForSeason == 'sako' ||
          typeForSeason == 'vesta' ||
          typeForSeason == 'flisova_bunda' ||
          typeForSeason == 'softshell_bunda') {
        if (filteredSeasons.isEmpty || filteredSeasons.contains('celoročne')) {
          filteredSeasons = ['jar', 'jeseň'];
        }
      } else if (typeForSeason == 'sveter_klasicky' ||
          typeForSeason == 'sveter_rolak' ||
          typeForSeason == 'sveter_kardigan' ||
          typeForSeason == 'sveter_pleteny') {
        print('CHECKPOINT SWEATER BRANCH');

        if (filteredSeasons.isEmpty || filteredSeasons.contains('celoročne')) {
          filteredSeasons = ['jeseň', 'zima'];
        }
        if (filteredSeasons.isEmpty || filteredSeasons.contains('celoročne')) {
          filteredSeasons = ['jar', 'jeseň'];
        }
      } else if (typeForSeason == 'crop_top' ||
          typeForSeason == 'sortky' ||
          typeForSeason == 'sortky_sportove' ||
          typeForSeason == 'sport_sortky' ||
          typeForSeason == 'sandale' ||
          typeForSeason == 'sandale_opatok' ||
          typeForSeason == 'slapky' ||
          typeForSeason == 'zabky' ||
          typeForSeason == 'espadrilky') {
        filteredSeasons = ['jar', 'leto'];
      }
    }

    print(
      'CHECKPOINT X => tesne pred final sanitize seasons, filteredSeasons=$filteredSeasons',
    );
    filteredSeasons = sanitizeSeasons(filteredSeasons);
    print('CHECKPOINT 3 => seasons done: $filteredSeasons');

    if (canonical == 'tank_top') {
      filteredSeasons = ['jar', 'leto'];
    } else if (canonical == 'undershirt') {
      filteredSeasons = ['celoročne'];
    } else if (canonical == 't_shirt') {
      filteredSeasons = ['celoročne'];
    } else if (canonical == 'longsleeve' || canonical == 'long_sleeve') {
      filteredSeasons = ['celoročne'];
    }

    final formPatterns = fixedPatterns.isNotEmpty
        ? <String>[fixedPatterns.first]
        : <String>[];

    final hiddenAiMetadata = _hiddenAiMetadataFromAnalysis(
      m,
      canonical: canonical,
      rawType: rawType,
      prettyType: prettyType,
      styles: fixedStyles,
      patterns: fixedPatterns,
      seasons: filteredSeasons,
      layerRoleFromAi: layerRoleFromAi.isNotEmpty ? layerRoleFromAi : null,
      warmthLevelFromAi: warmthLevelFromAi,
      formalityLevel: formalityFromAi,
      primaryTypeFromAi: primaryTypeFromAi,
      secondaryTypeFromAi: secondaryTypeFromAi,
    );

    return AddClothingAnalyzerMapperResult(
      mappedCanonicalType: canonical,
      rawType: rawType,
      prettyType: prettyType,
      primaryType: primaryTypeFromAi,
      secondaryType: secondaryTypeFromAi,
      mainGroupKey: nextMain,
      categoryKey: nextCat,
      subCategoryKey: nextSub,
      layerRole: nextLayerRole,
      aiStylingLayerRole: layerRoleFromAi.isNotEmpty ? layerRoleFromAi : null,
      warmthLevel: warmthLevelFromAi,
      formalityLevel: formalityFromAi,
      kbTypeDisplayName: kbTypeDisplayName,
      kbMatched: kbItem != null,
      displayColors: filteredColors,
      styles: fixedStyles,
      patterns: fixedPatterns,
      formPatterns: formPatterns,
      seasons: filteredSeasons,
      brand: brandFromAi,
      suggestedName: computeSuggestedName(
        displayColors: filteredColors,
        subCategoryKey: nextSub,
        kbTypeDisplayName: kbTypeDisplayName,
      ),
      wardrobeV2: wardrobeV2,
      wardrobeV2Raw: wardrobeV2Raw,
      hiddenAiMetadata: hiddenAiMetadata,
      materialFeel: materialFeelFromAi,
      vibe: vibeFromAi,
      visualDescription: visualDescFromAi,
      fit: (m['fit'] ?? '').toString().trim(),
      confidenceRaw: m['confidence'],
      usedAuthoritativeV2: useV2Identity,
    );
  }

  /// Documents the current Add save merge: spread server `wardrobeV2`, apply
  /// client overlays, then strip retired V1 aliases. Does not write Firestore.
  static Map<String, dynamic> characterizePostSaveDocument(
    AddClothingAnalyzerMapperResult mapped,
  ) {
    final hiddenAi = Map<String, dynamic>.from(mapped.hiddenAiMetadata);
    hiddenAi.remove('wardrobeV2');
    final compatibility = <String, dynamic>{
      if (mapped.wardrobeV2 != null) ...mapped.wardrobeV2!,
      'name': mapped.suggestedName,
      'brand': mapped.brand,
      'mainGroup': mapped.mainGroupKey,
      'mainGroupKey': mapped.mainGroupKey,
      'category': mapped.categoryKey,
      'categoryKey': mapped.categoryKey,
      'subCategory': mapped.subCategoryKey,
      'subCategoryKey': mapped.subCategoryKey,
      'layerRole': mapped.layerRole,
      'colors': mapped.displayColors,
      ...hiddenAi,
    };
    return WardrobeV1Retirement.stripRetiredFields(compatibility);
  }

  static String recognizedBrandOrEmpty(dynamic value) {
    final brand = (value ?? '').toString().trim();
    if (brand.isEmpty || _isUnknownBrandValue(brand)) return '';
    return brand;
  }

  static List<String> sanitizeSeasons(List<String> input) {
    final set = input.toSet();
    const four = {'jar', 'leto', 'jeseň', 'zima'};

    if (set.contains('celoročne')) return ['celoročne'];
    if (set.containsAll(four)) return ['celoročne'];

    return allowedSeasons.where((s) => set.contains(s)).toList();
  }

  static List<String> toStringList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => e.toString()).toList();

    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return [];
      return [s];
    }

    return [];
  }

  static String computeSuggestedName({
    required List<String> displayColors,
    required String? subCategoryKey,
    required String? kbTypeDisplayName,
  }) {
    final subKey = subCategoryKey;
    final subLabelRaw = (kbTypeDisplayName ?? subCategoryLabels[subKey] ?? '')
        .trim();

    String lowerFirst(String s) =>
        s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
    String upperFirst(String s) =>
        s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

    var colorPart = '';
    if (displayColors.isNotEmpty) {
      colorPart = _displayColorName(
        _colorToAdjectiveForSubcategory(
          displayColors.first,
          subKey ?? '',
          subLabelRaw,
        ).trim(),
      );
    }

    final subLabel = lowerFirst(subLabelRaw);
    final parts = [
      if (colorPart.isNotEmpty) colorPart,
      if (subLabel.isNotEmpty) subLabel,
    ];
    return upperFirst(parts.join(' ').trim());
  }

  static bool _isUnknownBrandValue(String value) {
    final normalized = _norm(value);
    return normalized == 'unknown' ||
        normalized == 'unknown brand' ||
        normalized == 'unknown_brand' ||
        normalized == 'unknownbrand' ||
        normalized == 'no brand' ||
        normalized == 'n/a' ||
        normalized == 'none' ||
        normalized == 'null' ||
        normalized == 'nezname' ||
        normalized == 'neznama' ||
        normalized == 'neznama znacka';
  }
}

class AddClothingAnalyzerMapperResult {
  const AddClothingAnalyzerMapperResult({
    required this.mappedCanonicalType,
    required this.rawType,
    required this.prettyType,
    required this.primaryType,
    required this.secondaryType,
    required this.mainGroupKey,
    required this.categoryKey,
    required this.subCategoryKey,
    required this.layerRole,
    required this.aiStylingLayerRole,
    required this.warmthLevel,
    required this.formalityLevel,
    required this.kbTypeDisplayName,
    required this.kbMatched,
    required this.displayColors,
    required this.styles,
    required this.patterns,
    required this.formPatterns,
    required this.seasons,
    required this.brand,
    required this.suggestedName,
    required this.wardrobeV2,
    required this.wardrobeV2Raw,
    required this.hiddenAiMetadata,
    required this.materialFeel,
    required this.vibe,
    required this.visualDescription,
    required this.fit,
    required this.confidenceRaw,
    required this.usedAuthoritativeV2,
  });

  /// Canonical used for the initial form. When [usedAuthoritativeV2] is true,
  /// this is `wardrobeV2.canonicalType`. Otherwise Phase 1 fallback/guards.
  /// This is NOT written over [wardrobeV2] `canonicalType`.
  final String mappedCanonicalType;
  final String rawType;
  final String prettyType;
  final String primaryType;
  final String secondaryType;
  final String? mainGroupKey;
  final String? categoryKey;
  final String? subCategoryKey;
  final String? layerRole;
  final String? aiStylingLayerRole;
  final int? warmthLevel;
  final int? formalityLevel;
  final String? kbTypeDisplayName;
  final bool kbMatched;
  final List<String> displayColors;
  final List<String> styles;
  final List<String> patterns;
  final List<String> formPatterns;
  final List<String> seasons;
  final String brand;
  final String suggestedName;

  /// Exact nested server payload when it is a JSON object; otherwise null.
  final Map<String, dynamic>? wardrobeV2;
  final Object? wardrobeV2Raw;
  final Map<String, dynamic> hiddenAiMetadata;
  final String materialFeel;
  final String vibe;
  final String visualDescription;
  final String fit;
  final Object? confidenceRaw;
  final bool usedAuthoritativeV2;

  bool get hasWardrobeV2Map => wardrobeV2 != null;
}

Map<String, dynamic> _hiddenAiMetadataFromAnalysis(
  Map<String, dynamic> m, {
  required String canonical,
  required String rawType,
  required String prettyType,
  required List<String> styles,
  required List<String> patterns,
  required List<String> seasons,
  String? layerRoleFromAi,
  int? warmthLevelFromAi,
  int? formalityLevel,
  String? primaryTypeFromAi,
  String? secondaryTypeFromAi,
}) {
  final hidden = <String, dynamic>{
    if (canonical.isNotEmpty) 'canonical_type': canonical,
    if (rawType.isNotEmpty) 'type': rawType,
    if (prettyType.isNotEmpty) 'type_pretty': prettyType,
    if (primaryTypeFromAi != null && primaryTypeFromAi.isNotEmpty)
      'primary_type': primaryTypeFromAi,
    if (secondaryTypeFromAi != null && secondaryTypeFromAi.isNotEmpty)
      'secondary_type': secondaryTypeFromAi,
    if (styles.isNotEmpty) 'styles': styles,
    if (patterns.isNotEmpty) 'patterns': patterns,
    if (seasons.isNotEmpty) 'seasons': seasons,
    if (layerRoleFromAi != null && layerRoleFromAi.isNotEmpty)
      'layer_role': layerRoleFromAi,
    if (warmthLevelFromAi != null) 'warmth_level': warmthLevelFromAi,
    if (formalityLevel != null) 'formality': formalityLevel,
  };

  for (final key in [
    'fit',
    if (formalityLevel == null) 'formality',
    'vibe',
    'logo_prominence',
    'occasion_fit',
    'material_feel',
    'visual_description',
    'visual_identity',
    'identity_confidence',
    'confidence',
    'debug_reason',
    'analyzerVersion',
    'analyzerProvider',
    'analyzerModel',
    'analyzerPromptVersion',
    'analyzerPromptHash',
    'wardrobeV2',
  ]) {
    final v = m[key];
    if (v == null) continue;
    if (v is String && v.trim().isEmpty) continue;
    if (v is List && v.isEmpty) continue;
    hidden[key] = v;
  }

  return hidden;
}

int? _boundedLevel(dynamic value) {
  if (value == null) return null;
  final n = num.tryParse(value.toString());
  if (n == null) return null;
  return n.round().clamp(1, 10);
}

String? _findCategoryForSubKey(String subKey) {
  for (final entry in subCategoryTree.entries) {
    if (entry.value.contains(subKey)) return entry.key;
  }
  return null;
}

String? _findMainGroupForCategory(String? categoryKey) {
  if (categoryKey == null) return null;
  for (final entry in categoryTree.entries) {
    if (entry.value.contains(categoryKey)) return entry.key;
  }
  return null;
}

String _norm(String s) {
  var out = s.toLowerCase().trim();

  const repl = {
    'á': 'a',
    'ä': 'a',
    'č': 'c',
    'ď': 'd',
    'é': 'e',
    'ě': 'e',
    'í': 'i',
    'ĺ': 'l',
    'ľ': 'l',
    'ň': 'n',
    'ó': 'o',
    'ô': 'o',
    'ŕ': 'r',
    'ř': 'r',
    'š': 's',
    'ť': 't',
    'ú': 'u',
    'ů': 'u',
    'ý': 'y',
    'ž': 'z',
  };

  final b = StringBuffer();
  for (final ch in out.split('')) {
    b.write(repl[ch] ?? ch);
  }

  out = b.toString();
  out = out.replaceAll(RegExp(r'\s+'), ' ');
  return out.trim();
}

List<String> _dedupeKeepAllowed(List<String> input, List<String> allowed) {
  final allowedNorm = {for (final s in allowed) _norm(s): s};
  final seen = <String>{};
  final out = <String>[];

  for (final item in input) {
    final key = _norm(item);
    final allowedValue = allowedNorm[key];
    if (allowedValue == null) continue;
    if (seen.add(_norm(allowedValue))) {
      out.add(allowedValue);
    }
  }

  return out;
}

List<String> _applyStyleRules({
  required List<String> stylesFromAi,
  required String brand,
  required String subCategoryKey,
  required List<String> patterns,
}) {
  final b = _norm(brand);
  final p = patterns.map(_norm).toList();

  final hasTextPattern = p.contains(_norm('textová potlač'));
  final hasGraphicPattern = p.contains(_norm('grafická potlač'));

  final isNikeFamily =
      b.contains('nike') ||
      b.contains('jordan') ||
      b.contains('adidas') ||
      b.contains('puma') ||
      b.contains('under armour') ||
      b.contains('reebok');

  var out = [...stylesFromAi];

  if (subCategoryKey == 'sport_tricko' ||
      subCategoryKey == 'sport_mikina' ||
      subCategoryKey == 'sport_leginy' ||
      subCategoryKey == 'sport_sortky' ||
      subCategoryKey == 'sport_suprava' ||
      subCategoryKey == 'sport_podprsenka' ||
      subCategoryKey == 'obuv_treningova' ||
      subCategoryKey == 'obuv_turisticka') {
    out = ['sport'];
  } else if (subCategoryKey == 'bluzka' ||
      subCategoryKey == 'sako' ||
      subCategoryKey == 'nohavice_elegantne' ||
      subCategoryKey == 'lodicky' ||
      subCategoryKey == 'poltopanky') {
    out.add('elegant');
    out.add('smart casual');
  } else if (subCategoryKey == 'kosela_klasicka' ||
      subCategoryKey == 'kosela_oversize' ||
      subCategoryKey == 'kosela_flanelova') {
    out.add('casual');
    out.add('smart casual');
  } else if (subCategoryKey == 'mikina_klasicka' ||
      subCategoryKey == 'mikina_na_zips' ||
      subCategoryKey == 'mikina_s_kapucnou' ||
      subCategoryKey == 'mikina_oversize') {
    out.add('casual');
    if (subCategoryKey == 'mikina_s_kapucnou' ||
        subCategoryKey == 'mikina_oversize') {
      out.add('streetwear');
    }
  } else if (subCategoryKey == 'sveter_klasicky' ||
      subCategoryKey == 'sveter_rolak' ||
      subCategoryKey == 'sveter_kardigan' ||
      subCategoryKey == 'sveter_pleteny') {
    out.add('casual');
    out.add('smart casual');
  } else if (subCategoryKey == 'tricko' ||
      subCategoryKey == 'tricko_dlhy_rukav' ||
      subCategoryKey == 'tielko' ||
      subCategoryKey == 'top_basic' ||
      subCategoryKey == 'crop_top' ||
      subCategoryKey == 'polo_tricko' ||
      subCategoryKey == 'body' ||
      subCategoryKey == 'korzet_top' ||
      subCategoryKey == 'undershirt') {
    out.add('casual');

    if (subCategoryKey == 'crop_top' || subCategoryKey == 'korzet_top') {
      out.add('streetwear');
    }

    if ((subCategoryKey == 'tricko' ||
            subCategoryKey == 'tricko_dlhy_rukav' ||
            subCategoryKey == 'tielko') &&
        isNikeFamily &&
        (hasTextPattern || hasGraphicPattern)) {
      out.removeWhere((s) => _norm(s) == _norm('sport'));
      out.removeWhere((s) => _norm(s) == _norm('športový'));
      out.removeWhere((s) => _norm(s) == _norm('sportový'));
      out.add('casual');
      out.add('streetwear');
    }
  } else if (subCategoryKey == 'rifle' ||
      subCategoryKey == 'rifle_skinny' ||
      subCategoryKey == 'rifle_wide_leg' ||
      subCategoryKey == 'rifle_mom' ||
      subCategoryKey == 'nohavice_klasicke' ||
      subCategoryKey == 'nohavice_chino' ||
      subCategoryKey == 'nohavice_cargo' ||
      subCategoryKey == 'sortky' ||
      subCategoryKey == 'sukna' ||
      subCategoryKey == 'sukna_mini' ||
      subCategoryKey == 'sukna_midi' ||
      subCategoryKey == 'sukna_maxi') {
    out.add('casual');
  } else if (subCategoryKey == 'tenisky_fashion') {
    out.add('casual');
    out.add('streetwear');
  } else if (subCategoryKey == 'tenisky_sportove' ||
      subCategoryKey == 'tenisky_bezecke') {
    out = ['sport'];
  } else if (subCategoryKey == 'kabelka' ||
      subCategoryKey == 'taska_crossbody' ||
      subCategoryKey == 'kabelka_listova' ||
      subCategoryKey == 'hodinky' ||
      subCategoryKey == 'sperky') {
    out.add('casual');
  }

  if (out.isEmpty) {
    out.add('casual');
  }

  return _dedupeKeepAllowed(out, allowedStyles);
}

List<String> _applyPatternRules({
  required List<String> patternsFromAi,
  required String brand,
  required String prettyType,
  required String rawType,
  required String subCategoryKey,
}) {
  final out = <String>[];
  final combined = _norm('$brand $prettyType $rawType');

  final hasTextHint =
      combined.contains('text') ||
      combined.contains('napis') ||
      combined.contains('nápis') ||
      combined.contains('letter') ||
      combined.contains('slogan');

  final hasGraphicHint =
      combined.contains('graphic') ||
      combined.contains('graf') ||
      combined.contains('logo') ||
      combined.contains('print') ||
      combined.contains('potlac') ||
      combined.contains('potlač');

  for (final p in patternsFromAi) {
    final mapped = _normalizePattern(p);
    if (mapped != null) out.add(mapped);
  }

  if (hasTextHint) {
    out.add('textová potlač');
  } else if (hasGraphicHint) {
    out.add('grafická potlač');
  }

  if (out.isEmpty &&
      (subCategoryKey == 'undershirt' ||
          subCategoryKey == 'tielko' ||
          subCategoryKey == 'top_basic' ||
          subCategoryKey == 'leginy' ||
          subCategoryKey == 'sport_leginy' ||
          subCategoryKey == 'nohavice_klasicke' ||
          subCategoryKey == 'rifle' ||
          subCategoryKey == 'tricko' ||
          subCategoryKey == 'tricko_dlhy_rukav')) {
    out.add('jednofarebné');
  }

  final deduped = _dedupeKeepAllowed(out, allowedPatterns);

  if (deduped.isEmpty) {
    return ['jednofarebné'];
  }

  if (deduped.contains('textová potlač')) return ['textová potlač'];
  if (deduped.contains('grafická potlač')) return ['grafická potlač'];
  if (deduped.contains('pruhované')) return ['pruhované'];
  if (deduped.contains('kockované')) return ['kockované'];
  if (deduped.contains('kamufláž')) return ['kamufláž'];

  return [deduped.first];
}

String? _normalizeStyle(String raw) {
  final v = _norm(raw);

  const map = {
    'basic': 'casual',
    'minimal': 'casual',
    'minimalist': 'casual',
    'everyday': 'casual',
    'everyday wear': 'casual',
    'casual': 'casual',
    'smart casual': 'smart casual',
    'smart-casual': 'smart casual',
    'business': 'business',
    'formal': 'formal',
    'sport': 'casual',
    'sporty': 'casual',
    'athletic': 'casual',
    'streetwear': 'streetwear',
    'street': 'streetwear',
    'elegant': 'elegantný',
  };

  final allowedMap = {for (final s in allowedStyles) _norm(s): s};

  final directAllowed = allowedMap[v];
  if (directAllowed != null) return directAllowed;

  final mapped = map[v];
  if (mapped != null) {
    final allowed2 = allowedMap[_norm(mapped)];
    if (allowed2 != null) return allowed2;

    if (v.contains('basic')) {
      final allowedBasic = allowedMap[_norm('casual')];
      if (allowedBasic != null) return allowedBasic;
    }
  }

  return null;
}

List<String> _normalizeStylesList(List<String> input) {
  final out = <String>[];
  for (final x in input) {
    final mapped = _normalizeStyle(x);
    if (mapped != null) out.add(mapped);
  }
  final seen = <String>{};
  return out.where((e) => seen.add(e)).toList();
}

String? _normalizePattern(String raw) {
  final v = _norm(raw);

  const map = {
    'plain': 'jednofarebné',
    'solid': 'jednofarebné',
    'no pattern': 'jednofarebné',
    'none': 'jednofarebné',
    'striped': 'pruhované',
    'stripes': 'pruhované',
    'stripe': 'pruhované',
    'plaid': 'kockované',
    'checkered': 'kockované',
    'checked': 'kockované',
    'tartan': 'kockované',
    'camo': 'kamufláž',
    'camouflage': 'kamufláž',
    'graphic': 'grafická potlač',
    'printed': 'grafická potlač',
    'print': 'grafická potlač',
    'logo': 'grafická potlač',
    'graficke': 'grafická potlač',
    'grafické': 'grafická potlač',
    'graficky': 'grafická potlač',
    'grafický': 'grafická potlač',
    'graficka': 'grafická potlač',
    'grafická': 'grafická potlač',
    'text': 'textová potlač',
    'lettering': 'textová potlač',
    'slogan': 'textová potlač',
  };

  final allowedMap = {for (final s in allowedPatterns) _norm(s): s};

  final direct = allowedMap[v];
  if (direct != null) return direct;

  final mapped = map[v];
  if (mapped != null) {
    final allowed = allowedMap[_norm(mapped)];
    if (allowed != null) return allowed;
  }

  if (v.contains('camo') || v.contains('camouflage')) {
    return allowedMap[_norm('kamufláž')];
  }
  if (v.contains('stripe')) {
    return allowedMap[_norm('pruhované')];
  }
  if (v.contains('plaid') || v.contains('check') || v.contains('tartan')) {
    return allowedMap[_norm('kockované')];
  }

  if (v.contains('text') || v.contains('letter') || v.contains('slogan')) {
    return allowedMap[_norm('textová potlač')];
  }
  if (v.contains('print') ||
      v.contains('graphic') ||
      v.contains('logo') ||
      v.contains('graf')) {
    return allowedMap[_norm('grafická potlač')];
  }

  return null;
}

bool _isPluralSubcategory(String subKey, String subLabelRaw) {
  final k = subKey.toLowerCase();
  final l = subLabelRaw.toLowerCase();

  return k.startsWith('nohavice_') ||
      k.startsWith('rifle') ||
      k.startsWith('sortky') ||
      k.startsWith('leginy') ||
      k.startsWith('tenisky_') ||
      k.startsWith('sandale') ||
      k.startsWith('cizmy_') ||
      k == 'gumaky' ||
      k == 'snehule' ||
      k == 'zabky' ||
      k == 'espadrilky' ||
      l.contains('nohavice') ||
      l.contains('rifle') ||
      l.contains('šortky') ||
      l.contains('legíny') ||
      l.contains('tenisky') ||
      l.contains('sandále') ||
      l.contains('čižmy') ||
      l.contains('gumáky') ||
      l.contains('snehule') ||
      l.contains('žabky') ||
      l.contains('espadrilky');
}

bool _isFeminineSubcategory(String subKey, String subLabelRaw) {
  final k = subKey.toLowerCase();
  final l = subLabelRaw.toLowerCase();

  return k.startsWith('mikina_') ||
      k.startsWith('bluzka') ||
      k.startsWith('kosela_') ||
      k.startsWith('bunda_') ||
      k == 'kabat' ||
      k == 'vesta' ||
      k == 'prsiplast' ||
      k == 'flisova_bunda' ||
      k.startsWith('sukna') ||
      k.startsWith('saty') ||
      k == 'ciapka' ||
      k == 'siltovka' ||
      k == 'kabelka' ||
      k == 'crossbody' ||
      k == 'totebag' ||
      k == 'listova_kabelka' ||
      l.contains('mikina') ||
      l.contains('blúzka') ||
      l.contains('košeľa') ||
      l.contains('bunda') ||
      l.contains('kabát') ||
      l.contains('vesta') ||
      l.contains('pršiplášť') ||
      l.contains('sukňa') ||
      l.contains('šaty') ||
      l.contains('čiapka') ||
      l.contains('šiltovka') ||
      l.contains('kabelka');
}

String _colorToAdjectiveForSubcategory(
  String color,
  String subKey,
  String subLabelRaw,
) {
  final c = color.trim();
  if (c.isEmpty) return c;

  if (_isPluralSubcategory(subKey, subLabelRaw)) {
    if (c.endsWith('á')) return '${c.substring(0, c.length - 1)}é';
    if (c.endsWith('a')) return '${c.substring(0, c.length - 1)}e';
    return c;
  }

  if (_isFeminineSubcategory(subKey, subLabelRaw)) {
    if (c.endsWith('é')) return '${c.substring(0, c.length - 1)}á';
    if (c.endsWith('e')) return '${c.substring(0, c.length - 1)}a';
    return c;
  }

  return c;
}

String _displayColorName(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}
