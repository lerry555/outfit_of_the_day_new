import 'package:flutter/foundation.dart';

import 'package:outfitofTheDay/constants/app_constants.dart';

/// OOTD Clothing Knowledge Base V1 — canonical type → taxonomy, layer, warmth, formality.

/// Single clothing type definition (English canonical key, Slovak display name).
class ClothingKbItem {
  final String canonicalType;
  final String skName;
  final String mainCategory;
  final String category;
  final String subcategory;
  final String layerRole;
  final int warmthDefault;
  final int formalityDefault;
  final List<String> aliases;

  const ClothingKbItem({
    required this.canonicalType,
    required this.skName,
    required this.mainCategory,
    required this.category,
    required this.subcategory,
    required this.layerRole,
    required this.warmthDefault,
    required this.formalityDefault,
    this.aliases = const [],
  });
}

/// Layer roles used in KB (styling-first).
abstract final class ClothingLayerRole {
  static const baseLayer = 'base_layer';
  static const midLayer = 'mid_layer';
  static const outerLayer = 'outer_layer';
  static const bottom = 'bottom';
  static const footwear = 'footwear';
  static const accessory = 'accessory';
}

/// Central registry + lookup helpers.
abstract final class ClothingKnowledgeBase {
  static const String mainOblecenie = 'oblecenie';
  static const String mainObuv = 'obuv';
  static const String mainDoplnky = 'doplnky';

  static final List<ClothingKbItem> allItems = List.unmodifiable(_items);

  static final Map<String, ClothingKbItem> _byCanonicalKey =
      _buildCanonicalIndex(_items);

  static final Map<String, ClothingKbItem> _byAliasKey = _buildAliasIndex(_items);

  static ClothingKbItem? findByCanonicalType(String canonicalType) {
    final key = _normalizeMatchKey(canonicalType);
    if (key.isEmpty) return null;
    return _byCanonicalKey[key];
  }

  static ClothingKbItem? findByAlias(String value) {
    final key = _normalizeMatchKey(value);
    if (key.isEmpty) return null;
    return _byAliasKey[key];
  }

  /// Search order: canonicalType → primaryType → typePretty → type → combined aliases.
  static ClothingKbItem? resolveClothingType({
    String? canonicalType,
    String? type,
    String? typePretty,
    String? primaryType,
  }) {
    for (final candidate in [
      canonicalType,
      primaryType,
      typePretty,
      type,
    ]) {
      final v = (candidate ?? '').trim();
      if (v.isEmpty) continue;

      final hit = findByCanonicalType(v) ?? findByAlias(v);
      if (hit != null) return hit;
    }

    final blob = [canonicalType, primaryType, typePretty, type]
        .where((s) => (s ?? '').trim().isNotEmpty)
        .join(' ');
    if (blob.trim().isEmpty) return null;

    return findByAlias(blob);
  }

  static void logMatch(ClothingKbItem item) {
    debugPrint(
      '[OOTD_KB_MATCH]\n'
      'canonical=${item.canonicalType}\n'
      'sk=${item.skName}\n'
      'layer=${item.layerRole}\n'
      'warmth=${item.warmthDefault}\n'
      'formality=${item.formalityDefault}',
    );
  }

  static void logNoMatch({
    String? canonicalType,
    String? primaryType,
    String? type,
    String? typePretty,
  }) {
    debugPrint(
      '[OOTD_KB_NO_MATCH]\n'
      'canonical=${canonicalType ?? ''}\n'
      'primary=${primaryType ?? ''}\n'
      'type=${type ?? ''}\n'
      'typePretty=${typePretty ?? ''}',
    );
  }

  /// Wardrobe UI grouping only — does not affect layer_role or stylist logic.
  static String? itemCanonicalType(Map<String, dynamic> item) {
    final direct = (item['canonical_type'] ?? item['canonicalType'] ?? '')
        .toString()
        .trim();
    if (direct.isNotEmpty) return direct;

    for (final key in [
      'uiProjection',
      'aiMetadata',
      'hiddenAiMetadata',
      'metadata',
    ]) {
      final nested = item[key];
      if (nested is Map) {
        final v = (nested['canonical_type'] ?? nested['canonicalType'] ?? '')
            .toString()
            .trim();
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  /// Category tab/section for wardrobe display (KB taxonomy when canonical known).
  static String wardrobeDisplayCategoryKey(Map<String, dynamic> item) {
    final canon = itemCanonicalType(item);
    if (canon != null && canon.isNotEmpty) {
      final kb = findByCanonicalType(canon);
      if (kb != null) return kb.category;
    }

    final kbFromLabels = resolveClothingType(
      typePretty: (item['name'] ?? item['type_pretty'] ?? '').toString(),
      type: (item['type'] ?? '').toString(),
      primaryType: (item['primary_type'] ?? '').toString(),
    );
    if (kbFromLabels != null) return kbFromLabels.category;

    final projected = item['uiProjection'];
    final projectedCategory = projected is Map
        ? (projected['category'] ?? '').toString().trim()
        : '';
    return (item['categoryKey'] ?? item['category'] ?? projectedCategory)
        .toString()
        .trim();
  }

  /// Subcategory chip filter for wardrobe category screen (optional KB override).
  static String wardrobeDisplaySubCategoryKey(Map<String, dynamic> item) {
    final canon = itemCanonicalType(item);
    if (canon != null && canon.isNotEmpty) {
      final kb = findByCanonicalType(canon);
      if (kb != null) return kb.subcategory;
    }
    return (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString().trim();
  }

  /// Human-readable wardrobe category for tiles (KB display taxonomy, not raw AI labels).
  static String wardrobeDisplayCategoryLabel(Map<String, dynamic> item) {
    final key = wardrobeDisplayCategoryKey(item);
    if (key.isNotEmpty) {
      return categoryLabels[key] ?? key;
    }
    return (item['categoryLabel'] as String?) ?? '';
  }

  static String _normalizeMatchKey(String raw) {
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

  static Map<String, ClothingKbItem> _buildCanonicalIndex(List<ClothingKbItem> items) {
    final map = <String, ClothingKbItem>{};
    for (final item in items) {
      map[_normalizeMatchKey(item.canonicalType)] = item;
    }
    return map;
  }

  static Map<String, ClothingKbItem> _buildAliasIndex(List<ClothingKbItem> items) {
    final map = <String, ClothingKbItem>{};
    void register(String alias, ClothingKbItem item) {
      final key = _normalizeMatchKey(alias);
      if (key.isEmpty) return;
      map.putIfAbsent(key, () => item);
    }

    for (final item in items) {
      register(item.canonicalType, item);
      register(item.skName, item);
      register(item.subcategory, item);
      for (final alias in item.aliases) {
        register(alias, item);
      }
    }
    return map;
  }

  // ---------------------------------------------------------------------------
  // TOPS (base_layer)
  // ---------------------------------------------------------------------------
  static const ClothingKbItem _t_shirt = ClothingKbItem(
    canonicalType: 't_shirt',
    skName: 'Tričko s krátkym rukávom',
    mainCategory: mainOblecenie,
    category: 'tricka_topy',
    subcategory: 'tricko',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 2,
    formalityDefault: 2,
    aliases: [
      'tshirt',
      't shirt',
      'tee',
    ],
  );

  static const ClothingKbItem _long_sleeve_t_shirt = ClothingKbItem(
    canonicalType: 'long_sleeve_t_shirt',
    skName: 'Tričko s dlhým rukávom',
    mainCategory: mainOblecenie,
    category: 'tricka_topy',
    subcategory: 'tricko_dlhy_rukav',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 3,
    formalityDefault: 2,
    aliases: [
      'long sleeve t shirt',
      'longsleeve',
    ],
  );

  static const ClothingKbItem _v_neck_t_shirt = ClothingKbItem(
    canonicalType: 'v_neck_t_shirt',
    skName: 'Tričko s výstrihom do V',
    mainCategory: mainOblecenie,
    category: 'tricka_topy',
    subcategory: 'tricko',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 2,
    formalityDefault: 2,
    aliases: [
      'v neck t shirt',
      'vneck',
    ],
  );

  static const ClothingKbItem _tank_top = ClothingKbItem(
    canonicalType: 'tank_top',
    skName: 'Tielko',
    mainCategory: mainOblecenie,
    category: 'tricka_topy',
    subcategory: 'tielko',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 1,
    formalityDefault: 2,
    aliases: [
      'tank',
      'sleeveless',
    ],
  );

  static const ClothingKbItem _polo_shirt = ClothingKbItem(
    canonicalType: 'polo_shirt',
    skName: 'Polo tričko',
    mainCategory: mainOblecenie,
    category: 'tricka_topy',
    subcategory: 'polo_tricko',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 3,
    formalityDefault: 4,
    aliases: [
      'polo',
    ],
  );

  static const ClothingKbItem _dress_shirt = ClothingKbItem(
    canonicalType: 'dress_shirt',
    skName: 'Klasická košeľa',
    mainCategory: mainOblecenie,
    category: 'kosele',
    subcategory: 'kosela_klasicka',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 3,
    formalityDefault: 7,
    aliases: [
      'button up shirt',
      'formal shirt',
    ],
  );

  static const ClothingKbItem _casual_shirt = ClothingKbItem(
    canonicalType: 'casual_shirt',
    skName: 'Casual košeľa',
    mainCategory: mainOblecenie,
    category: 'kosele',
    subcategory: 'kosela_oversize',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 3,
    formalityDefault: 4,
    aliases: [
      'casual shirt',
    ],
  );

  static const ClothingKbItem _flannel_shirt = ClothingKbItem(
    canonicalType: 'flannel_shirt',
    skName: 'Flanelová košeľa',
    mainCategory: mainOblecenie,
    category: 'kosele',
    subcategory: 'kosela_flanelova',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 4,
    formalityDefault: 3,
    aliases: [
      'flannel shirt',
    ],
  );

  static const ClothingKbItem _henley = ClothingKbItem(
    canonicalType: 'henley',
    skName: 'Henley tričko',
    mainCategory: mainOblecenie,
    category: 'tricka_topy',
    subcategory: 'tricko_dlhy_rukav',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 3,
    formalityDefault: 3,
    aliases: [
      'henley shirt',
    ],
  );

  static const ClothingKbItem _blouse = ClothingKbItem(
    canonicalType: 'blouse',
    skName: 'Blúzka',
    mainCategory: mainOblecenie,
    category: 'tricka_topy',
    subcategory: 'bluzka',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 3,
    formalityDefault: 5,
    aliases: [
      'bluzka',
      'halenka',
    ],
  );

  static const ClothingKbItem _crop_top = ClothingKbItem(
    canonicalType: 'crop_top',
    skName: 'Crop top',
    mainCategory: mainOblecenie,
    category: 'tricka_topy',
    subcategory: 'crop_top',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 2,
    formalityDefault: 3,
    aliases: [
      'croptop',
    ],
  );

  static const ClothingKbItem _football_jersey = ClothingKbItem(
    canonicalType: 'football_jersey',
    skName: 'Futbalový dres',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'sport_tricko',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 2,
    formalityDefault: 2,
    aliases: [
      'soccer jersey',
      'football shirt',
    ],
  );

  static const ClothingKbItem _basketball_jersey = ClothingKbItem(
    canonicalType: 'basketball_jersey',
    skName: 'Basketbalový dres',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'sport_tricko',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 2,
    formalityDefault: 2,
    aliases: [
      'basketball jersey',
    ],
  );

  static const ClothingKbItem _cycling_jersey = ClothingKbItem(
    canonicalType: 'cycling_jersey',
    skName: 'Cyklistický dres',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'sport_tricko',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 2,
    formalityDefault: 2,
    aliases: [
      'cycling jersey',
      'bike jersey',
    ],
  );

  static const ClothingKbItem _compression_top = ClothingKbItem(
    canonicalType: 'compression_top',
    skName: 'Kompresný top',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'sport_tricko',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 2,
    formalityDefault: 1,
    aliases: [
      'compression shirt',
    ],
  );

  static const ClothingKbItem _training_top = ClothingKbItem(
    canonicalType: 'training_top',
    skName: 'Tréningové tričko',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'sport_tricko',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 2,
    formalityDefault: 2,
    aliases: [
      'training shirt',
      'workout top',
    ],
  );

  static const ClothingKbItem _turtleneck = ClothingKbItem(
    canonicalType: 'turtleneck',
    skName: 'Rolák',
    mainCategory: mainOblecenie,
    category: 'svetre',
    subcategory: 'sveter_rolak',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 4,
    formalityDefault: 4,
    aliases: [
      'turtle neck',
      'rolak',
    ],
  );


  // ---------------------------------------------------------------------------
  // MID LAYER
  // ---------------------------------------------------------------------------
  static const ClothingKbItem _hoodie = ClothingKbItem(
    canonicalType: 'hoodie',
    skName: 'Mikina s kapucňou',
    mainCategory: mainOblecenie,
    category: 'mikiny',
    subcategory: 'mikina_s_kapucnou',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 5,
    formalityDefault: 2,
    aliases: [
      'hooded sweatshirt',
      'kapucnova mikina',
    ],
  );

  static const ClothingKbItem _zip_hoodie = ClothingKbItem(
    canonicalType: 'zip_hoodie',
    skName: 'Mikina na zips',
    mainCategory: mainOblecenie,
    category: 'mikiny',
    subcategory: 'mikina_na_zips',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 5,
    formalityDefault: 2,
    aliases: [
      'zip hoodie',
      'zip up hoodie',
    ],
  );

  static const ClothingKbItem _crewneck_sweatshirt = ClothingKbItem(
    canonicalType: 'crewneck_sweatshirt',
    skName: 'Mikina s okrúhlym výstrihom',
    mainCategory: mainOblecenie,
    category: 'mikiny',
    subcategory: 'mikina_klasicka',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 5,
    formalityDefault: 2,
    aliases: [
      'crewneck',
      'crew neck sweatshirt',
    ],
  );

  static const ClothingKbItem _sweatshirt = ClothingKbItem(
    canonicalType: 'sweatshirt',
    skName: 'Mikina',
    mainCategory: mainOblecenie,
    category: 'mikiny',
    subcategory: 'mikina_klasicka',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 5,
    formalityDefault: 2,
    aliases: [
      'pullover sweatshirt',
    ],
  );

  static const ClothingKbItem _cardigan = ClothingKbItem(
    canonicalType: 'cardigan',
    skName: 'Kardigan',
    mainCategory: mainOblecenie,
    category: 'svetre',
    subcategory: 'sveter_kardigan',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 5,
    formalityDefault: 4,
    aliases: [
      'kardigan',
    ],
  );

  static const ClothingKbItem _sweater = ClothingKbItem(
    canonicalType: 'sweater',
    skName: 'Sveter',
    mainCategory: mainOblecenie,
    category: 'svetre',
    subcategory: 'sveter_klasicky',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 6,
    formalityDefault: 4,
    aliases: [
      'pullover',
      'jumper',
    ],
  );

  static const ClothingKbItem _knit_sweater = ClothingKbItem(
    canonicalType: 'knit_sweater',
    skName: 'Pletený sveter',
    mainCategory: mainOblecenie,
    category: 'svetre',
    subcategory: 'sveter_pleteny',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 6,
    formalityDefault: 4,
    aliases: [
      'knit sweater',
      'knitted sweater',
    ],
  );

  static const ClothingKbItem _fleece = ClothingKbItem(
    canonicalType: 'fleece',
    skName: 'Flísová mikina',
    mainCategory: mainOblecenie,
    category: 'mikiny',
    subcategory: 'mikina_klasicka',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 6,
    formalityDefault: 2,
    aliases: [
      'fleece top',
      'fleece pullover',
    ],
  );

  static const ClothingKbItem _quarter_zip_pullover = ClothingKbItem(
    canonicalType: 'quarter_zip_pullover',
    skName: 'Mikina so zipsom do polovice',
    mainCategory: mainOblecenie,
    category: 'mikiny',
    subcategory: 'mikina_na_zips',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 5,
    formalityDefault: 3,
    aliases: [
      'quarter zip',
      '1/4 zip',
    ],
  );

  static const ClothingKbItem _track_jacket = ClothingKbItem(
    canonicalType: 'track_jacket',
    skName: 'Tréningová bunda',
    mainCategory: mainOblecenie,
    category: 'mikiny',
    subcategory: 'mikina_na_zips',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 5,
    formalityDefault: 2,
    aliases: [
      'track jacket',
      'treningova bunda',
    ],
  );

  static const ClothingKbItem _training_jacket = ClothingKbItem(
    canonicalType: 'training_jacket',
    skName: 'Tréningová športová bunda',
    mainCategory: mainOblecenie,
    category: 'mikiny',
    subcategory: 'mikina_na_zips',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 5,
    formalityDefault: 2,
    aliases: [
      'training jacket',
      'sport training jacket',
    ],
  );

  static const ClothingKbItem _overshirt = ClothingKbItem(
    canonicalType: 'overshirt',
    skName: 'Overshirt',
    mainCategory: mainOblecenie,
    category: 'kosele',
    subcategory: 'kosela_oversize',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 4,
    formalityDefault: 4,
    aliases: [
      'shacket',
      'shirt jacket',
    ],
  );

  static const ClothingKbItem _knitted_vest = ClothingKbItem(
    canonicalType: 'knitted_vest',
    skName: 'Pletená vesta',
    mainCategory: mainOblecenie,
    category: 'svetre',
    subcategory: 'sveter_pleteny',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 4,
    formalityDefault: 4,
    aliases: [
      'knit vest',
      'sweater vest',
    ],
  );


  // ---------------------------------------------------------------------------
  // OUTERWEAR (outer_layer)
  // ---------------------------------------------------------------------------
  static const ClothingKbItem _light_jacket = ClothingKbItem(
    canonicalType: 'light_jacket',
    skName: 'Ľahká bunda',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'bunda_prechodna',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 4,
    formalityDefault: 3,
    aliases: [
      'light jacket',
      'spring jacket',
    ],
  );

  static const ClothingKbItem _windbreaker = ClothingKbItem(
    canonicalType: 'windbreaker',
    skName: 'Vetrovka',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'bunda_prechodna',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 3,
    formalityDefault: 2,
    aliases: [
      'wind breaker',
      'windbreaker jacket',
    ],
  );

  static const ClothingKbItem _rain_jacket = ClothingKbItem(
    canonicalType: 'rain_jacket',
    skName: 'Pršiplášť',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'prsiplast',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 4,
    formalityDefault: 3,
    aliases: [
      'raincoat',
      'rain jacket',
      'macintosh',
    ],
  );

  static const ClothingKbItem _softshell = ClothingKbItem(
    canonicalType: 'softshell',
    skName: 'Softshell bunda',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'softshell_bunda',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 5,
    formalityDefault: 2,
    aliases: [
      'softshell jacket',
    ],
  );

  static const ClothingKbItem _bomber_jacket = ClothingKbItem(
    canonicalType: 'bomber_jacket',
    skName: 'Bomber bunda',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'bunda_bomber',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 5,
    formalityDefault: 4,
    aliases: [
      'bomber',
    ],
  );

  static const ClothingKbItem _varsity_jacket = ClothingKbItem(
    canonicalType: 'varsity_jacket',
    skName: 'Varsity bunda',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'bunda_prechodna',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 5,
    formalityDefault: 3,
    aliases: [
      'letterman jacket',
      'varsity',
    ],
  );

  static const ClothingKbItem _denim_jacket = ClothingKbItem(
    canonicalType: 'denim_jacket',
    skName: 'Rifľová bunda',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'bunda_riflova',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 4,
    formalityDefault: 3,
    aliases: [
      'jean jacket',
      'denim jacket',
    ],
  );

  static const ClothingKbItem _leather_jacket = ClothingKbItem(
    canonicalType: 'leather_jacket',
    skName: 'Kožená bunda',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'bunda_kozena',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 6,
    formalityDefault: 5,
    aliases: [
      'biker jacket',
    ],
  );

  static const ClothingKbItem _hiking_jacket = ClothingKbItem(
    canonicalType: 'hiking_jacket',
    skName: 'Turistická bunda',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'softshell_bunda',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 6,
    formalityDefault: 2,
    aliases: [
      'hiking jacket',
      'outdoor jacket',
    ],
  );

  static const ClothingKbItem _running_jacket = ClothingKbItem(
    canonicalType: 'running_jacket',
    skName: 'Bežecká bunda',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'softshell_bunda',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 4,
    formalityDefault: 2,
    aliases: [
      'running jacket',
    ],
  );

  static const ClothingKbItem _parka = ClothingKbItem(
    canonicalType: 'parka',
    skName: 'Parka',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'bunda_zimna',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 8,
    formalityDefault: 3,
    aliases: [
      'parka coat',
    ],
  );

  static const ClothingKbItem _puffer_jacket = ClothingKbItem(
    canonicalType: 'puffer_jacket',
    skName: 'Puffer bunda',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'bunda_zimna',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 9,
    formalityDefault: 3,
    aliases: [
      'puffer',
      'down jacket',
    ],
  );

  static const ClothingKbItem _winter_jacket = ClothingKbItem(
    canonicalType: 'winter_jacket',
    skName: 'Zimná bunda',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'bunda_zimna',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 9,
    formalityDefault: 3,
    aliases: [
      'winter jacket',
      'zimna bunda',
    ],
  );

  static const ClothingKbItem _ski_jacket = ClothingKbItem(
    canonicalType: 'ski_jacket',
    skName: 'Lyžiarska bunda',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'bunda_zimna',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 9,
    formalityDefault: 2,
    aliases: [
      'ski jacket',
      'snow jacket',
    ],
  );

  static const ClothingKbItem _overcoat = ClothingKbItem(
    canonicalType: 'overcoat',
    skName: 'Kabát',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'kabat',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 8,
    formalityDefault: 7,
    aliases: [
      'over coat',
      'long coat',
    ],
  );

  static const ClothingKbItem _trench_coat = ClothingKbItem(
    canonicalType: 'trench_coat',
    skName: 'Trenčkot',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'trenchcoat',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 6,
    formalityDefault: 7,
    aliases: [
      'trench coat',
      'trenchcoat',
      'trench',
    ],
  );

  static const ClothingKbItem _vest = ClothingKbItem(
    canonicalType: 'vest',
    skName: 'Vesta',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'vesta',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 4,
    formalityDefault: 4,
    aliases: [
      'gilet',
      'waistcoat',
    ],
  );

  static const ClothingKbItem _puffer_vest = ClothingKbItem(
    canonicalType: 'puffer_vest',
    skName: 'Puffer vesta',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'vesta',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 7,
    formalityDefault: 3,
    aliases: [
      'puffer vest',
      'down vest',
    ],
  );


  // ---------------------------------------------------------------------------
  // BOTTOMS
  // ---------------------------------------------------------------------------
  static const ClothingKbItem _jeans = ClothingKbItem(
    canonicalType: 'jeans',
    skName: 'Rifle',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'rifle',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 5,
    formalityDefault: 3,
    aliases: [
      'denim jeans',
    ],
  );

  static const ClothingKbItem _slim_jeans = ClothingKbItem(
    canonicalType: 'slim_jeans',
    skName: 'Slim rifle',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'rifle',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 5,
    formalityDefault: 3,
    aliases: [
      'slim jeans',
      'slim fit jeans',
    ],
  );

  static const ClothingKbItem _straight_jeans = ClothingKbItem(
    canonicalType: 'straight_jeans',
    skName: 'Rovné rifle',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'rifle',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 5,
    formalityDefault: 3,
    aliases: [
      'straight jeans',
      'straight leg jeans',
    ],
  );

  static const ClothingKbItem _skinny_jeans = ClothingKbItem(
    canonicalType: 'skinny_jeans',
    skName: 'Skinny rifle',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'rifle_skinny',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 5,
    formalityDefault: 3,
    aliases: [
      'skinny jeans',
    ],
  );

  static const ClothingKbItem _chinos = ClothingKbItem(
    canonicalType: 'chinos',
    skName: 'Chino nohavice',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'nohavice_chino',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 4,
    formalityDefault: 5,
    aliases: [
      'chino pants',
    ],
  );

  static const ClothingKbItem _cargo_pants = ClothingKbItem(
    canonicalType: 'cargo_pants',
    skName: 'Cargo nohavice',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'nohavice_cargo',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 4,
    formalityDefault: 2,
    aliases: [
      'cargo trousers',
    ],
  );

  static const ClothingKbItem _joggers = ClothingKbItem(
    canonicalType: 'joggers',
    skName: 'Joggery',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'nohavice_joggery',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 4,
    formalityDefault: 2,
    aliases: [
      'jogger pants',
    ],
  );

  static const ClothingKbItem _sweatpants = ClothingKbItem(
    canonicalType: 'sweatpants',
    skName: 'Teplákové nohavice',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'nohavice_teplakove',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 4,
    formalityDefault: 2,
    aliases: [
      'sweat pants',
      'track sweatpants',
    ],
  );

  static const ClothingKbItem _track_pants = ClothingKbItem(
    canonicalType: 'track_pants',
    skName: 'Teplákové tepláky',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'sport_suprava',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 4,
    formalityDefault: 2,
    aliases: [
      'track pants',
      'training pants',
    ],
  );

  static const ClothingKbItem _suit_trousers = ClothingKbItem(
    canonicalType: 'suit_trousers',
    skName: 'Súčasť obleku – nohavice',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'nohavice_elegantne',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 4,
    formalityDefault: 8,
    aliases: [
      'suit pants',
      'dress trousers',
      'slacks',
    ],
  );

  static const ClothingKbItem _leggings = ClothingKbItem(
    canonicalType: 'leggings',
    skName: 'Legíny',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'leginy',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 3,
    formalityDefault: 2,
    aliases: [
      'leginy',
    ],
  );

  static const ClothingKbItem _running_leggings = ClothingKbItem(
    canonicalType: 'running_leggings',
    skName: 'Bežecké legíny',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'sport_leginy',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 3,
    formalityDefault: 2,
    aliases: [
      'running tights',
    ],
  );

  static const ClothingKbItem _compression_tights = ClothingKbItem(
    canonicalType: 'compression_tights',
    skName: 'Kompresné legíny',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'sport_leginy',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 3,
    formalityDefault: 1,
    aliases: [
      'compression leggings',
    ],
  );

  static const ClothingKbItem _hiking_pants = ClothingKbItem(
    canonicalType: 'hiking_pants',
    skName: 'Turistické nohavice',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'sport_leginy',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 5,
    formalityDefault: 2,
    aliases: [
      'hiking trousers',
      'outdoor pants',
    ],
  );

  static const ClothingKbItem _corduroy_pants = ClothingKbItem(
    canonicalType: 'corduroy_pants',
    skName: 'Menčestrové nohavice',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'nohavice_klasicke',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 5,
    formalityDefault: 4,
    aliases: [
      'corduroy trousers',
    ],
  );

  static const ClothingKbItem _linen_pants = ClothingKbItem(
    canonicalType: 'linen_pants',
    skName: 'Ľanové nohavice',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'nohavice_klasicke',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 3,
    formalityDefault: 5,
    aliases: [
      'linen trousers',
    ],
  );

  static const ClothingKbItem _wide_leg_pants = ClothingKbItem(
    canonicalType: 'wide_leg_pants',
    skName: 'Nohavice wide leg',
    mainCategory: mainOblecenie,
    category: 'nohavice_rifle',
    subcategory: 'rifle_wide_leg',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 4,
    formalityDefault: 4,
    aliases: [
      'wide leg trousers',
      'wide leg pants',
    ],
  );


  // ---------------------------------------------------------------------------
  // SHORTS
  // ---------------------------------------------------------------------------
  static const ClothingKbItem _shorts = ClothingKbItem(
    canonicalType: 'shorts',
    skName: 'Šortky',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sortky',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 2,
    formalityDefault: 2,
    aliases: [
      'short pants',
      'kratasy',
    ],
  );

  static const ClothingKbItem _cargo_shorts = ClothingKbItem(
    canonicalType: 'cargo_shorts',
    skName: 'Cargo šortky',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sortky',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 2,
    formalityDefault: 2,
    aliases: [
      'cargo shorts',
    ],
  );

  static const ClothingKbItem _denim_shorts = ClothingKbItem(
    canonicalType: 'denim_shorts',
    skName: 'Rifľové šortky',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sortky',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 2,
    formalityDefault: 3,
    aliases: [
      'jean shorts',
    ],
  );

  static const ClothingKbItem _sport_shorts = ClothingKbItem(
    canonicalType: 'sport_shorts',
    skName: 'Športové šortky',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sortky_sportove',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 2,
    formalityDefault: 1,
    aliases: [
      'gym shorts',
      'athletic shorts',
    ],
  );

  static const ClothingKbItem _running_shorts = ClothingKbItem(
    canonicalType: 'running_shorts',
    skName: 'Bežecké šortky',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sortky_sportove',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 2,
    formalityDefault: 1,
    aliases: [
      'run shorts',
    ],
  );

  static const ClothingKbItem _cycling_shorts = ClothingKbItem(
    canonicalType: 'cycling_shorts',
    skName: 'Cyklistické šortky',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sortky_sportove',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 2,
    formalityDefault: 1,
    aliases: [
      'bike shorts',
      'cycling bib shorts',
    ],
  );

  static const ClothingKbItem _swim_shorts = ClothingKbItem(
    canonicalType: 'swim_shorts',
    skName: 'Plavky (šortky)',
    mainCategory: mainOblecenie,
    category: 'plavky',
    subcategory: 'plavecke_sortky',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 1,
    formalityDefault: 1,
    aliases: [
      'swim trunks',
      'board shorts',
    ],
  );

  static const ClothingKbItem _sweat_shorts = ClothingKbItem(
    canonicalType: 'sweat_shorts',
    skName: 'Teplákové šortky',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sortky_sportove',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 2,
    formalityDefault: 2,
    aliases: [
      'sweat shorts',
      'jersey shorts',
    ],
  );

  static const ClothingKbItem _linen_shorts = ClothingKbItem(
    canonicalType: 'linen_shorts',
    skName: 'Ľanové šortky',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sortky',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 2,
    formalityDefault: 4,
    aliases: [
      'linen shorts',
    ],
  );


  // ---------------------------------------------------------------------------
  // FOOTWEAR
  // ---------------------------------------------------------------------------
  static const ClothingKbItem _sneakers = ClothingKbItem(
    canonicalType: 'sneakers',
    skName: 'Tenisky',
    mainCategory: mainObuv,
    category: 'tenisky',
    subcategory: 'tenisky_fashion',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 3,
    formalityDefault: 2,
    aliases: [
      'sneaker',
      'trainers',
    ],
  );

  static const ClothingKbItem _running_shoes = ClothingKbItem(
    canonicalType: 'running_shoes',
    skName: 'Bežecké tenisky',
    mainCategory: mainObuv,
    category: 'tenisky',
    subcategory: 'tenisky_bezecke',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 3,
    formalityDefault: 2,
    aliases: [
      'running shoes',
      'runners',
    ],
  );

  static const ClothingKbItem _training_shoes = ClothingKbItem(
    canonicalType: 'training_shoes',
    skName: 'Tréningová obuv',
    mainCategory: mainObuv,
    category: 'sport_obuv_doplnky',
    subcategory: 'obuv_treningova',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 3,
    formalityDefault: 2,
    aliases: [
      'training shoes',
      'gym shoes',
    ],
  );

  static const ClothingKbItem _basketball_shoes = ClothingKbItem(
    canonicalType: 'basketball_shoes',
    skName: 'Basketbalová obuv',
    mainCategory: mainObuv,
    category: 'tenisky',
    subcategory: 'tenisky_sportove',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 3,
    formalityDefault: 2,
    aliases: [
      'basketball sneakers',
    ],
  );

  static const ClothingKbItem _football_boots = ClothingKbItem(
    canonicalType: 'football_boots',
    skName: 'Kopačky',
    mainCategory: mainObuv,
    category: 'tenisky',
    subcategory: 'tenisky_sportove',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 3,
    formalityDefault: 2,
    aliases: [
      'soccer cleats',
      'football cleats',
    ],
  );

  static const ClothingKbItem _hiking_shoes = ClothingKbItem(
    canonicalType: 'hiking_shoes',
    skName: 'Turistická obuv',
    mainCategory: mainObuv,
    category: 'sport_obuv_doplnky',
    subcategory: 'obuv_turisticka',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 5,
    formalityDefault: 2,
    aliases: [
      'hiking boots',
      'trail shoes',
    ],
  );

  static const ClothingKbItem _boots = ClothingKbItem(
    canonicalType: 'boots',
    skName: 'Čižmy',
    mainCategory: mainObuv,
    category: 'cizmy',
    subcategory: 'cizmy_vysoke',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 7,
    formalityDefault: 4,
    aliases: [
      'boot',
    ],
  );

  static const ClothingKbItem _chelsea_boots = ClothingKbItem(
    canonicalType: 'chelsea_boots',
    skName: 'Chelsea čižmy',
    mainCategory: mainObuv,
    category: 'cizmy',
    subcategory: 'cizmy_clenkove',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 6,
    formalityDefault: 5,
    aliases: [
      'chelsea boot',
      'ankle boots',
    ],
  );

  static const ClothingKbItem _winter_boots = ClothingKbItem(
    canonicalType: 'winter_boots',
    skName: 'Zimné čižmy',
    mainCategory: mainObuv,
    category: 'cizmy',
    subcategory: 'snehule',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 8,
    formalityDefault: 3,
    aliases: [
      'snow boots',
      'winter boot',
    ],
  );

  static const ClothingKbItem _sandals = ClothingKbItem(
    canonicalType: 'sandals',
    skName: 'Sandále',
    mainCategory: mainObuv,
    category: 'letna_obuv',
    subcategory: 'sandale',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 1,
    formalityDefault: 3,
    aliases: [
      'sandal',
    ],
  );

  static const ClothingKbItem _flip_flops = ClothingKbItem(
    canonicalType: 'flip_flops',
    skName: 'Žabky',
    mainCategory: mainObuv,
    category: 'letna_obuv',
    subcategory: 'zabky',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 1,
    formalityDefault: 1,
    aliases: [
      'flip flops',
      'thongs',
    ],
  );

  static const ClothingKbItem _slides = ClothingKbItem(
    canonicalType: 'slides',
    skName: 'Šľapky',
    mainCategory: mainObuv,
    category: 'letna_obuv',
    subcategory: 'slapky',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 1,
    formalityDefault: 2,
    aliases: [
      'slide sandals',
      'pool slides',
    ],
  );

  static const ClothingKbItem _dress_shoes = ClothingKbItem(
    canonicalType: 'dress_shoes',
    skName: 'Spoločenská obuv',
    mainCategory: mainObuv,
    category: 'elegantna_obuv',
    subcategory: 'poltopanky',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 4,
    formalityDefault: 7,
    aliases: [
      'formal shoes',
    ],
  );

  static const ClothingKbItem _oxford_shoes = ClothingKbItem(
    canonicalType: 'oxford_shoes',
    skName: 'Oxfordky',
    mainCategory: mainObuv,
    category: 'elegantna_obuv',
    subcategory: 'poltopanky',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 4,
    formalityDefault: 8,
    aliases: [
      'oxford',
      'oxfords',
    ],
  );

  static const ClothingKbItem _loafers = ClothingKbItem(
    canonicalType: 'loafers',
    skName: 'Mokasíny',
    mainCategory: mainObuv,
    category: 'elegantna_obuv',
    subcategory: 'mokasiny',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 4,
    formalityDefault: 6,
    aliases: [
      'loafer',
    ],
  );

  static const ClothingKbItem _heels = ClothingKbItem(
    canonicalType: 'heels',
    skName: 'Lodičky',
    mainCategory: mainObuv,
    category: 'elegantna_obuv',
    subcategory: 'lodicky',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 3,
    formalityDefault: 8,
    aliases: [
      'high heels',
      'pumps',
    ],
  );

  static const ClothingKbItem _canvas_shoes = ClothingKbItem(
    canonicalType: 'canvas_shoes',
    skName: 'Plátenné tenisky',
    mainCategory: mainObuv,
    category: 'tenisky',
    subcategory: 'tenisky_fashion',
    layerRole: ClothingLayerRole.footwear,
    warmthDefault: 3,
    formalityDefault: 3,
    aliases: [
      'canvas sneakers',
      'plátěnky',
    ],
  );


  // ---------------------------------------------------------------------------
  // ACCESSORIES
  // ---------------------------------------------------------------------------
  static const ClothingKbItem _baseball_cap = ClothingKbItem(
    canonicalType: 'baseball_cap',
    skName: 'Šiltovka',
    mainCategory: mainDoplnky,
    category: 'dopl_hlava',
    subcategory: 'siltovka',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 2,
    formalityDefault: 2,
    aliases: [
      'baseball cap',
      'cap',
      'snapback',
    ],
  );

  static const ClothingKbItem _beanie = ClothingKbItem(
    canonicalType: 'beanie',
    skName: 'Čiapka',
    mainCategory: mainDoplnky,
    category: 'dopl_hlava',
    subcategory: 'ciapka',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 5,
    formalityDefault: 2,
    aliases: [
      'knit hat',
      'wool hat',
    ],
  );

  static const ClothingKbItem _winter_hat = ClothingKbItem(
    canonicalType: 'winter_hat',
    skName: 'Zimná čiapka',
    mainCategory: mainDoplnky,
    category: 'dopl_hlava',
    subcategory: 'ciapka',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 6,
    formalityDefault: 2,
    aliases: [
      'winter beanie',
      'tuque',
    ],
  );

  static const ClothingKbItem _bucket_hat = ClothingKbItem(
    canonicalType: 'bucket_hat',
    skName: 'Bucket hat',
    mainCategory: mainDoplnky,
    category: 'dopl_hlava',
    subcategory: 'bucket_hat',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 2,
    formalityDefault: 2,
    aliases: [
      'fishing hat',
    ],
  );

  static const ClothingKbItem _scarf = ClothingKbItem(
    canonicalType: 'scarf',
    skName: 'Šál',
    mainCategory: mainDoplnky,
    category: 'dopl_saly_rukavice',
    subcategory: 'sal',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 5,
    formalityDefault: 4,
    aliases: [
      'scarf',
    ],
  );

  static const ClothingKbItem _gloves = ClothingKbItem(
    canonicalType: 'gloves',
    skName: 'Rukavice',
    mainCategory: mainDoplnky,
    category: 'dopl_saly_rukavice',
    subcategory: 'rukavice',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 6,
    formalityDefault: 3,
    aliases: [
      'glove',
    ],
  );

  static const ClothingKbItem _belt = ClothingKbItem(
    canonicalType: 'belt',
    skName: 'Opasok',
    mainCategory: mainDoplnky,
    category: 'dopl_ostatne',
    subcategory: 'opasok',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 1,
    formalityDefault: 5,
  );

  static const ClothingKbItem _sunglasses = ClothingKbItem(
    canonicalType: 'sunglasses',
    skName: 'Slnečné okuliare',
    mainCategory: mainDoplnky,
    category: 'dopl_ostatne',
    subcategory: 'slnecne_okuliare',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 1,
    formalityDefault: 3,
    aliases: [
      'sunglass',
    ],
  );

  static const ClothingKbItem _watch = ClothingKbItem(
    canonicalType: 'watch',
    skName: 'Hodinky',
    mainCategory: mainDoplnky,
    category: 'dopl_ostatne',
    subcategory: 'hodinky',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 1,
    formalityDefault: 5,
    aliases: [
      'wristwatch',
    ],
  );

  static const ClothingKbItem _backpack = ClothingKbItem(
    canonicalType: 'backpack',
    skName: 'Ruksak',
    mainCategory: mainDoplnky,
    category: 'dopl_tasky',
    subcategory: 'ruksak',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 1,
    formalityDefault: 2,
    aliases: [
      'back pack',
    ],
  );

  static const ClothingKbItem _handbag = ClothingKbItem(
    canonicalType: 'handbag',
    skName: 'Kabelka',
    mainCategory: mainDoplnky,
    category: 'dopl_tasky',
    subcategory: 'kabelka',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 1,
    formalityDefault: 5,
    aliases: [
      'purse',
      'hand bag',
    ],
  );

  static const ClothingKbItem _tote_bag = ClothingKbItem(
    canonicalType: 'tote_bag',
    skName: 'Taška tote',
    mainCategory: mainDoplnky,
    category: 'dopl_tasky',
    subcategory: 'kabelka_listova',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 1,
    formalityDefault: 4,
    aliases: [
      'tote',
      'tote bag',
    ],
  );

  static const ClothingKbItem _crossbody_bag = ClothingKbItem(
    canonicalType: 'crossbody_bag',
    skName: 'Crossbody taška',
    mainCategory: mainDoplnky,
    category: 'dopl_tasky',
    subcategory: 'taska_crossbody',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 1,
    formalityDefault: 4,
    aliases: [
      'crossbody',
      'shoulder bag',
      'cross-body bag',
    ],
  );

  static const ClothingKbItem _fanny_pack = ClothingKbItem(
    canonicalType: 'fanny_pack',
    skName: 'Ľadvinka',
    mainCategory: mainDoplnky,
    category: 'dopl_tasky',
    subcategory: 'ladvinka',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 1,
    formalityDefault: 2,
    aliases: [
      'belt bag',
      'bum bag',
      'fannypack',
    ],
  );


  // ---------------------------------------------------------------------------
  // FORMALWEAR
  // ---------------------------------------------------------------------------
  static const ClothingKbItem _blazer = ClothingKbItem(
    canonicalType: 'blazer',
    skName: 'Sako',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'sako',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 5,
    formalityDefault: 8,
    aliases: [
      'blejzer',
    ],
  );

  static const ClothingKbItem _sport_coat = ClothingKbItem(
    canonicalType: 'sport_coat',
    skName: 'Sportové sako',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'sako',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 5,
    formalityDefault: 7,
    aliases: [
      'sport coat',
      'sport jacket',
    ],
  );

  static const ClothingKbItem _suit_jacket = ClothingKbItem(
    canonicalType: 'suit_jacket',
    skName: 'Sako z obleku',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'sako',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 5,
    formalityDefault: 9,
    aliases: [
      'suit jacket',
    ],
  );

  static const ClothingKbItem _waistcoat = ClothingKbItem(
    canonicalType: 'waistcoat',
    skName: 'Vesta do obleku',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'vesta',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 4,
    formalityDefault: 8,
    aliases: [
      'waistcoat',
      'dress vest',
    ],
  );

  static const ClothingKbItem _suit_vest = ClothingKbItem(
    canonicalType: 'suit_vest',
    skName: 'Obleková vesta',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'vesta',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 4,
    formalityDefault: 8,
    aliases: [
      'suit vest',
    ],
  );

  static const ClothingKbItem _suit = ClothingKbItem(
    canonicalType: 'suit',
    skName: 'Oblek',
    mainCategory: mainOblecenie,
    category: 'bundy_kabaty',
    subcategory: 'sako',
    layerRole: ClothingLayerRole.outerLayer,
    warmthDefault: 5,
    formalityDefault: 9,
    aliases: [
      'business suit',
      'two piece suit',
    ],
  );

  static const ClothingKbItem _tie = ClothingKbItem(
    canonicalType: 'tie',
    skName: 'Kravata',
    mainCategory: mainDoplnky,
    category: 'dopl_ostatne',
    subcategory: 'kravata',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 1,
    formalityDefault: 8,
    aliases: [
      'necktie',
    ],
  );

  static const ClothingKbItem _bow_tie = ClothingKbItem(
    canonicalType: 'bow_tie',
    skName: 'Motýlik',
    mainCategory: mainDoplnky,
    category: 'dopl_ostatne',
    subcategory: 'motylik',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 1,
    formalityDefault: 9,
    aliases: [
      'bowtie',
      'bow tie',
    ],
  );


  // ---------------------------------------------------------------------------
  // DRESSES / SKIRTS / ONE-PIECES
  // ---------------------------------------------------------------------------
  static const ClothingKbItem _dress = ClothingKbItem(
    canonicalType: 'dress',
    skName: 'Šaty',
    mainCategory: mainOblecenie,
    category: 'saty_overaly',
    subcategory: 'saty',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 4,
    formalityDefault: 6,
    aliases: [
      'saty',
    ],
  );

  static const ClothingKbItem _evening_dress = ClothingKbItem(
    canonicalType: 'evening_dress',
    skName: 'Spoločenské šaty',
    mainCategory: mainOblecenie,
    category: 'saty_overaly',
    subcategory: 'saty_maxi',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 4,
    formalityDefault: 9,
    aliases: [
      'evening gown',
      'gala dress',
    ],
  );

  static const ClothingKbItem _cocktail_dress = ClothingKbItem(
    canonicalType: 'cocktail_dress',
    skName: 'Kokteilové šaty',
    mainCategory: mainOblecenie,
    category: 'saty_overaly',
    subcategory: 'saty_midi',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 3,
    formalityDefault: 8,
    aliases: [
      'cocktail dress',
    ],
  );

  static const ClothingKbItem _summer_dress = ClothingKbItem(
    canonicalType: 'summer_dress',
    skName: 'Letné šaty',
    mainCategory: mainOblecenie,
    category: 'saty_overaly',
    subcategory: 'saty_kratke',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 2,
    formalityDefault: 5,
    aliases: [
      'sun dress',
      'sundress',
    ],
  );

  static const ClothingKbItem _skirt = ClothingKbItem(
    canonicalType: 'skirt',
    skName: 'Sukňa',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sukna',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 3,
    formalityDefault: 5,
    aliases: [
      'sukna',
    ],
  );

  static const ClothingKbItem _mini_skirt = ClothingKbItem(
    canonicalType: 'mini_skirt',
    skName: 'Mini sukňa',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sukna_mini',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 2,
    formalityDefault: 4,
    aliases: [
      'mini skirt',
    ],
  );

  static const ClothingKbItem _midi_skirt = ClothingKbItem(
    canonicalType: 'midi_skirt',
    skName: 'Midi sukňa',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sukna_midi',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 3,
    formalityDefault: 5,
    aliases: [
      'midi skirt',
    ],
  );

  static const ClothingKbItem _maxi_skirt = ClothingKbItem(
    canonicalType: 'maxi_skirt',
    skName: 'Maxi sukňa',
    mainCategory: mainOblecenie,
    category: 'sortky_sukne',
    subcategory: 'sukna_maxi',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 3,
    formalityDefault: 5,
    aliases: [
      'maxi skirt',
      'long skirt',
    ],
  );

  static const ClothingKbItem _jumpsuit = ClothingKbItem(
    canonicalType: 'jumpsuit',
    skName: 'Overal',
    mainCategory: mainOblecenie,
    category: 'saty_overaly',
    subcategory: 'overal',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 4,
    formalityDefault: 5,
    aliases: [
      'jump suit',
    ],
  );

  static const ClothingKbItem _romper = ClothingKbItem(
    canonicalType: 'romper',
    skName: 'Krátky overal',
    mainCategory: mainOblecenie,
    category: 'saty_overaly',
    subcategory: 'overal',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 3,
    formalityDefault: 4,
    aliases: [
      'playsuit',
      'short jumpsuit',
    ],
  );


  // ---------------------------------------------------------------------------
  // SWIMWEAR
  // ---------------------------------------------------------------------------
  static const ClothingKbItem _swimsuit = ClothingKbItem(
    canonicalType: 'swimsuit',
    skName: 'Plavky jednodielne',
    mainCategory: mainOblecenie,
    category: 'plavky',
    subcategory: 'plavky_jednodielne',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 1,
    formalityDefault: 2,
    aliases: [
      'one piece swimsuit',
      'bathing suit',
    ],
  );

  static const ClothingKbItem _bikini_top = ClothingKbItem(
    canonicalType: 'bikini_top',
    skName: 'Bikini vrch',
    mainCategory: mainOblecenie,
    category: 'plavky',
    subcategory: 'plavky_vrch',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 1,
    formalityDefault: 2,
    aliases: [
      'bikini top',
    ],
  );

  static const ClothingKbItem _bikini_bottom = ClothingKbItem(
    canonicalType: 'bikini_bottom',
    skName: 'Bikini spodok',
    mainCategory: mainOblecenie,
    category: 'plavky',
    subcategory: 'plavky_spodok',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 1,
    formalityDefault: 2,
    aliases: [
      'bikini bottom',
    ],
  );


  // ---------------------------------------------------------------------------
  // SPECIAL / OUTDOOR
  // ---------------------------------------------------------------------------
  static const ClothingKbItem _hiking_outfit = ClothingKbItem(
    canonicalType: 'hiking_outfit',
    skName: 'Turistická súprava',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'sport_suprava',
    layerRole: ClothingLayerRole.midLayer,
    warmthDefault: 5,
    formalityDefault: 2,
    aliases: [
      'hiking set',
      'outdoor outfit',
    ],
  );

  static const ClothingKbItem _ski_pants = ClothingKbItem(
    canonicalType: 'ski_pants',
    skName: 'Lyžiarske nohavice',
    mainCategory: mainOblecenie,
    category: 'sport_oblecenie',
    subcategory: 'sport_leginy',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 7,
    formalityDefault: 2,
    aliases: [
      'ski trousers',
      'snow pants',
    ],
  );

  static const ClothingKbItem _ski_gloves = ClothingKbItem(
    canonicalType: 'ski_gloves',
    skName: 'Lyžiarske rukavice',
    mainCategory: mainDoplnky,
    category: 'dopl_saly_rukavice',
    subcategory: 'rukavice',
    layerRole: ClothingLayerRole.accessory,
    warmthDefault: 7,
    formalityDefault: 2,
    aliases: [
      'ski gloves',
      'snow gloves',
    ],
  );

  static const ClothingKbItem _thermal_top = ClothingKbItem(
    canonicalType: 'thermal_top',
    skName: 'Termo vrch',
    mainCategory: mainOblecenie,
    category: 'tricka_topy',
    subcategory: 'undershirt',
    layerRole: ClothingLayerRole.baseLayer,
    warmthDefault: 4,
    formalityDefault: 1,
    aliases: [
      'thermal shirt',
      'base layer top',
    ],
  );

  static const ClothingKbItem _thermal_bottom = ClothingKbItem(
    canonicalType: 'thermal_bottom',
    skName: 'Termo spodok',
    mainCategory: mainOblecenie,
    category: 'tricka_topy',
    subcategory: 'undershirt',
    layerRole: ClothingLayerRole.bottom,
    warmthDefault: 4,
    formalityDefault: 1,
    aliases: [
      'thermal leggings',
      'base layer bottom',
    ],
  );

  static const List<ClothingKbItem> _items = [
    _t_shirt,
    _long_sleeve_t_shirt,
    _v_neck_t_shirt,
    _tank_top,
    _polo_shirt,
    _dress_shirt,
    _casual_shirt,
    _flannel_shirt,
    _henley,
    _blouse,
    _crop_top,
    _football_jersey,
    _basketball_jersey,
    _cycling_jersey,
    _compression_top,
    _training_top,
    _turtleneck,
    _hoodie,
    _zip_hoodie,
    _crewneck_sweatshirt,
    _sweatshirt,
    _cardigan,
    _sweater,
    _knit_sweater,
    _fleece,
    _quarter_zip_pullover,
    _track_jacket,
    _training_jacket,
    _overshirt,
    _knitted_vest,
    _light_jacket,
    _windbreaker,
    _rain_jacket,
    _softshell,
    _bomber_jacket,
    _varsity_jacket,
    _denim_jacket,
    _leather_jacket,
    _hiking_jacket,
    _running_jacket,
    _parka,
    _puffer_jacket,
    _winter_jacket,
    _ski_jacket,
    _overcoat,
    _trench_coat,
    _vest,
    _puffer_vest,
    _jeans,
    _slim_jeans,
    _straight_jeans,
    _skinny_jeans,
    _chinos,
    _cargo_pants,
    _joggers,
    _sweatpants,
    _track_pants,
    _suit_trousers,
    _leggings,
    _running_leggings,
    _compression_tights,
    _hiking_pants,
    _corduroy_pants,
    _linen_pants,
    _wide_leg_pants,
    _shorts,
    _cargo_shorts,
    _denim_shorts,
    _sport_shorts,
    _running_shorts,
    _cycling_shorts,
    _swim_shorts,
    _sweat_shorts,
    _linen_shorts,
    _sneakers,
    _running_shoes,
    _training_shoes,
    _basketball_shoes,
    _football_boots,
    _hiking_shoes,
    _boots,
    _chelsea_boots,
    _winter_boots,
    _sandals,
    _flip_flops,
    _slides,
    _dress_shoes,
    _oxford_shoes,
    _loafers,
    _heels,
    _canvas_shoes,
    _baseball_cap,
    _beanie,
    _winter_hat,
    _bucket_hat,
    _scarf,
    _gloves,
    _belt,
    _sunglasses,
    _watch,
    _backpack,
    _handbag,
    _tote_bag,
    _crossbody_bag,
    _fanny_pack,
    _blazer,
    _sport_coat,
    _suit_jacket,
    _waistcoat,
    _suit_vest,
    _suit,
    _tie,
    _bow_tie,
    _dress,
    _evening_dress,
    _cocktail_dress,
    _summer_dress,
    _skirt,
    _mini_skirt,
    _midi_skirt,
    _maxi_skirt,
    _jumpsuit,
    _romper,
    _swimsuit,
    _bikini_top,
    _bikini_bottom,
    _hiking_outfit,
    _ski_pants,
    _ski_gloves,
    _thermal_top,
    _thermal_bottom,
  ];
}
