import 'wardrobe_observation_contract.dart';

enum VisionInputAssessment {
  validSingleItem,
  multipleItems,
  insufficientVisualInformation,
  nonWardrobeObject,
  ambiguousSubject;

  String get wireName => switch (this) {
    VisionInputAssessment.validSingleItem => 'valid_single_item',
    VisionInputAssessment.multipleItems => 'multiple_items',
    VisionInputAssessment.insufficientVisualInformation =>
      'insufficient_visual_information',
    VisionInputAssessment.nonWardrobeObject => 'non_wardrobe_object',
    VisionInputAssessment.ambiguousSubject => 'ambiguous_subject',
  };

  bool get isValid => this == VisionInputAssessment.validSingleItem;

  static VisionInputAssessment fromWireName(String value) =>
      VisionInputAssessment.values.firstWhere(
        (item) => item.wireName == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown Vision input assessment',
        ),
      );
}

enum VisibilityTrust { trusted, supported, unverified, rejected }

enum RegionDeclarationState {
  explicitlyVisible,
  impliedByPositiveObservation,
  undeclared,
  contradicted,
}

class PropertyVisibilityRequirement {
  const PropertyVisibilityRequirement({
    required this.property,
    required this.requiredPositiveRegions,
    required this.requiredAbsenceRegions,
    required this.minimumPositiveScope,
    required this.minimumAbsenceScope,
    this.absenceRequiresMultipleViews = false,
    this.absenceCanBeObserved = true,
    this.maximumTrustedConfidence = 0.95,
  });

  final String property;
  final Set<ObservationVisualRegion> requiredPositiveRegions;
  final Set<ObservationVisualRegion> requiredAbsenceRegions;
  final ObservationVisibilityScope minimumPositiveScope;
  final ObservationVisibilityScope minimumAbsenceScope;
  final bool absenceRequiresMultipleViews;
  final bool absenceCanBeObserved;
  final double maximumTrustedConfidence;
}

abstract final class PropertyVisibilityRequirements {
  static const Map<String, PropertyVisibilityRequirement> all = {
    'visiblePocketStructure': PropertyVisibilityRequirement(
      property: 'visiblePocketStructure',
      requiredPositiveRegions: {
        ObservationVisualRegion.pocketArea,
        ObservationVisualRegion.front,
        ObservationVisualRegion.side,
        ObservationVisualRegion.back,
      },
      requiredAbsenceRegions: {
        ObservationVisualRegion.front,
        ObservationVisualRegion.side,
        ObservationVisualRegion.pocketArea,
      },
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.complete,
      absenceRequiresMultipleViews: true,
      maximumTrustedConfidence: 0.9,
    ),
    'hasHood': PropertyVisibilityRequirement(
      property: 'hasHood',
      requiredPositiveRegions: {
        ObservationVisualRegion.collar,
        ObservationVisualRegion.back,
      },
      requiredAbsenceRegions: {
        ObservationVisualRegion.collar,
        ObservationVisualRegion.back,
      },
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.sufficient,
      maximumTrustedConfidence: 0.9,
    ),
    'frontClosure': PropertyVisibilityRequirement(
      property: 'frontClosure',
      requiredPositiveRegions: {ObservationVisualRegion.front},
      requiredAbsenceRegions: {ObservationVisualRegion.front},
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.sufficient,
      maximumTrustedConfidence: 0.9,
    ),
    'visibleStretchCue': PropertyVisibilityRequirement(
      property: 'visibleStretchCue',
      requiredPositiveRegions: {
        ObservationVisualRegion.surfaceDetail,
        ObservationVisualRegion.side,
      },
      requiredAbsenceRegions: {},
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.complete,
      absenceCanBeObserved: false,
      maximumTrustedConfidence: 0.85,
    ),
    'necklineShape': PropertyVisibilityRequirement(
      property: 'necklineShape',
      requiredPositiveRegions: {ObservationVisualRegion.neckline},
      requiredAbsenceRegions: {},
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.complete,
    ),
    'footwearFastening': PropertyVisibilityRequirement(
      property: 'footwearFastening',
      requiredPositiveRegions: {
        ObservationVisualRegion.fasteningArea,
        ObservationVisualRegion.footwearUpper,
      },
      requiredAbsenceRegions: {},
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.complete,
    ),
    'visibleTread': PropertyVisibilityRequirement(
      property: 'visibleTread',
      requiredPositiveRegions: {ObservationVisualRegion.outsole},
      requiredAbsenceRegions: {},
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.complete,
    ),
    'visibleBulk': PropertyVisibilityRequirement(
      property: 'visibleBulk',
      requiredPositiveRegions: {
        ObservationVisualRegion.fullSilhouette,
        ObservationVisualRegion.side,
      },
      requiredAbsenceRegions: {},
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.complete,
      maximumTrustedConfidence: 0.9,
    ),
    'coverage': PropertyVisibilityRequirement(
      property: 'coverage',
      requiredPositiveRegions: {ObservationVisualRegion.fullSilhouette},
      requiredAbsenceRegions: {},
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.complete,
    ),
    'footwearUpperHeight': PropertyVisibilityRequirement(
      property: 'footwearUpperHeight',
      requiredPositiveRegions: {
        ObservationVisualRegion.footwearUpper,
        ObservationVisualRegion.side,
      },
      requiredAbsenceRegions: {},
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.complete,
    ),
    'footwearConstruction': PropertyVisibilityRequirement(
      property: 'footwearConstruction',
      requiredPositiveRegions: {ObservationVisualRegion.footwearUpper},
      requiredAbsenceRegions: {},
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.complete,
    ),
    'soleProfile': PropertyVisibilityRequirement(
      property: 'soleProfile',
      requiredPositiveRegions: {
        ObservationVisualRegion.soleProfile,
        ObservationVisualRegion.side,
      },
      requiredAbsenceRegions: {},
      minimumPositiveScope: ObservationVisibilityScope.sufficient,
      minimumAbsenceScope: ObservationVisibilityScope.complete,
    ),
  };

  static Set<ObservationVisualRegion> impliedPositiveRegions<T>(
    String property,
    T value,
  ) {
    return switch (property) {
      'hasHood' when value == true => const {ObservationVisualRegion.collar},
      'frontClosure' when value != FrontClosure.none => const {
        ObservationVisualRegion.front,
      },
      'visiblePocketStructure' when value != VisiblePocketStructure.none =>
        const {ObservationVisualRegion.pocketArea},
      'visibleStretchCue' when value == true => const {
        ObservationVisualRegion.surfaceDetail,
      },
      'necklineShape' => const {ObservationVisualRegion.neckline},
      'footwearFastening' => const {ObservationVisualRegion.fasteningArea},
      'visibleTread' => const {ObservationVisualRegion.outsole},
      'footwearUpperHeight' => const {ObservationVisualRegion.footwearUpper},
      'footwearConstruction' => const {ObservationVisualRegion.footwearUpper},
      'soleProfile' => const {ObservationVisualRegion.soleProfile},
      _ => const {},
    };
  }
}

class VisibilityScopeQualification {
  const VisibilityScopeQualification({
    required this.property,
    required this.modelDeclaredScope,
    required this.systemQualifiedScope,
    required this.trust,
    required this.modelDeclaredRegions,
    this.impliedRegions = const {},
    this.regionDeclarationState = RegionDeclarationState.undeclared,
    required this.reasonCodes,
  });

  final String property;
  final ObservationVisibilityScope? modelDeclaredScope;
  final ObservationVisibilityScope systemQualifiedScope;
  final VisibilityTrust trust;
  final Set<ObservationVisualRegion> modelDeclaredRegions;
  final Set<ObservationVisualRegion> impliedRegions;
  final RegionDeclarationState regionDeclarationState;
  final List<String> reasonCodes;

  Map<String, Object?> toMap() => {
    'property': property,
    'modelDeclaredVisibilityScope': modelDeclaredScope?.wireName,
    'systemQualifiedVisibilityScope': systemQualifiedScope.wireName,
    'visibilityTrust': trust.name,
    'modelDeclaredRegions':
        modelDeclaredRegions.map((item) => item.wireName).toList()..sort(),
    'impliedRegions': impliedRegions.map((item) => item.wireName).toList()
      ..sort(),
    'regionDeclarationState': regionDeclarationState.name,
    'reasonCodes': reasonCodes,
  };
}

class VisionVisibilityTrustReport {
  const VisionVisibilityTrustReport({
    required this.inputAssessment,
    required this.qualifiedBundle,
    required this.properties,
  });

  final VisionInputAssessment inputAssessment;
  final ClothingObservationBundle qualifiedBundle;
  final Map<String, VisibilityScopeQualification> properties;

  Map<String, Object?> toMap() => {
    'inputAssessment': inputAssessment.wireName,
    'properties': {
      for (final entry in properties.entries) entry.key: entry.value.toMap(),
    },
  };
}

final class VisionVisibilityTrustQualifier {
  const VisionVisibilityTrustQualifier();

  VisionVisibilityTrustReport qualify({
    required ClothingObservationBundle bundle,
    required VisionInputAssessment inputAssessment,
    int viewCount = 1,
    Map<String, Set<ObservationVisualRegion>> complementaryRegions = const {},
  }) {
    final reports = <String, VisibilityScopeQualification>{};

    ObservationValue<T>? property<T>(
      String name,
      ObservationValue<T>? raw, {
      required bool Function(T value) isAbsence,
    }) {
      if (raw == null) return null;
      final result = _qualify(
        name,
        raw,
        inputAssessment: inputAssessment,
        quality: bundle.quality,
        viewCount: viewCount,
        complementaryRegions: complementaryRegions[name] ?? const {},
        isAbsence: isAbsence,
      );
      reports[name] = result.report;
      return result.observation;
    }

    final qualified = ClothingObservationBundle(
      analysisId: bundle.analysisId,
      modelVersion: bundle.modelVersion,
      sourceReference: bundle.sourceReference,
      observedAt: bundle.observedAt,
      quality: bundle.quality,
      coverage: property('coverage', bundle.coverage, isAbsence: (_) => false),
      hasHood: property(
        'hasHood',
        bundle.hasHood,
        isAbsence: (value) => !value,
      ),
      frontClosure: property(
        'frontClosure',
        bundle.frontClosure,
        isAbsence: (value) => value == FrontClosure.none,
      ),
      visibleBulk: property(
        'visibleBulk',
        bundle.visibleBulk,
        isAbsence: (_) => false,
      ),
      surfaceAppearance: property(
        'surfaceAppearance',
        bundle.surfaceAppearance,
        isAbsence: (_) => false,
      ),
      necklineShape: property(
        'necklineShape',
        bundle.necklineShape,
        isAbsence: (_) => false,
      ),
      visiblePocketStructure: property(
        'visiblePocketStructure',
        bundle.visiblePocketStructure,
        isAbsence: (value) => value == VisiblePocketStructure.none,
      ),
      visibleStretchCue: property(
        'visibleStretchCue',
        bundle.visibleStretchCue,
        isAbsence: (value) => !value,
      ),
      sportyCues: property(
        'sportyCues',
        bundle.sportyCues,
        isAbsence: (_) => false,
      ),
      formalCues: property(
        'formalCues',
        bundle.formalCues,
        isAbsence: (_) => false,
      ),
      footwearConstruction: property(
        'footwearConstruction',
        bundle.footwearConstruction,
        isAbsence: (_) => false,
      ),
      footwearFastening: property(
        'footwearFastening',
        bundle.footwearFastening,
        isAbsence: (_) => false,
      ),
      soleProfile: property(
        'soleProfile',
        bundle.soleProfile,
        isAbsence: (_) => false,
      ),
      visibleTread: property(
        'visibleTread',
        bundle.visibleTread,
        isAbsence: (_) => false,
      ),
      footwearUpperHeight: property(
        'footwearUpperHeight',
        bundle.footwearUpperHeight,
        isAbsence: (_) => false,
      ),
    );
    return VisionVisibilityTrustReport(
      inputAssessment: inputAssessment,
      qualifiedBundle: qualified,
      properties: Map.unmodifiable(reports),
    );
  }

  ({ObservationValue<T> observation, VisibilityScopeQualification report})
  _qualify<T>(
    String property,
    ObservationValue<T> raw, {
    required VisionInputAssessment inputAssessment,
    required ObservationImageQuality quality,
    required int viewCount,
    required Set<ObservationVisualRegion> complementaryRegions,
    required bool Function(T value) isAbsence,
  }) {
    final requirement = PropertyVisibilityRequirements.all[property];
    final declared =
        raw.visibilityScope ??
        (raw.state == ObservationState.notVisible
            ? ObservationVisibilityScope.notVisible
            : ObservationVisibilityScope.partial);
    final reasons = <String>[];
    if (!inputAssessment.isValid) {
      return (
        observation: raw.state == ObservationState.notApplicable
            ? ObservationValue<T>.notApplicable()
            : ObservationValue<T>.unknown(),
        report: VisibilityScopeQualification(
          property: property,
          modelDeclaredScope: raw.visibilityScope,
          systemQualifiedScope: ObservationVisibilityScope.notVisible,
          trust: VisibilityTrust.rejected,
          modelDeclaredRegions: raw.visibleRegions,
          regionDeclarationState: RegionDeclarationState.contradicted,
          reasonCodes: const ['invalid_input_visibility_rejected'],
        ),
      );
    }
    if (!raw.isObserved || requirement == null) {
      return (
        observation: raw,
        report: VisibilityScopeQualification(
          property: property,
          modelDeclaredScope: raw.visibilityScope,
          systemQualifiedScope: declared,
          trust: raw.isObserved
              ? VisibilityTrust.unverified
              : VisibilityTrust.supported,
          modelDeclaredRegions: raw.visibleRegions,
          regionDeclarationState:
              raw.visibilityScope == ObservationVisibilityScope.notVisible
              ? RegionDeclarationState.contradicted
              : RegionDeclarationState.undeclared,
          reasonCodes: [
            raw.isObserved
                ? 'no_property_visibility_requirement'
                : 'non_observed_state_preserved',
          ],
        ),
      );
    }

    final absence = isAbsence(raw.value as T);
    final requiredRegions = absence
        ? requirement.requiredAbsenceRegions
        : requirement.requiredPositiveRegions;
    final impliedRegions = absence || raw.visibleRegions.isNotEmpty
        ? const <ObservationVisualRegion>{}
        : PropertyVisibilityRequirements.impliedPositiveRegions(
            property,
            raw.value as T,
          );
    final effectiveRegions = {
      ...raw.visibleRegions,
      ...complementaryRegions,
      ...impliedRegions,
    };
    final hasRegions = requiredRegions.isEmpty
        ? !absence
        : absence
        ? effectiveRegions.containsAll(requiredRegions)
        : effectiveRegions.any(requiredRegions.contains);
    var qualifiedScope = declared;
    var trust = VisibilityTrust.trusted;
    var declarationState =
        raw.visibilityScope == ObservationVisibilityScope.notVisible
        ? RegionDeclarationState.contradicted
        : raw.visibleRegions.any(requiredRegions.contains)
        ? RegionDeclarationState.explicitlyVisible
        : impliedRegions.isNotEmpty
        ? RegionDeclarationState.impliedByPositiveObservation
        : RegionDeclarationState.undeclared;

    if (raw.visibilityScope == ObservationVisibilityScope.notVisible) {
      qualifiedScope = ObservationVisibilityScope.notVisible;
      trust = VisibilityTrust.rejected;
      reasons.add('declared_not_visible');
    } else if (raw.visibleRegions.isEmpty && impliedRegions.isEmpty) {
      qualifiedScope = ObservationVisibilityScope.partial;
      trust = VisibilityTrust.unverified;
      reasons.add('no_declared_relevant_regions');
    } else if (!hasRegions) {
      qualifiedScope = ObservationVisibilityScope.partial;
      trust = VisibilityTrust.rejected;
      reasons.add('required_region_not_declared');
    } else if (impliedRegions.isNotEmpty &&
        !raw.visibleRegions.any(requiredRegions.contains)) {
      if (_scopeRank(qualifiedScope) <
          _scopeRank(ObservationVisibilityScope.sufficient)) {
        qualifiedScope = ObservationVisibilityScope.sufficient;
      }
      trust = VisibilityTrust.supported;
      reasons.add('positive_observation_implies_region');
    }
    if (quality.itemFullyVisible == false &&
        qualifiedScope == ObservationVisibilityScope.complete) {
      qualifiedScope = ObservationVisibilityScope.sufficient;
      trust = VisibilityTrust.supported;
      reasons.add('cropped_item_downgraded_complete');
    }
    if (quality.occlusion == ImageOcclusion.substantial ||
        quality.clarity == ImageQualityLevel.low ||
        quality.backgroundInterference == ImageQualityLevel.high) {
      qualifiedScope = ObservationVisibilityScope.partial;
      trust = VisibilityTrust.unverified;
      reasons.add('image_quality_limits_visibility');
    }
    if (absence && !requirement.absenceCanBeObserved) {
      qualifiedScope = ObservationVisibilityScope.partial;
      trust = VisibilityTrust.rejected;
      reasons.add('absence_not_visually_provable');
    }
    if (absence && requirement.absenceRequiresMultipleViews && viewCount < 2) {
      qualifiedScope = ObservationVisibilityScope.partial;
      trust = VisibilityTrust.unverified;
      reasons.add('absence_requires_complementary_views');
    }
    final minimum = absence
        ? requirement.minimumAbsenceScope
        : requirement.minimumPositiveScope;
    if (_scopeRank(qualifiedScope) < _scopeRank(minimum)) {
      reasons.add('qualified_scope_below_property_minimum');
    }
    final usable =
        trust != VisibilityTrust.rejected &&
        _scopeRank(qualifiedScope) >= _scopeRank(minimum);
    final confidence = raw.confidence <= requirement.maximumTrustedConfidence
        ? raw.confidence
        : requirement.maximumTrustedConfidence;
    final observation = usable
        ? ObservationValue<T>.observed(
            value: raw.value as T,
            confidence: confidence,
            visibilityScope: qualifiedScope,
            visibleRegions: {...raw.visibleRegions, ...impliedRegions},
          )
        : ObservationValue<T>.unknown();
    if (reasons.isEmpty) reasons.add('declared_scope_and_regions_supported');
    if (confidence < raw.confidence) {
      reasons.add('visibility_confidence_calibrated');
    }
    return (
      observation: observation,
      report: VisibilityScopeQualification(
        property: property,
        modelDeclaredScope: raw.visibilityScope,
        systemQualifiedScope: qualifiedScope,
        trust: trust,
        modelDeclaredRegions: raw.visibleRegions,
        impliedRegions: impliedRegions,
        regionDeclarationState: declarationState,
        reasonCodes: List.unmodifiable(reasons),
      ),
    );
  }

  static int _scopeRank(ObservationVisibilityScope scope) => switch (scope) {
    ObservationVisibilityScope.complete => 3,
    ObservationVisibilityScope.sufficient => 2,
    ObservationVisibilityScope.partial => 1,
    ObservationVisibilityScope.notVisible => 0,
  };
}
