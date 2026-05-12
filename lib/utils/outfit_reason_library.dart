/// Kurátorská knižnica viet pre „Prečo tento outfit?“.
/// Jednoduché priame vety — žiadne spojky typu „zatiaľ čo“, „navyše“, „niečím okolo …“.

/// Rozdelenie vrchnej vrstvy pre komfortné bloky (mikina vs. bunda vs. kabát).
enum OutfitOuterComfortKind {
  hoodieOrSweater,
  jacketOrWind,
  coatOrBlazer,
  generic,
}

/// Centrálny register viet — výber len odtiaľto + parametrické doplnenie (teplota, názov kusu).
abstract final class OutfitReasonLibrary {
  OutfitReasonLibrary._();

  static OutfitOuterComfortKind comfortKindForOuterNoun(String outerNoun) {
    final o = outerNoun.toLowerCase();
    if (o.contains('mikin') || o.contains('sveter')) {
      return OutfitOuterComfortKind.hoodieOrSweater;
    }
    if (o.contains('bund') || o.contains('vetrov')) {
      return OutfitOuterComfortKind.jacketOrWind;
    }
    if (o.contains('kabát') ||
        o.contains('kabat') ||
        o.contains('sako')) {
      return OutfitOuterComfortKind.coatOrBlazer;
    }
    return OutfitOuterComfortKind.generic;
  }

  // --- WEATHER OPENINGS (krátke, priame; builder doplní bodku po prvom bloku) ---

  static List<String> weatherOpeningsHourly(String dw, int t) => [
        '$dw by malo byť okolo $t°C',
        '$dw to vyzerá na okolo $t°C',
        '$dw bude počas dňa okolo $t°C',
      ];

  static List<String> weatherOpeningsNoHourly(String dw, int t) => [
        '$dw bude okolo $t°C',
        'Rátaj s $t°C ${dw == 'Zajtra' ? 'na zajtra' : 'na dnes'}',
        'Teploty budú okolo $t°C (${dw.toLowerCase()})',
      ];

  /// Večerný trend bez porovnávania °C („teplejšie ako …“).
  static List<String> trendEveningCoolerThanDay() => [
        'večer sa ochladí',
        'po západe slnka sa ochladí',
        'večer bude znova chladno',
      ];

  static List<String> trendEveningCool() => [
        'večer sa môže ochladiť',
        'večer bude chladno',
      ];

  static List<String> trendWarmDay() => [
        'cez deň sa mierne oteplí',
        'outfit môže zostať ľahší',
        'cez deň bude teplo',
      ];

  static List<String> trendMorningCold(int morningTempC) => [
        'ráno bude okolo ${morningTempC}°C.',
        'ráno bude len okolo ${morningTempC}°C.',
      ];

  static List<String> windSnippets() => [
        'fúka vietor',
        'vietor je výrazný',
      ];

  /// Krátka veta pred dažďom, keď zároveň večer chladne (malým písmenom).
  static List<String> trendEveningCoolBeforeRain() => [
        'večer sa môže ochladiť',
        'večer sa ochladí',
      ];

  // --- CHLADNÉ RÁNO: samostatná veta — priamo °C, nie „chladnejšie“ ---

  static List<String> coldMorningStandalone(int mt) => [
        'Ráno bude okolo $mt°C.',
        'Ráno bude len okolo $mt°C.',
        'Ráno to bude okolo $mt°C.',
      ];

  static List<String> eveningAfterColdMorning() => [
        'Po západe slnka sa znovu ochladí.',
        'Večer sa po západe slnka ochladí.',
      ];

  // --- DAŽĎOVÉ BLOKY ---

  static List<String> rainUnknown() => [
        'počas dňa môže pršať alebo byť premenlivejšie',
        'počas dňa sa môžu objaviť krátke prehánky',
      ];

  static List<String> rainMorningOnly() => [
        'ráno bude ešte pršať, no okolo obeda by sa malo počasie upokojiť',
        'ráno mrholí alebo prší, obed už vyzerá suchší',
      ];

  static List<String> rainAfternoonOnly() => [
        'skôr poobede alebo okolo obeda môže zapršať',
        'dážď hlásia skôr poobede alebo okolo obeda',
      ];

  static List<String> rainEveningOnly() => [
        'dážď hlásia hlavne podvečer',
        'podvečer môže prísť dážď',
        'večer môže zapršať',
      ];

  static List<String> rainMorningAfternoon() => [
        'ráno aj poobede mrholí častejšie',
        'dažď treba čakať ráno aj poobede',
      ];

  static List<String> rainMorningEvening() => [
        'môže pršať ráno aj večer, poobede býva pokojnejšie',
        'ráno a večer hlásia zrážky, poobede je často pokojnejšie',
      ];

  static List<String> rainAfternoonEvening() => [
        'poobede alebo večer môže pršať, ráno ešte nemusí',
        'dažď skôr odpočú alebo večer',
      ];

  static List<String> rainAllDay() => [
        'počas dňa hlásia krátke prehánky',
        'mrholenie alebo prehánky môžu prísť kedykoľvek',
      ];

  // --- PRETO ---

  static List<String> thereforeLayerAndUmbrella(String outerNoun) => [
        'preto sa oplatí mať poruke $outerNoun alebo dáždnik',
        'preto má zmysel mať poruke $outerNoun alebo dáždnik',
        'preto si nechaj poruke $outerNoun alebo dáždnik',
      ];

  static List<String> thereforeLayerOnly(String outerNoun) => [
        'preto sa oplatí mať poruke aspoň $outerNoun',
        'preto má zmysel nechať si poruke $outerNoun',
        'preto si vezmi $outerNoun aspoň poruke',
      ];

  static List<String> thereforeUmbrellaOnly() => [
        'preto maj poruke dáždnik',
        'preto si vezmi dáždnik',
        'na večer sa môže zísť dáždnik',
      ];

  static List<String> thereforeEveningLayer(String outerNoun) => [
        'preto sa oplatí nechať si poruke $outerNoun',
        'preto má zmysel mať $outerNoun poruke na večer',
        'na večer sa oplatí nechať si $outerNoun poruke',
      ];

  // --- VRSTVA / NOSENIE (bez „navyše“ v zmysle výplne) ---

  static List<String> carryWhenWarmMidday(
    OutfitOuterComfortKind kind,
    String outerNoun,
    String outerAcc,
  ) {
    switch (kind) {
      case OutfitOuterComfortKind.hoodieOrSweater:
        return [
          'Mikina sa ráno určite zíde.',
          'Teplejšia vrstva pomôže hlavne ráno a večer.',
          'Mikinu môžeš cez deň pokojne nosiť v ruke.',
          'Na večer sa oplatí nechať si mikinu poruke.',
          'Keď sa oteplí, $outerAcc môžeš brať do ruke.',
        ];
      case OutfitOuterComfortKind.jacketOrWind:
        return [
          'Ľahšia bunda pomôže hlavne večer.',
          'Vrchný diel sa dnes nestratí.',
          'Bunda dáva zmysel hlavne kvôli večernému ochladeniu.',
          'Na sychravejšie počasie je bunda dobrá poistka.',
          'Keď sa oteplí, $outerAcc môžeš brať do ruke.',
        ];
      case OutfitOuterComfortKind.coatOrBlazer:
        return [
          'Kabát alebo sako vie zahriať hlavne večer.',
          'Vrchný diel sa dnes nestratí.',
          'Na večer má zmysel mať $outerNoun poruke.',
          'Keď sa oteplí, $outerAcc môžeš brať do ruke.',
        ];
      case OutfitOuterComfortKind.generic:
        return [
          'Teplejšia vrstva pomôže hlavne ráno a večer.',
          'Keď sa oteplí, $outerAcc môžeš brať do ruke.',
          '$outerNoun nechaj poruke. Cez deň $outerAcc môžeš nosiť v ruke.',
        ];
    }
  }

  // --- ŠTÝL: dve samostatné vety (žiadne „zatiaľ čo“) ---

  /// Druhá veta pri tmavom vrchu + svetlej vrchnáčke — celá veta s veľkým Začiatkom.
  static List<String> stylingLightOuterSentence() => [
        'Svetlejšia vrstva hore outfit trochu oživuje.',
        'Vrchná vrstva pridáva outfitu viac kontrastu.',
        'Svetlejší vrch celý výber opticky odľahčuje.',
        'Svetlejšia vrstva hore outfit pekne dopĺňa.',
      ];

  static List<String> stylingDarkLightTeeFirstSentence() => [
        'Čierne tričko drží outfit jednoduchý a univerzálny.',
        'Tmavší základ necháva outfit ľahko kombinovateľný.',
        'Čierny vrch drží celý výber jednoduchý.',
        'Tmavšie kúsky robia outfit univerzálnejším.',
        'Outfit ostáva jednoduchý, ale nepôsobí nudne.',
      ];

  static List<String> stylingDarkLightLabelFirstSentence(String label) => [
        '$label drží outfit jednoduchý a univerzálny.',
        'Tmavší horný diel drží výber univerzálny.',
        'Tmavší vrch drží celý výber pri zemi.',
        '$label necháva outfit ľahko nositeľný.',
      ];

  static List<String> stylingHoodieOuter() => [
        'Mikina alebo teplejšia vrstva hore sedí na bežný deň vonku.',
        'Teplejšia vrstva hore vyzerá prirodzene na celý deň.',
        'Mikina alebo sveter robí z toho pokojný bežný deň.',
      ];

  static List<String> stylingDarkDominant() => [
        'Tmavšie kúsky pôsobia modernejšie a dobre sa znášajú s ostatným.',
        'Tmavší tón drží celý výber súdržný a nositeľný.',
        'Tmavšie farby pôsobia čisto a zladene.',
      ];

  static List<String> stylingJeans() => [
        'Rifle dotiahnu outfit do praktického dňa bez zbytočností.',
        'Rifle držia výber pohodlný na pohyb.',
        'Džínsy robia z toho bežný, funkčný deň.',
      ];

  static List<String> stylingDefaultVibe() => [
        'Tieto kúsky spolu dávajú zmysel na bežný deň vonku.',
        'Celá kombinácia sedí na bežný deň mimo domu.',
        'Spolu to vyzerá prirodzene na celý deň vonku.',
      ];

  // --- OBUV ---

  static List<String> shoesSneakers() => [
        'Tenisky držia outfit pohodlný.',
        'Obuv necháva outfit uvoľnený a prirodzený.',
        'Tenisky sú pohodlné na celý deň.',
        'Celá kombinácia ostáva pohodlná aj počas dňa.',
        'Na celý deň sú tenisky pohodlné.',
      ];

  static List<String> shoesBoots() => [
        'Obuv je pevnejšia — znesie vlhší chodník.',
        'Čižmy alebo pevnejšia obuv znesú vlhko na chodníku.',
        'Pevnejšia obuv drží krok istejší v mokrejšom počasí.',
      ];
}
