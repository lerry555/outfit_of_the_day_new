import '../wardrobe_v2/outfit_suitability_policy_v2.dart';
import '../wardrobe_v2/wardrobe_item_v2.dart';

/// Phase 1 trip-local suitability for the live Trip packing generator.
///
/// Precedence (highest first):
/// 1. explicit trip kind / activity requirements (hiking, business, beach)
/// 2. destination weather/climate already supplied by the caller
/// 3. required footwear / layers / protection implied by (1)+(2)
/// 4. wardrobe availability (never invent an owned item)
/// 5. trip-local travel style, then set-partner, then day rotation
///
/// Weather values are injected by the live generator so a later phase can
/// replace synthetic heuristics without rewriting trip-kind rules.
///
/// Global saved taste scoring is intentionally unused.
enum TripIntentSlot { upper, lower, full, footwear, layer, accessory }

class TripIntentSignals {
  const TripIntentSignals({
    required this.hiking,
    required this.business,
    required this.warmBeach,
    required this.travelLeg,
    required this.travelStyles,
    required this.transport,
    this.highTempC,
    this.lowTempC,
    this.isRainy = false,
    this.isWindy = false,
    this.tripIncludesHiking = false,
  });

  final bool hiking;
  final bool business;
  final bool warmBeach;
  final bool travelLeg;
  final Set<String> travelStyles;
  final String transport;
  final int? highTempC;
  final int? lowTempC;
  final bool isRainy;
  final bool isWindy;

  /// True when hiking is selected for the trip, even on overlay days that
  /// are not themselves hiking days. Outdoor footwear is reserved for the
  /// hiking overlay day instead of covering casual days for compactness.
  final bool tripIncludesHiking;

  int? get effectiveTempC => highTempC ?? lowTempC;

  /// Same live layer rule as [TripPackingService.generatePlaceholderPlan]:
  /// skip extra layers on warm-beach days unless that day's low is under 14 °C.
  bool get needsColdLayer {
    final low = lowTempC ?? 99;
    if (warmBeach) return low < 14;
    return low < 14;
  }

  bool get needsWeatherLayer => needsColdLayer || isRainy || isWindy;

  bool get weatherProtectionRequired => isRainy || isWindy;
}

/// Deterministic V2 scoring used by the live Trip picker.
///
/// Formality policy for business/travel-to-work:
/// - floor is 5, matching [OutfitSuitabilityPolicyV2.formalityFloor] for work
/// - sweet spot is 5–7 (business/travel, not black-tie)
/// - 8–10 remains valid but is not boosted, so every day is not maximally formal
abstract final class TripIntentPolicy {
  TripIntentPolicy._();

  static const businessFormalityFloor = 5;
  static const businessFormalitySweetMax = 7;

  /// Mixed-kind overlay: hiking is trip-wide unless another kind is also
  /// selected, in which case only the last destination day is a hiking day.
  /// That keeps city sneakers reusable while still packing outdoor footwear
  /// for the hiking overlay day.
  static bool hikingAppliesOnDay({
    required bool selected,
    required bool mixedKinds,
    required int dayIndex,
    required int dayCount,
  }) {
    if (!selected) return false;
    if (!mixedKinds) return true;
    if (dayCount <= 1) return true;
    return dayIndex == dayCount - 1;
  }

  /// Mixed-kind overlay: business is trip-wide unless another kind is also
  /// selected, in which case only the first destination day is a business day.
  static bool businessAppliesOnDay({
    required bool selected,
    required bool mixedKinds,
    required int dayIndex,
    required int dayCount,
  }) {
    if (!selected) return false;
    if (!mixedKinds) return true;
    return dayIndex == 0;
  }

  static const _hikingFootwearTypes = <String>{'hiking_shoes'};
  static const _outdoorBootTypes = <String>{'boots', 'winter_boots'};
  static const _closedAthleticTypes = <String>{'running_shoes', 'sneakers'};
  static const _businessFootwearTypes = <String>{
    'loafers',
    'oxford_shoes',
    'dress_shoes',
    'chelsea_boots',
  };

  static int hardScore(
    WardrobeItemV2 item,
    TripIntentSignals signals,
    TripIntentSlot slot,
  ) {
    return kindScore(item, signals, slot) * 100 +
        weatherScore(item, signals, slot);
  }

  static int kindScore(
    WardrobeItemV2 item,
    TripIntentSignals signals,
    TripIntentSlot slot,
  ) {
    var score = 5;
    final type = item.canonicalType.toLowerCase();
    if (signals.hiking && !signals.travelLeg) {
      switch (slot) {
        case TripIntentSlot.footwear:
          score = _hikingFootwearKind(type);
        case TripIntentSlot.lower:
          if (type == 'hiking_pants') {
            score = 10;
          } else if (OutfitSuitabilityPolicyV2.isShorts(type)) {
            score = 3;
          } else {
            score = 6;
          }
        case TripIntentSlot.layer:
          if (type == 'hiking_jacket' || type == 'softshell') {
            score = 10;
          } else if (item.outfitFunctions.contains('weather_protection')) {
            score = 7;
          } else {
            score = 5;
          }
        case TripIntentSlot.full:
          score = type == 'hiking_outfit' ? 10 : 5;
        case TripIntentSlot.upper:
          if (item.layerPosition == 'outer' || item.layerPosition == 'shell') {
            score = 3;
          } else if (type == 'hiking_jacket') {
            score = 4;
          } else {
            score = 6;
          }
        case TripIntentSlot.accessory:
          score = 5;
      }
    }
    if (signals.business) {
      score += _businessKindDelta(item, slot, type);
    }
    if (signals.warmBeach && !signals.hiking) {
      score += _warmBeachKindDelta(item, slot, type);
    }
    if (signals.travelLeg) {
      score += _travelLegKindDelta(item, signals, slot, type);
    }
    if (!signals.hiking &&
        signals.tripIncludesHiking &&
        slot == TripIntentSlot.footwear) {
      if (_hikingFootwearTypes.contains(type) ||
          _outdoorBootTypes.contains(type)) {
        score -= 3;
      }
    }
    return score;
  }

  static int weatherScore(
    WardrobeItemV2 item,
    TripIntentSignals signals,
    TripIntentSlot slot,
  ) {
    final temp = signals.effectiveTempC;
    final type = item.canonicalType.toLowerCase();
    if (OutfitSuitabilityPolicyV2.isPhysicallyUnsuitable(
      item,
      tempC: temp,
      isRainy: signals.isRainy,
      activityType: signals.hiking && !signals.travelLeg ? 'hiking' : '',
    )) {
      return 0;
    }
    var score = 5;
    if (temp == null) {
      score = 5;
    } else if (signals.warmBeach || temp >= 24) {
      if (slot == TripIntentSlot.layer && item.warmth >= 7) {
        score = 0;
      } else if (item.warmth >= 7 &&
          (item.layerPosition == 'outer' ||
              item.layerPosition == 'shell' ||
              item.layerPosition == 'mid')) {
        score = 1;
      } else if (item.warmth <= 3) {
        score = 10;
      } else if (item.warmth <= 5) {
        score = 7;
      } else if (item.warmth <= 6) {
        score = 4;
      } else {
        score = 2;
      }
    } else if (temp <= 10) {
      if (OutfitSuitabilityPolicyV2.isOpenFootwear(type) ||
          OutfitSuitabilityPolicyV2.isShorts(type)) {
        score = 1;
      } else if (item.warmth >= 6) {
        score = 9;
      } else if (item.warmth >= 4) {
        score = 6;
      } else {
        score = 3;
      }
    }
    if (signals.isRainy || signals.isWindy) {
      if (slot == TripIntentSlot.footwear) {
        if (OutfitSuitabilityPolicyV2.isOpenFootwear(type)) {
          score = 0;
        } else if (OutfitSuitabilityPolicyV2.isBootFootwear(type) ||
            type == 'hiking_shoes') {
          score += 3;
        } else if (!OutfitSuitabilityPolicyV2.isFormalFootwear(type)) {
          score += 2;
        }
      }
      if (slot == TripIntentSlot.layer &&
          item.outfitFunctions.contains('weather_protection')) {
        score += 3;
      }
    }
    return score;
  }

  /// Trip-local styles only: comfy / elegant / subtle / stylish.
  /// Never large enough to beat [hardScore] differences.
  static int travelStyleScore(
    WardrobeItemV2 item,
    TripIntentSignals signals,
    TripIntentSlot slot,
  ) {
    if (signals.travelStyles.isEmpty) return 0;
    var score = 0;
    final type = item.canonicalType.toLowerCase();
    final f = item.formality;
    if (signals.travelStyles.contains('comfy')) {
      if (f <= 4) score += 2;
      if (f >= 7) score -= 1;
      if (slot == TripIntentSlot.footwear) {
        if (_closedAthleticTypes.contains(type)) score += 2;
        if (OutfitSuitabilityPolicyV2.isFormalFootwear(type) ||
            type.contains('heel')) {
          score -= 2;
        }
      }
    }
    if (signals.travelStyles.contains('elegant')) {
      if (f >= 5 && f <= 7) score += 3;
      if (f >= 8) score += 1;
      if (f <= 2) score -= 2;
      if (slot == TripIntentSlot.footwear &&
          _businessFootwearTypes.contains(type)) {
        score += 2;
      }
      if (OutfitSuitabilityPolicyV2.isShorts(type) ||
          OutfitSuitabilityPolicyV2.isOpenFootwear(type)) {
        score -= 1;
      }
    }
    if (signals.travelStyles.contains('subtle')) {
      if (f >= 3 && f <= 6) score += 2;
      if (f >= 8) score -= 1;
    }
    if (signals.travelStyles.contains('stylish')) {
      if (f >= 4 && f <= 7) score += 2;
      if (f <= 2) score -= 1;
    }
    return score;
  }

  static bool isAcceptableHikingFootwear(WardrobeItemV2 item) {
    if (!item.bodySlots.contains('feet')) return false;
    final type = item.canonicalType.toLowerCase();
    return _hikingFootwearTypes.contains(type) ||
        _outdoorBootTypes.contains(type);
  }

  static bool isBusinessAppropriateCore(WardrobeItemV2 item) {
    final isCore =
        item.bodySlots.contains('upper_body') ||
        item.bodySlots.contains('lower_body') ||
        item.bodySlots.contains('full_body');
    if (!isCore) return false;
    return item.formality >= businessFormalityFloor;
  }

  static int _hikingFootwearKind(String type) {
    if (_hikingFootwearTypes.contains(type)) return 10;
    if (_outdoorBootTypes.contains(type)) return 8;
    if (type == 'running_shoes') return 5;
    if (type == 'sneakers') return 4;
    if (type.contains('chelsea')) return 2;
    if (type == 'football_boots') return 1;
    if (OutfitSuitabilityPolicyV2.isOpenFootwear(type) ||
        OutfitSuitabilityPolicyV2.isFormalFootwear(type) ||
        type.contains('heel')) {
      return 0;
    }
    return 2;
  }

  static int _businessKindDelta(
    WardrobeItemV2 item,
    TripIntentSlot slot,
    String type,
  ) {
    if (slot == TripIntentSlot.footwear) {
      if (_businessFootwearTypes.contains(type)) return 4;
      if (_closedAthleticTypes.contains(type)) return 0;
      if (OutfitSuitabilityPolicyV2.isOpenFootwear(type)) return -3;
      return 0;
    }
    if (slot == TripIntentSlot.layer) {
      final f = item.formality;
      if (f >= businessFormalityFloor && f <= businessFormalitySweetMax) {
        return 3;
      }
      if (f >= 8) return 1;
      if (f <= 3) return -2;
      return 0;
    }
    if (slot == TripIntentSlot.upper ||
        slot == TripIntentSlot.lower ||
        slot == TripIntentSlot.full) {
      final f = item.formality;
      if (f >= businessFormalityFloor && f <= businessFormalitySweetMax) {
        return 4;
      }
      if (f >= 8) return 2;
      if (f == 4) return 1;
      return -2;
    }
    return 0;
  }

  static int _warmBeachKindDelta(
    WardrobeItemV2 item,
    TripIntentSlot slot,
    String type,
  ) {
    var delta = 0;
    if (slot == TripIntentSlot.footwear) {
      if (OutfitSuitabilityPolicyV2.isOpenFootwear(type)) delta += 3;
      if (_outdoorBootTypes.contains(type) || type == 'hiking_shoes') {
        delta -= 2;
      }
    }
    if (slot == TripIntentSlot.lower &&
        OutfitSuitabilityPolicyV2.isShorts(type)) {
      delta += 2;
    }
    if (slot == TripIntentSlot.layer && item.warmth >= 7) delta -= 4;
    if ((slot == TripIntentSlot.upper || slot == TripIntentSlot.full) &&
        (item.layerPosition == 'outer' || item.layerPosition == 'shell')) {
      delta -= 2;
    }
    return delta;
  }

  static int _travelLegKindDelta(
    WardrobeItemV2 item,
    TripIntentSignals signals,
    TripIntentSlot slot,
    String type,
  ) {
    if (slot != TripIntentSlot.footwear) return 0;
    final seated = signals.transport == 'plane' ||
        signals.transport == 'train' ||
        signals.transport == 'bus';
    if (!seated) return 0;
    if (_closedAthleticTypes.contains(type)) return 2;
    if (type.contains('heel') ||
        OutfitSuitabilityPolicyV2.isOpenFootwear(type)) {
      return -2;
    }
    return 0;
  }
}
