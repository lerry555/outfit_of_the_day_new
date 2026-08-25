import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class HomeOutfitStylistExplanationResult {
  const HomeOutfitStylistExplanationResult({
    required this.explanation,
    this.fallback = false,
  });

  final String explanation;
  final bool fallback;
}

class HomeOutfitStylistExplanationService {
  const HomeOutfitStylistExplanationService();

  Future<HomeOutfitStylistExplanationResult> generateExplanation({
    required DateTime date,
    required Map<String, dynamic> weatherContext,
    required List<Map<String, dynamic>> outfitItems,
    String? selectedReason,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-east1',
      ).httpsCallable('generateHomeOutfitExplanation');

      final result = await callable.call(<String, dynamic>{
        'date': date.toIso8601String(),
        'weatherContext': weatherContext,
        'outfitItems': outfitItems,
        if (selectedReason != null && selectedReason.trim().isNotEmpty)
          'selectedReason': selectedReason.trim(),
      });

      final data = result.data;
      if (data is! Map) {
        return const HomeOutfitStylistExplanationResult(
          explanation: '',
          fallback: true,
        );
      }

      final map = Map<String, dynamic>.from(data);
      final explanation = (map['explanation'] ?? map['reply'] ?? '')
          .toString()
          .trim();
      return HomeOutfitStylistExplanationResult(
        explanation: explanation,
        fallback: map['fallback'] == true || explanation.isEmpty,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[HOME_STYLIST_REASON_AI] cloud_error code=${e.code} message=${e.message}',
      );
      return const HomeOutfitStylistExplanationResult(
        explanation: '',
        fallback: true,
      );
    } catch (e) {
      debugPrint('[HOME_STYLIST_REASON_AI] cloud_error error=$e');
      return const HomeOutfitStylistExplanationResult(
        explanation: '',
        fallback: true,
      );
    }
  }
}
