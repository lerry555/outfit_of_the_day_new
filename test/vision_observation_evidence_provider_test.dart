import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_observation_evidence_provider.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_resolver.dart';

void main() {
  const provider = VisionObservationEvidenceProvider();
  const resolver = WardrobeProfileResolver();
  final observedAt = DateTime.utc(2026, 7, 27, 12);

  ClothingObservationBundle bundle({
    String analysisId = 'analysis-1',
    String sourceReference = 'image_front',
    ObservationValue<GarmentCoverage>? coverage,
    ObservationValue<bool>? hasHood,
    ObservationValue<FrontClosure>? frontClosure,
    ObservationValue<VisualAmount>? visibleBulk,
    ObservationValue<SurfaceAppearance>? surfaceAppearance,
    ObservationValue<NecklineShape>? necklineShape,
    ObservationValue<VisiblePocketStructure>? visiblePocketStructure,
    ObservationValue<bool>? visibleStretchCue,
    ObservationValue<VisualAmount>? sportyCues,
    ObservationValue<VisualAmount>? formalCues,
    ObservationValue<FootwearConstruction>? footwearConstruction,
    ObservationValue<FootwearFastening>? footwearFastening,
    ObservationValue<SoleProfile>? soleProfile,
    ObservationValue<VisibleTread>? visibleTread,
    ObservationValue<FootwearUpperHeight>? footwearUpperHeight,
  }) => ClothingObservationBundle(
    analysisId: analysisId,
    modelVersion: 'vision-observation-v1',
    sourceReference: sourceReference,
    observedAt: observedAt,
    quality: const ObservationImageQuality(
      itemFullyVisible: true,
      occlusion: ImageOcclusion.none,
      backgroundInterference: ImageQualityLevel.low,
      clarity: ImageQualityLevel.high,
    ),
    coverage: coverage,
    hasHood: hasHood,
    frontClosure: frontClosure,
    visibleBulk: visibleBulk,
    surfaceAppearance: surfaceAppearance,
    necklineShape: necklineShape,
    visiblePocketStructure: visiblePocketStructure,
    visibleStretchCue: visibleStretchCue,
    sportyCues: sportyCues,
    formalCues: formalCues,
    footwearConstruction: footwearConstruction,
    footwearFastening: footwearFastening,
    soleProfile: soleProfile,
    visibleTread: visibleTread,
    footwearUpperHeight: footwearUpperHeight,
  );

  test('observed true and false remain distinct facts', () {
    final withHood = provider.provide(
      bundle(
        hasHood: const ObservationValue<bool>.observed(
          value: true,
          confidence: 0.9,
        ),
      ),
    );
    final withoutHood = provider.provide(
      bundle(
        analysisId: 'analysis-2',
        hasHood: const ObservationValue<bool>.observed(
          value: false,
          confidence: 0.95,
        ),
      ),
    );

    expect(withHood.single.value, isTrue);
    expect(withoutHood.single.value, isFalse);
    expect(withHood.single.valueState, EvidenceValueState.known);
  });

  test('unknown, notVisible and notApplicable remain distinct', () {
    final evidence = provider.provide(
      bundle(
        hasHood: const ObservationValue<bool>.unknown(),
        visibleStretchCue: const ObservationValue<bool>.notVisible(),
        footwearConstruction:
            const ObservationValue<FootwearConstruction>.notApplicable(),
      ),
    );

    expect(evidence.map((item) => item.valueState), [
      EvidenceValueState.unknown,
      EvidenceValueState.notVisible,
      EvidenceValueState.notApplicable,
    ]);
    expect(evidence.every((item) => item.value == null), isTrue);
  });

  test('notVisible does not resolve to a negative fact', () {
    final evidence = provider.provide(
      bundle(hasHood: const ObservationValue<bool>.notVisible()),
    );
    final profile = resolver.resolve(itemId: 'hoodie', evidence: evidence);

    expect(profile.visual.hasHood.isUnknown, isTrue);
    expect(profile.visual.hasHood.value, isNull);
    expect(evidence.single.valueState, EvidenceValueState.notVisible);
  });

  test('notApplicable resolves through the existing field state', () {
    final evidence = provider.provide(
      bundle(
        visibleTread: const ObservationValue<VisibleTread>.notApplicable(),
      ),
    );
    final profile = resolver.resolve(itemId: 'shirt', evidence: evidence);

    expect(profile.visual.visibleTread.isNotApplicable, isTrue);
  });

  test('invalid enum and confidence are rejected', () {
    expect(
      () => ObservationValue<VisibleTread>.fromMap(<String, dynamic>{
        'state': 'observed',
        'value': 'extreme',
        'confidence': 0.8,
      }, decodeValue: (value) => VisibleTread.fromWireName(value.toString())),
      throwsArgumentError,
    );
    expect(
      () => ObservationValue<bool>.fromMap(<String, dynamic>{
        'state': 'observed',
        'value': true,
        'confidence': 1.2,
      }, decodeValue: (value) => value as bool),
      throwsFormatException,
    );
  });

  test('raw bundle serialization is deterministic and round-trips', () {
    final input = bundle(
      coverage: const ObservationValue<GarmentCoverage>.observed(
        value: GarmentCoverage.full,
        confidence: 0.9,
      ),
      frontClosure: const ObservationValue<FrontClosure>.observed(
        value: FrontClosure.fullZip,
        confidence: 0.85,
      ),
      visibleTread: const ObservationValue<VisibleTread>.notVisible(),
      necklineShape: const ObservationValue<NecklineShape>.observed(
        value: NecklineShape.vNeck,
        confidence: 0.91,
      ),
      visiblePocketStructure:
          const ObservationValue<VisiblePocketStructure>.unknown(),
      footwearFastening:
          const ObservationValue<FootwearFastening>.notApplicable(),
    );

    final first = input.toMap();
    final restored = ClothingObservationBundle.fromMap(
      Map<String, dynamic>.from(first),
    );

    expect(restored.toMap(), first);
    expect(input.toMap(), first);
  });

  test('subtype observations preserve all visibility states', () {
    final evidence = provider.provide(
      bundle(
        necklineShape: const ObservationValue<NecklineShape>.observed(
          value: NecklineShape.collared,
          confidence: 0.88,
        ),
        visiblePocketStructure:
            const ObservationValue<VisiblePocketStructure>.notVisible(),
        footwearFastening:
            const ObservationValue<FootwearFastening>.notApplicable(),
      ),
    );

    expect(evidence.map((item) => item.property), [
      WardrobeProfileProperty.necklineShape,
      WardrobeProfileProperty.visiblePocketStructure,
      WardrobeProfileProperty.footwearFastening,
    ]);
    expect(evidence.map((item) => item.valueState), [
      EvidenceValueState.known,
      EvidenceValueState.notVisible,
      EvidenceValueState.notApplicable,
    ]);
  });

  test('property paths are centralized under visual observations', () {
    expect(WardrobeProfileProperty.hasHood, 'visual.observations.hasHood');
    expect(
      WardrobeProfileProperty.visibleTread,
      'visual.observations.visibleTread',
    );
    expect(
      WardrobeProfileProperty.footwearConstruction,
      'visual.observations.footwearConstruction',
    );
    expect(
      WardrobeProfileProperty.necklineShape,
      'visual.observations.necklineShape',
    );
  });

  test('conversion preserves provenance and source image reference', () {
    final evidence = provider.provide(
      bundle(
        visibleBulk: const ObservationValue<VisualAmount>.observed(
          value: VisualAmount.high,
          confidence: 0.72,
        ),
      ),
    );
    final item = evidence.single;

    expect(item.source, EvidenceSource.visualObservation);
    expect(item.nature, EvidenceNature.observed);
    expect(item.method, 'vision_observation');
    expect(item.modelVersion, 'vision-observation-v1');
    expect(item.sourceReference, 'image_front');
    expect(item.createdAt, observedAt);
    expect(item.confidence, 0.72);
    expect(
      ProfileEvidence.fromMap(Map<String, dynamic>.from(item.toMap())).toMap(),
      item.toMap(),
    );
  });

  test('two photos create independent evidence records', () {
    final front = provider.provide(
      bundle(
        analysisId: 'front-analysis',
        sourceReference: 'image_front',
        hasHood: const ObservationValue<bool>.notVisible(),
      ),
    );
    final back = provider.provide(
      bundle(
        analysisId: 'back-analysis',
        sourceReference: 'image_back',
        hasHood: const ObservationValue<bool>.observed(
          value: true,
          confidence: 0.9,
        ),
      ),
    );

    expect(front.single.id, isNot(back.single.id));
    expect(front.single.sourceReference, 'image_front');
    expect(back.single.sourceReference, 'image_back');
    final profile = resolver.resolve(
      itemId: 'hoodie',
      evidence: [...front, ...back],
    );
    expect(profile.visual.hasHood.value, isTrue);
  });

  test('provider creates no capability, identity or suitability evidence', () {
    final evidence = provider.provide(
      bundle(
        visibleBulk: const ObservationValue<VisualAmount>.observed(
          value: VisualAmount.high,
          confidence: 0.8,
        ),
        sportyCues: const ObservationValue<VisualAmount>.observed(
          value: VisualAmount.high,
          confidence: 0.8,
        ),
        visibleTread: const ObservationValue<VisibleTread>.observed(
          value: VisibleTread.pronounced,
          confidence: 0.9,
        ),
      ),
    );

    expect(
      evidence.every(
        (item) =>
            item.property == WardrobeProfileProperty.coverage ||
            item.property.startsWith('visual.observations.'),
      ),
      isTrue,
    );
    expect(
      evidence.any(
        (item) =>
            item.property == WardrobeProfileProperty.warmth ||
            item.property == WardrobeProfileProperty.formality ||
            item.property == WardrobeProfileProperty.traction,
      ),
      isFalse,
    );
  });

  test('provider does not mutate its input bundle', () {
    final input = bundle(
      hasHood: const ObservationValue<bool>.observed(
        value: true,
        confidence: 0.9,
      ),
      visibleTread: const ObservationValue<VisibleTread>.notVisible(),
    );
    final before = input.toMap();

    provider.provide(input);

    expect(input.toMap(), before);
  });

  group('observation acceptance fixtures', () {
    test('A winter fashion ankle boot contains cues, not capabilities', () {
      final evidence = provider.provide(
        bundle(
          footwearConstruction:
              const ObservationValue<FootwearConstruction>.observed(
                value: FootwearConstruction.closed,
                confidence: 0.98,
              ),
          footwearUpperHeight:
              const ObservationValue<FootwearUpperHeight>.observed(
                value: FootwearUpperHeight.ankle,
                confidence: 0.9,
              ),
          soleProfile: const ObservationValue<SoleProfile>.observed(
            value: SoleProfile.standard,
            confidence: 0.8,
          ),
          visibleTread: const ObservationValue<VisibleTread>.notVisible(),
          visibleBulk: const ObservationValue<VisualAmount>.observed(
            value: VisualAmount.high,
            confidence: 0.75,
          ),
        ),
      );

      expect(
        evidence.map((item) => item.property),
        contains(WardrobeProfileProperty.footwearUpperHeight),
      );
      expect(
        evidence.any((item) => item.property.contains('traction')),
        isFalse,
      );
      expect(
        evidence.any((item) => item.property.contains('walkingComfort')),
        isFalse,
      );
    });

    test('B trail footwear records tread and sporty construction only', () {
      final evidence = provider.provide(
        bundle(
          footwearConstruction:
              const ObservationValue<FootwearConstruction>.observed(
                value: FootwearConstruction.closed,
                confidence: 0.98,
              ),
          footwearUpperHeight:
              const ObservationValue<FootwearUpperHeight>.observed(
                value: FootwearUpperHeight.lowCut,
                confidence: 0.9,
              ),
          visibleTread: const ObservationValue<VisibleTread>.observed(
            value: VisibleTread.pronounced,
            confidence: 0.9,
          ),
          sportyCues: const ObservationValue<VisualAmount>.observed(
            value: VisualAmount.high,
            confidence: 0.85,
          ),
          visibleBulk: const ObservationValue<VisualAmount>.observed(
            value: VisualAmount.low,
            confidence: 0.7,
          ),
        ),
      );

      expect(
        evidence
            .firstWhere(
              (item) => item.property == WardrobeProfileProperty.visibleTread,
            )
            .value,
        'pronounced',
      );
      expect(
        evidence.any(
          (item) => item.property == WardrobeProfileProperty.traction,
        ),
        isFalse,
      );
    });

    test('C elegant trousers separate coverage and formal visual cues', () {
      final evidence = provider.provide(
        bundle(
          coverage: const ObservationValue<GarmentCoverage>.observed(
            value: GarmentCoverage.full,
            confidence: 0.95,
          ),
          formalCues: const ObservationValue<VisualAmount>.observed(
            value: VisualAmount.high,
            confidence: 0.85,
          ),
          visibleStretchCue: const ObservationValue<bool>.notVisible(),
        ),
      );

      expect(
        evidence.any(
          (item) => item.property == WardrobeProfileProperty.formality,
        ),
        isFalse,
      );
      expect(
        evidence.any(
          (item) => item.property == WardrobeProfileProperty.mobility,
        ),
        isFalse,
      );
    });

    test('D functional trousers expose technical cues without mobility', () {
      final evidence = provider.provide(
        bundle(
          coverage: const ObservationValue<GarmentCoverage>.observed(
            value: GarmentCoverage.full,
            confidence: 0.95,
          ),
          sportyCues: const ObservationValue<VisualAmount>.observed(
            value: VisualAmount.high,
            confidence: 0.8,
          ),
          visibleStretchCue: const ObservationValue<bool>.observed(
            value: true,
            confidence: 0.65,
          ),
        ),
      );

      expect(
        evidence.any(
          (item) => item.property == WardrobeProfileProperty.mobility,
        ),
        isFalse,
      );
      expect(
        evidence
            .firstWhere(
              (item) =>
                  item.property == WardrobeProfileProperty.visibleStretchCue,
            )
            .value,
        isTrue,
      );
    });

    test('E hoodie and sweater preserve false versus notVisible', () {
      final hoodie = provider.provide(
        bundle(
          analysisId: 'hoodie',
          hasHood: const ObservationValue<bool>.observed(
            value: true,
            confidence: 0.98,
          ),
          frontClosure: const ObservationValue<FrontClosure>.observed(
            value: FrontClosure.fullZip,
            confidence: 0.9,
          ),
          surfaceAppearance: const ObservationValue<SurfaceAppearance>.observed(
            value: SurfaceAppearance.fleeceLike,
            confidence: 0.75,
          ),
        ),
      );
      final sweaterUnknown = provider.provide(
        bundle(
          analysisId: 'sweater-hidden-back',
          hasHood: const ObservationValue<bool>.notVisible(),
          surfaceAppearance: const ObservationValue<SurfaceAppearance>.observed(
            value: SurfaceAppearance.knit,
            confidence: 0.95,
          ),
        ),
      );
      final sweaterVisible = provider.provide(
        bundle(
          analysisId: 'sweater-visible',
          hasHood: const ObservationValue<bool>.observed(
            value: false,
            confidence: 0.95,
          ),
          surfaceAppearance: const ObservationValue<SurfaceAppearance>.observed(
            value: SurfaceAppearance.knit,
            confidence: 0.95,
          ),
        ),
      );

      expect(hoodie.first.value, isTrue);
      expect(sweaterUnknown.first.valueState, EvidenceValueState.notVisible);
      expect(sweaterUnknown.first.value, isNull);
      expect(sweaterVisible.first.value, isFalse);
    });
  });
}
