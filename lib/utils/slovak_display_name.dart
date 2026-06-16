import '../Services/color_naming_service.dart';

/// Grammatical agreement class for Slovak color + clothing names.
enum SlovakNounAgreement {
  plural,
  feminineSingular,
  neuterSingular,
  masculineSingular,
}

/// Builds a grammatically correct Slovak display name: `{color} {clothing}`.
///
/// Base colors are expected in feminine singular form ([wardrobeBaseColors]), e.g.
/// `čierna`, `biela`, `modrá`. The adjective is inflected to match the clothing noun.
String buildSlovakDisplayName({
  required String baseColor,
  required String clothingLabel,
  String? canonicalType,
  String? subCategoryKey,
}) {
  final label = clothingLabel.trim();
  if (label.isEmpty) return '';

  final agreement = _resolveAgreement(
    canonicalType: canonicalType,
    subCategoryKey: subCategoryKey,
    clothingLabel: label,
  );

  final colorAdj = _agreeColorAdjective(baseColor, agreement);
  final clothing = _lowerFirst(label);
  if (colorAdj.isEmpty) return _upperFirst(clothing);

  return _upperFirst('$colorAdj $clothing');
}

SlovakNounAgreement _resolveAgreement({
  String? canonicalType,
  String? subCategoryKey,
  required String clothingLabel,
}) {
  final key = (subCategoryKey ?? '').toLowerCase();
  final label = _normalizeSk(clothingLabel);
  final canon = (canonicalType ?? '').toLowerCase();

  if (_isPlural(key, label, canon)) return SlovakNounAgreement.plural;
  if (_isFeminine(key, label, canon)) return SlovakNounAgreement.feminineSingular;
  if (_isNeuter(key, label, canon)) return SlovakNounAgreement.neuterSingular;
  return SlovakNounAgreement.masculineSingular;
}

bool _isPlural(String key, String label, String canon) {
  if (key.startsWith('nohavice_') ||
      key.startsWith('rifle') ||
      key.startsWith('sortky') ||
      key.startsWith('leginy') ||
      key.startsWith('tenisky') ||
      key.startsWith('sandale') ||
      key.startsWith('cizmy') ||
      key == 'gumaky' ||
      key == 'snehule' ||
      key == 'zabky' ||
      key == 'espadrilky' ||
      key == 'okuliare' ||
      key == 'rukavice') {
    return true;
  }

  if (canon == 'sneakers' ||
      canon == 'sneaker' ||
      canon == 'jeans' ||
      canon == 'pants' ||
      canon == 'shorts' ||
      canon == 'boots' ||
      canon == 'glasses') {
    return true;
  }

  return label.contains('nohavice') ||
      label.contains('rifle') ||
      label.contains('sortky') ||
      label.contains('shortky') ||
      label.contains('leginy') ||
      label.contains('tenisky') ||
      label.contains('sandale') ||
      label.contains('cizmy') ||
      label.contains('gumaky') ||
      label.contains('snehule') ||
      label.contains('zabky') ||
      label.contains('espadrilky') ||
      label.contains('okuliare') ||
      label.contains('rukavice');
}

bool _isFeminine(String key, String label, String canon) {
  if (key.startsWith('mikina_') ||
      key.startsWith('bluzka') ||
      key.startsWith('kosela_') ||
      key.startsWith('bunda_') ||
      key == 'kabat' ||
      key == 'vesta' ||
      key == 'prsiplast' ||
      key == 'flisova_bunda' ||
      key.startsWith('sukna') ||
      key.startsWith('saty') ||
      key == 'ciapka' ||
      key == 'siltovka' ||
      key == 'sal' ||
      key == 'kabelka' ||
      key == 'crossbody' ||
      key == 'totebag' ||
      key == 'listova_kabelka') {
    return true;
  }

  if (canon == 'hoodie' ||
      canon == 'sweatshirt' ||
      canon == 'blouse' ||
      canon == 'dress' ||
      canon == 'skirt' ||
      canon == 'hat' ||
      canon == 'scarf') {
    return true;
  }

  return label.contains('mikina') ||
      label.contains('bluzka') ||
      label.contains('koseľa') ||
      label.contains('kosela') ||
      label.contains('bunda') && !label.contains('flisova') ||
      label.contains('vesta') ||
      label.contains('prsiplast') ||
      label.contains('sukna') ||
      label.contains('saty') ||
      label.contains('čiapka') ||
      label.contains('ciapka') ||
      label.contains('šiltovka') ||
      label.contains('siltovka') ||
      label.contains('kabelka') ||
      label.contains('sal') ||
      label.contains('šál');
}

bool _isNeuter(String key, String label, String canon) {
  if (key == 'tricko' ||
      key == 'tricko_dlhy_rukav' ||
      key == 'tielko' ||
      key == 'undershirt' ||
      key == 'top_basic' ||
      key == 'crop_top' ||
      key == 'polo_tricko' ||
      key == 'sport_tricko' ||
      key == 'sako') {
    return true;
  }

  if (canon == 'tshirt' ||
      canon == 'tank' ||
      canon == 'undershirt' ||
      canon == 'polo' ||
      canon == 'blazer') {
    return true;
  }

  return _containsWord(label, 'tričko') ||
      _containsWord(label, 'tricko') ||
      _containsWord(label, 'tielko') ||
      _containsWord(label, 'sako') ||
      label.contains('polo tričko') ||
      label.contains('polo tricko');
}

bool _containsWord(String haystack, String word) {
  final pattern = RegExp(r'(^|\s)' + RegExp.escape(word) + r'(\s|$)', caseSensitive: false);
  return pattern.hasMatch(haystack) || haystack.startsWith(word);
}

String _normalizeSk(String input) {
  var s = input.toLowerCase();
  const repl = {
    'á': 'a',
    'ä': 'a',
    'č': 'c',
    'ď': 'd',
    'é': 'e',
    'í': 'i',
    'ĺ': 'l',
    'ľ': 'l',
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
  for (final e in repl.entries) {
    s = s.replaceAll(e.key, e.value);
  }
  return s;
}

String _toFeminineColorBase(String color) {
  var c = color.trim().toLowerCase();
  if (c.isEmpty) return c;

  for (final base in wardrobeBaseColors) {
    if (c == base) return base;
  }

  final norm = _normalizeSk(c);
  for (final base in wardrobeBaseColors) {
    if (norm == _normalizeSk(base)) return base;
  }

  if (c.endsWith('é')) {
    return '${c.substring(0, c.length - 1)}á';
  }
  if (c.endsWith('e') && c.length > 3 && !c.endsWith('ove')) {
    return '${c.substring(0, c.length - 1)}a';
  }
  if (c.endsWith('ý')) {
    return '${c.substring(0, c.length - 1)}á';
  }
  if (c.endsWith('y') && c.length > 3) {
    return '${c.substring(0, c.length - 1)}a';
  }

  return c;
}

String _agreeColorAdjective(String baseColor, SlovakNounAgreement agreement) {
  final feminine = _toFeminineColorBase(baseColor);
  if (feminine.isEmpty) return feminine;

  if (!_looksInflectable(feminine)) return _upperFirst(feminine);

  switch (agreement) {
    case SlovakNounAgreement.plural:
    case SlovakNounAgreement.neuterSingular:
      if (feminine.endsWith('á')) {
        return '${feminine.substring(0, feminine.length - 1)}é';
      }
      if (feminine.endsWith('a')) {
        return '${feminine.substring(0, feminine.length - 1)}e';
      }
      return feminine;
    case SlovakNounAgreement.feminineSingular:
      return feminine;
    case SlovakNounAgreement.masculineSingular:
      if (feminine.endsWith('á')) {
        return '${feminine.substring(0, feminine.length - 1)}ý';
      }
      if (feminine.endsWith('a')) {
        return '${feminine.substring(0, feminine.length - 1)}y';
      }
      return feminine;
  }
}

bool _looksInflectable(String color) {
  if (color == 'khaki' || color == 'denim') return false;
  return color.endsWith('á') ||
      color.endsWith('a') ||
      color.endsWith('é') ||
      color.endsWith('ý');
}

String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

String _upperFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Protected descriptive phrases — grammar fix must not rewrite these names.
const List<String> protectedWardrobeNamePhrases = [
  'tréningová bunda',
  'treningova bunda',
  'fashion tenisky',
  'športové tenisky',
  'sportove tenisky',
  'sportové tenisky',
  'bežecké tenisky',
  'bezecke tenisky',
];

/// Fixes only the leading color adjective in [name] when agreement is obviously wrong.
///
/// Returns `null` when no safe fix applies. Does not change the clothing phrase.
String? fixSlovakWardrobeNameGrammar({
  required String name,
  String? subCategoryKey,
  String? canonicalType,
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  if (_hasProtectedPhrase(trimmed)) return null;

  final parsed = _parseLeadingColorName(trimmed);
  if (parsed == null) return null;

  final agreement = _resolveAgreement(
    canonicalType: canonicalType,
    subCategoryKey: subCategoryKey,
    clothingLabel: parsed.clothingPhrase,
  );

  final correctAdj = _agreeColorAdjective(parsed.baseColor, agreement);
  if (correctAdj.isEmpty) return null;

  if (_normalizeSk(parsed.leadingAdjective) == _normalizeSk(correctAdj)) {
    return null;
  }

  final fixedLeading = _upperFirst(correctAdj);
  final fixedName = '$fixedLeading ${parsed.clothingPhrase}';
  if (!_onlyLeadingColorWordChanged(trimmed, fixedName)) return null;

  return fixedName;
}

bool _hasProtectedPhrase(String name) {
  final n = _normalizeSk(name);
  for (final phrase in protectedWardrobeNamePhrases) {
    if (n.contains(_normalizeSk(phrase))) return true;
  }
  return false;
}

class _ParsedColorName {
  const _ParsedColorName({
    required this.leadingAdjective,
    required this.baseColor,
    required this.clothingPhrase,
  });

  final String leadingAdjective;
  final String baseColor;
  final String clothingPhrase;
}

_ParsedColorName? _parseLeadingColorName(String name) {
  final match = RegExp(r'^(\S+)\s+(.+)$').firstMatch(name.trim());
  if (match == null) return null;

  final leading = match.group(1) ?? '';
  final rest = (match.group(2) ?? '').trim();
  if (leading.isEmpty || rest.isEmpty) return null;

  final baseColor = _recognizeColorAdjectiveToken(leading);
  if (baseColor == null) return null;

  return _ParsedColorName(
    leadingAdjective: leading,
    baseColor: baseColor,
    clothingPhrase: rest,
  );
}

String? _recognizeColorAdjectiveToken(String token) {
  final feminine = _toFeminineColorBase(token.trim().toLowerCase());
  if (feminine.isEmpty || !_looksInflectable(feminine)) return null;

  for (final base in wardrobeBaseColors) {
    if (feminine == base || _normalizeSk(feminine) == _normalizeSk(base)) {
      return base;
    }
  }
  return null;
}

bool _onlyLeadingColorWordChanged(String oldName, String newName) {
  final oldParts = oldName.trim().split(RegExp(r'\s+'));
  final newParts = newName.trim().split(RegExp(r'\s+'));
  if (oldParts.length != newParts.length) return false;
  if (oldParts.length < 2) return false;

  for (var i = 1; i < oldParts.length; i++) {
    if (oldParts[i] != newParts[i]) return false;
  }
  return oldParts.first != newParts.first;
}
