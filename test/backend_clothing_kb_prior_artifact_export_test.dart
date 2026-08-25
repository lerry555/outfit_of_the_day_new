import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/export_clothing_knowledge_base_prior_artifact.dart' as exporter;

void main() {
  test(
    'clothing KB prior artifact is deterministic and dual-export identical',
    () {
      const update = bool.fromEnvironment('UPDATE_CLOTHING_KB_PRIOR_ARTIFACT');
      final first = exporter.exportClothingKnowledgeBasePriorArtifact(
        repositoryRoot: Directory.current,
        write: update,
      );
      final second = exporter.exportClothingKnowledgeBasePriorArtifact(
        repositoryRoot: Directory.current,
        write: false,
      );
      expect(first['artifactBytes'], second['artifactBytes']);
      expect(first['manifestBytes'], second['manifestBytes']);
      expect(first['artifactContentSha256'], second['artifactContentSha256']);
      expect((first['itemCount'] as int) > 0, isTrue);
    },
  );

  test('artifact schema and integrity bindings hold when present', () {
    final artifactFile = File(exporter.clothingKbPriorArtifactPath);
    final manifestFile = File(exporter.clothingKbPriorArtifactManifestPath);
    if (!artifactFile.existsSync() || !manifestFile.existsSync()) return;

    final artifactBytes = artifactFile.readAsBytesSync();
    final contentSha = sha256.convert(artifactBytes).toString();
    final manifest = _object(jsonDecode(manifestFile.readAsStringSync()));
    expect(manifest['status'], 'artifact_ready');
    expect(manifest['artifactId'], exporter.clothingKbPriorArtifactId);
    expect(
      manifest['artifactVersion'],
      exporter.clothingKbPriorArtifactVersion,
    );
    expect(
      manifest['schemaVersion'],
      exporter.clothingKbPriorArtifactSchemaVersion,
    );
    expect(manifest['artifactContentSha256'], contentSha);
    expect(
      sha256
          .convert(
            File('lib/data/clothing_knowledge_base.dart').readAsBytesSync(),
          )
          .toString(),
      manifest['sourceDartSha256'],
    );
    expect(
      sha256
          .convert(
            File(
              'tool/export_clothing_knowledge_base_prior_artifact.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['exporterImplementationSha256'],
    );

    final artifact = _object(jsonDecode(utf8.decode(artifactBytes)));
    expect(
      artifact['schemaVersion'],
      exporter.clothingKbPriorArtifactSchemaVersion,
    );
    expect(artifact.containsKey('items'), isTrue);
    final items = _list(artifact['items']).map(_object).toList();
    expect(items, isNotEmpty);
    final canonicals = <String>{};
    final aliases = <String>{};
    for (final item in items) {
      final canonical = item['canonicalType']! as String;
      expect(canonicals.add(canonical), isTrue, reason: 'dup:$canonical');
      expect(item.containsKey('skName'), isFalse);
      expect(item.containsKey('mainCategory'), isTrue);
      expect(item.containsKey('warmthDefault'), isTrue);
      expect(item.containsKey('formalityDefault'), isTrue);
      for (final alias in (_list(item['aliases'])).cast<String>()) {
        final key = alias.trim().toLowerCase();
        if (key.isEmpty || canonicals.contains(key)) continue;
        expect(aliases.add(key), isTrue, reason: 'dup alias:$alias');
      }
    }
    final encoded = utf8.decode(artifactBytes);
    expect(encoded, isNot(contains(r'C:\')));
    expect(encoded, isNot(contains('/Users/')));
    expect(encoded.contains(RegExp(r'"\d{4}-\d{2}-\d{2}T')), isFalse);
    expect(encoded, isNot(contains('debugPrint')));
    expect(_list(artifact['excludedFromArtifact']), contains('skName'));
    expect(_list(artifact['excludedFromArtifact']), contains('categoryLabels'));
    for (final item in items) {
      expect(item.keys, isNot(contains('skName')));
      expect(item.keys, isNot(contains('categoryLabels')));
    }
  });

  test('artifact round-trips through canonical JSON without mutation', () {
    final artifactFile = File(exporter.clothingKbPriorArtifactPath);
    if (!artifactFile.existsSync()) return;
    final original = artifactFile.readAsBytesSync();
    final parsed = jsonDecode(utf8.decode(original));
    final rewritten = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(_canonicalize(parsed))}\n',
    );
    expect(rewritten, original);
  });
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw FormatException('expected_object');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _list(Object? value) {
  if (value is! List) throw FormatException('expected_list');
  return List<Object?>.from(value);
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((item) => item.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalize(value[key])};
  }
  if (value is List) return value.map(_canonicalize).toList();
  if (value is double && value == 0) return 0;
  return value;
}
