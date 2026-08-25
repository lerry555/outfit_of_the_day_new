/// Keď geokóder nenájde mesto (typicky preklep), skúsime ponúknuť najbližšie
/// známe mesto, aby sa appka vedela spýtať „Myslíš Norimberg?“ namiesto
/// všeobecného „netuším, kde to je“.
class StylistCitySuggester {
  const StylistCitySuggester._();

  /// Bežné cieľové mestá (slovenské + zaužívané exonymá), na ktoré sa dá
  /// trafiť preklepom. Hodnota je kanonický tvar, ktorý ponúkneme používateľovi.
  static const List<String> _knownCities = [
    // Slovensko
    'Bratislava', 'Košice', 'Žilina', 'Martin', 'Prešov', 'Nitra', 'Trnava',
    'Trenčín', 'Poprad', 'Banská Bystrica', 'Piešťany', 'Liptovský Mikuláš',
    'Ružomberok', 'Zvolen', 'Michalovce', 'Komárno', 'Spišská Nová Ves',
    'Levice', 'Považská Bystrica', 'Humenné', 'Bardejov', 'Dolný Kubín',
    // Česko
    'Praha', 'Brno', 'Ostrava', 'Plzeň', 'Olomouc', 'Liberec',
    // Nemecko / Rakúsko
    'Viedeň', 'Mníchov', 'Norimberg', 'Berlín', 'Frankfurt', 'Hamburg',
    'Drážďany', 'Kolín nad Rýnom', 'Stuttgart', 'Salzburg', 'Linz', 'Graz',
    // Poľsko / Maďarsko
    'Krakov', 'Varšava', 'Vroclav', 'Katovice', 'Budapešť', 'Debrecín',
    // Ostatná Európa
    'Londýn', 'Dublin', 'Paríž', 'Rím', 'Miláno', 'Benátky', 'Florencia',
    'Barcelona', 'Madrid', 'Amsterdam', 'Brusel', 'Kodaň', 'Štokholm',
    'Zürich', 'Ženeva', 'Lisabon', 'Atény', 'Záhreb', 'Ľubľana',
  ];

  /// Vráti kanonický názov najbližšieho známeho mesta, ak je dosť blízko na to,
  /// aby šlo zrejme o preklep. Inak `null`.
  static String? suggestCorrection(String input) {
    final cleaned = _normalize(input);
    if (cleaned.length < 4) return null;

    String? best;
    var bestDistance = 1 << 30;
    for (final city in _knownCities) {
      final cand = _normalize(city);
      if (cand == cleaned) {
        // Presná zhoda po normalizácii – mesto poznáme, netreba sa pýtať.
        return null;
      }
      final dist = _levenshtein(cleaned, cand);
      if (dist < bestDistance) {
        bestDistance = dist;
        best = city;
      }
    }
    if (best == null) return null;

    // Tolerancia podľa dĺžky – pri dlhších názvoch dovolíme viac preklepov,
    // ale nikdy nie viac ako 2 (inak by sme hádali nezmysly).
    final maxAllowed = cleaned.length >= 7 ? 2 : 1;
    if (bestDistance <= maxAllowed) return best;
    return null;
  }

  /// Malé písmená, bez diakritiky a bez častej slovenskej lokálovej koncovky
  /// („Norinbergu“ → „norinberg“, „Mníchove“ → „mnichov“), aby sa preklep
  /// porovnal so základným tvarom mesta.
  static const Set<String> _trailingStopWords = {
    'po', 'meste', 'mestom', 'mesta', 'okolo', 'pri', 'cez', 'centre',
    'centra', 'ulici', 'rano', 'vecer', 'poobede', 'po meste', 'do',
  };

  static String _normalize(String input) {
    var s = _fold(input.toLowerCase().trim());
    s = s.split(',').first.trim();
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();
    // Odstráň koncové „výplňové“ slová (napr. „mnuchove po“ → „mnuchove“).
    var words = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    while (words.length > 1 && _trailingStopWords.contains(words.last)) {
      words = words.sublist(0, words.length - 1);
    }
    // Lokálovú koncovku skloňujeme len na poslednom slove (kvôli názvom ako
    // „banska bystrica“), zvyšok necháme.
    if (words.isNotEmpty) {
      words[words.length - 1] = _stripLocativeSuffix(words.last);
    }
    return words.join(' ');
  }

  static String _stripLocativeSuffix(String word) {
    if (word.length <= 4) return word;
    for (final suffix in const ['ovi', 'och', 'ami', 'ach', 'om', 'ou', 'e', 'u', 'i', 'y', 'a']) {
      if (word.length - suffix.length >= 3 && word.endsWith(suffix)) {
        return word.substring(0, word.length - suffix.length);
      }
    }
    return word;
  }

  static String _fold(String input) {
    const map = {
      'á': 'a', 'ä': 'a', 'č': 'c', 'ď': 'd', 'é': 'e', 'ě': 'e', 'í': 'i',
      'ĺ': 'l', 'ľ': 'l', 'ň': 'n', 'ó': 'o', 'ô': 'o', 'ŕ': 'r', 'š': 's',
      'ť': 't', 'ú': 'u', 'ů': 'u', 'ý': 'y', 'ž': 'z', 'ü': 'u', 'ö': 'o',
      'ß': 's',
    };
    final sb = StringBuffer();
    for (final ch in input.split('')) {
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      curr[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        final del = prev[j + 1] + 1;
        final ins = curr[j] + 1;
        final sub = prev[j] + cost;
        curr[j + 1] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      for (var j = 0; j <= b.length; j++) {
        prev[j] = curr[j];
      }
    }
    return prev[b.length];
  }
}
