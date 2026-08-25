import 'frozen_outfit_decision_envelope_v1.dart';

/// Canonical, provider-neutral input for the future frozen-candidate decision
/// role. This object deliberately contains no account, billing, Firestore or
/// provider credentials and has no candidate-index authority.
const String frozenOutfitDecisionRequestV1ContractVersion =
    'FrozenOutfitDecisionRequestV1';

class FrozenOutfitResolvedContextV1 {
  FrozenOutfitResolvedContextV1({
    this.activity,
    this.occasion,
    this.environment,
    this.weather,
    this.formality,
    this.terrain,
    Map<String, String?> relevantKnownTimingFacts = const <String, String?>{},
  }) : relevantKnownTimingFacts = Map.unmodifiable(
         Map<String, String?>.fromEntries(
           relevantKnownTimingFacts.entries
               .where((entry) => entry.key.trim().isNotEmpty)
               .map((entry) => MapEntry(entry.key.trim(), entry.value?.trim()))
               .toList(growable: false),
         ),
       );

  final String? activity;
  final String? occasion;
  final String? environment;
  final String? weather;
  final String? formality;
  final String? terrain;
  final Map<String, String?> relevantKnownTimingFacts;

  Map<String, Object?> toJson() => <String, Object?>{
    if (_known(activity)) 'activity': activity!.trim(),
    if (_known(occasion)) 'occasion': occasion!.trim(),
    if (_known(environment)) 'environment': environment!.trim(),
    if (_known(weather)) 'weather': weather!.trim(),
    if (_known(formality)) 'formality': formality!.trim(),
    if (_known(terrain)) 'terrain': terrain!.trim(),
    if (relevantKnownTimingFacts.isNotEmpty)
      'relevantKnownTimingFacts': <String, Object?>{
        for (final entry in relevantKnownTimingFacts.entries)
          if (_known(entry.value)) entry.key: entry.value!.trim(),
      },
  };
}

class FrozenOutfitDecisionRequestCandidateV1 {
  FrozenOutfitDecisionRequestCandidateV1({
    required this.candidateId,
    required Iterable<String> itemIds,
    required this.hardConstraintEvidence,
    required this.compromiseClassification,
  }) : itemIds = List.unmodifiable(itemIds.map((id) => id.trim()));

  factory FrozenOutfitDecisionRequestCandidateV1.fromFrozenCandidate(
    FrozenOutfitCandidateV1 candidate,
  ) => FrozenOutfitDecisionRequestCandidateV1(
    candidateId: candidate.candidateId,
    itemIds: candidate.itemIds,
    hardConstraintEvidence: candidate.hardConstraintEvidence,
    compromiseClassification: candidate.compromiseClassification,
  );

  final String candidateId;
  final List<String> itemIds;
  final FrozenOutfitHardConstraintEvidenceV1 hardConstraintEvidence;
  final FrozenOutfitCompromiseClassificationV1 compromiseClassification;

  Map<String, Object?> toJson() => <String, Object?>{
    'candidateId': candidateId,
    'itemIds': List<String>.from(itemIds),
    'deterministicEvidence': hardConstraintEvidence.toMap(),
    'compromiseClassification': compromiseClassification.toMap(),
  };
}

class FrozenOutfitDecisionRequestV1 {
  FrozenOutfitDecisionRequestV1({
    required this.resolvedContext,
    required Iterable<FrozenOutfitCandidateV1> frozenCandidates,
  }) : frozenCandidates = List.unmodifiable(
         frozenCandidates
             .map(FrozenOutfitDecisionRequestCandidateV1.fromFrozenCandidate)
             .toList(growable: false),
       ) {
    final ids = this.frozenCandidates.map((candidate) => candidate.candidateId);
    if (ids.toSet().length != this.frozenCandidates.length) {
      throw ArgumentError('frozen candidate IDs must be unique');
    }
  }

  final FrozenOutfitResolvedContextV1 resolvedContext;
  final List<FrozenOutfitDecisionRequestCandidateV1> frozenCandidates;

  static const List<String> allowedActions = <String>[
    'select_candidate',
    'reject_all',
  ];

  Map<String, Object?> toJson() => <String, Object?>{
    'contractVersion': frozenOutfitDecisionRequestV1ContractVersion,
    'resolvedContext': resolvedContext.toJson(),
    'frozenCandidates': frozenCandidates
        .map((candidate) => candidate.toJson())
        .toList(growable: false),
    'allowedActions': List<String>.from(allowedActions),
  };
}

bool _known(String? value) => value != null && value.trim().isNotEmpty;
