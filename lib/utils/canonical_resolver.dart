import '../data/clothing_knowledge_base.dart';

/// Runtime-only canonical type resolution for Home KB-first normalization.
///
/// Does not read or write Firestore; derives [canonicalType] from wardrobe fields.
class CanonicalResolution {
  final String canonicalType;
  final int confidence;
  final String source;

  const CanonicalResolution({
    required this.canonicalType,
    required this.confidence,
    required this.source,
  });
}

abstract final class CanonicalResolver {
  CanonicalResolver._();

  /// categoryKey|subCategoryKey (normalized) → default canonical when sub alone is ambiguous.
  static const Map<String, String> _categorySubCanonical = <String, String>{
    'trickatopy|tricko': 't_shirt',
    'trickatopy|trickodlhyrukav': 'long_sleeve_t_shirt',
    'trickatopy|tielko': 'tank_top',
    'trickatopy|polotricko': 'polo_shirt',
    'trickatopy|croptop': 'crop_top',
    'trickatopy|topbasic': 't_shirt',
    'trickatopy|sporttricko': 'training_top',
    'mikiny|mikinaklasicka': 'sweatshirt',
    'mikiny|mikinaskapucnou': 'hoodie',
    'mikiny|mikinanazips': 'zip_hoodie',
    'mikiny|mikinaoversize': 'sweatshirt',
    'mikiny|sportmikina': 'training_top',
    'mikiny|mikina': 'sweatshirt',
    'nohavicerifle|rifle': 'jeans',
    'nohavicerifle|rifleskinny': 'skinny_jeans',
    'nohavicerifle|riflewideleg': 'wide_leg_pants',
    'nohavicerifle|riflemom': 'jeans',
    'nohavicerifle|nohaviceklasicke': 'chinos',
    'nohavicerifle|nohavicecargo': 'cargo_pants',
    'nohavicerifle|nohavicetelasne': 'leggings',
    'nohavicerifle|nohavice': 'chinos',
    'nohavice|nohaviceklasicke': 'chinos',
    'sortkysukne|sortky': 'shorts',
    'sortkysukne|sortkysportove': 'sport_shorts',
    'tenisky|tenisky': 'sneakers',
    'tenisky|teniskyfashion': 'sneakers',
    'tenisky|teniskysportove': 'basketball_shoes',
    'tenisky|teniskybezecke': 'running_shoes',
    'bundykabaty|bundaprechodna': 'light_jacket',
    'bundykabaty|bunda_prechodna': 'light_jacket',
    'bundykabaty|bundabomber': 'bomber_jacket',
    'bundykabaty|bundazimna': 'winter_jacket',
    'bundykabaty|bunda_zimna': 'winter_jacket',
    'bundykabaty|bunda': 'light_jacket',
    'bundykabaty|kabat': 'overcoat',
    'bundykabaty|trenchcoat': 'trench_coat',
    'bundykabaty|prsiplast': 'rain_jacket',
    'bundykabaty|softshellbunda': 'softshell',
    'svetre|sveterklasicky': 'sweater',
    'svetre|sveterkardigan': 'cardigan',
    'svetre|sveterrolak': 'turtleneck',
    'kosele|koselaklasicka': 'dress_shirt',
    'kosele|koselaoxford': 'dress_shirt',
    'cizmy|cizmyclenkove': 'chelsea_boots',
    'cizmy|cizmychelsea': 'chelsea_boots',
    'topanky|topankymokasiny': 'loafers',
    'obuv|tenisky': 'sneakers',
  };

  /// Resolve canonical type: subCategory → category+sub map → typePretty → name.
  static CanonicalResolution? resolve(
    Map<String, dynamic> raw, {
    String? name,
  }) {
    final categoryKey = _firstNonEmpty([raw['categoryKey'], raw['category']]);
    final subCategoryKey =
        _firstNonEmpty([raw['subCategoryKey'], raw['subCategory']]);
    final typePretty = _firstNonEmpty([
      raw['type_pretty'],
      raw['typePretty'],
    ]);
    final itemName = name ??
        _firstNonEmpty([raw['name'], raw['title'], typePretty]);
    final nameBlob = _nameBlob(itemName, typePretty);

    final fromSub = _resolveFromSubCategory(
      subCategoryKey: subCategoryKey,
      nameBlob: nameBlob,
    );
    if (fromSub != null) return fromSub;

    final fromComposite = _resolveFromCategorySubMap(
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
      nameBlob: nameBlob,
    );
    if (fromComposite != null) return fromComposite;

    if (typePretty.isNotEmpty) {
      final kb = ClothingKnowledgeBase.resolveClothingType(typePretty: typePretty);
      if (kb != null) {
        return CanonicalResolution(
          canonicalType: kb.canonicalType,
          confidence: 80,
          source: 'type_pretty',
        );
      }
    }

    if (itemName.isNotEmpty) {
      final kb = ClothingKnowledgeBase.resolveClothingType(
        typePretty: itemName,
        primaryType: _firstNonEmpty([raw['primary_type'], raw['primaryType']]),
        type: (raw['type'] ?? '').toString(),
      );
      if (kb != null) {
        return CanonicalResolution(
          canonicalType: kb.canonicalType,
          confidence: 65,
          source: 'name',
        );
      }

      final fromNameRules = _resolveFromNameRules(nameBlob);
      if (fromNameRules != null) return fromNameRules;
    }

    return null;
  }

  static CanonicalResolution? _resolveFromSubCategory({
    required String subCategoryKey,
    required String nameBlob,
  }) {
    final subNorm = _normalizeKey(subCategoryKey);
    if (subNorm.isEmpty) return null;

    final matches = _kbItemsForSubcategory(subCategoryKey);
    if (matches.length == 1) {
      return CanonicalResolution(
        canonicalType: matches.first.canonicalType,
        confidence: 95,
        source: 'subcategory_exact',
      );
    }
    if (matches.length > 1) {
      final picked = _disambiguateByName(nameBlob, matches);
      if (picked != null) {
        return CanonicalResolution(
          canonicalType: picked.canonicalType,
          confidence: 90,
          source: 'subcategory_disambiguated',
        );
      }
      return null;
    }

    final aliasHit = ClothingKnowledgeBase.findByAlias(subCategoryKey);
    if (aliasHit != null) {
      return CanonicalResolution(
        canonicalType: aliasHit.canonicalType,
        confidence: 85,
        source: 'subcategory_alias',
      );
    }
    return null;
  }

  static CanonicalResolution? _resolveFromCategorySubMap({
    required String categoryKey,
    required String subCategoryKey,
    required String nameBlob,
  }) {
    final catNorm = _normalizeKey(categoryKey);
    final subNorm = _normalizeKey(subCategoryKey);
    if (catNorm.isEmpty && subNorm.isEmpty) return null;

    final compositeKey = '$catNorm|$subNorm';
    final direct = _categorySubCanonical[compositeKey];
    if (direct != null) {
      return CanonicalResolution(
        canonicalType: _disambiguateCanonical(direct, nameBlob),
        confidence: 90,
        source: 'category_sub_map',
      );
    }

    if (subNorm.isNotEmpty) {
      final subOnly = _categorySubCanonical['|$subNorm'] ??
          _categorySubCanonical.entries
              .where((e) => e.key.endsWith('|$subNorm'))
              .map((e) => e.value)
              .firstOrNull;
      if (subOnly != null) {
        return CanonicalResolution(
          canonicalType: _disambiguateCanonical(subOnly, nameBlob),
          confidence: 75,
          source: 'category_sub_map',
        );
      }
    }

    return null;
  }

  static CanonicalResolution? _resolveFromNameRules(String nameBlob) {
    if (nameBlob.isEmpty) return null;

    final ruleCanonical = _canonicalFromNameTokens(nameBlob);
    if (ruleCanonical == null) return null;

    final kb = ClothingKnowledgeBase.findByCanonicalType(ruleCanonical);
    if (kb == null) return null;

    return CanonicalResolution(
      canonicalType: kb.canonicalType,
      confidence: 60,
      source: 'name',
    );
  }

  static List<ClothingKbItem> _kbItemsForSubcategory(String subCategoryKey) {
    final subNorm = _normalizeKey(subCategoryKey);
    if (subNorm.isEmpty) return const <ClothingKbItem>[];

    final matches = <ClothingKbItem>[];
    for (final item in ClothingKnowledgeBase.allItems) {
      if (_normalizeKey(item.subcategory) == subNorm) {
        matches.add(item);
      }
    }
    return matches;
  }

  static ClothingKbItem? _disambiguateByName(
    String nameBlob,
    List<ClothingKbItem> candidates,
  ) {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;

    final preferred = _canonicalFromNameTokens(nameBlob);
    if (preferred != null) {
      for (final item in candidates) {
        if (item.canonicalType == preferred) return item;
      }
    }

    for (final item in candidates) {
      final sk = _normalizeKey(item.skName);
      if (sk.isNotEmpty && nameBlob.contains(sk)) return item;
    }

    return candidates.first;
  }

  static String _disambiguateCanonical(String baseCanonical, String nameBlob) {
    final preferred = _canonicalFromNameTokens(nameBlob);
    if (preferred == null) return baseCanonical;

    switch (baseCanonical) {
      case 'light_jacket':
        if (preferred == 'windbreaker' ||
            preferred == 'rain_jacket' ||
            preferred == 'bomber_jacket') {
          return preferred;
        }
      case 'winter_jacket':
        if (preferred == 'puffer_jacket' ||
            preferred == 'parka' ||
            preferred == 'ski_jacket') {
          return preferred;
        }
      case 'sweatshirt':
        if (preferred == 'crewneck_sweatshirt') return preferred;
      case 'jeans':
        if (preferred == 'skinny_jeans' ||
            preferred == 'slim_jeans' ||
            preferred == 'straight_jeans') {
          return preferred;
        }
      case 'overcoat':
        if (preferred == 'trench_coat') return preferred;
      case 'sneakers':
        if (preferred == 'running_shoes') return preferred;
    }
    return baseCanonical;
  }

  static String? _canonicalFromNameTokens(String blob) {
    if (blob.contains('vetrov') || blob.contains('windbreaker')) {
      return 'windbreaker';
    }
    if (blob.contains('puffer') ||
        blob.contains('perovy') ||
        blob.contains('perovy')) {
      return 'puffer_jacket';
    }
    if (blob.contains('parka')) return 'parka';
    if (blob.contains('lyziars') || blob.contains('ski')) return 'ski_jacket';
    if (blob.contains('zimn') || blob.contains('winter')) {
      return 'winter_jacket';
    }
    if (blob.contains('trench') || blob.contains('trenchcoat')) {
      return 'trench_coat';
    }
    if (blob.contains('bomber')) return 'bomber_jacket';
    if (blob.contains('prsiplast') || blob.contains('rain jacket')) {
      return 'rain_jacket';
    }
    if (blob.contains('skinny')) return 'skinny_jeans';
    if (blob.contains('slim') && blob.contains('rifl')) return 'slim_jeans';
    if (blob.contains('okrúhly') ||
        blob.contains('okruhly') ||
        blob.contains('crewneck')) {
      return 'crewneck_sweatshirt';
    }
    if (blob.contains('bezec') || blob.contains('running')) {
      return 'running_shoes';
    }
    if (blob.contains('kopack') || blob.contains('football boot')) {
      return 'football_boots';
    }
    if (blob.contains('tielko') || blob.contains('tank')) return 'tank_top';
    if (blob.contains('dlhy') && blob.contains('rukav')) {
      return 'long_sleeve_t_shirt';
    }
    return null;
  }

  static String _nameBlob(String name, String typePretty) {
    return _normalizeKey('$name $typePretty');
  }

  static String _normalizeKey(String raw) {
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
    out = out.replaceAll(RegExp(r'[\s_\-/|]+'), '');
    return out;
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
