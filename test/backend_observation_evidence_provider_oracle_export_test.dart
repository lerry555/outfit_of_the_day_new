import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

import '../tool/export_observation_evidence_provider_oracles.dart' as exporter;

void main() {
  test(
    'exports authoritative observation evidence provider oracles offline',
    () {
      const update = bool.fromEnvironment('UPDATE_PROVIDER_ORACLES');
      final repositoryRoot = Directory.current;
      final protectedBefore = _protectedHashes(repositoryRoot);
      final result = exporter.exportObservationEvidenceProviderOracles(
        repositoryRoot: repositoryRoot,
        write: update,
      );
      expect(result.ready, 8);
      expect(result.sourceMissing, 8);
      expect(result.invocationCount, 8);
      expect(result.oracleSha256ByScenario, hasLength(8));
      expect(_protectedHashes(repositoryRoot), protectedBefore);

      if (update) {
        final oracleDirectory = Directory(
          'test/fixtures/backend_qualification/provider_oracles/'
          'vision_observation_evidence_v1',
        );
        expect(
          oracleDirectory.listSync().whereType<File>().where(
            (file) => file.path.endsWith('.oracle.json'),
          ),
          hasLength(8),
        );
        expect(
          File(exporter.oracleManifestPath).readAsBytesSync(),
          result.manifestBytes,
        );
      }
    },
  );

  test(
    'exporter and observer boundary have no network or persistence imports',
    () {
      final exporterSource = File(
        'tool/export_observation_evidence_provider_oracles.dart',
      ).readAsStringSync();
      final orchestratorSource = File(
        'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
      ).readAsStringSync();
      expect(exporterSource, isNot(contains('package:http')));
      expect(exporterSource, isNot(contains('firebase')));
      expect(exporterSource, isNot(contains('Firestore')));
      expect(exporterSource, isNot(contains('Storage')));
      expect(exporterSource, isNot(contains('DateTime.now')));
      expect(exporterSource, isNot(contains('Random(')));
      expect(
        exporterSource,
        isNot(contains('QualifiedVisionPersistenceMapper')),
      );
      expect(exporterSource, isNot(contains('PersistenceCodec')));
      expect(
        RegExp(
          r'observationEvidenceTraceSink\?\.beforeInvocation\(input\);'
          r'[\s\S]*VisionObservationEvidenceProvider\(\)\.provide\(input\);'
          r'[\s\S]*observationEvidenceTraceSink\?\.afterInvocation\(input, output\);',
        ).hasMatch(orchestratorSource),
        isTrue,
      );
    },
  );

  test('passive observer does not change qualification output', () {
    final fixture = File(
      'test/fixtures/backend_qualification/parser/'
      'front_only_garment.parser.json',
    ).readAsStringSync();
    final taxonomy = File(
      'lib/data/clothing_knowledge_base.dart',
    ).readAsStringSync();
    final allowed = RegExp(
      r"canonicalType:\s*'([^']+)'",
    ).allMatches(taxonomy).map((match) => match.group(1)!).toSet();
    final response = const VisionParserFixtureReplay()
        .decodeResponses(fixture, allowedCanonicalTypes: allowed)
        .single;
    final baseline = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'front_only_garment',
      response: response,
    );
    final trace = _PassiveTrace();
    final observed = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'front_only_garment',
      response: response,
      observationEvidenceTraceSink: trace,
    );
    expect(trace.before, 1);
    expect(trace.after, 1);
    expect(trace.sameInputIdentity, isTrue);
    expect(observed.toMap(), baseline.toMap());
  });
}

final class _PassiveTrace implements VisionObservationEvidenceTraceSink {
  int before = 0;
  int after = 0;
  ClothingObservationBundle? input;
  bool sameInputIdentity = false;

  @override
  void beforeInvocation(ClothingObservationBundle input) {
    before++;
    this.input = input;
  }

  @override
  void afterInvocation(
    ClothingObservationBundle input,
    List<ProfileEvidence> output,
  ) {
    after++;
    sameInputIdentity = identical(this.input, input);
  }
}

Map<String, int> _protectedHashes(Directory root) {
  final paths = <File>[
    File('test/fixtures/backend_qualification_capture_manifest.json'),
    File('test/fixtures/backend_qualification_golden_manifest.json'),
    ..._files('test/fixtures/backend_qualification/parser'),
    ..._files('test/fixtures/backend_qualification/input'),
    ..._files('test/fixtures/backend_qualification/dart_reference'),
    ..._files('test/fixtures/vision_v2_assets/current_pipeline_assets_v1'),
  ];
  return {
    for (final file in paths)
      file.absolute.path: Object.hashAll(file.readAsBytesSync()),
  };
}

List<File> _files(String path) =>
    Directory(path).listSync(recursive: true).whereType<File>().toList()
      ..sort((left, right) => left.path.compareTo(right.path));
