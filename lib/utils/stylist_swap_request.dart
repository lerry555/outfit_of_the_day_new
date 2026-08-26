import 'bottom_family_guidance.dart';
import 'footwear_family_guidance.dart';
import 'stylist_bottom_request.dart';

/// Slot oblečenia, ktorý chce používateľ vymeniť.
enum StylistSwapSlot { top, bottom, shoes, outerwear }

/// Zjednotené rozpoznanie požiadavky „vymeň mi tento kus“ pre KTORÝKOĽVEK slot
/// (vrch / spodok / obuv / vrchná vrstva). Vďaka tomu sa všetky kúsky správajú
/// rovnako: keď používateľ chce iný kus, vymeníme len ten — bez zbytočných otázok
/// a bez prehodenia celého outfitu.
class StylistSwapRequest {
  const StylistSwapRequest({
    required this.slot,
    this.bottomFamily,
    this.shoeFamily,
  });

  final StylistSwapSlot slot;

  /// Vyplnené len pri spodku, keď používateľ chce konkrétnu rodinu (kraťasy…).
  final BottomFamily? bottomFamily;

  /// Vyplnené len pri obuvi, keď chce konkrétnu rodinu (tenisky, čižmy…).
  final FootwearFamily? shoeFamily;

  static const List<String> _changeWords = [
    'ine',
    'iny',
    'inu',
    'ineho',
    'inych',
    'vymen',
    'zmen',
    'prehod',
    'skus ine',
    'nieco ine',
    'daj ine',
    'daj mi ine',
    'radsej',
  ];

  static const List<String> _shoesWords = [
    'topank',
    'topanok',
    'tenis',
    'sneaker',
    'obuv',
    'cizm',
    'sandal',
    'mokasin',
    'lodick',
    'poltopank',
  ];

  static const List<String> _outerWords = [
    'bund',
    'kabat',
    'sako',
    'blazer',
    'vetrovk',
    'parka',
    'parku',
    'kardigan',
  ];

  static const List<String> _topWords = [
    'tricko',
    'tricka',
    'tielko',
    'tielka',
    'kosel',
    'mikin',
    'sveter',
    'pulover',
    'vrch',
    'top',
  ];

  static const List<String> _bottomWords = [
    'nohavic',
    'gate',
    'gatie',
    'gat',
    'rifle',
    'rifli',
    'kratas',
    'sortky',
    'sortk',
    'sukn',
    'spodok',
    'spodn',
  ];

  /// Rozpozná požiadavku na výmenu jedného slotu. Vráti `null`, ak text nie je
  /// žiadosť o výmenu kusu.
  static StylistSwapRequest? parse(String text) {
    final norm = _norm(text);
    if (norm.isEmpty) return null;

    // Mentioning a garment family inside an explanation/follow-up question is
    // not a request to replace it. Family detection is intentionally broad,
    // so this semantic guard must run before the family-only swap shortcut.
    if (_asksAboutExistingChoice(norm)) return null;

    final hasChangeIntent = _containsAny(norm, _changeWords);
    final bottomFamily = StylistBottomRequest.parse(text);
    final shoeFamily = _shoeFamilyFromText(norm);

    // Konkrétna rodina (kraťasy / čižmy) je sama o sebe jasná požiadavka — vtedy
    // netreba slovo „iné“. Pri ostatných slotoch zámer zmeny vyžadujeme.
    final mentionsShoes = _containsAny(norm, _shoesWords);
    final mentionsOuter = _containsAny(norm, _outerWords);
    final mentionsTop = _containsAny(norm, _topWords);
    final mentionsBottom = _containsAny(norm, _bottomWords);

    if (bottomFamily != null) {
      return StylistSwapRequest(
        slot: StylistSwapSlot.bottom,
        bottomFamily: bottomFamily,
      );
    }
    if (shoeFamily != null) {
      return StylistSwapRequest(
        slot: StylistSwapSlot.shoes,
        shoeFamily: shoeFamily,
      );
    }
    if (!hasChangeIntent) return null;

    // Poradie: obuv → vrchná vrstva → vrch → spodok (najšpecifickejšie najprv).
    if (mentionsShoes)
      return const StylistSwapRequest(slot: StylistSwapSlot.shoes);
    if (mentionsOuter) {
      return const StylistSwapRequest(slot: StylistSwapSlot.outerwear);
    }
    if (mentionsTop) return const StylistSwapRequest(slot: StylistSwapSlot.top);
    if (mentionsBottom) {
      return const StylistSwapRequest(slot: StylistSwapSlot.bottom);
    }
    return null;
  }

  static bool _asksAboutExistingChoice(String norm) {
    return RegExp(
      r'(^|\s)(preco|z akeho dovodu|ako to|ako sa|hodi|hodia|pasuje|pasuju|'
      r'vhodne|vhodna|vhodny|zmysel)(\s|$)',
    ).hasMatch(norm);
  }

  static FootwearFamily? _shoeFamilyFromText(String norm) {
    if (norm.contains('tenis') || norm.contains('sneaker')) {
      return FootwearFamily.sneakers;
    }
    if (norm.contains('cizm')) return FootwearFamily.boots;
    if (norm.contains('sandal')) return FootwearFamily.sandals;
    if (norm.contains('lodick') ||
        norm.contains('mokasin') ||
        norm.contains('poltopank') ||
        norm.contains('elegantne topan')) {
      return FootwearFamily.formalShoes;
    }
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
