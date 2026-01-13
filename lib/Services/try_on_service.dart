// lib/Services/try_on_service.dart
import 'package:cloud_functions/cloud_functions.dart';

class TryOnService {
  /// Callable Cloud Function name
  static const String _fnName = 'requestTryOn';

  final FirebaseFunctions _functions;

  TryOnService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Zavolá backend "try-on" a vráti URL výsledného obrázka.
  ///
  /// - garmentImageUrl: URL oblečenia (z tvojho šatníka: product/clean/cutout)
  /// - slot: napr. "torsoMid", "legsMid", "shoes"...
  /// - baseImageUrl: ak null -> backend použije default mannequin
  /// - sessionId: aby si vedel skladať viac kusov do jedného outfitu
  Future<String> requestTryOn({
    required String garmentImageUrl,
    required String slot,
    String? baseImageUrl,
    required String sessionId,
  }) async {
    final callable = _functions.httpsCallable(_fnName);

    final payload = <String, dynamic>{
      'garmentImageUrl': garmentImageUrl,
      'slot': slot,
      'sessionId': sessionId,
      if (baseImageUrl != null && baseImageUrl.trim().isNotEmpty)
        'baseImageUrl': baseImageUrl.trim(),
    };

    final res = await callable.call(payload);

    // Očakávame, že backend vráti { imageUrl: "https://..." }
    final data = res.data;
    if (data is Map) {
      final url = (data['imageUrl'] ?? data['resultUrl'] ?? data['url'])?.toString();
      if (url != null && url.trim().isNotEmpty) {
        return url.trim();
      }
    }

    throw Exception('requestTryOn: backend nevrátil imageUrl.');
  }
}
