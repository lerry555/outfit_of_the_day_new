import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_resolver.dart';

void main() {
  const resolver = WardrobeProfileResolver();
  final createdAt = DateTime.utc(2026, 7, 27);

  ProfileEvidence evidence({
    required String id,
    required String property,
    required Object? value,
    required EvidenceSource source,
    EvidenceNature nature = EvidenceNature.inferred,
    double confidence = 0.8,
    bool verified = false,
    bool active = true,
    String? supersedesEvidenceId,
    String? dependsOnCanonicalType,
  }) => ProfileEvidence(
    id: id,
    property: property,
    value: value,
    source: source,
    nature: nature,
    confidence: confidence,
    verified: verified,
    active: active,
    method: 'test',
    createdAt: createdAt,
    supersedesEvidenceId: supersedesEvidenceId,
    dependsOnCanonicalType: dependsOnCanonicalType,
  );

  ResolvedWardrobeItemProfile resolve(List<ProfileEvidence> items) =>
      resolver.resolve(itemId: 'item-1', evidence: items);

  test('user correction beats AI canonical type', () {
    final profile = resolve([
      evidence(
        id: 'ai',
        property: WardrobeProfileProperty.canonicalType,
        value: 'hoodie',
        source: EvidenceSource.aiInference,
        confidence: 0.9,
      ),
      evidence(
        id: 'user',
        property: WardrobeProfileProperty.canonicalType,
        value: 'softshell_jacket',
        source: EvidenceSource.userCorrection,
        nature: EvidenceNature.observed,
        confidence: 1,
      ),
    ]);

    expect(profile.identity.canonicalType.value, 'softshell_jacket');
    expect(profile.identity.canonicalType.userCorrected, isTrue);
    expect(
      profile.identity.canonicalType.winningSource,
      EvidenceSource.userCorrection,
    );
  });

  test('verified product metadata beats AI inference', () {
    final profile = resolve([
      evidence(
        id: 'ai',
        property: WardrobeProfileProperty.canonicalType,
        value: 'hoodie',
        source: EvidenceSource.aiInference,
        confidence: 0.85,
      ),
      evidence(
        id: 'product',
        property: WardrobeProfileProperty.canonicalType,
        value: 'softshell_jacket',
        source: EvidenceSource.verifiedProductMetadata,
        confidence: 0.75,
        verified: true,
      ),
    ]);

    expect(profile.identity.canonicalType.value, 'softshell_jacket');
    expect(
      profile.identity.canonicalType.winningSource,
      EvidenceSource.verifiedProductMetadata,
    );
    expect(profile.identity.canonicalType.hasConflict, isTrue);
    expect(profile.identity.canonicalType.conflictingEvidenceIds, ['ai']);
  });

  test('property policy resolves verified product versus verified label', () {
    final profile = resolve([
      evidence(
        id: 'product',
        property: WardrobeProfileProperty.canonicalType,
        value: 'softshell_jacket',
        source: EvidenceSource.verifiedProductMetadata,
        confidence: 0.8,
        verified: true,
      ),
      evidence(
        id: 'label',
        property: WardrobeProfileProperty.canonicalType,
        value: 'jacket',
        source: EvidenceSource.labelMetadata,
        confidence: 0.95,
        verified: true,
      ),
    ]);

    expect(profile.identity.canonicalType.isKnown, isTrue);
    expect(profile.identity.canonicalType.value, 'softshell_jacket');
    expect(
      profile.identity.canonicalType.winningSource,
      EvidenceSource.verifiedProductMetadata,
    );
    expect(profile.identity.canonicalType.hasConflict, isTrue);
  });

  test('visual evidence beats a KB default', () {
    final profile = resolve([
      evidence(
        id: 'kb',
        property: WardrobeProfileProperty.patterns,
        value: ['solid'],
        source: EvidenceSource.knowledgeBasePrior,
        nature: EvidenceNature.defaulted,
        confidence: 0.9,
      ),
      evidence(
        id: 'vision',
        property: WardrobeProfileProperty.patterns,
        value: ['striped'],
        source: EvidenceSource.visualObservation,
        nature: EvidenceNature.observed,
        confidence: 0.7,
      ),
    ]);

    expect(profile.visual.patterns.value, ['striped']);
    expect(
      profile.visual.patterns.winningSource,
      EvidenceSource.visualObservation,
    );
  });

  test('high-confidence AI cannot beat user correction', () {
    final profile = resolve([
      evidence(
        id: 'ai',
        property: WardrobeProfileProperty.fit,
        value: 'slim',
        source: EvidenceSource.aiInference,
        confidence: 0.99,
      ),
      evidence(
        id: 'user',
        property: WardrobeProfileProperty.fit,
        value: 'regular',
        source: EvidenceSource.userCorrection,
        confidence: 0.4,
      ),
    ]);

    expect(profile.visual.fit.value, 'regular');
    expect(profile.visual.fit.userCorrected, isTrue);
  });

  test('legacy fallback resolves when no better evidence exists', () {
    final profile = resolve([
      evidence(
        id: 'legacy',
        property: WardrobeProfileProperty.brand,
        value: 'Adidas',
        source: EvidenceSource.legacyFallback,
        nature: EvidenceNature.unknown,
        confidence: 0,
      ),
    ]);

    expect(profile.identity.brand.value, 'Adidas');
    expect(profile.identity.brand.winningSource, EvidenceSource.legacyFallback);
  });

  test('missing evidence remains unknown', () {
    final profile = resolve([]);

    expect(profile.identity.canonicalType.isKnown, isFalse);
    expect(profile.capabilities.mobility.isKnown, isFalse);
  });

  test('two equally authoritative quality assertions remain unknown', () {
    final profile = resolve([
      evidence(
        id: 'product-a',
        property: WardrobeProfileProperty.brand,
        value: 'Brand A',
        source: EvidenceSource.verifiedProductMetadata,
        confidence: 0.9,
        verified: true,
      ),
      evidence(
        id: 'product-b',
        property: WardrobeProfileProperty.brand,
        value: 'Brand B',
        source: EvidenceSource.verifiedProductMetadata,
        confidence: 0.9,
        verified: true,
      ),
    ]);

    expect(profile.identity.brand.isKnown, isFalse);
    expect(profile.identity.brand.hasConflict, isTrue);
    expect(
      profile.identity.brand.resolutionReason,
      'unresolved_high_authority_conflict',
    );
    expect(profile.identity.brand.conflictingEvidenceIds, [
      'product-a',
      'product-b',
    ]);
  });

  test('weak differing evidence is not recorded as significant conflict', () {
    final profile = resolve([
      evidence(
        id: 'user',
        property: WardrobeProfileProperty.canonicalType,
        value: 'hoodie',
        source: EvidenceSource.userCorrection,
        confidence: 1,
      ),
      evidence(
        id: 'weak-ai',
        property: WardrobeProfileProperty.canonicalType,
        value: 'jacket',
        source: EvidenceSource.aiInference,
        confidence: 0.2,
      ),
    ]);

    expect(profile.identity.canonicalType.value, 'hoodie');
    expect(profile.identity.canonicalType.hasConflict, isFalse);
  });

  test('concrete warmth evidence beats linked KB default', () {
    final profile = resolve([
      evidence(
        id: 'canonical',
        property: WardrobeProfileProperty.canonicalType,
        value: 'hoodie',
        source: EvidenceSource.aiInference,
      ),
      evidence(
        id: 'kb',
        property: WardrobeProfileProperty.warmth,
        value: 7,
        source: EvidenceSource.knowledgeBasePrior,
        nature: EvidenceNature.defaulted,
        confidence: 0.9,
        dependsOnCanonicalType: 'hoodie',
      ),
      evidence(
        id: 'visual',
        property: WardrobeProfileProperty.warmth,
        value: 3,
        source: EvidenceSource.visualObservation,
        nature: EvidenceNature.observed,
        confidence: 0.65,
      ),
    ]);

    expect(profile.capabilities.warmth.value, 3);
    expect(
      profile.capabilities.warmth.winningSource,
      EvidenceSource.visualObservation,
    );
  });

  test('rain suitability without evidence remains unknown', () {
    final profile = resolve([
      evidence(
        id: 'type',
        property: WardrobeProfileProperty.canonicalType,
        value: 'softshell_jacket',
        source: EvidenceSource.aiInference,
      ),
    ]);

    expect(profile.capabilities.rainSuitability.isKnown, isFalse);
  });

  test('inactive and superseded evidence are ignored', () {
    final profile = resolve([
      evidence(
        id: 'inactive',
        property: WardrobeProfileProperty.formality,
        value: 9,
        source: EvidenceSource.userCorrection,
        active: false,
      ),
      evidence(
        id: 'old',
        property: WardrobeProfileProperty.formality,
        value: 2,
        source: EvidenceSource.userCorrection,
      ),
      evidence(
        id: 'new',
        property: WardrobeProfileProperty.formality,
        value: 6,
        source: EvidenceSource.userCorrection,
        supersedesEvidenceId: 'old',
      ),
    ]);

    expect(profile.capabilities.formality.value, 6);
    expect(profile.capabilities.formality.winningEvidenceIds, ['new']);
    expect(profile.evidence.map((item) => item.id), ['new']);
  });

  test('same input resolved twice produces the same profile data', () {
    final items = [
      evidence(
        id: 'brand',
        property: WardrobeProfileProperty.brand,
        value: 'Nike',
        source: EvidenceSource.labelMetadata,
        confidence: 0.9,
      ),
      evidence(
        id: 'colors',
        property: WardrobeProfileProperty.colors,
        value: ['White', 'black'],
        source: EvidenceSource.visualObservation,
        nature: EvidenceNature.observed,
      ),
    ];

    final first = resolve(items);
    final second = resolve(items);

    expect(first.identity.brand.toMap(), second.identity.brand.toMap());
    expect(first.visual.colors.toMap(), second.visual.colors.toMap());
    expect(
      first.evidence.map((item) => item.toMap()).toList(),
      second.evidence.map((item) => item.toMap()).toList(),
    );
  });

  test('input order does not change resolution', () {
    final firstEvidence = evidence(
      id: 'ai',
      property: WardrobeProfileProperty.canonicalType,
      value: 'hoodie',
      source: EvidenceSource.aiInference,
      confidence: 0.8,
    );
    final secondEvidence = evidence(
      id: 'product',
      property: WardrobeProfileProperty.canonicalType,
      value: 'softshell',
      source: EvidenceSource.verifiedProductMetadata,
      confidence: 0.8,
      verified: true,
    );

    final forward = resolve([firstEvidence, secondEvidence]);
    final reverse = resolve([secondEvidence, firstEvidence]);

    expect(
      forward.identity.canonicalType.toMap(),
      reverse.identity.canonicalType.toMap(),
    );
    expect(
      forward.evidence.map((item) => item.id),
      reverse.evidence.map((item) => item.id),
    );
  });

  test('malformed values and conflicting duplicate IDs are ignored safely', () {
    final profile = resolve([
      evidence(
        id: 'bad-warmth',
        property: WardrobeProfileProperty.warmth,
        value: 'very warm',
        source: EvidenceSource.aiInference,
      ),
      evidence(
        id: 'duplicate',
        property: WardrobeProfileProperty.fit,
        value: 'slim',
        source: EvidenceSource.aiInference,
      ),
      evidence(
        id: 'duplicate',
        property: WardrobeProfileProperty.fit,
        value: 'regular',
        source: EvidenceSource.aiInference,
      ),
      evidence(
        id: 'unknown-property',
        property: 'unsupported.property',
        value: {'not': 'supported'},
        source: EvidenceSource.aiInference,
      ),
    ]);

    expect(profile.capabilities.warmth.isKnown, isFalse);
    expect(profile.visual.fit.isKnown, isFalse);
    expect(profile.evidence, isEmpty);
  });

  test('collection values are normalized and resolved deterministically', () {
    final profile = resolve([
      evidence(
        id: 'colors-b',
        property: WardrobeProfileProperty.colors,
        value: ['White', 'black', 'white'],
        source: EvidenceSource.visualObservation,
        nature: EvidenceNature.observed,
      ),
      evidence(
        id: 'colors-a',
        property: WardrobeProfileProperty.colors,
        value: ['black', 'White'],
        source: EvidenceSource.visualObservation,
        nature: EvidenceNature.observed,
      ),
      evidence(
        id: 'seasons',
        property: WardrobeProfileProperty.seasons,
        value: {'zima', 'Jeseň'},
        source: EvidenceSource.userCorrection,
      ),
    ]);

    expect(profile.visual.colors.value, ['black', 'White']);
    expect(profile.visual.colors.winningEvidenceIds, ['colors-a', 'colors-b']);
    expect(profile.suitability.seasons.value, {'Jeseň', 'zima'});
  });

  test('default tied to an old canonical type is discarded', () {
    final profile = resolve([
      evidence(
        id: 'corrected-type',
        property: WardrobeProfileProperty.canonicalType,
        value: 'light_softshell',
        source: EvidenceSource.userCorrection,
        confidence: 1,
      ),
      evidence(
        id: 'old-default',
        property: WardrobeProfileProperty.warmth,
        value: 8,
        source: EvidenceSource.knowledgeBasePrior,
        nature: EvidenceNature.defaulted,
        confidence: 0.9,
        dependsOnCanonicalType: 'winter_jacket',
      ),
    ]);

    expect(profile.capabilities.warmth.isKnown, isFalse);
  });
}
