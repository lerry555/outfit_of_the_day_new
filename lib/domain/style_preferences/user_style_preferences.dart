import 'styling_presentation.dart';

/// Authoritative user-taste document: `users/{uid}/stylePreferences/main`.
class UserStylePreferences {
  const UserStylePreferences({
    this.favoriteColors = const <String>[],
    this.avoidedColors = const <String>[],
    this.preferredStyles = const <String>[],
    this.favoriteBrands = const <String>[],
    this.topSize = '',
    this.outerwearSize = '',
    this.pantsSize = '',
    this.shortsSize = '',
    this.shoeSize = '',
    this.stylingPresentation = StylingPresentation.noPreference,
  });

  static const empty = UserStylePreferences();

  /// Stable empty Home taste fingerprint (sizes never participate).
  static const emptyHomeTasteFingerprint = 'v1:c=|a=|s=|b=';

  final List<String> favoriteColors;
  final List<String> avoidedColors;
  final List<String> preferredStyles;
  final List<String> favoriteBrands;
  final String topSize;
  final String outerwearSize;
  final String pantsSize;
  final String shortsSize;
  final String shoeSize;
  final StylingPresentation stylingPresentation;

  bool get isEmpty =>
      favoriteColors.isEmpty &&
      avoidedColors.isEmpty &&
      preferredStyles.isEmpty &&
      favoriteBrands.isEmpty &&
      stylingPresentation == StylingPresentation.noPreference;

  bool get isNotEmpty => !isEmpty;

  factory UserStylePreferences.fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return empty;
    return UserStylePreferences(
      favoriteColors: _stringList(data['favoriteColors']),
      avoidedColors: _stringList(data['avoidedColors']),
      preferredStyles: _stringList(data['preferredStyles']),
      favoriteBrands: _stringList(data['favoriteBrands']),
      topSize: _stringValue(data['topSize']),
      outerwearSize: _stringValue(data['outerwearSize']),
      pantsSize: _stringValue(data['pantsSize'] ?? data['bottomSize']),
      shortsSize: _stringValue(data['shortsSize']),
      shoeSize: _stringValue(data['shoeSize']),
      stylingPresentation: StylingPresentation.parse(
        data['stylingPresentation'] ?? data['wardrobeTarget'],
      ),
    );
  }

  /// Stylist / Home taste payload. Sizes and unrelated profile data omitted.
  Map<String, dynamic>? toStylistPayload() {
    if (isEmpty) return null;
    return <String, dynamic>{
      if (favoriteColors.isNotEmpty)
        'favoriteColors': canonicalColors(favoriteColors),
      if (avoidedColors.isNotEmpty)
        'avoidedColors': canonicalColors(avoidedColors),
      if (preferredStyles.isNotEmpty)
        'preferredStyles': canonicalStyles(preferredStyles),
      if (favoriteBrands.isNotEmpty)
        'favoriteBrands': List<String>.from(favoriteBrands),
      if (stylingPresentation != StylingPresentation.noPreference)
        'stylingPresentation': stylingPresentation.wireName,
    };
  }

  /// Order-insensitive Home cache fingerprint. Sizes are ignored.
  String get homeTasteFingerprint {
    final colors = _sortedUnique(canonicalColors(favoriteColors));
    final avoided = _sortedUnique(canonicalColors(avoidedColors));
    final styles = _sortedUnique(canonicalStyles(preferredStyles));
    final brands = _sortedUnique(canonicalBrands(favoriteBrands));
    return 'v1:c=${colors.join(',')}|a=${avoided.join(',')}|s=${styles.join(',')}|b=${brands.join(',')}';
  }

  static List<String> canonicalColors(List<String> values) {
    return values.map(canonicalColor).toList(growable: false);
  }

  static List<String> canonicalStyles(List<String> values) {
    return values.map(canonicalStyle).toList(growable: false);
  }

  static List<String> canonicalBrands(List<String> values) {
    return values.map(canonicalBrand).toList(growable: false);
  }

  static String canonicalColor(String value) {
    final folded = _fold(value);
    return _colorAliases[value.trim().toLowerCase()] ??
        _colorAliases[folded] ??
        folded;
  }

  static String canonicalStyle(String value) {
    final folded = _fold(value);
    return _styleAliases[value.trim().toLowerCase()] ??
        _styleAliases[folded] ??
        folded;
  }

  static String canonicalBrand(String value) => _fold(value);

  static List<String> _sortedUnique(List<String> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final value in values) {
      if (value.isEmpty || !seen.add(value)) continue;
      out.add(value);
    }
    out.sort();
    return out;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final value = item.toString().trim();
      if (value.isEmpty) continue;
      final key = value.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(value);
    }
    return out;
  }

  static String _stringValue(dynamic raw) {
    if (raw == null) return '';
    return raw.toString().trim();
  }

  static const Map<String, String> _colorAliases = <String, String>{
    'cierna': 'black',
    'čierna': 'black',
    'black': 'black',
    'biela': 'white',
    'white': 'white',
    'siva': 'gray',
    'sivá': 'gray',
    'gray': 'gray',
    'grey': 'gray',
    'bezova': 'beige',
    'béžová': 'beige',
    'beige': 'beige',
    'hneda': 'brown',
    'hnedá': 'brown',
    'brown': 'brown',
    'modra': 'blue',
    'modrá': 'blue',
    'blue': 'blue',
    'zelena': 'green',
    'zelená': 'green',
    'green': 'green',
    'cervena': 'red',
    'červená': 'red',
    'red': 'red',
    'ruzova': 'pink',
    'ružová': 'pink',
    'pink': 'pink',
    'fialova': 'purple',
    'fialová': 'purple',
    'purple': 'purple',
  };

  static const Map<String, String> _styleAliases = <String, String>{
    'casual': 'casual',
    'elegantny': 'elegant',
    'elegantný': 'elegant',
    'elegant': 'elegant',
    'streetwear': 'streetwear',
    'sportovy': 'sport',
    'športový': 'sport',
    'sport': 'sport',
    'minimalisticky': 'minimal',
    'minimalistický': 'minimal',
    'minimal': 'minimal',
    'business': 'business',
    'romanticky': 'romantic',
    'romantický': 'romantic',
    'romantic': 'romantic',
    'luxusny': 'luxury',
    'luxusný': 'luxury',
    'luxury': 'luxury',
    'smart casual': 'smart casual',
  };

  static String _fold(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ý', 'y')
        .replaceAll('č', 'c')
        .replaceAll('ď', 'd')
        .replaceAll('ľ', 'l')
        .replaceAll('ň', 'n')
        .replaceAll('š', 's')
        .replaceAll('ť', 't')
        .replaceAll('ž', 'z');
  }
}
