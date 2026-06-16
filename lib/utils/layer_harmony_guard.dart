import '../Services/outfit_generation_service.dart';
import 'bottom_family_guidance.dart';
import 'home_debug_logging.dart';
import 'stylist_layer_filter.dart';

/// Hard reject reasons for inconsistent layer combinations (pre–AI review).
class LayerHarmonyGuardResult {
  final bool rejected;
  final String? reason;

  const LayerHarmonyGuardResult._({
    required this.rejected,
    this.reason,
  });

  const LayerHarmonyGuardResult.accepted()
      : this._(rejected: false);

  const LayerHarmonyGuardResult.rejected(String reason)
      : this._(rejected: true, reason: reason);
}

String _normToken(String s) {
  return s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('č', 'c')
      .replaceAll('ď', 'd')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ľ', 'l')
      .replaceAll('ĺ', 'l')
      .replaceAll('ň', 'n')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ŕ', 'r')
      .replaceAll('š', 's')
      .replaceAll('ť', 't')
      .replaceAll('ú', 'u')
      .replaceAll('ý', 'y')
      .replaceAll('ž', 'z');
}

String _itemBlob(Map<String, dynamic> item) {
  return _normToken(
    [
      (item['name'] ?? '').toString(),
      (item['type_pretty'] ?? item['typePretty'] ?? '').toString(),
      (item['categoryKey'] ?? item['category'] ?? '').toString(),
      (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString(),
      (item['mainGroupKey'] ?? item['mainGroup'] ?? '').toString(),
      (item['canonical_type'] ?? item['canonicalType'] ?? '').toString(),
    ].join(' '),
  );
}

bool isOuterwearWardrobeItem(Map<String, dynamic> item) {
  final layer = _normToken(
    (item['layer_role'] ?? item['layerRole'] ?? item['stylingLayerRole'] ?? '')
        .toString(),
  );
  if (layer == 'outer_layer') return true;
  final b = _itemBlob(item);
  return b.contains('bunda') ||
      b.contains('kabat') ||
      b.contains('coat') ||
      b.contains('jacket') ||
      b.contains('mikina') ||
      b.contains('hoodie') ||
      b.contains('parka') ||
      b.contains('trench');
}

bool isHeavyOuterwearByMetadata(Map<String, dynamic> item) {
  final b = _itemBlob(item);
  return b.contains('zimn') ||
      b.contains('winter') ||
      b.contains('kabat') ||
      b.contains('heavy') ||
      b.contains('parka') ||
      b.contains('bunda_zimna') ||
      b.contains('bunda zimna');
}

bool isWinterOuterwearItem(Map<String, dynamic> item) {
  final warmth = StylistLayerFilter.inferWarmthLevel(item);
  if (warmth < 7) return false;
  final sub = _normToken(
    (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString(),
  );
  if (sub == 'bunda_zimna' || sub == 'kabat' || sub == 'trenchcoat') {
    return true;
  }
  return isHeavyOuterwearByMetadata(item);
}

bool isHeavyOuterItem(Map<String, dynamic> item) {
  final warmth = StylistLayerFilter.inferWarmthLevel(item);
  if (warmth >= 7) return true;
  return isHeavyOuterwearByMetadata(item);
}

bool isShortsBottomItem(Map<String, dynamic> item) {
  return classifyBottomFamily(item) == BottomFamily.shorts;
}

String previewCandidateItemsLabel(OutfitPreview preview) {
  final parts = <String>[
    preview.top.label,
    preview.bottom.label,
    preview.shoes.label,
    if (preview.outerwear != null) preview.outerwear!.label,
  ];
  return parts.join(' + ');
}

LayerHarmonyGuardResult evaluateLayerHarmony({
  required OutfitPreview preview,
  required int tempC,
}) {
  final outerItem = preview.outerwear?.item;
  final bottomItem = preview.bottom.item;
  final isShorts = isShortsBottomItem(bottomItem);

  if (outerItem == null) {
    return const LayerHarmonyGuardResult.accepted();
  }

  final outerWarmth = StylistLayerFilter.inferWarmthLevel(outerItem);
  final winterOuter = isWinterOuterwearItem(outerItem);
  final heavyOuter = isHeavyOuterItem(outerItem);

  if (isShorts && winterOuter) {
    return const LayerHarmonyGuardResult.rejected('winter_outer_with_shorts');
  }
  if (isShorts && (heavyOuter || outerWarmth >= 7)) {
    return const LayerHarmonyGuardResult.rejected('heavy_outer_with_shorts');
  }
  if (tempC >= 22 && winterOuter) {
    return const LayerHarmonyGuardResult.rejected('winter_outer_in_warm_weather');
  }
  if (tempC >= 20 && outerWarmth >= 7) {
    return const LayerHarmonyGuardResult.rejected('heavy_outer_in_warm_weather');
  }

  return const LayerHarmonyGuardResult.accepted();
}

void logLayerHarmonyGuard({
  required OutfitPreview preview,
  required int tempC,
  required LayerHarmonyGuardResult result,
}) {
  logVerboseHome(
    '[LAYER_HARMONY_GUARD] candidateItems=${previewCandidateItemsLabel(preview)} '
    'temp=$tempC rejected=${result.rejected} '
    'reason=${result.reason ?? 'none'}',
  );
}

bool previewPassesLayerHarmonyGuard({
  required OutfitPreview preview,
  required int tempC,
  bool log = true,
}) {
  final result = evaluateLayerHarmony(preview: preview, tempC: tempC);
  if (log) {
    logLayerHarmonyGuard(
      preview: preview,
      tempC: tempC,
      result: result,
    );
  }
  return !result.rejected;
}

/// Outerwear item ids to exclude when regenerating after all candidates rejected.
Set<String> layerHarmonyExcludedOuterIdsForRegeneration({
  required List<Map<String, dynamic>> wardrobe,
  required int tempC,
}) {
  final ids = <String>{};
  for (final raw in wardrobe) {
    if (!isOuterwearWardrobeItem(raw)) continue;
    final id = OutfitGenerationService.wardrobeItemId(raw);
    if (id.isEmpty) continue;
    if (isWinterOuterwearItem(raw)) {
      ids.add(id);
      continue;
    }
    if (tempC >= 20 && StylistLayerFilter.inferWarmthLevel(raw) >= 7) {
      ids.add(id);
    }
  }
  return ids;
}
