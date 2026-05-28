import '../utils/product_link_url_sanitize.dart';

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
    );
  }

  Map<String, dynamic> toInitialData() => <String, dynamic>{
        'sourceUrl': sourceUrl,
        'name': name,
        if (brand != null && brand!.isNotEmpty) 'brand': brand,
        if (mainGroupKey != null) 'mainGroupKey': mainGroupKey,
        if (categoryKey != null) 'categoryKey': categoryKey,
        if (subCategoryKey != null) 'subCategoryKey': subCategoryKey,
        if (canonicalType != null && canonicalType!.isNotEmpty)
          'canonical_type': canonicalType,
        'colors': colors,
        if (baseColors.isNotEmpty) 'baseColors': baseColors,
        if (colorHex.isNotEmpty) 'colorHex': colorHex,
        'seasons': seasons,
        'styles': styles,
        'patterns': patterns,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
        if (productImageUrl != null && productImageUrl!.isNotEmpty)
          'productImageUrl': productImageUrl,
        if (originalImageUrl != null && originalImageUrl!.isNotEmpty)
          'originalImageUrl': originalImageUrl,
        if (analysisImageUrl != null && analysisImageUrl!.isNotEmpty)
          'analysisImageUrl': analysisImageUrl,
        if (cleanImageUrl != null && cleanImageUrl!.isNotEmpty)
          'cleanImageUrl': cleanImageUrl,
        if (cutoutImageUrl != null && cutoutImageUrl!.isNotEmpty)
          'cutoutImageUrl': cutoutImageUrl,
        if (personDetected) 'personDetected': true,
        '_fromProductLink': true,
        '_linkPartial': partial,
      };
}

class ProductLinkFormOutcome {
  const ProductLinkFormOutcome({
    required this.analysis,
    this.remoteAiUsed = false,
    this.callableNotFound = false,
  });

  final ProductLinkAnalysis analysis;
  final bool remoteAiUsed;
  final bool callableNotFound;
}

Future<ProductLinkAnalysis?> fetchProductLinkSourcePage(String url) async {
  final canonical = canonicalProductLinkUrl(url);
  if (canonical.isEmpty) return null;
  return ProductLinkAnalysis(
    sourceUrl: canonical,
    name: 'Produkt z linku',
    partial: true,
  );
}

Future<ProductLinkFormOutcome> analyzeProductLinkForForm(
  String url, {
  bool skipMetadataFetch = false,
  ProductLinkAnalysis? prefetchedMetadata,
}) async {
  final canonical = canonicalProductLinkUrl(url);
  final analysis = prefetchedMetadata ??
      ProductLinkAnalysis(
        sourceUrl: canonical,
        name: 'Produkt z linku',
        partial: true,
      );
  return ProductLinkFormOutcome(
    analysis: analysis,
    remoteAiUsed: skipMetadataFetch,
    callableNotFound: false,
  );
}
