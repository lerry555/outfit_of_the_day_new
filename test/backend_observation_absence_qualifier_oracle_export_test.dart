import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/observation_absence_qualifier.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

import '../tool/export_observation_absence_qualifier_oracles.dart' as exporter;

void main() {
  test('captures exact absence-qualifier boundary deterministically', () {
    const update = bool.fromEnvironment('UPDATE_OBSERVATION_ABSENCE_ORACLES');
    final first = exporter.exportObservationAbsenceQualifierOracles(
      repositoryRoot: Directory.current,
      write: update,
    );
    final second = exporter.exportObservationAbsenceQualifierOracles(
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
    if (File(exporter.observationAbsenceOracleManifestPath).existsSync()) {
      expect(
        File(exporter.observationAbsenceOracleManifestPath).readAsBytesSync(),
        first['manifestBytes'],
      );
    }
  });

  test('manifest and every ready oracle are SHA bound', () {
    final manifestFile = File(exporter.observationAbsenceOracleManifestPath);
    if (!manifestFile.existsSync()) return;
    final manifest = _object(jsonDecode(manifestFile.readAsStringSync()));
    expect(manifest['providerId'], exporter.observationAbsenceProviderId);
    expect(
      manifest['providerVersion'],
      exporter.observationAbsenceProviderVersion,
    );
    expect(manifest['scenarioCount'], 16);
    expect(manifest['readyScenarioCount'], 8);
    expect(manifest['invocationCount'], 8);
    expect(
      sha256
          .convert(
            File(
              'lib/domain/wardrobe_profile/observation_absence_qualifier.dart',
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
              'tool/export_observation_absence_qualifier_oracles.dart',
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
      expect(oracle['providerId'], exporter.observationAbsenceProviderId);
      expect(
        oracle['callSitePreparationSha256'],
        manifest['callSitePreparationSha256'],
      );
      expect(
        oracle['providerImplementationSha256'],
        manifest['providerImplementationSha256'],
      );
      expect(
        oracle['sourceParserFixtureSha256'],
        entry['sourceParserFixtureSha256'],
      );
      final invocations = _list(oracle['invocations']).map(_object).toList();
      expect(invocations, hasLength(1));
      final invocation = invocations.single;
      expect(
        invocation['invocationId'],
        '${entry['scenarioId']}::observation-absence-qualifier',
      );
      expect(
        sha256.convert(_bytes(invocation['providerInput'])).toString(),
        invocation['providerInputSha256'],
      );
      expect(
        sha256.convert(_bytes(invocation['providerOutput'])).toString(),
        invocation['providerOutputSha256'],
      );
    }
  });

  test('input ordering and null versus omitted encoding are stable', () {
    final manifestFile = File(exporter.observationAbsenceOracleManifestPath);
    if (!manifestFile.existsSync()) return;
    final manifest = _object(jsonDecode(manifestFile.readAsStringSync()));
    final ready = _list(
      manifest['fixtures'],
    ).map(_object).where((item) => item['status'] == 'ready');
    for (final entry in ready) {
      final oracle = _object(
        jsonDecode(
          File(
            'test/fixtures/${entry['oraclePath'] as String}',
          ).readAsStringSync(),
        ),
      );
      final invocation = _object(_list(oracle['invocations']).single);
      final input = _object(invocation['providerInput']);
      final output = _object(invocation['providerOutput']);
      expect(input.keys.toList(), ['bundles']);
      expect(_list(input['bundles']), isNotEmpty);
      expect(output.containsKey('qualifiedBundle'), isTrue);
      for (final property in const [
        'visiblePocketStructure',
        'hasHood',
        'frontClosure',
        'visibleStretchCue',
      ]) {
        final audit = _object(output[property]);
        expect(audit['property'], property);
        expect(audit.containsKey('disposition'), isTrue);
        expect(audit.containsKey('reasonCodes'), isTrue);
        expect(audit.containsKey('raw'), isTrue);
        expect(audit.containsKey('qualified'), isTrue);
        final disposition = audit['disposition'];
        expect(
          [
            'unchanged',
            'qualified',
            'degradedToUnknown',
            'degradedToNotVisible',
            'conflict',
          ].contains(disposition),
          isTrue,
          reason: '$property:$disposition',
        );
      }
      expect(_bytes(input), _bytes(jsonDecode(utf8.decode(_bytes(input)))));
      expect(_bytes(output), _bytes(jsonDecode(utf8.decode(_bytes(output)))));
    }
  });

  test(
    'output occurs before ObservationEvidenceProvider and excludes evidence',
    () {
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
      final absence = _AbsenceCapture();
      final evidence = _EvidenceCapture();
      const VisionV2ShadowOrchestrator().analyze(
        itemId: 'front_only_garment',
        response: responses.first,
        additionalResponses: responses.skip(1),
        multiViewSubjectBinding: binding,
        observationAbsenceQualificationTraceSink: absence,
        observationEvidenceTraceSink: evidence,
      );
      expect(absence.beforeCount, 1);
      expect(absence.afterCount, 1);
      expect(evidence.beforeCount, 1);
      expect(absence.afterSeq, lessThan(evidence.beforeSeq));
      expect(absence.output, isNotNull);
      expect(absence.output!.containsKey('qualifiedBundle'), isTrue);
      expect(absence.output!.containsKey('visiblePocketStructure'), isTrue);
      expect(
        jsonEncode(absence.output!),
        isNot(contains('vision-observation:')),
      );
      expect(jsonEncode(absence.output!), isNot(contains('ProfileEvidence')));
      expect(evidence.input!.analysisId, absence.bundles!.first.analysisId);
    },
  );

  test('observer is optional passive and immediately wraps provider call', () {
    final source = File(
      'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('observationAbsenceQualificationTraceSink?.beforeInvocation'),
    );
    expect(source, contains('ObservationAbsenceQualifier().qualifyBundles'));
    expect(
      source,
      contains('observationAbsenceQualificationTraceSink?.afterInvocation'),
    );
    expect(source, contains('VisionObservationEvidenceProvider().provide'));
    expect(
      source.indexOf(
        'observationAbsenceQualificationTraceSink?.beforeInvocation',
      ),
      lessThan(source.indexOf('ObservationAbsenceQualifier().qualifyBundles')),
    );
    expect(
      source.indexOf('ObservationAbsenceQualifier().qualifyBundles'),
      lessThan(
        source.indexOf(
          'observationAbsenceQualificationTraceSink?.afterInvocation',
        ),
      ),
    );
    expect(
      source.indexOf(
        'observationAbsenceQualificationTraceSink?.afterInvocation',
      ),
      lessThan(source.indexOf('VisionObservationEvidenceProvider().provide')),
    );
  });

  test('exporter and observer remain offline and production isolated', () {
    final exporterSource = File(
      'tool/export_observation_absence_qualifier_oracles.dart',
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
    expect(production, isNot(contains('ObservationAbsenceQualifier')));
    expect(production, isNot(contains('observation_absence_qualifier')));
    expect(production, isNot(contains('qualifyAbsenceBundles')));
    expect(
      File('functions/observation_absence_qualifier.js').existsSync(),
      isTrue,
    );
    expect(
      File('functions/backend_observation_absence_parity.js').existsSync(),
      isTrue,
    );
    expect(
      File('functions/index.js').readAsStringSync(),
      isNot(contains("require('./observation_absence_qualifier")),
    );
    expect(
      File('functions/vision_v2_shadow.js').readAsStringSync(),
      isNot(contains("require('./observation_absence_qualifier")),
    );
  });

  test('conflicting multi-view remains one scenario-level invocation', () {
    final oracleFile = File(
      'test/fixtures/backend_qualification/provider_oracles/'
      'observation_absence_qualifier_v1/conflicting_multi_view.oracle.json',
    );
    if (!oracleFile.existsSync()) return;
    final oracle = _object(jsonDecode(oracleFile.readAsStringSync()));
    final invocation = _object(_list(oracle['invocations']).single);
    expect(
      invocation['invocationId'],
      'conflicting_multi_view::observation-absence-qualifier',
    );
    expect(invocation['viewCount'], 2);
    expect(_list(invocation['orderedViewIds']), ['view_1', 'view_2']);
    expect(
      _list(_object(invocation['providerInput'])['bundles']),
      hasLength(2),
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
    'lib/domain/wardrobe_profile/observation_absence_qualifier.dart',
  ]) {
    input.add(utf8.encode(File(path).uri.pathSegments.last));
    input.add(const <int>[0]);
    input.add(File(path).readAsBytesSync());
    input.add(const <int>[0]);
  }
  return sha256.convert(input.takeBytes()).toString();
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

final class _AbsenceCapture
    implements ObservationAbsenceQualificationTraceSink {
  int beforeCount = 0;
  int afterCount = 0;
  int afterSeq = 0;
  List<ClothingObservationBundle>? bundles;
  Map<String, Object?>? output;
  static int _seq = 0;

  @override
  void beforeInvocation({required List<ClothingObservationBundle> bundles}) {
    beforeCount++;
    this.bundles = List.unmodifiable(bundles);
  }

  @override
  void afterInvocation({
    required List<ClothingObservationBundle> bundles,
    required ObservationAbsenceQualificationReport output,
  }) {
    afterCount++;
    afterSeq = ++_seq;
    this.output = {
      'qualifiedBundle': output.qualifiedBundle.toMap(),
      ...output.toMap(),
    };
  }
}

final class _EvidenceCapture implements VisionObservationEvidenceTraceSink {
  int beforeCount = 0;
  int beforeSeq = 0;
  ClothingObservationBundle? input;

  @override
  void beforeInvocation(ClothingObservationBundle input) {
    beforeCount++;
    beforeSeq = ++_AbsenceCapture._seq;
    this.input = input;
  }

  @override
  void afterInvocation(
    ClothingObservationBundle input,
    List<ProfileEvidence> output,
  ) {}
}
