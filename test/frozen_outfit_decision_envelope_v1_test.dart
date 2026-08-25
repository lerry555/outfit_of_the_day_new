import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_envelope_v1.dart';

FrozenOutfitCandidateV1 candidate(
  String id,
  List<String> itemIds, {
  bool deterministicPassed = true,
  FrozenOutfitCompromiseLevelV1 compromiseLevel =
      FrozenOutfitCompromiseLevelV1.none,
  Map<String, Object?> facts = const <String, Object?>{},
}) => FrozenOutfitCandidateV1(
  candidateId: id,
  itemIds: itemIds,
  hardConstraintEvidence: FrozenOutfitHardConstraintEvidenceV1(
    candidateId: id,
    deterministicPassed: deterministicPassed,
    violationCodes: deterministicPassed
        ? const <String>[]
        : const <String>['unsafe'],
    facts: facts,
  ),
  compromiseClassification: FrozenOutfitCompromiseClassificationV1(
    level: compromiseLevel,
  ),
);

FrozenOutfitDecisionEnvelopeV1 envelope({
  required List<FrozenOutfitCandidateV1> candidates,
  FrozenOutfitDecisionAttemptV1? decision,
  Iterable<String> ownedItemIds = const <String>['top', 'bottom', 'shoes'],
}) => FrozenOutfitDecisionEnvelopeV1.freeze(
  candidates: candidates,
  authoritativeOwnedItemIds: ownedItemIds,
  decisionAttempt: decision,
);

void main() {
  final first = candidate('candidate-a', const ['top', 'bottom', 'shoes']);
  final second = candidate('candidate-b', const ['top', 'bottom', 'shoes']);

  test('valid select_candidate preserves frozen candidate identity', () {
    final result = envelope(
      candidates: [first, second],
      decision: FrozenOutfitDecisionAttemptV1.selectCandidate('candidate-b'),
    );

    expect(result.action, FrozenOutfitDecisionActionV1.selectCandidate);
    expect(result.selectedCandidateId, 'candidate-b');
    expect(result.selectedCandidate!.candidateId, 'candidate-b');
    expect(
      result.postDecisionValidatorResult.requestedDecisionAccepted,
      isTrue,
    );
  });

  test(
    'valid reject_all has null selection and no selected explanation outfit',
    () {
      final result = envelope(
        candidates: [first, second],
        decision: FrozenOutfitDecisionAttemptV1.rejectAll(),
      );

      expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
      expect(result.selectedCandidateId, isNull);
      expect(result.immutableExplanationInput.selectedCandidateId, isNull);
      expect(
        result.immutableExplanationInput.selectedCandidateItemIds,
        isEmpty,
      );
      expect(
        result.immutableExplanationInput.compromiseClassification.level,
        FrozenOutfitCompromiseLevelV1.rejectAll,
      );
    },
  );

  test(
    'candidate outside frozen set fails closed instead of selecting first',
    () {
      final result = envelope(
        candidates: [first, second],
        decision: FrozenOutfitDecisionAttemptV1.selectCandidate('not-in-set'),
      );

      expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
      expect(result.selectedCandidateId, isNull);
      expect(result.selectedCandidateId, isNot(first.candidateId));
      expect(
        result.postDecisionValidatorResult.reasonCodes,
        contains('selected_candidate_outside_frozen_set'),
      );
    },
  );

  test('unsafe set with no valid candidate becomes reject_all', () {
    final result = envelope(
      candidates: [
        candidate('unsafe-a', const [
          'top',
          'bottom',
          'shoes',
        ], deterministicPassed: false),
        candidate('unsafe-b', const [
          'top',
          'bottom',
          'shoes',
        ], compromiseLevel: FrozenOutfitCompromiseLevelV1.rejectAll),
      ],
      decision: FrozenOutfitDecisionAttemptV1.selectCandidate('unsafe-a'),
    );

    expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.selectedCandidateId, isNull);
    expect(
      result.postDecisionValidatorResult.reasonCodes,
      contains('no_valid_frozen_candidates'),
    );
  });

  test('explanation output cannot change a selected candidate', () {
    final result = envelope(
      candidates: [first, second],
      decision: FrozenOutfitDecisionAttemptV1.selectCandidate('candidate-a'),
    );

    expect(
      () => FrozenOutfitExplanationOutputV1.fromWire(<String, Object?>{
        'explanation': 'Skús druhý outfit.',
        'selectedCandidateId': 'candidate-b',
      }),
      throwsArgumentError,
    );
    expect(result.selectedCandidateId, 'candidate-a');
  });

  test('explanation output cannot undo reject_all', () {
    final result = envelope(
      candidates: [first],
      decision: FrozenOutfitDecisionAttemptV1.rejectAll(),
    );

    expect(
      () => FrozenOutfitExplanationOutputV1.fromWire(<String, Object?>{
        'explanation': 'Odporúčam tento outfit.',
        'action': 'select_candidate',
        'items': <String>['top', 'bottom', 'shoes'],
      }),
      throwsArgumentError,
    );
    expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.selectedCandidateId, isNull);
  });

  test('invented non-owned candidate is rejected', () {
    final owned = candidate('owned', const ['top', 'bottom', 'shoes']);
    final invented = candidate('invented', const ['top', 'bottom', 'imagined']);
    final result = envelope(
      candidates: [owned, invented],
      ownedItemIds: const ['top', 'bottom', 'shoes'],
      decision: FrozenOutfitDecisionAttemptV1.selectCandidate('invented'),
    );

    expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.selectedCandidateId, isNull);
    expect(
      result.frozenCandidates[1].hardConstraintEvidence.ownershipPassed,
      isFalse,
    );
    expect(
      result.frozenCandidates[1].hardConstraintEvidence.violationCodes,
      contains('candidate_contains_non_owned_item'),
    );
  });

  test('all decision errors fail closed without candidate zero fallback', () {
    final attempts = <FrozenOutfitDecisionAttemptV1?>[
      null,
      FrozenOutfitDecisionAttemptV1.invalid(),
      FrozenOutfitDecisionAttemptV1.fromWire(<String, Object?>{
        'action': 'unknown',
      }),
      FrozenOutfitDecisionAttemptV1.selectCandidate('missing'),
      FrozenOutfitDecisionAttemptV1.providerFailure(),
    ];

    for (final attempt in attempts) {
      final result = envelope(candidates: [first, second], decision: attempt);
      expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
      expect(result.selectedCandidateId, isNull);
      expect(result.selectedCandidateId, isNot(first.candidateId));
    }
  });

  test('deterministic validator vetoes an otherwise requested selection', () {
    final unsafe = candidate('unsafe', const [
      'top',
      'bottom',
      'shoes',
    ], deterministicPassed: false);
    final result = envelope(
      candidates: [unsafe, second],
      decision: FrozenOutfitDecisionAttemptV1.selectCandidate('unsafe'),
    );

    expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.selectedCandidateId, isNull);
    expect(
      result.postDecisionValidatorResult.requestedDecisionAccepted,
      isFalse,
    );
    expect(
      result.postDecisionValidatorResult.reasonCodes,
      contains('selected_candidate_failed_hard_constraints'),
    );
  });

  test('frozen candidate data and evidence facts are deeply immutable', () {
    final mutableItemIds = <String>['top', 'bottom', 'shoes'];
    final mutableFacts = <String, Object?>{
      'nested': <String, Object?>{'value': 'before'},
    };
    final mutableCandidate = candidate(
      'mutable',
      mutableItemIds,
      facts: mutableFacts,
    );
    final result = envelope(
      candidates: [mutableCandidate],
      decision: FrozenOutfitDecisionAttemptV1.selectCandidate('mutable'),
    );
    mutableItemIds.add('imagined');
    (mutableFacts['nested'] as Map<String, Object?>)['value'] = 'after';

    expect(result.frozenCandidates.single.itemIds, const [
      'top',
      'bottom',
      'shoes',
    ]);
    expect(
      (result.frozenCandidates.single.hardConstraintEvidence.facts['nested']
          as Map)['value'],
      'before',
    );
    expect(
      () => result.frozenCandidates.single.itemIds.add('new-item'),
      throwsUnsupportedError,
    );
    expect(
      () =>
          (result.frozenCandidates.single.hardConstraintEvidence.facts['nested']
                  as Map)['value'] =
              'mutate',
      throwsUnsupportedError,
    );
  });

  test('candidate identity is ID-based and duplicate IDs are rejected', () {
    final result = envelope(
      candidates: [second, first],
      decision: FrozenOutfitDecisionAttemptV1.selectCandidate('candidate-a'),
    );
    expect(result.selectedCandidateId, 'candidate-a');

    expect(
      () => envelope(
        candidates: [
          first,
          candidate('candidate-a', const ['top']),
        ],
        decision: FrozenOutfitDecisionAttemptV1.rejectAll(),
      ),
      throwsArgumentError,
    );
    expect(() => candidate('', const ['top']), throwsArgumentError);
  });
}
