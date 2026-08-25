import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_family_identity.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_subject_safety.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_visibility_trust.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

const familyIdentityProviderId = 'VisionFamilyIdentityResolver';
const familyIdentityProviderVersion = 'vision-family-identity-resolver-v1';
const familyIdentityOracleVersion = 1;
const familyIdentityExporterVersion = 1;
const familyIdentityOracleManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_family_identity_oracle_manifest.json';

Map<String, Object?> exportFamilyIdentityOracles({
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
    '${Platform.pathSeparator}vision_family_identity.dart',
  );
  final callSiteSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}domain${Platform.pathSeparator}wardrobe_profile'
    '${Platform.pathSeparator}vision_v2_shadow_analysis.dart',
  );
  final taxonomySource = providerSource;
  final serializerSources =
      [
        'lib/domain/wardrobe_profile/vision_family_identity.dart',
        'lib/domain/wardrobe_profile/wardrobe_observation_contract.dart',
        'lib/domain/wardrobe_profile/vision_subject_safety.dart',
        'lib/domain/wardrobe_profile/vision_visibility_trust.dart',
      ].map(
        (path) => File(
          '${repositoryRoot.path}${Platform.pathSeparator}'
          '${path.replaceAll('/', Platform.pathSeparator)}',
        ),
      );
  final exporterSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}tool'
    '${Platform.pathSeparator}export_family_identity_oracles.dart',
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
      'identityQualification': 'vision-identity-qualification-v1',
      'multiViewSubjectBindingContractVersion': 1,
      'familyRegistry': 'vision-canonical-family-registry-v1',
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
  var invalid = 0;
  var conflicting = 0;
  var selectedFamily = 0;
  var nullFamily = 0;
  var framingBlocked = 0;
  var noBroadSilhouette = 0;
  var noCandidate = 0;
  var taxonomyConflict = 0;
  var familyOnly = 0;
  var canonicalPlusFamily = 0;
  var familyWithoutCanonical = 0;
  var multiViewConflict = 0;

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
        'providerId': familyIdentityProviderId,
        'status': 'source_missing',
        'reason': 'captured_source_not_ready',
        'oracleVersion': familyIdentityOracleVersion,
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
    final observed = _FamilyTrace(id);
    final withSink = const VisionV2ShadowOrchestrator().analyze(
      itemId: id,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      familyIdentityTraceSink: observed,
    );
    if (!_equalBytes(_bytes(baseline.toMap()), _bytes(withSink.toMap()))) {
      throw FormatException('observer_changed_authoritative_behavior:$id');
    }
    if (observed.before != 1 ||
        observed.after != 1 ||
        observed.records.length != 1) {
      throw FormatException('family_invocation_count_invalid:$id');
    }
    final invocationId = '$id::vision-family-identity-resolver';
    if (!invocationIds.add(invocationId)) {
      throw FormatException('duplicate_family_invocation_id:$invocationId');
    }
    final record = observed.records.single;
    final input = _object(record['providerInput']);
    final output = _object(record['providerOutput']);
    final report = _object(output);
    switch (report['state']) {
      case 'confirmed':
        confirmed++;
      case 'supported':
        supported++;
      case 'ambiguous':
        ambiguous++;
      case 'insufficient_evidence':
        insufficient++;
      case 'invalid_input':
        invalid++;
      case 'conflicting':
        conflicting++;
    }
    if (report['resolvedFamily'] == null) {
      nullFamily++;
    } else {
      selectedFamily++;
    }
    final reasons = _list(report['reasonCodes']).map((item) => '$item').toSet();
    if (reasons.contains('subject_or_framing_rejects_family') ||
        reasons.contains('input_assessment_rejects_family')) {
      framingBlocked++;
    }
    if (reasons.contains('whole_item_silhouette_required_for_family')) {
      noBroadSilhouette++;
    }
    if (reasons.contains('no_mapped_family_candidate')) noCandidate++;
    if (reasons.contains('competing_families')) taxonomyConflict++;
    if (report['resolvedFamily'] != null && report['subtypeResolved'] != true) {
      familyOnly++;
      familyWithoutCanonical++;
    }
    if (report['resolvedFamily'] != null && report['subtypeResolved'] == true) {
      canonicalPlusFamily++;
    }
    if (responses.length > 1 &&
        !withSink.multiPhotoAssessment.permitsIdentityPromotion) {
      multiViewConflict++;
    }
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
      'oracleVersion': familyIdentityOracleVersion,
      'exporterVersion': familyIdentityExporterVersion,
      'providerId': familyIdentityProviderId,
      'providerVersion': familyIdentityProviderVersion,
      'inputContract': 'vision_family_identity_input/v1',
      'outputContract': 'VisionFamilyIdentityReport/v1',
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
        'familyCandidates': 'confidence_desc_then_family_wire_lexicographic',
        'subtypeCandidates': 'canonical_type_lexicographic',
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
        'vision_family_identity_resolver_v1/$id.oracle.json';
    writes[File(
          '${fixtures.path}${Platform.pathSeparator}'
          '${relative.replaceAll('/', Platform.pathSeparator)}',
        )] =
        bytes;
    entries.add({
      'scenarioId': id,
      'providerId': familyIdentityProviderId,
      'status': 'ready',
      'oraclePath': relative,
      'oracleSha256': sha256.convert(bytes).toString(),
      'invocationCount': 1,
      'sourceParserFixtureSha256': parserSha,
      'oracleVersion': familyIdentityOracleVersion,
    });
    ready++;
  }

  final coverage = <String, Object?>{
    'singleViewInvocations': singleViewInvocations,
    'multiViewInvocations': multiViewInvocations,
    'confirmedResults': confirmed,
    'supportedResults': supported,
    'ambiguousResults': ambiguous,
    'insufficientResults': insufficient,
    'invalidResults': invalid,
    'conflictingResults': conflicting,
    'selectedFamilyCount': selectedFamily,
    'nullFamilyCount': nullFamily,
    'framingBlockedResults': framingBlocked,
    'noBroadSilhouetteResults': noBroadSilhouette,
    'noCandidateResults': noCandidate,
    'taxonomyConflictResults': taxonomyConflict,
    'familyOnlyResults': familyOnly,
    'canonicalPlusFamilyResults': canonicalPlusFamily,
    'familyResolvedCanonicalUnresolvedResults': familyWithoutCanonical,
    'multiViewConflictResults': multiViewConflict,
  };
  final manifest = <String, Object?>{
    'manifestVersion': 1,
    'oracleVersion': familyIdentityOracleVersion,
    'exporterVersion': familyIdentityExporterVersion,
    'providerId': familyIdentityProviderId,
    'providerVersion': familyIdentityProviderVersion,
    'scenarioCount': catalog.length,
    'readyScenarioCount': ready,
    'sourceMissingScenarioCount': sourceMissing,
    'invocationCount': invocationCount,
    ...bindings,
    'generationCommand':
        'flutter test --dart-define=UPDATE_FAMILY_IDENTITY_ORACLES=true '
        'test/backend_family_identity_oracle_export_test.dart',
    'orderingPolicy': <String, Object?>{
      'scenario': 'vision_v2_adversarial_scenarios_manifest_order',
      'invocation': 'single_scenario_invocation',
      'familyCandidates': 'confidence_desc_then_family_wire_lexicographic',
      'subtypeCandidates': 'canonical_type_lexicographic',
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
        '${familyIdentityOracleManifestPath.replaceAll('/', Platform.pathSeparator)}',
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

final class _FamilyTrace implements VisionFamilyIdentityTraceSink {
  _FamilyTrace(this.scenarioId);

  final String scenarioId;
  int before = 0;
  int after = 0;
  Map<String, Object?>? _input;
  final List<Map<String, Object?>> records = [];

  @override
  void beforeInvocation({
    required List<VisionFamilyIdentityInput> identityCandidates,
    required ClothingObservationBundle observations,
    required String? resolvedCanonicalSubtype,
    required VisionInputAssessment inputAssessment,
    required VisionSubjectAssessment? subjectAssessment,
    required bool hasWholeItemSilhouette,
  }) {
    before++;
    _input = _providerInput(
      identityCandidates: identityCandidates,
      observations: observations,
      resolvedCanonicalSubtype: resolvedCanonicalSubtype,
      inputAssessment: inputAssessment,
      subjectAssessment: subjectAssessment,
      hasWholeItemSilhouette: hasWholeItemSilhouette,
    );
  }

  @override
  void afterInvocation({
    required List<VisionFamilyIdentityInput> identityCandidates,
    required ClothingObservationBundle observations,
    required String? resolvedCanonicalSubtype,
    required VisionInputAssessment inputAssessment,
    required VisionSubjectAssessment? subjectAssessment,
    required bool hasWholeItemSilhouette,
    required VisionFamilyIdentityReport output,
  }) {
    final current = _providerInput(
      identityCandidates: identityCandidates,
      observations: observations,
      resolvedCanonicalSubtype: resolvedCanonicalSubtype,
      inputAssessment: inputAssessment,
      subjectAssessment: subjectAssessment,
      hasWholeItemSilhouette: hasWholeItemSilhouette,
    );
    if (_input == null || !_equalBytes(_bytes(current), _bytes(_input!))) {
      throw FormatException('family_input_changed:$scenarioId');
    }
    after++;
    records.add({'providerInput': current, 'providerOutput': output.toMap()});
  }
}

Map<String, Object?> _providerInput({
  required List<VisionFamilyIdentityInput> identityCandidates,
  required ClothingObservationBundle observations,
  required String? resolvedCanonicalSubtype,
  required VisionInputAssessment inputAssessment,
  required VisionSubjectAssessment? subjectAssessment,
  required bool hasWholeItemSilhouette,
}) => <String, Object?>{
  'identityCandidates': identityCandidates.map((item) => item.toMap()).toList(),
  'observations': observations.toMap(),
  'resolvedCanonicalSubtype': resolvedCanonicalSubtype,
  'inputAssessment': inputAssessment.wireName,
  'subjectAssessment': subjectAssessment?.toMap(),
  'hasWholeItemSilhouette': hasWholeItemSilhouette,
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
