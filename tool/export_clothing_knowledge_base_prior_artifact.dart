import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/data/clothing_knowledge_base.dart';

/// Deterministic Clothing Knowledge Base prior artifact for backend authority.
///
/// Exports only declarative [ClothingKbItem] fields used by
/// [WardrobeKnowledgeBasePriorProvider]. Excludes Flutter/UI helpers,
/// display labels, and debug log helpers.
const clothingKbPriorArtifactSchemaVersion = 1;
const clothingKbPriorArtifactId = 'ClothingKnowledgeBasePriorArtifact';
const clothingKbPriorArtifactVersion = 'clothing-kb-prior-artifact-v1';
const clothingKbPriorArtifactPath =
    'test/fixtures/backend_qualification/artifacts/'
    'clothing_knowledge_base_prior_v1.json';
const clothingKbPriorArtifactManifestPath =
    'test/fixtures/backend_qualification/'
    'backend_clothing_kb_prior_artifact_manifest.json';

Map<String, Object?> exportClothingKnowledgeBasePriorArtifact({
  required Directory repositoryRoot,
  required bool write,
}) {
  final kbSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}data${Platform.pathSeparator}'
    'clothing_knowledge_base.dart',
  );
  final exporterSource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}tool'
    '${Platform.pathSeparator}export_clothing_knowledge_base_prior_artifact.dart',
  );
  final items =
      ClothingKnowledgeBase.allItems
          .map(
            (item) => <String, Object?>{
              'canonicalType': item.canonicalType,
              'mainCategory': item.mainCategory,
              'category': item.category,
              'subcategory': item.subcategory,
              'layerRole': item.layerRole,
              'warmthDefault': item.warmthDefault,
              'formalityDefault': item.formalityDefault,
              'aliases': [...item.aliases]..sort(),
              // skName is display-only for wardrobe UI; omitted from prior artifact.
            },
          )
          .toList()
        ..sort(
          (left, right) => (left['canonicalType']! as String).compareTo(
            right['canonicalType']! as String,
          ),
        );
  final seenCanonical = <String>{};
  final seenAliases = <String>{};
  for (final item in items) {
    final canonical = item['canonicalType']! as String;
    if (!seenCanonical.add(canonical)) {
      throw FormatException('duplicate_canonical_key:$canonical');
    }
    for (final alias in (item['aliases']! as List).cast<String>()) {
      final key = alias.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (seenCanonical.contains(key)) continue;
      if (!seenAliases.add(key)) {
        throw FormatException('duplicate_alias_key:$alias');
      }
    }
  }
  final artifact = <String, Object?>{
    'schemaVersion': clothingKbPriorArtifactSchemaVersion,
    'artifactId': clothingKbPriorArtifactId,
    'artifactVersion': clothingKbPriorArtifactVersion,
    'sourceDartPath': 'lib/data/clothing_knowledge_base.dart',
    'sourceDartSha256': _shaFile(kbSource),
    'itemCount': items.length,
    'items': items,
    'lookupPolicy': <String, Object?>{
      'canonical': 'exact_normalized_key',
      'alias': 'exact_normalized_key',
      'normalization':
          'trim_lower_case_strip_diacritics_collapse_separators_dart_parity',
    },
    'providerFields': const [
      'canonicalType',
      'mainCategory',
      'category',
      'subcategory',
      'layerRole',
      'warmthDefault',
      'formalityDefault',
      'aliases',
    ],
    'excludedFromArtifact': const [
      'skName',
      'categoryLabels',
      'wardrobeDisplayHelpers',
      'debugLogHelpers',
      'flutterFoundationImport',
    ],
  };
  final artifactBytes = _bytes(artifact);
  final contentSha = sha256.convert(artifactBytes).toString();
  final manifest = <String, Object?>{
    'manifestVersion': 1,
    'kind': 'kb_artifact',
    'status': 'artifact_ready',
    'artifactId': clothingKbPriorArtifactId,
    'artifactVersion': clothingKbPriorArtifactVersion,
    'schemaVersion': clothingKbPriorArtifactSchemaVersion,
    'artifactPath': clothingKbPriorArtifactPath.replaceFirst(
      'test/fixtures/',
      '',
    ),
    'artifactContentSha256': contentSha,
    'sourceDartPath': 'lib/data/clothing_knowledge_base.dart',
    'sourceDartSha256': _shaFile(kbSource),
    'exporterImplementationSha256': _shaFile(exporterSource),
    'itemCount': items.length,
    'generationCommand':
        'flutter test --dart-define=UPDATE_CLOTHING_KB_PRIOR_ARTIFACT=true '
        'test/backend_clothing_kb_prior_artifact_export_test.dart',
    'orderingPolicy': <String, Object?>{
      'items': 'canonical_type_lexicographic',
      'aliases': 'lexicographic',
      'mapKeys': 'canonical_json_lexicographic',
    },
  };
  final manifestBytes = _bytes(manifest);
  if (write) {
    _write(
      File(
        '${repositoryRoot.path}${Platform.pathSeparator}'
        '${clothingKbPriorArtifactPath.replaceAll('/', Platform.pathSeparator)}',
      ),
      artifactBytes,
    );
    _write(
      File(
        '${repositoryRoot.path}${Platform.pathSeparator}'
        '${clothingKbPriorArtifactManifestPath.replaceAll('/', Platform.pathSeparator)}',
      ),
      manifestBytes,
    );
  }
  return <String, Object?>{
    'itemCount': items.length,
    'artifactBytes': artifactBytes,
    'manifestBytes': manifestBytes,
    'artifactContentSha256': contentSha,
    'sourceDartSha256': _shaFile(kbSource),
    'exporterImplementationSha256': _shaFile(exporterSource),
  };
}

List<int> _bytes(Object? value) => utf8.encode(
  '${const JsonEncoder.withIndent('  ').convert(_canonicalize(value))}\n',
);

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((item) => item.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalize(value[key])};
  }
  if (value is List) return value.map(_canonicalize).toList();
  if (value is double && value == 0) return 0;
  return value;
}

String _shaFile(File file) => sha256.convert(file.readAsBytesSync()).toString();

void _write(File file, List<int> bytes) {
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}
