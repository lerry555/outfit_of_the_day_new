import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import '../data/outfit_intent.dart';
import '../data/stylist_intent.dart';
import '../utils/outfit_intent_scorer.dart';

/// Debug-only zber údajov z outfit pipeline (M2+).
class StylistChatOutfitDebugCollector {
  StylistIntent? stylistIntent;
  OutfitIntent? outfitIntent;
  final List<StylistChatIntentCandidateDebug> candidateScores = [];
  bool usedFallback = false;
  String? pickMode;
  OutfitPreview? finalPreview;
  OutfitIntentScoreBreakdown? winnerBreakdown;

  int _nextCandidateIndex = 0;

  void recordStylistIntent(StylistIntent intent) {
    stylistIntent = intent;
  }

  void recordOutfitIntent(OutfitIntent intent) {
    outfitIntent = intent;
  }

  void recordCandidate({
    required OutfitPreview preview,
    required OutfitIntentScoreBreakdown breakdown,
  }) {
    candidateScores.add(
      StylistChatIntentCandidateDebug(
        candidateIndex: _nextCandidateIndex++,
        items: _previewItemsLabel(preview),
        breakdown: breakdown,
      ),
    );
  }

  void markFallback() {
    usedFallback = true;
  }

  void markPickMode(String mode) {
    pickMode = mode;
  }

  void recordFinalPreview({
    required OutfitPreview preview,
    OutfitIntentScoreBreakdown? breakdown,
  }) {
    finalPreview = preview;
    winnerBreakdown = breakdown;
  }

  StylistChatPipelinePromptReport buildReport({
    required String prompt,
    OutfitPreview? preview,
  }) {
    final winner = preview ?? finalPreview;
    OutfitIntentScoreBreakdown? breakdown = winnerBreakdown;
    if (winner != null && outfitIntent != null && breakdown == null) {
      breakdown = OutfitIntentScorer.evaluate(
        preview: winner,
        intent: outfitIntent!,
        baseScore: 0,
      );
    }
    return StylistChatPipelinePromptReport(
      prompt: prompt,
      stylistIntent: stylistIntent,
      outfitIntent: outfitIntent,
      candidateScores: List<StylistChatIntentCandidateDebug>.from(
        candidateScores,
      ),
      finalPreview: winner,
      winnerBreakdown: breakdown,
      usedFallback: usedFallback,
      pickMode: pickMode,
    );
  }

  void printReport({required String prompt, OutfitPreview? preview}) {
    buildReport(prompt: prompt, preview: preview).printToConsole();
  }

  static String _previewItemsLabel(OutfitPreview preview) {
    return [
      preview.top.label,
      preview.bottom.label,
      preview.shoes.label,
      if (preview.outerwear != null) preview.outerwear!.label,
    ].join(' + ');
  }
}

class StylistChatIntentCandidateDebug {
  final int candidateIndex;
  final String items;
  final OutfitIntentScoreBreakdown breakdown;

  const StylistChatIntentCandidateDebug({
    required this.candidateIndex,
    required this.items,
    required this.breakdown,
  });
}

class StylistChatPipelinePromptReport {
  final String prompt;
  final StylistIntent? stylistIntent;
  final OutfitIntent? outfitIntent;
  final List<StylistChatIntentCandidateDebug> candidateScores;
  final OutfitPreview? finalPreview;
  final OutfitIntentScoreBreakdown? winnerBreakdown;
  final bool usedFallback;
  final String? pickMode;

  const StylistChatPipelinePromptReport({
    required this.prompt,
    this.stylistIntent,
    this.outfitIntent,
    this.candidateScores = const [],
    this.finalPreview,
    this.winnerBreakdown,
    this.usedFallback = false,
    this.pickMode,
  });

  bool get winnerViolatedNonNegotiables =>
      winnerBreakdown?.violatedNonNegotiables.isNotEmpty ?? false;

  void printToConsole() {
    debugPrint('');
    debugPrint('========== STYLIST CHAT DEBUG RUN ==========');
    debugPrint('prompt: $prompt');
    if (stylistIntent != null) {
      debugPrint(stylistIntent!.toLogLine());
    }
    if (outfitIntent != null) {
      debugPrint(outfitIntent!.toLogLine());
    }
    for (final candidate in candidateScores) {
      final b = candidate.breakdown;
      debugPrint(
        'STYLIST CHAT intent_score { '
        'candidateIndex=${candidate.candidateIndex}, '
        'items=${candidate.items}, '
        'baseScore=${b.baseScore.toStringAsFixed(2)}, '
        'intentBonus=${b.intentBonus.toStringAsFixed(2)}, '
        'intentPenalty=${b.intentPenalty.toStringAsFixed(2)}, '
        'finalScore=${b.finalScore.toStringAsFixed(2)}, '
        'matchedIntent=${b.matchedIntent.join("|")}, '
        'violatedNonNegotiables=${b.violatedNonNegotiables.join("|")} '
        '}',
      );
    }
    if (finalPreview != null) {
      debugPrint(
        'STYLIST CHAT debug_final_outfit { '
        'items=${StylistChatOutfitDebugCollector._previewItemsLabel(finalPreview!)}, '
        'pickMode=${pickMode ?? "unknown"}, '
        'usedFallback=$usedFallback, '
        'winnerViolatedNonNegotiables=$winnerViolatedNonNegotiables '
        '}',
      );
    } else {
      debugPrint(
        'STYLIST CHAT debug_final_outfit { '
        'items=null, pickMode=${pickMode ?? "none"}, '
        'usedFallback=$usedFallback, '
        'winnerViolatedNonNegotiables=false '
        '}',
      );
    }
    debugPrint('============================================');
    debugPrint('');
  }
}
