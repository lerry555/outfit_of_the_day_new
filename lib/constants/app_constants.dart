// lib/constants/app_constants.dart

/// Hlavné kategórie v šatníku – používame ich v UI
/// a ukladáme do "mainCategory".
const List<String> categories = [
  'Vrch',
  'Spodok',
  'Obuv',
  'Doplnky',
];

/// Podkategórie – toto ukladáme do "category"
/// (práve tieto názvy potom vidí AI: Tepláky, Bunda, Tenisky…)
const Map<String, List<String>> subcategoriesByCategory = {
  'Vrch': [
    'Tričko s krátkym rukávom',
    'Tričko s dlhým rukávom',
    'Košeľa',
    'Mikina',
    'Mikina na zips',
    'Sveter',
    'Rolák',
    'Vesta',
    'Sako',
    'Bunda',
    'Kabát',
    'Top',
  ],
  'Spodok': [
    'Nohavice',
    'Rifle',
    'Chinos',
    'Tepláky',
    'Teplákové kraťasy',
    'Kraťasy',
    'Legíny',
    'Sukňa',
  ],
  'Obuv': [
    'Tenisky',
    'Bežecké tenisky',
    'Turistické topánky',
    'Poltopánky',
    'Elegantné topánky',
    'Lodičky',
    'Čižmy',
    'Workery',
    'Sandále',
    'Šľapky',
  ],
  'Doplnky': [
    'Čiapka',
    'Šiltovka',
    'Zimná čiapka',
    'Šál',
    'Nákrčník',
    'Rukavice',
    'Opasok',
    'Kabelka',
    'Batoh',
    'Crossbody taška',
    'Ponožky',
    'Vysoké ponožky',
    'Pančuchy',
    'Šperky',
  ],
};

/// Farby – používame pri pridávaní oblečenia.
const List<String> colors = [
  'Biela',
  'Čierna',
  'Sivá',
  'Béžová',
  'Hnedá',
  'Modrá',
  'Svetlomodrá',
  'Tmavomodrá',
  'Zelená',
  'Olívová',
  'Červená',
  'Bordová',
  'Žltá',
  'Oranžová',
  'Ružová',
  'Fialová',
];

/// Štýly – dôležité aj pre AI (sporty vs. elegant atď.).
const List<String> styles = [
  'Ležérny (casual)',
  'Elegantný',
  'Športový',
  'Streetwear',
  'Business / kancelársky',
];


/// Vzory
const List<String> patterns = [
  'Jednofarebné',
  'Pruhy',
  'Kocky',
  'Bodky',
  'Kvetované',
  'Maskáčové',
  'Iný vzor',
];

/// Sezóny
const List<String> seasons = [
  'Celoročne',
  'Jar/Jeseň (prechodná)',
  'Leto',
  'Zima',
];
