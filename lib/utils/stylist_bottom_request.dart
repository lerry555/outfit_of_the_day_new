import 'bottom_family_guidance.dart';

/// Rozpozná, keď si používateľ v chate VÝSLOVNE pýta konkrétny typ spodku
/// (šortky / rifle / dlhé nohavice). Takáto požiadavka má prednosť pred
/// počasím — ak je vonku 16 °C, ale človek chce šortky, ukážeme šortky.
class StylistBottomRequest {
  const StylistBottomRequest._();

  static BottomFamily? parse(String text) {
    final norm = _norm(text);
    if (norm.isEmpty) return null;

    // Šortky: výslovné slová alebo „kratšie/krátke“ (mimo „krátky rukáv“).
    final shortsWord = _containsAny(norm, [
      'sortky',
      'sortkach',
      'sortiek',
      'kratasy',
      'kratase',
      'kratasoch',
      'shorts',
      'bermud',
    ]);
    final shorterWord = (norm.contains('kratsie') ||
            norm.contains('kratsich') ||
            norm.contains('kratke') ||
            norm.contains('kratsi')) &&
        !norm.contains('rukav');
    if (shortsWord || shorterWord) return BottomFamily.shorts;

    final jeansWord = _containsAny(norm, [
      'rifle',
      'riflach',
      'rifliach',
      'rifli',
      'dzins',
      'jeans',
      'denim',
    ]);
    if (jeansWord) return BottomFamily.jeans;

    final pantsWord = norm.contains('dlhe nohavice') ||
        norm.contains('dlhsie nohavice') ||
        norm.contains('dlhace') ||
        (norm.contains('nohavice') && norm.contains('dlh'));
    if (pantsWord) return BottomFamily.pants;

    return null;
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
