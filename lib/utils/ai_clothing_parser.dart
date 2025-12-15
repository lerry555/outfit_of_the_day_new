// lib/utils/ai_clothing_parser.dart

class AiParserInput {
  final String rawType;
  final String aiName;
  final String userName;
  final List<String> seasons;
  final String brand;

  /// NOVÉ (voliteľné): backend môže poslať canonical_type (napr. mikina_s_kapucnou)
  final String? canonicalType;

  AiParserInput({
    required this.rawType,
    required this.aiName,
    required this.userName,
    required this.seasons,
    required this.brand,
    this.canonicalType,
  });
}

class AiParserResult {
  final String mainGroupKey;
  final String categoryKey;
  final String subCategoryKey;

  AiParserResult({
    required this.mainGroupKey,
    required this.categoryKey,
    required this.subCategoryKey,
  });
}

class AiClothingParser {
  /// (do budúcna) – mapovanie, ak by backend posielal canonical_type
  static AiParserResult? fromCanonicalType(String canonicalType) {
    final ct = canonicalType.trim().toLowerCase();

    switch (ct) {
    // TRIČKÁ
      case 'tricko_kratky_rukav':
      case 'tricko':
      case 'tshirt':
      case 't-shirt':
      case 'tee':
        return AiParserResult(
          mainGroupKey: 'oblecenie',
          categoryKey: 'tricka_topy',
          subCategoryKey: 'tricko_kratky_rukav',
        );

      case 'tricko_dlhy_rukav':
      case 'tricko_long_sleeve':
      case 'longsleeve':
        return AiParserResult(
          mainGroupKey: 'oblecenie',
          categoryKey: 'tricka_topy',
          subCategoryKey: 'tricko_dlhy_rukav',
        );

    // MIKINY
      case 'mikina_klasicka':
      case 'mikina_bez_kapucne':
      case 'sweatshirt':
        return AiParserResult(
          mainGroupKey: 'oblecenie',
          categoryKey: 'mikiny',
          subCategoryKey: 'mikina_klasicka',
        );

      case 'mikina_s_kapucnou':
      case 'hoodie':
      case 'mikina_hoodie':
        return AiParserResult(
          mainGroupKey: 'oblecenie',
          categoryKey: 'mikiny',
          subCategoryKey: 'mikina_s_kapucnou',
        );

    // BUNDY
      case 'bunda_prechodna':
      case 'prechodna_bunda':
        return AiParserResult(
          mainGroupKey: 'oblecenie',
          categoryKey: 'bundy_kabaty',
          subCategoryKey: 'bunda_prechodna',
        );

      case 'bunda_zimna':
      case 'zimna_bunda':
      case 'puffer':
      case 'parka':
        return AiParserResult(
          mainGroupKey: 'oblecenie',
          categoryKey: 'bundy_kabaty',
          subCategoryKey: 'bunda_zimna',
        );

    // OBUV (zimná)
      case 'zimne_topanky':
      case 'winter_boots':
      case 'snow_boots':
        return AiParserResult(
          mainGroupKey: 'obuv',
          categoryKey: 'cizmy',
          subCategoryKey: 'cizmy_vysoke',
        );
    }
    return null;
  }

  /// ✅ NOVÉ: bezpečná wrapper funkcia
  /// - Ak príde canonicalType a vieme ho mapnúť → použijeme ho (priorita).
  /// - Inak pokračujeme tvojím pôvodným heuristickým mapovaním mapType().
  static AiParserResult? mapTypePreferCanonical(AiParserInput input) {
    final ct = input.canonicalType?.trim();
    if (ct != null && ct.isNotEmpty) {
      final mapped = fromCanonicalType(ct);
      if (mapped != null) return mapped;
    }
    return mapType(input);
  }

  /// Heuristické mapovanie podľa textu z AI (type + názov + značka + sezóny)
  /// ⚠️ Nechávam 1:1 tvoju pôvodnú logiku (bez zmien).
  static AiParserResult? mapType(AiParserInput input) {
    final buffer = StringBuffer();
    if (input.rawType.isNotEmpty) buffer.write('${input.rawType} ');
    if (input.aiName.isNotEmpty) buffer.write('${input.aiName} ');
    if (input.userName.isNotEmpty) buffer.write('${input.userName} ');
    if (input.brand.isNotEmpty) buffer.write('${input.brand} ');

    final text = buffer.toString().toLowerCase().trim();
    if (text.isEmpty) return null;

    bool has(String s) => text.contains(s);
    bool hasAny(List<String> list) => list.any((s) => text.contains(s));

    final lowerSeasons = input.seasons.map((s) => s.toLowerCase()).toList();
    bool hasSeason(String s) => lowerSeasons.contains(s);

    final bool hasWinter = hasSeason('zima');
    final bool hasSpring = hasSeason('jar');
    final bool hasAutumn =
        lowerSeasons.contains('jeseň') || lowerSeasons.contains('jesen');

    // 1) Zimná obuv / čižmy
    if (hasAny(['zimná obuv', 'zimna obuv', 'snow boots', 'winter boots']) ||
        (hasAny(['čižmy', 'cizmy', 'boots', 'boot']) && hasWinter)) {
      return AiParserResult(
        mainGroupKey: 'obuv',
        categoryKey: 'cizmy',
        subCategoryKey: 'cizmy_vysoke',
      );
    }

    // 2) Bundy & kabáty
    if (hasAny(['bunda', 'jacket', 'coat', 'parka', 'puffer'])) {
      // hrubá zimná bunda
      if (hasWinter && !hasSpring && !hasAutumn) {
        return AiParserResult(
          mainGroupKey: 'oblecenie',
          categoryKey: 'bundy_kabaty',
          subCategoryKey: 'bunda_zimna',
        );
      }
      // default prechodná
      return AiParserResult(
        mainGroupKey: 'oblecenie',
        categoryKey: 'bundy_kabaty',
        subCategoryKey: 'bunda_prechodna',
      );
    }

    // 3) Mikiny
    if (hasAny(['mikina', 'sweatshirt', 'hoodie'])) {
      // mikina s kapucňou (hood / kapucňa / klub)
      if (hasAny(['kapuc', 'hood', 'chelsea', 'fc'])) {
        return AiParserResult(
          mainGroupKey: 'oblecenie',
          categoryKey: 'mikiny',
          subCategoryKey: 'mikina_s_kapucnou',
        );
      }
      return AiParserResult(
        mainGroupKey: 'oblecenie',
        categoryKey: 'mikiny',
        subCategoryKey: 'mikina_klasicka',
      );
    }

    // 4) Tričká
    if (hasAny(['tričko', 'tricko', 't-shirt', 'tshirt', 'tee'])) {
      // dlhý rukáv
      if (hasAny(
          ['dlhý rukáv', 'dlhy rukav', 'longsleeve', 'long sleeve'])) {
        return AiParserResult(
          mainGroupKey: 'oblecenie',
          categoryKey: 'tricka_topy',
          subCategoryKey: 'tricko_dlhy_rukav',
        );
      }
      // krátky rukáv ako default
      return AiParserResult(
        mainGroupKey: 'oblecenie',
        categoryKey: 'tricka_topy',
        subCategoryKey: 'tricko_kratky_rukav',
      );
    }

    return null;
  }
}
