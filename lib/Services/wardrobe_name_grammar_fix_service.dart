import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/clothing_knowledge_base.dart';
import '../utils/slovak_display_name.dart';

/// One pending name grammar correction from dry-run.
class WardrobeNameGrammarPendingFix {
  const WardrobeNameGrammarPendingFix({
    required this.itemId,
    required this.oldName,
    required this.newName,
  });

  final String itemId;
  final String oldName;
  final String newName;
}

/// Safe Slovak adjective agreement fixes for wardrobe item names (name field only).
abstract final class WardrobeNameGrammarFixService {
  static bool dryRunCompletedThisSession = false;
  static List<WardrobeNameGrammarPendingFix> pendingFixes =
      <WardrobeNameGrammarPendingFix>[];

  static bool get canApply =>
      dryRunCompletedThisSession && pendingFixes.isNotEmpty;

  static Future<WardrobeNameGrammarFixSummary> dryRun() async {
    if (!kDebugMode) {
      throw Exception('Name grammar fix is developer-only.');
    }
    return _run(apply: false);
  }

  static Future<WardrobeNameGrammarFixSummary> apply() async {
    if (!kDebugMode) {
      throw Exception('Name grammar fix is developer-only.');
    }
    if (!dryRunCompletedThisSession) {
      throw Exception('Run dry-run first in this session.');
    }
    if (pendingFixes.isEmpty) {
      throw Exception('No pending grammar fixes from dry-run.');
    }
    return _run(apply: true);
  }

  static void clearSession() {
    dryRunCompletedThisSession = false;
    pendingFixes = <WardrobeNameGrammarPendingFix>[];
  }

  static Future<WardrobeNameGrammarFixSummary> _run({
    required bool apply,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Musíš byť prihlásený.');
    }

    if (apply) {
      return _applyPending(user.uid);
    }

    return _collectPendingFixes(user.uid);
  }

  static Future<WardrobeNameGrammarFixSummary> _collectPendingFixes(
    String uid,
  ) async {
    pendingFixes = <WardrobeNameGrammarPendingFix>[];
    dryRunCompletedThisSession = false;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('wardrobe')
        .get();

    var skipped = 0;
    var failed = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      try {
        final fix = _planFix(doc.id, data);
        if (fix == null) {
          skipped++;
          continue;
        }

        pendingFixes.add(fix);
        debugPrint(
          '[NAME_GRAMMAR_FIX_DRY_RUN] itemId=${fix.itemId} '
          'oldName=${fix.oldName} newName=${fix.newName}',
        );
      } catch (e, st) {
        failed++;
        debugPrint(
          '[NAME_GRAMMAR_FIX_DRY_RUN] itemId=${doc.id} FAILED error=$e',
        );
        if (kDebugMode) debugPrint('$st');
      }
    }

    dryRunCompletedThisSession = true;

    final summary = WardrobeNameGrammarFixSummary(
      total: snap.docs.length,
      fixed: pendingFixes.length,
      skipped: skipped,
      failed: failed,
      applied: false,
    );
    _logSummary(summary);
    return summary;
  }

  static Future<WardrobeNameGrammarFixSummary> _applyPending(String uid) async {
    final fixes = List<WardrobeNameGrammarPendingFix>.from(pendingFixes);
    var failed = 0;

    for (final fix in fixes) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('wardrobe')
            .doc(fix.itemId)
            .update({'name': fix.newName});

        debugPrint(
          '[NAME_GRAMMAR_FIX_APPLY] itemId=${fix.itemId} '
          'oldName=${fix.oldName} newName=${fix.newName}',
        );
      } catch (e, st) {
        failed++;
        debugPrint(
          '[NAME_GRAMMAR_FIX_APPLY] itemId=${fix.itemId} FAILED error=$e',
        );
        if (kDebugMode) debugPrint('$st');
      }
    }

    final appliedCount = fixes.length - failed;
    clearSession();

    final summary = WardrobeNameGrammarFixSummary(
      total: fixes.length,
      fixed: appliedCount,
      skipped: 0,
      failed: failed,
      applied: true,
    );
    _logSummary(summary);
    return summary;
  }

  static WardrobeNameGrammarPendingFix? _planFix(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final oldName = _readName(data);
    if (oldName.isEmpty) return null;

    final newName = fixSlovakWardrobeNameGrammar(
      name: oldName,
      subCategoryKey: _readSubCategoryKey(data),
      canonicalType: _readCanonicalType(data),
    );

    if (newName == null || newName.trim() == oldName.trim()) return null;

    return WardrobeNameGrammarPendingFix(
      itemId: documentId,
      oldName: oldName,
      newName: newName,
    );
  }

  static void _logSummary(WardrobeNameGrammarFixSummary summary) {
    debugPrint(
      '[NAME_GRAMMAR_FIX_SUMMARY] total=${summary.total} fixed=${summary.fixed} '
      'skipped=${summary.skipped} failed=${summary.failed} '
      'applied=${summary.applied}',
    );
  }

  static String _readName(Map<String, dynamic> data) {
    return (data['name'] ?? data['title'] ?? '').toString().trim();
  }

  static String? _readSubCategoryKey(Map<String, dynamic> data) {
    final v = (data['subCategoryKey'] ?? data['subCategory'] ?? '')
        .toString()
        .trim();
    return v.isEmpty ? null : v;
  }

  static String? _readCanonicalType(Map<String, dynamic> data) {
    final direct = (data['canonical_type'] ?? data['canonicalType'] ?? '')
        .toString()
        .trim();
    if (direct.isNotEmpty) return direct;
    return ClothingKnowledgeBase.itemCanonicalType(data);
  }
}

class WardrobeNameGrammarFixSummary {
  const WardrobeNameGrammarFixSummary({
    required this.total,
    required this.fixed,
    required this.skipped,
    required this.failed,
    required this.applied,
  });

  final int total;
  final int fixed;
  final int skipped;
  final int failed;
  final bool applied;
}
