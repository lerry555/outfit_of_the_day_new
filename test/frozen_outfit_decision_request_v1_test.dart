import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_envelope_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_request_v1.dart';

FrozenOutfitCandidateV1 _candidate(String id) => FrozenOutfitCandidateV1(
  candidateId: id,
  itemIds: const ['top', 'bottom', 'shoes'],
  hardConstraintEvidence: FrozenOutfitHardConstraintEvidenceV1(
    candidateId: id,
    deterministicPassed: true,
    facts: const {'weather': 'dry'},
  ),
  compromiseClassification: FrozenOutfitCompromiseClassificationV1(
    level: FrozenOutfitCompromiseLevelV1.none,
  ),
);

void main() {
  test('serializes only deterministic ID-based decision facts', () {
    final request = FrozenOutfitDecisionRequestV1(
      resolvedContext: FrozenOutfitResolvedContextV1(
        activity: 'walk',
        weather: 'dry',
        terrain: null,
        relevantKnownTimingFacts: const {'date': '2026-08-19', 'hour': null},
      ),
      frozenCandidates: [_candidate('candidate-b'), _candidate('candidate-a')],
    );

    final json = request.toJson();
    expect(
      json['contractVersion'],
      frozenOutfitDecisionRequestV1ContractVersion,
    );
    expect((json['resolvedContext'] as Map).containsKey('terrain'), isFalse);
    expect((json['resolvedContext'] as Map)['relevantKnownTimingFacts'], {
      'date': '2026-08-19',
    });
    expect(
      (json['frozenCandidates'] as List).first['candidateId'],
      'candidate-b',
    );
    expect(json['allowedActions'], const ['select_candidate', 'reject_all']);
    expect(json.toString(), isNot(contains('candidateIndex')));
    expect(json.toString(), isNot(contains('uid')));
  });

  test('snapshots candidates and context timing facts immutably', () {
    final ids = <String>['top', 'bottom', 'shoes'];
    final timing = <String, String?>{'hour': '18'};
    final source = _candidate('candidate-a');
    final candidate = FrozenOutfitCandidateV1(
      candidateId: source.candidateId,
      itemIds: ids,
      hardConstraintEvidence: source.hardConstraintEvidence,
      compromiseClassification: source.compromiseClassification,
    );
    final request = FrozenOutfitDecisionRequestV1(
      resolvedContext: FrozenOutfitResolvedContextV1(
        relevantKnownTimingFacts: timing,
      ),
      frozenCandidates: [candidate],
    );
    ids.add('invented');
    timing['hour'] = '22';
    expect(request.frozenCandidates.single.itemIds, const [
      'top',
      'bottom',
      'shoes',
    ]);
    expect(request.resolvedContext.relevantKnownTimingFacts['hour'], '18');
    expect(
      () => request.frozenCandidates.add(request.frozenCandidates.single),
      throwsUnsupportedError,
    );
  });

  test(
    'rejects duplicate candidate IDs instead of making an index authoritative',
    () {
      expect(
        () => FrozenOutfitDecisionRequestV1(
          resolvedContext: FrozenOutfitResolvedContextV1(),
          frozenCandidates: [_candidate('same'), _candidate('same')],
        ),
        throwsArgumentError,
      );
    },
  );
}
