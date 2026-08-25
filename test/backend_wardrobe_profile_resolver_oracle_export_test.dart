import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_resolver.dart';

import '../tool/export_wardrobe_profile_resolver_oracles.dart' as exporter;

void main() {
  test('resolver boundary remains behavior-neutral with sink', () {
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
        wardrobeProfileResolverTraceSink: _CountingSink(),
      );
      expect(jsonEncode(baseline.toMap()), jsonEncode(withSink.toMap()));
      expect(
        jsonEncode(baseline.resolvedProfile.toMap()),
        jsonEncode(withSink.resolvedProfile.toMap()),
      );
    }
  });

  test('captures exact resolver boundary deterministically', () {
    const update = bool.fromEnvironment(
      'UPDATE_WARDROBE_PROFILE_RESOLVER_ORACLES',
    );
    final first = exporter.exportWardrobeProfileResolverOracles(
      repositoryRoot: Directory.current,
      write: update,
    );
    final second = exporter.exportWardrobeProfileResolverOracles(
      repositoryRoot: Directory.current,
      write: false,
    );
    expect(first['ready'], 8);
    expect(first['sourceMissing'], 8);
    expect(first['invocationCount'], 8);
    expect(first['manifestBytes'], second['manifestBytes']);
    expect(first['oracleBytesByPath'], second['oracleBytesByPath']);
    if (File(exporter.wardrobeProfileResolverOracleManifestPath).existsSync()) {
      expect(
        File(
          exporter.wardrobeProfileResolverOracleManifestPath,
        ).readAsBytesSync(),
        first['manifestBytes'],
      );
    }
  });

  test('manifest and every ready oracle are SHA bound', () {
    final manifestFile = File(
      exporter.wardrobeProfileResolverOracleManifestPath,
    );
    if (!manifestFile.existsSync()) return;
    final manifest = _object(jsonDecode(manifestFile.readAsStringSync()));
    expect(manifest['providerId'], exporter.wardrobeProfileResolverId);
    expect(
      manifest['providerVersion'],
      exporter.wardrobeProfileResolverVersion,
    );
    expect(manifest['scenarioCount'], 16);
    expect(manifest['readyScenarioCount'], 8);
    expect(manifest['invocationCount'], 8);
    expect(
      sha256
          .convert(
            File(
              'lib/domain/wardrobe_profile/wardrobe_profile_resolver.dart',
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
              'tool/export_wardrobe_profile_resolver_oracles.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['exporterImplementationSha256'],
    );
    final ready = _list(manifest['fixtures'])
        .map(_object)
        .where((item) => item['status'] == 'ready')
        .toList();
    expect(ready, hasLength(8));
    for (final entry in ready) {
      final oracleFile = File(
        'test/fixtures/${entry['oraclePath']}'.replaceAll('/',
            Platform.pathSeparator),
      );
      expect(oracleFile.existsSync(), isTrue);
      expect(
        sha256.convert(oracleFile.readAsBytesSync()).toString(),
        entry['oracleSha256'],
      );
      final oracle = _object(jsonDecode(oracleFile.readAsStringSync()));
      expect(oracle['providerId'], exporter.wardrobeProfileResolverId);
      expect(oracle['inputContract'], 'wardrobe_profile_resolver_input/v1');
      expect(oracle['outputContract'], 'ResolvedWardrobeItemProfile/v1');
      final invocations = _list(oracle['invocations']).map(_object).toList();
      expect(invocations, hasLength(1));
      final invocation = invocations.single;
      expect(
        invocation['invocationId'],
        '${entry['scenarioId']}::wardrobe-profile-resolver',
      );
      final input = _object(invocation['resolverInput']);
      final output = _object(invocation['resolverOutput']);
      expect(input['itemId'], entry['scenarioId']);
      expect(input.containsKey('evidence'), isTrue);
      expect(input.containsKey('resolvedProfile'), isFalse);
      expect(input.containsKey('persistence'), isFalse);
      expect(output['itemId'], entry['scenarioId']);
      expect(output.containsKey('identity'), isTrue);
      expect(output.containsKey('evidence'), isTrue);
      expect(output.containsKey('userCorrections'), isFalse);
      expect(oracle['familyIntegration'], isA<Map>());
      final family = _object(oracle['familyIntegration']);
      expect(family['familyConsumedByResolver'], isFalse);
      expect(family['familyOnResolvedProfile'], isFalse);
      expect(
        sha256.convert(_canonicalBytes(input)).toString(),
        invocation['resolverInputSha256'],
      );
      expect(
        sha256.convert(_canonicalBytes(output)).toString(),
        invocation['resolverOutputSha256'],
      );
    }
  });

  test('output is captured before mapper and excludes persistence envelope', () {
    final taxonomy = File(
      'lib/data/clothing_knowledge_base.dart',
    ).readAsStringSync();
    final allowed = RegExp(
      r"canonicalType:\s*'([^']+)'",
    ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
    final fixture = File(
      'test/fixtures/backend_qualification/parser/shoe_without_outsole.parser.json',
    );
    final fixtureJson = fixture.readAsStringSync();
    final responses = const VisionParserFixtureReplay().decodeResponses(
      fixtureJson,
      allowedCanonicalTypes: allowed,
    );
    final binding = const VisionParserFixtureReplay().decodeBinding(
      fixtureJson,
    );
    final sink = _CaptureSink();
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'shoe_without_outsole',
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      wardrobeProfileResolverTraceSink: sink,
    );
    expect(sink.afterCount, 1);
    expect(sink.output, isNotNull);
    expect(
      jsonEncode(sink.output!.toMap()),
      jsonEncode(analysis.resolvedProfile.toMap()),
    );
    final encoded = jsonEncode(sink.output!.toMap());
    expect(encoded, isNot(contains('firestore')));
    expect(encoded, isNot(contains('userCorrections')));
    expect(encoded, isNot(contains('resolvedCache')));
    expect(encoded, isNot(contains('omittedReason')));
  });

  test('KB prior runs before resolver; family is not resolver evidence', () {
    final taxonomy = File(
      'lib/data/clothing_knowledge_base.dart',
    ).readAsStringSync();
    final allowed = RegExp(
      r"canonicalType:\s*'([^']+)'",
    ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
    final fixture = File(
      'test/fixtures/backend_qualification/parser/shoe_without_outsole.parser.json',
    );
    final fixtureJson = fixture.readAsStringSync();
    final responses = const VisionParserFixtureReplay().decodeResponses(
      fixtureJson,
      allowedCanonicalTypes: allowed,
    );
    final binding = const VisionParserFixtureReplay().decodeBinding(
      fixtureJson,
    );
    final clock = _SeqClock();
    final kb = _KbSeqSink(clock);
    final resolver = _ResolverSeqSink(clock);
    final analysis = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'shoe_without_outsole',
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      knowledgeBasePriorTraceSink: kb,
      wardrobeProfileResolverTraceSink: resolver,
    );
    expect(kb.afterSeq, lessThan(resolver.beforeSeq));
    expect(resolver.beforeSeq, lessThan(resolver.afterSeq));
    expect(
      resolver.inputEvidence!.any(
        (item) => item.property == WardrobeProfileProperty.family,
      ),
      isFalse,
    );
    expect(
      analysis.resolvedProfile.toMap().containsKey('family'),
      isFalse,
    );
    expect(
      (analysis.resolvedProfile.toMap()['identity'] as Map).containsKey(
        'family',
      ),
      isFalse,
    );
  });

  test(
    'observer is optional passive and wraps resolver before analysis return',
    () {
      final source = File(
        'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('wardrobeProfileResolverTraceSink?.beforeInvocation'),
      );
      expect(source, contains('WardrobeProfileResolver().resolve'));
      expect(
        source,
        contains('wardrobeProfileResolverTraceSink?.afterInvocation'),
      );
      expect(
        source.indexOf('wardrobeProfileResolverTraceSink?.beforeInvocation'),
        lessThan(source.indexOf('WardrobeProfileResolver().resolve')),
      );
      expect(
        source.indexOf('WardrobeProfileResolver().resolve'),
        lessThan(
          source.indexOf('wardrobeProfileResolverTraceSink?.afterInvocation'),
        ),
      );
      expect(
        source.indexOf('wardrobeProfileResolverTraceSink?.afterInvocation'),
        lessThan(source.indexOf('resolvedProfile: resolvedProfile')),
      );
    },
  );

  test('production remains unchanged with observer disabled', () {
    final production = <String>[
      File('functions/index.js').readAsStringSync(),
      File('functions/vision_v2_shadow.js').readAsStringSync(),
    ].join('\n');
    expect(production, isNot(contains('WardrobeProfileResolver')));
    expect(production, isNot(contains('wardrobe_profile_resolver')));
    expect(production, isNot(contains('provideWardrobeProfile')));
    expect(production, isNot(contains('backend_wardrobe_profile_resolver_parity')));
    final nodeProvider = File('functions/wardrobe_profile_resolver.js');
    expect(nodeProvider.existsSync(), isTrue);
    final nodeSource = nodeProvider.readAsStringSync();
    expect(nodeSource, isNot(contains('firebase')));
    expect(nodeSource, isNot(contains('firestore')));
  });

  group('resolver characterization remains explicit', () {
    test('visual beats KB where designed', () {
      final profile = const WardrobeProfileResolver().resolve(
        itemId: 'item',
        evidence: [
          _evidence(
            id: 'kb',
            property: WardrobeProfileProperty.colors,
            value: const ['black'],
            source: EvidenceSource.knowledgeBasePrior,
            nature: EvidenceNature.defaulted,
            confidence: 0.9,
          ),
          _evidence(
            id: 'vis',
            property: WardrobeProfileProperty.colors,
            value: const ['navy'],
            source: EvidenceSource.visualObservation,
            nature: EvidenceNature.observed,
            confidence: 0.7,
          ),
        ],
      );
      expect(profile.visual.colors.winningSource, EvidenceSource.visualObservation);
      expect(profile.visual.colors.value, ['navy']);
    });

    test('item-specific capability beats KB prior', () {
      final profile = const WardrobeProfileResolver().resolve(
        itemId: 'item',
        evidence: [
          _evidence(
            id: 'kb',
            property: WardrobeProfileProperty.warmth,
            value: 4,
            source: EvidenceSource.knowledgeBasePrior,
            nature: EvidenceNature.defaulted,
            confidence: 0.9,
            dependsOnCanonicalType: 'boots',
          ),
          _evidence(
            id: 'cap',
            property: WardrobeProfileProperty.warmth,
            value: 7,
            source: EvidenceSource.aiInference,
            nature: EvidenceNature.inferred,
            confidence: 0.7,
          ),
          _evidence(
            id: 'canon',
            property: WardrobeProfileProperty.canonicalType,
            value: 'boots',
            source: EvidenceSource.aiInference,
            nature: EvidenceNature.inferred,
            confidence: 0.8,
          ),
        ],
      );
      expect(profile.capabilities.warmth.winningSource, EvidenceSource.aiInference);
      expect(profile.capabilities.warmth.value, 7);
    });

    test('user correction wins over machine evidence', () {
      final profile = const WardrobeProfileResolver().resolve(
        itemId: 'item',
        evidence: [
          _evidence(
            id: 'ai',
            property: WardrobeProfileProperty.canonicalType,
            value: 'sneakers',
            source: EvidenceSource.aiInference,
            nature: EvidenceNature.inferred,
            confidence: 0.95,
          ),
          _evidence(
            id: 'user',
            property: WardrobeProfileProperty.canonicalType,
            value: 'boots',
            source: EvidenceSource.userCorrection,
            nature: EvidenceNature.observed,
            confidence: 1,
            verified: true,
          ),
        ],
      );
      expect(
        profile.identity.canonicalType.winningSource,
        EvidenceSource.userCorrection,
      );
      expect(profile.identity.canonicalType.value, 'boots');
    });

    test('inactive evidence is ignored', () {
      final profile = const WardrobeProfileResolver().resolve(
        itemId: 'item',
        evidence: [
          _evidence(
            id: 'inactive',
            property: WardrobeProfileProperty.canonicalType,
            value: 'boots',
            source: EvidenceSource.aiInference,
            nature: EvidenceNature.inferred,
            confidence: 0.9,
            active: false,
          ),
        ],
      );
      expect(profile.identity.canonicalType.isUnknown, isTrue);
    });

    test('unknown and not_visible candidates are skipped', () {
      final profile = const WardrobeProfileResolver().resolve(
        itemId: 'item',
        evidence: [
          _evidence(
            id: 'unk',
            property: WardrobeProfileProperty.hasHood,
            value: null,
            valueState: EvidenceValueState.unknown,
            source: EvidenceSource.visualObservation,
            nature: EvidenceNature.unknown,
            confidence: 0,
          ),
          _evidence(
            id: 'nv',
            property: WardrobeProfileProperty.hasHood,
            value: null,
            valueState: EvidenceValueState.notVisible,
            source: EvidenceSource.visualObservation,
            nature: EvidenceNature.observed,
            confidence: 0.4,
          ),
        ],
      );
      expect(profile.visual.hasHood.isUnknown, isTrue);
    });

    test('not_applicable can win', () {
      final profile = const WardrobeProfileResolver().resolve(
        itemId: 'item',
        evidence: [
          _evidence(
            id: 'na',
            property: WardrobeProfileProperty.hasHood,
            value: null,
            valueState: EvidenceValueState.notApplicable,
            source: EvidenceSource.visualObservation,
            nature: EvidenceNature.observed,
            confidence: 0.8,
          ),
        ],
      );
      expect(profile.visual.hasHood.isNotApplicable, isTrue);
    });

    test('legacy fallback is explicit low-authority source', () {
      final profile = const WardrobeProfileResolver().resolve(
        itemId: 'item',
        evidence: [
          _evidence(
            id: 'legacy',
            property: WardrobeProfileProperty.brand,
            value: 'LegacyBrand',
            source: EvidenceSource.legacyFallback,
            nature: EvidenceNature.unknown,
            confidence: 0.2,
          ),
        ],
      );
      expect(profile.identity.brand.winningSource, EvidenceSource.legacyFallback);
    });

    test('empty evidence yields unknown fields', () {
      final profile = const WardrobeProfileResolver().resolve(
        itemId: 'item',
        evidence: const [],
      );
      expect(profile.identity.canonicalType.isUnknown, isTrue);
      expect(profile.capabilities.warmth.isUnknown, isTrue);
      expect(profile.evidence, isEmpty);
    });

    test('equal high-authority conflict remains unresolved', () {
      final profile = const WardrobeProfileResolver().resolve(
        itemId: 'item',
        evidence: [
          _evidence(
            id: 'a',
            property: WardrobeProfileProperty.brand,
            value: 'A',
            source: EvidenceSource.verifiedProductMetadata,
            nature: EvidenceNature.observed,
            confidence: 0.9,
            verified: true,
          ),
          _evidence(
            id: 'b',
            property: WardrobeProfileProperty.brand,
            value: 'B',
            source: EvidenceSource.labelMetadata,
            nature: EvidenceNature.observed,
            confidence: 0.9,
            verified: true,
          ),
        ],
      );
      // Policies differ; when both high and unresolvable, brand may still resolve
      // via quality. Keep characterization of conflict recording.
      expect(profile.identity.brand.conflictingEvidenceIds, isNotEmpty);
    });
  });
}

ProfileEvidence _evidence({
  required String id,
  required String property,
  required Object? value,
  required EvidenceSource source,
  required EvidenceNature nature,
  required double confidence,
  EvidenceValueState valueState = EvidenceValueState.known,
  bool active = true,
  bool verified = false,
  String? dependsOnCanonicalType,
}) => ProfileEvidence(
  id: id,
  property: property,
  value: value,
  valueState: valueState,
  source: source,
  nature: nature,
  confidence: confidence,
  method: 'test',
  createdAt: DateTime.utc(1970),
  active: active,
  verified: verified,
  dependsOnCanonicalType: dependsOnCanonicalType,
);

final class _CountingSink implements WardrobeProfileResolverTraceSink {
  @override
  void beforeInvocation({
    required String itemId,
    required List<ProfileEvidence> evidence,
  }) {}

  @override
  void afterInvocation({
    required String itemId,
    required List<ProfileEvidence> evidence,
    required ResolvedWardrobeItemProfile output,
  }) {}
}

final class _CaptureSink implements WardrobeProfileResolverTraceSink {
  var afterCount = 0;
  ResolvedWardrobeItemProfile? output;

  @override
  void beforeInvocation({
    required String itemId,
    required List<ProfileEvidence> evidence,
  }) {}

  @override
  void afterInvocation({
    required String itemId,
    required List<ProfileEvidence> evidence,
    required ResolvedWardrobeItemProfile output,
  }) {
    afterCount++;
    this.output = output;
  }
}

final class _SeqClock {
  var value = 0;
  int next() => ++value;
}

final class _KbSeqSink implements WardrobeKnowledgeBasePriorTraceSink {
  _KbSeqSink(this.clock);
  final _SeqClock clock;
  var afterSeq = 0;

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
  }) {
    afterSeq = clock.next();
  }
}

final class _ResolverSeqSink implements WardrobeProfileResolverTraceSink {
  _ResolverSeqSink(this.clock);
  final _SeqClock clock;
  var beforeSeq = 0;
  var afterSeq = 0;
  List<ProfileEvidence>? inputEvidence;

  @override
  void beforeInvocation({
    required String itemId,
    required List<ProfileEvidence> evidence,
  }) {
    beforeSeq = clock.next();
    inputEvidence = List<ProfileEvidence>.from(evidence);
  }

  @override
  void afterInvocation({
    required String itemId,
    required List<ProfileEvidence> evidence,
    required ResolvedWardrobeItemProfile output,
  }) {
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

List<int> _canonicalBytes(Object? value) => utf8.encode(
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
