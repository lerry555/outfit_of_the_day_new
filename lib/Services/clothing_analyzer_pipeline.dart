import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import '../data/clothing_knowledge_base.dart';
import '../utils/ai_clothing_parser.dart';
import '../utils/slovak_display_name.dart';

/// Result of the Add Clothing analysis + KB + category mapping pipeline.
class ClothingAnalyzerPipelineResult {
  const ClothingAnalyzerPipelineResult({
    required this.suggestedName,
    required this.canonicalType,
    required this.layerRole,
    required this.categoryKey,
    required this.subCategoryKey,
    this.analyzerConfidence,
    this.detectedColors = const [],
    this.kbMatched = false,
  });

  final String suggestedName;
  final String canonicalType;
  final String layerRole;
  final String categoryKey;
  final String subCategoryKey;
  final int? analyzerConfidence;
  final List<String> detectedColors;
  final bool kbMatched;

  static const ClothingAnalyzerPipelineResult empty = ClothingAnalyzerPipelineResult(
    suggestedName: '',
    canonicalType: '',
    layerRole: '',
    categoryKey: '',
    subCategoryKey: '',
  );
}

/// Shared clothing image analysis used by Add Clothing (HTTP + KB + parser).
abstract final class ClothingAnalyzerPipeline {
  static const String analyzeEndpoint =
      'https://us-east1-outfitoftheday-4d401.cloudfunctions.net/analyzeClothingImage';

  static Future<ClothingAnalyzerPipelineResult> analyzeImageUrl(
    String imageUrl, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final resp = await http
        .post(
          Uri.parse(analyzeEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'imageUrl': imageUrl}),
        )
        .timeout(timeout);

    if (resp.statusCode != 200) {
      throw Exception('analyzeClothingImage ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('analyzeClothingImage response is not a JSON object');
    }

    return analyzeResponse(decoded);
  }

  /// Maps raw [analyzeClothingImage] JSON through KB + [AiClothingParser] (Add Clothing path).
  static ClothingAnalyzerPipelineResult analyzeResponse(Map<String, dynamic> m) {
    final prettyType = (m['type_pretty'] ?? m['type'] ?? '').toString().trim();
    final rawType = (m['type'] ?? '').toString().trim();
    var canonical = (m['canonical_type'] ?? '').toString().trim();
    final typeEvidence = '$rawType $prettyType'.toLowerCase();
    final canonicalLower = canonical.toLowerCase();

    if (canonicalLower == 'jacket') {
      final saysMikina = typeEvidence.contains('mikina') ||
          typeEvidence.contains('hoodie') ||
          typeEvidence.contains('sweatshirt');
      final saysHood =
          typeEvidence.contains('kapuc') || typeEvidence.contains('hood');
      if (saysMikina && saysHood) {
        canonical = 'hoodie';
      } else if (saysMikina) {
        canonical = 'sweatshirt';
      }
    }

    final colorsFromAi = _toStringList(m['colors'] ?? m['color']);
    final seasonsFromAi = _toStringList(m['season'] ?? m['seasons']);
    final brandFromAi = (m['brand'] ?? '').toString().trim();
    final primaryTypeFromAi = (m['primary_type'] ?? '').toString().trim();
    final secondaryTypeFromAi = (m['secondary_type'] ?? '').toString().trim();
    final materialFeelFromAi = (m['material_feel'] ?? '').toString().trim();
    final vibeFromAi = (m['vibe'] ?? '').toString().trim();
    final visualDescFromAi = (m['visual_description'] ?? '').toString().trim();
    var layerRoleFromAi = (m['layer_role'] ?? '').toString().trim();

    final kbItem = ClothingKnowledgeBase.resolveClothingType(
      canonicalType: canonical,
      type: rawType,
      typePretty: prettyType,
      primaryType: primaryTypeFromAi,
    );
    if (kbItem != null) {
      ClothingKnowledgeBase.logMatch(kbItem);
      layerRoleFromAi = kbItem.layerRole;
    } else {
      ClothingKnowledgeBase.logNoMatch(
        canonicalType: canonical,
        primaryType: primaryTypeFromAi,
        type: rawType,
        typePretty: prettyType,
      );
    }

    String? nextCat;
    String? nextSub;
    String? nextLayerRole;
    String? kbDisplayName = kbItem?.skName;

    final aiLayerForMapping =
        kbItem == null && layerRoleFromAi.isNotEmpty ? layerRoleFromAi : null;

    if (canonical.isNotEmpty &&
        canonical != 'sneakers' &&
        canonical != 'sneaker') {
      final mapped = AiClothingParser.fromCanonicalType(
        canonical,
        aiLayerRole: aiLayerForMapping,
      );
      if (mapped != null) {
        nextCat = mapped.categoryKey;
        nextSub = mapped.subCategoryKey;
        nextLayerRole = mapped.layerRole;
      }
    }

    if (nextCat == null || nextSub == null) {
      final mapped = AiClothingParser.mapType(
        AiParserInput(
          rawType: rawType,
          aiName: prettyType,
          userName: '',
          seasons: seasonsFromAi,
          brand: brandFromAi,
        ),
      );
      if (mapped != null) {
        nextCat = mapped.categoryKey;
        nextSub = mapped.subCategoryKey;
        if (kbItem == null) {
          nextLayerRole = AiClothingParser.resolveLayerRole(
            subCategoryKey: mapped.subCategoryKey,
            aiLayerRole: aiLayerForMapping,
          );
        }
      }
    }

    if (JacketV2Classifier.shouldClassify(
      currentSub: nextSub,
      canonicalType: canonical,
      primaryType: primaryTypeFromAi,
      rawType: rawType,
      prettyType: prettyType,
    )) {
      final jacketV2 = JacketV2Classifier.classify(
        primaryType: primaryTypeFromAi,
        secondaryType: secondaryTypeFromAi,
        warmthLevel: null,
        materialFeel: materialFeelFromAi,
        vibe: vibeFromAi,
        visualDescription: visualDescFromAi,
        rawType: rawType,
        prettyType: prettyType,
      );
      if (jacketV2 != null) {
        nextSub = jacketV2.subCategoryKey;
        nextCat = _findCategoryForSubKey(jacketV2.subCategoryKey);
        if (kbItem == null) {
          nextLayerRole = AiClothingParser.resolveLayerRole(
            subCategoryKey: jacketV2.subCategoryKey,
            aiLayerRole: aiLayerForMapping,
          );
        }
      }
    }

    if (kbItem != null) {
      nextLayerRole = kbItem.layerRole;
    } else if (nextSub != null) {
      nextLayerRole = AiClothingParser.resolveLayerRole(
        subCategoryKey: nextSub,
        aiLayerRole: aiLayerForMapping,
      );
    }

    final subKey = nextSub ?? '';
    final suggestedName = _computeSuggestedName(
      colors: colorsFromAi,
      subCategoryKey: subKey,
      kbDisplayName: kbDisplayName,
      canonicalType: canonical,
      prettyType: prettyType,
      rawType: rawType,
    );

    final confidenceRaw = m['confidence'];
    int? analyzerConfidence;
    if (confidenceRaw != null) {
      final n = num.tryParse(confidenceRaw.toString());
      if (n != null && n.isFinite) {
        analyzerConfidence = n.round().clamp(0, 100);
      }
    }

    return ClothingAnalyzerPipelineResult(
      suggestedName: suggestedName,
      canonicalType: canonical,
      layerRole: nextLayerRole ?? layerRoleFromAi,
      categoryKey: nextCat ?? '',
      subCategoryKey: subKey,
      analyzerConfidence: analyzerConfidence,
      detectedColors: colorsFromAi,
      kbMatched: kbItem != null,
    );
  }

  static String? _findCategoryForSubKey(String subKey) {
    for (final entry in subCategoryTree.entries) {
      if (entry.value.contains(subKey)) return entry.key;
    }
    return null;
  }

  static String _computeSuggestedName({
    required List<String> colors,
    required String subCategoryKey,
    required String? kbDisplayName,
    required String canonicalType,
    required String prettyType,
    required String rawType,
  }) {
    final subLabelRaw =
        (kbDisplayName ?? subCategoryLabels[subCategoryKey] ?? '').trim();
    if (subLabelRaw.isEmpty) {
      if (prettyType.isNotEmpty) return _upperFirst(prettyType);
      if (rawType.isNotEmpty) return _upperFirst(rawType);
      return '';
    }

    final baseColor = colors.isNotEmpty ? colors.first.trim() : '';
    if (baseColor.isEmpty) return _upperFirst(subLabelRaw);

    return buildSlovakDisplayName(
      baseColor: baseColor,
      clothingLabel: subLabelRaw,
      canonicalType: canonicalType.isNotEmpty ? canonicalType : null,
      subCategoryKey: subCategoryKey.isNotEmpty ? subCategoryKey : null,
    );
  }

  static String _upperFirst(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static List<String> _toStringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    return const [];
  }
}
