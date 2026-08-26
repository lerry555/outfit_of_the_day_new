import '../style_preferences/style_preference_taste.dart';
import '../style_preferences/styling_presentation.dart';
import 'flexible_outfit_result_v2.dart';
import 'functional_suitability_v1.dart';
import 'native_outfit_engine_v2.dart';
import 'outfit_composition_v2.dart';
import 'outfit_suitability_policy_v2.dart';
import 'wardrobe_v2_adapters.dart';
import 'wardrobe_v2_resolver.dart';

class V2CandidateMatrixContext {
  const V2CandidateMatrixContext({
    this.weatherProtectionRequired = false,
    this.minimumFormality = 1,
    this.requiredFunctions = const {},
    this.requiredOccasions = const {},
    this.preferOnePiece = false,
    this.maxCandidates = 8,
    this.tempC,
    this.feelsLikeC,
    this.eveningTempC,
    this.seasonKey = '',
    this.isRainy = false,
    this.isWindy = false,
    this.outdoor = true,
    this.activityType = '',
    this.occasionId = '',
    this.requestedItemIds = const {},
    this.forbiddenCanonicalTypes = const {},
    this.scoringFormalityFloor,
    this.styleTaste = StylePreferenceTaste.empty,
    this.stylingPresentation = StylingPresentation.noPreference,
    this.activityDurationMinutes,
    this.terrain = '',
    this.wetGroundRisk = false,
  });
  final bool weatherProtectionRequired,
      preferOnePiece,
      isRainy,
      isWindy,
      outdoor;
  final int minimumFormality, maxCandidates;
  final int? tempC, feelsLikeC, eveningTempC, scoringFormalityFloor;
  final int? activityDurationMinutes;
  final String seasonKey;
  final String activityType, occasionId;
  final String terrain;
  final bool wetGroundRisk;
  final Set<String> requiredFunctions, requiredOccasions;
  final Set<String> requestedItemIds, forbiddenCanonicalTypes;
  final StylePreferenceTaste styleTaste;
  final StylingPresentation stylingPresentation;

  int get decisionFormalityFloor => scoringFormalityFloor ?? minimumFormality;
}

class V2FlexibleCandidate {
  const V2FlexibleCandidate({
    required this.candidateId,
    required this.outfit,
    required this.score,
    required this.scoreBreakdown,
    this.functionalAssessment,
  });
  final String candidateId;
  final V2FlexibleOutfitResult outfit;
  final double score;
  final Map<String, double> scoreBreakdown;
  final CandidateFunctionalAssessmentV1? functionalAssessment;
}

/// Shared candidate source for Home and Stylist. It consumes only resolved V2
/// items and never reads names, legacy categories or fixed outfit slots.
abstract final class V2FlexibleCandidateMatrix {
  static List<V2FlexibleCandidate> generate({
    required Iterable<ResolvedWardrobeItemV2> wardrobe,
    required V2CandidateMatrixContext context,
  }) {
    final eligible = wardrobe
        .where(
          (value) =>
              context.requestedItemIds.contains(value.itemId) ||
              FunctionalSuitabilityEvaluatorV1.presentationAllowed(
                value,
                context.stylingPresentation,
              ),
        )
        .where((value) => value.item.formality >= context.minimumFormality)
        .where(
          (value) =>
              context.requiredOccasions.isEmpty ||
              value.item.occasionFit
                  .toSet()
                  .intersection(context.requiredOccasions)
                  .isNotEmpty,
        )
        // Candidate IDs are frozen after this matrix is built, so physically
        // unsuitable footwear must be removed before any model sees it.
        .where(
          (value) =>
              !value.item.bodySlots.contains('feet') ||
              !OutfitSuitabilityPolicyV2.isFootwearPhysicallyUnsuitableForConditions(
                value.item,
                tempC: OutfitSuitabilityPolicyV2.effectiveTempC(
                  tempC: context.tempC,
                  feelsLikeC: context.feelsLikeC,
                ),
                seasonKey: context.seasonKey,
              ),
        )
        .toList(growable: false);
    if (eligible.isEmpty) return const [];
    final results = <V2FlexibleCandidate>[], seen = <String>{};
    for (
      var offset = 0;
      offset < eligible.length && results.length < context.maxCandidates;
      offset++
    ) {
      final rotated = <ResolvedWardrobeItemV2>[
        ...eligible.skip(offset),
        ...eligible.take(offset),
      ];
      for (final preferOnePiece in <bool>{
        context.preferOnePiece,
        false,
        true,
      }) {
        final composition = NativeOutfitEngineV2.compose(
          rotated,
          NativeOutfitRequestV2(
            weatherProtectionRequired: context.weatherProtectionRequired,
            minimumFormality: context.minimumFormality,
            requiredFunctions: context.requiredFunctions,
            preferOnePiece: preferOnePiece,
            tempC: context.tempC,
            feelsLikeC: context.feelsLikeC,
            eveningTempC: context.eveningTempC,
            seasonKey: context.seasonKey,
            activityType: context.activityType,
            requestedItemIds: context.requestedItemIds,
            forbiddenCanonicalTypes: context.forbiddenCanonicalTypes,
            formalityFloor: [
              context.decisionFormalityFloor,
              OutfitSuitabilityPolicyV2.formalityFloor(
                occasionId: context.occasionId,
                activityType: context.activityType,
              ),
            ].reduce((a, b) => a > b ? a : b),
          ),
        );
        if (composition == null) continue;
        final signature = composition.items.map((x) => x.itemId).toList()
          ..sort();
        final key = '${composition.template.name}:${signature.join('|')}';
        if (!seen.add(key)) continue;
        final byId = {for (final value in eligible) value.itemId: value.raw};
        final outfit = V2FlexibleOutfitResult.fromComposition(
          composition,
          weatherProtectionRequired: context.weatherProtectionRequired,
          minimumFormality: context.minimumFormality,
          requiredFunctions: context.requiredFunctions,
          displayByItemId: byId,
        );
        if (outfit.validate().isNotEmpty) continue;
        final functional = FunctionalSuitabilityEvaluatorV1.assessCandidate(
          outfit: outfit,
          source: eligible,
          requirements: ActivityFunctionalRequirementsV1(
            activityType: context.activityType,
            outdoor: context.outdoor,
            isRainy: context.isRainy || context.weatherProtectionRequired,
            wetGroundRisk: context.wetGroundRisk,
            minimumFormality: context.decisionFormalityFloor,
            durationMinutes: context.activityDurationMinutes,
            terrain: context.terrain,
            tempC: OutfitSuitabilityPolicyV2.effectiveTempC(
              tempC: context.tempC,
              feelsLikeC: context.feelsLikeC,
            ),
          ),
        );
        if (!functional.selectable) continue;
        final breakdown = V2FlexibleOutfitScorer.score(outfit, context);
        breakdown['functionalCapability'] = functional.scoreAdjustment;
        results.add(
          V2FlexibleCandidate(
            candidateId: 'v2_${results.length + 1}',
            outfit: outfit,
            score: breakdown.values.fold(0, (a, b) => a + b),
            scoreBreakdown: breakdown,
            functionalAssessment: functional,
          ),
        );
        if (results.length >= context.maxCandidates) break;
      }
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return List.unmodifiable(results);
  }
}

abstract final class V2FlexibleOutfitScorer {
  static Map<String, double> score(
    V2FlexibleOutfitResult outfit,
    V2CandidateMatrixContext context,
  ) {
    final items = outfit.items.map((x) => x.item).toList(growable: false);
    final primary = items.map((x) => x.colorProfile.primary.family).toList();
    final accent = items
        .expand((x) => x.colorProfile.accents.map((c) => c.family))
        .toSet();
    final repeatedPrimary = primary.toSet().length < primary.length;
    final accentEcho = accent.any(primary.contains);
    final formalities = items.map((x) => x.formality).toList();
    final formalitySpread = formalities.isEmpty
        ? 0
        : (formalities.reduce((a, b) => a > b ? a : b) -
              formalities.reduce((a, b) => a < b ? a : b));
    final metals = items
        .expand((x) => [x.colorProfile.metalTone, x.colorProfile.hardwareTone])
        .where((x) => x != 'none' && x != 'unknown')
        .toSet();
    final suitability = Map<String, double>.from(
      OutfitSuitabilityPolicyV2.score(
        outfit: outfit,
        tempC: context.tempC,
        feelsLikeC: context.feelsLikeC,
        eveningTempC: context.eveningTempC,
        isRainy: context.isRainy || context.weatherProtectionRequired,
        isWindy: context.isWindy,
        outdoor: context.outdoor,
        activityType: context.activityType,
        occasionId: context.occasionId,
        minimumFormality: context.decisionFormalityFloor,
        requestedItemIds: context.requestedItemIds,
        forbiddenCanonicalTypes: context.forbiddenCanonicalTypes,
        seasonKey: context.seasonKey,
      ),
    );
    final contextualSet = suitability.remove('setContextual') ?? 0.0;
    return {
      'core': outfit.completeness.coreComplete ? 4 : -20,
      'weather': outfit.completeness.weatherComplete ? 2 : -8,
      'dressCode': outfit.completeness.dressCodeComplete ? 2 : -8,
      'functional': outfit.completeness.functionalComplete ? 2 : -8,
      'formalityCoherence': formalitySpread <= 3 ? 1.5 : -2,
      'primaryColorHarmony': repeatedPrimary ? 0.8 : 0,
      'accentCoordination': accentEcho ? 0.8 : 0,
      'metalHardware': metals.length <= 1 ? 0.5 : 0,
      'setCompatibility': contextualSet,
      'onePiecePreference': context.preferOnePiece
          ? (outfit.template == OutfitTemplateV2.onePiece ? 4.0 : -2.0)
          : 0.0,
      'enhancement': outfit.completeness.enhanced ? 0.4 : 0,
      'accessorySafety': outfit.toComposition().compatibilityErrors().isEmpty
          ? 1
          : -20,
      'styleTaste': StylePreferenceTasteScorer.score(
        outfit: outfit,
        taste: context.styleTaste,
      ),
      ...suitability,
    };
  }
}

abstract final class V2FlexibleSwapOrchestrator {
  static V2FlexibleOutfitResult? replace({
    required V2FlexibleOutfitResult current,
    required String itemId,
    required Iterable<ResolvedWardrobeItemV2> wardrobe,
    required V2CandidateMatrixContext context,
  }) {
    final target = current.items.where((x) => x.itemId == itemId).firstOrNull;
    if (target == null) return null;
    final remaining = current.items
        .where((x) => x.itemId != itemId)
        .map((x) => x.item)
        .toList(growable: false);
    final candidates = wardrobe
        .where((x) => x.itemId != itemId)
        .where(
          (candidate) => SwapCandidateSelectorV2.compatible(
            replaced: target.item,
            candidates: [candidate.item],
            compositionGroup: target.compositionGroup,
            minimumFormality: context.minimumFormality,
            requiredOccasions: context.requiredOccasions,
            requiredFunctions: target.item.outfitFunctions.toSet().intersection(
              context.requiredFunctions,
            ),
            remainingOutfit: remaining,
          ).isNotEmpty,
        );
    V2FlexibleOutfitResult? best;
    var bestScore = double.negativeInfinity;
    for (final candidate in candidates) {
      try {
        final next = current.replaceItem(
          itemId: itemId,
          replacementId: candidate.itemId,
          replacement: candidate.item,
          display: candidate.raw,
        );
        if (next.validate().isNotEmpty) continue;
        final score = V2FlexibleOutfitScorer.score(
          next,
          context,
        ).values.fold(0.0, (a, b) => a + b);
        if (score > bestScore) {
          bestScore = score;
          best = next;
        }
      } on StateError {
        continue;
      }
    }
    return best;
  }
}
