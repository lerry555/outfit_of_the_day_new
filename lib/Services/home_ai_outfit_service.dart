import 'package:cloud_functions/cloud_functions.dart';

class HomeAiOutfitResult {
  final String reply;
  final List<String> outfitItemIds;
  final bool fallback;
  final double confidence;
  final List<String> missingItems;

  const HomeAiOutfitResult({
    required this.reply,
    required this.outfitItemIds,
    required this.fallback,
    required this.confidence,
    required this.missingItems,
  });
}

class HomeAiOutfitService {
  const HomeAiOutfitService();

  Future<HomeAiOutfitResult> generateHomeOutfit({
    required DateTime date,
    required Map<String, dynamic> weatherContext,
    List<String> excludedItemIds = const [],
    List<String> rejectedCombinationSignatures = const [],
    List<String> previousOutfitItemIds = const [],
    bool forceDifferentOutfit = false,
  }) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-east1',
    ).httpsCallable('generateHomeOutfit');

    final result = await callable.call(<String, dynamic>{
      'date': date.toIso8601String(),
      'weatherContext': weatherContext,
      'excludedItemIds': excludedItemIds,
      'rejectedCombinationSignatures': rejectedCombinationSignatures,
      'previousOutfitItemIds': previousOutfitItemIds,
      'forceDifferentOutfit': forceDifferentOutfit,
    });

    final data = result.data;
    if (data is! Map) {
      return const HomeAiOutfitResult(
        reply: '',
        outfitItemIds: <String>[],
        fallback: true,
        confidence: 0.0,
        missingItems: <String>[],
      );
    }

    final map = Map<String, dynamic>.from(data);
    final ids = (map['outfitItemIds'] is List ? map['outfitItemIds'] as List : const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final missing = (map['missingItems'] is List ? map['missingItems'] as List : const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final confidenceRaw = map['confidence'];
    final confidence = confidenceRaw is num
        ? confidenceRaw.toDouble().clamp(0.0, 1.0)
        : double.tryParse(confidenceRaw?.toString() ?? '')?.clamp(0.0, 1.0) ?? 0.0;

    return HomeAiOutfitResult(
      reply: (map['reply'] ?? '').toString().trim(),
      outfitItemIds: ids,
      fallback: map['fallback'] == true,
      confidence: confidence,
      missingItems: missing,
    );
  }
}
