import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_framing_attestation.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_subject_safety.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_visibility_trust.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

void main() {
  const subject = VisionSubjectAssessment(
    subjectCountEstimate: 1,
    cardinality: VisionSubjectCardinality.singleItemSupported,
    primarySubjectPresent: true,
    sameItemConsistency: VisionSameItemConsistency.sameItemSupported,
    subjectDomain: VisionSubjectDomain.garmentOuterwear,
    framing: VisionFramingClass.fullItem,
  );
  const full = VisionFramingAttestations(
    visibleBoundaries: {
      VisionBoundary.top,
      VisionBoundary.bottom,
      VisionBoundary.left,
      VisionBoundary.right,
    },
    primarySilhouetteContinuous: true,
    visibleItemExtent: VisionItemExtent.whole,
    localDetailOnly: false,
    cropIndicators: {},
    subjectOrientation: VisionSubjectOrientation.front,
  );
  const quality = ObservationImageQuality(
    itemFullyVisible: true,
    occlusion: ImageOcclusion.none,
    clarity: ImageQualityLevel.high,
    backgroundInterference: ImageQualityLevel.low,
  );

  test('consistent full silhouette can be system-attested full', () {
    final report = const VisionFramingAttestor().attest(
      inputAssessment: VisionInputAssessment.validSingleItem,
      subject: subject,
      quality: quality,
      attestations: full,
    );
    expect(report.systemAttestedFraming, VisionFramingClass.fullItem);
    expect(report.hasWholeItemSilhouette, isTrue);
  });

  test('model full plus local detail is downgraded and blocks silhouette', () {
    final report = const VisionFramingAttestor().attest(
      inputAssessment: VisionInputAssessment.validSingleItem,
      subject: subject,
      quality: quality,
      attestations: const VisionFramingAttestations(
        visibleBoundaries: {},
        primarySilhouetteContinuous: false,
        visibleItemExtent: VisionItemExtent.local,
        localDetailOnly: true,
        cropIndicators: {'severe_crop'},
        subjectOrientation: VisionSubjectOrientation.unknown,
      ),
    );
    expect(report.systemAttestedFraming, VisionFramingClass.detailOnly);
    expect(report.hasWholeItemSilhouette, isFalse);
    expect(
      report.contradictions,
      contains('local_detail_contradicts_declared_framing'),
    );
  });

  test('missing bottom boundary caps full framing at mostly visible', () {
    final report = const VisionFramingAttestor().attest(
      inputAssessment: VisionInputAssessment.validSingleItem,
      subject: subject,
      quality: const ObservationImageQuality(
        itemFullyVisible: false,
        occlusion: ImageOcclusion.none,
      ),
      attestations: const VisionFramingAttestations(
        visibleBoundaries: {VisionBoundary.top, VisionBoundary.left},
        primarySilhouetteContinuous: true,
        visibleItemExtent: VisionItemExtent.broad,
        localDetailOnly: false,
        cropIndicators: {'bottom_cropped'},
        subjectOrientation: VisionSubjectOrientation.front,
      ),
    );
    expect(report.systemAttestedFraming, VisionFramingClass.mostlyVisible);
    expect(report.contradictions, contains('whole_item_boundary_missing'));
  });

  test('closure none needs full positive closure-path corroboration', () {
    final framing = const VisionFramingAttestor().attest(
      inputAssessment: VisionInputAssessment.validSingleItem,
      subject: subject,
      quality: quality,
      attestations: full,
    );
    final blocked = const VisionNegativeClaimCorroborator().qualify(
      bundle: _bundle(
        frontClosure: ObservationValue.observed(
          value: FrontClosure.none,
          confidence: .9,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: const {ObservationVisualRegion.front},
        ),
      ),
      subject: subject,
      framing: framing,
    );
    expect(
      blocked.qualifiedBundle.frontClosure?.state,
      ObservationState.unknown,
    );
    expect(
      blocked.claims['frontClosure']!.missingRegions,
      contains(ObservationVisualRegion.fasteningArea),
    );
  });

  test('clear full front closure path may corroborate none', () {
    final framing = const VisionFramingAttestor().attest(
      inputAssessment: VisionInputAssessment.validSingleItem,
      subject: subject,
      quality: quality,
      attestations: full,
    );
    final report = const VisionNegativeClaimCorroborator().qualify(
      bundle: _bundle(
        frontClosure: ObservationValue.observed(
          value: FrontClosure.none,
          confidence: .85,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: const {
            ObservationVisualRegion.front,
            ObservationVisualRegion.fasteningArea,
          },
        ),
      ),
      subject: subject,
      framing: framing,
    );
    expect(report.qualifiedBundle.frontClosure?.value, FrontClosure.none);
    expect(
      report.claims['frontClosure']!.state,
      NegativeClaimCorroborationState.corroborated,
    );
  });

  test('trousers closure none is blocked by domain-aware policy', () {
    final lower = VisionSubjectAssessment(
      subjectCountEstimate: 1,
      cardinality: VisionSubjectCardinality.singleItemSupported,
      primarySubjectPresent: true,
      sameItemConsistency: VisionSameItemConsistency.sameItemSupported,
      subjectDomain: VisionSubjectDomain.garmentLower,
      framing: VisionFramingClass.fullItem,
    );
    final framing = const VisionFramingAttestor().attest(
      inputAssessment: VisionInputAssessment.validSingleItem,
      subject: lower,
      quality: quality,
      attestations: full,
    );
    final report = const VisionNegativeClaimCorroborator().qualify(
      bundle: _bundle(
        frontClosure: ObservationValue.observed(
          value: FrontClosure.none,
          confidence: .95,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: const {
            ObservationVisualRegion.front,
            ObservationVisualRegion.fasteningArea,
          },
        ),
      ),
      subject: lower,
      framing: framing,
    );
    expect(
      report.qualifiedBundle.frontClosure?.state,
      ObservationState.unknown,
    );
  });

  test('stretch false remains unconfirmable', () {
    final framing = const VisionFramingAttestor().attest(
      inputAssessment: VisionInputAssessment.validSingleItem,
      subject: subject,
      quality: quality,
      attestations: full,
    );
    final report = const VisionNegativeClaimCorroborator().qualify(
      bundle: _bundle(
        stretch: ObservationValue.observed(
          value: false,
          confidence: .95,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: const {ObservationVisualRegion.surfaceDetail},
        ),
      ),
      subject: subject,
      framing: framing,
    );
    expect(
      report.qualifiedBundle.visibleStretchCue?.state,
      ObservationState.unknown,
    );
  });

  test('complementary same-item views can corroborate pocket absence', () {
    final mixed = VisionFramingAttestations(
      visibleBoundaries: full.visibleBoundaries,
      primarySilhouetteContinuous: true,
      visibleItemExtent: VisionItemExtent.whole,
      localDetailOnly: false,
      cropIndicators: const {},
      subjectOrientation: VisionSubjectOrientation.mixed,
    );
    final framing = const VisionFramingAttestor().attest(
      inputAssessment: VisionInputAssessment.validSingleItem,
      subject: subject,
      quality: quality,
      attestations: mixed,
    );
    final report = const VisionNegativeClaimCorroborator().qualify(
      bundle: ClothingObservationBundle(
        analysisId: 'pocket',
        modelVersion: 'test',
        sourceReference: 'test',
        observedAt: _date,
        quality: quality,
        visiblePocketStructure: ObservationValue.observed(
          value: VisiblePocketStructure.none,
          confidence: .8,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: {
            ObservationVisualRegion.front,
            ObservationVisualRegion.pocketArea,
          },
        ),
      ),
      subject: subject,
      framing: framing,
      viewCount: 2,
      complementaryRegions: {
        'visiblePocketStructure': {
          ObservationVisualRegion.side,
          ObservationVisualRegion.back,
        },
      },
    );
    expect(
      report.claims['visiblePocketStructure']?.state,
      NegativeClaimCorroborationState.corroborated,
    );
  });

  test('different-item views cannot corroborate pocket absence', () {
    final mixed = VisionFramingAttestations(
      visibleBoundaries: full.visibleBoundaries,
      primarySilhouetteContinuous: true,
      visibleItemExtent: VisionItemExtent.whole,
      localDetailOnly: false,
      cropIndicators: const {},
      subjectOrientation: VisionSubjectOrientation.mixed,
    );
    final framing = const VisionFramingAttestor().attest(
      inputAssessment: VisionInputAssessment.validSingleItem,
      subject: subject,
      quality: quality,
      attestations: mixed,
    );
    final report = const VisionNegativeClaimCorroborator().qualify(
      bundle: ClothingObservationBundle(
        analysisId: 'pocket',
        modelVersion: 'test',
        sourceReference: 'test',
        observedAt: _date,
        quality: quality,
        visiblePocketStructure: ObservationValue.observed(
          value: VisiblePocketStructure.none,
          confidence: .8,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: {
            ObservationVisualRegion.front,
            ObservationVisualRegion.side,
            ObservationVisualRegion.back,
            ObservationVisualRegion.pocketArea,
          },
        ),
      ),
      subject: subject,
      framing: framing,
      viewCount: 2,
      sameItemViews: false,
    );
    expect(
      report.qualifiedBundle.visiblePocketStructure?.state,
      ObservationState.unknown,
    );
  });

  test('positive evidence conflicts with a negative claim', () {
    final framing = const VisionFramingAttestor().attest(
      inputAssessment: VisionInputAssessment.validSingleItem,
      subject: subject,
      quality: quality,
      attestations: full,
    );
    final report = const VisionNegativeClaimCorroborator().qualify(
      bundle: _bundle(
        frontClosure: ObservationValue.observed(
          value: FrontClosure.none,
          confidence: .8,
          visibilityScope: ObservationVisibilityScope.complete,
          visibleRegions: {
            ObservationVisualRegion.front,
            ObservationVisualRegion.fasteningArea,
          },
        ),
      ),
      subject: subject,
      framing: framing,
      conflictingPositiveProperties: {'frontClosure'},
    );
    expect(
      report.claims['frontClosure']?.state,
      NegativeClaimCorroborationState.conflicting,
    );
    expect(
      report.qualifiedBundle.frontClosure?.state,
      ObservationState.unknown,
    );
  });
}

final _date = DateTime.utc(2026);

ClothingObservationBundle _bundle({
  ObservationValue<FrontClosure>? frontClosure,
  ObservationValue<bool>? stretch,
}) => ClothingObservationBundle(
  analysisId: 'test-analysis',
  modelVersion: 'test-model',
  sourceReference: 'test-source',
  observedAt: DateTime.utc(2026),
  quality: const ObservationImageQuality(
    itemFullyVisible: true,
    occlusion: ImageOcclusion.none,
    clarity: ImageQualityLevel.high,
    backgroundInterference: ImageQualityLevel.low,
  ),
  frontClosure: frontClosure,
  visibleStretchCue: stretch,
);
