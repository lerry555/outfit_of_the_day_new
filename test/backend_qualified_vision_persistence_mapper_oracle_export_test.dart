import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/qualified_vision_persistence_mapper.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_parser_fixture_replay.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_codec.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_persistence_contract.dart';

import '../tool/export_qualified_vision_persistence_mapper_oracles.dart'
    as exporter;

void main() {
  test('offline mapper oracle remains deterministic without production sink', () {
    final taxonomy = File(
      'lib/data/clothing_knowledge_base.dart',
    ).readAsStringSync();
    final allowed = RegExp(
      r"canonicalType:\s*'([^']+)'",
    ).allMatches(taxonomy).map((item) => item.group(1)!).toSet();
    for (final id in const [
      'shoe_without_outsole',
      'front_only_garment',
      'conflicting_multi_view',
    ]) {
      final fixture = File(
        'test/fixtures/backend_qualification/parser/$id.parser.json',
      );
      if (!fixture.existsSync()) continue;
      final fixtureJson = fixture.readAsStringSync();
      final responses = const VisionParserFixtureReplay().decodeResponses(
        fixtureJson,
        allowedCanonicalTypes: allowed,
      );
      final binding = const VisionParserFixtureReplay().decodeBinding(
        fixtureJson,
      );
      final first = const VisionV2ShadowOrchestrator().analyze(
        itemId: id,
        response: responses.first,
        additionalResponses: responses.skip(1),
        multiViewSubjectBinding: binding,
      );
      final second = const VisionV2ShadowOrchestrator().analyze(
        itemId: id,
        response: responses.first,
        additionalResponses: responses.skip(1),
        multiViewSubjectBinding: binding,
      );
      expect(jsonEncode(first.toMap()), jsonEncode(second.toMap()));
      final context = exporter.fixturePersistenceMappingContext(
        scenarioId: id,
        analysis: first,
      );
      const mapper = QualifiedVisionPersistenceMapper();
      final a = mapper.map(analysis: first, context: context);
      final b = mapper.map(analysis: second, context: context);
      expect(
        jsonEncode(exporter.encodeMappingResult(a)),
        jsonEncode(exporter.encodeMappingResult(b)),
      );
    }
  });

  test('captures exact mapper boundary deterministically', () {
    const update = bool.fromEnvironment(
      'UPDATE_QUALIFIED_VISION_PERSISTENCE_MAPPER_ORACLES',
    );
    final first = exporter.exportQualifiedVisionPersistenceMapperOracles(
      repositoryRoot: Directory.current,
      write: update,
    );
    final second = exporter.exportQualifiedVisionPersistenceMapperOracles(
      repositoryRoot: Directory.current,
      write: false,
    );
    expect(first['ready'], 8);
    expect(first['sourceMissing'], 8);
    expect(first['invocationCount'], 8);
    expect(first['manifestBytes'], second['manifestBytes']);
    expect(first['oracleBytesByPath'], second['oracleBytesByPath']);
    if (File(
      exporter.qualifiedVisionPersistenceMapperOracleManifestPath,
    ).existsSync()) {
      expect(
        File(
          exporter.qualifiedVisionPersistenceMapperOracleManifestPath,
        ).readAsBytesSync(),
        first['manifestBytes'],
      );
    }
  });

  test('manifest and every ready oracle are SHA bound', () {
    final manifestFile = File(
      exporter.qualifiedVisionPersistenceMapperOracleManifestPath,
    );
    if (!manifestFile.existsSync()) return;
    final manifest = _object(jsonDecode(manifestFile.readAsStringSync()));
    expect(manifest['providerId'], exporter.qualifiedVisionPersistenceMapperId);
    expect(
      manifest['providerVersion'],
      exporter.qualifiedVisionPersistenceMapperVersion,
    );
    expect(manifest['scenarioCount'], 16);
    expect(manifest['readyScenarioCount'], 8);
    expect(manifest['invocationCount'], 8);
    expect(
      manifest['oracleSourceStrategy'],
      exporter.qualifiedVisionPersistenceMapperOracleSourceStrategy,
    );
    expect(manifest['persistenceSchemaVersion'], 1);
    expect(manifest['persistenceEvidenceVersion'], 1);
    expect(manifest['resolverCompatibilityVersion'], 1);
    expect(
      sha256
          .convert(
            File(
              'lib/domain/wardrobe_profile/qualified_vision_persistence_mapper.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['providerImplementationSha256'],
    );
    expect(
      sha256
          .convert(
            File(
              'lib/domain/wardrobe_profile/vision_v2_shadow_analysis.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['callSitePreparationSha256'],
    );
    expect(
      sha256
          .convert(
            File(
              'tool/export_qualified_vision_persistence_mapper_oracles.dart',
            ).readAsBytesSync(),
          )
          .toString(),
      manifest['exporterImplementationSha256'],
    );
    final ready = _list(manifest['fixtures'])
        .map(_object)
        .where((item) => item['status'] == 'ready')
        .toList();
    expect(ready, hasLength(8));
    for (final entry in ready) {
      final oracleFile = File(
        'test/fixtures/${entry['oraclePath']}'.replaceAll(
          '/',
          Platform.pathSeparator,
        ),
      );
      expect(oracleFile.existsSync(), isTrue);
      expect(
        sha256.convert(oracleFile.readAsBytesSync()).toString(),
        entry['oracleSha256'],
      );
      final oracle = _object(jsonDecode(oracleFile.readAsStringSync()));
      expect(oracle['providerId'], exporter.qualifiedVisionPersistenceMapperId);
      expect(
        oracle['inputContract'],
        'qualified_vision_persistence_mapper_input/v1',
      );
      expect(
        oracle['outputContract'],
        'WardrobeProfilePersistenceMappingResult/v1',
      );
      final invocations = _list(oracle['invocations']).map(_object).toList();
      expect(invocations, hasLength(1));
      final invocation = invocations.single;
      expect(
        invocation['invocationId'],
        '${entry['scenarioId']}::qualified-vision-persistence-mapper',
      );
      final input = _object(invocation['mapperInput']);
      final output = _object(invocation['mapperOutput']);
      final context = _object(invocation['mappingContext']);
      final projection = _object(input['analysisProjection']);
      expect(projection.containsKey('observationEvidence'), isTrue);
      expect(projection.containsKey('familyIdentity'), isTrue);
      expect(projection.containsKey('resolvedProfile'), isFalse);
      expect(projection.containsKey('knowledgeBaseEvidence'), isFalse);
      expect(context['generationId'], startsWith('fixture-generation:'));
      expect(context['storagePath'], startsWith('fixture://'));
      expect(output['status'], isA<String>());
      expect(output.containsKey('omittedEvidenceReasonCodes'), isTrue);
      if (output['status'] == 'mapped') {
        final envelope = _object(output['envelope']);
        expect(envelope['userCorrections'], isEmpty);
        expect(envelope.containsKey('resolvedCache'), isFalse);
        final evidence = _list(envelope['machineEvidence']).map(_object).toList();
        expect(evidence, isNotEmpty);
        _assertEvidenceOrdering(evidence);
        _assertSupportingIdsResolvable(evidence);
        const WardrobeProfilePersistenceCodec().toPersistenceMap(
          _envelopeFromOracle(envelope),
        );
      }
      expect(
        sha256.convert(_canonicalBytes(input)).toString(),
        invocation['mapperInputSha256'],
      );
      expect(
        sha256.convert(_canonicalBytes(output)).toString(),
        invocation['mapperOutputSha256'],
      );
    }
  });

  test('fixture context is deterministic and secret-free', () {
    final manifestFile = File(
      exporter.qualifiedVisionPersistenceMapperOracleManifestPath,
    );
    if (!manifestFile.existsSync()) return;
    final ready = _list(
      _object(jsonDecode(manifestFile.readAsStringSync()))['fixtures'],
    ).map(_object).where((item) => item['status'] == 'ready');
    for (final entry in ready) {
      final oracle = _object(
        jsonDecode(
          File(
            'test/fixtures/${entry['oraclePath']}'.replaceAll(
              '/',
              Platform.pathSeparator,
            ),
          ).readAsStringSync(),
        ),
      );
      final text = jsonEncode(oracle);
      expect(text.contains(r'C:\'), isFalse);
      expect(text.contains('/Users/'), isFalse);
      expect(text.contains('Bearer '), isFalse);
      expect(text.contains('firebase'), isFalse);
      expect(text.contains('DateTime.now'), isFalse);
      final context = _object(
        _object(_list(oracle['invocations']).single)['mappingContext'],
      );
      expect(context['generationId'], startsWith('fixture-generation:'));
      expect(
        _object(oracle['contextAuthority'])['trustedProductionRevision'],
        isFalse,
      );
    }
  });

  test('production remains unchanged and Node mapper stays offline-only', () {
    final production = <String>[
      File('functions/index.js').readAsStringSync(),
      File('functions/vision_v2_shadow.js').readAsStringSync(),
    ].join('\n');
    expect(production, isNot(contains('QualifiedVisionPersistenceMapper')));
    expect(
      production,
      isNot(contains('qualified_vision_persistence_mapper')),
    );
    expect(
      File('functions/qualified_vision_persistence_mapper.js').existsSync(),
      isTrue,
    );
    expect(
      File(
        'functions/backend_qualified_vision_persistence_mapper_parity.js',
      ).existsSync(),
      isTrue,
    );
  });

  group('mapper characterization remains explicit', () {
    PersistenceMappingContext context({
      String analysisId = 'analysis-1',
      String model = 'gpt-4o-mini',
      int schema = 9,
    }) => PersistenceMappingContext(
      generationId: 'generation-1',
      revision: 1,
      createdAt: DateTime.utc(2026, 7, 29, 10),
      updatedAt: DateTime.utc(2026, 7, 29, 10, 1),
      imageRevision: 2,
      wardrobeItemRevision: 3,
      storagePath: 'fixture://wardrobe/item/source.jpg',
      analysisId: analysisId,
      analysisKind: WardrobeAnalysisKind.initialAnalysis,
      completedAt: DateTime.utc(2026, 7, 29, 10),
      modelIdentifier: model,
      pipelineVersion: 'vision-v2-phase-4.9',
      promptVersion: 'vision-v2-schema-9',
      visionSchemaVersion: schema,
      qualificationVersion: 'qualification-v1',
    );

    Map<String, Object?> observation(
      String state, {
      Object? value,
      double confidence = 0,
      String visibilityScope = 'complete',
      List<String> regions = const [],
    }) => {
      'state': state,
      if (state == 'observed') 'value': value,
      'confidence': confidence,
      'visibilityScope': state == 'not_visible' ? 'not_visible' : visibilityScope,
      'visibleRegions': regions,
    };

    Map<String, Object?> fixture({
      String input = 'valid_single_item',
      String framing = 'full_item',
      bool detail = false,
      String canonical = 'hoodie',
      List<Map<String, Object?>>? candidates,
    }) => {
      'schemaVersion': 9,
      'analysisId': 'analysis-1',
      'modelVersion': 'gpt-4o-mini',
      'sourceReference': 'fixture://item',
      'observedAt': '2026-07-29T10:00:00.000Z',
      'inputAssessment': input,
      'quality': {
        'itemFullyVisible': !detail,
        'occlusion': 'none',
        'backgroundInterference': 'low',
        'clarity': 'high',
      },
      'subjectAssessment': {
        'subjectCountEstimate': input == 'valid_single_item' ? 1 : 0,
        'cardinalityState': input == 'valid_single_item'
            ? 'single_item_supported'
            : 'no_wardrobe_subject',
        'primarySubjectPresent': input == 'valid_single_item',
        'sameItemConsistency': input == 'valid_single_item'
            ? 'same_item_supported'
            : 'not_applicable',
        'subjectDomain': 'garment_upper',
        'framingClass': framing,
        'framingAttestations': {
          'visibleBoundaries': detail
              ? <String>[]
              : ['top', 'bottom', 'left', 'right'],
          'primarySilhouetteContinuous': !detail,
          'visibleItemExtent': detail ? 'local' : 'whole',
          'localDetailOnly': detail,
          'cropIndicators': detail ? ['severe_crop'] : <String>[],
          'subjectOrientation': 'front',
        },
        'reasonCodes': <String>[],
      },
      'observations': {
        'coverage': observation(
          'observed',
          value: 'full',
          confidence: .9,
          regions: ['full_silhouette'],
        ),
        'hasHood': observation(
          'observed',
          value: true,
          confidence: .95,
          regions: ['collar', 'back'],
        ),
        'frontClosure': observation(
          'observed',
          value: 'full_zip',
          confidence: .9,
          regions: ['front', 'fastening_area'],
        ),
        'visibleBulk': observation(
          'observed',
          value: 'medium',
          confidence: .85,
          regions: ['full_silhouette'],
        ),
        'surfaceAppearance': observation(
          'observed',
          value: 'fleece_like',
          confidence: .85,
          regions: ['surface_detail'],
        ),
        'necklineShape': observation(
          'observed',
          value: 'high_neck',
          confidence: .8,
          regions: ['neckline'],
        ),
        'visiblePocketStructure': observation('unknown'),
        'visibleStretchCue': observation('not_visible'),
        'sportyCues': observation(
          'observed',
          value: 'medium',
          confidence: .8,
          regions: ['full_silhouette'],
        ),
        'formalCues': observation(
          'observed',
          value: 'low',
          confidence: .8,
          regions: ['full_silhouette'],
        ),
        'footwearConstruction': observation('not_applicable'),
        'footwearFastening': observation('not_applicable'),
        'soleProfile': observation('not_applicable'),
        'visibleTread': observation('not_applicable'),
        'footwearUpperHeight': observation('not_applicable'),
      },
      'identityCandidates':
          candidates ??
          [
            {
              'canonicalType': canonical,
              'confidence': .91,
              'definingObservations': ['hasHood', 'frontClosure'],
              'supportingObservations': ['visibleBulk', 'surfaceAppearance'],
            },
          ],
      'validationErrors': <String>[],
      'diagnostics': {
        'latencyMs': 1,
        'modelCallCount': 1,
        'inputPayloadBytes': 1,
        'outputPayloadBytes': 1,
        'observationFieldCount': 15,
      },
    };

    const allowed = {
      'hoodie',
      'sweater',
      't_shirt',
      'softshell',
      'chinos',
      'sneakers',
      'running_shoes',
      'basketball_shoes',
    };

    VisionV2ShadowAnalysis analyze(
      Map<String, Object?> raw, {
      List<Map<String, Object?>> additional = const [],
    }) => const VisionV2ShadowOrchestrator().analyze(
      itemId: 'item-1',
      response: VisionV2ShadowResponse.fromMap(
        raw,
        allowedCanonicalTypes: allowed,
      ),
      additionalResponses: additional.map(
        (item) => VisionV2ShadowResponse.fromMap(
          item,
          allowedCanonicalTypes: allowed,
        ),
      ),
    );

    const mapper = QualifiedVisionPersistenceMapper();

    test('family+canonical mapped envelope has empty userCorrections', () {
      final result = mapper.map(
        analysis: analyze(fixture()),
        context: context(),
      );
      expect(result.status, WardrobeProfilePersistenceMappingStatus.mapped);
      expect(result.envelope!.userCorrections, isEmpty);
      expect(
        result.envelope!.machineEvidence.any(
          (item) => item.property == WardrobeProfileProperty.family,
        ),
        isTrue,
      );
      expect(
        result.envelope!.machineEvidence.any(
          (item) => item.property == WardrobeProfileProperty.canonicalType,
        ),
        isTrue,
      );
    });

    test('invalid input returns invalidInput', () {
      final raw = fixture(input: 'non_wardrobe_object');
      final result = mapper.map(analysis: analyze(raw), context: context());
      expect(
        result.status,
        WardrobeProfilePersistenceMappingStatus.invalidInput,
      );
      expect(result.envelope, isNull);
    });

    test('analysis id mismatch is incompatibleInput', () {
      final result = mapper.map(
        analysis: analyze(fixture()),
        context: context(analysisId: 'other'),
      );
      expect(
        result.status,
        WardrobeProfilePersistenceMappingStatus.incompatibleInput,
      );
      expect(result.reasonCode, 'analysis_id_mismatch');
    });

    test('negative observation unknown and not_visible are preserved', () {
      final result = mapper.map(
        analysis: analyze(fixture()),
        context: context(),
      );
      final unknown = result.envelope!.machineEvidence.where(
        (item) =>
            item.property == WardrobeProfileProperty.visiblePocketStructure,
      );
      final notVisible = result.envelope!.machineEvidence.where(
        (item) => item.property == WardrobeProfileProperty.visibleStretchCue,
      );
      expect(unknown.single.valueState, EvidenceValueState.unknown);
      expect(notVisible.single.valueState, EvidenceValueState.notVisible);
    });

    test('deterministic evidence IDs and ordering', () {
      final first = mapper.map(analysis: analyze(fixture()), context: context());
      final second = mapper.map(
        analysis: analyze(fixture()),
        context: context(),
      );
      expect(
        first.envelope!.machineEvidence.map((item) => item.id).toList(),
        second.envelope!.machineEvidence.map((item) => item.id).toList(),
      );
      final encoded = exporter.encodeEnvelope(first.envelope!);
      _assertEvidenceOrdering(
        _list(encoded['machineEvidence']).map(_object).toList(),
      );
    });
  });
}

void _assertEvidenceOrdering(List<Map<String, Object?>> evidence) {
  int rank(String property) {
    if (property == WardrobeProfileProperty.family) return 0;
    if (property == WardrobeProfileProperty.canonicalType) return 1;
    if (property == WardrobeProfileProperty.coverage ||
        property.startsWith('visual.observations.')) {
      return 2;
    }
    return 3;
  }

  for (var i = 1; i < evidence.length; i++) {
    final left = evidence[i - 1];
    final right = evidence[i];
    final leftRank = rank('${left['property']}');
    final rightRank = rank('${right['property']}');
    if (leftRank != rightRank) {
      expect(leftRank, lessThanOrEqualTo(rightRank));
      continue;
    }
    final propertyCmp = '${left['property']}'.compareTo('${right['property']}');
    if (propertyCmp != 0) {
      expect(propertyCmp, lessThanOrEqualTo(0));
      continue;
    }
    expect('${left['id']}'.compareTo('${right['id']}'), lessThanOrEqualTo(0));
  }
}

void _assertSupportingIdsResolvable(List<Map<String, Object?>> evidence) {
  final ids = evidence.map((item) => '${item['id']}').toSet();
  for (final item in evidence) {
    final supports = _list(item['supportingEvidenceIds'] ?? const []);
    for (final support in supports) {
      expect(ids.contains('$support'), isTrue);
    }
  }
}

WardrobeProfilePersistenceEnvelope _envelopeFromOracle(
  Map<String, Object?> envelope,
) {
  final metadata = _object(envelope['metadata']);
  final source = _object(envelope['source']);
  final analysis = _object(envelope['analysis']);
  return WardrobeProfilePersistenceEnvelope(
    metadata: WardrobeProfilePersistenceMetadata(
      schemaVersion: metadata['schemaVersion'] as int,
      evidenceSchemaVersion: metadata['evidenceSchemaVersion'] as int,
      resolverCompatibilityVersion:
          metadata['resolverCompatibilityVersion'] as int,
      generationId: '${metadata['generationId']}',
      revision: metadata['revision'] as int,
      createdAt: DateTime.parse('${metadata['createdAt']}'),
      updatedAt: DateTime.parse('${metadata['updatedAt']}'),
    ),
    source: WardrobeProfileSourceProvenance(
      imageRevision: source['imageRevision'] as int,
      wardrobeItemRevision: source['wardrobeItemRevision'] as int,
      storagePath: source['storagePath']?.toString(),
      imageHash: source['imageHash']?.toString(),
      uploadGeneration: source['uploadGeneration']?.toString(),
    ),
    analysis: WardrobeProfileAnalysisProvenance(
      analysisId: '${analysis['analysisId']}',
      kind: WardrobeAnalysisKind.values.firstWhere(
        (item) => item.wireName == analysis['kind'],
      ),
      completedAt: DateTime.parse('${analysis['completedAt']}'),
      modelIdentifier: '${analysis['modelIdentifier']}',
      pipelineVersion: '${analysis['pipelineVersion']}',
      promptVersion: '${analysis['promptVersion']}',
      visionSchemaVersion: analysis['visionSchemaVersion'] as int,
      qualificationVersion: '${analysis['qualificationVersion']}',
    ),
    machineEvidence: _list(envelope['machineEvidence']).map((raw) {
      final item = _object(raw);
      return PersistedMachineEvidence(
        id: '${item['id']}',
        property: '${item['property']}',
        value: item['value'],
        valueState: EvidenceValueState.fromWireName('${item['valueState']}'),
        source: EvidenceSource.fromWireName('${item['source']}'),
        nature: EvidenceNature.fromWireName('${item['nature']}'),
        confidence: (item['confidence'] as num).toDouble(),
        method: '${item['method']}',
        createdAt: DateTime.parse('${item['createdAt']}'),
        modelVersion: '${item['modelVersion']}',
        identityQualification: item['identityQualification'] == null
            ? null
            : PersistedIdentityQualification.values.firstWhere(
                (value) => value.wireName == item['identityQualification'],
              ),
        supportingEvidenceIds: _list(
          item['supportingEvidenceIds'] ?? const [],
        ).map((value) => '$value').toList(),
      );
    }).toList(),
    userCorrections: const {},
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw FormatException('expected_object');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _list(Object? value) {
  if (value is! List) throw FormatException('expected_list');
  return List<Object?>.from(value);
}

List<int> _canonicalBytes(Object? value) => utf8.encode(
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
