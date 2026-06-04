#!/usr/bin/env python3
"""Generate lib/data/clothing_knowledge_base.dart with exact V1 canonical list."""

HEADER = r'''import 'package:flutter/foundation.dart';

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

'''

FOOTER = r'''
  static const List<ClothingKbItem> _items = [
ITEMS_LIST
  ];
}
'''

MAIN_O = 'mainOblecenie'
MAIN_B = 'mainObuv'
MAIN_D = 'mainDoplnky'
BL = 'ClothingLayerRole.baseLayer'
ML = 'ClothingLayerRole.midLayer'
OL = 'ClothingLayerRole.outerLayer'
BT = 'ClothingLayerRole.bottom'
FW = 'ClothingLayerRole.footwear'
AC = 'ClothingLayerRole.accessory'


def esc(s: str) -> str:
    return s.replace("'", "\\'")


def dart_item(name: str, canonical: str, sk: str, main: str, cat: str, sub: str,
               layer: str, warmth: int, formality: int, aliases: list[str]) -> str:
    alias_lines = ',\n      '.join(f"'{esc(a)}'" for a in aliases)
    alias_block = f'\n    aliases: [\n      {alias_lines},\n    ],' if aliases else ''
    return f'''  static const ClothingKbItem {name} = ClothingKbItem(
    canonicalType: '{canonical}',
    skName: '{esc(sk)}',
    mainCategory: {main},
    category: '{cat}',
    subcategory: '{sub}',
    layerRole: {layer},
    warmthDefault: {warmth},
    formalityDefault: {formality},{alias_block}
  );
'''


def pascal(s: str) -> str:
    parts = s.split('_')
    return ''.join(p[:1].upper() + p[1:] for p in parts if p)


# (var_name_suffix uses canonical for uniqueness)
# section, canonical, skName, category, subcategory, layer_const, warmth, formality, [aliases]
DATA: list[tuple] = []

def reg(section, canonical, sk, cat, sub, layer, warmth, formality, aliases=None):
    DATA.append((section, canonical, sk, cat, sub, layer, warmth, formality, aliases or []))

# --- TOPS ---
for row in [
    ('t_shirt', 'Tričko s krátkym rukávom', 'tricka_topy', 'tricko', BL, 2, 2, ['tshirt', 't shirt', 'tee']),
    ('long_sleeve_t_shirt', 'Tričko s dlhým rukávom', 'tricka_topy', 'tricko_dlhy_rukav', BL, 3, 2, ['long sleeve t shirt', 'longsleeve']),
    ('v_neck_t_shirt', 'Tričko s výstrihom do V', 'tricka_topy', 'tricko', BL, 2, 2, ['v neck t shirt', 'vneck']),
    ('tank_top', 'Tielko', 'tricka_topy', 'tielko', BL, 1, 2, ['tank', 'sleeveless']),
    ('polo_shirt', 'Polo tričko', 'tricka_topy', 'polo_tricko', BL, 3, 4, ['polo']),
    ('dress_shirt', 'Klasická košeľa', 'kosele', 'kosela_klasicka', BL, 3, 7, ['button up shirt', 'formal shirt']),
    ('casual_shirt', 'Casual košeľa', 'kosele', 'kosela_oversize', BL, 3, 4, ['casual shirt']),
    ('flannel_shirt', 'Flanelová košeľa', 'kosele', 'kosela_flanelova', BL, 4, 3, ['flannel shirt']),
    ('henley', 'Henley tričko', 'tricka_topy', 'tricko_dlhy_rukav', BL, 3, 3, ['henley shirt']),
    ('blouse', 'Blúzka', 'tricka_topy', 'bluzka', BL, 3, 5, ['bluzka', 'halenka']),
    ('crop_top', 'Crop top', 'tricka_topy', 'crop_top', BL, 2, 3, ['croptop']),
    ('football_jersey', 'Futbalový dres', 'sport_oblecenie', 'sport_tricko', BL, 2, 2, ['soccer jersey', 'football shirt']),
    ('basketball_jersey', 'Basketbalový dres', 'sport_oblecenie', 'sport_tricko', BL, 2, 2, ['basketball jersey']),
    ('cycling_jersey', 'Cyklistický dres', 'sport_oblecenie', 'sport_tricko', BL, 2, 2, ['cycling jersey', 'bike jersey']),
    ('compression_top', 'Kompresný top', 'sport_oblecenie', 'sport_tricko', BL, 2, 1, ['compression shirt']),
    ('training_top', 'Tréningové tričko', 'sport_oblecenie', 'sport_tricko', BL, 2, 2, ['training shirt', 'workout top']),
    ('turtleneck', 'Rolák', 'svetre', 'sveter_rolak', BL, 4, 4, ['turtle neck', 'rolak']),
]:
    reg('TOPS', *row)

# --- MID LAYER ---
for row in [
    ('hoodie', 'Mikina s kapucňou', 'mikiny', 'mikina_s_kapucnou', ML, 5, 2, ['hooded sweatshirt', 'kapucnova mikina']),
    ('zip_hoodie', 'Mikina na zips', 'mikiny', 'mikina_na_zips', ML, 5, 2, ['zip hoodie', 'zip up hoodie']),
    ('crewneck_sweatshirt', 'Mikina s okrúhlym výstrihom', 'mikiny', 'mikina_klasicka', ML, 5, 2, ['crewneck', 'crew neck sweatshirt']),
    ('sweatshirt', 'Mikina', 'mikiny', 'mikina_klasicka', ML, 5, 2, ['pullover sweatshirt']),
    ('cardigan', 'Kardigan', 'svetre', 'sveter_kardigan', ML, 5, 4, ['kardigan']),
    ('sweater', 'Sveter', 'svetre', 'sveter_klasicky', ML, 6, 4, ['pullover', 'jumper']),
    ('knit_sweater', 'Pletený sveter', 'svetre', 'sveter_pleteny', ML, 6, 4, ['knit sweater', 'knitted sweater']),
    ('fleece', 'Flísová mikina', 'mikiny', 'mikina_klasicka', ML, 6, 2, ['fleece top', 'fleece pullover']),
    ('quarter_zip_pullover', 'Mikina so zipsom do polovice', 'mikiny', 'mikina_na_zips', ML, 5, 3, ['quarter zip', '1/4 zip']),
    ('track_jacket', 'Tréningová bunda', 'mikiny', 'mikina_na_zips', ML, 5, 2, ['track jacket', 'treningova bunda']),
    ('training_jacket', 'Tréningová športová bunda', 'mikiny', 'mikina_na_zips', ML, 5, 2, ['training jacket', 'sport training jacket']),
    ('overshirt', 'Overshirt', 'kosele', 'kosela_oversize', ML, 4, 4, ['shacket', 'shirt jacket']),
    ('knitted_vest', 'Pletená vesta', 'svetre', 'sveter_pleteny', ML, 4, 4, ['knit vest', 'sweater vest']),
]:
    reg('MID', *row)

# --- OUTERWEAR ---
for row in [
    ('light_jacket', 'Ľahká bunda', 'bundy_kabaty', 'bunda_prechodna', OL, 4, 3, ['light jacket', 'spring jacket']),
    ('windbreaker', 'Vetrovka', 'bundy_kabaty', 'bunda_prechodna', OL, 3, 2, ['wind breaker', 'windbreaker jacket']),
    ('rain_jacket', 'Pršiplášť', 'bundy_kabaty', 'prsiplast', OL, 4, 3, ['raincoat', 'rain jacket']),
    ('softshell', 'Softshell bunda', 'sport_oblecenie', 'softshell_bunda', OL, 5, 2, ['softshell jacket']),
    ('bomber_jacket', 'Bomber bunda', 'bundy_kabaty', 'bunda_bomber', OL, 5, 4, ['bomber']),
    ('varsity_jacket', 'Varsity bunda', 'bundy_kabaty', 'bunda_prechodna', OL, 5, 3, ['letterman jacket', 'varsity']),
    ('denim_jacket', 'Rifľová bunda', 'bundy_kabaty', 'bunda_riflova', OL, 4, 3, ['jean jacket', 'denim jacket']),
    ('leather_jacket', 'Kožená bunda', 'bundy_kabaty', 'bunda_kozena', OL, 6, 5, ['biker jacket']),
    ('hiking_jacket', 'Turistická bunda', 'sport_oblecenie', 'softshell_bunda', OL, 6, 2, ['hiking jacket', 'outdoor jacket']),
    ('running_jacket', 'Bežecká bunda', 'sport_oblecenie', 'softshell_bunda', OL, 4, 2, ['running jacket']),
    ('parka', 'Parka', 'bundy_kabaty', 'bunda_zimna', OL, 8, 3, ['parka coat']),
    ('puffer_jacket', 'Puffer bunda', 'bundy_kabaty', 'bunda_zimna', OL, 9, 3, ['puffer', 'down jacket']),
    ('winter_jacket', 'Zimná bunda', 'bundy_kabaty', 'bunda_zimna', OL, 9, 3, ['winter jacket', 'zimna bunda']),
    ('ski_jacket', 'Lyžiarska bunda', 'bundy_kabaty', 'bunda_zimna', OL, 9, 2, ['ski jacket', 'snow jacket']),
    ('overcoat', 'Kabát', 'bundy_kabaty', 'kabat', OL, 8, 7, ['over coat', 'long coat']),
    ('trench_coat', 'Trenčkot', 'bundy_kabaty', 'trenchcoat', OL, 6, 7, ['trench coat', 'trenchcoat']),
    ('vest', 'Vesta', 'bundy_kabaty', 'vesta', OL, 4, 4, ['gilet', 'waistcoat']),
    ('puffer_vest', 'Puffer vesta', 'bundy_kabaty', 'vesta', OL, 7, 3, ['puffer vest', 'down vest']),
]:
    reg('OUTER', *row)

# --- BOTTOMS ---
for row in [
    ('jeans', 'Rifle', 'nohavice_rifle', 'rifle', BT, 5, 3, ['denim jeans']),
    ('slim_jeans', 'Slim rifle', 'nohavice_rifle', 'rifle', BT, 5, 3, ['slim jeans', 'slim fit jeans']),
    ('straight_jeans', 'Rovné rifle', 'nohavice_rifle', 'rifle', BT, 5, 3, ['straight jeans', 'straight leg jeans']),
    ('skinny_jeans', 'Skinny rifle', 'nohavice_rifle', 'rifle_skinny', BT, 5, 3, ['skinny jeans']),
    ('chinos', 'Chino nohavice', 'nohavice_rifle', 'nohavice_chino', BT, 4, 5, ['chino pants']),
    ('cargo_pants', 'Cargo nohavice', 'nohavice_rifle', 'nohavice_cargo', BT, 4, 2, ['cargo trousers']),
    ('joggers', 'Joggery', 'nohavice_rifle', 'nohavice_joggery', BT, 4, 2, ['jogger pants']),
    ('sweatpants', 'Teplákové nohavice', 'nohavice_rifle', 'nohavice_teplakove', BT, 4, 2, ['sweat pants', 'track sweatpants']),
    ('track_pants', 'Teplákové tepláky', 'sport_oblecenie', 'sport_suprava', BT, 4, 2, ['track pants', 'training pants']),
    ('suit_trousers', 'Súčasť obleku – nohavice', 'nohavice_rifle', 'nohavice_elegantne', BT, 4, 8, ['suit pants', 'dress trousers', 'slacks']),
    ('leggings', 'Legíny', 'nohavice_rifle', 'leginy', BT, 3, 2, ['leginy']),
    ('running_leggings', 'Bežecké legíny', 'sport_oblecenie', 'sport_leginy', BT, 3, 2, ['running tights']),
    ('compression_tights', 'Kompresné legíny', 'sport_oblecenie', 'sport_leginy', BT, 3, 1, ['compression leggings']),
    ('hiking_pants', 'Turistické nohavice', 'sport_oblecenie', 'sport_leginy', BT, 5, 2, ['hiking trousers', 'outdoor pants']),
    ('corduroy_pants', 'Menčestrové nohavice', 'nohavice_rifle', 'nohavice_klasicke', BT, 5, 4, ['corduroy trousers']),
    ('linen_pants', 'Ľanové nohavice', 'nohavice_rifle', 'nohavice_klasicke', BT, 3, 5, ['linen trousers']),
    ('wide_leg_pants', 'Nohavice wide leg', 'nohavice_rifle', 'rifle_wide_leg', BT, 4, 4, ['wide leg trousers', 'wide leg pants']),
]:
    reg('BOTTOMS', *row)

# --- SHORTS ---
for row in [
    ('shorts', 'Šortky', 'sortky_sukne', 'sortky', BT, 2, 2, ['short pants', 'kratasy']),
    ('cargo_shorts', 'Cargo šortky', 'sortky_sukne', 'sortky', BT, 2, 2, ['cargo shorts']),
    ('denim_shorts', 'Rifľové šortky', 'sortky_sukne', 'sortky', BT, 2, 3, ['jean shorts']),
    ('sport_shorts', 'Športové šortky', 'sortky_sukne', 'sortky_sportove', BT, 2, 1, ['gym shorts', 'athletic shorts']),
    ('running_shorts', 'Bežecké šortky', 'sortky_sukne', 'sortky_sportove', BT, 2, 1, ['run shorts']),
    ('cycling_shorts', 'Cyklistické šortky', 'sortky_sukne', 'sortky_sportove', BT, 2, 1, ['bike shorts', 'cycling bib shorts']),
    ('swim_shorts', 'Plavky (šortky)', 'plavky', 'plavecke_sortky', BT, 1, 1, ['swim trunks', 'board shorts']),
    ('sweat_shorts', 'Teplákové šortky', 'sortky_sukne', 'sortky_sportove', BT, 2, 2, ['sweat shorts', 'jersey shorts']),
    ('linen_shorts', 'Ľanové šortky', 'sortky_sukne', 'sortky', BT, 2, 4, ['linen shorts']),
]:
    reg('SHORTS', *row)

# --- FOOTWEAR ---
for row in [
    ('sneakers', 'Tenisky', 'tenisky', 'tenisky_fashion', FW, 3, 2, ['sneaker', 'trainers']),
    ('running_shoes', 'Bežecké tenisky', 'tenisky', 'tenisky_bezecke', FW, 3, 2, ['running shoes', 'runners']),
    ('training_shoes', 'Tréningová obuv', 'sport_obuv_doplnky', 'obuv_treningova', FW, 3, 2, ['training shoes', 'gym shoes']),
    ('basketball_shoes', 'Basketbalová obuv', 'tenisky', 'tenisky_sportove', FW, 3, 2, ['basketball sneakers']),
    ('football_boots', 'Kopačky', 'tenisky', 'tenisky_sportove', FW, 3, 2, ['soccer cleats', 'football cleats']),
    ('hiking_shoes', 'Turistická obuv', 'sport_obuv_doplnky', 'obuv_turisticka', FW, 5, 2, ['hiking boots', 'trail shoes']),
    ('boots', 'Čižmy', 'cizmy', 'cizmy_vysoke', FW, 7, 4, ['boot']),
    ('chelsea_boots', 'Chelsea čižmy', 'cizmy', 'cizmy_clenkove', FW, 6, 5, ['chelsea boot', 'ankle boots']),
    ('winter_boots', 'Zimné čižmy', 'cizmy', 'snehule', FW, 8, 3, ['snow boots', 'winter boot']),
    ('sandals', 'Sandále', 'letna_obuv', 'sandale', FW, 1, 3, ['sandal']),
    ('flip_flops', 'Žabky', 'letna_obuv', 'zabky', FW, 1, 1, ['flip flops', 'thongs']),
    ('slides', 'Šľapky', 'letna_obuv', 'slapky', FW, 1, 2, ['slide sandals', 'pool slides']),
    ('dress_shoes', 'Spoločenská obuv', 'elegantna_obuv', 'poltopanky', FW, 4, 7, ['formal shoes']),
    ('oxford_shoes', 'Oxfordky', 'elegantna_obuv', 'poltopanky', FW, 4, 8, ['oxford', 'oxfords']),
    ('loafers', 'Mokasíny', 'elegantna_obuv', 'mokasiny', FW, 4, 6, ['loafer']),
    ('heels', 'Lodičky', 'elegantna_obuv', 'lodicky', FW, 3, 8, ['high heels', 'pumps']),
    ('canvas_shoes', 'Plátenné tenisky', 'tenisky', 'tenisky_fashion', FW, 3, 3, ['canvas sneakers', 'plátěnky']),
]:
    reg('FOOTWEAR', *row)

# --- ACCESSORIES ---
for row in [
    ('baseball_cap', 'Šiltovka', 'dopl_hlava', 'siltovka', AC, 2, 2, ['baseball cap', 'cap', 'snapback']),
    ('beanie', 'Čiapka', 'dopl_hlava', 'ciapka', AC, 5, 2, ['knit hat', 'wool hat']),
    ('winter_hat', 'Zimná čiapka', 'dopl_hlava', 'ciapka', AC, 6, 2, ['winter beanie', 'tuque']),
    ('bucket_hat', 'Bucket hat', 'dopl_hlava', 'bucket_hat', AC, 2, 2, ['fishing hat']),
    ('scarf', 'Šál', 'dopl_saly_rukavice', 'sal', AC, 5, 4, ['scarf']),
    ('gloves', 'Rukavice', 'dopl_saly_rukavice', 'rukavice', AC, 6, 3, ['glove']),
    ('belt', 'Opasok', 'dopl_ostatne', 'opasok', AC, 1, 5, []),
    ('sunglasses', 'Slnečné okuliare', 'dopl_ostatne', 'slnecne_okuliare', AC, 1, 3, ['sunglass']),
    ('watch', 'Hodinky', 'dopl_ostatne', 'hodinky', AC, 1, 5, ['wristwatch']),
    ('backpack', 'Ruksak', 'dopl_tasky', 'ruksak', AC, 1, 2, ['back pack']),
    ('handbag', 'Kabelka', 'dopl_tasky', 'kabelka', AC, 1, 5, ['purse', 'hand bag']),
    ('tote_bag', 'Taška tote', 'dopl_tasky', 'kabelka_listova', AC, 1, 4, ['tote', 'tote bag']),
    ('crossbody_bag', 'Crossbody taška', 'dopl_tasky', 'taska_crossbody', AC, 1, 4, ['crossbody', 'shoulder bag']),
    ('fanny_pack', 'Ľadvinka', 'dopl_tasky', 'ladvinka', AC, 1, 2, ['belt bag', 'bum bag']),
]:
    reg('ACCESSORIES', *row)

# --- FORMALWEAR ---
for row in [
    ('blazer', 'Sako', 'bundy_kabaty', 'sako', OL, 5, 8, ['blejzer']),
    ('sport_coat', 'Sportové sako', 'bundy_kabaty', 'sako', OL, 5, 7, ['sport coat', 'sport jacket']),
    ('suit_jacket', 'Sako z obleku', 'bundy_kabaty', 'sako', OL, 5, 9, ['suit jacket']),
    ('waistcoat', 'Vesta do obleku', 'bundy_kabaty', 'vesta', ML, 4, 8, ['waistcoat', 'dress vest']),
    ('suit_vest', 'Obleková vesta', 'bundy_kabaty', 'vesta', ML, 4, 8, ['suit vest']),
    ('suit', 'Oblek', 'bundy_kabaty', 'sako', OL, 5, 9, ['business suit', 'two piece suit']),
    ('tie', 'Kravata', 'dopl_ostatne', 'kravata', AC, 1, 8, ['necktie']),
    ('bow_tie', 'Motýlik', 'dopl_ostatne', 'motylik', AC, 1, 9, ['bowtie', 'bow tie']),
]:
    reg('FORMAL', *row)

# --- DRESSES / SKIRTS ---
for row in [
    ('dress', 'Šaty', 'saty_overaly', 'saty', BT, 4, 6, ['saty']),
    ('evening_dress', 'Spoločenské šaty', 'saty_overaly', 'saty_maxi', BT, 4, 9, ['evening gown', 'gala dress']),
    ('cocktail_dress', 'Kokteilové šaty', 'saty_overaly', 'saty_midi', BT, 3, 8, ['cocktail dress']),
    ('summer_dress', 'Letné šaty', 'saty_overaly', 'saty_kratke', BT, 2, 5, ['sun dress', 'sundress']),
    ('skirt', 'Sukňa', 'sortky_sukne', 'sukna', BT, 3, 5, ['sukna']),
    ('mini_skirt', 'Mini sukňa', 'sortky_sukne', 'sukna_mini', BT, 2, 4, ['mini skirt']),
    ('midi_skirt', 'Midi sukňa', 'sortky_sukne', 'sukna_midi', BT, 3, 5, ['midi skirt']),
    ('maxi_skirt', 'Maxi sukňa', 'sortky_sukne', 'sukna_maxi', BT, 3, 5, ['maxi skirt', 'long skirt']),
    ('jumpsuit', 'Overal', 'saty_overaly', 'overal', BT, 4, 5, ['jump suit']),
    ('romper', 'Krátky overal', 'saty_overaly', 'overal', BT, 3, 4, ['playsuit', 'short jumpsuit']),
]:
    reg('DRESSES', *row)

# --- SWIMWEAR ---
for row in [
    ('swimsuit', 'Plavky jednodielne', 'plavky', 'plavky_jednodielne', BT, 1, 2, ['one piece swimsuit', 'bathing suit']),
    ('bikini_top', 'Bikini vrch', 'plavky', 'plavky_vrch', BT, 1, 2, ['bikini top']),
    ('bikini_bottom', 'Bikini spodok', 'plavky', 'plavky_spodok', BT, 1, 2, ['bikini bottom']),
]:
    reg('SWIM', *row)
# swim_shorts already in SHORTS - user listed in both; single canonical only in SHORTS

# --- SPECIAL OUTDOOR ---
for row in [
    ('hiking_outfit', 'Turistická súprava', 'sport_oblecenie', 'sport_suprava', ML, 5, 2, ['hiking set', 'outdoor outfit']),
    ('ski_pants', 'Lyžiarske nohavice', 'sport_oblecenie', 'sport_leginy', BT, 7, 2, ['ski trousers', 'snow pants']),
    ('ski_gloves', 'Lyžiarske rukavice', 'dopl_saly_rukavice', 'rukavice', AC, 7, 2, ['ski gloves', 'snow gloves']),
    ('thermal_top', 'Termo vrch', 'tricka_topy', 'undershirt', BL, 4, 1, ['thermal shirt', 'base layer top']),
    ('thermal_bottom', 'Termo spodok', 'tricka_topy', 'undershirt', BT, 4, 1, ['thermal leggings', 'base layer bottom']),
]:
    reg('SPECIAL', *row)

EXPECTED = [
    'TOPS', 17,
    'MID', 13,
    'OUTER', 18,
    'BOTTOMS', 17,
    'SHORTS', 9,
    'FOOTWEAR', 17,
    'ACCESSORIES', 14,
    'FORMAL', 8,
    'DRESSES', 10,
    'SWIM', 3,
    'SPECIAL', 5,
]
assert sum(EXPECTED[1::2]) == 131, 'unique canonical count (swim_shorts once)'
assert len(DATA) == 131, f'got {len(DATA)}'

# Verify exact canonical set from user list
USER_CANONICAL = '''
t_shirt long_sleeve_t_shirt v_neck_t_shirt tank_top polo_shirt dress_shirt casual_shirt flannel_shirt henley blouse crop_top football_jersey basketball_jersey cycling_jersey compression_top training_top turtleneck
hoodie zip_hoodie crewneck_sweatshirt sweatshirt cardigan sweater knit_sweater fleece quarter_zip_pullover track_jacket training_jacket overshirt knitted_vest
light_jacket windbreaker rain_jacket softshell bomber_jacket varsity_jacket denim_jacket leather_jacket hiking_jacket running_jacket parka puffer_jacket winter_jacket ski_jacket overcoat trench_coat vest puffer_vest
jeans slim_jeans straight_jeans skinny_jeans chinos cargo_pants joggers sweatpants track_pants suit_trousers leggings running_leggings compression_tights hiking_pants corduroy_pants linen_pants wide_leg_pants
shorts cargo_shorts denim_shorts sport_shorts running_shorts cycling_shorts swim_shorts sweat_shorts linen_shorts
sneakers running_shoes training_shoes basketball_shoes football_boots hiking_shoes boots chelsea_boots winter_boots sandals flip_flops slides dress_shoes oxford_shoes loafers heels canvas_shoes
baseball_cap beanie winter_hat bucket_hat scarf gloves belt sunglasses watch backpack handbag tote_bag crossbody_bag fanny_pack
blazer sport_coat suit_jacket waistcoat suit_vest suit tie bow_tie
dress evening_dress cocktail_dress summer_dress skirt mini_skirt midi_skirt maxi_skirt jumpsuit romper
swimsuit bikini_top bikini_bottom swim_shorts
hiking_outfit ski_pants ski_gloves thermal_top thermal_bottom
'''.split()
user_set = set(USER_CANONICAL)
data_set = {r[1] for r in DATA}
assert user_set == data_set, f'missing {user_set-data_set} extra {data_set-user_set}'

used_names = set()
body_parts = []
item_refs = []
current_section = None
section_comments = {
    'TOPS': '  // ---------------------------------------------------------------------------\n  // TOPS (base_layer)\n  // ---------------------------------------------------------------------------',
    'MID': '  // ---------------------------------------------------------------------------\n  // MID LAYER\n  // ---------------------------------------------------------------------------',
    'OUTER': '  // ---------------------------------------------------------------------------\n  // OUTERWEAR (outer_layer)\n  // ---------------------------------------------------------------------------',
    'BOTTOMS': '  // ---------------------------------------------------------------------------\n  // BOTTOMS\n  // ---------------------------------------------------------------------------',
    'SHORTS': '  // ---------------------------------------------------------------------------\n  // SHORTS\n  // ---------------------------------------------------------------------------',
    'FOOTWEAR': '  // ---------------------------------------------------------------------------\n  // FOOTWEAR\n  // ---------------------------------------------------------------------------',
    'ACCESSORIES': '  // ---------------------------------------------------------------------------\n  // ACCESSORIES\n  // ---------------------------------------------------------------------------',
    'FORMAL': '  // ---------------------------------------------------------------------------\n  // FORMALWEAR\n  // ---------------------------------------------------------------------------',
    'DRESSES': '  // ---------------------------------------------------------------------------\n  // DRESSES / SKIRTS / ONE-PIECES\n  // ---------------------------------------------------------------------------',
    'SWIM': '  // ---------------------------------------------------------------------------\n  // SWIMWEAR\n  // ---------------------------------------------------------------------------',
    'SPECIAL': '  // ---------------------------------------------------------------------------\n  // SPECIAL / OUTDOOR\n  // ---------------------------------------------------------------------------',
}

for row in DATA:
    section, canonical, sk, cat, sub, layer, warmth, formality, aliases = row
    if section != current_section:
        if current_section is not None:
            body_parts.append('')
        body_parts.append(section_comments[section])
        current_section = section
    main = MAIN_O
    if section in ('FOOTWEAR',):
        main = MAIN_B
    elif section in ('ACCESSORIES',):
        main = MAIN_D
    elif section in ('FORMAL',) and canonical in ('tie', 'bow_tie'):
        main = MAIN_D
    elif canonical in ('tie', 'bow_tie', 'watch', 'belt', 'sunglasses'):
        main = MAIN_D
    else:
        if cat.startswith('tenisky') or cat.startswith('elegantna') or cat.startswith('cizmy') or cat.startswith('letna') or cat.startswith('sport_obuv'):
            main = MAIN_B
        elif cat.startswith('dopl_'):
            main = MAIN_D
        else:
            main = MAIN_O

    base_name = '_' + canonical
    var_name = base_name
    i = 2
    while var_name in used_names:
        var_name = f'{base_name}{i}'
        i += 1
    used_names.add(var_name)

    body_parts.append(dart_item(var_name, canonical, sk, main, cat, sub, layer, warmth, formality, aliases))
    item_refs.append(f'    {var_name},')

items_list = '\n'.join(item_refs)
out = HEADER + '\n'.join(body_parts) + FOOTER.replace('ITEMS_LIST', items_list)
path = 'lib/data/clothing_knowledge_base.dart'
with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)
print(f'Wrote {path} with {len(DATA)} items')
