/// Image URL priority helper used across the app.
///
/// Priority (first non-empty after trim):
/// `productImageUrl → cutoutImageUrl → cleanImageUrl → imageUrl → originalImageUrl`
///
/// `originalImageUrl` len ako posledný fallback (nie medzi clean a imageUrl).
library wardrobe_image_url_priority;

bool _isUrlFilled(String? s) => s != null && s.trim().isNotEmpty;

String? resolveWardrobeImageUrl(Map<String, dynamic> item) {
  String? getStr(String key) {
    final v = item[key];
    if (v == null) return null;
    return v.toString();
  }

  final product = getStr('productImageUrl');
  if (_isUrlFilled(product)) return product!.trim();

  final cutout = getStr('cutoutImageUrl');
  if (_isUrlFilled(cutout)) return cutout!.trim();

  final clean = getStr('cleanImageUrl');
  if (_isUrlFilled(clean)) return clean!.trim();

  final legacy = getStr('imageUrl');
  if (_isUrlFilled(legacy)) return legacy!.trim();

  final original = getStr('originalImageUrl');
  if (_isUrlFilled(original)) return original!.trim();

  return null;
}

/// Home hero outfit tiles — prefer transparent garment assets over studio product shots.
/// Order: `cutoutImageUrl → cleanImageUrl → productImageUrl → imageUrl → originalImageUrl`.
String? resolveHeroHomeOutfitImageUrl(Map<String, dynamic> item) {
  String? getStr(String key) {
    final v = item[key];
    if (v == null) return null;
    return v.toString();
  }

  final cutout = getStr('cutoutImageUrl');
  if (_isUrlFilled(cutout)) return cutout!.trim();

  final clean = getStr('cleanImageUrl');
  if (_isUrlFilled(clean)) return clean!.trim();

  final product = getStr('productImageUrl');
  if (_isUrlFilled(product)) return product!.trim();

  final legacy = getStr('imageUrl');
  if (_isUrlFilled(legacy)) return legacy!.trim();

  final original = getStr('originalImageUrl');
  if (_isUrlFilled(original)) return original!.trim();

  return null;
}

