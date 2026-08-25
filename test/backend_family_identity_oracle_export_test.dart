import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_family_identity.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';

import '../tool/export_family_identity_oracles.dart' as exporter;

void main() {
  test('family resolver boundary remains behavior-neutral with sink', () {
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
      final baseline = const VisionV2ShadowOrchestrator().analyze(
        itemId: id,
        response: responses.first,
        additionalResponses: responses.skip(1),
        multiViewSubjectBinding: binding,
      );
      final withSink = const VisionV2ShadowOrchestrator().analyze(
        itemId: id,
        response: responses.first,
        additionalResponses: responses.skip(1),
        multiViewSubjectBinding: binding,
        familyIdentityTraceSink: _CountingSink(),
      );
      expect(jsonEncode(baseline.toMap()), jsonEncode(withSink.toMap()));
      expect(baseline.familyIdentity.state, withSink.familyIdentity.state);
    }
  });

  test('captures exact family-identity boundary deterministically', () {
    const update = bool.fromEnvironment('UPDATE_FAMILY_IDENTITY_ORACLES');
    final first = exporter.exportFamilyIdentityOracles(
      repositoryRoot: Directory.current,
      write: update,
    );
    final second = exporter.exportFamilyIdentityOracles(
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
    if (File(exporter.familyIdentityOracleManifestPath).existsSync()) {
      expect(
        File(exporter.familyIdentityOracleManifestPath).readAsBytesSync(),
        first['manifestBytes'],
      );
    }
  });

  test('manifest and every ready oracle are SHA bound', () {
    final manifestFile = File(exporter.familyIdentityOracleManifestPath);
    if (!manifestFile.existsSync()) return;
    final manifest = _object(jsonDecode(manifestFile.readAsStringSync()));
    expect(manifest['providerId'], exporter.familyIdentityProviderId);
    expect(manifest['providerVersion'], exporter.familyIdentityProviderVersion);
    expect(manifest['scenarioCount'], 16);
    expect(manifest['readyScenarioCount'], 8);
    expect(manifest['invocationCount'], 8);
    expect(
      sha256
          .convert(
            File(
              'lib/domain/wardrobe_profile/vision_family_identity.dart',
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
            File('tool/export_family_identity_oracles.dart').readAsBytesSync(),
          )
          .toString(),
      manifest['exporterImplementationSha256'],
    );
    expect(
      sha256
          .convert(
            File(
              'lib/domain/wardrobe_profile/vision_family_identity.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['taxonomyRegistrySha256'],
    );
    final ready = _list(
      manifest['fixtures'],
    ).map(_object).where((item) => item['status'] == 'ready').toList();
    expect(ready, hasLength(8));
    for (final entry in ready) {
      final oracleFile = File('test/fixtures/${entry['oraclePath'] as String}');
      expect(oracleFile.existsSync(), isTrue, reason: '${entry['scenarioId']}');
      expect(
        sha256.convert(oracleFile.readAsBytesSync()).toString(),
        entry['oracleSha256'],
      );
      final oracle = _object(jsonDecode(oracleFile.readAsStringSync()));
      expect(oracle['providerId'], exporter.familyIdentityProviderId);
      final invocations = _list(oracle['invocations']).map(_object).toList();
      expect(invocations, hasLength(1));
      final invocation = invocations.single;
      expect(
        invocation['invocationId'],
        '${entry['scenarioId']}::vision-family-identity-resolver',
      );
      final input = _object(invocation['providerInput']);
      final output = _object(invocation['providerOutput']);
      expect(input.containsKey('identityCandidates'), isTrue);
      expect(input.containsKey('observations'), isTrue);
      expect(input.containsKey('resolvedCanonicalSubtype'), isTrue);
      expect(input.containsKey('inputAssessment'), isTrue);
      expect(input.containsKey('hasWholeItemSilhouette'), isTrue);
      expect(output.containsKey('state'), isTrue);
      expect(output.containsKey('resolvedFamily'), isTrue);
      expect(output.containsKey('candidates'), isTrue);
      expect(jsonEncode(output), isNot(contains('knowledgeBaseEvidence')));
      expect(jsonEncode(output), isNot(contains('resolvedProfile')));
    }
  });

  test('output occurs before KB prior and excludes downstream', () {
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
    final clock = _SeqClock();
    final identity = _IdentitySeqSink(clock);
    final family = _FamilySeqSink(clock);
    const VisionV2ShadowOrchestrator().analyze(
      itemId: 'front_only_garment',
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      identityQualificationTraceSink: identity,
      familyIdentityTraceSink: family,
    );
    expect(identity.afterCount, 1);
    expect(family.beforeCount, 1);
    expect(family.afterCount, 1);
    expect(identity.afterSeq, lessThan(family.beforeSeq));
    expect(family.beforeSeq, lessThan(family.afterSeq));
  });

  test('observer is optional passive and wraps family resolver', () {
    final source = File(
      'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
    ).readAsStringSync();
    expect(source, contains('familyIdentityTraceSink?.beforeInvocation'));
    expect(source, contains('VisionFamilyIdentityResolver().resolve'));
    expect(source, contains('familyIdentityTraceSink?.afterInvocation'));
    expect(source, contains('WardrobeKnowledgeBasePriorProvider().provide'));
    expect(
      source.indexOf('familyIdentityTraceSink?.beforeInvocation'),
      lessThan(source.indexOf('VisionFamilyIdentityResolver().resolve')),
    );
    expect(
      source.indexOf('VisionFamilyIdentityResolver().resolve'),
      lessThan(source.indexOf('familyIdentityTraceSink?.afterInvocation')),
    );
    expect(
      source.indexOf('familyIdentityTraceSink?.afterInvocation'),
      lessThan(source.indexOf('WardrobeKnowledgeBasePriorProvider().provide')),
    );
  });

  test('status enums and selected family encoding are stable', () {
    final manifestFile = File(exporter.familyIdentityOracleManifestPath);
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
      'invalid_input',
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
        _list(oracle['invocations']).map(_object).single['providerOutput'],
      );
      expect(allowedStates.contains(output['state']), isTrue);
      expect(
        output.containsKey('resolvedFamily'),
        isTrue,
        reason: '${entry['scenarioId']}',
      );
    }
  });

  test('production remains unchanged with observer disabled', () {
    final production = <String>[
      File('functions/index.js').readAsStringSync(),
      File('functions/vision_v2_shadow.js').readAsStringSync(),
    ].join('\n');
    expect(production, isNot(contains('VisionFamilyIdentityResolver')));
    expect(production, isNot(contains('resolveVisionFamilyIdentity')));
    expect(production, isNot(contains('vision_family_identity_resolver')));
    expect(File('functions/vision_family_identity.js').existsSync(), isFalse);
    final nodeProvider = File('functions/vision_family_identity_resolver.js');
    expect(nodeProvider.existsSync(), isTrue);
    expect(nodeProvider.readAsStringSync(), isNot(contains('firebase')));
    expect(nodeProvider.readAsStringSync(), isNot(contains('firestore')));
  });
}

final class _CountingSink implements VisionFamilyIdentityTraceSink {
  @override
  void beforeInvocation({
    required List<VisionFamilyIdentityInput> identityCandidates,
    required observations,
    required String? resolvedCanonicalSubtype,
    required inputAssessment,
    required subjectAssessment,
    required bool hasWholeItemSilhouette,
  }) {}

  @override
  void afterInvocation({
    required List<VisionFamilyIdentityInput> identityCandidates,
    required observations,
    required String? resolvedCanonicalSubtype,
    required inputAssessment,
    required subjectAssessment,
    required bool hasWholeItemSilhouette,
    required VisionFamilyIdentityReport output,
  }) {}
}

final class _SeqClock {
  var value = 0;
  int next() => ++value;
}

final class _IdentitySeqSink implements VisionIdentityQualificationTraceSink {
  _IdentitySeqSink(this.clock);
  final _SeqClock clock;
  var afterCount = 0;
  var afterSeq = 0;

  @override
  void beforeInvocation({
    required identityEvidence,
    required consistency,
    required declaredByEvidenceId,
    required bool inputIsValid,
  }) {}

  @override
  void afterInvocation({
    required identityEvidence,
    required consistency,
    required declaredByEvidenceId,
    required bool inputIsValid,
    required qualifiedIdentityEvidence,
    required report,
  }) {
    afterCount++;
    afterSeq = clock.next();
  }
}

final class _FamilySeqSink implements VisionFamilyIdentityTraceSink {
  _FamilySeqSink(this.clock);
  final _SeqClock clock;
  var beforeCount = 0;
  var afterCount = 0;
  var beforeSeq = 0;
  var afterSeq = 0;

  @override
  void beforeInvocation({
    required List<VisionFamilyIdentityInput> identityCandidates,
    required observations,
    required String? resolvedCanonicalSubtype,
    required inputAssessment,
    required subjectAssessment,
    required bool hasWholeItemSilhouette,
  }) {
    beforeCount++;
    beforeSeq = clock.next();
  }

  @override
  void afterInvocation({
    required List<VisionFamilyIdentityInput> identityCandidates,
    required observations,
    required String? resolvedCanonicalSubtype,
    required inputAssessment,
    required subjectAssessment,
    required bool hasWholeItemSilhouette,
    required VisionFamilyIdentityReport output,
  }) {
    afterCount++;
    afterSeq = clock.next();
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('expected_object');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('expected_list');
  return List<Object?>.from(value);
}
