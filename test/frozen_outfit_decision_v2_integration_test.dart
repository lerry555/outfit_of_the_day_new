import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_envelope_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_transport_adapter_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';

import 'support/frozen_outfit_decision_v2_harness.dart';

WardrobeItemV2 _item({
  required String type,
  required String family,
  required List<String> slots,
  required String layer,
  int formality = 4,
  int warmth = 4,
}) => WardrobeItemV2(
  canonicalType: type,
  canonicalFamily: family,
  bodySlots: slots,
  layerPosition: layer,
  outfitFunctions: const <String>[],
  colorProfile: const ColorProfileV2(
    primary: SemanticColorV2(family: 'navy'),
    metalTone: 'none',
    hardwareTone: 'none',
  ),
  formality: formality,
  styles: const <String>[],
  occasionFit: const <String>[],
  seasons: const <String>[],
  warmth: warmth,
  attributes: const <String, dynamic>{},
  fieldSources: const <String, dynamic>{'canonicalType': 'fixture'},
  fieldConfidence: const <String, dynamic>{'canonicalType': 1.0},
  userOverrideFields: const <String>[],
);

ResolvedWardrobeItemV2 _resolved(String id, WardrobeItemV2 item) =>
    ResolvedWardrobeItemV2(
      itemId: id,
      item: item,
      raw: <String, dynamic>{'id': id},
    );

List<ResolvedWardrobeItemV2> _realMatrixWardrobe() => <ResolvedWardrobeItemV2>[
  _resolved(
    'top-a',
    _item(
      type: 't_shirt',
      family: 'top',
      slots: const <String>['upper_body'],
      layer: 'base',
      formality: 3,
      warmth: 2,
    ),
  ),
  _resolved(
    'top-b',
    _item(
      type: 'polo',
      family: 'top',
      slots: const <String>['upper_body'],
      layer: 'base',
      formality: 5,
      warmth: 3,
    ),
  ),
  _resolved(
    'bottom-a',
    _item(
      type: 'jeans',
      family: 'bottom',
      slots: const <String>['lower_body'],
      layer: 'outer',
      formality: 3,
    ),
  ),
  _resolved(
    'bottom-b',
    _item(
      type: 'trousers',
      family: 'bottom',
      slots: const <String>['lower_body'],
      layer: 'outer',
      formality: 5,
    ),
  ),
  _resolved(
    'shoes-a',
    _item(
      type: 'sneakers',
      family: 'footwear',
      slots: const <String>['feet'],
      layer: 'not_applicable',
      formality: 3,
      warmth: 3,
    ),
  ),
  _resolved(
    'shoes-b',
    _item(
      type: 'boots',
      family: 'footwear',
      slots: const <String>['feet'],
      layer: 'not_applicable',
      formality: 4,
      warmth: 4,
    ),
  ),
];

const _context = V2CandidateMatrixContext(maxCandidates: 6, tempC: 20);

void main() {
  FrozenOutfitDecisionV2HarnessResult run({
    Object? wireDecisionPayload,
    bool providerUnavailable = false,
    Iterable<String>? ownedItemIds,
    Iterable<V2FlexibleCandidate>? frozenCandidateOrder,
    Iterable<ResolvedWardrobeItemV2>? wardrobe,
  }) {
    final fixture = wardrobe ?? _realMatrixWardrobe();
    return FrozenOutfitDecisionV2Harness.run(
      wardrobe: fixture,
      context: _context,
      authoritativeOwnedItemIds:
          ownedItemIds ??
          FrozenOutfitDecisionV2Harness.ownedItemIdsFromWardrobe(fixture),
      wireDecisionPayload: wireDecisionPayload,
      providerUnavailable: providerUnavailable,
      frozenCandidateOrder: frozenCandidateOrder,
    );
  }

  test('real V2 matrix output freezes into a valid ID-based select', () {
    final baseline = run();
    expect(baseline.generatedCandidates.length, greaterThanOrEqualTo(3));
    final target = baseline.generatedCandidates[1];
    final result = run(
      wireDecisionPayload: <String, Object?>{
        'action': 'select_candidate',
        'selectedCandidateId': target.candidateId,
      },
    );

    expect(
      result.envelope.action,
      FrozenOutfitDecisionActionV1.selectCandidate,
    );
    expect(result.envelope.selectedCandidateId, target.candidateId);
    expect(
      result.envelope.selectedCandidate!.itemIds,
      target.outfit.items.map((item) => item.itemId).toList(),
    );
    expect(
      result.envelope.frozenCandidates.every(
        (candidate) => candidate.hardConstraintEvidence.ownershipPassed,
      ),
      isTrue,
    );
  });

  test(
    'reordering frozen candidate input preserves candidate ID and outfit',
    () {
      final baseline = run();
      final target = baseline.generatedCandidates[1];
      final reordered = baseline.generatedCandidates.reversed.toList();
      final result = run(
        frozenCandidateOrder: reordered,
        wireDecisionPayload: <String, Object?>{
          'action': 'select_candidate',
          'selectedCandidateId': target.candidateId,
        },
      );

      expect(result.envelope.selectedCandidateId, target.candidateId);
      expect(
        result.envelope.selectedCandidate!.itemIds,
        target.outfit.items.map((item) => item.itemId).toList(),
      );
    },
  );

  test('unknown generated-candidate ID is reject_all', () {
    final result = run(
      wireDecisionPayload: const <String, Object?>{
        'action': 'select_candidate',
        'selectedCandidateId': 'not-generated',
      },
    );

    expect(result.envelope.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.envelope.selectedCandidateId, isNull);
  });

  test(
    'ownership snapshot can deterministically invalidate selected candidate',
    () {
      final baseline = run();
      final target = baseline.generatedCandidates.first;
      final ownedIds = FrozenOutfitDecisionV2Harness.ownedItemIdsFromWardrobe(
        _realMatrixWardrobe(),
      ).toList();
      ownedIds.remove(target.outfit.items.first.itemId);
      final result = run(
        ownedItemIds: ownedIds,
        wireDecisionPayload: <String, Object?>{
          'action': 'select_candidate',
          'selectedCandidateId': target.candidateId,
        },
      );

      expect(result.envelope.action, FrozenOutfitDecisionActionV1.rejectAll);
      expect(result.envelope.selectedCandidateId, isNull);
      expect(
        result.envelope.frozenCandidates
            .singleWhere(
              (candidate) => candidate.candidateId == target.candidateId,
            )
            .hardConstraintEvidence
            .ownershipPassed,
        isFalse,
      );
    },
  );

  test('empty ownership snapshot makes all real candidates invalid', () {
    final baseline = run();
    final result = run(
      ownedItemIds: const <String>[],
      wireDecisionPayload: <String, Object?>{
        'action': 'select_candidate',
        'selectedCandidateId': baseline.generatedCandidates.first.candidateId,
      },
    );

    expect(result.envelope.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.envelope.selectedCandidateId, isNull);
    expect(
      result.envelope.postDecisionValidatorResult.reasonCodes,
      contains('no_valid_frozen_candidates'),
    );
  });

  test('explicit reject_all retains no selected explanation candidate', () {
    final result = run(
      wireDecisionPayload: const <String, Object?>{
        'action': 'reject_all',
        'selectedCandidateId': null,
      },
    );

    expect(result.envelope.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.immutableExplanationInput.selectedCandidateId, isNull);
    expect(result.immutableExplanationInput.selectedCandidateItemIds, isEmpty);
  });

  test('malformed wire fails closed through matrix, adapter, and envelope', () {
    final baseline = run();
    final firstCandidateId = baseline.generatedCandidates.first.candidateId;
    final result = run(
      wireDecisionPayload: const <String, Object?>{
        'action': 'candidate_zero',
        'selectedCandidateId': 'v2_1',
      },
    );

    expect(result.parsedDecision.isSuccess, isFalse);
    expect(result.envelope.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.envelope.selectedCandidateId, isNull);
    expect(result.envelope.selectedCandidateId, isNot(firstCandidateId));
  });

  test('provider failure has no end-to-end candidate fallback', () {
    final baseline = run();
    final firstCandidateId = baseline.generatedCandidates.first.candidateId;
    final result = run(providerUnavailable: true);

    expect(
      result.parsedDecision.failureCode,
      FrozenOutfitDecisionTransportAdapterV1.providerFailure,
    );
    expect(result.envelope.action, FrozenOutfitDecisionActionV1.rejectAll);
    expect(result.envelope.selectedCandidateId, isNull);
    expect(result.envelope.selectedCandidateId, isNot(firstCandidateId));
  });

  test('unknown, malformed, and provider failure never select candidate A', () {
    final baseline = run();
    expect(baseline.generatedCandidates.length, greaterThanOrEqualTo(3));
    final candidateA = baseline.generatedCandidates.first.candidateId;
    final results = <FrozenOutfitDecisionV2HarnessResult>[
      run(
        wireDecisionPayload: const <String, Object?>{
          'action': 'select_candidate',
          'selectedCandidateId': 'unknown-id',
        },
      ),
      run(
        wireDecisionPayload: const <String, Object?>{
          'action': 'invalid',
          'selectedCandidateId': 'v2_1',
        },
      ),
      run(providerUnavailable: true),
    ];

    for (final result in results) {
      expect(result.envelope.action, FrozenOutfitDecisionActionV1.rejectAll);
      expect(result.envelope.selectedCandidateId, isNull);
      expect(result.envelope.selectedCandidateId, isNot(candidateA));
    }
  });

  test('integration explanation input cannot mutate a frozen decision', () {
    final baseline = run();
    final target = baseline.generatedCandidates.first;
    final result = run(
      wireDecisionPayload: <String, Object?>{
        'action': 'select_candidate',
        'selectedCandidateId': target.candidateId,
      },
    );

    expect(
      () => FrozenOutfitExplanationOutputV1.fromWire(<String, Object?>{
        'explanation': 'Skús iný outfit.',
        'selectedCandidateId': 'different-candidate',
      }),
      throwsArgumentError,
    );
    expect(
      result.immutableExplanationInput.selectedCandidateId,
      target.candidateId,
    );
  });

  test('real generated candidate IDs are non-empty and unique', () {
    final result = run();
    final ids = result.generatedCandidates
        .map((candidate) => candidate.candidateId)
        .toList();

    expect(ids.every((id) => id.trim().isNotEmpty), isTrue);
    expect(ids.toSet().length, ids.length);
  });

  test('ownership snapshot is immutable after freeze', () {
    final mutableOwnedIds =
        FrozenOutfitDecisionV2Harness.ownedItemIdsFromWardrobe(
          _realMatrixWardrobe(),
        ).toList();
    final baseline = run();
    final target = baseline.generatedCandidates.first;
    final result = run(
      ownedItemIds: mutableOwnedIds,
      wireDecisionPayload: <String, Object?>{
        'action': 'select_candidate',
        'selectedCandidateId': target.candidateId,
      },
    );
    mutableOwnedIds.clear();

    expect(result.envelope.authoritativeOwnedItemIds, isNotEmpty);
    expect(
      result.envelope.action,
      FrozenOutfitDecisionActionV1.selectCandidate,
    );
  });

  test('candidate order helper collection is immutable after freeze', () {
    final baseline = run();
    final mutableOrder = baseline.generatedCandidates.toList();
    final target = mutableOrder.first;
    final result = run(
      frozenCandidateOrder: mutableOrder,
      wireDecisionPayload: <String, Object?>{
        'action': 'select_candidate',
        'selectedCandidateId': target.candidateId,
      },
    );
    mutableOrder.clear();

    expect(result.envelope.frozenCandidates, isNotEmpty);
    expect(result.envelope.selectedCandidateId, target.candidateId);
  });
}
