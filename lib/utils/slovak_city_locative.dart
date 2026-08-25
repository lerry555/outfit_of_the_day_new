/// Krátke skloňovanie miest do lokálu pre frázy typu „v Martine“.
class SlovakCityLocative {
  const SlovakCityLocative._();

  static const Map<String, String> _known = {
    'martin': 'Martine',
    'žilina': 'Žiline',
    'zilina': 'Žiline',
    'bratislava': 'Bratislave',
    'košice': 'Košiciach',
    'kosice': 'Košiciach',
    'prešov': 'Prešove',
    'presov': 'Prešove',
    'nitra': 'Nitre',
    'trnava': 'Trnave',
    'banská bystrica': 'Banskej Bystrici',
    'banska bystrica': 'Banskej Bystrici',
    'poprad': 'Poprade',
    'trenčín': 'Trenčíne',
    'trencin': 'Trenčíne',
    'london': 'Londýne',
    'dublin': 'Dubline',
    'galway': 'Galway',
  };

  /// „v Martine“, „v Žiline“…
  static String inCity(String cityShort) {
    final trimmed = cityShort.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    final loc = _known[lower] ?? trimmed;
    return 'v $loc';
  }

  /// „pri Martine“, „pri Žiline“… (lokál okolia mesta).
  static String nearCity(String cityShort) {
    final trimmed = cityShort.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.split(',').first.trim().toLowerCase();
    final loc = _known[lower] ?? trimmed.split(',').first.trim();
    return 'pri $loc';
  }

  /// Opraví bežné chyby AI („v Martin“ → „v Martine“, „pri Martin“ → „pri Martine“).
  static String fixCityDeclensionInText(String text) {
    var out = text;
    for (final entry in _known.entries) {
      final nominative = entry.key;
      final locative = entry.value;
      for (final prep in ['v', 'vo', 'pri', 'na']) {
        out = out.replaceAll(
          RegExp(
            '${RegExp.escape(prep)}\\s+${RegExp.escape(nominative)}\\b',
            caseSensitive: false,
          ),
          '$prep $locative',
        );
        out = out.replaceAll(
          RegExp(
            '${RegExp.escape(prep)}\\s+${RegExp.escape(_capitalize(nominative))}\\b',
          ),
          '$prep $locative',
        );
      }
    }
    return out;
  }

  @Deprecated('Use fixCityDeclensionInText')
  static String fixNearCityInText(String text) => fixCityDeclensionInText(text);

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
