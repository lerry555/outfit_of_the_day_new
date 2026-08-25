import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/canonical_observation_consistency_validator.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

const canonicalConsistencyProviderId =
    'CanonicalObservationConsistencyValidator';
const canonicalConsistencyProviderVersion = 'canonical-consistency-v1';
const canonicalConsistencyOracleManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_canonical_consistency_oracle_manifest.json';

Map<String, Object?> exportCanonicalConsistencyOracles({
  required Directory repositoryRoot,
  required bool write,
}) {
  final fixtures = Directory(
    '${repositoryRoot.path}${Platform.pathSeparator}test'
    '${Platform.pathSeparator}fixtures',
  );
  final captures = _byId(
    _read(
      File(
        '${fixtures.path}${Platform.pathSeparator}'
        'backend_qualification_capture_manifest.json',
      ),
    )['fixtures'],
  );
  final goldens = _byId(
    _read(
      File(
        '${fixtures.path}${Platform.pathSeparator}'
        'backend_qualification_golden_manifest.json',
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
  final taxonomy = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}data${Platform.pathSeparator}'
    'clothing_knowledge_base.dart',
  ).readAsStringSync();
  final allowed = RegExp(
    r"canonicalType:\s*'([^']+)'",
  ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
  final entries = <Map<String, Object?>>[];
  final writes = <File, List<int>>{};
  var ready = 0;
  var missing = 0;
  for (final raw in catalog) {
    final id = _map(raw)['id']! as String;
    final capture = captures[id];
    final golden = goldens[id];
    if (capture?['captureStatus'] != 'captured' ||
        golden?['goldenStatus'] != 'ready') {
      missing++;
      entries.add({
        'scenarioId': id,
        'providerId': canonicalConsistencyProviderId,
        'status': 'source_missing',
        'reason': 'captured_source_not_ready',
        'contractVersion': 1,
      });
      continue;
    }
    final parser = File(
      '${repositoryRoot.path}${Platform.pathSeparator}'
      '${(capture!['parserFixture']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final parserBytes = parser.readAsBytesSync();
    final parserSha = sha256.convert(parserBytes).toString();
    if (parserSha != capture['parserFixtureSha256']) {
      throw FormatException('parser_sha_mismatch:$id');
    }
    final fixtureJson = parser.readAsStringSync();
    final responses = const VisionParserFixtureReplay().decodeResponses(
      fixtureJson,
      allowedCanonicalTypes: allowed,
    );
    final binding = const VisionParserFixtureReplay().decodeBinding(fixtureJson);
    final trace = _Trace();
    const VisionV2ShadowOrchestrator().analyze(
      itemId: id,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      canonicalConsistencyTraceSink: trace,
    );
    if (trace.before != 1 || trace.after != 1 || trace.records.length != 1) {
      throw FormatException('canonical_consistency_invocation_invalid:$id');
    }
    final inputFile = File(
      '${fixtures.path}${Platform.pathSeparator}'
      '${(golden!['qualificationInput']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final goldenFile = File(
      '${fixtures.path}${Platform.pathSeparator}'
      '${(golden['dartReference']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final oracle = {
      'oracleContractVersion': 1,
      'providerId': canonicalConsistencyProviderId,
      'providerVersion': canonicalConsistencyProviderVersion,
      'scenarioId': id,
      'sourceParserFixtureSha256': parserSha,
      'sourceQualificationInputSha256': sha256
          .convert(inputFile.readAsBytesSync())
          .toString(),
      'sourceDartReferenceGoldenSha256': sha256
          .convert(goldenFile.readAsBytesSync())
          .toString(),
      ...trace.records.single,
    };
    final bytes = _bytes(oracle);
    final relative =
        'backend_qualification/provider_oracles/'
        'canonical_consistency_v1/$id.oracle.json';
    writes[File(
          '${fixtures.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        )] =
        bytes;
    entries.add({
      'scenarioId': id,
      'providerId': canonicalConsistencyProviderId,
      'status': 'ready',
      'oraclePath': relative,
      'oracleSha256': sha256.convert(bytes).toString(),
      'sourceParserFixtureSha256': parserSha,
      'contractVersion': 1,
    });
    ready++;
  }
  final manifest = {
    'manifestVersion': 1,
    'oracleContractVersion': 1,
    'providerId': canonicalConsistencyProviderId,
    'providerVersion': canonicalConsistencyProviderVersion,
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
        '${canonicalConsistencyOracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
      ),
      manifestBytes,
    );
  }
  return {
    'ready': ready,
    'sourceMissing': missing,
    'invocationCount': ready,
    'manifestBytes': manifestBytes,
  };
}

final class _Trace implements CanonicalConsistencyTraceSink {
  int before = 0;
  int after = 0;
  Map<String, Object?>? input;
  final List<Map<String, Object?>> records = [];

  @override
  void beforeInvocation({
    required List<ProfileEvidence> identityEvidence,
    required List<ProfileEvidence> observationEvidence,
  }) {
    before++;
    input = _input(identityEvidence, observationEvidence);
  }

  @override
  void afterInvocation({
    required List<ProfileEvidence> identityEvidence,
    required List<ProfileEvidence> observationEvidence,
    required CanonicalConsistencyReport output,
  }) {
    after++;
    final current = _input(identityEvidence, observationEvidence);
    if (jsonEncode(current) != jsonEncode(input)) {
      throw const FormatException('canonical_consistency_input_changed');
    }
    records.add({'providerInput': current, 'providerOutput': output.toMap()});
  }
}

Map<String, Object?> _input(
  List<ProfileEvidence> identityEvidence,
  List<ProfileEvidence> observationEvidence,
) => {
  'identityEvidence': identityEvidence.map((item) => item.toMap()).toList(),
  'observationEvidence': observationEvidence
      .map((item) => item.toMap())
      .toList(),
};
Map<String, Map<String, Object?>> _byId(Object? value) => {
  for (final raw in _list(value)) _map(raw)['id']! as String: _map(raw),
};
Map<String, Object?> _read(File file) =>
    _map(jsonDecode(file.readAsStringSync()));
Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException('expected_object');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('expected_list');
  return List<Object?>.from(value);
}

List<int> _bytes(Object? value) => utf8.encode(
  '${const JsonEncoder.withIndent('  ').convert(_canonical(value))}\n',
);
Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((item) => item.toString()).toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList(growable: false);
  if (value is double && value == 0) return 0;
  return value;
}

void _write(File file, List<int> bytes) {
  file.parent.createSync(recursive: true);
  final temporary = File('${file.path}.tmp');
  temporary.writeAsBytesSync(bytes, flush: true);
  temporary.renameSync(file.path);
}
