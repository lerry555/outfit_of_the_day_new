import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/situation_requirements_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_resolver.dart';

void main() {
  const resolver = WardrobeProfileResolver();
  final createdAt = DateTime.utc(2026, 7, 27);

  ProfileEvidence evidence({
    required String id,
    required String property,
    Object? value,
    EvidenceSource source = EvidenceSource.aiInference,
    EvidenceNature nature = EvidenceNature.inferred,
    double confidence = 0.8,
    String? dependsOnCanonicalType,
    EvidenceValueState valueState = EvidenceValueState.known,
  }) => ProfileEvidence(
    id: id,
    property: property,
    value: value,
    source: source,
    nature: nature,
    confidence: confidence,
    method: 'contract_test',
    createdAt: createdAt,
    dependsOnCanonicalType: dependsOnCanonicalType,
    valueState: valueState,
  );

  test('capability property paths are centralized and stable', () {
    expect(
      WardrobeProfileProperty.rainProtection,
      'capabilities.rainProtection',
    );
    expect(
      WardrobeProfileProperty.walkingComfort,
      'capabilities.walkingComfort',
    );
    expect(WardrobeProfileProperty.traction, 'capabilities.traction');
    expect(
      WardrobeProfileProperty.supportedLayerRoles,
      'capabilities.supportedLayerRoles',
    );
    expect(WardrobeProfileProperty.coverage, 'visual.coverage');
  });

  test('known capability preserves evidence provenance', () {
    final profile = resolver.resolve(
      itemId: 'shoe',
      evidence: [
        evidence(
          id: 'label-traction',
          property: WardrobeProfileProperty.traction,
          value: 'high',
          source: EvidenceSource.labelMetadata,
          nature: EvidenceNature.observed,
          confidence: 0.9,
        ),
      ],
    );

    expect(profile.capabilities.traction.value, CapabilityLevel.high);
    expect(
      profile.capabilities.traction.winningSource,
      EvidenceSource.labelMetadata,
    );
    expect(profile.capabilities.traction.winningEvidenceIds, [
      'label-traction',
    ]);
  });

  test('missing capability remains unknown and invalid value is ignored', () {
    final profile = resolver.resolve(
      itemId: 'shoe',
      evidence: [
        evidence(
          id: 'invalid-traction',
          property: WardrobeProfileProperty.traction,
          value: 'extreme',
        ),
      ],
    );

    expect(profile.capabilities.traction.isUnknown, isTrue);
    expect(profile.evidence, isEmpty);
  });

  test('explicit not-applicable evidence resolves without a neutral value', () {
    final profile = resolver.resolve(
      itemId: 'shirt',
      evidence: [
        evidence(
          id: 'user-na',
          property: WardrobeProfileProperty.traction,
          source: EvidenceSource.userCorrection,
          nature: EvidenceNature.observed,
          confidence: 1,
          valueState: EvidenceValueState.notApplicable,
        ),
      ],
    );

    expect(profile.capabilities.traction.isNotApplicable, isTrue);
    expect(profile.capabilities.traction.value, isNull);
    expect(profile.capabilities.traction.userCorrected, isTrue);
  });

  test('user correction beats conflicting AI capability evidence', () {
    final profile = resolver.resolve(
      itemId: 'shoe',
      evidence: [
        evidence(
          id: 'ai',
          property: WardrobeProfileProperty.traction,
          value: 'high',
          confidence: 0.99,
        ),
        evidence(
          id: 'user',
          property: WardrobeProfileProperty.traction,
          value: 'low',
          source: EvidenceSource.userCorrection,
          nature: EvidenceNature.observed,
          confidence: 1,
        ),
      ],
    );

    expect(profile.capabilities.traction.value, CapabilityLevel.low);
    expect(profile.capabilities.traction.userCorrected, isTrue);
    expect(profile.capabilities.traction.hasConflict, isTrue);
  });

  test('canonical-dependent capability default is invalidated', () {
    final profile = resolver.resolve(
      itemId: 'shoe',
      evidence: [
        evidence(
          id: 'canonical',
          property: WardrobeProfileProperty.canonicalType,
          value: 'trail_shoes',
          source: EvidenceSource.userCorrection,
          nature: EvidenceNature.observed,
          confidence: 1,
        ),
        evidence(
          id: 'old-default',
          property: WardrobeProfileProperty.traction,
          value: 'high',
          source: EvidenceSource.knowledgeBasePrior,
          nature: EvidenceNature.defaulted,
          dependsOnCanonicalType: 'winter_ankle_boots',
        ),
      ],
    );

    expect(profile.capabilities.traction.isUnknown, isTrue);
  });

  test('supported layer roles coexist with legacy primary role', () {
    final profile = resolver.resolve(
      itemId: 'hoodie',
      evidence: [
        evidence(
          id: 'legacy-role',
          property: WardrobeProfileProperty.layerRole,
          value: 'mid_layer',
          source: EvidenceSource.legacyFallback,
          nature: EvidenceNature.unknown,
          confidence: 0,
        ),
        evidence(
          id: 'supported-roles',
          property: WardrobeProfileProperty.supportedLayerRoles,
          value: ['mid_layer', 'base_layer'],
          source: EvidenceSource.userCorrection,
          nature: EvidenceNature.observed,
          confidence: 1,
        ),
      ],
    );

    expect(profile.capabilities.layerRole.value, WardrobeLayerRole.midLayer);
    expect(profile.capabilities.supportedLayerRoles.value, {
      WardrobeLayerRole.baseLayer,
      WardrobeLayerRole.midLayer,
    });
  });

  test('coverage resolves as an observable rather than a capability', () {
    final profile = resolver.resolve(
      itemId: 'trousers',
      evidence: [
        evidence(
          id: 'coverage',
          property: WardrobeProfileProperty.coverage,
          value: 'full',
          source: EvidenceSource.visualObservation,
          nature: EvidenceNature.observed,
        ),
      ],
    );

    expect(profile.visual.coverage.value, GarmentCoverage.full);
  });

  test('situation requirements serialize deterministically and round-trip', () {
    const requirements = SituationRequirements(
      thermal: SituationRequirement(
        value: CapabilityLevel.low,
        criticality: RequirementCriticality.softRequirement,
      ),
      mobility: SituationRequirement(
        value: CapabilityLevel.high,
        criticality: RequirementCriticality.hardRequirement,
      ),
      formality: SituationRequirement(
        value: FormalityRange(minimum: 2, maximum: 5),
        criticality: RequirementCriticality.preference,
      ),
      layerRoles: SituationRequirement(
        value: {WardrobeLayerRole.outerLayer, WardrobeLayerRole.midLayer},
      ),
      tractionDemand: SituationRequirement(
        value: CapabilityLevel.veryHigh,
        criticality: RequirementCriticality.safetyCritical,
      ),
      coverageDemand: SituationRequirement(
        value: GarmentCoverage.full,
        criticality: RequirementCriticality.hardRequirement,
      ),
    );

    final serialized = requirements.toMap();
    final restored = SituationRequirements.fromMap(
      Map<String, dynamic>.from(serialized),
    );

    expect(restored.toMap(), serialized);
    expect(
      serialized['contractVersion'],
      WardrobeProfileVersions.situationRequirementsContract,
    );
    expect((serialized['layerRoles'] as Map)['value'], [
      'mid_layer',
      'outer_layer',
    ]);
    expect(
      restored.tractionDemand?.criticality,
      RequirementCriticality.safetyCritical,
    );
  });

  group('acceptance fixtures represent decisions without activity labels', () {
    ResolvedField<CapabilityLevel> level(CapabilityLevel value) =>
        ResolvedField<CapabilityLevel>.known(
          value: value,
          nature: EvidenceNature.observed,
          winningSource: EvidenceSource.visualObservation,
          confidence: 0.8,
          resolutionReason: 'fixture',
        );

    ResolvedField<int> numeric(int value) => ResolvedField<int>.known(
      value: value,
      nature: EvidenceNature.observed,
      winningSource: EvidenceSource.visualObservation,
      confidence: 0.8,
      resolutionReason: 'fixture',
    );

    ResolvedField<GarmentCoverage> coverage(GarmentCoverage value) =>
        ResolvedField<GarmentCoverage>.known(
          value: value,
          nature: EvidenceNature.observed,
          winningSource: EvidenceSource.visualObservation,
          confidence: 0.8,
          resolutionReason: 'fixture',
        );

    test('warm workday distinguishes heavy jeans and light trousers', () {
      const situation = SituationRequirements(
        thermal: SituationRequirement(value: CapabilityLevel.low),
        breathability: SituationRequirement(value: CapabilityLevel.high),
        mobility: SituationRequirement(value: CapabilityLevel.medium),
        formality: SituationRequirement(
          value: FormalityRange(minimum: 4, maximum: 6),
        ),
      );
      final jeans = ResolvedWardrobeItemProfile(
        itemId: 'heavy-jeans',
        capabilities: WardrobeItemCapabilities(
          warmth: numeric(7),
          breathability: level(CapabilityLevel.low),
          mobility: level(CapabilityLevel.medium),
        ),
      );
      final lightTrousers = ResolvedWardrobeItemProfile(
        itemId: 'light-trousers',
        capabilities: WardrobeItemCapabilities(
          warmth: numeric(3),
          breathability: level(CapabilityLevel.high),
          mobility: level(CapabilityLevel.high),
        ),
      );

      expect(situation.toMap().toString(), isNot(contains('work')));
      expect(jeans.capabilities.warmth.value, 7);
      expect(
        lightTrousers.capabilities.breathability.value,
        CapabilityLevel.high,
      );
    });

    test('outdoor bottoms distinguish formality, mobility and coverage', () {
      const situation = SituationRequirements(
        mobility: SituationRequirement(value: CapabilityLevel.high),
        breathability: SituationRequirement(value: CapabilityLevel.high),
        walkingDemand: SituationRequirement(value: CapabilityLevel.high),
        coverageDemand: SituationRequirement(value: GarmentCoverage.full),
        formality: SituationRequirement(
          value: FormalityRange(minimum: 1, maximum: 3),
        ),
      );
      final elegant = ResolvedWardrobeItemProfile(
        itemId: 'elegant-trousers',
        visual: WardrobeItemVisualProfile(
          coverage: coverage(GarmentCoverage.full),
        ),
        capabilities: WardrobeItemCapabilities(
          mobility: level(CapabilityLevel.low),
          formality: numeric(8),
        ),
      );
      final outdoor = ResolvedWardrobeItemProfile(
        itemId: 'outdoor-trousers',
        visual: WardrobeItemVisualProfile(
          coverage: coverage(GarmentCoverage.full),
        ),
        capabilities: WardrobeItemCapabilities(
          mobility: level(CapabilityLevel.high),
          breathability: level(CapabilityLevel.high),
          formality: numeric(2),
        ),
      );

      expect(situation.toMap().toString(), isNot(contains('hike')));
      expect(elegant.visual.coverage.value, GarmentCoverage.full);
      expect(outdoor.capabilities.formality.value, 2);
    });

    test('outdoor footwear distinguishes winter boots and trail shoes', () {
      const situation = SituationRequirements(
        thermal: SituationRequirement(value: CapabilityLevel.low),
        mobility: SituationRequirement(value: CapabilityLevel.high),
        walkingDemand: SituationRequirement(value: CapabilityLevel.high),
        tractionDemand: SituationRequirement(
          value: CapabilityLevel.high,
          criticality: RequirementCriticality.hardRequirement,
        ),
      );
      final winterBoots = ResolvedWardrobeItemProfile(
        itemId: 'winter-ankle-boots',
        capabilities: WardrobeItemCapabilities(
          warmth: numeric(8),
          mobility: level(CapabilityLevel.low),
          walkingComfort: const ResolvedField<CapabilityLevel>.unknown(),
          traction: level(CapabilityLevel.low),
        ),
      );
      final trailShoes = ResolvedWardrobeItemProfile(
        itemId: 'trail-shoes',
        capabilities: WardrobeItemCapabilities(
          warmth: numeric(3),
          mobility: level(CapabilityLevel.high),
          walkingComfort: level(CapabilityLevel.high),
          traction: level(CapabilityLevel.high),
        ),
      );

      expect(situation.toMap().toString(), isNot(contains('hike')));
      expect(winterBoots.capabilities.walkingComfort.isUnknown, isTrue);
      expect(trailShoes.capabilities.traction.value, CapabilityLevel.high);
    });
  });
}
