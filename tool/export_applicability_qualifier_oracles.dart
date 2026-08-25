import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_subject_safety.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

const applicabilityProviderId = 'VisionPropertyApplicabilityQualifier';
const applicabilityProviderVersion = 'applicability-v1';
const applicabilityOracleContractVersion = 1;
const applicabilityOracleManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_applicability_qualifier_oracle_manifest.json';

final class ApplicabilityOracleExportResult {
  const ApplicabilityOracleExportResult({
    required this.ready,
    required this.sourceMissing,
    required this.invocationCount,
    required this.manifestBytes,
  });

  final int ready;
  final int sourceMissing;
  final int invocationCount;
  final List<int> manifestBytes;
}

ApplicabilityOracleExportResult exportApplicabilityQualifierOracles({
  required Directory repositoryRoot,
  required bool write,
}) {
  final fixtureRoot = Directory(
    '${repositoryRoot.path}${Platform.pathSeparator}test'
    '${Platform.pathSeparator}fixtures',
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
  final captures = {
    for (final raw in _list(captureManifest['fixtures'], 'captures'))
      _text(_object(raw, 'capture')['id'], 'capture.id'): _object(
        raw,
        'capture',
      ),
  };
  final goldens = {
    for (final raw in _list(goldenManifest['fixtures'], 'goldens'))
      _text(_object(raw, 'golden')['id'], 'golden.id'): _object(raw, 'golden'),
  };
  final catalog = _readList(
    File(
      '${fixtureRoot.path}${Platform.pathSeparator}'
      '${_text(goldenManifest['sourceCatalog'], 'sourceCatalog')}',
    ),
  );
  final taxonomy = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}data${Platform.pathSeparator}'
    'clothing_knowledge_base.dart',
  ).readAsStringSync();
  final allowedCanonicalTypes = RegExp(
    r"canonicalType:\s*'([^']+)'",
  ).allMatches(taxonomy).map((match) => match.group(1)!).toSet();
  final entries = <Map<String, Object?>>[];
  final writes = <File, List<int>>{};
  var ready = 0;
  var missing = 0;
  var invocations = 0;

  for (final raw in catalog) {
    final id = _text(_object(raw, 'scenario')['id'], 'scenario.id');
    final capture = captures[id];
    final golden = goldens[id];
    if (capture == null ||
        capture['captureStatus'] != 'captured' ||
        golden == null ||
        golden['goldenStatus'] != 'ready') {
      missing++;
      entries.add({
        'scenarioId': id,
        'providerId': applicabilityProviderId,
        'status': 'source_missing',
        'reason': 'captured_source_not_ready',
        'contractVersion': applicabilityOracleContractVersion,
      });
      continue;
    }
    final built = _build(
      repositoryRoot: repositoryRoot,
      fixtureRoot: fixtureRoot,
      id: id,
      capture: capture,
      golden: golden,
      allowedCanonicalTypes: allowedCanonicalTypes,
    );
    final first = _canonicalBytes(built.oracle);
    final second = _canonicalBytes(
      _build(
        repositoryRoot: repositoryRoot,
        fixtureRoot: fixtureRoot,
        id: id,
        capture: capture,
        golden: golden,
        allowedCanonicalTypes: allowedCanonicalTypes,
      ).oracle,
    );
    if (!_sameBytes(first, second)) {
      throw FormatException('applicability_oracle_non_deterministic:$id');
    }
    final relative =
        'backend_qualification/provider_oracles/'
        'vision_applicability_v1/$id.oracle.json';
    writes[File(
          '${fixtureRoot.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        )] =
        first;
    entries.add({
      'scenarioId': id,
      'providerId': applicabilityProviderId,
      'status': 'ready',
      'oraclePath': relative,
      'oracleSha256': sha256.convert(first).toString(),
      'invocationCount': built.invocationCount,
      'sourceParserFixtureSha256': built.parserSha,
      'sourceQualificationInputSha256': built.inputSha,
      'sourceGoldenSha256': built.goldenSha,
      'contractVersion': applicabilityOracleContractVersion,
    });
    ready++;
    invocations += built.invocationCount;
  }
  final manifest = {
    'manifestVersion': 1,
    'oracleContractVersion': applicabilityOracleContractVersion,
    'providerId': applicabilityProviderId,
    'providerVersion': applicabilityProviderVersion,
    'fixtures': entries,
  };
  final manifestBytes = _canonicalBytes(manifest);
  if (write) {
    for (final entry in writes.entries) {
      _atomicWrite(entry.key, entry.value);
    }
    _atomicWrite(
      File(
        '${repositoryRoot.path}${Platform.pathSeparator}'
        '${applicabilityOracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
      ),
      manifestBytes,
    );
  }
  return ApplicabilityOracleExportResult(
    ready: ready,
    sourceMissing: missing,
    invocationCount: invocations,
    manifestBytes: List.unmodifiable(manifestBytes),
  );
}

final class _Built {
  const _Built({
    required this.oracle,
    required this.invocationCount,
    required this.parserSha,
    required this.inputSha,
    required this.goldenSha,
  });

  final Map<String, Object?> oracle;
  final int invocationCount;
  final String parserSha;
  final String inputSha;
  final String goldenSha;
}

_Built _build({
  required Directory repositoryRoot,
  required Directory fixtureRoot,
  required String id,
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
    throw FormatException('parser_fixture_sha_mismatch:$id');
  }
  final inputFile = File(
    '${fixtureRoot.path}${Platform.pathSeparator}'
    '${_text(golden['qualificationInput'], 'input').replaceAll('/', Platform.pathSeparator)}',
  );
  final goldenFile = File(
    '${fixtureRoot.path}${Platform.pathSeparator}'
    '${_text(golden['dartReference'], 'golden').replaceAll('/', Platform.pathSeparator)}',
  );
  final fixtureJson = parserFile.readAsStringSync();
  final responses = const VisionParserFixtureReplay().decodeResponses(
    fixtureJson,
    allowedCanonicalTypes: allowedCanonicalTypes,
  );
  final binding = const VisionParserFixtureReplay().decodeBinding(fixtureJson);
  final trace = _ApplicabilityTrace();
  final analysis = const VisionV2ShadowOrchestrator().analyze(
    itemId: id,
    response: responses.first,
    additionalResponses: responses.skip(1),
    multiViewSubjectBinding: binding,
    applicabilityTraceSink: trace,
  );
  if (trace.before != responses.length ||
      trace.after != responses.length ||
      trace.invocations.length != responses.length) {
    throw FormatException('applicability_invocation_count_invalid:$id');
  }
  final analysisOutputs = analysis.applicabilityQualification
      .map(_reportMap)
      .toList(growable: false);
  final traceOutputs = trace.invocations
      .map((item) => item['providerOutput'])
      .toList(growable: false);
  if (jsonEncode(analysisOutputs) != jsonEncode(traceOutputs)) {
    throw FormatException('applicability_trace_output_mismatch:$id');
  }
  final views = _list(capture['views'], 'views');
  final invocationMaps = <Map<String, Object?>>[];
  for (var index = 0; index < trace.invocations.length; index++) {
    final invocation = trace.invocations[index];
    final input = _object(invocation['providerInput'], 'providerInput');
    final output = _object(invocation['providerOutput'], 'providerOutput');
    final view = _object(views[index], 'view');
    invocationMaps.add({
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
    'oracleContractVersion': applicabilityOracleContractVersion,
    'providerId': applicabilityProviderId,
    'providerVersion': applicabilityProviderVersion,
    'scenarioId': id,
    'sourceParserFixtureSha256': parserSha,
    'sourceQualificationInputSha256': sha256
        .convert(inputFile.readAsBytesSync())
        .toString(),
    'sourceDartReferenceGoldenSha256': sha256
        .convert(goldenFile.readAsBytesSync())
        .toString(),
    'invocations': invocationMaps,
  };
  return _Built(
    oracle: oracle,
    invocationCount: invocationMaps.length,
    parserSha: parserSha,
    inputSha: oracle['sourceQualificationInputSha256']! as String,
    goldenSha: oracle['sourceDartReferenceGoldenSha256']! as String,
  );
}

final class _ApplicabilityTrace implements VisionApplicabilityTraceSink {
  int before = 0;
  int after = 0;
  final List<Map<String, Object?>> _inputs = [];
  final List<Map<String, Object?>> invocations = [];

  @override
  void beforeInvocation({
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
  }) {
    before++;
    _inputs.add(_inputMap(bundle, subject));
  }

  @override
  void afterInvocation({
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
    required VisionApplicabilityReport output,
  }) {
    after++;
    final current = _inputMap(bundle, subject);
    if (jsonEncode(current) != jsonEncode(_inputs[after - 1])) {
      throw const FormatException('applicability_input_changed');
    }
    invocations.add({
      'providerInput': current,
      'providerOutput': _reportMap(output),
    });
  }
}

Map<String, Object?> _inputMap(
  ClothingObservationBundle bundle,
  VisionSubjectAssessment subject,
) {
  final subjectMap = Map<String, Object?>.from(subject.toMap())
    ..remove('permitsFamily')
    ..remove('permitsCanonical');
  return {'bundle': bundle.toMap(), 'subject': subjectMap};
}

Map<String, Object?> _reportMap(VisionApplicabilityReport report) => {
  'qualifiedBundle': report.qualifiedBundle.toMap(),
  ...report.toMap(),
};

List<int> _canonicalBytes(Object? value) => utf8.encode(
  '${const JsonEncoder.withIndent('  ').convert(_canonicalize(value))}\n',
);

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalize(value[key])};
  }
  if (value is List) return value.map(_canonicalize).toList(growable: false);
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
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

Map<String, Object?> _readObject(File file) =>
    _object(jsonDecode(file.readAsStringSync()), file.path);

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) throw FormatException('$label:expected_object');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<Object?> _readList(File file) =>
    _list(jsonDecode(file.readAsStringSync()), file.path);

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
