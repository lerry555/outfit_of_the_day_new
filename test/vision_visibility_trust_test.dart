import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/observation_absence_qualifier.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_visibility_trust.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

void main() {
  const qualifier = VisionVisibilityTrustQualifier();

  ClothingObservationBundle bundle({
    ObservationImageQuality quality = const ObservationImageQuality(
      itemFullyVisible: true,
      occlusion: ImageOcclusion.none,
      backgroundInterference: ImageQualityLevel.low,
      clarity: ImageQualityLevel.high,
    ),
    ObservationValue<VisiblePocketStructure>? pockets,
    ObservationValue<bool>? hood,
    ObservationValue<FrontClosure>? closure,
    ObservationValue<bool>? stretch,
    ObservationValue<NecklineShape>? neckline,
    ObservationValue<VisibleTread>? tread,
    ObservationValue<FootwearUpperHeight>? upperHeight,
  }) => ClothingObservationBundle(
    analysisId: 'visibility-fixture',
    modelVersion: 'fixture',
    sourceReference: 'fixture://visibility',
    observedAt: DateTime.utc(2026),
    quality: quality,
    visiblePocketStructure: pockets,
    hasHood: hood,
    frontClosure: closure,
    visibleStretchCue: stretch,
    necklineShape: neckline,
    visibleTread: tread,
    footwearUpperHeight: upperHeight,
  );

  test('front-only pants complete pocket claim is downgraded', () {
    final result = qualifier.qualify(
      bundle: bundle(
        pockets: const ObservationValue.observed(
          value: VisiblePocketStructure.none,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: {
            ObservationVisualRegion.front,
            ObservationVisualRegion.pocketArea,
          },
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );

    final audit = result.properties['visiblePocketStructure']!;
    expect(audit.modelDeclaredScope, ObservationVisibilityScope.complete);
    expect(audit.systemQualifiedScope, ObservationVisibilityScope.partial);
    expect(audit.reasonCodes, contains('absence_requires_complementary_views'));
    expect(
      result.qualifiedBundle.visiblePocketStructure!.state,
      ObservationState.unknown,
    );
  });

  test('complementary pants views can support pocket absence', () {
    const pocketNone = ObservationValue<VisiblePocketStructure>.observed(
      value: VisiblePocketStructure.none,
      confidence: 0.9,
      visibilityScope: ObservationVisibilityScope.complete,
      visibleRegions: {
        ObservationVisualRegion.front,
        ObservationVisualRegion.pocketArea,
      },
    );
    const complementary = {
      'visiblePocketStructure': {
        ObservationVisualRegion.front,
        ObservationVisualRegion.side,
        ObservationVisualRegion.pocketArea,
      },
    };
    final first = qualifier.qualify(
      bundle: bundle(pockets: pocketNone),
      inputAssessment: VisionInputAssessment.validSingleItem,
      viewCount: 2,
      complementaryRegions: complementary,
    );
    final second = qualifier.qualify(
      bundle: bundle(
        pockets: const ObservationValue.observed(
          value: VisiblePocketStructure.none,
          confidence: 0.85,
          visibilityScope: ObservationVisibilityScope.sufficient,
          visibleRegions: {
            ObservationVisualRegion.side,
            ObservationVisualRegion.pocketArea,
          },
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
      viewCount: 2,
      complementaryRegions: complementary,
    );
    final absence = const ObservationAbsenceQualifier().qualifyBundles([
      first.qualifiedBundle,
      second.qualifiedBundle,
    ]);
    expect(
      absence.qualifiedBundle.visiblePocketStructure!.value,
      VisiblePocketStructure.none,
    );
  });

  test('sufficient pocket absence does not meet complete absence minimum', () {
    final result = qualifier.qualify(
      bundle: bundle(
        pockets: const ObservationValue.observed(
          value: VisiblePocketStructure.none,
          confidence: 0.9,
          visibilityScope: ObservationVisibilityScope.sufficient,
          visibleRegions: {
            ObservationVisualRegion.front,
            ObservationVisualRegion.side,
            ObservationVisualRegion.pocketArea,
          },
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
      viewCount: 2,
      complementaryRegions: const {
        'visiblePocketStructure': {
          ObservationVisualRegion.front,
          ObservationVisualRegion.side,
          ObservationVisualRegion.pocketArea,
        },
      },
    );

    final audit = result.properties['visiblePocketStructure']!;
    expect(
      audit.reasonCodes,
      contains('qualified_scope_below_property_minimum'),
    );
    expect(
      result.qualifiedBundle.visiblePocketStructure!.state,
      ObservationState.unknown,
    );
  });

  test('side-only shoe can expose upper but not tread', () {
    final result = qualifier.qualify(
      bundle: bundle(
        upperHeight: const ObservationValue.observed(
          value: FootwearUpperHeight.ankle,
          confidence: 0.85,
          visibilityScope: ObservationVisibilityScope.sufficient,
          visibleRegions: {
            ObservationVisualRegion.side,
            ObservationVisualRegion.footwearUpper,
          },
        ),
        tread: const ObservationValue.observed(
          value: VisibleTread.pronounced,
          confidence: 0.9,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: {ObservationVisualRegion.side},
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    expect(
      result.qualifiedBundle.footwearUpperHeight!.value,
      FootwearUpperHeight.ankle,
    );
    expect(
      result.qualifiedBundle.visibleTread!.state,
      ObservationState.unknown,
    );
  });

  test('sole-only view can expose tread', () {
    final result = qualifier.qualify(
      bundle: bundle(
        tread: const ObservationValue.observed(
          value: VisibleTread.pronounced,
          confidence: 0.9,
          visibilityScope: ObservationVisibilityScope.sufficient,
          visibleRegions: {ObservationVisualRegion.outsole},
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    expect(result.qualifiedBundle.visibleTread!.value, VisibleTread.pronounced);
  });

  test('cropped neckline without neckline region becomes unknown', () {
    final result = qualifier.qualify(
      bundle: bundle(
        quality: const ObservationImageQuality(
          itemFullyVisible: false,
          clarity: ImageQualityLevel.high,
        ),
        neckline: const ObservationValue.observed(
          value: NecklineShape.vNeck,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: {ObservationVisualRegion.surfaceDetail},
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    expect(
      result.qualifiedBundle.necklineShape!.state,
      ObservationState.unknown,
    );
  });

  test('visible hood remains usable on a cropped garment', () {
    final result = qualifier.qualify(
      bundle: bundle(
        quality: const ObservationImageQuality(itemFullyVisible: false),
        hood: const ObservationValue.observed(
          value: true,
          confidence: 0.9,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: {
            ObservationVisualRegion.collar,
            ObservationVisualRegion.back,
          },
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    expect(result.qualifiedBundle.hasHood!.value, isTrue);
    expect(
      result.properties['hasHood']!.systemQualifiedScope,
      ObservationVisibilityScope.sufficient,
    );
  });

  test('positive hood safely implies an undeclared collar region', () {
    final result = qualifier.qualify(
      bundle: bundle(
        hood: const ObservationValue.observed(
          value: true,
          confidence: 0.9,
          visibilityScope: ObservationVisibilityScope.sufficient,
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    final audit = result.properties['hasHood']!;
    expect(result.qualifiedBundle.hasHood!.value, isTrue);
    expect(
      audit.regionDeclarationState,
      RegionDeclarationState.impliedByPositiveObservation,
    );
    expect(audit.impliedRegions, contains(ObservationVisualRegion.collar));
    expect(audit.reasonCodes, contains('positive_observation_implies_region'));
  });

  test('positive V-neck safely implies an undeclared neckline region', () {
    final result = qualifier.qualify(
      bundle: bundle(
        neckline: const ObservationValue.observed(
          value: NecklineShape.vNeck,
          confidence: 0.9,
          visibilityScope: ObservationVisibilityScope.sufficient,
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    expect(result.qualifiedBundle.necklineShape!.value, NecklineShape.vNeck);
    expect(
      result.properties['necklineShape']!.impliedRegions,
      contains(ObservationVisualRegion.neckline),
    );
  });

  test('positive zipper safely implies front region', () {
    final result = qualifier.qualify(
      bundle: bundle(
        closure: const ObservationValue.observed(
          value: FrontClosure.fullZip,
          confidence: 0.9,
          visibilityScope: ObservationVisibilityScope.sufficient,
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    expect(result.qualifiedBundle.frontClosure!.value, FrontClosure.fullZip);
    expect(
      result.properties['frontClosure']!.impliedRegions,
      contains(ObservationVisualRegion.front),
    );
  });

  test('negative observations never imply missing regions', () {
    final hood = qualifier.qualify(
      bundle: bundle(
        hood: const ObservationValue.observed(
          value: false,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.complete,
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    final pockets = qualifier.qualify(
      bundle: bundle(
        pockets: const ObservationValue.observed(
          value: VisiblePocketStructure.none,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.complete,
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    expect(hood.properties['hasHood']!.impliedRegions, isEmpty);
    expect(hood.qualifiedBundle.hasHood!.state, ObservationState.unknown);
    expect(
      pockets.properties['visiblePocketStructure']!.impliedRegions,
      isEmpty,
    );
    expect(
      pockets.qualifiedBundle.visiblePocketStructure!.state,
      ObservationState.unknown,
    );
  });

  test('hood absence from front-only view is rejected', () {
    final result = qualifier.qualify(
      bundle: bundle(
        hood: const ObservationValue.observed(
          value: false,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: {ObservationVisualRegion.front},
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    expect(result.qualifiedBundle.hasHood!.state, ObservationState.unknown);
  });

  test('partial front crop cannot establish closure absence', () {
    final result = qualifier.qualify(
      bundle: bundle(
        closure: const ObservationValue.observed(
          value: FrontClosure.none,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.partial,
          visibleRegions: {ObservationVisualRegion.front},
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    expect(
      result.qualifiedBundle.frontClosure!.state,
      ObservationState.unknown,
    );
  });

  test('stretch absence remains unknown even with declared complete scope', () {
    final result = qualifier.qualify(
      bundle: bundle(
        stretch: const ObservationValue.observed(
          value: false,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: {ObservationVisualRegion.surfaceDetail},
        ),
      ),
      inputAssessment: VisionInputAssessment.validSingleItem,
    );
    expect(
      result.qualifiedBundle.visibleStretchCue!.state,
      ObservationState.unknown,
    );
  });

  test('invalid input rejects otherwise observed properties', () {
    final result = qualifier.qualify(
      bundle: bundle(
        hood: const ObservationValue.observed(
          value: true,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: {ObservationVisualRegion.back},
        ),
      ),
      inputAssessment: VisionInputAssessment.nonWardrobeObject,
    );
    expect(result.qualifiedBundle.hasHood!.state, ObservationState.unknown);
    expect(result.properties['hasHood']!.trust, VisibilityTrust.rejected);
  });
}
