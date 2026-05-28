import '../Services/product_link_analyzer_service.dart';

bool isValidProductLinkImageUrl(String? url) {
  final u = (url ?? '').trim();
  if (u.isEmpty) return false;
  final uri = Uri.tryParse(u);
  if (uri == null || !uri.hasScheme) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  return uri.host.isNotEmpty;
}

String? resolveProductLinkImageUrl(ProductLinkAnalysis analysis) {
  final candidates = <String?>[
    analysis.productImageUrl,
    analysis.imageUrl,
    analysis.cleanImageUrl,
    analysis.originalImageUrl,
    analysis.analysisImageUrl,
    analysis.cutoutImageUrl,
  ];

  for (final raw in candidates) {
    final u = (raw ?? '').trim();
    if (isValidProductLinkImageUrl(u)) return u;
  }
  return null;
}
