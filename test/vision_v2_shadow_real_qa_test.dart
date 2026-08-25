import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/data/clothing_knowledge_base.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/vision_v2_shadow_analysis.dart';

const _v1 = <String, Map<String, Object?>>{
  'classic_trousers': {
    'canonical_type': 'corduroy_pants',
    'warmth': 4,
    'formality': 4,
    'layer_role': 'bottom',
  },
  'sport_shoes_white': {
    'canonical_type': null,
    'warmth': 4,
    'formality': 5,
    'layer_role': 'footwear',
  },
  'sport_shoes_red': {
    'canonical_type': null,
    'warmth': 4,
    'formality': 5,
    'layer_role': 'footwear',
  },
  'fashion_sneakers': {
    'canonical_type': 'sneakers',
    'warmth': 4,
    'formality': 5,
    'layer_role': 'footwear',
  },
  'ankle_boots': {
    'canonical_type': 'winter_boots',
    'warmth': 4,
    'formality': 5,
    'layer_role': 'footwear',
  },
  'winter_jacket': {
    'canonical_type': 'winter_jacket',
    'warmth': 7,
    'formality': 5,
    'layer_role': 'outer_layer',
  },
  'hoodie': {
    'canonical_type': 'hoodie',
    'warmth': 5,
    'formality': 5,
    'layer_role': 'mid_layer',
  },
  'jeans': {
    'canonical_type': 'jeans',
    'warmth': 4,
    'formality': 5,
    'layer_role': 'bottom',
  },
  't_shirt': {
    'canonical_type': 'v_neck_t_shirt',
    'warmth': 3,
    'formality': 5,
    'layer_role': 'base_layer',
  },
};

void main() {
  test('builds a local report from captured read-only responses', () {
    final inputPath = Platform.environment['VISION_V2_QA_INPUT'];
    final outputPath = Platform.environment['VISION_V2_QA_OUTPUT'];
    if (inputPath == null || outputPath == null) {
      return;
    }
    final decoded = jsonDecode(File(inputPath).readAsStringSync());
    expect(decoded, isA<List>());
    final retryPath = Platform.environment['VISION_V2_QA_RETRY_INPUT'];
    final retryEntries = retryPath == null
        ? const <dynamic>[]
        : jsonDecode(File(retryPath).readAsStringSync()) as List;
    final retriesById = {
      for (final raw in retryEntries) _map(raw)['id'].toString(): _map(raw),
    };
    final allowed = ClothingKnowledgeBase.allItems
        .map((item) => item.canonicalType)
        .toSet();
    final output = <Map<String, Object?>>[];
    for (final entryRaw in decoded as List) {
      var entry = _map(entryRaw);
      final id = entry['id'].toString();
      if (entry['ok'] != true && retriesById[id] != null) {
        entry = retriesById[id]!;
      }
      expect(entry['ok'], isTrue, reason: 'Remote shadow failed for $id');
      final response = VisionV2ShadowResponse.fromMap(
        _map(entry['response']),
        allowedCanonicalTypes: allowed,
      );
      final analysis = const VisionV2ShadowOrchestrator().analyze(
        itemId: id,
        response: response,
        v1Summary: _v1[id] ?? const {},
      );
      output.add({'id': id, ...analysis.toMap()});
    }
    File(
      outputPath,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));

    final scenarioPath = Platform.environment['VISION_V2_QA_SCENARIOS'];
    final scenarioOutputPath =
        Platform.environment['VISION_V2_QA_SCENARIO_OUTPUT'];
    if (scenarioPath == null || scenarioOutputPath == null) return;
    final scenarios = jsonDecode(File(scenarioPath).readAsStringSync()) as List;
    final entriesById = {
      for (final raw in decoded) _map(raw)['id'].toString(): _map(raw),
    };
    final scenarioOutput = <Map<String, Object?>>[];
    for (final scenarioRaw in scenarios) {
      final scenario = _map(scenarioRaw);
      final viewIds = (scenario['viewFixtureIds'] as List)
          .map((value) => value.toString())
          .toList();
      expect(viewIds, hasLength(2));
      final responses = viewIds
          .map(
            (id) => VisionV2ShadowResponse.fromMap(
              _map(entriesById[id]!['response']),
              allowedCanonicalTypes: allowed,
            ),
          )
          .toList();
      final analysis = const VisionV2ShadowOrchestrator().analyze(
        itemId: scenario['id'].toString(),
        response: responses.first,
        additionalResponses: [responses.last],
      );
      scenarioOutput.add({
        'id': scenario['id'],
        'viewFixtureIds': viewIds,
        'groundTruth': scenario['groundTruth'],
        ...analysis.toMap(),
      });
    }
    File(scenarioOutputPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(scenarioOutput),
    );
  });
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('Expected object');
  return value.map((key, value) => MapEntry(key.toString(), value));
}
