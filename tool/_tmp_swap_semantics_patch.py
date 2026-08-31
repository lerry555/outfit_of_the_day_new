from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


swap_path = Path("lib/utils/stylist_swap_request.dart")
old_swap = swap_path.read_text(encoding="utf-8")
if "enum StylistSwapThermalPreference" in old_swap:
    raise SystemExit("stylist_swap_request.dart already contains thermal semantics")
if "final bottomFamily = StylistBottomRequest.parse(text);" not in old_swap:
    raise SystemExit("stylist_swap_request.dart no longer matches expected baseline")

swap_path.write_text(r'''import 'bottom_family_guidance.dart';
import 'footwear_family_guidance.dart';
import 'stylist_bottom_request.dart';

enum StylistSwapSlot { top, bottom, shoes, outerwear }

enum StylistSwapThermalPreference { cooler, warmer }

class StylistSwapRequest {
  const StylistSwapRequest({
    required this.slot,
    this.bottomFamily,
    this.shoeFamily,
    this.thermalPreference,
  });

  final StylistSwapSlot slot;
  final BottomFamily? bottomFamily;
  final FootwearFamily? shoeFamily;
  final StylistSwapThermalPreference? thermalPreference;

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

  static const List<String> _rejectionWords = [
    'nechcem',
    'nechcel',
    'nechcela',
    'nevyhov',
    'nepaci',
    'nesedi',
    'nesedia',
    'tlaci',
    'tlacia',
    'skriab',
    'skrab',
    'nepohodl',
    'tesn',
    'radsej nie',
  ];

  static const List<String> _topWords = [
    'trick',
    'kosel',
    'poloko',
    'svetr',
    'mikina',
    'mikinu',
    'hoodie',
    'top',
  ];
  static const List<String> _bottomWords = [
    'nohav',
    'rifl',
    'dzins',
    'jeans',
    'krat',
    'sort',
    'bermud',
    'teplak',
    'jogger',
    'chino',
  ];
  static const List<String> _shoeWords = [
    'topank',
    'obuv',
    'tenisk',
    'sneaker',
    'cizm',
    'boot',
    'sand',
    'mokasin',
    'loafer',
  ];
  static const List<String> _outerWords = [
    'bund',
    'kabat',
    'vetrov',
    'bomber',
    'parka',
    'sako',
    'blazer',
    'outerwear',
  ];

  static StylistSwapRequest? parse(String text) {
    final norm = _norm(text);
    if (norm.isEmpty) return null;

    final hasActionCue = _hasActionCue(norm);
    if (_asksAboutExistingChoice(norm) && !hasActionCue) return null;
    if (_isQuestionOnly(norm) && !hasActionCue) return null;

    final thermalPreference = _thermalPreference(norm);
    final hasRejectionIntent =
        _containsAny(norm, _rejectionWords) || thermalPreference != null;
    final hasChangeIntent = _containsAny(norm, _changeWords);
    final desiredSegment = _desiredReplacementSegment(norm);

    final desiredBottomFamily = desiredSegment == null
        ? null
        : StylistBottomRequest.parse(desiredSegment);
    final desiredShoeFamily = desiredSegment == null
        ? null
        : _shoeFamilyFromText(desiredSegment);

    // Explicitly requested replacement always wins over the item mentioned as
    // rejected/changed: "nechcem rifle, daj kratasy" -> shorts, and
    // "vymen rifle za kratasy" -> shorts.
    if (desiredBottomFamily != null) {
      return StylistSwapRequest(
        slot: StylistSwapSlot.bottom,
        bottomFamily: desiredBottomFamily,
        thermalPreference: thermalPreference,
      );
    }
    if (desiredShoeFamily != null) {
      return StylistSwapRequest(
        slot: StylistSwapSlot.shoes,
        shoeFamily: desiredShoeFamily,
        thermalPreference: thermalPreference,
      );
    }

    final mentionsTop = _containsAny(norm, _topWords);
    final mentionsBottom = _containsAny(norm, _bottomWords);
    final mentionsShoes = _containsAny(norm, _shoeWords);
    final mentionsOuter = _containsAny(norm, _outerWords);
    final mentionedSlot = _singleMentionedSlot(
      top: mentionsTop,
      bottom: mentionsBottom,
      shoes: mentionsShoes,
      outerwear: mentionsOuter,
    );

    // A complaint/rejection names the item to REMOVE, never the desired
    // replacement. This applies to every supported clothing slot.
    if (hasRejectionIntent || hasChangeIntent) {
      if (mentionedSlot == null) return null;
      return StylistSwapRequest(
        slot: mentionedSlot,
        thermalPreference: thermalPreference,
      );
    }

    // Preserve compact direct requests such as "kratasy" / "rifle" and
    // "tenisky". Longer descriptive sentences are not silently interpreted as
    // replacement commands merely because they mention a garment family.
    if (_isCompactDirectRequest(norm)) {
      final bottomFamily = StylistBottomRequest.parse(text);
      if (bottomFamily != null) {
        return StylistSwapRequest(
          slot: StylistSwapSlot.bottom,
          bottomFamily: bottomFamily,
        );
      }
      final shoeFamily = _shoeFamilyFromText(norm);
      if (shoeFamily != null) {
        return StylistSwapRequest(
          slot: StylistSwapSlot.shoes,
          shoeFamily: shoeFamily,
        );
      }
    }

    return null;
  }

  static StylistSwapSlot? _singleMentionedSlot({
    required bool top,
    required bool bottom,
    required bool shoes,
    required bool outerwear,
  }) {
    final slots = <StylistSwapSlot>[
      if (top) StylistSwapSlot.top,
      if (bottom) StylistSwapSlot.bottom,
      if (shoes) StylistSwapSlot.shoes,
      if (outerwear) StylistSwapSlot.outerwear,
    ];
    return slots.length == 1 ? slots.single : null;
  }

  static StylistSwapThermalPreference? _thermalPreference(String norm) {
    final cooler = RegExp(
      r'(mi\s+(?:bude|je)\s+teplo|bude\s+mi\s+teplo|prilis\s+tepl|moc\s+tepl|spotim)',
    ).hasMatch(norm);
    final warmer = RegExp(
      r'(mi\s+(?:bude|je)\s+zima|bude\s+mi\s+zima|prilis\s+stud|moc\s+stud)',
    ).hasMatch(norm);
    if (cooler == warmer) return null;
    return cooler
        ? StylistSwapThermalPreference.cooler
        : StylistSwapThermalPreference.warmer;
  }

  static String? _desiredReplacementSegment(String norm) {
    // For change verbs, only the material AFTER "za" / "na" is the desired
    // replacement. "vymen rifle" therefore means replace the jeans, not
    // request another pair of jeans.
    final hasChangeVerb = RegExp(r'\b(vymen\w*|zmen\w*|prehod\w*)\b').hasMatch(norm);
    if (hasChangeVerb) {
      final za = norm.lastIndexOf(' za ');
      if (za >= 0 && za + 4 < norm.length) return norm.substring(za + 4).trim();
      final na = norm.lastIndexOf(' na ');
      if (na >= 0 && na + 4 < norm.length) return norm.substring(na + 4).trim();
    }

    final cue = RegExp(
      r'\b(daj(?:\s+mi)?|chcem|chcel\s+by\s+som|chcela\s+by\s+som|skus|radsej|dal\s+by\s+som\s+si|dala\s+by\s+som\s+si)\b',
    );
    final matches = cue.allMatches(norm).toList(growable: false);
    if (matches.isEmpty) return null;
    final last = matches.last;
    final segment = norm.substring(last.end).trim();
    if (segment.isEmpty || RegExp(r'^nie(?:\s|$)').hasMatch(segment)) return null;
    return segment;
  }

  static bool _hasActionCue(String norm) =>
      RegExp(
        r'\b(daj|chcem|chcel|chcela|skus|radsej|vymen\w*|zmen\w*|prehod\w*)\b',
      ).hasMatch(norm);

  static bool _isQuestionOnly(String norm) {
    if (norm.contains('?')) return true;
    return RegExp(
      r'^(preco|naco|nebude|bude\s+mi|myslis|co\s+ak|je\s+to\s+ok)\b',
    ).hasMatch(norm);
  }

  static bool _isCompactDirectRequest(String norm) {
    final words = norm
        .split(RegExp(r'\s+'))
        .where((x) => x.isNotEmpty)
        .length;
    return words <= 3;
  }

  static bool _asksAboutExistingChoice(String norm) {
    const questionWords = [
      'preco',
      'naco',
      'vhodn',
      'hodi',
      'hodia',
      'dobre',
      'ok',
      'nechat',
      'ponechat',
    ];
    return _containsAny(norm, questionWords);
  }

  static FootwearFamily? _shoeFamilyFromText(String norm) {
    if (_containsAny(norm, const ['cizm', 'boot'])) {
      return FootwearFamily.boots;
    }
    if (_containsAny(norm, const ['sand'])) {
      return FootwearFamily.sandals;
    }
    if (_containsAny(norm, const ['mokasin', 'loafer', 'poltopank', 'formal'])) {
      return FootwearFamily.formalShoes;
    }
    if (_containsAny(norm, const ['tenisk', 'sneaker'])) {
      return FootwearFamily.sneakers;
    }
    return null;
  }

  static bool _containsAny(String norm, List<String> needles) =>
      needles.any(norm.contains);

  static String _norm(String value) => value
      .trim()
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
''', encoding="utf-8")

replace_once(
    "lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart",
    """    bool allowCrossFamilySameSlot = false,\n  }) {\n""",
    """    bool allowCrossFamilySameSlot = false,\n    bool requireCoolerReplacement = false,\n    bool requireWarmerReplacement = false,\n  }) {\n""",
)
replace_once(
    "lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart",
    """    final candidates = wardrobe\n        .where((x) => x.itemId != itemId)\n        .where(\n          (candidate) => SwapCandidateSelectorV2.compatible(\n""",
    """    final candidates = wardrobe\n        .where((x) => x.itemId != itemId)\n        .where((candidate) {\n          if (requireCoolerReplacement &&\n              candidate.item.warmth >= target.item.warmth) {\n            return false;\n          }\n          if (requireWarmerReplacement &&\n              candidate.item.warmth <= target.item.warmth) {\n            return false;\n          }\n          return SwapCandidateSelectorV2.compatible(\n""",
)
replace_once(
    "lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart",
    """            allowCrossFamilySameSlot: allowCrossFamilySameSlot,\n          ).isNotEmpty,\n        );\n""",
    """            allowCrossFamilySameSlot: allowCrossFamilySameSlot,\n          ).isNotEmpty;\n        });\n""",
)

replace_once(
    "lib/Services/stylist_chat_outfit_service.dart",
    """            allowCrossFamilySameSlot: true,\n          ),\n""",
    """            allowCrossFamilySameSlot: true,\n            requireCoolerReplacement:\n                requestedSwap.thermalPreference ==\n                StylistSwapThermalPreference.cooler,\n            requireWarmerReplacement:\n                requestedSwap.thermalPreference ==\n                StylistSwapThermalPreference.warmer,\n          ),\n""",
)

replace_once(
    "lib/screens/stylist_chat_screen.dart",
    """        'shoes=${swapRequest.shoeFamily?.name ?? "-"}',\n""",
    """        'shoes=${swapRequest.shoeFamily?.name ?? "-"} '\n        'thermal=${swapRequest.thermalPreference?.name ?? "-"}',\n""",
)

bundle = Path("test/brain_v1_v2_offline_bundle_test.dart")
bundle_text = bundle.read_text(encoding="utf-8")
import_anchor = "import 'package:flutter_test/flutter_test.dart';\n"
if import_anchor not in bundle_text:
    raise SystemExit("offline bundle import anchor missing")
extra_imports = """import 'package:outfitofTheDay/utils/bottom_family_guidance.dart';\nimport 'package:outfitofTheDay/utils/footwear_family_guidance.dart';\nimport 'package:outfitofTheDay/utils/stylist_swap_request.dart';\n"""
if "utils/stylist_swap_request.dart" not in bundle_text:
    bundle_text = bundle_text.replace(import_anchor, import_anchor + extra_imports, 1)

test_block = r'''

  test('swap parser keeps rejection polarity global across clothing slots', () {
    final hotJeans = StylistSwapRequest.parse('v rifliach mi bude teplo');
    expect(hotJeans, isNotNull);
    expect(hotJeans!.slot, StylistSwapSlot.bottom);
    expect(hotJeans.bottomFamily, isNull);
    expect(hotJeans.thermalPreference, StylistSwapThermalPreference.cooler);

    expect(StylistSwapRequest.parse('Nebude mi v rifliach teplo?'), isNull);

    final shorts = StylistSwapRequest.parse('nechcem rifle, daj kratasy');
    expect(shorts, isNotNull);
    expect(shorts!.slot, StylistSwapSlot.bottom);
    expect(shorts.bottomFamily, BottomFamily.shorts);

    final jeans = StylistSwapRequest.parse('kratasy nechcem, daj rifle');
    expect(jeans, isNotNull);
    expect(jeans!.bottomFamily, BottomFamily.jeans);

    final top = StylistSwapRequest.parse('toto tricko mi nesedi');
    expect(top, isNotNull);
    expect(top!.slot, StylistSwapSlot.top);

    final shoes = StylistSwapRequest.parse('tieto topanky ma tlacia');
    expect(shoes, isNotNull);
    expect(shoes!.slot, StylistSwapSlot.shoes);
    expect(shoes.shoeFamily, isNull);

    final boots = StylistSwapRequest.parse('tenisky ma tlacia, daj cizmy');
    expect(boots, isNotNull);
    expect(boots!.slot, StylistSwapSlot.shoes);
    expect(boots.shoeFamily, FootwearFamily.boots);

    final outer = StylistSwapRequest.parse('v tej bunde mi bude teplo');
    expect(outer, isNotNull);
    expect(outer!.slot, StylistSwapSlot.outerwear);
    expect(outer.thermalPreference, StylistSwapThermalPreference.cooler);

    final coldTop = StylistSwapRequest.parse('v tomto tricku mi bude zima');
    expect(coldTop, isNotNull);
    expect(coldTop!.slot, StylistSwapSlot.top);
    expect(coldTop.thermalPreference, StylistSwapThermalPreference.warmer);

    final directJeans = StylistSwapRequest.parse('daj mi rifle');
    expect(directJeans, isNotNull);
    expect(directJeans!.bottomFamily, BottomFamily.jeans);

    final bareShorts = StylistSwapRequest.parse('kratasy');
    expect(bareShorts, isNotNull);
    expect(bareShorts!.bottomFamily, BottomFamily.shorts);

    final replaceJeans = StylistSwapRequest.parse('vymen mi rifle');
    expect(replaceJeans, isNotNull);
    expect(replaceJeans!.slot, StylistSwapSlot.bottom);
    expect(replaceJeans.bottomFamily, isNull);

    final replaceWithShorts = StylistSwapRequest.parse(
      'vymen rifle za kratasy',
    );
    expect(replaceWithShorts, isNotNull);
    expect(replaceWithShorts!.bottomFamily, BottomFamily.shorts);
  });
'''
if "swap parser keeps rejection polarity global across clothing slots" in bundle_text:
    raise SystemExit("offline bundle already contains swap polarity test")
idx = bundle_text.rfind("}\n")
if idx < 0:
    raise SystemExit("offline bundle final brace missing")
bundle_text = bundle_text[:idx] + test_block + bundle_text[idx:]
bundle.write_text(bundle_text, encoding="utf-8")
