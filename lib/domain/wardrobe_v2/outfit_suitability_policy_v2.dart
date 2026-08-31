import 'wardrobe_item_v2.dart';
import 'flexible_outfit_result_v2.dart';

/// Shared Home/Stylist suitability overlay. Physical and contextual fitness
/// outrank color, Set preference and stylistic extras.
///
/// Authoritative V2 item attributes ([WardrobeItemV2.warmth], formality,
/// layerPosition, canonicalType) always win over canonical-type defaults.
abstract final class OutfitSuitabilityPolicyV2 {
  static const double majorPenalty = -12;
  static const double strongPenalty = -8;
  static const double moderatePenalty = -5;
  static const double lightPenalty = -2.5;

  static int formalityFloor({
    required String occasionId,
    required String activityType,
  }) {
    final occ = occasionId.trim().toLowerCase();
    final act = activityType.trim().toLowerCase();
    if (_is(act, const {'funeral'}) || _is(occ, const {'funeral'})) return 8;
    if (_is(act, const {'wedding', 'formal_wedding'}) ||
        _is(occ, const {'wedding', 'formal_wedding', 'formal'})) {
      return 8;
    }
    if (_is(act, const {'interview', 'job_interview'}) ||
        _is(occ, const {'interview', 'job_interview'})) {
      return 7;
    }
    if (_is(act, const {'formal_dinner'}) ||
        _is(occ, const {'formal_dinner', 'philharmonic', 'theater'})) {
      return 7;
    }
    if (_is(act, const {'meeting', 'important_meeting', 'business_meeting'}) ||
        _is(occ, const {'meeting', 'important_meeting', 'business_meeting'})) {
      return 6;
    }
    if (_is(act, const {'semi_formal'}) ||
        _is(occ, const {'semi_formal', 'celebration'})) {
      return 6;
    }
    if (_is(act, const {'date', 'dinner'}) ||
        _is(occ, const {'date', 'dinner', 'restaurant_evening'})) {
      return 5;
    }
    if (_is(act, const {'work'}) ||
        _is(occ, const {'work', 'office', 'normal_office'})) {
      return 5;
    }
    if (_is(occ, const {'casual_office'})) return 4;
    if (_is(occ, const {'birthday'})) return 4;
    return 1;
  }

  static bool isTerrainActivity(String activityType) {
    final act = activityType.trim().toLowerCase();
    return _is(act, const {
      'hike',
      'hiking',
      'mountains',
      'mushroom',
      'outdoor',
      'nature_walk',
    });
  }

  static bool isAthleticActivity(String activityType) {
    final act = activityType.trim().toLowerCase();
    return _is(act, const {'sport', 'gym', 'run', 'training'});
  }

  static int? effectiveTempC({int? tempC, int? feelsLikeC}) =>
      feelsLikeC ?? tempC;

  static double targetMeanWarmth(int tempC) {
    if (tempC >= 30) return 2.2;
    if (tempC >= 26) return 2.6;
    if (tempC >= 22) return 3.2;
    if (tempC >= 18) return 4.0;
    if (tempC >= 12) return 5.2;
    if (tempC >= 6) return 6.4;
    if (tempC >= 0) return 7.4;
    return 8.2;
  }

  static bool isPhysicallyUnsuitable(
    WardrobeItemV2 item, {
    int? tempC,
    String seasonKey = '',
    bool isRainy = false,
    String activityType = '',
  }) {
    final temp = tempC;
    final type = item.canonicalType.toLowerCase();
    if (item.bodySlots.contains('feet') &&
        isFootwearPhysicallyUnsuitableForConditions(
          item,
          tempC: temp,
          seasonKey: seasonKey,
        )) {
      return true;
    }
    if (temp != null &&
        temp >= 24 &&
        item.warmth >= 7 &&
        (item.layerPosition == 'outer' ||
            item.layerPosition == 'shell' ||
            item.layerPosition == 'mid')) {
      return true;
    }
    if (isOpenFootwear(type) && (isRainy || (temp != null && temp <= 8))) {
      return true;
    }
    if (isTerrainActivity(activityType) && isFormalFootwear(type)) {
      return true;
    }
    return false;
  }

  /// Rejects only footwear whose V2 thermal facts make it plainly unsuitable.
  /// Rain can improve a suitable closed shoe's rank, but may not rescue an
  /// overly warm boot.
  static bool isFootwearPhysicallyUnsuitableForConditions(
    WardrobeItemV2 item, {
    int? tempC,
    String seasonKey = '',
  }) {
    if (!item.bodySlots.contains('feet') &&
        item.canonicalFamily.toLowerCase() != 'footwear') {
      return false;
    }
    final type = item.canonicalType.toLowerCase();
    final seasons = item.seasons.map(_normalizedSeason).toSet();
    final winterOnly =
        seasons.isNotEmpty && seasons.every((season) => season == 'winter');
    final supportsWarmSeason = seasons.any(
      (season) => const {'summer', 'all_season'}.contains(season),
    );
    final isBoot = isBootFootwear(type);
    final winterType = type.contains('winter') || type.contains('snow');

    if (tempC == null) return false;

    // Calendar season is deliberately not an eligibility gate. A cold March,
    // April or November day can require winter-capable footwear, while a warm
    // January day must not select it merely because the date says winter.
    if (tempC >= 14 && winterOnly && item.warmth >= 7) return true;
    if (tempC >= 18 && isBoot && winterType && item.warmth >= 7) {
      return true;
    }
    // At warm temperatures, the canonical Chelsea/ankle-boot class (typical
    // V2 warmth 6) is still thermally unsuitable unless its facts explicitly
    // support warm/all-season wear. This is deliberately stricter than the
    // prior high-warmth-only guard while retaining lightweight all-season
    // ankle boots for transitional conditions.
    if (tempC >= 20 && isBoot && item.warmth >= 6 && !supportsWarmSeason) {
      return true;
    }
    return false;
  }

  /// A small ranking prior only. It can never make an item ineligible or
  /// rescue one that failed a physical weather/thermal check.
  static double calendarSeasonCompatibilityAdjustment(
    WardrobeItemV2 item, {
    String seasonKey = '',
  }) {
    final current = _normalizedSeason(seasonKey);
    final seasons = item.seasons.map(_normalizedSeason).toSet();
    if (current.isEmpty ||
        seasons.isEmpty ||
        seasons.contains('all_season') ||
        seasons.contains(current)) {
      return 0;
    }
    return -0.35;
  }

  static String _normalizedSeason(String value) {
    final season = value.trim().toLowerCase();
    return switch (season) {
      'zim' || 'zima' || 'winter' => 'winter',
      'let' || 'leto' || 'summer' => 'summer',
      'celoročne' ||
      'celorocne' ||
      'all_season' ||
      'all-season' => 'all_season',
      'jar' || 'spring' => 'spring',
      'jese' || 'jeseň' || 'jesen' || 'autumn' || 'fall' => 'autumn',
      _ => season,
    };
  }

  static bool isOpenFootwear(String canonicalType) {
    final t = canonicalType.toLowerCase();
    return t.contains('sandal') ||
        t.contains('flip_flop') ||
        t.contains('slide');
  }

  static bool isFormalFootwear(String canonicalType) {
    final t = canonicalType.toLowerCase();
    return t.contains('dress_shoe') ||
        t.contains('oxford') ||
        t.contains('loafer') ||
        t.contains('heel') ||
        t.contains('pump');
  }

  static bool isBootFootwear(String canonicalType) {
    return canonicalType.toLowerCase().contains('boot');
  }

  static bool isHikingFootwear(String canonicalType) {
    final type = canonicalType.toLowerCase();
    return const {
      'hiking_boots',
      'hiking_shoes',
      'trail_shoes',
      'trekking_boots',
      'trekking_shoes',
    }.contains(type);
  }

  static bool isSneakerFootwear(String canonicalType) {
    final t = canonicalType.toLowerCase();
    return t.contains('sneaker') || t.contains('trainer');
  }

  static bool isShorts(String canonicalType) {
    final t = canonicalType.toLowerCase();
    return t.contains('short') && !t.contains('shirt');
  }

  static bool isSweatOrTrackBottom(String canonicalType) {
    final t = canonicalType.toLowerCase();
    return t.contains('sweatpant') ||
        t.contains('jogger') ||
        t.contains('track_pant');
  }

  static int footwearPreferenceRank(
    WardrobeItemV2 item, {
    required String activityType,
    required int formalityFloorValue,
    required bool isRainy,
    int? tempC,
    String seasonKey = '',
  }) {
    if (isFootwearPhysicallyUnsuitableForConditions(
      item,
      tempC: tempC,
      seasonKey: seasonKey,
    )) {
      return 1000;
    }
    final type = item.canonicalType.toLowerCase();
    if (isTerrainActivity(activityType)) {
      if (isHikingFootwear(type)) return 0;
      // A boot silhouette is not evidence of trail traction, stability or
      // hiking construction. Generic boots remain usable as a compromise,
      // but never outrank known hiking/trail footwear on category alone.
      if (isBootFootwear(type)) return 5;
      if (isSneakerFootwear(type)) return 3;
      if (isOpenFootwear(type)) return 30;
      if (isFormalFootwear(type)) return 28;
      return 8;
    }
    if (formalityFloorValue >= 6) {
      if (isFormalFootwear(type)) return 0;
      if (type.contains('chelsea') || type.contains('boot')) return 4;
      if (isSneakerFootwear(type)) return 12;
      if (isOpenFootwear(type)) return 24;
      return 8;
    }
    if (isRainy) {
      if (isBootFootwear(type)) return 0;
      if (isSneakerFootwear(type)) return 3;
      if (isFormalFootwear(type)) return 6;
      if (isOpenFootwear(type)) return 24;
      return 8;
    }
    return 0;
  }

  static Map<String, double> score({
    required V2FlexibleOutfitResult outfit,
    int? tempC,
    int? feelsLikeC,
    int? eveningTempC,
    bool isRainy = false,
    bool isWindy = false,
    bool outdoor = true,
    String activityType = '',
    String occasionId = '',
    int minimumFormality = 1,
    Set<String> requestedItemIds = const {},
    Set<String> forbiddenCanonicalTypes = const {},
    String seasonKey = '',
  }) {
    final items = outfit.items.map((x) => x.item).toList(growable: false);
    final ids = outfit.items.map((x) => x.itemId).toSet();
    final temp = effectiveTempC(tempC: tempC, feelsLikeC: feelsLikeC);
    final floor = [
      minimumFormality,
      formalityFloor(occasionId: occasionId, activityType: activityType),
    ].reduce((a, b) => a > b ? a : b);

    return {
      'weatherWarmth': _warmthScore(
        items: items,
        tempC: temp,
        isRainy: isRainy,
        isWindy: isWindy,
        eveningTempC: eveningTempC,
        outdoor: outdoor,
      ),
      'formalityWeakestLink': _formalityScore(items: items, floor: floor),
      'footwearSuitability': _footwearScore(
        items: items,
        activityType: activityType,
        floor: floor,
        isRainy: isRainy,
        tempC: temp,
        outdoor: outdoor,
      ),
      'layeringSuitability': _layeringScore(
        items: items,
        tempC: temp,
        eveningTempC: eveningTempC,
        isRainy: isRainy,
      ),
      'activitySuitability': _activityScore(
        items: items,
        activityType: activityType,
        occasionId: occasionId,
      ),
      'userPreference': _preferenceScore(
        ids: ids,
        items: items,
        requestedItemIds: requestedItemIds,
        forbiddenCanonicalTypes: forbiddenCanonicalTypes,
        tempC: temp,
        isRainy: isRainy,
        activityType: activityType,
      ),
      'setContextual': _setScore(
        items: items,
        floor: floor,
        activityType: activityType,
        tempC: temp,
      ),
      'calendarSeasonCompatibility': items.fold(
        0.0,
        (score, item) =>
            score +
            calendarSeasonCompatibilityAdjustment(item, seasonKey: seasonKey),
      ),
    };
  }

  static DecisionQualityGrade grade(Map<String, double> components) {
    final values = components.values.toList(growable: false);
    if (values.isEmpty) return DecisionQualityGrade.good;
    final worst = values.reduce((a, b) => a < b ? a : b);
    final majors = values.where((v) => v <= majorPenalty + 0.01).length;
    if (majors > 0 || worst <= -10) return DecisionQualityGrade.weak;
    if (worst <= -6) return DecisionQualityGrade.acceptableWithCompromise;
    if (worst <= -2.5) return DecisionQualityGrade.good;
    return DecisionQualityGrade.excellent;
  }

  static List<String> knownCompromises(Map<String, double> components) {
    final out = <String>[];
    components.forEach((key, value) {
      if (value <= -6) out.add(key);
    });
    return out;
  }

  static List<String> explanationInputs({
    required Map<String, double> components,
    int? tempC,
    bool isRainy = false,
    String activityType = '',
    String occasionId = '',
  }) {
    final inputs = <String>[];
    if (tempC != null) {
      if (tempC >= 24) {
        inputs.add('weather_light_layers');
      } else if (tempC <= 8) {
        inputs.add('weather_warm_layers');
      } else {
        inputs.add('weather_seasonal');
      }
    }
    if (isRainy) inputs.add('weather_rain');
    if (activityType.trim().isNotEmpty) inputs.add('activity_$activityType');
    if (occasionId.trim().isNotEmpty) inputs.add('occasion_$occasionId');
    if ((components['formalityWeakestLink'] ?? 0) < 0) {
      inputs.add('formality_compromise');
    }
    if ((components['footwearSuitability'] ?? 0) < 0) {
      inputs.add('footwear_compromise');
    }
    if ((components['setContextual'] ?? 0) > 1) inputs.add('set_preference');
    if ((components['userPreference'] ?? 0) > 0) {
      inputs.add('explicit_request');
    }
    return inputs;
  }

  static double _warmthScore({
    required List<WardrobeItemV2> items,
    required int? tempC,
    required bool isRainy,
    required bool isWindy,
    required int? eveningTempC,
    required bool outdoor,
  }) {
    if (tempC == null) return 0;
    var score = 0.0;
    for (final item in items) {
      final warmth = item.warmth;
      final layer = item.layerPosition;
      final type = item.canonicalType.toLowerCase();
      if (layer == 'outer' || layer == 'shell') {
        if (tempC >= 26 && warmth >= 7) {
          score += majorPenalty;
        } else if (tempC >= 22 && warmth >= 8) {
          score += strongPenalty;
        } else if (tempC >= 24 && warmth >= 5 && !isRainy) {
          score += moderatePenalty;
        } else if (tempC <= 6 && warmth >= 7) {
          score += 3;
        } else if (tempC <= 8 && warmth <= 4 && !isRainy && outdoor) {
          score += strongPenalty;
        } else if (isRainy &&
            (type.contains('rain') ||
                item.outfitFunctions.contains('weather_protection'))) {
          score += type.contains('winter') ? 0.5 : 4;
        } else if (isRainy && type.contains('track')) {
          score += moderatePenalty;
        }
      }
      if (layer == 'mid') {
        if (tempC >= 24 && warmth >= 5) score += strongPenalty;
        if (tempC <= 10 && warmth >= 5) score += 1.2;
      }
      if (isShorts(type)) {
        if (tempC <= 10) {
          score += strongPenalty;
        } else if (tempC >= 28) {
          score += 3.0;
        } else if (tempC >= 25) {
          score += 1.5;
        }
      }
      // Jeans are still valid in warm weather, but at real heat they should
      // not beat a suitable shorts option merely on generic style scoring.
      if (tempC >= 28 &&
          item.bodySlots.contains('lower_body') &&
          (type.contains('jean') || type.contains('denim'))) {
        score += lightPenalty;
      }
      if (isOpenFootwear(type) && tempC <= 8) score += majorPenalty;
    }
    if (items.isNotEmpty) {
      final mean =
          items.map((e) => e.warmth).reduce((a, b) => a + b) / items.length;
      score -= (mean - targetMeanWarmth(tempC)).abs() * 0.55;
    }
    if (eveningTempC != null &&
        tempC >= 18 &&
        eveningTempC <= 12 &&
        !items.any(
          (item) =>
              item.layerPosition == 'mid' ||
              item.layerPosition == 'outer' ||
              item.layerPosition == 'shell',
        )) {
      score += lightPenalty;
    }
    if (isWindy &&
        tempC <= 16 &&
        !items.any(
          (item) =>
              item.layerPosition == 'outer' || item.layerPosition == 'shell',
        )) {
      score += moderatePenalty;
    }
    return score;
  }

  static double _formalityScore({
    required List<WardrobeItemV2> items,
    required int floor,
  }) {
    if (items.isEmpty) return 0;
    final core = items
        .where(
          (item) =>
              item.bodySlots.contains('upper_body') ||
              item.bodySlots.contains('lower_body') ||
              item.bodySlots.contains('full_body') ||
              item.bodySlots.contains('feet'),
        )
        .toList(growable: false);
    final pool = core.isEmpty ? items : core;
    final minF = pool.map((e) => e.formality).reduce((a, b) => a < b ? a : b);
    var score = 0.0;
    if (floor >= 5) {
      if (minF + 2 < floor) {
        score += majorPenalty;
      } else if (minF < floor) {
        score += moderatePenalty;
      } else {
        score += 1.2;
      }
    }
    if (floor >= 5 && pool.any((item) => isShorts(item.canonicalType))) {
      score += majorPenalty;
    }
    if (floor >= 7 &&
        pool.any((item) => isSweatOrTrackBottom(item.canonicalType))) {
      score += majorPenalty;
    }
    if (floor >= 5 &&
        pool.any(
          (item) =>
              item.canonicalType.toLowerCase().contains('track_jacket') ||
              item.canonicalType.toLowerCase().contains('track_pant'),
        )) {
      score += strongPenalty;
    }
    if (floor >= 7 &&
        pool.any(
          (item) => item.canonicalType.toLowerCase().contains('hoodie'),
        )) {
      score += strongPenalty;
    }
    return score;
  }

  static double _footwearScore({
    required List<WardrobeItemV2> items,
    required String activityType,
    required int floor,
    required bool isRainy,
    required int? tempC,
    required bool outdoor,
  }) {
    final shoes = items
        .where((item) => item.bodySlots.contains('feet'))
        .toList(growable: false);
    if (shoes.isEmpty) return strongPenalty;
    var score = 0.0;
    for (final shoe in shoes) {
      final type = shoe.canonicalType.toLowerCase();
      if (isTerrainActivity(activityType)) {
        if (isHikingFootwear(type)) {
          score += 3;
        } else if (isBootFootwear(type)) {
          score += 0;
        } else if (isSneakerFootwear(type) &&
            (activityType == 'nature_walk' || activityType == 'outdoor')) {
          score += 1;
        } else if (isSneakerFootwear(type)) {
          score += lightPenalty;
        } else if (isFormalFootwear(type) || isOpenFootwear(type)) {
          score += majorPenalty;
        }
      }
      if (isRainy && isOpenFootwear(type)) score += majorPenalty;
      if (tempC != null && tempC <= 8 && isOpenFootwear(type)) {
        score += majorPenalty;
      }
      if (floor >= 6) {
        if (isFormalFootwear(type)) {
          score += 2;
        } else if (isSneakerFootwear(type) ||
            type.contains('track') ||
            isOpenFootwear(type)) {
          score += floor >= 7 ? strongPenalty : moderatePenalty;
        }
      }
      if (floor <= 3 &&
          !isTerrainActivity(activityType) &&
          isFormalFootwear(type) &&
          outdoor) {
        score += lightPenalty;
      }
    }
    return score;
  }

  static double _layeringScore({
    required List<WardrobeItemV2> items,
    required int? tempC,
    required int? eveningTempC,
    required bool isRainy,
  }) {
    if (tempC == null) return 0;
    final mids = items.where((item) => item.layerPosition == 'mid').length;
    final outers = items
        .where(
          (item) =>
              item.layerPosition == 'outer' || item.layerPosition == 'shell',
        )
        .where((item) => item.bodySlots.contains('upper_body'))
        .length;
    var score = 0.0;
    if (tempC >= 24 && !isRainy && (mids + outers) > 0) {
      score += moderatePenalty * (mids + outers);
    }
    if (tempC <= 6 && outers == 0) score += strongPenalty;
    if (eveningTempC != null &&
        tempC >= 18 &&
        eveningTempC <= 12 &&
        mids + outers == 0) {
      score += lightPenalty;
    }
    return score;
  }

  static double _activityScore({
    required List<WardrobeItemV2> items,
    required String activityType,
    required String occasionId,
  }) {
    if (activityType.trim().isEmpty && occasionId.trim().isEmpty) return 0;
    var score = 0.0;
    final types = items.map((e) => e.canonicalType.toLowerCase()).toList();
    if (isTerrainActivity(activityType)) {
      if (types.any((t) => t.contains('suit_jacket') || t.contains('blazer'))) {
        score += strongPenalty;
      }
      if (types.any((t) => t.contains('dress_shirt'))) score += lightPenalty;
    }
    if (isAthleticActivity(activityType)) {
      if (types.any((t) => t.contains('hoodie') || t.contains('track'))) {
        score += 1.5;
      }
      if (types.any((t) => t.contains('suit') || t.contains('oxford'))) {
        score += strongPenalty;
      }
    }
    return score;
  }

  static double _preferenceScore({
    required Set<String> ids,
    required List<WardrobeItemV2> items,
    required Set<String> requestedItemIds,
    required Set<String> forbiddenCanonicalTypes,
    required int? tempC,
    required bool isRainy,
    required String activityType,
  }) {
    var score = 0.0;
    if (forbiddenCanonicalTypes.isNotEmpty &&
        items.any(
          (item) => forbiddenCanonicalTypes.contains(item.canonicalType),
        )) {
      score += majorPenalty;
    }
    if (requestedItemIds.isEmpty) return score;
    var included = 0;
    var omitted = 0;
    for (final id in requestedItemIds) {
      if (ids.contains(id)) {
        included++;
        continue;
      }
      omitted++;
    }
    score += included * 4.0;
    if (included == 0 && omitted > 0) {
      score += moderatePenalty;
    }
    return score;
  }

  static double _setScore({
    required List<WardrobeItemV2> items,
    required int floor,
    required String activityType,
    required int? tempC,
  }) {
    final counts = <String, int>{};
    for (final item in items) {
      final id = item.setMembership?.setId;
      if (id != null) counts.update(id, (n) => n + 1, ifAbsent: () => 1);
    }
    final matching = items
        .map((item) => item.setMembership)
        .whereType<SetMembershipV2>()
        .where((set) => (counts[set.setId] ?? 0) > 1)
        .toList(growable: false);
    if (matching.isEmpty) return 0;
    final types = matching.map((set) => set.setType).toSet();
    final curated = matching.any(
      (set) => set.relationshipSource == 'user_curated',
    );
    if (types.contains('suit')) {
      if (isTerrainActivity(activityType)) return 0.2;
      if (floor >= 7) return 3.0;
      if (floor >= 5) return 1.6;
      return 0.6;
    }
    if (types.contains('tracksuit')) {
      if (floor >= 6) return strongPenalty;
      if (tempC != null && tempC <= 4) return 0.4;
      return curated ? 2.0 : 1.6;
    }
    if (curated) {
      if (tempC != null &&
          items.any(
            (item) =>
                item.warmth >= 7 &&
                tempC >= 24 &&
                (item.layerPosition == 'outer' || item.layerPosition == 'mid'),
          )) {
        return 0.2;
      }
      return 2.2;
    }
    if (floor >= 7) return 0.8;
    return 1.8;
  }

  static bool _is(String value, Set<String> options) =>
      options.contains(value.trim().toLowerCase());
}

enum DecisionQualityGrade { excellent, good, acceptableWithCompromise, weak }
