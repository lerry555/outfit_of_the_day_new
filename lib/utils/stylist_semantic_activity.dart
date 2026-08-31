/// Shared, deterministic semantic activity resolver for Stylist text.
///
/// This is deliberately a *fallback / fast-path* language layer. It normalizes
/// Slovak diacritics and recognizes word families / common paraphrases rather
/// than enumerating every grammatical case in every caller. Generic outing
/// words ("výlet", "niekam von", "cesta") intentionally stay unresolved.
/// Named cities, countries, regions, attractions and performers are never
/// semantic evidence for an activity.
class StylistSemanticActivity {
  const StylistSemanticActivity._();

  static const String runtimeVersion = 'brain_v1_semantic_activity_v7';

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
    // Used only after the Conversation Brain proves an explicit user-authored
    // activity that is not in the fast-path taxonomy (lecture, appointment,
    // conference, ceremony, etc.). The fast parser itself never emits `other`.
    'other',
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
  /// It must never turn a generic trip or a named place into an activity.
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

    // Concept-level mountain walking. Geographic proper nouns are excluded;
    // the activity must come from terrain + movement meaning.
    final mountainEnvironment = _has(
      text,
      r'\b(?:vysokohorsk\w*|horsk\w*|alpinsk\w*|hreben\w*|vrchol\w*|trail\w*)\b',
    );
    final walkingOrRoute = _has(
      text,
      r'\b(?:chodnik\w*|trasa\w*|trail\w*|krac\w*|chod\w*|ist\w*|idem\w*|ideme\w*|pojd\w*|mota\w*|vyraz\w*|stup\w*)\b',
    );
    if (mountainEnvironment && walkingOrRoute) return 'hike';

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

    // Corrections can contain both the rejected and replacement place, e.g.
    // "nejdeme do mesta, ideme do lesa". When both city and nature walking
    // evidence are present, the later mentioned place is the authoritative one.
    final cityPlaceIndex = text.lastIndexOf(
      RegExp(r'\b(?:centr\w*|mest\w*)\b', caseSensitive: false),
    );
    final naturePlaceIndex = text.lastIndexOf(
      RegExp(r'\b(?:les\w*|prirod\w*|luk\w*)\b', caseSensitive: false),
    );
    // A destination verb (idem/ideme/ísť/pôjdeme) says WHERE the user is
    // going, not HOW they will move there. Only explicit walking/sightseeing
    // language may create a *_walk activity. This prevents generic city or
    // forest outings from being rewritten as a made-up walk.
    final explicitWalkingMovement = _has(
      text,
      r'\b(?:prechadz\w*|prej\w*\s+sa|krac\w*|popozer\w*|sightseeing\w*|peso)\b',
    );
    final cityWalkEvidence = cityPlaceIndex >= 0 && explicitWalkingMovement;
    final natureWalkEvidence = naturePlaceIndex >= 0 && explicitWalkingMovement;

    if (cityWalkEvidence && natureWalkEvidence) {
      return naturePlaceIndex > cityPlaceIndex ? 'nature_walk' : 'city_walk';
    }
    if (cityWalkEvidence) return 'city_walk';
    // Keep the known typo-tolerant sightseeing phrase, but never let bare
    // "idem do mesta" become a walk.
    if (_has(text, r'\bpopozer\w*\s+po\s+(?:mete|mest\w*)\b') ||
        _has(text, r'\bpopozer\w*\s+mest\w*\b')) {
      return 'city_walk';
    }
    if (natureWalkEvidence) return 'nature_walk';

    if (_has(
      text,
      r'\b(?:autom\w*|vlakom\w*|lietadl\w*|letim\w*|letime\w*|presun\w*|autobus\w*|trajekt\w*)\b',
    )) {
      return 'travel';
    }

    return null;
  }

  static bool looksLikeGenericTrip(String input) {
    final text = normalize(input);
    return _has(
      text,
      r'\b(?:vylet\w*|cest\w*|dovolen\w*|niekam|prec)\b',
    );
  }

  static bool looksRemotePlan(String input) {
    final text = normalize(input);
    final activity = resolveExplicit(text);
    if (looksLikeGenericTrip(text)) return true;
    if (_has(
      text,
      r'\b(?:hor\w*|les\w*|prirod\w*|kopc\w*|zoo|hrad\w*|festival\w*|svadb\w*)\b',
    )) {
      return true;
    }
    return activity == 'hike' ||
        activity == 'nature_walk' ||
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
