import 'flexible_candidate_matrix_v2.dart';
import 'outfit_suitability_policy_v2.dart';
import 'wardrobe_item_v2.dart';
import 'wardrobe_v2_resolver.dart';

class DecisionQualityContext {
  const DecisionQualityContext({
    required this.tempC,
    this.feelsLikeC,
    this.eveningTempC,
    this.isRainy = false,
    this.isWindy = false,
    this.outdoor = true,
    this.activityType = '',
    this.occasionId = '',
    this.minimumFormality,
    this.preferOnePiece = false,
    this.maxCandidates = 8,
    this.requestedItemIds = const {},
    this.forbiddenCanonicalTypes = const {},
    this.requiredOccasions = const {},
  });

  final int tempC;
  final int? feelsLikeC;
  final int? eveningTempC;
  final bool isRainy, isWindy, outdoor, preferOnePiece;
  final String activityType, occasionId;
  final int? minimumFormality;
  final int maxCandidates;
  final Set<String> requestedItemIds, forbiddenCanonicalTypes, requiredOccasions;

  int get resolvedFormalityFloor {
    final policy = OutfitSuitabilityPolicyV2.formalityFloor(
      occasionId: occasionId,
      activityType: activityType,
    );
    final explicit = minimumFormality ?? 1;
    return explicit > policy ? explicit : policy;
  }

  V2CandidateMatrixContext toMatrixContext() {
    return V2CandidateMatrixContext(
      weatherProtectionRequired: isRainy || isWindy,
      minimumFormality: 1,
      scoringFormalityFloor: resolvedFormalityFloor,
      requiredOccasions: requiredOccasions,
      preferOnePiece: preferOnePiece,
      maxCandidates: maxCandidates,
      tempC: tempC,
      feelsLikeC: feelsLikeC,
      eveningTempC: eveningTempC,
      isRainy: isRainy,
      isWindy: isWindy,
      outdoor: outdoor,
      activityType: activityType,
      occasionId: occasionId,
      requestedItemIds: requestedItemIds,
      forbiddenCanonicalTypes: forbiddenCanonicalTypes,
    );
  }
}

class DecisionQualityExclusion {
  const DecisionQualityExclusion({
    required this.itemId,
    required this.canonicalType,
    required this.reason,
  });
  final String itemId, canonicalType, reason;
}

class DecisionQualityReport {
  const DecisionQualityReport({
    required this.context,
    required this.eligibleItemIds,
    required this.excluded,
    required this.candidates,
    required this.winner,
    required this.runnerUp,
    required this.grade,
    required this.trace,
  });

  final DecisionQualityContext context;
  final List<String> eligibleItemIds;
  final List<DecisionQualityExclusion> excluded;
  final List<V2FlexibleCandidate> candidates;
  final V2FlexibleCandidate? winner;
  final V2FlexibleCandidate? runnerUp;
  final DecisionQualityGrade grade;
  final Map<String, Object?> trace;

  List<String> get winnerTypes =>
      winner?.outfit.items.map((x) => x.item.canonicalType).toList() ??
      const [];

  bool winnerHasType(String canonicalType) =>
      winnerTypes.contains(canonicalType);

  bool winnerHasAny(Set<String> types) =>
      winnerTypes.any(types.contains);

  bool winnerHasLayer(String layerPosition) =>
      winner?.outfit.items.any(
        (item) => item.item.layerPosition == layerPosition,
      ) ??
      false;
}

/// Deterministic Home/Stylist decision-quality harness.
abstract final class DecisionQualityHarness {
  static DecisionQualityReport evaluate({
    required Iterable<ResolvedWardrobeItemV2> wardrobe,
    required DecisionQualityContext context,
  }) {
    final matrixContext = context.toMatrixContext();
    final excluded = <DecisionQualityExclusion>[];
    final eligible = <ResolvedWardrobeItemV2>[];
    for (final item in wardrobe) {
      final unsafe = OutfitSuitabilityPolicyV2.isPhysicallyUnsuitable(
        item.item,
        tempC: OutfitSuitabilityPolicyV2.effectiveTempC(
          tempC: context.tempC,
          feelsLikeC: context.feelsLikeC,
        ),
        isRainy: context.isRainy,
        activityType: context.activityType,
      );
      if (unsafe) {
        excluded.add(
          DecisionQualityExclusion(
            itemId: item.itemId,
            canonicalType: item.item.canonicalType,
            reason: _exclusionReason(item.item, context),
          ),
        );
      }
      eligible.add(item);
    }
    final candidates = V2FlexibleCandidateMatrix.generate(
      wardrobe: wardrobe,
      context: matrixContext,
    );
    final winner = candidates.isEmpty ? null : candidates.first;
    final runnerUp = candidates.length > 1 ? candidates[1] : null;
    final grade = winner == null
        ? DecisionQualityGrade.weak
        : OutfitSuitabilityPolicyV2.grade(winner.scoreBreakdown);
    final breakdown = winner?.scoreBreakdown ?? const <String, double>{};
    return DecisionQualityReport(
      context: context,
      eligibleItemIds: eligible.map((e) => e.itemId).toList(growable: false),
      excluded: excluded,
      candidates: candidates,
      winner: winner,
      runnerUp: runnerUp,
      grade: grade,
      trace: <String, Object?>{
        'CONTEXT': {
          'tempC': context.tempC,
          'feelsLikeC': context.feelsLikeC,
          'eveningTempC': context.eveningTempC,
          'isRainy': context.isRainy,
          'isWindy': context.isWindy,
          'outdoor': context.outdoor,
          'activityType': context.activityType,
          'occasionId': context.occasionId,
          'minimumFormality': matrixContext.minimumFormality,
          'formalityFloor': context.resolvedFormalityFloor,
        },
        'REQUIRED_SLOTS': winner == null
            ? const <String>[]
            : winner.outfit.items
                  .where((item) => item.requiredness == 'required')
                  .map((item) => item.compositionGroup)
                  .toList(growable: false),
        'CANDIDATE_COUNT': candidates.length,
        'EXCLUDED_ITEMS': excluded
            .map(
              (e) => <String, String>{
                'itemId': e.itemId,
                'canonicalType': e.canonicalType,
                'reason': e.reason,
              },
            )
            .toList(growable: false),
        'EXCLUSION_REASONS': excluded.map((e) => e.reason).toSet().toList(),
        'TOP_CANDIDATES': candidates
            .take(3)
            .map(
              (c) => <String, Object?>{
                'id': c.candidateId,
                'score': c.score,
                'types': c.outfit.items
                    .map((x) => x.item.canonicalType)
                    .toList(),
              },
            )
            .toList(growable: false),
        'SCORE_COMPONENTS': breakdown,
        'SET_SIGNAL': breakdown['setContextual'] ?? breakdown['setCompatibility'],
        'WEATHER_SIGNAL': breakdown['weatherWarmth'],
        'FORMALITY_SIGNAL': breakdown['formalityWeakestLink'],
        'ACTIVITY_SIGNAL': breakdown['activitySuitability'],
        'USER_PREFERENCE_SIGNAL': breakdown['userPreference'],
        'WINNER': winner?.outfit.items
            .map((x) => '${x.itemId}:${x.item.canonicalType}')
            .toList(),
        'RUNNER_UP': runnerUp?.outfit.items
            .map((x) => '${x.itemId}:${x.item.canonicalType}')
            .toList(),
        'WIN_REASON': OutfitSuitabilityPolicyV2.explanationInputs(
          components: breakdown,
          tempC: context.tempC,
          isRainy: context.isRainy,
          activityType: context.activityType,
          occasionId: context.occasionId,
        ),
        'KNOWN_COMPROMISES': OutfitSuitabilityPolicyV2.knownCompromises(
          breakdown,
        ),
        'GRADE': grade.name,
      },
    );
  }

  static String _exclusionReason(
    WardrobeItemV2 item,
    DecisionQualityContext context,
  ) {
    final temp = OutfitSuitabilityPolicyV2.effectiveTempC(
      tempC: context.tempC,
      feelsLikeC: context.feelsLikeC,
    );
    if (temp != null &&
        temp >= 24 &&
        item.warmth >= 7 &&
        (item.layerPosition == 'outer' ||
            item.layerPosition == 'shell' ||
            item.layerPosition == 'mid')) {
      return 'too_warm_for_temperature';
    }
    if (OutfitSuitabilityPolicyV2.isOpenFootwear(item.canonicalType) &&
        (context.isRainy || (temp != null && temp <= 8))) {
      return 'open_footwear_weather';
    }
    if (OutfitSuitabilityPolicyV2.isTerrainActivity(context.activityType) &&
        OutfitSuitabilityPolicyV2.isFormalFootwear(item.canonicalType)) {
      return 'formal_footwear_terrain';
    }
    return 'physically_unsuitable';
  }
}
