/// „Prečo tento outfit?“ — **plán stylistu** (`[_Plan]`) + **kurátorská knižnica** (`OutfitReasonLibrary`).
/// Žiadna voľná „AI“ generácia viet — len výber z ručne definovaných blokov.

import 'outfit_reason_library.dart';

// --- Rozhodnutia (iba dáta) -------------------------------------------------

enum _RainProfile {
  dry,
  unknown,
  morningOnly,
  afternoonOnly,
  eveningOnly,
  morningAfternoon,
  morningEvening,
  afternoonEvening,
  allDay,
}

class _Plan {
  _Plan({
    required this.dayWord,
    required this.anchorTempC,
    required this.morningTempC,
    required this.hasHourly,
    required this.morningMuchColder,
    required this.warmsMidday,
    required this.eveningCools,
    required this.windy,
    required this.rainy,
    required this.rainProfile,
    required this.wantUmbrella,
    required this.wantLayerNearby,
    required this.carryOuterInHand,
    required this.hasOuterwear,
    required this.darkTopLightOuter,
    required this.topLooksLikeTee,
    required this.topDisplayLabel,
    required this.outerIsHoodieLike,
    required this.darkDominant,
    required this.jeansBottom,
    required this.sneakers,
    required this.boots,
  });

  final String dayWord;
  final int anchorTempC;
  final int? morningTempC;
  final bool hasHourly;

  final bool morningMuchColder;
  final bool warmsMidday;
  final bool eveningCools;
  final bool windy;

  final bool rainy;
  final _RainProfile rainProfile;

  final bool wantUmbrella;
  final bool wantLayerNearby;
  final bool carryOuterInHand;

  final bool hasOuterwear;
  final bool darkTopLightOuter;
  final bool topLooksLikeTee;
  final String topDisplayLabel;
  final bool outerIsHoodieLike;
  final bool darkDominant;
  final bool jeansBottom;
  final bool sneakers;
  final bool boots;
}

class OutfitReasonBuilder {
  /// Posledné premium odstavce v rámci session — aby „Dnes“ a „Zajtra“ nekopírovali tie isté vety.
  static String? _sessionLastDnes;
  static String? _sessionLastZajtra;

  static String build({
    required int tempC,
    required bool isRainy,
    required bool isWindy,
    required bool isPremium,
    required List<Map<String, dynamic>> selectedItems,
    required bool hasOuterwear,
    bool isTomorrow = false,
    int? morningTempC,
    int? noonTempC,
    int? eveningTempC,
    bool morningRainSegment = false,
    bool afternoonRainSegment = false,
    bool eveningRainSegment = false,
    /// Voliteľný odsek druhého dňa (napr. keď UI pozná oba naraz) — silnejšia ochrana pred opakovaním.
    String? peerReasonBlurb,
  }) {
    if (!isPremium) {
      return _nonPremiumBlurb(
        tempC: tempC,
        isRainy: isRainy,
        isWindy: isWindy,
        hasOuterwear: hasOuterwear,
      );
    }

    final items = selectedItems.map(_normalizeItem).toList();
    final top = _findByType(items, const ['top']);
    final bottom = _findByType(items, const ['bottom']);
    final shoes = _findByType(items, const ['shoes']);
    final outer = _findByType(items, const ['outerwear']);

    final plan = _buildPlan(
      dayWord: isTomorrow ? 'Zajtra' : 'Dnes',
      tempC: tempC,
      morningTempC: morningTempC,
      noonTempC: noonTempC,
      eveningTempC: eveningTempC,
      isRainy: isRainy,
      isWindy: isWindy,
      morningRain: morningRainSegment,
      afternoonRain: afternoonRainSegment,
      eveningRain: eveningRainSegment,
      hasOuterwear: hasOuterwear,
      top: top,
      bottom: bottom,
      shoes: shoes,
      outer: outer,
    );

    final outerNoun = _outerLayerWord(outer);
    final outerAcc = _outerAccusative(outer);

    final vSalt = _styleVariationSalt(plan, top: top, shoes: shoes, outer: outer);

    final peerFromSession = isTomorrow ? _sessionLastDnes : _sessionLastZajtra;
    final peerExact = <String>{};
    peerExact.addAll(_sentenceKeysNormalized(peerReasonBlurb));
    peerExact.addAll(_sentenceKeysNormalized(peerFromSession));
    final peerTemplates = <String>{};
    peerTemplates.addAll(_templateKeysFromBlurb(peerReasonBlurb));
    peerTemplates.addAll(_templateKeysFromBlurb(peerFromSession));

    const maxAttempts = 14;
    const saltPrime = 7919;
    String? chosen;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final effectiveSalt = vSalt + attempt * saltPrime;
      final candidate = _composePremiumParagraph(
        plan: plan,
        outerNoun: outerNoun,
        outerAcc: outerAcc,
        effectiveSalt: effectiveSalt,
      );
      if (!_violatesPeerAntiRepeat(candidate, peerExact, peerTemplates)) {
        chosen = candidate;
        break;
      }
    }
    chosen ??= _composePremiumParagraph(
      plan: plan,
      outerNoun: outerNoun,
      outerAcc: outerAcc,
      effectiveSalt: vSalt + maxAttempts * saltPrime + 13331,
    );

    if (isTomorrow) {
      _sessionLastZajtra = chosen;
    } else {
      _sessionLastDnes = chosen;
    }
    return chosen;
  }

  /// Testovanie / reset session pamäte pre „Dnes vs. Zajtra“.
  static void clearAntiRepeatSession() {
    _sessionLastDnes = null;
    _sessionLastZajtra = null;
  }

  static String _composePremiumParagraph({
    required _Plan plan,
    required String outerNoun,
    required String outerAcc,
    required int effectiveSalt,
  }) {
    final weather = _renderWeatherAndPlan(
      plan,
      outerNoun: outerNoun,
      outerAcc: outerAcc,
      vSalt: effectiveSalt,
    );
    final outfit = _renderOutfitReasoning(plan, effectiveSalt);
    final footwear = _renderFootwear(plan, effectiveSalt);

    final swap =
        _shouldLeadWithOutfitBlock(plan, effectiveSalt, weather, outfit);
    if (swap) {
      return _joinNonEmpty([outfit, weather, footwear]);
    }
    return _joinNonEmpty([weather, outfit, footwear]);
  }

  /// Iný vstup do odstavca: niekedy štýl pred počasím (nie pri „rannom“ príbehu).
  static bool _shouldLeadWithOutfitBlock(
    _Plan plan,
    int salt,
    String weatherBlock,
    String outfitBlock,
  ) {
    if (weatherBlock.isEmpty || outfitBlock.isEmpty) return false;
    final weatherLedMorning = weatherBlock.contains('Ráno bude okolo') ||
        weatherBlock.contains('Ráno bude len okolo') ||
        weatherBlock.contains('Ráno to bude okolo');
    if (weatherLedMorning) return false;
    final h = (salt ~/ 7 + plan.dayWord.hashCode).abs();
    return h % 2 == 1;
  }

  static List<String> _splitIntoSentences(String text) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    return t
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static String _normalizeSentenceKey(String s) {
    return s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  /// Ignoruje konkrétne čísla — rozpozná rovnakú štruktúru vety pri iných teplotách.
  static String _templateKeyFromSentence(String sentence) {
    var t = _normalizeSentenceKey(sentence);
    t = t.replaceAll(RegExp(r'\d+\s*°?\s*c'), '#°c');
    return t;
  }

  static Set<String> _sentenceKeysNormalized(String? blurb) {
    if (blurb == null || blurb.trim().isEmpty) return {};
    return _splitIntoSentences(blurb).map(_normalizeSentenceKey).toSet();
  }

  static Set<String> _templateKeysFromBlurb(String? blurb) {
    if (blurb == null || blurb.trim().isEmpty) return {};
    final out = <String>{};
    for (final s in _splitIntoSentences(blurb)) {
      final n = _normalizeSentenceKey(s);
      if (n.length < 24) continue;
      final tk = _templateKeyFromSentence(s);
      if (tk.length >= 22) out.add(tk);
    }
    return out;
  }

  static bool _violatesPeerAntiRepeat(
    String candidate,
    Set<String> peerExact,
    Set<String> peerTemplates,
  ) {
    for (final s in _splitIntoSentences(candidate)) {
      final n = _normalizeSentenceKey(s);
      if (n.length < 8) continue;
      if (peerExact.contains(n)) return true;
      if (n.length >= 28) {
        final tk = _templateKeyFromSentence(s);
        if (tk.length >= 24 && peerTemplates.contains(tk)) return true;
      }
    }
    return false;
  }

  static int _styleVariationSalt(
    _Plan plan, {
    required Map<String, dynamic> top,
    required Map<String, dynamic> shoes,
    required Map<String, dynamic> outer,
  }) {
    var h = 17;
    h = 37 * h + plan.dayWord.hashCode;
    h = 37 * h + plan.anchorTempC;
    h = 37 * h + plan.rainProfile.index;
    h = 37 * h + plan.darkTopLightOuter.hashCode;
    h = 37 * h + plan.topDisplayLabel.hashCode;
    h = 37 * h + _blob(top).hashCode;
    h = 37 * h + _blob(shoes).hashCode;
    h = 37 * h + _blob(outer).hashCode;
    return h.abs();
  }

  static String _v(List<String> options, int salt, [int mix = 0]) {
    if (options.isEmpty) return '';
    final i = (salt + mix).abs() % options.length;
    return options[i];
  }

  static String _capitalizeFirst(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1);
  }

  // ---------------------------------------------------------------------------
  // Plán: čísla + booleany z počasia a šatníka
  // ---------------------------------------------------------------------------

  static _Plan _buildPlan({
    required String dayWord,
    required int tempC,
    required int? morningTempC,
    required int? noonTempC,
    required int? eveningTempC,
    required bool isRainy,
    required bool isWindy,
    required bool morningRain,
    required bool afternoonRain,
    required bool eveningRain,
    required bool hasOuterwear,
    required Map<String, dynamic> top,
    required Map<String, dynamic> bottom,
    required Map<String, dynamic> shoes,
    required Map<String, dynamic> outer,
  }) {
    final hasHourly =
        morningTempC != null && noonTempC != null && eveningTempC != null;

    late final int anchor;
    var warmsMidday = false;
    var eveningCools = false;
    var morningMuchColder = false;
    if (morningTempC != null && noonTempC != null && eveningTempC != null) {
      final mt = morningTempC;
      final nt = noonTempC;
      final et = eveningTempC;
      anchor = nt;
      warmsMidday = nt - mt >= 2;
      eveningCools = nt - et >= 2;
      morningMuchColder = (nt - mt).abs() >= 2;
    } else {
      anchor = tempC;
    }

    final rp = _rainProfileFromFlags(
      isRainy: isRainy,
      m: morningRain,
      a: afternoonRain,
      e: eveningRain,
    );

    final wantUmbrella = isRainy && rp != _RainProfile.dry;

    final wantLayerNearby = hasOuterwear &&
        (eveningCools ||
            isRainy ||
            morningMuchColder ||
            anchor < 14 ||
            (morningTempC != null && morningTempC < 12));

    final carryOuterInHand = hasOuterwear &&
        warmsMidday &&
        noonTempC != null &&
        noonTempC >= 12;

    final fam = _colorFamilies(_allColors([top, bottom, outer, shoes]));
    final topBlob = _blob(top);
    final bottomBlob = _blob(bottom);
    final outerBlob = _blob(outer);

    final topDark = topBlob.contains('čier') ||
        topBlob.contains('cier') ||
        topBlob.contains('black') ||
        fam.contains('black');
    final darkTopLightOuter = hasOuterwear && topDark && _outerLooksLight(outer);

    final topLooksLikeTee = topBlob.contains('trič') ||
        topBlob.contains('tric') ||
        topBlob.contains('tee') ||
        topBlob.contains('shirt');

    final label = _shortLabel(top, '');
    final topDisplayLabel = label.isNotEmpty ? label : 'Horný diel';

    final outerIsHoodieLike = outerBlob.contains('mikina') ||
        outerBlob.contains('hoodie') ||
        outerBlob.contains('sveter');

    final darkDominant = fam.contains('black') || fam.contains('navy');

    final jeansBottom = bottomBlob.contains('jeans') ||
        bottomBlob.contains('rifl') ||
        bottomBlob.contains('dzin') ||
        bottomBlob.contains('džín');

    final shoesBlob = _blob(shoes);
    final sneakers =
        shoesBlob.contains('tenis') || shoesBlob.contains('sneaker');
    final boots =
        shoesBlob.contains('čiž') || shoesBlob.contains('ciz') || shoesBlob.contains('boot');

    return _Plan(
      dayWord: dayWord,
      anchorTempC: anchor,
      morningTempC: morningTempC,
      hasHourly: hasHourly,
      morningMuchColder: morningMuchColder,
      warmsMidday: warmsMidday,
      eveningCools: eveningCools,
      windy: isWindy,
      rainy: isRainy,
      rainProfile: rp,
      wantUmbrella: wantUmbrella,
      wantLayerNearby: wantLayerNearby,
      carryOuterInHand: carryOuterInHand,
      hasOuterwear: hasOuterwear,
      darkTopLightOuter: darkTopLightOuter,
      topLooksLikeTee: topLooksLikeTee,
      topDisplayLabel: topDisplayLabel,
      outerIsHoodieLike: outerIsHoodieLike,
      darkDominant: darkDominant,
      jeansBottom: jeansBottom,
      sneakers: sneakers,
      boots: boots,
    );
  }

  static _RainProfile _rainProfileFromFlags({
    required bool isRainy,
    required bool m,
    required bool a,
    required bool e,
  }) {
    if (!isRainy) return _RainProfile.dry;
    final n = (m ? 1 : 0) + (a ? 1 : 0) + (e ? 1 : 0);
    if (n == 0) return _RainProfile.unknown;
    if (m && a && e) return _RainProfile.allDay;
    if (n >= 3) return _RainProfile.allDay;
    if (m && !a && !e) return _RainProfile.morningOnly;
    if (!m && a && !e) return _RainProfile.afternoonOnly;
    if (!m && !a && e) return _RainProfile.eveningOnly;
    if (m && a && !e) return _RainProfile.morningAfternoon;
    if (m && !a && e) return _RainProfile.morningEvening;
    if (!m && a && e) return _RainProfile.afternoonEvening;
    return _RainProfile.unknown;
  }

  // ---------------------------------------------------------------------------
  // Šablóny (text len podľa plánu)
  // ---------------------------------------------------------------------------

  static String _openingHourly(_Plan p, int vSalt) {
    final dw = p.dayWord;
    final t = p.anchorTempC;
    return _v(OutfitReasonLibrary.weatherOpeningsHourly(dw, t), vSalt, 0);
  }

  static String _openingNoHourly(_Plan p, int vSalt) {
    final dw = p.dayWord;
    final t = p.anchorTempC;
    return _v(OutfitReasonLibrary.weatherOpeningsNoHourly(dw, t), vSalt, 0);
  }

  /// Jedna súdržná myšlienka namiesto „meteo výstupu“. Max. dva krátke kontextové bloky pred „preto“.
  static String _renderWeatherAndPlan(
    _Plan p, {
    required String outerNoun,
    required String outerAcc,
    required int vSalt,
  }) {
    final opening = p.hasHourly ? _openingHourly(p, vSalt) : _openingNoHourly(p, vSalt);
    final sentence1 = '$opening.';

    final therefore = _thereforeClauseVariant(
      p,
      outerNoun: outerNoun,
      vSalt: vSalt,
    );

    String? carryLine;
    if (p.carryOuterInHand &&
        p.hasOuterwear &&
        p.warmsMidday &&
        !(therefore?.contains(outerNoun) ?? false)) {
      carryLine = _carryLineVariant(outerNoun, outerAcc, vSalt);
    }

    final rainEveningAlreadySaid =
        p.rainy &&
            (p.rainProfile == _RainProfile.eveningOnly ||
                p.rainProfile == _RainProfile.afternoonEvening);

    // Chladné ráno + vrstva (bez dažďa): jeden prirodzený blok ako od kamaráta.
    final coldMorningStory = p.hasHourly &&
        p.morningMuchColder &&
        p.morningTempC != null &&
        !p.rainy &&
        p.wantLayerNearby &&
        p.hasOuterwear &&
        therefore != null &&
        _thereforeAboutLayer(therefore, outerNoun);

    if (coldMorningStory) {
      final mt = p.morningTempC!;
      final tc = therefore;
      final coldStandalone = _v(
        OutfitReasonLibrary.coldMorningStandalone(mt),
        vSalt,
        50,
      );
      final adviceLine = '${_capitalizeFirst(tc)}.';
      final eveningExtra = p.eveningCools
          ? ' ${_eveningChillyExtraSentence(vSalt)}'
          : '';
      return _joinNonEmpty([
        sentence1,
        coldStandalone,
        adviceLine,
        eveningExtra.trim(),
        carryLine ?? '',
      ]);
    }

    final snippets = <String>[];

    if (p.rainy) {
      if (p.hasHourly && p.eveningCools && !rainEveningAlreadySaid) {
        snippets.add(
          _lowerFirst(
            _v(OutfitReasonLibrary.trendEveningCoolBeforeRain(), vSalt, 1),
          ),
        );
      }
      snippets.add(_rainClauseConversational(p.rainProfile, vSalt));
    } else if (p.hasHourly) {
      if (p.warmsMidday && p.eveningCools) {
        snippets.add(
          _lowerFirst(
            _v(OutfitReasonLibrary.trendEveningCoolerThanDay(), vSalt, 1),
          ),
        );
      } else if (p.eveningCools) {
        snippets.add(
          _lowerFirst(
            _v(OutfitReasonLibrary.trendEveningCool(), vSalt, 1),
          ),
        );
      } else if (p.warmsMidday) {
        snippets.add(
          _lowerFirst(
            _v(OutfitReasonLibrary.trendWarmDay(), vSalt, 1),
          ),
        );
      } else if (p.morningMuchColder && p.morningTempC != null) {
        snippets.add(
          _lowerFirst(
            _v(
              OutfitReasonLibrary.trendMorningCold(p.morningTempC!),
              vSalt,
              1,
            ),
          ),
        );
      }
    }

    if (!p.rainy &&
        p.windy &&
        snippets.length < 2) {
      snippets.add(
        _lowerFirst(
          _v(OutfitReasonLibrary.windSnippets(), vSalt, 2),
        ),
      );
    }

    while (snippets.length > 2) {
      snippets.removeLast();
    }
    snippets.removeWhere((s) => s.trim().isEmpty);

    String? sentence2;
    if (snippets.isNotEmpty || therefore != null) {
      var body = '';
      if (snippets.isNotEmpty) {
        body = _capitalizeFirst(snippets[0]);
        for (var i = 1; i < snippets.length; i++) {
          body += ' a ${snippets[i]}';
        }
      }
      if (therefore != null) {
        if (body.isEmpty) {
          body = _capitalizeFirst(therefore);
        } else {
          body += ', $therefore';
        }
      }
      sentence2 = '$body.';
    }

    return _joinNonEmpty([sentence1, sentence2 ?? '', carryLine ?? '']);
  }

  static bool _thereforeAboutLayer(String therefore, String outerNoun) {
    if (therefore.contains('dáždnik')) return false;
    return therefore.contains('poruke') &&
        (therefore.contains(outerNoun) ||
            therefore.contains('mikin') ||
            therefore.contains('bund') ||
            therefore.contains('kabát') ||
            therefore.contains('sako') ||
            therefore.contains('vrstv'));
  }

  static String _eveningChillyExtraSentence(int vSalt) {
    return _v(OutfitReasonLibrary.eveningAfterColdMorning(), vSalt, 12);
  }

  static String _rainClauseConversational(_RainProfile r, int vSalt) {
    switch (r) {
      case _RainProfile.dry:
        return '';
      case _RainProfile.unknown:
        return _lowerFirst(_v(OutfitReasonLibrary.rainUnknown(), vSalt, 3));
      case _RainProfile.morningOnly:
        return _lowerFirst(_v(OutfitReasonLibrary.rainMorningOnly(), vSalt, 3));
      case _RainProfile.afternoonOnly:
        return _lowerFirst(_v(OutfitReasonLibrary.rainAfternoonOnly(), vSalt, 3));
      case _RainProfile.eveningOnly:
        return _lowerFirst(_v(OutfitReasonLibrary.rainEveningOnly(), vSalt, 3));
      case _RainProfile.morningAfternoon:
        return _lowerFirst(_v(OutfitReasonLibrary.rainMorningAfternoon(), vSalt, 3));
      case _RainProfile.morningEvening:
        return _lowerFirst(_v(OutfitReasonLibrary.rainMorningEvening(), vSalt, 3));
      case _RainProfile.afternoonEvening:
        return _lowerFirst(_v(OutfitReasonLibrary.rainAfternoonEvening(), vSalt, 3));
      case _RainProfile.allDay:
        return _lowerFirst(_v(OutfitReasonLibrary.rainAllDay(), vSalt, 3));
    }
  }

  static String? _thereforeClauseVariant(
    _Plan p, {
    required String outerNoun,
    required int vSalt,
  }) {
    final u = p.wantUmbrella;
    final l = p.wantLayerNearby && p.hasOuterwear;

    if (l && u) {
      return _v(
        OutfitReasonLibrary.thereforeLayerAndUmbrella(outerNoun),
        vSalt,
        4,
      );
    }
    if (l && !u) {
      return _v(
        OutfitReasonLibrary.thereforeLayerOnly(outerNoun),
        vSalt,
        4,
      );
    }
    if (!l && u) {
      return _v(
        OutfitReasonLibrary.thereforeUmbrellaOnly(),
        vSalt,
        4,
      );
    }
    if (p.eveningCools && p.hasOuterwear && !p.rainy) {
      return _v(
        OutfitReasonLibrary.thereforeEveningLayer(outerNoun),
        vSalt,
        4,
      );
    }
    return null;
  }

  static String _carryLineVariant(
    String outerNoun,
    String outerAcc,
    int vSalt,
  ) {
    final kind = OutfitReasonLibrary.comfortKindForOuterNoun(outerNoun);
    return _v(
      OutfitReasonLibrary.carryWhenWarmMidday(kind, outerNoun, outerAcc),
      vSalt,
      11,
    );
  }

  static String _renderOutfitReasoning(_Plan p, int vSalt) {
    if (p.hasOuterwear && p.darkTopLightOuter) {
      final lightSentence = _v(
        OutfitReasonLibrary.stylingLightOuterSentence(),
        vSalt,
        5,
      );

      if (p.topLooksLikeTee) {
        final darkSentence = _v(
          OutfitReasonLibrary.stylingDarkLightTeeFirstSentence(),
          vSalt,
          7,
        );
        return '$darkSentence $lightSentence'.replaceAll(RegExp(r'\s+'), ' ');
      }

      final label = p.topDisplayLabel;
      final darkSentence = _v(
        OutfitReasonLibrary.stylingDarkLightLabelFirstSentence(label),
        vSalt,
        7,
      );
      return '$darkSentence $lightSentence'.replaceAll(RegExp(r'\s+'), ' ');
    }
    if (p.hasOuterwear && p.outerIsHoodieLike) {
      return _v(OutfitReasonLibrary.stylingHoodieOuter(), vSalt, 8);
    }
    if (p.darkDominant) {
      return _v(OutfitReasonLibrary.stylingDarkDominant(), vSalt, 8);
    }
    if (p.jeansBottom) {
      return _v(OutfitReasonLibrary.stylingJeans(), vSalt, 8);
    }
    return _v(OutfitReasonLibrary.stylingDefaultVibe(), vSalt, 9);
  }

  static String _renderFootwear(_Plan p, int vSalt) {
    if (p.sneakers) {
      return _v(OutfitReasonLibrary.shoesSneakers(), vSalt, 10);
    }
    if (p.boots) {
      return _v(OutfitReasonLibrary.shoesBoots(), vSalt, 10);
    }
    return '';
  }

  static String _lowerFirst(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t[0].toLowerCase() + t.substring(1);
  }

  static String _joinNonEmpty(List<String> parts) {
    return parts
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ---------------------------------------------------------------------------
  // Non-premium
  // ---------------------------------------------------------------------------

  static String _nonPremiumBlurb({
    required int tempC,
    required bool isRainy,
    required bool isWindy,
    required bool hasOuterwear,
  }) {
    final isCold = tempC < 10;
    final isMild = tempC >= 10 && tempC < 20;

    if (isCold || isRainy || isWindy) {
      final hint = hasOuterwear
          ? 'Ďalšia vrstva pomôže počas dňa.'
          : 'Ak chceš viac komfortu, zváž ľahkú vrstvu.';
      return 'Dnes je chladno alebo počasie nestále, preto outfit drží pohodlie a praktickosť. '
          '$hint Ak chceš detailnejšie vysvetlenie kombinácie, odomkni Premium.';
    }

    if (isMild) {
      return 'Dnes je mierne počasie, takže outfit pôsobí jednoducho a nositeľne. '
          'Premium ti ukáže presnejšie, prečo tieto kúsky spolu sedia.';
    }

    return 'Dnes je teplo, preto outfit ostáva ľahký a pohodlný na celý deň. '
        'Premium ti zobrazí detailnejšie stylistické zdôvodnenie.';
  }

  // ---------------------------------------------------------------------------

  static String _outerLayerWord(Map<String, dynamic> outer) {
    final b = _blob(outer);
    if (b.contains('hoodie') || b.contains('mikina')) return 'mikinu';
    if (b.contains('sako') || b.contains('blazer')) return 'sako';
    if (b.contains('kabát') || b.contains('kabat') || b.contains('coat')) {
      return 'kabát';
    }
    if (b.contains('bunda') || b.contains('jacket') || b.contains('parka')) {
      return 'bundu';
    }
    if (b.contains('vetrov') || b.contains('wind')) return 'vetrovku';
    return 'vrchnú vrstvu';
  }

  static String _outerAccusative(Map<String, dynamic> outer) {
    final b = _blob(outer);
    if (b.contains('kabát') ||
        b.contains('kabat') ||
        b.contains('coat') ||
        b.contains('sako') ||
        b.contains('blazer')) {
      return 'ho';
    }
    return 'ju';
  }

  static bool _outerLooksLight(Map<String, dynamic> outer) {
    if (outer.isEmpty) return false;
    final fam = _colorFamilies(_colorsOf(outer));
    final bl = _blob(outer);
    return fam.contains('white') ||
        fam.contains('beige') ||
        bl.contains('biel') ||
        bl.contains('white') ||
        bl.contains('svetl');
  }

  static List<String> _allColors(List<Map<String, dynamic>> items) {
    final out = <String>[];
    for (final it in items) {
      out.addAll(_colorsOf(it));
    }
    return out;
  }

  static String _shortLabel(Map<String, dynamic> item, String fallback) {
    if (item.isEmpty) return fallback;
    final n = (item['name'] ?? item['label'] ?? '').toString().trim();
    if (n.isEmpty) return fallback;
    if (n.length <= 36) return n;
    return '${n.substring(0, 33)}…';
  }

  static Map<String, dynamic> _normalizeItem(Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    map['name'] = (map['name'] ?? map['label'] ?? '').toString();
    map['category'] = (map['categoryKey'] ?? map['category'] ?? '').toString();
    map['subCategory'] =
        (map['subCategoryKey'] ?? map['subCategory'] ?? '').toString();
    map['mainGroup'] = (map['mainGroupKey'] ?? map['mainGroup'] ?? '').toString();
    map['typeKey'] = (map['typeKey'] ?? map['type'] ?? '').toString().trim();
    map['colors'] = map['colors'] ?? map['color'] ?? const [];
    return map;
  }

  static Map<String, dynamic> _findByType(
    List<Map<String, dynamic>> items,
    List<String> acceptedTypes,
  ) {
    for (final item in items) {
      final typeKey = (item['typeKey'] ?? '').toString().toLowerCase();
      if (acceptedTypes.contains(typeKey)) return item;
    }
    return const {};
  }

  static String _blob(Map<String, dynamic> item) {
    if (item.isEmpty) return '';
    return [
      (item['name'] ?? '').toString(),
      (item['label'] ?? '').toString(),
      (item['category'] ?? '').toString(),
      (item['subCategory'] ?? '').toString(),
      (item['mainGroup'] ?? '').toString(),
    ].join(' ').toLowerCase();
  }

  static List<String> _colorsOf(Map<String, dynamic> item) {
    if (item.isEmpty) return const [];

    final dyn = item['colors'];
    if (dyn is List) {
      return dyn.map((e) => e.toString()).toList();
    }
    if (dyn is String) {
      final s = dyn.trim();
      if (s.isEmpty) return const [];
      return s
          .replaceAll('[', '')
          .replaceAll(']', '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static Set<String> _colorFamilies(List<String> colors) {
    final fam = <String>{};
    for (final raw in colors) {
      final c = raw.toLowerCase();

      if (c.contains('čier') || c.contains('cier') || c.contains('black')) {
        fam.add('black');
      }
      if (c.contains('biel') || c.contains('white')) {
        fam.add('white');
      }
      if (c.contains('siv') || c.contains('gray') || c.contains('grey')) {
        fam.add('gray');
      }
      if (c.contains('béž') || c.contains('bez') || c.contains('beige')) {
        fam.add('beige');
      }
      if (c.contains('navy') || c.contains('tmavomod')) {
        fam.add('navy');
      }
      if (c.contains('červen') || c.contains('red')) fam.add('red');
      if (c.contains('zelen') || c.contains('green')) fam.add('green');
      if (c.contains('modr') || c.contains('blue')) fam.add('blue');
      if (c.contains('oranž') || c.contains('orange')) fam.add('orange');
      if (c.contains('žlt') || c.contains('yellow')) fam.add('yellow');
      if (c.contains('fial') || c.contains('purple')) fam.add('purple');
    }
    return fam;
  }
}
