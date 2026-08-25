import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/export_canonical_consistency_oracles.dart' as exporter;

void main() {
  test('exports passive deterministic canonical consistency oracles', () {
    const update = bool.fromEnvironment('UPDATE_CANONICAL_CONSISTENCY_ORACLES');
    final result = exporter.exportCanonicalConsistencyOracles(
      repositoryRoot: Directory.current,
      write: update,
    );
    expect(result['ready'], 8);
    expect(result['sourceMissing'], 8);
    expect(result['invocationCount'], 8);
    if (update) {
      expect(
        File(exporter.canonicalConsistencyOracleManifestPath).readAsBytesSync(),
        result['manifestBytes'],
      );
    }
  });

  test('canonical consistency exporter is offline and non-persistent', () {
    final source = File(
      'tool/export_canonical_consistency_oracles.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('package:http')));
    expect(source.toLowerCase(), isNot(contains('firebase')));
    expect(source, isNot(contains('DateTime.now')));
    expect(source, isNot(contains('QualifiedVisionPersistenceMapper')));
  });
}
