import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import '../domain/wardrobe_v2/flexible_outfit_result_v2.dart';
import '../data/outfit_intent.dart' show ItemEligibility, OutfitIntent;
import 'bottom_family_guidance.dart';
import 'footwear_family_guidance.dart';
import 'outfit_intent_scorer.dart';

/// Výsledok activity identity overlay — rozlíši outfity medzi aktivitami.
class ActivityIdentityResult {
  const ActivityIdentityResult({required this.score, this.reasons = const []});

  final double score;
  final List<String> reasons;
}

/// Slot-aware skórovanie identity outfitu podľa aktivity (overlay nad comfort/intent).
class ActivityOutfitIdentity {
  const ActivityOutfitIdentity._();

  /// Aktivity typu „smart / neat casual" (spoločenské) — rande, kino, večera.
  /// Preferujú clean/smart casual, nie outdoor look.
  static const Set<String> socialSmartCasualTypes = {
    'date',
    'cinema',
    'dinner',
  };

  static ActivityIdentityResult evaluateFlexible({
    required V2FlexibleOutfitResult outfit,
    required OutfitIntent intent,
    bool wetGroundMuddy = false,
  }) {
    final items = outfit.items.map((item) => item.item).toList(growable: false);
    var score = 0.0;
    final reasons = <String>[];
    final outdoor = items.any(
      (item) =>
          item.occasionFit.contains('outdoor') ||
          item.styles.contains('outdoor'),
    );
    final formal =
        items.isNotEmpty &&
        items.map((item) => item.formality).reduce((a, b) => a < b ? a : b) >=
            6;
    final closedFootwear = items
        .where((item) => item.bodySlots.contains('feet'))
        .every((item) => !item.canonicalType.contains('sandal'));
    if (intent.activityType == 'hike' || intent.activityType == 'outdoor') {
      score += outdoor ? 3 : -2;
      reasons.add(outdoor ? 'v2_outdoor_fit' : 'v2_outdoor_gap');
    }
    if ({'wedding', 'interview', 'funeral'}.contains(intent.activityType)) {
      score += formal ? 3 : -3;
      reasons.add(formal ? 'v2_formality_fit' : 'v2_formality_gap');
    }
    if (wetGroundMuddy && !closedFootwear) {
      score -= 3;
      reasons.add('v2_wet_ground_open_footwear');
    }
    return ActivityIdentityResult(score: score, reasons: reasons);
  }

  /// [forOpinion] zapína hodnotenie výhradne pre StylistOpinion — pridáva
  /// penalizáciu outdoor obuvi a bonus za clean sneakers pri date/cinema/dinner.
  /// Výber outfitu (selection) volá bez tohto flagu, takže sa nemení.
  static ActivityIdentityResult evaluate({
    required OutfitPreview preview,
    required OutfitIntent intent,
    bool wetGroundMuddy = false,
    bool forOpinion = false,
  }) {
    final reasons = <String>[];
    var score = 0.0;

    void bonus(double value, String reason) {
      if (value == 0) return;
      score += value;
      reasons.add(reason);
    }

    void penalty(double value, String reason) {
      if (value == 0) return;
      score -= value;
      reasons.add(reason);
    }

    final top = preview.top.item;
    final bottom = preview.bottom.item;
    final shoes = preview.shoes.item;
    final topStyle = OutfitIntentScorer.classifyTopIntentStyle(top);
    final topEligibility = OutfitIntentScorer.classifyTopEligibility(
      item: top,
      intent: intent,
    );
    final bottomFamily = classifyBottomFamily(bottom).wireName;
    final footwearFamily = classifyFootwearFamily(shoes).wireName;

    final topWhite = _isWhiteOrLight(top);
    final topDark = _isDark(top);
    final topClean = _isCleanPlainTop(top, topStyle);
    final shoesWhiteFashion = _isWhiteFashionSneakers(shoes, footwearFamily);
    final shoesOutdoor = _isOutdoorFootwear(shoes, footwearFamily);

    switch (intent.activityType) {
      case 'wedding':
      case 'interview':
      case 'funeral':
        if (topClean && topWhite) {
          bonus(3.5, 'formal_clean_light_top');
        } else if (topClean && topDark) {
          bonus(1.5, 'formal_clean_dark_top');
        }
        if (topEligibility.eligibility == ItemEligibility.compromise &&
            topClean) {
          bonus(1.0, 'formal_top_compromise_best_available');
        }
        if (bottomFamily == BottomFamily.pants.wireName) {
          bonus(2.5, 'formal_pants');
        } else if (bottomFamily == BottomFamily.jeans.wireName) {
          penalty(1.5, 'formal_jeans_compromise');
        }
        if (footwearFamily == FootwearFamily.formalShoes.wireName) {
          bonus(3.0, 'formal_shoes');
        } else if (shoesOutdoor) {
          penalty(6.0, 'formal_outdoor_footwear');
        } else if (footwearFamily == FootwearFamily.sneakers.wireName) {
          penalty(2.5, 'formal_sneakers_compromise');
        }
        if (intent.activityType == 'interview' && topDark && topClean) {
          bonus(1.5, 'interview_professional_dark_top');
        }

      case 'work':
        if (bottomFamily == BottomFamily.jeans.wireName) {
          bonus(3.5, 'work_jeans_business_casual');
        } else if (bottomFamily == BottomFamily.pants.wireName) {
          bonus(1.5, 'work_pants_ok');
        } else if (bottomFamily == BottomFamily.shorts.wireName) {
          penalty(4.0, 'work_shorts_too_casual');
        }
        if (topClean) {
          bonus(1.5, 'work_clean_top');
        }
        if (topEligibility.eligibility == ItemEligibility.forbidden) {
          penalty(8.0, 'work_forbidden_top');
        }
        if (shoesOutdoor) {
          penalty(4.0, 'work_outdoor_footwear');
        } else if (footwearFamily == FootwearFamily.sneakers.wireName) {
          bonus(1.0, 'work_sneakers_ok');
        }

      case 'hike':
        if (bottomFamily == BottomFamily.pants.wireName ||
            bottomFamily == BottomFamily.jeans.wireName ||
            bottomFamily == BottomFamily.joggers.wireName) {
          bonus(3.0, 'hike_practical_bottom');
        } else if (bottomFamily == BottomFamily.shorts.wireName) {
          if (wetGroundMuddy) {
            penalty(5.0, 'hike_shorts_wet_ground');
          } else {
            penalty(1.5, 'hike_shorts_less_ideal');
          }
        }
        if (shoesOutdoor) {
          bonus(6.0, 'hike_outdoor_footwear');
        } else if (shoesWhiteFashion) {
          penalty(4.0, 'hike_white_fashion_sneakers');
        } else if (footwearFamily == FootwearFamily.sneakers.wireName) {
          penalty(1.0, 'hike_casual_sneakers');
        }
        if (topDark) {
          bonus(0.75, 'hike_practical_dark_top');
        }

      case 'mushroom':
        if (topDark) {
          bonus(4.0, 'mushroom_dark_top');
        } else if (topWhite && wetGroundMuddy) {
          penalty(5.0, 'mushroom_white_top_wet_ground');
        }
        if (shoesOutdoor) {
          bonus(6.0, 'mushroom_outdoor_footwear');
        } else if (shoesWhiteFashion && wetGroundMuddy) {
          penalty(5.0, 'mushroom_white_sneakers_wet_ground');
        } else if (footwearFamily == FootwearFamily.sneakers.wireName) {
          penalty(2.0, 'mushroom_casual_sneakers');
        }
        if (bottomFamily == BottomFamily.jeans.wireName ||
            bottomFamily == BottomFamily.pants.wireName) {
          bonus(2.0, 'mushroom_practical_bottom');
        }

      case 'barbecue':
        if (bottomFamily == BottomFamily.shorts.wireName) {
          bonus(4.0, 'bbq_shorts_comfort');
        }
        if (topStyle == TopIntentStyle.casualTee ||
            topStyle == TopIntentStyle.polo) {
          bonus(1.5, 'bbq_casual_top');
        }
        if (footwearFamily == FootwearFamily.sneakers.wireName) {
          if (shoesOutdoor) {
            penalty(3.0, 'bbq_outdoor_footwear_overkill');
          } else {
            bonus(1.5, 'bbq_sneakers_comfort');
          }
        }

      case 'date':
      case 'cinema':
      case 'dinner':
        // Selection (forOpinion=false): iba 'date' skóruje ako doteraz;
        // cinema/dinner ostávajú neutrálne (0), aby sa výber nezmenil.
        if (!forOpinion && intent.activityType != 'date') break;

        if (bottomFamily == BottomFamily.pants.wireName ||
            bottomFamily == BottomFamily.jeans.wireName) {
          bonus(2.0, 'social_smart_bottom');
        } else if (bottomFamily == BottomFamily.shorts.wireName) {
          penalty(1.5, 'social_shorts_casual');
        }
        if (topClean) {
          bonus(2.0, 'social_clean_top');
        }

        if (!forOpinion) {
          // Pôvodné date správanie pre selection.
          if (footwearFamily == FootwearFamily.sneakers.wireName &&
              !shoesWhiteFashion) {
            bonus(0.5, 'date_sneakers_ok');
          }
          break;
        }

        // Opinion-only: rande/kino/večera preferujú clean/smart casual,
        // nie outdoor look.
        if (shoesOutdoor) {
          penalty(3.5, 'social_outdoor_footwear_not_ideal');
        } else if (shoesWhiteFashion) {
          bonus(1.5, 'social_clean_sneakers');
        } else if (footwearFamily == FootwearFamily.sneakers.wireName) {
          bonus(0.5, 'social_sneakers_ok');
        } else if (footwearFamily == FootwearFamily.formalShoes.wireName) {
          bonus(1.0, 'social_formal_shoes_neat');
        }

      default:
        break;
    }

    return ActivityIdentityResult(score: score, reasons: reasons);
  }

  /// Verejná detekcia outdoor/hiking obuvi (pre StylistOpinion caps).
  static bool isOutdoorFootwearItem(Map<String, dynamic> item) {
    return _isOutdoorFootwear(item, classifyFootwearFamily(item).wireName);
  }

  /// Verejná detekcia clean fashion sneakers (pre StylistOpinion).
  static bool isCleanSneakerItem(Map<String, dynamic> item) {
    return _isWhiteFashionSneakers(item, classifyFootwearFamily(item).wireName);
  }

  static void log({
    required String activityType,
    required OutfitPreview preview,
    required ActivityIdentityResult result,
  }) {
    final items = [
      preview.top.label,
      preview.bottom.label,
      preview.shoes.label,
      if (preview.outerwear != null) preview.outerwear!.label,
    ].join(' + ');
    debugPrint(
      'STYLIST CHAT activity_outfit_identity { '
      'activityType=$activityType, '
      'selectedItems=$items, '
      'identityScore=${result.score.toStringAsFixed(2)}, '
      'reasons=${result.reasons.join("|")} '
      '}',
    );
  }

  static String _blob(Map<String, dynamic> item) {
    return [
      item['name'],
      item['category'],
      item['subCategory'],
      item['canonical_type'] ?? item['canonicalType'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
  }

  static bool _isWhiteOrLight(Map<String, dynamic> item) {
    final blob = _blob(item);
    return blob.contains('biel') ||
        blob.contains('white') ||
        blob.contains('svetl') ||
        blob.contains('cream') ||
        blob.contains('krém') ||
        blob.contains('krem') ||
        blob.contains('čist') ||
        blob.contains('cist');
  }

  static bool _isDark(Map<String, dynamic> item) {
    final blob = _blob(item);
    return blob.contains('čier') ||
        blob.contains('cier') ||
        blob.contains('black') ||
        blob.contains('tmav') ||
        blob.contains('dark') ||
        blob.contains('navy');
  }

  static bool _isCleanPlainTop(
    Map<String, dynamic> item,
    TopIntentStyle style,
  ) {
    if (style == TopIntentStyle.graphicTee ||
        style == TopIntentStyle.sportyCasual) {
      return false;
    }
    final blob = _blob(item);
    return style == TopIntentStyle.casualTee ||
        style == TopIntentStyle.shirtOrBlouse ||
        style == TopIntentStyle.polo ||
        blob.contains('čist') ||
        blob.contains('cist') ||
        blob.contains('basic');
  }

  static bool _isWhiteFashionSneakers(
    Map<String, dynamic> item,
    String footwearFamily,
  ) {
    if (footwearFamily != FootwearFamily.sneakers.wireName &&
        footwearFamily != FootwearFamily.other.wireName) {
      return false;
    }
    final blob = _blob(item);
    if (blob.contains('turist') ||
        blob.contains('hiking') ||
        blob.contains('trek')) {
      return false;
    }
    return _isWhiteOrLight(item);
  }

  static bool _isOutdoorFootwear(
    Map<String, dynamic> item,
    String footwearFamily,
  ) {
    if (footwearFamily == FootwearFamily.boots.wireName) return true;
    final blob = _blob(item);
    final canonical = (item['canonical_type'] ?? item['canonicalType'] ?? '')
        .toString();
    return blob.contains('turist') ||
        blob.contains('hiking') ||
        blob.contains('trek') ||
        canonical.toLowerCase().contains('hiking');
  }
}
