import 'wardrobe_profile_contract.dart';

abstract final class WardrobeProfilePersistenceVersions {
  static const int schema = 1;
  static const int evidence = 1;
  static const int resolverCompatibility = WardrobeProfileVersions.resolver;
}

enum PersistedProfileStatus {
  ready;

  String get wireName => name;
}

enum WardrobeAnalysisKind {
  initialAnalysis,
  reanalysis;

  String get wireName => switch (this) {
    WardrobeAnalysisKind.initialAnalysis => 'initial_analysis',
    WardrobeAnalysisKind.reanalysis => 'reanalysis',
  };
}

enum UserCorrectionAction {
  set,
  cleared,
  rejected;

  String get wireName => name;
}

enum PersistedIdentityQualification {
  confirmed,
  supported;

  String get wireName => name;
}

class WardrobeProfilePersistenceMetadata {
  const WardrobeProfilePersistenceMetadata({
    required this.generationId,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = WardrobeProfilePersistenceVersions.schema,
    this.evidenceSchemaVersion = WardrobeProfilePersistenceVersions.evidence,
    this.resolverCompatibilityVersion =
        WardrobeProfilePersistenceVersions.resolverCompatibility,
    this.status = PersistedProfileStatus.ready,
  });

  final int schemaVersion;
  final int evidenceSchemaVersion;
  final int resolverCompatibilityVersion;
  final String generationId;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final PersistedProfileStatus status;
}

class WardrobeProfileSourceProvenance {
  const WardrobeProfileSourceProvenance({
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

class WardrobeProfileAnalysisProvenance {
  const WardrobeProfileAnalysisProvenance({
    required this.analysisId,
    required this.kind,
    required this.completedAt,
    required this.modelIdentifier,
    required this.pipelineVersion,
    required this.promptVersion,
    required this.visionSchemaVersion,
    required this.qualificationVersion,
  });

  final String analysisId;
  final WardrobeAnalysisKind kind;
  final DateTime completedAt;
  final String modelIdentifier;
  final String pipelineVersion;
  final String promptVersion;
  final int visionSchemaVersion;
  final String qualificationVersion;
}

/// Compact, allow-listed machine assertion. It is evidence, not resolved truth.
class PersistedMachineEvidence {
  const PersistedMachineEvidence({
    required this.id,
    required this.property,
    required this.value,
    required this.valueState,
    required this.source,
    required this.nature,
    required this.confidence,
    required this.method,
    required this.createdAt,
    required this.modelVersion,
    this.identityQualification,
    this.supportingEvidenceIds = const <String>[],
  });

  final String id;
  final String property;
  final Object? value;
  final EvidenceValueState valueState;
  final EvidenceSource source;
  final EvidenceNature nature;
  final double confidence;
  final String method;
  final DateTime createdAt;
  final String modelVersion;
  final PersistedIdentityQualification? identityQualification;
  final List<String> supportingEvidenceIds;

  ProfileEvidence toRuntimeEvidence() => ProfileEvidence(
    id: id,
    property: property,
    value: value,
    valueState: valueState,
    source: source,
    nature: nature,
    confidence: confidence,
    method: method,
    createdAt: createdAt,
    modelVersion: modelVersion,
  );
}

/// A missing map entry means no correction. [action] distinguishes an explicit
/// value from an explicit clear or rejection.
class PersistedUserCorrection {
  const PersistedUserCorrection({
    required this.id,
    required this.property,
    required this.action,
    required this.value,
    required this.correctedAt,
    required this.method,
    this.rejectedValue,
    this.actorId,
    this.supersedesEvidenceId,
  });

  final String id;
  final String property;
  final UserCorrectionAction action;
  final Object? value;
  final Object? rejectedValue;
  final DateTime correctedAt;
  final String method;
  final String? actorId;
  final String? supersedesEvidenceId;

  ProfileEvidence toRuntimeEvidence() {
    if (action != UserCorrectionAction.set) {
      throw StateError(
        'Cleared and rejected corrections require read-path policy handling.',
      );
    }
    return ProfileEvidence(
      id: id,
      property: property,
      value: value,
      source: EvidenceSource.userCorrection,
      nature: EvidenceNature.observed,
      confidence: 1,
      verified: true,
      method: method,
      createdAt: correctedAt,
      supersedesEvidenceId: supersedesEvidenceId,
    );
  }
}

class WardrobeProfilePersistenceEnvelope {
  const WardrobeProfilePersistenceEnvelope({
    required this.metadata,
    required this.source,
    required this.analysis,
    required this.machineEvidence,
    required this.userCorrections,
  });

  final WardrobeProfilePersistenceMetadata metadata;
  final WardrobeProfileSourceProvenance source;
  final WardrobeProfileAnalysisProvenance analysis;
  final List<PersistedMachineEvidence> machineEvidence;
  final Map<String, PersistedUserCorrection> userCorrections;

  WardrobeProfilePersistenceEnvelope replaceMachineGeneration({
    required WardrobeProfilePersistenceMetadata metadata,
    required WardrobeProfileSourceProvenance source,
    required WardrobeProfileAnalysisProvenance analysis,
    required List<PersistedMachineEvidence> machineEvidence,
  }) => WardrobeProfilePersistenceEnvelope(
    metadata: metadata,
    source: source,
    analysis: analysis,
    machineEvidence: List.unmodifiable(machineEvidence),
    userCorrections: userCorrections,
  );
}

enum WardrobeProfileDecodeStatus { valid, missing, unsupportedVersion, invalid }

class WardrobeProfileDecodeResult {
  const WardrobeProfileDecodeResult._({
    required this.status,
    this.envelope,
    this.failureCode,
  });

  const WardrobeProfileDecodeResult.valid(
    WardrobeProfilePersistenceEnvelope envelope,
  ) : this._(status: WardrobeProfileDecodeStatus.valid, envelope: envelope);

  const WardrobeProfileDecodeResult.missing()
    : this._(status: WardrobeProfileDecodeStatus.missing);

  const WardrobeProfileDecodeResult.unsupportedVersion(String failureCode)
    : this._(
        status: WardrobeProfileDecodeStatus.unsupportedVersion,
        failureCode: failureCode,
      );

  const WardrobeProfileDecodeResult.invalid(String failureCode)
    : this._(
        status: WardrobeProfileDecodeStatus.invalid,
        failureCode: failureCode,
      );

  final WardrobeProfileDecodeStatus status;
  final WardrobeProfilePersistenceEnvelope? envelope;
  final String? failureCode;
}
