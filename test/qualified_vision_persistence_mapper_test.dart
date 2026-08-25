import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/qualified_vision_persistence_mapper.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_subject_safety.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_codec.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_contract.dart';

const allowed = {
  'hoodie',
  'sweater',
  't_shirt',
  'softshell',
  'chinos',
  'sneakers',
  'running_shoes',
  'basketball_shoes',
};

Map<String, Object?> observation(
  String state, {
  Object? value,
  double confidence = 0,
  String visibilityScope = 'complete',
  List<String> regions = const [],
}) => {
  'state': state,
  if (state == 'observed') 'value': value,
  'confidence': confidence,
  'visibilityScope': state == 'not_visible' ? 'not_visible' : visibilityScope,
  'visibleRegions': regions,
};

Map<String, Object?> fixture({
  String input = 'valid_single_item',
  String framing = 'full_item',
  bool detail = false,
  String canonical = 'hoodie',
  List<Map<String, Object?>>? candidates,
}) => {
  'schemaVersion': 9,
  'analysisId': 'analysis-1',
  'modelVersion': 'gpt-4o-mini',
  'sourceReference': 'fixture://item',
  'observedAt': '2026-07-29T10:00:00.000Z',
  'inputAssessment': input,
  'quality': {
    'itemFullyVisible': !detail,
    'occlusion': 'none',
    'backgroundInterference': 'low',
    'clarity': 'high',
  },
  'subjectAssessment': {
    'subjectCountEstimate': input == 'valid_single_item' ? 1 : 0,
    'cardinalityState': input == 'valid_single_item'
        ? 'single_item_supported'
        : 'no_wardrobe_subject',
    'primarySubjectPresent': input == 'valid_single_item',
    'sameItemConsistency': input == 'valid_single_item'
        ? 'same_item_supported'
        : 'not_applicable',
    'subjectDomain': 'garment_upper',
    'framingClass': framing,
    'framingAttestations': {
      'visibleBoundaries': detail
          ? <String>[]
          : ['top', 'bottom', 'left', 'right'],
      'primarySilhouetteContinuous': !detail,
      'visibleItemExtent': detail ? 'local' : 'whole',
      'localDetailOnly': detail,
      'cropIndicators': detail ? ['severe_crop'] : <String>[],
      'subjectOrientation': 'front',
    },
    'reasonCodes': <String>[],
  },
  'observations': {
    'coverage': observation(
      'observed',
      value: 'full',
      confidence: .9,
      regions: ['full_silhouette'],
    ),
    'hasHood': observation(
      'observed',
      value: true,
      confidence: .95,
      regions: ['collar', 'back'],
    ),
    'frontClosure': observation(
      'observed',
      value: 'full_zip',
      confidence: .9,
      regions: ['front', 'fastening_area'],
    ),
    'visibleBulk': observation(
      'observed',
      value: 'medium',
      confidence: .85,
      regions: ['full_silhouette'],
    ),
    'surfaceAppearance': observation(
      'observed',
      value: 'fleece_like',
      confidence: .85,
      regions: ['surface_detail'],
    ),
    'necklineShape': observation(
      'observed',
      value: 'high_neck',
      confidence: .8,
      regions: ['neckline'],
    ),
    'visiblePocketStructure': observation('unknown'),
    'visibleStretchCue': observation('not_visible'),
    'sportyCues': observation(
      'observed',
      value: 'medium',
      confidence: .8,
      regions: ['full_silhouette'],
    ),
    'formalCues': observation(
      'observed',
      value: 'low',
      confidence: .8,
      regions: ['full_silhouette'],
    ),
    'footwearConstruction': observation('not_applicable'),
    'footwearFastening': observation('not_applicable'),
    'soleProfile': observation('not_applicable'),
    'visibleTread': observation('not_applicable'),
    'footwearUpperHeight': observation('not_applicable'),
  },
  'identityCandidates':
      candidates ??
      [
        {
          'canonicalType': canonical,
          'confidence': .91,
          'definingObservations': ['hasHood', 'frontClosure'],
          'supportingObservations': ['visibleBulk', 'surfaceAppearance'],
        },
      ],
  'validationErrors': <String>[],
  'diagnostics': {
    'latencyMs': 1,
    'modelCallCount': 1,
    'inputPayloadBytes': 1,
    'outputPayloadBytes': 1,
    'observationFieldCount': 15,
  },
};

VisionV2ShadowAnalysis analyze(
  Map<String, Object?> raw, {
  List<Map<String, Object?>> additional = const [],
  VisionMultiViewSubjectBinding multiViewSubjectBinding =
      VisionMultiViewSubjectBinding.undeclared,
}) => const VisionV2ShadowOrchestrator().analyze(
  itemId: 'item-1',
  response: VisionV2ShadowResponse.fromMap(raw, allowedCanonicalTypes: allowed),
  additionalResponses: additional.map(
    (item) =>
        VisionV2ShadowResponse.fromMap(item, allowedCanonicalTypes: allowed),
  ),
  multiViewSubjectBinding: multiViewSubjectBinding,
);

VisionV2ShadowAnalysis copyAnalysis(
  VisionV2ShadowAnalysis source, {
  List<ProfileEvidence>? observations,
  List<ProfileEvidence>? capabilities,
  List<ProfileEvidence>? knowledgeBase,
}) => VisionV2ShadowAnalysis(
  response: source.response,
  observationEvidence: observations ?? source.observationEvidence,
  identityEvidence: source.identityEvidence,
  qualifiedIdentityEvidence: source.qualifiedIdentityEvidence,
  identityQualification: source.identityQualification,
  framingQualification: source.framingQualification,
  negativeClaimCorroboration: source.negativeClaimCorroboration,
  visibilityQualification: source.visibilityQualification,
  applicabilityQualification: source.applicabilityQualification,
  multiPhotoConsistency: source.multiPhotoConsistency,
  multiPhotoAssessment: source.multiPhotoAssessment,
  observationQualification: source.observationQualification,
  familyIdentity: source.familyIdentity,
  capabilityEvidence: capabilities ?? source.capabilityEvidence,
  knowledgeBaseEvidence: knowledgeBase ?? source.knowledgeBaseEvidence,
  consistency: source.consistency,
  resolvedProfile: source.resolvedProfile,
  v1Summary: source.v1Summary,
);

void main() {
  const mapper = QualifiedVisionPersistenceMapper();
  const codec = WardrobeProfilePersistenceCodec();

  PersistenceMappingContext context({
    String analysisId = 'analysis-1',
    String generationId = 'generation-1',
  }) => PersistenceMappingContext(
    generationId: generationId,
    revision: 1,
    createdAt: DateTime.utc(2026, 7, 29, 10),
    updatedAt: DateTime.utc(2026, 7, 29, 10, 1),
    imageRevision: 2,
    wardrobeItemRevision: 3,
    storagePath: 'users/u/wardrobe/i/source.jpg',
    analysisId: analysisId,
    analysisKind: WardrobeAnalysisKind.initialAnalysis,
    completedAt: DateTime.utc(2026, 7, 29, 10),
    modelIdentifier: 'gpt-4o-mini',
    pipelineVersion: 'vision-v2-phase-4.9',
    promptVersion: 'vision-v2-schema-9',
    visionSchemaVersion: 9,
    qualificationVersion: 'qualification-v1',
  );

  WardrobeProfilePersistenceMappingResult map(
    VisionV2ShadowAnalysis analysis, {
    PersistenceMappingContext? withContext,
  }) => mapper.map(analysis: analysis, context: withContext ?? context());

  Iterable<PersistedMachineEvidence> property(
    WardrobeProfilePersistenceMappingResult result,
    String path,
  ) => result.envelope!.machineEvidence.where((item) => item.property == path);

  test(
    'full mapping contains family canonical observations and capabilities',
    () {
      final result = map(analyze(fixture()));
      expect(result.status, WardrobeProfilePersistenceMappingStatus.mapped);
      expect(property(result, WardrobeProfileProperty.family), isNotEmpty);
      expect(
        property(result, WardrobeProfileProperty.canonicalType),
        isNotEmpty,
      );
      expect(property(result, WardrobeProfileProperty.hasHood), isNotEmpty);
      expect(
        result.envelope!.machineEvidence.any(
          (item) => item.property.startsWith('capabilities.'),
        ),
        isTrue,
      );
    },
  );

  test('family-only mapping preserves supported family without canonical', () {
    final raw = fixture(
      candidates: [
        {
          'canonicalType': 'chinos',
          'confidence': .8,
          'definingObservations': ['coverage'],
          'supportingObservations': ['visiblePocketStructure'],
        },
      ],
    );
    final subject = raw['subjectAssessment']! as Map<String, Object?>;
    subject['subjectDomain'] = 'garment_lower';
    final observations = raw['observations']! as Map<String, Object?>;
    observations['visiblePocketStructure'] = observation(
      'observed',
      value: 'none',
      confidence: .95,
      visibilityScope: 'partial',
      regions: ['front'],
    );
    final result = map(analyze(raw));
    expect(result.status, WardrobeProfilePersistenceMappingStatus.mapped);
    expect(property(result, WardrobeProfileProperty.family), isNotEmpty);
    expect(property(result, WardrobeProfileProperty.canonicalType), isEmpty);
  });

  test('family and canonical retain their real independent tiers', () {
    final result = map(analyze(fixture()));
    final family = property(result, WardrobeProfileProperty.family).single;
    final canonical = property(
      result,
      WardrobeProfileProperty.canonicalType,
    ).single;
    expect(family.identityQualification, isNotNull);
    expect(canonical.identityQualification, isNotNull);
    expect(family.id, isNot(canonical.id));
  });

  test('ambiguous family is not persisted', () {
    final raw = fixture(
      candidates: [
        {
          'canonicalType': 'hoodie',
          'confidence': .5,
          'definingObservations': ['hasHood'],
          'supportingObservations': ['frontClosure'],
        },
        {
          'canonicalType': 't_shirt',
          'confidence': .5,
          'definingObservations': ['coverage'],
          'supportingObservations': ['necklineShape'],
        },
      ],
    );
    final result = map(analyze(raw));
    expect(property(result, WardrobeProfileProperty.family), isEmpty);
  });

  test('conflicting family is not persisted', () {
    final first = fixture();
    final second = fixture(canonical: 't_shirt');
    final result = map(analyze(first, additional: [second]));
    expect(property(result, WardrobeProfileProperty.family), isEmpty);
  });

  test('invalid input returns invalidInput without envelope', () {
    final raw = fixture(input: 'non_wardrobe_object')
      ..['observations'] = <String, Object?>{}
      ..['identityCandidates'] = <Object?>[];
    final result = map(analyze(raw));
    expect(result.status, WardrobeProfilePersistenceMappingStatus.invalidInput);
    expect(result.envelope, isNull);
  });

  test('detail framing cannot persist raw canonical or family promotion', () {
    final result = map(analyze(fixture(framing: 'detail_only', detail: true)));
    if (result.envelope != null) {
      expect(property(result, WardrobeProfileProperty.family), isEmpty);
      expect(property(result, WardrobeProfileProperty.canonicalType), isEmpty);
    }
  });

  test('cross-subject multi-photo blocks identity evidence', () {
    final second = fixture(canonical: 't_shirt');
    (second['subjectAssessment']!
            as Map<String, Object?>)['sameItemConsistency'] =
        'conflicting_subjects';
    final result = map(analyze(fixture(), additional: [second]));
    expect(property(result, WardrobeProfileProperty.family), isEmpty);
    expect(property(result, WardrobeProfileProperty.canonicalType), isEmpty);
  });

  test('unsupported footwear subtype never leaks from raw candidate', () {
    final raw = fixture(
      candidates: [
        {
          'canonicalType': 'basketball_shoes',
          'confidence': .95,
          'definingObservations': ['sportyCues'],
          'supportingObservations': ['visibleBulk'],
        },
      ],
    );
    final result = map(analyze(raw));
    expect(
      property(
        result,
        WardrobeProfileProperty.canonicalType,
      ).any((item) => item.value == 'basketball_shoes'),
      isFalse,
    );
  });

  test('positive visible front closure is persisted', () {
    final result = map(analyze(fixture()));
    expect(
      property(result, WardrobeProfileProperty.frontClosure).single.value,
      'full_zip',
    );
  });

  test('uncorroborated frontClosure none is not a persisted negative fact', () {
    final raw = fixture();
    final observations = raw['observations']! as Map<String, Object?>;
    observations['frontClosure'] = observation(
      'observed',
      value: 'none',
      confidence: .99,
      regions: ['front'],
    );
    final result = map(analyze(raw));
    expect(
      property(result, WardrobeProfileProperty.frontClosure).any(
        (item) =>
            item.valueState == EvidenceValueState.known && item.value == 'none',
      ),
      isFalse,
    );
  });

  test('uncorroborated hood false is not a persisted negative fact', () {
    final raw = fixture();
    final observations = raw['observations']! as Map<String, Object?>;
    observations['hasHood'] = observation(
      'observed',
      value: false,
      confidence: .99,
      regions: ['collar'],
    );
    final result = map(analyze(raw));
    expect(
      property(result, WardrobeProfileProperty.hasHood).any(
        (item) =>
            item.valueState == EvidenceValueState.known && item.value == false,
      ),
      isFalse,
    );
  });

  test('known notVisible and notApplicable states survive mapping', () {
    final result = map(analyze(fixture()));
    expect(
      property(result, WardrobeProfileProperty.hasHood).single.valueState,
      EvidenceValueState.known,
    );
    expect(
      property(
        result,
        WardrobeProfileProperty.visibleStretchCue,
      ).single.valueState,
      EvidenceValueState.notVisible,
    );
    expect(
      property(
        result,
        WardrobeProfileProperty.footwearConstruction,
      ).single.valueState,
      EvidenceValueState.notApplicable,
    );
  });

  test('valid item-specific capability has resolvable supports', () {
    final result = map(analyze(fixture()));
    final ids = result.envelope!.machineEvidence.map((item) => item.id).toSet();
    for (final item in result.envelope!.machineEvidence.where(
      (item) => item.property.startsWith('capabilities.'),
    )) {
      expect(item.supportingEvidenceIds, isNotEmpty);
      expect(item.supportingEvidenceIds.every(ids.contains), isTrue);
    }
  });

  test('capability is omitted when required observation is absent', () {
    final original = analyze(fixture());
    final observations = original.observationEvidence
        .where((item) => item.property != WardrobeProfileProperty.visibleBulk)
        .toList();
    final result = map(copyAnalysis(original, observations: observations));
    expect(
      result.envelope!.machineEvidence.any(
        (item) =>
            item.property == WardrobeProfileProperty.supportedLayerRoles ||
            item.property == WardrobeProfileProperty.warmth,
      ),
      isFalse,
    );
  });

  test('KB prior is never mapped', () {
    final analysis = analyze(fixture());
    final result = map(analysis);
    expect(
      result.envelope!.machineEvidence.any(
        (item) => item.source == EvidenceSource.knowledgeBasePrior,
      ),
      isFalse,
    );
  });

  test('legacy fallback in candidate list is ignored', () {
    final original = analyze(fixture());
    final legacy = ProfileEvidence(
      id: 'legacy',
      property: WardrobeProfileProperty.warmth,
      value: 5,
      source: EvidenceSource.legacyFallback,
      nature: EvidenceNature.defaulted,
      confidence: .5,
      method: 'legacy',
      createdAt: DateTime.utc(2026),
    );
    final result = map(
      copyAnalysis(
        original,
        capabilities: [...original.capabilityEvidence, legacy],
      ),
    );
    expect(
      result.envelope!.machineEvidence.any((item) => item.id == 'legacy'),
      isFalse,
    );
  });

  test('resolved profile values are not mapper inputs', () {
    final result = map(analyze(fixture()));
    final encoded = codec.toPersistenceMap(result.envelope!);
    expect(encoded, isNot(contains('resolvedProfile')));
    expect(encoded, isNot(contains('resolvedCache')));
  });

  test('evidence IDs are deterministic and independent from ordering', () {
    final analysis = analyze(fixture());
    final first = map(analysis).envelope!.machineEvidence.map((e) => e.id);
    final reversed = copyAnalysis(
      analysis,
      observations: analysis.observationEvidence.reversed.toList(),
      capabilities: analysis.capabilityEvidence.reversed.toList(),
    );
    final second = map(reversed).envelope!.machineEvidence.map((e) => e.id);
    expect(second, first);
  });

  test(
    'machine evidence ordering is family canonical observations capability',
    () {
      final items = map(analyze(fixture())).envelope!.machineEvidence;
      final familyIndex = items.indexWhere(
        (item) => item.property == WardrobeProfileProperty.family,
      );
      final canonicalIndex = items.indexWhere(
        (item) => item.property == WardrobeProfileProperty.canonicalType,
      );
      final observationIndex = items.indexWhere(
        (item) => item.property == WardrobeProfileProperty.coverage,
      );
      final capabilityIndex = items.indexWhere(
        (item) => item.property.startsWith('capabilities.'),
      );
      expect(familyIndex, 0);
      expect(canonicalIndex, 1);
      expect(observationIndex, greaterThan(canonicalIndex));
      expect(capabilityIndex, greaterThan(observationIndex));
    },
  );

  test('identical duplicate observation is deterministically deduplicated', () {
    final original = analyze(fixture());
    final duplicate = original.observationEvidence.first;
    final result = map(
      copyAnalysis(
        original,
        observations: [...original.observationEvidence, duplicate],
      ),
    );
    expect(
      result.envelope!.machineEvidence.where(
        (item) => item.property == duplicate.property,
      ),
      hasLength(1),
    );
  });

  test('conflicting duplicate observation fails mapping', () {
    final original = analyze(fixture());
    final first = original.observationEvidence.first;
    final conflict = ProfileEvidence(
      id: '${first.id}:conflict',
      property: first.property,
      value: 'partial',
      source: first.source,
      nature: first.nature,
      confidence: first.confidence,
      method: first.method,
      createdAt: first.createdAt,
      modelVersion: first.modelVersion,
    );
    final result = map(
      copyAnalysis(
        original,
        observations: [...original.observationEvidence, conflict],
      ),
    );
    expect(
      result.status,
      WardrobeProfilePersistenceMappingStatus.mappingFailure,
    );
  });

  test('missing required provenance is incompatible input', () {
    final result = map(
      analyze(fixture()),
      withContext: context(generationId: ''),
    );
    expect(
      result.status,
      WardrobeProfilePersistenceMappingStatus.incompatibleInput,
    );
  });

  test('same-item multi-photo maps reconciled output', () {
    final result = map(
      analyze(
        fixture(),
        additional: [fixture()],
        multiViewSubjectBinding: const VisionMultiViewSubjectBinding(
          physicalIdentityClaim:
              VisionMultiViewPhysicalIdentityClaim.samePhysicalItem,
          source: VisionMultiViewSubjectBindingSource.userItemUploadIntent,
        ),
      ),
    );
    expect(result.status, WardrobeProfilePersistenceMappingStatus.mapped);
    expect(property(result, WardrobeProfileProperty.family), isNotEmpty);
  });

  test('conflicting-subject multi-photo blocks identity', () {
    final second = fixture(canonical: 't_shirt');
    (second['subjectAssessment']!
            as Map<String, Object?>)['sameItemConsistency'] =
        'conflicting_subjects';
    final result = map(
      analyze(
        fixture(),
        additional: [second],
        multiViewSubjectBinding: const VisionMultiViewSubjectBinding(
          physicalIdentityClaim:
              VisionMultiViewPhysicalIdentityClaim.samePhysicalItem,
          source: VisionMultiViewSubjectBindingSource.userItemUploadIntent,
        ),
      ),
    );
    expect(property(result, WardrobeProfileProperty.family), isEmpty);
    expect(property(result, WardrobeProfileProperty.canonicalType), isEmpty);
  });

  test('mapped envelope passes the persistence codec', () {
    final result = map(analyze(fixture()));
    final decoded = codec.fromPersistenceMap(
      codec.toPersistenceMap(result.envelope!),
    );
    expect(decoded.status, WardrobeProfileDecodeStatus.valid);
  });

  test('analysis id mismatch is incompatible rather than guessed', () {
    final result = map(
      analyze(fixture()),
      withContext: context(analysisId: 'different'),
    );
    expect(
      result.status,
      WardrobeProfilePersistenceMappingStatus.incompatibleInput,
    );
  });

  test('valid empty analysis returns noPersistableEvidence', () {
    final raw = fixture()
      ..['observations'] = <String, Object?>{}
      ..['identityCandidates'] = <Object?>[];
    final empty = analyze(raw);
    final result = map(
      copyAnalysis(empty, observations: const [], capabilities: const []),
    );
    expect(
      result.status,
      WardrobeProfilePersistenceMappingStatus.noPersistableEvidence,
    );
  });
}
