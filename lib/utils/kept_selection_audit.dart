import 'package:flutter/foundation.dart';

import 'home_debug_logging.dart';

/// Audit logs for [fillKeptFromScored] kept-list selection (no behavior change).
void logKeptSelectionPassStart({
  required String pass,
  required int keptCountBefore,
  required int candidateLimit,
  required int scoredCount,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[KEPT_SELECTION_AUDIT] '
    'phase=pass_start '
    'pass=$pass '
    'keptCountBefore=$keptCountBefore '
    'candidateLimit=$candidateLimit '
    'scoredCount=$scoredCount',
  );
}

void logKeptSelectionScoredHead({
  required String pass,
  required List<KeptSelectionScoredRow> rows,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    debugPrint(
      '[KEPT_SELECTION_AUDIT] '
      'phase=scored_head '
      'pass=$pass '
      'scoredRank=${i + 1} '
      'candidate=${row.candidate} '
      'withOuter=${row.withOuter} '
      'wholeScore=${row.wholeScore.toStringAsFixed(2)} '
      'eow=${row.eow.isNaN ? 'n/a' : row.eow.toStringAsFixed(2)} '
      'ct=${row.ct.isNaN ? 'n/a' : row.ct.toStringAsFixed(2)} '
      'eowDeltaFromCt=${row.eowDeltaFromCt.isNaN ? 'n/a' : row.eowDeltaFromCt.toStringAsFixed(2)} '
      'bottomId=${row.bottomId}',
    );
  }
}

void logKeptSelectionKept({
  required String pass,
  required int slot,
  required int scoredRank,
  required String candidate,
  required bool withOuter,
  required double wholeScore,
  required double eow,
  required double ct,
  required String bottomId,
  String? baseComboKey,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  final eowDelta = eow.isNaN || ct.isNaN ? double.nan : (eow - ct).abs();
  debugPrint(
    '[KEPT_SELECTION_AUDIT] '
    'phase=kept '
    'action=kept '
    'pass=$pass '
    'slot=$slot '
    'scoredRank=$scoredRank '
    'candidate=$candidate '
    'withOuter=$withOuter '
    'wholeScore=${wholeScore.toStringAsFixed(2)} '
    'eow=${eow.isNaN ? 'n/a' : eow.toStringAsFixed(2)} '
    'ct=${ct.isNaN ? 'n/a' : ct.toStringAsFixed(2)} '
    'eowDeltaFromCt=${eowDelta.isNaN ? 'n/a' : eowDelta.toStringAsFixed(2)} '
    'bottomId=$bottomId'
    '${baseComboKey != null && baseComboKey.isNotEmpty ? ' baseComboKey=$baseComboKey' : ''}',
  );
}

void logKeptSelectionSkipped({
  required String pass,
  required int scoredRank,
  required String reason,
  required String candidate,
  required bool withOuter,
  required double wholeScore,
  required double eow,
  required double ct,
  String? bottomId,
  String? incumbentCandidate,
  bool? incumbentWithOuter,
  double? incumbentWholeScore,
  int? incumbentScoredRank,
  double? incumbentEow,
  double? incumbentCt,
  int? keptCount,
  int? candidateLimit,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  final eowDelta = eow.isNaN || ct.isNaN ? double.nan : (eow - ct).abs();
  final incumbentDelta = incumbentEow != null &&
          incumbentCt != null &&
          !incumbentEow.isNaN &&
          !incumbentCt.isNaN
      ? (incumbentEow - incumbentCt).abs()
      : null;
  debugPrint(
    '[KEPT_SELECTION_AUDIT] '
    'phase=skipped '
    'action=skipped '
    'pass=$pass '
    'scoredRank=$scoredRank '
    'reason=$reason '
    'candidate=$candidate '
    'withOuter=$withOuter '
    'wholeScore=${wholeScore.toStringAsFixed(2)} '
    'eow=${eow.isNaN ? 'n/a' : eow.toStringAsFixed(2)} '
    'ct=${ct.isNaN ? 'n/a' : ct.toStringAsFixed(2)} '
    'eowDeltaFromCt=${eowDelta.isNaN ? 'n/a' : eowDelta.toStringAsFixed(2)}'
    '${bottomId != null && bottomId.isNotEmpty ? ' bottomId=$bottomId' : ''}'
    '${keptCount != null ? ' keptCount=$keptCount' : ''}'
    '${candidateLimit != null ? ' candidateLimit=$candidateLimit' : ''}'
    '${incumbentCandidate != null ? ' incumbentCandidate=$incumbentCandidate' : ''}'
    '${incumbentWithOuter != null ? ' incumbentWithOuter=$incumbentWithOuter' : ''}'
    '${incumbentWholeScore != null ? ' incumbentWholeScore=${incumbentWholeScore.toStringAsFixed(2)}' : ''}'
    '${incumbentScoredRank != null ? ' incumbentScoredRank=$incumbentScoredRank' : ''}'
    '${incumbentEow != null ? ' incumbentEow=${incumbentEow.isNaN ? 'n/a' : incumbentEow.toStringAsFixed(2)}' : ''}'
    '${incumbentCt != null ? ' incumbentCt=${incumbentCt.isNaN ? 'n/a' : incumbentCt.toStringAsFixed(2)}' : ''}'
    '${incumbentDelta != null ? ' incumbentEowDeltaFromCt=${incumbentDelta.toStringAsFixed(2)}' : ''}',
  );
}

void logKeptSelectionHeadToHead({
  required String pass,
  required String baseComboKey,
  required String winnerCandidate,
  required bool winnerWithOuter,
  required double winnerWholeScore,
  required double winnerEow,
  required int winnerScoredRank,
  required String loserCandidate,
  required bool loserWithOuter,
  required double loserWholeScore,
  required double loserEow,
  required int loserScoredRank,
  required double ct,
  required String winReason,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  final winnerDelta =
      winnerEow.isNaN || ct.isNaN ? double.nan : (winnerEow - ct).abs();
  final loserDelta =
      loserEow.isNaN || ct.isNaN ? double.nan : (loserEow - ct).abs();
  debugPrint(
    '[KEPT_SELECTION_AUDIT] '
    'phase=head_to_head '
    'pass=$pass '
    'baseComboKey=$baseComboKey '
    'winReason=$winReason '
    'winnerScoredRank=$winnerScoredRank '
    'winner=$winnerCandidate '
    'winnerWithOuter=$winnerWithOuter '
    'winnerWholeScore=${winnerWholeScore.toStringAsFixed(2)} '
    'winnerEow=${winnerEow.isNaN ? 'n/a' : winnerEow.toStringAsFixed(2)} '
    'winnerEowDeltaFromCt=${winnerDelta.isNaN ? 'n/a' : winnerDelta.toStringAsFixed(2)} '
    'loserScoredRank=$loserScoredRank '
    'loser=$loserCandidate '
    'loserWithOuter=$loserWithOuter '
    'loserWholeScore=${loserWholeScore.toStringAsFixed(2)} '
    'loserEow=${loserEow.isNaN ? 'n/a' : loserEow.toStringAsFixed(2)} '
    'loserEowDeltaFromCt=${loserDelta.isNaN ? 'n/a' : loserDelta.toStringAsFixed(2)} '
    'ct=${ct.isNaN ? 'n/a' : ct.toStringAsFixed(2)}',
  );
}

void logKeptSelectionPassEnd({
  required String pass,
  required List<KeptSelectionKeptRow> keptRows,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[KEPT_SELECTION_AUDIT] '
    'phase=pass_end '
    'pass=$pass '
    'keptCount=${keptRows.length}',
  );
  for (var i = 0; i < keptRows.length; i++) {
    final row = keptRows[i];
    debugPrint(
      '[KEPT_SELECTION_AUDIT] '
      'phase=pass_end_kept '
      'pass=$pass '
      'slot=$i '
      'candidate=${row.candidate} '
      'withOuter=${row.withOuter} '
      'wholeScore=${row.wholeScore.toStringAsFixed(2)} '
      'eow=${row.eow.isNaN ? 'n/a' : row.eow.toStringAsFixed(2)} '
      'ct=${row.ct.isNaN ? 'n/a' : row.ct.toStringAsFixed(2)} '
      'eowDeltaFromCt=${row.eowDeltaFromCt.isNaN ? 'n/a' : row.eowDeltaFromCt.toStringAsFixed(2)} '
      'scoredRank=${row.scoredRank}',
    );
  }
}

class KeptSelectionScoredRow {
  final String candidate;
  final bool withOuter;
  final double wholeScore;
  final double eow;
  final double ct;
  final double eowDeltaFromCt;
  final String bottomId;

  const KeptSelectionScoredRow({
    required this.candidate,
    required this.withOuter,
    required this.wholeScore,
    required this.eow,
    required this.ct,
    required this.eowDeltaFromCt,
    required this.bottomId,
  });
}

class KeptSelectionKeptRow {
  final String candidate;
  final bool withOuter;
  final double wholeScore;
  final double eow;
  final double ct;
  final double eowDeltaFromCt;
  final int scoredRank;

  const KeptSelectionKeptRow({
    required this.candidate,
    required this.withOuter,
    required this.wholeScore,
    required this.eow,
    required this.ct,
    required this.eowDeltaFromCt,
    required this.scoredRank,
  });
}
