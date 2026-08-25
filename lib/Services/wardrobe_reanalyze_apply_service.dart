import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'clothing_analyzer_pipeline.dart';
import 'wardrobe_reanalyze_dry_run_service.dart';
import 'wardrobe_write_path_cutover.dart';

/// Re-analyzes wardrobe photos and writes logo/pattern metadata to Firestore.
abstract final class WardrobeReanalyzeApplyService {
  // Vyššia pauza medzi kúskami, aby sme nenarazili na OpenAI TPM limit
  // (gpt-4o-mini ~200k tokenov/min, jedna vision analýza ~2600 tokenov).
  static const Duration perItemDelay = Duration(milliseconds: 1200);
  static const int maxRateLimitRetries = 5;

  static bool _isRateLimit(Object e) {
    final s = e.toString();
    return s.contains('429') || s.contains('rate_limit');
  }

  /// Analyzes one image, retrying on 429 with exponential backoff.
  static Future<ClothingAnalyzerPipelineResult> _analyzeWithRetry(
    String imageUrl,
    Duration itemTimeout, {
    required String idToken,
    required String storagePath,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await ClothingAnalyzerPipeline.analyzeImageUrl(
          imageUrl,
          idToken: idToken,
          storagePath: storagePath,
          timeout: itemTimeout,
        );
      } catch (e) {
        attempt++;
        if (!_isRateLimit(e) || attempt > maxRateLimitRetries) rethrow;
        final waitMs = 1500 * attempt; // 1.5s, 3s, 4.5s, 6s, 7.5s
        debugPrint(
          '[WARDROBE_REANALYZE_APPLY] rate limit, retry $attempt '
          'after ${waitMs}ms',
        );
        await Future<void>.delayed(Duration(milliseconds: waitMs));
      }
    }
  }

  /// Re-runs vision analysis and updates patterns, logo_prominence,
  /// visual_description (+ related AI fields). Does not change name/categories.
  static Future<WardrobeReanalyzeApplySummary> applyMetadataRefresh({
    int? maxItems,
    Duration itemTimeout = const Duration(seconds: 35),
    void Function(int completed, int total)? onProgress,
    // Ak true, preskočí kúsky, ktoré už boli raz reanalyzované
    // (majú metadata_reanalyzed_at). Šetrí tokeny pri opakovanom behu.
    bool onlyMissing = false,
  }) async {
    if (!kDebugMode) {
      throw Exception('Metadata reanalyze is developer-only.');
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
    if (onlyMissing) {
      docs = docs
          .where((d) => (d.data())['metadata_reanalyzed_at'] == null)
          .toList();
    }
    if (maxItems != null && maxItems > 0 && docs.length > maxItems) {
      docs = docs.take(maxItems).toList();
    }

    var updated = 0;
    var skipped = 0;
    var failed = 0;
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Nepodarilo sa získať auth token.');
    }

    for (var i = 0; i < docs.length; i++) {
      onProgress?.call(i, docs.length);
      final doc = docs[i];
      final data = Map<String, dynamic>.from(doc.data());
      final imageUrl = WardrobeReanalyzeDryRunService.pickAnalysisImageUrl(data);

      try {
        if (imageUrl == null || imageUrl.isEmpty) {
          failed++;
          debugPrint(
            '[WARDROBE_REANALYZE_APPLY] itemId=${doc.id} FAILED no_image_url',
          );
          continue;
        }

        final old = WardrobeReanalyzeFields.fromStored(data);
        final storagePath = ClothingAnalyzerPipeline.resolveOwnedStoragePath(
          storagePath: (data['storagePath'] ?? '').toString(),
          imageUrl: imageUrl,
        );
        if (storagePath == null ||
            storagePath.isEmpty ||
            !storagePath.startsWith('wardrobe/')) {
          failed++;
          debugPrint(
            '[WARDROBE_REANALYZE_APPLY] itemId=${doc.id} FAILED '
            'no_owned_storage_path',
          );
          continue;
        }
        final pipeline = await _analyzeWithRetry(
          imageUrl,
          itemTimeout,
          idToken: idToken,
          storagePath: storagePath,
        );
        final neu = WardrobeReanalyzeFields.fromPipeline(pipeline);

        if (!old.metadataDiffersFrom(neu)) {
          skipped++;
          debugPrint(
            '[WARDROBE_REANALYZE_APPLY] itemId=${doc.id} SKIP unchanged '
            'patterns=${neu.patterns} logo=${neu.logoProminence}',
          );
          continue;
        }

        final patch = _metadataPatchFromPipeline(pipeline);
        await doc.reference.update(patch);
        await WardrobeWritePathCutover.instance.afterSameImageReanalysis(
          itemId: doc.id,
        );
        updated++;

        debugPrint(
          '[WARDROBE_REANALYZE_APPLY] itemId=${doc.id} UPDATED\n'
          'oldPatterns=${old.patterns} newPatterns=${neu.patterns}\n'
          'oldLogo=${old.logoProminence} newLogo=${neu.logoProminence}\n'
          'newVisual=${neu.visualDescription}',
        );

        if (i < docs.length - 1) {
          await Future<void>.delayed(perItemDelay);
        }
      } catch (e, st) {
        failed++;
        debugPrint(
          '[WARDROBE_REANALYZE_APPLY] itemId=${doc.id} FAILED error=$e',
        );
        if (kDebugMode) debugPrint('$st');
      }
    }

    onProgress?.call(docs.length, docs.length);

    final summary = WardrobeReanalyzeApplySummary(
      total: docs.length,
      updated: updated,
      skipped: skipped,
      failed: failed,
    );
    debugPrint(
      '[WARDROBE_REANALYZE_APPLY_SUMMARY] total=${summary.total} '
      'updated=${summary.updated} skipped=${summary.skipped} '
      'failed=${summary.failed}',
    );
    return summary;
  }

  static Map<String, dynamic> _metadataPatchFromPipeline(
    ClothingAnalyzerPipelineResult pipeline,
  ) {
    return {
      ...metadataFieldsFromPipeline(pipeline),
      'metadata_reanalyzed_at': FieldValue.serverTimestamp(),
    };
  }

  /// Metadata fields debug reanalyze may persist. Never includes V2 identity.
  static const Set<String> allowedMetadataKeys = {
    'patterns',
    'logo_prominence',
    'visual_description',
    'visual_identity',
    'identity_confidence',
    'confidence',
    'metadata_reanalyzed_at',
  };

  static const Set<String> protectedIdentityKeys = {
    'canonicalType',
    'canonicalFamily',
    'bodySlots',
    'layerPosition',
    'colorProfile',
    'warmth',
    'formality',
    'outfitFunctions',
    'uiProjection',
    'accessoryGroup',
    'multiplicity',
    'userOverrideFields',
    'fieldSources',
    'fieldConfidence',
    'analyzerProvenance',
  };

  static Map<String, dynamic> metadataFieldsFromPipeline(
    ClothingAnalyzerPipelineResult pipeline,
  ) {
    final patch = <String, dynamic>{};
    if (pipeline.patterns.isNotEmpty) {
      patch['patterns'] = pipeline.patterns;
    }
    if (pipeline.logoProminence.isNotEmpty &&
        pipeline.logoProminence != 'unknown') {
      patch['logo_prominence'] = pipeline.logoProminence;
    }
    if (pipeline.visualDescription.isNotEmpty) {
      patch['visual_description'] = pipeline.visualDescription;
    }
    if (pipeline.visualIdentity.isNotEmpty) {
      patch['visual_identity'] = pipeline.visualIdentity;
    }
    if (pipeline.identityConfidence != null) {
      patch['identity_confidence'] = pipeline.identityConfidence;
    }
    if (pipeline.analyzerConfidence != null) {
      patch['confidence'] = pipeline.analyzerConfidence;
    }
    return patch;
  }

  /// Applies allowed metadata onto a stored item without touching V2 identity
  /// or user-correction provenance. Does not write Firestore.
  static Map<String, dynamic> mergeMetadataPatch(
    Map<String, dynamic> stored,
    Map<String, dynamic> metadataFields,
  ) {
    final out = Map<String, dynamic>.from(stored);
    for (final entry in metadataFields.entries) {
      if (protectedIdentityKeys.contains(entry.key)) continue;
      if (!allowedMetadataKeys.contains(entry.key)) continue;
      out[entry.key] = entry.value;
    }
    return out;
  }
}

class WardrobeReanalyzeApplySummary {
  const WardrobeReanalyzeApplySummary({
    required this.total,
    required this.updated,
    required this.skipped,
    required this.failed,
  });

  final int total;
  final int updated;
  final int skipped;
  final int failed;
}
