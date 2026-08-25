/// Shared Home swap-picker matching. Isolated so Košele cannot match T-shirts
/// merely because the substring "shirt" appears in "t-shirt".
String normalizeHomeClothingToken(String? raw) {
  return (raw ?? '')
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

bool homeContainsAnyNormalized(String haystack, List<String> needles) {
  return needles.any((n) => haystack.contains(normalizeHomeClothingToken(n)));
}

String homeManualHeroBlob(Map<String, dynamic> raw) {
  final cat = (raw['categoryKey'] ?? raw['category'] ?? '').toString();
  final sub = (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString();
  final main = (raw['mainGroupKey'] ?? raw['mainGroup'] ?? '').toString();
  final name = (raw['name'] ?? '').toString();
  final pretty = (raw['type_pretty'] ?? raw['typePretty'] ?? '').toString();
  final canonical = (raw['canonicalType'] ?? raw['canonical_type'] ?? '')
      .toString();
  final ui = raw['uiProjection'];
  final uiCat = ui is Map
      ? '${ui['category'] ?? ''} ${ui['mainCategory'] ?? ''}'
      : '';
  return '$name $pretty $canonical $uiCat $cat $sub $main'.toLowerCase();
}

/// Returns whether [blob] matches a named override group.
/// `null` means the caller should apply its type-default matcher.
bool? homeManualGroupMatches({
  required String blob,
  required String group,
}) {
  final normalized = normalizeHomeClothingToken(blob);
  bool has(List<String> words) =>
      homeContainsAnyNormalized(normalized, words);
  switch (group) {
    case 'tee_tank':
      return has(['t-shirt', 'tricko', 'tričko', 'tank', 'tielko']);
    case 'shirt':
      return has(['kosel', 'kosele', 'kosela', 'dress_shirt', 'oxford']) &&
          !has(['t-shirt', 'tricko', 'tielko', 'tank']);
    case 'hoodie':
      return has(['hoodie', 'mikina']);
    case 'jacket':
      return has(['jacket', 'bunda']);
    case 'coat':
      return has(['coat', 'kabat', 'kabát']);
    case 'bottom':
      return has([
        'nohav',
        'rifl',
        'jeans',
        'pants',
        'sukn',
        'skirt',
        'short',
      ]);
    case 'shoes':
      return has([
        'topan',
        'topán',
        'tenis',
        'sneaker',
        'boots',
        'sand',
        'obuv',
        'shoes',
      ]);
    case 'type_default':
    default:
      return null;
  }
}
