import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_framing_attestation.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_subject_safety.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_visibility_trust.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

const providerId = 'VisionFramingAttestor';
const providerVersion = 'framing-attestor-v1';
const oracleContractVersion = 1;
const framingOracleManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_framing_attestor_oracle_manifest.json';

final class FramingOracleExportResult {
  const FramingOracleExportResult({
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

FramingOracleExportResult exportFramingAttestorOracles({
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
      scenarioId: id,
      capture: capture,
      golden: golden,
      allowedCanonicalTypes: allowedCanonicalTypes,
    );
    final firstBytes = _canonicalBytes(built.oracle);
    final second = _buildOracle(
      repositoryRoot: repositoryRoot,
      scenarioId: id,
      capture: capture,
      golden: golden,
      allowedCanonicalTypes: allowedCanonicalTypes,
    );
    if (!_sameBytes(firstBytes, _canonicalBytes(second.oracle))) {
      throw FormatException('non_deterministic_framing_oracle:$id');
    }
    final oracleSha = sha256.convert(firstBytes).toString();
    final relativePath =
        'backend_qualification/provider_oracles/'
        'vision_framing_attestor_v1/$id.oracle.json';
    final target = File(
      '${fixtureRoot.path}${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    pendingWrites[target] = firstBytes;
    hashes[id] = oracleSha;
    invocationCount += built.invocationCount;
    ready++;
    entries.add({
      'scenarioId': id,
      'providerId': providerId,
      'status': 'ready',
      'oraclePath': relativePath,
      'oracleSha256': oracleSha,
      'invocationCount': built.invocationCount,
      'sourceParserFixtureSha256': built.sourceParserFixtureSha256,
      'sourceQualificationInputSha256': built.sourceQualificationInputSha256,
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
        '${framingOracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
      ),
      manifestBytes,
    );
  }
  return FramingOracleExportResult(
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
    required this.sourceParserFixtureSha256,
    required this.sourceQualificationInputSha256,
    required this.sourceGoldenSha256,
  });

  final Map<String, Object?> oracle;
  final int invocationCount;
  final String sourceParserFixtureSha256;
  final String sourceQualificationInputSha256;
  final String sourceGoldenSha256;
}

_BuiltOracle _buildOracle({
  required Directory repositoryRoot,
  required String scenarioId,
  required Map<String, Object?> capture,
  required Map<String, Object?> golden,
  required Set<String> allowedCanonicalTypes,
}) {
  final parserFile = File(
    '${repositoryRoot.path}${Platform.pathSeparator}'
    '${_text(capture['parserFixture'], 'parserFixture').replaceAll('/', Platform.pathSeparator)}',
  );
  final parserBytes = parserFile.readAsBytesSync();
  final parserSha = sha256.convert(parserBytes).toString();
  if (parserSha != capture['parserFixtureSha256']) {
    throw FormatException('parser_fixture_sha256_mismatch:$scenarioId');
  }
  final fixtureRoot = Directory(
    '${repositoryRoot.path}${Platform.pathSeparator}'
    'test${Platform.pathSeparator}fixtures',
  );
  final inputFile = File(
    '${fixtureRoot.path}${Platform.pathSeparator}'
    '${_text(golden['qualificationInput'], 'qualificationInput').replaceAll('/', Platform.pathSeparator)}',
  );
  final goldenFile = File(
    '${fixtureRoot.path}${Platform.pathSeparator}'
    '${_text(golden['dartReference'], 'dartReference').replaceAll('/', Platform.pathSeparator)}',
  );
  final fixtureJson = parserFile.readAsStringSync();
  final responses = const VisionParserFixtureReplay().decodeResponses(
    fixtureJson,
    allowedCanonicalTypes: allowedCanonicalTypes,
  );
  final binding = const VisionParserFixtureReplay().decodeBinding(fixtureJson);
  final trace = _FramingTrace();
  final analysis = const VisionV2ShadowOrchestrator().analyze(
    itemId: scenarioId,
    response: responses.first,
    additionalResponses: responses.skip(1),
    multiViewSubjectBinding: binding,
    framingAttestationTraceSink: trace,
  );
  if (trace.beforeCount != responses.length ||
      trace.afterCount != responses.length ||
      trace.invocations.length != responses.length) {
    throw FormatException('framing_invocation_count_invalid:$scenarioId');
  }
  final tracedOutputs = trace.invocations
      .map((item) => item.output)
      .toList(growable: false);
  final analysisOutputs = analysis.framingQualification
      .map((item) => item.toMap())
      .toList(growable: false);
  if (jsonEncode(tracedOutputs) != jsonEncode(analysisOutputs)) {
    throw FormatException('framing_trace_output_mismatch:$scenarioId');
  }
  final captureViews = _list(capture['views'], 'capture.views');
  if (captureViews.length != trace.invocations.length) {
    throw FormatException('framing_view_count_mismatch:$scenarioId');
  }
  final invocations = <Map<String, Object?>>[];
  for (var index = 0; index < trace.invocations.length; index++) {
    final invocation = trace.invocations[index];
    final view = _object(captureViews[index], 'capture.view');
    final input = invocation.input;
    final output = invocation.output;
    invocations.add({
      'viewIndex': index,
      'viewId': view['viewId'],
      'assetSha256': view['assetSha256'],
      'providerInput': input,
      'providerInputSha256': sha256.convert(_canonicalBytes(input)).toString(),
      'providerOutput': output,
      'providerOutputSha256': sha256
          .convert(_canonicalBytes(output))
          .toString(),
    });
  }
  final oracle = <String, Object?>{
    'oracleContractVersion': oracleContractVersion,
    'providerId': providerId,
    'providerVersion': providerVersion,
    'scenarioId': scenarioId,
    'sourceParserFixtureSha256': parserSha,
    'sourceQualificationInputSha256': sha256
        .convert(inputFile.readAsBytesSync())
        .toString(),
    'sourceDartReferenceGoldenSha256': sha256
        .convert(goldenFile.readAsBytesSync())
        .toString(),
    'invocations': invocations,
  };
  _assertOracle(oracle);
  return _BuiltOracle(
    oracle: oracle,
    invocationCount: invocations.length,
    sourceParserFixtureSha256: parserSha,
    sourceQualificationInputSha256:
        oracle['sourceQualificationInputSha256']! as String,
    sourceGoldenSha256: oracle['sourceDartReferenceGoldenSha256']! as String,
  );
}

final class _FramingInvocation {
  const _FramingInvocation({required this.input, required this.output});

  final Map<String, Object?> input;
  final Map<String, Object?> output;
}

final class _FramingTrace implements VisionFramingAttestationTraceSink {
  int beforeCount = 0;
  int afterCount = 0;
  final List<Map<String, Object?>> _pending = [];
  final List<_FramingInvocation> invocations = [];

  @override
  void beforeInvocation({
    required VisionInputAssessment inputAssessment,
    required VisionSubjectAssessment subject,
    required ObservationImageQuality quality,
    required VisionFramingAttestations? attestations,
  }) {
    beforeCount++;
    _pending.add(
      _inputMap(
        inputAssessment: inputAssessment,
        subject: subject,
        quality: quality,
        attestations: attestations,
      ),
    );
  }

  @override
  void afterInvocation({
    required VisionInputAssessment inputAssessment,
    required VisionSubjectAssessment subject,
    required ObservationImageQuality quality,
    required VisionFramingAttestations? attestations,
    required VisionFramingAttestationReport output,
  }) {
    afterCount++;
    final after = _inputMap(
      inputAssessment: inputAssessment,
      subject: subject,
      quality: quality,
      attestations: attestations,
    );
    final before = _pending[afterCount - 1];
    if (jsonEncode(before) != jsonEncode(after)) {
      throw const FormatException('framing_provider_input_changed');
    }
    invocations.add(_FramingInvocation(input: before, output: output.toMap()));
  }
}

Map<String, Object?> _inputMap({
  required VisionInputAssessment inputAssessment,
  required VisionSubjectAssessment subject,
  required ObservationImageQuality quality,
  required VisionFramingAttestations? attestations,
}) {
  final subjectMap = Map<String, Object?>.from(subject.toMap())
    ..remove('permitsFamily')
    ..remove('permitsCanonical');
  return {
    'inputAssessment': inputAssessment.wireName,
    'subject': subjectMap,
    'quality': quality.toMap(),
    'attestations': attestations?.toMap(),
  };
}

void _assertOracle(Map<String, Object?> oracle) {
  final invocations = _list(oracle['invocations'], 'invocations');
  if (oracle['oracleContractVersion'] != oracleContractVersion ||
      oracle['providerId'] != providerId ||
      oracle['providerVersion'] != providerVersion ||
      invocations.isEmpty) {
    throw const FormatException('framing_oracle_contract_invalid');
  }
  for (final raw in invocations) {
    final invocation = _object(raw, 'invocation');
    if (invocation['providerInput'] is! Map ||
        invocation['providerOutput'] is! Map) {
      throw const FormatException('framing_invocation_contract_invalid');
    }
  }
  final bytes = _canonicalBytes(oracle);
  if (!_sameBytes(bytes, _canonicalBytes(jsonDecode(utf8.decode(bytes))))) {
    throw const FormatException('framing_oracle_round_trip_failed');
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
