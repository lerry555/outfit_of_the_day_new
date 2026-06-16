import 'package:flutter/foundation.dart';

import 'bottom_family_guidance.dart';
import 'family_guidance_exclusion_audit.dart';
import 'footwear_family_guidance.dart';
import 'home_debug_logging.dart';
import 'stylist_layer_filter.dart';

/// Verbose candidate-generation audit ([CANDIDATE_GENERATION_AUDIT], etc.).
const bool kCandidateGenerationAudit = kDebugMode && kVerboseHomeLogs;

String auditWardrobeItemId(Map<String, dynamic> raw) {
  final v = raw['id'] ?? raw['documentId'];
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? '' : s;
}

String candidateAuditItemLabel(Map<String, dynamic> item) {
  final name = (item['name'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  final sub =
      (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString().trim();
  if (sub.isNotEmpty) return sub;
  final id = auditWardrobeItemId(item);
  return id.isEmpty ? 'unknown' : id;
}

String candidateAuditPoolLabels(Iterable<Map<String, dynamic>> items) {
  final labels = items.map(candidateAuditItemLabel).toList();
  if (labels.isEmpty) return '(none)';
  return labels.join(', ');
}

bool isAuditLongBottom(Map<String, dynamic> item) {
  final family = classifyBottomFamily(item);
  return family == BottomFamily.jeans || family == BottomFamily.pants;
}

bool isAuditSneaker(Map<String, dynamic> item) {
  return classifyFootwearFamily(item) == FootwearFamily.sneakers;
}

bool isAuditShortsBottom(Map<String, dynamic> item) {
  return classifyBottomFamily(item) == BottomFamily.shorts;
}

void logCandidateGenerationAudit({
  required int passIndex,
  required String passLabel,
  required int tempC,
  required List<Map<String, dynamic>> availableTops,
  required List<Map<String, dynamic>> availableMidLayers,
  required List<Map<String, dynamic>> availableOuterLayers,
  required List<Map<String, dynamic>> availableBottoms,
  required List<Map<String, dynamic>> availableFootwear,
  Set<String> excludedItemIds = const {},
}) {
  if (!kCandidateGenerationAudit) return;
  debugPrint(
    '[CANDIDATE_GENERATION_AUDIT] '
    'passIndex=$passIndex pass=$passLabel temp=${tempC}°C '
    'availableTops=${candidateAuditPoolLabels(availableTops)} '
    'availableMidLayers=${candidateAuditPoolLabels(availableMidLayers)} '
    'availableOuterLayers=${candidateAuditPoolLabels(availableOuterLayers)} '
    'availableBottoms=${candidateAuditPoolLabels(availableBottoms)} '
    'availableFootwear=${candidateAuditPoolLabels(availableFootwear)} '
    'excludedItemCount=${excludedItemIds.length}',
  );
}

void logCandidateBuild({
  required int candidateIndex,
  required String selectedTop,
  required String selectedBottom,
  required String selectedFootwear,
  required String? selectedOuter,
  required String selectionReason,
  int? generationAttempt,
  int? pickRankIndex,
}) {
  if (!kCandidateGenerationAudit) return;
  debugPrint(
    '[CANDIDATE_BUILD] '
    'candidateIndex=$candidateIndex '
    'selectedTop=$selectedTop '
    'selectedBottom=$selectedBottom '
    'selectedFootwear=$selectedFootwear '
    'selectedOuter=${selectedOuter ?? '(none)'} '
    'selectionReason=$selectionReason'
    '${generationAttempt != null ? ' generationAttempt=$generationAttempt' : ''}'
    '${pickRankIndex != null ? ' pickRankIndex=$pickRankIndex' : ''}',
  );
}

void logCandidateRejection({
  required String item,
  required String category,
  required String reason,
  String? detail,
  int? candidateIndex,
  int? passIndex,
}) {
  if (!kCandidateGenerationAudit) return;
  debugPrint(
    '[CANDIDATE_REJECTION] '
    'item=$item '
    'category=$category '
    'reason=$reason'
    '${detail != null && detail.isNotEmpty ? ' detail=$detail' : ''}'
    '${candidateIndex != null ? ' candidateIndex=$candidateIndex' : ''}'
    '${passIndex != null ? ' passIndex=$passIndex' : ''}',
  );
}

void logTrackedBottomFootwearPoolStatus({
  required List<Map<String, dynamic>> wardrobe,
  required Set<String> excludedItemIds,
  required Set<String> callerExcludedItemIds,
  required Set<String> excludedDiscouragedFootwearIds,
  required Set<String> excludedDiscouragedBottomIds,
  required FootwearFamilyGuidance footwearGuidance,
  required BottomFamilyGuidance bottomGuidance,
  required List<Map<String, dynamic>> genTops,
  required List<Map<String, dynamic>> genBottoms,
  required List<Map<String, dynamic>> genFootwear,
  required int tempC,
  int passIndex = 0,
}) {
  if (!kCandidateGenerationAudit) return;

  final stylistWeather = StylistWeatherContext(
    tempC: tempC,
    isRainy: false,
    isWindy: false,
    seasonKey: '',
  );

  for (final raw in wardrobe) {
    final id = auditWardrobeItemId(raw);
    final label = candidateAuditItemLabel(raw);

    if (isAuditLongBottom(raw)) {
      _logTrackedItemPoolStatus(
        item: raw,
        label: label,
        category: 'bottom',
        excludedItemIds: excludedItemIds,
        callerExcludedItemIds: callerExcludedItemIds,
        excludedDiscouragedFootwearIds: excludedDiscouragedFootwearIds,
        excludedDiscouragedBottomIds: excludedDiscouragedBottomIds,
        footwearGuidance: footwearGuidance,
        bottomGuidance: bottomGuidance,
        inGenPool: genBottoms.any(
          (it) => auditWardrobeItemId(it) == id,
        ),
        stylistWeather: stylistWeather,
        passIndex: passIndex,
      );
    }

    if (isAuditSneaker(raw)) {
      _logTrackedItemPoolStatus(
        item: raw,
        label: label,
        category: 'footwear',
        excludedItemIds: excludedItemIds,
        callerExcludedItemIds: callerExcludedItemIds,
        excludedDiscouragedFootwearIds: excludedDiscouragedFootwearIds,
        excludedDiscouragedBottomIds: excludedDiscouragedBottomIds,
        footwearGuidance: footwearGuidance,
        bottomGuidance: bottomGuidance,
        inGenPool: genFootwear.any(
          (it) => auditWardrobeItemId(it) == id,
        ),
        stylistWeather: stylistWeather,
        passIndex: passIndex,
      );
    }
  }
}

void _logTrackedItemPoolStatus({
  required Map<String, dynamic> item,
  required String label,
  required String category,
  required Set<String> excludedItemIds,
  required Set<String> callerExcludedItemIds,
  required Set<String> excludedDiscouragedFootwearIds,
  required Set<String> excludedDiscouragedBottomIds,
  required FootwearFamilyGuidance footwearGuidance,
  required BottomFamilyGuidance bottomGuidance,
  required bool inGenPool,
  required StylistWeatherContext stylistWeather,
  required int passIndex,
}) {
  final id = auditWardrobeItemId(item);
  if (id.isNotEmpty && excludedItemIds.contains(id)) {
    final canonical =
        (item['canonical_type'] ?? item['canonicalType'] ?? '').toString();
    final sub =
        (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString();

    if (category == 'footwear' &&
        excludedDiscouragedFootwearIds.contains(id)) {
      final family = classifyFootwearFamily(item);
      logFamilyGuidanceExclusion(
        item: label,
        category: category,
        family: family.wireName,
        preferred: footwearGuidance.preferredFamilies,
        allowed: footwearGuidance.allowedFamilies,
        discouraged: footwearGuidance.discouragedFamilies,
        reason: 'discouraged_footwear_pool_filter',
        canonicalType: canonical,
        subCategory: sub,
        itemId: id,
      );
      logCandidateRejection(
        item: label,
        category: category,
        reason: 'family_guidance',
        detail: 'excluded_from_pool_by_guidance_filter',
        passIndex: passIndex,
      );
      return;
    }

    if (category == 'bottom' && excludedDiscouragedBottomIds.contains(id)) {
      final family = classifyBottomFamily(item);
      logFamilyGuidanceExclusion(
        item: label,
        category: category,
        family: family.wireName,
        preferred: bottomGuidance.preferredFamilies,
        allowed: bottomGuidance.allowedFamilies,
        discouraged: bottomGuidance.discouragedFamilies,
        reason: 'discouraged_bottom_pool_filter',
        canonicalType: canonical,
        subCategory: sub,
        itemId: id,
      );
      logCandidateRejection(
        item: label,
        category: category,
        reason: 'family_guidance',
        detail: 'excluded_from_pool_by_guidance_filter',
        passIndex: passIndex,
      );
      return;
    }

    if (callerExcludedItemIds.contains(id)) {
      logCandidateRejection(
        item: label,
        category: category,
        reason: 'caller_excluded',
        detail: 'excluded_by_caller_item_ids_not_family_guidance',
        passIndex: passIndex,
      );
      return;
    }

    logCandidateRejection(
      item: label,
      category: category,
      reason: 'excluded_other',
      detail: 'in_effective_excluded_unknown_source',
      passIndex: passIndex,
    );
    return;
  }

  if (!inGenPool) {
    final usable = StylistLayerFilter.isItemUsableForWeather(
      item,
      stylistWeather,
      log: false,
    );
    logCandidateRejection(
      item: label,
      category: category,
      reason: usable ? 'no_valid_combination' : 'warmth_target',
      detail: usable
          ? 'not_in_generator_slot_pool'
          : 'removed_by_stylist_layer_filter',
      passIndex: passIndex,
    );
  }
}

void logRankedSlotRejections({
  required String slotCategory,
  required List<Map<String, dynamic>> rankedPool,
  required Map<String, dynamic>? selected,
  required double Function(Map<String, dynamic>) scoreFn,
  required bool Function(Map<String, dynamic>) trackItem,
  int? candidateIndex,
  int? passIndex,
  int pickRankIndex = 0,
}) {
  if (!kCandidateGenerationAudit) return;
  if (selected == null || rankedPool.isEmpty) return;

  final selectedId = auditWardrobeItemId(selected);
  final selectedScore = scoreFn(selected);
  final selectedRank = rankedPool.indexWhere(
    (it) => auditWardrobeItemId(it) == selectedId,
  );

  for (final it in rankedPool) {
    if (!trackItem(it)) continue;
    final id = auditWardrobeItemId(it);
    if (id.isNotEmpty && id == selectedId) continue;

    final rank = rankedPool.indexWhere(
      (candidate) => auditWardrobeItemId(candidate) == id,
    );
    final score = scoreFn(it);
    logCandidateRejection(
      item: candidateAuditItemLabel(it),
      category: slotCategory,
      reason: rank < pickRankIndex
          ? 'excluded_by_rejected_signature'
          : 'lower_score_than_selected',
      detail: 'itemScore=${score.toStringAsFixed(2)} '
          'selectedScore=${selectedScore.toStringAsFixed(2)} '
          'itemRank=$rank selectedRank=$selectedRank pickRankIndex=$pickRankIndex',
      candidateIndex: candidateIndex,
      passIndex: passIndex,
    );
  }
}

void logPreviewBatchRejection({
  required String topLabel,
  required String bottomLabel,
  required Map<String, dynamic> bottomItem,
  required String shoesLabel,
  required Map<String, dynamic> shoesItem,
  required String? outerLabel,
  required String reason,
  String? detail,
  int? candidateIndex,
  int? passIndex,
}) {
  if (!kCandidateGenerationAudit) return;

  final comboParts = <String>[
    topLabel,
    bottomLabel,
    shoesLabel,
    if (outerLabel != null && outerLabel.isNotEmpty) outerLabel,
  ];
  final combo = comboParts.join(' + ');
  debugPrint(
    '[CANDIDATE_REJECTION] '
    'item=$combo '
    'category=combination '
    'reason=$reason'
    '${detail != null && detail.isNotEmpty ? ' detail=$detail' : ''}'
    '${candidateIndex != null ? ' candidateIndex=$candidateIndex' : ''}'
    '${passIndex != null ? ' passIndex=$passIndex' : ''}',
  );

  if (isAuditLongBottom(bottomItem)) {
    logCandidateRejection(
      item: bottomLabel,
      category: 'bottom',
      reason: reason,
      detail: detail ?? 'combo_rejected',
      candidateIndex: candidateIndex,
      passIndex: passIndex,
    );
  } else if (isAuditShortsBottom(bottomItem) &&
      (reason == 'family_guidance' || reason == 'layer_harmony_guard')) {
    logCandidateRejection(
      item: bottomLabel,
      category: 'bottom',
      reason: reason,
      detail: detail,
      candidateIndex: candidateIndex,
      passIndex: passIndex,
    );
  }

  if (isAuditSneaker(shoesItem)) {
    logCandidateRejection(
      item: shoesLabel,
      category: 'footwear',
      reason: reason,
      detail: detail ?? 'combo_rejected',
      candidateIndex: candidateIndex,
      passIndex: passIndex,
    );
  }
}

void logFinalCandidateAbsence({
  required List<Map<String, dynamic>> wardrobe,
  required Set<String> usedBottomIds,
  required Set<String> usedShoeIds,
  required int passIndex,
}) {
  if (!kCandidateGenerationAudit) return;

  for (final raw in wardrobe) {
    final id = auditWardrobeItemId(raw);
    if (id.isEmpty) continue;
    final label = candidateAuditItemLabel(raw);

    if (isAuditLongBottom(raw) && !usedBottomIds.contains(id)) {
      logCandidateRejection(
        item: label,
        category: 'bottom',
        reason: 'no_valid_combination',
        detail: 'never_selected_in_final_candidate_set',
        passIndex: passIndex,
      );
    }
    if (isAuditSneaker(raw) && !usedShoeIds.contains(id)) {
      logCandidateRejection(
        item: label,
        category: 'footwear',
        reason: 'no_valid_combination',
        detail: 'never_selected_in_final_candidate_set',
        passIndex: passIndex,
      );
    }
  }
}

List<Map<String, dynamic>> midLayersFromPool(List<Map<String, dynamic>> pool) {
  return pool
      .where(
        (it) => StylistLayerFilter.resolveEffectiveLayerRole(it) == 'mid_layer',
      )
      .toList();
}

void logCandidateMatrix({
  required int topCount,
  required int bottomCount,
  required int footwearCount,
  required int outerCount,
  required int combinationCount,
  required int keptCount,
  int? passIndex,
}) {
  if (!kCandidateGenerationAudit) return;
  debugPrint(
    '[CANDIDATE_MATRIX] '
    'topCount=$topCount '
    'bottomCount=$bottomCount '
    'footwearCount=$footwearCount '
    'outerCount=$outerCount '
    'combinationCount=$combinationCount '
    'keptCount=$keptCount'
    '${passIndex != null ? ' passIndex=$passIndex' : ''}',
  );
}

void logCandidateForcedCombo({
  required String reason,
  required String bottom,
  required String footwear,
  required String? outer,
  String? top,
}) {
  if (!kCandidateGenerationAudit) return;
  debugPrint(
    '[CANDIDATE_FORCED_COMBO] '
    'reason=$reason '
    'bottom=$bottom '
    'footwear=$footwear '
    'outer=${outer ?? '(none)'}'
    '${top != null && top.isNotEmpty ? ' top=$top' : ''}',
  );
}
