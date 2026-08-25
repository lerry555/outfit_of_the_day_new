import 'frozen_outfit_decision_envelope_v1.dart';
import 'frozen_outfit_decision_request_v1.dart';
import 'frozen_outfit_decision_transport_adapter_v1.dart';

/// Provider-neutral seam. Implementations may return only the small wire
/// decision contract; they cannot receive mutable candidate authority.
abstract interface class FrozenOutfitDecisionClientV1 {
  Future<Object?> decide(FrozenOutfitDecisionRequestV1 request);
}

enum FrozenOutfitDecisionClientFailureKindV1 { provider, timeout }

class FrozenOutfitDecisionClientExceptionV1 implements Exception {
  const FrozenOutfitDecisionClientExceptionV1(this.kind, {this.reasonCode});

  final FrozenOutfitDecisionClientFailureKindV1 kind;
  final String? reasonCode;
}

enum FrozenOutfitDecisionOutcomeKindV1 {
  successSelect,
  validRejectAll,
  transportFailure,
  contractFailure,
  deterministicVeto,
}

/// A first-class app-side result. Rejecting all candidates is a valid decision,
/// never an exception. The effective decision always belongs to [envelope].
class FrozenOutfitDecisionOutcomeV1 {
  const FrozenOutfitDecisionOutcomeV1({
    required this.kind,
    required this.envelope,
    required this.parseResult,
  });

  final FrozenOutfitDecisionOutcomeKindV1 kind;
  final FrozenOutfitDecisionEnvelopeV1 envelope;
  final FrozenOutfitDecisionWireParseResultV1 parseResult;

  FrozenOutfitDecisionActionV1 get action => envelope.action;
  String? get selectedCandidateId => envelope.selectedCandidateId;
  bool get isRejected => action == FrozenOutfitDecisionActionV1.rejectAll;
}

/// Disabled/shadow-only orchestration. It intentionally has no import from a
/// screen, final-review runner, callable, router, or provider transport.
class FrozenOutfitDecisionOrchestratorV1 {
  const FrozenOutfitDecisionOrchestratorV1(this.client);

  final FrozenOutfitDecisionClientV1 client;

  Future<FrozenOutfitDecisionOutcomeV1> decide({
    required FrozenOutfitDecisionRequestV1 request,
    required Iterable<FrozenOutfitCandidateV1> frozenCandidates,
    required Iterable<String> authoritativeOwnedItemIds,
  }) async {
    FrozenOutfitDecisionWireParseResultV1 parsed;
    var transportFailure = false;
    try {
      final wire = await client.decide(request);
      parsed = FrozenOutfitDecisionTransportAdapterV1.parse(wire);
    } on FrozenOutfitDecisionClientExceptionV1 {
      transportFailure = true;
      // The adapter owns its stable wire failure code. The typed outcome
      // below preserves transport failure without selecting a replacement.
      parsed = FrozenOutfitDecisionTransportAdapterV1.providerUnavailable();
    } catch (_) {
      transportFailure = true;
      parsed = FrozenOutfitDecisionTransportAdapterV1.providerUnavailable();
    }

    final envelope = FrozenOutfitDecisionEnvelopeV1.freeze(
      candidates: frozenCandidates,
      authoritativeOwnedItemIds: authoritativeOwnedItemIds,
      decisionAttempt: parsed.toAttempt(),
    );
    return FrozenOutfitDecisionOutcomeV1(
      kind: _kindFor(
        parsed: parsed,
        envelope: envelope,
        transportFailure: transportFailure,
      ),
      envelope: envelope,
      parseResult: parsed,
    );
  }

  FrozenOutfitDecisionOutcomeKindV1 _kindFor({
    required FrozenOutfitDecisionWireParseResultV1 parsed,
    required FrozenOutfitDecisionEnvelopeV1 envelope,
    required bool transportFailure,
  }) {
    if (transportFailure || parsed.failureCode == 'provider_failure') {
      return FrozenOutfitDecisionOutcomeKindV1.transportFailure;
    }
    if (!parsed.isSuccess) {
      return FrozenOutfitDecisionOutcomeKindV1.contractFailure;
    }
    if (envelope.action == FrozenOutfitDecisionActionV1.selectCandidate) {
      return FrozenOutfitDecisionOutcomeKindV1.successSelect;
    }
    if (parsed.response!.action == FrozenOutfitDecisionActionV1.rejectAll &&
        envelope.postDecisionValidatorResult.requestedDecisionAccepted) {
      return FrozenOutfitDecisionOutcomeKindV1.validRejectAll;
    }
    return FrozenOutfitDecisionOutcomeKindV1.deterministicVeto;
  }
}
