import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:http/http.dart' as http;

import 'add_clothing_analyzer_mapper.dart';
import 'firebase_app_check_bootstrap.dart';

/// Shared interpretation of a `wardrobe-analyzer-v2` response for debug
/// reanalyze review. Identity fields here are interpretive only and must not
/// be persisted by metadata apply.
class ClothingAnalyzerPipelineResult {
  const ClothingAnalyzerPipelineResult({
    required this.suggestedName,
    required this.canonicalType,
    required this.layerRole,
    required this.categoryKey,
    required this.subCategoryKey,
    this.analyzerConfidence,
    this.detectedColors = const [],
    this.kbMatched = false,
    this.patterns = const [],
    this.logoProminence = '',
    this.visualDescription = '',
    this.visualIdentity = '',
    this.identityConfidence,
  });

  /// Review/display only. Debug apply must not persist this.
  final String suggestedName;
  /// Review/display only. Debug apply must not persist this.
  final String canonicalType;
  /// Review/display only. Debug apply must not persist this.
  final String layerRole;
  /// Review/display only. Debug apply must not persist this.
  final String categoryKey;
  /// Review/display only. Debug apply must not persist this.
  final String subCategoryKey;
  final int? analyzerConfidence;
  /// Interpreted display colors. Review only; apply must not write colorProfile.
  final List<String> detectedColors;
  final bool kbMatched;
  final List<String> patterns;
  final String logoProminence;
  final String visualDescription;
  final String visualIdentity;
  final int? identityConfidence;

  static const ClothingAnalyzerPipelineResult empty =
      ClothingAnalyzerPipelineResult(
        suggestedName: '',
        canonicalType: '',
        layerRole: '',
        categoryKey: '',
        subCategoryKey: '',
      );
}

/// Debug/gated reanalyze HTTP + shared Add Clothing interpretation.
/// Persistence authority stays in [WardrobeReanalyzeApplyService].
abstract final class ClothingAnalyzerPipeline {
  static const String analyzeEndpoint =
      'https://us-east1-outfitoftheday-4d401.cloudfunctions.net/analyzeClothingImage';
  static const String contractVersion = 'wardrobe-analyzer-v2';

  /// Owned original under `wardrobe/{uid}/...`. Rejects `wardrobe_product/`.
  static String requireOwnedAnalyzerStoragePath(String? storagePath) {
    final path = (storagePath ?? '').trim();
    if (path.isEmpty) {
      throw Exception('analyzeClothingImage requires owned storagePath');
    }
    if (path.startsWith('wardrobe_product/') ||
        path.contains('/wardrobe_product/') ||
        path.contains('..') ||
        !path.startsWith('wardrobe/') ||
        path.split('/').length < 3) {
      throw Exception(
        'analyzeClothingImage storagePath must be under wardrobe/',
      );
    }
    return path;
  }

  static bool isOwnedAnalyzerStoragePath(String? storagePath) {
    try {
      requireOwnedAnalyzerStoragePath(storagePath);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> buildAnalyzeRequestBody({
    required String storagePath,
    String? imageUrl,
  }) {
    final path = requireOwnedAnalyzerStoragePath(storagePath);
    final trimmedUrl = (imageUrl ?? '').trim();
    final urlPath = storagePathFromFirebaseUrl(trimmedUrl);
    final includeOwnedImageUrl =
        trimmedUrl.isNotEmpty && isOwnedAnalyzerStoragePath(urlPath);
    return <String, dynamic>{
      'contractVersion': contractVersion,
      'storagePath': path,
      if (includeOwnedImageUrl) 'imageUrl': trimmedUrl,
    };
  }

  /// Calls production [analyzeClothingImage].
  ///
  /// Requires Firebase ID token and owned wardrobe [storagePath].
  /// [imageUrl] is optional supporting context; server authorizes via storagePath.
  static Future<ClothingAnalyzerPipelineResult> analyzeImageUrl(
    String imageUrl, {
    required String idToken,
    required String storagePath,
    String? appCheckToken,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final decoded = await analyzeRaw(
      idToken: idToken,
      imageUrl: imageUrl,
      storagePath: storagePath,
      appCheckToken: appCheckToken,
      timeout: timeout,
    );
    return analyzeResponse(decoded);
  }

  /// Raw JSON helper for callers that need analyzer metadata fields.
  static Future<Map<String, dynamic>> analyzeRaw({
    required String idToken,
    required String storagePath,
    String? imageUrl,
    String? appCheckToken,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final path = requireOwnedAnalyzerStoragePath(storagePath);

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    };
    var check = (appCheckToken ?? '').trim();
    if (check.isEmpty) {
      try {
        if (FirebaseAppCheckBootstrap.instance.isReady) {
          check = (await FirebaseAppCheck.instance.getToken())?.trim() ?? '';
        }
      } catch (_) {
        check = '';
      }
    }
    if (check.isNotEmpty) {
      headers['X-Firebase-AppCheck'] = check;
    }

    final body = buildAnalyzeRequestBody(
      storagePath: path,
      imageUrl: imageUrl,
    );
    final resp = await http
        .post(
          Uri.parse(analyzeEndpoint),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw Exception('analyzeClothingImage ${resp.statusCode}: ${resp.body}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('analyzeClothingImage response is not a JSON object');
    }
    return decoded;
  }

  /// Derive owned Firebase Storage object path from a download URL.
  /// Returns null for external / unparseable URLs.
  static String? storagePathFromFirebaseUrl(String? imageUrl) {
    final raw = (imageUrl ?? '').trim();
    if (raw.isEmpty) return null;
    final Uri url;
    try {
      url = Uri.parse(raw);
    } catch (_) {
      return null;
    }

    if (url.host == 'firebasestorage.googleapis.com') {
      final m = RegExp(r'^/v0/b/([^/]+)/o/(.+)$').firstMatch(url.path);
      if (m == null) return null;
      return Uri.decodeComponent(m.group(2)!);
    }
    if (url.host == 'storage.googleapis.com') {
      final parts = url.path.replaceFirst(RegExp(r'^/+'), '').split('/');
      if (parts.length < 2) return null;
      return parts.sublist(1).join('/');
    }
    return null;
  }

  /// Prefer explicit [storagePath], else parse from Firebase download URL.
  static String? resolveOwnedStoragePath({
    String? storagePath,
    String? imageUrl,
  }) {
    final direct = (storagePath ?? '').trim();
    if (direct.isNotEmpty) return direct;
    return storagePathFromFirebaseUrl(imageUrl);
  }

  /// Interprets analyzer JSON through [AddClothingAnalyzerMapper].
  /// Callers must not persist identity fields from this result.
  static ClothingAnalyzerPipelineResult analyzeResponse(Map<String, dynamic> m) {
    return fromMapper(AddClothingAnalyzerMapper.map(m));
  }

  static ClothingAnalyzerPipelineResult fromMapper(
    AddClothingAnalyzerMapperResult mapped,
  ) {
    final hidden = mapped.hiddenAiMetadata;
    return ClothingAnalyzerPipelineResult(
      suggestedName: mapped.suggestedName,
      canonicalType: mapped.mappedCanonicalType,
      layerRole: mapped.layerRole ?? mapped.aiStylingLayerRole ?? '',
      categoryKey: mapped.categoryKey ?? '',
      subCategoryKey: mapped.subCategoryKey ?? '',
      analyzerConfidence: _asConfidence(mapped.confidenceRaw),
      detectedColors: List<String>.from(mapped.displayColors),
      kbMatched: mapped.kbMatched,
      patterns: List<String>.from(mapped.patterns),
      logoProminence:
          (hidden['logo_prominence'] ?? hidden['logoProminence'] ?? '')
              .toString()
              .trim(),
      visualDescription: mapped.visualDescription,
      visualIdentity:
          (hidden['visual_identity'] ?? hidden['visualIdentity'] ?? '')
              .toString()
              .trim(),
      identityConfidence: _asConfidence(
        hidden['identity_confidence'] ?? hidden['identityConfidence'],
      ),
    );
  }

  static int? _asConfidence(dynamic raw) {
    if (raw == null) return null;
    final n = num.tryParse(raw.toString());
    if (n == null || !n.isFinite) return null;
    return n.round().clamp(0, 100);
  }
}
