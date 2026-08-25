import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/data/clothing_knowledge_base.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_subject_safety.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

Set<String> get _allowed =>
    ClothingKnowledgeBase.allItems.map((item) => item.canonicalType).toSet();

void main() {
  const replay = VisionParserFixtureReplay();

  test('missing binding decodes as undeclared fail-closed', () {
    final fixture = File(
      'test/fixtures/backend_qualification/parser/front_only_garment.parser.json',
    ).readAsStringSync();
    final binding = replay.decodeBinding(fixture);
    expect(
      binding.physicalIdentityClaim,
      VisionMultiViewPhysicalIdentityClaim.undeclared,
    );
    final analysis = replay.replayQualification(
      fixture,
      fixtureId: 'front_only_garment',
      allowedCanonicalTypes: _allowed,
    );
    expect(analysis.multiPhotoAssessment.sameItemViews, isTrue);
    expect(
      analysis.multiPhotoAssessment.binding.physicalIdentityClaim,
      VisionMultiViewPhysicalIdentityClaim.undeclared,
    );
  });

  test('complementary_multi_view binding enables sameItemViews', () {
    final fixture = File(
      'test/fixtures/backend_qualification/parser/'
      'complementary_multi_view.parser.json',
    ).readAsStringSync();
    final binding = replay.decodeBinding(fixture);
    expect(
      binding.physicalIdentityClaim,
      VisionMultiViewPhysicalIdentityClaim.samePhysicalItem,
    );
    final trace = _NegativeClaimTrace();
    final responses = replay.decodeResponses(
      fixture,
      allowedCanonicalTypes: _allowed,
    );
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'complementary_multi_view',
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      negativeClaimCorroborationTraceSink: trace,
    );
    expect(
      analysis.multiPhotoAssessment.physicalIdentity,
      VisionMultiPhotoConsistency.sameItemSupported,
    );
    expect(
      analysis.multiPhotoAssessment.semanticAgreement,
      VisionMultiPhotoSemanticAgreement.consistent,
    );
    expect(analysis.multiPhotoAssessment.sameItemViews, isTrue);
    expect(analysis.multiPhotoAssessment.permitsIdentityPromotion, isTrue);
    expect(analysis.identityQualification.selectedCanonicalType, isNull);
    expect(trace.inputs, hasLength(2));
    expect(
      trace.inputs.every((input) => input['sameItemViews'] == true),
      isTrue,
    );
  });

  test('conflicting_multi_view binding keeps sameItemViews false', () {
    final fixture = File(
      'test/fixtures/backend_qualification/parser/'
      'conflicting_multi_view.parser.json',
    ).readAsStringSync();
    final analysis = replay.replayQualification(
      fixture,
      fixtureId: 'conflicting_multi_view',
      allowedCanonicalTypes: _allowed,
    );
    expect(
      analysis.multiPhotoAssessment.physicalIdentity,
      VisionMultiPhotoConsistency.conflictingSubjects,
    );
    expect(analysis.multiPhotoAssessment.sameItemViews, isFalse);
    expect(analysis.multiPhotoAssessment.permitsIdentityPromotion, isFalse);
  });

  test('fixture binding invalid version fails decode', () {
    final root =
        jsonDecode(
              File(
                'test/fixtures/backend_qualification/parser/'
                'front_only_garment.parser.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    root['multiViewSubjectBinding'] = {
      'contractVersion': 99,
      'physicalIdentityClaim': 'same_physical_item',
      'source': 'unknown',
    };
    expect(() => replay.decodeBinding(jsonEncode(root)), throwsFormatException);
  });
}

final class _NegativeClaimTrace
    implements VisionNegativeClaimCorroborationTraceSink {
  final inputs = <Map<String, Object?>>[];

  @override
  void beforeInvocation({
    required int viewIndex,
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
    required framing,
    required int viewCount,
    required bool sameItemViews,
    required Map complementaryRegions,
    required Set conflictingPositiveProperties,
  }) {
    inputs.add({'sameItemViews': sameItemViews, 'viewIndex': viewIndex});
  }

  @override
  void afterInvocation({
    required int viewIndex,
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
    required framing,
    required int viewCount,
    required bool sameItemViews,
    required Map complementaryRegions,
    required Set conflictingPositiveProperties,
    required output,
  }) {}
}
