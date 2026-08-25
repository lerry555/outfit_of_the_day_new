import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/canonical_observation_consistency_validator.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

import '../tool/export_identity_qualification_oracles.dart' as exporter;

void main() {
  test('pure helper extraction remains behavior-neutral on ready fixtures', () {
    final taxonomy = File(
      'lib/data/clothing_knowledge_base.dart',
    ).readAsStringSync();
    final allowed = RegExp(
      r"canonicalType:\s*'([^']+)'",
    ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
    for (final id in const [
      'front_only_garment',
      'conflicting_multi_view',
      'cropped_upper',
    ]) {
      final fixture = File(
        'test/fixtures/backend_qualification/parser/$id.parser.json',
      );
      if (!fixture.existsSync()) continue;
      final fixtureJson = fixture.readAsStringSync();
      final responses = const VisionParserFixtureReplay().decodeResponses(
        fixtureJson,
        allowedCanonicalTypes: allowed,
      );
      final binding = const VisionParserFixtureReplay().decodeBinding(
        fixtureJson,
      );
      final analysis = const VisionV2ShadowOrchestrator().analyze(
        itemId: id,
        response: responses.first,
        additionalResponses: responses.skip(1),
        multiViewSubjectBinding: binding,
      );
      expect(analysis.identityQualification, isNotNull);
      expect(analysis.qualifiedIdentityEvidence, isNotEmpty);
      expect(analysis.identityQualification.candidates, isNotEmpty);
    }
  });

  test('captures exact identity-qualification boundary deterministically', () {
    const update = bool.fromEnvironment(
      'UPDATE_IDENTITY_QUALIFICATION_ORACLES',
    );
    final first = exporter.exportIdentityQualificationOracles(
      repositoryRoot: Directory.current,
      write: update,
    );
    final second = exporter.exportIdentityQualificationOracles(
      repositoryRoot: Directory.current,
      write: false,
    );
    expect(first['ready'], 8);
    expect(first['sourceMissing'], 8);
    expect(first['invocationCount'], 8);
    expect(first['singleViewInvocations'], 7);
    expect(first['multiViewInvocations'], 1);
    expect(first['manifestBytes'], second['manifestBytes']);
    expect(first['oracleBytesByPath'], second['oracleBytesByPath']);
    if (File(exporter.identityQualificationOracleManifestPath).existsSync()) {
      expect(
        File(
          exporter.identityQualificationOracleManifestPath,
        ).readAsBytesSync(),
        first['manifestBytes'],
      );
    }
  });

  test('manifest and every ready oracle are SHA bound', () {
    final manifestFile = File(exporter.identityQualificationOracleManifestPath);
    if (!manifestFile.existsSync()) return;
    final manifest = _object(jsonDecode(manifestFile.readAsStringSync()));
    expect(manifest['providerId'], exporter.identityQualificationStageId);
    expect(
      manifest['providerVersion'],
      exporter.identityQualificationStageVersion,
    );
    expect(manifest['scenarioCount'], 16);
    expect(manifest['readyScenarioCount'], 8);
    expect(manifest['invocationCount'], 8);
    expect(
      sha256
          .convert(
            File(
              'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
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
              'tool/export_identity_qualification_oracles.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['exporterImplementationSha256'],
    );
    expect(
      sha256
          .convert(
            File(
              'lib/domain/wardrobe_profile/'
              'canonical_observation_consistency_validator.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['taxonomyRegistrySha256'],
    );
    expect(_serializerSha256(), manifest['serializerSha256']);
    final ready = _list(
      manifest['fixtures'],
    ).map(_object).where((item) => item['status'] == 'ready').toList();
    expect(ready, hasLength(8));
    for (final entry in ready) {
      final oracleFile = File('test/fixtures/${entry['oraclePath'] as String}');
      expect(
        oracleFile.existsSync(),
        isTrue,
        reason: entry['scenarioId'].toString(),
      );
      expect(
        sha256.convert(oracleFile.readAsBytesSync()).toString(),
        entry['oracleSha256'],
      );
      final oracle = _object(jsonDecode(oracleFile.readAsStringSync()));
      expect(oracle['providerId'], exporter.identityQualificationStageId);
      final invocations = _list(oracle['invocations']).map(_object).toList();
      expect(invocations, hasLength(1));
      final invocation = invocations.single;
      expect(
        invocation['invocationId'],
        '${entry['scenarioId']}::vision-identity-qualification',
      );
      final input = _object(invocation['providerInput']);
      final output = _object(invocation['providerOutput']);
      expect(input.containsKey('identityEvidence'), isTrue);
      expect(input.containsKey('consistency'), isTrue);
      expect(input.containsKey('declaredByEvidenceId'), isTrue);
      expect(input.containsKey('inputIsValid'), isTrue);
      expect(output.containsKey('qualifiedIdentityEvidence'), isTrue);
      expect(output.containsKey('report'), isTrue);
      expect(jsonEncode(output), isNot(contains('familyIdentity')));
      expect(jsonEncode(output), isNot(contains('resolvedProfile')));
      expect(jsonEncode(output), isNot(contains('knowledgeBaseEvidence')));
    }
  });

  test('output occurs before family resolver and excludes downstream', () {
    final fixture = File(
      'test/fixtures/backend_qualification/parser/front_only_garment.parser.json',
    );
    final taxonomy = File(
      'lib/data/clothing_knowledge_base.dart',
    ).readAsStringSync();
    final allowed = RegExp(
      r"canonicalType:\s*'([^']+)'",
    ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
    final fixtureJson = fixture.readAsStringSync();
    final responses = const VisionParserFixtureReplay().decodeResponses(
      fixtureJson,
      allowedCanonicalTypes: allowed,
    );
    final binding = const VisionParserFixtureReplay().decodeBinding(
      fixtureJson,
    );
    final identity = _IdentityCapture();
    const VisionV2ShadowOrchestrator().analyze(
      itemId: 'front_only_garment',
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      identityQualificationTraceSink: identity,
    );
    expect(identity.beforeCount, 1);
    expect(identity.afterCount, 1);
    expect(identity.report, isNotNull);
    expect(identity.qualifiedEvidence, isNotEmpty);
    expect(identity.afterSeq, 1);
  });

  test('observer is optional passive and immediately wraps qualifier', () {
    final source = File(
      'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('identityQualificationTraceSink?.beforeInvocation'),
    );
    expect(source, contains('VisionIdentityQualifier().qualify'));
    expect(source, contains('identityQualificationTraceSink?.afterInvocation'));
    expect(source, contains('VisionFamilyIdentityResolver().resolve'));
    expect(
      source.indexOf('identityQualificationTraceSink?.beforeInvocation'),
      lessThan(source.indexOf('VisionIdentityQualifier().qualify')),
    );
    expect(
      source.indexOf('VisionIdentityQualifier().qualify'),
      lessThan(
        source.indexOf('identityQualificationTraceSink?.afterInvocation'),
      ),
    );
    expect(
      source.indexOf('identityQualificationTraceSink?.afterInvocation'),
      lessThan(source.indexOf('VisionFamilyIdentityResolver().resolve')),
    );
  });

  test('exporter and observer remain offline and production isolated', () {
    final exporterSource = File(
      'tool/export_identity_qualification_oracles.dart',
    ).readAsStringSync();
    final production = <String>[
      File('functions/index.js').readAsStringSync(),
      File('functions/vision_v2_shadow.js').readAsStringSync(),
    ].join('\n');
    expect(exporterSource, isNot(contains('package:http')));
    expect(exporterSource.toLowerCase(), isNot(contains('firebase')));
    expect(exporterSource, isNot(contains('DateTime.now')));
    expect(exporterSource, isNot(contains('Random(')));
    expect(exporterSource, isNot(contains('QualifiedVisionPersistenceMapper')));
    expect(production, isNot(contains('VisionIdentityQualifier')));
    expect(production, isNot(contains('identity_qualification')));
    expect(
      File('functions/vision_identity_qualifier.js').existsSync(),
      isTrue,
      reason: 'Node VisionIdentityQualifier port must exist after 3A-R',
    );
    expect(
      Directory('functions')
          .listSync()
          .whereType<File>()
          .map((file) => file.path.replaceAll('\\', '/'))
          .where((path) {
            final lower = path.toLowerCase();
            if (!lower.contains('identity_qualification') &&
                !lower.contains('vision_identity_qualifier')) {
              return false;
            }
            if (lower.contains('oracle')) return false;
            // Allowed Node surfaces for identity qualification port.
            if (lower.endsWith('vision_identity_qualifier.js') ||
                lower.endsWith('vision_identity_qualifier.test.js') ||
                lower.endsWith('backend_identity_qualification_parity.js') ||
                lower.endsWith(
                  'prepare_vision_identity_qualification_input.js',
                ) ||
                lower.endsWith(
                  'prepare_vision_identity_qualification_input.test.js',
                ) ||
                lower.endsWith(
                  'backend_identity_qualification_input_parity.js',
                )) {
              return false;
            }
            return true;
          }),
      isEmpty,
    );
  });

  test('status enums and selected canonical encoding are stable', () {
    final manifestFile = File(exporter.identityQualificationOracleManifestPath);
    if (!manifestFile.existsSync()) return;
    final manifest = _object(jsonDecode(manifestFile.readAsStringSync()));
    final ready = _list(
      manifest['fixtures'],
    ).map(_object).where((item) => item['status'] == 'ready');
    final allowedStates = {
      'confirmed',
      'supported',
      'ambiguous',
      'insufficient_evidence',
      'conflicting',
    };
    for (final entry in ready) {
      final oracle = _object(
        jsonDecode(
          File(
            'test/fixtures/${entry['oraclePath'] as String}',
          ).readAsStringSync(),
        ),
      );
      final output = _object(
        _object(_list(oracle['invocations']).single)['providerOutput'],
      );
      final report = _object(output['report']);
      expect(allowedStates.contains(report['state']), isTrue);
      expect(report.containsKey('selectedCanonicalType'), isTrue);
      expect(report.containsKey('topMargin'), isTrue);
      expect(report.containsKey('candidates'), isTrue);
      for (final raw in _list(report['candidates'])) {
        final candidate = _object(raw);
        expect(candidate['canonicalType'], isA<String>());
        expect(allowedStates.contains(candidate['state']), isTrue);
        expect(candidate['reasonCodes'], isA<List>());
      }
    }
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
    'lib/domain/wardrobe_profile/wardrobe_profile_contract.dart',
    'lib/domain/wardrobe_profile/canonical_observation_consistency_validator.dart',
    'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
  ]) {
    input.add(utf8.encode(File(path).uri.pathSegments.last));
    input.add(const <int>[0]);
    input.add(File(path).readAsBytesSync());
    input.add(const <int>[0]);
  }
  return sha256.convert(input.takeBytes()).toString();
}

final class _IdentityCapture implements VisionIdentityQualificationTraceSink {
  int beforeCount = 0;
  int afterCount = 0;
  int afterSeq = 0;
  VisionIdentityQualificationReport? report;
  List<ProfileEvidence>? qualifiedEvidence;
  static int _seq = 0;

  @override
  void beforeInvocation({
    required List<ProfileEvidence> identityEvidence,
    required CanonicalConsistencyReport consistency,
    required Map<String, ({List<String> defining, List<String> supporting})>
    declaredByEvidenceId,
    required bool inputIsValid,
  }) {
    beforeCount++;
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
    afterCount++;
    afterSeq = ++_seq;
    this.report = report;
    qualifiedEvidence = List.unmodifiable(qualifiedIdentityEvidence);
  }
}
