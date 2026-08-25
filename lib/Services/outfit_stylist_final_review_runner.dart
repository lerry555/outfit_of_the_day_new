import 'package:flutter/foundation.dart';

import '../debug/ai_stylist_dev_shadow_host_v1.dart';
import '../domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import '../domain/wardrobe_v2/flexible_outfit_result_v2.dart';
import 'home_final_review_payload.dart';
import 'home_generation_telemetry.dart';
import 'home_stylist_final_review_service.dart';
import 'outfit_generation_service.dart';

/// Shared final review for Home and Stylist. Candidate identity, validity and
/// fallback ranking remain V2-native; the reviewer may only select an index.
class OutfitStylistFinalReviewPick {
  const OutfitStylistFinalReviewPick({
    required this.outfit,
    this.reason = '',
    this.usedReviewer = false,
  });

  final V2FlexibleOutfitResult outfit;
  final String reason;
  final bool usedReviewer;
}

class OutfitStylistFinalReviewRunner {
  const OutfitStylistFinalReviewRunner({this.devShadowHost});

  /// Debug-only sidecar. Null keeps the production callsite disconnected from
  /// any configurable provider; the default host itself is compile-time gated.
  final AiStylistDevShadowHostV1? devShadowHost;

  Future<V2FlexibleOutfitResult> selectBestCandidate({
    required List<V2FlexibleCandidate> candidates,
    required OutfitWeatherSnapshot weather,
    Map<String, dynamic>? weatherContext,
    Map<String, dynamic>? userStylePreferences,
    String logPrefix = '[STYLIST_FINAL_REVIEW_V2]',
    HomeGenerationTrace? trace,
  }) async {
    final pick = await selectBestCandidateDetailed(
      candidates: candidates,
      weather: weather,
      weatherContext: weatherContext,
      userStylePreferences: userStylePreferences,
      logPrefix: logPrefix,
      trace: trace,
    );
    return pick.outfit;
  }

  Future<OutfitStylistFinalReviewPick> selectBestCandidateDetailed({
    required List<V2FlexibleCandidate> candidates,
    required OutfitWeatherSnapshot weather,
    Map<String, dynamic>? weatherContext,
    Map<String, dynamic>? userStylePreferences,
    String logPrefix = '[STYLIST_FINAL_REVIEW_V2]',
    HomeGenerationTrace? trace,
  }) async {
    if (candidates.isEmpty) {
      throw ArgumentError('candidates must not be empty');
    }
    if (candidates.length == 1) {
      return _finishLegacyPick(
        OutfitStylistFinalReviewPick(outfit: candidates.first.outfit),
        candidates: candidates,
        weather: weather,
        allowRealProviderSmoke: _isStylistSmokeEligible(logPrefix),
      );
    }

    final payload = HomeFinalReviewPayload.fromCandidates(candidates);
    final requestEnvelope = <String, dynamic>{
      'weatherContext':
          weatherContext ??
          <String, dynamic>{
            'tempC': weather.tempC,
            'isRainy': weather.isRainy,
            'isWindy': weather.isWindy,
            'seasonKey': weather.seasonKey,
          },
      'candidates': payload,
      if (userStylePreferences != null && userStylePreferences.isNotEmpty)
        'userStylePreferences': userStylePreferences,
    };
    final payloadBytes = HomeFinalReviewPayload.utf8ByteLength(requestEnvelope);
    trace?.candidateCount = payload.length;
    trace?.payloadBytes = payloadBytes;
    trace?.finalReviewAttempted = true;
    debugPrint(
      '$logPrefix FINAL_REVIEW_REQUEST_START candidateCount=${payload.length} '
      'payloadBytes=$payloadBytes',
    );
    final started = Stopwatch()..start();
    try {
      final result = await const HomeStylistFinalReviewService()
          .reviewCandidates(
            weatherContext:
                weatherContext ??
                <String, dynamic>{
                  'tempC': weather.tempC,
                  'isRainy': weather.isRainy,
                  'isWindy': weather.isWindy,
                  'seasonKey': weather.seasonKey,
                },
            candidates: payload,
            userStylePreferences: userStylePreferences,
          )
          .timeout(kHomeFinalReviewTimeout);
      final elapsed = started.elapsedMilliseconds;
      trace?.mark('FINAL_REVIEW_BACKEND_MS', started);
      trace?.mark('FINAL_REVIEW_TOTAL_MS', started);
      debugPrint(
        '$logPrefix elapsedMs=$elapsed fallback=${result.fallback} '
        'payloadBytes=$payloadBytes',
      );
      final index = result.selectedCandidateIndex;
      if (!result.fallback && index >= 0 && index < candidates.length) {
        trace?.finalReviewOutcome = 'success';
        debugPrint('$logPrefix selected=$index fallback=false');
        return _finishLegacyPick(
          OutfitStylistFinalReviewPick(
            outfit: candidates[index].outfit,
            reason: result.reason,
            usedReviewer: true,
          ),
          candidates: candidates,
          weather: weather,
          allowRealProviderSmoke: _isStylistSmokeEligible(logPrefix),
        );
      }
      trace?.finalReviewOutcome = 'invalid';
      trace?.fallbackType = 'final_review_invalid_response';
    } catch (error) {
      final elapsed = started.elapsedMilliseconds;
      trace?.mark('FINAL_REVIEW_BACKEND_MS', started);
      trace?.mark('FINAL_REVIEW_TOTAL_MS', started);
      final timedOut = error.toString().toLowerCase().contains('timeout');
      trace?.finalReviewOutcome = timedOut ? 'timeout' : 'failure';
      trace?.fallbackType = timedOut
          ? 'final_review_timeout'
          : 'final_review_network_failure';
      debugPrint(
        '$logPrefix reviewer_error=$error '
        'elapsedMs=$elapsed '
        'fallback=true',
      );
    }
    return _finishLegacyPick(
      OutfitStylistFinalReviewPick(outfit: candidates.first.outfit),
      candidates: candidates,
      weather: weather,
      allowRealProviderSmoke: _isStylistSmokeEligible(logPrefix),
    );
  }

  OutfitStylistFinalReviewPick _finishLegacyPick(
    OutfitStylistFinalReviewPick legacyPick, {
    required List<V2FlexibleCandidate> candidates,
    required OutfitWeatherSnapshot weather,
    required bool allowRealProviderSmoke,
  }) {
    // The legacy pick already exists. This fire-and-forget debug sidecar has no
    // return channel into Home/Stylist state, cache, persistence or UI.
    (devShadowHost ?? const AiStylistDevShadowHostV1())
        .launchAfterLegacyFinalized(
          legacyResult: legacyPick,
          candidates: candidates,
          weatherSignature:
              '${weather.tempC}|${weather.isRainy}|${weather.isWindy}|'
              '${weather.seasonKey}',
          allowRealProviderSmoke: allowRealProviderSmoke,
        );
    return legacyPick;
  }

  @visibleForTesting
  static bool isStylistSmokeEligibleLogPrefix(String logPrefix) =>
      _isStylistSmokeEligible(logPrefix);

  static bool _isStylistSmokeEligible(String logPrefix) =>
      logPrefix.startsWith('[STYLIST CHAT ');
}
