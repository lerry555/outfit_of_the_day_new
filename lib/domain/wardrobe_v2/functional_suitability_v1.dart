import '../style_preferences/styling_presentation.dart';
import '../wardrobe_profile/wardrobe_profile_contract.dart';
import '../wardrobe_profile/wardrobe_profile_persistence_codec.dart';
import '../wardrobe_profile/wardrobe_profile_resolver.dart';
import 'flexible_outfit_result_v2.dart';
import 'wardrobe_v2_resolver.dart';

enum WardrobeItemPresentationV1 { menswear, womenswear, unisex, unknown }

enum FunctionalSuitabilityTierV1 {
  ideal,
  good,
  acceptableCompromise,
  strongCompromise,
  inappropriate;

  int get severity => index;
}

class ActivityFunctionalRequirementsV1 {
  const ActivityFunctionalRequirementsV1({
    required this.activityType,
    required this.outdoor,
    required this.isRainy,
    required this.wetGroundRisk,
    required this.minimumFormality,
    this.durationMinutes,
    this.terrain = '',
    this.tempC,
  });

  final String activityType;
  final bool outdoor, isRainy, wetGroundRisk;
  final int minimumFormality;
  final int? durationMinutes, tempC;
  final String terrain;

  String get normalizedActivity => activityType.trim().toLowerCase();

  bool get terrainActivity => const {
    'hike',
    'hiking',
    'mountains',
    'nature_walk',
    'forest_walk',
    'outdoor',
    'mushroom',
  }.contains(normalizedActivity);

  bool get demandingTrailActivity =>
      const {'hike', 'hiking', 'mountains'}.contains(normalizedActivity) ||
      (terrainActivity && (durationMinutes ?? 0) >= 240);

  bool get longWalkingDay =>
      (durationMinutes ?? 0) >= 300 ||
      const {'zoo', 'sightseeing', 'city_trip'}.contains(normalizedActivity);

  bool get athletic => const {
    'sport',
    'gym',
    'run',
    'running',
    'training',
  }.contains(normalizedActivity);
}

class ItemFunctionalAssessmentV1 {
  const ItemFunctionalAssessmentV1({
    required this.itemId,
    required this.tier,
    this.reasonCodes = const <String>[],
    this.missingCapabilities = const <String>[],
    this.idealReplacementDescription,
  });

  final String itemId;
  final FunctionalSuitabilityTierV1 tier;
  final List<String> reasonCodes, missingCapabilities;
  final String? idealReplacementDescription;

  Map<String, dynamic> toUserFacingMap(String itemName) => <String, dynamic>{
    'itemName': itemName,
    'tier': tier.name,
    'reasonCodes': reasonCodes,
    'missingCapabilities': missingCapabilities,
    if (idealReplacementDescription != null)
      'idealReplacementDescription': idealReplacementDescription,
  };
}

class CandidateFunctionalAssessmentV1 {
  const CandidateFunctionalAssessmentV1({
    required this.tier,
    required this.items,
  });

  final FunctionalSuitabilityTierV1 tier;
  final List<ItemFunctionalAssessmentV1> items;

  bool get selectable => tier != FunctionalSuitabilityTierV1.inappropriate;

  double get scoreAdjustment => switch (tier) {
    FunctionalSuitabilityTierV1.ideal => 6,
    FunctionalSuitabilityTierV1.good => 3,
    FunctionalSuitabilityTierV1.acceptableCompromise => -3,
    FunctionalSuitabilityTierV1.strongCompromise => -11,
    FunctionalSuitabilityTierV1.inappropriate => -1000,
  };

  List<String> get reasonCodes =>
      items.expand((item) => item.reasonCodes).toSet().toList(growable: false);

  List<String> get missingCapabilities => items
      .expand((item) => item.missingCapabilities)
      .toSet()
      .toList(growable: false);
}

class WardrobeFunctionalProfileV1 {
  const WardrobeFunctionalProfileV1({
    required this.presentation,
    this.mobility,
    this.breathability,
    this.rainProtection,
    this.windProtection,
    this.walkingComfort,
    this.traction,
  });

  final WardrobeItemPresentationV1 presentation;
  final CapabilityLevel? mobility,
      breathability,
      rainProtection,
      windProtection,
      walkingComfort,
      traction;

  static WardrobeFunctionalProfileV1 fromResolved(
    ResolvedWardrobeItemV2 resolved,
  ) {
    ResolvedWardrobeItemProfile? profile;
    final document = resolved.raw.map<String, Object?>(
      (key, value) => MapEntry(key, value),
    );
    final decoded = const WardrobeProfilePersistenceCodec().fromDocumentMap(
      document,
    );
    final envelope = decoded.envelope;
    if (envelope != null) {
      final evidence = <ProfileEvidence>[
        ...envelope.machineEvidence.map((item) => item.toRuntimeEvidence()),
        ...envelope.userCorrections.values
            .where((item) => item.action.name == 'set')
            .map((item) => item.toRuntimeEvidence()),
      ];
      profile = const WardrobeProfileResolver().resolve(
        itemId: resolved.itemId,
        evidence: evidence,
      );
    }

    CapabilityLevel? known(ResolvedField<CapabilityLevel>? value) =>
        value?.isKnown == true ? value!.value : null;

    return WardrobeFunctionalProfileV1(
      presentation: _presentationFor(resolved),
      mobility: known(profile?.capabilities.mobility),
      breathability: known(profile?.capabilities.breathability),
      rainProtection: known(profile?.capabilities.rainProtection),
      windProtection: known(profile?.capabilities.windProtection),
      walkingComfort: known(profile?.capabilities.walkingComfort),
      traction: known(profile?.capabilities.traction),
    );
  }

  static WardrobeItemPresentationV1 _presentationFor(
    ResolvedWardrobeItemV2 resolved,
  ) {
    final raw = resolved.raw;
    final attributes = resolved.item.attributes;
    final explicit =
        (raw['stylingPresentation'] ??
                raw['presentationTarget'] ??
                attributes['stylingPresentation'] ??
                attributes['presentationTarget'])
            ?.toString()
            .trim()
            .toLowerCase();
    if (explicit == 'menswear') return WardrobeItemPresentationV1.menswear;
    if (explicit == 'womenswear') {
      return WardrobeItemPresentationV1.womenswear;
    }
    if (explicit == 'unisex') return WardrobeItemPresentationV1.unisex;

    final type = resolved.item.canonicalType.toLowerCase();
    if (const {
      'bra',
      'blouse',
      'dress',
      'heels',
      'maxi_skirt',
      'midi_skirt',
      'mini_skirt',
      'skirt',
    }.contains(type)) {
      return WardrobeItemPresentationV1.womenswear;
    }
    // Most ordinary tops, trousers, outerwear and footwear are not reliably
    // presentation-exclusive from an image or canonical type alone.
    return WardrobeItemPresentationV1.unknown;
  }
}

abstract final class FunctionalSuitabilityEvaluatorV1 {
  static bool presentationAllowed(
    ResolvedWardrobeItemV2 item,
    StylingPresentation preference,
  ) {
    if (!preference.filtersWardrobe) return true;
    final presentation = WardrobeFunctionalProfileV1.fromResolved(
      item,
    ).presentation;
    if (presentation == WardrobeItemPresentationV1.unknown ||
        presentation == WardrobeItemPresentationV1.unisex) {
      return true;
    }
    return switch (preference) {
      StylingPresentation.menswear =>
        presentation != WardrobeItemPresentationV1.womenswear,
      StylingPresentation.womenswear =>
        presentation != WardrobeItemPresentationV1.menswear,
      StylingPresentation.mixed || StylingPresentation.noPreference => true,
    };
  }

  static CandidateFunctionalAssessmentV1 assessCandidate({
    required V2FlexibleOutfitResult outfit,
    required Iterable<ResolvedWardrobeItemV2> source,
    required ActivityFunctionalRequirementsV1 requirements,
  }) {
    final byId = {for (final item in source) item.itemId: item};
    final assessments = <ItemFunctionalAssessmentV1>[];
    for (final selected in outfit.items) {
      final resolved = byId[selected.itemId];
      if (resolved == null) continue;
      assessments.add(
        _assessItem(resolved: resolved, requirements: requirements),
      );
    }
    final tier = assessments.isEmpty
        ? FunctionalSuitabilityTierV1.strongCompromise
        : assessments
              .map((item) => item.tier)
              .reduce(
                (left, right) => left.severity >= right.severity ? left : right,
              );
    return CandidateFunctionalAssessmentV1(
      tier: tier,
      items: List<ItemFunctionalAssessmentV1>.unmodifiable(assessments),
    );
  }

  static ItemFunctionalAssessmentV1 _assessItem({
    required ResolvedWardrobeItemV2 resolved,
    required ActivityFunctionalRequirementsV1 requirements,
  }) {
    final item = resolved.item;
    final type = item.canonicalType.toLowerCase();
    final profile = WardrobeFunctionalProfileV1.fromResolved(resolved);
    final isFeet = item.bodySlots.contains('feet');
    final isBottom = item.bodySlots.contains('lower_body');
    final isUpper = item.bodySlots.contains('upper_body');
    final isOuter =
        item.layerPosition == 'outer' || item.layerPosition == 'shell';

    if (requirements.demandingTrailActivity && isFeet) {
      if (_isOpenOrFormalFootwear(type)) {
        return _result(
          resolved,
          FunctionalSuitabilityTierV1.inappropriate,
          const ['terrain_footwear_inappropriate'],
          const ['hiking_footwear', 'traction', 'walking_stability'],
          'turistické alebo trailové topánky s istým gripom',
        );
      }
      if (_isHikingFootwear(type)) {
        final traction = profile.traction;
        return _result(
          resolved,
          traction == CapabilityLevel.low || traction == CapabilityLevel.veryLow
              ? FunctionalSuitabilityTierV1.acceptableCompromise
              : FunctionalSuitabilityTierV1.ideal,
          traction == CapabilityLevel.low || traction == CapabilityLevel.veryLow
              ? const ['hiking_footwear_low_observed_traction']
              : const [],
          traction == CapabilityLevel.low || traction == CapabilityLevel.veryLow
              ? const ['traction']
              : const [],
          traction == CapabilityLevel.low || traction == CapabilityLevel.veryLow
              ? 'turistické topánky s lepším gripom'
              : null,
        );
      }
      return _result(
        resolved,
        FunctionalSuitabilityTierV1.strongCompromise,
        [
          'footwear_not_hiking_or_trail_rated',
          if (requirements.wetGroundRisk) 'wet_terrain_grip_unverified',
        ],
        const ['hiking_footwear', 'traction', 'walking_stability'],
        'ľahšie turistické alebo trailové topánky s dobrým gripom',
      );
    }

    if (requirements.terrainActivity && isFeet) {
      if (_isOpenOrFormalFootwear(type)) {
        return _result(
          resolved,
          FunctionalSuitabilityTierV1.inappropriate,
          const ['terrain_footwear_inappropriate'],
          const ['closed_practical_footwear'],
          'uzavretá praktická obuv do terénu',
        );
      }
      if (_isHikingFootwear(type)) {
        return _result(resolved, FunctionalSuitabilityTierV1.ideal);
      }
      if (requirements.wetGroundRisk &&
          !_atLeast(profile.traction, CapabilityLevel.medium)) {
        return _result(
          resolved,
          FunctionalSuitabilityTierV1.strongCompromise,
          const ['wet_terrain_grip_unverified'],
          const ['wet_terrain_footwear', 'traction'],
          'trailová obuv s lepším gripom do mokrého terénu',
        );
      }
      return _result(
        resolved,
        FunctionalSuitabilityTierV1.acceptableCompromise,
        const ['general_footwear_for_terrain'],
        const ['terrain_footwear'],
        'praktická trailová obuv',
      );
    }

    if (requirements.demandingTrailActivity && isBottom) {
      if (_isSkirtOrDress(type)) {
        return _result(
          resolved,
          FunctionalSuitabilityTierV1.inappropriate,
          const ['bottom_mobility_inappropriate_for_long_hike'],
          const ['hiking_bottom', 'mobility'],
          'pohyblivé turistické nohavice',
        );
      }
      if (type == 'jeans' ||
          !_atLeast(profile.mobility, CapabilityLevel.medium)) {
        return _result(
          resolved,
          FunctionalSuitabilityTierV1.strongCompromise,
          const ['bottom_mobility_compromise_for_long_hike'],
          const ['hiking_bottom', 'mobility', 'moisture_handling'],
          'ľahké turistické nohavice s lepšou pohyblivosťou',
        );
      }
      if (_isTechnicalBottom(type, item.outfitFunctions)) {
        return _result(resolved, FunctionalSuitabilityTierV1.ideal);
      }
      return _result(
        resolved,
        FunctionalSuitabilityTierV1.acceptableCompromise,
      );
    }

    if (requirements.demandingTrailActivity && isUpper && !isOuter) {
      if (type.contains('dress_shirt') || type == 'blouse') {
        return _result(
          resolved,
          FunctionalSuitabilityTierV1.strongCompromise,
          const ['top_activity_breathability_compromise'],
          const ['activity_top', 'breathability'],
          'funkčný alebo dobre priedušný vrch',
        );
      }
      if (_atLeast(profile.breathability, CapabilityLevel.medium) ||
          _containsAny(type, const {'sport', 'technical', 'base_layer'})) {
        return _result(resolved, FunctionalSuitabilityTierV1.good);
      }
      return _result(
        resolved,
        FunctionalSuitabilityTierV1.acceptableCompromise,
        const ['top_moisture_handling_unknown'],
        const ['breathability'],
        'priedušný funkčný vrch',
      );
    }

    if ((requirements.isRainy || requirements.wetGroundRisk) &&
        requirements.outdoor &&
        isOuter) {
      if (_atLeast(profile.rainProtection, CapabilityLevel.medium) ||
          _containsAny(type, const {'rain', 'shell', 'waterproof'})) {
        return _result(resolved, FunctionalSuitabilityTierV1.ideal);
      }
      if (_containsAny(type, const {'denim', 'blazer', 'suit_jacket'})) {
        return _result(
          resolved,
          FunctionalSuitabilityTierV1.strongCompromise,
          const ['outerwear_rain_protection_missing'],
          const ['rain_shell'],
          'ľahká nepremokavá vrstva',
        );
      }
      return _result(
        resolved,
        FunctionalSuitabilityTierV1.acceptableCompromise,
        const ['outerwear_rain_protection_unknown'],
        const ['rain_protection'],
        'vrchná vrstva s overenou ochranou pred dažďom',
      );
    }

    if (requirements.athletic &&
        (_isSkirtOrDress(type) ||
            type.contains('suit') ||
            type.contains('heel'))) {
      return _result(
        resolved,
        FunctionalSuitabilityTierV1.inappropriate,
        const ['sport_mobility_inappropriate'],
        const ['sport_mobility'],
        'športový kúsok s voľnosťou pohybu',
      );
    }

    if (requirements.longWalkingDay && isFeet) {
      if (_atLeast(profile.walkingComfort, CapabilityLevel.medium) ||
          _isHikingFootwear(type) ||
          type.contains('running')) {
        return _result(resolved, FunctionalSuitabilityTierV1.good);
      }
      if (_isOpenOrFormalFootwear(type)) {
        return _result(
          resolved,
          FunctionalSuitabilityTierV1.strongCompromise,
          const ['long_walk_comfort_unverified'],
          const ['walking_comfort'],
          'pohodlná obuv na celodennú chôdzu',
        );
      }
      return _result(
        resolved,
        FunctionalSuitabilityTierV1.acceptableCompromise,
      );
    }

    return _result(resolved, FunctionalSuitabilityTierV1.good);
  }

  static ItemFunctionalAssessmentV1 _result(
    ResolvedWardrobeItemV2 resolved,
    FunctionalSuitabilityTierV1 tier, [
    List<String> reasons = const <String>[],
    List<String> missing = const <String>[],
    String? replacement,
  ]) => ItemFunctionalAssessmentV1(
    itemId: resolved.itemId,
    tier: tier,
    reasonCodes: List.unmodifiable(reasons),
    missingCapabilities: List.unmodifiable(missing),
    idealReplacementDescription: replacement,
  );

  static bool _isHikingFootwear(String type) => const {
    'hiking_boots',
    'hiking_shoes',
    'trail_shoes',
    'trekking_boots',
    'trekking_shoes',
  }.contains(type);

  static bool _isOpenOrFormalFootwear(String type) => _containsAny(type, const {
    'sandal',
    'flip_flop',
    'slide',
    'heel',
    'pump',
    'oxford',
    'dress_shoe',
    'loafer',
  });

  static bool _isSkirtOrDress(String type) =>
      type == 'dress' || type.contains('skirt');

  static bool _isTechnicalBottom(String type, List<String> functions) =>
      _containsAny(type, const {'hiking', 'trail', 'track', 'outdoor'}) ||
      functions.any(
        (value) => _containsAny(value.toLowerCase(), const {
          'sport',
          'outdoor',
          'mobility',
        }),
      );

  static bool _containsAny(String value, Set<String> parts) =>
      parts.any(value.contains);

  static bool _atLeast(CapabilityLevel? value, CapabilityLevel minimum) {
    if (value == null || value == CapabilityLevel.unknown) return false;
    return value.index >= minimum.index;
  }
}
