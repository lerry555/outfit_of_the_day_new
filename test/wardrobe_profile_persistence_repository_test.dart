import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/qualified_vision_persistence_mapper.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_codec.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_repository.dart';

void main() {
  const codec = WardrobeProfilePersistenceCodec();
  const source = WardrobeItemSourceSnapshot(
    imageRevision: 2,
    wardrobeItemRevision: 7,
    storagePath: 'wardrobe/u/item.jpg',
    imageHash: 'image-hash',
    uploadGeneration: 'upload-2',
  );

  PersistedMachineEvidence evidence({
    String analysisId = 'analysis-1',
    Object value = false,
  }) => PersistedMachineEvidence(
    id: 'observation:$analysisId:hasHood',
    property: WardrobeProfileProperty.hasHood,
    value: value,
    valueState: EvidenceValueState.known,
    source: EvidenceSource.visualObservation,
    nature: EvidenceNature.observed,
    confidence: .9,
    method: 'vision_observation',
    createdAt: DateTime.utc(2026, 7, 29, 10),
    modelVersion: 'model-v1',
  );

  PersistedUserCorrection correction(
    UserCorrectionAction action, {
    String property = WardrobeProfileProperty.canonicalType,
  }) => PersistedUserCorrection(
    id: 'correction:${action.name}',
    property: property,
    action: action,
    value: action == UserCorrectionAction.set ? 'hoodie' : null,
    rejectedValue: action == UserCorrectionAction.rejected
        ? (property == WardrobeProfileProperty.formality ? 5 : 'jacket')
        : null,
    correctedAt: DateTime.utc(2026, 7, 29, 9),
    method: 'wardrobe_item_edit',
    actorId: 'owner',
  );

  WardrobeProfilePersistenceEnvelope envelope({
    int revision = 1,
    String generationId = 'generation-1',
    String analysisId = 'analysis-1',
    WardrobeItemSourceSnapshot envelopeSource = source,
    List<PersistedMachineEvidence>? machineEvidence,
    Map<String, PersistedUserCorrection> corrections = const {},
  }) => WardrobeProfilePersistenceEnvelope(
    metadata: WardrobeProfilePersistenceMetadata(
      generationId: generationId,
      revision: revision,
      createdAt: DateTime.utc(2026, 7, 29, 10),
      updatedAt: DateTime.utc(2026, 7, 29, 10, revision),
    ),
    source: WardrobeProfileSourceProvenance(
      imageRevision: envelopeSource.imageRevision,
      wardrobeItemRevision: envelopeSource.wardrobeItemRevision,
      storagePath: envelopeSource.storagePath,
      imageHash: envelopeSource.imageHash,
      uploadGeneration: envelopeSource.uploadGeneration,
    ),
    analysis: WardrobeProfileAnalysisProvenance(
      analysisId: analysisId,
      kind: revision == 1
          ? WardrobeAnalysisKind.initialAnalysis
          : WardrobeAnalysisKind.reanalysis,
      completedAt: DateTime.utc(2026, 7, 29, 10),
      modelIdentifier: 'model-v1',
      pipelineVersion: 'pipeline-v1',
      promptVersion: 'prompt-v1',
      visionSchemaVersion: 9,
      qualificationVersion: 'qualification-v1',
    ),
    machineEvidence:
        machineEvidence ??
        <PersistedMachineEvidence>[evidence(analysisId: analysisId)],
    userCorrections: corrections,
  );

  PersistMappedWardrobeProfileCommand command({
    WardrobeProfilePersistenceMappingResult? mapping,
    WardrobeProfilePersistenceEnvelope? value,
    WardrobeItemSourceSnapshot expectedSource = source,
    int? expectedRevision,
  }) => PersistMappedWardrobeProfileCommand(
    userId: 'user-1',
    wardrobeItemId: 'item-1',
    mappingResult:
        mapping ??
        WardrobeProfilePersistenceMappingResult.mapped(value ?? envelope()),
    expectedSource: expectedSource,
    expectedProfileRevision: expectedRevision,
  );

  Map<String, Object?> document([WardrobeProfilePersistenceEnvelope? value]) =>
      <String, Object?>{
        'name': 'Legacy shirt',
        'colors': <String>['blue'],
        if (value != null)
          WardrobeProfilePersistenceCodec.envelopeKey: codec.toPersistenceMap(
            value,
          ),
      };

  WardrobeProfileTransactionState state({
    bool exists = true,
    WardrobeItemSourceSnapshot? currentSource = source,
    WardrobeProfilePersistenceEnvelope? profile,
    Map<String, Object?>? raw,
  }) => WardrobeProfileTransactionState(
    exists: exists,
    source: currentSource,
    document: raw ?? document(profile),
  );

  const policy = WardrobeProfileTransactionalWritePolicy();

  WardrobeProfileTransactionDecision evaluate({
    required WardrobeProfileTransactionState current,
    required PersistMappedWardrobeProfileCommand write,
  }) => policy.evaluate(current: current, command: write);

  test('first valid generation creates a complete envelope patch', () {
    final decision = evaluate(current: state(), write: command());
    expect(decision.result.status, WardrobeProfileWriteStatus.created);
    expect(decision.documentPatch!.keys, ['wardrobeProfile']);
    expect(
      codec.fromDocumentMap(decision.documentPatch!).status,
      WardrobeProfileDecodeStatus.valid,
    );
  });

  test('new generation updates same current source revision', () {
    final next = envelope(
      revision: 2,
      generationId: 'generation-2',
      analysisId: 'analysis-2',
    );
    final decision = evaluate(
      current: state(profile: envelope()),
      write: command(value: next, expectedRevision: 1),
    );
    expect(decision.result.status, WardrobeProfileWriteStatus.updated);
  });

  test('all tri-state corrections survive an empty mapper map', () {
    final corrections = <String, PersistedUserCorrection>{
      'identity.canonicalType': correction(UserCorrectionAction.set),
      'capabilities.warmth': correction(
        UserCorrectionAction.cleared,
        property: WardrobeProfileProperty.warmth,
      ),
      'capabilities.formality': correction(
        UserCorrectionAction.rejected,
        property: WardrobeProfileProperty.formality,
      ),
    };
    final old = envelope(corrections: corrections);
    final next = envelope(
      revision: 2,
      generationId: 'generation-2',
      analysisId: 'analysis-2',
    );
    final decision = evaluate(
      current: state(profile: old),
      write: command(value: next, expectedRevision: 1),
    );
    final decoded = codec.fromDocumentMap(decision.documentPatch!);
    expect(
      decoded.envelope!.userCorrections.keys,
      unorderedEquals(corrections.keys),
    );
    for (final entry in corrections.entries) {
      final actual = decoded.envelope!.userCorrections[entry.key]!;
      expect(actual.action, entry.value.action);
      expect(actual.correctedAt, entry.value.correctedAt);
      expect(actual.method, entry.value.method);
    }
  });

  for (final mapping in <WardrobeProfilePersistenceMappingResult>[
    const WardrobeProfilePersistenceMappingResult.noPersistableEvidence('none'),
    const WardrobeProfilePersistenceMappingResult.invalidInput('invalid'),
    const WardrobeProfilePersistenceMappingResult.incompatibleInput('version'),
    const WardrobeProfilePersistenceMappingResult.mappingFailure('failure'),
  ]) {
    test('${mapping.status.name} never writes', () {
      final decision = evaluate(
        current: state(profile: envelope()),
        write: command(mapping: mapping, expectedRevision: 1),
      );
      expect(
        decision.result.status,
        WardrobeProfileWriteStatus.invalidWriteInput,
      );
      expect(decision.documentPatch, isNull);
    });
  }

  test('old image revision is stale', () {
    const oldSource = WardrobeItemSourceSnapshot(
      imageRevision: 1,
      wardrobeItemRevision: 7,
      storagePath: 'wardrobe/u/item.jpg',
      imageHash: 'image-hash',
      uploadGeneration: 'upload-2',
    );
    final decision = evaluate(
      current: state(),
      write: command(
        expectedSource: oldSource,
        value: envelope(envelopeSource: oldSource),
      ),
    );
    expect(decision.result.status, WardrobeProfileWriteStatus.staleRejected);
    expect(decision.result.reasonCode, 'image_revision_mismatch');
  });

  test('old wardrobe item revision is stale', () {
    const oldSource = WardrobeItemSourceSnapshot(
      imageRevision: 2,
      wardrobeItemRevision: 6,
      storagePath: 'wardrobe/u/item.jpg',
      imageHash: 'image-hash',
      uploadGeneration: 'upload-2',
    );
    final decision = evaluate(
      current: state(),
      write: command(
        expectedSource: oldSource,
        value: envelope(envelopeSource: oldSource),
      ),
    );
    expect(decision.result.reasonCode, 'wardrobe_item_revision_mismatch');
  });

  test('mismatched upload generation is stale', () {
    const oldSource = WardrobeItemSourceSnapshot(
      imageRevision: 2,
      wardrobeItemRevision: 7,
      storagePath: 'wardrobe/u/item.jpg',
      imageHash: 'image-hash',
      uploadGeneration: 'upload-1',
    );
    final decision = evaluate(
      current: state(),
      write: command(
        expectedSource: oldSource,
        value: envelope(envelopeSource: oldSource),
      ),
    );
    expect(decision.result.reasonCode, 'upload_generation_mismatch');
  });

  test('identical generation retry is an idempotent no-op', () {
    final current = envelope();
    final decision = evaluate(
      current: state(profile: current),
      write: command(value: current, expectedRevision: 1),
    );
    expect(decision.result.status, WardrobeProfileWriteStatus.alreadyApplied);
    expect(decision.documentPatch, isNull);
  });

  test('same generation identity with different content conflicts', () {
    final changed = envelope(machineEvidence: [evidence(value: true)]);
    final decision = evaluate(
      current: state(profile: envelope()),
      write: command(value: changed, expectedRevision: 1),
    );
    expect(decision.result.status, WardrobeProfileWriteStatus.revisionConflict);
    expect(
      decision.result.reasonCode,
      'generation_identity_reused_with_different_content',
    );
  });

  test('unknown higher existing schema fails closed', () {
    final raw = document(envelope());
    final profile = Map<String, Object?>.from(raw['wardrobeProfile']! as Map);
    final metadata = Map<String, Object?>.from(profile['metadata']! as Map);
    metadata['schemaVersion'] = 99;
    profile['metadata'] = metadata;
    raw['wardrobeProfile'] = profile;
    final decision = evaluate(
      current: state(raw: raw),
      write: command(expectedRevision: 1),
    );
    expect(
      decision.result.status,
      WardrobeProfileWriteStatus.unsupportedExistingVersion,
    );
  });

  test('invalid existing envelope fails closed', () {
    final decision = evaluate(
      current: state(
        raw: {
          'name': 'Legacy',
          'wardrobeProfile': {'bad': true},
        },
      ),
      write: command(expectedRevision: 1),
    );
    expect(
      decision.result.status,
      WardrobeProfileWriteStatus.invalidExistingProfile,
    );
  });

  test('missing item returns notFound', () {
    final decision = evaluate(
      current: state(exists: false, currentSource: null),
      write: command(),
    );
    expect(decision.result.status, WardrobeProfileWriteStatus.notFound);
  });

  test('invalid new envelope is rejected by codec before write', () {
    final invalid = WardrobeProfilePersistenceEnvelope(
      metadata: WardrobeProfilePersistenceMetadata(
        generationId: '',
        revision: 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      source: envelope().source,
      analysis: envelope().analysis,
      machineEvidence: envelope().machineEvidence,
      userCorrections: const {},
    );
    final decision = evaluate(
      current: state(),
      write: command(value: invalid),
    );
    expect(
      decision.result.status,
      WardrobeProfileWriteStatus.invalidWriteInput,
    );
    expect(decision.documentPatch, isNull);
  });

  test('patch changes no legacy fields and has no cache or history data', () {
    final before = state(raw: document()).document;
    final decision = evaluate(
      current: state(raw: before),
      write: command(),
    );
    expect(before, {
      'name': 'Legacy shirt',
      'colors': ['blue'],
    });
    expect(decision.documentPatch!.keys, ['wardrobeProfile']);
    expect(decision.documentPatch, isNot(contains('resolvedCache')));
    expect(decision.documentPatch, isNot(contains('history')));
    final profile = decision.documentPatch!['wardrobeProfile']! as Map;
    expect(profile['machineEvidence'], isA<List>());
  });

  test('revision must increase exactly once', () {
    final next = envelope(
      revision: 3,
      generationId: 'generation-2',
      analysisId: 'analysis-2',
    );
    final decision = evaluate(
      current: state(profile: envelope()),
      write: command(value: next, expectedRevision: 1),
    );
    expect(
      decision.result.status,
      WardrobeProfileWriteStatus.invalidWriteInput,
    );
  });

  test('missing trusted source snapshot fails authority closed', () {
    final decision = evaluate(
      current: state(currentSource: null),
      write: command(),
    );
    expect(decision.result.status, WardrobeProfileWriteStatus.authorityFailure);
  });

  test('authority-blocked production default can never write', () async {
    const repository = AuthorityBlockedWardrobeProfilePersistenceRepository();
    final result = await repository.persistMappedWardrobeProfile(command());
    expect(result.status, WardrobeProfileWriteStatus.authorityFailure);
  });

  test('store failures remain distinguishable from policy conflicts', () async {
    for (final entry
        in <WardrobeProfileStoreFailureKind, WardrobeProfileWriteStatus>{
          WardrobeProfileStoreFailureKind.permissionDenied:
              WardrobeProfileWriteStatus.authorityFailure,
          WardrobeProfileStoreFailureKind.transient:
              WardrobeProfileWriteStatus.transientFailure,
          WardrobeProfileStoreFailureKind.permanent:
              WardrobeProfileWriteStatus.permanentFailure,
        }.entries) {
      final repository = TrustedWardrobeProfilePersistenceRepository(
        store: _FailingStore(entry.key),
      );
      final result = await repository.persistMappedWardrobeProfile(command());
      expect(result.status, entry.value);
    }
  });

  test('serialized concurrent compare-and-set permits one commit', () async {
    final store = _MemoryTransactionalStore(state(profile: envelope()));
    final repository = TrustedWardrobeProfilePersistenceRepository(
      store: store,
    );
    final first = command(
      value: envelope(
        revision: 2,
        generationId: 'generation-2a',
        analysisId: 'analysis-2a',
      ),
      expectedRevision: 1,
    );
    final second = command(
      value: envelope(
        revision: 2,
        generationId: 'generation-2b',
        analysisId: 'analysis-2b',
      ),
      expectedRevision: 1,
    );
    final results = await Future.wait([
      repository.persistMappedWardrobeProfile(first),
      repository.persistMappedWardrobeProfile(second),
    ]);
    expect(
      results.map((result) => result.status),
      containsAll([
        WardrobeProfileWriteStatus.updated,
        WardrobeProfileWriteStatus.revisionConflict,
      ]),
    );
    expect(store.commitCount, 1);
  });

  test('deterministic retry survives correction map insertion order', () {
    final left = <String, PersistedUserCorrection>{
      'identity.canonicalType': correction(UserCorrectionAction.set),
      'capabilities.warmth': correction(
        UserCorrectionAction.cleared,
        property: WardrobeProfileProperty.warmth,
      ),
    };
    final right = <String, PersistedUserCorrection>{
      'capabilities.warmth': left['capabilities.warmth']!,
      'identity.canonicalType': left['identity.canonicalType']!,
    };
    final current = envelope(corrections: left);
    final incoming = envelope(corrections: right);
    final decision = evaluate(
      current: state(profile: current),
      write: command(value: incoming, expectedRevision: 1),
    );
    expect(decision.result.status, WardrobeProfileWriteStatus.alreadyApplied);
  });
}

final class _FailingStore implements WardrobeProfileTransactionalStore {
  const _FailingStore(this.kind);

  final WardrobeProfileStoreFailureKind kind;

  @override
  Future<WardrobeProfileWriteResult> runTransaction({
    required String userId,
    required String wardrobeItemId,
    required WardrobeProfileTransactionCallback transaction,
  }) => throw WardrobeProfileStoreFailure(kind, 'store_failure');
}

final class _MemoryTransactionalStore
    implements WardrobeProfileTransactionalStore {
  _MemoryTransactionalStore(this.state);

  WardrobeProfileTransactionState state;
  int commitCount = 0;
  Future<void> _tail = Future<void>.value();

  @override
  Future<WardrobeProfileWriteResult> runTransaction({
    required String userId,
    required String wardrobeItemId,
    required WardrobeProfileTransactionCallback transaction,
  }) {
    final completer = Completer<WardrobeProfileWriteResult>();
    _tail = _tail.then((_) {
      final decision = transaction(state);
      if (decision.documentPatch != null) {
        final next = Map<String, Object?>.from(state.document)
          ..addAll(decision.documentPatch!);
        state = WardrobeProfileTransactionState(
          exists: state.exists,
          source: state.source,
          document: next,
        );
        commitCount++;
      }
      completer.complete(decision.result);
    });
    return completer.future;
  }
}
