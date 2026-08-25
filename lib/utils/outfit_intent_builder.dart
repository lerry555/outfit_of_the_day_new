import 'package:flutter/foundation.dart';

import '../data/event_dress_code.dart';
import '../data/outfit_intent.dart';
import '../data/stylist_intent.dart';
import 'bottom_family_guidance.dart';
import 'footwear_family_guidance.dart';

/// Prekladá StylistIntent + dress code + guidance na technický OutfitIntent.
class OutfitIntentBuilder {
  const OutfitIntentBuilder._();

  static const List<String> _allBottomFamilies = [
    'shorts',
    'jeans',
    'pants',
    'joggers',
    'other',
  ];

  static const List<String> _allFootwearFamilies = [
    'sneakers',
    'boots',
    'sandals',
    'formal_shoes',
    'other',
  ];

  static const Set<String> _formalActivityTypes = {
    'wedding',
    'interview',
    'funeral',
  };

  static OutfitIntent build({
    required StylistIntent stylistIntent,
    required EventDressCodeSpec dressCode,
    required BottomFamilyGuidance bottomGuidance,
    required FootwearFamilyGuidance footwearGuidance,
    bool wetGroundMuddy = false,
  }) {
    var bottomPreferred = _knownFamilies(
      bottomGuidance.preferredFamilies,
      _allBottomFamilies,
    );
    var footwearPreferred = _knownFamilies(
      footwearGuidance.preferredFamilies,
      _allFootwearFamilies,
    );

    _applyBottomActivityOverlay(
      preferred: bottomPreferred,
      stylistIntent: stylistIntent,
      wetGroundMuddy: wetGroundMuddy,
    );

    var bottomForbidden = _deriveForbidden(
      universe: _allBottomFamilies,
      preferred: bottomPreferred,
      allowed: bottomGuidance.allowedFamilies,
    );

    _applyFootwearPreferredOverlay(
      preferred: footwearPreferred,
      stylistIntent: stylistIntent,
      dressCode: dressCode,
    );

    var footwearForbidden = _deriveForbidden(
      universe: _allFootwearFamilies,
      preferred: footwearPreferred,
      allowed: footwearGuidance.allowedFamilies,
    );

    _applyFootwearForbiddenOverlay(
      preferred: footwearPreferred,
      forbidden: footwearForbidden,
      stylistIntent: stylistIntent,
      dressCode: dressCode,
      footwearGuidance: footwearGuidance,
    );

    bottomForbidden = _ensureDisjoint(
      preferred: bottomPreferred,
      forbidden: bottomForbidden,
    );
    footwearForbidden = _ensureDisjoint(
      preferred: footwearPreferred,
      forbidden: footwearForbidden,
    );

    _validateDisjoint(slot: 'bottom', preferred: bottomPreferred, forbidden: bottomForbidden);
    _validateDisjoint(
      slot: 'footwear',
      preferred: footwearPreferred,
      forbidden: footwearForbidden,
    );

    return OutfitIntent(
      activityType: stylistIntent.activityType,
      idealSummarySk: _idealSummarySk(stylistIntent, dressCode),
      bottomPreferred: bottomPreferred,
      bottomForbidden: bottomForbidden,
      footwearPreferred: footwearPreferred,
      footwearForbidden: footwearForbidden,
      topPreference: _topPreference(stylistIntent, dressCode),
      nonNegotiables: _nonNegotiables(
        stylistIntent: stylistIntent,
        dressCode: dressCode,
        bottomGuidance: bottomGuidance,
        footwearGuidance: footwearGuidance,
        wetGroundMuddy: wetGroundMuddy,
      ),
    );
  }

  /// Zakázané rodiny = nie sú v allowed, ale nikdy nie tie, čo sú preferred.
  /// Znevýhodnené (discouraged), ale stále allowed, sem nepatria — rieši scorer.
  static List<String> _deriveForbidden({
    required List<String> universe,
    required List<String> preferred,
    required List<String> allowed,
  }) {
    final preferredSet = preferred.toSet();
    return universe
        .where((family) => !allowed.contains(family))
        .where((family) => !preferredSet.contains(family))
        .toList();
  }

  static List<String> _knownFamilies(
    List<String> raw,
    List<String> universe,
  ) {
    final known = universe.toSet();
    return raw.where(known.contains).toList();
  }

  static List<String> _ensureDisjoint({
    required List<String> preferred,
    required List<String> forbidden,
  }) {
    final preferredSet = preferred.toSet();
    return forbidden.where((family) => !preferredSet.contains(family)).toList();
  }

  static void _validateDisjoint({
    required String slot,
    required List<String> preferred,
    required List<String> forbidden,
  }) {
    final overlap =
        preferred.toSet().intersection(forbidden.toSet()).toList(growable: false);
    if (overlap.isEmpty) return;

    debugPrint(
      'INVALID_INTENT_CONFIGURATION { '
      'slot=$slot, overlap=${overlap.join(",")}, '
      'preferred=${preferred.join(",")}, forbidden=${forbidden.join(",")} '
      '}',
    );
    assert(
      overlap.isEmpty,
      'OutfitIntent $slot: preferred and forbidden overlap: $overlap',
    );
  }

  static void _applyBottomActivityOverlay({
    required List<String> preferred,
    required StylistIntent stylistIntent,
    required bool wetGroundMuddy,
  }) {
    final outdoorPractical = stylistIntent.activityType == 'hike' ||
        stylistIntent.activityType == 'mushroom' ||
        wetGroundMuddy;
    if (!outdoorPractical) return;
    preferred.remove('shorts');
  }

  static void _applyFootwearPreferredOverlay({
    required List<String> preferred,
    required StylistIntent stylistIntent,
    required EventDressCodeSpec dressCode,
  }) {
    final isFormalOccasion =
        _formalActivityTypes.contains(stylistIntent.activityType) ||
            dressCode.formalityTarget >= 7;

    if (isFormalOccasion) {
      preferred
        ..clear()
        ..add('formal_shoes');
      return;
    }

    preferred.remove('sandals');
  }

  static void _applyFootwearForbiddenOverlay({
    required List<String> preferred,
    required List<String> forbidden,
    required StylistIntent stylistIntent,
    required EventDressCodeSpec dressCode,
    required FootwearFamilyGuidance footwearGuidance,
  }) {
    final isFormalOccasion =
        _formalActivityTypes.contains(stylistIntent.activityType) ||
            dressCode.formalityTarget >= 7;

    if (isFormalOccasion) {
      forbidden
        ..remove('sneakers')
        ..remove('formal_shoes');
      _ensureListed(forbidden, 'sandals');
      return;
    }

    if (stylistIntent.activityType == 'work' ||
        dressCode.formalityTarget >= 5) {
      forbidden
        ..remove('sneakers')
        ..remove('boots');
      _ensureListed(forbidden, 'sandals');
      return;
    }

    if (stylistIntent.activityType == 'hike' ||
        stylistIntent.activityType == 'mushroom' ||
        footwearGuidance.isDiscouraged(FootwearFamily.sandals)) {
      _ensureListed(forbidden, 'sandals');
    }
  }

  static void _ensureListed(List<String> values, String value) {
    if (!values.contains(value)) values.add(value);
  }

  static String _idealSummarySk(
    StylistIntent stylistIntent,
    EventDressCodeSpec dressCode,
  ) {
    final occasionLabel = dressCode.labelSk;
    if (dressCode.id == stylistIntent.activityType ||
        dressCode.id == 'casual') {
      return '${stylistIntent.impressionSummarySk} ($occasionLabel)';
    }
    return '${stylistIntent.impressionSummarySk} — $occasionLabel: '
        '${dressCode.explainPhrase()}';
  }

  static String _topPreference(
    StylistIntent stylistIntent,
    EventDressCodeSpec dressCode,
  ) {
    if (dressCode.formalityTarget >= 7) return 'shirt_or_blouse';
    if (dressCode.formalityTarget >= 5) return 'polo_or_shirt';
    if (stylistIntent.primaryImpressions.contains(ImpressionTag.upraveny)) {
      return 'smart_casual_top';
    }
    if (stylistIntent.primaryImpressions.contains(ImpressionTag.pohodlny) ||
        stylistIntent.primaryImpressions.contains(ImpressionTag.uvolneny)) {
      return 'casual_top';
    }
    return 'casual_top';
  }

  static List<String> _nonNegotiables({
    required StylistIntent stylistIntent,
    required EventDressCodeSpec dressCode,
    required BottomFamilyGuidance bottomGuidance,
    required FootwearFamilyGuidance footwearGuidance,
    required bool wetGroundMuddy,
  }) {
    final tags = <String>[];

    if (!bottomGuidance.isAllowed(BottomFamily.shorts)) {
      tags.add('bottom_shorts_forbidden');
    }
    if (!footwearGuidance.isAllowed(FootwearFamily.sandals)) {
      tags.add('footwear_sandals_forbidden');
    }
    if (dressCode.formalityTarget >= 7 &&
        footwearGuidance.isPreferred(FootwearFamily.formalShoes)) {
      tags.add('formal_closed_footwear_preferred');
    }
    if (wetGroundMuddy) {
      tags.add('wet_ground_closed_footwear');
    }
    if (stylistIntent.activityType == 'hike' &&
        bottomGuidance.isDiscouraged(BottomFamily.jeans)) {
      tags.add('hike_jeans_discouraged');
    }
    if (stylistIntent.activityType == 'mushroom') {
      tags.add('mushroom_practical_footwear');
    }
    if (stylistIntent.activityType == 'barbecue') {
      tags.add('barbecue_comfort_first');
    }

    return tags;
  }
}
