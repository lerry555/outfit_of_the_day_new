import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_framing_attestation.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_subject_safety.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

import '../tool/export_negative_claim_corroborator_oracles.dart' as exporter;

void main() {
  test('live capture negatives reach corroborator when regions suffice', () {
    final parser = File(
      'test/fixtures/backend_qualification/parser/'
      'complementary_multi_view.parser.json',
    );
    if (!parser.existsSync()) return;
    final taxonomy = File(
      'lib/data/clothing_knowledge_base.dart',
    ).readAsStringSync();
    final allowed = RegExp(
      r"canonicalType:\s*'([^']+)'",
    ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
    final fixtureJson = parser.readAsStringSync();
    final responses = const VisionParserFixtureReplay().decodeResponses(
      fixtureJson,
      allowedCanonicalTypes: allowed,
    );
    final binding = const VisionParserFixtureReplay().decodeBinding(
      fixtureJson,
    );
    final trace = _CharacterizationTrace();
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'complementary_multi_view',
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      negativeClaimCorroborationTraceSink: trace,
    );
    final claims = trace.outputs.expand((item) => item.claims.values).toList();
    expect(responses, hasLength(2));
    expect(trace.beforeCount, 2);
    expect(trace.inputs, hasLength(2));
    expect(
      trace.inputs.every((input) => input['sameItemViews'] == true),
      isTrue,
    );
    expect(trace.outputs, hasLength(2));
    // Prompt schema_10 now declares property-specific regions on some
    // observed absences. Visibility still rejects incomplete hood/pocket
    // absence region sets, but back-view frontClosure=none reaches the
    // corroborator and is audited as conflicting against the front zip.
    expect(claims, isNotEmpty);
    expect(claims.any((claim) => claim.property == 'frontClosure'), isTrue);
    expect(
      claims
          .where((claim) => claim.property == 'frontClosure')
          .every(
            (claim) =>
                claim.state == NegativeClaimCorroborationState.conflicting,
          ),
      isTrue,
    );
    expect(
      responses.any(
        (response) =>
            response.observations.hasHood?.isObserved == true &&
            response.observations.hasHood?.value == false,
      ),
      isTrue,
    );
    expect(
      responses.any(
        (response) =>
            response.observations.visiblePocketStructure?.isObserved == true &&
            response.observations.visiblePocketStructure?.value ==
                VisiblePocketStructure.none,
      ),
      isTrue,
    );
    expect(analysis.observationQualification, isNotNull);
  });

  test('captures exact negative-claim boundary deterministically', () {
    const update = bool.fromEnvironment('UPDATE_NEGATIVE_CLAIM_ORACLES');
    final first = exporter.exportNegativeClaimCorroboratorOracles(
      repositoryRoot: Directory.current,
      write: update,
    );
    final second = exporter.exportNegativeClaimCorroboratorOracles(
      repositoryRoot: Directory.current,
      write: false,
    );
    expect(first['ready'], 8);
    expect(first['sourceMissing'], 8);
    expect(first['invocationCount'], 9);
    expect(first['manifestBytes'], second['manifestBytes']);
    expect(first['oracleBytesByPath'], second['oracleBytesByPath']);
    if (File(exporter.negativeClaimOracleManifestPath).existsSync()) {
      expect(
        File(exporter.negativeClaimOracleManifestPath).readAsBytesSync(),
        first['manifestBytes'],
      );
    }
  });

  test('manifest and every ready oracle are SHA bound', () {
    final manifestFile = File(exporter.negativeClaimOracleManifestPath);
    if (!manifestFile.existsSync()) return;
    final manifest = _object(jsonDecode(manifestFile.readAsStringSync()));
    expect(manifest['providerId'], exporter.negativeClaimProviderId);
    expect(manifest['scenarioCount'], 16);
    expect(manifest['readyScenarioCount'], 8);
    expect(manifest['invocationCount'], 9);
    expect(
      sha256
          .convert(
            File(
              'lib/domain/wardrobe_profile/vision_framing_attestation.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['providerImplementationSha256'],
    );
    expect(
      sha256
          .convert(
            File(
              'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['callSitePreparationSha256'],
    );
    expect(
      sha256
          .convert(
            File(
              'tool/export_negative_claim_corroborator_oracles.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['exporterImplementationSha256'],
    );
    expect(_serializerSha256(), manifest['serializerSha256']);
    final ready = _list(
      manifest['fixtures'],
    ).map(_object).where((item) => item['status'] == 'ready').toList();
    expect(ready, hasLength(8));
    final ids = <String>{};
    for (final entry in ready) {
      final oracleFile = File('test/fixtures/${entry['oraclePath']}');
      expect(oracleFile.existsSync(), isTrue);
      expect(
        sha256.convert(oracleFile.readAsBytesSync()).toString(),
        entry['oracleSha256'],
      );
      final oracle = _object(jsonDecode(oracleFile.readAsStringSync()));
      for (final raw in _list(oracle['invocations'])) {
        final invocation = _object(raw);
        expect(ids.add(invocation['invocationId']! as String), isTrue);
        expect(invocation['providerInput'], isA<Map>());
        expect(invocation['providerOutput'], isA<Map>());
      }
    }
    expect(ids, hasLength(9));
  });

  test('input ordering and null versus omitted encoding are stable', () {
    final result = exporter.exportNegativeClaimCorroboratorOracles(
      repositoryRoot: Directory.current,
      write: false,
    );
    final bytesByPath = _object(result['oracleBytesByPath']);
    final invocationIds = <String>[];
    for (final bytes in bytesByPath.values) {
      final oracle = _object(
        jsonDecode(utf8.decode(List<int>.from(bytes as List))),
      );
      for (final raw in _list(oracle['invocations'])) {
        final invocation = _object(raw);
        invocationIds.add(invocation['invocationId']! as String);
        final input = _object(invocation['providerInput']);
        expect(
          input.keys,
          containsAll(<String>[
            'bundle',
            'subject',
            'framing',
            'viewCount',
            'sameItemViews',
            'complementaryRegions',
            'conflictingPositiveProperties',
          ]),
        );
        expect(input['complementaryRegions'], isA<Map>());
        expect(input['conflictingPositiveProperties'], isA<List>());
        final output = _object(invocation['providerOutput']);
        expect(output.keys, containsAll(<String>['qualifiedBundle', 'claims']));
        expect(output, isNot(contains('observationQualification')));
      }
    }
    expect(invocationIds.toSet(), hasLength(invocationIds.length));
    expect(
      invocationIds.where((id) => id.contains('conflicting_multi_view')),
      hasLength(2),
    );
  });

  test('observer is optional passive and immediately wraps provider call', () {
    final source = File(
      'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('negativeClaimCorroborationTraceSink?.beforeInvocation'),
    );
    expect(source, contains('VisionNegativeClaimCorroborator().qualify'));
    expect(
      source,
      contains('negativeClaimCorroborationTraceSink?.afterInvocation'),
    );
    expect(source, contains('ObservationAbsenceQualifier().qualifyBundles'));
    expect(
      source.indexOf('negativeClaimCorroborationTraceSink?.beforeInvocation'),
      lessThan(source.indexOf('VisionNegativeClaimCorroborator().qualify')),
    );
    expect(
      source.indexOf('VisionNegativeClaimCorroborator().qualify'),
      lessThan(
        source.indexOf('negativeClaimCorroborationTraceSink?.afterInvocation'),
      ),
    );
    expect(
      source.indexOf('negativeClaimCorroborationTraceSink?.afterInvocation'),
      lessThan(source.indexOf('ObservationAbsenceQualifier().qualifyBundles')),
    );
  });

  test('exporter and observer remain offline and production isolated', () {
    final exporterSource = File(
      'tool/export_negative_claim_corroborator_oracles.dart',
    ).readAsStringSync();
    final production = <String>[
      File('functions/index.js').readAsStringSync(),
      File('functions/vision_v2_shadow.js').readAsStringSync(),
    ].join('\n');
    expect(exporterSource, isNot(contains('package:http')));
    expect(exporterSource.toLowerCase(), isNot(contains('firebase')));
    expect(exporterSource, isNot(contains('DateTime.now')));
    expect(exporterSource, isNot(contains('QualifiedVisionPersistenceMapper')));
    expect(production, isNot(contains('NegativeClaimCorroborator')));
    expect(production, isNot(contains('vision_negative_claim_corroborator')));
    expect(production, isNot(contains('qualifyNegativeClaims')));
    expect(
      File('functions/vision_negative_claim_corroborator.js').existsSync(),
      isTrue,
    );
    expect(
      File('functions/backend_negative_claim_parity.js').existsSync(),
      isTrue,
    );
    expect(
      File('functions/index.js').readAsStringSync(),
      isNot(contains("require('./vision_negative_claim_corroborator")),
    );
    expect(
      File('functions/vision_v2_shadow.js').readAsStringSync(),
      isNot(contains("require('./vision_negative_claim_corroborator")),
    );
  });
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('expected_object');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('expected_list');
  return List<Object?>.from(value);
}

String _serializerSha256() {
  final input = BytesBuilder(copy: false);
  for (final path in <String>[
    'lib/domain/wardrobe_profile/wardrobe_observation_contract.dart',
    'lib/domain/wardrobe_profile/vision_subject_safety.dart',
    'lib/domain/wardrobe_profile/vision_framing_attestation.dart',
  ]) {
    input.add(utf8.encode(File(path).uri.pathSegments.last));
    input.add(const <int>[0]);
    input.add(File(path).readAsBytesSync());
    input.add(const <int>[0]);
  }
  return sha256.convert(input.takeBytes()).toString();
}

final class _CharacterizationTrace
    implements VisionNegativeClaimCorroborationTraceSink {
  int beforeCount = 0;
  final List<Map<String, Object?>> inputs = [];
  final List<NegativeClaimCorroborationReport> outputs = [];

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
    beforeCount++;
    inputs.add(<String, Object?>{
      'viewIndex': viewIndex,
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
    });
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
    outputs.add(output);
  }
}
