import 'clothing_analyzer_pipeline.dart';

/// Semantic source for owned-V2 product-link (and photo Add) items:
/// `storagePath` under `wardrobe/{uid}/...`.
///
/// Display lineage (no new schema):
/// - canonical source: `storagePath`
/// - owned original: `imageUrl`
/// - same-source derivatives: `cleanImageUrl` / `cutoutImageUrl` /
///   `productImageUrl` only when they resolve to `wardrobe_clean/{uid}/{basename}`
///   or `wardrobe_product/{uid}/{basename}` matching that source
/// - external product page: `sourceUrl`
/// - remote seed: `productLinkSeedImageUrl` / `originalImageUrl` (lineage only)
const Set<String> kOwnedV2ProtectedIdentityKeys = {
  'canonicalType',
  'canonicalFamily',
  'bodySlots',
  'layerPosition',
  'colorProfile',
  'formality',
  'warmth',
  'colors',
  'baseColors',
  'colorHex',
  'name',
  'wardrobeV2',
};

bool isOwnedV2CanonicalStoragePath(String? storagePath) {
  return ClothingAnalyzerPipeline.isOwnedAnalyzerStoragePath(storagePath);
}

String? ownedV2SourceBasename(String? storagePath) {
  if (!isOwnedV2CanonicalStoragePath(storagePath)) return null;
  final name = storagePath!.trim().split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return name;
  return name.substring(0, dot);
}

bool isOwnedV2SameSourceDerivativePath({
  required String? objectPath,
  required String? storagePath,
}) {
  if (!isOwnedV2CanonicalStoragePath(storagePath)) return false;
  final path = (objectPath ?? '').trim();
  if (path.isEmpty || path.contains('..')) return false;
  final parts = path.split('/');
  if (parts.length < 3) return false;
  final ns = parts[0];
  if (ns != 'wardrobe_clean' && ns != 'wardrobe_product') return false;
  final src = storagePath!.trim().split('/');
  if (parts[1] != src[1]) return false;
  final srcBase = ownedV2SourceBasename(storagePath);
  final derName = parts.last;
  final derDot = derName.lastIndexOf('.');
  final derBase = derDot <= 0 ? derName : derName.substring(0, derDot);
  return srcBase != null && derBase == srcBase;
}

/// True when [url] is the owned original or a rembg/studio derivative of it.
bool isOwnedV2SameSourceDisplayUrl({
  required Map<String, dynamic> item,
  required String? url,
}) {
  final storagePath = (item['storagePath'] ?? '').toString().trim();
  if (!isOwnedV2CanonicalStoragePath(storagePath)) return false;
  final u = (url ?? '').trim();
  if (u.isEmpty) return false;

  final ownedOriginal = (item['imageUrl'] ?? '').toString().trim();
  if (ownedOriginal.isNotEmpty && u == ownedOriginal) return true;

  final objectPath = ClothingAnalyzerPipeline.storagePathFromFirebaseUrl(u);
  if (objectPath != null) {
    if (objectPath == storagePath) return true;
    if (isOwnedV2SameSourceDerivativePath(
      objectPath: objectPath,
      storagePath: storagePath,
    )) {
      return true;
    }
  }

  final cleanUrl = (item['cleanImageUrl'] ?? '').toString().trim();
  final cutoutUrl = (item['cutoutImageUrl'] ?? '').toString().trim();
  final productUrl = (item['productImageUrl'] ?? '').toString().trim();
  final cleanPath = (item['cleanStoragePath'] ?? '').toString().trim();
  final productPath = (item['productStoragePath'] ?? '').toString().trim();

  if (u == cleanUrl || u == cutoutUrl) {
    if (isOwnedV2SameSourceDerivativePath(
      objectPath: cleanPath,
      storagePath: storagePath,
    )) {
      return true;
    }
  }
  if (u == productUrl) {
    if (isOwnedV2SameSourceDerivativePath(
      objectPath: productPath,
      storagePath: storagePath,
    )) {
      return true;
    }
  }
  return false;
}

/// Display-only patches may write image/processing fields, never V2 identity.
bool ownedV2DisplayPatchTouchesIdentity(Map<String, dynamic> patch) {
  return patch.keys.any(kOwnedV2ProtectedIdentityKeys.contains);
}

/// Rembg/cutout failure: keep the owned original as the usable display image.
bool ownedV2KeepsOriginalWhenDerivativeMissing(Map<String, dynamic> item) {
  if (!isOwnedV2CanonicalStoragePath((item['storagePath'] ?? '').toString())) {
    return false;
  }
  final owned = (item['imageUrl'] ?? '').toString().trim();
  return owned.startsWith('http://') || owned.startsWith('https://');
}
