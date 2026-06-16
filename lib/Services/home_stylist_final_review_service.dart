import 'package:cloud_functions/cloud_functions.dart';

/// Result from AI stylist final review between multiple full outfit candidates.
class HomeStylistFinalReviewResult {
  HomeStylistFinalReviewResult({
    required this.selectedCandidateIndex,
    required this.reason,
    this.warnings = const [],
    this.fallback = false,
    this.suggestedSwap,
  });

  final int selectedCandidateIndex;
  final String reason;
  final List<String> warnings;
  final bool fallback;
  final Map<String, dynamic>? suggestedSwap;
}

class HomeStylistFinalReviewService {
  const HomeStylistFinalReviewService();

  Future<HomeStylistFinalReviewResult> reviewCandidates({
    required Map<String, dynamic> weatherContext,
    required List<Map<String, dynamic>> candidates,
    Map<String, dynamic>? footwearGuidance,
    Map<String, dynamic>? bottomGuidance,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-east1')
        .httpsCallable('finalReviewHomeOutfitCandidates');

    final result = await callable.call(<String, dynamic>{
      'weatherContext': weatherContext,
      'candidates': candidates,
      if (footwearGuidance != null) 'footwearGuidance': footwearGuidance,
      if (bottomGuidance != null) 'bottomGuidance': bottomGuidance,
    });

    final data = result.data;
    if (data is! Map) {
      return HomeStylistFinalReviewResult(
        selectedCandidateIndex: 0,
        reason: 'invalid_response_shape',
        fallback: true,
      );
    }
    final map = Map<String, dynamic>.from(data);

    final fallback = map['fallback'] == true;
    final selectedRaw = map['selectedCandidateIndex'];
    final int? selectedCandidateIndex =
        selectedRaw is num
            ? selectedRaw.toInt()
            : int.tryParse(selectedRaw?.toString() ?? '');

    final reason = (map['reason'] ?? '').toString().trim();
    final warningsRaw = map['warnings'];
    final warnings = warningsRaw is List
        ? warningsRaw.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    final suggestedSwapRaw = map['suggestedSwap'];
    Map<String, dynamic>? suggestedSwap;
    if (suggestedSwapRaw is Map) {
      suggestedSwap = Map<String, dynamic>.from(suggestedSwapRaw);
    }

    if (selectedCandidateIndex == null || selectedCandidateIndex < 0) {
      return HomeStylistFinalReviewResult(
        selectedCandidateIndex: 0,
        reason: reason.isEmpty ? 'invalid_selected_index' : reason,
        warnings: warnings,
        fallback: true,
        suggestedSwap: suggestedSwap,
      );
    }

    return HomeStylistFinalReviewResult(
      selectedCandidateIndex: selectedCandidateIndex,
      reason: reason,
      warnings: warnings,
      fallback: fallback,
      suggestedSwap: suggestedSwap,
    );
  }
}

