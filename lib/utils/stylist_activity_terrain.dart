/// Typ povrchu / aktivity — ovplyvňuje, či má zmysel spomínať minulý dážď
/// (mokrá tráva/hlina) alebo len aktuálne a budúce počasie (mestská prechádzka).
enum StylistActivityTerrain {
  /// Hory, lúka, les, trail — minulý dážď môže znamenať mokro pod nohami.
  wetGround,

  /// Mesto, chodník, centrum — minulý dážď pred hodinami nie je relevantný.
  urban,
}

class StylistActivityTerrainClassifier {
  const StylistActivityTerrainClassifier._();

  static const List<String> _wetGroundHints = [
    'hory',
    'horach',
    'horou',
    'horu',
    'hore',
    'horami',
    'do hory',
    'v horach',
    'na horach',
    'turist',
    'trail',
    'trava',
    'trave',
    'travou',
    'luka',
    'luk',
    'lukach',
    'lukou',
    'po luke',
    'po trave',
    'les',
    'lese',
    'lesom',
    'priroda',
    'prirode',
    'prirodu',
    'kopce',
    'kopcoch',
    'blato',
    'hline',
    'hlin',
    'huby',
    'hub',
    'hrib',
  ];

  static const List<String> _urbanHints = [
    'meste',
    'mesto',
    'mestom',
    'centre',
    'centra',
    'centrum',
    'chodnik',
    'chodniku',
    'namesti',
    'namestie',
    'ulici',
    'ulicou',
    'ulic',
    'beton',
    'chodnik',
  ];

  /// Rozpozná typ aktivity z konverzácie a príležitosti.
  /// Default: [urban] — všeobecná prechádzka = chodník, minulý dážď nespomíname.
  static StylistActivityTerrain classify({
    String? conversationText,
    String? occasion,
  }) {
    final blob = _norm('${conversationText ?? ''} ${occasion ?? ''}');
    if (blob.isEmpty) return StylistActivityTerrain.urban;

    if (_containsAny(blob, _wetGroundHints)) {
      return StylistActivityTerrain.wetGround;
    }
    if (_containsAny(blob, _urbanHints)) {
      return StylistActivityTerrain.urban;
    }
    // „prechádzka“ bez hôr/prírody = mestský chodník.
    if (blob.contains('prechadz') || blob.contains('prechádz')) {
      return StylistActivityTerrain.urban;
    }
    return StylistActivityTerrain.urban;
  }

  static bool _containsAny(String haystack, List<String> needles) {
    return needles.any(haystack.contains);
  }

  static String _norm(String input) {
    return input
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('č', 'c')
        .replaceAll('ď', 'd')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ľ', 'l')
        .replaceAll('ĺ', 'l')
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
