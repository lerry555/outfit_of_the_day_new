import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

import '../tool/export_wardrobe_kb_prior_oracles.dart' as exporter;

void main() {
  test('KB prior boundary remains behavior-neutral with sink', () {
    final taxonomy = File(
      'lib/data/clothing_knowledge_base.dart',
    ).readAsStringSync();
    final allowed = RegExp(
      r"canonicalType:\s*'([^']+)'",
    ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
    for (final id in const [
      'shoe_without_outsole',
      'front_only_garment',
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
        knowledgeBasePriorTraceSink: _CountingSink(),
      );
      expect(jsonEncode(baseline.toMap()), jsonEncode(withSink.toMap()));
      expect(
        baseline.knowledgeBaseEvidence.map((item) => item.toMap()).toList(),
        withSink.knowledgeBaseEvidence.map((item) => item.toMap()).toList(),
      );
    }
  });

  test('captures exact KB-prior boundary deterministically', () {
    const update = bool.fromEnvironment('UPDATE_WARDROBE_KB_PRIOR_ORACLES');
    final first = exporter.exportWardrobeKnowledgeBasePriorOracles(
      repositoryRoot: Directory.current,
      write: update,
    );
    final second = exporter.exportWardrobeKnowledgeBasePriorOracles(
      repositoryRoot: Directory.current,
      write: false,
    );
    expect(first['ready'], 8);
    expect(first['sourceMissing'], 8);
    expect(first['invocationCount'], 8);
    expect(first['manifestBytes'], second['manifestBytes']);
    expect(first['oracleBytesByPath'], second['oracleBytesByPath']);
    expect(first['artifactContentSha256'], second['artifactContentSha256']);
    if (File(exporter.kbPriorOracleManifestPath).existsSync()) {
      expect(
        File(exporter.kbPriorOracleManifestPath).readAsBytesSync(),
        first['manifestBytes'],
      );
    }
  });

  test('manifest and every ready oracle are SHA bound', () {
    final manifestFile = File(exporter.kbPriorOracleManifestPath);
    if (!manifestFile.existsSync()) return;
    final manifest = _object(jsonDecode(manifestFile.readAsStringSync()));
    expect(manifest['providerId'], exporter.kbPriorProviderId);
    expect(manifest['providerVersion'], exporter.kbPriorProviderVersion);
    expect(manifest['scenarioCount'], 16);
    expect(manifest['readyScenarioCount'], 8);
    expect(manifest['invocationCount'], 8);
    expect(
      sha256
          .convert(
            File(
              'lib/domain/wardrobe_profile/'
              'wardrobe_knowledge_base_prior_provider.dart',
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
              'tool/export_wardrobe_kb_prior_oracles.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['exporterImplementationSha256'],
    );
    expect(
      sha256
          .convert(
            File('lib/data/clothing_knowledge_base.dart').readAsBytesSync(),
          )
          .toString(),
      manifest['knowledgeBaseSourceSha256'],
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
      expect(oracle['providerId'], exporter.kbPriorProviderId);
      expect(
        oracle['callSitePreparationSha256'],
        manifest['callSitePreparationSha256'],
      );
      expect(
        oracle['knowledgeBaseArtifactContentSha256'],
        manifest['knowledgeBaseArtifactContentSha256'],
      );
      final invocations = _list(oracle['invocations']).map(_object).toList();
      expect(invocations, hasLength(1));
      final invocation = invocations.single;
      expect(
        invocation['invocationId'],
        '${entry['scenarioId']}::wardrobe-kb-prior-provider',
      );
      final input = _object(invocation['providerInput']);
      final output = _list(invocation['providerOutput']);
      expect(input.containsKey('document'), isTrue);
      expect(input.containsKey('existingEvidence'), isTrue);
      expect(_object(input['document']), isEmpty);
      expect(jsonEncode(input), isNot(contains('resolvedProfile')));
      expect(jsonEncode(output), isNot(contains('resolvedProfile')));
      for (final raw in output) {
        final evidence = _object(raw);
        expect(evidence['source'], 'knowledge_base_prior');
        expect(evidence.containsKey('id'), isTrue);
        expect(evidence.containsKey('property'), isTrue);
        expect(evidence.containsKey('nature'), isTrue);
        expect(evidence.containsKey('confidence'), isTrue);
        expect(evidence.containsKey('method'), isTrue);
        expect(evidence.containsKey('createdAt'), isTrue);
        expect(evidence.containsKey('sourceReference'), isTrue);
      }
    }
  });

  test('output occurs before resolver and after upstream evidence', () {
    final fixture = File(
      'test/fixtures/backend_qualification/parser/shoe_without_outsole.parser.json',
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
    final kb = _KbSeqSink(clock);
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'shoe_without_outsole',
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      identityQualificationTraceSink: identity,
      knowledgeBasePriorTraceSink: kb,
    );
    expect(identity.afterCount, 1);
    expect(kb.beforeCount, 1);
    expect(kb.afterCount, 1);
    expect(identity.afterSeq, lessThan(kb.beforeSeq));
    expect(kb.beforeSeq, lessThan(kb.afterSeq));
    expect(analysis.knowledgeBaseEvidence, isNotEmpty);
    expect(
      analysis.resolvedProfile.evidence.any(
        (item) => item.source == EvidenceSource.knowledgeBasePrior,
      ),
      isTrue,
    );
  });

  test(
    'observer is optional passive and wraps KB provider before resolver',
    () {
      final source = File(
        'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
      ).readAsStringSync();
      expect(source, contains('knowledgeBasePriorTraceSink?.beforeInvocation'));
      expect(source, contains('WardrobeKnowledgeBasePriorProvider().provide'));
      expect(source, contains('knowledgeBasePriorTraceSink?.afterInvocation'));
      expect(source, contains('WardrobeProfileResolver().resolve'));
      expect(
        source.indexOf('knowledgeBasePriorTraceSink?.beforeInvocation'),
        lessThan(
          source.indexOf('WardrobeKnowledgeBasePriorProvider().provide'),
        ),
      );
      expect(
        source.indexOf('WardrobeKnowledgeBasePriorProvider().provide'),
        lessThan(
          source.indexOf('knowledgeBasePriorTraceSink?.afterInvocation'),
        ),
      );
      expect(
        source.indexOf('knowledgeBasePriorTraceSink?.afterInvocation'),
        lessThan(source.indexOf('WardrobeProfileResolver().resolve')),
      );
    },
  );

  test('production remains unchanged with observer disabled', () {
    final production = <String>[
      File('functions/index.js').readAsStringSync(),
      File('functions/vision_v2_shadow.js').readAsStringSync(),
    ].join('\n');
    expect(production, isNot(contains('WardrobeKnowledgeBasePriorProvider')));
    expect(production, isNot(contains('wardrobe_knowledge_base_prior')));
    expect(production, isNot(contains('provideWardrobeKnowledgeBasePriors')));
    expect(production, isNot(contains('backend_wardrobe_kb_prior_parity')));
    final nodeProvider = File(
      'functions/wardrobe_knowledge_base_prior_provider.js',
    );
    expect(nodeProvider.existsSync(), isTrue);
    final nodeSource = nodeProvider.readAsStringSync();
    expect(nodeSource, isNot(contains('firebase')));
    expect(nodeSource, isNot(contains('firestore')));
  });
}

final class _CountingSink implements WardrobeKnowledgeBasePriorTraceSink {
  @override
  void beforeInvocation({
    required Map<String, dynamic> document,
    required List<ProfileEvidence> existingEvidence,
  }) {}

  @override
  void afterInvocation({
    required Map<String, dynamic> document,
    required List<ProfileEvidence> existingEvidence,
    required List<ProfileEvidence> output,
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

final class _KbSeqSink implements WardrobeKnowledgeBasePriorTraceSink {
  _KbSeqSink(this.clock);
  final _SeqClock clock;
  var beforeCount = 0;
  var afterCount = 0;
  var beforeSeq = 0;
  var afterSeq = 0;

  @override
  void beforeInvocation({
    required Map<String, dynamic> document,
    required List<ProfileEvidence> existingEvidence,
  }) {
    beforeCount++;
    beforeSeq = clock.next();
  }

  @override
  void afterInvocation({
    required Map<String, dynamic> document,
    required List<ProfileEvidence> existingEvidence,
    required List<ProfileEvidence> output,
  }) {
    afterCount++;
    afterSeq = clock.next();
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw FormatException('expected_object');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _list(Object? value) {
  if (value is! List) throw FormatException('expected_list');
  return List<Object?>.from(value);
}
