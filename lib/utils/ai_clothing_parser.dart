import '../constants/app_constants.dart';

class AiParserInput {
  final String rawType;
  final String aiName;
  final String userName;
  final List<String> seasons;
  final String brand;

  AiParserInput({
    required this.rawType,
    required this.aiName,
    required this.userName,
    required this.seasons,
    required this.brand,
  });
}

class AiMappedCategory {
  final String mainGroupKey;
  final String categoryKey;
  final String subCategoryKey;
  final String layerRole;

  AiMappedCategory({
    required this.mainGroupKey,
    required this.categoryKey,
    required this.subCategoryKey,
    required this.layerRole,
  });
}

class AiClothingParser {
  static final Map<String, String> _canonicalAliasToSubKey = {
    // TRIČKÁ / TOPY
    'tricko': 'tricko',
    'tričko': 'tricko',
    'tshirt': 'tricko',
    't shirt': 'tricko',
    'tee': 'tricko',
    'tee shirt': 'tricko',
    'short sleeve t shirt': 'tricko',
    'short sleeve tshirt': 'tricko',
    'short sleeve tee': 'tricko',
    'tricko s kratkym rukavom': 'tricko',
    't_shirt': 'tricko',

    'tricko dlhy rukav': 'tricko_dlhy_rukav',
    'tricko s dlhym rukavom': 'tricko_dlhy_rukav',
    'long sleeve': 'tricko_dlhy_rukav',
    'long sleeve tee': 'tricko_dlhy_rukav',
    'long sleeve t shirt': 'tricko_dlhy_rukav',
    'long sleeve tshirt': 'tricko_dlhy_rukav',
    'longsleeve': 'tricko_dlhy_rukav',
    'long_sleeve': 'tricko_dlhy_rukav',
    'long_sleeve_tshirt': 'tricko_dlhy_rukav',
    'long_sleeve_t_shirt': 'tricko_dlhy_rukav',

    'tielko': 'tielko',
    'tank': 'tielko',
    'tank top': 'tielko',
    'tanktop': 'tielko',
    'sleeveless top': 'tielko',
    'sleeveless shirt': 'tielko',
    'sleeveless tee': 'tielko',
    'sleeveless t shirt': 'tielko',
    'bezrukavove tricko': 'tielko',
    'bezrukávové tričko': 'tielko',
    'bez rukavov': 'tielko',
    'tank_top': 'tielko',

    'undershirt': 'undershirt',
    'under shirt': 'undershirt',
    'spodne tielko': 'undershirt',
    'spodné tielko': 'undershirt',
    'basic undershirt': 'undershirt',
    'base layer tank': 'undershirt',
    'inner tank': 'undershirt',

    'top': 'top_basic',
    'basic top': 'top_basic',
    'fashion top': 'top_basic',
    'top_basic': 'top_basic',

    'crop top': 'crop_top',
    'croptop': 'crop_top',
    'crop_top': 'crop_top',

    'polo': 'polo_tricko',
    'polo shirt': 'polo_tricko',
    'polo_shirt': 'polo_tricko',
    'polo_tricko': 'polo_tricko',

    'body': 'body',
    'bodysuit': 'body',

    'korzet': 'korzet_top',
    'corset': 'korzet_top',
    'corset top': 'korzet_top',
    'korzet top': 'korzet_top',

    'bluzka': 'bluzka',
    'blúzka': 'bluzka',
    'bluza': 'bluzka',
    'halenka': 'bluzka',
    'blouse': 'bluzka',
    'blouse top': 'bluzka',

    // KOŠELE
    'kosela': 'kosela_klasicka',
    'košeľa': 'kosela_klasicka',
    'shirt': 'kosela_klasicka',
    'button up': 'kosela_klasicka',
    'button-up': 'kosela_klasicka',
    'button down': 'kosela_klasicka',
    'button-down': 'kosela_klasicka',
    'dress shirt': 'kosela_klasicka',
    'formal shirt': 'kosela_klasicka',
    'kosela_klasicka': 'kosela_klasicka',

    'oversize kosela': 'kosela_oversize',
    'oversized shirt': 'kosela_oversize',
    'oversize shirt': 'kosela_oversize',
    'overshirt': 'kosela_oversize',
    'shacket': 'kosela_oversize',
    'kosela_oversize': 'kosela_oversize',

    'flanelova kosela': 'kosela_flanelova',
    'flanelová košeľa': 'kosela_flanelova',
    'flanel shirt': 'kosela_flanelova',
    'flannel shirt': 'kosela_flanelova',
    'plaid shirt': 'kosela_flanelova',
    'kosela_flanelova': 'kosela_flanelova',

    // MIKINY / SVETRE
    'mikina': 'mikina_klasicka',
    'sweatshirt': 'mikina_klasicka',
    'crewneck sweatshirt': 'mikina_klasicka',
    'crewneck': 'mikina_klasicka',
    'pullover sweatshirt': 'mikina_klasicka',
    'mikina_klasicka': 'mikina_klasicka',

    'hoodie': 'mikina_s_kapucnou',
    'hooded sweatshirt': 'mikina_s_kapucnou',
    'mikina s kapucnou': 'mikina_s_kapucnou',
    'mikina_s_kapucnou': 'mikina_s_kapucnou',

    'zip hoodie': 'mikina_na_zips',
    'zip up hoodie': 'mikina_na_zips',
    'zip-up hoodie': 'mikina_na_zips',
    'mikina na zips': 'mikina_na_zips',
    'zip sweatshirt': 'mikina_na_zips',
    'mikina_na_zips': 'mikina_na_zips',

    'oversize mikina': 'mikina_oversize',
    'oversized sweatshirt': 'mikina_oversize',
    'oversize hoodie': 'mikina_oversize',
    'mikina_oversize': 'mikina_oversize',

    'sveter': 'sveter_klasicky',
    'sweater': 'sveter_klasicky',
    'jumper': 'sveter_klasicky',
    'pullover': 'sveter_klasicky',
    'knit sweater': 'sveter_klasicky',
    'knitted sweater': 'sveter_klasicky',
    'sveter_klasicky': 'sveter_klasicky',

    'rolak': 'sveter_rolak',
    'rolák': 'sveter_rolak',
    'turtleneck': 'sveter_rolak',
    'turtle neck': 'sveter_rolak',
    'roll neck': 'sveter_rolak',
    'sveter_rolak': 'sveter_rolak',

    'kardigan': 'sveter_kardigan',
    'cardigan': 'sveter_kardigan',
    'sveter_kardigan': 'sveter_kardigan',

    'pleteny sveter': 'sveter_pleteny',
    'pletený sveter': 'sveter_pleteny',
    'chunky knit': 'sveter_pleteny',
    'cable knit': 'sveter_pleteny',
    'sveter_pleteny': 'sveter_pleteny',

    // BUNDY / KABÁTY
    'bunda': 'bunda_prechodna',
    'jacket': 'bunda_prechodna',
    'light jacket': 'bunda_prechodna',
    'spring jacket': 'bunda_prechodna',
    'fall jacket': 'bunda_prechodna',
    'transitional jacket': 'bunda_prechodna',

    'denim jacket': 'bunda_riflova',
    'jean jacket': 'bunda_riflova',
    'riflova bunda': 'bunda_riflova',
    'rifľová bunda': 'bunda_riflova',
    'denim_jacket': 'bunda_riflova',
    'bunda_riflova': 'bunda_riflova',

    'leather jacket': 'bunda_kozena',
    'biker jacket': 'bunda_kozena',
    'kozena bunda': 'bunda_kozena',
    'kožená bunda': 'bunda_kozena',
    'leather_jacket': 'bunda_kozena',
    'bunda_kozena': 'bunda_kozena',

    'bomber': 'bunda_bomber',
    'bomber jacket': 'bunda_bomber',
    'bunda_bomber': 'bunda_bomber',

    'puffer': 'bunda_zimna',
    'puffer jacket': 'bunda_zimna',
    'winter jacket': 'bunda_zimna',
    'zimna bunda': 'bunda_zimna',
    'zimná bunda': 'bunda_zimna',
    'parka': 'bunda_zimna',
    'down jacket': 'bunda_zimna',
    'puffer_jacket': 'bunda_zimna',
    'bunda_zimna': 'bunda_zimna',

    'rain jacket': 'prsiplast',
    'raincoat': 'prsiplast',
    'prsiplast': 'prsiplast',
    'pršiplášť': 'prsiplast',
    'rain_jacket': 'prsiplast',

    'fleece jacket': 'flisova_bunda',
    'flis': 'flisova_bunda',
    'fleece': 'flisova_bunda',
    'flisova bunda': 'flisova_bunda',
    'flísová bunda': 'flisova_bunda',
    'flisova_bunda': 'flisova_bunda',

    'kabat': 'kabat',
    'kabát': 'kabat',
    'coat': 'kabat',
    'overcoat': 'kabat',

    'trench': 'trenchcoat',
    'trench coat': 'trenchcoat',
    'trenchcoat': 'trenchcoat',

    'sako': 'sako',
    'blazer': 'sako',
    'blejzer': 'sako',

    'vesta': 'vesta',
    'vest': 'vesta',
    'waistcoat': 'vesta',
    'gilet': 'vesta',

    // NOHAVICE / SPODOK
    'rifle': 'rifle',
    'jeans': 'rifle',

    'skinny jeans': 'rifle_skinny',
    'skinny rifle': 'rifle_skinny',
    'rifle_skinny': 'rifle_skinny',

    'wide leg jeans': 'rifle_wide_leg',
    'wide leg rifle': 'rifle_wide_leg',
    'wideleg jeans': 'rifle_wide_leg',
    'rifle_wide_leg': 'rifle_wide_leg',

    'mom jeans': 'rifle_mom',
    'mom fit jeans': 'rifle_mom',
    'rifle_mom': 'rifle_mom',

    'nohavice': 'nohavice_klasicke',
    'pants': 'nohavice_klasicke',
    'trousers': 'nohavice_klasicke',
    'slacks': 'nohavice_klasicke',
    'tailored trousers': 'nohavice_klasicke',
    'nohavice_klasicke': 'nohavice_klasicke',

    'formal trousers': 'nohavice_elegantne',
    'dress pants': 'nohavice_elegantne',
    'elegantne nohavice': 'nohavice_elegantne',
    'elegantné nohavice': 'nohavice_elegantne',
    'suit pants': 'nohavice_elegantne',
    'nohavice_elegantne': 'nohavice_elegantne',

    'chino': 'nohavice_chino',
    'chinos': 'nohavice_chino',
    'chino pants': 'nohavice_chino',
    'nohavice_chino': 'nohavice_chino',

    'teplaky': 'nohavice_teplakove',
    'tepláky': 'nohavice_teplakove',
    'sweatpants': 'nohavice_teplakove',
    'sweat pants': 'nohavice_teplakove',
    'track pants': 'nohavice_teplakove',
    'training pants': 'nohavice_teplakove',
    'nohavice_teplakove': 'nohavice_teplakove',

    'joggers': 'nohavice_joggery',
    'jogger': 'nohavice_joggery',
    'joggery': 'nohavice_joggery',
    'nohavice_joggery': 'nohavice_joggery',

    'cargo': 'nohavice_cargo',
    'cargo pants': 'nohavice_cargo',
    'cargo trousers': 'nohavice_cargo',
    'nohavice_cargo': 'nohavice_cargo',

    'leginy': 'leginy',
    'legíny': 'leginy',
    'leggings': 'leginy',
    'legging': 'leginy',

    'sortky': 'sortky',
    'šortky': 'sortky',
    'shorts': 'sortky',

    'sport shorts': 'sortky_sportove',
    'sportove sortky': 'sortky_sportove',
    'športové šortky': 'sortky_sportove',
    'athletic shorts': 'sortky_sportove',
    'running shorts': 'sortky_sportove',
    'gym shorts': 'sortky_sportove',
    'sortky_sportove': 'sortky_sportove',

    'sukna': 'sukna',
    'sukňa': 'sukna',
    'skirt': 'sukna',

    'mini skirt': 'sukna_mini',
    'mini sukna': 'sukna_mini',
    'mini sukňa': 'sukna_mini',
    'sukna_mini': 'sukna_mini',

    'midi skirt': 'sukna_midi',
    'midi sukna': 'sukna_midi',
    'midi sukňa': 'sukna_midi',
    'sukna_midi': 'sukna_midi',

    'maxi skirt': 'sukna_maxi',
    'maxi sukna': 'sukna_maxi',
    'maxi sukňa': 'sukna_maxi',
    'sukna_maxi': 'sukna_maxi',

    // ŠATY / OVERALY
    'saty': 'saty',
    'šaty': 'saty',
    'dress': 'saty',

    'short dress': 'saty_kratke',
    'mini dress': 'saty_kratke',
    'kratke saty': 'saty_kratke',
    'krátke šaty': 'saty_kratke',
    'saty_kratke': 'saty_kratke',

    'midi dress': 'saty_midi',
    'midi saty': 'saty_midi',
    'midi šaty': 'saty_midi',
    'saty_midi': 'saty_midi',

    'maxi dress': 'saty_maxi',
    'maxi saty': 'saty_maxi',
    'maxi šaty': 'saty_maxi',
    'saty_maxi': 'saty_maxi',

    'shirt dress': 'saty_koselove',
    'koselove saty': 'saty_koselove',
    'košeľové šaty': 'saty_koselove',
    'saty_koselove': 'saty_koselove',

    'bodycon dress': 'saty_bodycon',
    'bodycon saty': 'saty_bodycon',
    'bodycon šaty': 'saty_bodycon',
    'saty_bodycon': 'saty_bodycon',

    'overal': 'overal',
    'jumpsuit': 'overal',
    'playsuit': 'overal',
    'romper': 'overal',

    // OBUV
    'tenisky': 'tenisky_fashion',
    'sneakers': 'tenisky_fashion',
    'sneaker': 'tenisky_fashion',
    'fashion sneakers': 'tenisky_fashion',
    'casual sneakers': 'tenisky_fashion',
    'tenisky_fashion': 'tenisky_fashion',

    'sportove tenisky': 'tenisky_sportove',
    'športové tenisky': 'tenisky_sportove',
    'sport sneakers': 'tenisky_sportove',
    'training sneakers': 'tenisky_sportove',
    'gym shoes': 'tenisky_sportove',
    'tenisky_sportove': 'tenisky_sportove',

    'running shoes': 'tenisky_bezecke',
    'bezecke tenisky': 'tenisky_bezecke',
    'bežecké tenisky': 'tenisky_bezecke',
    'tenisky_bezecke': 'tenisky_bezecke',

    'heels': 'lodicky',
    'high heels': 'lodicky',
    'pumps': 'lodicky',
    'lodicky': 'lodicky',
    'lodičky': 'lodicky',

    'heeled sandals': 'sandale_opatok',
    'sandale na opatku': 'sandale_opatok',
    'sandále na opätku': 'sandale_opatok',
    'sandale_opatok': 'sandale_opatok',

    'flats': 'balerinky',
    'ballet flats': 'balerinky',
    'balerinky': 'balerinky',

    'loafers': 'mokasiny',
    'loafer': 'mokasiny',
    'mokasiny': 'mokasiny',
    'mokasíny': 'mokasiny',

    'oxfords': 'poltopanky',
    'derby shoes': 'poltopanky',
    'formal shoes': 'poltopanky',
    'poltopanky': 'poltopanky',
    'poltopánky': 'poltopanky',

    'platform shoes': 'obuv_platforma',
    'platform sandals': 'obuv_platforma',
    'obuv_platforma': 'obuv_platforma',

    'boots': 'cizmy_clenkove',
    'boot': 'cizmy_clenkove',
    'ankle boots': 'cizmy_clenkove',
    'clenkove cizmy': 'cizmy_clenkove',
    'členkové čižmy': 'cizmy_clenkove',
    'cizmy_clenkove': 'cizmy_clenkove',

    'knee boots': 'cizmy_vysoke',
    'high boots': 'cizmy_vysoke',
    'vysoke cizmy': 'cizmy_vysoke',
    'vysoké čižmy': 'cizmy_vysoke',
    'cizmy_vysoke': 'cizmy_vysoke',

    'over the knee boots': 'cizmy_nad_kolena',
    'thigh high boots': 'cizmy_nad_kolena',
    'cizmy nad kolena': 'cizmy_nad_kolena',
    'čižmy nad kolená': 'cizmy_nad_kolena',
    'cizmy_nad_kolena': 'cizmy_nad_kolena',

    'rain boots': 'gumaky',
    'wellington boots': 'gumaky',
    'gumaky': 'gumaky',
    'gumáky': 'gumaky',

    'snow boots': 'snehule',
    'winter boots': 'snehule',
    'snehule': 'snehule',

    'sandals': 'sandale',
    'sandale': 'sandale',
    'sandále': 'sandale',

    'slippers': 'slapky',
    'slides': 'slapky',
    'slide sandals': 'slapky',
    'slapky': 'slapky',
    'šľapky': 'slapky',

    'flip flops': 'zabky',
    'flipflops': 'zabky',
    'zabky': 'zabky',
    'žabky': 'zabky',

    'espadrilles': 'espadrilky',
    'espadrille': 'espadrilky',
    'espadrilky': 'espadrilky',

    // DOPLNKY
    'ciapka': 'ciapka',
    'čiapka': 'ciapka',
    'beanie': 'ciapka',
    'winter hat': 'ciapka',

    'cap': 'siltovka',
    'baseball cap': 'siltovka',
    'snapback': 'siltovka',
    'siltovka': 'siltovka',
    'šiltovka': 'siltovka',

    'hat': 'bucket_hat',
    'bucket hat': 'bucket_hat',
    'sun hat': 'bucket_hat',
    'klobuk': 'bucket_hat',
    'klobúk': 'bucket_hat',

    'sal': 'sal',
    'šál': 'sal',
    'scarf': 'sal',

    'satka': 'satka',
    'šatka': 'satka',
    'shawl': 'satka',
    'bandana': 'satka',

    'rukavice': 'rukavice',
    'gloves': 'rukavice',

    'kabelka': 'kabelka',
    'handbag': 'kabelka',
    'purse': 'kabelka',

    'crossbody bag': 'taska_crossbody',
    'crossbody': 'taska_crossbody',
    'taska_crossbody': 'taska_crossbody',
    'crossbody taška': 'taska_crossbody',

    'backpack': 'ruksak',
    'ruksak': 'ruksak',

    'clutch': 'kabelka_listova',
    'clutch bag': 'kabelka_listova',
    'kabelka_listova': 'kabelka_listova',
    'listová kabelka': 'kabelka_listova',

    'belt bag': 'ladvinka',
    'fanny pack': 'ladvinka',
    'waist bag': 'ladvinka',
    'ladvinka': 'ladvinka',
    'ľadvinka': 'ladvinka',

    'sunglasses': 'slnecne_okuliare',
    'slnecne okuliare': 'slnecne_okuliare',
    'slnečné okuliare': 'slnecne_okuliare',
    'slnecne_okuliare': 'slnecne_okuliare',

    'belt': 'opasok',
    'opasok': 'opasok',

    'wallet': 'penazenka',
    'penazenka': 'penazenka',
    'peňaženka': 'penazenka',

    'watch': 'hodinky',
    'hodinky': 'hodinky',

    'jewelry': 'sperky',
    'jewellery': 'sperky',
    'sperky': 'sperky',
    'šperky': 'sperky',

    // ŠPORT
    'sport t shirt': 'sport_tricko',
    'sportove tricko': 'sport_tricko',
    'športové tričko': 'sport_tricko',
    'gym shirt': 'sport_tricko',
    'training shirt': 'sport_tricko',
    'sport_tricko': 'sport_tricko',

    'sport hoodie': 'sport_mikina',
    'functional hoodie': 'sport_mikina',
    'funkcna mikina': 'sport_mikina',
    'funkčná mikina': 'sport_mikina',
    'sport_mikina': 'sport_mikina',

    'sport leggings': 'sport_leginy',
    'workout leggings': 'sport_leginy',
    'gym leggings': 'sport_leginy',
    'sport_leginy': 'sport_leginy',

    'training shorts': 'sport_sortky',
    'sport_sortky': 'sport_sortky',

    'tracksuit': 'sport_suprava',
    'teplakova suprava': 'sport_suprava',
    'tepláková súprava': 'sport_suprava',
    'sport_suprava': 'sport_suprava',

    'softshell': 'softshell_bunda',
    'softshell jacket': 'softshell_bunda',
    'softshell_bunda': 'softshell_bunda',

    'sports bra': 'sport_podprsenka',
    'sport bra': 'sport_podprsenka',
    'sportova podprsenka': 'sport_podprsenka',
    'športová podprsenka': 'sport_podprsenka',
    'sport_podprsenka': 'sport_podprsenka',

    'training shoes': 'obuv_treningova',
    'treningova obuv': 'obuv_treningova',
    'tréningová obuv': 'obuv_treningova',
    'obuv_treningova': 'obuv_treningova',

    'hiking shoes': 'obuv_turisticka',
    'trail shoes': 'obuv_turisticka',
    'turisticka obuv': 'obuv_turisticka',
    'turistická obuv': 'obuv_turisticka',
    'obuv_turisticka': 'obuv_turisticka',

    'gym bag': 'sport_taska',
    'duffel bag': 'sport_taska',
    'sport bag': 'sport_taska',
    'sport_taska': 'sport_taska',

    'wristband': 'potitka',
    'sweatband': 'potitka',
    'potitka': 'potitka',
    'potítka': 'potitka',
  };

  static AiMappedCategory? fromCanonicalType(String canonicalType) {
    final normalized = _norm(canonicalType);
    if (normalized.isEmpty) return null;

    String? subKey = _canonicalAliasToSubKey[normalized];
    subKey ??= _findExistingSubKeyByNormalized(normalized);

    if (subKey == null || subKey.isEmpty) return null;

    final catKey = _findCategoryForSubKey(subKey);
    if (catKey == null) return null;

    final mainKey = _findMainGroupForCategory(catKey);
    if (mainKey == null) return null;

    final layerRole = subCategoryLayerRoles[subKey] ?? _fallbackLayerRoleForSubKey(subKey);

    return AiMappedCategory(
      mainGroupKey: mainKey,
      categoryKey: catKey,
      subCategoryKey: subKey,
      layerRole: layerRole,
    );
  }

  static AiMappedCategory? mapType(AiParserInput input) {
    final combined = [
      input.rawType,
      input.aiName,
      input.userName,
      input.brand,
      input.seasons.join(' '),
    ].join(' ');

    final t = _norm(combined);

    // 1) veľmi špecifické
    if (_hasAny(t, ['undershirt', 'under shirt', 'spodne tielko', 'spodné tielko', 'base layer'])) {
      return fromCanonicalType('undershirt');
    }

    if (_hasAny(t, ['sports bra', 'sport bra', 'sportova podprsenka', 'športová podprsenka'])) {
      return fromCanonicalType('sport_podprsenka');
    }

    if (_hasAny(t, ['softshell'])) {
      return fromCanonicalType('softshell_bunda');
    }

    // 2) šaty / overaly
    if (_hasAny(t, ['bodycon dress', 'bodycon saty', 'bodycon šaty'])) {
      return fromCanonicalType('saty_bodycon');
    }
    if (_hasAny(t, ['shirt dress', 'koselove saty', 'košeľové šaty'])) {
      return fromCanonicalType('saty_koselove');
    }
    if (_hasAny(t, ['maxi dress', 'maxi saty', 'maxi šaty'])) {
      return fromCanonicalType('saty_maxi');
    }
    if (_hasAny(t, ['midi dress', 'midi saty', 'midi šaty'])) {
      return fromCanonicalType('saty_midi');
    }
    if (_hasAny(t, ['mini dress', 'short dress', 'kratke saty', 'krátke šaty'])) {
      return fromCanonicalType('saty_kratke');
    }
    if (_hasAny(t, ['dress', 'saty', 'šaty'])) {
      return fromCanonicalType('saty');
    }
    if (_hasAny(t, ['jumpsuit', 'playsuit', 'romper', 'overal'])) {
      return fromCanonicalType('overal');
    }

    // 3) nohavice / spodok
    if (_hasAny(t, ['skinny jeans'])) {
      return fromCanonicalType('rifle_skinny');
    }
    if (_hasAny(t, ['wide leg jeans', 'wideleg jeans', 'wide leg'])) {
      return fromCanonicalType('rifle_wide_leg');
    }
    if (_hasAny(t, ['mom jeans', 'mom fit'])) {
      return fromCanonicalType('rifle_mom');
    }
    if (_hasAny(t, ['jeans', 'rifle', 'denim'])) {
      return fromCanonicalType('rifle');
    }

    if (_hasAny(t, ['cargo'])) {
      return fromCanonicalType('nohavice_cargo');
    }
    if (_hasAny(t, ['joggers', 'joggery', 'jogger'])) {
      return fromCanonicalType('nohavice_joggery');
    }
    if (_hasAny(t, ['sweatpants', 'sweat pants', 'teplaky', 'tepláky', 'teplakove'])) {
      return fromCanonicalType('nohavice_teplakove');
    }
    if (_hasAny(t, ['chino', 'chinos'])) {
      return fromCanonicalType('nohavice_chino');
    }
    if (_hasAny(t, ['formal trousers', 'dress pants', 'elegantne nohavice', 'elegantné nohavice', 'slacks'])) {
      return fromCanonicalType('nohavice_elegantne');
    }
    if (_hasAny(t, ['leggings', 'leginy', 'legíny', 'legging'])) {
      if (_hasAny(t, ['sport', 'gym', 'workout', 'training', 'running'])) {
        return fromCanonicalType('sport_leginy');
      }
      return fromCanonicalType('leginy');
    }
    if (_hasAny(t, ['running shorts', 'gym shorts', 'athletic shorts', 'sport shorts', 'sportove sortky', 'športové šortky'])) {
      return fromCanonicalType('sortky_sportove');
    }
    if (_hasAny(t, ['shorts', 'sortky', 'šortky'])) {
      return fromCanonicalType('sortky');
    }
    if (_hasAny(t, ['mini skirt', 'mini sukna', 'mini sukňa'])) {
      return fromCanonicalType('sukna_mini');
    }
    if (_hasAny(t, ['midi skirt', 'midi sukna', 'midi sukňa'])) {
      return fromCanonicalType('sukna_midi');
    }
    if (_hasAny(t, ['maxi skirt', 'maxi sukna', 'maxi sukňa'])) {
      return fromCanonicalType('sukna_maxi');
    }
    if (_hasAny(t, ['skirt', 'sukna', 'sukňa'])) {
      return fromCanonicalType('sukna');
    }
    if (_hasAny(t, ['pants', 'trousers', 'nohavice'])) {
      return fromCanonicalType('nohavice_klasicke');
    }

    // 4) topy
    if (_hasAny(t, ['blouse', 'bluzka', 'blúzka', 'halenka'])) {
      return fromCanonicalType('bluzka');
    }
    if (_hasAny(t, ['corset', 'korzet'])) {
      return fromCanonicalType('korzet_top');
    }
    if (_hasAny(t, ['bodysuit', 'body'])) {
      return fromCanonicalType('body');
    }
    if (_hasAny(t, ['crop top', 'croptop'])) {
      return fromCanonicalType('crop_top');
    }
    if (_hasAny(t, ['polo'])) {
      return fromCanonicalType('polo_tricko');
    }
    if (_hasAny(t, ['tank top', 'tanktop', 'tielko', 'sleeveless', 'bezrukavove', 'bezrukávové', 'bez rukavov'])) {
      return fromCanonicalType('tielko');
    }
    if (_hasAny(t, ['long sleeve', 'longsleeve', 'dlhy rukav', 'dlhym rukavom'])) {
      return fromCanonicalType('tricko_dlhy_rukav');
    }
    if (_hasAny(t, ['t-shirt', 'tshirt', 'tee', 'tricko', 'tričko'])) {
      return fromCanonicalType('tricko');
    }
    if (_hasAny(t, ['top'])) {
      return fromCanonicalType('top_basic');
    }

    // 5) košele
    if (_hasAny(t, ['flannel shirt', 'flanelova kosela', 'flanelová košeľa', 'flanel shirt'])) {
      return fromCanonicalType('kosela_flanelova');
    }
    if (_hasAny(t, ['overshirt', 'shacket', 'oversized shirt', 'oversize kosela'])) {
      return fromCanonicalType('kosela_oversize');
    }
    if (_hasAny(t, ['shirt', 'kosela', 'košeľa', 'button up', 'button down'])) {
      return fromCanonicalType('kosela_klasicka');
    }

    // 6) mikiny / svetre
    if (_hasAny(t, ['zip hoodie', 'zip-up hoodie', 'zip up hoodie', 'mikina na zips'])) {
      return fromCanonicalType('mikina_na_zips');
    }
    if (_hasAny(t, ['hoodie', 'mikina s kapucnou', 'hooded sweatshirt'])) {
      return fromCanonicalType('mikina_s_kapucnou');
    }
    if (_hasAny(t, ['oversized sweatshirt', 'oversize hoodie', 'oversize mikina'])) {
      return fromCanonicalType('mikina_oversize');
    }
    if (_hasAny(t, ['sweatshirt', 'mikina', 'crewneck'])) {
      return fromCanonicalType('mikina_klasicka');
    }

    if (_hasAny(t, ['cardigan', 'kardigan'])) {
      return fromCanonicalType('sveter_kardigan');
    }
    if (_hasAny(t, ['turtleneck', 'roll neck', 'rolak', 'rolák'])) {
      return fromCanonicalType('sveter_rolak');
    }
    if (_hasAny(t, ['knit', 'knitted', 'pleteny sveter', 'pletený sveter', 'chunky knit', 'cable knit'])) {
      return fromCanonicalType('sveter_pleteny');
    }
    if (_hasAny(t, ['sweater', 'jumper', 'pullover', 'sveter'])) {
      return fromCanonicalType('sveter_klasicky');
    }

    // 7) bundy
    if (_hasAny(t, ['denim jacket', 'jean jacket', 'riflova bunda', 'rifľová bunda'])) {
      return fromCanonicalType('bunda_riflova');
    }
    if (_hasAny(t, ['leather jacket', 'biker jacket', 'kozena bunda', 'kožená bunda'])) {
      return fromCanonicalType('bunda_kozena');
    }
    if (_hasAny(t, ['bomber'])) {
      return fromCanonicalType('bunda_bomber');
    }
    if (_hasAny(t, ['puffer', 'parka', 'down jacket', 'zimna bunda', 'zimná bunda', 'winter jacket'])) {
      return fromCanonicalType('bunda_zimna');
    }
    if (_hasAny(t, ['raincoat', 'rain jacket', 'prsiplast', 'pršiplášť'])) {
      return fromCanonicalType('prsiplast');
    }
    if (_hasAny(t, ['fleece', 'flis', 'flís'])) {
      return fromCanonicalType('flisova_bunda');
    }
    if (_hasAny(t, ['trench', 'trenchcoat'])) {
      return fromCanonicalType('trenchcoat');
    }
    if (_hasAny(t, ['coat', 'kabat', 'kabát'])) {
      return fromCanonicalType('kabat');
    }
    if (_hasAny(t, ['blazer', 'sako', 'blejzer'])) {
      return fromCanonicalType('sako');
    }
    if (_hasAny(t, ['vest', 'vesta', 'waistcoat', 'gilet'])) {
      return fromCanonicalType('vesta');
    }
    if (_hasAny(t, ['jacket', 'bunda'])) {
      return fromCanonicalType('bunda_prechodna');
    }

    // 8) obuv
    if (_hasAny(t, ['running shoes', 'bezecke tenisky', 'bežecké tenisky'])) {
      return fromCanonicalType('tenisky_bezecke');
    }
    if (_hasAny(t, ['gym shoes', 'training shoes', 'sport sneakers', 'sportove tenisky', 'športové tenisky'])) {
      return fromCanonicalType('tenisky_sportove');
    }
    if (_hasAny(t, ['sneakers', 'sneaker', 'tenisky'])) {
      return fromCanonicalType('tenisky_fashion');
    }

    if (_hasAny(t, ['over the knee boots', 'thigh high boots', 'cizmy nad kolena', 'čižmy nad kolená'])) {
      return fromCanonicalType('cizmy_nad_kolena');
    }
    if (_hasAny(t, ['high boots', 'knee boots', 'vysoke cizmy', 'vysoké čižmy'])) {
      return fromCanonicalType('cizmy_vysoke');
    }
    if (_hasAny(t, ['snow boots', 'winter boots', 'snehule'])) {
      return fromCanonicalType('snehule');
    }
    if (_hasAny(t, ['rain boots', 'gumaky', 'gumáky', 'wellington boots'])) {
      return fromCanonicalType('gumaky');
    }
    if (_hasAny(t, ['boots', 'boot', 'cizmy', 'čižmy'])) {
      return fromCanonicalType('cizmy_clenkove');
    }

    if (_hasAny(t, ['heeled sandals', 'sandale na opatku', 'sandále na opätku'])) {
      return fromCanonicalType('sandale_opatok');
    }
    if (_hasAny(t, ['sandals', 'sandale', 'sandále'])) {
      return fromCanonicalType('sandale');
    }
    if (_hasAny(t, ['flip flops', 'flipflops', 'zabky', 'žabky'])) {
      return fromCanonicalType('zabky');
    }
    if (_hasAny(t, ['slippers', 'slides', 'slapky', 'šľapky'])) {
      return fromCanonicalType('slapky');
    }
    if (_hasAny(t, ['espadrilles', 'espadrilky'])) {
      return fromCanonicalType('espadrilky');
    }

    if (_hasAny(t, ['heels', 'high heels', 'pumps', 'lodicky', 'lodičky'])) {
      return fromCanonicalType('lodicky');
    }
    if (_hasAny(t, ['loafers', 'loafer', 'mokasiny', 'mokasíny'])) {
      return fromCanonicalType('mokasiny');
    }
    if (_hasAny(t, ['flats', 'ballet flats', 'balerinky'])) {
      return fromCanonicalType('balerinky');
    }
    if (_hasAny(t, ['oxfords', 'derby shoes', 'poltopanky', 'poltopánky'])) {
      return fromCanonicalType('poltopanky');
    }
    if (_hasAny(t, ['platform shoes', 'platform sandals'])) {
      return fromCanonicalType('obuv_platforma');
    }

    // 9) doplnky
    if (_hasAny(t, ['baseball cap', 'snapback', 'cap', 'siltovka', 'šiltovka'])) {
      return fromCanonicalType('siltovka');
    }
    if (_hasAny(t, ['bucket hat', 'sun hat', 'klobuk', 'klobúk', 'hat'])) {
      return fromCanonicalType('bucket_hat');
    }
    if (_hasAny(t, ['beanie', 'ciapka', 'čiapka'])) {
      return fromCanonicalType('ciapka');
    }

    if (_hasAny(t, ['scarf', 'sal', 'šál'])) {
      return fromCanonicalType('sal');
    }
    if (_hasAny(t, ['shawl', 'bandana', 'satka', 'šatka'])) {
      return fromCanonicalType('satka');
    }
    if (_hasAny(t, ['gloves', 'rukavice'])) {
      return fromCanonicalType('rukavice');
    }

    if (_hasAny(t, ['crossbody', 'crossbody bag'])) {
      return fromCanonicalType('taska_crossbody');
    }
    if (_hasAny(t, ['backpack', 'ruksak'])) {
      return fromCanonicalType('ruksak');
    }
    if (_hasAny(t, ['clutch', 'clutch bag', 'listova kabelka', 'listová kabelka'])) {
      return fromCanonicalType('kabelka_listova');
    }
    if (_hasAny(t, ['belt bag', 'fanny pack', 'waist bag', 'ladvinka', 'ľadvinka'])) {
      return fromCanonicalType('ladvinka');
    }
    if (_hasAny(t, ['handbag', 'purse', 'kabelka', 'bag'])) {
      return fromCanonicalType('kabelka');
    }

    if (_hasAny(t, ['sunglasses', 'slnecne okuliare', 'slnečné okuliare'])) {
      return fromCanonicalType('slnecne_okuliare');
    }
    if (_hasAny(t, ['belt', 'opasok'])) {
      return fromCanonicalType('opasok');
    }
    if (_hasAny(t, ['wallet', 'penazenka', 'peňaženka'])) {
      return fromCanonicalType('penazenka');
    }
    if (_hasAny(t, ['watch', 'hodinky'])) {
      return fromCanonicalType('hodinky');
    }
    if (_hasAny(t, ['jewelry', 'jewellery', 'sperky', 'šperky'])) {
      return fromCanonicalType('sperky');
    }

    // 10) šport
    if (_hasAny(t, ['tracksuit', 'teplakova suprava', 'tepláková súprava'])) {
      return fromCanonicalType('sport_suprava');
    }
    if (_hasAny(t, ['sport bag', 'gym bag', 'duffel bag'])) {
      return fromCanonicalType('sport_taska');
    }
    if (_hasAny(t, ['wristband', 'sweatband', 'potitka', 'potítka'])) {
      return fromCanonicalType('potitka');
    }

    return null;
  }

  static String _norm(String s) {
    var out = s.toLowerCase().trim();

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

    final b = StringBuffer();
    for (final ch in out.split('')) {
      b.write(repl[ch] ?? ch);
    }

    out = b.toString();
    out = out.replaceAll('_', ' ');
    out = out.replaceAll('-', ' ');
    out = out.replaceAll('/', ' ');
    out = out.replaceAll('\n', ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ');
    return out.trim();
  }

  static bool _hasAny(String text, List<String> needles) {
    for (final n in needles) {
      if (text.contains(_norm(n))) return true;
    }
    return false;
  }

  static String? _findExistingSubKeyByNormalized(String normalizedInput) {
    for (final entry in subCategoryTree.entries) {
      for (final subKey in entry.value) {
        if (_norm(subKey) == normalizedInput) return subKey;
      }
    }
    return null;
  }

  static String? _findCategoryForSubKey(String subKey) {
    for (final entry in subCategoryTree.entries) {
      if (entry.value.contains(subKey)) return entry.key;
    }
    return null;
  }

  static String? _findMainGroupForCategory(String categoryKey) {
    for (final entry in categoryTree.entries) {
      if (entry.value.contains(categoryKey)) return entry.key;
    }
    return null;
  }

  static String _fallbackLayerRoleForSubKey(String subKey) {
    if (subCategoryTree['tricka_topy']?.contains(subKey) == true) {
      return subKey == 'undershirt' ? 'base_layer' : 'main_top';
    }
    if (subCategoryTree['kosele']?.contains(subKey) == true) return 'main_top';
    if (subCategoryTree['mikiny']?.contains(subKey) == true) return 'outer_layer';
    if (subCategoryTree['svetre']?.contains(subKey) == true) return 'main_top';
    if (subCategoryTree['bundy_kabaty']?.contains(subKey) == true) return 'outer_layer';
    if (subCategoryTree['nohavice_rifle']?.contains(subKey) == true) {
      return (subKey == 'leginy') ? 'base_bottom' : 'main_bottom';
    }
    if (subCategoryTree['sortky_sukne']?.contains(subKey) == true) return 'main_bottom';
    if (subCategoryTree['saty_overaly']?.contains(subKey) == true) return 'one_piece';
    if (subCategoryTree['tenisky']?.contains(subKey) == true) return 'footwear';
    if (subCategoryTree['elegantna_obuv']?.contains(subKey) == true) return 'footwear';
    if (subCategoryTree['cizmy']?.contains(subKey) == true) return 'footwear';
    if (subCategoryTree['letna_obuv']?.contains(subKey) == true) return 'footwear';
    if (subCategoryTree['sport_obuv_doplnky']?.contains(subKey) == true) {
      if (subKey == 'obuv_treningova' || subKey == 'obuv_turisticka') return 'footwear';
      return 'accessory';
    }
    if (subCategoryTree['dopl_hlava']?.contains(subKey) == true) return 'accessory';
    if (subCategoryTree['dopl_saly_rukavice']?.contains(subKey) == true) return 'accessory';
    if (subCategoryTree['dopl_tasky']?.contains(subKey) == true) return 'accessory';
    if (subCategoryTree['dopl_ostatne']?.contains(subKey) == true) return 'accessory';
    if (subCategoryTree['sport_oblecenie']?.contains(subKey) == true) {
      if (subKey == 'sport_leginy') return 'base_bottom';
      if (subKey == 'sport_sortky') return 'main_bottom';
      if (subKey == 'sport_suprava') return 'one_piece';
      if (subKey == 'sport_mikina' || subKey == 'softshell_bunda') return 'outer_layer';
      return 'main_top';
    }

    return 'main_top';
  }
}