import 'dart:convert';

import 'vision_subject_safety.dart';
import 'vision_v2_shadow_analysis.dart';

final class VisionParserFixtureReplay {
  const VisionParserFixtureReplay();

  List<VisionV2ShadowResponse> decodeResponses(
    String fixtureJson, {
    required Set<String> allowedCanonicalTypes,
  }) {
    final root = _decodeRoot(fixtureJson);
    final views = root['views'];
    if (views is! List || views.isEmpty) {
      throw const FormatException('Parser fixture requires at least one view.');
    }
    return List.unmodifiable(
      views.map((raw) {
        if (raw is! Map || raw['response'] is! Map) {
          throw const FormatException('Parser fixture view is invalid.');
        }
        return VisionV2ShadowResponse.fromJson(
          jsonEncode(raw['response']),
          allowedCanonicalTypes: allowedCanonicalTypes,
        );
      }),
    );
  }

  VisionMultiViewSubjectBinding decodeBinding(String fixtureJson) {
    final root = _decodeRoot(fixtureJson);
    final raw = root['multiViewSubjectBinding'];
    if (raw == null) return VisionMultiViewSubjectBinding.undeclared;
    if (raw is! Map) {
      throw const FormatException('Invalid multiViewSubjectBinding');
    }
    return VisionMultiViewSubjectBinding.fromMap(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  VisionV2ShadowAnalysis replayQualification(
    String fixtureJson, {
    required String fixtureId,
    required Set<String> allowedCanonicalTypes,
  }) {
    final responses = decodeResponses(
      fixtureJson,
      allowedCanonicalTypes: allowedCanonicalTypes,
    );
    return const VisionV2ShadowOrchestrator().analyze(
      itemId: fixtureId,
      response: responses.first,
      additionalResponses: responses.skip(1),
      multiViewSubjectBinding: decodeBinding(fixtureJson),
    );
  }

  Map<String, dynamic> _decodeRoot(String fixtureJson) {
    final decoded = jsonDecode(fixtureJson);
    if (decoded is! Map) {
      throw const FormatException('Parser fixture root must be an object.');
    }
    final root = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (root['fixtureContractVersion'] != 1 ||
        root['captureDataset'] != 'current_pipeline_capture_v1') {
      throw const FormatException('Unsupported parser fixture contract.');
    }
    if (_containsForbiddenKey(root)) {
      throw const FormatException('Parser fixture contains forbidden data.');
    }
    return root;
  }

  bool _containsForbiddenKey(Object? value) {
    if (value is List) return value.any(_containsForbiddenKey);
    if (value is! Map) return false;
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key == 'resolvedprofile' ||
          key == 'knowledgebaseevidence' ||
          key == 'machineevidence' ||
          key == 'usercorrections' ||
          key == 'authorization' ||
          key.contains('signedurl') ||
          key.contains('downloadtoken')) {
        return true;
      }
      if (_containsForbiddenKey(entry.value)) return true;
    }
    return false;
  }
}
