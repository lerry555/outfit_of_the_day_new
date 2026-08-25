/// Skloňovanie názvov kúskov do inštrumentálu pre frázy typu „s čiernym tričkom“.
class SlovakOutfitInstrumental {
  const SlovakOutfitInstrumental._();

  static const Map<String, List<String>> _colorInstrumental = {
    'čiern': ['čiernym', 'čiernymi'],
    'modr': ['modrým', 'modrými'],
    'biel': ['bielym', 'bielymi'],
    'siv': ['sivým', 'sivými'],
    'bordov': ['bordovým', 'bordovými'],
    'zelen': ['zeleným', 'zelenými'],
    'červen': ['červeným', 'červenými'],
    'béžov': ['béžovým', 'béžovými'],
    'bezov': ['béžovým', 'béžovými'],
    'hned': ['hnedým', 'hnedými'],
    'žlt': ['žltým', 'žltými'],
    'zlt': ['žltým', 'žltými'],
    'ružov': ['ružovým', 'ružovými'],
    'ruzov': ['ružovým', 'ružovými'],
    'fialov': ['fialovým', 'fialovými'],
    'oranžov': ['oranžovým', 'oranžovými'],
    'oranzov': ['oranžovým', 'oranžovými'],
    'tmavomodr': ['tmavomodrým', 'tmavomodrými'],
    'svetlomodr': ['svetlomodrým', 'svetlomodrými'],
    'khaki': ['khaki', 'khaki'],
    'zlat': ['zlatým', 'zlatými'],
    'strieborn': ['strieborným', 'striebornými'],
  };

  static const Set<String> _garmentWords = {
    'tričko',
    'tricko',
    'tielko',
    'košeľa',
    'kosela',
    'košelu',
    'šortky',
    'sortky',
    'tenisky',
    'topánky',
    'topanky',
    'nohavice',
    'rifle',
    'bunda',
    'mikina',
    'kabát',
    'kabat',
    'sukňa',
    'sukna',
    'sveter',
    'vesta',
    'mikinu',
    'bundu',
  };

  static String phrase(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return trimmed;

    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return trimmed;

    final nounIndex = _findGarmentNounIndex(words);
    if (nounIndex <= 0) return trimmed;

    final noun = words[nounIndex];
    final plural = _isPluralGarment(noun);
    final declinedAdj = _declineAdjective(words.first, plural: plural);
    if (declinedAdj == null) return trimmed;

    final declinedNoun = _declineNoun(noun);
    final prefix = <String>[declinedAdj];
    if (nounIndex > 1) {
      prefix.addAll(words.sublist(1, nounIndex));
    }
    prefix.add(declinedNoun);
    final suffix = words.sublist(nounIndex + 1);
    return [...prefix, ...suffix].join(' ');
  }

  /// Akuzatív pre frázy typu „dal som ti čierne šortky / bordové tričko / čiernu
  /// bundu“. Pri strednom rode, mužskom neživotnom a množnom čísle je akuzatív
  /// rovný nominatívu (vstupný názov), mení sa len ženský rod jednotného čísla
  /// (bunda → bundu, čierna → čiernu).
  static String accusative(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return trimmed;

    final words =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return trimmed;

    final nounIndex = _findGarmentNounIndex(words);
    if (nounIndex <= 0) return _lowerFirst(trimmed);

    final noun = words[nounIndex];
    final lowerNoun = noun.toLowerCase();
    final feminineSingular =
        !_isPluralGarment(noun) && lowerNoun.endsWith('a');
    if (!feminineSingular) {
      // Akuzatív = nominatív (vstupný názov), len malé prvé písmeno.
      return _lowerFirst(trimmed);
    }

    final declinedAdj = _accusativeFeminineAdjective(words.first);
    final declinedNoun = '${noun.substring(0, noun.length - 1)}u';
    final prefix = <String>[declinedAdj];
    if (nounIndex > 1) {
      prefix.addAll(words.sublist(1, nounIndex));
    }
    prefix.add(declinedNoun);
    final suffix = words.sublist(nounIndex + 1);
    return _lowerFirst([...prefix, ...suffix].join(' '));
  }

  /// Správna podoba predložky „s/so“ pred inštrumentálom podľa začiatočného
  /// písmena nasledujúceho slova (so sivými, so striebornými, s čiernymi).
  static String sSo(String followingWord) {
    final w = _stripDiacritics(followingWord.trim().toLowerCase());
    if (w.isEmpty) return 's';
    final first = w[0];
    if (first == 's' || first == 'z') return 'so';
    return 's';
  }

  static String _accusativeFeminineAdjective(String adjective) {
    // Pri ženskom rode jednotného čísla: -a → -u, -á → -ú.
    if (adjective.endsWith('á')) {
      return '${adjective.substring(0, adjective.length - 1)}ú';
    }
    if (adjective.endsWith('a')) {
      return '${adjective.substring(0, adjective.length - 1)}u';
    }
    return adjective;
  }

  static String _lowerFirst(String input) {
    if (input.isEmpty) return input;
    return input[0].toLowerCase() + input.substring(1);
  }

  static String joinWithA(List<String> phrases) {
    final cleaned = phrases.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (cleaned.isEmpty) return '';
    if (cleaned.length == 1) return cleaned.first;
    if (cleaned.length == 2) return '${cleaned[0]} a ${cleaned[1]}';
    return '${cleaned.sublist(0, cleaned.length - 1).join(', ')} a ${cleaned.last}';
  }

  static int _findGarmentNounIndex(List<String> words) {
    for (var i = 1; i < words.length; i++) {
      final bare = _stripDiacritics(words[i].toLowerCase());
      for (final garment in _garmentWords) {
        if (bare == _stripDiacritics(garment)) return i;
      }
      if (_looksLikeGarmentNoun(words[i])) return i;
    }
    return -1;
  }

  static bool _looksLikeGarmentNoun(String word) {
    final lower = word.toLowerCase();
    return lower.endsWith('ky') ||
        lower.endsWith('ice') ||
        lower.endsWith('o') ||
        lower.endsWith('a') ||
        lower.endsWith('y');
  }

  static bool _isPluralGarment(String noun) {
    final lower = noun.toLowerCase();
    return lower.endsWith('ky') ||
        lower.endsWith('ice') ||
        lower.endsWith('y') && !lower.endsWith('ko');
  }

  static String? _declineAdjective(String adjective, {required bool plural}) {
    final lower = adjective.toLowerCase();
    for (final entry in _colorInstrumental.entries) {
      if (lower.startsWith(entry.key) ||
          _stripDiacritics(lower).startsWith(entry.key)) {
        return entry.value[plural ? 1 : 0];
      }
    }
    return null;
  }

  static String _declineNoun(String noun) {
    final lower = noun.toLowerCase();
    if (lower.endsWith('ice')) {
      return '${noun.substring(0, noun.length - 1)}ami';
    }
    if (lower == 'rifle') {
      return 'rifľami';
    }
    if (lower.endsWith('ky')) {
      return '${noun.substring(0, noun.length - 1)}ami';
    }
    if (lower.endsWith('y') && !lower.endsWith('ky')) {
      return '${noun.substring(0, noun.length - 1)}ami';
    }
    if (lower.endsWith('o')) {
      return '${noun.substring(0, noun.length - 1)}om';
    }
    if (lower.endsWith('a')) {
      return '${noun.substring(0, noun.length - 1)}ou';
    }
    if (lower.endsWith('t')) {
      return '${noun}om';
    }
    return noun;
  }

  static String _stripDiacritics(String input) {
    return input
        .replaceAll('á', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('č', 'c')
        .replaceAll('ď', 'd')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ĺ', 'l')
        .replaceAll('ľ', 'l')
        .replaceAll('ň', 'n')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ŕ', 'r')
        .replaceAll('š', 's')
        .replaceAll('ť', 't')
        .replaceAll('ú', 'u')
        .replaceAll('ý', 'y')
        .replaceAll('ž', 'z');
  }
}
