class OutfitReasonBuilder {
  static String build({
    required int tempC,
    required bool isRainy,
    required bool isWindy,
    required List<Map<String, dynamic>> selectedItems,
    required bool hasOuterwear,
    String? seasonLabel,
  }) {
    final normalizedItems = selectedItems.map(_normalizeItem).toList();

    final topItem = _findByType(normalizedItems, const ['top']);
    final bottomItem = _findByType(normalizedItems, const ['bottom']);
    final shoesItem = _findByType(normalizedItems, const ['shoes']);
    final outerItem = _findByType(normalizedItems, const ['outerwear']);

    final isWarm = tempC >= 20;
    final isMild = tempC >= 10 && tempC < 20;
    final isCold = tempC < 10;

    String describeTemperatureFeel() {
      final morning = isCold
          ? 'Ráno bude citeľne chladnejšie'
          : isMild
          ? 'Ráno bude príjemne svieže'
          : 'Ráno bude skôr komfortné';

      final later = isCold
          ? 'a cez deň sa to aspoň trochu uvoľní a oteplí'
          : isWarm
          ? 'a neskôr sa z toho stane ľahší, teplejší deň'
          : 'a popoludní sa to zvyčajne zjemní a bude príjemnejšie';

      final windy = isWindy
          ? ' Vietor spraví pocit chladu ostrejší, takže dáva zmysel outfit, ktorý zostane príjemný aj pri pohybe vonku.'
          : '';

      final rainy = isRainy
          ? ' Keď sa pridá dážď, povrch aj vzduch pôsobia chladnejšie, preto je fajn mať kombináciu, ktorá ostane praktická počas celého dňa.'
          : '';

      return '$morning, $later.$windy$rainy'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    String describeLayeringNeed() {
      if (hasOuterwear) {
        if (isRainy) {
          return 'Vrchnú vrstvu som zaradil hlavne kvôli dažďu a vetru. Outfit tak pôsobí kompletnejšie a zároveň je praktickejší, keď sa počasie počas dňa zhorší.';
        }
        return 'Vrchná vrstva tu dáva zmysel hlavne kvôli chladnejšiemu ránu a večeru. Cez deň ju môžeš pokojne nechať rozopnutú alebo odložiť, ale outfit bude stále držať peknú líniu.';
      }

      if (isWarm) {
        return 'Pri teplejšom počasí som to držal ľahšie a bez zbytočne ťažkého vrstvenia, aby outfit pôsobil uvoľnene a pohodlne.';
      }

      return 'Tu som sa nesnažil vrstviť nasilu. Radšej držím jednoduchší základ, ktorý je pohodlný, čistý a prirodzený na bežný deň.';
    }

    String describeColorHarmony() {
      final allColors = <String>[];
      for (final item in normalizedItems) {
        allColors.addAll(_colorsOf(item));
      }

      final fam = _colorFamilies(allColors);
      final neutralFamilies = {'black', 'white', 'gray', 'beige', 'navy'};
      final hasNeutralSet = fam.any(neutralFamilies.contains);

      String neutralPhrase() {
        final names = <String>[];
        if (fam.contains('black')) names.add('čierna');
        if (fam.contains('white')) names.add('biela');
        if (fam.contains('gray')) names.add('sivá');
        if (fam.contains('beige')) names.add('béžová');
        if (fam.contains('navy')) names.add('tmavomodrá');
        if (names.isEmpty) return 'neutrálne tóny';
        return names.join(', ');
      }

      if (hasNeutralSet) {
        return 'Farebne to drží pokope neutrálna paleta (${neutralPhrase()}). Vďaka tomu top, spodok aj obuv spolu nepôsobia rozhádzane, ale zladene a čisto.';
      }

      return 'Farebne som to držal súvislé, aby outfit pôsobil harmonicky a neťahal každým smerom inam.';
    }

    String describeStyleVibe() {
      final topBlob = _blob(topItem);
      final bottomBlob = _blob(bottomItem);
      final shoesBlob = _blob(shoesItem);
      final outerBlob = _blob(outerItem);

      if (outerBlob.contains('sako') || outerBlob.contains('blazer')) {
        return 'Celé to má mestský, upravený vibe, ale stále zostáva dosť pohodlné na normálne fungovanie počas dňa.';
      }

      if (topBlob.contains('hoodie') ||
          topBlob.contains('mikina') ||
          topBlob.contains('sweater') ||
          topBlob.contains('sveter')) {
        return 'Vibe je skôr pohodlný a prirodzený, niečo medzi casual a street štýlom, takže outfit vyzerá dobre bez toho, aby pôsobil nasilu.';
      }

      if (bottomBlob.contains('jeans') ||
          bottomBlob.contains('rifl') ||
          bottomBlob.contains('dzin') ||
          bottomBlob.contains('džín')) {
        return 'Je to čistý každodenný outfit, ktorý pôsobí uvoľnene, ale stále upravene a zladene.';
      }

      if (shoesBlob.contains('tenis') ||
          shoesBlob.contains('sneaker') ||
          shoesBlob.contains('shoes')) {
        return 'Celé to pôsobí moderne, nositeľne a prirodzene, takže si vieš outfit zobrať na bežný deň bez rozmýšľania navyše.';
      }

      return 'Celkový dojem je vyvážený, pohodlný a prirodzený, takže outfit funguje prakticky aj vizuálne.';
    }

    String describeSilhouette() {
      final hasTop = topItem.isNotEmpty;
      final hasBottom = bottomItem.isNotEmpty;
      final hasShoes = shoesItem.isNotEmpty;

      if (hasTop && hasBottom && hasShoes) {
        return hasOuterwear
            ? 'Top, spodok a obuv spolu držia jednu líniu a vrchná vrstva to celé pekne rámuje, takže outfit pôsobí hotovo a dospelo.'
            : 'Top, spodok aj obuv spolu držia jednu líniu, takže outfit nepôsobí rozbito, ale čisto a premyslene.';
      }

      return 'Jednotlivé kúsky spolu vizuálne fungujú tak, aby outfit pôsobil kompaktne a príjemne na nosenie.';
    }

    final parts = <String>[
      describeTemperatureFeel(),
      describeLayeringNeed(),
      describeSilhouette(),
      describeColorHarmony(),
      describeStyleVibe(),
    ];

    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Map<String, dynamic> _normalizeItem(Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);

    map['name'] = (map['name'] ?? map['label'] ?? '').toString();
    map['category'] =
        (map['categoryKey'] ?? map['category'] ?? '').toString();
    map['subCategory'] =
        (map['subCategoryKey'] ?? map['subCategory'] ?? '').toString();
    map['mainGroup'] =
        (map['mainGroupKey'] ?? map['mainGroup'] ?? '').toString();

    final typeKey = (map['typeKey'] ?? map['type'] ?? '').toString().trim();
    map['typeKey'] = typeKey;

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
      if (c.contains('červen') || c.contains('red')) {
        fam.add('red');
      }
      if (c.contains('zelen') || c.contains('green')) {
        fam.add('green');
      }
      if (c.contains('modr') || c.contains('blue')) {
        fam.add('blue');
      }
      if (c.contains('oranž') || c.contains('orange')) {
        fam.add('orange');
      }
      if (c.contains('žlt') || c.contains('yellow')) {
        fam.add('yellow');
      }
      if (c.contains('fial') || c.contains('purple')) {
        fam.add('purple');
      }
    }
    return fam;
  }
}