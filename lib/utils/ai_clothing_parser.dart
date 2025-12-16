// lib/utils/ai_clothing_parser.dart
import '../constants/app_constants.dart';

class AiParserInput {
  final String rawType;
  final String aiName;
  final String userName;
  final List<String> seasons;
  final String brand;

  AiParserInput({
    required this.rawType,
    required this.aiName,
    required this.userName,
    required this.seasons,
    required this.brand,
  });
}

class AiMappedCategory {
  final String mainGroupKey;
  final String categoryKey;
  final String subCategoryKey;

  AiMappedCategory({
    required this.mainGroupKey,
    required this.categoryKey,
    required this.subCategoryKey,
  });
}

class AiClothingParser {
  /// 1) Najlepšia cesta: canonical_type == subCategoryKey (napr. "rifle")
  /// Potom už len nájsť categoryKey + mainGroupKey podľa stromu v app_constants.dart
  static AiMappedCategory? fromCanonicalType(String canonicalType) {
    final subKey = canonicalType.trim();
    if (subKey.isEmpty) return null;

    // canonical_type musí byť jeden z našich subCategoryTree kľúčov
    final catKey = _findCategoryForSubKey(subKey);
    if (catKey == null) return null;

    final mainKey = _findMainGroupForCategory(catKey);
    if (mainKey == null) return null;

    return AiMappedCategory(
      mainGroupKey: mainKey,
      categoryKey: catKey,
      subCategoryKey: subKey,
    );
  }

  /// 2) Fallback: keď canonical_type chýba, mapujeme podľa textu
  static AiMappedCategory? mapType(AiParserInput input) {
    final combined = [
      input.rawType,
      input.aiName,
      input.userName,
      input.brand,
      input.seasons.join(' '),
    ].join(' ');

    final t = _norm(combined);

    // --- NOHAVICE / RIFLE ---
    if (_hasAny(t, ['rifle', 'jeans', 'dzins', 'dzin', 'denim'])) {
      return fromCanonicalType('rifle');
    }
    if (_hasAny(t, ['skinny'])) {
      return fromCanonicalType('rifle_skinny');
    }
    if (_hasAny(t, ['wide leg', 'wideleg', 'wide'])) {
      return fromCanonicalType('rifle_wide_leg');
    }
    if (_hasAny(t, ['mom jeans', 'mom'])) {
      return fromCanonicalType('rifle_mom');
    }
    if (_hasAny(t, ['chino'])) {
      return fromCanonicalType('nohavice_chino');
    }
    if (_hasAny(t, ['teplaky', 'tepláky', 'sweatpant', 'jogger', 'joggery'])) {
      // ak chceš striktne: teplaky = nohavice_teplakove, joggery = nohavice_joggery
      if (_hasAny(t, ['jogger', 'joggery'])) return fromCanonicalType('nohavice_joggery');
      return fromCanonicalType('nohavice_teplakove');
    }
    if (_hasAny(t, ['cargo'])) {
      return fromCanonicalType('nohavice_cargo');
    }
    if (_hasAny(t, ['elegant', 'oblek', 'formal'])) {
      return fromCanonicalType('nohavice_elegantne');
    }
    if (_hasAny(t, ['nohavice', 'pants', 'trousers'])) {
      // všeobecné nohavice – zvolíme elegantné vs teplákové vs chino sa rieši vyššie,
      // inak nechajme aspoň rifle alebo elegantné? ja dávam elegantné nie, radšej "rifle" nie.
      return fromCanonicalType('nohavice_elegantne');
    }

    // --- TRIČKÁ ---
    if (_hasAny(t, ['tricko', 'tri\u010dko', 't-shirt', 'tshirt'])) {
      if (_hasAny(t, ['dlhy rukav', 'dlh\u00fd ruk\u00e1v', 'long sleeve'])) {
        return fromCanonicalType('tricko_dlhy_rukav');
      }
      return fromCanonicalType('tricko');
    }
    if (_hasAny(t, ['tielko', 'tank'])) return fromCanonicalType('tielko');
    if (_hasAny(t, ['polo'])) return fromCanonicalType('polo_tricko');

    // --- MIKINY ---
    if (_hasAny(t, ['mikina', 'hoodie', 'sweatshirt'])) {
      if (_hasAny(t, ['kapuc', 'hood'])) return fromCanonicalType('mikina_s_kapucnou');
      if (_hasAny(t, ['zip', 'zips'])) return fromCanonicalType('mikina_na_zips');
      if (_hasAny(t, ['oversize'])) return fromCanonicalType('mikina_oversize');
      return fromCanonicalType('mikina_klasicka');
    }

    // --- BUNDY ---
    if (_hasAny(t, ['bunda', 'jacket', 'coat', 'kabat', 'kab\u00e1t'])) {
      if (_hasAny(t, ['riflova', 'rif\u013eov\u00e1', 'denim'])) return fromCanonicalType('bunda_riflova');
      if (_hasAny(t, ['kozena', 'ko\u017een\u00e1', 'leather'])) return fromCanonicalType('bunda_kozena');
      if (_hasAny(t, ['bomber'])) return fromCanonicalType('bunda_bomber');

      // zimná vs prechodná – dáme jednoduchý fallback, ale finálne to má riešiť prompt
      if (_hasAny(t, ['puffer', 'parka', 'zimna', 'zimn\u00e1'])) return fromCanonicalType('bunda_zimna');
      if (_hasAny(t, ['prechodna', 'prechodn\u00e1'])) return fromCanonicalType('bunda_prechodna');

      // keď nič, radšej prechodná než generic
      return fromCanonicalType('bunda_prechodna');
    }

    // --- OBUV ---
    if (_hasAny(t, ['tenisky', 'sneaker'])) return fromCanonicalType('tenisky_fashion');
    if (_hasAny(t, ['cizmy', 'či\u017emy', 'boots'])) return fromCanonicalType('cizmy_clenkove');
    if (_hasAny(t, ['sandale', 'sand\u00e1le'])) return fromCanonicalType('sandale');

    // --- DOPLNKY ---
    if (_hasAny(t, ['ciapka', 'čiapka', 'beanie', 'hat'])) return fromCanonicalType('ciapka');
    if (_hasAny(t, ['sal', '\u0161\u00e1l', 'scarf'])) return fromCanonicalType('sal');
    if (_hasAny(t, ['opasok', 'belt'])) return fromCanonicalType('opasok');

    return null;
  }

  // ----------------- helpers -----------------

  static String _norm(String s) {
    var out = s.toLowerCase().trim();
    out = out.replaceAll('\n', ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ');
    return out;
  }

  static bool _hasAny(String text, List<String> needles) {
    for (final n in needles) {
      if (text.contains(_norm(n))) return true;
    }
    return false;
  }

  static String? _findCategoryForSubKey(String subKey) {
    for (final entry in subCategoryTree.entries) {
      if (entry.value.contains(subKey)) {
        return entry.key; // categoryKey
      }
    }
    return null;
  }

  static String? _findMainGroupForCategory(String categoryKey) {
    for (final entry in categoryTree.entries) {
      if (entry.value.contains(categoryKey)) {
        return entry.key; // mainGroupKey
      }
    }
    return null;
  }
}
