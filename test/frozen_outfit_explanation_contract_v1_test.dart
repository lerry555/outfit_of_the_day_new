import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_envelope_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_request_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_explanation_contract_v1.dart';

class _FakeExplanationClient implements FrozenOutfitExplanationClientV1 {
  _FakeExplanationClient(this.result);
  final Object? result;
  @override
  Future<Object?> explain(FrozenOutfitExplanationRequestV1 request) async =>
      result;
}

FrozenOutfitCandidateV1 _candidate() => FrozenOutfitCandidateV1(
  candidateId: 'candidate-a',
  itemIds: const ['top', 'bottom', 'shoes'],
  hardConstraintEvidence: FrozenOutfitHardConstraintEvidenceV1(
    candidateId: 'candidate-a',
    deterministicPassed: true,
  ),
  compromiseClassification: FrozenOutfitCompromiseClassificationV1(
    level: FrozenOutfitCompromiseLevelV1.none,
  ),
);

FrozenOutfitExplanationRequestV1 _request(FrozenOutfitDecisionActionV1 action) {
  final envelope = FrozenOutfitDecisionEnvelopeV1.freeze(
    candidates: [_candidate()],
    authoritativeOwnedItemIds: const ['top', 'bottom', 'shoes'],
    decisionAttempt: action == FrozenOutfitDecisionActionV1.selectCandidate
        ? FrozenOutfitDecisionAttemptV1.selectCandidate('candidate-a')
        : FrozenOutfitDecisionAttemptV1.rejectAll(),
  );
  return FrozenOutfitExplanationRequestV1.fromValidatedEnvelope(
    envelope: envelope,
    resolvedContext: FrozenOutfitResolvedContextV1(activity: 'walk'),
  );
}

void main() {
  test('select explanation receives only immutable validated facts', () {
    final request = _request(FrozenOutfitDecisionActionV1.selectCandidate);
    final json = request.toJson();
    expect(json['effectiveAction'], 'select_candidate');
    expect(json['effectiveSelectedCandidateId'], 'candidate-a');
    expect(json['selectedFrozenItemIds'], const ['top', 'bottom', 'shoes']);
    expect(json.toString(), isNot(contains('candidateIndex')));
  });

  test('reject_all explanation has no selected candidate or items', () {
    final json = _request(FrozenOutfitDecisionActionV1.rejectAll).toJson();
    expect(json['effectiveAction'], 'reject_all');
    expect(json['effectiveSelectedCandidateId'], isNull);
    expect(json['selectedFrozenItemIds'], isEmpty);
  });

  test(
    'authority-bearing explanation response is rejected, never applied',
    () async {
      final request = _request(FrozenOutfitDecisionActionV1.rejectAll);
      final result = await FrozenOutfitExplanationOrchestratorV1(
        _FakeExplanationClient(const {
          'explanation': 'Vyber druhý outfit.',
          'selectedCandidateId': 'candidate-a',
        }),
      ).explain(request);
      expect(result.usedFallback, isTrue);
      expect(
        result.response.warningCodes,
        contains('explanation_authority_field_rejected'),
      );
      expect(request.decision.action, FrozenOutfitDecisionActionV1.rejectAll);
      expect(request.decision.selectedCandidateId, isNull);
    },
  );

  test(
    'provider explanation failure uses Slovak fallback without reselection',
    () async {
      final request = _request(FrozenOutfitDecisionActionV1.selectCandidate);
      final result = await FrozenOutfitExplanationOrchestratorV1(
        _FakeExplanationClient(null),
      ).explain(request);
      expect(result.usedFallback, isTrue);
      expect(result.response.text, contains('deterministickou kontrolou'));
      expect(request.decision.selectedCandidateId, 'candidate-a');
    },
  );
}
