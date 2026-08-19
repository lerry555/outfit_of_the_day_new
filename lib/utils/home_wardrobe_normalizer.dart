import 'package:flutter/foundation.dart';

import '../data/clothing_knowledge_base.dart';
import 'canonical_resolver.dart';
import 'home_debug_logging.dart';
import 'stylist_layer_filter.dart';
import 'wardrobe_image_url_priority.dart';

/// Lightweight runtime wardrobe item for Home Brain (KB overrides legacy Firestore fields).
class HomeNormalizedWardrobeItem {
  const HomeNormalizedWardrobeItem({
    required this.id,
    required this.name,
    required this.canonicalType,
    required this.skName,
    required this.categoryKey,
    required this.subCategoryKey,
    required this.layerRole,
    required this.warmthLevel,
    required this.formality,
    required this.colors,
    required this.baseColors,
    required this.seasons,
    required this.imageUrl,
    required this.cleanImageUrl,
    required this.productImageUrl,
    required this.kbApplied,
    required this.legacyFallbackApplied,
    required this.raw,
  });

  final String id;
  final String name;
  final String canonicalType;
  final String skName;
  final String categoryKey;
  final String subCategoryKey;
  final String layerRole;
  final int warmthLevel;
  final int formality;
  final List<String> colors;
  final List<String> baseColors;
  final List<String> seasons;
  final String? imageUrl;
  final String? cleanImageUrl;
  final String? productImageUrl;
  final bool kbApplied;
  final bool legacyFallbackApplied;
  final Map<String, dynamic> raw;

  /// Map for existing Home / outfit code paths (same shape as Firestore + KB fields).
  Map<String, dynamic> toOutfitMap() {
    final m = Map<String, dynamic>.from(raw);
    if (id.isNotEmpty) m['id'] = id;
    if (name.isNotEmpty) m['name'] = name;
    m['canonical_type'] = canonicalType;
    m['canonicalType'] = canonicalType;
    if (skName.isNotEmpty) {
      m['type_pretty'] = skName;
      m['typePretty'] = skName;
    }
    if (kbApplied && canonicalType.isNotEmpty) {
      final kb = ClothingKnowledgeBase.findByCanonicalType(canonicalType);
      if (kb != null) {
        m['mainGroupKey'] = kb.mainCategory;
      }
    } else if (legacyFallbackApplied) {
      final main = HomeWardrobeNormalizer.mainGroupForLegacyCategory(categoryKey);
      if (main.isNotEmpty) m['mainGroupKey'] = main;
    }
    m['mainGroup'] =
        (m['mainGroupKey'] ?? m['mainGroup'] ?? '').toString();
    m['categoryKey'] = categoryKey;
    m['category'] = categoryKey;
    m['subCategoryKey'] = subCategoryKey;
    m['subCategory'] = subCategoryKey;
    m['layer_role'] = layerRole;
    m['layerRole'] = layerRole;
    m['warmth_level'] = warmthLevel;
    m['warmthLevel'] = warmthLevel;
    m['formality'] = formality;
    m['colors'] = colors;
    m['color'] = colors;
    m['baseColors'] = baseColors;
    m['seasons'] = seasons;
    m['season'] = seasons;
    if (imageUrl != null && imageUrl!.isNotEmpty) m['imageUrl'] = imageUrl;
    if (cleanImageUrl != null && cleanImageUrl!.isNotEmpty) {
      m['cleanImageUrl'] = cleanImageUrl;
    }
    if (productImageUrl != null && productImageUrl!.isNotEmpty) {
      m['productImageUrl'] = productImageUrl;
    }
    m['home_kb_applied'] = kbApplied;
    m['home_legacy_fallback'] = legacyFallbackApplied;
    return m;
  }
}

class _LegacyFallbackResult {
  const _LegacyFallbackResult({
    required this.matched,
    required this.layerRole,
    required this.categoryKey,
    required this.subCategoryKey,
    required this.source,
  });

  final bool matched;
  final String layerRole;
  final String categoryKey;
  final String subCategoryKey;
  final String source;
}

/// Normalizes wardrobe for Home using [ClothingKnowledgeBase] only.
abstract final class HomeWardrobeNormalizer {
  static final Set<String> _loggedKbMatchKeys = <String>{};
  static final Set<String> _loggedKbNoMatchKeys = <String>{};
  static final Set<String> _loggedFallbackMatchKeys = <String>{};
  static final Set<String> _loggedNormalizedKeys = <String>{};
  static final Set<String> _loggedCanonicalResolverKeys = <String>{};
  static final Set<String> _loggedKbRuntimeResolutionKeys = <String>{};
  static String? _lastSummarySig;
  static String? _lastRuntimeSummarySig;

  static const Set<String> _knownLayers = {
    'base_layer',
    'mid_layer',
    'outer_layer',
    'bottom',
    'footwear',
    'accessory',
  };

  /// subCategoryKey / categoryKey (normalized) → layer_role for pre-KB wardrobe items.
  static const Map<String, String> _legacySubLayerByKey = {
    'tricko': ClothingLayerRole.baseLayer,
    'trickodlhyrukav': ClothingLayerRole.baseLayer,
    'tielko': ClothingLayerRole.baseLayer,
    'undershirt': ClothingLayerRole.baseLayer,
    'topbasic': ClothingLayerRole.baseLayer,
    'croptop': ClothingLayerRole.baseLayer,
    'polotricko': ClothingLayerRole.baseLayer,
    'sporttricko': ClothingLayerRole.baseLayer,
    'kosela': ClothingLayerRole.baseLayer,
    'koselaklasicka': ClothingLayerRole.baseLayer,
    'koselaoxford': ClothingLayerRole.baseLayer,
    'koselaoversize': ClothingLayerRole.baseLayer,
    'bluzka': ClothingLayerRole.baseLayer,
    'mikina': ClothingLayerRole.midLayer,
    'mikinaklasicka': ClothingLayerRole.midLayer,
    'mikinanazips': ClothingLayerRole.midLayer,
    'mikinaskapucnou': ClothingLayerRole.midLayer,
    'mikinaoversize': ClothingLayerRole.midLayer,
    'sportmikina': ClothingLayerRole.midLayer,
    'flisovabunda': ClothingLayerRole.midLayer,
    'sveterklasicky': ClothingLayerRole.midLayer,
    'sveterrolak': ClothingLayerRole.midLayer,
    'sveterkardigan': ClothingLayerRole.midLayer,
    'sveterpleteny': ClothingLayerRole.midLayer,
    'treningovabunda': ClothingLayerRole.midLayer,
    'bunda_prechodna': ClothingLayerRole.midLayer,
    'bundaprechodna': ClothingLayerRole.midLayer,
    'bundabomber': ClothingLayerRole.midLayer,
    'softshellbunda': ClothingLayerRole.midLayer,
    'bunda': ClothingLayerRole.outerLayer,
    'bundariflova': ClothingLayerRole.outerLayer,
    'bundakozena': ClothingLayerRole.outerLayer,
    'bundazimna': ClothingLayerRole.outerLayer,
    'kabat': ClothingLayerRole.outerLayer,
    'trenchcoat': ClothingLayerRole.outerLayer,
    'sako': ClothingLayerRole.outerLayer,
    'vesta': ClothingLayerRole.outerLayer,
    'prsiplast': ClothingLayerRole.outerLayer,
    'rifle': ClothingLayerRole.bottom,
    'rifleskinny': ClothingLayerRole.bottom,
    'riflewideleg': ClothingLayerRole.bottom,
    'riflemom': ClothingLayerRole.bottom,
    'nohavice': ClothingLayerRole.bottom,
    'nohaviceklasicke': ClothingLayerRole.bottom,
    'nohavicetelasne': ClothingLayerRole.bottom,
    'nohavicecargo': ClothingLayerRole.bottom,
    'sortky': ClothingLayerRole.bottom,
    'sortkysukne': ClothingLayerRole.bottom,
    'sukna': ClothingLayerRole.bottom,
    'suknamini': ClothingLayerRole.bottom,
    'suknamidi': ClothingLayerRole.bottom,
    'suknamaxi': ClothingLayerRole.bottom,
    'tenisky': ClothingLayerRole.footwear,
    'teniskyfashion': ClothingLayerRole.footwear,
    'teniskysportove': ClothingLayerRole.footwear,
    'teniskybezecke': ClothingLayerRole.footwear,
    'cizmy': ClothingLayerRole.footwear,
    'cizmyclenkove': ClothingLayerRole.footwear,
    'cizmychelsea': ClothingLayerRole.footwear,
    'topanky': ClothingLayerRole.footwear,
    'topankymokasiny': ClothingLayerRole.footwear,
    'topankylesadlo': ClothingLayerRole.footwear,
    'sandale': ClothingLayerRole.footwear,
    'sportobuv': ClothingLayerRole.footwear,
    'ciapka': ClothingLayerRole.accessory,
    'sal': ClothingLayerRole.accessory,
    'rukavice': ClothingLayerRole.accessory,
    'opasok': ClothingLayerRole.accessory,
    'okuliare': ClothingLayerRole.accessory,
  };

  static const Map<String, String> _legacyCategoryLayerByKey = {
    'trickatopy': ClothingLayerRole.baseLayer,
    'kosele': ClothingLayerRole.baseLayer,
    'mikiny': ClothingLayerRole.midLayer,
    'svetre': ClothingLayerRole.midLayer,
    'bundykabaty': ClothingLayerRole.outerLayer,
    'nohavice': ClothingLayerRole.bottom,
    'nohavicerifle': ClothingLayerRole.bottom,
    'sortkysukne': ClothingLayerRole.bottom,
    'tenisky': ClothingLayerRole.footwear,
    'cizmy': ClothingLayerRole.footwear,
    'topanky': ClothingLayerRole.footwear,
    'doplnky': ClothingLayerRole.accessory,
    'sport': ClothingLayerRole.midLayer,
    'obuv': ClothingLayerRole.footwear,
    'oblecenie': ClothingLayerRole.baseLayer,
  };

  /// Normalize full wardrobe once before Home outfit generation; logs summary once per wardrobe sig.
  static List<Map<String, dynamic>> normalizeWardrobeForHome(
    List<Map<String, dynamic>> rawItems, {
    bool log = true,
  }) {
    var beforeKb = 0;
    var beforeLegacy = 0;
    var afterKb = 0;
    var afterLegacy = 0;

    final items = <Map<String, dynamic>>[];
    for (final raw in rawItems) {
      if (kRuntimeCanonicalResolverEnabled && log && kDebugMode) {
        final before = _normalizeInternal(
          raw,
          enableRuntimeResolver: false,
          log: false,
        );
        if (before.kbApplied) beforeKb++;
        if (before.legacyFallbackApplied) beforeLegacy++;
      }

      final item = _normalizeInternal(
        raw,
        enableRuntimeResolver: kRuntimeCanonicalResolverEnabled,
        log: log,
      );
      if (item.kbApplied) afterKb++;
      if (item.legacyFallbackApplied) afterLegacy++;
      items.add(item.toOutfitMap());
    }

    if (log && kDebugMode) {
      _logSummaryOnce(items);
      if (kRuntimeCanonicalResolverEnabled) {
        _logKbRuntimeSummaryOnce(
          beforeKb: beforeKb,
          afterKb: afterKb,
          beforeLegacy: beforeLegacy,
          afterLegacy: afterLegacy,
          items: items,
        );
      }
    }
    return items;
  }

  static HomeNormalizedWardrobeItem normalize(
    Map<String, dynamic> raw, {
    bool log = true,
  }) {
    return _normalizeInternal(
      raw,
      enableRuntimeResolver: kRuntimeCanonicalResolverEnabled,
      log: log,
    );
  }

  static HomeNormalizedWardrobeItem _normalizeInternal(
    Map<String, dynamic> raw, {
    required bool enableRuntimeResolver,
    bool log = true,
  }) {
    final id = _wardrobeId(raw);
    final name = _firstNonEmpty([
      raw['name'],
      raw['title'],
      raw['type_pretty'],
      raw['typePretty'],
    ]);

    final explicitCanonical = _explicitCanonicalType(raw);
    if (explicitCanonical.isNotEmpty) {
      final kb = ClothingKnowledgeBase.resolveClothingType(
        canonicalType: explicitCanonical,
        primaryType: _firstNonEmpty([raw['primary_type'], raw['primaryType']]),
        typePretty: _firstNonEmpty([raw['type_pretty'], raw['typePretty']]),
        type: (raw['type'] ?? '').toString(),
      );
      if (kb != null) {
        _logKbMatchOnce(log: log, id: id, item: kb);
        final item = _applyTankTopOverride(
          item: _fromKb(raw: raw, id: id, name: name, kb: kb),
          log: log,
        );
        _logNormalizedOnce(log: log, item: item);
        return item;
      }
    }

    if (enableRuntimeResolver) {
      final resolution = CanonicalResolver.resolve(raw, name: name);
      if (resolution != null) {
        _logCanonicalResolverOnce(
          log: log,
          id: id,
          name: name,
          resolution: resolution,
        );
        final kb = ClothingKnowledgeBase.findByCanonicalType(
              resolution.canonicalType,
            ) ??
            ClothingKnowledgeBase.resolveClothingType(
              canonicalType: resolution.canonicalType,
            );
        if (kb != null) {
          final withoutResolver = _normalizeInternal(
            raw,
            enableRuntimeResolver: false,
            log: false,
          );
          if (!withoutResolver.kbApplied) {
            _logKbRuntimeResolutionOnce(
              log: log,
              id: id,
              name: name,
            );
          }
          _logKbMatchOnce(log: log, id: id, item: kb);
          final item = _applyTankTopOverride(
            item: _fromKb(raw: raw, id: id, name: name, kb: kb),
            log: log,
          );
          _logNormalizedOnce(log: log, item: item);
          return item;
        }
      }
    }

    final categoryKey =
        _firstNonEmpty([raw['categoryKey'], raw['category']]);
    final subCategoryKey =
        _firstNonEmpty([raw['subCategoryKey'], raw['subCategory']]);
    final fallback = _classifyLegacyFallback(
      raw: raw,
      name: name,
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
    );

    if (fallback.matched) {
      _logFallbackMatchOnce(
        log: log,
        id: id,
        name: name,
        result: fallback,
      );
      final item = _applyTankTopOverride(
        item: _fromLegacyFallback(
          raw: raw,
          id: id,
          name: name,
          result: fallback,
        ),
        log: log,
      );
      _logNormalizedOnce(log: log, item: item);
      return item;
    }

    _logKbNoMatchOnce(
      log: log,
      id: id,
      name: name,
      raw: raw,
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
    );
    final item = _applyTankTopOverride(
      item: _fromLegacyUnmatched(raw: raw, id: id, name: name),
      log: log,
    );
    _logNormalizedOnce(log: log, item: item);
    return item;
  }

  static bool _isTankTopCandidate({
    required Map<String, dynamic> raw,
    required String name,
    required String subCategoryKey,
    required String canonicalType,
  }) {
    if (StylistLayerFilter.isTankTopItem({
      ...raw,
      'name': name,
      'subCategoryKey': subCategoryKey,
      'subCategory': subCategoryKey,
      'canonical_type': canonicalType,
      'canonicalType': canonicalType,
    })) {
      return true;
    }
    return _norm(subCategoryKey) == 'tielko' ||
        (_norm(canonicalType) == 'tank_top' || _norm(canonicalType) == 'tanktop') ||
        (_norm(name).contains('tielko') &&
            !_norm(name).contains('spodne tielko') &&
            !_norm(name).contains('spodné tielko'));
  }

  static HomeNormalizedWardrobeItem _applyTankTopOverride({
    required HomeNormalizedWardrobeItem item,
    required bool log,
  }) {
    if (!_isTankTopCandidate(
      raw: item.raw,
      name: item.name,
      subCategoryKey: item.subCategoryKey,
      canonicalType: item.canonicalType,
    )) {
      return item;
    }

    final oldWarmth = item.warmthLevel;
    final kb = ClothingKnowledgeBase.findByCanonicalType('tank_top');
    final patched = HomeNormalizedWardrobeItem(
      id: item.id,
      name: item.name,
      canonicalType: 'tank_top',
      skName: item.skName.isNotEmpty
          ? item.skName
          : (kb?.skName ?? 'Tielko'),
      categoryKey: item.categoryKey.isNotEmpty
          ? item.categoryKey
          : (kb?.category ?? 'tricka_topy'),
      subCategoryKey: item.subCategoryKey.isNotEmpty
          ? item.subCategoryKey
          : (kb?.subcategory ?? 'tielko'),
      layerRole: ClothingLayerRole.baseLayer,
      warmthLevel: 1,
      formality: item.formality,
      colors: item.colors,
      baseColors: item.baseColors,
      seasons: item.seasons,
      imageUrl: item.imageUrl,
      cleanImageUrl: item.cleanImageUrl,
      productImageUrl: item.productImageUrl,
      kbApplied: item.kbApplied || kb != null,
      legacyFallbackApplied: item.legacyFallbackApplied,
      raw: item.raw,
    );

    if (log && kDebugMode && kVerboseHomeLogs) {
      logVerboseHome(
        '[TANK_TOP_NORMALIZED] '
        'itemId=${item.id.isEmpty ? 'unknown' : item.id} '
        'name=${item.name} '
        'oldWarmth=$oldWarmth '
        'newWarmth=1 '
        'source=override',
      );
    }
    return patched;
  }

  static String _explicitCanonicalType(Map<String, dynamic> raw) {
    final direct = _firstNonEmpty([
      raw['canonical_type'],
      raw['canonicalType'],
    ]);
    if (direct.isNotEmpty) return direct;
    return ClothingKnowledgeBase.itemCanonicalType(raw) ?? '';
  }

  static HomeNormalizedWardrobeItem _fromKb({
    required Map<String, dynamic> raw,
    required String id,
    required String name,
    required ClothingKbItem kb,
  }) {
    return HomeNormalizedWardrobeItem(
      id: id,
      name: name.isNotEmpty ? name : kb.skName,
      canonicalType: kb.canonicalType,
      skName: kb.skName,
      categoryKey: kb.category,
      subCategoryKey: kb.subcategory,
      layerRole: kb.layerRole,
      warmthLevel: kb.warmthDefault,
      formality: kb.formalityDefault,
      colors: _stringList(raw['colors'] ?? raw['color']),
      baseColors: _stringList(raw['baseColors']),
      seasons: _stringList(raw['seasons'] ?? raw['season']),
      imageUrl: _getStr(raw, 'imageUrl'),
      cleanImageUrl: _getStr(raw, 'cleanImageUrl'),
      productImageUrl: _getStr(raw, 'productImageUrl') ??
          resolveWardrobeImageUrl(raw),
      kbApplied: true,
      legacyFallbackApplied: false,
      raw: raw,
    );
  }

  static HomeNormalizedWardrobeItem _fromLegacyFallback({
    required Map<String, dynamic> raw,
    required String id,
    required String name,
    required _LegacyFallbackResult result,
  }) {
    return HomeNormalizedWardrobeItem(
      id: id,
      name: name,
      canonicalType: '',
      skName: _firstNonEmpty([raw['type_pretty'], raw['typePretty'], name]),
      categoryKey: result.categoryKey,
      subCategoryKey: result.subCategoryKey,
      layerRole: result.layerRole,
      warmthLevel: _parseWarmth(raw) ?? _defaultWarmthForLayer(result.layerRole),
      formality: _parseFormality(raw) ?? 5,
      colors: _stringList(raw['colors'] ?? raw['color']),
      baseColors: _stringList(raw['baseColors']),
      seasons: _stringList(raw['seasons'] ?? raw['season']),
      imageUrl: _getStr(raw, 'imageUrl'),
      cleanImageUrl: _getStr(raw, 'cleanImageUrl'),
      productImageUrl: _getStr(raw, 'productImageUrl') ??
          resolveWardrobeImageUrl(raw),
      kbApplied: false,
      legacyFallbackApplied: true,
      raw: raw,
    );
  }

  static HomeNormalizedWardrobeItem _fromLegacyUnmatched({
    required Map<String, dynamic> raw,
    required String id,
    required String name,
  }) {
    final categoryKey =
        _firstNonEmpty([raw['categoryKey'], raw['category']]);
    final subCategoryKey =
        _firstNonEmpty([raw['subCategoryKey'], raw['subCategory']]);
    return HomeNormalizedWardrobeItem(
      id: id,
      name: name,
      canonicalType: _firstNonEmpty([raw['type'], raw['primary_type']]),
      skName: _firstNonEmpty([raw['type_pretty'], raw['typePretty'], name]),
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
      layerRole: _layerRoleFromStoredFields(raw),
      warmthLevel: _parseWarmth(raw) ?? 5,
      formality: _parseFormality(raw) ?? 5,
      colors: _stringList(raw['colors'] ?? raw['color']),
      baseColors: _stringList(raw['baseColors']),
      seasons: _stringList(raw['seasons'] ?? raw['season']),
      imageUrl: _getStr(raw, 'imageUrl'),
      cleanImageUrl: _getStr(raw, 'cleanImageUrl'),
      productImageUrl: _getStr(raw, 'productImageUrl') ??
          resolveWardrobeImageUrl(raw),
      kbApplied: false,
      legacyFallbackApplied: false,
      raw: raw,
    );
  }

  static _LegacyFallbackResult _classifyLegacyFallback({
    required Map<String, dynamic> raw,
    required String name,
    required String categoryKey,
    required String subCategoryKey,
  }) {
    final stored = _layerRoleFromStoredFields(raw);
    if (stored.isNotEmpty) {
      return _LegacyFallbackResult(
        matched: true,
        layerRole: stored,
        categoryKey: categoryKey,
        subCategoryKey: subCategoryKey,
        source: 'layer_role',
      );
    }

    final subNorm = _normalizeLegacyKey(subCategoryKey);
    if (subNorm.isNotEmpty) {
      final layer = _legacySubLayerByKey[subNorm] ?? _layerFromLegacyToken(subNorm);
      if (layer != null) {
        return _LegacyFallbackResult(
          matched: true,
          layerRole: layer,
          categoryKey: categoryKey,
          subCategoryKey: subCategoryKey,
          source: 'subCategory',
        );
      }
    }

    final catNorm = _normalizeLegacyKey(categoryKey);
    if (catNorm.isNotEmpty) {
      final layer =
          _legacyCategoryLayerByKey[catNorm] ?? _layerFromLegacyToken(catNorm);
      if (layer != null) {
        return _LegacyFallbackResult(
          matched: true,
          layerRole: layer,
          categoryKey: categoryKey,
          subCategoryKey: subCategoryKey,
          source: 'category',
        );
      }
    }

    final nameNorm = _normalizeLegacyKey(name);
    if (nameNorm.isNotEmpty) {
      final layer = _layerFromLegacyToken(nameNorm);
      if (layer != null) {
        return _LegacyFallbackResult(
          matched: true,
          layerRole: layer,
          categoryKey: categoryKey,
          subCategoryKey: subCategoryKey,
          source: 'name',
        );
      }
    }

    return const _LegacyFallbackResult(
      matched: false,
      layerRole: '',
      categoryKey: '',
      subCategoryKey: '',
      source: '',
    );
  }

  static String? _layerFromLegacyToken(String token) {
    if (token.contains('tenisk') ||
        token.contains('sneaker') ||
        token.contains('cizm') ||
        token.contains('topank') ||
        token.contains('obuv') ||
        token.contains('sand') ||
        token.contains('mokas')) {
      return ClothingLayerRole.footwear;
    }
    if (token.contains('rifl') ||
        token.contains('nohav') ||
        token.contains('sortk') ||
        token.contains('sukn') ||
        token.contains('krat') ||
        token.contains('jeans') ||
        token.contains('pants')) {
      return ClothingLayerRole.bottom;
    }
    if (token.contains('kabat') ||
        (token.contains('bunda') && !token.contains('trening')) ||
        token.contains('coat') ||
        token.contains('parka') ||
        token.contains('trench') ||
        token.contains('sako') ||
        token.contains('blazer')) {
      return ClothingLayerRole.outerLayer;
    }
    if (token.contains('mikina') ||
        token.contains('hoodie') ||
        token.contains('sveter') ||
        token.contains('sweater') ||
        token.contains('trening') ||
        token.contains('flis')) {
      return ClothingLayerRole.midLayer;
    }
    if (token.contains('trick') ||
        token.contains('tielk') ||
        token.contains('kosel') ||
        token.contains('bluz') ||
        token.contains('shirt') ||
        token.contains('top')) {
      return ClothingLayerRole.baseLayer;
    }
    if (token.contains('ciap') ||
        token.contains('sal') ||
        token.contains('rukav') ||
        token.contains('opas') ||
        token.contains('okuliar') ||
        token.contains('dopln')) {
      return ClothingLayerRole.accessory;
    }
    return null;
  }

  static String _layerRoleFromStoredFields(Map<String, dynamic> raw) {
    final v2 = _norm((raw['layer_role'] ?? raw['stylingLayerRole'] ?? '').toString());
    if (_knownLayers.contains(v2)) return v2;
    final app = _norm((raw['layerRole'] ?? '').toString());
    if (_knownLayers.contains(app)) return app;
    return '';
  }

  static int _defaultWarmthForLayer(String layer) {
    switch (layer) {
      case ClothingLayerRole.baseLayer:
        return 3;
      case ClothingLayerRole.midLayer:
        return 5;
      case ClothingLayerRole.outerLayer:
        return 7;
      case ClothingLayerRole.bottom:
        return 4;
      case ClothingLayerRole.footwear:
        return 4;
      case ClothingLayerRole.accessory:
        return 2;
      default:
        return 5;
    }
  }

  static String mainGroupForLegacyCategory(String categoryKey) {
    final c = _normalizeLegacyKey(categoryKey);
    if (c.contains('obuv') ||
        c == 'tenisky' ||
        c == 'cizmy' ||
        c == 'topanky') {
      return ClothingKnowledgeBase.mainObuv;
    }
    if (c == 'doplnky') return ClothingKnowledgeBase.mainDoplnky;
    return ClothingKnowledgeBase.mainOblecenie;
  }

  static void _logCanonicalResolverOnce({
    required bool log,
    required String id,
    required String name,
    required CanonicalResolution resolution,
  }) {
    if (!log || !kDebugMode || !kVerboseHomeLogs) return;
    final key = '$id|${resolution.canonicalType}|${resolution.source}';
    if (!_loggedCanonicalResolverKeys.add(key)) return;
    logVerboseHome(
      '[CANONICAL_RESOLVER] '
      'item=${name.isEmpty ? id : name} '
      'resolvedCanonical=${resolution.canonicalType} '
      'confidence=${resolution.confidence} '
      'source=${resolution.source}',
    );
  }

  static void _logKbRuntimeResolutionOnce({
    required bool log,
    required String id,
    required String name,
  }) {
    if (!log || !kDebugMode || !kVerboseHomeLogs) return;
    final key = id.isEmpty ? name : id;
    if (key.isEmpty) return;
    if (!_loggedKbRuntimeResolutionKeys.add(key)) return;
    logVerboseHome(
      '[KB_RUNTIME_RESOLUTION] '
      'item=${name.isEmpty ? id : name} '
      'oldPath=legacy '
      'newPath=kb',
    );
  }

  static void _logKbRuntimeSummaryOnce({
    required int beforeKb,
    required int afterKb,
    required int beforeLegacy,
    required int afterLegacy,
    required List<Map<String, dynamic>> items,
  }) {
    if (!kDebugMode || !kVerboseHomeLogs) return;
    final sig = '${items.length}:${items.map((e) => e['id']).join(',')}';
    if (_lastRuntimeSummarySig == sig) return;
    _lastRuntimeSummarySig = sig;

    logVerboseHome(
      '[KB_RUNTIME_SUMMARY] '
      'beforeKb=$beforeKb '
      'afterKb=$afterKb '
      'beforeLegacy=$beforeLegacy '
      'afterLegacy=$afterLegacy',
    );
  }

  static void _logSummaryOnce(List<Map<String, dynamic>> items) {
    if (!kDebugMode || !kVerboseHomeLogs) return;
    final sig = '${items.length}:${items.map((e) => e['id']).join(',')}';
    if (_lastSummarySig == sig) return;
    _lastSummarySig = sig;

    final counts = <String, int>{
      'base_layer': 0,
      'mid_layer': 0,
      'outer_layer': 0,
      'bottom': 0,
      'footwear': 0,
      'accessory': 0,
      'no_match': 0,
      'kb': 0,
      'legacy_fallback': 0,
    };
    final samples = <Map<String, dynamic>>[];

    for (final m in items) {
      if (m['home_kb_applied'] == true) counts['kb'] = counts['kb']! + 1;
      if (m['home_legacy_fallback'] == true) {
        counts['legacy_fallback'] = counts['legacy_fallback']! + 1;
      }
      final layer = (m['layer_role'] ?? '').toString();
      if (_knownLayers.contains(layer)) {
        counts[layer] = (counts[layer] ?? 0) + 1;
      } else {
        counts['no_match'] = counts['no_match']! + 1;
      }
      if (samples.length < 4) samples.add(m);
    }

    logVerboseHome(
      '[HOME_KB_SUMMARY] base_layer=${counts['base_layer']} '
      'mid_layer=${counts['mid_layer']} outer_layer=${counts['outer_layer']} '
      'bottom=${counts['bottom']} footwear=${counts['footwear']} '
      'accessory=${counts['accessory']} no_match=${counts['no_match']} '
      'kb=${counts['kb']} legacy_fallback=${counts['legacy_fallback']}',
    );
    for (final s in samples) {
      logVerboseHome(
        '[HOME_KB_SAMPLE] name=${s['name']} canonicalType=${s['canonical_type']} '
        'layerRole=${s['layer_role']} categoryKey=${s['categoryKey']} '
        'subCategoryKey=${s['subCategoryKey']} kb=${s['home_kb_applied']} '
        'legacy=${s['home_legacy_fallback']}',
      );
    }
  }

  static void _logKbMatchOnce({
    required bool log,
    required String id,
    required ClothingKbItem item,
  }) {
    if (!log || !kDebugMode || !kVerboseHomeLogs) return;
    final key = '$id|${item.canonicalType}';
    if (!_loggedKbMatchKeys.add(key)) return;
    logVerboseHome(
      '[HOME_KB_MATCH] item=$id canonical=${item.canonicalType} '
      'sk=${item.skName} layer=${item.layerRole} warmth=${item.warmthDefault} '
      'formality=${item.formalityDefault} source=kb',
    );
  }

  static void _logFallbackMatchOnce({
    required bool log,
    required String id,
    required String name,
    required _LegacyFallbackResult result,
  }) {
    if (!log || !kDebugMode || !kVerboseHomeLogs) return;
    final key = '$id|${result.subCategoryKey}|${result.categoryKey}';
    if (!_loggedFallbackMatchKeys.add(key)) return;
    debugPrint(
      '[HOME_KB_FALLBACK_MATCH] item=$id name=$name source=${result.source} '
      'layer=${result.layerRole} categoryKey=${result.categoryKey} '
      'subCategoryKey=${result.subCategoryKey}',
    );
  }

  static void _logKbNoMatchOnce({
    required bool log,
    required String id,
    required String name,
    required Map<String, dynamic> raw,
    required String categoryKey,
    required String subCategoryKey,
  }) {
    if (!log || !kDebugMode || !kVerboseHomeLogs) return;
    final key = '$id|$name|$categoryKey|$subCategoryKey';
    if (!_loggedKbNoMatchKeys.add(key)) return;
    logVerboseHome(
      '[HOME_KB_NO_MATCH] item=$id name=$name type=${raw['type'] ?? ''} '
      'category=$categoryKey subCategory=$subCategoryKey',
    );
  }

  static void _logNormalizedOnce({
    required bool log,
    required HomeNormalizedWardrobeItem item,
  }) {
    if (!log || !kDebugMode || !kVerboseHomeLogs) return;
    final key = '${item.id}|${item.canonicalType}|${item.layerRole}|${item.legacyFallbackApplied}';
    if (!_loggedNormalizedKeys.add(key)) return;
    debugPrint(
      '[HOME_NORMALIZED_ITEM] name=${item.name} layerRole=${item.layerRole} '
      'categoryKey=${item.categoryKey} subCategoryKey=${item.subCategoryKey} '
      'warmth=${item.warmthLevel} kb=${item.kbApplied} legacy=${item.legacyFallbackApplied}',
    );
  }

  static String _normalizeLegacyKey(String raw) {
    var out = raw.trim().toLowerCase();
    if (out.isEmpty) return '';

    const repl = {
      'á': 'a',
      'ä': 'a',
      'č': 'c',
      'ď': 'd',
      'é': 'e',
      'ě': 'e',
      'í': 'i',
      'ĺ': 'l',
      'ľ': 'l',
      'ň': 'n',
      'ó': 'o',
      'ô': 'o',
      'ŕ': 'r',
      'ř': 'r',
      'š': 's',
      'ť': 't',
      'ú': 'u',
      'ů': 'u',
      'ü': 'u',
      'ý': 'y',
      'ž': 'z',
    };

    final buffer = StringBuffer();
    for (final ch in out.split('')) {
      buffer.write(repl[ch] ?? ch);
    }
    out = buffer.toString();
    out = out.replaceAll(RegExp(r'[\s_\-/]+'), '');
    return out;
  }

  static String _wardrobeId(Map<String, dynamic> raw) {
    final v = raw['id'] ?? raw['documentId'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? '' : s;
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    return const [];
  }

  static String? _getStr(Map<String, dynamic> item, String key) {
    final v = item[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int? _parseWarmth(Map<String, dynamic> raw) {
    final n = num.tryParse(
      (raw['warmth_level'] ?? raw['warmthLevel'] ?? raw['warmth'] ?? '')
          .toString(),
    );
    if (n == null || !n.isFinite) return null;
    return n.round().clamp(1, 10);
  }

  static int? _parseFormality(Map<String, dynamic> raw) {
    final n = num.tryParse((raw['formality'] ?? '').toString());
    if (n == null || !n.isFinite) return null;
    return n.round().clamp(1, 10);
  }

  static String _norm(String s) => s.toLowerCase().trim();
}
