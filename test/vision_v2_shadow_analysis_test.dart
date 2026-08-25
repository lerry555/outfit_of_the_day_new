import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/data/clothing_knowledge_base.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_subject_safety.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

const allowed = {
  'hoodie',
  'sweater',
  't_shirt',
  'v_neck_t_shirt',
  'puffer_jacket',
  'chinos',
  'sneakers',
  'running_shoes',
  'basketball_shoes',
  'shorts',
  'cargo_shorts',
  'track_jacket',
  'hiking_jacket',
};

Map<String, Object?> observation(
  String state, {
  Object? value,
  double confidence = 0,
  String? visibilityScope,
}) {
  final result = <String, Object?>{
    'state': state,
    if (state == 'observed') 'value': value,
    'confidence': confidence,
  };
  if (visibilityScope != null) {
    result['visibilityScope'] = visibilityScope;
  }
  return result;
}

Map<String, Object?> fixture({
  List<Map<String, Object?>> candidates = const [
    {'canonicalType': 'hoodie', 'confidence': 0.72},
    {'canonicalType': 'sweater', 'confidence': 0.28},
  ],
}) => {
  'schemaVersion': 3,
  'analysisId': 'analysis-1',
  'modelVersion': 'gpt-4o-mini',
  'sourceReference': 'fixture://hoodie',
  'observedAt': '2026-07-27T10:00:00.000Z',
  'quality': {
    'itemFullyVisible': true,
    'occlusion': 'none',
    'backgroundInterference': 'low',
    'clarity': 'high',
  },
  'observations': {
    'coverage': observation('observed', value: 'full', confidence: 0.9),
    'hasHood': observation('observed', value: true, confidence: 0.95),
    'frontClosure': observation('observed', value: 'full_zip', confidence: 0.9),
    'visibleBulk': observation('observed', value: 'medium', confidence: 0.8),
    'surfaceAppearance': observation(
      'observed',
      value: 'fleece_like',
      confidence: 0.8,
    ),
    'necklineShape': observation('observed', value: 'crew', confidence: 0.85),
    'visiblePocketStructure': observation('not_applicable', confidence: 1),
    'visibleStretchCue': observation('not_visible'),
    'sportyCues': observation('observed', value: 'medium', confidence: 0.8),
    'formalCues': observation('observed', value: 'low', confidence: 0.8),
    'footwearConstruction': observation('not_applicable', confidence: 1),
    'footwearFastening': observation('not_applicable', confidence: 1),
    'soleProfile': observation('not_applicable', confidence: 1),
    'visibleTread': observation('not_applicable', confidence: 1),
    'footwearUpperHeight': observation('not_applicable', confidence: 1),
  },
  'identityCandidates': candidates
      .map(
        (candidate) => {
          ...candidate,
          'supportingObservations':
              candidate['supportingObservations'] ??
              const ['hasHood', 'frontClosure'],
        },
      )
      .toList(),
  'directInferences': <String, Object?>{},
  'validationErrors': <String>[],
  'diagnostics': {
    'latencyMs': 850,
    'modelCallCount': 1,
    'inputPayloadBytes': 4200,
    'outputPayloadBytes': 1500,
    'observationFieldCount': 12,
  },
};

Map<String, Object?> v5Fixture({
  required List<Map<String, Object?>> candidates,
}) {
  final raw = fixture(candidates: candidates);
  raw['schemaVersion'] = 5;
  raw['identityCandidates'] = candidates;
  return raw;
}

Map<String, Object?> v6Fixture({
  required List<Map<String, Object?>> candidates,
}) {
  final raw = v5Fixture(candidates: candidates);
  raw['schemaVersion'] = 6;
  final observations = raw['observations']! as Map<String, Object?>;
  for (final entry in observations.entries.toList()) {
    final value = Map<String, Object?>.from(entry.value! as Map);
    value['visibilityScope'] = value['state'] == 'not_visible'
        ? 'not_visible'
        : 'complete';
    observations[entry.key] = value;
  }
  return raw;
}

Map<String, Object?> v7Fixture({
  required List<Map<String, Object?>> candidates,
  String inputAssessment = 'valid_single_item',
}) {
  final raw = v6Fixture(candidates: candidates);
  raw['schemaVersion'] = 7;
  raw['inputAssessment'] = inputAssessment;
  final observations = raw['observations']! as Map<String, Object?>;
  const regions = {
    'coverage': ['full_silhouette'],
    'hasHood': ['collar', 'back'],
    'frontClosure': ['front'],
    'visibleBulk': ['full_silhouette'],
    'surfaceAppearance': ['surface_detail'],
    'necklineShape': ['neckline'],
    'visiblePocketStructure': ['front', 'side', 'pocket_area'],
    'visibleStretchCue': ['surface_detail'],
    'sportyCues': ['full_silhouette'],
    'formalCues': ['full_silhouette'],
    'footwearConstruction': ['footwear_upper'],
    'footwearFastening': ['fastening_area'],
    'soleProfile': ['sole_profile', 'side'],
    'visibleTread': ['outsole'],
    'footwearUpperHeight': ['footwear_upper', 'side'],
  };
  for (final entry in observations.entries.toList()) {
    final value = Map<String, Object?>.from(entry.value! as Map);
    value['visibleRegions'] = regions[entry.key] ?? const <String>[];
    observations[entry.key] = value;
  }
  return raw;
}

Map<String, Object?> v9Fixture({
  required List<Map<String, Object?>> candidates,
  String framing = 'full_item',
  bool localDetailOnly = false,
  String extent = 'whole',
  bool silhouetteContinuous = true,
}) {
  final raw = v7Fixture(candidates: candidates);
  raw['schemaVersion'] = 9;
  raw['subjectAssessment'] = {
    'subjectCountEstimate': 1,
    'cardinalityState': 'single_item_supported',
    'primarySubjectPresent': true,
    'sameItemConsistency': 'same_item_supported',
    'subjectDomain': 'garment_upper',
    'framingClass': framing,
    'framingAttestations': {
      'visibleBoundaries': localDetailOnly
          ? <String>[]
          : ['top', 'bottom', 'left', 'right'],
      'primarySilhouetteContinuous': silhouetteContinuous,
      'visibleItemExtent': extent,
      'localDetailOnly': localDetailOnly,
      'cropIndicators': localDetailOnly ? ['severe_crop'] : <String>[],
      'subjectOrientation': 'front',
    },
    'reasonCodes': <String>[],
  };
  return raw;
}

void main() {
  test('valid response parses with multiple identity candidates', () {
    final result = VisionV2ShadowResponse.fromMap(
      fixture(),
      allowedCanonicalTypes: allowed,
    );
    expect(result.identityCandidates, hasLength(2));
    expect(result.observations.hasHood!.value, isTrue);
    expect(result.diagnostics.modelCallCount, 1);
  });

  test(
    'schema v9 local detail blocks family and canonical despite full claim',
    () {
      final raw = v9Fixture(
        candidates: const [
          {
            'canonicalType': 't_shirt',
            'confidence': .9,
            'definingObservations': ['necklineShape'],
            'supportingObservations': ['surfaceAppearance'],
          },
        ],
        localDetailOnly: true,
        extent: 'local',
        silhouetteContinuous: false,
      );
      final response = VisionV2ShadowResponse.fromMap(
        raw,
        allowedCanonicalTypes: allowed,
      );
      final analysis = const VisionV2ShadowOrchestrator().analyze(
        itemId: 'detail',
        response: response,
      );
      expect(
        analysis.framingQualification.single.systemAttestedFraming.wireName,
        'detail_only',
      );
      expect(analysis.familyIdentity.resolvedFamily, isNull);
      expect(analysis.identityQualification.selectedCanonicalType, isNull);
    },
  );

  test('invalid JSON fails strictly', () {
    expect(
      () => VisionV2ShadowResponse.fromJson(
        '{bad',
        allowedCanonicalTypes: allowed,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('unknown observation enum fails rather than defaulting', () {
    final input = fixture();
    final observations = Map<String, Object?>.from(
      input['observations']! as Map,
    );
    observations['visibleBulk'] = observation(
      'observed',
      value: 'neutral',
      confidence: 0.7,
    );
    input['observations'] = observations;
    expect(
      () =>
          VisionV2ShadowResponse.fromMap(input, allowedCanonicalTypes: allowed),
      throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
    );
  });

  test('invalid candidate confidence and unknown canonical are rejected', () {
    for (final candidate in [
      {'canonicalType': 'hoodie', 'confidence': 2},
      {'canonicalType': 'invented', 'confidence': 0.8},
    ]) {
      expect(
        () => VisionV2ShadowResponse.fromMap(
          fixture(candidates: [candidate]),
          allowedCanonicalTypes: allowed,
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('missing observation stays missing and is not neutral', () {
    final input = fixture();
    final observations = Map<String, Object?>.from(
      input['observations']! as Map,
    )..remove('visibleBulk');
    input['observations'] = observations;
    final result = VisionV2ShadowResponse.fromMap(
      input,
      allowedCanonicalTypes: allowed,
    );
    expect(result.observations.visibleBulk, isNull);
  });

  test('notVisible remains different from observed false', () {
    final hidden = VisionV2ShadowResponse.fromMap(
      fixture(),
      allowedCanonicalTypes: allowed,
    );
    expect(hidden.observations.visibleStretchCue!.value, isNull);
    expect(
      hidden.observations.visibleStretchCue!.state.wireName,
      'not_visible',
    );

    final input = fixture();
    final observations = Map<String, Object?>.from(
      input['observations']! as Map,
    );
    observations['visibleStretchCue'] = observation(
      'observed',
      value: false,
      confidence: 0.9,
    );
    input['observations'] = observations;
    final visible = VisionV2ShadowResponse.fromMap(
      input,
      allowedCanonicalTypes: allowed,
    );
    expect(visible.observations.visibleStretchCue!.value, isFalse);
  });

  test('orchestration creates normal evidence and consistency report', () {
    final response = VisionV2ShadowResponse.fromMap(
      fixture(),
      allowedCanonicalTypes: allowed,
    );
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'item-1',
      response: response,
      v1Summary: const {'canonical_type': 'sweater', 'warmth_level': 5},
    );
    expect(
      analysis.observationEvidence.every(
        (item) => item.source == EvidenceSource.visualObservation,
      ),
      isTrue,
    );
    expect(
      analysis.identityEvidence.every(
        (item) =>
            item.source == EvidenceSource.aiInference &&
            item.nature == EvidenceNature.inferred,
      ),
      isTrue,
    );
    expect(analysis.capabilityEvidence, isNotEmpty);
    expect(analysis.consistency.results, hasLength(2));
    expect(
      analysis.qualifiedIdentityEvidence
          .where((item) => item.value == 'hoodie')
          .single
          .active,
      isTrue,
    );
    expect(
      analysis.qualifiedIdentityEvidence
          .where((item) => item.value == 'sweater')
          .single
          .active,
      isFalse,
    );
    expect(analysis.v1Summary['canonical_type'], 'sweater');
  });

  test('uncertain AI candidate is deactivated despite high confidence', () {
    final input = fixture(
      candidates: const [
        {'canonicalType': 't_shirt', 'confidence': 0.95},
      ],
    );
    final observations =
        Map<String, Object?>.from(input['observations']! as Map)
          ..['coverage'] = observation('unknown')
          ..['hasHood'] = observation('not_visible')
          ..['frontClosure'] = observation('unknown')
          ..['visibleBulk'] = observation('unknown')
          ..['surfaceAppearance'] = observation('unknown')
          ..['necklineShape'] = observation('unknown');
    input['observations'] = observations;
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'uncertain',
      response: VisionV2ShadowResponse.fromMap(
        input,
        allowedCanonicalTypes: allowed,
      ),
    );
    expect(analysis.qualifiedIdentityEvidence.single.active, isFalse);
    expect(analysis.resolvedProfile.identity.canonicalType.isUnknown, isTrue);
    expect(
      analysis.qualifiedIdentityEvidence.single.method,
      contains('consistency_uncertain:support_'),
    );
  });

  test('high identity confidence needs two observed support properties', () {
    final response = VisionV2ShadowResponse.fromMap(
      (() {
        final raw = fixture(
          candidates: const [
            {
              'canonicalType': 'hoodie',
              'confidence': 0.95,
              'supportingObservations': ['hasHood'],
            },
          ],
        );
        final observations =
            Map<String, Object?>.from(raw['observations']! as Map)
              ..['visibleBulk'] = observation(
                'observed',
                value: 'high',
                confidence: 0.9,
              )
              ..['surfaceAppearance'] = observation(
                'observed',
                value: 'quilted',
                confidence: 0.9,
              );
        raw['observations'] = observations;
        return raw;
      })(),
      allowedCanonicalTypes: allowed,
    );
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'support-audit',
      response: response,
    );

    expect(analysis.qualifiedIdentityEvidence.single.active, isTrue);
    expect(analysis.qualifiedIdentityEvidence.single.confidence, 0.60);
    expect(
      analysis.qualifiedIdentityEvidence.single.method,
      contains('support_1:qualified'),
    );
  });

  test('single candidate permits KB priors but observation inference wins', () {
    final response = VisionV2ShadowResponse.fromMap(
      (() {
        final raw = fixture(
          candidates: const [
            {
              'canonicalType': 'puffer_jacket',
              'confidence': 0.9,
              'supportingObservations': ['visibleBulk', 'surfaceAppearance'],
            },
          ],
        );
        final observations =
            Map<String, Object?>.from(raw['observations']! as Map)
              ..['visibleBulk'] = observation(
                'observed',
                value: 'high',
                confidence: 0.9,
              )
              ..['surfaceAppearance'] = observation(
                'observed',
                value: 'quilted',
                confidence: 0.9,
              );
        raw['observations'] = observations;
        return raw;
      })(),
      allowedCanonicalTypes: allowed,
    );
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'item-2',
      response: response,
    );
    expect(analysis.knowledgeBaseEvidence, isNotEmpty);
    expect(
      analysis.knowledgeBaseEvidence.every(
        (item) =>
            item.source == EvidenceSource.knowledgeBasePrior &&
            (item.dependsOnCanonicalType == null ||
                item.dependsOnCanonicalType == 'puffer_jacket'),
      ),
      isTrue,
    );
  });

  test('shadow output is deterministic and does not mutate V1 input', () {
    final raw = fixture();
    final before = jsonEncode(raw);
    final response = VisionV2ShadowResponse.fromMap(
      raw,
      allowedCanonicalTypes: allowed,
    );
    final v1 = <String, Object?>{'canonical_type': 'hoodie', 'warmth_level': 5};
    final v1Before = Map<String, Object?>.from(v1);
    final first = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'item-1',
      response: response,
      v1Summary: v1,
    );
    final second = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'item-1',
      response: response,
      v1Summary: v1,
    );
    expect(first.toMap(), second.toMap());
    expect(jsonEncode(raw), before);
    expect(v1, v1Before);
  });

  test('multi-photo orchestration uses visible hood evidence', () {
    final front = fixture();
    final frontObservations = Map<String, Object?>.from(
      front['observations']! as Map,
    )..['hasHood'] = observation('not_visible');
    front['observations'] = frontObservations;

    final back = fixture(
      candidates: const [
        {'canonicalType': 'hoodie', 'confidence': 0.82},
      ],
    );
    final backObservations =
        Map<String, Object?>.from(back['observations']! as Map)
          ..['analysisId'] = 'analysis-back'
          ..['sourceReference'] = 'image-back'
          ..['hasHood'] = observation('observed', value: true, confidence: 0.9);
    back['observations'] = backObservations;

    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'multi-photo',
      response: VisionV2ShadowResponse.fromMap(
        front,
        allowedCanonicalTypes: allowed,
      ),
      additionalResponses: [
        VisionV2ShadowResponse.fromMap(back, allowedCanonicalTypes: allowed),
      ],
      multiViewSubjectBinding: const VisionMultiViewSubjectBinding(
        physicalIdentityClaim:
            VisionMultiViewPhysicalIdentityClaim.samePhysicalItem,
        source: VisionMultiViewSubjectBindingSource.userItemUploadIntent,
      ),
    );

    final hoodEvidence = analysis.observationEvidence
        .where((item) => item.property == WardrobeProfileProperty.hasHood)
        .toList();
    expect(hoodEvidence, hasLength(2));
    expect(
      hoodEvidence.any(
        (item) => item.valueState == EvidenceValueState.notVisible,
      ),
      isTrue,
    );
    expect(hoodEvidence.any((item) => item.value == true), isTrue);
    expect(
      analysis.qualifiedIdentityEvidence
          .where((item) => item.value == 'hoodie')
          .any((item) => item.active),
      isTrue,
    );
  });

  test('client taxonomy comes from the existing KB', () {
    final canonical = ClothingKnowledgeBase.allItems
        .map((item) => item.canonicalType)
        .toSet();
    expect(canonical, containsAll(allowed));
  });

  test('semantic defining support can beat a higher generic candidate', () {
    final raw = fixture(
      candidates: const [
        {
          'canonicalType': 't_shirt',
          'confidence': 0.72,
          'supportingObservations': ['visibleBulk', 'frontClosure'],
        },
        {
          'canonicalType': 'v_neck_t_shirt',
          'confidence': 0.70,
          'supportingObservations': ['necklineShape', 'visibleBulk'],
        },
      ],
    );
    final observations = Map<String, Object?>.from(raw['observations']! as Map)
      ..['hasHood'] = observation('observed', value: false, confidence: 0.95)
      ..['frontClosure'] = observation(
        'observed',
        value: 'none',
        confidence: 0.95,
      )
      ..['visibleBulk'] = observation(
        'observed',
        value: 'low',
        confidence: 0.85,
      )
      ..['necklineShape'] = observation(
        'observed',
        value: 'v_neck',
        confidence: 0.95,
      );
    raw['observations'] = observations;

    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'v-neck',
      response: VisionV2ShadowResponse.fromMap(
        raw,
        allowedCanonicalTypes: allowed,
      ),
    );

    expect(
      analysis.identityQualification.selectedCanonicalType,
      'v_neck_t_shirt',
    );
    expect(
      analysis.identityQualification.candidates
          .firstWhere((item) => item.canonicalType == 'v_neck_t_shirt')
          .usedDefiningSupports,
      contains(WardrobeProfileProperty.necklineShape),
    );
  });

  test('high raw subtype without semantic support stays unresolved', () {
    final raw = fixture(
      candidates: const [
        {
          'canonicalType': 'chinos',
          'confidence': 0.95,
          'supportingObservations': ['coverage', 'frontClosure'],
        },
      ],
    );
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'generic-trousers',
      response: VisionV2ShadowResponse.fromMap(
        raw,
        allowedCanonicalTypes: allowed,
      ),
    );

    expect(
      analysis.identityQualification.state,
      VisionIdentityState.insufficientEvidence,
    );
    expect(analysis.resolvedProfile.identity.canonicalType.isUnknown, isTrue);
    expect(
      analysis
          .identityQualification
          .candidates
          .single
          .rejectedSupportingObservations,
      isNotEmpty,
    );
  });

  test('close safe sibling candidates remain ambiguous', () {
    final raw = fixture(
      candidates: const [
        {
          'canonicalType': 'sneakers',
          'confidence': 0.61,
          'supportingObservations': [
            'footwearConstruction',
            'footwearUpperHeight',
          ],
        },
        {
          'canonicalType': 'running_shoes',
          'confidence': 0.59,
          'supportingObservations': [
            'surfaceAppearance',
            'soleProfile',
            'sportyCues',
          ],
        },
      ],
    );
    final observations = Map<String, Object?>.from(raw['observations']! as Map)
      ..['footwearConstruction'] = observation(
        'observed',
        value: 'closed',
        confidence: 0.9,
      )
      ..['footwearUpperHeight'] = observation(
        'observed',
        value: 'low_cut',
        confidence: 0.9,
      )
      ..['surfaceAppearance'] = observation(
        'observed',
        value: 'mesh',
        confidence: 0.85,
      )
      ..['soleProfile'] = observation(
        'observed',
        value: 'standard',
        confidence: 0.8,
      )
      ..['sportyCues'] = observation(
        'observed',
        value: 'high',
        confidence: 0.8,
      );
    raw['observations'] = observations;

    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'close-footwear',
      response: VisionV2ShadowResponse.fromMap(
        raw,
        allowedCanonicalTypes: allowed,
      ),
    );

    expect(analysis.identityQualification.state, VisionIdentityState.ambiguous);
    expect(analysis.resolvedProfile.identity.canonicalType.isUnknown, isTrue);
    expect(
      analysis.qualifiedIdentityEvidence.every((item) => !item.active),
      isTrue,
    );
  });

  test('schema v5 validates defining and supporting roles separately', () {
    final raw = v5Fixture(
      candidates: const [
        {
          'canonicalType': 'v_neck_t_shirt',
          'confidence': 0.78,
          'definingObservations': ['necklineShape', 'coverage'],
          'supportingObservations': ['frontClosure', 'surfaceAppearance'],
        },
      ],
    );
    final observations = Map<String, Object?>.from(raw['observations']! as Map)
      ..['hasHood'] = observation('observed', value: false, confidence: 0.95)
      ..['frontClosure'] = observation(
        'observed',
        value: 'none',
        confidence: 0.9,
      )
      ..['visibleBulk'] = observation('observed', value: 'low', confidence: 0.8)
      ..['necklineShape'] = observation(
        'observed',
        value: 'v_neck',
        confidence: 0.95,
      );
    raw['observations'] = observations;
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'semantic-roles',
      response: VisionV2ShadowResponse.fromMap(
        raw,
        allowedCanonicalTypes: allowed,
      ),
    );
    final audit = analysis.identityQualification.candidates.single;

    expect(audit.usedDefiningSupports, [WardrobeProfileProperty.necklineShape]);
    expect(audit.rejectedDefiningObservations, contains('coverage'));
    expect(
      audit.usedSupportingObservations,
      contains(WardrobeProfileProperty.frontClosure),
    );
    expect(audit.rejectedSupportingObservations, contains('surfaceAppearance'));
    expect(analysis.identityQualification.state, VisionIdentityState.confirmed);
  });

  test(
    'generic shorts use garment coverage but cargo subtype needs pockets',
    () {
      final raw = v5Fixture(
        candidates: const [
          {
            'canonicalType': 'shorts',
            'confidence': 0.8,
            'definingObservations': ['coverage'],
            'supportingObservations': [],
          },
          {
            'canonicalType': 'cargo_shorts',
            'confidence': 0.2,
            'definingObservations': ['coverage'],
            'supportingObservations': ['visiblePocketStructure'],
          },
        ],
      );
      final observations =
          Map<String, Object?>.from(raw['observations']! as Map)
            ..['coverage'] = observation(
              'observed',
              value: 'partial',
              confidence: 0.9,
            )
            ..['visiblePocketStructure'] = observation(
              'unknown',
              confidence: 0,
            );
      raw['observations'] = observations;
      final analysis = const VisionV2ShadowOrchestrator().analyze(
        itemId: 'generic-shorts',
        response: VisionV2ShadowResponse.fromMap(
          raw,
          allowedCanonicalTypes: allowed,
        ),
      );

      expect(analysis.identityQualification.selectedCanonicalType, 'shorts');
      expect(
        analysis.identityQualification.candidates
            .firstWhere((item) => item.canonicalType == 'cargo_shorts')
            .state,
        VisionIdentityState.insufficientEvidence,
      );
    },
  );

  test('missing signature is explicit and cannot activate AI identity', () {
    final raw = v5Fixture(
      candidates: const [
        {
          'canonicalType': 'hiking_jacket',
          'confidence': 0.95,
          'definingObservations': ['sportyCues', 'hasHood'],
          'supportingObservations': ['frontClosure'],
        },
      ],
    );
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'missing-signature',
      response: VisionV2ShadowResponse.fromMap(
        raw,
        allowedCanonicalTypes: allowed,
      ),
    );
    final audit = analysis.identityQualification.candidates.single;

    expect(audit.missingSignatureCoverage, isTrue);
    expect(audit.reasonCodes, contains('missing_signature_coverage'));
    expect(analysis.resolvedProfile.identity.canonicalType.isUnknown, isTrue);
    expect(
      analysis.capabilityEvidence.any(
        (item) =>
            item.property == WardrobeProfileProperty.rainProtection ||
            item.property == WardrobeProfileProperty.windProtection,
      ),
      isFalse,
    );
  });

  test('schema v6 preserves raw absence and exposes qualified observation', () {
    final raw = v6Fixture(
      candidates: const [
        {
          'canonicalType': 'chinos',
          'confidence': 0.8,
          'definingObservations': ['coverage'],
          'supportingObservations': [],
        },
      ],
    );
    final observations = raw['observations']! as Map<String, Object?>;
    observations['visiblePocketStructure'] = observation(
      'observed',
      value: 'none',
      confidence: 0.95,
      visibilityScope: 'partial',
    );
    final response = VisionV2ShadowResponse.fromMap(
      raw,
      allowedCanonicalTypes: allowed,
    );
    final result = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'schema-v6',
      response: response,
    );

    expect(response.observations.visiblePocketStructure!.value, isNotNull);
    expect(
      result
          .observationQualification!
          .qualifiedBundle
          .visiblePocketStructure!
          .state
          .wireName,
      'unknown',
    );
    expect(result.familyIdentity.resolvedFamily?.wireName, 'trousers');
    expect(result.identityQualification.selectedCanonicalType, isNull);
  });

  test('schema v7 invalid input deactivates subtype and family', () {
    final raw = v7Fixture(
      inputAssessment: 'non_wardrobe_object',
      candidates: const [
        {
          'canonicalType': 't_shirt',
          'confidence': 0.9,
          'definingObservations': ['coverage'],
          'supportingObservations': ['necklineShape'],
        },
      ],
    );
    final response = VisionV2ShadowResponse.fromMap(
      raw,
      allowedCanonicalTypes: allowed,
    );
    final result = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'invalid-v7',
      response: response,
    );

    expect(response.inputAssessment.wireName, 'non_wardrobe_object');
    expect(result.identityQualification.selectedCanonicalType, isNull);
    expect(result.familyIdentity.state.wireName, 'invalid_input');
    expect(result.familyIdentity.resolvedFamily, isNull);
    expect(result.visibilityQualification, isNotEmpty);
    expect(
      result.capabilityEvidence.every(
        (item) => item.valueState != EvidenceValueState.known,
      ),
      isTrue,
    );
  });

  test('high top and sporty cues cannot activate basketball subtype', () {
    final raw = v7Fixture(
      candidates: const [
        {
          'canonicalType': 'basketball_shoes',
          'confidence': 0.85,
          'definingObservations': ['footwearUpperHeight', 'sportyCues'],
          'supportingObservations': ['footwearFastening'],
        },
        {
          'canonicalType': 'sneakers',
          'confidence': 0.15,
          'definingObservations': ['footwearConstruction'],
          'supportingObservations': ['footwearFastening'],
        },
      ],
    );
    final observations = raw['observations']! as Map<String, Object?>;
    observations['footwearConstruction'] = observation(
      'observed',
      value: 'closed',
      confidence: 0.9,
      visibilityScope: 'sufficient',
    )..['visibleRegions'] = ['footwear_upper'];
    observations['footwearUpperHeight'] = observation(
      'observed',
      value: 'ankle',
      confidence: 0.85,
      visibilityScope: 'sufficient',
    )..['visibleRegions'] = ['footwear_upper', 'side'];
    observations['sportyCues'] = observation(
      'observed',
      value: 'high',
      confidence: 0.8,
      visibilityScope: 'sufficient',
    )..['visibleRegions'] = ['full_silhouette'];

    final result = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'fashion-high-top',
      response: VisionV2ShadowResponse.fromMap(
        raw,
        allowedCanonicalTypes: allowed,
      ),
    );

    expect(
      result.identityQualification.selectedCanonicalType,
      isNot('basketball_shoes'),
    );
    final basketball = result.identityQualification.candidates.singleWhere(
      (item) => item.canonicalType == 'basketball_shoes',
    );
    expect(basketball.missingSignatureCoverage, isTrue);
    expect(result.familyIdentity.resolvedFamily?.wireName, 'sneakers');
  });
}
