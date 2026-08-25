import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_envelope_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_orchestration_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_request_v1.dart';

class _FakeDecisionClient implements FrozenOutfitDecisionClientV1 {
  _FakeDecisionClient(this.response);
  final Object? response;
  @override
  Future<Object?> decide(FrozenOutfitDecisionRequestV1 request) async =>
      response;
}

class _ThrowingDecisionClient implements FrozenOutfitDecisionClientV1 {
  _ThrowingDecisionClient(this.error);
  final Object error;
  @override
  Future<Object?> decide(FrozenOutfitDecisionRequestV1 request) =>
      Future.error(error);
}

FrozenOutfitCandidateV1 _candidate(String id, {bool safe = true}) =>
    FrozenOutfitCandidateV1(
      candidateId: id,
      itemIds: const ['top', 'bottom', 'shoes'],
      hardConstraintEvidence: FrozenOutfitHardConstraintEvidenceV1(
        candidateId: id,
        deterministicPassed: safe,
        violationCodes: safe ? const [] : const ['unsafe'],
      ),
      compromiseClassification: FrozenOutfitCompromiseClassificationV1(
        level: FrozenOutfitCompromiseLevelV1.none,
      ),
    );

FrozenOutfitDecisionRequestV1 _request(
  List<FrozenOutfitCandidateV1> candidates,
) => FrozenOutfitDecisionRequestV1(
  resolvedContext: FrozenOutfitResolvedContextV1(activity: 'walk'),
  frozenCandidates: candidates,
);

Future<FrozenOutfitDecisionOutcomeV1> _run(
  FrozenOutfitDecisionClientV1 client,
  List<FrozenOutfitCandidateV1> candidates, {
  Iterable<String> owned = const ['top', 'bottom', 'shoes'],
}) => FrozenOutfitDecisionOrchestratorV1(client).decide(
  request: _request(candidates),
  frozenCandidates: candidates,
  authoritativeOwnedItemIds: owned,
);

void main() {
  final a = _candidate('candidate-a');
  final b = _candidate('candidate-b');

  test('valid ID select remains selected through the disabled seam', () async {
    final result = await _run(
      _FakeDecisionClient(const {
        'action': 'select_candidate',
        'selectedCandidateId': 'candidate-b',
      }),
      [a, b],
    );
    expect(result.kind, FrozenOutfitDecisionOutcomeKindV1.successSelect);
    expect(result.selectedCandidateId, 'candidate-b');
  });

  test('explicit reject_all is a valid typed outcome', () async {
    final result = await _run(
      _FakeDecisionClient(const {
        'action': 'reject_all',
        'selectedCandidateId': null,
      }),
      [a, b],
    );
    expect(result.kind, FrozenOutfitDecisionOutcomeKindV1.validRejectAll);
    expect(result.selectedCandidateId, isNull);
  });

  test(
    'provider exception and timeout fail closed without candidate zero',
    () async {
      for (final error in <Object>[
        const FrozenOutfitDecisionClientExceptionV1(
          FrozenOutfitDecisionClientFailureKindV1.provider,
        ),
        const FrozenOutfitDecisionClientExceptionV1(
          FrozenOutfitDecisionClientFailureKindV1.timeout,
        ),
      ]) {
        final result = await _run(_ThrowingDecisionClient(error), [a, b]);
        expect(result.kind, FrozenOutfitDecisionOutcomeKindV1.transportFailure);
        expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
        expect(result.selectedCandidateId, isNull);
        expect(result.selectedCandidateId, isNot(a.candidateId));
      }
    },
  );

  test(
    'malformed, unknown and empty responses are contract failures, never first',
    () async {
      for (final response in <Object?>[
        null,
        const {'action': 'select_candidate', 'selectedCandidateId': 'missing'},
        const {'action': 'select_candidate', 'selectedCandidateId': ''},
      ]) {
        final result = await _run(_FakeDecisionClient(response), [a, b]);
        expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
        expect(result.selectedCandidateId, isNull);
        expect(result.selectedCandidateId, isNot(a.candidateId));
      }
    },
  );

  test('unknown and non-owned selections are deterministic vetoes', () async {
    final unknown = await _run(
      _FakeDecisionClient(const {
        'action': 'select_candidate',
        'selectedCandidateId': 'outside',
      }),
      [a, b],
    );
    expect(unknown.kind, FrozenOutfitDecisionOutcomeKindV1.deterministicVeto);

    final ownedFailure = await _run(
      _FakeDecisionClient(const {
        'action': 'select_candidate',
        'selectedCandidateId': 'candidate-a',
      }),
      [a],
      owned: const ['top', 'bottom'],
    );
    expect(
      ownedFailure.kind,
      FrozenOutfitDecisionOutcomeKindV1.deterministicVeto,
    );
    expect(ownedFailure.selectedCandidateId, isNull);
  });

  test(
    'no valid candidate is a deterministic veto, not a replacement selection',
    () async {
      final result = await _run(
        _FakeDecisionClient(const {
          'action': 'select_candidate',
          'selectedCandidateId': 'unsafe',
        }),
        [_candidate('unsafe', safe: false)],
      );
      // No candidate is inferred merely because it occupies a list position.
      expect(result.kind, FrozenOutfitDecisionOutcomeKindV1.deterministicVeto);
      expect(result.selectedCandidateId, isNull);
    },
  );
}
