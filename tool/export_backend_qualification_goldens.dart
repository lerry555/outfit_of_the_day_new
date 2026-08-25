import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/qualified_vision_persistence_mapper.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_codec.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_contract.dart';

const _manifestPath =
    'test/fixtures/backend_qualification_golden_manifest.json';
const _missingParserFixture = 'missing_validated_parser_fixture';

final class GoldenExportResult {
  const GoldenExportResult({
    required this.ready,
    required this.pendingById,
    required this.manifestBytes,
  });

  final int ready;
  final Map<String, String> pendingById;
  final List<int> manifestBytes;

  int get pending => pendingById.length;
}

final class CapturedGoldenExportResult {
  const CapturedGoldenExportResult({
    required this.fixtureIds,
    required this.sha256ByPath,
    required this.manifestBytes,
  });

  final List<String> fixtureIds;
  final Map<String, String> sha256ByPath;
  final List<int> manifestBytes;
}

/// Runs the existing Dart qualification implementation over captured parser
/// fixtures only. This code has no network, Firebase, repository, or platform
/// imports; parser fixtures are its sole Vision input.
CapturedGoldenExportResult exportCapturedQualificationGoldens({
  required File manifestFile,
  required Set<String> fixtureIds,
  bool write = true,
  bool preflightOnly = false,
}) {
  final manifest = _readObject(manifestFile);
  final captureRelative = _text(
    manifest['captureManifest'],
    'golden_manifest.captureManifest',
  );
  final captureFile = _relativeFile(manifestFile, captureRelative);
  final capture = _readObject(captureFile);
  final goldenById = <String, Map<String, Object?>>{
    for (final raw in _list(manifest['fixtures'], 'golden.fixtures'))
      _text(_object(raw, 'golden.fixture')['id'], 'golden.fixture.id'): _object(
        raw,
        'golden.fixture',
      ),
  };
  final captured = <String, Map<String, Object?>>{};
  for (final raw in _list(capture['fixtures'], 'capture.fixtures')) {
    final entry = _object(raw, 'capture.fixture');
    captured[_text(entry['id'], 'capture.fixture.id')] = entry;
  }
  final requested = fixtureIds.toList()..sort();
  final artifacts = <String, ({List<int> input, List<int> reference})>{};
  for (final id in requested) {
    final existing = goldenById[id];
    if (!preflightOnly &&
        existing != null &&
        existing['goldenStatus'] == 'ready') {
      final input = existing['qualificationInput'];
      final reference = existing['dartReference'];
      if (input is String &&
          reference is String &&
          _relativeFile(manifestFile, input).existsSync() &&
          _relativeFile(manifestFile, reference).existsSync()) {
        continue;
      }
      throw FormatException('ready_golden_artifact_missing:$id');
    }
    final entry = captured[id];
    if (entry == null || entry['captureStatus'] != 'captured') {
      throw FormatException('fixture_not_captured:$id');
    }
    final first = _buildCapturedGolden(
      repositoryRoot: manifestFile.parent.parent.parent,
      captureEntry: entry,
    );
    final second = _buildCapturedGolden(
      repositoryRoot: manifestFile.parent.parent.parent,
      captureEntry: entry,
    );
    if (!_sameBytes(first.input, second.input) ||
        !_sameBytes(first.reference, second.reference)) {
      throw FormatException('non_deterministic_export:$id');
    }
    artifacts[id] = first;
  }
  if (preflightOnly) {
    return CapturedGoldenExportResult(
      fixtureIds: List.unmodifiable(requested),
      sha256ByPath: const {},
      manifestBytes: manifestFile.readAsBytesSync(),
    );
  }

  final updatedFixtures = <Map<String, Object?>>[];
  final requestedSet = requested.toSet();
  for (final raw in _list(manifest['fixtures'], 'golden.fixtures')) {
    final entry = _object(raw, 'golden.fixture');
    final id = _text(entry['id'], 'golden.fixture.id');
    if (!requestedSet.contains(id)) {
      updatedFixtures.add(entry);
      continue;
    }
    final inputPath = 'backend_qualification/input/$id.input.json';
    final referencePath =
        'backend_qualification/dart_reference/$id.reference.json';
    updatedFixtures.add({
      'id': id,
      'goldenStatus': 'ready',
      'qualificationInput': inputPath,
      'dartReference': referencePath,
    });
  }
  final output = <String, Object?>{
    'manifestVersion': manifest['manifestVersion'],
    'fixtureContractVersion': manifest['fixtureContractVersion'],
    'captureManifest': captureRelative,
    'sourceCatalog': manifest['sourceCatalog'],
    'referenceProducer': manifest['referenceProducer'],
    'fixtures': updatedFixtures,
  };
  final manifestBytes = utf8.encode('${_prettyCanonicalJson(output)}\n');
  final hashes = <String, String>{};
  if (write) {
    for (final id in requested) {
      final pair = artifacts[id];
      if (pair == null) continue;
      final input = _relativeFile(
        manifestFile,
        'backend_qualification/input/$id.input.json',
      );
      final reference = _relativeFile(
        manifestFile,
        'backend_qualification/dart_reference/$id.reference.json',
      );
      _atomicWrite(input, pair.input);
      _atomicWrite(reference, pair.reference);
      hashes[_portableRelative(manifestFile.parent, input)] = sha256
          .convert(pair.input)
          .toString();
      hashes[_portableRelative(manifestFile.parent, reference)] = sha256
          .convert(pair.reference)
          .toString();
    }
    _atomicWrite(manifestFile, manifestBytes);
  }
  return CapturedGoldenExportResult(
    fixtureIds: List.unmodifiable(requested),
    sha256ByPath: Map.unmodifiable(hashes),
    manifestBytes: List.unmodifiable(manifestBytes),
  );
}

({List<int> input, List<int> reference}) _buildCapturedGolden({
  required Directory repositoryRoot,
  required Map<String, Object?> captureEntry,
}) {
  final id = _text(captureEntry['id'], 'capture.id');
  final fixturePath = _text(captureEntry['parserFixture'], 'capture.fixture');
  final fixture = File(
    '${repositoryRoot.path}${Platform.pathSeparator}'
    '${fixturePath.replaceAll('/', Platform.pathSeparator)}',
  );
  if (!fixture.existsSync()) throw FormatException('fixture_missing:$id');
  final bytes = fixture.readAsBytesSync();
  final declaredHash = captureEntry['parserFixtureSha256'];
  if (declaredHash is! String || declaredHash.isEmpty) {
    throw FormatException('missing_contract_field:parserFixtureSha256:$id');
  }
  if (sha256.convert(bytes).toString() != declaredHash) {
    throw FormatException('parser_fixture_sha256_mismatch:$id');
  }
  final root = _readObject(fixture);
  if (root['fixtureId'] != id ||
      root['captureDataset'] != 'current_pipeline_capture_v1') {
    throw FormatException('fixture_identity_mismatch:$id');
  }
  final provenance = _object(root['captureProvenance'], 'capture.provenance');
  for (final key in [
    'modelIdentifier',
    'promptVersion',
    'pipelineVersion',
    'visionSchemaVersion',
    'parserVersion',
  ]) {
    if (provenance[key] != captureEntry[key]) {
      throw FormatException('fixture_version_mismatch:$id:$key');
    }
  }
  final views = _list(root['views'], 'fixture.views');
  final expectedViews = _list(captureEntry['views'], 'capture.views');
  if (views.length != expectedViews.length) {
    throw FormatException('fixture_view_count_mismatch:$id');
  }
  for (var index = 0; index < views.length; index++) {
    final actual = _object(views[index], 'fixture.view');
    final expected = _object(expectedViews[index], 'capture.view');
    for (final key in ['viewId', 'assetPath', 'assetSha256', 'mimeType']) {
      if (actual[key] != expected[key]) {
        throw FormatException('fixture_view_mismatch:$id:$index:$key');
      }
    }
  }

  const replay = VisionParserFixtureReplay();
  final taxonomySource = File(
    '${repositoryRoot.path}${Platform.pathSeparator}'
    'lib${Platform.pathSeparator}data${Platform.pathSeparator}'
    'clothing_knowledge_base.dart',
  ).readAsStringSync();
  final allowedCanonicalTypes = RegExp(
    r"canonicalType:\s*'([^']+)'",
  ).allMatches(taxonomySource).map((match) => match.group(1)!).toSet();
  final fixtureJson = utf8.decode(bytes);
  final responses = replay.decodeResponses(
    fixtureJson,
    allowedCanonicalTypes: allowedCanonicalTypes,
  );
  final analysis = const VisionV2ShadowOrchestrator().analyze(
    itemId: id,
    response: responses.first,
    additionalResponses: responses.skip(1),
    multiViewSubjectBinding: replay.decodeBinding(fixtureJson),
  );
  final primary = _object(
    _object(views.first, 'fixture.primary')['response'],
    'fixture.primary.response',
  );
  final input = <String, Object?>{
    'contractVersion': 1,
    'analysisId': primary['analysisId'],
    'sourceReference': primary['sourceReference'],
    'modelIdentifier': primary['modelVersion'],
    'visionSchemaVersion': primary['schemaVersion'],
    'observedAt': primary['observedAt'],
    'quality': primary['quality'],
    'subjectAssessment': primary['subjectAssessment'],
    'observations': primary['observations'],
    'identityCandidates': primary['identityCandidates'],
    'validationErrors': primary['validationErrors'],
    if (views.length > 1)
      'additionalResponses': views
          .skip(1)
          .map((view) => _object(_object(view, 'view')['response'], 'response'))
          .toList(growable: false),
  };

  final observedAt = analysis.response.observations.observedAt;
  final mapping = const QualifiedVisionPersistenceMapper().map(
    analysis: analysis,
    context: PersistenceMappingContext(
      generationId: 'fixture:$id',
      revision: 0,
      createdAt: observedAt,
      updatedAt: observedAt,
      imageRevision: 0,
      wardrobeItemRevision: 0,
      analysisId: analysis.response.observations.analysisId,
      analysisKind: WardrobeAnalysisKind.initialAnalysis,
      completedAt: observedAt,
      modelIdentifier: analysis.response.observations.modelVersion,
      pipelineVersion: _text(provenance['pipelineVersion'], 'pipelineVersion'),
      promptVersion: _text(provenance['promptVersion'], 'promptVersion'),
      visionSchemaVersion: analysis.response.schemaVersion,
      qualificationVersion: 'qualification-v1',
    ),
  );
  if (mapping.status ==
          WardrobeProfilePersistenceMappingStatus.mappingFailure ||
      mapping.status ==
          WardrobeProfilePersistenceMappingStatus.incompatibleInput) {
    throw FormatException('mapper_failed:$id:${mapping.reasonCode}');
  }
  final machineEvidence = mapping.envelope == null
      ? <Object?>[]
      : List<Object?>.from(
          const WardrobeProfilePersistenceCodec().toPersistenceMap(
                mapping.envelope!,
              )['machineEvidence']
              as List,
        ).map(_normalizePersistedEvidence).toList(growable: false);
  final omitted = <String>[
    ...mapping.omittedEvidenceReasonCodes,
    if (mapping.reasonCode != null) mapping.reasonCode!,
  ]..sort();
  final reference = <String, Object?>{
    'contractVersion': 1,
    'fixtureId': id,
    'producer': 'dart_vision_v2_shadow_orchestrator',
    'producerVersion': 'qualification-v1',
    'observationEvidence': analysis.observationEvidence
        .map(_runtimeEvidence)
        .toList(growable: false),
    'capabilityEvidence': analysis.capabilityEvidence
        .map(_runtimeEvidence)
        .toList(growable: false),
    'machineEvidence': machineEvidence,
    'omittedReasons': omitted,
    'identityQualification': {
      'tier': analysis.identityQualification.state.wireName,
      if (analysis.identityQualification.selectedCanonicalType != null)
        'selectedCanonicalType':
            analysis.identityQualification.selectedCanonicalType,
    },
    'familyQualification': {
      'tier': analysis.familyIdentity.state.wireName,
      if (analysis.familyIdentity.resolvedFamily != null)
        'family': analysis.familyIdentity.resolvedFamily!.wireName,
    },
  };
  final inputBytes = utf8.encode('${_prettyCanonicalJson(input)}\n');
  final referenceBytes = utf8.encode('${_prettyCanonicalJson(reference)}\n');
  _assertCanonicalRoundTrip(inputBytes, 'input:$id');
  _assertCanonicalRoundTrip(referenceBytes, 'reference:$id');
  return (input: inputBytes, reference: referenceBytes);
}

Map<String, Object?> _runtimeEvidence(ProfileEvidence evidence) => {
  'id': evidence.id,
  'property': evidence.property,
  'value': evidence.value,
  'valueState': evidence.valueState.wireName,
  'source': evidence.source.wireName,
  'nature': evidence.nature.wireName,
  'confidence': evidence.confidence,
  'method': evidence.method,
  'supportingEvidenceIds': <String>[],
};

Map<String, Object?> _normalizePersistedEvidence(Object? raw) {
  final value = _object(raw, 'machineEvidence');
  return {
    'id': value['id'],
    'property': value['property'],
    'value': value['value'],
    'valueState': value['valueState'],
    'source': value['source'],
    'nature': value['nature'],
    'confidence': value['confidence'],
    'method': value['method'],
    'supportingEvidenceIds': value['supportingEvidenceIds'] ?? <String>[],
    if (value['identityQualification'] != null)
      'qualificationTier': value['identityQualification'],
  };
}

GoldenExportResult exportBackendQualificationGoldens({
  required File manifestFile,
  bool write = true,
}) {
  final manifest = _readObject(manifestFile);
  if (manifest['manifestVersion'] != 1) {
    throw const FormatException('golden_manifest_version_unsupported');
  }
  final sourceCatalog = manifest['sourceCatalog'];
  if (sourceCatalog is! String || sourceCatalog.trim().isEmpty) {
    throw const FormatException('source_catalog_required');
  }
  final catalogFile = File(
    '${manifestFile.parent.path}${Platform.pathSeparator}$sourceCatalog',
  );
  final catalog = _readList(catalogFile);
  final captureById = _captureStatusById(manifestFile, manifest);
  final catalogIds = <String>{};
  for (final raw in catalog) {
    final item = _object(raw, 'source_catalog_item');
    final id = _text(item['id'], 'source_catalog_item.id');
    if (!catalogIds.add(id)) {
      throw FormatException('duplicate_source_catalog_id:$id');
    }
  }

  final fixturesRaw = manifest['fixtures'];
  if (fixturesRaw is! List) {
    throw const FormatException('golden_manifest_fixtures_invalid');
  }
  final fixtureIds = <String>{};
  final pending = <String, String>{};
  var ready = 0;
  final fixtures = <Map<String, Object?>>[];

  for (final raw in fixturesRaw) {
    final fixture = _object(raw, 'golden_fixture');
    final id = _text(fixture['id'], 'golden_fixture.id');
    if (!fixtureIds.add(id)) {
      throw FormatException('duplicate_golden_fixture_id:$id');
    }
    if (!catalogIds.contains(id)) {
      throw FormatException('unknown_golden_fixture_id:$id');
    }

    final inputPath = fixture['qualificationInput'];
    final referencePath = fixture['dartReference'];
    final hasInput = inputPath is String && inputPath.trim().isNotEmpty;
    final hasReference =
        referencePath is String && referencePath.trim().isNotEmpty;
    final inputExists =
        hasInput && _relativeFile(manifestFile, inputPath).existsSync();
    final referenceExists =
        hasReference && _relativeFile(manifestFile, referencePath).existsSync();

    if (hasInput && hasReference && inputExists && referenceExists) {
      ready++;
      fixtures.add(<String, Object?>{
        'id': id,
        'goldenStatus': 'ready',
        'qualificationInput': inputPath,
        'dartReference': referencePath,
      });
      continue;
    }

    final reason = hasInput || hasReference
        ? 'incomplete_golden_artifacts'
        : captureById[id] == 'missing_asset'
        ? 'capture_missing_asset'
        : _missingParserFixture;
    pending[id] = reason;
    fixtures.add(<String, Object?>{
      'id': id,
      'goldenStatus': 'pending_dart_export',
      'pendingReason': reason,
    });
  }

  final output = <String, Object?>{
    'manifestVersion': 1,
    'fixtureContractVersion': manifest['fixtureContractVersion'],
    if (manifest['captureManifest'] != null)
      'captureManifest': manifest['captureManifest'],
    'sourceCatalog': sourceCatalog,
    'referenceProducer': manifest['referenceProducer'],
    'fixtures': fixtures,
  };
  final bytes = utf8.encode('${_prettyCanonicalJson(output)}\n');
  if (write) manifestFile.writeAsBytesSync(bytes, flush: true);
  return GoldenExportResult(
    ready: ready,
    pendingById: Map.unmodifiable(pending),
    manifestBytes: List.unmodifiable(bytes),
  );
}

Map<String, String> _captureStatusById(
  File manifestFile,
  Map<String, Object?> manifest,
) {
  final relative = manifest['captureManifest'];
  if (relative is! String || relative.trim().isEmpty) return const {};
  final capture = _readObject(_relativeFile(manifestFile, relative));
  final fixtures = capture['fixtures'];
  if (fixtures is! List) {
    throw const FormatException('capture_manifest_fixtures_invalid');
  }
  final result = <String, String>{};
  for (final raw in fixtures) {
    final item = _object(raw, 'capture_fixture');
    result[_text(item['id'], 'capture_fixture.id')] = _text(
      item['captureStatus'],
      'capture_fixture.captureStatus',
    );
  }
  return result;
}

void main(List<String> arguments) {
  final fixtureArgument = arguments
      .where((item) => item.startsWith('--fixtures='))
      .firstOrNull;
  final allowed = {'--require-all-ready', '--preflight'};
  final unknown = arguments
      .where(
        (item) => !allowed.contains(item) && !item.startsWith('--fixtures='),
      )
      .toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown arguments: ${unknown.join(', ')}');
    exitCode = 64;
    return;
  }
  try {
    if (fixtureArgument != null) {
      final fixtureIds = fixtureArgument
          .substring('--fixtures='.length)
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet();
      if (fixtureIds.isEmpty) {
        throw const FormatException('fixtures_required');
      }
      final result = exportCapturedQualificationGoldens(
        manifestFile: File(_manifestPath),
        fixtureIds: fixtureIds,
        preflightOnly: arguments.contains('--preflight'),
      );
      stdout.writeln(
        jsonEncode({
          'mode': arguments.contains('--preflight') ? 'preflight' : 'export',
          'fixtures': result.fixtureIds,
          'sha256ByPath': result.sha256ByPath,
        }),
      );
      return;
    }
    final result = exportBackendQualificationGoldens(
      manifestFile: File(_manifestPath),
    );
    stdout.writeln(
      jsonEncode({
        'ready': result.ready,
        'pending': result.pending,
        'complete': result.pending == 0,
      }),
    );
    for (final entry in result.pendingById.entries) {
      stdout.writeln('PENDING ${entry.key}: ${entry.value}');
    }
    if (arguments.contains('--require-all-ready') && result.pending > 0) {
      exitCode = 2;
    }
  } on Object catch (error) {
    stderr.writeln('Golden export failed: $error');
    exitCode = 1;
  }
}

File _relativeFile(File manifest, String relativePath) => File(
  '${manifest.parent.path}${Platform.pathSeparator}'
  '${relativePath.replaceAll('/', Platform.pathSeparator)}',
);

Map<String, Object?> _readObject(File file) =>
    _object(jsonDecode(file.readAsStringSync()), file.path);

List<Object?> _readList(File file) {
  final value = jsonDecode(file.readAsStringSync());
  if (value is! List) throw FormatException('${file.path}:expected_list');
  return List<Object?>.from(value);
}

List<Object?> _list(Object? value, String label) {
  if (value is! List) throw FormatException('$label:expected_list');
  return List<Object?>.from(value);
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) throw FormatException('$label:expected_object');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

String _text(Object? value, String label) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$label:required_text');
  }
  return value.trim();
}

String _prettyCanonicalJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(_canonicalize(value));

void _assertCanonicalRoundTrip(List<int> bytes, String label) {
  final decoded = jsonDecode(utf8.decode(bytes));
  final encoded = utf8.encode('${_prettyCanonicalJson(decoded)}\n');
  if (!_sameBytes(bytes, encoded)) {
    throw FormatException('canonical_round_trip_failed:$label');
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _atomicWrite(File target, List<int> bytes) {
  target.parent.createSync(recursive: true);
  final temporary = File('${target.path}.tmp');
  temporary.writeAsBytesSync(bytes, flush: true);
  temporary.renameSync(target.path);
}

String _portableRelative(Directory base, File file) {
  final basePath = base.absolute.path;
  final filePath = file.absolute.path;
  if (!filePath.startsWith(basePath)) {
    throw FormatException('output_outside_fixture_root:${file.path}');
  }
  return filePath
      .substring(basePath.length)
      .replaceFirst(RegExp(r'^[\\/]'), '')
      .replaceAll(r'\', '/');
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalize).toList(growable: false);
  }
  if (value is double && value == 0) return 0;
  return value;
}
