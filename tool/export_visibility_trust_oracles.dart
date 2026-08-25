import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_visibility_trust.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

const visibilityProviderId = 'VisionVisibilityTrustQualifier';
const visibilityProviderVersion = 'visibility-trust-v1';
const visibilityOracleManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_visibility_trust_oracle_manifest.json';

Map<String, Object?> exportVisibilityTrustOracles({
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
  var invocationCount = 0;
  for (final raw in catalog) {
    final id = _map(raw)['id']! as String;
    final capture = captures[id];
    final golden = goldens[id];
    if (capture?['captureStatus'] != 'captured' ||
        golden?['goldenStatus'] != 'ready') {
      missing++;
      entries.add({
        'scenarioId': id,
        'providerId': visibilityProviderId,
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
    final fixtureJson = utf8.decode(parser.readAsBytesSync());
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
      visibilityTrustTraceSink: trace,
    );
    if (trace.before != responses.length ||
        trace.after != responses.length ||
        trace.records.length != responses.length) {
      throw FormatException('visibility_invocation_count_invalid:$id');
    }
    final views = _list(capture['views']);
    final invocations = <Map<String, Object?>>[];
    for (var i = 0; i < trace.records.length; i++) {
      final record = trace.records[i];
      final view = _map(views[i]);
      final input = _map(record['providerInput']);
      final output = _map(record['providerOutput']);
      invocations.add({
        'viewIndex': i,
        'viewId': view['viewId'],
        'assetSha256': view['assetSha256'],
        'providerInput': input,
        'providerInputSha256': sha256.convert(_bytes(input)).toString(),
        'providerOutput': output,
        'providerOutputSha256': sha256.convert(_bytes(output)).toString(),
      });
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
      'providerId': visibilityProviderId,
      'providerVersion': visibilityProviderVersion,
      'scenarioId': id,
      'sourceParserFixtureSha256': parserSha,
      'sourceQualificationInputSha256': sha256
          .convert(inputFile.readAsBytesSync())
          .toString(),
      'sourceDartReferenceGoldenSha256': sha256
          .convert(goldenFile.readAsBytesSync())
          .toString(),
      'invocations': invocations,
    };
    final first = _bytes(oracle);
    final relative =
        'backend_qualification/provider_oracles/'
        'vision_visibility_trust_v1/$id.oracle.json';
    writes[File(
          '${fixtures.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        )] =
        first;
    entries.add({
      'scenarioId': id,
      'providerId': visibilityProviderId,
      'status': 'ready',
      'oraclePath': relative,
      'oracleSha256': sha256.convert(first).toString(),
      'invocationCount': invocations.length,
      'sourceParserFixtureSha256': parserSha,
      'contractVersion': 1,
    });
    ready++;
    invocationCount += invocations.length;
  }
  final manifest = {
    'manifestVersion': 1,
    'oracleContractVersion': 1,
    'providerId': visibilityProviderId,
    'providerVersion': visibilityProviderVersion,
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
        '${visibilityOracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
      ),
      manifestBytes,
    );
  }
  return {
    'ready': ready,
    'sourceMissing': missing,
    'invocationCount': invocationCount,
    'manifestBytes': manifestBytes,
  };
}

final class _Trace implements VisionVisibilityTrustTraceSink {
  int before = 0;
  int after = 0;
  final List<Map<String, Object?>> _inputs = [];
  final List<Map<String, Object?>> records = [];

  @override
  void beforeInvocation({
    required ClothingObservationBundle bundle,
    required VisionInputAssessment inputAssessment,
    required int viewCount,
    required Map<String, Set<ObservationVisualRegion>> complementaryRegions,
  }) {
    before++;
    _inputs.add(
      _input(bundle, inputAssessment, viewCount, complementaryRegions),
    );
  }

  @override
  void afterInvocation({
    required ClothingObservationBundle bundle,
    required VisionInputAssessment inputAssessment,
    required int viewCount,
    required Map<String, Set<ObservationVisualRegion>> complementaryRegions,
    required VisionVisibilityTrustReport output,
  }) {
    after++;
    final value = _input(
      bundle,
      inputAssessment,
      viewCount,
      complementaryRegions,
    );
    if (jsonEncode(value) != jsonEncode(_inputs[after - 1])) {
      throw const FormatException('visibility_input_changed');
    }
    records.add({
      'providerInput': value,
      'providerOutput': {
        'qualifiedBundle': output.qualifiedBundle.toMap(),
        ...output.toMap(),
      },
    });
  }
}

Map<String, Object?> _input(
  ClothingObservationBundle bundle,
  VisionInputAssessment assessment,
  int viewCount,
  Map<String, Set<ObservationVisualRegion>> complementary,
) => {
  'bundle': bundle.toMap(),
  'inputAssessment': assessment.wireName,
  'viewCount': viewCount,
  'complementaryRegions': {
    for (final entry in complementary.entries)
      entry.key: entry.value.map((item) => item.wireName).toList()..sort(),
  },
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
