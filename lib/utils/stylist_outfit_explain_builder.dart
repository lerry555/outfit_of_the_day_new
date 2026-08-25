import '../data/stylist_opinion.dart';
import '../data/wardrobe_analysis.dart';
import 'slovak_outfit_instrumental.dart';
import 'stylist_occasion_guidance.dart';
import 'stylist_personality.dart';

/// Deterministické vysvetlenie outfitu pre Stylist Chat — ľudská slovenčina bez technického žargónu.
class StylistOutfitExplainBuilder {
  const StylistOutfitExplainBuilder._();

  static final RegExp _technicalJargon = RegExp(
    r'formality\s*target|formalitytarget|finalscore|base\s*score|intent\s*bonus|'
    r'generated\s*candidates?|topcount|candidate\s*index|violated\s*non|'
    r'preferred\s*families|fallback\s*families|outfit\s*intent|item\s*eligibility|'
    r'compromise\s*notes|wardrobe\s*analysis|blocksidealoutfit|wirekey|'
    r'\blevel\s*\d|\bscore\s*[=:]|\bfallback\b|\bintent\b|\bkandidát',
    caseSensitive: false,
  );

  static bool containsTechnicalJargon(String text) {
    return _technicalJargon.hasMatch(text.trim());
  }

  static bool replyIsMisleading({
    required String reply,
    required StylistOccasionProfile profile,
    WardrobeAnalysis? wardrobeAnalysis,
    StylistOpinion? stylistOpinion,
  }) {
    final lower = reply.toLowerCase();
    final formal = profile.dressCode.formalityTarget >= 7;
    final analysis = wardrobeAnalysis ?? const WardrobeAnalysis();

    // Rule 7: AI explain nesmie byť optimistickejší než StylistOpinion.
    if (stylistOpinion != null &&
        _contradictsOpinion(lower, stylistOpinion)) {
      return true;
    }

    if (analysis.usedCompromise) {
      final tooConfident = <String>[
        'ideálny outfit',
        'ideálna voľba',
        'perfektný outfit',
        'perfektná voľba',
        'úplne vhodný',
        'nemusíš nič meniť',
        'outfit je vhodný',
        'sedí perfektne',
      ];
      if (tooConfident.any(lower.contains)) return true;
    }

    if (formal) {
      if ((lower.contains('tenisk') || lower.contains('sneaker')) &&
          (lower.contains('elegant') ||
              lower.contains('formál') ||
              lower.contains('formal'))) {
        return true;
      }
      if ((lower.contains('tričk') || lower.contains('trick')) &&
          (lower.contains('ideál') || lower.contains('ideal')) &&
          (lower.contains('svadb') ||
              lower.contains('pohovor') ||
              lower.contains('formál'))) {
        return true;
      }
      if (profile.excludeShorts &&
          (lower.contains('šortk') || lower.contains('shortk')) &&
          (lower.contains('skvel') ||
              lower.contains('super') ||
              lower.contains('ideál'))) {
        return true;
      }
    }

    if (analysis.missingItems.any((g) => g.category == 'shirt') &&
        (lower.contains('košeľ') || lower.contains('kosel')) &&
        (lower.contains('máš') || lower.contains('mas')) &&
        !lower.contains('nemáš') &&
        !lower.contains('nemas') &&
        !lower.contains('nemáte')) {
      return true;
    }

    return false;
  }

  /// Vráti true, ak AI odpoveď znie sebavedomejšie než [opinion] dovoľuje.
  static bool _contradictsOpinion(String lower, StylistOpinion opinion) {
    // Úprimné „nie je to ideál / nie úplný ideál" NIE je vychvaľovanie.
    final honestlyNotIdeal = lower.contains('nie je ideál') ||
        lower.contains('nie je to ideál') ||
        lower.contains('nie ideál') ||
        lower.contains('nie úplne ideál') ||
        lower.contains('nie úplný ideál') ||
        lower.contains('nie je ideal') ||
        lower.contains('nie je to ideal');

    // acceptable/weak → outfit nesmie byť prezentovaný ako ideál/perfektný.
    // Používame afirmatívne frázy, nie holé „ideál" (aby sme neoznačili úprimné
    // „nie je to ideál").
    final overConfident = <String>[
      if (!honestlyNotIdeal) ...[
        'ideálny outfit',
        'idealny outfit',
        'ideálna voľba',
        'idealna volba',
        'je ideáln',
        'je ideal',
        'úplne ideál',
        'uplne ideal',
      ],
      'perfektn',
      'dokonal',
      'skvelá voľba',
      'skvela volba',
      'skvelý outfit',
      'skvely outfit',
      'výborná voľba',
      'vyborna volba',
      'pokojne odporúčam',
      'pokojne odporucam',
      'nemusíš nič meniť',
      'nemusis nic menit',
      'sedí perfektne',
      'sedi perfektne',
    ];
    // weak → ani mierne pochvalné „dobrá/super voľba" nie je v poriadku.
    const tooPositiveForWeak = <String>[
      'dobrá voľba',
      'dobra volba',
      'super voľba',
      'super volba',
      'skvel',
      'výborn',
      'vyborn',
      'paráda',
      'parada',
    ];

    switch (opinion.opinionLevel) {
      case StylistOpinionLevel.excellent:
      case StylistOpinionLevel.good:
        return false;
      case StylistOpinionLevel.acceptable:
        return overConfident.any(lower.contains);
      case StylistOpinionLevel.weak:
        return overConfident.any(lower.contains) ||
            tooPositiveForWeak.any(lower.contains);
    }
  }

  static bool shouldUseLocalExplain({
    required String? aiReply,
    required StylistOccasionProfile profile,
    WardrobeAnalysis? wardrobeAnalysis,
    StylistOpinion? stylistOpinion,
  }) {
    final reply = (aiReply ?? '').trim();
    if (reply.isEmpty) return true;
    if (containsTechnicalJargon(reply)) return true;
    if (replyIsMisleading(
      reply: reply,
      profile: profile,
      wardrobeAnalysis: wardrobeAnalysis,
      stylistOpinion: stylistOpinion,
    )) {
      return true;
    }
    return false;
  }

  static String buildLocalExplainSk({
    required List<Map<String, dynamic>> suggestedItems,
    required StylistOccasionProfile profile,
    WardrobeAnalysis? wardrobeAnalysis,
    String? weatherLine,
    String? activityType,
    StylistOpinion? stylistOpinion,
    bool weatherIsRainy = false,
    bool wetGroundMuddy = false,
    int? tempC,
    String? conversationText,
  }) {
    final labels = suggestedItems
        .map((item) => (item['name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (labels.isEmpty) {
      return stylistOpinion?.shortOpinionSk ??
          'Pripravil som ti outfit z toho, čo máš v šatníku.';
    }

    final analysis = wardrobeAnalysis ?? const WardrobeAnalysis();
    // Persona activityType mení iba tón textu (meeting vs work) — nezasahuje do
    // selection, opinion engine ani wardrobe analysis (tie dostávajú activityType
    // nezmenený zvonku).
    final personaActivity = _personaActivityType(activityType, conversationText);
    final occasion = _occasionPhrase(profile, activityType: personaActivity);

    // Rule 5: ak máme StylistOpinion, explain začne shortOpinionSk a tón
    // nikdy nie je optimistickejší než opinion (rule 1–4).
    if (stylistOpinion != null) {
      return _buildOpinionAwareExplainSk(
        labels: labels,
        profile: profile,
        analysis: analysis,
        occasion: occasion,
        opinion: stylistOpinion,
        weatherLine: weatherLine,
        activityType: personaActivity,
        weatherIsRainy: weatherIsRainy,
        wetGroundMuddy: wetGroundMuddy,
        tempC: tempC,
      );
    }
    final pieces = SlovakOutfitInstrumental.joinWithA(
      labels.map(SlovakOutfitInstrumental.accusative).toList(growable: false),
    );
    final missingCategories = _missingCategories(analysis);
    final level = analysis.usedCompromise
        ? StylistOpinionLevel.acceptable
        : StylistOpinionLevel.good;
    final weatherBucket = _weatherBucket(
      weatherIsRainy: weatherIsRainy,
      wetGroundMuddy: wetGroundMuddy,
      tempC: tempC,
    );
    final buffer = StringBuffer();

    final flavour = StylistPersonality.activityFlavour(
      activityType: personaActivity,
      level: level,
      usedCompromise: analysis.usedCompromise,
      missingCategories: missingCategories,
      weatherBucket: weatherBucket,
    );

    buffer.write(
      '${StylistPersonality.opening(
        level: level,
        occasion: occasion,
        usedCompromise: analysis.usedCompromise,
        biggestMissingPiece: analysis.missingItems.isNotEmpty
            ? analysis.missingItems.first.category
            : null,
        missingCategories: missingCategories,
        activityType: personaActivity,
        suppressOccasionSuffix: flavour != null,
        weatherBucket: weatherBucket,
      )} ',
    );

    if (flavour != null) buffer.write('$flavour ');

    buffer.write(
      '${StylistPersonality.outfitIntro(
        pieces: pieces,
        level: level,
        activityType: personaActivity,
        usedCompromise: analysis.usedCompromise,
        missingCategories: missingCategories,
        weatherBucket: weatherBucket,
      )} ',
    );

    if (analysis.usedCompromise) {
      final primaryGap =
          analysis.missingItems.isNotEmpty ? analysis.missingItems.first : null;
      if (primaryGap != null && primaryGap.explanationSk.isNotEmpty) {
        buffer.write('${primaryGap.explanationSk} ');
      }
      final compromise = StylistPersonality.compromisePhrase(
        level: level,
        usedCompromise: true,
        activityType: personaActivity,
        missingCategories: missingCategories,
        weatherBucket: weatherBucket,
      );
      if (compromise != null) buffer.write('$compromise ');
    }

    final positive = _positivePieceNote(labels, profile, analysis.usedCompromise);
    if (positive != null && positive.isNotEmpty) {
      buffer.write('$positive ');
    }

    final gapCategory =
        analysis.missingItems.isNotEmpty ? analysis.missingItems.first.category : null;
    final purchase = StylistPersonality.wardrobeClosing(
      gapCategory: gapCategory,
      activityType: personaActivity,
      level: level,
      usedCompromise: analysis.usedCompromise,
      missingCategories: missingCategories,
      weatherBucket: weatherBucket,
    );
    if (purchase != null && purchase.isNotEmpty) {
      buffer.write(purchase);
    } else if (!analysis.usedCompromise) {
      buffer.write(
        StylistPersonality.excellentClosing(
          occasion: occasion,
          level: StylistOpinionLevel.good,
          activityType: personaActivity,
          usedCompromise: false,
          missingCategories: missingCategories,
          weatherBucket: weatherBucket,
        ),
      );
    }

    final weather = (weatherLine ?? '').trim();
    if (weather.isNotEmpty) {
      buffer.write(' $weather');
    }

    return _normalizeWhitespace(buffer.toString());
  }

  /// Neurčitá veta z `shortOpinionSk`, ktorú v explaine nahrádzame konkrétnym
  /// dôvodom (dážď / mokrá tráva / teplo).
  static const String _vagueWeatherPhrase =
      'Na dnešné počasie by som niečo ešte upravil.';

  /// Explain, ktorý rešpektuje [StylistOpinion] — začína `shortOpinionSk`
  /// a tón zodpovedá `opinionLevel` (nikdy nie je optimistickejší).
  static String _buildOpinionAwareExplainSk({
    required List<String> labels,
    required StylistOccasionProfile profile,
    required WardrobeAnalysis analysis,
    required String occasion,
    required StylistOpinion opinion,
    String? weatherLine,
    String? activityType,
    bool weatherIsRainy = false,
    bool wetGroundMuddy = false,
    int? tempC,
  }) {
    final buffer = StringBuffer();
    final missingCategories = _missingCategories(analysis);
    final missing = opinion.biggestMissingPiece;
    final weatherBucket = _weatherBucket(
      weatherIsRainy: weatherIsRainy,
      wetGroundMuddy: wetGroundMuddy,
      tempC: tempC,
    );

    // M8.1: flavour poznáme vopred, aby opening nezduploval „Na X sa s tým dá ísť".
    final flavour = StylistPersonality.activityFlavour(
      activityType: activityType,
      level: opinion.opinionLevel,
      usedCompromise: analysis.usedCompromise,
      missingCategories: missingCategories,
      weatherBucket: weatherBucket,
    );

    final openingText = StylistPersonality.opening(
      level: opinion.opinionLevel,
      occasion: occasion,
      usedCompromise: analysis.usedCompromise,
      biggestMissingPiece: missing,
      missingCategories: missingCategories,
      activityType: activityType,
      suppressOccasionSuffix: flavour != null,
      weatherBucket: weatherBucket,
    );
    buffer.write('$openingText ');

    if (flavour != null) buffer.write('$flavour ');

    final pieces = SlovakOutfitInstrumental.joinWithA(
      labels.map(SlovakOutfitInstrumental.accusative).toList(growable: false),
    );
    if (pieces.isNotEmpty) {
      buffer.write(
        '${StylistPersonality.outfitIntro(
          pieces: pieces,
          level: opinion.opinionLevel,
          activityType: activityType,
          usedCompromise: analysis.usedCompromise,
          missingCategories: missingCategories,
          weatherBucket: weatherBucket,
        )} ',
      );
    }

    // Rule 2: kontextová veta o spodku namiesto generickej „dobrý základ".
    final bottomNote = _bottomContextNote(
      labels: labels,
      profile: profile,
      activityType: activityType,
    );
    if (bottomNote != null && bottomNote.isNotEmpty) {
      buffer.write('$bottomNote ');
    }

    // M8.1: pri smart casual (rande/kino/večera) + outdoor obuv nepôsob elegantne.
    final footwearNote = _socialFootwearNote(
      labels: labels,
      activityType: activityType,
      occasion: occasion,
    );
    if (footwearNote != null && footwearNote.isNotEmpty) {
      buffer.write('$footwearNote ');
    }

    final compromise = StylistPersonality.compromisePhrase(
      level: opinion.opinionLevel,
      usedCompromise: analysis.usedCompromise,
      activityType: activityType,
      missingCategories: missingCategories,
      weatherBucket: weatherBucket,
    );
    if (compromise != null &&
        !openingText.toLowerCase().contains('kompromis') &&
        !openingText.toLowerCase().contains('ideál')) {
      buffer.write('$compromise ');
    }

    switch (opinion.opinionLevel) {
      case StylistOpinionLevel.excellent:
        buffer.write(
          StylistPersonality.excellentClosing(
            occasion: occasion,
            level: opinion.opinionLevel,
            activityType: activityType,
            usedCompromise: analysis.usedCompromise,
            missingCategories: missingCategories,
            weatherBucket: weatherBucket,
          ),
        );
      case StylistOpinionLevel.good:
        break;
      case StylistOpinionLevel.acceptable:
        final gapCategory = analysis.missingItems.isNotEmpty
            ? analysis.missingItems.first.category
            : null;
        final purchase = StylistPersonality.wardrobeClosing(
          gapCategory: gapCategory,
          activityType: activityType,
          level: opinion.opinionLevel,
          usedCompromise: analysis.usedCompromise,
          missingCategories: missingCategories,
          weatherBucket: weatherBucket,
        );
        if (purchase != null && purchase.isNotEmpty) {
          buffer.write(purchase);
        }
      case StylistOpinionLevel.weak:
        final opinionMentionsMissing = missing != null &&
            openingText.toLowerCase().contains(missing.toLowerCase());
        final weakNote = StylistPersonality.weakMissingNote(
          piece: missing ?? '',
          level: opinion.opinionLevel,
          activityType: activityType,
          usedCompromise: analysis.usedCompromise,
          missingCategories: missingCategories,
          alreadyMentioned: opinionMentionsMissing,
          weatherBucket: weatherBucket,
        );
        if (weakNote != null) buffer.write('$weakNote ');
        final gapCategory = analysis.missingItems.isNotEmpty
            ? analysis.missingItems.first.category
            : null;
        final purchase = StylistPersonality.wardrobeClosing(
          gapCategory: gapCategory,
          activityType: activityType,
          level: opinion.opinionLevel,
          usedCompromise: analysis.usedCompromise,
          missingCategories: missingCategories,
          weatherBucket: weatherBucket,
        );
        if (purchase != null && purchase.isNotEmpty) {
          buffer.write(purchase);
        }
    }

    // Rule 1: konkrétny dôvod pre počasie namiesto neurčitej vety.
    final weatherReason = _weatherReasonNote(
      labels: labels,
      weatherIsRainy: weatherIsRainy,
      wetGroundMuddy: wetGroundMuddy,
      tempC: tempC,
    );
    if (weatherReason != null && weatherReason.isNotEmpty) {
      buffer.write(' $weatherReason');
    }

    final weather = (weatherLine ?? '').trim();
    if (weather.isNotEmpty) {
      buffer.write(' $weather');
    }

    return _normalizeWhitespace(buffer.toString());
  }

  static List<String> _missingCategories(WardrobeAnalysis analysis) =>
      analysis.missingItems.map((gap) => gap.category).toList(growable: false);

  /// Deterministický „weather bucket" — pridáva do výberu viet ďalší rozmer,
  /// aby rovnaký outfit pri inom počasí neznel vždy rovnako. Nemení výber ani
  /// opinion, iba formuláciu (rovnaký vstup = rovnaký text).
  static String _weatherBucket({
    required bool weatherIsRainy,
    required bool wetGroundMuddy,
    int? tempC,
  }) {
    if (wetGroundMuddy) return 'wet';
    if (weatherIsRainy) return 'rain';
    if (tempC != null && tempC >= 24) return 'hot';
    if (tempC != null && tempC <= 5) return 'cold';
    return 'mild';
  }

  static String _stripVagueWeatherPhrase(String opinionText) {
    return opinionText.replaceAll(_vagueWeatherPhrase, '').trim();
  }

  /// Kontextová veta o spodku podľa príležitosti (Rule 2).
  static String? _bottomContextNote({
    required List<String> labels,
    required StylistOccasionProfile profile,
    required String? activityType,
  }) {
    final bottom = _bottomLabel(labels);
    if (bottom == null) return null;
    final lower = bottom.toLowerCase();
    final isJeans = lower.contains('rifle') || lower.contains('džín') ||
        lower.contains('dzin');
    final isPants = lower.contains('nohav');
    final isShorts = lower.contains('šortk') || lower.contains('sortk') ||
        lower.contains('kraťas') || lower.contains('kratas');
    final label = _capitalize(bottom);

    final type = activityType ?? '';
    final formal = type == 'wedding' ||
        type == 'interview' ||
        type == 'funeral' ||
        profile.dressCode.formalityTarget >= 7;
    final social = type == 'date' || type == 'cinema' || type == 'dinner';
    // M8.1: social vyhodnocujeme pred „work", inak by večera spadla do
    // business-casual vety.
    final work = !formal &&
        !social &&
        (type == 'work' || type == 'meeting' ||
            profile.dressCode.formalityTarget >= 5);
    final outdoor = type == 'hike' || type == 'mushroom';

    if (formal) {
      if (isPants) return '$label pôsobia upravenejšie než rifle.';
      if (isJeans) {
        return '$label sú kompromis — košeľa a nohavice by pôsobili '
            'formálnejšie.';
      }
      return null;
    }
    if (social) {
      if (isPants) return '$label pôsobia upravene a sadnú na smart casual.';
      if (isJeans) {
        // Rule 3 (M8.1): pri večeri žiadne „business casual".
        if (type == 'dinner') {
          return '$label sú v poriadku, ale košeľa by večeru posunula vyššie.';
        }
        return '$label sú fajn na smart casual, ale nohavice by pôsobili '
            'upravenejšie.';
      }
      if (isShorts) {
        return 'Šortky sú skôr uvoľnené — na smart casual by nohavice sadli '
            'lepšie.';
      }
      return null;
    }
    if (work) {
      if (isJeans) {
        return '$label sú v poriadku na business casual, ale košeľa by '
            'outfit posunula vyššie.';
      }
      if (isPants) return '$label sú na prácu v poriadku.';
      return null;
    }
    if (outdoor) {
      if (isPants || isJeans) return '$label sú praktickejšie než šortky.';
      return null;
    }
    return null;
  }

  /// Persona activityType — mení iba tón textu, nie výber/opinion.
  /// „work" scenár, ktorý spomína meeting/prezentáciu, dostane tón „meeting".
  static String? _personaActivityType(
    String? activityType,
    String? conversationText,
  ) {
    if (activityType != 'work') return activityType;
    final blob = (conversationText ?? '').toLowerCase();
    final mentionsMeeting = blob.contains('meeting') ||
        blob.contains('stretnut') ||
        blob.contains('prezent') ||
        blob.contains('porad') ||
        blob.contains('klient');
    return mentionsMeeting ? 'meeting' : activityType;
  }

  /// M8.1 (Rule 4): pri smart casual + outdoor obuvi buď priamy — pomenuj obuv
  /// aj príležitosť, ale zdôvodni ju dostupnosťou.
  static String? _socialFootwearNote({
    required List<String> labels,
    required String? activityType,
    required String occasion,
  }) {
    final social = activityType == 'date' ||
        activityType == 'cinema' ||
        activityType == 'dinner';
    if (!social) return null;
    final footwear = _footwearLabel(labels);
    if (footwear == null || !_isOutdoorLabel(footwear)) return null;
    final occ = occasion.trim().isEmpty ? 'takúto príležitosť' : occasion;
    return '${_capitalize(footwear)} by som na $occ nebral ako ideál, '
        'ale z dostupných možností dávajú najväčší zmysel.';
  }

  /// Konkrétny dôvod pri počasí namiesto neurčitej vety (Rule 1).
  static String? _weatherReasonNote({
    required List<String> labels,
    required bool weatherIsRainy,
    required bool wetGroundMuddy,
    int? tempC,
  }) {
    final footwear = _footwearLabel(labels);
    if (wetGroundMuddy && footwear != null && _isOutdoorLabel(footwear)) {
      return 'Do mokrej trávy sú ${footwear.toLowerCase()} dobrá voľba.';
    }
    if (weatherIsRainy && footwear != null && !_isOutdoorLabel(footwear)) {
      return 'Keďže môže pršať, ${footwear.toLowerCase()} sú kompromis.';
    }
    if (tempC != null && tempC >= 24) {
      return 'Pri tomto počasí držím outfit ľahší.';
    }
    return null;
  }

  static String? _bottomLabel(List<String> labels) {
    for (final label in labels) {
      final lower = label.toLowerCase();
      if (lower.contains('nohav') ||
          lower.contains('rifle') ||
          lower.contains('džín') ||
          lower.contains('dzin') ||
          lower.contains('šortk') ||
          lower.contains('sortk') ||
          lower.contains('kraťas') ||
          lower.contains('kratas') ||
          lower.contains('suk')) {
        return label;
      }
    }
    return null;
  }

  static String? _footwearLabel(List<String> labels) {
    for (final label in labels) {
      final lower = label.toLowerCase();
      if (lower.contains('tenisk') ||
          lower.contains('topán') ||
          lower.contains('topan') ||
          lower.contains('obuv') ||
          lower.contains('sandál') ||
          lower.contains('sandal') ||
          lower.contains('čižm') ||
          lower.contains('cizm')) {
        return label;
      }
    }
    return null;
  }

  static bool _isOutdoorLabel(String label) {
    final lower = label.toLowerCase();
    return lower.contains('turist') ||
        lower.contains('hiking') ||
        lower.contains('trek') ||
        lower.contains('čižm') ||
        lower.contains('cizm');
  }

  static String? _positivePieceNote(
    List<String> labels,
    StylistOccasionProfile profile,
    bool usedCompromise,
  ) {
    for (final label in labels) {
      final lower = label.toLowerCase();
      if (lower.contains('nohav') || lower.contains('rifle')) {
        return '${_capitalize(label)} sú dobrý základ.';
      }
      if (lower.contains('tenisk') || lower.contains('topán')) {
        if (profile.dressCode.formalityTarget >= 7) continue;
        return '$label budú na túto aktivitu pohodlné.';
      }
    }
    return null;
  }

  static String _occasionPhrase(
    StylistOccasionProfile profile, {
    String? activityType,
  }) {
    switch (activityType) {
      case 'wedding':
        return 'svadbu';
      case 'interview':
        return 'pohovor';
      case 'work':
        return 'prácu';
      case 'meeting':
        return 'stretnutie';
      case 'hike':
        return 'túru';
      case 'mushroom':
        return 'hubovanie';
      case 'barbecue':
        return 'grilovačku';
      case 'date':
        return 'rande';
      case 'cinema':
        return 'kino';
      case 'dinner':
        return 'večeru';
    }
    final label = profile.label.trim();
    if (label.isNotEmpty) return label.toLowerCase();
    switch (profile.dressCode.id) {
      case 'wedding':
        return 'svadbu';
      case 'interview':
        return 'pohovor';
      case 'work':
        return 'prácu';
      case 'hike':
        return 'túru';
      case 'bbq':
      case 'celebration':
        return 'grilovačku';
      default:
        return 'túto príležitosť';
    }
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  static String _normalizeWhitespace(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').replaceAll(' .', '.').trim();
  }

  static String stripTechnicalJargon(String text) {
    var out = text.trim();
    if (out.isEmpty) return out;
    out = out.replaceAll(_technicalJargon, '');
    return _normalizeWhitespace(out);
  }
}
