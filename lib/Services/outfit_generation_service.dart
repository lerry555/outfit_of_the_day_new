import 'package:flutter/foundation.dart';

import '../utils/candidate_generation_audit.dart';
import '../utils/home_debug_logging.dart';
import '../utils/kept_selection_audit.dart';
import '../utils/outer_variant_selection.dart';
import '../utils/outerwear_policy.dart';
import '../utils/stylist_layer_filter.dart';
import '../utils/wardrobe_image_url_priority.dart';

/// Optional predicate over a generated [OutfitPreview] (avoids circular imports).
typedef OutfitPreviewPredicate = bool Function(OutfitPreview preview);

/// Optional bonus scorer over a generated [OutfitPreview].
typedef OutfitPreviewBonusScorer = double Function(OutfitPreview preview);

/// EOW reader for outer-matrix audit logs (avoids circular imports).
typedef OutfitPreviewEowReader = double Function(OutfitPreview preview);

/// Slim weather snapshot used to pick outfits.
///
/// This is intentionally simple and UI-agnostic.
class OutfitWeatherSnapshot {
  final int tempC;
  final bool isRainy;
  final bool isWindy;
  final String seasonKey; // jar | let | jese | zim
  /// Optional: light | moderate | heavy | strong
  final String? rainIntensity;

  const OutfitWeatherSnapshot({
    required this.tempC,
    required this.isRainy,
    required this.isWindy,
    required this.seasonKey,
    this.rainIntensity,
  });

  bool get isHeavyRain {
    final r = (rainIntensity ?? '').trim().toLowerCase();
    return r == 'heavy' || r == 'strong' || r == 'intense';
  }
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

/// Wardrobe pools used by [OutfitGenerationService.generatePreview] (audit / introspection).
class OutfitGenerationPools {
  const OutfitGenerationPools({
    required this.tops,
    required this.bottoms,
    required this.shoes,
    required this.outerwear,
    required this.midLayers,
    required this.layerFilteredPool,
  });

  final List<Map<String, dynamic>> tops;
  final List<Map<String, dynamic>> bottoms;
  final List<Map<String, dynamic>> shoes;
  final List<Map<String, dynamic>> outerwear;
  final List<Map<String, dynamic>> midLayers;
  final List<Map<String, dynamic>> layerFilteredPool;
}

/// Pure outfit selection logic extracted from `HomeScreen`.
class OutfitGenerationService {
  const OutfitGenerationService._();

  /// Firestore document id merged into wardrobe maps as `id`.
  static String wardrobeItemId(Map<String, dynamic> raw) {
    final v = raw['id'] ?? raw['documentId'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? '' : s;
  }

  static String combinationSignature(
    Map<String, dynamic> top,
    Map<String, dynamic> bottom,
    Map<String, dynamic> shoes,
    Map<String, dynamic>? outer,
  ) {
    final parts = <String>[
      wardrobeItemId(top),
      wardrobeItemId(bottom),
      wardrobeItemId(shoes),
      if (outer != null) wardrobeItemId(outer),
    ].where((e) => e.isNotEmpty).toList()
      ..sort();
    return parts.join('|');
  }

  static int overlapCount(Set<String> previousIds, List<Map<String, dynamic>> picks) {
    if (previousIds.isEmpty) return 0;
    var n = 0;
    for (final m in picks) {
      final id = wardrobeItemId(m);
      if (id.isNotEmpty && previousIds.contains(id)) n++;
    }
    return n;
  }

  static OutfitGenerationPools? collectGenerationPools({
    required List<Map<String, dynamic>> wardrobeItems,
    required OutfitWeatherSnapshot weather,
    Set<String> excludedItemIds = const {},
    Set<String> allowedShoeItemIds = const {},
    Set<String> allowedBottomItemIds = const {},
  }) {
    final preview = _generatePreviewInternal(
      wardrobeItems: wardrobeItems,
      weather: weather,
      excludedItemIds: excludedItemIds,
      rejectedCombinationSignatures: const {},
      previousItemIds: const {},
      forceDifferentOutfit: false,
      allowedShoeItemIds: allowedShoeItemIds,
      allowedBottomItemIds: allowedBottomItemIds,
      auditPoolsOnly: true,
    );
    return preview.pools;
  }

  static OutfitPreview? generatePreview({
    required List<Map<String, dynamic>> wardrobeItems,
    required OutfitWeatherSnapshot weather,
    Set<String> excludedItemIds = const {},
    Set<String> rejectedCombinationSignatures = const {},
    Set<String> previousItemIds = const {},
    bool forceDifferentOutfit = false,
    Set<String> allowedShoeItemIds = const {},
    Set<String> allowedBottomItemIds = const {},
    bool auditCandidateGeneration = false,
    int auditPassIndex = 0,
    String auditPassLabel = 'generatePreview',
    int? auditCandidateIndex,
    bool preferredBottomExists = false,
    bool preferredFootwearExists = false,
    OutfitPreviewPredicate? isPreferredBottom,
    OutfitPreviewPredicate? isPreferredFootwear,
    OutfitPreviewPredicate? isDiscouragedBottom,
    OutfitPreviewPredicate? isDiscouragedFootwear,
    OutfitPreviewPredicate? passesLayerHarmony,
    OutfitPreviewBonusScorer? comfortBonusScorer,
    OutfitPreviewPredicate? preferNoOuterWhenComfortable,
    void Function(int candidateIndex, OutfitPreview preview)?
        logOptionalOuterCandidate,
    OutfitPreviewEowReader? outerMatrixEowReader,
    double? outerMatrixCt,
    OuterVariantComfortBands? outerVariantComfortBands,
  }) {
    return _generatePreviewInternal(
      wardrobeItems: wardrobeItems,
      weather: weather,
      excludedItemIds: excludedItemIds,
      rejectedCombinationSignatures: rejectedCombinationSignatures,
      previousItemIds: previousItemIds,
      forceDifferentOutfit: forceDifferentOutfit,
      allowedShoeItemIds: allowedShoeItemIds,
      allowedBottomItemIds: allowedBottomItemIds,
      auditCandidateGeneration: auditCandidateGeneration,
      auditPassIndex: auditPassIndex,
      auditPassLabel: auditPassLabel,
      auditCandidateIndex: auditCandidateIndex,
      preferredBottomExists: preferredBottomExists,
      preferredFootwearExists: preferredFootwearExists,
      isPreferredBottom: isPreferredBottom,
      isPreferredFootwear: isPreferredFootwear,
      isDiscouragedBottom: isDiscouragedBottom,
      isDiscouragedFootwear: isDiscouragedFootwear,
      passesLayerHarmony: passesLayerHarmony,
      comfortBonusScorer: comfortBonusScorer,
      preferNoOuterWhenComfortable: preferNoOuterWhenComfortable,
      logOptionalOuterCandidate: logOptionalOuterCandidate,
      outerMatrixEowReader: outerMatrixEowReader,
      outerMatrixCt: outerMatrixCt,
      outerVariantComfortBands: outerVariantComfortBands,
      candidateLimit: 1,
      multiCandidate: false,
    ).preview;
  }

  static List<OutfitPreview> generateCandidatePreviews({
    required List<Map<String, dynamic>> wardrobeItems,
    required OutfitWeatherSnapshot weather,
    Set<String> excludedItemIds = const {},
    Set<String> rejectedCombinationSignatures = const {},
    Set<String> previousItemIds = const {},
    bool forceDifferentOutfit = false,
    int limit = 4,
    bool preferredBottomExists = false,
    bool preferredFootwearExists = false,
    OutfitPreviewPredicate? isPreferredBottom,
    OutfitPreviewPredicate? isPreferredFootwear,
    OutfitPreviewPredicate? isDiscouragedBottom,
    OutfitPreviewPredicate? isDiscouragedFootwear,
    OutfitPreviewPredicate? passesLayerHarmony,
    OutfitPreviewBonusScorer? comfortBonusScorer,
    OutfitPreviewPredicate? preferNoOuterWhenComfortable,
    void Function(int candidateIndex, OutfitPreview preview)?
        logOptionalOuterCandidate,
    OutfitPreviewEowReader? outerMatrixEowReader,
    double? outerMatrixCt,
    OuterVariantComfortBands? outerVariantComfortBands,
    bool auditCandidateGeneration = false,
    int auditPassIndex = 0,
    String auditPassLabel = 'candidate_matrix',
  }) {
    return _generatePreviewInternal(
      wardrobeItems: wardrobeItems,
      weather: weather,
      excludedItemIds: excludedItemIds,
      rejectedCombinationSignatures: rejectedCombinationSignatures,
      previousItemIds: previousItemIds,
      forceDifferentOutfit: forceDifferentOutfit,
      auditCandidateGeneration: auditCandidateGeneration,
      auditPassIndex: auditPassIndex,
      auditPassLabel: auditPassLabel,
      preferredBottomExists: preferredBottomExists,
      preferredFootwearExists: preferredFootwearExists,
      isPreferredBottom: isPreferredBottom,
      isPreferredFootwear: isPreferredFootwear,
      isDiscouragedBottom: isDiscouragedBottom,
      isDiscouragedFootwear: isDiscouragedFootwear,
      passesLayerHarmony: passesLayerHarmony,
      comfortBonusScorer: comfortBonusScorer,
      preferNoOuterWhenComfortable: preferNoOuterWhenComfortable,
      logOptionalOuterCandidate: logOptionalOuterCandidate,
      outerMatrixEowReader: outerMatrixEowReader,
      outerMatrixCt: outerMatrixCt,
      outerVariantComfortBands: outerVariantComfortBands,
      candidateLimit: limit,
      multiCandidate: true,
    ).previews;
  }

  static ({
    OutfitPreview? preview,
    List<OutfitPreview> previews,
    OutfitGenerationPools? pools,
  }) _generatePreviewInternal({
    required List<Map<String, dynamic>> wardrobeItems,
    required OutfitWeatherSnapshot weather,
    Set<String> excludedItemIds = const {},
    Set<String> rejectedCombinationSignatures = const {},
    Set<String> previousItemIds = const {},
    bool forceDifferentOutfit = false,
    Set<String> allowedShoeItemIds = const {},
    Set<String> allowedBottomItemIds = const {},
    bool auditCandidateGeneration = false,
    int auditPassIndex = 0,
    String auditPassLabel = 'generatePreview',
    int? auditCandidateIndex,
    bool auditPoolsOnly = false,
    bool preferredBottomExists = false,
    bool preferredFootwearExists = false,
    OutfitPreviewPredicate? isPreferredBottom,
    OutfitPreviewPredicate? isPreferredFootwear,
    OutfitPreviewPredicate? isDiscouragedBottom,
    OutfitPreviewPredicate? isDiscouragedFootwear,
    OutfitPreviewPredicate? passesLayerHarmony,
    OutfitPreviewBonusScorer? comfortBonusScorer,
    OutfitPreviewPredicate? preferNoOuterWhenComfortable,
    void Function(int candidateIndex, OutfitPreview preview)?
        logOptionalOuterCandidate,
    OutfitPreviewEowReader? outerMatrixEowReader,
    double? outerMatrixCt,
    OuterVariantComfortBands? outerVariantComfortBands,
    int candidateLimit = 1,
    bool multiCandidate = false,
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

    if (cleanItems.isEmpty) {
      return (preview: null, previews: const [], pools: null);
    }

    final stylistWeather = StylistWeatherContext(
      tempC: weather.tempC,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
      seasonKey: weather.seasonKey,
    );

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
      if (StylistLayerFilter.isTankTopItem(it)) return true;
      final b = blob(it);
      return containsAny(b, [
        'trič',
        'trick',
        't-shirt',
        'tielko',
        'tank',
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
      final baseDyn = it['baseColors'];
      final baseColors = <String>[
        if (baseDyn is List) ...baseDyn.map((e) => e.toString()),
        if (baseDyn is String && baseDyn.trim().isNotEmpty) baseDyn,
      ]
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();

      final colorsDyn = it['colors'];
      final colors = <String>[
        if (colorsDyn is List) ...colorsDyn.map((e) => e.toString()),
        if (colorsDyn is String && colorsDyn.trim().isNotEmpty) colorsDyn,
      ]
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();

      final check = baseColors.isNotEmpty ? baseColors : colors;
      if (check.isEmpty) return false;

      return check.any((c) {
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

    List<Map<String, dynamic>> rankPool(
      List<Map<String, dynamic>> candidates,
      double Function(Map<String, dynamic>) scoreFn,
    ) {
      if (candidates.isEmpty) return const [];
      final ranked = candidates.map((c) => (c, scoreFn(c))).toList()
        ..sort((a, b) {
          final cmp = b.$2.compareTo(a.$2);
          if (cmp != 0) return cmp;
          return wardrobeItemId(a.$1).compareTo(wardrobeItemId(b.$1));
        });
      return ranked.map((e) => e.$1).toList();
    }

    List<Map<String, dynamic>> filterExcluded(
      List<Map<String, dynamic>> pool,
      String slotLabel,
    ) {
      if (excludedItemIds.isEmpty) return pool;
      final filtered = pool.where((it) {
        final id = wardrobeItemId(it);
        return id.isEmpty || !excludedItemIds.contains(id);
      }).toList();
      if (filtered.isEmpty) {
        debugPrint(
          '[OUTFIT_GEN] excluded fallback slot=$slotLabel pool=${pool.length} '
          '(žiadna alternatíva mimo excluded)',
        );
        return pool;
      }
      return filtered;
    }

    final layerFiltered = cleanItems
        .where(
          (it) => StylistLayerFilter.isItemUsableForWeather(
            it,
            stylistWeather,
            log: kDebugMode && kVerboseHomeLogs,
          ),
        )
        .toList();
    final pool = layerFiltered.isNotEmpty ? layerFiltered : cleanItems;

    var tops = pool.where(isTop).toList();
    var bottoms = pool.where(isBottom).toList();
    if (allowedBottomItemIds.isNotEmpty) {
      final restrictedBottoms = bottoms
          .where((it) {
            final id = wardrobeItemId(it);
            return id.isNotEmpty && allowedBottomItemIds.contains(id);
          })
          .toList();
      if (restrictedBottoms.isNotEmpty) {
        bottoms = restrictedBottoms;
      }
    }
    var shoes = pool.where(isShoes).toList();
    if (allowedShoeItemIds.isNotEmpty) {
      final restricted = shoes
          .where((it) {
            final id = wardrobeItemId(it);
            return id.isNotEmpty && allowedShoeItemIds.contains(id);
          })
          .toList();
      if (restricted.isNotEmpty) {
        shoes = restricted;
      }
    }
    final outerwear = pool.where(isOuterwear).toList();

    if (tops.isEmpty || bottoms.isEmpty || shoes.isEmpty) {
      return (preview: null, previews: const [], pools: null);
    }

    final temp = weather.tempC;
    final isWarm = temp >= 20;
    final isMild = temp >= 10 && temp < 20;
    final isCold = temp < 10;
    final isFreezing = stylistWeather.isFreezing;

    String seasonsLabel(Map<String, dynamic> it) {
      final raw = it['seasons'] ?? it['season'];
      if (raw is List) {
        return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).join(',');
      }
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      return '';
    }

    String canonicalLabel(Map<String, dynamic> it) {
      return (it['canonical_type'] ?? it['canonicalType'] ?? '').toString().trim();
    }

    String labelFor(Map<String, dynamic> it, {required String fallback}) {
      final name = (it['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
      final sub = (it['subCategory'] ?? '').toString().trim();
      if (sub.isNotEmpty) return sub;
      final cat = (it['category'] ?? '').toString().trim();
      if (cat.isNotEmpty) return cat;
      return fallback;
    }

    List<Map<String, dynamic>> applyTankTopRulesForTops(
      List<Map<String, dynamic>> candidates,
    ) {
      final nonTanks = candidates
          .where((it) => !StylistLayerFilter.isTankTopItem(it))
          .toList();

      for (final it in candidates) {
        if (!StylistLayerFilter.isTankTopItem(it)) continue;
        if (temp < 18 && !StylistLayerFilter.isSportOrBeachOccasionItem(it)) {
          debugPrint(
            '[TANK_TOP_REJECTED] '
            'item=${labelFor(it, fallback: 'top')} '
            'reason=too_cold_for_tank_top '
            'temp=$temp',
          );
        }
      }

      if (temp < 18) {
        final sportTanks = candidates.where((it) {
          if (!StylistLayerFilter.isTankTopItem(it)) return true;
          return StylistLayerFilter.isSportOrBeachOccasionItem(it);
        }).toList();
        if (nonTanks.isNotEmpty) return nonTanks;
        if (sportTanks.isNotEmpty) return sportTanks;
        return candidates;
      }

      if (temp < 24 && nonTanks.isNotEmpty) {
        return nonTanks;
      }

      return candidates;
    }

    tops = applyTankTopRulesForTops(tops);
    if (tops.isEmpty) {
      return (preview: null, previews: const [], pools: null);
    }

    final midLayers = midLayersFromPool(pool);
    final poolsSnapshot = OutfitGenerationPools(
      tops: tops,
      bottoms: bottoms,
      shoes: shoes,
      outerwear: outerwear,
      midLayers: midLayers,
      layerFilteredPool: pool,
    );

    final auditEnabled =
        !auditPoolsOnly && (auditCandidateGeneration || kCandidateGenerationAudit);

    if (auditPoolsOnly) {
      return (preview: null, previews: const [], pools: poolsSnapshot);
    }

    List<String> seasonTokens(Map<String, dynamic> it) {
      final raw = it['seasons'] ?? it['season'];
      if (raw is List) {
        return raw
            .map((e) => e.toString().trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (raw is String && raw.trim().isNotEmpty) {
        return [raw.trim().toLowerCase()];
      }
      return const [];
    }

    bool seasonMentionsWinter(List<String> tokens) {
      return tokens.any(
        (t) =>
            t.contains('zim') ||
            t.contains('winter') ||
            t == 'zim' ||
            t == 'zima',
      );
    }

    bool seasonMentionsSummer(List<String> tokens) {
      return tokens.any(
        (t) =>
            t.contains('let') ||
            t.contains('summer') ||
            t == 'leto' ||
            t == 'let',
      );
    }

    bool isBootFootwear(String b, String canonical) {
      final c = canonical.toLowerCase();
      return b.contains('čiž') ||
          b.contains('ciz') ||
          b.contains('boot') ||
          c.contains('boot');
    }

    bool isSneakerFootwear(String b, String canonical) {
      final c = canonical.toLowerCase();
      return b.contains('tenis') ||
          b.contains('sneaker') ||
          c.contains('sneaker') ||
          c == 'sneakers';
    }

    bool isWhiteOrLightFootwear(Map<String, dynamic> it, String b) {
      final colorSources = <String>[
        if (it['colors'] is List)
          ...(it['colors'] as List).map((e) => e.toString()),
        if (it['colors'] is String) it['colors'].toString(),
        if (it['baseColors'] is List)
          ...(it['baseColors'] as List).map((e) => e.toString()),
        if (it['baseColors'] is String) it['baseColors'].toString(),
        b,
      ];
      for (final raw in colorSources) {
        final c = raw.trim().toLowerCase();
        if (c.isEmpty) continue;
        if (c.contains('biel') ||
            c.contains('white') ||
            c.contains('svetl') ||
            c.contains('cream') ||
            c.contains('ivory') ||
            c.contains('krém') ||
            c.contains('krem')) {
          return true;
        }
      }
      return false;
    }

    /// Footwear score components (logging mirrors actual [scoreShoes] math).
    ({double base, double warmth, double season, double rain}) footwearScoreParts(
      Map<String, dynamic> it,
    ) {
      final b = blob(it);
      final canonical = canonicalLabel(it);
      final scoreBase = baseScore(it);
      var scoreRain = 0.0;
      var scoreWarmth = 0.0;
      var scoreSeason = 0.0;

      final warmthLevel = StylistLayerFilter.inferWarmthLevel(it);
      if (warmthLevel >= 6) {
        if (temp <= 8) {
          scoreWarmth += 1.5;
        } else if (temp >= 18) {
          scoreWarmth -= 3.0;
        } else if (temp >= 14) {
          scoreWarmth -= 2.0;
        }
      }

      if (isWarm && (b.contains('sandál') || b.contains('sandal'))) {
        scoreWarmth += 1.0;
      }

      final seasons = seasonTokens(it);
      if (seasonMentionsWinter(seasons) && temp >= 14) {
        scoreSeason -= 2.0;
      }
      if (seasonMentionsSummer(seasons) && temp <= 10) {
        scoreSeason -= 2.0;
      }

      if (weather.isRainy) {
        final bootLike = isBootFootwear(b, canonical);
        final sneakerLike = isSneakerFootwear(b, canonical);
        final heavyRain = weather.isHeavyRain;

        if (bootLike && (temp <= 12 || heavyRain)) {
          scoreRain += 1.0;
        }

        if (sneakerLike && temp > 12) {
          if (isWhiteOrLightFootwear(it, b)) {
            scoreRain -= 1.0;
          } else {
            scoreRain += 0.5;
          }
        }
      }

      return (
        base: scoreBase,
        warmth: scoreWarmth,
        season: scoreSeason,
        rain: scoreRain,
      );
    }

    double footwearScoreTotal(Map<String, dynamic> it) {
      final p = footwearScoreParts(it);
      return p.base + p.warmth + p.season + p.rain;
    }

    void logFootwearCandidate(Map<String, dynamic> it) {
      if (!kDebugMode || !kVerboseHomeLogs) return;
      final parts = footwearScoreParts(it);
      final total = parts.base + parts.warmth + parts.season + parts.rain;
      debugPrint(
        '[FOOTWEAR_SCORE]\n'
        'name=${labelFor(it, fallback: 'Obuv')}\n'
        'canonicalType=${canonicalLabel(it)}\n'
        'season=${seasonsLabel(it)}\n'
        'warmthLevel=${StylistLayerFilter.inferWarmthLevel(it)}\n'
        'weatherTemp=$temp\n'
        'rain=${weather.isRainy}\n'
        'score_base=${parts.base}\n'
        'score_warmth=${parts.warmth}\n'
        'score_season=${parts.season}\n'
        'score_rain=${parts.rain}\n'
        'score_total=$total',
      );
    }

    void logFootwearWinner({
      required Map<String, dynamic> selected,
      required List<Map<String, dynamic>> candidatePool,
      required int attempt,
    }) {
      if (!kDebugMode) return;
      final ranked = candidatePool
          .map((c) => (item: c, total: footwearScoreTotal(c)))
          .toList()
        ..sort((a, b) {
          final cmp = b.total.compareTo(a.total);
          if (cmp != 0) return cmp;
          return wardrobeItemId(a.item).compareTo(wardrobeItemId(b.item));
        });

      final winnerParts = footwearScoreParts(selected);
      final winnerTotal =
          winnerParts.base + winnerParts.warmth + winnerParts.season + winnerParts.rain;
      final reasons = <String>[];

      if (attempt > 0) {
        reasons.add('pick_rank_index=$attempt (nth-best after exclusions)');
      } else if (attempt < 0) {
        reasons.add('pick_rank_index=forceDifferent_fallback');
      } else {
        reasons.add('pick_rank_index=0 (highest score in pool)');
      }
      if (winnerParts.rain != 0) {
        reasons.add('score_rain=${winnerParts.rain}');
      }
      if (winnerParts.warmth != 0) {
        reasons.add('score_warmth=${winnerParts.warmth}');
      }
      if (winnerParts.season != 0) {
        reasons.add('score_season=${winnerParts.season}');
      }
      if (winnerParts.base > 0) {
        reasons.add('score_base=+${winnerParts.base}');
      }
      reasons.add('score_total=$winnerTotal');
      if (ranked.length > 1) {
        final runner = ranked.firstWhere(
          (e) => wardrobeItemId(e.item) != wardrobeItemId(selected),
          orElse: () => ranked[1],
        );
        final gap = winnerTotal - runner.total;
        reasons.add(
          'runner_up=${labelFor(runner.item, fallback: 'Obuv')} '
          '(total=${runner.total}, gap=${gap.toStringAsFixed(2)})',
        );
      }
      reasons.add('pool_size=${candidatePool.length}');

      debugPrint(
        '[FOOTWEAR_WINNER]\n'
        'selected=${labelFor(selected, fallback: 'Obuv')}\n'
        'reason=${reasons.join('; ')}',
      );
    }

    if (kDebugMode && kVerboseHomeLogs) {
      debugPrint(
        '[FOOTWEAR_SCORE] pool_size=${shoes.length} weatherTemp=$temp '
        'rain=${weather.isRainy} heavyRain=${weather.isHeavyRain} '
        'rainIntensity=${weather.rainIntensity ?? ''} seasonKey=${weather.seasonKey}',
      );
      for (final it in shoes) {
        logFootwearCandidate(it);
      }
    }

    double scoreTop(Map<String, dynamic> it) {
      var s = baseScore(it);
      if (!StylistLayerFilter.isTankTopItem(it)) return s;

      if (temp >= 24 || StylistLayerFilter.isSportOrBeachOccasionItem(it)) {
        return s + 0.5;
      }
      return s - 6.0;
    }

    double scoreBottom(Map<String, dynamic> it) {
      final b = blob(it);
      var s = baseScore(it);
      if (isWarm && (b.contains('krať') || b.contains('short'))) s += 1.0;
      return s;
    }

    double scoreShoes(Map<String, dynamic> it) => footwearScoreTotal(it);

    double scoreOuter(Map<String, dynamic> it) {
      final b = blob(it);
      var s = baseScore(it);
      final warmth = StylistLayerFilter.inferWarmthLevel(it);
      final layer = StylistLayerFilter.resolveEffectiveLayerRole(it);
      if (isCold && warmth >= 7) s += 1.4;
      if (isCold && isHeavyOuterwear(it)) s += 1.2;
      if (isCold && layer == 'mid_layer') s += 0.35;
      if (isFreezing && warmth <= 5) s -= 1.1;
      if (isMild && isLightOuterwear(it)) s += 1.0;
      if (isWarm && warmth >= 7) s -= 1.5;
      if (isWarm && layer == 'mid_layer') s -= 0.6;
      if (weather.isRainy && b.contains('bunda')) s += 0.4;
      return s;
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

    bool isShortsBottom(Map<String, dynamic> it) {
      final b = blob(it);
      return b.contains('krať') ||
          b.contains('krat') ||
          b.contains('short') ||
          b.contains('sortk') ||
          b.contains('šortk');
    }

    bool isSummerShortsBottom(Map<String, dynamic> it) {
      if (!isShortsBottom(it)) return false;
      final w = StylistLayerFilter.inferWarmthLevel(it);
      if (w <= 3) return true;
      return seasonMentionsSummer(seasonTokens(it));
    }

    bool isWinterJacketOuter(Map<String, dynamic> it) {
      final b = blob(it);
      final w = StylistLayerFilter.inferWarmthLevel(it);
      if (w < 7) return false;
      return b.contains('zimn') ||
          b.contains('winter') ||
          b.contains('bunda_zimna') ||
          b.contains('bunda zimna') ||
          isHeavyOuterwear(it);
    }

    void logOutfitConsistency({
      required Map<String, dynamic> topItem,
      required Map<String, dynamic> bottomItem,
      required Map<String, dynamic> shoesItem,
      Map<String, dynamic>? outerItem,
    }) {
      if (!kDebugMode) return;

      final topWarmth = StylistLayerFilter.inferWarmthLevel(topItem);
      final bottomWarmth = StylistLayerFilter.inferWarmthLevel(bottomItem);
      final footwearWarmth = StylistLayerFilter.inferWarmthLevel(shoesItem);
      final outerWarmth = outerItem == null
          ? null
          : StylistLayerFilter.inferWarmthLevel(outerItem);

      final warmths = <int>[topWarmth, bottomWarmth, footwearWarmth];
      if (outerWarmth != null) warmths.add(outerWarmth);
      final maxWarmth = warmths.reduce((a, b) => a > b ? a : b);
      final minWarmth = warmths.reduce((a, b) => a < b ? a : b);
      final warmthSpread = maxWarmth - minWarmth;

      final outfitItems = <String>[
        'top:${labelFor(topItem, fallback: 'top')}(w=$topWarmth)',
        'bottom:${labelFor(bottomItem, fallback: 'bottom')}(w=$bottomWarmth)',
        'footwear:${labelFor(shoesItem, fallback: 'shoes')}(w=$footwearWarmth)',
        if (outerItem != null)
          'outer:${labelFor(outerItem, fallback: 'outer')}(w=$outerWarmth)',
      ].join(' | ');

      const winterJacketShortsPenalty = 3.0;
      const heavyOuterSummerShortsPenalty = 2.5;
      const warmthSpreadThreshold = 5;
      const warmthSpreadPenalty = 2.0;

      final issues = <String>[];
      var penaltyTotal = 0.0;

      if (outerItem != null &&
          isWinterJacketOuter(outerItem) &&
          isShortsBottom(bottomItem)) {
        penaltyTotal -= winterJacketShortsPenalty;
        issues.add(
          'winter_jacket_with_shorts(-$winterJacketShortsPenalty)',
        );
      }

      if (outerItem != null &&
          isSummerShortsBottom(bottomItem) &&
          (isHeavyOuterwear(outerItem) ||
              StylistLayerFilter.inferWarmthLevel(outerItem) >= 7)) {
        penaltyTotal -= heavyOuterSummerShortsPenalty;
        issues.add(
          'heavy_outerwear_with_summer_shorts(-$heavyOuterSummerShortsPenalty)',
        );
      }

      if (warmthSpread >= warmthSpreadThreshold) {
        penaltyTotal -= warmthSpreadPenalty;
        issues.add(
          'warmth_spread_too_large(spread=$warmthSpread,-$warmthSpreadPenalty)',
        );
      }

      debugPrint(
        '[OUTFIT_CONSISTENCY]\n'
        'topWarmth=$topWarmth\n'
        'outerWarmth=${outerWarmth ?? 'none'}\n'
        'bottomWarmth=$bottomWarmth\n'
        'footwearWarmth=$footwearWarmth\n'
        'warmthSpread=$warmthSpread\n'
        'outfitItems=$outfitItems\n'
        'issues=${issues.isEmpty ? 'none' : issues.join('; ')}\n'
        'penalty_total=$penaltyTotal',
      );
    }

    OutfitPreview buildPreview({
      required Map<String, dynamic> topItem,
      required Map<String, dynamic> bottomItem,
      required Map<String, dynamic> shoesItem,
      required Map<String, dynamic>? outerItem,
    }) {
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

    final prevIdSet = previousItemIds.toSet();
    const matrixTopN = 4;
    const matrixBottomN = 4;
    const matrixFootwearN = 3;
    const matrixOuterN = 3;

    final ftops = filterExcluded(tops, 'top');
    final fbottoms = filterExcluded(bottoms, 'bottom');
    final fshoes = filterExcluded(shoes, 'shoes');

    final topCandidates =
        rankPool(ftops, scoreTop).take(matrixTopN).toList(growable: false);
    final bottomCandidates =
        rankPool(fbottoms, scoreBottom).take(matrixBottomN).toList(growable: false);
    final footwearCandidates =
        rankPool(fshoes, scoreShoes).take(matrixFootwearN).toList(growable: false);

    final outerPolicy = resolveOuterwearPolicy(
      tempC: temp,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
    );
    logOuterPolicy(
      policy: outerPolicy,
      reason: outerwearPolicyReason(
        tempC: temp,
        isRainy: weather.isRainy,
        isWindy: weather.isWindy,
        policy: outerPolicy,
      ),
      tempC: temp,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
    );

    bool shouldPreferNoOuter(OutfitPreview preview) {
      return preferNoOuterWhenComfortable?.call(preview) ?? false;
    }

    final List<Map<String, dynamic>?> outerCandidates;
    switch (outerPolicy) {
      case OuterwearPolicy.forbidden:
        outerCandidates = const [null];
      case OuterwearPolicy.required:
        if (outerwear.isEmpty) {
          outerCandidates = const [null];
        } else {
          final fo = filterExcluded(outerwear, 'outerwear');
          outerCandidates = rankPool(fo, scoreOuter)
              .take(matrixOuterN)
              .map<Map<String, dynamic>?>((e) => e)
              .toList(growable: false);
        }
      case OuterwearPolicy.optional:
        final rankedOuter = outerwear.isEmpty
            ? const <Map<String, dynamic>>[]
            : rankPool(
                filterExcluded(outerwear, 'outerwear'),
                scoreOuter,
              ).take(matrixOuterN).toList(growable: false);
        outerCandidates = <Map<String, dynamic>?>[
          null,
          ...rankedOuter,
        ];
    }

    String matrixCandidateLabel(OutfitPreview preview) {
      final parts = <String>[
        preview.top.label,
        preview.bottom.label,
        preview.shoes.label,
      ];
      if (preview.outerwear != null) {
        parts.add(preview.outerwear!.label);
      }
      return parts.join(' + ');
    }

    double matrixEow(OutfitPreview preview) {
      return outerMatrixEowReader?.call(preview) ?? double.nan;
    }

    final auditOuterMatrix = outerPolicy == OuterwearPolicy.optional;

    String? combinationFilterRejection({
      required OutfitPreview preview,
      required String sig,
      required List<Map<String, dynamic>> picks,
    }) {
      if (sig.isEmpty) return 'empty_signature';
      if (rejectedCombinationSignatures.contains(sig)) {
        return 'rejected_signature';
      }
      if (preferredFootwearExists &&
          isDiscouragedFootwear != null &&
          isDiscouragedFootwear(preview)) {
        return 'discouraged_footwear';
      }
      if (preferredBottomExists &&
          isDiscouragedBottom != null &&
          isDiscouragedBottom(preview)) {
        return 'discouraged_bottom';
      }
      if (passesLayerHarmony != null && !passesLayerHarmony(preview)) {
        return 'layer_harmony';
      }
      if (forceDifferentOutfit &&
          prevIdSet.isNotEmpty &&
          overlapCount(prevIdSet, picks) >= 3) {
        return 'force_different_outfit_overlap';
      }
      return null;
    }

    double combinationScore(OutfitPreview preview) {
      var total = ruleBasedOutfitScoreForPreview(
        preview: preview,
        weather: weather,
      );
      total += consistencyPenaltyForPreview(preview: preview);

      if (isPreferredBottom != null && isPreferredBottom(preview)) {
        total += 1.5;
      }
      if (isPreferredFootwear != null && isPreferredFootwear(preview)) {
        total += 1.5;
      }
      if (isPreferredBottom != null &&
          isPreferredFootwear != null &&
          isPreferredBottom(preview) &&
          isPreferredFootwear(preview)) {
        total += 1.0;
      }
      if (comfortBonusScorer != null) {
        total += comfortBonusScorer(preview);
      }
      if (outerPolicy == OuterwearPolicy.optional &&
          preview.outerwear != null &&
          shouldPreferNoOuter(preview)) {
        total -= 1.5;
      }
      if (outerPolicy == OuterwearPolicy.optional &&
          preview.outerwear == null &&
          shouldPreferNoOuter(preview)) {
        total += 0.4;
      }
      return total;
    }

    final nullOuterSlotCount =
        outerCandidates.where((outerItem) => outerItem == null).length;
    final outerWearSlotCount =
        outerCandidates.where((outerItem) => outerItem != null).length;
    final matrixCellCount = topCandidates.length *
        bottomCandidates.length *
        footwearCandidates.length;
    final nullOuterCombinations = matrixCellCount * nullOuterSlotCount;
    final outerCombinations = matrixCellCount * outerWearSlotCount;
    if (auditOuterMatrix) {
      logOuterMatrixCombinationCounts(
        nullOuterCombinations: nullOuterCombinations,
        outerCombinations: outerCombinations,
        outerCandidateSlots: outerCandidates.length,
      );
    }

    var combinationCount = 0;
    var nullOuterRejectedByFilter = 0;
    var nullOuterScored = 0;
    var outerScored = 0;
    final scored = <({OutfitPreview preview, double score, String sig})>[];

    for (final topItem in topCandidates) {
      for (final bottomItem in bottomCandidates) {
        for (final shoesItem in footwearCandidates) {
          for (final outerItem in outerCandidates) {
            combinationCount++;
            final preview = buildPreview(
              topItem: topItem,
              bottomItem: bottomItem,
              shoesItem: shoesItem,
              outerItem: outerItem,
            );
            final sig = combinationSignature(
              topItem,
              bottomItem,
              shoesItem,
              outerItem,
            );
            final picks = <Map<String, dynamic>>[
              topItem,
              bottomItem,
              shoesItem,
              if (outerItem != null) outerItem,
            ];
            final filterRejection = combinationFilterRejection(
              preview: preview,
              sig: sig,
              picks: picks,
            );
            if (filterRejection != null) {
              if (auditOuterMatrix && outerItem == null) {
                logOuterMatrixRejection(
                  candidate: matrixCandidateLabel(preview),
                  reason: filterRejection,
                  phase: 'matrix_filter',
                );
                nullOuterRejectedByFilter++;
              }
              continue;
            }
            final score = combinationScore(preview);
            scored.add((
              preview: preview,
              score: score,
              sig: sig,
            ));
            if (outerItem == null) {
              nullOuterScored++;
              if (auditOuterMatrix) {
                logOuterMatrixAudit(
                  candidate: matrixCandidateLabel(preview),
                  withOuter: false,
                  eow: matrixEow(preview),
                  ct: outerMatrixCt ?? double.nan,
                  wholeScore: score,
                  phase: 'scored',
                );
              }
            } else {
              outerScored++;
            }
          }
        }
      }
    }

    if (auditOuterMatrix) {
      logOuterMatrixScoredSummary(
        nullOuterScored: nullOuterScored,
        outerScored: outerScored,
        nullOuterRejectedByFilter: nullOuterRejectedByFilter,
      );
    }

    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.sig.compareTo(b.sig);
    });

    String baseComboKeyForPreview(OutfitPreview preview) {
      return [
        wardrobeItemId(preview.top.item),
        wardrobeItemId(preview.bottom.item),
        wardrobeItemId(preview.shoes.item),
      ].join('|');
    }

    List<({OutfitPreview preview, double score, String sig})>
        collapseOptionalOuterScored(
      List<({OutfitPreview preview, double score, String sig})> source,
    ) {
      final grouped =
          <String, List<({OutfitPreview preview, double score, String sig})>>{};
      for (final entry in source) {
        final key = baseComboKeyForPreview(entry.preview);
        grouped.putIfAbsent(key, () => []).add(entry);
      }

      final collapsed =
          <({OutfitPreview preview, double score, String sig})>[];
      for (final groupEntry in grouped.entries) {
        final baseKey = groupEntry.key;
        final group = groupEntry.value;
        final noOuter = group
            .where((entry) => entry.preview.outerwear == null)
            .toList(growable: false);
        final withOuter = group
            .where((entry) => entry.preview.outerwear != null)
            .toList(growable: false);

        if (noOuter.isEmpty) {
          withOuter.sort((a, b) {
            final cmp = b.score.compareTo(a.score);
            if (cmp != 0) return cmp;
            return a.sig.compareTo(b.sig);
          });
          collapsed.add(withOuter.first);
          continue;
        }
        if (withOuter.isEmpty) {
          collapsed.add(noOuter.first);
          continue;
        }

        withOuter.sort((a, b) {
          final cmp = b.score.compareTo(a.score);
          if (cmp != 0) return cmp;
          return a.sig.compareTo(b.sig);
        });
        final noEntry = noOuter.first;
        final bestWith = withOuter.first;
        final noEow = matrixEow(noEntry.preview);
        final withEow = matrixEow(bestWith.preview);
        final bands = outerVariantComfortBands!;

        final decision = decideOuterVariant(
          noOuterScore: noEntry.score,
          withOuterScore: bestWith.score,
          noOuterEow: noEow,
          withOuterEow: withEow,
          bands: bands,
        );

        logOuterVariantDecision(
          baseCombo: baseKey,
          selected: decision.selected,
          noOuterEow: noEow,
          withOuterEow: withEow,
          ct: bands.ct,
          reason: decision.reason,
        );

        collapsed.add(
          decision.selected == OuterVariantSelection.noOuter
              ? noEntry
              : bestWith,
        );
      }
      return collapsed;
    }

    var scoredForKept = scored;
    if (outerPolicy == OuterwearPolicy.optional &&
        outerMatrixEowReader != null &&
        outerVariantComfortBands != null) {
      scoredForKept = collapseOptionalOuterScored(scored);
      scoredForKept.sort((a, b) {
        final cmp = b.score.compareTo(a.score);
        if (cmp != 0) return cmp;
        return a.sig.compareTo(b.sig);
      });
    }

    final kept = <OutfitPreview>[];
    final keptSigs = <String>{};

    void insertForcedPreview({
      required OutfitPreview? preview,
      required String reason,
    }) {
      if (preview == null) return;
      final sig = combinationSignature(
        preview.top.item,
        preview.bottom.item,
        preview.shoes.item,
        preview.outerwear?.item,
      );
      if (sig.isEmpty || keptSigs.contains(sig)) return;
      logCandidateForcedCombo(
        reason: reason,
        bottom: preview.bottom.label,
        footwear: preview.shoes.label,
        outer: preview.outerwear?.label,
        top: preview.top.label,
      );
      if (kept.length >= candidateLimit) {
        final removed = kept.removeLast();
        final removedSig = combinationSignature(
          removed.top.item,
          removed.bottom.item,
          removed.shoes.item,
          removed.outerwear?.item,
        );
        if (auditOuterMatrix && removed.outerwear == null) {
          final removedScore = scoredForKept
              .where((entry) => entry.sig == removedSig)
              .map((entry) => entry.score)
              .fold<double?>(null, (best, score) {
            if (best == null || score > best) return score;
            return best;
          });
          logOuterMatrixRejection(
            candidate: matrixCandidateLabel(removed),
            reason: 'forced_preview_displaced',
            detail: reason,
            phase: 'kept',
          );
          if (removedScore != null) {
            logOuterMatrixAudit(
              candidate: matrixCandidateLabel(removed),
              withOuter: false,
              eow: matrixEow(removed),
              ct: outerMatrixCt ?? double.nan,
              wholeScore: removedScore,
              phase: 'displaced',
            );
          }
        }
        keptSigs.remove(removedSig);
      }
      kept.insert(0, preview);
      keptSigs.add(sig);
    }

    bool hasPreferredBottomIn(List<OutfitPreview> list) {
      if (isPreferredBottom == null) return true;
      return list.any(isPreferredBottom);
    }

    bool hasPreferredFootwearIn(List<OutfitPreview> list) {
      if (isPreferredFootwear == null) return true;
      return list.any(isPreferredFootwear);
    }

    bool hasPreferredPairIn(List<OutfitPreview> list) {
      if (isPreferredBottom == null || isPreferredFootwear == null) return true;
      return list.any(
        (p) => isPreferredBottom(p) && isPreferredFootwear(p),
      );
    }

    OutfitPreview? bestScoredWhere(bool Function(OutfitPreview) test) {
      OutfitPreview? best;
      var bestScore = double.negativeInfinity;
      for (final entry in scoredForKept) {
        if (!test(entry.preview)) continue;
        var score = entry.score;
        if (entry.preview.outerwear == null &&
            shouldPreferNoOuter(entry.preview)) {
          score += 0.4;
        }
        if (score > bestScore) {
          bestScore = score;
          best = entry.preview;
        }
      }
      return best;
    }

    OutfitPreview? bestPreferredPairCombo() {
      if (isPreferredBottom == null || isPreferredFootwear == null) return null;
      OutfitPreview? best;
      var bestScore = double.negativeInfinity;
      for (final entry in scoredForKept) {
        final p = entry.preview;
        if (!isPreferredBottom(p) || !isPreferredFootwear(p)) {
          continue;
        }
        if (p.outerwear != null && shouldPreferNoOuter(p)) {
          continue;
        }
        var score = entry.score;
        final outer = p.outerwear?.item;
        if (isMild &&
            outer != null &&
            isLightOuterwear(outer) &&
            !shouldPreferNoOuter(p)) {
          score += 0.5;
        }
        if (p.outerwear == null && shouldPreferNoOuter(p)) {
          score += 0.4;
        }
        if (score > bestScore) {
          bestScore = score;
          best = p;
        }
      }
      return best;
    }

    final usedBottomIds = <String>{};
    final usedShoeIds = <String>{};

    final scoredRankBySig = <String, int>{
      for (var i = 0; i < scoredForKept.length; i++)
        scoredForKept[i].sig: i + 1,
    };

    double scoreForPreview(OutfitPreview preview) {
      final sig = combinationSignature(
        preview.top.item,
        preview.bottom.item,
        preview.shoes.item,
        preview.outerwear?.item,
      );
      for (final entry in scoredForKept) {
        if (entry.sig == sig) return entry.score;
      }
      return double.nan;
    }

    int scoredRankForPreview(OutfitPreview preview) {
      final sig = combinationSignature(
        preview.top.item,
        preview.bottom.item,
        preview.shoes.item,
        preview.outerwear?.item,
      );
      return scoredRankBySig[sig] ?? -1;
    }

    OutfitPreview? incumbentForBottomId(String bottomId) {
      for (final preview in kept) {
        if (wardrobeItemId(preview.bottom.item) == bottomId) {
          return preview;
        }
      }
      return null;
    }

    void logHeadToHeadForBaseCombo({
      required String pass,
      required ({OutfitPreview preview, double score, String sig}) entry,
      required int entryScoredRank,
      required String winReason,
    }) {
      final baseKey = baseComboKeyForPreview(entry.preview);
      final ct = outerMatrixCt ?? double.nan;
      for (final alternate in scoredForKept) {
        if (alternate.sig == entry.sig) continue;
        if (baseComboKeyForPreview(alternate.preview) != baseKey) continue;
        final alternateRank = scoredRankBySig[alternate.sig] ?? -1;
        final entryWins = entryScoredRank < alternateRank;
        logKeptSelectionHeadToHead(
          pass: pass,
          baseComboKey: baseKey,
          winnerCandidate: matrixCandidateLabel(
            entryWins ? entry.preview : alternate.preview,
          ),
          winnerWithOuter: entryWins
              ? entry.preview.outerwear != null
              : alternate.preview.outerwear != null,
          winnerWholeScore: entryWins ? entry.score : alternate.score,
          winnerEow: matrixEow(
            entryWins ? entry.preview : alternate.preview,
          ),
          winnerScoredRank: entryWins ? entryScoredRank : alternateRank,
          loserCandidate: matrixCandidateLabel(
            entryWins ? alternate.preview : entry.preview,
          ),
          loserWithOuter: entryWins
              ? alternate.preview.outerwear != null
              : entry.preview.outerwear != null,
          loserWholeScore: entryWins ? alternate.score : entry.score,
          loserEow: matrixEow(
            entryWins ? alternate.preview : entry.preview,
          ),
          loserScoredRank: entryWins ? alternateRank : entryScoredRank,
          ct: ct,
          winReason: winReason,
        );
      }
    }

    List<KeptSelectionKeptRow> keptRowsForAudit() {
      final ct = outerMatrixCt ?? double.nan;
      return [
        for (var i = 0; i < kept.length; i++)
          KeptSelectionKeptRow(
            candidate: matrixCandidateLabel(kept[i]),
            withOuter: kept[i].outerwear != null,
            wholeScore: scoreForPreview(kept[i]),
            eow: matrixEow(kept[i]),
            ct: ct,
            eowDeltaFromCt: matrixEow(kept[i]).isNaN || ct.isNaN
                ? double.nan
                : (matrixEow(kept[i]) - ct).abs(),
            scoredRank: scoredRankForPreview(kept[i]),
          ),
      ];
    }

    void fillKeptFromScored({required bool requireUniqueBottom}) {
      final pass =
          requireUniqueBottom ? 'unique_bottom_pass' : 'diversity_fill_pass';
      final ct = outerMatrixCt ?? double.nan;

      if (auditOuterMatrix) {
        logKeptSelectionPassStart(
          pass: pass,
          keptCountBefore: kept.length,
          candidateLimit: candidateLimit,
          scoredCount: scoredForKept.length,
        );
        logKeptSelectionScoredHead(
          pass: pass,
          rows: [
            for (var i = 0; i < scoredForKept.length && i < 16; i++)
              KeptSelectionScoredRow(
                candidate: matrixCandidateLabel(scoredForKept[i].preview),
                withOuter: scoredForKept[i].preview.outerwear != null,
                wholeScore: scoredForKept[i].score,
                eow: matrixEow(scoredForKept[i].preview),
                ct: ct,
                eowDeltaFromCt:
                    matrixEow(scoredForKept[i].preview).isNaN || ct.isNaN
                        ? double.nan
                        : (matrixEow(scoredForKept[i].preview) - ct).abs(),
                bottomId:
                    wardrobeItemId(scoredForKept[i].preview.bottom.item),
              ),
          ],
        );
      }

      var scoredRank = 0;
      for (final entry in scoredForKept) {
        scoredRank++;
        final preview = entry.preview;
        final candidate = matrixCandidateLabel(preview);
        final withOuter = preview.outerwear != null;
        final eow = matrixEow(preview);
        final bottomId = wardrobeItemId(preview.bottom.item);

        if (kept.length >= candidateLimit) {
          if (auditOuterMatrix && !keptSigs.contains(entry.sig)) {
            logKeptSelectionSkipped(
              pass: pass,
              scoredRank: scoredRank,
              reason: 'candidate_limit_reached',
              candidate: candidate,
              withOuter: withOuter,
              wholeScore: entry.score,
              eow: eow,
              ct: ct,
              bottomId: bottomId,
              keptCount: kept.length,
              candidateLimit: candidateLimit,
            );
          }
          continue;
        }
        if (keptSigs.contains(entry.sig)) continue;

        final shoeId = wardrobeItemId(preview.shoes.item);
        if (requireUniqueBottom &&
            bottomId.isNotEmpty &&
            usedBottomIds.contains(bottomId)) {
          if (auditOuterMatrix) {
            final incumbent = incumbentForBottomId(bottomId);
            logKeptSelectionSkipped(
              pass: pass,
              scoredRank: scoredRank,
              reason: 'unique_bottom_diversity',
              candidate: candidate,
              withOuter: withOuter,
              wholeScore: entry.score,
              eow: eow,
              ct: ct,
              bottomId: bottomId,
              incumbentCandidate: incumbent == null
                  ? null
                  : matrixCandidateLabel(incumbent),
              incumbentWithOuter: incumbent?.outerwear != null,
              incumbentWholeScore:
                  incumbent == null ? null : scoreForPreview(incumbent),
              incumbentScoredRank:
                  incumbent == null ? null : scoredRankForPreview(incumbent),
              incumbentEow:
                  incumbent == null ? null : matrixEow(incumbent),
              incumbentCt: ct,
            );
            logHeadToHeadForBaseCombo(
              pass: pass,
              entry: entry,
              entryScoredRank: scoredRank,
              winReason: 'same_base_combo_ranked_order',
            );
          }
          continue;
        }

        kept.add(preview);
        keptSigs.add(entry.sig);
        if (bottomId.isNotEmpty) usedBottomIds.add(bottomId);
        if (shoeId.isNotEmpty) usedShoeIds.add(shoeId);

        if (auditOuterMatrix) {
          logKeptSelectionKept(
            pass: pass,
            slot: kept.length - 1,
            scoredRank: scoredRank,
            candidate: candidate,
            withOuter: withOuter,
            wholeScore: entry.score,
            eow: eow,
            ct: ct,
            bottomId: bottomId,
            baseComboKey: baseComboKeyForPreview(preview),
          );
          logHeadToHeadForBaseCombo(
            pass: pass,
            entry: entry,
            entryScoredRank: scoredRank,
            winReason: 'kept_over_same_base_combo_alternate',
          );
        }
      }

      if (auditOuterMatrix) {
        logKeptSelectionPassEnd(pass: pass, keptRows: keptRowsForAudit());
      }
    }

    fillKeptFromScored(requireUniqueBottom: true);
    fillKeptFromScored(requireUniqueBottom: false);

    if (preferredBottomExists &&
        preferredFootwearExists &&
        !hasPreferredPairIn(kept)) {
      insertForcedPreview(
        preview: bestPreferredPairCombo(),
        reason: 'preferred_bottom_plus_preferred_footwear',
      );
    }
    if (preferredBottomExists && !hasPreferredBottomIn(kept)) {
      insertForcedPreview(
        preview: bestScoredWhere(
          (p) => isPreferredBottom != null && isPreferredBottom(p),
        ),
        reason: 'preferred_bottom_family',
      );
    }
    if (preferredFootwearExists && !hasPreferredFootwearIn(kept)) {
      insertForcedPreview(
        preview: bestScoredWhere(
          (p) => isPreferredFootwear != null && isPreferredFootwear(p),
        ),
        reason: 'preferred_footwear_family',
      );
    }

    if (auditOuterMatrix) {
      for (var i = 0; i < kept.length; i++) {
        final p = kept[i];
        final keptScore = scoredForKept
            .where((entry) => entry.sig == combinationSignature(
                  p.top.item,
                  p.bottom.item,
                  p.shoes.item,
                  p.outerwear?.item,
                ))
            .map((entry) => entry.score)
            .fold<double?>(null, (best, score) {
          if (best == null || score > best) return score;
          return best;
        });
        logOuterMatrixAudit(
          candidate: matrixCandidateLabel(p),
          withOuter: p.outerwear != null,
          eow: matrixEow(p),
          ct: outerMatrixCt ?? double.nan,
          wholeScore: keptScore ?? double.nan,
          phase: 'kept',
          rank: i,
        );
      }
    }

    for (var i = 0; i < kept.length; i++) {
      if (outerPolicy == OuterwearPolicy.optional) {
        logOptionalOuterCandidate?.call(i, kept[i]);
      }
    }

    if (auditEnabled) {
      logCandidateMatrix(
        topCount: topCandidates.length,
        bottomCount: bottomCandidates.length,
        footwearCount: footwearCandidates.length,
        outerCount: outerCandidates.length,
        combinationCount: combinationCount,
        keptCount: kept.length,
        passIndex: auditPassIndex,
      );
      for (var i = 0; i < kept.length; i++) {
        final p = kept[i];
        logCandidateBuild(
          candidateIndex: multiCandidate ? i : (auditCandidateIndex ?? 0),
          selectedTop: p.top.label,
          selectedBottom: p.bottom.label,
          selectedFootwear: p.shoes.label,
          selectedOuter: p.outerwear?.label,
          selectionReason: multiCandidate
              ? 'matrix_combination_rank_$i'
              : 'best_matrix_combination',
        );
        if (!multiCandidate && i == 0) {
          logOutfitConsistency(
            topItem: p.top.item,
            bottomItem: p.bottom.item,
            shoesItem: p.shoes.item,
            outerItem: p.outerwear?.item,
          );
          logFootwearWinner(
            selected: p.shoes.item,
            candidatePool: fshoes,
            attempt: 0,
          );
        }
      }
    }

    return (
      preview: kept.isEmpty ? null : kept.first,
      previews: kept,
      pools: poolsSnapshot,
    );
  }

  /// Rule-based outfit score for logging / explainability (does NOT affect selection).
  /// Mirrors the scoring math used by [generatePreview].
  static double ruleBasedOutfitScoreForPreview({
    required OutfitPreview preview,
    required OutfitWeatherSnapshot weather,
  }) {
    String blob(Map<String, dynamic> it) {
      return [
        (it['name'] ?? '').toString(),
        (it['category'] ?? it['categoryKey'] ?? '').toString(),
        (it['subCategory'] ?? it['subCategoryKey'] ?? '').toString(),
        (it['mainGroup'] ?? it['mainGroupKey'] ?? '').toString(),
      ].join(' ').toLowerCase();
    }

    double baseScore(Map<String, dynamic> it) {
      final baseDyn = it['baseColors'];
      final baseColors = <String>[
        if (baseDyn is List) ...baseDyn.map((e) => e.toString()),
        if (baseDyn is String && baseDyn.trim().isNotEmpty) baseDyn,
      ]
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();

      final colorsDyn = it['colors'];
      final colors = <String>[
        if (colorsDyn is List) ...colorsDyn.map((e) => e.toString()),
        if (colorsDyn is String && colorsDyn.trim().isNotEmpty) colorsDyn,
      ]
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();

      final check = baseColors.isNotEmpty ? baseColors : colors;
      final isNeutral = check.isNotEmpty && check.any((c) {
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

      double s = 0.0;
      if (isNeutral) s += 2.0;

      final b = blob(it);
      if (b.contains('basic')) s += 1.0;

      final brand = (it['brand'] ?? '').toString().trim();
      if (brand.isNotEmpty) s += 0.2;
      return s;
    }

    final temp = weather.tempC;
    final isWarm = temp >= 20;
    final isMild = temp >= 10 && temp < 20;
    final isCold = temp < 10;
    final isFreezing = temp < 0;

    bool isHeavyOuterwear(Map<String, dynamic> it) {
      final b = blob(it);
      return b.contains('kabát') ||
          b.contains('kabat') ||
          b.contains('coat') ||
          b.contains('parka') ||
          b.contains('čiž') ||
          b.contains('ciz');
    }

    bool isLightOuterwear(Map<String, dynamic> it) {
      final b = blob(it);
      return b.contains('mikina') ||
          b.contains('hoodie') ||
          b.contains('sako') ||
          b.contains('blazer') ||
          b.contains('bunda') ||
          b.contains('jacket');
    }

    // --- Footwear scoring (mirrors the local functions in generatePreview) ---
    List<String> seasonTokens(Map<String, dynamic> it) {
      final raw = it['seasons'] ?? it['season'];
      if (raw is List) {
        return raw
            .map((e) => e.toString().trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (raw is String && raw.trim().isNotEmpty) {
        return [raw.trim().toLowerCase()];
      }
      return const [];
    }

    bool seasonMentionsWinter(List<String> tokens) {
      return tokens.any((t) =>
          t.contains('zim') || t.contains('winter') || t == 'zim' || t == 'zima');
    }

    bool seasonMentionsSummer(List<String> tokens) {
      return tokens.any((t) =>
          t.contains('let') || t.contains('summer') || t == 'leto' || t == 'let');
    }

    bool isBootFootwear(String b, String canonical) {
      final c = canonical.toLowerCase();
      return b.contains('čiž') || b.contains('ciz') || b.contains('boot') || c.contains('boot');
    }

    bool isSneakerFootwear(String b, String canonical) {
      final c = canonical.toLowerCase();
      return b.contains('tenis') ||
          b.contains('sneaker') ||
          c.contains('sneaker') ||
          c == 'sneakers';
    }

    bool isWhiteOrLightFootwear(Map<String, dynamic> it, String b) {
      final colorSources = <String>[
        if (it['colors'] is List) ...(it['colors'] as List).map((e) => e.toString()),
        if (it['colors'] is String) it['colors'].toString(),
        if (it['baseColors'] is List)
          ...(it['baseColors'] as List).map((e) => e.toString()),
        if (it['baseColors'] is String) it['baseColors'].toString(),
        b,
      ];

      for (final raw in colorSources) {
        final c = raw.trim().toLowerCase();
        if (c.isEmpty) continue;
        if (c.contains('biel') ||
            c.contains('white') ||
            c.contains('svetl') ||
            c.contains('cream') ||
            c.contains('ivory') ||
            c.contains('krém') ||
            c.contains('krem')) {
          return true;
        }
      }
      return false;
    }

    ({double base, double warmth, double season, double rain}) footwearScoreParts(
      Map<String, dynamic> it,
    ) {
      final b = blob(it);
      final canonical = (it['canonical_type'] ?? it['canonicalType'] ?? '')
          .toString()
          .trim();

      final scoreBase = baseScore(it);
      var scoreRain = 0.0;
      var scoreWarmth = 0.0;
      var scoreSeason = 0.0;

      final warmthLevel = StylistLayerFilter.inferWarmthLevel(it);
      if (warmthLevel >= 6) {
        if (temp <= 8) {
          scoreWarmth += 1.5;
        } else if (temp >= 18) {
          scoreWarmth -= 3.0;
        } else if (temp >= 14) {
          scoreWarmth -= 2.0;
        }
      }

      if (isWarm && (b.contains('sandál') || b.contains('sandal'))) {
        scoreWarmth += 1.0;
      }

      final seasons = seasonTokens(it);
      if (seasonMentionsWinter(seasons) && temp >= 14) {
        scoreSeason -= 2.0;
      }
      if (seasonMentionsSummer(seasons) && temp <= 10) {
        scoreSeason -= 2.0;
      }

      if (weather.isRainy) {
        final bootLike = isBootFootwear(b, canonical);
        final sneakerLike = isSneakerFootwear(b, canonical);
        final heavyRain = weather.isHeavyRain;

        if (bootLike && (temp <= 12 || heavyRain)) {
          scoreRain += 1.0;
        }

        if (sneakerLike && temp > 12) {
          if (isWhiteOrLightFootwear(it, b)) {
            scoreRain -= 1.0;
          } else {
            scoreRain += 0.5;
          }
        }
      }

      return (
        base: scoreBase,
        warmth: scoreWarmth,
        season: scoreSeason,
        rain: scoreRain,
      );
    }

    double scoreShoes(Map<String, dynamic> it) {
      final p = footwearScoreParts(it);
      return p.base + p.warmth + p.season + p.rain;
    }

    double scoreBottom(Map<String, dynamic> it) {
      final b = blob(it);
      var s = baseScore(it);
      if (isWarm && (b.contains('krať') || b.contains('short'))) s += 1.0;
      return s;
    }

    double scoreOuter(Map<String, dynamic> it) {
      final b = blob(it);
      var s = baseScore(it);
      final warmth = StylistLayerFilter.inferWarmthLevel(it);
      final layer = StylistLayerFilter.resolveEffectiveLayerRole(it);

      if (isCold && warmth >= 7) s += 1.4;
      if (isCold && isHeavyOuterwear(it)) s += 1.2;
      if (isCold && layer == 'mid_layer') s += 0.35;
      if (isFreezing && warmth <= 5) s -= 1.1;
      if (isMild && isLightOuterwear(it)) s += 1.0;
      if (isWarm && warmth >= 7) s -= 1.5;
      if (isWarm && layer == 'mid_layer') s -= 0.6;
      if (weather.isRainy && b.contains('bunda')) s += 0.4;
      return s;
    }

    final topScore = baseScore(preview.top.item);
    final bottomScore = scoreBottom(preview.bottom.item);
    final shoesScore = scoreShoes(preview.shoes.item);
    final outerScore = preview.outerwear == null
        ? 0.0
        : scoreOuter(preview.outerwear!.item);

    return topScore + bottomScore + shoesScore + outerScore;
  }

  /// Consistency penalty used for logging (NOT used by generator).
  static double consistencyPenaltyForPreview({
    required OutfitPreview preview,
  }) {
    int warmthOf(Map<String, dynamic> it) {
      return StylistLayerFilter.inferWarmthLevel(it);
    }

    bool isShortsBottom(Map<String, dynamic> it) {
      final b = [
        (it['name'] ?? '').toString(),
        (it['category'] ?? it['categoryKey'] ?? '').toString(),
        (it['subCategory'] ?? it['subCategoryKey'] ?? '').toString(),
        (it['mainGroup'] ?? it['mainGroupKey'] ?? '').toString(),
      ].join(' ').toLowerCase();

      return b.contains('krať') ||
          b.contains('krat') ||
          b.contains('short') ||
          b.contains('sortk') ||
          b.contains('šortk');
    }

    List<String> seasonTokens(Map<String, dynamic> it) {
      final raw = it['seasons'] ?? it['season'];
      if (raw is List) {
        return raw
            .map((e) => e.toString().trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (raw is String && raw.trim().isNotEmpty) {
        return [raw.trim().toLowerCase()];
      }
      return const [];
    }

    bool seasonMentionsSummer(List<String> tokens) {
      return tokens.any((t) => t.contains('let') || t == 'leto' || t.contains('summer'));
    }

    bool isHeavyOuterwear(Map<String, dynamic> it) {
      final b = [
        (it['name'] ?? '').toString(),
        (it['category'] ?? it['categoryKey'] ?? '').toString(),
        (it['subCategory'] ?? it['subCategoryKey'] ?? '').toString(),
        (it['mainGroup'] ?? it['mainGroupKey'] ?? '').toString(),
      ].join(' ').toLowerCase();

      return b.contains('kabát') ||
          b.contains('kabat') ||
          b.contains('coat') ||
          b.contains('parka') ||
          b.contains('čiž') ||
          b.contains('ciz');
    }

    bool isWinterJacketOuter(Map<String, dynamic> outer) {
      final b = [
        (outer['name'] ?? '').toString(),
        (outer['category'] ?? outer['categoryKey'] ?? '').toString(),
        (outer['subCategory'] ?? outer['subCategoryKey'] ?? '').toString(),
        (outer['mainGroup'] ?? outer['mainGroupKey'] ?? '').toString(),
      ].join(' ').toLowerCase();
      final w = warmthOf(outer);
      if (w < 7) return false;
      return b.contains('zimn') ||
          b.contains('winter') ||
          b.contains('bunda_zimna') ||
          b.contains('bunda zimna') ||
          isHeavyOuterwear(outer);
    }

    bool isSummerShortsBottom(Map<String, dynamic> bottom) {
      if (!isShortsBottom(bottom)) return false;
      final w = warmthOf(bottom);
      if (w <= 3) return true;
      return seasonMentionsSummer(seasonTokens(bottom));
    }

    final topWarmth = warmthOf(preview.top.item);
    final bottomWarmth = warmthOf(preview.bottom.item);
    final footwearWarmth = warmthOf(preview.shoes.item);
    final outerWarmth = preview.outerwear == null ? null : warmthOf(preview.outerwear!.item);

    final warmths = <int>[topWarmth, bottomWarmth, footwearWarmth];
    if (outerWarmth != null) warmths.add(outerWarmth);

    final maxWarmth = warmths.reduce((a, b) => a > b ? a : b);
    final minWarmth = warmths.reduce((a, b) => a < b ? a : b);
    final warmthSpread = maxWarmth - minWarmth;

    const winterJacketShortsPenalty = -3.0;
    const heavyOuterSummerShortsPenalty = -2.5;
    const warmthSpreadPenalty = -2.0;
    const warmthSpreadThreshold = 5;

    var penaltyTotal = 0.0;

    final outerItem = preview.outerwear?.item;
    if (outerItem != null && isWinterJacketOuter(outerItem) && isShortsBottom(preview.bottom.item)) {
      penaltyTotal += winterJacketShortsPenalty;
    }

    if (outerItem != null && isSummerShortsBottom(preview.bottom.item) &&
        (isHeavyOuterwear(outerItem) || warmthOf(outerItem) >= 7)) {
      penaltyTotal += heavyOuterSummerShortsPenalty;
    }

    if (warmthSpread >= warmthSpreadThreshold) {
      penaltyTotal += warmthSpreadPenalty;
    }

    return penaltyTotal;
  }
}

