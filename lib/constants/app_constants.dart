// lib/constants/app_constants.dart

import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// ZÁKLADNÉ KONŠTANTY, ktoré už používa appka (AddClothingScreen, šatník...)
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
  // nové (AI)
  'casual',
  'streetwear',
  'sport',
  'elegant',
  'smart casual',

  // staršie/legacy (kvôli existujúcim uloženým dátam)
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

// Alias, aby sedeli názvy v AddClothingScreen:
const List<String> allowedColors = colors;
const List<String> allowedStyles = styles;
const List<String> allowedPatterns = patterns;
const List<String> allowedSeasons = seasons;

/// Toto používa tvoj starý jednoduchý AddClothingScreen pre hlavnú kategóriu.
const Map<String, List<String>> subcategoriesByCategory = {
  'Vrch': [
    'Tričko s krátkym rukávom',
    'Tričko s dlhým rukávom',
    'Tielko',
    'Košeľa',
    'Mikina',
    'Sveter',
    'Rolák',
    'Top',
    'Blúzka',
    'Kardigan',
  ],
  'Spodok': [
    'Rifle',
    'Nohavice',
    'Chino nohavice',
    'Tepláky',
    'Joggery',
    'Šortky',
    'Sukňa',
    'Legíny',
  ],
  'Obuv': [
    'Tenisky',
    'Členkové čižmy',
    'Vysoké čižmy',
    'Kozačky',
    'Sandále',
    'Šľapky',
    'Žabky',
    'Poltopánky',
  ],
  'Doplnky': [
    'Čiapka',
    'Šiltovka',
    'Šál',
    'Rukavice',
    'Okuliare',
    'Kabelka',
    'Ruksak',
    'Opasok',
    'Hodinky',
    'Šperky',
  ],
};

/// ---------------------------------------------------------------------------
/// NOVÝ PROFESIONÁLNY STROM (mainGroup -> category -> subCategory)
/// ---------------------------------------------------------------------------

/// Hlavné skupiny
const Map<String, String> mainCategoryGroups = {
  'oblecenie': 'Oblečenie',
  'obuv': 'Obuv',
  'doplnky': 'Doplnky',
};

/// Kategórie v rámci hlavnej skupiny
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

/// Labely kategórií
const Map<String, String> categoryLabels = {
  'tricka_topy': 'Tričká & topy',
  'kosele': 'Košele',
  'mikiny': 'Mikiny',
  'svetre': 'Svetre',
  'bundy_kabaty': 'Bundy & kabáty',
  'nohavice_rifle': 'Nohavice & rifle',
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

/// Podkategórie v rámci kategórie
const Map<String, List<String>> subCategoryTree = {
  'tricka_topy': [
    'tricko',
    'tricko_dlhy_rukav',
    'tielko',
    'crop_top',
    'polo_tricko',
    'body',
    'korzet_top',
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
    'nohavice_chino',
    'nohavice_teplakove',
    'nohavice_joggery',
    'nohavice_elegantne',
    'nohavice_cargo',
  ],
  'sortky_sukne': [
    'sortky',
    'sortky_sportove',
    'sukna_mini',
    'sukna_midi',
    'sukna_maxi',
  ],
  'saty_overaly': [
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

/// Labely podkategórií (používaš v autocomplete názvu)
const Map<String, String> subCategoryLabels = {
  // Tričká & topy
  'tricko': 'Tričko s krátkym rukávom',
  'tricko_dlhy_rukav': 'Tričko s dlhým rukávom',
  'tielko': 'Tielko',
  'crop_top': 'Crop top',
  'polo_tricko': 'Polo tričko',
  'body': 'Body',
  'korzet_top': 'Korzet (top)',

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
  'nohavice_chino': 'Chino nohavice',
  'nohavice_teplakove': 'Teplákové nohavice',
  'nohavice_joggery': 'Joggery',
  'nohavice_elegantne': 'Elegantné nohavice',
  'nohavice_cargo': 'Cargo nohavice',

  // Šortky & sukne
  'sortky': 'Šortky',
  'sortky_sportove': 'Športové šortky',
  'sukna_mini': 'Mini sukňa',
  'sukna_midi': 'Midi sukňa',
  'sukna_maxi': 'Maxi sukňa',

  // Šaty & overaly
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
// Premium značky (používané v PremiumScreen)
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
