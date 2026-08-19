import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../utils/product_link_image_resolve.dart';
import '../utils/product_link_url_sanitize.dart';

/// Live product-link PL-1 calls this callable **only** in source-page mode.
const String kProductLinkSourcePageCallableName = 'analyzeClothingProductUrl';
const String kProductLinkSourcePageCallableRegion = 'us-east1';
const Duration kProductLinkSourcePageTimeout = Duration(seconds: 60);

const String kProductLinkGenericName = 'Produkt z linku';

/// Page brand wins over analyzer brand when already filled.
String preferProductLinkBrand({
  required String existingBrand,
  required String analyzerBrand,
}) {
  final existing = existingBrand.trim();
  if (existing.isNotEmpty) return existing;
  return analyzerBrand.trim();
}

/// Backend / legacy identity keys that PL-1 must never treat as wardrobe identity.
const Set<String> kProductLinkIgnoredIdentityKeys = {
  'canonical_type',
  'canonicalType',
  'mainGroupKey',
  'mainGroup',
  'categoryKey',
  'category',
  'subCategoryKey',
  'subCategory',
  'colors',
  'baseColors',
  'colorHex',
  'colorProfile',
  'seasons',
  'styles',
  'patterns',
  'warmth',
  'warmth_level',
  'formality',
  'layer_role',
  'layerPosition',
  'bodySlots',
  'canonicalFamily',
  'wardrobeV2',
  'personDetected',
};

typedef ProductLinkSourcePageTransport =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

/// Strict metadata-only request. Extra flags that could reach the OpenAI
/// identity branch are intentionally omitted.
Map<String, dynamic> buildProductLinkSourcePageRequest(String canonicalUrl) {
  return <String, dynamic>{
    'url': canonicalUrl,
    'sourcePageOnly': true,
  };
}

void assertProductLinkSourcePageOnlyRequest(Map<String, dynamic> payload) {
  if (payload['sourcePageOnly'] != true) {
    throw StateError('product_link_source_page_only_required');
  }
  if (payload.containsKey('imageCleanupOnly') ||
      payload.containsKey('metadataOnly')) {
    throw StateError('product_link_identity_flags_forbidden');
  }
}

String? _nonEmptyString(dynamic value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

String _pageTitleFromSourcePage(Map<String, dynamic> data) {
  final name = _nonEmptyString(data['name']);
  if (name != null) return name;
  return kProductLinkGenericName;
}

String? _seedImageFromSourcePage(Map<String, dynamic> data) {
  for (final key in <String>[
    'productImageUrl',
    'imageUrl',
    'originalImageUrl',
  ]) {
    final url = _nonEmptyString(data[key]);
    if (isValidProductLinkImageUrl(url)) return url;
  }
  return null;
}

/// Maps callable JSON to enrichment-only [ProductLinkAnalysis].
///
/// Ignores legacy V1 / OpenAI identity fields even if the backend still
/// returns them from the shared callable.
ProductLinkAnalysis mapProductLinkSourcePageResponse(
  Map<String, dynamic> data, {
  required String fallbackSourceUrl,
}) {
  final sourceUrl =
      _nonEmptyString(data['sourceUrl']) ??
      canonicalProductLinkUrl(fallbackSourceUrl);
  final name = _pageTitleFromSourcePage(data);
  final brand = _nonEmptyString(data['brand']);
  final seed = _seedImageFromSourcePage(data);
  final hasTitle = name != kProductLinkGenericName;
  final partial = seed == null || (!hasTitle && brand == null);

  return ProductLinkAnalysis(
    sourceUrl: sourceUrl,
    name: name,
    brand: brand,
    imageUrl: seed,
    productImageUrl: seed,
    originalImageUrl: seed,
    partial: partial,
    sourcePageOnly: true,
    missingImage: seed == null,
  );
}

enum ProductLinkSourcePageError { invalidUrl, callableNotFound, fetchFailed }

class ProductLinkSourcePageException implements Exception {
  const ProductLinkSourcePageException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final ProductLinkSourcePageError kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'ProductLinkSourcePageException($kind: $message)';
}

class ProductLinkAnalysis {
  const ProductLinkAnalysis({
    required this.sourceUrl,
    required this.name,
    this.brand,
    this.mainGroupKey,
    this.categoryKey,
    this.subCategoryKey,
    this.canonicalType,
    this.colors = const <String>[],
    this.baseColors = const <String>[],
    this.colorHex = const <String>[],
    this.seasons = const <String>[],
    this.styles = const <String>[],
    this.patterns = const <String>[],
    this.imageUrl,
    this.productImageUrl,
    this.originalImageUrl,
    this.analysisImageUrl,
    this.cleanImageUrl,
    this.cutoutImageUrl,
    this.personDetected = false,
    this.partial = false,
    this.sourcePageOnly = false,
    this.missingImage = false,
  });

  final String sourceUrl;
  final String name;
  final String? brand;
  final String? mainGroupKey;
  final String? categoryKey;
  final String? subCategoryKey;
  final String? canonicalType;
  final List<String> colors;
  final List<String> baseColors;
  final List<String> colorHex;
  final List<String> seasons;
  final List<String> styles;
  final List<String> patterns;
  final String? imageUrl;
  final String? productImageUrl;
  final String? originalImageUrl;
  final String? analysisImageUrl;
  final String? cleanImageUrl;
  final String? cutoutImageUrl;
  final bool personDetected;
  final bool partial;
  final bool sourcePageOnly;
  final bool missingImage;

  ProductLinkAnalysis copyWith({
    String? sourceUrl,
    String? name,
    String? brand,
    String? mainGroupKey,
    String? categoryKey,
    String? subCategoryKey,
    String? canonicalType,
    List<String>? colors,
    List<String>? baseColors,
    List<String>? colorHex,
    List<String>? seasons,
    List<String>? styles,
    List<String>? patterns,
    String? imageUrl,
    String? productImageUrl,
    String? originalImageUrl,
    String? analysisImageUrl,
    String? cleanImageUrl,
    String? cutoutImageUrl,
    bool? personDetected,
    bool? partial,
    bool? sourcePageOnly,
    bool? missingImage,
  }) {
    return ProductLinkAnalysis(
      sourceUrl: sourceUrl ?? this.sourceUrl,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      mainGroupKey: mainGroupKey ?? this.mainGroupKey,
      categoryKey: categoryKey ?? this.categoryKey,
      subCategoryKey: subCategoryKey ?? this.subCategoryKey,
      canonicalType: canonicalType ?? this.canonicalType,
      colors: colors ?? this.colors,
      baseColors: baseColors ?? this.baseColors,
      colorHex: colorHex ?? this.colorHex,
      seasons: seasons ?? this.seasons,
      styles: styles ?? this.styles,
      patterns: patterns ?? this.patterns,
      imageUrl: imageUrl ?? this.imageUrl,
      productImageUrl: productImageUrl ?? this.productImageUrl,
      originalImageUrl: originalImageUrl ?? this.originalImageUrl,
      analysisImageUrl: analysisImageUrl ?? this.analysisImageUrl,
      cleanImageUrl: cleanImageUrl ?? this.cleanImageUrl,
      cutoutImageUrl: cutoutImageUrl ?? this.cutoutImageUrl,
      personDetected: personDetected ?? this.personDetected,
      partial: partial ?? this.partial,
      sourcePageOnly: sourcePageOnly ?? this.sourcePageOnly,
      missingImage: missingImage ?? this.missingImage,
    );
  }

  /// Form prefill for PL-1. Emits enrichment only — never identity / V2.
  Map<String, dynamic> toInitialData() => <String, dynamic>{
        'sourceUrl': sourceUrl,
        'name': name,
        if (brand != null && brand!.isNotEmpty) 'brand': brand,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
        if (productImageUrl != null && productImageUrl!.isNotEmpty)
          'productImageUrl': productImageUrl,
        if (originalImageUrl != null && originalImageUrl!.isNotEmpty)
          'originalImageUrl': originalImageUrl,
        '_fromProductLink': true,
        '_linkPartial': partial,
        '_sourcePageOnly': sourcePageOnly,
        if (missingImage) '_linkMissingImage': true,
      };
}

class ProductLinkFormOutcome {
  const ProductLinkFormOutcome({
    required this.analysis,
    this.remoteAiUsed = false,
    this.callableNotFound = false,
    this.fetchFailed = false,
    this.sourcePageOnly = true,
  });

  final ProductLinkAnalysis analysis;
  final bool remoteAiUsed;
  final bool callableNotFound;
  final bool fetchFailed;
  final bool sourcePageOnly;
}

class ProductLinkAnalyzerService {
  ProductLinkAnalyzerService({
    ProductLinkSourcePageTransport? transport,
    FirebaseFunctions? functions,
  }) : _transport = transport,
       _functions = functions;

  static ProductLinkAnalyzerService instance = ProductLinkAnalyzerService();

  final ProductLinkSourcePageTransport? _transport;
  final FirebaseFunctions? _functions;

  Future<ProductLinkAnalysis?> fetchSourcePage(String url) async {
    final canonical = canonicalProductLinkUrl(url);
    if (canonical.isEmpty) return null;
    return _callSourcePage(canonical);
  }

  Future<ProductLinkFormOutcome> analyzeForForm(
    String url, {
    bool skipMetadataFetch = false,
    ProductLinkAnalysis? prefetchedMetadata,
  }) async {
    final canonical = canonicalProductLinkUrl(url);
    if (canonical.isEmpty) {
      return ProductLinkFormOutcome(
        analysis: const ProductLinkAnalysis(
          sourceUrl: '',
          name: kProductLinkGenericName,
          partial: true,
          sourcePageOnly: true,
          missingImage: true,
        ),
        fetchFailed: true,
        sourcePageOnly: true,
      );
    }

    try {
      final analysis =
          (skipMetadataFetch ? prefetchedMetadata : null) ??
          await _callSourcePage(canonical);
      return ProductLinkFormOutcome(
        analysis: analysis,
        remoteAiUsed: false,
        callableNotFound: false,
        fetchFailed: false,
        sourcePageOnly: true,
      );
    } on ProductLinkSourcePageException catch (e) {
      final empty = ProductLinkAnalysis(
        sourceUrl: canonical,
        name: kProductLinkGenericName,
        partial: true,
        sourcePageOnly: true,
        missingImage: true,
      );
      return ProductLinkFormOutcome(
        analysis: empty,
        remoteAiUsed: false,
        callableNotFound: e.kind == ProductLinkSourcePageError.callableNotFound,
        fetchFailed: true,
        sourcePageOnly: true,
      );
    }
  }

  Future<ProductLinkAnalysis> _callSourcePage(String canonicalUrl) async {
    final payload = buildProductLinkSourcePageRequest(canonicalUrl);
    assertProductLinkSourcePageOnlyRequest(payload);

    try {
      final data = await _invoke(payload);
      return mapProductLinkSourcePageResponse(
        data,
        fallbackSourceUrl: canonicalUrl,
      );
    } on ProductLinkSourcePageException {
      rethrow;
    } on FirebaseFunctionsException catch (e) {
      throw ProductLinkSourcePageException(
        kind: _kindForCallableCode(e.code),
        message: e.message ?? e.code,
        cause: e,
      );
    } catch (e) {
      throw ProductLinkSourcePageException(
        kind: ProductLinkSourcePageError.fetchFailed,
        message: e.toString(),
        cause: e,
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> payload) async {
    final transport = _transport;
    if (transport != null) {
      return transport(payload);
    }
    final functions =
        _functions ??
        FirebaseFunctions.instanceFor(
          region: kProductLinkSourcePageCallableRegion,
        );
    final callable = functions.httpsCallable(
      kProductLinkSourcePageCallableName,
      options: HttpsCallableOptions(timeout: kProductLinkSourcePageTimeout),
    );
    final result = await callable.call<dynamic>(payload);
    final raw = result.data;
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    throw const ProductLinkSourcePageException(
      kind: ProductLinkSourcePageError.fetchFailed,
      message: 'invalid_source_page_response',
    );
  }

  static ProductLinkSourcePageError _kindForCallableCode(String code) {
    switch (code) {
      case 'not-found':
      case 'unimplemented':
        return ProductLinkSourcePageError.callableNotFound;
      case 'invalid-argument':
        return ProductLinkSourcePageError.invalidUrl;
      default:
        return ProductLinkSourcePageError.fetchFailed;
    }
  }
}

ProductLinkAnalyzerService? _debugOverride;

@visibleForTesting
void debugOverrideProductLinkAnalyzerService(ProductLinkAnalyzerService? value) {
  _debugOverride = value;
}

ProductLinkAnalyzerService get productLinkAnalyzerService =>
    _debugOverride ?? ProductLinkAnalyzerService.instance;

Future<ProductLinkAnalysis?> fetchProductLinkSourcePage(String url) {
  return productLinkAnalyzerService.fetchSourcePage(url);
}

Future<ProductLinkFormOutcome> analyzeProductLinkForForm(
  String url, {
  bool skipMetadataFetch = false,
  ProductLinkAnalysis? prefetchedMetadata,
}) {
  return productLinkAnalyzerService.analyzeForForm(
    url,
    skipMetadataFetch: skipMetadataFetch,
    prefetchedMetadata: prefetchedMetadata,
  );
}
