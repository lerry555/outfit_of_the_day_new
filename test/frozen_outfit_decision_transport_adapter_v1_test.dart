import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_envelope_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_transport_adapter_v1.dart';

FrozenOutfitCandidateV1 _candidate(String id, List<String> itemIds) =>
    FrozenOutfitCandidateV1(
      candidateId: id,
      itemIds: itemIds,
      hardConstraintEvidence: FrozenOutfitHardConstraintEvidenceV1(
        candidateId: id,
        deterministicPassed: true,
      ),
      compromiseClassification: FrozenOutfitCompromiseClassificationV1(
        level: FrozenOutfitCompromiseLevelV1.none,
      ),
    );

FrozenOutfitDecisionEnvelopeV1 _envelope(
  List<FrozenOutfitCandidateV1> candidates,
  FrozenOutfitDecisionWireParseResultV1 parsed,
) => FrozenOutfitDecisionEnvelopeV1.freeze(
  candidates: candidates,
  authoritativeOwnedItemIds: const <String>['top', 'bottom', 'shoes'],
  decisionAttempt: parsed.toAttempt(),
);

void main() {
  const selectWire = <String, Object?>{
    'action': 'select_candidate',
    'selectedCandidateId': 'candidate-b',
  };
  const rejectWire = <String, Object?>{
    'action': 'reject_all',
    'selectedCandidateId': null,
  };

  test('valid select_candidate parses to an ID-based attempt', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(selectWire);

    expect(parsed.isSuccess, isTrue);
    expect(parsed.failureCode, isNull);
    expect(
      parsed.response!.action,
      FrozenOutfitDecisionActionV1.selectCandidate,
    );
    expect(parsed.response!.selectedCandidateId, 'candidate-b');
    expect(parsed.toAttempt().selectedCandidateId, 'candidate-b');
  });

  test('valid reject_all parses to a null selected candidate', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(rejectWire);

    expect(parsed.isSuccess, isTrue);
    expect(parsed.toAttempt().action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(parsed.toAttempt().selectedCandidateId, isNull);
  });

  test('missing action fails with a stable code', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(
      const <String, Object?>{'selectedCandidateId': 'candidate-a'},
    );

    expect(parsed.isSuccess, isFalse);
    expect(
      parsed.failureCode,
      FrozenOutfitDecisionTransportAdapterV1.actionMissing,
    );
  });

  test('invalid action fails with a stable code', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(
      const <String, Object?>{
        'action': 'select_by_index',
        'selectedCandidateId': 'candidate-a',
      },
    );

    expect(parsed.isSuccess, isFalse);
    expect(
      parsed.failureCode,
      FrozenOutfitDecisionTransportAdapterV1.actionInvalid,
    );
  });

  test('select_candidate requires a present candidate ID', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(
      const <String, Object?>{'action': 'select_candidate'},
    );

    expect(
      parsed.failureCode,
      FrozenOutfitDecisionTransportAdapterV1.selectedCandidateIdMissing,
    );
  });

  test('select_candidate rejects null candidate ID', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(
      const <String, Object?>{
        'action': 'select_candidate',
        'selectedCandidateId': null,
      },
    );

    expect(
      parsed.failureCode,
      FrozenOutfitDecisionTransportAdapterV1.selectedCandidateIdInvalid,
    );
  });

  test('select_candidate rejects empty and whitespace-only IDs', () {
    for (final id in const <String>['', '   ']) {
      final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(
        <String, Object?>{
          'action': 'select_candidate',
          'selectedCandidateId': id,
        },
      );
      expect(
        parsed.failureCode,
        FrozenOutfitDecisionTransportAdapterV1.selectedCandidateIdInvalid,
      );
    }
  });

  test('select_candidate rejects non-string candidate ID', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(
      const <String, Object?>{
        'action': 'select_candidate',
        'selectedCandidateId': 0,
      },
    );

    expect(
      parsed.failureCode,
      FrozenOutfitDecisionTransportAdapterV1.selectedCandidateIdInvalid,
    );
  });

  test('reject_all rejects non-null candidate ID', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(
      const <String, Object?>{
        'action': 'reject_all',
        'selectedCandidateId': 'candidate-a',
      },
    );

    expect(
      parsed.failureCode,
      FrozenOutfitDecisionTransportAdapterV1.rejectAllRequiresNullCandidate,
    );
  });

  test('null and non-object payloads have distinct failures', () {
    expect(
      FrozenOutfitDecisionTransportAdapterV1.parse(null).failureCode,
      FrozenOutfitDecisionTransportAdapterV1.payloadMissing,
    );
    expect(
      FrozenOutfitDecisionTransportAdapterV1.parse('not-a-map').failureCode,
      FrozenOutfitDecisionTransportAdapterV1.payloadNotObject,
    );
  });

  test('unexpected malformed structure fails closed', () {
    final parsed =
        FrozenOutfitDecisionTransportAdapterV1.parse(const <String, Object?>{
          'action': 'select_candidate',
          'selectedCandidateId': 'candidate-a',
          'selectedCandidateIndex': 0,
        });

    expect(parsed.isSuccess, isFalse);
    expect(
      parsed.failureCode,
      FrozenOutfitDecisionTransportAdapterV1.payloadMalformed,
    );
  });

  test('provider failure becomes a fail-closed attempt', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.providerUnavailable();
    final result = _envelope([
      _candidate('candidate-a', const ['top', 'bottom', 'shoes']),
    ], parsed);

    expect(
      parsed.failureCode,
      FrozenOutfitDecisionTransportAdapterV1.providerFailure,
    );
    expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.selectedCandidateId, isNull);
    expect(
      result.postDecisionValidatorResult.reasonCodes,
      contains('decision_provider_failure'),
    );
  });

  test('known parsed candidate is selected only after envelope validation', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(selectWire);
    final result = _envelope([
      _candidate('candidate-a', const ['top', 'bottom', 'shoes']),
      _candidate('candidate-b', const ['top', 'bottom', 'shoes']),
    ], parsed);

    expect(result.action, FrozenOutfitDecisionActionV1.selectCandidate);
    expect(result.selectedCandidateId, 'candidate-b');
  });

  test('unknown parsed candidate is rejected by the envelope', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(
      const <String, Object?>{
        'action': 'select_candidate',
        'selectedCandidateId': 'unknown',
      },
    );
    final result = _envelope([
      _candidate('candidate-a', const ['top', 'bottom', 'shoes']),
    ], parsed);

    expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.selectedCandidateId, isNull);
  });

  test('non-owned parsed candidate is rejected by the envelope', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(
      const <String, Object?>{
        'action': 'select_candidate',
        'selectedCandidateId': 'invented',
      },
    );
    final result = _envelope([
      _candidate('invented', const ['top', 'bottom', 'imagined']),
    ], parsed);

    expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.selectedCandidateId, isNull);
  });

  test('reordering candidates does not change an ID-based decision', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(selectWire);
    final result = _envelope([
      _candidate('candidate-b', const ['top', 'bottom', 'shoes']),
      _candidate('candidate-a', const ['top', 'bottom', 'shoes']),
    ], parsed);

    expect(result.selectedCandidateId, 'candidate-b');
  });

  test('invalid parsing never selects candidate zero or a first candidate', () {
    final invalidPayloads = <Object?>[
      null,
      'not-a-map',
      const <String, Object?>{'action': 'bad'},
      const <String, Object?>{'action': 'select_candidate'},
      const <String, Object?>{
        'action': 'reject_all',
        'selectedCandidateId': 'candidate-a',
      },
    ];
    for (final payload in invalidPayloads) {
      final result = _envelope([
        _candidate('candidate-a', const ['top', 'bottom', 'shoes']),
        _candidate('candidate-b', const ['top', 'bottom', 'shoes']),
      ], FrozenOutfitDecisionTransportAdapterV1.parse(payload));
      expect(result.action, FrozenOutfitDecisionActionV1.rejectAll);
      expect(result.selectedCandidateId, isNull);
      expect(result.selectedCandidateId, isNot('candidate-a'));
    }
  });

  test('select JSON round-trips through typed attempt', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(selectWire);
    final roundTripped = FrozenOutfitDecisionWireResponseV1.fromAttempt(
      parsed.toAttempt(),
    ).toJson();

    expect(roundTripped, selectWire);
  });

  test('reject_all JSON round-trips through typed attempt', () {
    final parsed = FrozenOutfitDecisionTransportAdapterV1.parse(rejectWire);
    final roundTripped = FrozenOutfitDecisionWireResponseV1.fromAttempt(
      parsed.toAttempt(),
    ).toJson();

    expect(roundTripped, rejectWire);
  });
}
