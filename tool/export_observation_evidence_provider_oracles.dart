import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

const providerId = 'VisionObservationEvidenceProvider';
const providerVersion = 'qualification-v1';
const oracleContractVersion = 1;
const oracleManifestPath =
    'test/fixtures/backend_qualification/backend_provider_oracle_manifest.json';

final class ProviderOracleExportResult {
  const ProviderOracleExportResult({
    required this.ready,
    required this.sourceMissing,
    required this.invocationCount,
    required this.oracleSha256ByScenario,
    required this.manifestBytes,
  });

  final int ready;
  final int sourceMissing;
  final int invocationCount;
  final Map<String, String> oracleSha256ByScenario;
  final List<int> manifestBytes;
}

ProviderOracleExportResult exportObservationEvidenceProviderOracles({
  required Directory repositoryRoot,
  required bool write,
}) {
  final fixtureRoot = Directory(
    '${repositoryRoot.path}${Platform.pathSeparator}'
    'test${Platform.pathSeparator}fixtures',
  );
  final captureManifest = _readObject(
    File(
      '${fixtureRoot.path}${Platform.pathSeparator}'
      'backend_qualification_capture_manifest.json',
    ),
  );
  final goldenManifest = _readObject(
    File(
      '${fixtureRoot.path}${Platform.pathSeparator}'
      'backend_qualification_golden_manifest.json',
    ),
  );
  final captureById = {
    for (final raw in _list(captureManifest['fixtures'], 'capture.fixtures'))
      _text(_object(raw, 'capture.fixture')['id'], 'capture.id'): _object(
        raw,
        'capture.fixture',
      ),
  };
  final goldenById = {
    for (final raw in _list(goldenManifest['fixtures'], 'golden.fixtures'))
      _text(_object(raw, 'golden.fixture')['id'], 'golden.id'): _object(
        raw,
        'golden.fixture',
      ),
  };
  final catalog = _readList(
    File(
      '${fixtureRoot.path}${Platform.pathSeparator}'
      '${_text(goldenManifest['sourceCatalog'], 'sourceCatalog')}',
    ),
  );
  final taxonomySource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}'
    'lib${Platform.pathSeparator}data${Platform.pathSeparator}'
    'clothing_knowledge_base.dart',
  ).readAsStringSync();
  final allowedCanonicalTypes = RegExp(
    r"canonicalType:\s*'([^']+)'",
  ).allMatches(taxonomySource).map((match) => match.group(1)!).toSet();

  final entries = <Map<String, Object?>>[];
  final pendingWrites = <File, List<int>>{};
  final hashes = <String, String>{};
  var ready = 0;
  var sourceMissing = 0;
  var invocationCount = 0;

  for (final raw in catalog) {
    final scenario = _object(raw, 'catalog.scenario');
    final id = _text(scenario['id'], 'catalog.id');
    final capture = captureById[id];
    final golden = goldenById[id];
    if (capture == null ||
        capture['captureStatus'] != 'captured' ||
        golden == null ||
        golden['goldenStatus'] != 'ready') {
      sourceMissing++;
      entries.add({
        'scenarioId': id,
        'providerId': providerId,
        'status': 'source_missing',
        'reason': 'captured_source_not_ready',
        'contractVersion': oracleContractVersion,
      });
      continue;
    }

    final built = _buildOracle(
      repositoryRoot: repositoryRoot,
      fixtureRoot: fixtureRoot,
      scenarioId: id,
      capture: capture,
      golden: golden,
      allowedCanonicalTypes: allowedCanonicalTypes,
    );
    invocationCount += built.invocationCount;
    final firstBytes = _canonicalBytes(built.oracle);
    final second = _buildOracle(
      repositoryRoot: repositoryRoot,
      fixtureRoot: fixtureRoot,
      scenarioId: id,
      capture: capture,
      golden: golden,
      allowedCanonicalTypes: allowedCanonicalTypes,
    );
    final secondBytes = _canonicalBytes(second.oracle);
    if (!_sameBytes(firstBytes, secondBytes)) {
      throw FormatException('non_deterministic_oracle:$id');
    }
    final oracleSha = sha256.convert(firstBytes).toString();
    final relativePath =
        'backend_qualification/provider_oracles/'
        'vision_observation_evidence_v1/$id.oracle.json';
    final target = File(
      '${fixtureRoot.path}${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    pendingWrites[target] = firstBytes;
    hashes[id] = oracleSha;
    ready++;
    entries.add({
      'scenarioId': id,
      'providerId': providerId,
      'status': 'ready',
      'oraclePath': relativePath,
      'oracleSha256': oracleSha,
      'providerInputSha256': built.providerInputSha256,
      'providerOutputSha256': built.providerOutputSha256,
      'sourceParserFixtureSha256': built.sourceParserFixtureSha256,
      'sourceGoldenSha256': built.sourceGoldenSha256,
      'contractVersion': oracleContractVersion,
    });
  }
  final manifest = {
    'manifestVersion': 1,
    'oracleContractVersion': oracleContractVersion,
    'providerId': providerId,
    'providerVersion': providerVersion,
    'fixtures': entries,
  };
  final manifestBytes = _canonicalBytes(manifest);
  if (write) {
    for (final entry in pendingWrites.entries) {
      _atomicWrite(entry.key, entry.value);
    }
    _atomicWrite(
      File(
        '${repositoryRoot.path}${Platform.pathSeparator}'
        '${oracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
      ),
      manifestBytes,
    );
  }
  return ProviderOracleExportResult(
    ready: ready,
    sourceMissing: sourceMissing,
    invocationCount: invocationCount,
    oracleSha256ByScenario: Map.unmodifiable(hashes),
    manifestBytes: List.unmodifiable(manifestBytes),
  );
}

final class _BuiltOracle {
  const _BuiltOracle({
    required this.oracle,
    required this.invocationCount,
    required this.providerInputSha256,
    required this.providerOutputSha256,
    required this.sourceParserFixtureSha256,
    required this.sourceGoldenSha256,
  });

  final Map<String, Object?> oracle;
  final int invocationCount;
  final String providerInputSha256;
  final String providerOutputSha256;
  final String sourceParserFixtureSha256;
  final String sourceGoldenSha256;
}

_BuiltOracle _buildOracle({
  required Directory repositoryRoot,
  required Directory fixtureRoot,
  required String scenarioId,
  required Map<String, Object?> capture,
  required Map<String, Object?> golden,
  required Set<String> allowedCanonicalTypes,
}) {
  final parserRelative = _text(capture['parserFixture'], 'parserFixture');
  final parserFile = File(
    '${repositoryRoot.path}${Platform.pathSeparator}'
    '${parserRelative.replaceAll('/', Platform.pathSeparator)}',
  );
  final parserBytes = parserFile.readAsBytesSync();
  final parserSha = sha256.convert(parserBytes).toString();
  if (parserSha != capture['parserFixtureSha256']) {
    throw FormatException('parser_fixture_sha256_mismatch:$scenarioId');
  }
  final inputRelative = _text(golden['qualificationInput'], 'inputPath');
  final goldenRelative = _text(golden['dartReference'], 'goldenPath');
  final inputFile = File(
    '${fixtureRoot.path}${Platform.pathSeparator}'
    '${inputRelative.replaceAll('/', Platform.pathSeparator)}',
  );
  final goldenFile = File(
    '${fixtureRoot.path}${Platform.pathSeparator}'
    '${goldenRelative.replaceAll('/', Platform.pathSeparator)}',
  );
  if (!inputFile.existsSync()) {
    throw FormatException('qualification_input_missing:$scenarioId');
  }
  if (!goldenFile.existsSync()) {
    throw FormatException('dart_reference_missing:$scenarioId');
  }
  final inputBytes = inputFile.readAsBytesSync();
  final goldenBytes = goldenFile.readAsBytesSync();
  final inputMap = _readObject(inputFile);
  final finalGolden = _readObject(goldenFile);
  if (finalGolden['fixtureId'] != scenarioId ||
      inputMap['contractVersion'] != 1) {
    throw FormatException('source_contract_mismatch:$scenarioId');
  }
  final parserRoot = _readObject(parserFile);
  if (parserRoot['fixtureId'] != scenarioId) {
    throw FormatException('parser_scenario_mismatch:$scenarioId');
  }
  final provenance = _object(
    parserRoot['captureProvenance'],
    'captureProvenance',
  );
  for (final key in [
    'modelIdentifier',
    'promptVersion',
    'pipelineVersion',
    'visionSchemaVersion',
    'parserVersion',
  ]) {
    if (provenance[key] != capture[key]) {
      throw FormatException('source_version_mismatch:$scenarioId:$key');
    }
  }
  final captureViews = _list(capture['views'], 'capture.views');
  final parserViews = _list(parserRoot['views'], 'parser.views');
  if (captureViews.length != parserViews.length) {
    throw FormatException('ordered_view_count_mismatch:$scenarioId');
  }
  for (var index = 0; index < captureViews.length; index++) {
    final expected = _object(captureViews[index], 'capture.view');
    final actual = _object(parserViews[index], 'parser.view');
    for (final key in ['viewId', 'assetPath', 'assetSha256', 'mimeType']) {
      if (expected[key] != actual[key]) {
        throw FormatException(
          'ordered_view_metadata_mismatch:$scenarioId:$index:$key',
        );
      }
    }
  }

  final fixtureJson = utf8.decode(parserBytes);
  final responses = const VisionParserFixtureReplay().decodeResponses(
    fixtureJson,
    allowedCanonicalTypes: allowedCanonicalTypes,
  );
  final binding = const VisionParserFixtureReplay().decodeBinding(fixtureJson);
  final trace = _TraceCollector();
  const VisionV2ShadowOrchestrator().analyze(
    itemId: scenarioId,
    response: responses.first,
    additionalResponses: responses.skip(1),
    multiViewSubjectBinding: binding,
    observationEvidenceTraceSink: trace,
  );
  if (trace.beforeCount != 1 || trace.afterCount != 1) {
    throw FormatException(
      'provider_invocation_count_invalid:$scenarioId:'
      '${trace.beforeCount}:${trace.afterCount}',
    );
  }
  if (!identical(trace.inputBefore, trace.inputAfter)) {
    throw FormatException('provider_input_identity_changed:$scenarioId');
  }
  final providerInput = trace.inputBefore!.toMap();
  final providerOutput = trace.output!
      .map(_evidenceMap)
      .toList(growable: false);
  final expectedOutput = _list(
    finalGolden['observationEvidence'],
    'finalGolden.observationEvidence',
  ).map((item) => _object(item, 'observationEvidence')).toList();
  if (_canonicalEvidenceJson(providerOutput) !=
      _canonicalEvidenceJson(expectedOutput)) {
    throw FormatException('final_golden_projection_mismatch:$scenarioId');
  }
  final providerInputSha = sha256
      .convert(_canonicalBytes(providerInput))
      .toString();
  final providerOutputSha = sha256
      .convert(_canonicalBytes(providerOutput))
      .toString();
  final orderedViews = <Map<String, Object?>>[
    for (final raw in captureViews)
      {
        'viewId': _object(raw, 'view')['viewId'],
        'assetSha256': _object(raw, 'view')['assetSha256'],
        'mimeType': _object(raw, 'view')['mimeType'],
      },
  ];
  final oracle = <String, Object?>{
    'oracleContractVersion': oracleContractVersion,
    'providerId': providerId,
    'providerVersion': providerVersion,
    'scenarioId': scenarioId,
    'sourceParserFixtureId': scenarioId,
    'sourceParserFixtureSha256': parserSha,
    'sourceQualificationInputSha256': sha256.convert(inputBytes).toString(),
    'sourceDartReferenceGoldenSha256': sha256.convert(goldenBytes).toString(),
    'pipelineVersion': provenance['pipelineVersion'],
    'parserVersion': provenance['parserVersion'],
    'qualificationProducerVersion': finalGolden['producerVersion'],
    'orderedViewProvenance': orderedViews,
    'providerInput': providerInput,
    'providerInputSha256': providerInputSha,
    'providerOutput': providerOutput,
    'providerOutputSha256': providerOutputSha,
  };
  _assertOracle(oracle);
  return _BuiltOracle(
    oracle: oracle,
    invocationCount: 1,
    providerInputSha256: providerInputSha,
    providerOutputSha256: providerOutputSha,
    sourceParserFixtureSha256: parserSha,
    sourceGoldenSha256: sha256.convert(goldenBytes).toString(),
  );
}

final class _TraceCollector implements VisionObservationEvidenceTraceSink {
  int beforeCount = 0;
  int afterCount = 0;
  ClothingObservationBundle? inputBefore;
  ClothingObservationBundle? inputAfter;
  List<ProfileEvidence>? output;

  @override
  void beforeInvocation(ClothingObservationBundle input) {
    beforeCount++;
    inputBefore = input;
  }

  @override
  void afterInvocation(
    ClothingObservationBundle input,
    List<ProfileEvidence> output,
  ) {
    afterCount++;
    inputAfter = input;
    this.output = output;
  }
}

Map<String, Object?> _evidenceMap(ProfileEvidence evidence) => {
  'id': evidence.id,
  'property': evidence.property,
  'value': evidence.value,
  'valueState': evidence.valueState.wireName,
  'source': evidence.source.wireName,
  'nature': evidence.nature.wireName,
  'confidence': evidence.confidence,
  'method': evidence.method,
  'supportingEvidenceIds': <String>[],
};

String _canonicalEvidenceJson(List<Object?> evidence) {
  final normalized =
      evidence
          .map((item) => _object(item, 'evidence'))
          .map(
            (item) => {
              ...item,
              'supportingEvidenceIds': _list(
                item['supportingEvidenceIds'] ?? const [],
                'supportingEvidenceIds',
              ).map((value) => value.toString()).toList()..sort(),
            },
          )
          .toList()
        ..sort(
          (left, right) =>
              left['id'].toString().compareTo(right['id'].toString()),
        );
  return utf8.decode(_canonicalBytes(normalized));
}

void _assertOracle(Map<String, Object?> oracle) {
  if (oracle['oracleContractVersion'] != oracleContractVersion ||
      oracle['providerId'] != providerId ||
      oracle['providerVersion'] != providerVersion ||
      _list(oracle['orderedViewProvenance'], 'views').isEmpty ||
      oracle['providerInput'] is! Map ||
      oracle['providerOutput'] is! List) {
    throw const FormatException('provider_oracle_contract_invalid');
  }
  final bytes = _canonicalBytes(oracle);
  if (!_sameBytes(bytes, _canonicalBytes(jsonDecode(utf8.decode(bytes))))) {
    throw const FormatException('provider_oracle_round_trip_failed');
  }
}

List<int> _canonicalBytes(Object? value) => utf8.encode(
  '${const JsonEncoder.withIndent('  ').convert(_canonicalize(value))}\n',
);

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalize).toList(growable: false);
  }
  if (value is double && value == 0) return 0;
  return value;
}

void _atomicWrite(File target, List<int> bytes) {
  target.parent.createSync(recursive: true);
  final temporary = File('${target.path}.tmp');
  temporary.writeAsBytesSync(bytes, flush: true);
  temporary.renameSync(target.path);
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Map<String, Object?> _readObject(File file) =>
    _object(jsonDecode(file.readAsStringSync()), file.path);

List<Object?> _readList(File file) =>
    _list(jsonDecode(file.readAsStringSync()), file.path);

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) throw FormatException('$label:expected_object');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<Object?> _list(Object? value, String label) {
  if (value is! List) throw FormatException('$label:expected_list');
  return List<Object?>.from(value);
}

String _text(Object? value, String label) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$label:required_text');
  }
  return value.trim();
}
