/// Z konverzácie vyčíta dátum udalosti: relatívne výrazy (dnes / zajtra /
/// pozajtra), slovenské názvy dní v týždni a bežné explicitné kalendárne
/// formáty. Konkrétne dátumy nie sú whitelistované — parser pracuje iba so
/// všeobecnou syntaxou dátumu a kalendárnou validáciou.
class StylistDayParser {
  const StylistDayParser._();

  /// Mapuje stem (bez diakritiky) → číslo dňa podľa [DateTime.weekday]
  /// (pondelok = 1 … nedeľa = 7). Ide o lokalizačnú gramatiku, nie zoznam
  /// udalostí alebo pomenovaných entít.
  static const Map<String, int> _weekdayWords = {
    'pondelok': DateTime.monday,
    'pondelka': DateTime.monday,
    'pondelky': DateTime.monday,
    'utorok': DateTime.tuesday,
    'utorka': DateTime.tuesday,
    'streda': DateTime.wednesday,
    'stredu': DateTime.wednesday,
    'stredou': DateTime.wednesday,
    'stvrtok': DateTime.thursday,
    'stvrtka': DateTime.thursday,
    'piatok': DateTime.friday,
    'piatka': DateTime.friday,
    'sobota': DateTime.saturday,
    'soboty': DateTime.saturday,
    'sobotu': DateTime.saturday,
    'sobotou': DateTime.saturday,
    'nedela': DateTime.sunday,
    'nedelu': DateTime.sunday,
    'nedelou': DateTime.sunday,
  };

  /// Vráti konkrétny dátum udalosti alebo `null`, ak v texte nie je žiadny
  /// platný explicitný časový údaj. Najneskôr vyslovený časový fakt vyhráva,
  /// takže prirodzená oprava typu „nie zajtra, ale 12.12.“ prepíše starší údaj.
  static DateTime? resolveDate(String conversation, {DateTime? now}) {
    final base = now ?? DateTime.now();
    final today = DateTime(base.year, base.month, base.day);
    final blob = _fold(conversation.toLowerCase());
    DateTime? resolved;
    var resolvedAt = -1;

    void considerAt(int at, DateTime? date) {
      if (date == null || at < resolvedAt) return;
      resolvedAt = at;
      resolved = date;
    }

    void considerWord(String word, DateTime date) {
      final matches = RegExp('\\b${RegExp.escape(word)}\\b').allMatches(blob);
      if (matches.isEmpty) return;
      considerAt(matches.last.start, date);
    }

    // Explicit ISO date: 2026-12-12. Word/digit guards prevent accidentally
    // parsing a longer identifier or a timestamp fragment as another date.
    final iso = RegExp(r'(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)');
    for (final match in iso.allMatches(blob)) {
      final year = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);
      final day = int.tryParse(match.group(3)!);
      considerAt(match.start, _validDate(year, month, day));
    }

    // Slovak/European numeric forms: 12.12., 12.12.2026, 12/12, 12/12/2026.
    // A missing year means the next occurrence of that calendar day: this year
    // if it is today/future, otherwise next year. That makes a future-planning
    // chat useful without hardcoding the current year.
    final european = RegExp(
      r'(?<!\d)(\d{1,2})\s*([./])\s*(\d{1,2})(?:\s*\2\s*(\d{4}))?\s*\.?\s*(?!\d)',
    );
    for (final match in european.allMatches(blob)) {
      final day = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(3)!);
      final explicitYear = int.tryParse(match.group(4) ?? '');
      final date = explicitYear != null
          ? _validDate(explicitYear, month, day)
          : _nextOccurrence(month: month, day: day, today: today);
      considerAt(match.start, date);
    }

    // The latest explicit temporal fact wins. This is important for natural
    // corrections such as "nie zajtra, až v sobotu".
    considerWord('pozajtra', today.add(const Duration(days: 2)));
    considerWord('zajtra', today.add(const Duration(days: 1)));
    considerWord('tomorrow', today.add(const Duration(days: 1)));
    considerWord('dnes', today);
    considerWord('dneska', today);
    considerWord('today', today);
    for (final entry in _weekdayWords.entries) {
      var diff = (entry.value - today.weekday) % 7;
      if (diff < 0) diff += 7;
      considerWord(entry.key, today.add(Duration(days: diff)));
    }
    return resolved;
  }

  static DateTime? _nextOccurrence({
    required int? month,
    required int? day,
    required DateTime today,
  }) {
    var candidate = _validDate(today.year, month, day);
    if (candidate == null) return null;
    if (candidate.isBefore(today)) {
      candidate = _validDate(today.year + 1, month, day);
    }
    return candidate;
  }

  /// DateTime v Dart-e normalizuje napr. 31.2. na marec. Round-trip kontrola
  /// preto zabezpečí, že neexistujúci dátum nie je prijatý ako iný deň.
  static DateTime? _validDate(int? year, int? month, int? day) {
    if (year == null || month == null || day == null) return null;
    if (year < 1900 || year > 2200 || month < 1 || month > 12 || day < 1) {
      return null;
    }
    final candidate = DateTime(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      return null;
    }
    return candidate;
  }

  static String _fold(String input) {
    const map = {
      'á': 'a', 'ä': 'a', 'č': 'c', 'ď': 'd', 'é': 'e', 'ě': 'e', 'í': 'i',
      'ĺ': 'l', 'ľ': 'l', 'ň': 'n', 'ó': 'o', 'ô': 'o', 'ŕ': 'r', 'š': 's',
      'ť': 't', 'ú': 'u', 'ů': 'u', 'ý': 'y', 'ž': 'z',
    };
    final sb = StringBuffer();
    for (final ch in input.split('')) {
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }

  /// Slovenský názov dňa v tvare pre frázu „v …“ (napr. „v stredu“).
  static String? inDayPhrase(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'v pondelok';
      case DateTime.tuesday:
        return 'v utorok';
      case DateTime.wednesday:
        return 'v stredu';
      case DateTime.thursday:
        return 'vo štvrtok';
      case DateTime.friday:
        return 'v piatok';
      case DateTime.saturday:
        return 'v sobotu';
      case DateTime.sunday:
        return 'v nedeľu';
    }
    return null;
  }
}
