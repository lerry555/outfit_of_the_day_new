import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import '../domain/wardrobe_v2/flexible_outfit_result_v2.dart';
import '../data/outfit_intent.dart';
import 'bottom_family_guidance.dart';
import 'footwear_family_guidance.dart';
import 'stylist_layer_filter.dart';

/// Výsledok intent overlay skórovania jedného kandidáta.
class OutfitIntentScoreBreakdown {
  final double baseScore;
  final double intentBonus;
  final double intentPenalty;
  final double finalScore;
  final List<String> matchedIntent;
  final List<String> violatedNonNegotiables;

  const OutfitIntentScoreBreakdown({
    required this.baseScore,
    required this.intentBonus,
    required this.intentPenalty,
    required this.finalScore,
    this.matchedIntent = const [],
    this.violatedNonNegotiables = const [],
  });

  bool get isExcluded => violatedNonNegotiables.isNotEmpty;
}

enum TopIntentStyle {
  shirtOrBlouse,
  polo,
  smartCasual,
  casualTee,
  graphicTee,
  sportyCasual,
  unknown,
}

/// Intent overlay nad existujúcim generátorom — M2.
class OutfitIntentScorer {
  const OutfitIntentScorer._();

  static const double _preferredPrimaryBonus = 2.0;
  static const double _preferredSecondaryBonus = 1.0;
  static const double _discouragedPenalty = 2.5;
  static const double _notPreferredPenalty = 2.0;
  static const double _topMatchBonus = 1.5;
  static const double _excludedFinalScore = -999.0;

  static OutfitIntentScoreBreakdown evaluateFlexible({
    required V2FlexibleOutfitResult outfit,
    required OutfitIntent intent,
    required double baseScore,
  }) {
    final matched = <String>[];
    final violated = <String>[];
    var bonus = 0.0;
    var penalty = 0.0;
    final items = outfit.items.map((item) => item.item).toList(growable: false);
    final footwear = items.where((item) => item.bodySlots.contains('feet'));
    final lower = items.where((item) => item.bodySlots.contains('lower_body'));
    final hasSandals = footwear.any(
      (item) => item.canonicalType.contains('sandal'),
    );
    final hasShorts = lower.any(
      (item) => item.canonicalType.contains('shorts'),
    );
    if (intent.nonNegotiables.contains('bottom_shorts_forbidden') &&
        hasShorts) {
      violated.add('bottom_shorts_forbidden');
    }
    if ((intent.nonNegotiables.contains('footwear_sandals_forbidden') ||
            intent.nonNegotiables.contains('wet_ground_closed_footwear')) &&
        hasSandals) {
      violated.add('footwear_sandals_forbidden');
    }
    if (outfit.completeness.dressCodeComplete) {
      bonus += 2;
      matched.add('dress_code_complete');
    } else {
      penalty += 3;
    }
    if (outfit.completeness.weatherComplete) {
      bonus += 1;
      matched.add('weather_complete');
    }
    if ({'hike', 'hiking', 'mountains', 'mushroom', 'outdoor', 'nature_walk'}
            .contains(intent.activityType) &&
        footwear.any(
          (item) =>
              item.canonicalType.contains('dress_shoe') ||
              item.canonicalType.contains('oxford') ||
              item.canonicalType.contains('loafer'),
        )) {
      penalty += 8;
      matched.add('terrain_formal_footwear');
    }
    return OutfitIntentScoreBreakdown(
      baseScore: baseScore,
      intentBonus: bonus,
      intentPenalty: penalty,
      finalScore: violated.isEmpty
          ? baseScore + bonus - penalty
          : _excludedFinalScore,
      matchedIntent: matched,
      violatedNonNegotiables: violated,
    );
  }

  /// Bonus pre matrix [combinationScore] v generátore.
  static double combinationBonus({
    required OutfitPreview preview,
    required OutfitIntent intent,
  }) {
    final breakdown = evaluate(preview: preview, intent: intent, baseScore: 0);
    if (breakdown.isExcluded) return -50.0;
    return breakdown.intentBonus - breakdown.intentPenalty;
  }

  static OutfitIntentScoreBreakdown evaluate({
    required OutfitPreview preview,
    required OutfitIntent intent,
    required double baseScore,
  }) {
    final matched = <String>[];
    final violated = <String>[];
    var bonus = 0.0;
    var penalty = 0.0;

    final bottomFamily = classifyBottomFamily(preview.bottom.item).wireName;
    final footwearFamily = classifyFootwearFamily(preview.shoes.item).wireName;
    final topStyle = classifyTopIntentStyle(preview.top.item);

    if (intent.bottomForbidden.contains(bottomFamily)) {
      penalty += _discouragedPenalty;
      matched.add('bottom_forbidden:$bottomFamily');
    }
    if (intent.footwearForbidden.contains(footwearFamily)) {
      penalty += _discouragedPenalty;
      matched.add('footwear_forbidden:$footwearFamily');
    }

    for (final tag in intent.nonNegotiables) {
      switch (tag) {
        case 'bottom_shorts_forbidden':
          if (bottomFamily == BottomFamily.shorts.wireName) {
            violated.add(tag);
          }
        case 'footwear_sandals_forbidden':
        case 'wet_ground_closed_footwear':
          if (footwearFamily == FootwearFamily.sandals.wireName) {
            violated.add(tag);
          }
        case 'hike_jeans_discouraged':
          if (bottomFamily == BottomFamily.jeans.wireName) {
            penalty += _discouragedPenalty;
            matched.add(tag);
          }
        case 'mushroom_practical_footwear':
          if (footwearFamily == FootwearFamily.sandals.wireName) {
            violated.add(tag);
          } else if (footwearFamily == FootwearFamily.sneakers.wireName ||
              footwearFamily == FootwearFamily.boots.wireName) {
            bonus += _preferredSecondaryBonus;
            matched.add(tag);
          }
        case 'formal_closed_footwear_preferred':
          if (footwearFamily == FootwearFamily.formalShoes.wireName) {
            bonus += _preferredPrimaryBonus;
            matched.add(tag);
          }
        case 'barbecue_comfort_first':
          if (topStyle == TopIntentStyle.casualTee ||
              topStyle == TopIntentStyle.polo) {
            bonus += _preferredSecondaryBonus;
            matched.add(tag);
          }
      }
    }

    _applyPreferredFamilyBonus(
      family: bottomFamily,
      preferred: intent.bottomPreferred,
      matched: matched,
      prefix: 'bottom_preferred',
      onBonus: (value) => bonus += value,
    );
    _applyNotPreferredFamilyPenalty(
      family: bottomFamily,
      preferred: intent.bottomPreferred,
      forbidden: intent.bottomForbidden,
      matched: matched,
      prefix: 'bottom_not_preferred',
      onPenalty: (value) => penalty += value,
    );
    _applyPreferredFamilyBonus(
      family: footwearFamily,
      preferred: intent.footwearPreferred,
      matched: matched,
      prefix: 'footwear_preferred',
      onBonus: (value) => bonus += value,
    );
    _applyNotPreferredFamilyPenalty(
      family: footwearFamily,
      preferred: intent.footwearPreferred,
      forbidden: intent.footwearForbidden,
      matched: matched,
      prefix: 'footwear_not_preferred',
      onPenalty: (value) => penalty += value,
    );

    final topEligibility = classifyTopEligibility(
      item: preview.top.item,
      intent: intent,
    );
    switch (topEligibility.eligibility) {
      case ItemEligibility.preferred:
        bonus += _topMatchBonus;
        matched.add('top_preferred');
      case ItemEligibility.acceptable:
        bonus += _preferredSecondaryBonus * 0.25;
        matched.add('top_acceptable');
      case ItemEligibility.compromise:
        penalty += 1.0;
        matched.add('top_compromise');
      case ItemEligibility.forbidden:
        penalty += 2.5;
        matched.add('top_emergency_compromise');
    }
    matched.add('top_eligibility:${topEligibility.reason}');

    final excluded = violated.isNotEmpty;
    final finalScore = excluded
        ? _excludedFinalScore
        : baseScore + bonus - penalty;

    return OutfitIntentScoreBreakdown(
      baseScore: baseScore,
      intentBonus: bonus,
      intentPenalty: penalty,
      finalScore: finalScore,
      matchedIntent: matched,
      violatedNonNegotiables: violated,
    );
  }

  static void logCandidate({
    required int candidateIndex,
    required OutfitPreview preview,
    required OutfitIntentScoreBreakdown breakdown,
  }) {
    final items = [
      preview.top.label,
      preview.bottom.label,
      preview.shoes.label,
      if (preview.outerwear != null) preview.outerwear!.label,
    ].join(' + ');
    debugPrint(
      'STYLIST CHAT intent_score { '
      'candidateIndex=$candidateIndex, '
      'items=$items, '
      'baseScore=${breakdown.baseScore.toStringAsFixed(2)}, '
      'intentBonus=${breakdown.intentBonus.toStringAsFixed(2)}, '
      'intentPenalty=${breakdown.intentPenalty.toStringAsFixed(2)}, '
      'finalScore=${breakdown.finalScore.toStringAsFixed(2)}, '
      'matchedIntent=${breakdown.matchedIntent.join("|")}, '
      'violatedNonNegotiables=${breakdown.violatedNonNegotiables.join("|")} '
      '}',
    );
  }

  static TopEligibilityResult classifyTopEligibility({
    required Map<String, dynamic> item,
    required OutfitIntent intent,
  }) {
    final style = classifyTopIntentStyle(item);
    final pref = intent.topPreference;
    final activity = intent.activityType;
    final isFormal = _isFormalActivity(activity);
    final isWork = activity == 'work';

    if (StylistLayerFilter.isTankTopItem(item)) {
      if (isFormal || isWork) {
        return TopEligibilityResult(
          eligibility: ItemEligibility.forbidden,
          reason: 'tank_top_$activity',
        );
      }
      if (pref == 'casual_top') {
        return const TopEligibilityResult(
          eligibility: ItemEligibility.acceptable,
          reason: 'tank_top_casual',
        );
      }
      return const TopEligibilityResult(
        eligibility: ItemEligibility.compromise,
        reason: 'tank_top_non_casual',
      );
    }

    if (style == TopIntentStyle.graphicTee) {
      if (isFormal) {
        return const TopEligibilityResult(
          eligibility: ItemEligibility.forbidden,
          reason: 'graphic_tee_formal',
        );
      }
      if (pref == 'shirt_or_blouse') {
        return const TopEligibilityResult(
          eligibility: ItemEligibility.forbidden,
          reason: 'graphic_tee_formal_pref',
        );
      }
      if (pref == 'casual_top') {
        return const TopEligibilityResult(
          eligibility: ItemEligibility.acceptable,
          reason: 'graphic_tee_casual',
        );
      }
      return const TopEligibilityResult(
        eligibility: ItemEligibility.compromise,
        reason: 'graphic_tee_work',
      );
    }

    if (style == TopIntentStyle.sportyCasual) {
      if (isFormal || isWork) {
        return TopEligibilityResult(
          eligibility: ItemEligibility.forbidden,
          reason: 'sporty_casual_$activity',
        );
      }
      if (pref == 'casual_top') {
        return const TopEligibilityResult(
          eligibility: ItemEligibility.acceptable,
          reason: 'sporty_casual_ok',
        );
      }
      return const TopEligibilityResult(
        eligibility: ItemEligibility.compromise,
        reason: 'sporty_casual_smart_casual',
      );
    }

    switch (pref) {
      case 'shirt_or_blouse':
        if (style == TopIntentStyle.shirtOrBlouse) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.preferred,
            reason: 'shirt_or_blouse_match',
          );
        }
        if (style == TopIntentStyle.smartCasual) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.acceptable,
            reason: 'smart_casual_formal',
          );
        }
        if (style == TopIntentStyle.polo) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.acceptable,
            reason: 'polo_formal_ok',
          );
        }
        if (style == TopIntentStyle.casualTee) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.compromise,
            reason: 'tee_formal_compromise',
          );
        }
        return const TopEligibilityResult(
          eligibility: ItemEligibility.compromise,
          reason: 'unknown_shirt_pref',
        );

      case 'polo_or_shirt':
        if (style == TopIntentStyle.polo) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.preferred,
            reason: 'polo_work_match',
          );
        }
        if (style == TopIntentStyle.shirtOrBlouse) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.acceptable,
            reason: 'shirt_work_ok',
          );
        }
        if (style == TopIntentStyle.smartCasual) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.acceptable,
            reason: 'smart_casual_work',
          );
        }
        if (style == TopIntentStyle.casualTee) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.compromise,
            reason: 'tee_work_compromise',
          );
        }
        return const TopEligibilityResult(
          eligibility: ItemEligibility.compromise,
          reason: 'unknown_polo_pref',
        );

      case 'smart_casual_top':
        if (style == TopIntentStyle.polo ||
            style == TopIntentStyle.shirtOrBlouse ||
            style == TopIntentStyle.smartCasual) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.preferred,
            reason: 'smart_casual_match',
          );
        }
        if (style == TopIntentStyle.casualTee) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.acceptable,
            reason: 'tee_smart_casual_ok',
          );
        }
        return const TopEligibilityResult(
          eligibility: ItemEligibility.compromise,
          reason: 'unknown_smart_casual',
        );

      case 'casual_top':
        if (style == TopIntentStyle.casualTee || style == TopIntentStyle.polo) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.preferred,
            reason: 'casual_top_match',
          );
        }
        if (style == TopIntentStyle.shirtOrBlouse ||
            style == TopIntentStyle.smartCasual) {
          return const TopEligibilityResult(
            eligibility: ItemEligibility.acceptable,
            reason: 'smart_item_casual_ok',
          );
        }
        return const TopEligibilityResult(
          eligibility: ItemEligibility.acceptable,
          reason: 'casual_default',
        );

      default:
        return const TopEligibilityResult(
          eligibility: ItemEligibility.acceptable,
          reason: 'no_top_preference',
        );
    }
  }

  static void logTopEligibility({
    required Map<String, dynamic> item,
    required TopEligibilityResult result,
  }) {
    final name = (item['name'] ?? item['label'] ?? '').toString().trim();
    final label = name.isNotEmpty
        ? name
        : (item['canonical_type'] ?? item['canonicalType'] ?? 'top')
              .toString()
              .trim();
    debugPrint(
      'STYLIST CHAT top_eligibility { '
      'item=$label, '
      'eligibility=${result.eligibility.wireName}, '
      'reason=${result.reason} '
      '}',
    );
  }

  static bool _isFormalActivity(String activity) {
    return activity == 'wedding' ||
        activity == 'interview' ||
        activity == 'funeral';
  }

  static TopIntentStyle classifyTopIntentStyle(Map<String, dynamic> item) {
    final blob = _itemBlob(item);
    final isShirtLike = _containsAny(blob, [
      'kosel',
      'shirt',
      'bluz',
      'blouse',
    ]);
    final isTeeLike = _containsAny(blob, [
      't-shirt',
      'tshirt',
      't_shirt',
      'trick',
      'tee',
    ]);
    if (isShirtLike && !isTeeLike) return TopIntentStyle.shirtOrBlouse;
    if (_containsAny(blob, ['polo'])) return TopIntentStyle.polo;
    if (_containsAny(blob, ['graphic', 'print', 'logo', 'graf'])) {
      return TopIntentStyle.graphicTee;
    }
    if (_containsAny(blob, ['hoodie', 'mikina', 'sport', 'jersey'])) {
      return TopIntentStyle.sportyCasual;
    }
    if (_containsAny(blob, ['tielko', 'tank'])) {
      return TopIntentStyle.sportyCasual;
    }
    if (_containsAny(blob, ['sweater', 'sveter', 'cardigan', 'rolak'])) {
      return TopIntentStyle.smartCasual;
    }
    if (isTeeLike) return TopIntentStyle.casualTee;
    return TopIntentStyle.unknown;
  }

  /// Intent-aware bonus pre top pool ranking.
  static double topPoolScoreAdjustment({
    required String topPreference,
    required Map<String, dynamic> item,
    required String activityType,
  }) {
    if (topPreference.isEmpty) return 0;
    final result = classifyTopEligibility(
      item: item,
      intent: OutfitIntent(
        activityType: activityType,
        idealSummarySk: '',
        bottomPreferred: const [],
        bottomForbidden: const [],
        footwearPreferred: const [],
        footwearForbidden: const [],
        topPreference: topPreference,
      ),
    );
    return switch (result.eligibility) {
      ItemEligibility.preferred => _topMatchBonus,
      ItemEligibility.acceptable => _preferredSecondaryBonus * 0.25,
      ItemEligibility.compromise => -1.0,
      ItemEligibility.forbidden => -10.0,
    };
  }

  /// Či top je [ItemEligibility.preferred] pre daný intent.
  static bool topMatchesPreference({
    required String topPreference,
    required Map<String, dynamic> item,
    required String activityType,
  }) {
    if (topPreference.isEmpty) return true;
    final result = classifyTopEligibility(
      item: item,
      intent: OutfitIntent(
        activityType: activityType,
        idealSummarySk: '',
        bottomPreferred: const [],
        bottomForbidden: const [],
        footwearPreferred: const [],
        footwearForbidden: const [],
        topPreference: topPreference,
      ),
    );
    return result.eligibility == ItemEligibility.preferred;
  }

  static void _applyPreferredFamilyBonus({
    required String family,
    required List<String> preferred,
    required List<String> matched,
    required String prefix,
    required void Function(double value) onBonus,
  }) {
    final index = preferred.indexOf(family);
    if (index < 0) return;
    onBonus(index == 0 ? _preferredPrimaryBonus : _preferredSecondaryBonus);
    matched.add('$prefix:$family');
  }

  static void _applyNotPreferredFamilyPenalty({
    required String family,
    required List<String> preferred,
    required List<String> forbidden,
    required List<String> matched,
    required String prefix,
    required void Function(double value) onPenalty,
  }) {
    if (preferred.isEmpty) return;
    if (preferred.contains(family) || forbidden.contains(family)) return;
    onPenalty(_notPreferredPenalty);
    matched.add('$prefix:$family');
  }

  static String _itemBlob(Map<String, dynamic> item) {
    return [
      item['name'],
      item['label'],
      item['canonical_type'],
      item['canonicalType'],
      item['category'],
      item['subCategory'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
  }

  static bool _containsAny(String blob, List<String> needles) {
    for (final needle in needles) {
      if (blob.contains(needle)) return true;
    }
    return false;
  }
}
