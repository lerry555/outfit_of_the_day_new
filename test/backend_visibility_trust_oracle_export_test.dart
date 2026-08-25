import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/export_visibility_trust_oracles.dart' as exporter;

void main() {
  test('exports passive deterministic visibility trust oracles', () {
    const update = bool.fromEnvironment('UPDATE_VISIBILITY_ORACLES');
    final result = exporter.exportVisibilityTrustOracles(
      repositoryRoot: Directory.current,
      write: update,
    );
    expect(result['ready'], 8);
    expect(result['sourceMissing'], 8);
    expect(result['invocationCount'], 9);
    expect(
      File(exporter.visibilityOracleManifestPath).readAsBytesSync(),
      result['manifestBytes'],
    );
  });

  test('visibility exporter is offline and non-persistent', () {
    final source = File(
      'tool/export_visibility_trust_oracles.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('package:http')));
    expect(source.toLowerCase(), isNot(contains('firebase')));
    expect(source, isNot(contains('DateTime.now')));
    expect(source, isNot(contains('QualifiedVisionPersistenceMapper')));
  });
}
