import 'flexible_candidate_matrix_v2.dart';

/// Disabled/test-only boundary for a future frozen outfit decision pipeline.
///
/// It deliberately has no provider, Firebase, routing, or callable dependency.
/// Live production continues to use the existing final-review path until a
/// separately approved integration replaces that path.
const String frozenOutfitDecisionEnvelopeV1ContractVersion =
    'FrozenOutfitDecisionEnvelopeV1';

enum FrozenOutfitDecisionActionV1 {
  selectCandidate('select_candidate'),
  rejectAll('reject_all');

  const FrozenOutfitDecisionActionV1(this.wireValue);

  final String wireValue;
}

enum FrozenOutfitCompromiseLevelV1 {
  none('none'),
  acceptable('acceptable_compromise'),
  material('material_compromise'),
  rejectAll('reject_all');

  const FrozenOutfitCompromiseLevelV1(this.wireValue);

  final String wireValue;
}

/// Deterministic classification supplied by Wardrobe V2 rules. The explanation
/// layer may describe this value but never changes it.
class FrozenOutfitCompromiseClassificationV1 {
  FrozenOutfitCompromiseClassificationV1({
    required this.level,
    Iterable<String> reasonCodes = const <String>[],
  }) : reasonCodes = List.unmodifiable(_cleanCodes(reasonCodes));

  final FrozenOutfitCompromiseLevelV1 level;
  final List<String> reasonCodes;

  Map<String, Object?> toMap() => <String, Object?>{
    'level': level.wireValue,
    'reasonCodes': List<String>.from(reasonCodes),
  };
}

/// Evidence produced by deterministic code, not by a provider response.
class FrozenOutfitHardConstraintEvidenceV1 {
  FrozenOutfitHardConstraintEvidenceV1({
    required this.candidateId,
    required this.deterministicPassed,
    this.ownershipPassed = true,
    Iterable<String> violationCodes = const <String>[],
    Map<String, Object?> facts = const <String, Object?>{},
  }) : violationCodes = List.unmodifiable(_cleanCodes(violationCodes)),
       facts = _freezeStringMap(facts);

  final String candidateId;
  final bool deterministicPassed;
  final bool ownershipPassed;
  final List<String> violationCodes;
  final Map<String, Object?> facts;

  bool get passed =>
      deterministicPassed && ownershipPassed && violationCodes.isEmpty;

  FrozenOutfitHardConstraintEvidenceV1 withOwnershipCheck({
    required bool passed,
    Iterable<String> additionalViolationCodes = const <String>[],
  }) => FrozenOutfitHardConstraintEvidenceV1(
    candidateId: candidateId,
    deterministicPassed: deterministicPassed,
    ownershipPassed: ownershipPassed && passed,
    violationCodes: <String>[...violationCodes, ...additionalViolationCodes],
    facts: facts,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'candidateId': candidateId,
    'deterministicPassed': deterministicPassed,
    'ownershipPassed': ownershipPassed,
    'passed': passed,
    'violationCodes': List<String>.from(violationCodes),
    'facts': _copyFrozenMap(facts),
  };

  /// Adapter for existing Wardrobe V2 output. It preserves the current V2
  /// composition validator as evidence; it does not invent new fashion rules.
  factory FrozenOutfitHardConstraintEvidenceV1.fromFlexibleCandidate(
    V2FlexibleCandidate candidate,
  ) {
    final validationErrors = candidate.outfit.validate();
    return FrozenOutfitHardConstraintEvidenceV1(
      candidateId: candidate.candidateId,
      deterministicPassed: validationErrors.isEmpty,
      violationCodes: validationErrors,
      facts: <String, Object?>{
        'outfitValidationErrors': validationErrors,
        'coreComplete': candidate.outfit.completeness.coreComplete,
        'weatherComplete': candidate.outfit.completeness.weatherComplete,
        'dressCodeComplete': candidate.outfit.completeness.dressCodeComplete,
        'functionalComplete': candidate.outfit.completeness.functionalComplete,
      },
    );
  }
}

/// Immutable candidate identity and deterministic evidence captured at freeze.
class FrozenOutfitCandidateV1 {
  FrozenOutfitCandidateV1({
    required this.candidateId,
    required Iterable<String> itemIds,
    required this.hardConstraintEvidence,
    required this.compromiseClassification,
  }) : itemIds = List.unmodifiable(_cleanItemIds(itemIds)) {
    if (candidateId.trim().isEmpty) {
      throw ArgumentError.value(
        candidateId,
        'candidateId',
        'must not be empty',
      );
    }
    if (hardConstraintEvidence.candidateId != candidateId) {
      throw ArgumentError(
        'hardConstraintEvidence.candidateId must match candidateId',
      );
    }
  }

  final String candidateId;
  final List<String> itemIds;
  final FrozenOutfitHardConstraintEvidenceV1 hardConstraintEvidence;
  final FrozenOutfitCompromiseClassificationV1 compromiseClassification;

  bool get eligibleForSelection =>
      hardConstraintEvidence.passed &&
      compromiseClassification.level != FrozenOutfitCompromiseLevelV1.rejectAll;

  FrozenOutfitCandidateV1 withHardConstraintEvidence(
    FrozenOutfitHardConstraintEvidenceV1 evidence,
  ) => FrozenOutfitCandidateV1(
    candidateId: candidateId,
    itemIds: itemIds,
    hardConstraintEvidence: evidence,
    compromiseClassification: compromiseClassification,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'candidateId': candidateId,
    'itemIds': List<String>.from(itemIds),
    'hardConstraintEvidence': hardConstraintEvidence.toMap(),
    'compromiseClassification': compromiseClassification.toMap(),
  };

  /// Adapter for a future integration from the existing V2 candidate matrix.
  factory FrozenOutfitCandidateV1.fromFlexibleCandidate(
    V2FlexibleCandidate candidate, {
    FrozenOutfitCompromiseClassificationV1? compromiseClassification,
  }) => FrozenOutfitCandidateV1(
    candidateId: candidate.candidateId,
    itemIds: candidate.outfit.items.map((item) => item.itemId),
    hardConstraintEvidence:
        FrozenOutfitHardConstraintEvidenceV1.fromFlexibleCandidate(candidate),
    compromiseClassification:
        compromiseClassification ??
        FrozenOutfitCompromiseClassificationV1(
          level: FrozenOutfitCompromiseLevelV1.none,
        ),
  );
}

/// Untrusted decision input. A null [action] is intentionally representable so
/// malformed provider output can be converted to a safe reject-all result.
class FrozenOutfitDecisionAttemptV1 {
  FrozenOutfitDecisionAttemptV1._({
    required this.action,
    required this.selectedCandidateId,
    Iterable<String> reasonCodes = const <String>[],
  }) : reasonCodes = List.unmodifiable(_cleanCodes(reasonCodes));

  final FrozenOutfitDecisionActionV1? action;
  final String? selectedCandidateId;
  final List<String> reasonCodes;

  factory FrozenOutfitDecisionAttemptV1.selectCandidate(
    String candidateId, {
    Iterable<String> reasonCodes = const <String>[],
  }) => FrozenOutfitDecisionAttemptV1._(
    action: FrozenOutfitDecisionActionV1.selectCandidate,
    selectedCandidateId: candidateId.trim(),
    reasonCodes: reasonCodes,
  );

  factory FrozenOutfitDecisionAttemptV1.rejectAll({
    Iterable<String> reasonCodes = const <String>[],
  }) => FrozenOutfitDecisionAttemptV1._(
    action: FrozenOutfitDecisionActionV1.rejectAll,
    selectedCandidateId: null,
    reasonCodes: reasonCodes,
  );

  factory FrozenOutfitDecisionAttemptV1.invalid({
    String reasonCode = 'invalid_decision_attempt',
  }) => FrozenOutfitDecisionAttemptV1._(
    action: null,
    selectedCandidateId: null,
    reasonCodes: <String>[reasonCode],
  );

  factory FrozenOutfitDecisionAttemptV1.providerFailure({
    String reasonCode = 'decision_provider_failure',
  }) => FrozenOutfitDecisionAttemptV1.invalid(reasonCode: reasonCode);

  factory FrozenOutfitDecisionAttemptV1.fromWire(Object? value) {
    if (value is! Map) return FrozenOutfitDecisionAttemptV1.invalid();
    final map = Map<Object?, Object?>.from(value);
    final action = map['action'];
    final selectedCandidateId = map['selectedCandidateId']?.toString().trim();
    if (action == FrozenOutfitDecisionActionV1.selectCandidate.wireValue) {
      return FrozenOutfitDecisionAttemptV1.selectCandidate(
        selectedCandidateId ?? '',
      );
    }
    if (action == FrozenOutfitDecisionActionV1.rejectAll.wireValue) {
      if (selectedCandidateId?.isNotEmpty == true) {
        return FrozenOutfitDecisionAttemptV1.invalid(
          reasonCode: 'reject_all_must_not_select_candidate',
        );
      }
      return FrozenOutfitDecisionAttemptV1.rejectAll();
    }
    return FrozenOutfitDecisionAttemptV1.invalid(reasonCode: 'invalid_action');
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'action': action?.wireValue,
    'selectedCandidateId': selectedCandidateId,
    'reasonCodes': List<String>.from(reasonCodes),
  };
}

/// Result of the deterministic, post-decision authority check.
class FrozenOutfitPostDecisionValidatorResultV1 {
  FrozenOutfitPostDecisionValidatorResultV1({
    required this.requestedAction,
    required this.requestedSelectedCandidateId,
    required this.effectiveAction,
    required this.effectiveSelectedCandidateId,
    required this.requestedDecisionAccepted,
    Iterable<String> reasonCodes = const <String>[],
  }) : reasonCodes = List.unmodifiable(_cleanCodes(reasonCodes)) {
    if (effectiveAction == FrozenOutfitDecisionActionV1.rejectAll &&
        effectiveSelectedCandidateId != null) {
      throw ArgumentError(
        'reject_all must have null effectiveSelectedCandidateId',
      );
    }
    if (effectiveAction == FrozenOutfitDecisionActionV1.selectCandidate &&
        (effectiveSelectedCandidateId == null ||
            effectiveSelectedCandidateId!.isEmpty)) {
      throw ArgumentError(
        'select_candidate requires effectiveSelectedCandidateId',
      );
    }
  }

  final FrozenOutfitDecisionActionV1? requestedAction;
  final String? requestedSelectedCandidateId;
  final FrozenOutfitDecisionActionV1 effectiveAction;
  final String? effectiveSelectedCandidateId;
  final bool requestedDecisionAccepted;
  final List<String> reasonCodes;

  Map<String, Object?> toMap() => <String, Object?>{
    'requestedAction': requestedAction?.wireValue,
    'requestedSelectedCandidateId': requestedSelectedCandidateId,
    'effectiveAction': effectiveAction.wireValue,
    'effectiveSelectedCandidateId': effectiveSelectedCandidateId,
    'requestedDecisionAccepted': requestedDecisionAccepted,
    'reasonCodes': List<String>.from(reasonCodes),
  };
}

/// Pure deterministic authority. It cannot select a replacement candidate.
abstract final class FrozenOutfitDecisionValidatorV1 {
  static FrozenOutfitPostDecisionValidatorResultV1 validate({
    required List<FrozenOutfitCandidateV1> candidates,
    required FrozenOutfitDecisionAttemptV1? decisionAttempt,
  }) {
    final requestedAction = decisionAttempt?.action;
    final requestedId = decisionAttempt?.selectedCandidateId;
    final commonReasons = <String>[...?decisionAttempt?.reasonCodes];
    final validCandidates = candidates
        .where((candidate) => candidate.eligibleForSelection)
        .toList(growable: false);

    FrozenOutfitPostDecisionValidatorResultV1 reject(
      String reasonCode, {
      bool accepted = false,
    }) => FrozenOutfitPostDecisionValidatorResultV1(
      requestedAction: requestedAction,
      requestedSelectedCandidateId: requestedId,
      effectiveAction: FrozenOutfitDecisionActionV1.rejectAll,
      effectiveSelectedCandidateId: null,
      requestedDecisionAccepted: accepted,
      reasonCodes: <String>[...commonReasons, reasonCode],
    );

    if (validCandidates.isEmpty) return reject('no_valid_frozen_candidates');
    if (decisionAttempt == null || requestedAction == null) {
      return reject('missing_or_invalid_decision');
    }
    if (requestedAction == FrozenOutfitDecisionActionV1.rejectAll) {
      if (requestedId != null) {
        return reject('reject_all_must_not_select_candidate');
      }
      return reject('decision_reject_all', accepted: true);
    }
    if (requestedId == null || requestedId.trim().isEmpty) {
      return reject('missing_selected_candidate_id');
    }
    final candidate = candidates
        .where((candidate) => candidate.candidateId == requestedId)
        .firstOrNull;
    if (candidate == null) {
      return reject('selected_candidate_outside_frozen_set');
    }
    if (!candidate.eligibleForSelection) {
      return reject('selected_candidate_failed_hard_constraints');
    }
    return FrozenOutfitPostDecisionValidatorResultV1(
      requestedAction: requestedAction,
      requestedSelectedCandidateId: requestedId,
      effectiveAction: FrozenOutfitDecisionActionV1.selectCandidate,
      effectiveSelectedCandidateId: candidate.candidateId,
      requestedDecisionAccepted: true,
      reasonCodes: commonReasons,
    );
  }
}

/// The only data an explanation layer may receive about the decision.
class FrozenOutfitExplanationInputV1 {
  FrozenOutfitExplanationInputV1._({
    required this.action,
    required this.selectedCandidateId,
    required Iterable<String> selectedCandidateItemIds,
    required this.hardConstraintEvidence,
    required this.compromiseClassification,
    required this.postDecisionValidatorResult,
  }) : selectedCandidateItemIds = List.unmodifiable(
         _cleanItemIds(selectedCandidateItemIds),
       );

  final FrozenOutfitDecisionActionV1 action;
  final String? selectedCandidateId;
  final List<String> selectedCandidateItemIds;
  final FrozenOutfitHardConstraintEvidenceV1? hardConstraintEvidence;
  final FrozenOutfitCompromiseClassificationV1 compromiseClassification;
  final FrozenOutfitPostDecisionValidatorResultV1 postDecisionValidatorResult;

  Map<String, Object?> toMap() => <String, Object?>{
    'contractVersion': frozenOutfitDecisionEnvelopeV1ContractVersion,
    'action': action.wireValue,
    'selectedCandidateId': selectedCandidateId,
    'selectedCandidateItemIds': List<String>.from(selectedCandidateItemIds),
    'hardConstraintEvidence': hardConstraintEvidence?.toMap(),
    'compromiseClassification': compromiseClassification.toMap(),
    'postDecisionValidatorResult': postDecisionValidatorResult.toMap(),
  };
}

/// Explanation output has no authority-bearing fields by design.
class FrozenOutfitExplanationOutputV1 {
  FrozenOutfitExplanationOutputV1({
    required String explanation,
    Iterable<String> warnings = const <String>[],
  }) : explanation = explanation.trim(),
       warnings = List.unmodifiable(_cleanCodes(warnings));

  final String explanation;
  final List<String> warnings;

  factory FrozenOutfitExplanationOutputV1.fromWire(Object? value) {
    if (value is! Map) {
      throw ArgumentError.value(value, 'value', 'must be a map');
    }
    const forbiddenAuthorityKeys = <String>{
      'action',
      'selectedCandidateId',
      'candidateId',
      'candidates',
      'items',
      'outfitItems',
      'suggestedSwap',
      'swapInItemIds',
      'swapOutItemIds',
    };
    final keys = value.keys.map((key) => key.toString()).toSet();
    final forbidden = keys.intersection(forbiddenAuthorityKeys);
    if (forbidden.isNotEmpty) {
      throw ArgumentError(
        'explanation output contains authority fields: $forbidden',
      );
    }
    final rawWarnings = value['warnings'];
    return FrozenOutfitExplanationOutputV1(
      explanation: value['explanation']?.toString() ?? '',
      warnings: rawWarnings is Iterable
          ? rawWarnings.map((warning) => warning.toString())
          : const <String>[],
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'explanation': explanation,
    'warnings': List<String>.from(warnings),
  };
}

/// Frozen boundary output. The effective action is always the deterministic
/// validator result, never the provider's raw attempt.
class FrozenOutfitDecisionEnvelopeV1 {
  FrozenOutfitDecisionEnvelopeV1._({
    required Iterable<FrozenOutfitCandidateV1> frozenCandidates,
    required Iterable<String> authoritativeOwnedItemIds,
    required this.postDecisionValidatorResult,
  }) : frozenCandidates = List.unmodifiable(frozenCandidates),
       authoritativeOwnedItemIds = Set.unmodifiable(
         _cleanItemIds(authoritativeOwnedItemIds),
       );

  final List<FrozenOutfitCandidateV1> frozenCandidates;
  final Set<String> authoritativeOwnedItemIds;
  final FrozenOutfitPostDecisionValidatorResultV1 postDecisionValidatorResult;

  FrozenOutfitDecisionActionV1 get action =>
      postDecisionValidatorResult.effectiveAction;
  String? get selectedCandidateId =>
      postDecisionValidatorResult.effectiveSelectedCandidateId;

  FrozenOutfitCandidateV1? get selectedCandidate => selectedCandidateId == null
      ? null
      : frozenCandidates
            .where((candidate) => candidate.candidateId == selectedCandidateId)
            .firstOrNull;

  FrozenOutfitCompromiseClassificationV1 get compromiseClassification {
    final selected = selectedCandidate;
    if (selected != null) return selected.compromiseClassification;
    return FrozenOutfitCompromiseClassificationV1(
      level: FrozenOutfitCompromiseLevelV1.rejectAll,
      reasonCodes: postDecisionValidatorResult.reasonCodes,
    );
  }

  FrozenOutfitExplanationInputV1 get immutableExplanationInput =>
      FrozenOutfitExplanationInputV1._(
        action: action,
        selectedCandidateId: selectedCandidateId,
        selectedCandidateItemIds:
            selectedCandidate?.itemIds ?? const <String>[],
        hardConstraintEvidence: selectedCandidate?.hardConstraintEvidence,
        compromiseClassification: compromiseClassification,
        postDecisionValidatorResult: postDecisionValidatorResult,
      );

  Map<String, Object?> toMap() => <String, Object?>{
    'contractVersion': frozenOutfitDecisionEnvelopeV1ContractVersion,
    'frozenCandidates': frozenCandidates
        .map((candidate) => candidate.toMap())
        .toList(growable: false),
    'action': action.wireValue,
    'selectedCandidateId': selectedCandidateId,
    'deterministicHardConstraintEvidence': <String, Object?>{
      for (final candidate in frozenCandidates)
        candidate.candidateId: candidate.hardConstraintEvidence.toMap(),
    },
    'compromiseClassification': compromiseClassification.toMap(),
    'immutableExplanationInput': immutableExplanationInput.toMap(),
    'postDecisionValidatorResult': postDecisionValidatorResult.toMap(),
  };

  /// Freezes candidates and makes the deterministic post-decision result the
  /// sole authority. No error path in this factory selects a list position.
  factory FrozenOutfitDecisionEnvelopeV1.freeze({
    required Iterable<FrozenOutfitCandidateV1> candidates,
    required Iterable<String> authoritativeOwnedItemIds,
    FrozenOutfitDecisionAttemptV1? decisionAttempt,
  }) {
    final ownedIds = Set<String>.from(_cleanItemIds(authoritativeOwnedItemIds));
    final seenIds = <String>{};
    final frozenCandidates = <FrozenOutfitCandidateV1>[];
    for (final candidate in candidates) {
      if (!seenIds.add(candidate.candidateId)) {
        throw ArgumentError.value(
          candidate.candidateId,
          'candidates',
          'candidateId must be unique within a frozen set',
        );
      }
      final nonOwnedItemIds = candidate.itemIds
          .where((itemId) => !ownedIds.contains(itemId))
          .toList(growable: false);
      final evidence = candidate.hardConstraintEvidence.withOwnershipCheck(
        passed: nonOwnedItemIds.isEmpty,
        additionalViolationCodes: nonOwnedItemIds.isEmpty
            ? const <String>[]
            : const <String>['candidate_contains_non_owned_item'],
      );
      frozenCandidates.add(candidate.withHardConstraintEvidence(evidence));
    }
    final validatorResult = FrozenOutfitDecisionValidatorV1.validate(
      candidates: frozenCandidates,
      decisionAttempt: decisionAttempt,
    );
    return FrozenOutfitDecisionEnvelopeV1._(
      frozenCandidates: frozenCandidates,
      authoritativeOwnedItemIds: ownedIds,
      postDecisionValidatorResult: validatorResult,
    );
  }
}

List<String> _cleanCodes(Iterable<String> values) => values
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .toSet()
    .toList(growable: false);

List<String> _cleanItemIds(Iterable<String> values) => values
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .toList(growable: false);

Map<String, Object?> _freezeStringMap(Map<String, Object?> source) =>
    Map.unmodifiable(<String, Object?>{
      for (final entry in source.entries) entry.key: _freezeValue(entry.value),
    });

Map<String, Object?> _copyFrozenMap(
  Map<String, Object?> source,
) => <String, Object?>{
  for (final entry in source.entries) entry.key: _copyFrozenValue(entry.value),
};

Object? _freezeValue(Object? value) {
  if (value is Map) {
    return Map.unmodifiable(<Object?, Object?>{
      for (final entry in value.entries) entry.key: _freezeValue(entry.value),
    });
  }
  if (value is Iterable) {
    return List.unmodifiable(value.map(_freezeValue));
  }
  return value;
}

Object? _copyFrozenValue(Object? value) {
  if (value is Map) {
    return <Object?, Object?>{
      for (final entry in value.entries)
        entry.key: _copyFrozenValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_copyFrozenValue).toList(growable: false);
  }
  return value;
}
