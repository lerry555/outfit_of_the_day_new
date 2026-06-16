import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import 'bottom_family_guidance.dart';
import 'footwear_family_guidance.dart';
import 'home_debug_logging.dart';

void logFamilyGuidanceExclusion({
  required String item,
  required String category,
  required String family,
  required List<String> preferred,
  required List<String> allowed,
  required List<String> discouraged,
  required String reason,
  String? canonicalType,
  String? subCategory,
  String? itemId,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[FAMILY_GUIDANCE_EXCLUSION] '
    'item=$item '
    'category=$category '
    'family=$family '
    'preferred=${preferred.join(",")} '
    'allowed=${allowed.join(",")} '
    'discouraged=${discouraged.join(",")} '
    'reason=$reason'
    '${canonicalType != null && canonicalType.isNotEmpty ? ' canonical=$canonicalType' : ''}'
    '${subCategory != null && subCategory.isNotEmpty ? ' subCategory=$subCategory' : ''}'
    '${itemId != null && itemId.isNotEmpty ? ' itemId=$itemId' : ''}',
  );
}

void logFamilyGuidanceClassificationProbe({
  required String category,
  required String canonicalType,
  required String classifiedFamily,
  required bool isPreferred,
  required bool isAllowed,
  required bool isDiscouraged,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[FAMILY_GUIDANCE_CLASSIFICATION_PROBE] '
    'category=$category '
    'canonical=$canonicalType '
    'classifiedFamily=$classifiedFamily '
    'isPreferred=$isPreferred '
    'isAllowed=$isAllowed '
    'isDiscouraged=$isDiscouraged',
  );
}

Map<String, dynamic> _probeItem(String canonicalType) {
  return <String, dynamic>{
    'canonical_type': canonicalType,
    'canonicalType': canonicalType,
    'name': canonicalType,
  };
}

void logFootwearCanonicalFamilyProbes({
  required FootwearFamilyGuidance guidance,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  const probes = <String>[
    'basketball_shoes',
    'running_shoes',
    'sport_shoes',
    'athletic_shoes',
    'training_shoes',
    'sneakers',
    'fashion_sneakers',
  ];
  for (final canonical in probes) {
    final item = _probeItem(canonical);
    final family = classifyFootwearFamily(item);
    logFamilyGuidanceClassificationProbe(
      category: 'footwear',
      canonicalType: canonical,
      classifiedFamily: family.wireName,
      isPreferred: guidance.isPreferred(family),
      isAllowed: guidance.isAllowed(family),
      isDiscouraged: guidance.isDiscouraged(family),
    );
  }
}

void logBottomCanonicalFamilyProbes({
  required BottomFamilyGuidance guidance,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  const probes = <String>[
    'corduroy_pants',
    'pants',
    'jeans',
  ];
  for (final canonical in probes) {
    final item = _probeItem(canonical);
    final family = classifyBottomFamily(item);
    logFamilyGuidanceClassificationProbe(
      category: 'bottom',
      canonicalType: canonical,
      classifiedFamily: family.wireName,
      isPreferred: guidance.isPreferred(family),
      isAllowed: guidance.isAllowed(family),
      isDiscouraged: guidance.isDiscouraged(family),
    );
    if (canonical == 'corduroy_pants') {
      debugPrint(
        '[FAMILY_GUIDANCE_CLASSIFICATION_PROBE] '
        'category=bottom '
        'canonical=corduroy_pants '
        'isHeavyBottom=${isHeavyBottomItem(item)}',
      );
    }
  }
}

String _itemLabel(Map<String, dynamic> item) {
  final name = (item['name'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  final sub =
      (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString().trim();
  if (sub.isNotEmpty) return sub;
  return (item['id'] ?? item['documentId'] ?? '').toString();
}

void logDiscouragedFamilyPoolExclusions({
  required List<Map<String, dynamic>> wardrobe,
  required Set<String> excludedDiscouragedFootwearIds,
  required Set<String> excludedDiscouragedBottomIds,
  required FootwearFamilyGuidance footwearGuidance,
  required BottomFamilyGuidance bottomGuidance,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;

  for (final raw in wardrobe) {
    final id = OutfitGenerationService.wardrobeItemId(raw);
    if (id.isEmpty) continue;

    if (excludedDiscouragedFootwearIds.contains(id) &&
        isFootwearWardrobeItem(raw)) {
      final family = classifyFootwearFamily(raw);
      final canonical =
          (raw['canonical_type'] ?? raw['canonicalType'] ?? '').toString();
      final sub = (raw['subCategoryKey'] ?? raw['subCategory'] ?? '')
          .toString();
      logFamilyGuidanceExclusion(
        item: _itemLabel(raw),
        category: 'footwear',
        family: family.wireName,
        preferred: footwearGuidance.preferredFamilies,
        allowed: footwearGuidance.allowedFamilies,
        discouraged: footwearGuidance.discouragedFamilies,
        reason: 'discouraged_footwear_pool_filter',
        canonicalType: canonical,
        subCategory: sub,
        itemId: id,
      );
    }

    if (excludedDiscouragedBottomIds.contains(id) &&
        isBottomWardrobeItem(raw)) {
      final family = classifyBottomFamily(raw);
      final canonical =
          (raw['canonical_type'] ?? raw['canonicalType'] ?? '').toString();
      final sub = (raw['subCategoryKey'] ?? raw['subCategory'] ?? '')
          .toString();
      logFamilyGuidanceExclusion(
        item: _itemLabel(raw),
        category: 'bottom',
        family: family.wireName,
        preferred: bottomGuidance.preferredFamilies,
        allowed: bottomGuidance.allowedFamilies,
        discouraged: bottomGuidance.discouragedFamilies,
        reason: 'discouraged_bottom_pool_filter',
        canonicalType: canonical,
        subCategory: sub,
        itemId: id,
      );
    }
  }
}

void logPreferredItemsInEffectiveExcluded({
  required List<Map<String, dynamic>> wardrobe,
  required Set<String> effectiveExcluded,
  required Set<String> callerExcludedItemIds,
  required Set<String> excludedDiscouragedFootwearIds,
  required Set<String> excludedDiscouragedBottomIds,
  required FootwearFamilyGuidance footwearGuidance,
  required BottomFamilyGuidance bottomGuidance,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;

  for (final raw in wardrobe) {
    final id = OutfitGenerationService.wardrobeItemId(raw);
    if (id.isEmpty || !effectiveExcluded.contains(id)) continue;

    if (isFootwearWardrobeItem(raw) &&
        footwearGuidance.isPreferred(classifyFootwearFamily(raw))) {
      final family = classifyFootwearFamily(raw).wireName;
      final source = excludedDiscouragedFootwearIds.contains(id)
          ? 'discouraged_footwear_pool_filter'
          : callerExcludedItemIds.contains(id)
              ? 'caller_excluded_item_ids'
              : 'other_effective_excluded';
      logFamilyGuidanceExclusion(
        item: _itemLabel(raw),
        category: 'footwear',
        family: family,
        preferred: footwearGuidance.preferredFamilies,
        allowed: footwearGuidance.allowedFamilies,
        discouraged: footwearGuidance.discouragedFamilies,
        reason: source,
        canonicalType:
            (raw['canonical_type'] ?? raw['canonicalType'] ?? '').toString(),
        subCategory:
            (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString(),
        itemId: id,
      );
    }

    if (isBottomWardrobeItem(raw) &&
        isBottomPreferredForGuidance(raw, bottomGuidance)) {
      final family = classifyBottomFamily(raw).wireName;
      final source = excludedDiscouragedBottomIds.contains(id)
          ? 'discouraged_bottom_pool_filter'
          : callerExcludedItemIds.contains(id)
              ? 'caller_excluded_item_ids'
              : 'other_effective_excluded';
      logFamilyGuidanceExclusion(
        item: _itemLabel(raw),
        category: 'bottom',
        family: family,
        preferred: bottomGuidance.preferredFamilies,
        allowed: bottomGuidance.allowedFamilies,
        discouraged: bottomGuidance.discouragedFamilies,
        reason: source,
        canonicalType:
            (raw['canonical_type'] ?? raw['canonicalType'] ?? '').toString(),
        subCategory:
            (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString(),
        itemId: id,
      );
    }
  }
}
