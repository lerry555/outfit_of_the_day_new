import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/export_backend_qualification_goldens.dart' as exporter;

const _capturedFixtureIds = {
  'cropped_upper',
  'cropped_lower',
  'fabric_detail_only',
  'front_only_garment',
  'shoe_without_outsole',
  'dark_low_contrast',
  'blurred_item',
  'conflicting_multi_view',
};

void main() {
  test('captured fixtures export through the authoritative Dart pipeline', () {
    const update = bool.fromEnvironment('UPDATE_QUALIFICATION_GOLDENS');
    final manifest = File(
      'test/fixtures/backend_qualification_golden_manifest.json',
    );
    final beforeParsers = _parserHashes();
    final result = exporter.exportCapturedQualificationGoldens(
      manifestFile: manifest,
      fixtureIds: _capturedFixtureIds,
      write: update,
      preflightOnly: !update,
    );
    expect(result.fixtureIds.toSet(), _capturedFixtureIds);
    expect(_parserHashes(), beforeParsers);

    if (!update) return;
    final decoded = jsonDecode(manifest.readAsStringSync()) as Map;
    final fixtures = (decoded['fixtures'] as List).cast<Map>();
    final ready = fixtures
        .where((item) => item['goldenStatus'] == 'ready')
        .map((item) => item['id'])
        .toSet();
    expect(ready, containsAll(_capturedFixtureIds));
    expect(ready.length, 8);
    for (final id in _capturedFixtureIds) {
      final input = File(
        'test/fixtures/backend_qualification/input/$id.input.json',
      );
      final reference = File(
        'test/fixtures/backend_qualification/dart_reference/'
        '$id.reference.json',
      );
      expect(input.existsSync(), isTrue, reason: id);
      expect(reference.existsSync(), isTrue, reason: id);
      final inputMap = jsonDecode(input.readAsStringSync()) as Map;
      expect(
        (inputMap['additionalResponses'] as List?)?.length ?? 0,
        id == 'conflicting_multi_view' ? 1 : 0,
      );
    }
  });
}

Map<String, int> _parserHashes() => {
  for (final file in Directory(
    'test/fixtures/backend_qualification/parser',
  ).listSync().whereType<File>())
    file.path: Object.hashAll(file.readAsBytesSync()),
};
