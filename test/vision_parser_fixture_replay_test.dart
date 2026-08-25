import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';

void main() {
  const replay = VisionParserFixtureReplay();

  test('offline loader rejects a fixture without views', () {
    final fixture = jsonEncode({
      'fixtureContractVersion': 1,
      'captureDataset': 'current_pipeline_capture_v1',
      'fixtureId': 'missing',
      'views': [],
    });
    expect(
      () => replay.decodeResponses(
        fixture,
        allowedCanonicalTypes: const {'t_shirt'},
      ),
      throwsFormatException,
    );
  });

  test('offline loader rejects forbidden resolved or machine output', () {
    for (final key in ['resolvedProfile', 'machineEvidence']) {
      final fixture = jsonEncode({
        'fixtureContractVersion': 1,
        'captureDataset': 'current_pipeline_capture_v1',
        'fixtureId': 'unsafe',
        key: {},
        'views': [
          {'response': {}},
        ],
      });
      expect(
        () => replay.decodeResponses(
          fixture,
          allowedCanonicalTypes: const {'t_shirt'},
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'replay implementation has no network Firebase or Storage dependency',
    () {
      final source = File(
        'lib/domain/wardrobe_profile/vision_parser_fixture_replay.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('http')));
      expect(source, isNot(contains('Firebase')));
      expect(source, isNot(contains('Firestore')));
      expect(source, isNot(contains('Storage')));
    },
  );

  test('all captured fixtures decode and replay offline in manifest order', () {
    final manifest =
        jsonDecode(
              File(
                'test/fixtures/backend_qualification_capture_manifest.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final taxonomySource = File(
      'lib/data/clothing_knowledge_base.dart',
    ).readAsStringSync();
    final allowedCanonicalTypes = RegExp(
      r"canonicalType:\s*'([^']+)'",
    ).allMatches(taxonomySource).map((match) => match.group(1)!).toSet();
    final captured = (manifest['fixtures'] as List)
        .cast<Map<String, dynamic>>()
        .where((item) => item['captureStatus'] == 'captured')
        .toList();
    expect(captured, hasLength(9));
    for (final item in captured) {
      final fixtureJson = File(
        item['parserFixture'] as String,
      ).readAsStringSync();
      final responses = replay.decodeResponses(
        fixtureJson,
        allowedCanonicalTypes: allowedCanonicalTypes,
      );
      expect(responses, hasLength((item['views'] as List).length));
      expect(
        () => replay.replayQualification(
          fixtureJson,
          fixtureId: item['id'] as String,
          allowedCanonicalTypes: allowedCanonicalTypes,
        ),
        returnsNormally,
      );
    }
    final conflicting = captured.singleWhere(
      (item) => item['id'] == 'conflicting_multi_view',
    );
    final conflictingResponses = replay.decodeResponses(
      File(conflicting['parserFixture'] as String).readAsStringSync(),
      allowedCanonicalTypes: allowedCanonicalTypes,
    );
    expect(conflictingResponses, hasLength(2));
    final complementary = captured.singleWhere(
      (item) => item['id'] == 'complementary_multi_view',
    );
    final complementaryResponses = replay.decodeResponses(
      File(complementary['parserFixture'] as String).readAsStringSync(),
      allowedCanonicalTypes: allowedCanonicalTypes,
    );
    expect(complementaryResponses, hasLength(2));
  });
}
