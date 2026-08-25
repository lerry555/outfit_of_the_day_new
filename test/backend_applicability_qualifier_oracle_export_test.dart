import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/export_applicability_qualifier_oracles.dart' as exporter;

void main() {
  test('exports deterministic passive applicability oracles', () {
    const update = bool.fromEnvironment('UPDATE_APPLICABILITY_ORACLES');
    final result = exporter.exportApplicabilityQualifierOracles(
      repositoryRoot: Directory.current,
      write: update,
    );
    expect(result.ready, 8);
    expect(result.sourceMissing, 8);
    expect(result.invocationCount, 9);
    if (update) {
      expect(
        File(exporter.applicabilityOracleManifestPath).readAsBytesSync(),
        result.manifestBytes,
      );
      final files =
          Directory(
            'test/fixtures/backend_qualification/provider_oracles/'
            'vision_applicability_v1',
          ).listSync().whereType<File>().where(
            (file) => file.path.endsWith('.oracle.json'),
          );
      expect(files, hasLength(8));
    }
  });

  test('applicability oracle exporter is offline and non-persistent', () {
    final source = File(
      'tool/export_applicability_qualifier_oracles.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('package:http')));
    expect(source.toLowerCase(), isNot(contains('firebase')));
    expect(source, isNot(contains('DateTime.now')));
    expect(source, isNot(contains('QualifiedVisionPersistenceMapper')));
  });
}
