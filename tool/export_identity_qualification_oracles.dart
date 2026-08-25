import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/canonical_observation_consistency_validator.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

const identityQualificationStageId = 'VisionIdentityQualification';
const identityQualificationStageVersion = 'vision-identity-qualification-v1';
const identityQualificationOracleVersion = 1;
const identityQualificationExporterVersion = 1;
const identityQualificationOracleManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_identity_qualification_oracle_manifest.json';

Map<String, Object?> exportIdentityQualificationOracles({
  required Directory repositoryRoot,
  required bool write,
}) {
  final fixtures = Directory(
    '${repositoryRoot.path}${Platform.pathSeparator}test'
    '${Platform.pathSeparator}fixtures',
  );
  final captures = _byId(
    _readObject(
      File(
        '${fixtures.path}${Platform.pathSeparator}'
        'backend_qualification_capture_manifest.json',
      ),
    )['fixtures'],
  );
  final goldens = _byId(
    _readObject(
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
  final providerSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}domain${Platform.pathSeparator}wardrobe_profile'
    '${Platform.pathSeparator}vision_v2_shadow_analysis.dart',
  );
  final callSiteSource = providerSource;
  final taxonomySource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}domain${Platform.pathSeparator}wardrobe_profile'
    '${Platform.pathSeparator}canonical_observation_consistency_validator.dart',
  );
  final serializerSources =
      [
        'lib/domain/wardrobe_profile/wardrobe_profile_contract.dart',
        'lib/domain/wardrobe_profile/canonical_observation_consistency_validator.dart',
        'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
      ].map(
        (path) => File(
          '${repositoryRoot.path}${Platform.pathSeparator}'
          '${path.replaceAll('/', Platform.pathSeparator)}',
        ),
      );
  final exporterSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}tool'
    '${Platform.pathSeparator}export_identity_qualification_oracles.dart',
  );
  final taxonomy = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}data${Platform.pathSeparator}'
    'clothing_knowledge_base.dart',
  ).readAsStringSync();
  final allowed = RegExp(
    r"canonicalType:\s*'([^']+)'",
  ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
  final bindings = <String, Object?>{
    'providerImplementationSha256': _shaFile(providerSource),
    'callSitePreparationSha256': _shaFile(callSiteSource),
    'serializerSha256': _combinedSha(serializerSources),
    'exporterImplementationSha256': _shaFile(exporterSource),
    'taxonomyRegistrySha256': _shaFile(taxonomySource),
    'upstreamBindings': <String, Object?>{
      'framingAttestor': 'framing-attestor-v1',
      'canonicalConsistency': 'canonical-consistency-v1',
      'observationEvidence': 'qualification-v1',
      'multiViewSubjectBindingContractVersion': 1,
      'identityMethodTag': 'safe_identity_v1',
    },
  };
  final entries = <Map<String, Object?>>[];
  final writes = <File, List<int>>{};
  final invocationIds = <String>{};
  var ready = 0;
  var sourceMissing = 0;
  var invocationCount = 0;
  var singleViewInvocations = 0;
  var multiViewInvocations = 0;
  var confirmed = 0;
  var supported = 0;
  var ambiguous = 0;
  var insufficient = 0;
  var conflicting = 0;
  var selectedCanonical = 0;
  var nullCanonical = 0;
  var totalCandidates = 0;
  var activeEvidence = 0;
  var omittedEvidence = 0;
  var framingBlocked = 0;
  var physicalIdentityBlocked = 0;
  var noCandidate = 0;

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
        'providerId': identityQualificationStageId,
        'status': 'source_missing',
        'reason': 'captured_source_not_ready',
        'oracleVersion': identityQualificationOracleVersion,
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
    final binding = const VisionParserFixtureReplay().decodeBinding(
      fixtureJson,
    );
    final baseline = const VisionV2ShadowOrchestrator().analyze(
      itemId: id,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
    );
    final trace = _IdentityTrace(id);
    final observed = const VisionV2ShadowOrchestrator().analyze(
      itemId: id,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      identityQualificationTraceSink: trace,
    );
    if (!_equalBytes(_bytes(baseline.toMap()), _bytes(observed.toMap()))) {
      throw FormatException('observer_changed_authoritative_behavior:$id');
    }
    if (trace.before != 1 || trace.after != 1 || trace.records.length != 1) {
      throw FormatException(
        'identity_qualification_invocation_count_invalid:$id',
      );
    }
    final record = trace.records.single;
    final invocationId = '$id::vision-identity-qualification';
    if (!invocationIds.add(invocationId)) {
      throw FormatException('duplicate_invocation_id:$invocationId');
    }
    final input = _object(record['providerInput']);
    final output = _object(record['providerOutput']);
    final report = _object(output['report']);
    final evidence = _list(output['qualifiedIdentityEvidence']);
    final state = report['state']! as String;
    switch (state) {
      case 'confirmed':
        confirmed++;
      case 'supported':
        supported++;
      case 'ambiguous':
        ambiguous++;
      case 'insufficient_evidence':
        insufficient++;
      case 'conflicting':
        conflicting++;
      default:
        throw FormatException('unknown_identity_state:$id:$state');
    }
    totalCandidates += _list(report['candidates']).length;
    if (report['selectedCanonicalType'] == null) {
      nullCanonical++;
    } else {
      selectedCanonical++;
    }
    for (final item in evidence) {
      final map = _object(item);
      if (map['active'] == true) {
        activeEvidence++;
      } else {
        omittedEvidence++;
      }
    }
    if (input['inputIsValid'] != true) {
      if (!observed.multiPhotoAssessment.permitsIdentityPromotion) {
        physicalIdentityBlocked++;
      } else {
        framingBlocked++;
      }
    }
    if (_list(input['identityEvidence']).isEmpty) noCandidate++;
    invocationCount++;
    if (responses.length == 1) {
      singleViewInvocations++;
    } else {
      multiViewInvocations++;
    }
    final inputFile = File(
      '${fixtures.path}${Platform.pathSeparator}'
      '${(golden!['qualificationInput']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final goldenFile = File(
      '${fixtures.path}${Platform.pathSeparator}'
      '${(golden['dartReference']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final oracle = <String, Object?>{
      'oracleVersion': identityQualificationOracleVersion,
      'exporterVersion': identityQualificationExporterVersion,
      'providerId': identityQualificationStageId,
      'providerVersion': identityQualificationStageVersion,
      'inputContract': 'vision_identity_qualification_input/v1',
      'outputContract': 'VisionIdentityQualificationResult/v1',
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
        'candidates': 'canonical_type_lexicographic',
        'qualifiedEvidence': 'evidence_id_lexicographic',
        'mapKeys': 'canonical_json_lexicographic',
        'declaredSupports': 'wire_name_lexicographic',
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
        'vision_identity_qualification_v1/$id.oracle.json';
    writes[File(
          '${fixtures.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        )] =
        bytes;
    entries.add({
      'scenarioId': id,
      'providerId': identityQualificationStageId,
      'status': 'ready',
      'oraclePath': relative,
      'oracleSha256': sha256.convert(bytes).toString(),
      'invocationCount': 1,
      'sourceParserFixtureSha256': parserSha,
      'oracleVersion': identityQualificationOracleVersion,
    });
    ready++;
  }

  final coverage = <String, Object?>{
    'singleViewInvocations': singleViewInvocations,
    'multiViewInvocations': multiViewInvocations,
    'totalCandidates': totalCandidates,
    'confirmedResults': confirmed,
    'supportedResults': supported,
    'ambiguousResults': ambiguous,
    'insufficientResults': insufficient,
    'conflictingResults': conflicting,
    'selectedCanonicalCount': selectedCanonical,
    'nullCanonicalCount': nullCanonical,
    'activeIdentityEvidenceCount': activeEvidence,
    'omittedIdentityEvidenceCount': omittedEvidence,
    'framingBlockedResults': framingBlocked,
    'physicalIdentityBlockedResults': physicalIdentityBlocked,
    'noCandidateResults': noCandidate,
    'semanticConflictBlockedResults': conflicting,
    'taxonomyConflictResults': 0,
  };
  final manifest = <String, Object?>{
    'manifestVersion': 1,
    'oracleVersion': identityQualificationOracleVersion,
    'exporterVersion': identityQualificationExporterVersion,
    'providerId': identityQualificationStageId,
    'providerVersion': identityQualificationStageVersion,
    'scenarioCount': catalog.length,
    'readyScenarioCount': ready,
    'sourceMissingScenarioCount': sourceMissing,
    'invocationCount': invocationCount,
    ...bindings,
    'generationCommand':
        'flutter test --dart-define=UPDATE_IDENTITY_QUALIFICATION_ORACLES=true '
        'test/backend_identity_qualification_oracle_export_test.dart',
    'orderingPolicy': <String, Object?>{
      'scenario': 'vision_v2_adversarial_scenarios_manifest_order',
      'invocation': 'single_scenario_invocation',
      'candidates': 'canonical_type_lexicographic',
      'qualifiedEvidence': 'evidence_id_lexicographic',
      'mapKeys': 'canonical_json_lexicographic',
      'declaredSupports': 'wire_name_lexicographic',
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
        '${identityQualificationOracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
      ),
      manifestBytes,
    );
  }
  return <String, Object?>{
    'ready': ready,
    'sourceMissing': sourceMissing,
    'invocationCount': invocationCount,
    'singleViewInvocations': singleViewInvocations,
    'multiViewInvocations': multiViewInvocations,
    'manifestBytes': manifestBytes,
    'oracleBytesByPath': {
      for (final item in writes.entries) item.key.path: item.value,
    },
    'coverage': coverage,
    ...bindings,
  };
}

final class _IdentityTrace implements VisionIdentityQualificationTraceSink {
  _IdentityTrace(this.scenarioId);

  final String scenarioId;
  int before = 0;
  int after = 0;
  Map<String, Object?>? _input;
  final List<Map<String, Object?>> records = [];

  @override
  void beforeInvocation({
    required List<ProfileEvidence> identityEvidence,
    required CanonicalConsistencyReport consistency,
    required Map<String, ({List<String> defining, List<String> supporting})>
    declaredByEvidenceId,
    required bool inputIsValid,
  }) {
    before++;
    _input = _providerInput(
      identityEvidence,
      consistency,
      declaredByEvidenceId,
      inputIsValid,
    );
  }

  @override
  void afterInvocation({
    required List<ProfileEvidence> identityEvidence,
    required CanonicalConsistencyReport consistency,
    required Map<String, ({List<String> defining, List<String> supporting})>
    declaredByEvidenceId,
    required bool inputIsValid,
    required List<ProfileEvidence> qualifiedIdentityEvidence,
    required VisionIdentityQualificationReport report,
  }) {
    final current = _providerInput(
      identityEvidence,
      consistency,
      declaredByEvidenceId,
      inputIsValid,
    );
    if (_input == null || !_equalBytes(_bytes(current), _bytes(_input!))) {
      throw FormatException('identity_input_changed:$scenarioId');
    }
    after++;
    records.add({
      'providerInput': current,
      'providerOutput': {
        'qualifiedIdentityEvidence': qualifiedIdentityEvidence
            .map((item) => item.toMap())
            .toList(),
        'report': report.toMap(),
      },
    });
  }
}

Map<String, Object?> _providerInput(
  List<ProfileEvidence> identityEvidence,
  CanonicalConsistencyReport consistency,
  Map<String, ({List<String> defining, List<String> supporting})>
  declaredByEvidenceId,
  bool inputIsValid,
) {
  final declaredKeys = declaredByEvidenceId.keys.toList()..sort();
  return <String, Object?>{
    'identityEvidence': identityEvidence.map((item) => item.toMap()).toList(),
    'consistency': consistency.toMap(),
    'declaredByEvidenceId': {
      for (final key in declaredKeys)
        key: <String, Object?>{
          'defining': declaredByEvidenceId[key]!.defining,
          'supporting': declaredByEvidenceId[key]!.supporting,
        },
    },
    'inputIsValid': inputIsValid,
  };
}

Map<String, Map<String, Object?>> _byId(Object? value) => {
  for (final raw in _list(value)) _object(raw)['id']! as String: _object(raw),
};
Map<String, Object?> _readObject(File file) =>
    _object(jsonDecode(file.readAsStringSync()));
Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('expected_object');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('expected_list');
  return List<Object?>.from(value);
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

bool _equalBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _write(File file, List<int> bytes) {
  file.parent.createSync(recursive: true);
  final temporary = File('${file.path}.tmp');
  temporary.writeAsBytesSync(bytes, flush: true);
  temporary.renameSync(file.path);
}
