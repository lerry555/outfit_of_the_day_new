import 'frozen_outfit_decision_envelope_v1.dart';

/// Provider-neutral, offline-only DTO for the future frozen-decision response.
///
/// This module intentionally has no Firebase, provider, routing, or callable
/// dependency. Live production continues to use its current index-based
/// contract until a separately approved integration is introduced.
class FrozenOutfitDecisionWireResponseV1 {
  FrozenOutfitDecisionWireResponseV1({
    required this.action,
    required this.selectedCandidateId,
  }) {
    switch (action) {
      case FrozenOutfitDecisionActionV1.selectCandidate:
        if (selectedCandidateId == null || selectedCandidateId!.isEmpty) {
          throw ArgumentError(
            'select_candidate requires a non-empty selectedCandidateId',
          );
        }
      case FrozenOutfitDecisionActionV1.rejectAll:
        if (selectedCandidateId != null) {
          throw ArgumentError('reject_all requires null selectedCandidateId');
        }
    }
  }

  final FrozenOutfitDecisionActionV1 action;
  final String? selectedCandidateId;

  FrozenOutfitDecisionAttemptV1 toAttempt() => switch (action) {
    FrozenOutfitDecisionActionV1.selectCandidate =>
      FrozenOutfitDecisionAttemptV1.selectCandidate(selectedCandidateId!),
    FrozenOutfitDecisionActionV1.rejectAll =>
      FrozenOutfitDecisionAttemptV1.rejectAll(),
  };

  factory FrozenOutfitDecisionWireResponseV1.fromAttempt(
    FrozenOutfitDecisionAttemptV1 attempt,
  ) {
    final action = attempt.action;
    if (action == null) {
      throw ArgumentError('invalid attempt has no serializable wire action');
    }
    return FrozenOutfitDecisionWireResponseV1(
      action: action,
      selectedCandidateId: attempt.selectedCandidateId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'action': action.wireValue,
    'selectedCandidateId': selectedCandidateId,
  };
}

/// Typed parse outcome. Failures remain explicit and can only become a
/// fail-closed [FrozenOutfitDecisionAttemptV1].
class FrozenOutfitDecisionWireParseResultV1 {
  FrozenOutfitDecisionWireParseResultV1._success(this.response)
    : failureCode = null;

  FrozenOutfitDecisionWireParseResultV1._failure(this.failureCode)
    : response = null;

  final FrozenOutfitDecisionWireResponseV1? response;
  final String? failureCode;

  bool get isSuccess => response != null;

  FrozenOutfitDecisionAttemptV1 toAttempt() {
    final validResponse = response;
    if (validResponse != null) return validResponse.toAttempt();
    if (failureCode == FrozenOutfitDecisionTransportAdapterV1.providerFailure) {
      return FrozenOutfitDecisionAttemptV1.providerFailure();
    }
    return FrozenOutfitDecisionAttemptV1.invalid(
      reasonCode:
          failureCode ??
          FrozenOutfitDecisionTransportAdapterV1.payloadMalformed,
    );
  }
}

/// Strict parser and serializer for the ID-based decision wire contract.
abstract final class FrozenOutfitDecisionTransportAdapterV1 {
  static const String payloadMissing = 'payload_missing';
  static const String payloadNotObject = 'payload_not_object';
  static const String payloadMalformed = 'payload_malformed';
  static const String actionMissing = 'action_missing';
  static const String actionInvalid = 'action_invalid';
  static const String selectedCandidateIdMissing =
      'selected_candidate_id_missing';
  static const String selectedCandidateIdInvalid =
      'selected_candidate_id_invalid';
  static const String rejectAllRequiresNullCandidate =
      'reject_all_requires_null_candidate';
  static const String providerFailure = 'provider_failure';

  static const Set<String> _allowedKeys = <String>{
    'action',
    'selectedCandidateId',
  };

  static FrozenOutfitDecisionWireParseResultV1 parse(Object? payload) {
    if (payload == null) {
      return FrozenOutfitDecisionWireParseResultV1._failure(payloadMissing);
    }
    if (payload is! Map) {
      return FrozenOutfitDecisionWireParseResultV1._failure(payloadNotObject);
    }
    if (payload.keys.any((key) => key is! String)) {
      return FrozenOutfitDecisionWireParseResultV1._failure(payloadMalformed);
    }
    final map = Map<String, Object?>.from(payload);
    if (map.keys.any((key) => !_allowedKeys.contains(key))) {
      return FrozenOutfitDecisionWireParseResultV1._failure(payloadMalformed);
    }
    if (!map.containsKey('action')) {
      return FrozenOutfitDecisionWireParseResultV1._failure(actionMissing);
    }
    final actionValue = map['action'];
    if (actionValue is! String) {
      return FrozenOutfitDecisionWireParseResultV1._failure(actionInvalid);
    }
    switch (actionValue) {
      case 'select_candidate':
        return _parseSelect(map);
      case 'reject_all':
        return _parseRejectAll(map);
      default:
        return FrozenOutfitDecisionWireParseResultV1._failure(actionInvalid);
    }
  }

  static FrozenOutfitDecisionWireParseResultV1 providerUnavailable() =>
      FrozenOutfitDecisionWireParseResultV1._failure(providerFailure);

  static FrozenOutfitDecisionWireParseResultV1 _parseSelect(
    Map<String, Object?> map,
  ) {
    if (!map.containsKey('selectedCandidateId')) {
      return FrozenOutfitDecisionWireParseResultV1._failure(
        selectedCandidateIdMissing,
      );
    }
    final rawId = map['selectedCandidateId'];
    if (rawId is! String) {
      return FrozenOutfitDecisionWireParseResultV1._failure(
        selectedCandidateIdInvalid,
      );
    }
    final candidateId = rawId.trim();
    if (candidateId.isEmpty) {
      return FrozenOutfitDecisionWireParseResultV1._failure(
        selectedCandidateIdInvalid,
      );
    }
    return FrozenOutfitDecisionWireParseResultV1._success(
      FrozenOutfitDecisionWireResponseV1(
        action: FrozenOutfitDecisionActionV1.selectCandidate,
        selectedCandidateId: candidateId,
      ),
    );
  }

  static FrozenOutfitDecisionWireParseResultV1 _parseRejectAll(
    Map<String, Object?> map,
  ) {
    if (!map.containsKey('selectedCandidateId') ||
        map['selectedCandidateId'] != null) {
      return FrozenOutfitDecisionWireParseResultV1._failure(
        rejectAllRequiresNullCandidate,
      );
    }
    return FrozenOutfitDecisionWireParseResultV1._success(
      FrozenOutfitDecisionWireResponseV1(
        action: FrozenOutfitDecisionActionV1.rejectAll,
        selectedCandidateId: null,
      ),
    );
  }
}
