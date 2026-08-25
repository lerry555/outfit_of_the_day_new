import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

const wardrobeProfileResolverId = 'WardrobeProfileResolver';
const wardrobeProfileResolverVersion = 'wardrobe-profile-resolver-v1';
const wardrobeProfileResolverOracleVersion = 1;
const wardrobeProfileResolverExporterVersion = 1;
const wardrobeProfileResolverOracleManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_wardrobe_profile_resolver_oracle_manifest.json';

Map<String, Object?> exportWardrobeProfileResolverOracles({
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
  final providerSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}domain${Platform.pathSeparator}wardrobe_profile'
    '${Platform.pathSeparator}wardrobe_profile_resolver.dart',
  );
  final callSiteSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}domain${Platform.pathSeparator}wardrobe_profile'
    '${Platform.pathSeparator}vision_v2_shadow_analysis.dart',
  );
  final serializerSources =
      [
        'lib/domain/wardrobe_profile/wardrobe_profile_resolver.dart',
        'lib/domain/wardrobe_profile/wardrobe_profile_contract.dart',
        'lib/domain/wardrobe_profile/wardrobe_observation_contract.dart',
      ].map(
        (path) => File(
          '${repositoryRoot.path}${Platform.pathSeparator}'
          '${path.replaceAll('/', Platform.pathSeparator)}',
        ),
      );
  final exporterSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}tool'
    '${Platform.pathSeparator}export_wardrobe_profile_resolver_oracles.dart',
  );
  final taxonomy = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}data${Platform.pathSeparator}'
    'clothing_knowledge_base.dart',
  ).readAsStringSync();
  final allowed = RegExp(
    r"canonicalType:\s*'([^']+)'",
  ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
  final kbArtifact = File(
    '${fixtures.path}${Platform.pathSeparator}'
    'backend_qualification${Platform.pathSeparator}artifacts'
    '${Platform.pathSeparator}clothing_knowledge_base_prior_v1.json',
  );
  final kbArtifactManifest = File(
    '${repositoryRoot.path}${Platform.pathSeparator}test'
    '${Platform.pathSeparator}fixtures${Platform.pathSeparator}'
    'backend_qualification${Platform.pathSeparator}'
    'backend_clothing_kb_prior_artifact_manifest.json',
  );
  final kbArtifactContentSha = _object(
    jsonDecode(kbArtifactManifest.readAsStringSync()),
  )['artifactContentSha256'];
  final bindings = <String, Object?>{
    'providerImplementationSha256': _shaFile(providerSource),
    'callSitePreparationSha256': _shaFile(callSiteSource),
    'serializerSha256': _combinedSha(serializerSources),
    'exporterImplementationSha256': _shaFile(exporterSource),
    'knowledgeBaseArtifactContentSha256': kbArtifactContentSha,
    'knowledgeBaseArtifactSchemaVersion': 1,
    'knowledgeBaseArtifactPath':
        'backend_qualification/artifacts/clothing_knowledge_base_prior_v1.json',
    'knowledgeBaseArtifactFileSha256': _shaFile(kbArtifact),
    'upstreamBindings': <String, Object?>{
      'observationEvidence': 'qualification-v1',
      'identityQualification': 'vision-identity-qualification-v1',
      'capabilityInference': 'capability-inference-v1',
      'knowledgeBasePrior': 'wardrobe-kb-prior-provider-v1',
      'familyIdentity': 'vision-family-identity-resolver-v1',
      'prepareIdentity': 'vision-identity-qualification-input-v1',
      'prepareFamily': 'vision-family-identity-input-v1',
      'prepareKnowledgeBasePrior': 'knowledge-base-prior-input-v1',
      'knowledgeBaseArtifact': 'clothing-kb-prior-artifact-v1',
      'knowledgeBaseLoader': 'clothing-kb-prior-loader-v1',
    },
  };
  final entries = <Map<String, Object?>>[];
  final writes = <File, List<int>>{};
  final invocationIds = <String>{};
  var ready = 0;
  var sourceMissing = 0;
  var invocationCount = 0;
  var resolvedCanonical = 0;
  var unresolvedCanonical = 0;
  var resolvedFamilyOnProfile = 0;
  var familyReportPresent = 0;
  var familyIgnoredByResolver = 0;
  var resolvedObservationFields = 0;
  var resolvedCapabilityFields = 0;
  var kbSelected = 0;
  var visualSelected = 0;
  var aiSelected = 0;
  var legacySelected = 0;
  var userCorrectionSelected = 0;
  var compatibilityFallbackSelected = 0;
  var conflictFields = 0;
  var fullyUnresolvedProfiles = 0;
  var totalInputEvidence = 0;
  final evidenceBySource = <String, int>{};
  final evidenceByNature = <String, int>{};
  var activeEvidence = 0;
  var inactiveEvidence = 0;
  var verifiedEvidence = 0;
  var unverifiedEvidence = 0;
  final valueStateCounts = <String, int>{};
  final selectedByProperty = <String, int>{};
  final unresolvedProperties = <String, int>{};
  final conflictProperties = <String, int>{};

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
        'providerId': wardrobeProfileResolverId,
        'status': 'source_missing',
        'reason': 'captured_source_not_ready',
        'oracleVersion': wardrobeProfileResolverOracleVersion,
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
    final baseline = const VisionV2ShadowOrchestrator().analyze(
      itemId: id,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
    );
    final observed = _ResolverTrace(id);
    final withSink = const VisionV2ShadowOrchestrator().analyze(
      itemId: id,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      wardrobeProfileResolverTraceSink: observed,
    );
    if (!_equalBytes(_bytes(baseline.toMap()), _bytes(withSink.toMap()))) {
      throw FormatException('observer_changed_authoritative_behavior:$id');
    }
    if (!_equalBytes(
      _bytes(baseline.resolvedProfile.toMap()),
      _bytes(withSink.resolvedProfile.toMap()),
    )) {
      throw FormatException('observer_changed_resolved_profile:$id');
    }
    if (observed.before != 1 ||
        observed.after != 1 ||
        observed.records.length != 1) {
      throw FormatException('resolver_invocation_count_invalid:$id');
    }
    final invocationId = '$id::wardrobe-profile-resolver';
    if (!invocationIds.add(invocationId)) {
      throw FormatException('duplicate_resolver_invocation_id:$invocationId');
    }
    final record = observed.records.single;
    final input = _object(record['resolverInput']);
    final output = _object(record['resolverOutput']);
    final inputEvidence = _list(input['evidence']).map(_object).toList();
    totalInputEvidence += inputEvidence.length;
    for (final item in inputEvidence) {
      final source = '${item['source']}';
      final nature = '${item['nature']}';
      final valueState = item['valueState']?.toString() ?? 'known';
      evidenceBySource[source] = (evidenceBySource[source] ?? 0) + 1;
      evidenceByNature[nature] = (evidenceByNature[nature] ?? 0) + 1;
      valueStateCounts[valueState] = (valueStateCounts[valueState] ?? 0) + 1;
      if (item['active'] == true) {
        activeEvidence++;
      } else {
        inactiveEvidence++;
      }
      if (item['verified'] == true) {
        verifiedEvidence++;
      } else {
        unverifiedEvidence++;
      }
    }
    final identity = _object(output['identity']);
    final visual = _object(output['visual']);
    final capabilities = _object(output['capabilities']);
    final suitability = _object(output['suitability']);
    final fields = <String, Map<String, Object?>>{
      for (final entry in identity.entries)
        'identity.${entry.key}': _object(entry.value),
      for (final entry in visual.entries)
        'visual.${entry.key}': _object(entry.value),
      for (final entry in capabilities.entries)
        'capabilities.${entry.key}': _object(entry.value),
      for (final entry in suitability.entries)
        'suitability.${entry.key}': _object(entry.value),
    };
    final canonical = fields['identity.canonicalType']!;
    if (canonical['state'] == 'known') {
      resolvedCanonical++;
    } else {
      unresolvedCanonical++;
    }
    // Family is not a ResolvedWardrobeItemProfile field; track analysis only.
    if (withSink.familyIdentity.resolvedFamily != null) {
      familyReportPresent++;
      familyIgnoredByResolver++;
    }
    var knownFieldCount = 0;
    var scenarioConflicts = 0;
    for (final entry in fields.entries) {
      final field = entry.value;
      final state = '${field['state']}';
      final source = field['winningSource']?.toString();
      final conflicts = _list(field['conflictingEvidenceIds'] ?? const []);
      if (state == 'known' || state == 'not_applicable') {
        knownFieldCount++;
        selectedByProperty[entry.key] =
            (selectedByProperty[entry.key] ?? 0) + 1;
        if (entry.key.startsWith('visual.')) {
          resolvedObservationFields++;
        }
        if (entry.key.startsWith('capabilities.')) {
          resolvedCapabilityFields++;
        }
        switch (source) {
          case 'knowledge_base_prior':
            kbSelected++;
          case 'visual_observation':
            visualSelected++;
          case 'ai_inference':
            aiSelected++;
          case 'legacy_fallback':
            legacySelected++;
          case 'user_correction':
            userCorrectionSelected++;
        }
      } else {
        unresolvedProperties[entry.key] =
            (unresolvedProperties[entry.key] ?? 0) + 1;
      }
      if (conflicts.isNotEmpty) {
        scenarioConflicts++;
        conflictFields++;
        conflictProperties[entry.key] =
            (conflictProperties[entry.key] ?? 0) + 1;
      }
    }
    if (knownFieldCount == 0) {
      fullyUnresolvedProfiles++;
    }
    invocationCount++;
    final inputFile = File(
      '${fixtures.path}${Platform.pathSeparator}'
      '${(golden!['qualificationInput']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final goldenFile = File(
      '${fixtures.path}${Platform.pathSeparator}'
      '${(golden['dartReference']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final oracle = <String, Object?>{
      'oracleVersion': wardrobeProfileResolverOracleVersion,
      'exporterVersion': wardrobeProfileResolverExporterVersion,
      'providerId': wardrobeProfileResolverId,
      'providerVersion': wardrobeProfileResolverVersion,
      'inputContract': 'wardrobe_profile_resolver_input/v1',
      'outputContract': 'ResolvedWardrobeItemProfile/v1',
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
      'familyIntegration': <String, Object?>{
        'familyReportPresent': withSink.familyIdentity.resolvedFamily != null,
        'familyState': withSink.familyIdentity.state.wireName,
        'familyConsumedByResolver': false,
        'familyOnResolvedProfile': false,
      },
      'orderingPolicy': <String, Object?>{
        'scenario': 'vision_v2_adversarial_scenarios_manifest_order',
        'invocation': 'single_scenario_invocation',
        'inputEvidence': 'orchestrator_all_evidence_concat_order',
        'sanitizedEvidence': 'resolver_id_sort',
        'mapKeys': 'canonical_json_lexicographic',
      },
      'invocations': [
        {
          'invocationId': invocationId,
          'viewCount': responses.length,
          'resolverInput': input,
          'resolverInputSha256': sha256.convert(_bytes(input)).toString(),
          'resolverOutput': output,
          'resolverOutputSha256': sha256.convert(_bytes(output)).toString(),
          'conflictFieldCount': scenarioConflicts,
          'knownFieldCount': knownFieldCount,
        },
      ],
    };
    final bytes = _bytes(oracle);
    final relative =
        'backend_qualification/provider_oracles/'
        'wardrobe_profile_resolver_v1/$id.oracle.json';
    writes[File(
          '${fixtures.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        )] =
        bytes;
    entries.add({
      'scenarioId': id,
      'providerId': wardrobeProfileResolverId,
      'status': 'ready',
      'oraclePath': relative,
      'oracleSha256': sha256.convert(bytes).toString(),
      'invocationCount': 1,
      'sourceParserFixtureSha256': parserSha,
      'oracleVersion': wardrobeProfileResolverOracleVersion,
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
    'totalInputEvidence': totalInputEvidence,
    'evidenceBySource': sortedCounts(evidenceBySource),
    'evidenceByNature': sortedCounts(evidenceByNature),
    'activeEvidence': activeEvidence,
    'inactiveEvidence': inactiveEvidence,
    'verifiedEvidence': verifiedEvidence,
    'unverifiedEvidence': unverifiedEvidence,
    'valueStateCounts': sortedCounts(valueStateCounts),
    'resolvedCanonicalCount': resolvedCanonical,
    'unresolvedCanonicalCount': unresolvedCanonical,
    'resolvedFamilyOnProfileCount': resolvedFamilyOnProfile,
    'familyReportPresentCount': familyReportPresent,
    'familyIgnoredByResolverCount': familyIgnoredByResolver,
    'resolvedObservationFieldCount': resolvedObservationFields,
    'resolvedCapabilityFieldCount': resolvedCapabilityFields,
    'kbSelectedCount': kbSelected,
    'visualSelectedCount': visualSelected,
    'aiSelectedCount': aiSelected,
    'legacySelectedCount': legacySelected,
    'userCorrectionSelectedCount': userCorrectionSelected,
    'compatibilityFallbackSelectedCount': compatibilityFallbackSelected,
    'conflictFieldCount': conflictFields,
    'fullyUnresolvedProfileCount': fullyUnresolvedProfiles,
    'selectedByProperty': sortedCounts(selectedByProperty),
    'unresolvedProperties': sortedCounts(unresolvedProperties),
    'conflictProperties': sortedCounts(conflictProperties),
  };
  final manifest = <String, Object?>{
    'manifestVersion': 1,
    'oracleVersion': wardrobeProfileResolverOracleVersion,
    'exporterVersion': wardrobeProfileResolverExporterVersion,
    'providerId': wardrobeProfileResolverId,
    'providerVersion': wardrobeProfileResolverVersion,
    'scenarioCount': catalog.length,
    'readyScenarioCount': ready,
    'sourceMissingScenarioCount': sourceMissing,
    'invocationCount': invocationCount,
    ...bindings,
    'generationCommand':
        'flutter test --dart-define=UPDATE_WARDROBE_PROFILE_RESOLVER_ORACLES=true '
        'test/backend_wardrobe_profile_resolver_oracle_export_test.dart',
    'orderingPolicy': <String, Object?>{
      'scenario': 'vision_v2_adversarial_scenarios_manifest_order',
      'invocation': 'single_scenario_invocation',
      'inputEvidence': 'orchestrator_all_evidence_concat_order',
      'sanitizedEvidence': 'resolver_id_sort',
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
        '${wardrobeProfileResolverOracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
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

final class _ResolverTrace implements WardrobeProfileResolverTraceSink {
  _ResolverTrace(this.scenarioId);

  final String scenarioId;
  int before = 0;
  int after = 0;
  Map<String, Object?>? _input;
  final List<Map<String, Object?>> records = [];

  @override
  void beforeInvocation({
    required String itemId,
    required List<ProfileEvidence> evidence,
  }) {
    before++;
    _input = _resolverInput(itemId: itemId, evidence: evidence);
  }

  @override
  void afterInvocation({
    required String itemId,
    required List<ProfileEvidence> evidence,
    required ResolvedWardrobeItemProfile output,
  }) {
    final current = _resolverInput(itemId: itemId, evidence: evidence);
    if (_input == null || !_equalBytes(_bytes(current), _bytes(_input!))) {
      throw FormatException('resolver_input_changed:$scenarioId');
    }
    after++;
    records.add({
      'resolverInput': current,
      'resolverOutput': output.toMap(),
    });
  }
}

Map<String, Object?> _resolverInput({
  required String itemId,
  required List<ProfileEvidence> evidence,
}) => <String, Object?>{
  'itemId': itemId,
  'evidence': evidence.map((item) => item.toMap()).toList(),
};

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
