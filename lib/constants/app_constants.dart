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
  'casual',
  'streetwear',
  'sportový',
  'elegantný',
  'business',
  'homewear',
  'party',
];

const List<String> patterns = [
  'jednofarebné',
  'pruhované',
  'kockované',
  'bodkované',
  'kamufláž',
  'kvety',
  'grafická potlač',
];

const List<String> seasons = [
  'jar',
  'leto',
  'jeseň',
  'zima',
  'celoročne',
];

/// Toto používa tvoj AddClothingScreen pre jednoduché podkategórie.
/// Kľúč = hlavná kategória (Vrch/Spodok/Obuv/Doplnky), hodnota = zoznam typov.
const Map<String, List<String>> subcategoriesByCategory = {
  'Vrch': [
    'Tričko',
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
    'Legíny',
    'Šortky',
    'Sukňa',
    'Elegantné nohavice',
    'Cargo nohavice',
  ],
  'Obuv': [
    'Tenisky',
    'Bežecké tenisky',
    'Elegantné topánky',
    'Lodičky',
    'Sandále',
    'Šľapky',
    'Členkové čižmy',
    'Vysoké čižmy',
    'Kozačky',
    'Mokasíny',
    'Poltopánky',
  ],
  'Doplnky': [
    'Čiapka',
    'Šiltovka',
    'Zimná čiapka',
    'Šál',
    'Šatka',
    'Rukavice',
    'Kabelka',
    'Crossbody taška',
    'Ruksak',
    'Batoh',
    'Ľadvinka',
    'Listová kabelka',
    'Slnečné okuliare',
    'Opasok',
    'Peňaženka',
  ],
};

/// ---------------------------------------------------------------------------
///  PROFESIONÁLNY STROM KATEGÓRIÍ PRE CELOÚ APPKU (Recommended, Premium, AI)
/// ---------------------------------------------------------------------------

/// Hlavné skupiny – použijeme v Recommended & Premium
const Map<String, String> mainCategoryGroups = {
  'oblecenie': 'Oblečenie',
  'obuv': 'Obuv',
  'doplnky': 'Doplnky',
  'plavky': 'Plavky',
  'sport': 'Šport',
};

/// Druhá úroveň – ktoré kategórie patria do ktorej skupiny
const Map<String, List<String>> categoryTree = {
  'oblecenie': [
    'tricka_topy',
    'kosele',
    'mikiny',
    'svetre',
    'bundy_kabaty',
    'nohavice',
    'sortky_sukne',
    'saty_overaly',
  ],
  'obuv': [
    'tenisky',
    'elegantna_obuv',
    'cizmy',
    'letna_obuv',
  ],
  'doplnky': [
    'dopl_hlava',
    'dopl_saly_rukavice',
    'dopl_tasky',
    'dopl_ostatne',
  ],
  'plavky': [
    'plavky_damske',
    'plavky_panske',
    'plazove_doplnky',
  ],
  'sport': [
    'sport_oblecenie',
    'sport_obuv',
    'sport_doplnky',
  ],
};

/// Label pre kategórie (druhá úroveň)
const Map<String, String> categoryLabels = {
  // OBLEČENIE
  'tricka_topy': 'Tričká & topy',
  'kosele': 'Košele',
  'mikiny': 'Mikiny',
  'svetre': 'Svetre & roláky',
  'bundy_kabaty': 'Bundy & kabáty',
  'nohavice': 'Nohavice & rifle',
  'sortky_sukne': 'Šortky & sukne',
  'saty_overaly': 'Šaty & overaly',

  // OBUV
  'tenisky': 'Tenisky',
  'elegantna_obuv': 'Elegantná obuv',
  'cizmy': 'Čižmy',
  'letna_obuv': 'Letná obuv',

  // DOPLNKY
  'dopl_hlava': 'Čiapky & šiltovky',
  'dopl_saly_rukavice': 'Šály & rukavice',
  'dopl_tasky': 'Tašky & kabelky',
  'dopl_ostatne': 'Ostatné doplnky',

  // PLAVKY
  'plavky_damske': 'Dámske plavky',
  'plavky_panske': 'Pánske plavky',
  'plazove_doplnky': 'Plážové doplnky',

  // ŠPORT
  'sport_oblecenie': 'Športové oblečenie',
  'sport_obuv': 'Športová obuv',
  'sport_doplnky': 'Športové doplnky',
};

/// Tretia úroveň – konkrétne typy vecí v jednotlivých kategóriách.
/// Kľúče sú ID kategórií z [categoryLabels].
const Map<String, List<String>> subCategoryTree = {
  // OBLEČENIE -> TRIČKÁ & TOPY
  'tricka_topy': [
    'tricko',
    'tricko_dlhy_rukav',
    'tielko',
    'crop_top',
    'polo_tricko',
    'basic_tricko',
  ],

  // OBLEČENIE -> KOŠELE
  'kosele': [
    'kosela_klasicka',
    'kosela_oversize',
    'kosela_flanelova',
  ],

  // OBLEČENIE -> MIKINY
  'mikiny': [
    'mikina_klasicka',
    'mikina_na_zips',
    'mikina_s_kapucnou',
    'mikina_oversize',
  ],

  // OBLEČENIE -> SVETRE
  'svetre': [
    'sveter_klasicky',
    'sveter_rolak',
    'sveter_kardigan',
    'sveter_pleteny',
  ],

  // OBLEČENIE -> BUNDY & KABÁTY
  'bundy_kabaty': [
    'bunda_riflova',
    'bunda_kozena',
    'bunda_bomber',
    'bunda_prechodna',
    'bunda_zimna',
    'bunda_parka',
    'kabat',
    'trenchcoat',
    'bunda_puffer',
  ],

  // OBLEČENIE -> NOHAVICE & RIFLE
  'nohavice': [
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

  // OBLEČENIE -> ŠORTKY & SUKNE
  'sortky_sukne': [
    'sortky',
    'sortky_sportove',
    'sukna_mini',
    'sukna_midi',
    'sukna_maxi',
  ],

  // OBLEČENIE -> ŠATY & OVERALY
  'saty_overaly': [
    'saty_kratke',
    'saty_midi',
    'saty_maxi',
    'saty_koselove',
    'saty_bodycon',
    'overal',
  ],

  // OBUV -> TENISKY
  'tenisky': [
    'tenisky_fashion',
    'tenisky_sportove',
    'tenisky_bezecke',
  ],

  // OBUV -> ELEGANTNÁ
  'elegantna_obuv': [
    'lodicky',
    'sandale_opatok',
    'balerinky',
    'mokasiny',
    'poltopanky',
  ],

  // OBUV -> ČIŽMY
  'cizmy': [
    'cizmy_clenkove',
    'cizmy_vysoke',
    'kozacky',
    'cizmy_nad_kolena',
  ],

  // OBUV -> LETNÁ
  'letna_obuv': [
    'sandale',
    'slapky',
    'zabky',
    'espadrilky',
  ],

  // DOPLNKY -> HLAVA
  'dopl_hlava': [
    'ciapka',
    'ciapka_zimna',
    'siltovka',
    'bucket_hat',
  ],

  // DOPLNKY -> ŠÁLY, RUKAVICE
  'dopl_saly_rukavice': [
    'sal',
    'satka',
    'rukavice',
  ],

  // DOPLNKY -> TAŠKY & KABELKY
  'dopl_tasky': [
    'kabelka',
    'taska_crossbody',
    'ruksak',
    'batoh',
    'kabelka_listova',
    'ladvinka',
  ],

  // DOPLNKY -> OSTATNÉ
  'dopl_ostatne': [
    'slnecne_okuliare',
    'opasok',
    'penazenka',
  ],

  // PLAVKY -> DÁMSKE
  'plavky_damske': [
    'bikiny',
    'plavky_jednodielne',
    'plavkove_nohavicky',
    'plavkova_podprsenka',
    'tankiny',
  ],

  // PLAVKY -> PÁNSKE
  'plavky_panske': [
    'plavkove_sortky',
    'plavky_slipove',
  ],

  // PLAVKY -> PLÁŽOVÉ DOPLNKY
  'plazove_doplnky': [
    'pareo',
    'kaftan',
    'plazova_tunika',
  ],

  // ŠPORT -> OBLEČENIE
  'sport_oblecenie': [
    'sport_tricko',
    'sport_mikina',
    'sport_leginy',
    'sport_sortky',
    'sport_suprava',
    'softshell_bunda',
    'sport_podprsenka',
  ],

  // ŠPORT -> OBUV
  'sport_obuv': [
    'tenisky_bezecke',
    'obuv_treningova',
    'obuv_turisticka',
  ],

  // ŠPORT -> DOPLNKY
  'sport_doplnky': [
    'sport_taska',
    'potitka',
  ],
};

/// Label pre podkategórie (tretia úroveň) – všetky kľúče sú UNIKÁTNE
const Map<String, String> subCategoryLabels = {
  // TRIČKÁ & TOPY
  'tricko': 'Tričko',
  'tricko_dlhy_rukav': 'Tričko s dlhým rukávom',
  'tielko': 'Tielko',
  'crop_top': 'Crop top',
  'polo_tricko': 'Polo tričko',
  'basic_tricko': 'Basic tričko',

  // KOŠELE
  'kosela_klasicka': 'Klasická košeľa',
  'kosela_oversize': 'Oversize košeľa',
  'kosela_flanelova': 'Flanelová košeľa',

  // MIKINY
  'mikina_klasicka': 'Mikina',
  'mikina_na_zips': 'Mikina na zips',
  'mikina_s_kapucnou': 'Mikina s kapucňou',
  'mikina_oversize': 'Oversize mikina',

  // SVETRE
  'sveter_klasicky': 'Sveter',
  'sveter_rolak': 'Rolák',
  'sveter_kardigan': 'Kardigan',
  'sveter_pleteny': 'Pletený sveter',

  // BUNDY & KABÁTY
  'bunda_riflova': 'Rifľová bunda',
  'bunda_kozena': 'Kožená bunda',
  'bunda_bomber': 'Bomber bunda',
  'bunda_prechodna': 'Prechodná bunda',
  'bunda_zimna': 'Zimná bunda',
  'bunda_parka': 'Parka',
  'kabat': 'Kabát',
  'trenchcoat': 'Trenchcoat',
  'bunda_puffer': 'Puffer bunda',

  // NOHAVICE & RIFLE
  'rifle': 'Rifle',
  'rifle_skinny': 'Skinny rifle',
  'rifle_wide_leg': 'Rifle wide leg',
  'rifle_mom': 'Mom jeans',
  'nohavice_chino': 'Chino nohavice',
  'nohavice_teplakove': 'Teplákové nohavice',
  'nohavice_joggery': 'Joggery',
  'nohavice_elegantne': 'Elegantné nohavice',
  'nohavice_cargo': 'Cargo nohavice',

  // ŠORTKY & SUKNE
  'sortky': 'Šortky',
  'sortky_sportove': 'Športové šortky',
  'sukna_mini': 'Mini sukňa',
  'sukna_midi': 'Midi sukňa',
  'sukna_maxi': 'Maxi sukňa',

  // ŠATY & OVERALY
  'saty_kratke': 'Krátke šaty',
  'saty_midi': 'Midi šaty',
  'saty_maxi': 'Maxi šaty',
  'saty_koselove': 'Košeľové šaty',
  'saty_bodycon': 'Bodycon šaty',
  'overal': 'Overal',

  // OBUV – TENISKY
  'tenisky_fashion': 'Fashion tenisky',
  'tenisky_sportove': 'Športové tenisky',
  'tenisky_bezecke': 'Bežecké tenisky',

  // OBUV – ELEGANTNÁ
  'lodicky': 'Lodičky',
  'sandale_opatok': 'Sandále na opätku',
  'balerinky': 'Balerínky',
  'mokasiny': 'Mokasíny',
  'poltopanky': 'Poltopánky',

  // OBUV – ČIŽMY
  'cizmy_clenkove': 'Členkové čižmy',
  'cizmy_vysoke': 'Vysoké čižmy',
  'kozacky': 'Kozačky',
  'cizmy_nad_kolena': 'Čižmy nad kolená',

  // OBUV – LETNÁ
  'sandale': 'Sandále',
  'slapky': 'Šľapky',
  'zabky': 'Žabky',
  'espadrilky': 'Espadrilky',

  // DOPLNKY – HLAVA
  'ciapka': 'Čiapka',
  'ciapka_zimna': 'Zimná čiapka',
  'siltovka': 'Šiltovka',
  'bucket_hat': 'Bucket hat',

  // DOPLNKY – ŠÁLY, RUKAVICE
  'sal': 'Šál',
  'satka': 'Šatka',
  'rukavice': 'Rukavice',

  // DOPLNKY – TAŠKY
  'kabelka': 'Kabelka',
  'taska_crossbody': 'Crossbody taška',
  'ruksak': 'Ruksak',
  'batoh': 'Batoh',
  'kabelka_listova': 'Listová kabelka',
  'ladvinka': 'Ľadvinka',

  // DOPLNKY – OSTATNÉ
  'slnecne_okuliare': 'Slnečné okuliare',
  'opasok': 'Opasok',
  'penazenka': 'Peňaženka',

  // PLAVKY – DÁMSKE
  'bikiny': 'Dvojdielne plavky (bikiny)',
  'plavky_jednodielne': 'Jednodielne plavky',
  'plavkove_nohavicky': 'Plavkové nohavičky',
  'plavkova_podprsenka': 'Plavková podprsenka',
  'tankiny': 'Tankiny',

  // PLAVKY – PÁNSKE
  'plavkove_sortky': 'Plavkové šortky',
  'plavky_slipove': 'Slipové plavky',

  // PLÁŽOVÉ DOPLNKY
  'pareo': 'Pareo',
  'kaftan': 'Kaftan',
  'plazova_tunika': 'Plážová tunika',

  // ŠPORT – OBLEČENIE
  'sport_tricko': 'Športové tričko',
  'sport_mikina': 'Funkčná mikina',
  'sport_leginy': 'Športové legíny',
  'sport_sortky': 'Športové kraťasy',
  'sport_suprava': 'Tepláková súprava',
  'softshell_bunda': 'Softshell bunda',
  'sport_podprsenka': 'Športová podprsenka',

  // ŠPORT – OBUV
  'obuv_treningova': 'Tréningová obuv',
  'obuv_turisticka': 'Turistická obuv',

  // ŠPORT – DOPLNKY
  'sport_taska': 'Športová taška',
  'potitka': 'Potítka',

};

/// Prémiové značky – využijeme neskôr v Premium sekcii / AI
const List<String> premiumBrands = [
  'Tommy Hilfiger',
  'Calvin Klein',
  'Lacoste',
  'Hugo Boss',
  'Boss',
  'Diesel',
  'Guess',
  'Karl Lagerfeld',
  'Armani Exchange',
  'Hugo',
  'Ralph Lauren',
  'Levi\'s Premium',
];
