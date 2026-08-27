/// Shared, deterministic semantic activity resolver for Stylist text.
///
/// This is deliberately a *fallback / fast-path* language layer. It normalizes
/// Slovak diacritics and recognizes word families / common paraphrases rather
/// than enumerating every grammatical case in every caller. Generic outing
/// words ("výlet", "niekam von", "cesta") intentionally stay unresolved.
class StylistSemanticActivity {
  const StylistSemanticActivity._();

  static const Set<String> canonicalActivities = <String>{
    'hike',
    'nature_walk',
    'city_walk',
    'dinner',
    'travel',
    'work',
    'gym',
    'run',
    'cycling',
    'barbecue',
    'mushroom',
    'date',
    'cinema',
    'concert',
    'wedding',
    'funeral',
    'interview',
    'zoo',
  };

  static String normalize(String input) {
    var value = input.toLowerCase();
    const replacements = <String, String>{
      'á': 'a',
      'ä': 'a',
      'č': 'c',
      'ď': 'd',
      'é': 'e',
      'í': 'i',
      'ľ': 'l',
      'ĺ': 'l',
      'ň': 'n',
      'ó': 'o',
      'ô': 'o',
      'ŕ': 'r',
      'š': 's',
      'ť': 't',
      'ú': 'u',
      'ý': 'y',
      'ž': 'z',
    };
    replacements.forEach((from, to) {
      value = value.replaceAll(from, to);
    });
    return value
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? canonicalize(String? value) {
    final normalized = normalize(value ?? '').replaceAll(' ', '_');
    if (canonicalActivities.contains(normalized)) return normalized;
    if (normalized == 'hiking' || normalized == 'trekking') return 'hike';
    if (normalized == 'mesto' || normalized == 'sightseeing') {
      return 'city_walk';
    }
    if (normalized == 'forest_walk' || normalized == 'outdoor_walk') {
      return 'nature_walk';
    }
    return null;
  }

  /// Resolves only activities that the user's wording itself makes explicit.
  /// It must never turn a generic trip into hiking/city walking by assumption.
  static String? resolveExplicit(String input) {
    final text = normalize(input);
    if (text.isEmpty) return null;

    if (_has(text, r'\b(?:svadb\w*|sobas\w*)\b')) return 'wedding';
    if (_has(text, r'\b(?:pohreb\w*|kar\w*)\b')) return 'funeral';
    if (_has(text, r'\b(?:pohovor\w*|interview\w*)\b')) return 'interview';
    if (_has(text, r'\b(?:rande\w*|date night)\b')) return 'date';
    if (_has(text, r'\b(?:kino\w*|cinema\w*|movie\w*)\b')) return 'cinema';
    if (_has(text, r'\b(?:koncert\w*|festival\w*)\b')) return 'concert';
    if (_has(text, r'\bzoo\b')) return 'zoo';

    if (_has(text, r'\b(?:hub\w*|hrib\w*|hubarc\w*)\b')) {
      return 'mushroom';
    }
    if (_has(text, r'\b(?:gril\w*|grill\w*|bbq|barbecue\w*|opek\w*)\b')) {
      return 'barbecue';
    }

    // Dinner, but deliberately never plain "večer".
    if (_has(text, r'\b(?:vecer(?:a|u|i|ou)|restaur\w*|dinner)\b')) {
      return 'dinner';
    }

    // Strong hiking language. The `tur...` noun pattern covers grammatical
    // cases (túra, túry, túru, túre, túrou, túrami, túrach) in one family.
    if (_has(
      text,
      r'\b(?:turistik\w*|turistick\w*|tur(?:a|y|u|e|ou|ami|ach)|trek\w*|hike|hiking|vyslap\w*|hrebenovk\w*)\b',
    )) {
      return 'hike';
    }
    if (_has(
      text,
      r'\b(?:vystup\w*|slap\w*)\b.*\b(?:vrchol\w*|kopec\w*|hreben\w*)\b',
    )) {
      return 'hike';
    }
    if (_has(text, r'\b(?:na|po)\s+(?:vrchol\w*|hreben\w*)\b')) {
      return 'hike';
    }
    if (_has(text, r'\b(?:do|na|po)\s+hor(?:y|ach|ami|u|ou)?\b')) {
      return 'hike';
    }

    if (_has(text, r'\b(?:behat\w*|beh\w*|jogging\w*)\b')) return 'run';
    if (_has(text, r'\b(?:bicykl\w*|cyklist\w*|bike\w*)\b')) return 'cycling';
    if (_has(text, r'\b(?:posil\w*|fitko\w*|fitness\w*|gym\w*|cvicen\w*)\b')) {
      return 'gym';
    }
    if (_has(text, r'\b(?:prac\w*|robot\w*)\b') &&
        !_has(text, r'\b(?:pracovna cesta|sluzobna cesta)\b')) {
      return 'work';
    }

    if (_has(text, r'\b(?:pamiat\w*|sightseeing\w*|prehliadk\w*)\b')) {
      return 'city_walk';
    }
    if (_has(
          text,
          r'\b(?:centrum\w*|centre\w*|mesto\w*|meste\w*|mestom\w*)\b',
        ) &&
        _has(
          text,
          r'\b(?:prechadz\w*|chod\w*|popozer\w*|pozriet\w*|pozer\w*)\b',
        )) {
      return 'city_walk';
    }
    if (_has(text, r'\bpo\s+mete\b') ||
        _has(text, r'\bpopozer\w*\s+mest\w*\b')) {
      return 'city_walk';
    }

    if (_has(text, r'\b(?:do|v|po)\s+les\w*\b')) return 'nature_walk';
    if (_has(text, r'\b(?:les\w*|prirod\w*|luk\w*)\b') &&
        _has(
          text,
          r'\b(?:prechadz\w*|chod\w*|idem\w*|ideme\w*|ist\w*|pojd\w*|vyraz\w*)\b',
        )) {
      return 'nature_walk';
    }

    if (_has(text, r'\b(?:autom\w*|vlakom\w*|lietadl\w*|letim\w*|presun\w*)\b')) {
      return 'travel';
    }

    return null;
  }

  static bool looksLikeGenericTrip(String input) {
    final text = normalize(input);
    return _has(
      text,
      r'\b(?:vylet\w*|cest\w*|dovolen\w*|niekam|prec|von)\b',
    );
  }

  static bool looksRemotePlan(String input) {
    final text = normalize(input);
    final activity = resolveExplicit(text);
    if (looksLikeGenericTrip(text)) return true;
    if (_has(
      text,
      r'\b(?:hor\w*|les\w*|prirod\w*|tatr\w*|kopc\w*|zoo|hrad\w*|festival\w*|svadb\w*)\b',
    )) {
      return true;
    }
    return activity == 'hike' ||
        activity == 'nature_walk' ||
        activity == 'city_walk' ||
        activity == 'travel' ||
        activity == 'mushroom' ||
        activity == 'wedding' ||
        activity == 'funeral' ||
        activity == 'concert' ||
        activity == 'zoo';
  }

  static bool isOutdoor(String? canonical) =>
      canonical == 'hike' ||
      canonical == 'nature_walk' ||
      canonical == 'mushroom' ||
      canonical == 'run' ||
      canonical == 'cycling' ||
      canonical == 'barbecue';

  static bool _has(String text, String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(text);
}
