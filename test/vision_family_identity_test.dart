import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_family_identity.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_visibility_trust.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

void main() {
  const resolver = VisionFamilyIdentityResolver();
  const quality = ObservationImageQuality();

  ClothingObservationBundle garment() => ClothingObservationBundle(
    analysisId: 'family-test',
    modelVersion: 'fixture',
    sourceReference: 'fixture://family',
    observedAt: DateTime.utc(2026),
    quality: quality,
    coverage: const ObservationValue<GarmentCoverage>.observed(
      value: GarmentCoverage.full,
      confidence: 0.9,
      visibilityScope: ObservationVisibilityScope.complete,
    ),
  );

  VisionFamilyIdentityInput candidate(String type, double confidence) =>
      VisionFamilyIdentityInput(canonicalType: type, confidence: confidence);

  test('trouser family resolves while subtype remains unknown', () {
    final result = resolver.resolve(
      identityCandidates: [
        candidate('chinos', 0.8),
        candidate('cargo_pants', 0.2),
      ],
      observations: garment(),
      resolvedCanonicalSubtype: null,
    );
    expect(result.resolvedFamily, VisionIdentityFamily.trousers);
    expect(result.subtypeResolved, isFalse);
    expect(result.reasonCodes, contains('family_resolved_subtype_unresolved'));
  });

  test('jacket family resolves without creating capabilities', () {
    final result = resolver.resolve(
      identityCandidates: [
        candidate('puffer_jacket', 0.5),
        candidate('winter_jacket', 0.5),
      ],
      observations: garment(),
      resolvedCanonicalSubtype: null,
    );
    expect(result.resolvedFamily, VisionIdentityFamily.jacketOuterwear);
    expect(result.toMap(), isNot(contains('warmth')));
    expect(result.toMap(), isNot(contains('rainProtection')));
  });

  test('running and sneaker candidates resolve sneaker family only', () {
    final observations = ClothingObservationBundle(
      analysisId: 'shoes',
      modelVersion: 'fixture',
      sourceReference: 'fixture://shoes',
      observedAt: DateTime.utc(2026),
      quality: quality,
      footwearConstruction:
          const ObservationValue<FootwearConstruction>.observed(
            value: FootwearConstruction.closed,
            confidence: 0.85,
            visibilityScope: ObservationVisibilityScope.complete,
          ),
    );
    final result = resolver.resolve(
      identityCandidates: [
        candidate('running_shoes', 0.7),
        candidate('sneakers', 0.3),
      ],
      observations: observations,
      resolvedCanonicalSubtype: null,
    );
    expect(result.resolvedFamily, VisionIdentityFamily.sneakers);
    expect(result.subtypeResolved, isFalse);
    expect(result.toMap(), isNot(contains('traction')));
  });

  test('partial side shoe can support family but not create subtype', () {
    final observations = ClothingObservationBundle(
      analysisId: 'side-shoe',
      modelVersion: 'fixture',
      sourceReference: 'fixture://side-shoe',
      observedAt: DateTime.utc(2026),
      quality: const ObservationImageQuality(
        itemFullyVisible: false,
        clarity: ImageQualityLevel.high,
      ),
      footwearConstruction:
          const ObservationValue<FootwearConstruction>.observed(
            value: FootwearConstruction.closed,
            confidence: 0.85,
            visibilityScope: ObservationVisibilityScope.partial,
            visibleRegions: {ObservationVisualRegion.footwearUpper},
          ),
      footwearUpperHeight: const ObservationValue<FootwearUpperHeight>.observed(
        value: FootwearUpperHeight.lowCut,
        confidence: 0.8,
        visibilityScope: ObservationVisibilityScope.partial,
        visibleRegions: {ObservationVisualRegion.footwearUpper},
      ),
    );
    final result = resolver.resolve(
      identityCandidates: [candidate('running_shoes', 0.75)],
      observations: observations,
      resolvedCanonicalSubtype: null,
    );
    expect(result.resolvedFamily, VisionIdentityFamily.sneakers);
    expect(result.state, VisionFamilyResolutionState.supported);
    expect(result.subtypeResolved, isFalse);
    expect(
      result.candidates.single.confidenceComponents,
      containsPair('directFamilyEvidence', greaterThan(0)),
    );
  });

  test('family confidence distinguishes complete and partial evidence', () {
    final complete = resolver.resolve(
      identityCandidates: [candidate('t_shirt', 0.85)],
      observations: garment(),
      resolvedCanonicalSubtype: null,
    );
    final partial = resolver.resolve(
      identityCandidates: [candidate('t_shirt', 0.85)],
      observations: ClothingObservationBundle(
        analysisId: 'partial-top',
        modelVersion: 'fixture',
        sourceReference: 'fixture://partial-top',
        observedAt: DateTime.utc(2026),
        quality: const ObservationImageQuality(
          itemFullyVisible: false,
          clarity: ImageQualityLevel.high,
        ),
        coverage: const ObservationValue<GarmentCoverage>.observed(
          value: GarmentCoverage.partial,
          confidence: 0.85,
          visibilityScope: ObservationVisibilityScope.partial,
        ),
      ),
      resolvedCanonicalSubtype: null,
    );
    expect(complete.confidence, greaterThan(partial.confidence));
    expect(partial.resolvedFamily, VisionIdentityFamily.top);
  });

  test('basketball and running candidates share declared sneaker family', () {
    final observations = ClothingObservationBundle(
      analysisId: 'basketball-shoes',
      modelVersion: 'fixture',
      sourceReference: 'fixture://basketball-shoes',
      observedAt: DateTime.utc(2026),
      quality: quality,
      footwearConstruction:
          const ObservationValue<FootwearConstruction>.observed(
            value: FootwearConstruction.closed,
            confidence: 0.85,
            visibilityScope: ObservationVisibilityScope.complete,
          ),
    );
    final result = resolver.resolve(
      identityCandidates: [
        candidate('basketball_shoes', 0.85),
        candidate('running_shoes', 0.15),
      ],
      observations: observations,
      resolvedCanonicalSubtype: null,
    );
    expect(result.resolvedFamily, VisionIdentityFamily.sneakers);
    expect(result.candidates.single.canonicalCandidates, hasLength(2));
  });

  test('different candidate families do not pick raw top candidate', () {
    final result = resolver.resolve(
      identityCandidates: [
        candidate('chinos', 0.55),
        candidate('light_jacket', 0.45),
      ],
      observations: garment(),
      resolvedCanonicalSubtype: null,
    );
    expect(result.state, VisionFamilyResolutionState.ambiguous);
    expect(result.resolvedFamily, isNull);
  });

  test('mapping is declarative and deterministic', () {
    final first = resolver.resolve(
      identityCandidates: [candidate('cargo_shorts', 0.8)],
      observations: garment(),
      resolvedCanonicalSubtype: null,
    );
    final second = resolver.resolve(
      identityCandidates: [candidate('cargo_shorts', 0.8)],
      observations: garment(),
      resolvedCanonicalSubtype: null,
    );
    expect(first.toMap(), second.toMap());
    expect(
      VisionCanonicalFamilyRegistry.canonicalToFamily['cargo_shorts'],
      VisionIdentityFamily.shorts,
    );
  });

  test('cropped detail does not resolve family from candidate alone', () {
    final observations = ClothingObservationBundle(
      analysisId: 'crop',
      modelVersion: 'fixture',
      sourceReference: 'fixture://crop',
      observedAt: DateTime.utc(2026),
      quality: const ObservationImageQuality(
        itemFullyVisible: false,
        clarity: ImageQualityLevel.low,
      ),
      coverage: const ObservationValue<GarmentCoverage>.unknown(),
    );
    final result = resolver.resolve(
      identityCandidates: [candidate('t_shirt', 0.9)],
      observations: observations,
      resolvedCanonicalSubtype: null,
    );
    expect(result.state, VisionFamilyResolutionState.insufficientEvidence);
    expect(result.resolvedFamily, isNull);
  });

  test('sole-only shoe does not establish sneaker family', () {
    final observations = ClothingObservationBundle(
      analysisId: 'sole',
      modelVersion: 'fixture',
      sourceReference: 'fixture://sole',
      observedAt: DateTime.utc(2026),
      quality: quality,
      visibleTread: const ObservationValue<VisibleTread>.observed(
        value: VisibleTread.pronounced,
        confidence: 0.9,
        visibilityScope: ObservationVisibilityScope.sufficient,
        visibleRegions: {ObservationVisualRegion.outsole},
      ),
    );
    final result = resolver.resolve(
      identityCandidates: [candidate('running_shoes', 0.9)],
      observations: observations,
      resolvedCanonicalSubtype: null,
    );
    expect(result.state, VisionFamilyResolutionState.insufficientEvidence);
    expect(result.resolvedFamily, isNull);
  });

  test('non wardrobe input has explicit invalid family state', () {
    final result = resolver.resolve(
      identityCandidates: [candidate('t_shirt', 0.9)],
      observations: garment(),
      resolvedCanonicalSubtype: 't_shirt',
      inputAssessment: VisionInputAssessment.nonWardrobeObject,
    );
    expect(result.state, VisionFamilyResolutionState.invalidInput);
    expect(result.resolvedFamily, isNull);
    expect(result.subtypeResolved, isFalse);
  });
}
