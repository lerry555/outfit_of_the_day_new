import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import '../data/outfit_intent.dart';
import 'activity_outfit_identity.dart';
import 'comfort_target.dart';
import 'outfit_intent_scorer.dart';

/// Dôvod vyradenia kandidáta medzi matrix a final review.
enum CandidateEliminationReason {
  duplicateItems('duplicate_items'),
  lowerComfort('lower_comfort'),
  lowerIntent('lower_intent'),
  duplicateTop('duplicate_top'),
  duplicateBottom('duplicate_bottom'),
  duplicateShoes('duplicate_shoes'),
  failedValidation('failed_validation'),
  filteredBeforeFinalReview('filtered_before_final_review');

  const CandidateEliminationReason(this.wireName);
  final String wireName;
}

class ScoredOutfitCandidate {
  const ScoredOutfitCandidate({
    required this.preview,
    required this.comfort,
    required this.finalScore,
    required this.intentBonus,
    required this.intentPenalty,
    required this.baseScore,
    required this.ids,
    required this.signature,
    required this.matrixIndex,
  });

  final OutfitPreview preview;
  final double comfort;
  final double finalScore;
  final double intentBonus;
  final double intentPenalty;
  final double baseScore;
  final Set<String> ids;
  final String signature;
  final int matrixIndex;

  String get itemsLabel {
    final parts = [
      preview.top.label,
      preview.bottom.label,
      preview.shoes.label,
    ];
    if (preview.outerwear != null) {
      parts.add(preview.outerwear!.label);
    }
    return parts.join(' + ');
  }
}

class CandidatePipelineResult {
  const CandidatePipelineResult({
    required this.matrixGenerated,
    required this.afterFiltering,
    required this.forFinalReview,
    required this.topPick,
  });

  final int matrixGenerated;
  final int afterFiltering;
  final List<ScoredOutfitCandidate> forFinalReview;
  final ScoredOutfitCandidate topPick;

  void logSummary({required int finalWinner}) {
    debugPrint(
      'STYLIST CHAT candidate_pipeline { '
      'matrixGenerated=$matrixGenerated, '
      'afterFiltering=$afterFiltering, '
      'sentToFinalReview=${forFinalReview.length}, '
      'finalWinner=$finalWinner '
      '}',
    );
  }
}

/// Výber kandidátov medzi matrix generátorom a AI final review.
class StylistChatCandidatePipeline {
  const StylistChatCandidatePipeline._();

  static const minFinalReviewCandidates = 4;

  static void _logElimination({
    required int candidateIndex,
    required ScoredOutfitCandidate candidate,
    required CandidateEliminationReason reason,
    String? detail,
  }) {
    debugPrint(
      'STYLIST CHAT candidate_eliminated { '
      'candidateIndex=$candidateIndex, '
      'matrixIndex=${candidate.matrixIndex}, '
      'items=${candidate.itemsLabel}, '
      'reason=${reason.wireName}, '
      'comfort=${candidate.comfort.toStringAsFixed(2)}, '
      'finalScore=${candidate.finalScore.toStringAsFixed(2)}, '
      'detail=${detail ?? "none"} '
      '}',
    );
  }

  static String _previewSignature(OutfitPreview preview) {
    return OutfitGenerationService.combinationSignature(
      preview.top.item,
      preview.bottom.item,
      preview.shoes.item,
      preview.outerwear?.item,
    );
  }

  static CandidateEliminationReason _rankingEliminationReason({
    required ScoredOutfitCandidate candidate,
    required ScoredOutfitCandidate cutoff,
  }) {
    final comfortGap = cutoff.comfort - candidate.comfort;
    final intentGap =
        (cutoff.intentBonus - cutoff.intentPenalty) -
        (candidate.intentBonus - candidate.intentPenalty);
    if (comfortGap > 0.05 && comfortGap >= intentGap) {
      return CandidateEliminationReason.lowerComfort;
    }
    if (intentGap > 0.05) {
      return CandidateEliminationReason.lowerIntent;
    }
    return CandidateEliminationReason.filteredBeforeFinalReview;
  }

  static CandidateEliminationReason? _duplicateSlotReason({
    required ScoredOutfitCandidate candidate,
    required List<ScoredOutfitCandidate> selected,
  }) {
    final topId =
        OutfitGenerationService.wardrobeItemId(candidate.preview.top.item);
    final bottomId =
        OutfitGenerationService.wardrobeItemId(candidate.preview.bottom.item);
    final shoeId =
        OutfitGenerationService.wardrobeItemId(candidate.preview.shoes.item);

    if (topId.isNotEmpty &&
        selected.any(
          (picked) =>
              OutfitGenerationService.wardrobeItemId(picked.preview.top.item) ==
              topId,
        )) {
      return CandidateEliminationReason.duplicateTop;
    }
    if (bottomId.isNotEmpty &&
        selected.any(
          (picked) =>
              OutfitGenerationService.wardrobeItemId(
                picked.preview.bottom.item,
              ) ==
              bottomId,
        )) {
      return CandidateEliminationReason.duplicateBottom;
    }
    if (shoeId.isNotEmpty &&
        selected.any(
          (picked) =>
              OutfitGenerationService.wardrobeItemId(
                picked.preview.shoes.item,
              ) ==
              shoeId,
        )) {
      return CandidateEliminationReason.duplicateShoes;
    }
    return null;
  }

  /// Zoradí matrix kandidátov, zaloguje vyradenia a vyberie top N pre final review.
  static CandidatePipelineResult selectForFinalReview({
    required List<OutfitPreview> matrixPreviews,
    required List<ScoredOutfitCandidate> scoredCandidates,
    Set<String> previousOutfitItemIds = const {},
  }) {
    final matrixGenerated = matrixPreviews.length;
    var eliminationLogIndex = 0;

    final ranked = List<ScoredOutfitCandidate>.from(scoredCandidates)
      ..sort((a, b) {
        final scoreCmp = b.finalScore.compareTo(a.finalScore);
        if (scoreCmp != 0) return scoreCmp;
        final comfortCmp = b.comfort.compareTo(a.comfort);
        if (comfortCmp != 0) return comfortCmp;
        return a.matrixIndex.compareTo(b.matrixIndex);
      });

    if (previousOutfitItemIds.isNotEmpty && ranked.length > 1) {
      ranked.sort((a, b) {
        final aRepeats = _overlapsPrevious(a.ids, previousOutfitItemIds);
        final bRepeats = _overlapsPrevious(b.ids, previousOutfitItemIds);
        if (aRepeats != bRepeats) return aRepeats ? 1 : -1;
        final scoreCmp = b.finalScore.compareTo(a.finalScore);
        if (scoreCmp != 0) return scoreCmp;
        return b.comfort.compareTo(a.comfort);
      });
    }

    final deduped = <ScoredOutfitCandidate>[];
    final seenSignatures = <String>{};
    for (final candidate in ranked) {
      if (candidate.signature.isEmpty) {
        _logElimination(
          candidateIndex: eliminationLogIndex++,
          candidate: candidate,
          reason: CandidateEliminationReason.failedValidation,
          detail: 'empty_signature',
        );
        continue;
      }
      if (seenSignatures.contains(candidate.signature)) {
        _logElimination(
          candidateIndex: eliminationLogIndex++,
          candidate: candidate,
          reason: CandidateEliminationReason.duplicateItems,
        );
        continue;
      }
      seenSignatures.add(candidate.signature);
      deduped.add(candidate);
    }

    final afterFiltering = deduped.length;
    if (deduped.isEmpty) {
      debugPrint(
        'STYLIST CHAT candidate_pipeline { '
        'matrixGenerated=$matrixGenerated, '
        'afterFiltering=0, '
        'sentToFinalReview=0, '
        'finalWinner=0 '
        '}',
      );
      throw StateError('No scored candidates after pipeline filtering');
    }

    final reviewTarget = deduped.length >= minFinalReviewCandidates
        ? minFinalReviewCandidates
        : deduped.length;

    final forReview = <ScoredOutfitCandidate>[];
    final deferred = <ScoredOutfitCandidate>[];

    for (final candidate in deduped) {
      if (forReview.length >= reviewTarget) break;
      final duplicateReason = _duplicateSlotReason(
        candidate: candidate,
        selected: forReview,
      );
      if (duplicateReason != null) {
        deferred.add(candidate);
        continue;
      }
      forReview.add(candidate);
    }

    for (final candidate in deferred) {
      if (forReview.length >= reviewTarget) {
        break;
      }
      forReview.add(candidate);
    }

    for (final candidate in deferred) {
      if (forReview.contains(candidate)) continue;
      _logElimination(
        candidateIndex: eliminationLogIndex++,
        candidate: candidate,
        reason: _duplicateSlotReason(
              candidate: candidate,
              selected: forReview,
            ) ??
            CandidateEliminationReason.filteredBeforeFinalReview,
      );
    }

    final cutoff = forReview.length >= reviewTarget
        ? forReview[reviewTarget - 1]
        : forReview.last;
    for (final candidate in deduped) {
      if (forReview.contains(candidate)) continue;
      _logElimination(
        candidateIndex: eliminationLogIndex++,
        candidate: candidate,
        reason: _rankingEliminationReason(
          candidate: candidate,
          cutoff: cutoff,
        ),
      );
    }

    return CandidatePipelineResult(
      matrixGenerated: matrixGenerated,
      afterFiltering: afterFiltering,
      forFinalReview: forReview,
      topPick: forReview.first,
    );
  }

  static bool _overlapsPrevious(
    Set<String> ids,
    Set<String> previousOutfitItemIds,
  ) {
    if (previousOutfitItemIds.isEmpty) return false;
    for (final id in ids) {
      if (id.isNotEmpty && previousOutfitItemIds.contains(id)) return true;
    }
    return false;
  }

  static ScoredOutfitCandidate? scoreCandidate({
    required OutfitPreview preview,
    required OutfitIntent outfitIntent,
    required ComfortTarget comfortTarget,
    required int matrixIndex,
    bool wetGroundMuddy = false,
    required void Function({
      required OutfitPreview preview,
      required OutfitIntentScoreBreakdown breakdown,
    })
    logIntentCandidate,
  }) {
    final warmth = calculateEffectiveOutfitWarmthForPreview(
      preview,
      target: comfortTarget,
    );
    final breakdown = OutfitIntentScorer.evaluate(
      preview: preview,
      intent: outfitIntent,
      baseScore: warmth.comfortScore,
    );
    logIntentCandidate(preview: preview, breakdown: breakdown);

    final identity = ActivityOutfitIdentity.evaluate(
      preview: preview,
      intent: outfitIntent,
      wetGroundMuddy: wetGroundMuddy,
    );
    final finalScore = breakdown.finalScore + identity.score;

    final candidate = ScoredOutfitCandidate(
      preview: preview,
      comfort: warmth.comfortScore,
      finalScore: finalScore,
      intentBonus: breakdown.intentBonus,
      intentPenalty: breakdown.intentPenalty,
      baseScore: breakdown.baseScore,
      ids: _previewItemIds(preview),
      signature: _previewSignature(preview),
      matrixIndex: matrixIndex,
    );

    if (breakdown.isExcluded) {
      _logElimination(
        candidateIndex: matrixIndex,
        candidate: candidate,
        reason: CandidateEliminationReason.failedValidation,
        detail: breakdown.violatedNonNegotiables.join('|'),
      );
      return null;
    }

    return candidate;
  }

  static Set<String> _previewItemIds(OutfitPreview preview) {
    return {
      OutfitGenerationService.wardrobeItemId(preview.top.item),
      OutfitGenerationService.wardrobeItemId(preview.bottom.item),
      OutfitGenerationService.wardrobeItemId(preview.shoes.item),
      if (preview.outerwear != null)
        OutfitGenerationService.wardrobeItemId(preview.outerwear!.item),
    }..removeWhere((id) => id.isEmpty);
  }
}
