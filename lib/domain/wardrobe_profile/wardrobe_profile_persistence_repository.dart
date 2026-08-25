import 'dart:convert';

import 'qualified_vision_persistence_mapper.dart';
import 'wardrobe_profile_persistence_codec.dart';
import 'wardrobe_profile_persistence_contract.dart';

enum WardrobeProfileWriteStatus {
  created,
  updated,
  alreadyApplied,
  staleRejected,
  revisionConflict,
  unsupportedExistingVersion,
  invalidExistingProfile,
  invalidWriteInput,
  notFound,
  authorityFailure,
  transientFailure,
  permanentFailure,
}

final class WardrobeProfileWriteResult {
  const WardrobeProfileWriteResult({
    required this.status,
    required this.reasonCode,
    this.currentRevision,
    this.currentGenerationId,
  });

  final WardrobeProfileWriteStatus status;
  final String reasonCode;
  final int? currentRevision;
  final String? currentGenerationId;

  bool get applied =>
      status == WardrobeProfileWriteStatus.created ||
      status == WardrobeProfileWriteStatus.updated ||
      status == WardrobeProfileWriteStatus.alreadyApplied;
}

/// Source identity read by a trusted transaction from the wardrobe item.
///
/// These values are preconditions, not client-controlled ordering signals.
final class WardrobeItemSourceSnapshot {
  const WardrobeItemSourceSnapshot({
    required this.imageRevision,
    required this.wardrobeItemRevision,
    this.storagePath,
    this.imageHash,
    this.uploadGeneration,
  });

  final int imageRevision;
  final int wardrobeItemRevision;
  final String? storagePath;
  final String? imageHash;
  final String? uploadGeneration;
}

final class PersistMappedWardrobeProfileCommand {
  const PersistMappedWardrobeProfileCommand({
    required this.userId,
    required this.wardrobeItemId,
    required this.mappingResult,
    required this.expectedSource,
    required this.expectedProfileRevision,
  });

  final String userId;
  final String wardrobeItemId;
  final WardrobeProfilePersistenceMappingResult mappingResult;
  final WardrobeItemSourceSnapshot expectedSource;

  /// `null` means that no profile is expected. Updates use the exact revision
  /// read before analysis (compare-and-set).
  final int? expectedProfileRevision;
}

abstract interface class WardrobeProfilePersistenceRepository {
  Future<WardrobeProfileWriteResult> persistMappedWardrobeProfile(
    PersistMappedWardrobeProfileCommand command,
  );
}

enum WardrobeProfileStoreFailureKind { permissionDenied, transient, permanent }

final class WardrobeProfileStoreFailure implements Exception {
  const WardrobeProfileStoreFailure(this.kind, this.reasonCode);

  final WardrobeProfileStoreFailureKind kind;
  final String reasonCode;
}

typedef WardrobeProfileTransactionCallback =
    WardrobeProfileTransactionDecision Function(
      WardrobeProfileTransactionState current,
    );

/// Port that a trusted Admin-SDK adapter must implement with one real
/// Firestore transaction. The callback's complete envelope patch is committed
/// before [runTransaction] returns.
abstract interface class WardrobeProfileTransactionalStore {
  Future<WardrobeProfileWriteResult> runTransaction({
    required String userId,
    required String wardrobeItemId,
    required WardrobeProfileTransactionCallback transaction,
  });
}

/// Repository implementation intended only for a trusted backend adapter.
///
/// Supplying a client-SDK store would violate ADR-002. No such adapter is
/// provided or wired by Phase 5.2.
final class TrustedWardrobeProfilePersistenceRepository
    implements WardrobeProfilePersistenceRepository {
  const TrustedWardrobeProfilePersistenceRepository({
    required this.store,
    this.policy = const WardrobeProfileTransactionalWritePolicy(),
  });

  final WardrobeProfileTransactionalStore store;
  final WardrobeProfileTransactionalWritePolicy policy;

  @override
  Future<WardrobeProfileWriteResult> persistMappedWardrobeProfile(
    PersistMappedWardrobeProfileCommand command,
  ) async {
    try {
      return await store.runTransaction(
        userId: command.userId,
        wardrobeItemId: command.wardrobeItemId,
        transaction: (current) =>
            policy.evaluate(current: current, command: command),
      );
    } on WardrobeProfileStoreFailure catch (error) {
      return WardrobeProfileWriteResult(
        status: switch (error.kind) {
          WardrobeProfileStoreFailureKind.permissionDenied =>
            WardrobeProfileWriteStatus.authorityFailure,
          WardrobeProfileStoreFailureKind.transient =>
            WardrobeProfileWriteStatus.transientFailure,
          WardrobeProfileStoreFailureKind.permanent =>
            WardrobeProfileWriteStatus.permanentFailure,
        },
        reasonCode: error.reasonCode,
      );
    } on Object {
      return const WardrobeProfileWriteResult(
        status: WardrobeProfileWriteStatus.permanentFailure,
        reasonCode: 'unclassified_store_failure',
      );
    }
  }
}

/// Safe production default while qualification and source revisions are not
/// owned by the trusted backend. It cannot write Firestore.
final class AuthorityBlockedWardrobeProfilePersistenceRepository
    implements WardrobeProfilePersistenceRepository {
  const AuthorityBlockedWardrobeProfilePersistenceRepository();

  @override
  Future<WardrobeProfileWriteResult> persistMappedWardrobeProfile(
    PersistMappedWardrobeProfileCommand command,
  ) async => const WardrobeProfileWriteResult(
    status: WardrobeProfileWriteStatus.authorityFailure,
    reasonCode: 'trusted_persistence_boundary_not_available',
  );
}

final class WardrobeProfileTransactionState {
  const WardrobeProfileTransactionState({
    required this.exists,
    required this.source,
    required this.document,
  });

  final bool exists;
  final WardrobeItemSourceSnapshot? source;
  final Map<String, Object?> document;
}

final class WardrobeProfileTransactionDecision {
  const WardrobeProfileTransactionDecision.result(this.result)
    : documentPatch = null;

  const WardrobeProfileTransactionDecision.write(
    this.result,
    this.documentPatch,
  );

  final WardrobeProfileWriteResult result;

  /// A single-field patch containing the complete envelope.
  final Map<String, Object?>? documentPatch;
}

/// Pure compare-and-set policy for a future trusted Firestore transaction.
///
/// It performs no I/O and never creates evidence. A backend adapter must read
/// the item and apply [documentPatch] atomically in the same transaction.
final class WardrobeProfileTransactionalWritePolicy {
  const WardrobeProfileTransactionalWritePolicy({
    this.codec = const WardrobeProfilePersistenceCodec(),
  });

  final WardrobeProfilePersistenceCodec codec;

  WardrobeProfileTransactionDecision evaluate({
    required WardrobeProfileTransactionState current,
    required PersistMappedWardrobeProfileCommand command,
  }) {
    final inputFailure = _validateInput(command);
    if (inputFailure != null) {
      return WardrobeProfileTransactionDecision.result(inputFailure);
    }
    if (!current.exists) {
      return const WardrobeProfileTransactionDecision.result(
        WardrobeProfileWriteResult(
          status: WardrobeProfileWriteStatus.notFound,
          reasonCode: 'wardrobe_item_not_found',
        ),
      );
    }

    final currentSource = current.source;
    if (currentSource == null) {
      return const WardrobeProfileTransactionDecision.result(
        WardrobeProfileWriteResult(
          status: WardrobeProfileWriteStatus.authorityFailure,
          reasonCode: 'trusted_source_snapshot_missing',
        ),
      );
    }
    final sourceFailure = _compareSource(
      expected: command.expectedSource,
      actual: currentSource,
    );
    if (sourceFailure != null) {
      return WardrobeProfileTransactionDecision.result(sourceFailure);
    }

    final mapped = command.mappingResult.envelope!;
    final mappedSourceFailure = _compareEnvelopeSource(
      expected: command.expectedSource,
      envelope: mapped,
    );
    if (mappedSourceFailure != null) {
      return WardrobeProfileTransactionDecision.result(mappedSourceFailure);
    }

    final existing = codec.fromDocumentMap(current.document);
    switch (existing.status) {
      case WardrobeProfileDecodeStatus.unsupportedVersion:
        return WardrobeProfileTransactionDecision.result(
          WardrobeProfileWriteResult(
            status: WardrobeProfileWriteStatus.unsupportedExistingVersion,
            reasonCode: existing.failureCode ?? 'unsupported_existing_profile',
          ),
        );
      case WardrobeProfileDecodeStatus.invalid:
        return WardrobeProfileTransactionDecision.result(
          WardrobeProfileWriteResult(
            status: WardrobeProfileWriteStatus.invalidExistingProfile,
            reasonCode: existing.failureCode ?? 'invalid_existing_profile',
          ),
        );
      case WardrobeProfileDecodeStatus.missing:
        if (command.expectedProfileRevision != null) {
          return const WardrobeProfileTransactionDecision.result(
            WardrobeProfileWriteResult(
              status: WardrobeProfileWriteStatus.revisionConflict,
              reasonCode: 'profile_missing_but_revision_expected',
            ),
          );
        }
        if (mapped.metadata.revision != 1) {
          return const WardrobeProfileTransactionDecision.result(
            WardrobeProfileWriteResult(
              status: WardrobeProfileWriteStatus.invalidWriteInput,
              reasonCode: 'first_profile_revision_must_be_1',
            ),
          );
        }
        return _write(
          status: WardrobeProfileWriteStatus.created,
          reasonCode: 'profile_created',
          envelope: mapped,
        );
      case WardrobeProfileDecodeStatus.valid:
        break;
    }

    final old = existing.envelope!;
    final sameIdentity =
        old.metadata.generationId == mapped.metadata.generationId &&
        old.analysis.analysisId == mapped.analysis.analysisId;
    if (sameIdentity) {
      final incomingWithCorrections = mapped.replaceMachineGeneration(
        metadata: mapped.metadata,
        source: mapped.source,
        analysis: mapped.analysis,
        machineEvidence: mapped.machineEvidence,
      );
      final merged = WardrobeProfilePersistenceEnvelope(
        metadata: incomingWithCorrections.metadata,
        source: incomingWithCorrections.source,
        analysis: incomingWithCorrections.analysis,
        machineEvidence: incomingWithCorrections.machineEvidence,
        userCorrections: old.userCorrections,
      );
      if (_fingerprint(old) == _fingerprint(merged)) {
        return WardrobeProfileTransactionDecision.result(
          WardrobeProfileWriteResult(
            status: WardrobeProfileWriteStatus.alreadyApplied,
            reasonCode: 'identical_generation_already_applied',
            currentRevision: old.metadata.revision,
            currentGenerationId: old.metadata.generationId,
          ),
        );
      }
      return WardrobeProfileTransactionDecision.result(
        WardrobeProfileWriteResult(
          status: WardrobeProfileWriteStatus.revisionConflict,
          reasonCode: 'generation_identity_reused_with_different_content',
          currentRevision: old.metadata.revision,
          currentGenerationId: old.metadata.generationId,
        ),
      );
    }

    if (command.expectedProfileRevision != old.metadata.revision) {
      return WardrobeProfileTransactionDecision.result(
        WardrobeProfileWriteResult(
          status: WardrobeProfileWriteStatus.revisionConflict,
          reasonCode: 'expected_profile_revision_mismatch',
          currentRevision: old.metadata.revision,
          currentGenerationId: old.metadata.generationId,
        ),
      );
    }
    if (mapped.metadata.revision != old.metadata.revision + 1) {
      return WardrobeProfileTransactionDecision.result(
        WardrobeProfileWriteResult(
          status: WardrobeProfileWriteStatus.invalidWriteInput,
          reasonCode: 'profile_revision_must_increment_by_one',
          currentRevision: old.metadata.revision,
          currentGenerationId: old.metadata.generationId,
        ),
      );
    }

    final merged = WardrobeProfilePersistenceEnvelope(
      metadata: mapped.metadata,
      source: mapped.source,
      analysis: mapped.analysis,
      machineEvidence: mapped.machineEvidence,
      userCorrections: old.userCorrections,
    );
    return _write(
      status: WardrobeProfileWriteStatus.updated,
      reasonCode: 'profile_generation_updated',
      envelope: merged,
    );
  }

  WardrobeProfileWriteResult? _validateInput(
    PersistMappedWardrobeProfileCommand command,
  ) {
    if (command.userId.trim().isEmpty ||
        command.wardrobeItemId.trim().isEmpty) {
      return const WardrobeProfileWriteResult(
        status: WardrobeProfileWriteStatus.invalidWriteInput,
        reasonCode: 'stable_identifiers_required',
      );
    }
    if (command.mappingResult.status !=
            WardrobeProfilePersistenceMappingStatus.mapped ||
        command.mappingResult.envelope == null) {
      return const WardrobeProfileWriteResult(
        status: WardrobeProfileWriteStatus.invalidWriteInput,
        reasonCode: 'mapped_envelope_required',
      );
    }
    try {
      final encoded = codec.toPersistenceMap(command.mappingResult.envelope!);
      final decoded = codec.fromPersistenceMap(encoded);
      if (decoded.status != WardrobeProfileDecodeStatus.valid) {
        return WardrobeProfileWriteResult(
          status: WardrobeProfileWriteStatus.invalidWriteInput,
          reasonCode: decoded.failureCode ?? 'envelope_codec_validation_failed',
        );
      }
    } on Object {
      return const WardrobeProfileWriteResult(
        status: WardrobeProfileWriteStatus.invalidWriteInput,
        reasonCode: 'envelope_codec_validation_failed',
      );
    }
    return null;
  }

  WardrobeProfileWriteResult? _compareSource({
    required WardrobeItemSourceSnapshot expected,
    required WardrobeItemSourceSnapshot actual,
  }) {
    if (expected.imageRevision != actual.imageRevision) {
      return _stale('image_revision_mismatch');
    }
    if (expected.wardrobeItemRevision != actual.wardrobeItemRevision) {
      return _stale('wardrobe_item_revision_mismatch');
    }
    if (expected.uploadGeneration != actual.uploadGeneration) {
      return _stale('upload_generation_mismatch');
    }
    if (expected.storagePath != actual.storagePath ||
        expected.imageHash != actual.imageHash) {
      return _stale('image_identity_mismatch');
    }
    return null;
  }

  WardrobeProfileWriteResult? _compareEnvelopeSource({
    required WardrobeItemSourceSnapshot expected,
    required WardrobeProfilePersistenceEnvelope envelope,
  }) => _compareSource(
    expected: expected,
    actual: WardrobeItemSourceSnapshot(
      imageRevision: envelope.source.imageRevision,
      wardrobeItemRevision: envelope.source.wardrobeItemRevision,
      storagePath: envelope.source.storagePath,
      imageHash: envelope.source.imageHash,
      uploadGeneration: envelope.source.uploadGeneration,
    ),
  );

  WardrobeProfileWriteResult _stale(String reasonCode) =>
      WardrobeProfileWriteResult(
        status: WardrobeProfileWriteStatus.staleRejected,
        reasonCode: reasonCode,
      );

  WardrobeProfileTransactionDecision _write({
    required WardrobeProfileWriteStatus status,
    required String reasonCode,
    required WardrobeProfilePersistenceEnvelope envelope,
  }) => WardrobeProfileTransactionDecision.write(
    WardrobeProfileWriteResult(
      status: status,
      reasonCode: reasonCode,
      currentRevision: envelope.metadata.revision,
      currentGenerationId: envelope.metadata.generationId,
    ),
    <String, Object?>{
      WardrobeProfilePersistenceCodec.envelopeKey: codec.toPersistenceMap(
        envelope,
      ),
    },
  );

  String _fingerprint(WardrobeProfilePersistenceEnvelope envelope) =>
      jsonEncode(_canonicalize(codec.toPersistenceMap(envelope)));

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList(growable: false);
    return value;
  }
}
