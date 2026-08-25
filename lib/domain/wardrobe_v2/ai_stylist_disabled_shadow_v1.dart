import 'ai_stylist_role_clients_v1.dart';
import 'flexible_candidate_matrix_v2.dart';
import 'frozen_outfit_decision_envelope_v1.dart';
import 'frozen_outfit_decision_orchestration_v1.dart';
import 'frozen_outfit_decision_request_v1.dart';
import 'frozen_outfit_explanation_contract_v1.dart';
import 'wardrobe_v2_resolver.dart';

/// Intentionally unwired production-source shadow seam. No screen, callable,
/// router, Firebase configuration, or provider transport imports this module.
const bool aiStylistDisabledShadowV1Enabled = false;

enum AiStylistShadowContextStatusV1 {
  model,
  deterministicKnownContextFallback,
  deterministicClarificationFallback,
  contractFailure,
}

class AiStylistShadowContextOutcomeV1 {
  const AiStylistShadowContextOutcomeV1({
    required this.response,
    required this.status,
  });
  final ContextClarificationResponseV1 response;
  final AiStylistShadowContextStatusV1 status;
}

class AiStylistShadowTraceV1 {
  AiStylistShadowTraceV1({
    required this.context,
    required Iterable<String> generatedCandidateIds,
    this.decision,
    this.explanation,
    required Map<String, Duration> stageTimings,
  }) : generatedCandidateIds = List.unmodifiable(generatedCandidateIds),
       stageTimings = Map.unmodifiable(stageTimings);

  final AiStylistShadowContextOutcomeV1 context;
  final List<String> generatedCandidateIds;
  final FrozenOutfitDecisionOutcomeV1? decision;
  final FrozenOutfitExplanationResultV1? explanation;
  final Map<String, Duration> stageTimings;

  bool get fallbackUsed =>
      context.status != AiStylistShadowContextStatusV1.model ||
      decision?.kind == FrozenOutfitDecisionOutcomeKindV1.transportFailure ||
      decision?.kind == FrozenOutfitDecisionOutcomeKindV1.contractFailure ||
      explanation?.usedFallback == true;
}

class AiStylistDisabledShadowRunnerV1 {
  const AiStylistDisabledShadowRunnerV1({
    required this.contextClient,
    required this.decisionClient,
    required this.explanationClient,
  });

  final ContextDecisionClientV1 contextClient;
  final FinalCandidateDecisionClientV1 decisionClient;
  final ExplanationClientV1 explanationClient;

  Future<AiStylistShadowTraceV1> run({
    required ContextClarificationRequestV1 contextRequest,
    required FrozenOutfitResolvedContextV1 resolvedContext,
    required Iterable<ResolvedWardrobeItemV2> wardrobe,
    required V2CandidateMatrixContext candidateContext,
    required Iterable<String> authoritativeOwnedItemIds,
  }) async {
    final timings = <String, Duration>{};
    final contextClock = Stopwatch()..start();
    final context = await _resolveContext(contextRequest);
    contextClock.stop();
    timings['context'] = contextClock.elapsed;

    final generationClock = Stopwatch()..start();
    final generated = V2FlexibleCandidateMatrix.generate(
      wardrobe: wardrobe,
      context: candidateContext,
    );
    generationClock.stop();
    timings['candidateGeneration'] = generationClock.elapsed;
    return _runFromGeneratedCandidates(
      context: context,
      resolvedContext: resolvedContext,
      generated: generated,
      authoritativeOwnedItemIds: authoritativeOwnedItemIds,
      stageTimings: timings,
    );
  }

  /// Uses the exact V2 candidate set already finalized by an existing host.
  /// This is the shadow-only bridge for the legacy final-review runner; it
  /// never generates a replacement candidate set.
  Future<AiStylistShadowTraceV1> runFromGeneratedCandidates({
    required ContextClarificationRequestV1 contextRequest,
    required FrozenOutfitResolvedContextV1 resolvedContext,
    required Iterable<V2FlexibleCandidate> generatedCandidates,
    required Iterable<String> authoritativeOwnedItemIds,
  }) async {
    final timings = <String, Duration>{};
    final contextClock = Stopwatch()..start();
    final context = await _resolveContext(contextRequest);
    contextClock.stop();
    timings['context'] = contextClock.elapsed;
    timings['candidateGeneration'] = Duration.zero;
    return _runFromGeneratedCandidates(
      context: context,
      resolvedContext: resolvedContext,
      generated: generatedCandidates,
      authoritativeOwnedItemIds: authoritativeOwnedItemIds,
      stageTimings: timings,
    );
  }

  Future<AiStylistShadowTraceV1> _runFromGeneratedCandidates({
    required AiStylistShadowContextOutcomeV1 context,
    required FrozenOutfitResolvedContextV1 resolvedContext,
    required Iterable<V2FlexibleCandidate> generated,
    required Iterable<String> authoritativeOwnedItemIds,
    required Map<String, Duration> stageTimings,
  }) async {
    final timings = stageTimings;

    // A clarification or stop is not silently converted to an outfit choice.
    if (context.response.action != ContextClarificationActionV1.proceed) {
      return AiStylistShadowTraceV1(
        context: context,
        generatedCandidateIds: const [],
        stageTimings: timings,
      );
    }

    final frozenCandidates = generated
        .map(FrozenOutfitCandidateV1.fromFlexibleCandidate)
        .toList(growable: false);

    final request = FrozenOutfitDecisionRequestV1(
      resolvedContext: resolvedContext,
      frozenCandidates: frozenCandidates,
    );
    final decisionClock = Stopwatch()..start();
    final decision = await FrozenOutfitDecisionOrchestratorV1(decisionClient)
        .decide(
          request: request,
          frozenCandidates: frozenCandidates,
          authoritativeOwnedItemIds: authoritativeOwnedItemIds,
        );
    decisionClock.stop();
    timings['decision'] = decisionClock.elapsed;

    final explanationClock = Stopwatch()..start();
    final explanation =
        await FrozenOutfitExplanationOrchestratorV1(explanationClient).explain(
          FrozenOutfitExplanationRequestV1.fromValidatedEnvelope(
            envelope: decision.envelope,
            resolvedContext: resolvedContext,
          ),
        );
    explanationClock.stop();
    timings['explanation'] = explanationClock.elapsed;

    return AiStylistShadowTraceV1(
      context: context,
      generatedCandidateIds: generated.map(
        (candidate) => candidate.candidateId,
      ),
      decision: decision,
      explanation: explanation,
      stageTimings: timings,
    );
  }

  Future<AiStylistShadowContextOutcomeV1> _resolveContext(
    ContextClarificationRequestV1 request,
  ) async {
    try {
      final response = ContextClarificationTransportAdapterV1.parse(
        await contextClient.interpret(request),
      );
      if (!response.isAllowedFor(request)) {
        return _deterministicContextFallback(
          request,
          AiStylistShadowContextStatusV1.contractFailure,
        );
      }
      return AiStylistShadowContextOutcomeV1(
        response: response,
        status: AiStylistShadowContextStatusV1.model,
      );
    } catch (_) {
      return _deterministicContextFallback(
        request,
        MinimalNecessaryClarificationPolicyV1.next(request) == null
            ? AiStylistShadowContextStatusV1.deterministicKnownContextFallback
            : AiStylistShadowContextStatusV1.deterministicClarificationFallback,
      );
    }
  }

  AiStylistShadowContextOutcomeV1 _deterministicContextFallback(
    ContextClarificationRequestV1 request,
    AiStylistShadowContextStatusV1 status,
  ) {
    final needed = MinimalNecessaryClarificationPolicyV1.next(request);
    return AiStylistShadowContextOutcomeV1(
      response: needed == null
          ? ContextClarificationResponseV1(
              action: ContextClarificationActionV1.proceed,
            )
          : ContextClarificationResponseV1(
              action: ContextClarificationActionV1.askClarification,
              clarificationFactKey: needed.factKey,
            ),
      status: status,
    );
  }
}
