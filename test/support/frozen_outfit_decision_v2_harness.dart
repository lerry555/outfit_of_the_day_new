import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_envelope_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/frozen_outfit_decision_transport_adapter_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';

/// Test-only integration harness for the future ID-based frozen-decision path.
/// It snapshots existing V2 candidate output and never participates in runtime.
class FrozenOutfitDecisionV2HarnessResult {
  const FrozenOutfitDecisionV2HarnessResult({
    required this.generatedCandidates,
    required this.parsedDecision,
    required this.envelope,
  });

  final List<V2FlexibleCandidate> generatedCandidates;
  final FrozenOutfitDecisionWireParseResultV1 parsedDecision;
  final FrozenOutfitDecisionEnvelopeV1 envelope;

  FrozenOutfitExplanationInputV1 get immutableExplanationInput =>
      envelope.immutableExplanationInput;
}

abstract final class FrozenOutfitDecisionV2Harness {
  /// Creates the authoritative ownership input from the same resolved wardrobe
  /// fixture that feeds the existing V2 candidate matrix.
  static List<String> ownedItemIdsFromWardrobe(
    Iterable<ResolvedWardrobeItemV2> wardrobe,
  ) => List.unmodifiable(wardrobe.map((item) => item.itemId));

  static FrozenOutfitDecisionV2HarnessResult run({
    required Iterable<ResolvedWardrobeItemV2> wardrobe,
    required V2CandidateMatrixContext context,
    required Iterable<String> authoritativeOwnedItemIds,
    Object? wireDecisionPayload,
    bool providerUnavailable = false,
    Iterable<V2FlexibleCandidate>? frozenCandidateOrder,
  }) {
    if (providerUnavailable && wireDecisionPayload != null) {
      throw ArgumentError(
        'providerUnavailable and wireDecisionPayload are mutually exclusive',
      );
    }
    final generatedCandidates = V2FlexibleCandidateMatrix.generate(
      wardrobe: wardrobe,
      context: context,
    );
    final orderedCandidates = List<V2FlexibleCandidate>.from(
      frozenCandidateOrder ?? generatedCandidates,
    );
    final frozenCandidates = orderedCandidates
        .map(FrozenOutfitCandidateV1.fromFlexibleCandidate)
        .toList(growable: false);
    final parsedDecision = providerUnavailable
        ? FrozenOutfitDecisionTransportAdapterV1.providerUnavailable()
        : FrozenOutfitDecisionTransportAdapterV1.parse(wireDecisionPayload);
    final envelope = FrozenOutfitDecisionEnvelopeV1.freeze(
      candidates: frozenCandidates,
      authoritativeOwnedItemIds: authoritativeOwnedItemIds,
      decisionAttempt: parsedDecision.toAttempt(),
    );
    return FrozenOutfitDecisionV2HarnessResult(
      generatedCandidates: List.unmodifiable(generatedCandidates),
      parsedDecision: parsedDecision,
      envelope: envelope,
    );
  }
}
