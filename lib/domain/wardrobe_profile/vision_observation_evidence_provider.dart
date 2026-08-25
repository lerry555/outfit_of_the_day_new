import 'wardrobe_profile_contract.dart';

/// Converts typed image observations into the existing M11 evidence language.
///
/// It deliberately performs no identity classification, capability inference,
/// conflict resolution, knowledge-base lookup, or persistence.
final class VisionObservationEvidenceProvider {
  const VisionObservationEvidenceProvider();

  List<ProfileEvidence> provide(ClothingObservationBundle bundle) {
    final evidence = <ProfileEvidence>[];

    void add<T>(
      String property,
      ObservationValue<T>? observation,
      Object? Function(T value) encodeValue,
    ) {
      if (observation == null) return;
      final valueState = switch (observation.state) {
        ObservationState.observed => EvidenceValueState.known,
        ObservationState.unknown => EvidenceValueState.unknown,
        ObservationState.notVisible => EvidenceValueState.notVisible,
        ObservationState.notApplicable => EvidenceValueState.notApplicable,
      };
      evidence.add(
        ProfileEvidence(
          id: _evidenceId(bundle.analysisId, bundle.sourceReference, property),
          property: property,
          value: observation.isObserved
              ? encodeValue(observation.value as T)
              : null,
          valueState: valueState,
          source: EvidenceSource.visualObservation,
          nature: EvidenceNature.observed,
          confidence: observation.confidence,
          method: 'vision_observation',
          createdAt: bundle.observedAt,
          modelVersion: bundle.modelVersion,
          sourceReference: bundle.sourceReference,
        ),
      );
    }

    add(
      WardrobeProfileProperty.coverage,
      bundle.coverage,
      (value) => value.wireName,
    );
    add(WardrobeProfileProperty.hasHood, bundle.hasHood, (value) => value);
    add(
      WardrobeProfileProperty.frontClosure,
      bundle.frontClosure,
      (value) => value.wireName,
    );
    add(
      WardrobeProfileProperty.visibleBulk,
      bundle.visibleBulk,
      (value) => value.wireName,
    );
    add(
      WardrobeProfileProperty.surfaceAppearance,
      bundle.surfaceAppearance,
      (value) => value.wireName,
    );
    add(
      WardrobeProfileProperty.necklineShape,
      bundle.necklineShape,
      (value) => value.wireName,
    );
    add(
      WardrobeProfileProperty.visiblePocketStructure,
      bundle.visiblePocketStructure,
      (value) => value.wireName,
    );
    add(
      WardrobeProfileProperty.visibleStretchCue,
      bundle.visibleStretchCue,
      (value) => value,
    );
    add(
      WardrobeProfileProperty.sportyCues,
      bundle.sportyCues,
      (value) => value.wireName,
    );
    add(
      WardrobeProfileProperty.formalCues,
      bundle.formalCues,
      (value) => value.wireName,
    );
    add(
      WardrobeProfileProperty.footwearConstruction,
      bundle.footwearConstruction,
      (value) => value.wireName,
    );
    add(
      WardrobeProfileProperty.footwearFastening,
      bundle.footwearFastening,
      (value) => value.wireName,
    );
    add(
      WardrobeProfileProperty.soleProfile,
      bundle.soleProfile,
      (value) => value.wireName,
    );
    add(
      WardrobeProfileProperty.visibleTread,
      bundle.visibleTread,
      (value) => value.wireName,
    );
    add(
      WardrobeProfileProperty.footwearUpperHeight,
      bundle.footwearUpperHeight,
      (value) => value.wireName,
    );

    return List<ProfileEvidence>.unmodifiable(evidence);
  }

  static String _evidenceId(
    String analysisId,
    String sourceReference,
    String property,
  ) =>
      'observation:${Uri.encodeComponent(analysisId)}:'
      '${Uri.encodeComponent(sourceReference)}:$property';
}
