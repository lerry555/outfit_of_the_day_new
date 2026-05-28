import '../Services/product_link_image_cleanup.dart';

bool wardrobeItemShowsImageProcessingBadge(Map<String, dynamic> raw) {
  final s = (raw['imageProcessingStatus'] ?? kImageProcessingStatusNone).toString();
  return s == kImageProcessingStatusProcessing;
}

bool _wardrobeUrlFilled(String? url) {
  final u = (url ?? '').trim();
  return u.startsWith('http://') || u.startsWith('https://');
}

String wardrobeTileDisplayImageUrl(Map<String, dynamic> data) {
  final processing = wardrobeItemShowsImageProcessingBadge(data);
  final seed = (data['productLinkSeedImageUrl'] ?? '').toString().trim();
  final original = (data['originalImageUrl'] ?? '').toString().trim();
  final product = (data['productImageUrl'] ?? '').toString().trim();
  final clean = (data['cleanImageUrl'] ?? '').toString().trim();
  final cutout = (data['cutoutImageUrl'] ?? '').toString().trim();
  final legacy = (data['imageUrl'] ?? '').toString().trim();

  if (processing) {
    if (_wardrobeUrlFilled(seed)) return seed;
    if (_wardrobeUrlFilled(original)) return original;
    if (_wardrobeUrlFilled(legacy)) return legacy;
    return '';
  }

  if (_wardrobeUrlFilled(product)) return product;
  if (_wardrobeUrlFilled(clean)) return clean;
  if (_wardrobeUrlFilled(cutout)) return cutout;
  if (_wardrobeUrlFilled(original)) return original;
  if (_wardrobeUrlFilled(seed)) return seed;
  if (_wardrobeUrlFilled(legacy)) return legacy;
  return '';
}

String? wardrobeTileImageFallbackUrl(Map<String, dynamic> data, String failedUrl) {
  final failed = failedUrl.trim();
  final candidates = [
    data['productLinkSeedImageUrl'],
    data['originalImageUrl'],
    data['imageUrl'],
    data['cleanImageUrl'],
    data['cutoutImageUrl'],
    data['productImageUrl'],
  ];
  for (final raw in candidates) {
    final u = (raw ?? '').toString().trim();
    if (!_wardrobeUrlFilled(u) || u == failed) continue;
    return u;
  }
  return null;
}
