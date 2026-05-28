import '../constants/app_constants.dart';
import '../utils/product_link_url_sanitize.dart';
import 'color_naming_service.dart';
import 'product_link_analyzer_service.dart';

class ProductLinkUrlFallback {
  ProductLinkUrlFallback._();

  static ProductLinkAnalysis detect(String url) {
    final canonical = canonicalProductLinkUrl(url);
    final lower = canonical.toLowerCase();

    String? main;
    String? cat;
    String? sub;
    String name = 'Produkt z linku';
    List<String> seasons = const <String>['celoročne'];

    if (lower.contains('swim') || lower.contains('plavk') || lower.contains('sortky')) {
      main = 'oblecenie';
      cat = 'plavky';
      sub = 'plavecke_sortky';
      name = subCategoryLabels[sub] ?? 'Plavecké šortky';
      seasons = const <String>['leto'];
    } else if (lower.contains('mikina') || lower.contains('hoodie')) {
      main = 'oblecenie';
      cat = 'mikiny';
      sub = 'mikina_klasicka';
      name = subCategoryLabels[sub] ?? 'Mikina';
    } else if (lower.contains('jean') || lower.contains('dzins') || lower.contains('rifle')) {
      main = 'oblecenie';
      cat = 'nohavice_rifle';
      sub = 'rifle';
      name = subCategoryLabels[sub] ?? 'Rifle';
    }

    final colors = ColorNamingService.instance.detectColorsInText(lower);
    return ProductLinkAnalysis(
      sourceUrl: canonical,
      name: name,
      brand: _detectBrand(lower),
      mainGroupKey: main,
      categoryKey: cat,
      subCategoryKey: sub,
      colors: colors,
      baseColors: colors,
      styles: const <String>['casual'],
      patterns: const <String>['jednofarebné'],
      seasons: seasons,
      partial: sub == null,
    );
  }

  static String? _detectBrand(String lower) {
    if (lower.contains('adidas')) return 'Adidas';
    if (lower.contains('nike')) return 'Nike';
    if (lower.contains('puma')) return 'Puma';
    return null;
  }
}

ProductLinkAnalysis detectClothingFromUrlFallback(String url) =>
    ProductLinkUrlFallback.detect(url);

String? extractProductStyleCodeFromUrl(String url) {
  final blob = canonicalProductLinkUrl(url).toUpperCase();
  final patterns = <RegExp>[
    RegExp(r'\b([A-Z]{2}[A-Z0-9]{4}-\d{3})\b'),
    RegExp(r'\b([A-Z]{2,4}\d{4,8}-\d{2,4})\b'),
    RegExp(r'\b([A-Z]{2}\d{4,6})\b'),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(blob);
    if (m != null && m.group(1)!.isNotEmpty) return m.group(1);
  }
  return null;
}
