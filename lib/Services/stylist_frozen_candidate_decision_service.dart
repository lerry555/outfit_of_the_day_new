import 'package:cloud_functions/cloud_functions.dart';

import '../domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import '../domain/wardrobe_v2/flexible_outfit_result_v2.dart';
import '../domain/wardrobe_v2/functional_suitability_v1.dart';

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
  bool get selected =>
      action == 'select_candidate' &&
      selectedCandidateId != null &&
      selectedCandidateId!.isNotEmpty;

  static const rejectAllFallback = StylistFrozenCandidateDecisionResultV1(
    action: 'reject_all',
    selectedCandidateId: null,
    explanation:
        'Tentoraz ti radšej outfit nepotvrdím, než by som predstieral, že je '
        'niektorá z možností naozaj vhodná.',
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

  static const conversationBrainVersion = 'brain_v1';

  final FirebaseFunctions? functions;

  Future<StylistFrozenCandidateDecisionResultV1> resolve({
    required List<V2FlexibleCandidate> candidates,
    required Map<String, dynamic> resolvedContext,
    bool lockedSelection = false,
    String presentationMode = 'normal',
    String focusSlot = '',
    String userRequest = '',
  }) async {
    if (candidates.isEmpty) {
      return StylistFrozenCandidateDecisionResultV1.rejectAllFallback;
    }
    try {
      final callable =
          (functions ?? FirebaseFunctions.instanceFor(region: 'us-east1'))
              .httpsCallable('resolveStylistFrozenCandidatesV1');
      final result = await callable
          .call(<String, dynamic>{
            'contractVersion': 1,
            // Explicit experiment opt-in. Older clients omit this marker and
            // retain the settled explanation path on the shared callable.
            'conversationBrainVersion': conversationBrainVersion,
            'resolvedContext': resolvedContext,
            'decisionMode': lockedSelection ? 'locked_selection' : 'select_candidate',
            'presentationMode': presentationMode,
            if (focusSlot.trim().isNotEmpty) 'focusSlot': focusSlot.trim(),
            if (userRequest.trim().isNotEmpty) 'userRequest': userRequest.trim(),
            'frozenCandidates': candidates
                .map(_candidatePayload)
                .toList(growable: false),
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
        selectedCandidateId: action == 'select_candidate'
            ? selectedCandidateId
            : null,
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
    final functional = candidate.functionalAssessment;
    final compromiseLevel = switch (functional?.tier) {
      FunctionalSuitabilityTierV1.acceptableCompromise =>
        'acceptable_compromise',
      FunctionalSuitabilityTierV1.strongCompromise => 'material_compromise',
      FunctionalSuitabilityTierV1.inappropriate => 'reject_all',
      _ => 'none',
    };
    return <String, dynamic>{
      'candidateId': candidate.candidateId,
      'itemIds': candidate.outfit.items
          .map((item) => item.itemId)
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false),
      // Presentation data is an immutable description of this same frozen
      // candidate. The authority validates itemId membership before using it
      // to build the user-facing explanation snapshot.
      'presentationItems': candidate.outfit.items
          .map(
            (item) => <String, dynamic>{
              'itemId': item.itemId,
              'name': _presentationName(item),
              'canonicalType': item.item.canonicalType,
              'primaryColor': item.item.colorProfile.primary.family,
              'slot': _presentationSlot(item),
            },
          )
          .toList(growable: false),
      'hardConstraintEvidence': <String, dynamic>{
        'deterministicPassed': validationErrors.isEmpty,
        'violationCodes': validationErrors,
      },
      'compromiseClassification': const <String, dynamic>{
        'level': 'none',
        'reasonCodes': <String>[],
      },
      if (functional != null) ...<String, dynamic>{
        'compromiseClassification': <String, dynamic>{
          'level': compromiseLevel,
          'reasonCodes': functional.reasonCodes,
        },
        'compromiseDetails': functional.items
            .where(
              (item) =>
                  item.tier.severity >=
                  FunctionalSuitabilityTierV1.acceptableCompromise.severity,
            )
            .map((item) {
              final selected = candidate.outfit.items
                  .where((value) => value.itemId == item.itemId)
                  .firstOrNull;
              return item.toUserFacingMap(
                selected == null
                    ? 'kúsok outfitu'
                    : _presentationName(selected),
              );
            })
            .toList(growable: false),
      },
    };
  }

  static String _presentationSlot(V2FlexibleOutfitItem item) {
    if (item.item.bodySlots.contains('feet')) return 'shoes';
    if (item.item.layerPosition == 'outer' || item.item.layerPosition == 'shell') {
      return 'outerwear';
    }
    if (item.item.bodySlots.contains('lower_body') &&
        !item.item.bodySlots.contains('upper_body')) {
      return 'bottom';
    }
    if (item.item.bodySlots.contains('upper_body')) return 'top';
    return '';
  }

  static String _presentationName(V2FlexibleOutfitItem item) {
    final display = item.display;
    for (final key in const ['name', 'displayName', 'title']) {
      final value = display[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return item.item.canonicalType;
  }
}
