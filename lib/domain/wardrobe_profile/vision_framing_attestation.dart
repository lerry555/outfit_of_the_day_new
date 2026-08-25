import 'vision_subject_safety.dart';
import 'vision_visibility_trust.dart';
import 'wardrobe_observation_contract.dart';

enum VisionItemExtent { whole, broad, local, indeterminate }

enum VisionSubjectOrientation { front, side, back, mixed, unknown }

enum VisionBoundary { top, bottom, left, right }

enum VisionFramingTrustState {
  attested,
  downgraded,
  rejected,
  legacyUnverified,
}

class VisionFramingAttestations {
  const VisionFramingAttestations({
    required this.visibleBoundaries,
    required this.primarySilhouetteContinuous,
    required this.visibleItemExtent,
    required this.localDetailOnly,
    required this.cropIndicators,
    required this.subjectOrientation,
  });

  final Set<VisionBoundary> visibleBoundaries;
  final bool primarySilhouetteContinuous;
  final VisionItemExtent visibleItemExtent;
  final bool localDetailOnly;
  final Set<String> cropIndicators;
  final VisionSubjectOrientation subjectOrientation;

  factory VisionFramingAttestations.fromMap(Map<String, dynamic> map) {
    final boundaries = map['visibleBoundaries'];
    final crops = map['cropIndicators'];
    if (boundaries is! List ||
        crops is! List ||
        map['primarySilhouetteContinuous'] is! bool ||
        map['localDetailOnly'] is! bool) {
      throw const FormatException('Invalid framing attestations');
    }
    return VisionFramingAttestations(
      visibleBoundaries: Set.unmodifiable(
        boundaries.map(
          (value) => VisionBoundary.values.firstWhere(
            (item) => item.name == value,
            orElse: () => throw FormatException('Invalid boundary: $value'),
          ),
        ),
      ),
      primarySilhouetteContinuous: map['primarySilhouetteContinuous'] as bool,
      visibleItemExtent: VisionItemExtent.values.firstWhere(
        (item) => item.name == map['visibleItemExtent'],
        orElse: () => throw const FormatException('Invalid visible extent'),
      ),
      localDetailOnly: map['localDetailOnly'] as bool,
      cropIndicators: Set.unmodifiable(crops.map((value) => value.toString())),
      subjectOrientation: VisionSubjectOrientation.values.firstWhere(
        (item) => item.name == map['subjectOrientation'],
        orElse: () => throw const FormatException('Invalid orientation'),
      ),
    );
  }

  Map<String, Object?> toMap() => {
    'visibleBoundaries': visibleBoundaries.map((item) => item.name).toList()
      ..sort(),
    'primarySilhouetteContinuous': primarySilhouetteContinuous,
    'visibleItemExtent': visibleItemExtent.name,
    'localDetailOnly': localDetailOnly,
    'cropIndicators': cropIndicators.toList()..sort(),
    'subjectOrientation': subjectOrientation.name,
  };
}

class VisionFramingAttestationReport {
  const VisionFramingAttestationReport({
    required this.modelDeclaredFraming,
    required this.systemAttestedFraming,
    required this.trustState,
    required this.attestations,
    required this.contradictions,
    required this.reasonCodes,
  });

  final VisionFramingClass modelDeclaredFraming;
  final VisionFramingClass systemAttestedFraming;
  final VisionFramingTrustState trustState;
  final VisionFramingAttestations? attestations;
  final List<String> contradictions;
  final List<String> reasonCodes;

  bool get hasWholeItemSilhouette =>
      attestations?.localDetailOnly == false &&
      attestations?.primarySilhouetteContinuous == true &&
      (attestations?.visibleItemExtent == VisionItemExtent.whole ||
          attestations?.visibleItemExtent == VisionItemExtent.broad) &&
      (systemAttestedFraming == VisionFramingClass.fullItem ||
          systemAttestedFraming == VisionFramingClass.mostlyVisible);

  VisionSubjectAssessment applyTo(VisionSubjectAssessment subject) =>
      VisionSubjectAssessment(
        subjectCountEstimate: subject.subjectCountEstimate,
        cardinality: subject.cardinality,
        primarySubjectPresent: subject.primarySubjectPresent,
        sameItemConsistency: subject.sameItemConsistency,
        subjectDomain: subject.subjectDomain,
        framing: systemAttestedFraming,
        reasonCodes: [...subject.reasonCodes, ...reasonCodes],
      );

  Map<String, Object?> toMap() => {
    'modelDeclaredFraming': modelDeclaredFraming.wireName,
    'systemAttestedFraming': systemAttestedFraming.wireName,
    'framingTrustState': trustState.name,
    'framingEvidence': attestations?.toMap(),
    'framingContradictions': contradictions,
    'reasonCodes': reasonCodes,
  };
}

final class VisionFramingAttestor {
  const VisionFramingAttestor();

  VisionFramingAttestationReport attest({
    required VisionInputAssessment inputAssessment,
    required VisionSubjectAssessment subject,
    required ObservationImageQuality quality,
    required VisionFramingAttestations? attestations,
  }) {
    if (attestations == null) {
      return VisionFramingAttestationReport(
        modelDeclaredFraming: subject.framing,
        systemAttestedFraming: subject.framing,
        trustState: VisionFramingTrustState.legacyUnverified,
        attestations: null,
        contradictions: const [],
        reasonCodes: const ['legacy_schema_without_framing_attestations'],
      );
    }
    final contradictions = <String>[];
    final reasons = <String>[];
    final validSubject =
        inputAssessment.isValid &&
        subject.cardinality == VisionSubjectCardinality.singleItemSupported &&
        subject.primarySubjectPresent &&
        subject.subjectDomain != VisionSubjectDomain.unknown &&
        subject.subjectDomain != VisionSubjectDomain.mixed;
    VisionFramingClass framing;
    if (!validSubject) {
      framing = subject.primarySubjectPresent
          ? VisionFramingClass.ambiguousFraming
          : VisionFramingClass.noItem;
      contradictions.add('input_or_subject_rejects_whole_item_framing');
    } else if (attestations.localDetailOnly ||
        attestations.visibleItemExtent == VisionItemExtent.local) {
      framing = VisionFramingClass.detailOnly;
      if (subject.framing != VisionFramingClass.detailOnly) {
        contradictions.add('local_detail_contradicts_declared_framing');
      }
    } else if (!attestations.primarySilhouetteContinuous ||
        attestations.visibleItemExtent == VisionItemExtent.indeterminate) {
      framing = VisionFramingClass.partialItem;
      contradictions.add('silhouette_not_continuous_or_indeterminate');
    } else {
      final top = attestations.visibleBoundaries.contains(VisionBoundary.top);
      final bottom = attestations.visibleBoundaries.contains(
        VisionBoundary.bottom,
      );
      final severeCrop = attestations.cropIndicators.contains('severe_crop');
      if (severeCrop) {
        framing = VisionFramingClass.partialItem;
        contradictions.add('severe_crop');
      } else if (quality.itemFullyVisible == true &&
          top &&
          bottom &&
          attestations.visibleItemExtent == VisionItemExtent.whole &&
          attestations.cropIndicators.isEmpty) {
        framing = VisionFramingClass.fullItem;
      } else if (attestations.visibleItemExtent == VisionItemExtent.broad ||
          (attestations.visibleItemExtent == VisionItemExtent.whole &&
              (top || bottom))) {
        framing = VisionFramingClass.mostlyVisible;
        if (!top || !bottom) {
          contradictions.add('whole_item_boundary_missing');
        }
        if (quality.itemFullyVisible == false) {
          contradictions.add('item_not_fully_visible');
        }
      } else {
        framing = VisionFramingClass.partialItem;
      }
    }
    // Attestations may confirm or downgrade the model claim, but this
    // same-model contract must not silently promote a conservative claim.
    if (_framingRank(framing) > _framingRank(subject.framing)) {
      framing = subject.framing;
      reasons.add('conservative_model_framing_not_auto_promoted');
    }
    if (subject.framing == VisionFramingClass.fullItem &&
        framing != VisionFramingClass.fullItem) {
      reasons.add('model_full_item_downgraded');
    }
    reasons.add(
      framing == VisionFramingClass.fullItem
          ? 'whole_item_attestations_consistent'
          : framing == VisionFramingClass.mostlyVisible
          ? 'broad_silhouette_attested'
          : framing == VisionFramingClass.detailOnly
          ? 'local_detail_only'
          : 'whole_item_attestations_insufficient',
    );
    return VisionFramingAttestationReport(
      modelDeclaredFraming: subject.framing,
      systemAttestedFraming: framing,
      trustState: framing == subject.framing
          ? VisionFramingTrustState.attested
          : VisionFramingTrustState.downgraded,
      attestations: attestations,
      contradictions: List.unmodifiable(contradictions..sort()),
      reasonCodes: List.unmodifiable(reasons..sort()),
    );
  }

  static int _framingRank(VisionFramingClass value) => switch (value) {
    VisionFramingClass.fullItem => 4,
    VisionFramingClass.mostlyVisible => 3,
    VisionFramingClass.partialItem => 2,
    VisionFramingClass.detailOnly => 1,
    VisionFramingClass.ambiguousFraming => 0,
    VisionFramingClass.noItem => 0,
  };
}

enum NegativeClaimCorroborationState {
  corroborated,
  blocked,
  notNegative,
  notApplicable,
  conflicting,
}

class NegativeClaimCorroborationAudit {
  const NegativeClaimCorroborationAudit({
    required this.property,
    required this.state,
    required this.requiredRegions,
    required this.coveredRegions,
    required this.missingRegions,
    required this.corroboratingViews,
    required this.conflictingPositiveEvidence,
    required this.reasonCodes,
  });

  final String property;
  final NegativeClaimCorroborationState state;
  final Set<ObservationVisualRegion> requiredRegions;
  final Set<ObservationVisualRegion> coveredRegions;
  final Set<ObservationVisualRegion> missingRegions;
  final int corroboratingViews;
  final bool conflictingPositiveEvidence;
  final List<String> reasonCodes;

  Map<String, Object?> toMap() => {
    'property': property,
    'corroborationState': state.name,
    'requiredRegions': requiredRegions.map((item) => item.wireName).toList()
      ..sort(),
    'coveredRequiredRegions':
        coveredRegions.map((item) => item.wireName).toList()..sort(),
    'missingRequiredRegions':
        missingRegions.map((item) => item.wireName).toList()..sort(),
    'corroboratingViews': corroboratingViews,
    'conflictingPositiveEvidence': conflictingPositiveEvidence,
    'reasonCodes': reasonCodes,
  };
}

class NegativeClaimCorroborationReport {
  const NegativeClaimCorroborationReport({
    required this.qualifiedBundle,
    required this.claims,
  });

  final ClothingObservationBundle qualifiedBundle;
  final Map<String, NegativeClaimCorroborationAudit> claims;

  Map<String, Object?> toMap() => {
    'claims': {
      for (final entry in claims.entries) entry.key: entry.value.toMap(),
    },
  };
}

final class VisionNegativeClaimCorroborator {
  const VisionNegativeClaimCorroborator();

  NegativeClaimCorroborationReport qualify({
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
    required VisionFramingAttestationReport framing,
    int viewCount = 1,
    bool sameItemViews = true,
    Map<String, Set<ObservationVisualRegion>> complementaryRegions = const {},
    Set<String> conflictingPositiveProperties = const {},
  }) {
    final audits = <String, NegativeClaimCorroborationAudit>{};

    ObservationValue<T>? check<T>(
      String property,
      ObservationValue<T>? value, {
      required bool Function(T) isNegative,
      required Set<ObservationVisualRegion> required,
      required bool domainAllowed,
      required bool orientationAllowed,
      bool requiresMultipleViews = false,
      bool visuallyConfirmable = true,
    }) {
      if (value == null || !value.isObserved || !isNegative(value.value as T)) {
        return value;
      }
      final covered = {
        ...value.visibleRegions,
        ...?complementaryRegions[property],
      };
      final missing = required.difference(covered);
      final reasons = <String>[];
      if (!domainAllowed) reasons.add('negative_claim_domain_not_applicable');
      if (!framing.hasWholeItemSilhouette) {
        reasons.add('system_framing_lacks_whole_item_silhouette');
      }
      if (!orientationAllowed) {
        reasons.add('subject_orientation_cannot_assess_region');
      }
      if (missing.isNotEmpty) {
        reasons.add('required_region_not_positively_visible');
      }
      if (bundle.quality.occlusion != ImageOcclusion.none) {
        reasons.add('occlusion_blocks_absence');
      }
      if (framing.attestations?.cropIndicators.isNotEmpty ?? true) {
        reasons.add('crop_blocks_absence');
      }
      if (!visuallyConfirmable) reasons.add('absence_not_visually_confirmable');
      if (requiresMultipleViews && (!sameItemViews || viewCount < 2)) {
        reasons.add('complementary_same_item_views_required');
      }
      final hasPositiveConflict = conflictingPositiveProperties.contains(
        property,
      );
      if (hasPositiveConflict) {
        reasons.add('conflicting_positive_evidence');
      }
      final corroborated = reasons.isEmpty;
      audits[property] = NegativeClaimCorroborationAudit(
        property: property,
        state: hasPositiveConflict
            ? NegativeClaimCorroborationState.conflicting
            : corroborated
            ? NegativeClaimCorroborationState.corroborated
            : domainAllowed
            ? NegativeClaimCorroborationState.blocked
            : NegativeClaimCorroborationState.notApplicable,
        requiredRegions: required,
        coveredRegions: required.intersection(covered),
        missingRegions: missing,
        corroboratingViews: viewCount,
        conflictingPositiveEvidence: hasPositiveConflict,
        reasonCodes: List.unmodifiable(
          corroborated
              ? <String>['negative_claim_corroborated']
              : (reasons..sort()),
        ),
      );
      return corroborated ? value : ObservationValue<T>.unknown();
    }

    final orientation =
        framing.attestations?.subjectOrientation ??
        VisionSubjectOrientation.unknown;
    final frontOrientation =
        orientation == VisionSubjectOrientation.front ||
        orientation == VisionSubjectOrientation.mixed;
    final closure = check<FrontClosure>(
      'frontClosure',
      bundle.frontClosure,
      isNegative: (value) => value == FrontClosure.none,
      required: const {
        ObservationVisualRegion.front,
        ObservationVisualRegion.fasteningArea,
      },
      domainAllowed:
          subject.subjectDomain == VisionSubjectDomain.garmentUpper ||
          subject.subjectDomain == VisionSubjectDomain.garmentOuterwear,
      // A lower-garment fly is intentionally not qualified by this broad
      // legacy property; it needs a separate domain-aware observation.
      orientationAllowed: frontOrientation,
    );
    final hood = check<bool>(
      'hasHood',
      bundle.hasHood,
      isNegative: (value) => value == false,
      required: const {
        ObservationVisualRegion.collar,
        ObservationVisualRegion.back,
      },
      domainAllowed:
          subject.subjectDomain == VisionSubjectDomain.garmentUpper ||
          subject.subjectDomain == VisionSubjectDomain.garmentOuterwear,
      orientationAllowed:
          orientation == VisionSubjectOrientation.back ||
          orientation == VisionSubjectOrientation.mixed,
    );
    final pocket = check<VisiblePocketStructure>(
      'visiblePocketStructure',
      bundle.visiblePocketStructure,
      isNegative: (value) => value == VisiblePocketStructure.none,
      required: const {
        ObservationVisualRegion.front,
        ObservationVisualRegion.side,
        ObservationVisualRegion.back,
        ObservationVisualRegion.pocketArea,
      },
      domainAllowed: subject.subjectDomain.isGarment,
      orientationAllowed: orientation == VisionSubjectOrientation.mixed,
      requiresMultipleViews: true,
    );
    final stretch = check<bool>(
      'visibleStretchCue',
      bundle.visibleStretchCue,
      isNegative: (value) => value == false,
      required: const {ObservationVisualRegion.surfaceDetail},
      domainAllowed: true,
      orientationAllowed: true,
      visuallyConfirmable: false,
    );
    return NegativeClaimCorroborationReport(
      qualifiedBundle: ClothingObservationBundle(
        analysisId: bundle.analysisId,
        modelVersion: bundle.modelVersion,
        sourceReference: bundle.sourceReference,
        observedAt: bundle.observedAt,
        quality: bundle.quality,
        coverage: bundle.coverage,
        hasHood: hood,
        frontClosure: closure,
        visibleBulk: bundle.visibleBulk,
        surfaceAppearance: bundle.surfaceAppearance,
        necklineShape: bundle.necklineShape,
        visiblePocketStructure: pocket,
        visibleStretchCue: stretch,
        sportyCues: bundle.sportyCues,
        formalCues: bundle.formalCues,
        footwearConstruction: bundle.footwearConstruction,
        footwearFastening: bundle.footwearFastening,
        soleProfile: bundle.soleProfile,
        visibleTread: bundle.visibleTread,
        footwearUpperHeight: bundle.footwearUpperHeight,
      ),
      claims: Map.unmodifiable(audits),
    );
  }
}
