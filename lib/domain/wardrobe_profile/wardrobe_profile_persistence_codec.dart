import 'dart:convert';

import 'vision_family_identity.dart';
import 'wardrobe_profile_contract.dart';
import 'wardrobe_profile_persistence_contract.dart';

abstract final class WardrobeProfilePersistencePolicy {
  static const machineEvidenceProperties = <String>{
    WardrobeProfileProperty.family,
    WardrobeProfileProperty.canonicalType,
    WardrobeProfileProperty.coverage,
    WardrobeProfileProperty.hasHood,
    WardrobeProfileProperty.frontClosure,
    WardrobeProfileProperty.visibleBulk,
    WardrobeProfileProperty.surfaceAppearance,
    WardrobeProfileProperty.necklineShape,
    WardrobeProfileProperty.visiblePocketStructure,
    WardrobeProfileProperty.visibleStretchCue,
    WardrobeProfileProperty.sportyCues,
    WardrobeProfileProperty.formalCues,
    WardrobeProfileProperty.footwearConstruction,
    WardrobeProfileProperty.footwearFastening,
    WardrobeProfileProperty.soleProfile,
    WardrobeProfileProperty.visibleTread,
    WardrobeProfileProperty.footwearUpperHeight,
    WardrobeProfileProperty.warmth,
    WardrobeProfileProperty.formality,
    WardrobeProfileProperty.supportedLayerRoles,
    WardrobeProfileProperty.mobility,
    WardrobeProfileProperty.breathability,
    WardrobeProfileProperty.walkingComfort,
    WardrobeProfileProperty.traction,
  };

  static const userCorrectionProperties = <String>{
    WardrobeProfileProperty.family,
    WardrobeProfileProperty.canonicalType,
    WardrobeProfileProperty.colors,
    WardrobeProfileProperty.patterns,
    WardrobeProfileProperty.styles,
    WardrobeProfileProperty.fit,
    WardrobeProfileProperty.warmth,
    WardrobeProfileProperty.formality,
    WardrobeProfileProperty.layerRole,
    WardrobeProfileProperty.mobility,
    WardrobeProfileProperty.breathability,
    WardrobeProfileProperty.windProtection,
    WardrobeProfileProperty.rainProtection,
    WardrobeProfileProperty.walkingComfort,
    WardrobeProfileProperty.traction,
    WardrobeProfileProperty.seasons,
    WardrobeProfileProperty.occasions,
    WardrobeProfileProperty.activities,
    WardrobeProfileProperty.terrain,
  };
}

final class WardrobeProfilePersistenceCodec {
  const WardrobeProfilePersistenceCodec();

  static const String envelopeKey = 'wardrobeProfile';

  Map<String, Object?> toPersistenceMap(
    WardrobeProfilePersistenceEnvelope envelope,
  ) {
    _validateEnvelope(envelope);
    return <String, Object?>{
      'metadata': <String, Object?>{
        'schemaVersion': envelope.metadata.schemaVersion,
        'evidenceSchemaVersion': envelope.metadata.evidenceSchemaVersion,
        'resolverCompatibilityVersion':
            envelope.metadata.resolverCompatibilityVersion,
        'generationId': envelope.metadata.generationId,
        'revision': envelope.metadata.revision,
        'createdAt': _time(envelope.metadata.createdAt),
        'updatedAt': _time(envelope.metadata.updatedAt),
        'status': envelope.metadata.status.wireName,
      },
      'source': <String, Object?>{
        'imageRevision': envelope.source.imageRevision,
        'wardrobeItemRevision': envelope.source.wardrobeItemRevision,
        if (envelope.source.storagePath != null)
          'storagePath': envelope.source.storagePath,
        if (envelope.source.imageHash != null)
          'imageHash': envelope.source.imageHash,
        if (envelope.source.uploadGeneration != null)
          'uploadGeneration': envelope.source.uploadGeneration,
      },
      'analysis': <String, Object?>{
        'analysisId': envelope.analysis.analysisId,
        'kind': envelope.analysis.kind.wireName,
        'completedAt': _time(envelope.analysis.completedAt),
        'modelIdentifier': envelope.analysis.modelIdentifier,
        'pipelineVersion': envelope.analysis.pipelineVersion,
        'promptVersion': envelope.analysis.promptVersion,
        'visionSchemaVersion': envelope.analysis.visionSchemaVersion,
        'qualificationVersion': envelope.analysis.qualificationVersion,
      },
      'machineEvidence':
          (envelope.machineEvidence.toList()
                ..sort((left, right) => left.id.compareTo(right.id)))
              .map(_encodeMachineEvidence)
              .toList(growable: false),
      'userCorrections': <String, Object?>{
        for (final entry in _sortedCorrections(envelope.userCorrections))
          entry.key: _encodeCorrection(entry.value),
      },
    };
  }

  String toJson(WardrobeProfilePersistenceEnvelope envelope) =>
      jsonEncode(toPersistenceMap(envelope));

  WardrobeProfileDecodeResult fromDocumentMap(Map<String, Object?> document) =>
      fromPersistenceMap(document[envelopeKey]);

  WardrobeProfileDecodeResult fromJson(String source) {
    try {
      return fromPersistenceMap(jsonDecode(source));
    } on FormatException {
      return const WardrobeProfileDecodeResult.invalid('invalid_json');
    }
  }

  WardrobeProfileDecodeResult fromPersistenceMap(Object? raw) {
    if (raw == null) return const WardrobeProfileDecodeResult.missing();
    try {
      final root = _object(raw, 'envelope');
      final metadata = _object(root['metadata'], 'metadata');
      final schemaVersion = _integer(
        metadata['schemaVersion'],
        'metadata.schemaVersion',
      );
      if (schemaVersion != WardrobeProfilePersistenceVersions.schema) {
        return WardrobeProfileDecodeResult.unsupportedVersion(
          'unsupported_schema_version:$schemaVersion',
        );
      }
      final evidenceVersion = _integer(
        metadata['evidenceSchemaVersion'],
        'metadata.evidenceSchemaVersion',
      );
      if (evidenceVersion != WardrobeProfilePersistenceVersions.evidence) {
        return WardrobeProfileDecodeResult.unsupportedVersion(
          'unsupported_evidence_schema_version:$evidenceVersion',
        );
      }

      final source = _object(root['source'], 'source');
      final analysis = _object(root['analysis'], 'analysis');
      final machineRaw = root['machineEvidence'];
      final correctionsRaw = _object(
        root['userCorrections'],
        'userCorrections',
      );
      if (machineRaw is! List) {
        throw const FormatException('machineEvidence.required_list');
      }

      final envelope = WardrobeProfilePersistenceEnvelope(
        metadata: WardrobeProfilePersistenceMetadata(
          schemaVersion: schemaVersion,
          evidenceSchemaVersion: evidenceVersion,
          resolverCompatibilityVersion: _positiveInt(
            metadata['resolverCompatibilityVersion'],
            'metadata.resolverCompatibilityVersion',
          ),
          generationId: _text(
            metadata['generationId'],
            'metadata.generationId',
          ),
          revision: _nonNegativeInt(metadata['revision'], 'metadata.revision'),
          createdAt: _date(metadata['createdAt'], 'metadata.createdAt'),
          updatedAt: _date(metadata['updatedAt'], 'metadata.updatedAt'),
          status: _enumValue(
            metadata['status'],
            'metadata.status',
            PersistedProfileStatus.values,
            (value) => value.wireName,
          ),
        ),
        source: WardrobeProfileSourceProvenance(
          imageRevision: _nonNegativeInt(
            source['imageRevision'],
            'source.imageRevision',
          ),
          wardrobeItemRevision: _nonNegativeInt(
            source['wardrobeItemRevision'],
            'source.wardrobeItemRevision',
          ),
          storagePath: _optionalText(source['storagePath']),
          imageHash: _optionalText(source['imageHash']),
          uploadGeneration: _optionalText(source['uploadGeneration']),
        ),
        analysis: WardrobeProfileAnalysisProvenance(
          analysisId: _text(analysis['analysisId'], 'analysis.analysisId'),
          kind: _enumValue(
            analysis['kind'],
            'analysis.kind',
            WardrobeAnalysisKind.values,
            (value) => value.wireName,
          ),
          completedAt: _date(analysis['completedAt'], 'analysis.completedAt'),
          modelIdentifier: _text(
            analysis['modelIdentifier'],
            'analysis.modelIdentifier',
          ),
          pipelineVersion: _text(
            analysis['pipelineVersion'],
            'analysis.pipelineVersion',
          ),
          promptVersion: _text(
            analysis['promptVersion'],
            'analysis.promptVersion',
          ),
          visionSchemaVersion: _positiveInt(
            analysis['visionSchemaVersion'],
            'analysis.visionSchemaVersion',
          ),
          qualificationVersion: _text(
            analysis['qualificationVersion'],
            'analysis.qualificationVersion',
          ),
        ),
        machineEvidence: List.unmodifiable(
          machineRaw.map(_decodeMachineEvidence),
        ),
        userCorrections: Map.unmodifiable({
          for (final entry in correctionsRaw.entries)
            entry.key: _decodeCorrection(entry.key, entry.value),
        }),
      );
      _validateEnvelope(envelope);
      return WardrobeProfileDecodeResult.valid(envelope);
    } on FormatException catch (error) {
      return WardrobeProfileDecodeResult.invalid(error.message.toString());
    } on ArgumentError catch (error) {
      return WardrobeProfileDecodeResult.invalid(error.message.toString());
    } on TypeError {
      return const WardrobeProfileDecodeResult.invalid('invalid_type');
    }
  }

  Map<String, Object?> _encodeMachineEvidence(
    PersistedMachineEvidence evidence,
  ) => <String, Object?>{
    'id': evidence.id,
    'property': evidence.property,
    'value': evidence.value,
    'valueState': evidence.valueState.wireName,
    'source': evidence.source.wireName,
    'nature': evidence.nature.wireName,
    'confidence': evidence.confidence,
    'method': evidence.method,
    'createdAt': _time(evidence.createdAt),
    'modelVersion': evidence.modelVersion,
    if (evidence.identityQualification != null)
      'identityQualification': evidence.identityQualification!.wireName,
    if (evidence.supportingEvidenceIds.isNotEmpty)
      'supportingEvidenceIds': evidence.supportingEvidenceIds,
  };

  PersistedMachineEvidence _decodeMachineEvidence(Object? raw) {
    final map = _object(raw, 'machineEvidence.item');
    final evidence = PersistedMachineEvidence(
      id: _text(map['id'], 'machineEvidence.id'),
      property: _text(map['property'], 'machineEvidence.property'),
      value: map['value'],
      valueState: _enumValue(
        map['valueState'],
        'machineEvidence.valueState',
        EvidenceValueState.values,
        (value) => value.wireName,
      ),
      source: _enumValue(
        map['source'],
        'machineEvidence.source',
        EvidenceSource.values,
        (value) => value.wireName,
      ),
      nature: _enumValue(
        map['nature'],
        'machineEvidence.nature',
        EvidenceNature.values,
        (value) => value.wireName,
      ),
      confidence: _confidence(map['confidence'], 'machineEvidence.confidence'),
      method: _text(map['method'], 'machineEvidence.method'),
      createdAt: _date(map['createdAt'], 'machineEvidence.createdAt'),
      modelVersion: _text(map['modelVersion'], 'machineEvidence.modelVersion'),
      identityQualification: map['identityQualification'] == null
          ? null
          : _enumValue<PersistedIdentityQualification>(
              map['identityQualification'],
              'machineEvidence.identityQualification',
              PersistedIdentityQualification.values,
              (value) => value.wireName,
            ),
      supportingEvidenceIds: _stringList(
        map['supportingEvidenceIds'],
        'machineEvidence.supportingEvidenceIds',
        optional: true,
      ),
    );
    _validateMachineEvidence(evidence);
    return evidence;
  }

  Map<String, Object?> _encodeCorrection(PersistedUserCorrection correction) =>
      <String, Object?>{
        'id': correction.id,
        'property': correction.property,
        'action': correction.action.wireName,
        if (correction.action == UserCorrectionAction.set)
          'value': correction.value,
        if (correction.action == UserCorrectionAction.rejected)
          'rejectedValue': correction.rejectedValue,
        'correctedAt': _time(correction.correctedAt),
        'method': correction.method,
        if (correction.actorId != null) 'actorId': correction.actorId,
        if (correction.supersedesEvidenceId != null)
          'supersedesEvidenceId': correction.supersedesEvidenceId,
      };

  PersistedUserCorrection _decodeCorrection(String key, Object? raw) {
    final map = _object(raw, 'userCorrections.$key');
    final correction = PersistedUserCorrection(
      id: _text(map['id'], 'userCorrections.$key.id'),
      property: _text(map['property'], 'userCorrections.$key.property'),
      action: _enumValue(
        map['action'],
        'userCorrections.$key.action',
        UserCorrectionAction.values,
        (value) => value.wireName,
      ),
      value: map['value'],
      rejectedValue: map['rejectedValue'],
      correctedAt: _date(
        map['correctedAt'],
        'userCorrections.$key.correctedAt',
      ),
      method: _text(map['method'], 'userCorrections.$key.method'),
      actorId: _optionalText(map['actorId']),
      supersedesEvidenceId: _optionalText(map['supersedesEvidenceId']),
    );
    if (key != correction.property) {
      throw FormatException('userCorrections.$key.property_mismatch');
    }
    _validateCorrection(correction);
    return correction;
  }

  void _validateEnvelope(WardrobeProfilePersistenceEnvelope envelope) {
    final metadata = envelope.metadata;
    if (metadata.schemaVersion != WardrobeProfilePersistenceVersions.schema ||
        metadata.evidenceSchemaVersion !=
            WardrobeProfilePersistenceVersions.evidence) {
      throw const FormatException('unsupported_persistence_version');
    }
    if (metadata.resolverCompatibilityVersion <= 0 ||
        metadata.generationId.trim().isEmpty ||
        metadata.revision < 0 ||
        metadata.updatedAt.isBefore(metadata.createdAt)) {
      throw const FormatException('invalid_metadata');
    }
    if (envelope.source.imageRevision < 0 ||
        envelope.source.wardrobeItemRevision < 0) {
      throw const FormatException('invalid_source_revision');
    }
    final analysis = envelope.analysis;
    if (analysis.analysisId.trim().isEmpty ||
        analysis.modelIdentifier.trim().isEmpty ||
        analysis.pipelineVersion.trim().isEmpty ||
        analysis.promptVersion.trim().isEmpty ||
        analysis.qualificationVersion.trim().isEmpty ||
        analysis.visionSchemaVersion <= 0) {
      throw const FormatException('invalid_analysis');
    }
    final ids = <String>{};
    for (final evidence in envelope.machineEvidence) {
      _validateMachineEvidence(evidence);
      if (!ids.add(evidence.id)) {
        throw const FormatException('duplicate_machine_evidence_id');
      }
    }
    for (final entry in envelope.userCorrections.entries) {
      if (entry.key != entry.value.property) {
        throw const FormatException('user_correction_property_mismatch');
      }
      _validateCorrection(entry.value);
    }
  }

  void _validateMachineEvidence(PersistedMachineEvidence evidence) {
    if (evidence.id.trim().isEmpty ||
        evidence.method.trim().isEmpty ||
        evidence.modelVersion.trim().isEmpty ||
        !WardrobeProfilePersistencePolicy.machineEvidenceProperties.contains(
          evidence.property,
        )) {
      throw const FormatException('machine_evidence_not_allow_listed');
    }
    if (evidence.source != EvidenceSource.visualObservation &&
        evidence.source != EvidenceSource.aiInference) {
      throw const FormatException('machine_evidence_source_forbidden');
    }
    if (evidence.source == EvidenceSource.visualObservation &&
        evidence.nature != EvidenceNature.observed) {
      throw const FormatException('visual_evidence_nature_invalid');
    }
    if (evidence.source == EvidenceSource.aiInference &&
        evidence.nature != EvidenceNature.inferred) {
      throw const FormatException('ai_evidence_nature_invalid');
    }
    final isIdentity =
        evidence.property == WardrobeProfileProperty.family ||
        evidence.property == WardrobeProfileProperty.canonicalType;
    if (isIdentity) {
      if (evidence.source != EvidenceSource.aiInference ||
          evidence.identityQualification == null ||
          !evidence.method.startsWith('vision_') ||
          evidence.supportingEvidenceIds.isEmpty) {
        throw const FormatException('qualified_identity_evidence_required');
      }
    } else if (evidence.identityQualification != null) {
      throw const FormatException(
        'identity_qualification_for_non_identity_evidence',
      );
    }
    if (_capabilityInferenceProperties.contains(evidence.property) &&
        (evidence.source != EvidenceSource.aiInference ||
            evidence.nature != EvidenceNature.inferred ||
            !evidence.method.startsWith('capability_inference:') ||
            evidence.supportingEvidenceIds.isEmpty)) {
      throw const FormatException(
        'item_specific_capability_provenance_required',
      );
    }
    if (!evidence.confidence.isFinite ||
        evidence.confidence < 0 ||
        evidence.confidence > 1) {
      throw const FormatException('machine_evidence_confidence_invalid');
    }
    if (evidence.valueState == EvidenceValueState.known) {
      if (evidence.value == null) {
        throw const FormatException('known_machine_evidence_value_required');
      }
      _validatePropertyValue(evidence.property, evidence.value);
    } else if (evidence.value != null) {
      throw const FormatException('non_value_machine_evidence_must_be_null');
    }
  }

  void _validateCorrection(PersistedUserCorrection correction) {
    if (correction.id.trim().isEmpty ||
        correction.method.trim().isEmpty ||
        !WardrobeProfilePersistencePolicy.userCorrectionProperties.contains(
          correction.property,
        )) {
      throw const FormatException('user_correction_not_allow_listed');
    }
    switch (correction.action) {
      case UserCorrectionAction.set:
        if (correction.value == null || correction.rejectedValue != null) {
          throw const FormatException('set_correction_value_invalid');
        }
        _validatePropertyValue(correction.property, correction.value);
      case UserCorrectionAction.cleared:
        if (correction.value != null || correction.rejectedValue != null) {
          throw const FormatException('cleared_correction_value_invalid');
        }
      case UserCorrectionAction.rejected:
        if (correction.value != null || correction.rejectedValue == null) {
          throw const FormatException('rejected_correction_value_invalid');
        }
        _validatePropertyValue(correction.property, correction.rejectedValue);
    }
  }

  void _validatePropertyValue(String property, Object? value) {
    if (!_isJsonValue(value)) {
      throw FormatException('non_json_value:$property');
    }
    if (property == WardrobeProfileProperty.canonicalType) {
      if (value is! String ||
          !VisionCanonicalFamilyRegistry.canonicalToFamily.containsKey(value)) {
        throw FormatException('unknown_canonical_key:$value');
      }
      return;
    }
    if (property == WardrobeProfileProperty.family) {
      if (value is! String ||
          !VisionIdentityFamily.values.any((item) => item.wireName == value)) {
        throw FormatException('unknown_family_key:$value');
      }
      return;
    }
    if (property == WardrobeProfileProperty.hasHood ||
        property == WardrobeProfileProperty.visibleStretchCue) {
      if (value is! bool) throw FormatException('invalid_bool:$property');
      return;
    }
    if (property == WardrobeProfileProperty.warmth ||
        property == WardrobeProfileProperty.formality) {
      if (value is! int || value < 0 || value > 10) {
        throw FormatException('invalid_scale:$property');
      }
      return;
    }
    if (_collectionProperties.contains(property)) {
      if (value is! List ||
          value.any((item) => item is! String || item.trim().isEmpty)) {
        throw FormatException('invalid_string_collection:$property');
      }
      if (property == WardrobeProfileProperty.supportedLayerRoles &&
          value.any(
            (item) =>
                !WardrobeLayerRole.values.any((role) => role.wireName == item),
          )) {
        throw const FormatException('unknown_layer_role');
      }
      return;
    }
    final allowed = _enumValues[property];
    if (allowed != null && (value is! String || !allowed.contains(value))) {
      throw FormatException('unknown_enum_value:$property:$value');
    }
  }

  static const _collectionProperties = <String>{
    WardrobeProfileProperty.colors,
    WardrobeProfileProperty.patterns,
    WardrobeProfileProperty.styles,
    WardrobeProfileProperty.seasons,
    WardrobeProfileProperty.occasions,
    WardrobeProfileProperty.activities,
    WardrobeProfileProperty.terrain,
    WardrobeProfileProperty.supportedLayerRoles,
  };

  static const _capabilityInferenceProperties = <String>{
    WardrobeProfileProperty.warmth,
    WardrobeProfileProperty.formality,
    WardrobeProfileProperty.supportedLayerRoles,
    WardrobeProfileProperty.mobility,
    WardrobeProfileProperty.breathability,
    WardrobeProfileProperty.walkingComfort,
    WardrobeProfileProperty.traction,
  };

  static const _enumValues = <String, Set<String>>{
    WardrobeProfileProperty.coverage: {'minimal', 'partial', 'full'},
    WardrobeProfileProperty.frontClosure: {
      'none',
      'partial_zip',
      'full_zip',
      'buttons',
      'snaps',
      'other',
    },
    WardrobeProfileProperty.visibleBulk: {'low', 'medium', 'high'},
    WardrobeProfileProperty.surfaceAppearance: {
      'knit',
      'woven',
      'fleece_like',
      'quilted',
      'smooth',
      'textured',
      'mesh',
      'leather_like',
    },
    WardrobeProfileProperty.necklineShape: {
      'crew',
      'v_neck',
      'scoop',
      'high_neck',
      'collared',
      'other',
    },
    WardrobeProfileProperty.visiblePocketStructure: {
      'none',
      'standard',
      'cargo',
      'patch',
      'other',
    },
    WardrobeProfileProperty.sportyCues: {'low', 'medium', 'high'},
    WardrobeProfileProperty.formalCues: {'low', 'medium', 'high'},
    WardrobeProfileProperty.footwearConstruction: {
      'open',
      'partially_open',
      'closed',
    },
    WardrobeProfileProperty.footwearFastening: {
      'laces',
      'zipper',
      'elastic_side_panels',
      'slip_on',
      'straps',
      'buckles',
      'other',
    },
    WardrobeProfileProperty.soleProfile: {'thin', 'standard', 'chunky'},
    WardrobeProfileProperty.visibleTread: {'low', 'moderate', 'pronounced'},
    WardrobeProfileProperty.footwearUpperHeight: {
      'low_cut',
      'ankle',
      'high_shaft',
    },
    WardrobeProfileProperty.mobility: {
      'unknown',
      'very_low',
      'low',
      'medium',
      'high',
      'very_high',
    },
    WardrobeProfileProperty.breathability: {
      'unknown',
      'very_low',
      'low',
      'medium',
      'high',
      'very_high',
    },
    WardrobeProfileProperty.walkingComfort: {
      'unknown',
      'very_low',
      'low',
      'medium',
      'high',
      'very_high',
    },
    WardrobeProfileProperty.traction: {
      'unknown',
      'very_low',
      'low',
      'medium',
      'high',
      'very_high',
    },
    WardrobeProfileProperty.windProtection: {
      'unknown',
      'very_low',
      'low',
      'medium',
      'high',
      'very_high',
    },
    WardrobeProfileProperty.rainProtection: {
      'unknown',
      'very_low',
      'low',
      'medium',
      'high',
      'very_high',
    },
    WardrobeProfileProperty.layerRole: {
      'unknown',
      'base_layer',
      'mid_layer',
      'outer_layer',
      'bottom',
      'footwear',
      'accessory',
    },
  };

  static List<MapEntry<String, PersistedUserCorrection>> _sortedCorrections(
    Map<String, PersistedUserCorrection> corrections,
  ) =>
      corrections.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));

  static Map<String, Object?> _object(Object? value, String path) {
    if (value is! Map) throw FormatException('$path.required_object');
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) throw FormatException('$path.invalid_key');
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static T _enumValue<T>(
    Object? raw,
    String path,
    List<T> values,
    String Function(T value) wireName,
  ) {
    if (raw is! String) throw FormatException('$path.required_string');
    for (final value in values) {
      if (wireName(value) == raw) return value;
    }
    throw FormatException('$path.unknown_enum:$raw');
  }

  static String _text(Object? value, String path) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$path.required_text');
    }
    return value;
  }

  static String? _optionalText(Object? value) {
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('optional_text.invalid');
    }
    return value;
  }

  static int _integer(Object? value, String path) {
    if (value is! int) throw FormatException('$path.required_int');
    return value;
  }

  static int _positiveInt(Object? value, String path) {
    final result = _integer(value, path);
    if (result <= 0) throw FormatException('$path.must_be_positive');
    return result;
  }

  static int _nonNegativeInt(Object? value, String path) {
    final result = _integer(value, path);
    if (result < 0) throw FormatException('$path.must_be_non_negative');
    return result;
  }

  static double _confidence(Object? value, String path) {
    if (value is! num || !value.isFinite || value < 0 || value > 1) {
      throw FormatException('$path.invalid');
    }
    return value.toDouble();
  }

  static DateTime _date(Object? value, String path) {
    if (value is! String) throw FormatException('$path.required_timestamp');
    final date = DateTime.tryParse(value);
    if (date == null || !date.isUtc) {
      throw FormatException('$path.invalid_timestamp');
    }
    return date;
  }

  static List<String> _stringList(
    Object? value,
    String path, {
    required bool optional,
  }) {
    if (value == null && optional) return const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('$path.invalid_list');
    }
    return List.unmodifiable(value.cast<String>());
  }

  static bool _isJsonValue(Object? value) {
    if (value == null || value is String || value is bool || value is num) {
      return true;
    }
    if (value is List) return value.every(_isJsonValue);
    if (value is Map) {
      return value.keys.every((key) => key is String) &&
          value.values.every(_isJsonValue);
    }
    return false;
  }

  static String _time(DateTime value) => value.toUtc().toIso8601String();
}
