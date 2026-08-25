import '../data/stylist_opinion.dart';

/// Jednotný hlas stylistu — centrálna knižnica textových formulácií.
///
/// Táto vrstva **nerozhoduje** o outfite, opinion skóre ani wardrobe analýze.
/// Obsahuje iba vety a deterministický výber, aby stylista znel ako jeden
/// konzistentný človek, nie ako generátor náhodných viet.
///
/// Determinizmus: výber závisí od `opinionLevel`, `activity`, `compromise`,
/// `wardrobe gaps` a `weather bucket`. Rovnaký vstup = rovnaký text.
abstract final class StylistVoiceLibrary {
  // ---------------------------------------------------------------------------
  // 1. ÚVODY (40+ naprieč úrovňami)
  // ---------------------------------------------------------------------------

  static const List<String> _openingsExcellent = [
    'Tento outfit by som pokojne odporučil.',
    'Nič by som na ňom nemenil.',
    'Za mňa veľmi vydarená kombinácia.',
    'Toto je za mňa veľmi vydarené.',
    'S týmto by som nemal problém nikam ísť.',
    'Toto pôsobí naozaj prirodzene.',
    'Za mňa veľmi dobrá voľba.',
    'Presne takto by som to nechal.',
    'Vyzerá to prirodzene a sebavedomo.',
    'Takto by som to na tvojom mieste nechal.',
    'Podľa mňa je to presne to, čo situácia vyžaduje.',
    'Na prvý pohľad mi to dáva zmysel.',
  ];

  static const List<String> _openingsGood = [
    'Celkovo dobrá voľba — pár detailov by sa dalo doladiť, ale sedí.',
    'Mám z toho dobrý pocit, aj keď nie je všetko dokonalé.',
    'Za mňa solídna kombinácia, ktorá funguje.',
    'Nie je to dokonalosť, ale pôsobí to upravene a prirodzene.',
    'Takto by som to na teba videl bez väčších výhrad.',
    'Pôsobí to vyvážene — malé rezervy tam sú, ale nič zásadné.',
    'Dobrý základ, s ktorým sa dá pracovať.',
    'Za mňa fajn voľba, drobnosti by sa ešte našli.',
    'Vyzerá to dobre, len maličkosti by som prípadne doladil.',
    'Slušná kombinácia, ktorá svoje odvedie.',
  ];

  static const List<String> _openingsAcceptable = [
    'Z toho, čo máš v šatníku, je to rozumný kompromis.',
    'Nie je to vysnívaná kombinácia, ale určite neurazí.',
    'Za mňa je to rozumné riešenie z dostupných možností.',
    'Je to kompromis, ale stále vie fungovať.',
    'Nie je to úplne ideál, ale stále to vie fungovať.',
    'Z tvojho šatníka mi najlepšie vychádza práve táto kombinácia.',
    'Ak by som mal vybrať z toho, čo máš, išiel by som do tohto.',
    'Nie je to dokonalé, ale dá sa s tým ísť.',
    'Beriem to ako rozumný kompromis — poslúži to.',
    'Nie je to výhra, ale svoju úlohu to splní.',
    'Dá sa s tým vyjsť, aj keď rezervy tam sú.',
    'Za mňa prijateľné riešenie z toho, čo je poruke.',
  ];

  static const List<String> _openingsWeak = [
    'Úprimne, trochu mi tam niečo chýba.',
    'Keby som mal byť úplne úprimný, nie som z toho úplne presvedčený.',
    'Nebudem tvrdiť, že je to ideálne.',
    'Úprimne — nie som z tejto kombinácie nadšený.',
    'Ak by som mohol zmeniť jednu vec, určite by som siahol inam.',
    'Tu už narážame na limity tvojho šatníka.',
    'Vidno, že robíme kompromis.',
    'Najviac ma tu mrzí, že chýba vhodnejší kúsok.',
    'Musím byť úprimný — toto nie je ono.',
    'Priznám sa, že z tohto nie som celkom spokojný.',
  ];

  static List<String> openings(StylistOpinionLevel level) => switch (level) {
        StylistOpinionLevel.excellent => _openingsExcellent,
        StylistOpinionLevel.good => _openingsGood,
        StylistOpinionLevel.acceptable => _openingsAcceptable,
        StylistOpinionLevel.weak => _openingsWeak,
      };

  // ---------------------------------------------------------------------------
  // 5. OSOBNÝ NÁZOR — predstavenie outfitu (namiesto „Poskladal som ti...")
  // ---------------------------------------------------------------------------

  static const List<String> outfitIntros = [
    'Ja by som na tvojom mieste zvolil {pieces}.',
    'Na túto príležitosť by som išiel do kombinácie: {pieces}.',
    'Ja osobne by som siahol po kombinácii: {pieces}.',
    'Mne by na túto situáciu najväčší zmysel dávala kombinácia: {pieces}.',
    'Na dnešok by som skombinoval {pieces}.',
    'Keby som vyberal ja, išiel by som do kombinácie: {pieces}.',
    'Z tvojho šatníka mi najlepšie vychádza kombinácia: {pieces}.',
    'Najlepšie podľa mňa funguje kombinácia: {pieces}.',
    'Skúsil by som to takto: {pieces}.',
    'Osobne by som sa rozhodol pre {pieces}.',
    'V tvojom prípade by som siahol po kombinácii: {pieces}.',
    'Táto kombinácia mi dáva najväčší zmysel: {pieces}.',
    'Práve {pieces} by som na teba videl najprirodzenejšie.',
    'Z toho, čo máš, by som najskôr skúsil {pieces}.',
    'Na teba by som v tomto momente stavil na kombináciu: {pieces}.',
    'Moja voľba by bola: {pieces}.',
    'Keby to bol môj outfit, zvolil by som {pieces}.',
    'Za mňa najlepšie sedí kombinácia: {pieces}.',
    'Takto by som to poskladal: {pieces}.',
    'Osobne preferujem {pieces}.',
    'Ak by som mal siahnuť po jednej kombinácii, bola by to: {pieces}.',
    'Najrozumnejšie mi príde kombinácia: {pieces}.',
    'V tomto prípade by som išiel do kombinácie: {pieces}.',
    'Z praktického hľadiska dáva zmysel kombinácia: {pieces}.',
    'Ak mám byť konkrétny — {pieces}.',
    'Môj tip by bol: {pieces}.',
    'Ja by som zvolil {pieces}.',
    'Skombinoval by som to ako {pieces}.',
    'Na teba by som videl {pieces}.',
    'Takto by som to uchopil: {pieces}.',
  ];

  // ---------------------------------------------------------------------------
  // 3. ÚPRIMNÁ KRITIKA — kompromisná doplnková veta
  // ---------------------------------------------------------------------------

  static const List<String> compromises = [
    'Keby si mal vhodnejší kúsok, siahol by som po ňom.',
    'Nie je to úplne ideál, ale stále to vie fungovať.',
    'Z toho, čo máš, je toto podľa mňa najlepšia možnosť.',
    'Je to kompromis, ale stále vyzerá upravene.',
    'Za mňa je to rozumné riešenie.',
    'Nie je to vysnívaná kombinácia, ale určite neurazí.',
    'Ide o kompromis, ktorý sa ešte drží pohromade.',
    'Nie je to dokonalé, ale z tvojho šatníka je to najlepšie, čo máme.',
    'Mal by som radšej niečo iné, ale s týmto sa dá ísť.',
    'Nie je to úplne ideálna voľba, ale je to najlepšie, čo sa dá z tvojho šatníka.',
    'Kompromis áno, ale stále to pôsobí rozumne.',
    'Nie je to presne to, čo by som si predstavoval, ale funguje to.',
    'Vidno, že tu robíme kompromis, no dá sa s tým vyjsť.',
    'Tu už trochu narážame na limity šatníka.',
    'Práve na tomto mieste outfit trochu brzdí, ale poslúži.',
    'Keby to bol môj outfit, jeden kúsok by som ešte vymenil.',
  ];

  // ---------------------------------------------------------------------------
  // 4. ACTIVITY VOICE — prechodová veta podľa aktivity
  // ---------------------------------------------------------------------------

  static const Map<String, List<String>> _activityFlavour = {
    'wedding': [
      'Na svadbe väčšinou lepšie funguje trochu upravenejší look.',
      'Nebál by som sa ísť trochu elegantnejšie.',
      'Pri takejto udalosti by som sa snažil pôsobiť slávnostnejšie.',
    ],
    'interview': [
      'Prvý dojem tu vie spraviť veľa.',
      'Na pohovor je dôležité pôsobiť upravene a sebavedomo.',
      'Pri pohovore by som sa vyhol príliš uvoľnenému dojmu.',
    ],
    'work': [
      'Na bežný pracovný deň stačí čistý a upravený vzhľad.',
      'Do kancelárie by som volil skôr upravenejší dojem.',
      'Do práce by som sa snažil vyzerať čisto a upravene.',
    ],
    'meeting': [
      'Na meetingu sa oplatí pôsobiť trochu upravenejšie.',
      'Keď stojíš pred ľuďmi, oplatí sa vyzerať sebavedomo a upravene.',
      'Na dôležité stretnutie by som pridal kúsok navyše k upravenosti.',
    ],
    'hike': [
      'Na túre je praktickosť vždy pred módou.',
      'V horách je podľa mňa dôležitejšie pohodlie a praktickosť.',
      'V teréne je kľúčové, aby ťa nič neobmedzovalo.',
    ],
    'mushroom': [
      'V lese riešim najskôr pohodlie.',
      'Na huby je dôležitejšia funkčnosť než elegancia.',
      'V lese sa oplatí myslieť na pohodlie a suché nohy.',
    ],
    'barbecue': [
      'Tu by som zostal hlavne pri pohodlí.',
      'Na grilovačku si podľa mňa žiada uvoľnený, ale čistý štýl.',
      'Pri grilovaní je hlavné cítiť sa dobre.',
    ],
    'date': [
      'Na rande by som sa snažil pôsobiť upravene, ale nie nasilu.',
      'Na rande je dôležité pôsobiť sebavedomo, nie príliš formálne.',
      'Pri rande by som volil skôr smart casual než outdoor look.',
    ],
    'cinema': [
      'Kino je skôr uvoľnená príležitosť.',
      'Do kina by som šiel skôr v čistom casual štýle.',
      'Na kino outfit nemusí byť formálny, ale upravený áno.',
    ],
    'dinner': [
      'Večera v reštaurácii si pýta trochu viac upravenosti.',
      'Na večeru v reštaurácii by som sa snažil pôsobiť elegantnejšie.',
      'Pri večeri vonku je podľa mňa vhodný smart casual.',
    ],
  };

  static List<String>? activityFlavour(String? activityType) =>
      _activityFlavour[activityType ?? ''];

  // ---------------------------------------------------------------------------
  // 2. POZITÍVNE REAKCIE — zakončenie pre excellent
  // ---------------------------------------------------------------------------

  static const List<String> _excellentClosingsGeneric = [
    'Takto by som to nechal — nič zásadné by som nemenil.',
    'Za mňa veľmi vydarená kombinácia.',
    'Pôsobí to prirodzene a sebavedomo.',
    'Kombinácia mi dáva zmysel od hlavy po päty.',
    'Presne takto by som to na teba videl.',
    'S týmto by som nemal problém nikam ísť.',
  ];

  static const Map<String, List<String>> _excellentClosingsByActivity = {
    'hike': [
      'Na túru mi to príde veľmi dobré.',
      'Do hôr by som to takto pokojne vzal.',
      'Na túru to podľa mňa výborne poslúži.',
    ],
    'mushroom': [
      'Na huby by som to nechal presne takto.',
      'Do lesa mi to dáva úplný zmysel.',
      'Na hubovanie to takto perfektne sadne.',
    ],
    'barbecue': [
      'Na grilovačku mi to dáva zmysel.',
      'Na grilovačku to takto úplne stačí.',
      'Pri grilovaní sa v tomto budeš cítiť dobre.',
    ],
    'date': [
      'Na rande to podľa mňa pôsobí prirodzene.',
      'Na rande by som to takto pokojne nechal.',
    ],
    'cinema': [
      'Na kino to takto úplne stačí.',
      'Do kina by som to takto pokojne vzal.',
    ],
    'dinner': [
      'Na večeru to pôsobí príjemne a upravene.',
      'Na večeru by som to takto nechal.',
    ],
    'work': [
      'Do práce to takto pôsobí čisto a upravene.',
    ],
    'meeting': [
      'Na meetingu to pôsobí sebavedomo a upravene.',
    ],
  };

  static List<String> excellentClosings(String? activityType) {
    final pool = _excellentClosingsByActivity[activityType ?? ''];
    return (pool != null && pool.isNotEmpty) ? pool : _excellentClosingsGeneric;
  }

  // ---------------------------------------------------------------------------
  // 6. NÁKUPY — odporúčanie doplniť šatník (nie ako reklama)
  // ---------------------------------------------------------------------------

  static const List<String> _closingsGeneric = [
    'Ak časom doplníš šatník, možnosti budú oveľa širšie.',
    'Keby si mal doplniť len jednu vec, začal by som práve tu.',
    'Najväčší rozdiel by spravil práve takýto kúsok.',
    'Práve tento kúsok ti otvorí veľa ďalších kombinácií.',
    'A potom už budeš mať outfit prakticky bez kompromisov.',
    'S týmto kúskom by si mal do budúcna oveľa voľnejšiu ruku.',
  ];

  static const List<String> _closingsShirtFormal = [
    'Keby si mal doplniť jednu vec, kúpil by som jednoduchú košeľu.',
    'Jednoduchá košeľa by ti otvorila dvere na formálnejšie príležitosti.',
    'Košeľa by tu spravila najväčší rozdiel.',
  ];

  static const List<String> _closingsShirtSocial = [
    'Košeľa alebo polo by ti na smart casual príležitosti sadli výborne.',
    'Na rande či večeru by sa ti hodila košeľa alebo polo.',
    'Smart casual kúsok ako košeľa by ti do budúcna veľa uľahčil.',
  ];

  static const List<String> _closingsShirtWork = [
    'Polo alebo košeľa by outfit na prácu posunuli výrazne vyššie.',
    'Do práce by som ako prvé doplnil polo alebo košeľu.',
    'Práve polo alebo košeľa by tu spravili najväčší rozdiel.',
  ];

  static const List<String> _closingsShirtMeeting = [
    'Na pracovné stretnutia by som ako prvé doplnil polo alebo jednoduchú košeľu.',
  ];

  static const List<String> _closingsFormalShoes = [
    'Čistá formálna obuv by na slávnostné príležitosti urobila veľký rozdiel.',
    'Elegantná obuv by ti otvorila úplne iné možnosti.',
    'Formálna obuv je prvý krok k lepšiemu dojmu na svadbe či pohovore.',
  ];

  static const List<String> _closingsRainJacket = [
    'Nepremokavá bunda by ti pri daždi uľahčila život.',
    'Pri daždi by sa hodila nepremokavá vrstva — to by som doplnil ako prvé.',
  ];

  static const List<String> _closingsHikingPants = [
    'Odolnejšie turistické nohavice by ti na výlety spravili službu.',
    'Na ďalšie túry by som zvážil odolnejšie turistické nohavice.',
  ];

  static List<String> wardrobeClosings({
    required String gapCategory,
    required bool social,
    bool meeting = false,
  }) {
    if (meeting && (gapCategory == 'polo' || gapCategory == 'shirt')) {
      return _closingsShirtMeeting;
    }
    return switch (gapCategory) {
      'shirt' when social => _closingsShirtSocial,
      'shirt' => _closingsShirtFormal,
      'polo' when social => _closingsShirtSocial,
      'polo' => _closingsShirtWork,
      'formal_shoes' => _closingsFormalShoes,
      'rain_jacket' => _closingsRainJacket,
      'hiking_pants' => _closingsHikingPants,
      _ => _closingsGeneric,
    };
  }

  // ---------------------------------------------------------------------------
  // 3. ÚPRIMNÁ KRITIKA — poznámka o chýbajúcom kúsku (weak)
  // ---------------------------------------------------------------------------

  static const List<String> weakMissingNotes = [
    'Najviac by pomohlo doplniť {piece}.',
    'Keby som mohol zmeniť jednu vec, pridal by som {piece}.',
    'Najväčší rozdiel by spravilo {piece}.',
    'Práve {piece} je to, čo mi tu najviac chýba.',
    'Bez {piece} to bude vždy len kompromis.',
    'Najviac ma mrzí, že chýba {piece}.',
  ];

  // ---------------------------------------------------------------------------
  // 7. DETERMINISTICKÝ VÝBER (opinionLevel + activity + compromise + gaps + weather)
  // ---------------------------------------------------------------------------

  static String pick({
    required String slot,
    required StylistOpinionLevel level,
    required String? activityType,
    required bool usedCompromise,
    required List<String> missingCategories,
    required List<String> pool,
    String weatherBucket = '',
  }) {
    if (pool.isEmpty) return '';
    final missing = [...missingCategories]..sort();
    final key = '$slot|${level.wireName}|${activityType ?? ''}|'
        '$usedCompromise|${missing.join(',')}|$weatherBucket';
    return pool[_index(key, pool.length)];
  }

  static int _index(String key, int count) {
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % count;
  }
}
