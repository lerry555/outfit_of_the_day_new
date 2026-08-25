import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_codec.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_contract.dart';

void main() {
  const codec = WardrobeProfilePersistenceCodec();
  final created = DateTime.utc(2026, 7, 29, 10);
  final updated = DateTime.utc(2026, 7, 29, 10, 1);

  PersistedMachineEvidence canonical({
    String value = 't_shirt',
    EvidenceSource source = EvidenceSource.aiInference,
  }) => PersistedMachineEvidence(
    id: 'identity:analysis-1:t_shirt',
    property: WardrobeProfileProperty.canonicalType,
    value: value,
    valueState: EvidenceValueState.known,
    source: source,
    nature: EvidenceNature.inferred,
    confidence: 0.87,
    method: 'vision_v2_identity_candidate',
    createdAt: created,
    modelVersion: 'gpt-4o-mini',
    identityQualification: PersistedIdentityQualification.confirmed,
    supportingEvidenceIds: const [
      'observation:analysis-1:visual.coverage',
      'observation:analysis-1:visual.observations.necklineShape',
    ],
  );

  PersistedMachineEvidence family({
    String value = 'top',
    PersistedIdentityQualification qualification =
        PersistedIdentityQualification.confirmed,
  }) => PersistedMachineEvidence(
    id: 'family:analysis-1:$value',
    property: WardrobeProfileProperty.family,
    value: value,
    valueState: EvidenceValueState.known,
    source: EvidenceSource.aiInference,
    nature: EvidenceNature.inferred,
    confidence: qualification == PersistedIdentityQualification.confirmed
        ? 0.91
        : 0.72,
    method: 'vision_family_identity',
    createdAt: created,
    modelVersion: 'family-identity-v1',
    identityQualification: qualification,
    supportingEvidenceIds: const ['observation:analysis-1:visual.coverage'],
  );

  PersistedMachineEvidence capability({
    EvidenceSource source = EvidenceSource.aiInference,
    String method = 'capability_inference:warmth.bulk_and_surface',
  }) => PersistedMachineEvidence(
    id: 'capability:analysis-1:warmth',
    property: WardrobeProfileProperty.warmth,
    value: 7,
    valueState: EvidenceValueState.known,
    source: source,
    nature: source == EvidenceSource.aiInference
        ? EvidenceNature.inferred
        : EvidenceNature.defaulted,
    confidence: 0.68,
    method: method,
    createdAt: created,
    modelVersion: 'capability-inference-v1',
    supportingEvidenceIds: const [
      'observation:analysis-1:visual.observations.visibleBulk',
      'observation:analysis-1:visual.observations.surfaceAppearance',
    ],
  );

  PersistedMachineEvidence observation() => PersistedMachineEvidence(
    id: 'observation:analysis-1:hasHood',
    property: WardrobeProfileProperty.hasHood,
    value: false,
    valueState: EvidenceValueState.known,
    source: EvidenceSource.visualObservation,
    nature: EvidenceNature.observed,
    confidence: 0.91,
    method: 'vision_observation',
    createdAt: created,
    modelVersion: 'gpt-4o-mini',
  );

  PersistedUserCorrection correction({
    UserCorrectionAction action = UserCorrectionAction.set,
    Object? value = 'sweatshirt',
    Object? rejectedValue,
  }) => PersistedUserCorrection(
    id: 'correction-1',
    property: WardrobeProfileProperty.canonicalType,
    action: action,
    value: value,
    rejectedValue: rejectedValue,
    correctedAt: updated,
    method: 'wardrobe_item_edit',
    actorId: 'owner',
    supersedesEvidenceId: 'identity:analysis-1:t_shirt',
  );

  WardrobeProfilePersistenceEnvelope envelope({
    List<PersistedMachineEvidence>? evidence,
    Map<String, PersistedUserCorrection>? corrections,
    int revision = 3,
  }) => WardrobeProfilePersistenceEnvelope(
    metadata: WardrobeProfilePersistenceMetadata(
      generationId: 'generation-3',
      revision: revision,
      createdAt: created,
      updatedAt: updated,
    ),
    source: const WardrobeProfileSourceProvenance(
      imageRevision: 2,
      wardrobeItemRevision: 7,
      storagePath: 'users/u/wardrobe/i/source.jpg',
      uploadGeneration: 'upload-2',
    ),
    analysis: WardrobeProfileAnalysisProvenance(
      analysisId: 'analysis-1',
      kind: WardrobeAnalysisKind.initialAnalysis,
      completedAt: created,
      modelIdentifier: 'gpt-4o-mini',
      pipelineVersion: 'vision-v2-phase-4.9',
      promptVersion: 'vision-v2-schema-9',
      visionSchemaVersion: 9,
      qualificationVersion: 'qualification-v1',
    ),
    machineEvidence: evidence ?? [canonical(), observation()],
    userCorrections:
        corrections ?? {WardrobeProfileProperty.canonicalType: correction()},
  );

  Map<String, Object?> encoded([WardrobeProfilePersistenceEnvelope? value]) =>
      codec.toPersistenceMap(value ?? envelope());

  Map<String, Object?> jsonCopy([WardrobeProfilePersistenceEnvelope? value]) =>
      (jsonDecode(jsonEncode(encoded(value))) as Map).map(
        (key, item) => MapEntry(key.toString(), item),
      );

  test('valid contract round-trips through persistence map and JSON', () {
    final result = codec.fromJson(codec.toJson(envelope()));

    expect(result.status, WardrobeProfileDecodeStatus.valid);
    final restored = result.envelope!;
    expect(restored.metadata.generationId, 'generation-3');
    expect(restored.source.storagePath, endsWith('source.jpg'));
    expect(restored.analysis.visionSchemaVersion, 9);
    expect(restored.machineEvidence, hasLength(2));
    expect(
      restored.userCorrections[WardrobeProfileProperty.canonicalType]!.value,
      'sweatshirt',
    );
  });

  test('encoded envelope contains all required groups and version fields', () {
    final map = encoded();
    expect(
      map.keys,
      containsAll([
        'metadata',
        'source',
        'analysis',
        'machineEvidence',
        'userCorrections',
      ]),
    );
    final metadata = map['metadata']! as Map<String, Object?>;
    expect(
      metadata.keys,
      containsAll([
        'schemaVersion',
        'evidenceSchemaVersion',
        'resolverCompatibilityVersion',
        'generationId',
        'revision',
        'createdAt',
        'updatedAt',
        'status',
      ]),
    );
  });

  test('unknown schema version is unsupported', () {
    final map = jsonCopy();
    (map['metadata']! as Map)['schemaVersion'] = 99;

    final result = codec.fromPersistenceMap(map);
    expect(result.status, WardrobeProfileDecodeStatus.unsupportedVersion);
  });

  test('corrupt envelope is invalid rather than empty valid profile', () {
    final result = codec.fromPersistenceMap({'metadata': 'broken'});
    expect(result.status, WardrobeProfileDecodeStatus.invalid);
    expect(result.envelope, isNull);
  });

  test('unknown enum is invalid and is not defaulted', () {
    final map = jsonCopy();
    (map['metadata']! as Map)['status'] = 'mystery';

    final result = codec.fromPersistenceMap(map);
    expect(result.status, WardrobeProfileDecodeStatus.invalid);
    expect(result.failureCode, contains('unknown_enum'));
  });

  test('unknown canonical key is invalid', () {
    final map = jsonCopy();
    ((map['machineEvidence']! as List).first as Map)['value'] =
        'invented_garment';

    final result = codec.fromPersistenceMap(map);
    expect(result.status, WardrobeProfileDecodeStatus.invalid);
    expect(result.failureCode, contains('unknown_canonical_key'));
  });

  test('missing machineEvidence is invalid', () {
    final map = jsonCopy()..remove('machineEvidence');
    expect(
      codec.fromPersistenceMap(map).status,
      WardrobeProfileDecodeStatus.invalid,
    );
  });

  test('empty userCorrections is valid', () {
    final result = codec.fromPersistenceMap(
      jsonCopy(envelope(corrections: const {})),
    );
    expect(result.status, WardrobeProfileDecodeStatus.valid);
    expect(result.envelope!.userCorrections, isEmpty);
  });

  test('user correction tri-state is explicit', () {
    final missing = envelope(corrections: const {});
    final set = envelope();
    final cleared = envelope(
      corrections: {
        WardrobeProfileProperty.canonicalType: correction(
          action: UserCorrectionAction.cleared,
          value: null,
        ),
      },
    );
    final rejected = envelope(
      corrections: {
        WardrobeProfileProperty.canonicalType: correction(
          action: UserCorrectionAction.rejected,
          value: null,
          rejectedValue: 't_shirt',
        ),
      },
    );

    expect(
      codec.fromPersistenceMap(jsonCopy(missing)).envelope!.userCorrections,
      isEmpty,
    );
    expect(
      codec
          .fromPersistenceMap(jsonCopy(set))
          .envelope!
          .userCorrections
          .values
          .single
          .action,
      UserCorrectionAction.set,
    );
    expect(
      codec
          .fromPersistenceMap(jsonCopy(cleared))
          .envelope!
          .userCorrections
          .values
          .single
          .action,
      UserCorrectionAction.cleared,
    );
    expect(
      () => cleared.userCorrections.values.single.toRuntimeEvidence(),
      throwsStateError,
    );
    expect(
      codec
          .fromPersistenceMap(jsonCopy(rejected))
          .envelope!
          .userCorrections
          .values
          .single
          .rejectedValue,
      't_shirt',
    );
  });

  test('replacing machine generation preserves user corrections', () {
    final old = envelope();
    final replacement = old.replaceMachineGeneration(
      metadata: WardrobeProfilePersistenceMetadata(
        generationId: 'generation-4',
        revision: 4,
        createdAt: created,
        updatedAt: updated.add(const Duration(minutes: 1)),
      ),
      source: old.source,
      analysis: WardrobeProfileAnalysisProvenance(
        analysisId: 'analysis-2',
        kind: WardrobeAnalysisKind.reanalysis,
        completedAt: updated,
        modelIdentifier: 'gpt-4o-mini',
        pipelineVersion: 'vision-v2-phase-4.9',
        promptVersion: 'vision-v2-schema-9',
        visionSchemaVersion: 9,
        qualificationVersion: 'qualification-v1',
      ),
      machineEvidence: [canonical(value: 'hoodie')],
    );

    expect(replacement.machineEvidence.single.value, 'hoodie');
    expect(replacement.userCorrections, same(old.userCorrections));
    expect(replacement.userCorrections.values.single.value, 'sweatshirt');
  });

  test('unknown additive fields are ignored', () {
    final map = jsonCopy();
    map['futureRootField'] = {'anything': true};
    (map['metadata']! as Map)['futureMetadataField'] = 42;
    ((map['machineEvidence']! as List).first as Map)['futureEvidenceField'] =
        'ignored';

    expect(
      codec.fromPersistenceMap(map).status,
      WardrobeProfileDecodeStatus.valid,
    );
  });

  test('codec cannot serialize raw response or diagnostic fields', () {
    final map = encoded();
    expect(map, isNot(contains('rawResponse')));
    expect(map, isNot(contains('prompt')));
    expect(map, isNot(contains('diagnostics')));
    expect(map, isNot(contains('resolvedProfile')));
    expect(map, isNot(contains('resolvedCache')));
    expect(jsonEncode(map), isNot(contains('base64')));
    expect(jsonEncode(map), isNot(contains('requestHeaders')));
  });

  test('timestamps and revisions are strictly validated', () {
    final invalidRevision = jsonCopy();
    (invalidRevision['metadata']! as Map)['revision'] = -1;
    expect(
      codec.fromPersistenceMap(invalidRevision).status,
      WardrobeProfileDecodeStatus.invalid,
    );

    final invalidTimestamp = jsonCopy();
    (invalidTimestamp['metadata']! as Map)['updatedAt'] = 'not-a-date';
    expect(
      codec.fromPersistenceMap(invalidTimestamp).status,
      WardrobeProfileDecodeStatus.invalid,
    );
  });

  test('decode distinguishes missing unsupported invalid and valid', () {
    expect(
      codec.fromPersistenceMap(null).status,
      WardrobeProfileDecodeStatus.missing,
    );

    final unsupported = jsonCopy();
    (unsupported['metadata']! as Map)['schemaVersion'] = 2;
    expect(
      codec.fromPersistenceMap(unsupported).status,
      WardrobeProfileDecodeStatus.unsupportedVersion,
    );
    expect(
      codec.fromPersistenceMap({'bad': true}).status,
      WardrobeProfileDecodeStatus.invalid,
    );
    expect(
      codec.fromPersistenceMap(jsonCopy()).status,
      WardrobeProfileDecodeStatus.valid,
    );
  });

  test('document decode distinguishes absent wardrobeProfile', () {
    expect(
      codec.fromDocumentMap(const {}).status,
      WardrobeProfileDecodeStatus.missing,
    );
    expect(
      codec.fromDocumentMap({
        WardrobeProfilePersistenceCodec.envelopeKey: jsonCopy(),
      }).status,
      WardrobeProfileDecodeStatus.valid,
    );
  });

  test('KB prior and resolved output cannot be persisted as evidence', () {
    expect(
      () => encoded(
        envelope(
          evidence: [canonical(source: EvidenceSource.knowledgeBasePrior)],
        ),
      ),
      throwsFormatException,
    );

    final map = encoded();
    expect(map, isNot(contains('resolvedProfile')));
    expect(map, isNot(contains('capabilities')));
    expect(map, isNot(contains('knowledgeBaseEvidence')));
  });

  test('non-value observation round-trips without a neutral default', () {
    final unknownHood = PersistedMachineEvidence(
      id: 'observation:analysis-1:hasHood',
      property: WardrobeProfileProperty.hasHood,
      value: null,
      valueState: EvidenceValueState.notVisible,
      source: EvidenceSource.visualObservation,
      nature: EvidenceNature.observed,
      confidence: 0,
      method: 'vision_observation',
      createdAt: created,
      modelVersion: 'gpt-4o-mini',
    );
    final result = codec.fromPersistenceMap(
      jsonCopy(envelope(evidence: [unknownHood])),
    );

    expect(result.status, WardrobeProfileDecodeStatus.valid);
    expect(result.envelope!.machineEvidence.single.value, isNull);
    expect(
      result.envelope!.machineEvidence.single.valueState,
      EvidenceValueState.notVisible,
    );
  });

  test('valid family machine evidence preserves qualification', () {
    final result = codec.fromPersistenceMap(
      jsonCopy(envelope(evidence: [family()])),
    );

    expect(result.status, WardrobeProfileDecodeStatus.valid);
    final restored = result.envelope!.machineEvidence.single;
    expect(restored.property, WardrobeProfileProperty.family);
    expect(restored.value, 'top');
    expect(
      restored.identityQualification,
      PersistedIdentityQualification.confirmed,
    );
  });

  test('family-only supported profile round-trips without canonical', () {
    final result = codec.fromPersistenceMap(
      jsonCopy(
        envelope(
          evidence: [
            family(qualification: PersistedIdentityQualification.supported),
          ],
        ),
      ),
    );

    expect(result.status, WardrobeProfileDecodeStatus.valid);
    expect(
      result.envelope!.machineEvidence.where(
        (item) => item.property == WardrobeProfileProperty.canonicalType,
      ),
      isEmpty,
    );
    expect(
      result.envelope!.machineEvidence.single.identityQualification,
      PersistedIdentityQualification.supported,
    );
  });

  test('family and canonical remain separate identity evidence', () {
    final result = codec.fromPersistenceMap(
      jsonCopy(envelope(evidence: [family(), canonical()])),
    );

    expect(result.status, WardrobeProfileDecodeStatus.valid);
    expect(
      result.envelope!.machineEvidence.map((item) => item.property).toSet(),
      {WardrobeProfileProperty.family, WardrobeProfileProperty.canonicalType},
    );
  });

  test('machine family and user family correction remain separate', () {
    final familyCorrection = PersistedUserCorrection(
      id: 'family-correction',
      property: WardrobeProfileProperty.family,
      action: UserCorrectionAction.rejected,
      value: null,
      rejectedValue: 'top',
      correctedAt: updated,
      method: 'wardrobe_item_edit',
    );
    final result = codec.fromPersistenceMap(
      jsonCopy(
        envelope(
          evidence: [family()],
          corrections: {WardrobeProfileProperty.family: familyCorrection},
        ),
      ),
    );

    expect(result.status, WardrobeProfileDecodeStatus.valid);
    expect(result.envelope!.machineEvidence.single.value, 'top');
    expect(
      result.envelope!.userCorrections[WardrobeProfileProperty.family]!.action,
      UserCorrectionAction.rejected,
    );
  });

  test('unknown family key is invalid', () {
    final map = jsonCopy(envelope(evidence: [family()]));
    ((map['machineEvidence']! as List).single as Map)['value'] =
        'invented_family';

    final result = codec.fromPersistenceMap(map);
    expect(result.status, WardrobeProfileDecodeStatus.invalid);
    expect(result.failureCode, contains('unknown_family_key'));
  });

  test('unqualified or forbidden family state is not persistable', () {
    final missingQualification = jsonCopy(envelope(evidence: [family()]));
    ((missingQualification['machineEvidence']! as List).single as Map).remove(
      'identityQualification',
    );
    expect(
      codec.fromPersistenceMap(missingQualification).status,
      WardrobeProfileDecodeStatus.invalid,
    );

    final invalidState = jsonCopy(envelope(evidence: [family()]));
    ((invalidState['machineEvidence']! as List).single
            as Map)['identityQualification'] =
        'invalid_input';
    expect(
      codec.fromPersistenceMap(invalidState).status,
      WardrobeProfileDecodeStatus.invalid,
    );
  });

  test('detail or cross-family state cannot masquerade as qualification', () {
    for (final state in [
      'conflicting',
      'insufficient_evidence',
      'invalid_input',
    ]) {
      final map = jsonCopy(envelope(evidence: [family()]));
      ((map['machineEvidence']! as List).single
              as Map)['identityQualification'] =
          state;
      expect(
        codec.fromPersistenceMap(map).status,
        WardrobeProfileDecodeStatus.invalid,
        reason: state,
      );
    }
  });

  test('item-specific capability inference is valid', () {
    final result = codec.fromPersistenceMap(
      jsonCopy(envelope(evidence: [capability()])),
    );
    expect(result.status, WardrobeProfileDecodeStatus.valid);
    expect(
      result.envelope!.machineEvidence.single.supportingEvidenceIds,
      hasLength(2),
    );
  });

  test('capability path rejects KB legacy and non-provider origins', () {
    for (final source in [
      EvidenceSource.knowledgeBasePrior,
      EvidenceSource.legacyFallback,
    ]) {
      expect(
        () => encoded(envelope(evidence: [capability(source: source)])),
        throwsFormatException,
      );
    }
    expect(
      () => encoded(
        envelope(evidence: [capability(method: 'resolved_profile_projection')]),
      ),
      throwsFormatException,
    );
  });
}
