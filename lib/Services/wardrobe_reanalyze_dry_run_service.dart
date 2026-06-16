import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/clothing_knowledge_base.dart';
import '../utils/wardrobe_reanalyze_inspector.dart';
import 'clothing_analyzer_pipeline.dart';

export '../utils/wardrobe_reanalyze_inspector.dart'
    show WardrobeReanalyzeReviewStatus;

/// Developer-only dry run: re-analyze wardrobe images without Firestore writes.
abstract final class WardrobeReanalyzeDryRunService {
  static const Duration perItemDelay = Duration(milliseconds: 400);

  /// Console-only dry run (legacy entry point).
  static Future<WardrobeReanalyzeSummary> run({
    int? maxItems,
    Duration itemTimeout = const Duration(seconds: 35),
  }) async {
    final result = await runForReview(
      maxItems: maxItems,
      itemTimeout: itemTimeout,
    );
    return result.summary;
  }

  /// Full dry run with per-item review rows for the developer screen.
  static Future<WardrobeReanalyzeRunResult> runForReview({
    int? maxItems,
    Duration itemTimeout = const Duration(seconds: 35),
    void Function(int completed, int total)? onProgress,
  }) async {
    if (!kDebugMode) {
      debugPrint('[WARDROBE_REANALYZE] skipped (not debug mode)');
      return const WardrobeReanalyzeRunResult(
        items: [],
        summary: WardrobeReanalyzeSummary(
          total: 0,
          improved: 0,
          unchanged: 0,
          suspicious: 0,
          failed: 0,
        ),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Musíš byť prihlásený.');
    }

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('wardrobe')
        .get();

    var docs = snap.docs;
    if (maxItems != null && maxItems > 0 && docs.length > maxItems) {
      docs = docs.take(maxItems).toList();
    }

    final items = <WardrobeReanalyzeReviewItem>[];
    var improved = 0;
    var unchanged = 0;
    var suspicious = 0;
    var failed = 0;

    for (var i = 0; i < docs.length; i++) {
      onProgress?.call(i, docs.length);
      final doc = docs[i];
      final data = Map<String, dynamic>.from(doc.data());
      final storedItemId = (data['id'] ?? data['itemId'] ?? doc.id).toString();
      final brand = (data['brand'] ?? '').toString().trim();
      final imageUrl = pickAnalysisImageUrl(data);

      try {
        if (imageUrl == null || imageUrl.isEmpty) {
          failed++;
          items.add(
            WardrobeReanalyzeReviewItem.failed(
              documentId: doc.id,
              itemId: storedItemId,
              brand: brand,
              imageUrl: null,
              old: WardrobeReanalyzeFields.fromStored(data),
              error: 'no_image_url',
            ),
          );
          debugPrint(
            '[WARDROBE_REANALYZE] itemId=${doc.id} FAILED reason=no_image_url',
          );
          continue;
        }

        final old = WardrobeReanalyzeFields.fromStored(data);
        final pipeline = await ClothingAnalyzerPipeline.analyzeImageUrl(
          imageUrl,
          timeout: itemTimeout,
        );
        final neu = WardrobeReanalyzeFields.fromPipeline(pipeline);

        final fieldsChanged = old.differsFrom(neu);
        final status = WardrobeReanalyzeInspector.classifyStatus(
          fieldsChanged: fieldsChanged,
          oldName: old.name,
          newName: neu.name,
          oldCanonical: old.canonicalType,
          newCanonical: neu.canonicalType,
          detectedColors: pipeline.detectedColors,
          analyzerConfidence: pipeline.analyzerConfidence,
          kbMatched: pipeline.kbMatched,
        );
        final suspiciousReasons = WardrobeReanalyzeInspector.suspiciousReasons(
          oldName: old.name,
          newName: neu.name,
          oldCanonical: old.canonicalType,
          newCanonical: neu.canonicalType,
          detectedColors: pipeline.detectedColors,
          analyzerConfidence: pipeline.analyzerConfidence,
          kbMatched: pipeline.kbMatched,
        );

        final row = WardrobeReanalyzeReviewItem(
          documentId: doc.id,
          itemId: storedItemId,
          brand: brand,
          imageUrl: imageUrl,
          old: old,
          newFields: neu,
          status: status,
          suspiciousReasons: suspiciousReasons,
          analyzerConfidence: pipeline.analyzerConfidence,
          detectedColors: pipeline.detectedColors,
          failed: false,
          error: null,
        );
        items.add(row);
        switch (status) {
          case WardrobeReanalyzeReviewStatus.improved:
            improved++;
          case WardrobeReanalyzeReviewStatus.unchanged:
            unchanged++;
          case WardrobeReanalyzeReviewStatus.suspicious:
            suspicious++;
        }
        _logComparison(row);

        if (i < docs.length - 1) {
          await Future<void>.delayed(perItemDelay);
        }
      } catch (e, st) {
        failed++;
        items.add(
          WardrobeReanalyzeReviewItem.failed(
            documentId: doc.id,
            itemId: storedItemId,
            brand: brand,
            imageUrl: imageUrl,
            old: WardrobeReanalyzeFields.fromStored(data),
            error: e.toString(),
          ),
        );
        debugPrint('[WARDROBE_REANALYZE] itemId=${doc.id} FAILED error=$e');
        if (kDebugMode) debugPrint('$st');
      }
    }

    onProgress?.call(docs.length, docs.length);

    final summary = WardrobeReanalyzeSummary(
      total: docs.length,
      improved: improved,
      unchanged: unchanged,
      suspicious: suspicious,
      failed: failed,
    );
    _logSummary(summary);
    return WardrobeReanalyzeRunResult(items: items, summary: summary);
  }

  /// productImageUrl → cleanImageUrl → imageUrl (dry-run spec; no processing gate).
  static String? pickAnalysisImageUrl(Map<String, dynamic> item) {
    for (final key in ['productImageUrl', 'cleanImageUrl', 'imageUrl']) {
      final s = (item[key] ?? '').toString().trim();
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
    }
    return null;
  }

  static void _logComparison(WardrobeReanalyzeReviewItem row) {
    debugPrint(
      '[WARDROBE_REANALYZE]\n'
      'itemId=${row.documentId}\n'
      'status=${row.statusLabel}\n'
      'oldName=${row.old.name}\n'
      'newName=${row.newFields.name}\n'
      'oldCanonical=${row.old.canonicalType}\n'
      'newCanonical=${row.newFields.canonicalType}\n'
      'oldLayer=${row.old.layerRole}\n'
      'newLayer=${row.newFields.layerRole}\n'
      'oldCategory=${row.old.categoryKey}\n'
      'newCategory=${row.newFields.categoryKey}\n'
      'oldSubCategory=${row.old.subCategoryKey}\n'
      'newSubCategory=${row.newFields.subCategoryKey}\n'
      'suspiciousReasons=${row.suspiciousReasons.join('; ')}',
    );
  }

  static void _logSummary(WardrobeReanalyzeSummary summary) {
    debugPrint(
      '[WARDROBE_REANALYZE_SUMMARY] total=${summary.total} '
      'improved=${summary.improved} unchanged=${summary.unchanged} '
      'suspicious=${summary.suspicious} failed=${summary.failed}',
    );
  }
}

class WardrobeReanalyzeRunResult {
  const WardrobeReanalyzeRunResult({
    required this.items,
    required this.summary,
  });

  final List<WardrobeReanalyzeReviewItem> items;
  final WardrobeReanalyzeSummary summary;
}

class WardrobeReanalyzeSummary {
  const WardrobeReanalyzeSummary({
    required this.total,
    required this.improved,
    required this.unchanged,
    required this.suspicious,
    required this.failed,
  });

  final int total;
  final int improved;
  final int unchanged;
  final int suspicious;
  final int failed;

  /// Legacy alias for improved count.
  int get changed => improved;
}

class WardrobeReanalyzeFields {
  const WardrobeReanalyzeFields({
    required this.name,
    required this.canonicalType,
    required this.layerRole,
    required this.categoryKey,
    required this.subCategoryKey,
  });

  final String name;
  final String canonicalType;
  final String layerRole;
  final String categoryKey;
  final String subCategoryKey;

  factory WardrobeReanalyzeFields.fromStored(Map<String, dynamic> item) {
    return WardrobeReanalyzeFields(
      name: (item['name'] ?? '').toString().trim(),
      canonicalType: _storedCanonical(item),
      layerRole:
          (item['layer_role'] ?? item['layerRole'] ?? '').toString().trim(),
      categoryKey:
          (item['categoryKey'] ?? item['category'] ?? '').toString().trim(),
      subCategoryKey: (item['subCategoryKey'] ?? item['subCategory'] ?? '')
          .toString()
          .trim(),
    );
  }

  factory WardrobeReanalyzeFields.fromPipeline(
    ClothingAnalyzerPipelineResult pipeline,
  ) {
    return WardrobeReanalyzeFields(
      name: pipeline.suggestedName,
      canonicalType: pipeline.canonicalType,
      layerRole: pipeline.layerRole,
      categoryKey: pipeline.categoryKey,
      subCategoryKey: pipeline.subCategoryKey,
    );
  }

  static String _storedCanonical(Map<String, dynamic> item) {
    final direct = (item['canonical_type'] ?? item['canonicalType'] ?? '')
        .toString()
        .trim();
    if (direct.isNotEmpty) return direct;
    return ClothingKnowledgeBase.itemCanonicalType(item) ?? '';
  }

  bool differsFrom(WardrobeReanalyzeFields other) {
    return _norm(name) != _norm(other.name) ||
        _norm(canonicalType) != _norm(other.canonicalType) ||
        _norm(layerRole) != _norm(other.layerRole) ||
        _norm(categoryKey) != _norm(other.categoryKey) ||
        _norm(subCategoryKey) != _norm(other.subCategoryKey);
  }

  static String _norm(String s) => s.trim().toLowerCase();
}

class WardrobeReanalyzeReviewItem {
  const WardrobeReanalyzeReviewItem({
    required this.documentId,
    required this.itemId,
    required this.brand,
    required this.imageUrl,
    required this.old,
    required this.newFields,
    required this.status,
    required this.suspiciousReasons,
    required this.analyzerConfidence,
    required this.detectedColors,
    required this.failed,
    this.error,
  });

  factory WardrobeReanalyzeReviewItem.failed({
    required String documentId,
    required String itemId,
    required String brand,
    required String? imageUrl,
    required WardrobeReanalyzeFields old,
    required String error,
  }) {
    return WardrobeReanalyzeReviewItem(
      documentId: documentId,
      itemId: itemId,
      brand: brand,
      imageUrl: imageUrl,
      old: old,
      newFields: const WardrobeReanalyzeFields(
        name: '',
        canonicalType: '',
        layerRole: '',
        categoryKey: '',
        subCategoryKey: '',
      ),
      status: WardrobeReanalyzeReviewStatus.suspicious,
      suspiciousReasons: ['analysis failed: $error'],
      analyzerConfidence: null,
      detectedColors: const [],
      failed: true,
      error: error,
    );
  }

  final String documentId;
  final String itemId;
  final String brand;
  final String? imageUrl;
  final WardrobeReanalyzeFields old;
  final WardrobeReanalyzeFields newFields;
  final WardrobeReanalyzeReviewStatus status;
  final List<String> suspiciousReasons;
  final int? analyzerConfidence;
  final List<String> detectedColors;
  final bool failed;
  final String? error;

  String get statusLabel {
    if (failed) return 'Failed';
    return switch (status) {
      WardrobeReanalyzeReviewStatus.improved => 'Improved',
      WardrobeReanalyzeReviewStatus.unchanged => 'Unchanged',
      WardrobeReanalyzeReviewStatus.suspicious => 'Suspicious',
    };
  }
}
