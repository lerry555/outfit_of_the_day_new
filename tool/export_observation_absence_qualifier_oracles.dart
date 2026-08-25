import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/observation_absence_qualifier.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

const observationAbsenceProviderId = 'ObservationAbsenceQualifier';
const observationAbsenceProviderVersion = 'observation-absence-qualifier-v1';
const observationAbsenceOracleVersion = 1;
const observationAbsenceExporterVersion = 1;
const observationAbsenceOracleManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_observation_absence_qualifier_oracle_manifest.json';

const _absenceProperties = <String>[
  'visiblePocketStructure',
  'hasHood',
  'frontClosure',
  'visibleStretchCue',
];

Map<String, Object?> exportObservationAbsenceQualifierOracles({
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
    '${Platform.pathSeparator}observation_absence_qualifier.dart',
  );
  final callSiteSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}domain${Platform.pathSeparator}wardrobe_profile'
    '${Platform.pathSeparator}vision_v2_shadow_analysis.dart',
  );
  final serializerSources =
      [
        'lib/domain/wardrobe_profile/wardrobe_observation_contract.dart',
        'lib/domain/wardrobe_profile/observation_absence_qualifier.dart',
      ].map(
        (path) => File(
          '${repositoryRoot.path}${Platform.pathSeparator}'
          '${path.replaceAll('/', Platform.pathSeparator)}',
        ),
      );
  final exporterSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}tool'
    '${Platform.pathSeparator}export_observation_absence_qualifier_oracles.dart',
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
  var inputNegativeClaims = 0;
  var corroboratedClaims = 0;
  var unresolvedRejectedClaims = 0;
  var mergedAbsences = 0;
  var outputUnknown = 0;
  var outputNotVisible = 0;
  var outputNotApplicable = 0;
  var unchangedObservations = 0;
  var changedObservations = 0;
  var multiViewMerges = 0;
  var conflictingPositiveCases = 0;

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
        'providerId': observationAbsenceProviderId,
        'status': 'source_missing',
        'reason': 'captured_source_not_ready',
        'oracleVersion': observationAbsenceOracleVersion,
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
    final trace = _AbsenceTrace(id);
    final observed = const VisionV2ShadowOrchestrator().analyze(
      itemId: id,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      observationAbsenceQualificationTraceSink: trace,
    );
    if (!_equalBytes(_bytes(baseline.toMap()), _bytes(observed.toMap()))) {
      throw FormatException('observer_changed_authoritative_behavior:$id');
    }
    if (trace.before != 1 || trace.after != 1 || trace.records.length != 1) {
      throw FormatException('absence_qualifier_invocation_count_invalid:$id');
    }
    final views = _list(capture['views']);
    final record = trace.records.single;
    final invocationId = '$id::observation-absence-qualifier';
    if (!invocationIds.add(invocationId)) {
      throw FormatException('duplicate_invocation_id:$invocationId');
    }
    final input = _object(record['providerInput']);
    final output = _object(record['providerOutput']);
    final bundles = _list(input['bundles']);
    if (bundles.length != responses.length) {
      throw FormatException('absence_bundle_count_invalid:$id');
    }
    final orderedViewIds = <String>[
      for (final view in views) _object(view)['viewId']! as String,
    ];
    final invocation = <String, Object?>{
      'invocationId': invocationId,
      'viewCount': responses.length,
      'orderedViewIds': orderedViewIds,
      'orderedViewProvenance': [
        for (final view in views)
          <String, Object?>{
            'viewId': _object(view)['viewId'],
            'assetSha256': _object(view)['assetSha256'],
          },
      ],
      'providerInput': input,
      'providerInputSha256': sha256.convert(_bytes(input)).toString(),
      'providerOutput': output,
      'providerOutputSha256': sha256.convert(_bytes(output)).toString(),
    };
    invocationCount++;
    if (responses.length == 1) {
      singleViewInvocations++;
    } else {
      multiViewInvocations++;
      multiViewMerges++;
    }

    final coverageDelta = _coverageFromInvocation(
      inputBundles: bundles,
      output: output,
    );
    inputNegativeClaims += coverageDelta.inputNegativeClaims;
    corroboratedClaims += coverageDelta.corroboratedClaims;
    unresolvedRejectedClaims += coverageDelta.unresolvedRejectedClaims;
    mergedAbsences += coverageDelta.mergedAbsences;
    outputUnknown += coverageDelta.outputUnknown;
    outputNotVisible += coverageDelta.outputNotVisible;
    outputNotApplicable += coverageDelta.outputNotApplicable;
    unchangedObservations += coverageDelta.unchangedObservations;
    changedObservations += coverageDelta.changedObservations;
    conflictingPositiveCases += coverageDelta.conflictingPositiveCases;

    final inputFile = File(
      '${fixtures.path}${Platform.pathSeparator}'
      '${(golden!['qualificationInput']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final goldenFile = File(
      '${fixtures.path}${Platform.pathSeparator}'
      '${(golden['dartReference']! as String).replaceAll('/', Platform.pathSeparator)}',
    );
    final oracle = <String, Object?>{
      'oracleVersion': observationAbsenceOracleVersion,
      'exporterVersion': observationAbsenceExporterVersion,
      'providerId': observationAbsenceProviderId,
      'providerVersion': observationAbsenceProviderVersion,
      'inputContract': 'observation_absence_qualifier_input/v1',
      'outputContract': 'ObservationAbsenceQualificationReport/v1',
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
        'bundles': 'view_index_ascending',
        'mapKeys': 'canonical_json_lexicographic',
        'qualifiedObservations':
            'visiblePocketStructure_hasHood_frontClosure_visibleStretchCue',
      },
      'invocations': [invocation],
    };
    final bytes = _bytes(oracle);
    final relative =
        'backend_qualification/provider_oracles/'
        'observation_absence_qualifier_v1/$id.oracle.json';
    writes[File(
          '${fixtures.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        )] =
        bytes;
    entries.add({
      'scenarioId': id,
      'providerId': observationAbsenceProviderId,
      'status': 'ready',
      'oraclePath': relative,
      'oracleSha256': sha256.convert(bytes).toString(),
      'invocationCount': 1,
      'sourceParserFixtureSha256': parserSha,
      'oracleVersion': observationAbsenceOracleVersion,
    });
    ready++;
  }

  final coverage = <String, Object?>{
    'singleViewInvocations': singleViewInvocations,
    'multiViewInvocations': multiViewInvocations,
    'inputNegativeClaims': inputNegativeClaims,
    'corroboratedClaims': corroboratedClaims,
    'unresolvedRejectedClaims': unresolvedRejectedClaims,
    'mergedAbsences': mergedAbsences,
    'outputUnknown': outputUnknown,
    'outputNotVisible': outputNotVisible,
    'outputNotApplicable': outputNotApplicable,
    'unchangedObservations': unchangedObservations,
    'changedObservations': changedObservations,
    'multiViewMerges': multiViewMerges,
    'conflictingPositiveCases': conflictingPositiveCases,
  };
  final manifest = <String, Object?>{
    'manifestVersion': 1,
    'oracleVersion': observationAbsenceOracleVersion,
    'exporterVersion': observationAbsenceExporterVersion,
    'providerId': observationAbsenceProviderId,
    'providerVersion': observationAbsenceProviderVersion,
    'scenarioCount': catalog.length,
    'readyScenarioCount': ready,
    'sourceMissingScenarioCount': sourceMissing,
    'invocationCount': invocationCount,
    ...bindings,
    'generationCommand':
        'flutter test --dart-define=UPDATE_OBSERVATION_ABSENCE_ORACLES=true '
        'test/backend_observation_absence_qualifier_oracle_export_test.dart',
    'orderingPolicy': <String, Object?>{
      'scenario': 'vision_v2_adversarial_scenarios_manifest_order',
      'invocation': 'single_scenario_invocation',
      'bundles': 'view_index_ascending',
      'mapKeys': 'canonical_json_lexicographic',
      'qualifiedObservations':
          'visiblePocketStructure_hasHood_frontClosure_visibleStretchCue',
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
        '${observationAbsenceOracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
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

class _CoverageDelta {
  const _CoverageDelta({
    required this.inputNegativeClaims,
    required this.corroboratedClaims,
    required this.unresolvedRejectedClaims,
    required this.mergedAbsences,
    required this.outputUnknown,
    required this.outputNotVisible,
    required this.outputNotApplicable,
    required this.unchangedObservations,
    required this.changedObservations,
    required this.conflictingPositiveCases,
  });

  final int inputNegativeClaims;
  final int corroboratedClaims;
  final int unresolvedRejectedClaims;
  final int mergedAbsences;
  final int outputUnknown;
  final int outputNotVisible;
  final int outputNotApplicable;
  final int unchangedObservations;
  final int changedObservations;
  final int conflictingPositiveCases;
}

_CoverageDelta _coverageFromInvocation({
  required List<Object?> inputBundles,
  required Map<String, Object?> output,
}) {
  var inputNegativeClaims = 0;
  for (final rawBundle in inputBundles) {
    final bundle = _object(rawBundle);
    for (final property in _absenceProperties) {
      final observation = bundle[property];
      if (observation is! Map) continue;
      if (observation['state'] != 'observed') continue;
      final value = observation['value'];
      final isNegative = switch (property) {
        'hasHood' || 'visibleStretchCue' => value == false,
        'frontClosure' || 'visiblePocketStructure' => value == 'none',
        _ => false,
      };
      if (isNegative) inputNegativeClaims++;
    }
  }

  var corroboratedClaims = 0;
  var unresolvedRejectedClaims = 0;
  var mergedAbsences = 0;
  var outputUnknown = 0;
  var outputNotVisible = 0;
  var outputNotApplicable = 0;
  var unchangedObservations = 0;
  var changedObservations = 0;
  var conflictingPositiveCases = 0;

  for (final property in _absenceProperties) {
    final audit = _object(output[property]);
    final disposition = audit['disposition']! as String;
    final reasons = _list(audit['reasonCodes']).map((item) => '$item').toList();
    final qualified = _object(audit['qualified']);
    switch (qualified['state']) {
      case 'unknown':
        outputUnknown++;
      case 'not_visible':
        outputNotVisible++;
      case 'not_applicable':
        outputNotApplicable++;
    }
    if (disposition == 'unchanged') {
      unchangedObservations++;
    } else {
      changedObservations++;
    }
    if (disposition == 'qualified' &&
        (reasons.contains('complete_visibility_confirms_absence') ||
            reasons.contains('multiple_sufficient_views_confirm_absence'))) {
      corroboratedClaims++;
      mergedAbsences++;
    }
    if (disposition == 'conflict' ||
        reasons.contains('positive_existence_overrides_negative') ||
        reasons.contains('conflicting_positive_observations')) {
      conflictingPositiveCases++;
    }
    if (disposition == 'degradedToUnknown' ||
        disposition == 'degradedToNotVisible' ||
        disposition == 'conflict' ||
        reasons.contains('insufficient_visibility_for_absence') ||
        reasons.contains('absence_not_visually_provable') ||
        reasons.contains('no_observed_absence_evidence')) {
      unresolvedRejectedClaims++;
    }
  }

  return _CoverageDelta(
    inputNegativeClaims: inputNegativeClaims,
    corroboratedClaims: corroboratedClaims,
    unresolvedRejectedClaims: unresolvedRejectedClaims,
    mergedAbsences: mergedAbsences,
    outputUnknown: outputUnknown,
    outputNotVisible: outputNotVisible,
    outputNotApplicable: outputNotApplicable,
    unchangedObservations: unchangedObservations,
    changedObservations: changedObservations,
    conflictingPositiveCases: conflictingPositiveCases,
  );
}

final class _AbsenceTrace implements ObservationAbsenceQualificationTraceSink {
  _AbsenceTrace(this.scenarioId);

  final String scenarioId;
  int before = 0;
  int after = 0;
  Map<String, Object?>? _input;
  final List<Map<String, Object?>> records = [];

  @override
  void beforeInvocation({required List<ClothingObservationBundle> bundles}) {
    before++;
    _input = _providerInput(bundles);
  }

  @override
  void afterInvocation({
    required List<ClothingObservationBundle> bundles,
    required ObservationAbsenceQualificationReport output,
  }) {
    final current = _providerInput(bundles);
    if (_input == null || !_equalBytes(_bytes(current), _bytes(_input!))) {
      throw FormatException('absence_input_changed:$scenarioId');
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

Map<String, Object?> _providerInput(List<ClothingObservationBundle> bundles) =>
    <String, Object?>{
      'bundles': [for (final bundle in bundles) bundle.toMap()],
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
