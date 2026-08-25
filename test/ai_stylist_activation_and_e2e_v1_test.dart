import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/outfit_generation_service.dart';
import 'package:outfitofTheDay/Services/outfit_stylist_final_review_runner.dart';
import 'package:outfitofTheDay/debug/ai_stylist_dev_shadow_host_v1.dart';
import 'package:outfitofTheDay/debug/ai_stylist_real_dev_shadow_smoke_trigger_v1.dart';
import 'package:outfitofTheDay/debug/ai_stylist_shadow_activation_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/ai_stylist_disabled_shadow_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/ai_stylist_observability_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/ai_stylist_role_clients_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/ai_stylist_role_fallback_policy_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/ai_stylist_shadow_execution_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_orchestration_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_request_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_explanation_contract_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';

class _ContextClient implements ContextDecisionClientV1 {
  _ContextClient(this.response);
  final Object? response;
  @override
  Future<Object?> interpret(ContextClarificationRequestV1 request) =>
      response is Exception ? Future.error(response!) : Future.value(response);
}

class _DecisionClient implements FinalCandidateDecisionClientV1 {
  _DecisionClient(this.response);
  final Object? response;
  @override
  Future<Object?> decide(FrozenOutfitDecisionRequestV1 request) =>
      response is Exception ? Future.error(response!) : Future.value(response);
}

class _ExplanationClient implements ExplanationClientV1 {
  _ExplanationClient(this.response);
  final Object? response;
  @override
  Future<Object?> explain(FrozenOutfitExplanationRequestV1 request) =>
      response is Exception ? Future.error(response!) : Future.value(response);
}

WardrobeItemV2 _item({
  required String type,
  required String family,
  required List<String> slots,
  required String layer,
}) => WardrobeItemV2(
  canonicalType: type,
  canonicalFamily: family,
  bodySlots: slots,
  layerPosition: layer,
  outfitFunctions: const [],
  colorProfile: const ColorProfileV2(
    primary: SemanticColorV2(family: 'navy'),
    metalTone: 'none',
    hardwareTone: 'none',
  ),
  formality: 3,
  styles: const [],
  occasionFit: const [],
  seasons: const [],
  warmth: 3,
  attributes: const {},
  fieldSources: const {'canonicalType': 'fixture'},
  fieldConfidence: const {'canonicalType': 1.0},
  userOverrideFields: const [],
);

List<ResolvedWardrobeItemV2> _wardrobe() => [
  ResolvedWardrobeItemV2(
    itemId: 'top',
    item: _item(
      type: 't_shirt',
      family: 'top',
      slots: const ['upper_body'],
      layer: 'base',
    ),
    raw: const {},
  ),
  ResolvedWardrobeItemV2(
    itemId: 'bottom',
    item: _item(
      type: 'jeans',
      family: 'bottom',
      slots: const ['lower_body'],
      layer: 'outer',
    ),
    raw: const {},
  ),
  ResolvedWardrobeItemV2(
    itemId: 'shoes',
    item: _item(
      type: 'sneakers',
      family: 'footwear',
      slots: const ['feet'],
      layer: 'not_applicable',
    ),
    raw: const {},
  ),
];

const _matrixContext = V2CandidateMatrixContext(maxCandidates: 3, tempC: 20);

ContextClarificationRequestV1 _contextRequest() =>
    ContextClarificationRequestV1(
      knownFacts: const [ContextKnownFactV1(key: 'activity', value: 'walk')],
      unresolvedFacts: const [],
    );

Future<AiStylistShadowTraceV1> _run({
  required Object? context,
  required Object? decision,
  required Object? explanation,
}) {
  return AiStylistDisabledShadowRunnerV1(
    contextClient: _ContextClient(context),
    decisionClient: _DecisionClient(decision),
    explanationClient: _ExplanationClient(explanation),
  ).run(
    contextRequest: _contextRequest(),
    resolvedContext: FrozenOutfitResolvedContextV1(activity: 'walk'),
    wardrobe: _wardrobe(),
    candidateContext: _matrixContext,
    authoritativeOwnedItemIds: const ['top', 'bottom', 'shoes'],
  );
}

void main() {
  test('activation policy defaults and fails closed, including live', () {
    expect(
      AiStylistPathActivationPolicyV1.resolve(
        isDebugBuild: false,
        requested: 'dev_shadow',
      ),
      AiStylistPathActivationV1.disabled,
    );
    for (final requested in <Object?>[null, 'unknown', 'live', true]) {
      expect(
        AiStylistPathActivationPolicyV1.resolve(
          isDebugBuild: true,
          requested: requested,
        ),
        AiStylistPathActivationV1.disabled,
      );
    }
    expect(
      AiStylistPathActivationPolicyV1.resolve(
        isDebugBuild: true,
        requested: 'dev_shadow',
      ),
      AiStylistPathActivationV1.devShadow,
    );
    expect(
      AiStylistRealDevShadowSmokePolicyV1.permits(
        isDebugBuild: false,
        explicitlyRequested: true,
      ),
      isFalse,
    );
    expect(
      AiStylistRealDevShadowSmokePolicyV1.permits(
        isDebugBuild: true,
        explicitlyRequested: false,
      ),
      isFalse,
    );
    expect(
      AiStylistRealDevShadowSmokePolicyV1.permits(
        isDebugBuild: true,
        explicitlyRequested: true,
      ),
      isTrue,
    );
    expect(
      OutfitStylistFinalReviewRunner.isStylistSmokeEligibleLogPrefix(
        '[HOME_AI_OUTFIT final_review_v2]',
      ),
      isFalse,
    );
    expect(
      OutfitStylistFinalReviewRunner.isStylistSmokeEligibleLogPrefix(
        '[STYLIST CHAT final_review_v2]',
      ),
      isTrue,
    );
  });

  test(
    'context parser rejects malformed output and fact-authority injection',
    () {
      for (final wire in <Object?>[
        null,
        const {'action': 'unknown'},
        const {
          'action': 'proceed',
          'knownFacts': {'weather': 'rain'},
        },
        const {'action': 'ask_clarification'},
      ]) {
        expect(
          () => ContextClarificationTransportAdapterV1.parse(wire),
          throwsFormatException,
        );
      }
    },
  );

  test('fallback policy is declarative and cannot change role authority', () {
    expect(
      AiStylistRoleFallbackPoliciesV1.context.targets.map(
        (target) => target.modelAlias,
      ),
      ['gpt-4o', 'claude-sonnet-5'],
    );
    expect(
      AiStylistRoleFallbackPoliciesV1.finalDecision.targets.last.modelAlias,
      'gpt-4o',
    );
    expect(
      AiStylistRoleFallbackPoliciesV1.explanation.targets.last.modelAlias,
      'deterministic_slovak_template',
    );
    expect(
      AiStylistRoleFallbackPoliciesV1.explanation.preservesRoleAuthority,
      isTrue,
    );
  });

  test(
    'end-to-end mock shadow freezes V2 selection and preserves legacy identity',
    () async {
      final candidates = V2FlexibleCandidateMatrix.generate(
        wardrobe: _wardrobe(),
        context: _matrixContext,
      );
      final legacy = Object();
      final execution = await AiStylistShadowExecutionV1.preserveLegacy(
        legacyResult: legacy,
        activation: AiStylistPathActivationV1.devShadow,
        shadowWork: () => _run(
          context: const {'action': 'proceed'},
          decision: {
            'action': 'select_candidate',
            'selectedCandidateId': candidates.single.candidateId,
          },
          explanation: const {'explanation': 'Outfit je vhodný.'},
        ),
      );
      expect(identical(execution.legacyResult, legacy), isTrue);
      expect(execution.shadowAuthoritative, isFalse);
      expect(
        execution.shadowTrace!.decision!.selectedCandidateId,
        candidates.single.candidateId,
      );
      expect(execution.shadowTrace!.explanation!.usedFallback, isFalse);
      final events = AiStylistShadowTraceEventsV1.fromTrace(
        runId: 'shadow-run-1',
        trace: execution.shadowTrace!,
      );
      expect(
        events.every(
          (event) => event.authority == AiStylistTraceAuthorityV1.shadow,
        ),
        isTrue,
      );
      expect(
        events.map((event) => event.toJson().toString()).join(),
        isNot(contains('uid')),
      );
    },
  );

  test(
    'decision failure gives reject_all fallback explanation and never changes legacy',
    () async {
      final legacy = Object();
      final execution = await AiStylistShadowExecutionV1.preserveLegacy(
        legacyResult: legacy,
        activation: AiStylistPathActivationV1.devShadow,
        shadowWork: () => _run(
          context: const {'action': 'proceed'},
          decision: const FrozenOutfitDecisionClientExceptionV1(
            FrozenOutfitDecisionClientFailureKindV1.timeout,
          ),
          explanation: null,
        ),
      );
      final trace = execution.shadowTrace!;
      expect(identical(execution.legacyResult, legacy), isTrue);
      expect(trace.decision!.selectedCandidateId, isNull);
      expect(trace.decision!.isRejected, isTrue);
      expect(trace.explanation!.usedFallback, isTrue);
      expect(
        trace.explanation!.response.text,
        contains('Nenašiel som bezpečný outfit'),
      );
    },
  );

  test(
    'context malformed output stays non-authoritative and uses known-context fallback',
    () async {
      final trace = await _run(
        context: const {
          'action': 'proceed',
          'knownFacts': {'invented': 'fact'},
        },
        decision: const {'action': 'reject_all', 'selectedCandidateId': null},
        explanation: const {'explanation': 'Bezpečne bez výberu.'},
      );
      expect(
        trace.context.status,
        AiStylistShadowContextStatusV1.deterministicKnownContextFallback,
      );
      expect(trace.decision!.isRejected, isTrue);
    },
  );

  test(
    'explanation alternate-candidate and undo-reject attempts are discarded',
    () async {
      for (final injection in <Object?>[
        const {
          'explanation': 'Vyber druhý.',
          'selectedCandidateId': 'candidate-a',
        },
        const {'explanation': 'Vyber outfit.', 'action': 'select_candidate'},
      ]) {
        final trace = await _run(
          context: const {'action': 'proceed'},
          decision: const {'action': 'reject_all', 'selectedCandidateId': null},
          explanation: injection,
        );
        expect(trace.decision!.isRejected, isTrue);
        expect(trace.decision!.selectedCandidateId, isNull);
        expect(trace.explanation!.usedFallback, isTrue);
      }
    },
  );

  test(
    'disabled execution neither starts shadow nor blocks legacy result',
    () async {
      var called = false;
      final legacy = <String>['legacy'];
      final execution = await AiStylistShadowExecutionV1.preserveLegacy(
        legacyResult: legacy,
        activation: AiStylistPathActivationV1.live,
        shadowWork: () async {
          called = true;
          throw StateError('must not run');
        },
      );
      expect(called, isFalse);
      expect(identical(execution.legacyResult, legacy), isTrue);
      expect(execution.activation, AiStylistPathActivationV1.disabled);
    },
  );

  test(
    'real final-review host launches one non-authoritative fake shadow run',
    () async {
      AiStylistDevShadowRunLedgerV1.reset();
      AiStylistDevShadowTraceSinkV1.reset();
      final candidates = V2FlexibleCandidateMatrix.generate(
        wardrobe: _wardrobe(),
        context: _matrixContext,
      );
      expect(candidates, isNotEmpty);
      final singleCandidate = <V2FlexibleCandidate>[candidates.first];
      final runner = OutfitStylistFinalReviewRunner(
        devShadowHost: const AiStylistDevShadowHostV1(
          activationOverride: AiStylistPathActivationV1.devShadow,
        ),
      );
      const weather = OutfitWeatherSnapshot(
        tempC: 20,
        isRainy: false,
        isWindy: false,
        seasonKey: 'let',
      );

      final first = await runner.selectBestCandidateDetailed(
        candidates: singleCandidate,
        weather: weather,
      );
      expect(identical(first.outfit, singleCandidate.single.outfit), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      final firstEvents = AiStylistDevShadowTraceSinkV1.events;
      expect(firstEvents, isNotEmpty);
      expect(
        firstEvents.every(
          (event) => event.authority == AiStylistTraceAuthorityV1.shadow,
        ),
        isTrue,
      );

      final second = await runner.selectBestCandidateDetailed(
        candidates: singleCandidate,
        weather: weather,
      );
      expect(identical(second.outfit, singleCandidate.single.outfit), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(AiStylistDevShadowTraceSinkV1.events.length, firstEvents.length);
    },
  );

  test(
    'host gate off and shadow failure cannot affect the legacy pick',
    () async {
      AiStylistDevShadowRunLedgerV1.reset();
      AiStylistDevShadowTraceSinkV1.reset();
      final candidates = V2FlexibleCandidateMatrix.generate(
        wardrobe: _wardrobe(),
        context: _matrixContext,
      );
      final singleCandidate = <V2FlexibleCandidate>[candidates.first];
      const weather = OutfitWeatherSnapshot(
        tempC: 20,
        isRainy: false,
        isWindy: false,
        seasonKey: 'let',
      );
      final disabledRunner = OutfitStylistFinalReviewRunner(
        devShadowHost: const AiStylistDevShadowHostV1(
          activationOverride: AiStylistPathActivationV1.disabled,
        ),
      );
      final disabledPick = await disabledRunner.selectBestCandidateDetailed(
        candidates: singleCandidate,
        weather: weather,
      );
      expect(
        identical(disabledPick.outfit, singleCandidate.single.outfit),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(AiStylistDevShadowTraceSinkV1.events, isEmpty);

      final failingRunner = OutfitStylistFinalReviewRunner(
        devShadowHost: AiStylistDevShadowHostV1(
          activationOverride: AiStylistPathActivationV1.devShadow,
          decisionClient: _DecisionClient(Exception('offline fake failure')),
        ),
      );
      final failingPick = await failingRunner.selectBestCandidateDetailed(
        candidates: singleCandidate,
        weather: weather,
      );
      expect(
        identical(failingPick.outfit, singleCandidate.single.outfit),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(AiStylistDevShadowTraceSinkV1.events, isNotEmpty);
      expect(
        AiStylistDevShadowTraceSinkV1.events.any((event) => event.rejectAll),
        isTrue,
      );
    },
  );
}
