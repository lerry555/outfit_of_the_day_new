import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// ZÁKLADNÉ KONŠTANTY
/// ---------------------------------------------------------------------------

const List<String> categories = [
  'Vrch',
  'Spodok',
  'Obuv',
  'Doplnky',
];

const List<String> colors = [
  'biela',
  'čierna',
  'sivá',
  'béžová',
  'hnedá',
  'modrá',
  'tmavomodrá',
  'svetlomodrá',
  'červená',
  'bordová',
  'ružová',
  'fialová',
  'zelená',
  'khaki',
  'žltá',
  'oranžová',
  'zlatá',
  'strieborná',
];

const List<String> styles = [
  'casual',
  'streetwear',
  'sport',
  'elegant',
  'smart casual',

  // legacy kompatibilita
  'športový',
  'sportový',
  'elegantný',
  'business',
  'homewear',
  'party',
];

const List<String> patterns = [
  'jednofarebné',
  'textová potlač',
  'grafická potlač',
  'pruhované',
  'kockované',
  'kamufláž',
];

const List<String> seasons = [
  'jar',
  'leto',
  'jeseň',
  'zima',
  'celoročne',
];

const List<String> allowedColors = colors;
const List<String> allowedStyles = styles;
const List<String> allowedPatterns = patterns;
const List<String> allowedSeasons = seasons;

/// ---------------------------------------------------------------------------
/// LAYER ROLE – interné sloty pre outfit skladanie
/// ---------------------------------------------------------------------------

const List<String> layerRoles = [
  'base_layer',
  'main_top',
  'outer_layer',
  'base_bottom',
  'main_bottom',
  'one_piece',
  'footwear',
  'accessory',
];

/// ---------------------------------------------------------------------------
/// STARÝ JEDNODUCHÝ SCREEN – kompatibilita
/// ---------------------------------------------------------------------------

const Map<String, List<String>> subcategoriesByCategory = {
  'Vrch': [
    'Tričko s krátkym rukávom',
    'Tričko s dlhým rukávom',
    'Tielko',
    'Spodné tielko',
    'Top',
    'Crop top',
    'Body',
    'Blúzka',
    'Košeľa',
    'Mikina',
    'Sveter',
    'Rolák',
    'Kardigan',
    'Sako / blejzer',
    'Vesta',
    'Bunda',
    'Kabát',
  ],
  'Spodok': [
    'Rifle',
    'Skinny rifle',
    'Rifle wide leg',
    'Mom jeans',
    'Nohavice',
    'Elegantné nohavice',
    'Chino nohavice',
    'Teplákové nohavice',
    'Joggery',
    'Legíny',
    'Športové legíny',
    'Šortky',
    'Športové šortky',
    'Sukňa',
    'Mini sukňa',
    'Midi sukňa',
    'Maxi sukňa',
    'Šaty',
    'Overal',
  ],
  'Obuv': [
    'Fashion tenisky',
    'Športové tenisky',
    'Bežecké tenisky',
    'Členkové čižmy',
    'Vysoké čižmy',
    'Čižmy nad kolená',
    'Sandále',
    'Sandále na opätku',
    'Šľapky',
    'Žabky',
    'Poltopánky',
    'Mokasíny',
    'Lodičky',
    'Balerínky',
  ],
  'Doplnky': [
    'Čiapka',
    'Šiltovka',
    'Bucket hat',
    'Šál',
    'Šatka',
    'Rukavice',
    'Slnečné okuliare',
    'Kabelka',
    'Crossbody taška',
    'Ruksak',
    'Listová kabelka',
    'Ľadvinka',
    'Opasok',
    'Hodinky',
    'Šperky',
  ],
};

/// ---------------------------------------------------------------------------
/// PROFESIONÁLNY STROM
/// ---------------------------------------------------------------------------

const Map<String, String> mainCategoryGroups = {
  'oblecenie': 'Oblečenie',
  'obuv': 'Obuv',
  'doplnky': 'Doplnky',
};

const Map<String, List<String>> categoryTree = {
  'oblecenie': [
    'tricka_topy',
    'kosele',
    'mikiny',
    'svetre',
    'bundy_kabaty',
    'nohavice_rifle',
    'sortky_sukne',
    'saty_overaly',
    'sport_oblecenie',
  ],
  'obuv': [
    'tenisky',
    'elegantna_obuv',
    'cizmy',
    'letna_obuv',
    'sport_obuv_doplnky',
  ],
  'doplnky': [
    'dopl_hlava',
    'dopl_saly_rukavice',
    'dopl_tasky',
    'dopl_ostatne',
  ],
};

const Map<String, String> categoryLabels = {
  'tricka_topy': 'Tričká & topy',
  'kosele': 'Košele',
  'mikiny': 'Mikiny',
  'svetre': 'Svetre',
  'bundy_kabaty': 'Bundy & kabáty',
  'nohavice_rifle': 'Nohavice',
  'sortky_sukne': 'Šortky & sukne',
  'saty_overaly': 'Šaty & overaly',
  'sport_oblecenie': 'Šport – oblečenie',

  'tenisky': 'Tenisky',
  'elegantna_obuv': 'Elegantná obuv',
  'cizmy': 'Čižmy',
  'letna_obuv': 'Letná obuv',
  'sport_obuv_doplnky': 'Šport – obuv + doplnky',

  'dopl_hlava': 'Doplnky – hlava',
  'dopl_saly_rukavice': 'Doplnky – šály, rukavice',
  'dopl_tasky': 'Doplnky – tašky',
  'dopl_ostatne': 'Doplnky – ostatné',
};

const Map<String, List<String>> subCategoryTree = {
  'tricka_topy': [
    'tricko',
    'tricko_dlhy_rukav',
    'tielko',
    'undershirt',
    'top_basic',
    'crop_top',
    'polo_tricko',
    'body',
    'korzet_top',
    'bluzka',
  ],
  'kosele': [
    'kosela_klasicka',
    'kosela_oversize',
    'kosela_flanelova',
  ],
  'mikiny': [
    'mikina_klasicka',
    'mikina_na_zips',
    'mikina_s_kapucnou',
    'mikina_oversize',
  ],
  'svetre': [
    'sveter_klasicky',
    'sveter_rolak',
    'sveter_kardigan',
    'sveter_pleteny',
  ],
  'bundy_kabaty': [
    'bunda_riflova',
    'bunda_kozena',
    'bunda_bomber',
    'bunda_prechodna',
    'bunda_zimna',
    'kabat',
    'trenchcoat',
    'sako',
    'vesta',
    'prsiplast',
    'flisova_bunda',
  ],
  'nohavice_rifle': [
    'rifle',
    'rifle_skinny',
    'rifle_wide_leg',
    'rifle_mom',
    'nohavice_klasicke',
    'nohavice_chino',
    'nohavice_teplakove',
    'nohavice_joggery',
    'nohavice_elegantne',
    'nohavice_cargo',
    'leginy',
  ],
  'sortky_sukne': [
    'sortky',
    'sortky_sportove',
    'sukna',
    'sukna_mini',
    'sukna_midi',
    'sukna_maxi',
  ],
  'saty_overaly': [
    'saty',
    'saty_kratke',
    'saty_midi',
    'saty_maxi',
    'saty_koselove',
    'saty_bodycon',
    'overal',
  ],
  'tenisky': [
    'tenisky_fashion',
    'tenisky_sportove',
    'tenisky_bezecke',
  ],
  'elegantna_obuv': [
    'lodicky',
    'sandale_opatok',
    'balerinky',
    'mokasiny',
    'poltopanky',
    'obuv_platforma',
  ],
  'cizmy': [
    'cizmy_clenkove',
    'cizmy_vysoke',
    'cizmy_nad_kolena',
    'gumaky',
    'snehule',
  ],
  'letna_obuv': [
    'sandale',
    'slapky',
    'zabky',
    'espadrilky',
  ],
  'dopl_hlava': [
    'ciapka',
    'siltovka',
    'bucket_hat',
  ],
  'dopl_saly_rukavice': [
    'sal',
    'satka',
    'rukavice',
  ],
  'dopl_tasky': [
    'kabelka',
    'taska_crossbody',
    'ruksak',
    'kabelka_listova',
    'ladvinka',
  ],
  'dopl_ostatne': [
    'slnecne_okuliare',
    'opasok',
    'penazenka',
    'hodinky',
    'sperky',
  ],
  'sport_oblecenie': [
    'sport_tricko',
    'sport_mikina',
    'sport_leginy',
    'sport_sortky',
    'sport_suprava',
    'softshell_bunda',
    'sport_podprsenka',
  ],
  'sport_obuv_doplnky': [
    'obuv_treningova',
    'obuv_turisticka',
    'sport_taska',
    'potitka',
  ],
};

const Map<String, String> subCategoryLabels = {
  // Tričká & topy
  'tricko': 'Tričko s krátkym rukávom',
  'tricko_dlhy_rukav': 'Tričko s dlhým rukávom',
  'tielko': 'Tielko',
  'undershirt': 'Spodné tielko',
  'top_basic': 'Top',
  'crop_top': 'Crop top',
  'polo_tricko': 'Polo tričko',
  'body': 'Body',
  'korzet_top': 'Korzet (top)',
  'bluzka': 'Blúzka',

  // Košele
  'kosela_klasicka': 'Klasická košeľa',
  'kosela_oversize': 'Oversize košeľa',
  'kosela_flanelova': 'Flanelová košeľa',

  // Mikiny
  'mikina_klasicka': 'Mikina',
  'mikina_na_zips': 'Mikina na zips',
  'mikina_s_kapucnou': 'Mikina s kapucňou',
  'mikina_oversize': 'Oversize mikina',

  // Svetre
  'sveter_klasicky': 'Sveter',
  'sveter_rolak': 'Rolák',
  'sveter_kardigan': 'Kardigan',
  'sveter_pleteny': 'Pletený sveter',

  // Bundy & kabáty
  'bunda_riflova': 'Rifľová bunda',
  'bunda_kozena': 'Kožená bunda',
  'bunda_bomber': 'Bomber bunda',
  'bunda_prechodna': 'Prechodná bunda',
  'bunda_zimna': 'Zimná bunda',
  'kabat': 'Kabát',
  'trenchcoat': 'Trenchcoat',
  'sako': 'Sako / blejzer',
  'vesta': 'Vesta',
  'prsiplast': 'Pršiplášť',
  'flisova_bunda': 'Flísová bunda',

  // Nohavice & rifle
  'rifle': 'Rifle',
  'rifle_skinny': 'Skinny rifle',
  'rifle_wide_leg': 'Rifle wide leg',
  'rifle_mom': 'Mom jeans',
  'nohavice_klasicke': 'Nohavice',
  'nohavice_chino': 'Chino nohavice',
  'nohavice_teplakove': 'Teplákové nohavice',
  'nohavice_joggery': 'Joggery',
  'nohavice_elegantne': 'Elegantné nohavice',
  'nohavice_cargo': 'Cargo nohavice',
  'leginy': 'Legíny',

  // Šortky & sukne
  'sortky': 'Šortky',
  'sortky_sportove': 'Športové šortky',
  'sukna': 'Sukňa',
  'sukna_mini': 'Mini sukňa',
  'sukna_midi': 'Midi sukňa',
  'sukna_maxi': 'Maxi sukňa',

  // Šaty & overaly
  'saty': 'Šaty',
  'saty_kratke': 'Krátke šaty',
  'saty_midi': 'Midi šaty',
  'saty_maxi': 'Maxi šaty',
  'saty_koselove': 'Košeľové šaty',
  'saty_bodycon': 'Bodycon šaty',
  'overal': 'Overal',

  // Obuv – tenisky
  'tenisky_fashion': 'Fashion tenisky',
  'tenisky_sportove': 'Športové tenisky',
  'tenisky_bezecke': 'Bežecké tenisky',

  // Obuv – elegantná
  'lodicky': 'Lodičky',
  'sandale_opatok': 'Sandále na opätku',
  'balerinky': 'Balerínky',
  'mokasiny': 'Mokasíny',
  'poltopanky': 'Poltopánky',
  'obuv_platforma': 'Obuv na platforme',

  // Obuv – čižmy
  'cizmy_clenkove': 'Členkové čižmy',
  'cizmy_vysoke': 'Vysoké čižmy',
  'cizmy_nad_kolena': 'Čižmy nad kolená',
  'gumaky': 'Gumáky',
  'snehule': 'Snehule',

  // Obuv – letná
  'sandale': 'Sandále',
  'slapky': 'Šľapky',
  'zabky': 'Žabky',
  'espadrilky': 'Espadrilky',

  // Doplnky – hlava
  'ciapka': 'Čiapka',
  'siltovka': 'Šiltovka',
  'bucket_hat': 'Bucket hat',

  // Doplnky – šály, rukavice
  'sal': 'Šál',
  'satka': 'Šatka',
  'rukavice': 'Rukavice',

  // Doplnky – tašky
  'kabelka': 'Kabelka',
  'taska_crossbody': 'Crossbody taška',
  'ruksak': 'Ruksak',
  'kabelka_listova': 'Listová kabelka',
  'ladvinka': 'Ľadvinka',

  // Doplnky – ostatné
  'slnecne_okuliare': 'Slnečné okuliare',
  'opasok': 'Opasok',
  'penazenka': 'Peňaženka',
  'hodinky': 'Hodinky',
  'sperky': 'Šperky',

  // Šport
  'sport_tricko': 'Športové tričko',
  'sport_mikina': 'Funkčná mikina',
  'sport_leginy': 'Športové legíny',
  'sport_sortky': 'Športové kraťasy',
  'sport_suprava': 'Tepláková súprava',
  'softshell_bunda': 'Softshell bunda',
  'sport_podprsenka': 'Športová podprsenka',
  'obuv_treningova': 'Tréningová obuv',
  'obuv_turisticka': 'Turistická obuv',
  'sport_taska': 'Športová taška',
  'potitka': 'Potítka',
};

/// ---------------------------------------------------------------------------
/// Layer role podľa subCategoryKey
/// ---------------------------------------------------------------------------

const Map<String, String> subCategoryLayerRoles = {
  // top base layer
  'undershirt': 'base_layer',

  // main top
  'tricko': 'main_top',
  'tricko_dlhy_rukav': 'main_top',
  'tielko': 'main_top',
  'top_basic': 'main_top',
  'crop_top': 'main_top',
  'polo_tricko': 'main_top',
  'body': 'main_top',
  'korzet_top': 'main_top',
  'bluzka': 'main_top',
  'kosela_klasicka': 'main_top',
  'kosela_oversize': 'main_top',
  'kosela_flanelova': 'main_top',
  'sveter_klasicky': 'main_top',
  'sveter_rolak': 'main_top',
  'sveter_kardigan': 'main_top',
  'sveter_pleteny': 'main_top',
  'sport_tricko': 'main_top',
  'sport_podprsenka': 'main_top',

  // outer layer
  'mikina_klasicka': 'outer_layer',
  'mikina_na_zips': 'outer_layer',
  'mikina_s_kapucnou': 'outer_layer',
  'mikina_oversize': 'outer_layer',
  'bunda_riflova': 'outer_layer',
  'bunda_kozena': 'outer_layer',
  'bunda_bomber': 'outer_layer',
  'bunda_prechodna': 'outer_layer',
  'bunda_zimna': 'outer_layer',
  'kabat': 'outer_layer',
  'trenchcoat': 'outer_layer',
  'sako': 'outer_layer',
  'vesta': 'outer_layer',
  'prsiplast': 'outer_layer',
  'flisova_bunda': 'outer_layer',
  'sport_mikina': 'outer_layer',
  'softshell_bunda': 'outer_layer',

  // base bottom
  'leginy': 'base_bottom',
  'sport_leginy': 'base_bottom',

  // main bottom
  'rifle': 'main_bottom',
  'rifle_skinny': 'main_bottom',
  'rifle_wide_leg': 'main_bottom',
  'rifle_mom': 'main_bottom',
  'nohavice_klasicke': 'main_bottom',
  'nohavice_chino': 'main_bottom',
  'nohavice_teplakove': 'main_bottom',
  'nohavice_joggery': 'main_bottom',
  'nohavice_elegantne': 'main_bottom',
  'nohavice_cargo': 'main_bottom',
  'sortky': 'main_bottom',
  'sortky_sportove': 'main_bottom',
  'sukna': 'main_bottom',
  'sukna_mini': 'main_bottom',
  'sukna_midi': 'main_bottom',
  'sukna_maxi': 'main_bottom',

  // one piece
  'saty': 'one_piece',
  'saty_kratke': 'one_piece',
  'saty_midi': 'one_piece',
  'saty_maxi': 'one_piece',
  'saty_koselove': 'one_piece',
  'saty_bodycon': 'one_piece',
  'overal': 'one_piece',
  'sport_suprava': 'one_piece',

  // footwear
  'tenisky_fashion': 'footwear',
  'tenisky_sportove': 'footwear',
  'tenisky_bezecke': 'footwear',
  'lodicky': 'footwear',
  'sandale_opatok': 'footwear',
  'balerinky': 'footwear',
  'mokasiny': 'footwear',
  'poltopanky': 'footwear',
  'obuv_platforma': 'footwear',
  'cizmy_clenkove': 'footwear',
  'cizmy_vysoke': 'footwear',
  'cizmy_nad_kolena': 'footwear',
  'gumaky': 'footwear',
  'snehule': 'footwear',
  'sandale': 'footwear',
  'slapky': 'footwear',
  'zabky': 'footwear',
  'espadrilky': 'footwear',
  'obuv_treningova': 'footwear',
  'obuv_turisticka': 'footwear',

  // accessory
  'ciapka': 'accessory',
  'siltovka': 'accessory',
  'bucket_hat': 'accessory',
  'sal': 'accessory',
  'satka': 'accessory',
  'rukavice': 'accessory',
  'kabelka': 'accessory',
  'taska_crossbody': 'accessory',
  'ruksak': 'accessory',
  'kabelka_listova': 'accessory',
  'ladvinka': 'accessory',
  'slnecne_okuliare': 'accessory',
  'opasok': 'accessory',
  'penazenka': 'accessory',
  'hodinky': 'accessory',
  'sperky': 'accessory',
  'sport_taska': 'accessory',
  'potitka': 'accessory',
};

const List<String> premiumBrands = [
  'Nike',
  'Adidas',
  'Puma',
  'Calvin Klein',
  'Tommy Hilfiger',
  'Hugo Boss',
  'Ralph Lauren',
  'Armani',
  'Guess',
  'Lacoste',
];