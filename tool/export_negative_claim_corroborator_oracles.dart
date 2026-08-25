import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_framing_attestation.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_subject_safety.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

const negativeClaimProviderId = 'VisionNegativeClaimCorroborator';
const negativeClaimProviderVersion = 'negative-claim-corroborator-v1';
const negativeClaimOracleVersion = 1;
const negativeClaimExporterVersion = 1;
const negativeClaimOracleManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_negative_claim_corroborator_oracle_manifest.json';

Map<String, Object?> exportNegativeClaimCorroboratorOracles({
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
    '${Platform.pathSeparator}vision_framing_attestation.dart',
  );
  final callSiteSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}domain${Platform.pathSeparator}wardrobe_profile'
    '${Platform.pathSeparator}vision_v2_shadow_analysis.dart',
  );
  final serializerSources =
      [
        'lib/domain/wardrobe_profile/wardrobe_observation_contract.dart',
        'lib/domain/wardrobe_profile/vision_subject_safety.dart',
        'lib/domain/wardrobe_profile/vision_framing_attestation.dart',
      ].map(
        (path) => File(
          '${repositoryRoot.path}${Platform.pathSeparator}'
          '${path.replaceAll('/', Platform.pathSeparator)}',
        ),
      );
  final exporterSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}tool'
    '${Platform.pathSeparator}export_negative_claim_corroborator_oracles.dart',
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
  };
  final entries = <Map<String, Object?>>[];
  final writes = <File, List<int>>{};
  final invocationIds = <String>{};
  var ready = 0;
  var sourceMissing = 0;
  var invocationCount = 0;
  var singleViewInvocations = 0;
  var multiViewInvocations = 0;
  var negativeClaims = 0;
  var complementaryClaims = 0;
  var conflictingPositiveClaims = 0;
  var sameItemInvocations = 0;
  var unusableInputs = 0;
  var changedOutputs = 0;
  var unchangedOutputs = 0;
  var unknownOutputs = 0;
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
        'providerId': negativeClaimProviderId,
        'status': 'source_missing',
        'reason': 'captured_source_not_ready',
        'oracleVersion': negativeClaimOracleVersion,
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
    final trace = _NegativeClaimTrace(id);
    final observed = const VisionV2ShadowOrchestrator().analyze(
      itemId: id,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      negativeClaimCorroborationTraceSink: trace,
    );
    if (!_equalBytes(_bytes(baseline.toMap()), _bytes(observed.toMap()))) {
      throw FormatException('observer_changed_authoritative_behavior:$id');
    }
    if (trace.before != responses.length ||
        trace.after != responses.length ||
        trace.records.length != responses.length) {
      throw FormatException('negative_claim_invocation_count_invalid:$id');
    }
    final views = _list(capture['views']);
    final invocations = <Map<String, Object?>>[];
    for (var index = 0; index < trace.records.length; index++) {
      final record = trace.records[index];
      final view = _object(views[index]);
      final invocationId =
          '$id::view-$index::vision-negative-claim-corroborator';
      if (!invocationIds.add(invocationId)) {
        throw FormatException('duplicate_invocation_id:$invocationId');
      }
      final input = _object(record['providerInput']);
      final output = _object(record['providerOutput']);
      invocations.add({
        'invocationId': invocationId,
        'viewIndex': index,
        'viewId': view['viewId'],
        'assetSha256': view['assetSha256'],
        'providerInput': input,
        'providerInputSha256': sha256.convert(_bytes(input)).toString(),
        'providerOutput': output,
        'providerOutputSha256': sha256.convert(_bytes(output)).toString(),
      });
      invocationCount++;
      if (responses.length == 1) {
        singleViewInvocations++;
      } else {
        multiViewInvocations++;
      }
      if (input['sameItemViews'] == true) sameItemInvocations++;
      final complementary = _object(input['complementaryRegions']);
      final conflicts = _list(input['conflictingPositiveProperties']);
      if (complementary.isNotEmpty) complementaryClaims++;
      if (conflicts.isNotEmpty) conflictingPositiveClaims++;
      final claims = _object(output['claims']);
      negativeClaims += claims.length;
      for (final claim in claims.values) {
        final audit = _object(claim);
        final state = audit['corroborationState'];
        if (state == 'blocked' || state == 'notApplicable') unusableInputs++;
        if (state == 'corroborated') {
          unchangedOutputs++;
        } else {
          changedOutputs++;
        }
      }
      final qualifiedBundle = _object(output['qualifiedBundle']);
      unknownOutputs += qualifiedBundle.values.where((value) {
        return value is Map && value['state'] == 'unknown';
      }).length;
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
      'oracleVersion': negativeClaimOracleVersion,
      'exporterVersion': negativeClaimExporterVersion,
      'providerId': negativeClaimProviderId,
      'providerVersion': negativeClaimProviderVersion,
      'inputContract': 'negative_claim_corroborator_input/v1',
      'outputContract': 'NegativeClaimCorroborationReport/v1',
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
        'invocation': 'view_index_ascending',
        'mapKeys': 'canonical_json_lexicographic',
        'sets': 'wire_name_lexicographic',
      },
      'invocations': invocations,
    };
    final bytes = _bytes(oracle);
    final relative =
        'backend_qualification/provider_oracles/'
        'vision_negative_claim_corroborator_v1/$id.oracle.json';
    writes[File(
          '${fixtures.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        )] =
        bytes;
    entries.add({
      'scenarioId': id,
      'providerId': negativeClaimProviderId,
      'status': 'ready',
      'oraclePath': relative,
      'oracleSha256': sha256.convert(bytes).toString(),
      'invocationCount': invocations.length,
      'sourceParserFixtureSha256': parserSha,
      'oracleVersion': negativeClaimOracleVersion,
    });
    ready++;
  }
  final coverage = <String, Object?>{
    'singleViewInvocations': singleViewInvocations,
    'multiViewInvocations': multiViewInvocations,
    'negativeClaims': negativeClaims,
    'absenceRelevantClaims': negativeClaims,
    'claimsWithComplementaryRegions': complementaryClaims,
    'claimsWithConflictingPositives': conflictingPositiveClaims,
    'sameItemCorroborationInvocations': sameItemInvocations,
    'unusableVisibilityInputs': unusableInputs,
    'changedOutputs': changedOutputs,
    'unchangedOutputs': unchangedOutputs,
    'unknownOutputs': unknownOutputs,
  };
  final manifest = <String, Object?>{
    'manifestVersion': 1,
    'oracleVersion': negativeClaimOracleVersion,
    'exporterVersion': negativeClaimExporterVersion,
    'providerId': negativeClaimProviderId,
    'providerVersion': negativeClaimProviderVersion,
    'scenarioCount': catalog.length,
    'readyScenarioCount': ready,
    'sourceMissingScenarioCount': sourceMissing,
    'invocationCount': invocationCount,
    ...bindings,
    'generationCommand':
        'flutter test --dart-define=UPDATE_NEGATIVE_CLAIM_ORACLES=true '
        'test/backend_negative_claim_corroborator_oracle_export_test.dart',
    'orderingPolicy': <String, Object?>{
      'scenario': 'vision_v2_adversarial_scenarios_manifest_order',
      'invocation': 'view_index_ascending',
      'mapKeys': 'canonical_json_lexicographic',
      'sets': 'wire_name_lexicographic',
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
        '${negativeClaimOracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
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

final class _NegativeClaimTrace
    implements VisionNegativeClaimCorroborationTraceSink {
  _NegativeClaimTrace(this.scenarioId);

  final String scenarioId;
  int before = 0;
  int after = 0;
  final List<Map<String, Object?>> _inputs = [];
  final List<Map<String, Object?>> records = [];

  @override
  void beforeInvocation({
    required int viewIndex,
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
    required VisionFramingAttestationReport framing,
    required int viewCount,
    required bool sameItemViews,
    required Map<String, Set<ObservationVisualRegion>> complementaryRegions,
    required Set<String> conflictingPositiveProperties,
  }) {
    if (viewIndex != before) {
      throw FormatException('view_order_invalid:$scenarioId:$viewIndex');
    }
    before++;
    _inputs.add(
      _input(
        bundle,
        subject,
        framing,
        viewCount,
        sameItemViews,
        complementaryRegions,
        conflictingPositiveProperties,
      ),
    );
  }

  @override
  void afterInvocation({
    required int viewIndex,
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
    required VisionFramingAttestationReport framing,
    required int viewCount,
    required bool sameItemViews,
    required Map<String, Set<ObservationVisualRegion>> complementaryRegions,
    required Set<String> conflictingPositiveProperties,
    required NegativeClaimCorroborationReport output,
  }) {
    if (viewIndex != after) {
      throw FormatException('view_order_invalid:$scenarioId:$viewIndex');
    }
    final current = _input(
      bundle,
      subject,
      framing,
      viewCount,
      sameItemViews,
      complementaryRegions,
      conflictingPositiveProperties,
    );
    if (!_equalBytes(_bytes(current), _bytes(_inputs[after]))) {
      throw FormatException('negative_claim_input_changed:$scenarioId');
    }
    after++;
    records.add({
      'providerInput': current,
      'providerOutput': {
        'qualifiedBundle': output.qualifiedBundle.toMap(),
        ...output.toMap(),
      },
    });
  }
}

Map<String, Object?> _input(
  ClothingObservationBundle bundle,
  VisionSubjectAssessment subject,
  VisionFramingAttestationReport framing,
  int viewCount,
  bool sameItemViews,
  Map<String, Set<ObservationVisualRegion>> complementaryRegions,
  Set<String> conflictingPositiveProperties,
) => <String, Object?>{
  'bundle': bundle.toMap(),
  'subject': subject.toMap(),
  'framing': framing.toMap(),
  'viewCount': viewCount,
  'sameItemViews': sameItemViews,
  'complementaryRegions': {
    for (final entry in complementaryRegions.entries)
      entry.key: entry.value.map((item) => item.wireName).toList()..sort(),
  },
  'conflictingPositiveProperties': conflictingPositiveProperties.toList()
    ..sort(),
};

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
