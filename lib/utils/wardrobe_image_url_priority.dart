/// Image URL priority helper used across the app.
///
/// [getBestWardrobeImageUrl] picks the best display URL:
/// product (only when `processing.product == done` and distinct from original)
/// → cutout → clean → imageUrl / originalImageUrl.
library wardrobe_image_url_priority;

import 'package:flutter/foundation.dart';

import 'home_debug_logging.dart';

bool _isHttpUrl(String? s) {
  final u = (s ?? '').trim();
  return u.startsWith('http://') || u.startsWith('https://');
}

bool _urlsEqual(String? a, String? b) {
  if (a == null || b == null) return false;
  return a.trim() == b.trim();
}

String _processingStatus(Map<String, dynamic> item, String key) {
  final p = item['processing'];
  if (p is Map) {
    final v = (p.cast<String, dynamic>()[key] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  final dotted = item['processing.$key'];
  if (dotted != null) {
    final v = dotted.toString().trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}

String? _getStr(Map<String, dynamic> item, String key) {
  final v = item[key];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

bool canUseProductImageUrl(Map<String, dynamic> item) {
  final product = _getStr(item, 'productImageUrl');
  if (!_isHttpUrl(product)) return false;

  final productStatus = _processingStatus(item, 'product');
  if (productStatus != 'done') return false;

  final legacy = _getStr(item, 'imageUrl');
  final original = _getStr(item, 'originalImageUrl');
  if (_urlsEqual(product, legacy) || _urlsEqual(product, original)) {
    return false;
  }

  return true;
}

/// Result of wardrobe image URL selection (shared by cards and detail).
class WardrobeImagePick {
  final String? url;
  final String reason;

  const WardrobeImagePick({required this.url, required this.reason});
}

WardrobeImagePick pickBestWardrobeImageUrl(Map<String, dynamic> item) {
  if (canUseProductImageUrl(item)) {
    return WardrobeImagePick(
      url: _getStr(item, 'productImageUrl'),
      reason: 'product_done',
    );
  }

  final productStatus = _processingStatus(item, 'product');
  final product = _getStr(item, 'productImageUrl');
  if (_isHttpUrl(product)) {
    if (productStatus != 'done') {
      // product queued/running — fall through to cutout/clean.
    } else if (_urlsEqual(product, _getStr(item, 'imageUrl')) ||
        _urlsEqual(product, _getStr(item, 'originalImageUrl'))) {
      // product same as original — fall through.
    }
  }

  final cutout = _getStr(item, 'cutoutImageUrl');
  if (_isHttpUrl(cutout)) {
    return WardrobeImagePick(url: cutout, reason: 'cutout');
  }

  final clean = _getStr(item, 'cleanImageUrl');
  if (_isHttpUrl(clean)) {
    return WardrobeImagePick(url: clean, reason: 'clean');
  }

  final legacy = _getStr(item, 'imageUrl');
  if (_isHttpUrl(legacy)) {
    return WardrobeImagePick(url: legacy, reason: 'imageUrl');
  }

  final original = _getStr(item, 'originalImageUrl');
  if (_isHttpUrl(original)) {
    return WardrobeImagePick(url: original, reason: 'originalImageUrl');
  }

  return const WardrobeImagePick(url: null, reason: 'none');
}

final Set<String> _wardrobeCardImageLogKeys = <String>{};
bool _wardrobeCardImageLoggingEnabled = false;

/// Wardrobe tab only — avoids logging every card while Home is visible (IndexedStack).
void setWardrobeCardImageLoggingEnabled(bool enabled) {
  _wardrobeCardImageLoggingEnabled = enabled;
}

/// Debug: log once per item+pick (cards). Same pick as detail screen.
void debugLogWardrobeCardImage(Map<String, dynamic> item) {
  if (!kDebugMode || !kVerboseHomeLogs || !_wardrobeCardImageLoggingEnabled) {
    return;
  }

  final pick = pickBestWardrobeImageUrl(item);
  final id = (_getStr(item, '__id') ?? _getStr(item, 'id') ?? '').trim();
  final name = (_getStr(item, 'name') ?? 'unknown').trim();
  final logKey = '$id|${pick.url}|${pick.reason}';
  if (_wardrobeCardImageLogKeys.contains(logKey)) return;
  _wardrobeCardImageLogKeys.add(logKey);

  debugPrint(
    '[WARDROBE_CARD_IMAGE] '
    'name=$name '
    'imageUrl=${_getStr(item, 'imageUrl') ?? ''} '
    'cleanImageUrl=${_getStr(item, 'cleanImageUrl') ?? ''} '
    'cutoutImageUrl=${_getStr(item, 'cutoutImageUrl') ?? ''} '
    'productImageUrl=${_getStr(item, 'productImageUrl') ?? ''} '
    'processing.product=${_processingStatus(item, 'product')} '
    'chosenUrl=${pick.url ?? ''} '
    'chosenReason=${pick.reason}',
  );
}

/// Best wardrobe item image for UI (tiles, hero cards, pickers, detail).
String getBestWardrobeImageUrl(Map<String, dynamic> item) {
  return getBestWardrobeImageUrlOrNull(item) ?? '';
}

/// Nullable variant for callers that expect `String?`.
String? getBestWardrobeImageUrlOrNull(Map<String, dynamic> item) {
  return pickBestWardrobeImageUrl(item).url;
}

/// Home outfit canvas — transparent cutout PNGs on dark background (not product-card wells).
///
/// Priority: cutout → product (only if done & distinct) → clean → imageUrl / originalImageUrl.
String? getHomeOutfitImageUrlOrNull(Map<String, dynamic> item) {
  return pickHomeOutfitImageUrl(item).url;
}

WardrobeImagePick pickHomeOutfitImageUrl(Map<String, dynamic> item) {
  final cutout = _getStr(item, 'cutoutImageUrl');
  if (_isHttpUrl(cutout)) {
    return WardrobeImagePick(url: cutout, reason: 'cutout');
  }

  if (canUseProductImageUrl(item)) {
    return WardrobeImagePick(
      url: _getStr(item, 'productImageUrl'),
      reason: 'product_done',
    );
  }

  final clean = _getStr(item, 'cleanImageUrl');
  if (_isHttpUrl(clean)) {
    return WardrobeImagePick(url: clean, reason: 'clean');
  }

  final legacy = _getStr(item, 'imageUrl');
  if (_isHttpUrl(legacy)) {
    return WardrobeImagePick(url: legacy, reason: 'imageUrl');
  }

  final original = _getStr(item, 'originalImageUrl');
  if (_isHttpUrl(original)) {
    return WardrobeImagePick(url: original, reason: 'originalImageUrl');
  }

  return const WardrobeImagePick(url: null, reason: 'none');
}

/// @deprecated Use [getBestWardrobeImageUrlOrNull].
String? resolveWardrobeImageUrl(Map<String, dynamic> item) {
  return getBestWardrobeImageUrlOrNull(item);
}

/// Home hero outfit tiles — prefer transparent cutout over product-card URLs.
String? resolveHeroHomeOutfitImageUrl(Map<String, dynamic> item) {
  return getHomeOutfitImageUrlOrNull(item);
}

/// All candidate URLs in display priority (for image load fallbacks).
List<String> wardrobeImageUrlCandidates(Map<String, dynamic> item) {
  final out = <String>[];
  void add(String? u) {
    if (u == null || !_isHttpUrl(u) || out.contains(u)) return;
    out.add(u);
  }

  if (canUseProductImageUrl(item)) {
    add(_getStr(item, 'productImageUrl'));
  }
  add(_getStr(item, 'cutoutImageUrl'));
  add(_getStr(item, 'cleanImageUrl'));
  add(_getStr(item, 'imageUrl'));
  add(_getStr(item, 'originalImageUrl'));
  add(_getStr(item, 'productLinkSeedImageUrl'));
  return out;
}
