import 'package:flutter/foundation.dart';

import 'home_debug_logging.dart';

/// When the generator must include an outer layer in the matrix.
enum OuterwearPolicy {
  required,
  optional,
  forbidden,
}

extension OuterwearPolicyWire on OuterwearPolicy {
  String get wireName {
    switch (this) {
      case OuterwearPolicy.required:
        return 'required';
      case OuterwearPolicy.optional:
        return 'optional';
      case OuterwearPolicy.forbidden:
        return 'forbidden';
    }
  }
}

/// Resolve outerwear matrix policy from weather (Phase 1).
OuterwearPolicy resolveOuterwearPolicy({
  required int tempC,
  required bool isRainy,
  required bool isWindy,
}) {
  if (tempC < 10 || isRainy || isWindy) {
    return OuterwearPolicy.required;
  }
  if (tempC >= 10 && tempC < 20) {
    return OuterwearPolicy.optional;
  }
  return OuterwearPolicy.forbidden;
}

String outerwearPolicyReason({
  required int tempC,
  required bool isRainy,
  required bool isWindy,
  required OuterwearPolicy policy,
}) {
  switch (policy) {
    case OuterwearPolicy.required:
      if (tempC < 10) {
        return 'temp_below_10C';
      }
      if (isRainy) {
        return 'rain';
      }
      if (isWindy) {
        return 'wind';
      }
      return 'required_weather';
    case OuterwearPolicy.optional:
      return 'dry_mild_band_10_19C';
    case OuterwearPolicy.forbidden:
      if (tempC >= 20) {
        return 'warm_dry_temp_gte_20C';
      }
      return 'no_outer_layer_needed';
  }
}

void logOuterPolicy({
  required OuterwearPolicy policy,
  required String reason,
  required int tempC,
  required bool isRainy,
  required bool isWindy,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[OUTER_POLICY] '
    'policy=${policy.wireName} '
    'reason=$reason '
    'temp=${tempC}°C '
    'rain=$isRainy '
    'wind=$isWindy',
  );
}

void logOuterOptionalCandidate({
  required int candidateIndex,
  required bool withOuter,
  required double eow,
  required double ct,
  String? outerLabel,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[OUTER_OPTIONAL_CANDIDATE] '
    'candidateIndex=$candidateIndex '
    'withOuter=$withOuter '
    'eow=${eow.toStringAsFixed(2)} '
    'ct=${ct.toStringAsFixed(2)}'
    '${outerLabel != null && outerLabel.isNotEmpty ? ' outer=$outerLabel' : ''}',
  );
}

void logOuterMatrixCombinationCounts({
  required int nullOuterCombinations,
  required int outerCombinations,
  required int outerCandidateSlots,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[OUTER_MATRIX_AUDIT] '
    'phase=combination_counts '
    'nullOuterCombinations=$nullOuterCombinations '
    'outerCombinations=$outerCombinations '
    'outerCandidateSlots=$outerCandidateSlots',
  );
}

void logOuterMatrixRejection({
  required String candidate,
  required String reason,
  String? detail,
  String phase = 'matrix_filter',
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[OUTER_MATRIX_AUDIT] '
    'phase=$phase '
    'withOuter=false '
    'candidate=$candidate '
    'rejection=$reason'
    '${detail != null && detail.isNotEmpty ? ' detail=$detail' : ''}',
  );
}

void logOuterMatrixAudit({
  required String candidate,
  required bool withOuter,
  required double eow,
  required double ct,
  required double wholeScore,
  required String phase,
  int? rank,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[OUTER_MATRIX_AUDIT] '
    'phase=$phase '
    'candidate=$candidate '
    'withOuter=$withOuter '
    'eow=${eow.isNaN ? 'n/a' : eow.toStringAsFixed(2)} '
    'ct=${ct.isNaN ? 'n/a' : ct.toStringAsFixed(2)} '
    'wholeScore=${wholeScore.toStringAsFixed(2)}'
    '${rank != null ? ' rank=$rank' : ''}',
  );
}

void logOuterMatrixScoredSummary({
  required int nullOuterScored,
  required int outerScored,
  required int nullOuterRejectedByFilter,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[OUTER_MATRIX_AUDIT] '
    'phase=scored_summary '
    'nullOuterScored=$nullOuterScored '
    'outerScored=$outerScored '
    'nullOuterRejectedByFilter=$nullOuterRejectedByFilter',
  );
}
