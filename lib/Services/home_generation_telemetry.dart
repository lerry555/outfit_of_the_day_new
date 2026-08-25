import 'package:flutter/foundation.dart';

/// Structured Home generation timings. Never logs secrets or image bytes.
class HomeGenerationTrace {
  HomeGenerationTrace({
    required this.runId,
    required this.day,
    required this.source,
  });

  final String runId;
  final String day;
  final String source;
  final Stopwatch _total = Stopwatch()..start();
  final Map<String, int> stages = <String, int>{};

  bool cacheHit = false;
  int wardrobeItemCount = 0;
  int candidateCountBeforeDedup = 0;
  int candidateCount = 0;
  int payloadBytes = 0;
  bool finalReviewAttempted = false;
  String finalReviewOutcome = 'not_attempted';
  String fallbackType = 'none';

  static String newRunId() =>
      'hgen_${DateTime.now().millisecondsSinceEpoch}';

  int mark(String stage, Stopwatch watch) {
    final ms = watch.elapsedMilliseconds;
    stages[stage] = ms;
    return ms;
  }

  int get totalMs => _total.elapsedMilliseconds;

  void logStart() {
    debugPrint(
      '[HOME_LATENCY] HOME_REQUEST_START runId=$runId day=$day source=$source',
    );
  }

  void logFinish() {
    debugPrint(
      '[HOME_LATENCY] TOTAL_HOME_GENERATION_MS=$totalMs runId=$runId '
      'day=$day source=$source cache=${cacheHit ? 'hit' : 'miss'} '
      'wardrobeItemCount=$wardrobeItemCount '
      'candidateCountBeforeDedup=$candidateCountBeforeDedup '
      'candidateCount=$candidateCount '
      'finalReviewAttempted=$finalReviewAttempted '
      'finalReviewOutcome=$finalReviewOutcome '
      'fallbackType=$fallbackType '
      'payloadBytes=$payloadBytes '
      'WARDROBE_RESOLVE_MS=${stages['WARDROBE_RESOLVE_MS'] ?? 0} '
      'CANDIDATE_MATRIX_MS=${stages['CANDIDATE_MATRIX_MS'] ?? 0} '
      'LOCAL_SCORING_MS=${stages['LOCAL_SCORING_MS'] ?? 0} '
      'FINAL_REVIEW_BACKEND_MS=${stages['FINAL_REVIEW_BACKEND_MS'] ?? 0} '
      'FINAL_REVIEW_PARSE_MS=${stages['FINAL_REVIEW_PARSE_MS'] ?? 0} '
      'FINAL_REVIEW_TOTAL_MS=${stages['FINAL_REVIEW_TOTAL_MS'] ?? 0} '
      'CACHE_WRITE_MS=${stages['CACHE_WRITE_MS'] ?? 0} '
      'DISPLAY_APPLY_MS=${stages['DISPLAY_APPLY_MS'] ?? 0}',
    );
  }
}

/// Client timeout for `finalReviewHomeOutfitCandidates`. Keep until evidence
/// shows healthy responses landing just above this bound.
const Duration kHomeFinalReviewTimeout = Duration(seconds: 8);

/// Client timeout for `generateHomeOutfit`. Independent of final-review.
const Duration kHomeGenerateOutfitTimeout = Duration(seconds: 9);
