import 'wardrobe_observation_contract.dart';
import 'vision_visibility_trust.dart';
import 'vision_subject_safety.dart';

enum VisionIdentityFamily {
  top,
  knitwear,
  trousers,
  shorts,
  jacketOuterwear,
  sneakers,
  boots;

  String get wireName => switch (this) {
    VisionIdentityFamily.jacketOuterwear => 'jacket_outerwear',
    _ => name,
  };
}

enum VisionFamilyResolutionState {
  confirmed,
  supported,
  ambiguous,
  insufficientEvidence,
  invalidInput,
  conflicting;

  String get wireName => switch (this) {
    VisionFamilyResolutionState.insufficientEvidence => 'insufficient_evidence',
    VisionFamilyResolutionState.invalidInput => 'invalid_input',
    _ => name,
  };
}

class VisionFamilyIdentityInput {
  const VisionFamilyIdentityInput({
    required this.canonicalType,
    required this.confidence,
  });

  final String canonicalType;
  final double confidence;

  Map<String, Object?> toMap() => {
    'canonicalType': canonicalType,
    'confidence': confidence,
  };
}

class VisionFamilyCandidate {
  const VisionFamilyCandidate({
    required this.family,
    required this.canonicalCandidates,
    required this.confidence,
    required this.evidence,
    required this.confidenceComponents,
  });

  final VisionIdentityFamily family;
  final List<String> canonicalCandidates;
  final double confidence;
  final List<String> evidence;
  final Map<String, double> confidenceComponents;

  Map<String, Object?> toMap() => {
    'family': family.wireName,
    'canonicalCandidates': canonicalCandidates,
    'confidence': confidence,
    'evidence': evidence,
    'confidenceComponents': confidenceComponents,
  };
}

class VisionFamilyIdentityReport {
  const VisionFamilyIdentityReport({
    required this.state,
    required this.resolvedFamily,
    required this.confidence,
    required this.candidates,
    required this.subtypeCandidates,
    required this.subtypeResolved,
    required this.reasonCodes,
  });

  final VisionFamilyResolutionState state;
  final VisionIdentityFamily? resolvedFamily;
  final double confidence;
  final List<VisionFamilyCandidate> candidates;
  final List<String> subtypeCandidates;
  final bool subtypeResolved;
  final List<String> reasonCodes;

  Map<String, Object?> toMap() => {
    'state': state.wireName,
    'resolvedFamily': resolvedFamily?.wireName,
    'confidence': confidence,
    'candidates': candidates.map((item) => item.toMap()).toList(),
    'subtypeCandidates': subtypeCandidates,
    'subtypeResolved': subtypeResolved,
    'reasonCodes': reasonCodes,
  };
}

abstract final class VisionCanonicalFamilyRegistry {
  static const Map<String, VisionIdentityFamily> canonicalToFamily = {
    't_shirt': VisionIdentityFamily.top,
    'v_neck_t_shirt': VisionIdentityFamily.top,
    'tank_top': VisionIdentityFamily.top,
    'hoodie': VisionIdentityFamily.knitwear,
    'zip_hoodie': VisionIdentityFamily.knitwear,
    'sweatshirt': VisionIdentityFamily.knitwear,
    'crewneck_sweatshirt': VisionIdentityFamily.knitwear,
    'sweater': VisionIdentityFamily.knitwear,
    'knit_sweater': VisionIdentityFamily.knitwear,
    'jeans': VisionIdentityFamily.trousers,
    'skinny_jeans': VisionIdentityFamily.trousers,
    'slim_jeans': VisionIdentityFamily.trousers,
    'straight_jeans': VisionIdentityFamily.trousers,
    'chinos': VisionIdentityFamily.trousers,
    'cargo_pants': VisionIdentityFamily.trousers,
    'corduroy_pants': VisionIdentityFamily.trousers,
    'suit_trousers': VisionIdentityFamily.trousers,
    'hiking_pants': VisionIdentityFamily.trousers,
    'linen_pants': VisionIdentityFamily.trousers,
    'wide_leg_pants': VisionIdentityFamily.trousers,
    'shorts': VisionIdentityFamily.shorts,
    'cargo_shorts': VisionIdentityFamily.shorts,
    'light_jacket': VisionIdentityFamily.jacketOuterwear,
    'winter_jacket': VisionIdentityFamily.jacketOuterwear,
    'puffer_jacket': VisionIdentityFamily.jacketOuterwear,
    'softshell': VisionIdentityFamily.jacketOuterwear,
    'track_jacket': VisionIdentityFamily.jacketOuterwear,
    'hiking_jacket': VisionIdentityFamily.jacketOuterwear,
    'bomber_jacket': VisionIdentityFamily.jacketOuterwear,
    'rain_jacket': VisionIdentityFamily.jacketOuterwear,
    'windbreaker': VisionIdentityFamily.jacketOuterwear,
    'denim_jacket': VisionIdentityFamily.jacketOuterwear,
    'leather_jacket': VisionIdentityFamily.jacketOuterwear,
    'sneakers': VisionIdentityFamily.sneakers,
    'running_shoes': VisionIdentityFamily.sneakers,
    'basketball_shoes': VisionIdentityFamily.sneakers,
    'canvas_shoes': VisionIdentityFamily.sneakers,
    'boots': VisionIdentityFamily.boots,
    'chelsea_boots': VisionIdentityFamily.boots,
    'hiking_shoes': VisionIdentityFamily.boots,
    'winter_boots': VisionIdentityFamily.boots,
  };
}

final class VisionFamilyIdentityResolver {
  const VisionFamilyIdentityResolver();

  VisionFamilyIdentityReport resolve({
    required Iterable<VisionFamilyIdentityInput> identityCandidates,
    required ClothingObservationBundle observations,
    required String? resolvedCanonicalSubtype,
    VisionInputAssessment inputAssessment =
        VisionInputAssessment.validSingleItem,
    VisionSubjectAssessment? subjectAssessment,
    bool hasWholeItemSilhouette = true,
  }) {
    if (!inputAssessment.isValid ||
        (subjectAssessment != null && !subjectAssessment.permitsFamily) ||
        !hasWholeItemSilhouette) {
      return VisionFamilyIdentityReport(
        state: VisionFamilyResolutionState.invalidInput,
        resolvedFamily: null,
        confidence: 0,
        candidates: const [],
        subtypeCandidates: _subtypes(identityCandidates),
        subtypeResolved: false,
        reasonCodes: [
          if (!inputAssessment.isValid) 'input_assessment_rejects_family',
          if (subjectAssessment != null && !subjectAssessment.permitsFamily)
            'subject_or_framing_rejects_family',
          if (!hasWholeItemSilhouette)
            'whole_item_silhouette_required_for_family',
        ],
      );
    }
    final candidates = identityCandidates.toList();
    final grouped = <VisionIdentityFamily, List<VisionFamilyIdentityInput>>{};
    for (final candidate in candidates) {
      final family = VisionCanonicalFamilyRegistry
          .canonicalToFamily[candidate.canonicalType];
      if (family != null) {
        grouped.putIfAbsent(family, () => []).add(candidate);
      }
    }
    if (grouped.isEmpty) {
      return VisionFamilyIdentityReport(
        state: VisionFamilyResolutionState.insufficientEvidence,
        resolvedFamily: null,
        confidence: 0,
        candidates: const [],
        subtypeCandidates: _subtypes(candidates),
        subtypeResolved: resolvedCanonicalSubtype != null,
        reasonCodes: const ['no_mapped_family_candidate'],
      );
    }

    final qualityConfidence = _qualityConfidence(observations.quality);
    final familyCandidates =
        grouped.entries.map((entry) {
          final generalEvidence = _familyEvidence(entry.key, observations);
          final candidateAgreement = entry.value.fold<double>(
            0,
            (sum, item) => sum + item.confidence,
          );
          final candidateConfidence = candidateAgreement > 1
              ? 1.0
              : candidateAgreement;
          final visibilityConfidence = generalEvidence.directConfidence == 0
              ? 0.0
              : generalEvidence.directConfidence;
          final confidence = generalEvidence.directConfidence == 0
              ? 0.0
              : (candidateConfidence * 0.30 +
                        generalEvidence.directConfidence * 0.35 +
                        generalEvidence.supportingConfidence * 0.10 +
                        qualityConfidence * 0.15 +
                        visibilityConfidence * 0.10)
                    .toDouble();
          return VisionFamilyCandidate(
            family: entry.key,
            canonicalCandidates: _subtypes(entry.value),
            confidence: confidence,
            evidence: generalEvidence.evidence,
            confidenceComponents: {
              'candidateAgreement': candidateConfidence,
              'directFamilyEvidence': generalEvidence.directConfidence,
              'supportingFamilyEvidence': generalEvidence.supportingConfidence,
              'imageQuality': qualityConfidence,
              'visibilityTrust': visibilityConfidence,
            },
          );
        }).toList()..sort((left, right) {
          final confidence = right.confidence.compareTo(left.confidence);
          if (confidence != 0) return confidence;
          return left.family.wireName.compareTo(right.family.wireName);
        });

    final top = familyCandidates.first;
    final ambiguous =
        familyCandidates.length > 1 &&
        top.confidence - familyCandidates[1].confidence < 0.20;
    final supported = !ambiguous && top.confidence >= 0.62;
    final confirmed =
        supported &&
        top.confidence >= 0.82 &&
        !(subjectAssessment?.capsFamilyAtSupported ?? false);
    return VisionFamilyIdentityReport(
      state: ambiguous
          ? VisionFamilyResolutionState.ambiguous
          : confirmed
          ? VisionFamilyResolutionState.confirmed
          : supported
          ? VisionFamilyResolutionState.supported
          : VisionFamilyResolutionState.insufficientEvidence,
      resolvedFamily: supported ? top.family : null,
      confidence: supported ? top.confidence : 0,
      candidates: List.unmodifiable(familyCandidates),
      subtypeCandidates: _subtypes(candidates),
      subtypeResolved: resolvedCanonicalSubtype != null,
      reasonCodes: [
        if (ambiguous) 'competing_families',
        if (!ambiguous && !supported) 'insufficient_family_evidence',
        if (supported) 'taxonomy_family_agrees_with_visual_family_evidence',
        if (supported && resolvedCanonicalSubtype == null)
          'family_resolved_subtype_unresolved',
      ],
    );
  }

  static ({
    double directConfidence,
    double supportingConfidence,
    List<String> evidence,
  })
  _familyEvidence(
    VisionIdentityFamily family,
    ClothingObservationBundle observations,
  ) {
    if (family == VisionIdentityFamily.sneakers ||
        family == VisionIdentityFamily.boots) {
      final construction = observations.footwearConstruction;
      final height = observations.footwearUpperHeight;
      final fastening = observations.footwearFastening;
      final surface = observations.surfaceAppearance;
      final evidence = <String>[
        if (_familyVisible(construction)) 'tier1:footwearConstruction',
        if (_familyVisible(height)) 'tier1:footwearUpperHeight',
        if (_familyVisible(fastening)) 'tier2:footwearFastening',
        if (_familyVisible(surface)) 'tier2:surfaceAppearance',
      ];
      final direct = [
        if (_familyVisible(construction)) _scopeAdjusted(construction!),
        if (_familyVisible(height)) _scopeAdjusted(height!),
      ];
      final supporting = [
        if (_familyVisible(fastening)) _scopeAdjusted(fastening!),
        if (_familyVisible(surface)) _scopeAdjusted(surface!),
      ];
      return (
        directConfidence: direct.isEmpty
            ? 0
            : (direct.reduce((left, right) => left > right ? left : right) +
                      (direct.length > 1 ? 0.05 : 0))
                  .clamp(0.0, 1.0),
        supportingConfidence: supporting.isEmpty
            ? 0
            : supporting.reduce((left, right) => left > right ? left : right),
        evidence: evidence,
      );
    }
    final coverage = observations.coverage;
    final bulk = observations.visibleBulk;
    final neckline = observations.necklineShape;
    final closure = observations.frontClosure;
    final direct = _familyVisible(coverage) ? _scopeAdjusted(coverage!) : 0.0;
    final supporting = [
      if (_familyVisible(bulk)) _scopeAdjusted(bulk!),
      if (_familyVisible(neckline)) _scopeAdjusted(neckline!),
      if (_familyVisible(closure) && closure!.value != FrontClosure.none)
        _scopeAdjusted(closure),
    ];
    return (
      directConfidence: direct,
      supportingConfidence: supporting.isEmpty
          ? 0
          : supporting.reduce((left, right) => left > right ? left : right),
      evidence: [
        if (_familyVisible(coverage)) 'tier1:coverage',
        if (_familyVisible(bulk)) 'tier2:visibleBulk',
        if (_familyVisible(neckline)) 'tier2:necklineShape',
        if (_familyVisible(closure) && closure!.value != FrontClosure.none)
          'tier2:frontClosure',
      ],
    );
  }

  static bool _familyVisible<T>(ObservationValue<T>? value) =>
      value?.isObserved ?? false;

  static double _scopeAdjusted<T>(ObservationValue<T> value) {
    final multiplier = switch (value.visibilityScope) {
      ObservationVisibilityScope.complete => 1.0,
      ObservationVisibilityScope.sufficient => 0.9,
      ObservationVisibilityScope.partial => 0.7,
      ObservationVisibilityScope.notVisible => 0.0,
      null => 0.6,
    };
    return value.confidence * multiplier;
  }

  static double _qualityConfidence(ObservationImageQuality quality) {
    var result = switch (quality.clarity) {
      ImageQualityLevel.high => 0.95,
      ImageQualityLevel.medium => 0.7,
      ImageQualityLevel.low => 0.2,
      null => 0.5,
    };
    if (quality.itemFullyVisible == false && result > 0.7) result = 0.7;
    if (quality.occlusion == ImageOcclusion.partial && result > 0.65) {
      result = 0.65;
    }
    if (quality.occlusion == ImageOcclusion.substantial && result > 0.25) {
      result = 0.25;
    }
    if (quality.backgroundInterference == ImageQualityLevel.high &&
        result > 0.35) {
      result = 0.35;
    }
    return result;
  }

  static List<String> _subtypes(
    Iterable<VisionFamilyIdentityInput> candidates,
  ) => candidates.map((item) => item.canonicalType).toSet().toList()..sort();
}
