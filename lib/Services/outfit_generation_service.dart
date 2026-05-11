import '../utils/wardrobe_image_url_priority.dart';

/// Slim weather snapshot used to pick outfits.
///
/// This is intentionally simple and UI-agnostic.
class OutfitWeatherSnapshot {
  final int tempC;
  final bool isRainy;
  final bool isWindy;
  final String seasonKey; // jar | let | jese | zim

  const OutfitWeatherSnapshot({
    required this.tempC,
    required this.isRainy,
    required this.isWindy,
    required this.seasonKey,
  });
}

/// Wardrobe outfit parts.
enum OutfitWearType { top, bottom, shoes, outerwear }

/// Result of picking concrete wardrobe items.
class OutfitPreviewItem {
  final OutfitWearType type;
  final Map<String, dynamic> item;
  final String label;
  final String? imageUrl;

  const OutfitPreviewItem({
    required this.type,
    required this.item,
    required this.label,
    required this.imageUrl,
  });
}

class OutfitPreview {
  final OutfitPreviewItem top;
  final OutfitPreviewItem bottom;
  final OutfitPreviewItem shoes;
  final OutfitPreviewItem? outerwear;

  const OutfitPreview({
    required this.top,
    required this.bottom,
    required this.shoes,
    required this.outerwear,
  });

  List<OutfitPreviewItem> get orderedTiles => [
        if (outerwear != null) outerwear!,
        top,
        bottom,
        shoes,
      ];
}

/// Pure outfit selection logic extracted from `HomeScreen`.
class OutfitGenerationService {
  const OutfitGenerationService._();

  static OutfitPreview? generatePreview({
    required List<Map<String, dynamic>> wardrobeItems,
    required OutfitWeatherSnapshot weather,
  }) {
    Map<String, dynamic> normalize(Map<String, dynamic> raw) {
      final m = Map<String, dynamic>.from(raw);
      m['name'] = (m['name'] ?? '').toString();
      m['category'] = (m['categoryKey'] ?? m['category'] ?? '').toString();
      m['subCategory'] =
          (m['subCategoryKey'] ?? m['subCategory'] ?? '').toString();
      m['mainGroup'] =
          (m['mainGroupKey'] ?? m['mainGroup'] ?? '').toString();
      m['colors'] = m['colors'] ?? m['color'] ?? const [];
      m['seasons'] = m['seasons'] ?? m['season'] ?? const [];
      return m;
    }

    bool isCleanCandidate(Map<String, dynamic> raw) {
      final isClean = raw['isClean'];
      if (isClean is bool) return isClean;
      return true; // missing -> treat as ok
    }

    final cleanItems = wardrobeItems
        .where(isCleanCandidate)
        .map((raw) => normalize(raw))
        .toList();

    if (cleanItems.isEmpty) return null;

    bool matchesSeason(Map<String, dynamic> item) {
      final seasonsDyn = item['seasons'];
      final seasons = <String>[
        if (seasonsDyn is List) ...seasonsDyn.map((e) => e.toString()),
        if (seasonsDyn is String && seasonsDyn.trim().isNotEmpty)
          seasonsDyn,
      ]
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();

      if (seasons.isEmpty) return true;
      final target = weather.seasonKey;
      return seasons.any((s) => s.contains('cel') || s.contains(target));
    }

    bool containsAny(String haystack, List<String> needles) {
      final h = haystack.toLowerCase();
      return needles.any((n) => h.contains(n));
    }

    String blob(Map<String, dynamic> it) {
      return [
        (it['name'] ?? '').toString(),
        (it['category'] ?? '').toString(),
        (it['subCategory'] ?? '').toString(),
        (it['mainGroup'] ?? '').toString(),
      ].join(' ').toLowerCase();
    }

    bool isTop(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, [
        'trič',
        'trick',
        't-shirt',
        'top',
        'koše',
        'kosel',
        'blúz',
        'bluz',
        'sveter',
        'shirt',
        'blouse',
      ]);
    }

    bool isBottom(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, [
        'nohav',
        'rifl',
        'džín',
        'dzín',
        'jeans',
        'pants',
        'sukn',
        'skirt',
        'krať',
        'krat',
        'short',
      ]);
    }

    bool isShoes(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, [
        'topán',
        'topan',
        'tenis',
        'sneaker',
        'boots',
        'čiž',
        'ciz',
        'sandál',
        'sandal',
        'obuv',
        'shoes',
      ]);
    }

    bool isOuterwear(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, [
        'bunda',
        'kabát',
        'kabat',
        'mikina',
        'sako',
        'blazer',
        'coat',
        'jacket',
        'hoodie',
      ]);
    }

    bool isHeavyOuterwear(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, ['kabát', 'kabat', 'coat', 'parka', 'čiž', 'ciz']);
    }

    bool isLightOuterwear(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, [
        'mikina',
        'hoodie',
        'sako',
        'blazer',
        'bunda',
        'jacket',
      ]);
    }

    bool isNeutral(Map<String, dynamic> it) {
      final colorsDyn = it['colors'];
      final colors = <String>[
        if (colorsDyn is List) ...colorsDyn.map((e) => e.toString()),
        if (colorsDyn is String && colorsDyn.trim().isNotEmpty) colorsDyn,
      ]
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();

      if (colors.isEmpty) return false;

      return colors.any((c) {
        return c.contains('čier') ||
            c.contains('cier') ||
            c.contains('black') ||
            c.contains('biel') ||
            c.contains('white') ||
            c.contains('siv') ||
            c.contains('gray') ||
            c.contains('grey') ||
            c.contains('béž') ||
            c.contains('bez') ||
            c.contains('beige') ||
            c.contains('navy') ||
            c.contains('tmavomod');
      });
    }

    double baseScore(Map<String, dynamic> it) {
      final b = blob(it);
      var s = 0.0;
      if (isNeutral(it)) s += 2.0;
      if (b.contains('basic')) s += 1.0;
      final brand = (it['brand'] ?? '').toString().trim();
      if (brand.isNotEmpty) s += 0.2;
      return s;
    }

    Map<String, dynamic>? pickBest(
      List<Map<String, dynamic>> candidates,
      double Function(Map<String, dynamic>) score,
    ) {
      if (candidates.isEmpty) return null;
      Map<String, dynamic>? best;
      var bestScore = -1e9;
      for (final c in candidates) {
        final s = score(c);
        if (s > bestScore) {
          bestScore = s;
          best = c;
        }
      }
      return best;
    }

    final seasonal = cleanItems.where(matchesSeason).toList();
    final pool = seasonal.isNotEmpty ? seasonal : cleanItems;

    final tops = pool.where(isTop).toList();
    final bottoms = pool.where(isBottom).toList();
    final shoes = pool.where(isShoes).toList();
    final outerwear = pool.where(isOuterwear).toList();

    if (tops.isEmpty || bottoms.isEmpty || shoes.isEmpty) return null;

    final temp = weather.tempC;
    final isWarm = temp >= 20;
    final isMild = temp >= 10 && temp < 20;
    final isCold = temp < 10;
    final needsOuterwear = isCold || weather.isRainy;

    final topItem = pickBest(tops, baseScore);
    final bottomItem = pickBest(bottoms, (it) {
      final b = blob(it);
      var s = baseScore(it);
      if (isWarm && (b.contains('krať') || b.contains('short'))) s += 1.0;
      return s;
    });
    final shoesItem = pickBest(shoes, (it) {
      final b = blob(it);
      var s = baseScore(it);
      if (weather.isRainy &&
          (b.contains('čiž') || b.contains('ciz') || b.contains('boots'))) {
        s += 1.0;
      }
      if (isWarm && (b.contains('sandál') || b.contains('sandal'))) s += 1.0;
      return s;
    });

    Map<String, dynamic>? outerItem;
    if (!isWarm && outerwear.isNotEmpty && (needsOuterwear || isMild)) {
      outerItem = pickBest(outerwear, (it) {
        final b = blob(it);
        var s = baseScore(it);
        if (isCold && isHeavyOuterwear(it)) s += 1.2;
        if (isMild && isLightOuterwear(it)) s += 1.0;
        if (weather.isRainy && b.contains('bunda')) s += 0.4;
        return s;
      });
    }

    if (topItem == null || bottomItem == null || shoesItem == null) return null;

    String labelFor(Map<String, dynamic> it, {required String fallback}) {
      final name = (it['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
      final sub = (it['subCategory'] ?? '').toString().trim();
      if (sub.isNotEmpty) return sub;
      final cat = (it['category'] ?? '').toString().trim();
      if (cat.isNotEmpty) return cat;
      return fallback;
    }

    OutfitPreviewItem toPreviewItem({
      required OutfitWearType type,
      required Map<String, dynamic> item,
      required String fallbackLabel,
    }) {
      final resolvedImageUrl = resolveWardrobeImageUrl(item);
      return OutfitPreviewItem(
        type: type,
        item: item,
        label: labelFor(item, fallback: fallbackLabel),
        imageUrl: resolvedImageUrl?.trim().isNotEmpty == true
            ? resolvedImageUrl
            : null,
      );
    }

    return OutfitPreview(
      top: toPreviewItem(
        type: OutfitWearType.top,
        item: topItem,
        fallbackLabel: 'Vrchný diel',
      ),
      bottom: toPreviewItem(
        type: OutfitWearType.bottom,
        item: bottomItem,
        fallbackLabel: 'Spodný diel',
      ),
      shoes: toPreviewItem(
        type: OutfitWearType.shoes,
        item: shoesItem,
        fallbackLabel: 'Obuv',
      ),
      outerwear: outerItem == null
          ? null
          : toPreviewItem(
              type: OutfitWearType.outerwear,
              item: outerItem,
              fallbackLabel: 'Vrstva',
            ),
    );
  }
}

