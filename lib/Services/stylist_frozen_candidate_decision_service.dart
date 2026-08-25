import 'package:cloud_functions/cloud_functions.dart';

import '../domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';

/// Client transport for the authoritative Stylist Track-D/R seam.
///
/// It intentionally returns no positional fallback. A timeout, malformed
/// payload or provider failure is represented as [rejectAll], so callers never
/// turn a failed decision into `candidates.first`.
class StylistFrozenCandidateDecisionResultV1 {
  const StylistFrozenCandidateDecisionResultV1({
    required this.action,
    required this.selectedCandidateId,
    required this.explanation,
    required this.reasonCodes,
    required this.explanationFallback,
  });

  final String action;
  final String? selectedCandidateId;
  final String explanation;
  final List<String> reasonCodes;
  final bool explanationFallback;

  bool get rejectAll => action == 'reject_all';
  bool get selected => action == 'select_candidate' &&
      selectedCandidateId != null &&
      selectedCandidateId!.isNotEmpty;

  static const rejectAllFallback = StylistFrozenCandidateDecisionResultV1(
    action: 'reject_all',
    selectedCandidateId: null,
    explanation: 'Z dostupných možností teraz neviem bezpečne potvrdiť vhodný outfit.',
    reasonCodes: <String>['decision_transport_unavailable'],
    explanationFallback: true,
  );
}

class StylistFrozenDecisionRejectedExceptionV1 implements Exception {
  const StylistFrozenDecisionRejectedExceptionV1(
    this.reasonCodes, {
    this.explanation = '',
  });
  final List<String> reasonCodes;
  final String explanation;
}

class StylistFrozenCandidateDecisionServiceV1 {
  const StylistFrozenCandidateDecisionServiceV1({this.functions});

  final FirebaseFunctions? functions;

  Future<StylistFrozenCandidateDecisionResultV1> resolve({
    required List<V2FlexibleCandidate> candidates,
    required Map<String, dynamic> resolvedContext,
  }) async {
    if (candidates.isEmpty) {
      return StylistFrozenCandidateDecisionResultV1.rejectAllFallback;
    }
    try {
      final callable = (functions ?? FirebaseFunctions.instanceFor(
        region: 'us-east1',
      )).httpsCallable('resolveStylistFrozenCandidatesV1');
      final result = await callable
          .call(<String, dynamic>{
            'contractVersion': 1,
            'resolvedContext': resolvedContext,
            'frozenCandidates': candidates.map(_candidatePayload).toList(
              growable: false,
            ),
          })
          .timeout(const Duration(seconds: 45));
      final raw = result.data;
      if (raw is! Map) {
        return StylistFrozenCandidateDecisionResultV1.rejectAllFallback;
      }
      final action = (raw['action'] ?? '').toString();
      final selectedCandidateId = raw['selectedCandidateId']?.toString().trim();
      if (action == 'select_candidate' &&
          (selectedCandidateId == null || selectedCandidateId.isEmpty)) {
        return StylistFrozenCandidateDecisionResultV1.rejectAllFallback;
      }
      if (action != 'select_candidate' && action != 'reject_all') {
        return StylistFrozenCandidateDecisionResultV1.rejectAllFallback;
      }
      return StylistFrozenCandidateDecisionResultV1(
        action: action,
        selectedCandidateId:
            action == 'select_candidate' ? selectedCandidateId : null,
        explanation: (raw['explanation'] ?? '').toString().trim(),
        reasonCodes: raw['reasonCodes'] is List
            ? (raw['reasonCodes'] as List)
                  .map((value) => value.toString().trim())
                  .where((value) => value.isNotEmpty)
                  .toList(growable: false)
            : const <String>[],
        explanationFallback: raw['explanationFallback'] == true,
      );
    } catch (_) {
      return StylistFrozenCandidateDecisionResultV1.rejectAllFallback;
    }
  }

  static Map<String, dynamic> _candidatePayload(V2FlexibleCandidate candidate) {
    final validationErrors = candidate.outfit.validate();
    return <String, dynamic>{
      'candidateId': candidate.candidateId,
      'itemIds': candidate.outfit.items
          .map((item) => item.itemId)
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false),
      'hardConstraintEvidence': <String, dynamic>{
        'deterministicPassed': validationErrors.isEmpty,
        'violationCodes': validationErrors,
      },
      'compromiseClassification': const <String, dynamic>{
        'level': 'none',
        'reasonCodes': <String>[],
      },
    };
  }
}
