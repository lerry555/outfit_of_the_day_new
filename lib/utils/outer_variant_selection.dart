import 'package:flutter/foundation.dart';

import 'home_debug_logging.dart';

/// CT bands used to pick no-outer vs with-outer for the same base combo.
class OuterVariantComfortBands {
  final double ct;
  final double tolerance;
  final double hardMax;

  const OuterVariantComfortBands({
    required this.ct,
    required this.tolerance,
    required this.hardMax,
  });
}

enum OuterVariantSelection {
  noOuter,
  withOuter,
}

extension OuterVariantSelectionWire on OuterVariantSelection {
  String get wireName {
    switch (this) {
      case OuterVariantSelection.noOuter:
        return 'no_outer';
      case OuterVariantSelection.withOuter:
        return 'with_outer';
    }
  }
}

class OuterVariantDecision {
  final OuterVariantSelection selected;
  final String reason;

  const OuterVariantDecision({
    required this.selected,
    required this.reason,
  });
}

/// Pick no-outer vs with-outer for the same top+bottom+footwear base combo.
OuterVariantDecision decideOuterVariant({
  required double noOuterScore,
  required double withOuterScore,
  required double noOuterEow,
  required double withOuterEow,
  required OuterVariantComfortBands bands,
}) {
  final ct = bands.ct;
  final tolerance = bands.tolerance;
  final hardMax = bands.hardMax;

  final noInTolerance = (noOuterEow - ct).abs() <= tolerance;
  final withInTolerance = (withOuterEow - ct).abs() <= tolerance;
  final noDelta = (noOuterEow - ct).abs();
  final withDelta = (withOuterEow - ct).abs();
  final noTooCold = noOuterEow < ct - tolerance;

  if (noInTolerance && (!withInTolerance || withOuterEow > hardMax)) {
    return const OuterVariantDecision(
      selected: OuterVariantSelection.noOuter,
      reason: 'no_outer_inside_with_outer_above_hardmax',
    );
  }

  if (noTooCold && withDelta < noDelta) {
    return const OuterVariantDecision(
      selected: OuterVariantSelection.withOuter,
      reason: 'with_outer_closer',
    );
  }

  if (noInTolerance && withInTolerance) {
    if (noOuterScore >= withOuterScore) {
      return const OuterVariantDecision(
        selected: OuterVariantSelection.noOuter,
        reason: 'score_tiebreak',
      );
    }
    return const OuterVariantDecision(
      selected: OuterVariantSelection.withOuter,
      reason: 'score_tiebreak',
    );
  }

  if (withDelta < noDelta) {
    return const OuterVariantDecision(
      selected: OuterVariantSelection.withOuter,
      reason: 'closer_to_ct',
    );
  }
  if (noDelta < withDelta) {
    return const OuterVariantDecision(
      selected: OuterVariantSelection.noOuter,
      reason: 'closer_to_ct',
    );
  }

  if (noOuterScore >= withOuterScore) {
    return const OuterVariantDecision(
      selected: OuterVariantSelection.noOuter,
      reason: 'score_tiebreak',
    );
  }
  return const OuterVariantDecision(
    selected: OuterVariantSelection.withOuter,
    reason: 'score_tiebreak',
  );
}

void logOuterVariantDecision({
  required String baseCombo,
  required OuterVariantSelection selected,
  required double noOuterEow,
  required double withOuterEow,
  required double ct,
  required String reason,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[OUTER_VARIANT_DECISION] '
    'baseCombo=$baseCombo '
    'selected=${selected.wireName} '
    'noOuterEow=${noOuterEow.toStringAsFixed(2)} '
    'withOuterEow=${withOuterEow.toStringAsFixed(2)} '
    'ct=${ct.toStringAsFixed(2)} '
    'reason=$reason',
  );
}
