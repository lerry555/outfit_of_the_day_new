import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/clothing_knowledge_base.dart';
import '../utils/home_wardrobe_normalizer.dart';

/// One-time safe KB metadata migration for the signed-in user's wardrobe.
abstract final class WardrobeMetadataMigrationService {
  static const int migrationVersion = 2;
  static const int mikinaMidLayerMigrationVersion = 1;
  static const int minConfidenceThreshold = 70;

  static const Set<String> _mikinaSubCategories = {
    'mikina_klasicka',
    'mikina_na_zips',
    'mikina_s_kapucnou',
    'mikina_oversize',
    'sport_mikina',
  };

  static const Set<String> _knownLayers = {
    ClothingLayerRole.baseLayer,
    ClothingLayerRole.midLayer,
    ClothingLayerRole.outerLayer,
    ClothingLayerRole.bottom,
    ClothingLayerRole.footwear,
    ClothingLayerRole.accessory,
  };

  /// Applies safe metadata migration for all wardrobe items (Firestore writes).
  static Future<WardrobeMetadataMigrationSummary> apply({
    bool dryRun = false,
  }) async {
    if (!kDebugMode && !dryRun) {
      throw Exception('Metadata migration is developer-only.');
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

    var updated = 0;
    var skipped = 0;
    var failed = 0;

    for (final doc in snap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;

      try {
        final decision = _planForItem(data);
        _logItem(doc.id, data, decision);

        if (!decision.shouldUpdate) {
          skipped++;
          continue;
        }

        if (!dryRun) {
          await doc.reference.update(decision.patch);
        }
        updated++;
      } catch (e, st) {
        failed++;
        debugPrint('[METADATA_MIGRATION] itemId=${doc.id} FAILED error=$e');
        if (kDebugMode) debugPrint('$st');
      }
    }

    final summary = WardrobeMetadataMigrationSummary(
      total: snap.docs.length,
      updated: updated,
      skipped: skipped,
      failed: failed,
      dryRun: dryRun,
    );
    _logSummary(summary);
    return summary;
  }

  /// Targeted one-time fix for older wardrobe documents where mikiny were stored
  /// as outer_layer. Updates only layer metadata for mikina subtypes.
  static Future<WardrobeMetadataMigrationSummary> applyMikinaMidLayerFix({
    bool dryRun = false,
  }) async {
    if (!kDebugMode && !dryRun) {
      throw Exception('Mikina layer migration is developer-only.');
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

    var updated = 0;
    var skipped = 0;
    var failed = 0;

    for (final doc in snap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;

      try {
        if (!_isMikinaItem(data)) {
          skipped++;
          continue;
        }

        final currentLayer =
            (data['layer_role'] ?? data['layerRole'] ?? '').toString().trim();
        final currentLayerV2 = (data['layer_role'] ?? '').toString().trim();
        final currentLayerLegacy = (data['layerRole'] ?? '').toString().trim();
        if (_norm(currentLayerV2) == ClothingLayerRole.midLayer &&
            _norm(currentLayerLegacy) == ClothingLayerRole.midLayer) {
          skipped++;
          continue;
        }

        final patch = <String, dynamic>{
          'layer_role': ClothingLayerRole.midLayer,
          'layerRole': ClothingLayerRole.midLayer,
          'mikina_mid_layer_migrated_at': FieldValue.serverTimestamp(),
          'mikina_mid_layer_migration_version': mikinaMidLayerMigrationVersion,
        };

        _logMikinaLayerFix(doc.id, data, currentLayer);
        if (!dryRun) {
          await doc.reference.update(patch);
        }
        updated++;
      } catch (e, st) {
        failed++;
        debugPrint('[MIKINA_LAYER_MIGRATION] itemId=${doc.id} FAILED error=$e');
        if (kDebugMode) debugPrint('$st');
      }
    }

    final summary = WardrobeMetadataMigrationSummary(
      total: snap.docs.length,
      updated: updated,
      skipped: skipped,
      failed: failed,
      dryRun: dryRun,
    );
    _logMikinaLayerSummary(summary);
    return summary;
  }

  static _MigrationDecision _planForItem(Map<String, dynamic> raw) {
    final old = _snapshotFromStored(raw);
    final norm = HomeWardrobeNormalizer.normalize(raw, log: false);

    if (!_hasSufficientConfidence(raw, norm)) {
      return _MigrationDecision.skip(reason: 'confidence_too_low');
    }

    final resolvedCanonical = _resolveCanonical(raw, norm);
    final kb = resolvedCanonical.isNotEmpty
        ? ClothingKnowledgeBase.findByCanonicalType(resolvedCanonical)
        : null;

    final layerRole = kb?.layerRole ?? norm.layerRole;
    if (!_isKnownLayer(layerRole)) {
      return _MigrationDecision.skip(reason: 'layer_undetermined');
    }

    final categoryKey = _nonEmpty(kb?.category, norm.categoryKey, old.categoryKey);
    final subCategoryKey =
        _nonEmpty(kb?.subcategory, norm.subCategoryKey, old.subCategoryKey);
    final warmthLevel = kb?.warmthDefault ?? norm.warmthLevel;
    final formality = kb?.formalityDefault ?? norm.formality;
    final mainGroupKey = kb != null
        ? kb.mainCategory
        : HomeWardrobeNormalizer.mainGroupForLegacyCategory(categoryKey);

    final patch = <String, dynamic>{
      'layer_role': layerRole,
      'layerRole': layerRole,
      'warmth_level': warmthLevel,
      'warmthLevel': warmthLevel,
      'formality': formality,
      'categoryKey': categoryKey,
      'subCategoryKey': subCategoryKey,
      'mainGroupKey': mainGroupKey,
      'kb_migrated_at': FieldValue.serverTimestamp(),
      'kb_migration_version': migrationVersion,
    };

    if (resolvedCanonical.isNotEmpty) {
      patch['canonical_type'] = resolvedCanonical;
      patch['canonicalType'] = resolvedCanonical;
    }

    if (!_metadataDiffers(old, patch, resolvedCanonical)) {
      return _MigrationDecision.skip(reason: 'already_up_to_date');
    }

    return _MigrationDecision.update(
      patch: patch,
      old: old,
      resolvedCanonical: resolvedCanonical,
      layerRole: layerRole,
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
    );
  }

  static bool _hasSufficientConfidence(
    Map<String, dynamic> raw,
    HomeNormalizedWardrobeItem norm,
  ) {
    if (norm.kbApplied || norm.legacyFallbackApplied) return true;

    final storedConfidence = _storedAnalyzerConfidence(raw);
    if (storedConfidence != null && storedConfidence < minConfidenceThreshold) {
      return false;
    }

    return _isKnownLayer(norm.layerRole);
  }

  static int? _storedAnalyzerConfidence(Map<String, dynamic> raw) {
    final direct = num.tryParse((raw['confidence'] ?? '').toString());
    if (direct != null && direct.isFinite) {
      return direct.round().clamp(0, 100);
    }

    for (final key in ['hiddenAiMetadata', 'aiMetadata', 'metadata']) {
      final nested = raw[key];
      if (nested is Map) {
        final n = num.tryParse(
          (nested['confidence'] ?? '').toString(),
        );
        if (n != null && n.isFinite) {
          return n.round().clamp(0, 100);
        }
      }
    }
    return null;
  }

  static String _resolveCanonical(
    Map<String, dynamic> raw,
    HomeNormalizedWardrobeItem norm,
  ) {
    final oldCanonical = _storedCanonical(raw);
    final oldKb = oldCanonical.isNotEmpty
        ? ClothingKnowledgeBase.findByCanonicalType(oldCanonical)
        : null;

    if (oldKb != null) {
      return oldKb.canonicalType;
    }

    if (norm.kbApplied && norm.canonicalType.isNotEmpty) {
      return norm.canonicalType;
    }

    if (oldCanonical.isNotEmpty) {
      return oldCanonical;
    }

    return norm.canonicalType;
  }

  static bool _metadataDiffers(
    _MetadataSnapshot old,
    Map<String, dynamic> patch,
    String resolvedCanonical,
  ) {
    if (_norm(old.canonicalType) != _norm(resolvedCanonical)) return true;
    if (_norm(old.layerRole) != _norm((patch['layer_role'] ?? '').toString())) {
      return true;
    }
    if (_norm(old.categoryKey) != _norm((patch['categoryKey'] ?? '').toString())) {
      return true;
    }
    if (_norm(old.subCategoryKey) !=
        _norm((patch['subCategoryKey'] ?? '').toString())) {
      return true;
    }
    final warmth = num.tryParse((patch['warmth_level'] ?? '').toString());
    if (warmth != null && warmth.round() != old.warmthLevel) return true;
    final formality = num.tryParse((patch['formality'] ?? '').toString());
    if (formality != null && formality.round() != old.formality) return true;
    if (_norm(old.mainGroupKey) !=
        _norm((patch['mainGroupKey'] ?? '').toString())) {
      return true;
    }
    return false;
  }

  static _MetadataSnapshot _snapshotFromStored(Map<String, dynamic> item) {
    final warmth = num.tryParse(
      (item['warmth_level'] ?? item['warmthLevel'] ?? '').toString(),
    );
    final formality = num.tryParse((item['formality'] ?? '').toString());
    return _MetadataSnapshot(
      name: (item['name'] ?? '').toString().trim(),
      canonicalType: _storedCanonical(item),
      layerRole:
          (item['layer_role'] ?? item['layerRole'] ?? '').toString().trim(),
      categoryKey:
          (item['categoryKey'] ?? item['category'] ?? '').toString().trim(),
      subCategoryKey: (item['subCategoryKey'] ?? item['subCategory'] ?? '')
          .toString()
          .trim(),
      mainGroupKey:
          (item['mainGroupKey'] ?? item['mainGroup'] ?? '').toString().trim(),
      warmthLevel: warmth?.round() ?? 0,
      formality: formality?.round() ?? 0,
    );
  }

  static String _storedCanonical(Map<String, dynamic> item) {
    final direct = (item['canonical_type'] ?? item['canonicalType'] ?? '')
        .toString()
        .trim();
    if (direct.isNotEmpty) return direct;
    return ClothingKnowledgeBase.itemCanonicalType(item) ?? '';
  }

  static String _nonEmpty(String? a, String b, String c) {
    if (a != null && a.trim().isNotEmpty) return a.trim();
    if (b.trim().isNotEmpty) return b.trim();
    return c.trim();
  }

  static bool _isKnownLayer(String layer) => _knownLayers.contains(layer);

  static String _norm(String s) => s.trim().toLowerCase();

  static bool _isMikinaItem(Map<String, dynamic> item) {
    final norm = HomeWardrobeNormalizer.normalize(item, log: false);
    if (_mikinaSubCategories.contains(norm.subCategoryKey)) return true;
    if (_norm(norm.categoryKey) == 'mikiny') return true;

    final canonical = _storedCanonical(item);
    if (canonical.isNotEmpty) {
      final kb = ClothingKnowledgeBase.findByCanonicalType(canonical);
      if (kb != null &&
          (_mikinaSubCategories.contains(kb.subcategory) ||
              _norm(kb.category) == 'mikiny')) {
        return true;
      }
    }

    final sub = _norm(
      (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString(),
    );
    if (_mikinaSubCategories.contains(sub)) return true;
    if (_norm((item['categoryKey'] ?? item['category'] ?? '').toString()) ==
        'mikiny') {
      return true;
    }

    final text = [
      item['name'],
      item['type'],
      item['type_pretty'],
      item['primary_type'],
      item['canonical_type'],
      item['canonicalType'],
    ].map((v) => (v ?? '').toString().toLowerCase()).join(' ');
    return text.contains('mikina') ||
        text.contains('hoodie') ||
        text.contains('sweatshirt');
  }

  static void _logMikinaLayerFix(
    String documentId,
    Map<String, dynamic> raw,
    String oldLayer,
  ) {
    final name = (raw['name'] ?? '').toString().trim();
    debugPrint(
      '[MIKINA_LAYER_MIGRATION]\n'
      'itemId=$documentId\n'
      'name=$name\n'
      'oldLayer=$oldLayer\n'
      'newLayer=${ClothingLayerRole.midLayer}',
    );
  }

  static void _logMikinaLayerSummary(
    WardrobeMetadataMigrationSummary summary,
  ) {
    debugPrint(
      '[MIKINA_LAYER_MIGRATION_SUMMARY] total=${summary.total} '
      'updated=${summary.updated} skipped=${summary.skipped} '
      'failed=${summary.failed}'
      '${summary.dryRun ? ' dry_run=true' : ''}',
    );
  }

  static void _logItem(
    String documentId,
    Map<String, dynamic> raw,
    _MigrationDecision decision,
  ) {
    final name = (raw['name'] ?? '').toString().trim();
    if (!decision.shouldUpdate) {
      debugPrint(
        '[METADATA_MIGRATION] itemId=$documentId name=$name '
        'SKIPPED reason=${decision.skipReason ?? 'unknown'}',
      );
      return;
    }

    final old = decision.old!;
    debugPrint(
      '[METADATA_MIGRATION]\n'
      'itemId=$documentId\n'
      'name=$name\n'
      'oldCanonical=${old.canonicalType}\n'
      'newCanonical=${decision.resolvedCanonical}\n'
      'oldLayer=${old.layerRole}\n'
      'newLayer=${decision.layerRole}\n'
      'oldCategory=${old.categoryKey}\n'
      'newCategory=${decision.categoryKey}\n'
      'oldSubCategory=${old.subCategoryKey}\n'
      'newSubCategory=${decision.subCategoryKey}',
    );
  }

  static void _logSummary(WardrobeMetadataMigrationSummary summary) {
    debugPrint(
      '[METADATA_MIGRATION_SUMMARY] total=${summary.total} '
      'updated=${summary.updated} skipped=${summary.skipped} '
      'failed=${summary.failed}'
      '${summary.dryRun ? ' dry_run=true' : ''}',
    );
  }
}

class WardrobeMetadataMigrationSummary {
  const WardrobeMetadataMigrationSummary({
    required this.total,
    required this.updated,
    required this.skipped,
    required this.failed,
    this.dryRun = false,
  });

  final int total;
  final int updated;
  final int skipped;
  final int failed;
  final bool dryRun;
}

class _MetadataSnapshot {
  const _MetadataSnapshot({
    required this.name,
    required this.canonicalType,
    required this.layerRole,
    required this.categoryKey,
    required this.subCategoryKey,
    required this.mainGroupKey,
    required this.warmthLevel,
    required this.formality,
  });

  final String name;
  final String canonicalType;
  final String layerRole;
  final String categoryKey;
  final String subCategoryKey;
  final String mainGroupKey;
  final int warmthLevel;
  final int formality;
}

class _MigrationDecision {
  const _MigrationDecision._({
    required this.shouldUpdate,
    this.patch = const {},
    this.old,
    this.resolvedCanonical = '',
    this.layerRole = '',
    this.categoryKey = '',
    this.subCategoryKey = '',
    this.skipReason,
  });

  factory _MigrationDecision.update({
    required Map<String, dynamic> patch,
    required _MetadataSnapshot old,
    required String resolvedCanonical,
    required String layerRole,
    required String categoryKey,
    required String subCategoryKey,
  }) {
    return _MigrationDecision._(
      shouldUpdate: true,
      patch: patch,
      old: old,
      resolvedCanonical: resolvedCanonical,
      layerRole: layerRole,
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
    );
  }

  factory _MigrationDecision.skip({required String reason}) {
    return _MigrationDecision._(shouldUpdate: false, skipReason: reason);
  }

  final bool shouldUpdate;
  final Map<String, dynamic> patch;
  final _MetadataSnapshot? old;
  final String resolvedCanonical;
  final String layerRole;
  final String categoryKey;
  final String subCategoryKey;
  final String? skipReason;
}
