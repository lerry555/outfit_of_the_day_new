import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/export_backend_qualification_goldens.dart' as exporter;

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync(
      'backend_qualification_golden_export_',
    );
  });

  tearDown(() {
    temporary.deleteSync(recursive: true);
  });

  File prepare({
    List<Map<String, Object?>> fixtures = const [
      {'id': 'fixture_a', 'goldenStatus': 'pending_dart_export'},
    ],
    List<Map<String, Object?>> catalog = const [
      {'id': 'fixture_a'},
    ],
  }) {
    final fixtureDir = Directory(
      '${temporary.path}${Platform.pathSeparator}fixtures',
    )..createSync();
    File(
      '${fixtureDir.path}${Platform.pathSeparator}catalog.json',
    ).writeAsStringSync(jsonEncode(catalog));
    final manifest =
        File('${fixtureDir.path}${Platform.pathSeparator}manifest.json')
          ..writeAsStringSync(
            jsonEncode({
              'manifestVersion': 1,
              'fixtureContractVersion': 1,
              'sourceCatalog': 'catalog.json',
              'referenceProducer': 'dart_vision_v2_shadow_orchestrator',
              'fixtures': fixtures,
            }),
          );
    return manifest;
  }

  test('missing parser fixture remains pending with explicit reason', () {
    final manifest = prepare();
    final result = exporter.exportBackendQualificationGoldens(
      manifestFile: manifest,
    );
    expect(result.ready, 0);
    expect(result.pending, 1);
    expect(result.pendingById['fixture_a'], 'missing_validated_parser_fixture');
    final decoded = jsonDecode(manifest.readAsStringSync()) as Map;
    expect(
      (decoded['fixtures'] as List).single['pendingReason'],
      'missing_validated_parser_fixture',
    );
  });

  test(
    'two exports are byte-identical with stable key ordering and newline',
    () {
      final manifest = prepare();
      exporter.exportBackendQualificationGoldens(manifestFile: manifest);
      final first = manifest.readAsBytesSync();
      exporter.exportBackendQualificationGoldens(manifestFile: manifest);
      final second = manifest.readAsBytesSync();
      expect(second, first);
      expect(utf8.decode(second).endsWith('\n'), isTrue);
      expect(
        utf8.decode(second).indexOf('"fixtureContractVersion"'),
        lessThan(utf8.decode(second).indexOf('"fixtures"')),
      );
    },
  );

  test('ready requires both existing artifact files', () {
    final manifest = prepare(
      fixtures: [
        {
          'id': 'fixture_a',
          'goldenStatus': 'ready',
          'qualificationInput':
              'backend_qualification/generated/fixture_a.input.json',
          'dartReference':
              'backend_qualification/generated/fixture_a.reference.json',
        },
      ],
    );
    final generated = Directory(
      '${manifest.parent.path}${Platform.pathSeparator}'
      'backend_qualification${Platform.pathSeparator}generated',
    )..createSync(recursive: true);
    File(
      '${generated.path}${Platform.pathSeparator}fixture_a.input.json',
    ).writeAsStringSync('{}');
    final incomplete = exporter.exportBackendQualificationGoldens(
      manifestFile: manifest,
    );
    expect(incomplete.ready, 0);
    expect(incomplete.pendingById['fixture_a'], 'incomplete_golden_artifacts');
  });

  test('existing complete artifact pair remains ready', () {
    final manifest = prepare(
      fixtures: [
        {
          'id': 'fixture_a',
          'goldenStatus': 'ready',
          'qualificationInput':
              'backend_qualification/generated/fixture_a.input.json',
          'dartReference':
              'backend_qualification/generated/fixture_a.reference.json',
        },
      ],
    );
    final generated = Directory(
      '${manifest.parent.path}${Platform.pathSeparator}'
      'backend_qualification${Platform.pathSeparator}generated',
    )..createSync(recursive: true);
    for (final suffix in ['input', 'reference']) {
      File(
        '${generated.path}${Platform.pathSeparator}fixture_a.$suffix.json',
      ).writeAsStringSync('{}');
    }
    final result = exporter.exportBackendQualificationGoldens(
      manifestFile: manifest,
    );
    expect(result.ready, 1);
    expect(result.pending, 0);
  });

  test('duplicate fixture id fails', () {
    final manifest = prepare(
      fixtures: const [
        {'id': 'fixture_a'},
        {'id': 'fixture_a'},
      ],
    );
    expect(
      () => exporter.exportBackendQualificationGoldens(manifestFile: manifest),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'duplicate_golden_fixture_id:fixture_a',
        ),
      ),
    );
  });

  test('unknown fixture id fails', () {
    final manifest = prepare(
      fixtures: const [
        {'id': 'unknown_fixture'},
      ],
    );
    expect(
      () => exporter.exportBackendQualificationGoldens(manifestFile: manifest),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'unknown_golden_fixture_id:unknown_fixture',
        ),
      ),
    );
  });

  test('exporter source has no current time or random ID dependency', () {
    final source = File(
      'tool/export_backend_qualification_goldens.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('DateTime.now')));
    expect(source, isNot(contains('Random(')));
    expect(source.toLowerCase(), isNot(contains('uuid')));
    expect(source, isNot(contains('http')));
  });
}
