import 'vision_family_identity.dart';
import 'vision_subject_safety.dart';
import 'vision_v2_shadow_analysis.dart';
import 'wardrobe_profile_contract.dart';
import 'wardrobe_profile_persistence_codec.dart';
import 'wardrobe_profile_persistence_contract.dart';

class PersistenceMappingContext {
  const PersistenceMappingContext({
    required this.generationId,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.imageRevision,
    required this.wardrobeItemRevision,
    required this.analysisId,
    required this.analysisKind,
    required this.completedAt,
    required this.modelIdentifier,
    required this.pipelineVersion,
    required this.promptVersion,
    required this.visionSchemaVersion,
    required this.qualificationVersion,
    this.storagePath,
    this.imageHash,
    this.uploadGeneration,
  });

  final String generationId;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int imageRevision;
  final int wardrobeItemRevision;
  final String? storagePath;
  final String? imageHash;
  final String? uploadGeneration;
  final String analysisId;
  final WardrobeAnalysisKind analysisKind;
  final DateTime completedAt;
  final String modelIdentifier;
  final String pipelineVersion;
  final String promptVersion;
  final int visionSchemaVersion;
  final String qualificationVersion;
}

enum WardrobeProfilePersistenceMappingStatus {
  mapped,
  noPersistableEvidence,
  invalidInput,
  incompatibleInput,
  mappingFailure,
}

class WardrobeProfilePersistenceMappingResult {
  const WardrobeProfilePersistenceMappingResult._({
    required this.status,
    this.envelope,
    this.reasonCode,
    this.omittedEvidenceReasonCodes = const <String>[],
  });

  const WardrobeProfilePersistenceMappingResult.mapped(
    WardrobeProfilePersistenceEnvelope envelope, {
    List<String> omittedEvidenceReasonCodes = const <String>[],
  }) : this._(
         status: WardrobeProfilePersistenceMappingStatus.mapped,
         envelope: envelope,
         omittedEvidenceReasonCodes: omittedEvidenceReasonCodes,
       );

  const WardrobeProfilePersistenceMappingResult.noPersistableEvidence(
    String reasonCode,
  ) : this._(
        status: WardrobeProfilePersistenceMappingStatus.noPersistableEvidence,
        reasonCode: reasonCode,
      );

  const WardrobeProfilePersistenceMappingResult.invalidInput(String reasonCode)
    : this._(
        status: WardrobeProfilePersistenceMappingStatus.invalidInput,
        reasonCode: reasonCode,
      );

  const WardrobeProfilePersistenceMappingResult.incompatibleInput(
    String reasonCode,
  ) : this._(
        status: WardrobeProfilePersistenceMappingStatus.incompatibleInput,
        reasonCode: reasonCode,
      );

  const WardrobeProfilePersistenceMappingResult.mappingFailure(
    String reasonCode,
  ) : this._(
        status: WardrobeProfilePersistenceMappingStatus.mappingFailure,
        reasonCode: reasonCode,
      );

  final WardrobeProfilePersistenceMappingStatus status;
  final WardrobeProfilePersistenceEnvelope? envelope;
  final String? reasonCode;
  final List<String> omittedEvidenceReasonCodes;
}

/// Maps only the final, qualified Phase 4.9 analysis into persistence DTOs.
final class QualifiedVisionPersistenceMapper {
  const QualifiedVisionPersistenceMapper();

  WardrobeProfilePersistenceMappingResult map({
    required VisionV2ShadowAnalysis analysis,
    required PersistenceMappingContext context,
  }) {
    final contextFailure = _validateContext(context, analysis);
    if (contextFailure != null) {
      return WardrobeProfilePersistenceMappingResult.incompatibleInput(
        contextFailure,
      );
    }
    if (!analysis.response.inputAssessment.isValid) {
      return const WardrobeProfilePersistenceMappingResult.invalidInput(
        'vision_input_not_valid',
      );
    }

    final observations = <PersistedMachineEvidence>[];
    final observationByProperty = <String, PersistedMachineEvidence>{};
    for (final runtime in analysis.observationEvidence) {
      if (!runtime.active ||
          runtime.source != EvidenceSource.visualObservation ||
          !WardrobeProfilePersistencePolicy.machineEvidenceProperties.contains(
            runtime.property,
          ) ||
          runtime.property == WardrobeProfileProperty.family ||
          runtime.property == WardrobeProfileProperty.canonicalType ||
          runtime.property.startsWith('capabilities.')) {
        continue;
      }
      final persisted = _observation(runtime, context);
      final existing = observationByProperty[persisted.property];
      if (existing != null && !_sameEvidence(existing, persisted)) {
        return WardrobeProfilePersistenceMappingResult.mappingFailure(
          'conflicting_observation:${persisted.property}',
        );
      }
      observationByProperty[persisted.property] = existing ?? persisted;
    }
    observations.addAll(observationByProperty.values);

    final omitted = <String>[];
    PersistedMachineEvidence? family = _family(
      analysis,
      context,
      observationByProperty,
    );
    PersistedMachineEvidence? canonical = _canonical(
      analysis,
      context,
      observationByProperty,
    );

    final identityBlockedByMultiPhoto =
        !analysis.multiPhotoAssessment.permitsIdentityPromotion;
    if (identityBlockedByMultiPhoto) {
      family = null;
      canonical = null;
      if (analysis.multiPhotoAssessment.physicalIdentity !=
          VisionMultiPhotoConsistency.sameItemSupported) {
        omitted.add('identity_omitted:multi_photo_physical_conflict');
      } else {
        omitted.add('identity_omitted:multi_photo_semantic_conflict');
      }
    }
    if (family != null && canonical != null) {
      final canonicalFamily =
          VisionCanonicalFamilyRegistry.canonicalToFamily[canonical.value];
      if (canonicalFamily?.wireName != family.value) {
        family = null;
        canonical = null;
        omitted.add('identity_omitted:cross_family_conflict');
      }
    }

    final capabilities = <PersistedMachineEvidence>[];
    for (final runtime in analysis.capabilityEvidence) {
      final persisted = _capability(runtime, context, observationByProperty);
      if (persisted == null) {
        omitted.add('capability_omitted:${runtime.property}');
      } else {
        capabilities.add(persisted);
      }
    }

    final evidence = <PersistedMachineEvidence>[
      ?family,
      ?canonical,
      ...observations,
      ...capabilities,
    ]..sort(_compareEvidence);
    final duplicateFailure = _duplicateFailure(evidence);
    if (duplicateFailure != null) {
      return WardrobeProfilePersistenceMappingResult.mappingFailure(
        duplicateFailure,
      );
    }
    final deduplicated = <String, PersistedMachineEvidence>{
      for (final item in evidence) item.id: item,
    }.values.toList()..sort(_compareEvidence);
    if (deduplicated.isEmpty) {
      return const WardrobeProfilePersistenceMappingResult.noPersistableEvidence(
        'no_qualified_evidence',
      );
    }

    final envelope = WardrobeProfilePersistenceEnvelope(
      metadata: WardrobeProfilePersistenceMetadata(
        generationId: context.generationId,
        revision: context.revision,
        createdAt: context.createdAt,
        updatedAt: context.updatedAt,
      ),
      source: WardrobeProfileSourceProvenance(
        imageRevision: context.imageRevision,
        wardrobeItemRevision: context.wardrobeItemRevision,
        storagePath: context.storagePath,
        imageHash: context.imageHash,
        uploadGeneration: context.uploadGeneration,
      ),
      analysis: WardrobeProfileAnalysisProvenance(
        analysisId: context.analysisId,
        kind: context.analysisKind,
        completedAt: context.completedAt,
        modelIdentifier: context.modelIdentifier,
        pipelineVersion: context.pipelineVersion,
        promptVersion: context.promptVersion,
        visionSchemaVersion: context.visionSchemaVersion,
        qualificationVersion: context.qualificationVersion,
      ),
      machineEvidence: List.unmodifiable(deduplicated),
      userCorrections: const {},
    );
    try {
      const WardrobeProfilePersistenceCodec().toPersistenceMap(envelope);
    } on FormatException catch (error) {
      return WardrobeProfilePersistenceMappingResult.mappingFailure(
        'codec_validation:${error.message}',
      );
    }
    return WardrobeProfilePersistenceMappingResult.mapped(
      envelope,
      omittedEvidenceReasonCodes: List.unmodifiable(omitted..sort()),
    );
  }

  String? _validateContext(
    PersistenceMappingContext context,
    VisionV2ShadowAnalysis analysis,
  ) {
    if (context.generationId.trim().isEmpty ||
        context.analysisId.trim().isEmpty ||
        context.modelIdentifier.trim().isEmpty ||
        context.pipelineVersion.trim().isEmpty ||
        context.promptVersion.trim().isEmpty ||
        context.qualificationVersion.trim().isEmpty) {
      return 'required_provenance_missing';
    }
    if (context.revision < 0 ||
        context.imageRevision < 0 ||
        context.wardrobeItemRevision < 0 ||
        context.visionSchemaVersion <= 0 ||
        context.updatedAt.isBefore(context.createdAt)) {
      return 'provenance_value_invalid';
    }
    if (context.analysisId != analysis.response.observations.analysisId) {
      return 'analysis_id_mismatch';
    }
    if (context.visionSchemaVersion != analysis.response.schemaVersion) {
      return 'vision_schema_version_mismatch';
    }
    if (context.modelIdentifier !=
        analysis.response.observations.modelVersion) {
      return 'model_identifier_mismatch';
    }
    return null;
  }

  PersistedMachineEvidence _observation(
    ProfileEvidence runtime,
    PersistenceMappingContext context,
  ) => PersistedMachineEvidence(
    id: _id('observation', context.analysisId, runtime.property),
    property: runtime.property,
    value: runtime.value,
    valueState: runtime.valueState,
    source: EvidenceSource.visualObservation,
    nature: EvidenceNature.observed,
    confidence: runtime.confidence,
    method: 'vision_observation',
    createdAt: context.completedAt,
    modelVersion: runtime.modelVersion ?? context.modelIdentifier,
  );

  PersistedMachineEvidence? _family(
    VisionV2ShadowAnalysis analysis,
    PersistenceMappingContext context,
    Map<String, PersistedMachineEvidence> observations,
  ) {
    final report = analysis.familyIdentity;
    final qualification = switch (report.state) {
      VisionFamilyResolutionState.confirmed =>
        PersistedIdentityQualification.confirmed,
      VisionFamilyResolutionState.supported =>
        PersistedIdentityQualification.supported,
      _ => null,
    };
    final family = report.resolvedFamily;
    if (qualification == null || family == null) return null;
    final candidate = report.candidates
        .where((item) => item.family == family)
        .firstOrNull;
    if (candidate == null) return null;
    final supports = _supportIds(
      candidate.evidence.map((item) => item.split(':').last),
      observations,
    );
    if (supports.isEmpty) return null;
    return PersistedMachineEvidence(
      id: _id('family', context.analysisId, family.wireName),
      property: WardrobeProfileProperty.family,
      value: family.wireName,
      valueState: EvidenceValueState.known,
      source: EvidenceSource.aiInference,
      nature: EvidenceNature.inferred,
      confidence: report.confidence,
      method: 'vision_family_identity',
      createdAt: context.completedAt,
      modelVersion: context.modelIdentifier,
      identityQualification: qualification,
      supportingEvidenceIds: supports,
    );
  }

  PersistedMachineEvidence? _canonical(
    VisionV2ShadowAnalysis analysis,
    PersistenceMappingContext context,
    Map<String, PersistedMachineEvidence> observations,
  ) {
    final selected = analysis.identityQualification.selectedCanonicalType;
    final qualification = switch (analysis.identityQualification.state) {
      VisionIdentityState.confirmed => PersistedIdentityQualification.confirmed,
      VisionIdentityState.supported => PersistedIdentityQualification.supported,
      _ => null,
    };
    if (selected == null || qualification == null) return null;
    final runtime = analysis.qualifiedIdentityEvidence
        .where(
          (item) =>
              item.active &&
              item.property == WardrobeProfileProperty.canonicalType &&
              item.value == selected,
        )
        .firstOrNull;
    final report = analysis.identityQualification.candidates
        .where((item) => item.canonicalType == selected)
        .firstOrNull;
    if (runtime == null || report == null) return null;
    final supports = _supportIds([
      ...report.usedDefiningSupports,
      ...report.usedSupportingObservations,
    ], observations);
    if (supports.isEmpty) return null;
    return PersistedMachineEvidence(
      id: _id('canonical', context.analysisId, selected),
      property: WardrobeProfileProperty.canonicalType,
      value: selected,
      valueState: EvidenceValueState.known,
      source: EvidenceSource.aiInference,
      nature: EvidenceNature.inferred,
      confidence: runtime.confidence,
      method: 'vision_v2_identity_candidate',
      createdAt: context.completedAt,
      modelVersion: runtime.modelVersion ?? context.modelIdentifier,
      identityQualification: qualification,
      supportingEvidenceIds: supports,
    );
  }

  PersistedMachineEvidence? _capability(
    ProfileEvidence runtime,
    PersistenceMappingContext context,
    Map<String, PersistedMachineEvidence> observations,
  ) {
    if (!runtime.active ||
        runtime.source != EvidenceSource.aiInference ||
        runtime.nature != EvidenceNature.inferred ||
        !runtime.method.startsWith('capability_inference:') ||
        !_capabilitySupportProperties.containsKey(runtime.method)) {
      return null;
    }
    final supports = _supportIds(
      _capabilitySupportProperties[runtime.method]!,
      observations,
    );
    if (supports.length !=
        _capabilitySupportProperties[runtime.method]!.length) {
      return null;
    }
    return PersistedMachineEvidence(
      id: _id('capability', context.analysisId, runtime.property),
      property: runtime.property,
      value: runtime.value,
      valueState: runtime.valueState,
      source: EvidenceSource.aiInference,
      nature: EvidenceNature.inferred,
      confidence: runtime.confidence,
      method: runtime.method,
      createdAt: context.completedAt,
      modelVersion: runtime.modelVersion ?? 'capability-inference-v1',
      supportingEvidenceIds: supports,
    );
  }

  List<String> _supportIds(
    Iterable<String> names,
    Map<String, PersistedMachineEvidence> observations,
  ) {
    final ids = <String>{};
    for (final name in names) {
      final property = _observationProperty(name);
      final evidence = property == null ? null : observations[property];
      if (evidence != null) ids.add(evidence.id);
    }
    return ids.toList()..sort();
  }

  String? _observationProperty(String value) {
    if (value == WardrobeProfileProperty.coverage ||
        value.startsWith('visual.observations.')) {
      return value;
    }
    return _observationNames[value];
  }

  String? _duplicateFailure(List<PersistedMachineEvidence> evidence) {
    final byId = <String, PersistedMachineEvidence>{};
    for (final item in evidence) {
      final existing = byId[item.id];
      if (existing != null && !_sameEvidence(existing, item)) {
        return 'conflicting_duplicate_id:${item.id}';
      }
      byId[item.id] = item;
    }
    return null;
  }

  bool _sameEvidence(
    PersistedMachineEvidence left,
    PersistedMachineEvidence right,
  ) =>
      left.id == right.id &&
      left.property == right.property &&
      _valueKey(left.value) == _valueKey(right.value) &&
      left.valueState == right.valueState &&
      left.source == right.source &&
      left.nature == right.nature &&
      left.confidence == right.confidence &&
      left.method == right.method &&
      left.modelVersion == right.modelVersion &&
      left.identityQualification == right.identityQualification;

  static int _compareEvidence(
    PersistedMachineEvidence left,
    PersistedMachineEvidence right,
  ) {
    final rank = _rank(left).compareTo(_rank(right));
    if (rank != 0) return rank;
    final property = left.property.compareTo(right.property);
    if (property != 0) return property;
    return left.id.compareTo(right.id);
  }

  static int _rank(PersistedMachineEvidence item) {
    if (item.property == WardrobeProfileProperty.family) return 0;
    if (item.property == WardrobeProfileProperty.canonicalType) return 1;
    if (item.property == WardrobeProfileProperty.coverage ||
        item.property.startsWith('visual.observations.')) {
      return 2;
    }
    return 3;
  }

  static String _id(String kind, String analysisId, String discriminator) =>
      '$kind:${Uri.encodeComponent(analysisId)}:'
      '${Uri.encodeComponent(discriminator)}';

  static String _valueKey(Object? value) =>
      value is Iterable ? value.join('|') : '$value';

  static const _observationNames = <String, String>{
    'coverage': WardrobeProfileProperty.coverage,
    'hasHood': WardrobeProfileProperty.hasHood,
    'frontClosure': WardrobeProfileProperty.frontClosure,
    'visibleBulk': WardrobeProfileProperty.visibleBulk,
    'surfaceAppearance': WardrobeProfileProperty.surfaceAppearance,
    'necklineShape': WardrobeProfileProperty.necklineShape,
    'visiblePocketStructure': WardrobeProfileProperty.visiblePocketStructure,
    'visibleStretchCue': WardrobeProfileProperty.visibleStretchCue,
    'sportyCues': WardrobeProfileProperty.sportyCues,
    'formalCues': WardrobeProfileProperty.formalCues,
    'footwearConstruction': WardrobeProfileProperty.footwearConstruction,
    'footwearFastening': WardrobeProfileProperty.footwearFastening,
    'soleProfile': WardrobeProfileProperty.soleProfile,
    'visibleTread': WardrobeProfileProperty.visibleTread,
    'footwearUpperHeight': WardrobeProfileProperty.footwearUpperHeight,
  };

  static const _capabilitySupportProperties = <String, List<String>>{
    'capability_inference:warmth.bulk_and_insulating_surface': [
      'visibleBulk',
      'surfaceAppearance',
    ],
    'capability_inference:warmth.bulk_and_full_coverage': [
      'visibleBulk',
      'coverage',
    ],
    'capability_inference:warmth.ankle_upper_and_bulk': [
      'footwearUpperHeight',
      'visibleBulk',
    ],
    'capability_inference:warmth.low_bulk_mesh': [
      'visibleBulk',
      'surfaceAppearance',
    ],
    'capability_inference:warmth.low_bulk_full_coverage': [
      'visibleBulk',
      'coverage',
    ],
    'capability_inference:breathability.mesh_and_low_bulk': [
      'surfaceAppearance',
      'visibleBulk',
    ],
    'capability_inference:breathability.mesh_and_open_construction': [
      'surfaceAppearance',
      'footwearConstruction',
    ],
    'capability_inference:mobility.stretch_and_sporty_construction': [
      'visibleStretchCue',
      'sportyCues',
    ],
    'capability_inference:mobility.visible_stretch': ['visibleStretchCue'],
    'capability_inference:formality.formal_over_sporty_cues': [
      'formalCues',
      'sportyCues',
    ],
    'capability_inference:formality.strong_formal_cues': ['formalCues'],
    'capability_inference:formality.strong_sporty_cues': [
      'sportyCues',
      'formalCues',
    ],
    'capability_inference:supported_layer_roles.hooded_zip_layer': [
      'hasHood',
      'frontClosure',
      'visibleBulk',
    ],
    'capability_inference:supported_layer_roles.knit_pullover': [
      'surfaceAppearance',
      'frontClosure',
      'visibleBulk',
    ],
    'capability_inference:walking_comfort.sporty_low_cut_supported_sole': [
      'footwearConstruction',
      'footwearUpperHeight',
      'soleProfile',
      'sportyCues',
    ],
    'capability_inference:traction.pronounced_visible_tread': ['visibleTread'],
    'capability_inference:traction.low_visible_tread': ['visibleTread'],
  };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
