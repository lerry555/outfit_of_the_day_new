import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/ai_stylist_disabled_shadow_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/ai_stylist_role_clients_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_orchestration_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_request_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_explanation_contract_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';

class _ContextClient implements ContextDecisionClientV1 {
  _ContextClient(this.response);
  final Object response;
  @override
  Future<ContextClarificationResponseV1> interpret(
    ContextClarificationRequestV1 request,
  ) => response is ContextClarificationResponseV1
      ? Future.value(response as ContextClarificationResponseV1)
      : Future.error(response);
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
      Future.value(response);
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

ContextClarificationRequestV1 _contextRequest({bool material = false}) =>
    ContextClarificationRequestV1(
      knownFacts: const [ContextKnownFactV1(key: 'activity', value: 'walk')],
      unresolvedFacts: material
          ? const [
              ContextMaterialUncertaintyV1(
                factKey: 'terrain',
                materialImpact: 'footwear_family',
              ),
            ]
          : const [],
    );

AiStylistDisabledShadowRunnerV1 _runner({
  required Object context,
  required Object? decision,
  Object? explanation = const {'explanation': 'V poriadku.'},
}) => AiStylistDisabledShadowRunnerV1(
  contextClient: _ContextClient(context),
  decisionClient: _DecisionClient(decision),
  explanationClient: _ExplanationClient(explanation),
);

Future<AiStylistShadowTraceV1> _run(
  AiStylistDisabledShadowRunnerV1 runner, {
  bool material = false,
}) => runner.run(
  contextRequest: _contextRequest(material: material),
  resolvedContext: FrozenOutfitResolvedContextV1(
    activity: 'walk',
    weather: 'dry',
  ),
  wardrobe: _wardrobe(),
  candidateContext: _matrixContext,
  authoritativeOwnedItemIds: const ['top', 'bottom', 'shoes'],
);

void main() {
  test(
    'disabled shadow runs real V2 generation through validated select and explanation',
    () async {
      expect(aiStylistDisabledShadowV1Enabled, isFalse);
      final generated = V2FlexibleCandidateMatrix.generate(
        wardrobe: _wardrobe(),
        context: _matrixContext,
      );
      expect(generated, isNotEmpty);
      final trace = await _run(
        _runner(
          context: ContextClarificationResponseV1(
            action: ContextClarificationActionV1.proceed,
          ),
          decision: {
            'action': 'select_candidate',
            'selectedCandidateId': generated.last.candidateId,
          },
        ),
      );
      expect(trace.generatedCandidateIds, contains(generated.last.candidateId));
      expect(trace.decision!.selectedCandidateId, generated.last.candidateId);
      expect(trace.explanation!.usedFallback, isFalse);
      expect(
        trace.stageTimings.keys,
        containsAll([
          'context',
          'candidateGeneration',
          'decision',
          'explanation',
        ]),
      );
    },
  );

  test(
    'decision failure is reject_all, never generated candidate zero',
    () async {
      final trace = await _run(
        _runner(
          context: ContextClarificationResponseV1(
            action: ContextClarificationActionV1.proceed,
          ),
          decision: const FrozenOutfitDecisionClientExceptionV1(
            FrozenOutfitDecisionClientFailureKindV1.timeout,
          ),
        ),
      );
      expect(trace.generatedCandidateIds, isNotEmpty);
      expect(trace.decision!.selectedCandidateId, isNull);
      expect(
        trace.decision!.selectedCandidateId,
        isNot(trace.generatedCandidateIds.first),
      );
    },
  );

  test(
    'unknown ID and malformed explanation preserve reject_all and use only fallback text',
    () async {
      final trace = await _run(
        _runner(
          context: ContextClarificationResponseV1(
            action: ContextClarificationActionV1.proceed,
          ),
          decision: const {
            'action': 'select_candidate',
            'selectedCandidateId': 'outside',
          },
          explanation: const {
            'explanation': 'vyber iný',
            'action': 'select_candidate',
          },
        ),
      );
      expect(trace.decision!.selectedCandidateId, isNull);
      expect(trace.explanation!.usedFallback, isTrue);
      expect(trace.fallbackUsed, isTrue);
    },
  );

  test(
    'context failure asks deterministic material clarification and does not generate an outfit',
    () async {
      final trace = await _run(
        _runner(context: StateError('timeout'), decision: null),
        material: true,
      );
      expect(
        trace.context.status,
        AiStylistShadowContextStatusV1.deterministicClarificationFallback,
      );
      expect(
        trace.context.response.action,
        ContextClarificationActionV1.askClarification,
      );
      expect(trace.generatedCandidateIds, isEmpty);
      expect(trace.decision, isNull);
    },
  );

  test(
    'failure injection: invalid context proceed is replaced by required clarification',
    () async {
      final trace = await _run(
        _runner(
          context: ContextClarificationResponseV1(
            action: ContextClarificationActionV1.proceed,
          ),
          decision: null,
        ),
        material: true,
      );
      expect(
        trace.context.status,
        AiStylistShadowContextStatusV1.contractFailure,
      );
      expect(
        trace.context.response.action,
        ContextClarificationActionV1.askClarification,
      );
      expect(trace.generatedCandidateIds, isEmpty);
    },
  );

  test(
    'failure injection: empty real V2 set becomes first-class reject_all',
    () async {
      final trace =
          await AiStylistDisabledShadowRunnerV1(
            contextClient: _ContextClient(
              ContextClarificationResponseV1(
                action: ContextClarificationActionV1.proceed,
              ),
            ),
            decisionClient: _DecisionClient(const {
              'action': 'select_candidate',
              'selectedCandidateId': 'candidate-a',
            }),
            explanationClient: _ExplanationClient(null),
          ).run(
            contextRequest: _contextRequest(),
            resolvedContext: FrozenOutfitResolvedContextV1(activity: 'walk'),
            wardrobe: const [],
            candidateContext: _matrixContext,
            authoritativeOwnedItemIds: const [],
          );
      expect(trace.generatedCandidateIds, isEmpty);
      expect(trace.decision!.selectedCandidateId, isNull);
      expect(trace.explanation!.usedFallback, isTrue);
    },
  );
}
