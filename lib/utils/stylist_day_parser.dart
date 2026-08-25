/// Z konverzácie vyčíta deň udalosti: relatívne výrazy (dnes / zajtra /
/// pozajtra) aj slovenské názvy dní v týždni vrátane skloňovaných tvarov
/// („v stredu“, „vo štvrtok“, „cez víkend“…). Vracia konkrétny dátum, alebo
/// `null`, keď používateľ deň explicitne nespomenul.
class StylistDayParser {
  const StylistDayParser._();

  /// Mapuje stem (bez diakritiky) → číslo dňa podľa [DateTime.weekday]
  /// (pondelok = 1 … nedeľa = 7). Uvádzame aj časté skloňované tvary.
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
    'sobotu': DateTime.saturday,
    'sobotou': DateTime.saturday,
    'nedela': DateTime.sunday,
    'nedelu': DateTime.sunday,
    'nedelou': DateTime.sunday,
  };

  /// Vráti dátum udalosti alebo `null`, ak v texte nie je žiadny explicitný deň.
  static DateTime? resolveDate(String conversation, {DateTime? now}) {
    final base = now ?? DateTime.now();
    final today = DateTime(base.year, base.month, base.day);
    final blob = _fold(conversation.toLowerCase());

    // Relatívne výrazy – od najkonkrétnejšieho.
    if (_hasWord(blob, 'pozajtra')) {
      return today.add(const Duration(days: 2));
    }
    if (_hasWord(blob, 'zajtra') || _hasWord(blob, 'tomorrow')) {
      return today.add(const Duration(days: 1));
    }
    if (_hasWord(blob, 'dnes') ||
        _hasWord(blob, 'dneska') ||
        _hasWord(blob, 'today')) {
      return today;
    }

    final weekday = _weekdayFromText(blob);
    if (weekday != null) {
      var diff = (weekday - today.weekday) % 7;
      if (diff < 0) diff += 7;
      // „v stredu“, keď je práve streda, bežne znamená dnes (diff 0).
      return today.add(Duration(days: diff));
    }
    return null;
  }

  static int? _weekdayFromText(String foldedBlob) {
    for (final entry in _weekdayWords.entries) {
      if (_hasWord(foldedBlob, entry.key)) return entry.value;
    }
    return null;
  }

  /// Hľadá celé slovo (so slovnými hranicami), aby „stredu“ nepadlo na
  /// „prostredie“ či „streda“ na „stredisko“.
  static bool _hasWord(String text, String word) {
    return RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(text);
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
