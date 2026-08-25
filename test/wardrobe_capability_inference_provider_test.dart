import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_observation_evidence_provider.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_capability_inference_provider.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_resolver.dart';

void main() {
  const observationProvider = VisionObservationEvidenceProvider();
  const inferenceProvider = WardrobeCapabilityInferenceProvider();
  const resolver = WardrobeProfileResolver();
  final now = DateTime.utc(2026, 7, 27, 14);

  ClothingObservationBundle bundle({
    String analysisId = 'analysis',
    String sourceReference = 'image_front',
    ObservationValue<GarmentCoverage>? coverage,
    ObservationValue<bool>? hasHood,
    ObservationValue<FrontClosure>? frontClosure,
    ObservationValue<VisualAmount>? visibleBulk,
    ObservationValue<SurfaceAppearance>? surfaceAppearance,
    ObservationValue<bool>? visibleStretchCue,
    ObservationValue<VisualAmount>? sportyCues,
    ObservationValue<VisualAmount>? formalCues,
    ObservationValue<FootwearConstruction>? footwearConstruction,
    ObservationValue<SoleProfile>? soleProfile,
    ObservationValue<VisibleTread>? visibleTread,
    ObservationValue<FootwearUpperHeight>? footwearUpperHeight,
  }) => ClothingObservationBundle(
    analysisId: analysisId,
    modelVersion: 'observation-v1',
    sourceReference: sourceReference,
    observedAt: now,
    coverage: coverage,
    hasHood: hasHood,
    frontClosure: frontClosure,
    visibleBulk: visibleBulk,
    surfaceAppearance: surfaceAppearance,
    visibleStretchCue: visibleStretchCue,
    sportyCues: sportyCues,
    formalCues: formalCues,
    footwearConstruction: footwearConstruction,
    soleProfile: soleProfile,
    visibleTread: visibleTread,
    footwearUpperHeight: footwearUpperHeight,
  );

  List<ProfileEvidence> observations(ClothingObservationBundle input) =>
      observationProvider.provide(input);

  List<ProfileEvidence> infer(
    List<ProfileEvidence> input, {
    String inferenceId = 'inference',
  }) => inferenceProvider.infer(
    inferenceId: inferenceId,
    evidence: input,
    createdAt: now,
  );

  ProfileEvidence direct({
    required String id,
    required String property,
    required Object? value,
    required EvidenceSource source,
    EvidenceNature nature = EvidenceNature.observed,
    double confidence = 0.9,
    bool verified = true,
    String? dependsOnCanonicalType,
  }) => ProfileEvidence(
    id: id,
    property: property,
    value: value,
    source: source,
    nature: nature,
    confidence: confidence,
    verified: verified,
    method: 'test_direct_evidence',
    createdAt: now,
    dependsOnCanonicalType: dependsOnCanonicalType,
  );

  ProfileEvidence inferred(List<ProfileEvidence> output, String property) =>
      output.singleWhere((item) => item.property == property);

  test('warmth is inferred from multiple relevant observations', () {
    final output = infer(
      observations(
        bundle(
          visibleBulk: const ObservationValue.observed(
            value: VisualAmount.high,
            confidence: 0.9,
          ),
          surfaceAppearance: const ObservationValue.observed(
            value: SurfaceAppearance.fleeceLike,
            confidence: 0.85,
          ),
        ),
      ),
    );

    final warmth = inferred(output, WardrobeProfileProperty.warmth);
    expect(warmth.value, 7);
    expect(warmth.confidence, lessThanOrEqualTo(0.68));
    expect(warmth.method, contains('bulk_and_insulating_surface'));
  });

  test('one weak warmth clue remains unknown', () {
    final output = infer(
      observations(
        bundle(
          visibleBulk: const ObservationValue.observed(
            value: VisualAmount.high,
            confidence: 0.95,
          ),
        ),
      ),
    );

    expect(
      output.any((item) => item.property == WardrobeProfileProperty.warmth),
      isFalse,
    );
  });

  test('breathability remains unknown without specific clues', () {
    final output = infer(
      observations(
        bundle(
          surfaceAppearance: const ObservationValue.observed(
            value: SurfaceAppearance.woven,
            confidence: 0.95,
          ),
          visibleBulk: const ObservationValue.observed(
            value: VisualAmount.low,
            confidence: 0.9,
          ),
        ),
      ),
    );

    expect(
      output.any(
        (item) => item.property == WardrobeProfileProperty.breathability,
      ),
      isFalse,
    );
  });

  test('mesh and low bulk support breathability inference', () {
    final profileEvidence = observations(
      bundle(
        surfaceAppearance: const ObservationValue.observed(
          value: SurfaceAppearance.mesh,
          confidence: 0.9,
        ),
        visibleBulk: const ObservationValue.observed(
          value: VisualAmount.low,
          confidence: 0.85,
        ),
      ),
    );
    final profile = resolver.resolve(
      itemId: 'mesh-item',
      evidence: [...profileEvidence, ...infer(profileEvidence)],
    );

    expect(profile.capabilities.breathability.value, CapabilityLevel.high);
  });

  test('stretch plus sporty cues support mobility', () {
    final output = infer(
      observations(
        bundle(
          visibleStretchCue: const ObservationValue.observed(
            value: true,
            confidence: 0.8,
          ),
          sportyCues: const ObservationValue.observed(
            value: VisualAmount.high,
            confidence: 0.85,
          ),
        ),
      ),
    );

    expect(inferred(output, WardrobeProfileProperty.mobility).value, 'high');
  });

  test('absence or invisibility of stretch is not low mobility', () {
    for (final stretch in [
      const ObservationValue<bool>.observed(value: false, confidence: 0.9),
      const ObservationValue<bool>.notVisible(),
    ]) {
      final output = infer(observations(bundle(visibleStretchCue: stretch)));
      expect(
        output.any((item) => item.property == WardrobeProfileProperty.mobility),
        isFalse,
      );
    }
  });

  test('classic trousers image cues do not infer wind protection', () {
    final output = infer(
      observations(
        bundle(
          coverage: const ObservationValue.observed(
            value: GarmentCoverage.full,
            confidence: 0.9,
          ),
          frontClosure: const ObservationValue.observed(
            value: FrontClosure.fullZip,
            confidence: 0.85,
          ),
          surfaceAppearance: const ObservationValue.observed(
            value: SurfaceAppearance.smooth,
            confidence: 0.8,
          ),
        ),
      ),
    );
    expect(
      output.any(
        (item) => item.property == WardrobeProfileProperty.windProtection,
      ),
      isFalse,
    );
  });

  test('hoodie image-only construction leaves rain protection unknown', () {
    final sparse = observations(
      bundle(
        hasHood: const ObservationValue.observed(value: true, confidence: 0.9),
        surfaceAppearance: const ObservationValue.observed(
          value: SurfaceAppearance.smooth,
          confidence: 0.85,
        ),
      ),
    );
    expect(
      infer(
        sparse,
      ).any((item) => item.property == WardrobeProfileProperty.rainProtection),
      isFalse,
    );

    final complete = observations(
      bundle(
        coverage: const ObservationValue.observed(
          value: GarmentCoverage.full,
          confidence: 0.9,
        ),
        hasHood: const ObservationValue.observed(value: true, confidence: 0.9),
        frontClosure: const ObservationValue.observed(
          value: FrontClosure.fullZip,
          confidence: 0.9,
        ),
        surfaceAppearance: const ObservationValue.observed(
          value: SurfaceAppearance.smooth,
          confidence: 0.85,
        ),
      ),
    );
    expect(
      infer(
        complete,
      ).any((item) => item.property == WardrobeProfileProperty.rainProtection),
      isFalse,
    );
  });

  test('verified rain specification beats visual inference', () {
    final observed = observations(
      bundle(
        coverage: const ObservationValue.observed(
          value: GarmentCoverage.full,
          confidence: 0.9,
        ),
        hasHood: const ObservationValue.observed(value: true, confidence: 0.9),
        frontClosure: const ObservationValue.observed(
          value: FrontClosure.fullZip,
          confidence: 0.9,
        ),
        surfaceAppearance: const ObservationValue.observed(
          value: SurfaceAppearance.smooth,
          confidence: 0.9,
        ),
      ),
    );
    final profile = resolver.resolve(
      itemId: 'shell',
      evidence: [
        ...observed,
        ...infer(observed),
        direct(
          id: 'verified-waterproof-rating',
          property: WardrobeProfileProperty.rainProtection,
          value: 'very_high',
          source: EvidenceSource.verifiedProductMetadata,
          confidence: 0.98,
        ),
      ],
    );

    expect(profile.capabilities.rainProtection.value, CapabilityLevel.veryHigh);
    expect(
      profile.capabilities.rainProtection.winningSource,
      EvidenceSource.verifiedProductMetadata,
    );
  });

  test('formality is inferred from visual cues, not canonical type', () {
    final output = infer(
      observations(
        bundle(
          formalCues: const ObservationValue.observed(
            value: VisualAmount.high,
            confidence: 0.9,
          ),
          sportyCues: const ObservationValue.observed(
            value: VisualAmount.low,
            confidence: 0.85,
          ),
        ),
      ),
    );

    expect(inferred(output, WardrobeProfileProperty.formality).value, 8);
  });

  test('supported layer roles are inferred from construction cues', () {
    final observed = observations(
      bundle(
        hasHood: const ObservationValue.observed(value: true, confidence: 0.9),
        frontClosure: const ObservationValue.observed(
          value: FrontClosure.fullZip,
          confidence: 0.9,
        ),
        visibleBulk: const ObservationValue.observed(
          value: VisualAmount.medium,
          confidence: 0.8,
        ),
      ),
    );
    final profile = resolver.resolve(
      itemId: 'hooded-layer',
      evidence: [...observed, ...infer(observed)],
    );

    expect(profile.capabilities.supportedLayerRoles.value, {
      WardrobeLayerRole.midLayer,
      WardrobeLayerRole.outerLayer,
    });
    expect(profile.capabilities.layerRole.isUnknown, isTrue);
  });

  test('pronounced tread supports traction but not guaranteed suitability', () {
    final output = infer(
      observations(
        bundle(
          footwearConstruction: const ObservationValue.observed(
            value: FootwearConstruction.closed,
            confidence: 0.98,
          ),
          visibleTread: const ObservationValue.observed(
            value: VisibleTread.pronounced,
            confidence: 0.9,
          ),
        ),
      ),
    );

    expect(inferred(output, WardrobeProfileProperty.traction).value, 'high');
    expect(
      output.any(
        (item) => item.property == WardrobeProfileProperty.outdoorSuitability,
      ),
      isFalse,
    );
  });

  test('tread notVisible leaves traction unknown', () {
    final output = infer(
      observations(
        bundle(
          footwearConstruction: const ObservationValue.observed(
            value: FootwearConstruction.closed,
            confidence: 0.98,
          ),
          visibleTread: const ObservationValue<VisibleTread>.notVisible(),
        ),
      ),
    );

    expect(
      output.any((item) => item.property == WardrobeProfileProperty.traction),
      isFalse,
    );
  });

  test('walking comfort requires a complete footwear cue set', () {
    final bootOutput = infer(
      observations(
        bundle(
          footwearConstruction: const ObservationValue.observed(
            value: FootwearConstruction.closed,
            confidence: 0.95,
          ),
          footwearUpperHeight: const ObservationValue.observed(
            value: FootwearUpperHeight.ankle,
            confidence: 0.9,
          ),
          soleProfile: const ObservationValue.observed(
            value: SoleProfile.chunky,
            confidence: 0.8,
          ),
        ),
      ),
    );
    expect(
      bootOutput.any(
        (item) => item.property == WardrobeProfileProperty.walkingComfort,
      ),
      isFalse,
    );

    final trailOutput = infer(
      observations(
        bundle(
          footwearConstruction: const ObservationValue.observed(
            value: FootwearConstruction.closed,
            confidence: 0.95,
          ),
          footwearUpperHeight: const ObservationValue.observed(
            value: FootwearUpperHeight.lowCut,
            confidence: 0.9,
          ),
          soleProfile: const ObservationValue.observed(
            value: SoleProfile.standard,
            confidence: 0.85,
          ),
          sportyCues: const ObservationValue.observed(
            value: VisualAmount.high,
            confidence: 0.9,
          ),
        ),
      ),
    );
    final comfort = inferred(
      trailOutput,
      WardrobeProfileProperty.walkingComfort,
    );
    expect(comfort.value, 'medium');
    expect(comfort.confidence, lessThanOrEqualTo(0.5));
  });

  test('explicit non-footwear structure makes footwear capabilities N/A', () {
    final output = infer(
      observations(
        bundle(
          footwearConstruction:
              const ObservationValue<FootwearConstruction>.notApplicable(),
        ),
      ),
    );
    final profile = resolver.resolve(itemId: 'shirt', evidence: output);

    expect(profile.capabilities.traction.isNotApplicable, isTrue);
    expect(profile.capabilities.walkingComfort.isNotApplicable, isTrue);
  });

  test('user correction beats inferred traction', () {
    final observed = observations(
      bundle(
        visibleTread: const ObservationValue.observed(
          value: VisibleTread.pronounced,
          confidence: 0.95,
        ),
      ),
    );
    final profile = resolver.resolve(
      itemId: 'shoe',
      evidence: [
        ...observed,
        ...infer(observed),
        direct(
          id: 'user-traction',
          property: WardrobeProfileProperty.traction,
          value: 'low',
          source: EvidenceSource.userCorrection,
          confidence: 1,
        ),
      ],
    );

    expect(profile.capabilities.traction.value, CapabilityLevel.low);
    expect(profile.capabilities.traction.userCorrected, isTrue);
  });

  test('item-specific inference beats KB prior', () {
    final observed = observations(
      bundle(
        visibleStretchCue: const ObservationValue.observed(
          value: true,
          confidence: 0.9,
        ),
        sportyCues: const ObservationValue.observed(
          value: VisualAmount.high,
          confidence: 0.9,
        ),
      ),
    );
    final profile = resolver.resolve(
      itemId: 'trousers',
      evidence: [
        ...observed,
        ...infer(observed),
        direct(
          id: 'kb-mobility',
          property: WardrobeProfileProperty.mobility,
          value: 'low',
          source: EvidenceSource.knowledgeBasePrior,
          nature: EvidenceNature.defaulted,
          confidence: 0.9,
          verified: false,
        ),
      ],
    );

    expect(profile.capabilities.mobility.value, CapabilityLevel.high);
    expect(
      profile.capabilities.mobility.winningSource,
      EvidenceSource.aiInference,
    );
  });

  test('stale canonical-dependent default remains invalidated', () {
    final observed = observations(
      bundle(
        visibleTread: const ObservationValue.observed(
          value: VisibleTread.pronounced,
          confidence: 0.9,
        ),
      ),
    );
    final profile = resolver.resolve(
      itemId: 'shoe',
      evidence: [
        ...observed,
        ...infer(observed),
        direct(
          id: 'canonical',
          property: WardrobeProfileProperty.canonicalType,
          value: 'trail_shoes',
          source: EvidenceSource.userCorrection,
          confidence: 1,
        ),
        direct(
          id: 'stale-kb',
          property: WardrobeProfileProperty.traction,
          value: 'low',
          source: EvidenceSource.knowledgeBasePrior,
          nature: EvidenceNature.defaulted,
          confidence: 0.9,
          verified: false,
          dependsOnCanonicalType: 'fashion_boots',
        ),
      ],
    );

    expect(profile.capabilities.traction.value, CapabilityLevel.high);
    expect(profile.capabilities.traction.winningEvidenceIds, [
      'capability:inference:capabilities.traction',
    ]);
  });

  test('multi-photo agreement contributes without using max confidence', () {
    final front = observations(
      bundle(
        analysisId: 'front',
        sourceReference: 'image_front',
        visibleTread: const ObservationValue.observed(
          value: VisibleTread.pronounced,
          confidence: 0.7,
        ),
      ),
    );
    final sole = observations(
      bundle(
        analysisId: 'sole',
        sourceReference: 'image_sole',
        visibleTread: const ObservationValue.observed(
          value: VisibleTread.pronounced,
          confidence: 0.9,
        ),
      ),
    );
    final traction = inferred(
      infer([...front, ...sole]),
      WardrobeProfileProperty.traction,
    );

    expect(traction.sourceReference, 'image_front|image_sole');
    expect(traction.confidence, lessThan(0.9));
    expect(traction.confidence, greaterThan(0.7 * 0.8));
  });

  test('multi-photo conflict produces no random inference', () {
    final low = observations(
      bundle(
        analysisId: 'low',
        sourceReference: 'image_a',
        visibleTread: const ObservationValue.observed(
          value: VisibleTread.low,
          confidence: 0.9,
        ),
      ),
    );
    final pronounced = observations(
      bundle(
        analysisId: 'pronounced',
        sourceReference: 'image_b',
        visibleTread: const ObservationValue.observed(
          value: VisibleTread.pronounced,
          confidence: 0.9,
        ),
      ),
    );

    expect(
      infer([
        ...low,
        ...pronounced,
      ]).any((item) => item.property == WardrobeProfileProperty.traction),
      isFalse,
    );
  });

  test('provider is deterministic, immutable and capability-only', () {
    final input = observations(
      bundle(
        visibleTread: const ObservationValue.observed(
          value: VisibleTread.pronounced,
          confidence: 0.9,
        ),
        sportyCues: const ObservationValue.observed(
          value: VisualAmount.high,
          confidence: 0.8,
        ),
      ),
    );
    final before = input.map((item) => item.toMap()).toList();
    final first = infer(input);
    final second = infer(input);

    expect(
      first.map((item) => item.toMap()).toList(),
      second.map((item) => item.toMap()).toList(),
    );
    expect(input.map((item) => item.toMap()).toList(), before);
    expect(
      first.every((item) => item.property.startsWith('capabilities.')),
      isTrue,
    );
    expect(
      first.any(
        (item) =>
            item.property.contains('activity') ||
            item.property.contains('hiking') ||
            item.property.startsWith('suitability.'),
      ),
      isFalse,
    );
  });

  group('acceptance pairs have distinct evidence without matching', () {
    test('thicker jeans and light trousers differ thermally', () {
      final heavy = infer(
        observations(
          bundle(
            coverage: const ObservationValue.observed(
              value: GarmentCoverage.full,
              confidence: 0.95,
            ),
            visibleBulk: const ObservationValue.observed(
              value: VisualAmount.high,
              confidence: 0.85,
            ),
          ),
        ),
        inferenceId: 'heavy',
      );
      final light = infer(
        observations(
          bundle(
            analysisId: 'light',
            coverage: const ObservationValue.observed(
              value: GarmentCoverage.full,
              confidence: 0.95,
            ),
            visibleBulk: const ObservationValue.observed(
              value: VisualAmount.low,
              confidence: 0.85,
            ),
          ),
        ),
        inferenceId: 'light',
      );

      expect(inferred(heavy, WardrobeProfileProperty.warmth).value, 6);
      expect(inferred(light, WardrobeProfileProperty.warmth).value, 3);
    });

    test('elegant and functional trousers differ without hike semantics', () {
      final elegant = infer(
        observations(
          bundle(
            formalCues: const ObservationValue.observed(
              value: VisualAmount.high,
              confidence: 0.9,
            ),
            sportyCues: const ObservationValue.observed(
              value: VisualAmount.low,
              confidence: 0.85,
            ),
            visibleStretchCue: const ObservationValue<bool>.notVisible(),
          ),
        ),
        inferenceId: 'elegant',
      );
      final functional = infer(
        observations(
          bundle(
            analysisId: 'functional',
            sportyCues: const ObservationValue.observed(
              value: VisualAmount.high,
              confidence: 0.9,
            ),
            visibleStretchCue: const ObservationValue.observed(
              value: true,
              confidence: 0.8,
            ),
          ),
        ),
        inferenceId: 'functional',
      );

      expect(inferred(elegant, WardrobeProfileProperty.formality).value, 8);
      expect(
        elegant.any(
          (item) => item.property == WardrobeProfileProperty.mobility,
        ),
        isFalse,
      );
      expect(
        inferred(functional, WardrobeProfileProperty.mobility).value,
        'high',
      );
      expect(
        functional.any(
          (item) => item.property == WardrobeProfileProperty.outdoorSuitability,
        ),
        isFalse,
      );
    });

    test('fashion ankle boot and trail footwear differ conservatively', () {
      final fashion = infer(
        observations(
          bundle(
            footwearConstruction: const ObservationValue.observed(
              value: FootwearConstruction.closed,
              confidence: 0.98,
            ),
            footwearUpperHeight: const ObservationValue.observed(
              value: FootwearUpperHeight.ankle,
              confidence: 0.9,
            ),
            soleProfile: const ObservationValue.observed(
              value: SoleProfile.chunky,
              confidence: 0.8,
            ),
            visibleTread: const ObservationValue<VisibleTread>.notVisible(),
            visibleBulk: const ObservationValue.observed(
              value: VisualAmount.high,
              confidence: 0.8,
            ),
            formalCues: const ObservationValue.observed(
              value: VisualAmount.high,
              confidence: 0.8,
            ),
          ),
        ),
        inferenceId: 'fashion',
      );
      final trail = infer(
        observations(
          bundle(
            analysisId: 'trail',
            footwearConstruction: const ObservationValue.observed(
              value: FootwearConstruction.closed,
              confidence: 0.98,
            ),
            footwearUpperHeight: const ObservationValue.observed(
              value: FootwearUpperHeight.lowCut,
              confidence: 0.9,
            ),
            soleProfile: const ObservationValue.observed(
              value: SoleProfile.standard,
              confidence: 0.85,
            ),
            visibleTread: const ObservationValue.observed(
              value: VisibleTread.pronounced,
              confidence: 0.9,
            ),
            visibleBulk: const ObservationValue.observed(
              value: VisualAmount.low,
              confidence: 0.8,
            ),
            sportyCues: const ObservationValue.observed(
              value: VisualAmount.high,
              confidence: 0.9,
            ),
          ),
        ),
        inferenceId: 'trail',
      );

      expect(
        fashion.any(
          (item) => item.property == WardrobeProfileProperty.traction,
        ),
        isFalse,
      );
      expect(
        fashion.any(
          (item) => item.property == WardrobeProfileProperty.walkingComfort,
        ),
        isFalse,
      );
      expect(inferred(trail, WardrobeProfileProperty.traction).value, 'high');
      expect(
        inferred(trail, WardrobeProfileProperty.walkingComfort).value,
        'medium',
      );
    });

    test('hoodie and sweater produce roles without canonical consistency', () {
      final hoodie = infer(
        observations(
          bundle(
            hasHood: const ObservationValue.observed(
              value: true,
              confidence: 0.95,
            ),
            frontClosure: const ObservationValue.observed(
              value: FrontClosure.fullZip,
              confidence: 0.9,
            ),
            visibleBulk: const ObservationValue.observed(
              value: VisualAmount.medium,
              confidence: 0.8,
            ),
          ),
        ),
        inferenceId: 'hoodie',
      );
      final sweater = infer(
        observations(
          bundle(
            analysisId: 'sweater',
            frontClosure: const ObservationValue.observed(
              value: FrontClosure.none,
              confidence: 0.95,
            ),
            surfaceAppearance: const ObservationValue.observed(
              value: SurfaceAppearance.knit,
              confidence: 0.95,
            ),
            visibleBulk: const ObservationValue.observed(
              value: VisualAmount.medium,
              confidence: 0.8,
            ),
          ),
        ),
        inferenceId: 'sweater',
      );

      expect(
        inferred(hoodie, WardrobeProfileProperty.supportedLayerRoles).value,
        ['mid_layer', 'outer_layer'],
      );
      expect(
        inferred(sweater, WardrobeProfileProperty.supportedLayerRoles).value,
        ['base_layer', 'mid_layer'],
      );
      expect(
        [
          ...hoodie,
          ...sweater,
        ].any((item) => item.property == WardrobeProfileProperty.canonicalType),
        isFalse,
      );
    });
  });
}
