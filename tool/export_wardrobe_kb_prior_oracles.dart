import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

import 'export_clothing_knowledge_base_prior_artifact.dart' as kb_artifact;

const kbPriorProviderId = 'WardrobeKnowledgeBasePriorProvider';
const kbPriorProviderVersion = 'wardrobe-kb-prior-provider-v1';
const kbPriorOracleVersion = 1;
const kbPriorExporterVersion = 1;
const kbPriorOracleManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_wardrobe_kb_prior_oracle_manifest.json';

Map<String, Object?> exportWardrobeKnowledgeBasePriorOracles({
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
    '${Platform.pathSeparator}wardrobe_knowledge_base_prior_provider.dart',
  );
  final callSiteSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}domain${Platform.pathSeparator}wardrobe_profile'
    '${Platform.pathSeparator}vision_v2_shadow_analysis.dart',
  );
  final kbSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}data${Platform.pathSeparator}'
    'clothing_knowledge_base.dart',
  );
  final serializerSources =
      [
        'lib/domain/wardrobe_profile/wardrobe_knowledge_base_prior_provider.dart',
        'lib/domain/wardrobe_profile/wardrobe_profile_contract.dart',
        'lib/data/clothing_knowledge_base.dart',
      ].map(
        (path) => File(
          '${repositoryRoot.path}${Platform.pathSeparator}'
          '${path.replaceAll('/', Platform.pathSeparator)}',
        ),
      );
  final exporterSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}tool'
    '${Platform.pathSeparator}export_wardrobe_kb_prior_oracles.dart',
  );
  final taxonomy = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}data${Platform.pathSeparator}'
    'clothing_knowledge_base.dart',
  ).readAsStringSync();
  final allowed = RegExp(
    r"canonicalType:\s*'([^']+)'",
  ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
  final artifactExport = kb_artifact.exportClothingKnowledgeBasePriorArtifact(
    repositoryRoot: repositoryRoot,
    write: write,
  );
  final bindings = <String, Object?>{
    'providerImplementationSha256': _shaFile(providerSource),
    'callSitePreparationSha256': _shaFile(callSiteSource),
    'serializerSha256': _combinedSha(serializerSources),
    'exporterImplementationSha256': _shaFile(exporterSource),
    'knowledgeBaseSourceSha256': _shaFile(kbSource),
    'knowledgeBaseArtifactContentSha256':
        artifactExport['artifactContentSha256'],
    'knowledgeBaseArtifactSchemaVersion':
        kb_artifact.clothingKbPriorArtifactSchemaVersion,
    'knowledgeBaseArtifactVersion': kb_artifact.clothingKbPriorArtifactVersion,
    'upstreamBindings': <String, Object?>{
      'observationEvidence': 'qualification-v1',
      'identityQualification': 'vision-identity-qualification-v1',
      'capabilityInference': 'capability-inference-v1',
      'familyIdentity': 'vision-family-identity-resolver-v1',
      'knowledgeBaseArtifact': kb_artifact.clothingKbPriorArtifactVersion,
    },
  };
  final entries = <Map<String, Object?>>[];
  final writes = <File, List<int>>{};
  final invocationIds = <String>{};
  var ready = 0;
  var sourceMissing = 0;
  var invocationCount = 0;
  var kbEvidenceCount = 0;
  var scenariosWithCanonical = 0;
  var scenariosWithFamilyOnly = 0;
  var scenariosWithNoKb = 0;
  final propertyCounts = <String, int>{};
  final canonicalKeys = <String, int>{};

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
        'providerId': kbPriorProviderId,
        'status': 'source_missing',
        'reason': 'captured_source_not_ready',
        'oracleVersion': kbPriorOracleVersion,
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
    final observed = _KbTrace(id);
    final withSink = const VisionV2ShadowOrchestrator().analyze(
      itemId: id,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      knowledgeBasePriorTraceSink: observed,
    );
    if (!_equalBytes(_bytes(baseline.toMap()), _bytes(withSink.toMap()))) {
      throw FormatException('observer_changed_authoritative_behavior:$id');
    }
    if (observed.before != 1 ||
        observed.after != 1 ||
        observed.records.length != 1) {
      throw FormatException('kb_invocation_count_invalid:$id');
    }
    final invocationId = '$id::wardrobe-kb-prior-provider';
    if (!invocationIds.add(invocationId)) {
      throw FormatException('duplicate_kb_invocation_id:$invocationId');
    }
    final record = observed.records.single;
    final input = _object(record['providerInput']);
    final output = _list(record['providerOutput']);
    final evidenceMaps = output.map(_object).toList();
    kbEvidenceCount += evidenceMaps.length;
    if (evidenceMaps.isEmpty) {
      scenariosWithNoKb++;
    }
    final activeCanonical = _list(input['existingEvidence'])
        .map(_object)
        .where(
          (item) =>
              item['active'] == true &&
              item['property'] == WardrobeProfileProperty.canonicalType,
        )
        .map((item) => '${item['value']}')
        .toSet();
    if (activeCanonical.isNotEmpty) {
      scenariosWithCanonical++;
      for (final key in activeCanonical) {
        canonicalKeys[key] = (canonicalKeys[key] ?? 0) + 1;
      }
    } else if (withSink.familyIdentity.resolvedFamily != null) {
      scenariosWithFamilyOnly++;
    }
    for (final item in evidenceMaps) {
      final property = item['property']! as String;
      propertyCounts[property] = (propertyCounts[property] ?? 0) + 1;
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
      'oracleVersion': kbPriorOracleVersion,
      'exporterVersion': kbPriorExporterVersion,
      'providerId': kbPriorProviderId,
      'providerVersion': kbPriorProviderVersion,
      'inputContract': 'wardrobe_kb_prior_input/v1',
      'outputContract': 'ProfileEvidence[]/kb_prior_v1',
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
      'orderingPolicy': <String, Object?>{
        'scenario': 'vision_v2_adversarial_scenarios_manifest_order',
        'invocation': 'single_scenario_invocation',
        'existingEvidence': 'orchestrator_initial_evidence_order',
        'kbEvidence': 'provider_emission_order',
        'mapKeys': 'canonical_json_lexicographic',
      },
      'invocations': [
        {
          'invocationId': invocationId,
          'viewCount': responses.length,
          'providerInput': input,
          'providerInputSha256': sha256.convert(_bytes(input)).toString(),
          'providerOutput': output,
          'providerOutputSha256': sha256.convert(_bytes(output)).toString(),
        },
      ],
    };
    final bytes = _bytes(oracle);
    final relative =
        'backend_qualification/provider_oracles/'
        'wardrobe_knowledge_base_prior_provider_v1/$id.oracle.json';
    writes[File(
          '${fixtures.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        )] =
        bytes;
    entries.add({
      'scenarioId': id,
      'providerId': kbPriorProviderId,
      'status': 'ready',
      'oraclePath': relative,
      'oracleSha256': sha256.convert(bytes).toString(),
      'invocationCount': 1,
      'sourceParserFixtureSha256': parserSha,
      'oracleVersion': kbPriorOracleVersion,
    });
    ready++;
  }

  final coverage = <String, Object?>{
    'kbEvidenceCount': kbEvidenceCount,
    'scenariosWithCanonicalType': scenariosWithCanonical,
    'scenariosWithFamilyOnlyNoKb': scenariosWithFamilyOnly,
    'scenariosWithNoKbEvidence': scenariosWithNoKb,
    'evidenceCountByProperty': Map<String, Object?>.fromEntries(
      (propertyCounts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => MapEntry(e.key, e.value)),
    ),
    'canonicalKeyDistribution': Map<String, Object?>.fromEntries(
      (canonicalKeys.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => MapEntry(e.key, e.value)),
    ),
  };
  final manifest = <String, Object?>{
    'manifestVersion': 1,
    'oracleVersion': kbPriorOracleVersion,
    'exporterVersion': kbPriorExporterVersion,
    'providerId': kbPriorProviderId,
    'providerVersion': kbPriorProviderVersion,
    'scenarioCount': catalog.length,
    'readyScenarioCount': ready,
    'sourceMissingScenarioCount': sourceMissing,
    'invocationCount': invocationCount,
    ...bindings,
    'generationCommand':
        'flutter test --dart-define=UPDATE_WARDROBE_KB_PRIOR_ORACLES=true '
        'test/backend_wardrobe_kb_prior_oracle_export_test.dart',
    'orderingPolicy': <String, Object?>{
      'scenario': 'vision_v2_adversarial_scenarios_manifest_order',
      'invocation': 'single_scenario_invocation',
      'existingEvidence': 'orchestrator_initial_evidence_order',
      'kbEvidence': 'provider_emission_order',
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
        '${kbPriorOracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
      ),
      manifestBytes,
    );
  }
  return <String, Object?>{
    'ready': ready,
    'sourceMissing': sourceMissing,
    'invocationCount': invocationCount,
    'kbEvidenceCount': kbEvidenceCount,
    'manifestBytes': manifestBytes,
    'oracleBytesByPath': {
      for (final item in writes.entries) item.key.path: item.value,
    },
    'coverage': coverage,
    'artifactContentSha256': artifactExport['artifactContentSha256'],
    ...bindings,
  };
}

final class _KbTrace implements WardrobeKnowledgeBasePriorTraceSink {
  _KbTrace(this.scenarioId);

  final String scenarioId;
  int before = 0;
  int after = 0;
  Map<String, Object?>? _input;
  final List<Map<String, Object?>> records = [];

  @override
  void beforeInvocation({
    required Map<String, dynamic> document,
    required List<ProfileEvidence> existingEvidence,
  }) {
    before++;
    _input = _providerInput(
      document: document,
      existingEvidence: existingEvidence,
    );
  }

  @override
  void afterInvocation({
    required Map<String, dynamic> document,
    required List<ProfileEvidence> existingEvidence,
    required List<ProfileEvidence> output,
  }) {
    final current = _providerInput(
      document: document,
      existingEvidence: existingEvidence,
    );
    if (_input == null || !_equalBytes(_bytes(current), _bytes(_input!))) {
      throw FormatException('kb_input_changed:$scenarioId');
    }
    after++;
    records.add({
      'providerInput': current,
      'providerOutput': output.map((item) => item.toMap()).toList(),
    });
  }
}

Map<String, Object?> _providerInput({
  required Map<String, dynamic> document,
  required List<ProfileEvidence> existingEvidence,
}) => <String, Object?>{
  'document': Map<String, Object?>.from(document),
  'existingEvidence': existingEvidence.map((item) => item.toMap()).toList(),
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
