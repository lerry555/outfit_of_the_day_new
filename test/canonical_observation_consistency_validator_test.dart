import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/canonical_observation_consistency_validator.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_observation_evidence_provider.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

void main() {
  const validator = CanonicalObservationConsistencyValidator();
  const observationProvider = VisionObservationEvidenceProvider();
  final now = DateTime.utc(2026, 7, 27, 16);

  ProfileEvidence identity(
    String canonical, {
    String? id,
    EvidenceSource source = EvidenceSource.aiInference,
    double confidence = 0.9,
    bool verified = false,
  }) => ProfileEvidence(
    id: id ?? 'identity-$canonical',
    property: WardrobeProfileProperty.canonicalType,
    value: canonical,
    source: source,
    nature: source == EvidenceSource.aiInference
        ? EvidenceNature.inferred
        : EvidenceNature.observed,
    confidence: confidence,
    verified: verified,
    method: 'test_identity',
    createdAt: now,
  );

  ProfileEvidence productObservation(
    String id,
    String property,
    Object value,
  ) => ProfileEvidence(
    id: id,
    property: property,
    value: value,
    source: EvidenceSource.verifiedProductMetadata,
    nature: EvidenceNature.observed,
    confidence: 0.98,
    verified: true,
    method: 'verified_product_spec',
    createdAt: now,
    sourceReference: 'product:test',
  );

  List<ProfileEvidence> observe({
    String analysisId = 'analysis',
    String sourceReference = 'image_front',
    ObservationValue<GarmentCoverage>? coverage,
    ObservationValue<bool>? hasHood,
    ObservationValue<FrontClosure>? frontClosure,
    ObservationValue<VisualAmount>? visibleBulk,
    ObservationValue<SurfaceAppearance>? surfaceAppearance,
    ObservationValue<NecklineShape>? necklineShape,
    ObservationValue<VisiblePocketStructure>? visiblePocketStructure,
    ObservationValue<VisualAmount>? sportyCues,
    ObservationValue<VisualAmount>? formalCues,
    ObservationValue<FootwearConstruction>? footwearConstruction,
    ObservationValue<FootwearFastening>? footwearFastening,
    ObservationValue<VisibleTread>? visibleTread,
    ObservationValue<FootwearUpperHeight>? footwearUpperHeight,
  }) => observationProvider.provide(
    ClothingObservationBundle(
      analysisId: analysisId,
      modelVersion: 'observation-v1',
      sourceReference: sourceReference,
      observedAt: now,
      coverage: coverage,
      hasHood: hasHood,
      frontClosure: frontClosure,
      visibleBulk: visibleBulk,
      surfaceAppearance: surfaceAppearance,
      necklineShape: necklineShape,
      visiblePocketStructure: visiblePocketStructure,
      sportyCues: sportyCues,
      formalCues: formalCues,
      footwearConstruction: footwearConstruction,
      footwearFastening: footwearFastening,
      visibleTread: visibleTread,
      footwearUpperHeight: footwearUpperHeight,
    ),
  );

  CanonicalCompatibilityResult validateOne(
    String canonical,
    List<ProfileEvidence> observations, {
    EvidenceSource source = EvidenceSource.aiInference,
  }) => validator
      .validate(
        identityEvidence: [identity(canonical, source: source)],
        observationEvidence: observations,
      )
      .results
      .single;

  test('exact compatible signature is reported without changing identity', () {
    final candidate = identity('t_shirt');
    final result = validator.validate(
      identityEvidence: [candidate],
      observationEvidence: observe(
        visibleBulk: const ObservationValue.observed(
          value: VisualAmount.low,
          confidence: 0.9,
        ),
        hasHood: const ObservationValue.observed(
          value: false,
          confidence: 0.95,
        ),
        frontClosure: const ObservationValue.observed(
          value: FrontClosure.none,
          confidence: 0.95,
        ),
      ),
    );

    expect(
      result.results.single.compatibilityLevel,
      CanonicalCompatibilityLevel.compatible,
    );
    expect(candidate.value, 't_shirt');
    expect(result.results.single.candidateCanonicalType, 't_shirt');
  });

  test('strong support is distinguished from basic compatibility', () {
    final result = validateOne(
      'puffer_jacket',
      observe(
        visibleBulk: const ObservationValue.observed(
          value: VisualAmount.high,
          confidence: 0.95,
        ),
        surfaceAppearance: const ObservationValue.observed(
          value: SurfaceAppearance.quilted,
          confidence: 0.95,
        ),
        coverage: const ObservationValue.observed(
          value: GarmentCoverage.full,
          confidence: 0.9,
        ),
      ),
    );

    expect(result.compatibilityLevel, CanonicalCompatibilityLevel.strong);
    expect(result.score, 5);
  });

  test('missing and notVisible evidence produce uncertainty, not conflict', () {
    final result = validateOne(
      'sweater',
      observe(
        hasHood: const ObservationValue<bool>.notVisible(),
        surfaceAppearance:
            const ObservationValue<SurfaceAppearance>.notVisible(),
        frontClosure: const ObservationValue<FrontClosure>.unknown(),
      ),
    );

    expect(result.compatibilityLevel, CanonicalCompatibilityLevel.uncertain);
    expect(result.conflictingEvidence, isEmpty);
    expect(
      result.missingExpectedEvidence,
      contains(WardrobeProfileProperty.hasHood),
    );
    expect(result.neededEvidence, contains('show_hood_area'));
    expect(result.neededEvidence, contains('close_surface_image'));
  });

  test('observed false differs from notVisible', () {
    final visibleFalse = validateOne(
      'sweater',
      observe(
        hasHood: const ObservationValue.observed(
          value: false,
          confidence: 0.95,
        ),
        surfaceAppearance: const ObservationValue.observed(
          value: SurfaceAppearance.knit,
          confidence: 0.95,
        ),
        frontClosure: const ObservationValue.observed(
          value: FrontClosure.none,
          confidence: 0.95,
        ),
      ),
    );
    final hidden = validateOne(
      'sweater',
      observe(
        analysisId: 'hidden',
        hasHood: const ObservationValue<bool>.notVisible(),
      ),
    );

    expect(visibleFalse.compatibilityLevel, CanonicalCompatibilityLevel.strong);
    expect(hidden.compatibilityLevel, CanonicalCompatibilityLevel.uncertain);
  });

  test('sweater with hood full zip and smooth surface conflicts', () {
    final result = validateOne(
      'sweater',
      observe(
        hasHood: const ObservationValue.observed(value: true, confidence: 0.98),
        frontClosure: const ObservationValue.observed(
          value: FrontClosure.fullZip,
          confidence: 0.95,
        ),
        surfaceAppearance: const ObservationValue.observed(
          value: SurfaceAppearance.smooth,
          confidence: 0.9,
        ),
      ),
    );

    expect(result.compatibilityLevel, CanonicalCompatibilityLevel.conflicting);
    expect(result.score, lessThan(0));
    expect(
      result.conflictingEvidence,
      containsAll([
        WardrobeProfileProperty.hasHood,
        WardrobeProfileProperty.frontClosure,
      ]),
    );
  });

  test('same observations are compatible with hoodie candidate', () {
    final result = validateOne(
      'zip_hoodie',
      observe(
        hasHood: const ObservationValue.observed(value: true, confidence: 0.98),
        frontClosure: const ObservationValue.observed(
          value: FrontClosure.fullZip,
          confidence: 0.95,
        ),
        surfaceAppearance: const ObservationValue.observed(
          value: SurfaceAppearance.smooth,
          confidence: 0.9,
        ),
        sportyCues: const ObservationValue.observed(
          value: VisualAmount.high,
          confidence: 0.85,
        ),
      ),
    );

    expect(result.compatibilityLevel, CanonicalCompatibilityLevel.strong);
    expect(result.candidateCanonicalType, 'zip_hoodie');
  });

  test(
    'winter jacket conflicts with verified low-bulk lightweight metadata',
    () {
      final observations = [
        ...observe(
          surfaceAppearance: const ObservationValue.observed(
            value: SurfaceAppearance.smooth,
            confidence: 0.9,
          ),
        ),
        productObservation(
          'verified-unlined-lightweight',
          WardrobeProfileProperty.visibleBulk,
          'low',
        ),
      ];
      final result = validateOne('winter_jacket', observations);

      expect(
        result.compatibilityLevel,
        CanonicalCompatibilityLevel.conflicting,
      );
      expect(
        result.conflictingEvidence,
        contains(WardrobeProfileProperty.visibleBulk),
      );
    },
  );

  test('puffer high bulk and quilted surface is strongly compatible', () {
    final result = validateOne(
      'winter_jacket',
      observe(
        visibleBulk: const ObservationValue.observed(
          value: VisualAmount.high,
          confidence: 0.95,
        ),
        surfaceAppearance: const ObservationValue.observed(
          value: SurfaceAppearance.quilted,
          confidence: 0.95,
        ),
        coverage: const ObservationValue.observed(
          value: GarmentCoverage.full,
          confidence: 0.9,
        ),
      ),
    );

    expect(result.compatibilityLevel, CanonicalCompatibilityLevel.strong);
  });

  test(
    'fashion ankle boot signature is compatible without traction claims',
    () {
      final result = validateOne(
        'chelsea_boots',
        observe(
          footwearUpperHeight: const ObservationValue.observed(
            value: FootwearUpperHeight.ankle,
            confidence: 0.95,
          ),
          visibleTread: const ObservationValue.observed(
            value: VisibleTread.low,
            confidence: 0.9,
          ),
          formalCues: const ObservationValue.observed(
            value: VisualAmount.high,
            confidence: 0.85,
          ),
        ),
      );

      expect(result.compatibilityLevel, CanonicalCompatibilityLevel.compatible);
      expect(result.neededEvidence, contains('clear_side_footwear_image'));
    },
  );

  test('trail footwear signature uses tread and sporty observations', () {
    final result = validateOne(
      'hiking_shoes',
      observe(
        footwearConstruction: const ObservationValue.observed(
          value: FootwearConstruction.closed,
          confidence: 0.98,
        ),
        visibleTread: const ObservationValue.observed(
          value: VisibleTread.pronounced,
          confidence: 0.95,
        ),
        sportyCues: const ObservationValue.observed(
          value: VisualAmount.high,
          confidence: 0.9,
        ),
      ),
    );

    expect(result.compatibilityLevel, CanonicalCompatibilityLevel.strong);
  });

  test('two identity candidates receive separate compatibility results', () {
    final sweater = identity('sweater', id: 'vision-sweater');
    final hoodie = identity(
      'zip_hoodie',
      id: 'product-hoodie',
      source: EvidenceSource.verifiedProductMetadata,
      verified: true,
    );
    final input = observe(
      hasHood: const ObservationValue.observed(value: true, confidence: 0.98),
      frontClosure: const ObservationValue.observed(
        value: FrontClosure.fullZip,
        confidence: 0.95,
      ),
      sportyCues: const ObservationValue.observed(
        value: VisualAmount.high,
        confidence: 0.9,
      ),
    );
    final report = validator.validate(
      identityEvidence: [sweater, hoodie],
      observationEvidence: input,
    );

    final byType = {
      for (final result in report.results)
        result.candidateCanonicalType: result,
    };
    expect(
      byType['sweater']?.compatibilityLevel,
      CanonicalCompatibilityLevel.conflicting,
    );
    expect(
      byType['zip_hoodie']?.compatibilityLevel,
      CanonicalCompatibilityLevel.strong,
    );
    expect(report.candidateGap, CandidateGap.large);
    expect(report.identityConflict, isTrue);
  });

  test(
    'validator reports candidates but never selects or rewrites canonical',
    () {
      final first = identity('sweater');
      final second = identity('zip_hoodie');
      final before = [first.toMap(), second.toMap()];
      final report = validator.validate(
        identityEvidence: [second, first],
        observationEvidence: observe(
          hasHood: const ObservationValue.observed(
            value: true,
            confidence: 0.9,
          ),
        ),
      );

      expect(report.toMap().containsKey('selectedCanonicalType'), isFalse);
      expect(report.competingCanonicalTypes, ['sweater', 'zip_hoodie']);
      expect([first.toMap(), second.toMap()], before);
    },
  );

  test('validator ignores and never mutates capability evidence', () {
    final capability = ProfileEvidence(
      id: 'warmth',
      property: WardrobeProfileProperty.warmth,
      value: 7,
      source: EvidenceSource.aiInference,
      nature: EvidenceNature.inferred,
      confidence: 0.6,
      method: 'capability_inference:test',
      createdAt: now,
    );
    final before = capability.toMap();

    validator.validate(
      identityEvidence: [identity('winter_jacket')],
      observationEvidence: [
        ...observe(
          visibleBulk: const ObservationValue.observed(
            value: VisualAmount.low,
            confidence: 0.9,
          ),
        ),
        capability,
      ],
    );

    expect(capability.toMap(), before);
  });

  test(
    'verified product identity is validated rather than blindly accepted',
    () {
      final result = validateOne(
        'winter_jacket',
        observe(
          visibleBulk: const ObservationValue.observed(
            value: VisualAmount.low,
            confidence: 0.95,
          ),
        ),
        source: EvidenceSource.verifiedProductMetadata,
      );

      expect(result.identitySource, EvidenceSource.verifiedProductMetadata);
      expect(
        result.compatibilityLevel,
        CanonicalCompatibilityLevel.conflicting,
      );
    },
  );

  test('multi-photo agreement uses visible evidence over notVisible', () {
    final front = observe(
      analysisId: 'front',
      sourceReference: 'image_front',
      hasHood: const ObservationValue<bool>.notVisible(),
    );
    final back = observe(
      analysisId: 'back',
      sourceReference: 'image_back',
      hasHood: const ObservationValue.observed(value: true, confidence: 0.95),
    );
    final result = validateOne('hoodie', [...front, ...back]);

    expect(
      result.supportingEvidence,
      contains(WardrobeProfileProperty.hasHood),
    );
    expect(
      result.conflictingEvidence,
      isNot(contains(WardrobeProfileProperty.hasHood)),
    );
  });

  test('multi-photo disagreement is uncertain rather than random', () {
    final knit = observe(
      analysisId: 'knit',
      sourceReference: 'image_a',
      surfaceAppearance: const ObservationValue.observed(
        value: SurfaceAppearance.knit,
        confidence: 0.9,
      ),
    );
    final smooth = observe(
      analysisId: 'smooth',
      sourceReference: 'image_b',
      surfaceAppearance: const ObservationValue.observed(
        value: SurfaceAppearance.smooth,
        confidence: 0.9,
      ),
    );
    final result = validateOne('sweater', [...knit, ...smooth]);

    expect(result.compatibilityLevel, CanonicalCompatibilityLevel.uncertain);
    expect(
      result.reasonCodes,
      contains('observation_conflict:visual.observations.surfaceAppearance'),
    );
  });

  test('output is deterministic and inputs remain immutable', () {
    final candidate = identity('hiking_shoes');
    final input = observe(
      visibleTread: const ObservationValue.observed(
        value: VisibleTread.pronounced,
        confidence: 0.9,
      ),
      sportyCues: const ObservationValue.observed(
        value: VisualAmount.high,
        confidence: 0.9,
      ),
    );
    final beforeIdentity = candidate.toMap();
    final beforeObservations = input.map((item) => item.toMap()).toList();

    final first = validator.validate(
      identityEvidence: [candidate],
      observationEvidence: input,
    );
    final second = validator.validate(
      identityEvidence: [candidate],
      observationEvidence: input.reversed,
    );

    expect(first.toMap(), second.toMap());
    expect(candidate.toMap(), beforeIdentity);
    expect(input.map((item) => item.toMap()).toList(), beforeObservations);
  });

  test('uncertainty report exposes machine-readable needed evidence', () {
    final report = validator.validate(
      identityEvidence: [identity('sweater')],
      observationEvidence: const [],
    );

    expect(
      report.results.single.compatibilityLevel,
      CanonicalCompatibilityLevel.uncertain,
    );
    expect(report.neededEvidence, contains('show_hood_area'));
    expect(report.neededEvidence, contains('show_front_closure'));
    expect(report.neededEvidence, contains('close_surface_image'));
  });

  test('visible v-neck strongly supports v-neck subtype', () {
    final result = validateOne(
      'v_neck_t_shirt',
      observe(
        necklineShape: const ObservationValue.observed(
          value: NecklineShape.vNeck,
          confidence: 0.9,
        ),
        visibleBulk: const ObservationValue.observed(
          value: VisualAmount.low,
          confidence: 0.85,
        ),
        frontClosure: const ObservationValue.observed(
          value: FrontClosure.none,
          confidence: 0.9,
        ),
      ),
    );

    expect(result.compatibilityLevel, CanonicalCompatibilityLevel.strong);
    expect(
      result.supportingEvidence,
      contains(WardrobeProfileProperty.necklineShape),
    );
  });

  test('hidden neckline cannot visually confirm v-neck subtype', () {
    final result = validateOne(
      'v_neck_t_shirt',
      observe(
        necklineShape: const ObservationValue<NecklineShape>.notVisible(),
      ),
    );

    expect(result.compatibilityLevel, CanonicalCompatibilityLevel.uncertain);
    expect(result.neededEvidence, contains('clear_neckline_image'));
  });

  test('high bulk alone does not strongly support puffer subtype', () {
    final result = validateOne(
      'puffer_jacket',
      observe(
        visibleBulk: const ObservationValue.observed(
          value: VisualAmount.high,
          confidence: 0.95,
        ),
        surfaceAppearance: const ObservationValue<SurfaceAppearance>.unknown(),
      ),
    );

    expect(result.compatibilityLevel, CanonicalCompatibilityLevel.compatible);
    expect(
      result.missingExpectedEvidence,
      contains(WardrobeProfileProperty.surfaceAppearance),
    );
  });

  test('cargo pockets and Chelsea panels are reusable subtype evidence', () {
    final cargo = validateOne(
      'cargo_pants',
      observe(
        visiblePocketStructure: const ObservationValue.observed(
          value: VisiblePocketStructure.cargo,
          confidence: 0.9,
        ),
      ),
    );
    final chelsea = validateOne(
      'chelsea_boots',
      observe(
        footwearUpperHeight: const ObservationValue.observed(
          value: FootwearUpperHeight.ankle,
          confidence: 0.9,
        ),
        footwearFastening: const ObservationValue.observed(
          value: FootwearFastening.elasticSidePanels,
          confidence: 0.9,
        ),
      ),
    );

    expect(cargo.compatibilityLevel, CanonicalCompatibilityLevel.compatible);
    expect(chelsea.compatibilityLevel, CanonicalCompatibilityLevel.strong);
  });
}
