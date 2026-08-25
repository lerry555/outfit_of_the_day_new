import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/qualified_vision_persistence_mapper.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_codec.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_contract.dart';

const qualifiedVisionPersistenceMapperId = 'QualifiedVisionPersistenceMapper';
const qualifiedVisionPersistenceMapperVersion =
    'qualified-vision-persistence-mapper-v1';
const qualifiedVisionPersistenceMapperOracleVersion = 1;
const qualifiedVisionPersistenceMapperExporterVersion = 1;
const qualifiedVisionPersistenceMapperOracleSourceStrategy =
    'offline_authoritative_mapper_oracle';
const qualifiedVisionPersistenceMapperOracleManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_qualified_vision_persistence_mapper_oracle_manifest.json';

/// Offline authoritative oracle export for QualifiedVisionPersistenceMapper.
///
/// There is no production mapper call-site sink. Oracles are produced by
/// replaying authoritative parser fixtures through VisionV2ShadowOrchestrator,
/// attaching a deterministic fixture-only PersistenceMappingContext, and
/// invoking QualifiedVisionPersistenceMapper.map directly. Capture stops at
/// WardrobeProfilePersistenceMappingResult — before repository / Firestore /
/// CAS / user-correction merge.
Map<String, Object?> exportQualifiedVisionPersistenceMapperOracles({
  required Directory repositoryRoot,
  required bool write,
}) {
  final fixtures = Directory(
    '${repositoryRoot.path}${Platform.pathSeparator}test'
    '${Platform.pathSeparator}fixtures',
  );
  final captures = _byId(
    _object(
      jsonDecode(
        File(
          '${fixtures.path}${Platform.pathSeparator}'
          'backend_qualification_capture_manifest.json',
        ).readAsStringSync().replaceFirst('\uFEFF', ''),
      ),
    )['fixtures'],
  );
  final goldens = _byId(
    _object(
      jsonDecode(
        File(
          '${fixtures.path}${Platform.pathSeparator}'
          'backend_qualification_golden_manifest.json',
        ).readAsStringSync().replaceFirst('\uFEFF', ''),
      ),
    )['fixtures'],
  );
  final catalog = _list(
    jsonDecode(
      File(
        '${fixtures.path}${Platform.pathSeparator}'
        'vision_v2_adversarial_scenarios.json',
      ).readAsStringSync(),
    ),
  );
  final mapperSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}domain${Platform.pathSeparator}wardrobe_profile'
    '${Platform.pathSeparator}qualified_vision_persistence_mapper.dart',
  );
  final callSiteSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}domain${Platform.pathSeparator}wardrobe_profile'
    '${Platform.pathSeparator}vision_v2_shadow_analysis.dart',
  );
  final serializerSources = [
    'lib/domain/wardrobe_profile/qualified_vision_persistence_mapper.dart',
    'lib/domain/wardrobe_profile/wardrobe_profile_persistence_contract.dart',
    'lib/domain/wardrobe_profile/wardrobe_profile_persistence_codec.dart',
    'lib/domain/wardrobe_profile/wardrobe_profile_contract.dart',
  ].map(
    (path) => File(
      '${repositoryRoot.path}${Platform.pathSeparator}'
      '${path.replaceAll('/', Platform.pathSeparator)}',
    ),
  );
  final exporterSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}tool'
    '${Platform.pathSeparator}'
    'export_qualified_vision_persistence_mapper_oracles.dart',
  );
  final codecSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}domain${Platform.pathSeparator}wardrobe_profile'
    '${Platform.pathSeparator}wardrobe_profile_persistence_codec.dart',
  );
  final taxonomy = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}data${Platform.pathSeparator}'
    'clothing_knowledge_base.dart',
  ).readAsStringSync();
  final allowed = RegExp(
    r"canonicalType:\s*'([^']+)'",
  ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
  final resolverOracleManifest = File(
    '${fixtures.path}${Platform.pathSeparator}'
    'backend_qualification${Platform.pathSeparator}'
    'backend_wardrobe_profile_resolver_oracle_manifest.json',
  );
  final resolverOracleManifestSha = _shaFile(resolverOracleManifest);
  final bindings = <String, Object?>{
    'providerImplementationSha256': _shaFile(mapperSource),
    'callSitePreparationSha256': _shaFile(callSiteSource),
    'serializerSha256': _combinedSha(serializerSources),
    'codecImplementationSha256': _shaFile(codecSource),
    'exporterImplementationSha256': _shaFile(exporterSource),
    'persistenceSchemaVersion': WardrobeProfilePersistenceVersions.schema,
    'persistenceEvidenceVersion': WardrobeProfilePersistenceVersions.evidence,
    'resolverCompatibilityVersion':
        WardrobeProfilePersistenceVersions.resolverCompatibility,
    'resolverOracleManifest':
        'backend_qualification/backend_wardrobe_profile_resolver_oracle_manifest.json',
    'resolverOracleManifestSha256': resolverOracleManifestSha,
    'oracleSourceStrategy':
        qualifiedVisionPersistenceMapperOracleSourceStrategy,
    'upstreamBindings': <String, Object?>{
      'observationEvidence': 'qualification-v1',
      'identityQualification': 'vision-identity-qualification-v1',
      'familyIdentity': 'vision-family-identity-resolver-v1',
      'capabilityInference': 'capability-inference-v1',
      'profileResolver': 'wardrobe-profile-resolver-v1',
      'persistenceCodec': 'wardrobe-profile-persistence-codec-v1',
      'persistenceSchema': WardrobeProfilePersistenceVersions.schema,
      'persistenceEvidence': WardrobeProfilePersistenceVersions.evidence,
    },
  };

  final entries = <Map<String, Object?>>[];
  final writes = <File, List<int>>{};
  final invocationIds = <String>{};
  var ready = 0;
  var sourceMissing = 0;
  var invocationCount = 0;

  var mappedCount = 0;
  var noPersistableEvidenceCount = 0;
  var invalidInputCount = 0;
  var incompatibleInputCount = 0;
  var mappingFailureCount = 0;
  var totalMachineEvidence = 0;
  var familyEvidenceCount = 0;
  var canonicalEvidenceCount = 0;
  var observationEvidenceCount = 0;
  var capabilityEvidenceCount = 0;
  var omittedEvidenceCount = 0;
  final omittedReasons = <String, int>{};
  final valueStateCounts = <String, int>{};
  var supportingIdCount = 0;
  var danglingSupportCount = 0;
  var duplicateConflictCount = 0;
  var familyOnlyMapped = 0;
  var canonicalAndFamily = 0;
  var noIdentity = 0;
  var multiViewBlocked = 0;

  const mapper = QualifiedVisionPersistenceMapper();
  const codec = WardrobeProfilePersistenceCodec();

  for (final raw in catalog) {
    final scenario = _object(raw);
    final id = scenario['id']! as String;
    final capture = captures[id];
    final golden = goldens[id];
    if (capture?['captureStatus'] != 'captured' ||
        golden?['goldenStatus'] != 'ready') {
      sourceMissing++;
      entries.add({
        'scenarioId': id,
        'providerId': qualifiedVisionPersistenceMapperId,
        'status': 'source_missing',
        'reason': 'captured_source_not_ready',
        'oracleVersion': qualifiedVisionPersistenceMapperOracleVersion,
      });
      continue;
    }
    final parserPath = File(
      '${repositoryRoot.path}${Platform.pathSeparator}'
      '${(capture!['parserFixture']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final parserBytes = parserPath.readAsBytesSync();
    final parserSha = sha256.convert(parserBytes).toString();
    if (parserSha != capture['parserFixtureSha256']) {
      throw FormatException('parser_sha_mismatch:$id');
    }
    final fixtureJson = parserPath.readAsStringSync();
    final responses = const VisionParserFixtureReplay().decodeResponses(
      fixtureJson,
      allowedCanonicalTypes: allowed,
    );
    final binding = const VisionParserFixtureReplay().decodeBinding(
      fixtureJson,
    );
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: id,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
    );
    // Offline oracle: mapper is not invoked by production orchestrator.
    // Re-run analyze to prove analysis is deterministic without any mapper sink.
    final analysisRerun = const VisionV2ShadowOrchestrator().analyze(
      itemId: id,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
    );
    if (!_equalBytes(
      _bytes(analysis.toMap()),
      _bytes(analysisRerun.toMap()),
    )) {
      throw FormatException('analysis_nondeterministic:$id');
    }

    final context = fixturePersistenceMappingContext(
      scenarioId: id,
      analysis: analysis,
    );
    final contextMap = encodePersistenceMappingContext(context);
    final analysisProjection = encodeMapperAnalysisProjection(analysis);
    final result = mapper.map(analysis: analysis, context: context);
    final resultRerun = mapper.map(analysis: analysisRerun, context: context);
    final output = encodeMappingResult(result);
    final outputRerun = encodeMappingResult(resultRerun);
    if (!_equalBytes(_bytes(output), _bytes(outputRerun))) {
      throw FormatException('mapper_output_nondeterministic:$id');
    }
    if (result.status == WardrobeProfilePersistenceMappingStatus.mapped) {
      try {
        codec.toPersistenceMap(result.envelope!);
      } on FormatException catch (error) {
        throw FormatException('codec_reject:$id:${error.message}');
      }
    }

    final invocationId = '$id::qualified-vision-persistence-mapper';
    if (!invocationIds.add(invocationId)) {
      throw FormatException('duplicate_mapper_invocation_id:$invocationId');
    }

    final coverage = _accumulateCoverage(
      result: result,
      mappedCount: mappedCount,
      noPersistableEvidenceCount: noPersistableEvidenceCount,
      invalidInputCount: invalidInputCount,
      incompatibleInputCount: incompatibleInputCount,
      mappingFailureCount: mappingFailureCount,
      totalMachineEvidence: totalMachineEvidence,
      familyEvidenceCount: familyEvidenceCount,
      canonicalEvidenceCount: canonicalEvidenceCount,
      observationEvidenceCount: observationEvidenceCount,
      capabilityEvidenceCount: capabilityEvidenceCount,
      omittedEvidenceCount: omittedEvidenceCount,
      omittedReasons: omittedReasons,
      valueStateCounts: valueStateCounts,
      supportingIdCount: supportingIdCount,
      danglingSupportCount: danglingSupportCount,
      duplicateConflictCount: duplicateConflictCount,
      familyOnlyMapped: familyOnlyMapped,
      canonicalAndFamily: canonicalAndFamily,
      noIdentity: noIdentity,
      multiViewBlocked: multiViewBlocked,
    );
    mappedCount = coverage.mappedCount;
    noPersistableEvidenceCount = coverage.noPersistableEvidenceCount;
    invalidInputCount = coverage.invalidInputCount;
    incompatibleInputCount = coverage.incompatibleInputCount;
    mappingFailureCount = coverage.mappingFailureCount;
    totalMachineEvidence = coverage.totalMachineEvidence;
    familyEvidenceCount = coverage.familyEvidenceCount;
    canonicalEvidenceCount = coverage.canonicalEvidenceCount;
    observationEvidenceCount = coverage.observationEvidenceCount;
    capabilityEvidenceCount = coverage.capabilityEvidenceCount;
    omittedEvidenceCount = coverage.omittedEvidenceCount;
    supportingIdCount = coverage.supportingIdCount;
    danglingSupportCount = coverage.danglingSupportCount;
    duplicateConflictCount = coverage.duplicateConflictCount;
    familyOnlyMapped = coverage.familyOnlyMapped;
    canonicalAndFamily = coverage.canonicalAndFamily;
    noIdentity = coverage.noIdentity;
    multiViewBlocked = coverage.multiViewBlocked;

    invocationCount++;
    final inputFile = File(
      '${fixtures.path}${Platform.pathSeparator}'
      '${(golden!['qualificationInput']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final goldenFile = File(
      '${fixtures.path}${Platform.pathSeparator}'
      '${(golden['dartReference']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final mapperInput = <String, Object?>{
      'analysisProjection': analysisProjection,
      'mappingContext': contextMap,
    };
    final oracle = <String, Object?>{
      'oracleVersion': qualifiedVisionPersistenceMapperOracleVersion,
      'exporterVersion': qualifiedVisionPersistenceMapperExporterVersion,
      'providerId': qualifiedVisionPersistenceMapperId,
      'providerVersion': qualifiedVisionPersistenceMapperVersion,
      'inputContract': 'qualified_vision_persistence_mapper_input/v1',
      'outputContract': 'WardrobeProfilePersistenceMappingResult/v1',
      'oracleSourceStrategy':
          qualifiedVisionPersistenceMapperOracleSourceStrategy,
      'scenarioId': id,
      'sourceParserFixture': capture['parserFixture'],
      'sourceParserFixtureSha256': parserSha,
      'sourceQualificationInputSha256': sha256
          .convert(inputFile.readAsBytesSync())
          .toString(),
      'sourceDartReferenceGoldenSha256': sha256
          .convert(goldenFile.readAsBytesSync())
          .toString(),
      ...bindings,
      'contextAuthority': <String, Object?>{
        'fixtureOnly': true,
        'trustedProductionRevision': false,
        'revisionAffectsMapperDecisionSemantics': false,
        'revisionCopiedIntoEnvelopeOnly': true,
      },
      'ignoredAnalysisFields': <String>[
        'resolvedProfile',
        'knowledgeBaseEvidence',
        'identityEvidence',
        'diagnostics',
        'v1Summary',
        'consistency',
        'rawObservations',
        'rawCandidates',
        'compatibilityLegacyFallback',
      ],
      'orderingPolicy': <String, Object?>{
        'scenario': 'vision_v2_adversarial_scenarios_manifest_order',
        'invocation': 'single_scenario_invocation',
        'machineEvidence':
            'mapper_rank_family_canonical_observation_capability_then_property_id',
        'omittedReasons': 'sorted_lexicographic',
        'mapKeys': 'canonical_json_lexicographic',
      },
      'invocations': [
        {
          'invocationId': invocationId,
          'viewCount': responses.length,
          'mapperInput': mapperInput,
          'mapperInputSha256': sha256.convert(_bytes(mapperInput)).toString(),
          'mappingContext': contextMap,
          'mappingContextSha256': sha256.convert(_bytes(contextMap)).toString(),
          'mapperOutput': output,
          'mapperOutputSha256': sha256.convert(_bytes(output)).toString(),
          'mappingStatus': result.status.name,
          'machineEvidenceCount': result.envelope?.machineEvidence.length ?? 0,
          'omittedEvidenceCount': result.omittedEvidenceReasonCodes.length,
        },
      ],
    };
    final bytes = _bytes(oracle);
    final relative =
        'backend_qualification/provider_oracles/'
        'qualified_vision_persistence_mapper_v1/$id.oracle.json';
    writes[File(
          '${fixtures.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        )] =
        bytes;
    entries.add({
      'scenarioId': id,
      'providerId': qualifiedVisionPersistenceMapperId,
      'status': 'ready',
      'oraclePath': relative,
      'oracleSha256': sha256.convert(bytes).toString(),
      'invocationCount': 1,
      'sourceParserFixtureSha256': parserSha,
      'oracleVersion': qualifiedVisionPersistenceMapperOracleVersion,
      'mappingStatus': result.status.name,
    });
    ready++;
  }

  Map<String, Object?> sortedCounts(Map<String, int> counts) =>
      Map<String, Object?>.fromEntries(
        (counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map(
          (e) => MapEntry(e.key, e.value),
        ),
      );

  final coverage = <String, Object?>{
    'mappedCount': mappedCount,
    'noPersistableEvidenceCount': noPersistableEvidenceCount,
    'invalidInputCount': invalidInputCount,
    'incompatibleInputCount': incompatibleInputCount,
    'mappingFailureCount': mappingFailureCount,
    'totalMachineEvidence': totalMachineEvidence,
    'familyEvidenceCount': familyEvidenceCount,
    'canonicalEvidenceCount': canonicalEvidenceCount,
    'observationEvidenceCount': observationEvidenceCount,
    'capabilityEvidenceCount': capabilityEvidenceCount,
    'omittedEvidenceCount': omittedEvidenceCount,
    'omittedReasons': sortedCounts(omittedReasons),
    'valueStateCounts': sortedCounts(valueStateCounts),
    'supportingIdCount': supportingIdCount,
    'danglingSupportCount': danglingSupportCount,
    'duplicateConflictCount': duplicateConflictCount,
    'familyOnlyMappedCount': familyOnlyMapped,
    'canonicalAndFamilyMappedCount': canonicalAndFamily,
    'noIdentityMappedCount': noIdentity,
    'multiViewBlockedCount': multiViewBlocked,
  };
  final manifest = <String, Object?>{
    'manifestVersion': 1,
    'oracleVersion': qualifiedVisionPersistenceMapperOracleVersion,
    'exporterVersion': qualifiedVisionPersistenceMapperExporterVersion,
    'providerId': qualifiedVisionPersistenceMapperId,
    'providerVersion': qualifiedVisionPersistenceMapperVersion,
    'scenarioCount': catalog.length,
    'readyScenarioCount': ready,
    'sourceMissingScenarioCount': sourceMissing,
    'invocationCount': invocationCount,
    ...bindings,
    'generationCommand':
        'flutter test --dart-define=UPDATE_QUALIFIED_VISION_PERSISTENCE_MAPPER_ORACLES=true '
        'test/backend_qualified_vision_persistence_mapper_oracle_export_test.dart',
    'orderingPolicy': <String, Object?>{
      'scenario': 'vision_v2_adversarial_scenarios_manifest_order',
      'invocation': 'single_scenario_invocation',
      'machineEvidence':
          'mapper_rank_family_canonical_observation_capability_then_property_id',
      'omittedReasons': 'sorted_lexicographic',
      'mapKeys': 'canonical_json_lexicographic',
    },
    'coverage': coverage,
    'fixtures': entries,
  };
  final manifestBytes = _bytes(manifest);
  if (write) {
    for (final item in writes.entries) {
      _write(item.key, item.value);
    }
    _write(
      File(
        '${repositoryRoot.path}${Platform.pathSeparator}'
        '${qualifiedVisionPersistenceMapperOracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
      ),
      manifestBytes,
    );
  }
  return <String, Object?>{
    'ready': ready,
    'sourceMissing': sourceMissing,
    'invocationCount': invocationCount,
    'manifestBytes': manifestBytes,
    'oracleBytesByPath': {
      for (final item in writes.entries) item.key.path: item.value,
    },
    'coverage': coverage,
    ...bindings,
  };
}

/// Deterministic fixture-only context. Never treat as production-trusted.
PersistenceMappingContext fixturePersistenceMappingContext({
  required String scenarioId,
  required VisionV2ShadowAnalysis analysis,
}) {
  final observedAt = analysis.response.observations.observedAt.toUtc();
  return PersistenceMappingContext(
    generationId: 'fixture-generation:$scenarioId',
    revision: 1,
    createdAt: observedAt,
    updatedAt: observedAt,
    imageRevision: 1,
    wardrobeItemRevision: 1,
    storagePath: 'fixture://wardrobe/$scenarioId/source.jpg',
    imageHash: 'fixture-hash:$scenarioId',
    uploadGeneration: 'fixture-upload:$scenarioId',
    analysisId: analysis.response.observations.analysisId,
    analysisKind: WardrobeAnalysisKind.initialAnalysis,
    completedAt: observedAt,
    modelIdentifier: analysis.response.observations.modelVersion,
    pipelineVersion: 'vision-v2-phase-4.9',
    promptVersion: 'vision-v2-schema-9',
    visionSchemaVersion: analysis.response.schemaVersion,
    qualificationVersion: 'qualification-v1',
  );
}

Map<String, Object?> encodePersistenceMappingContext(
  PersistenceMappingContext context,
) => <String, Object?>{
  'generationId': context.generationId,
  'revision': context.revision,
  'createdAt': context.createdAt.toUtc().toIso8601String(),
  'updatedAt': context.updatedAt.toUtc().toIso8601String(),
  'imageRevision': context.imageRevision,
  'wardrobeItemRevision': context.wardrobeItemRevision,
  if (context.storagePath != null) 'storagePath': context.storagePath,
  if (context.imageHash != null) 'imageHash': context.imageHash,
  if (context.uploadGeneration != null)
    'uploadGeneration': context.uploadGeneration,
  'analysisId': context.analysisId,
  'analysisKind': context.analysisKind.wireName,
  'completedAt': context.completedAt.toUtc().toIso8601String(),
  'modelIdentifier': context.modelIdentifier,
  'pipelineVersion': context.pipelineVersion,
  'promptVersion': context.promptVersion,
  'visionSchemaVersion': context.visionSchemaVersion,
  'qualificationVersion': context.qualificationVersion,
};

/// Minimal projection of fields actually read by the mapper.
Map<String, Object?> encodeMapperAnalysisProjection(
  VisionV2ShadowAnalysis analysis,
) => <String, Object?>{
  'inputAssessment': analysis.response.inputAssessment.wireName,
  'inputAssessmentValid': analysis.response.inputAssessment.isValid,
  'schemaVersion': analysis.response.schemaVersion,
  'analysisId': analysis.response.observations.analysisId,
  'modelVersion': analysis.response.observations.modelVersion,
  'observationEvidence': analysis.observationEvidence
      .map((item) => item.toMap())
      .toList(),
  'qualifiedIdentityEvidence': analysis.qualifiedIdentityEvidence
      .map((item) => item.toMap())
      .toList(),
  'capabilityEvidence': analysis.capabilityEvidence
      .map((item) => item.toMap())
      .toList(),
  'identityQualification': analysis.identityQualification.toMap(),
  'familyIdentity': analysis.familyIdentity.toMap(),
  'multiPhotoAssessment': analysis.multiPhotoAssessment.toMap(),
};

Map<String, Object?> encodeMappingResult(
  WardrobeProfilePersistenceMappingResult result,
) => <String, Object?>{
  'status': result.status.name,
  if (result.reasonCode != null) 'reasonCode': result.reasonCode,
  'omittedEvidenceReasonCodes': result.omittedEvidenceReasonCodes,
  if (result.envelope != null) 'envelope': encodeEnvelope(result.envelope!),
};

/// Mapper-order envelope encoding (rank order preserved; codec may re-sort by id).
Map<String, Object?> encodeEnvelope(WardrobeProfilePersistenceEnvelope envelope) =>
    <String, Object?>{
      'metadata': <String, Object?>{
        'schemaVersion': envelope.metadata.schemaVersion,
        'evidenceSchemaVersion': envelope.metadata.evidenceSchemaVersion,
        'resolverCompatibilityVersion':
            envelope.metadata.resolverCompatibilityVersion,
        'generationId': envelope.metadata.generationId,
        'revision': envelope.metadata.revision,
        'createdAt': envelope.metadata.createdAt.toUtc().toIso8601String(),
        'updatedAt': envelope.metadata.updatedAt.toUtc().toIso8601String(),
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
        'completedAt': envelope.analysis.completedAt.toUtc().toIso8601String(),
        'modelIdentifier': envelope.analysis.modelIdentifier,
        'pipelineVersion': envelope.analysis.pipelineVersion,
        'promptVersion': envelope.analysis.promptVersion,
        'visionSchemaVersion': envelope.analysis.visionSchemaVersion,
        'qualificationVersion': envelope.analysis.qualificationVersion,
      },
      'machineEvidence': envelope.machineEvidence
          .map(_encodeMachineEvidence)
          .toList(growable: false),
      'userCorrections': <String, Object?>{
        for (final entry in envelope.userCorrections.entries)
          entry.key: <String, Object?>{
            'id': entry.value.id,
            'property': entry.value.property,
            'action': entry.value.action.wireName,
          },
      },
    };

Map<String, Object?> _encodeMachineEvidence(PersistedMachineEvidence evidence) =>
    <String, Object?>{
      'id': evidence.id,
      'property': evidence.property,
      'value': evidence.value,
      'valueState': evidence.valueState.wireName,
      'source': evidence.source.wireName,
      'nature': evidence.nature.wireName,
      'confidence': evidence.confidence,
      'method': evidence.method,
      'createdAt': evidence.createdAt.toUtc().toIso8601String(),
      'modelVersion': evidence.modelVersion,
      if (evidence.identityQualification != null)
        'identityQualification': evidence.identityQualification!.wireName,
      if (evidence.supportingEvidenceIds.isNotEmpty)
        'supportingEvidenceIds': evidence.supportingEvidenceIds,
    };

({
  int mappedCount,
  int noPersistableEvidenceCount,
  int invalidInputCount,
  int incompatibleInputCount,
  int mappingFailureCount,
  int totalMachineEvidence,
  int familyEvidenceCount,
  int canonicalEvidenceCount,
  int observationEvidenceCount,
  int capabilityEvidenceCount,
  int omittedEvidenceCount,
  int supportingIdCount,
  int danglingSupportCount,
  int duplicateConflictCount,
  int familyOnlyMapped,
  int canonicalAndFamily,
  int noIdentity,
  int multiViewBlocked,
})
_accumulateCoverage({
  required WardrobeProfilePersistenceMappingResult result,
  required int mappedCount,
  required int noPersistableEvidenceCount,
  required int invalidInputCount,
  required int incompatibleInputCount,
  required int mappingFailureCount,
  required int totalMachineEvidence,
  required int familyEvidenceCount,
  required int canonicalEvidenceCount,
  required int observationEvidenceCount,
  required int capabilityEvidenceCount,
  required int omittedEvidenceCount,
  required Map<String, int> omittedReasons,
  required Map<String, int> valueStateCounts,
  required int supportingIdCount,
  required int danglingSupportCount,
  required int duplicateConflictCount,
  required int familyOnlyMapped,
  required int canonicalAndFamily,
  required int noIdentity,
  required int multiViewBlocked,
}) {
  switch (result.status) {
    case WardrobeProfilePersistenceMappingStatus.mapped:
      mappedCount++;
    case WardrobeProfilePersistenceMappingStatus.noPersistableEvidence:
      noPersistableEvidenceCount++;
    case WardrobeProfilePersistenceMappingStatus.invalidInput:
      invalidInputCount++;
    case WardrobeProfilePersistenceMappingStatus.incompatibleInput:
      incompatibleInputCount++;
    case WardrobeProfilePersistenceMappingStatus.mappingFailure:
      mappingFailureCount++;
      if (result.reasonCode?.startsWith('conflicting_duplicate_id:') == true) {
        duplicateConflictCount++;
      }
  }
  omittedEvidenceCount += result.omittedEvidenceReasonCodes.length;
  for (final reason in result.omittedEvidenceReasonCodes) {
    omittedReasons[reason] = (omittedReasons[reason] ?? 0) + 1;
    if (reason.startsWith('identity_omitted:multi_photo_')) {
      multiViewBlocked++;
    }
  }
  final evidence = result.envelope?.machineEvidence ?? const [];
  totalMachineEvidence += evidence.length;
  var hasFamily = false;
  var hasCanonical = false;
  final ids = evidence.map((item) => item.id).toSet();
  for (final item in evidence) {
    valueStateCounts[item.valueState.wireName] =
        (valueStateCounts[item.valueState.wireName] ?? 0) + 1;
    supportingIdCount += item.supportingEvidenceIds.length;
    for (final support in item.supportingEvidenceIds) {
      if (!ids.contains(support)) danglingSupportCount++;
    }
    if (item.property == WardrobeProfileProperty.family) {
      familyEvidenceCount++;
      hasFamily = true;
    } else if (item.property == WardrobeProfileProperty.canonicalType) {
      canonicalEvidenceCount++;
      hasCanonical = true;
    } else if (item.property.startsWith('capabilities.')) {
      capabilityEvidenceCount++;
    } else {
      observationEvidenceCount++;
    }
  }
  if (result.status == WardrobeProfilePersistenceMappingStatus.mapped) {
    if (hasFamily && hasCanonical) {
      canonicalAndFamily++;
    } else if (hasFamily && !hasCanonical) {
      familyOnlyMapped++;
    } else if (!hasFamily && !hasCanonical) {
      noIdentity++;
    }
  }
  return (
    mappedCount: mappedCount,
    noPersistableEvidenceCount: noPersistableEvidenceCount,
    invalidInputCount: invalidInputCount,
    incompatibleInputCount: incompatibleInputCount,
    mappingFailureCount: mappingFailureCount,
    totalMachineEvidence: totalMachineEvidence,
    familyEvidenceCount: familyEvidenceCount,
    canonicalEvidenceCount: canonicalEvidenceCount,
    observationEvidenceCount: observationEvidenceCount,
    capabilityEvidenceCount: capabilityEvidenceCount,
    omittedEvidenceCount: omittedEvidenceCount,
    supportingIdCount: supportingIdCount,
    danglingSupportCount: danglingSupportCount,
    duplicateConflictCount: duplicateConflictCount,
    familyOnlyMapped: familyOnlyMapped,
    canonicalAndFamily: canonicalAndFamily,
    noIdentity: noIdentity,
    multiViewBlocked: multiViewBlocked,
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw FormatException('expected_object');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _list(Object? value) {
  if (value is! List) throw FormatException('expected_list');
  return List<Object?>.from(value);
}

Map<String, Map<String, Object?>> _byId(Object? value) {
  final result = <String, Map<String, Object?>>{};
  for (final item in _list(value)) {
    final map = _object(item);
    result[map['id']! as String] = map;
  }
  return result;
}

List<int> _bytes(Object? value) => utf8.encode(
  '${const JsonEncoder.withIndent('  ').convert(_canonicalize(value))}\n',
);

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((item) => item.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalize(value[key])};
  }
  if (value is List) return value.map(_canonicalize).toList();
  if (value is double && value == 0) return 0;
  return value;
}

String _shaFile(File file) => sha256.convert(file.readAsBytesSync()).toString();

String _combinedSha(Iterable<File> files) {
  final bytes = <int>[];
  for (final file in files) {
    bytes
      ..addAll(utf8.encode(file.path.split(Platform.pathSeparator).last))
      ..add(0)
      ..addAll(file.readAsBytesSync())
      ..add(0);
  }
  return sha256.convert(bytes).toString();
}

bool _equalBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

void _write(File file, List<int> bytes) {
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}
