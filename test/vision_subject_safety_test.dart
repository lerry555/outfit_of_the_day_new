import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_subject_safety.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

void main() {
  const qualifier = VisionPropertyApplicabilityQualifier();

  VisionSubjectAssessment subject({
    VisionSubjectDomain domain = VisionSubjectDomain.garmentUpper,
    VisionFramingClass framing = VisionFramingClass.fullItem,
    VisionSubjectCardinality cardinality =
        VisionSubjectCardinality.singleItemSupported,
    VisionSameItemConsistency? sameItemConsistency,
  }) => VisionSubjectAssessment(
    subjectCountEstimate: cardinality == VisionSubjectCardinality.multipleItems
        ? 2
        : 1,
    cardinality: cardinality,
    primarySubjectPresent: true,
    sameItemConsistency:
        sameItemConsistency ??
        (cardinality == VisionSubjectCardinality.singleItemSupported
            ? VisionSameItemConsistency.sameItemSupported
            : VisionSameItemConsistency.differentItemsSuspected),
    subjectDomain: domain,
    framing: framing,
  );

  ClothingObservationBundle bundle({
    ObservationValue<FrontClosure>? closure,
    ObservationValue<NecklineShape>? neckline,
    ObservationValue<VisibleTread>? tread,
    ObservationValue<bool>? hood,
    ObservationValue<FootwearFastening>? fastening,
  }) => ClothingObservationBundle(
    analysisId: 'subject-fixture',
    modelVersion: 'fixture',
    sourceReference: 'fixture://subject',
    observedAt: DateTime.utc(2026),
    quality: const ObservationImageQuality(),
    frontClosure: closure,
    necklineShape: neckline,
    visibleTread: tread,
    hasHood: hood,
    footwearFastening: fastening,
  );

  test('footwear rejects garment closure and neckline', () {
    final result = qualifier.qualify(
      bundle: bundle(
        closure: const ObservationValue.observed(
          value: FrontClosure.none,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.complete,
        ),
        neckline: const ObservationValue.observed(
          value: NecklineShape.crew,
          confidence: 0.9,
        ),
      ),
      subject: subject(domain: VisionSubjectDomain.footwear),
    );
    expect(
      result.qualifiedBundle.frontClosure!.state,
      ObservationState.notApplicable,
    );
    expect(
      result.qualifiedBundle.necklineShape!.state,
      ObservationState.notApplicable,
    );
  });

  test('garment rejects footwear observations', () {
    final result = qualifier.qualify(
      bundle: bundle(
        tread: const ObservationValue.observed(
          value: VisibleTread.pronounced,
          confidence: 0.9,
        ),
        fastening: const ObservationValue.observed(
          value: FootwearFastening.laces,
          confidence: 0.9,
        ),
      ),
      subject: subject(),
    );
    expect(
      result.qualifiedBundle.visibleTread!.state,
      ObservationState.notApplicable,
    );
    expect(
      result.qualifiedBundle.footwearFastening!.state,
      ObservationState.notApplicable,
    );
  });

  test('lower garment rejects hood', () {
    final result = qualifier.qualify(
      bundle: bundle(
        hood: const ObservationValue.observed(value: false, confidence: 0.95),
      ),
      subject: subject(domain: VisionSubjectDomain.garmentLower),
    );
    expect(
      result.qualifiedBundle.hasHood!.state,
      ObservationState.notApplicable,
    );
  });

  test('mixed domain cannot authorize domain-specific evidence', () {
    final result = qualifier.qualify(
      bundle: bundle(
        closure: const ObservationValue.observed(
          value: FrontClosure.fullZip,
          confidence: 0.9,
        ),
        tread: const ObservationValue.observed(
          value: VisibleTread.moderate,
          confidence: 0.9,
        ),
      ),
      subject: subject(domain: VisionSubjectDomain.mixed),
    );
    expect(
      result.qualifiedBundle.frontClosure!.state,
      ObservationState.notApplicable,
    );
    expect(
      result.qualifiedBundle.visibleTread!.state,
      ObservationState.notApplicable,
    );
  });

  test('framing policy separates family and canonical authority', () {
    expect(subject().permitsFamily, isTrue);
    expect(subject().permitsCanonical, isTrue);
    expect(
      subject(framing: VisionFramingClass.partialItem).permitsFamily,
      isTrue,
    );
    expect(
      subject(framing: VisionFramingClass.partialItem).permitsCanonical,
      isFalse,
    );
    expect(
      subject(framing: VisionFramingClass.detailOnly).permitsFamily,
      isFalse,
    );
  });

  test('hard domain mismatch is semantic conflict, not automatic physical', () {
    final result = assessMultiPhotoConsistency([
      subject(domain: VisionSubjectDomain.garmentUpper),
      subject(domain: VisionSubjectDomain.footwear),
    ]);
    expect(
      result.physicalIdentity,
      VisionMultiPhotoConsistency.sameItemUncertain,
    );
    expect(
      result.semanticAgreement,
      VisionMultiPhotoSemanticAgreement.conflicting,
    );
    expect(result.sameItemViews, isFalse);
  });

  test('complementary same-domain subjects stay undeclared fail-closed', () {
    final result = assessMultiPhotoConsistency([
      subject(),
      subject(framing: VisionFramingClass.mostlyVisible),
    ]);
    expect(
      result.physicalIdentity,
      VisionMultiPhotoConsistency.sameItemUncertain,
    );
    expect(
      result.semanticAgreement,
      VisionMultiPhotoSemanticAgreement.consistent,
    );
    expect(result.sameItemViews, isFalse);
  });

  test('samePhysicalItem with soft domain keeps physical same', () {
    final result = assessMultiPhotoConsistency(
      [
        subject(domain: VisionSubjectDomain.garmentOuterwear),
        subject(domain: VisionSubjectDomain.garmentUpper),
      ],
      binding: const VisionMultiViewSubjectBinding(
        physicalIdentityClaim:
            VisionMultiViewPhysicalIdentityClaim.samePhysicalItem,
        source: VisionMultiViewSubjectBindingSource.captureDeclaration,
      ),
    );
    expect(
      result.physicalIdentity,
      VisionMultiPhotoConsistency.sameItemSupported,
    );
    expect(
      result.semanticAgreement,
      VisionMultiPhotoSemanticAgreement.compatible,
    );
    expect(result.sameItemViews, isTrue);
    expect(result.permitsIdentityPromotion, isFalse);
  });

  test('samePhysicalItem with hard semantic conflict keeps physical same', () {
    final result = assessMultiPhotoConsistency(
      [
        subject(domain: VisionSubjectDomain.garmentUpper),
        subject(domain: VisionSubjectDomain.footwear),
      ],
      binding: const VisionMultiViewSubjectBinding(
        physicalIdentityClaim:
            VisionMultiViewPhysicalIdentityClaim.samePhysicalItem,
        source: VisionMultiViewSubjectBindingSource.userItemUploadIntent,
      ),
    );
    expect(
      result.physicalIdentity,
      VisionMultiPhotoConsistency.sameItemSupported,
    );
    expect(
      result.semanticAgreement,
      VisionMultiPhotoSemanticAgreement.conflicting,
    );
    expect(result.sameItemViews, isTrue);
    expect(result.permitsIdentityPromotion, isFalse);
  });

  test(
    'differentPhysicalItems blocks sameItemViews even when domains match',
    () {
      final result = assessMultiPhotoConsistency(
        [subject(), subject()],
        binding: const VisionMultiViewSubjectBinding(
          physicalIdentityClaim:
              VisionMultiViewPhysicalIdentityClaim.differentPhysicalItems,
          source: VisionMultiViewSubjectBindingSource.assetManifestRelationship,
        ),
      );
      expect(
        result.physicalIdentity,
        VisionMultiPhotoConsistency.conflictingSubjects,
      );
      expect(
        result.semanticAgreement,
        VisionMultiPhotoSemanticAgreement.consistent,
      );
      expect(result.sameItemViews, isFalse);
    },
  );

  test('same domain undeclared never becomes samePhysicalItem', () {
    final result = assessMultiPhotoConsistency([subject(), subject()]);
    expect(
      result.binding.physicalIdentityClaim,
      VisionMultiViewPhysicalIdentityClaim.undeclared,
    );
    expect(
      result.physicalIdentity,
      VisionMultiPhotoConsistency.sameItemUncertain,
    );
    expect(result.sameItemViews, isFalse);
  });

  test('cardinality veto wins over samePhysicalItem binding', () {
    final result = assessMultiPhotoConsistency(
      [subject(cardinality: VisionSubjectCardinality.multipleItems), subject()],
      binding: const VisionMultiViewSubjectBinding(
        physicalIdentityClaim:
            VisionMultiViewPhysicalIdentityClaim.samePhysicalItem,
        source: VisionMultiViewSubjectBindingSource.userItemUploadIntent,
      ),
    );
    expect(
      result.physicalIdentity,
      VisionMultiPhotoConsistency.differentItemsSuspected,
    );
    expect(result.sameItemViews, isFalse);
  });

  test('invalid binding version fails closed on decode', () {
    expect(
      () => VisionMultiViewSubjectBinding.fromMap({
        'contractVersion': 2,
        'physicalIdentityClaim': 'same_physical_item',
        'source': 'unknown',
      }),
      throwsFormatException,
    );
  });

  test('invalid binding enum fails closed on decode', () {
    expect(
      () => VisionMultiViewSubjectBinding.fromMap({
        'contractVersion': 1,
        'physicalIdentityClaim': 'maybe_same',
        'source': 'unknown',
      }),
      throwsArgumentError,
    );
  });

  test('missing binding map field defaults stay undeclared constant', () {
    expect(
      VisionMultiViewSubjectBinding.undeclared.physicalIdentityClaim,
      VisionMultiViewPhysicalIdentityClaim.undeclared,
    );
  });
}
