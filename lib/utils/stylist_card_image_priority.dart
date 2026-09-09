import '../Services/clothing_analyzer_pipeline.dart';
import '../Services/product_link_v2_display_policy.dart';
import 'wardrobe_image_url_priority.dart';

class StylistCardImageCandidate {
  const StylistCardImageCandidate({required this.url, required this.kind, this.storagePath});
  final String url;
  final String kind;
  final String? storagePath;
}

bool _http(String value) => value.startsWith('http://') || value.startsWith('https://');

String? _pathFor(Map<String, dynamic> item, String key, String url) {
  final explicit = (item[key] ?? '').toString().trim();
  if (explicit.isNotEmpty) return explicit;
  return ClothingAnalyzerPipeline.storagePathFromFirebaseUrl(url);
}

/// Stylist cards are product-like recommendation surfaces. Raw imageUrl and
/// originalImageUrl are intentionally excluded because they can contain the
/// person who uploaded the garment.
List<StylistCardImageCandidate> stylistCardImageCandidates(Map<String, dynamic> item) {
  final out = <StylistCardImageCandidate>[];
  final seen = <String>{};
  final storagePath = (item['storagePath'] ?? '').toString().trim();
  final ownedV2 = isOwnedV2CanonicalStoragePath(storagePath);

  void add(String key, String kind, String storageKey, {bool product = false}) {
    final url = (item[key] ?? '').toString().trim();
    if (!_http(url) || seen.contains(url)) return;
    if (product && !canUseProductImageUrl(item)) return;
    if (!product && ownedV2 && !isOwnedV2SameSourceDisplayUrl(item: item, url: url)) return;
    seen.add(url);
    out.add(StylistCardImageCandidate(
      url: url,
      kind: kind,
      storagePath: _pathFor(item, storageKey, url),
    ));
  }

  add('productImageUrl', 'product', 'productStoragePath', product: true);
  add('cutoutImageUrl', 'cutout', 'cleanStoragePath');
  add('cleanImageUrl', 'clean', 'cleanStoragePath');
  return List<StylistCardImageCandidate>.unmodifiable(out);
}
