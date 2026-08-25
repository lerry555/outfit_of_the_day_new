import 'frozen_outfit_decision_envelope_v1.dart';
import 'frozen_outfit_decision_request_v1.dart';

const String frozenOutfitExplanationRequestV1ContractVersion =
    'FrozenOutfitExplanationRequestV1';

/// Explanation input is constructed only after deterministic validation. It
/// deliberately has no field by which a provider could select, replace or swap
/// a candidate.
class FrozenOutfitExplanationRequestV1 {
  FrozenOutfitExplanationRequestV1._({
    required this.decision,
    required this.resolvedContext,
  });

  factory FrozenOutfitExplanationRequestV1.fromValidatedEnvelope({
    required FrozenOutfitDecisionEnvelopeV1 envelope,
    required FrozenOutfitResolvedContextV1 resolvedContext,
  }) => FrozenOutfitExplanationRequestV1._(
    decision: envelope.immutableExplanationInput,
    resolvedContext: resolvedContext,
  );

  final FrozenOutfitExplanationInputV1 decision;
  final FrozenOutfitResolvedContextV1 resolvedContext;

  Map<String, Object?> toJson() => <String, Object?>{
    'contractVersion': frozenOutfitExplanationRequestV1ContractVersion,
    'effectiveAction': decision.action.wireValue,
    'effectiveSelectedCandidateId': decision.selectedCandidateId,
    'selectedFrozenItemIds': List<String>.from(
      decision.selectedCandidateItemIds,
    ),
    'hardConstraintEvidence': decision.hardConstraintEvidence?.toMap(),
    'compromiseClassification': decision.compromiseClassification.toMap(),
    'decisionReasons': List<String>.from(
      decision.postDecisionValidatorResult.reasonCodes,
    ),
    'resolvedContext': resolvedContext.toJson(),
  };
}

class FrozenOutfitExplanationResponseV1 {
  FrozenOutfitExplanationResponseV1({
    required String text,
    Iterable<String> warningCodes = const <String>[],
  }) : text = text.trim(),
       warningCodes = List.unmodifiable(
         warningCodes
             .map((code) => code.trim())
             .where((code) => code.isNotEmpty),
       );

  final String text;
  final List<String> warningCodes;

  factory FrozenOutfitExplanationResponseV1.parse(Object? wire) {
    if (wire is! Map) {
      throw const FormatException('explanation_payload_not_object');
    }
    final map = Map<Object?, Object?>.from(wire);
    const allowed = {'explanation', 'warnings'};
    if (map.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('explanation_authority_field_rejected');
    }
    if (map['explanation'] is! String ||
        (map['explanation'] as String).trim().isEmpty) {
      throw const FormatException('explanation_text_invalid');
    }
    final warnings = map['warnings'];
    if (warnings != null &&
        (warnings is! List || warnings.any((value) => value is! String))) {
      throw const FormatException('explanation_warnings_invalid');
    }
    return FrozenOutfitExplanationResponseV1(
      text: map['explanation'] as String,
      warningCodes: warnings == null
          ? const []
          : List<String>.from(warnings as List),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'explanation': text,
    if (warningCodes.isNotEmpty) 'warnings': List<String>.from(warningCodes),
  };
}

abstract interface class FrozenOutfitExplanationClientV1 {
  Future<Object?> explain(FrozenOutfitExplanationRequestV1 request);
}

/// Safe, local Slovak fallback. It reads an immutable decision and never starts
/// a second candidate-selection pass.
abstract final class FrozenOutfitExplanationFallbackV1 {
  static FrozenOutfitExplanationResponseV1 forRequest(
    FrozenOutfitExplanationRequestV1 request, {
    String reasonCode = 'explanation_unavailable',
  }) => FrozenOutfitExplanationResponseV1(
    text: request.decision.action == FrozenOutfitDecisionActionV1.rejectAll
        ? 'Nenašiel som bezpečný outfit, ktorý by prešiel všetkými podmienkami.'
        : 'Vybraný outfit prešiel deterministickou kontrolou podmienok.',
    warningCodes: [reasonCode],
  );
}

class FrozenOutfitExplanationResultV1 {
  const FrozenOutfitExplanationResultV1({
    required this.response,
    required this.usedFallback,
    this.failureCode,
  });
  final FrozenOutfitExplanationResponseV1 response;
  final bool usedFallback;
  final String? failureCode;
}

class FrozenOutfitExplanationOrchestratorV1 {
  const FrozenOutfitExplanationOrchestratorV1(this.client);
  final FrozenOutfitExplanationClientV1 client;

  Future<FrozenOutfitExplanationResultV1> explain(
    FrozenOutfitExplanationRequestV1 request,
  ) async {
    try {
      return FrozenOutfitExplanationResultV1(
        response: FrozenOutfitExplanationResponseV1.parse(
          await client.explain(request),
        ),
        usedFallback: false,
      );
    } on FormatException catch (error) {
      return FrozenOutfitExplanationResultV1(
        response: FrozenOutfitExplanationFallbackV1.forRequest(
          request,
          reasonCode: error.message.toString(),
        ),
        usedFallback: true,
        failureCode: error.message.toString(),
      );
    } catch (_) {
      return FrozenOutfitExplanationResultV1(
        response: FrozenOutfitExplanationFallbackV1.forRequest(request),
        usedFallback: true,
        failureCode: 'explanation_provider_failure',
      );
    }
  }
}
