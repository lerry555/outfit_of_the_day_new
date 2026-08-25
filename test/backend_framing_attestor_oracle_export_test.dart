import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_framing_attestation.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_subject_safety.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_visibility_trust.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

import '../tool/export_framing_attestor_oracles.dart' as exporter;

void main() {
  test('exports deterministic passive framing attestor oracles', () {
    const update = bool.fromEnvironment('UPDATE_FRAMING_ORACLES');
    final result = exporter.exportFramingAttestorOracles(
      repositoryRoot: Directory.current,
      write: update,
    );
    expect(result.ready, 8);
    expect(result.sourceMissing, 8);
    expect(result.invocationCount, 9);
    expect(result.oracleSha256ByScenario, hasLength(8));
    if (update) {
      expect(
        File(exporter.framingOracleManifestPath).readAsBytesSync(),
        result.manifestBytes,
      );
      final directory = Directory(
        'test/fixtures/backend_qualification/provider_oracles/'
        'vision_framing_attestor_v1',
      );
      expect(
        directory.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.oracle.json'),
        ),
        hasLength(8),
      );
    }
  });

  test('framing observer is passive and preserves exact invocation count', () {
    final fixture = File(
      'test/fixtures/backend_qualification/parser/'
      'conflicting_multi_view.parser.json',
    ).readAsStringSync();
    final taxonomy = File(
      'lib/data/clothing_knowledge_base.dart',
    ).readAsStringSync();
    final allowed = RegExp(
      r"canonicalType:\s*'([^']+)'",
    ).allMatches(taxonomy).map((match) => match.group(1)!).toSet();
    final responses = const VisionParserFixtureReplay().decodeResponses(
      fixture,
      allowedCanonicalTypes: allowed,
    );
    final binding = const VisionParserFixtureReplay().decodeBinding(fixture);
    final baseline = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'conflicting_multi_view',
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
    );
    final trace = _PassiveFramingTrace();
    final observed = const VisionV2ShadowOrchestrator().analyze(
      itemId: 'conflicting_multi_view',
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: binding,
      framingAttestationTraceSink: trace,
    );
    expect(trace.before, 2);
    expect(trace.after, 2);
    expect(observed.toMap(), baseline.toMap());
  });

  test('exporter and observer contain no network or persistence boundary', () {
    final exporterSource = File(
      'tool/export_framing_attestor_oracles.dart',
    ).readAsStringSync();
    final productionSource = File(
      'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
    ).readAsStringSync();
    expect(exporterSource, isNot(contains('package:http')));
    expect(exporterSource.toLowerCase(), isNot(contains('firebase')));
    expect(exporterSource, isNot(contains('DateTime.now')));
    expect(exporterSource, isNot(contains('QualifiedVisionPersistenceMapper')));
    expect(
      RegExp(
        r'framingAttestationTraceSink\?\.beforeInvocation\('
        r'[\s\S]*VisionFramingAttestor\(\)\.attest\('
        r'[\s\S]*framingAttestationTraceSink\?\.afterInvocation\(',
      ).hasMatch(productionSource),
      isTrue,
    );
  });
}

final class _PassiveFramingTrace implements VisionFramingAttestationTraceSink {
  int before = 0;
  int after = 0;

  @override
  void beforeInvocation({
    required VisionInputAssessment inputAssessment,
    required VisionSubjectAssessment subject,
    required ObservationImageQuality quality,
    required VisionFramingAttestations? attestations,
  }) {
    before++;
  }

  @override
  void afterInvocation({
    required VisionInputAssessment inputAssessment,
    required VisionSubjectAssessment subject,
    required ObservationImageQuality quality,
    required VisionFramingAttestations? attestations,
    required VisionFramingAttestationReport output,
  }) {
    after++;
  }
}
