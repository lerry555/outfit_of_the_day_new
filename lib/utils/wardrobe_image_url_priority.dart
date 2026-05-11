/// Image URL priority helper used across the app.
///
/// Priority required by product:
/// `productImageUrl -> cutoutImageUrl -> cleanImageUrl -> imageUrl`
///
/// Notes:
/// - Some wardrobe items also have `originalImageUrl`; we keep it as a fallback
///   right before the legacy `imageUrl` field to avoid broken previews.
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

  // Extra fallback (some items store an "original" URL).
  final original = getStr('originalImageUrl');
  if (_isUrlFilled(original)) return original!.trim();

  final legacy = getStr('imageUrl');
  if (_isUrlFilled(legacy)) return legacy!.trim();

  return null;
}

