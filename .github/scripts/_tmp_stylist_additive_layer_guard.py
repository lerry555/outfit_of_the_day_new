from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one anchor, found {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


guard = Path("lib/utils/stylist_outfit_directive_guard.dart")
if guard.exists():
    raise SystemExit("guard file already exists unexpectedly")

guard.write_text(
    r'''abstract final class StylistOutfitDirectiveGuard {
  /// Repairs only a structural contradiction: when an already visible outfit
  /// exists and the user explicitly asks to ADD an upper layer, that request is
  /// additive. A model directive that calls it a one-slot top replacement must
  /// not be allowed to silently change the base outfit.
  static Map<String, dynamic>? repair({
    required Object? rawDirective,
    required String userText,
    required bool hasCurrentOutfit,
  }) {
    final original = rawDirective is Map
        ? Map<String, dynamic>.from(rawDirective)
        : <String, dynamic>{};
    if (!hasCurrentOutfit) {
      return rawDirective is Map ? original : null;
    }

    final folded = _fold(userText);
    final layerFamily = _explicitLayerFamily(folded);
    if (layerFamily == null || !_isExplicitAdditiveRequest(folded)) {
      return rawDirective is Map ? original : null;
    }

    // "Vymeň/zmeň/nahradiť X za mikinu" is a replacement, not an additive
    // layer request, so leave that meaning to the Brain.
    if (RegExp(r'\b(vymen\w*|zmen\w*|nahrad\w*)\b').hasMatch(folded)) {
      return rawDirective is Map ? original : null;
    }

    return <String, dynamic>{
      ...original,
      'scope': 'full_outfit',
      'slot': 'none',
      'family': 'none',
      'preserveOtherSlots': false,
      'preserveCurrentOutfit': true,
      'extraLayer': 'required_upper_layer',
      'layerFamily': layerFamily,
      'presentation': 'concise_full',
    };
  }

  static bool _isExplicitAdditiveRequest(String folded) {
    if (RegExp(
      r'\b(pridaj|pridat|pridame|prihod|prihodit|dopln|doplnit)\w*\b',
    ).hasMatch(folded)) {
      return true;
    }
    return RegExp(
      r'\bdaj\b.{0,50}\b(aj|tam|k tomu|do neho|do toho|do outfitu)\b',
    ).hasMatch(folded);
  }

  static String? _explicitLayerFamily(String folded) {
    if (RegExp(r'\b(mikina|mikinu|mikiny|hoodie)\b').hasMatch(folded)) {
      return 'hoodie';
    }
    if (RegExp(r'\b(sveter|svetra|svetrom|svetre)\b').hasMatch(folded)) {
      return 'sweater';
    }
    if (RegExp(r'\b(bunda|bundu|bundy|vetrovka|vetrovku)\b').hasMatch(folded)) {
      return 'jacket';
    }
    if (RegExp(r'\b(kabat|kabata|kabatom)\b').hasMatch(folded)) {
      return 'coat';
    }
    if (RegExp(r'\b(sako|saka|sakom)\b').hasMatch(folded)) {
      return 'blazer';
    }
    if (RegExp(r'\b(kardigan|kardiganu|kardiganom)\b').hasMatch(folded)) {
      return 'cardigan';
    }
    return null;
  }

  static String _fold(String value) {
    var out = value.toLowerCase();
    const replacements = <String, String>{
      'á': 'a',
      'ä': 'a',
      'č': 'c',
      'ď': 'd',
      'é': 'e',
      'í': 'i',
      'ľ': 'l',
      'ĺ': 'l',
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
    replacements.forEach((from, to) => out = out.replaceAll(from, to));
    return out;
  }
}
''',
    encoding="utf-8",
)

replace_once(
    "lib/screens/stylist_chat_screen.dart",
    "import '../utils/stylist_conversation_signals.dart';\n",
    "import '../utils/stylist_conversation_signals.dart';\n"
    "import '../utils/stylist_outfit_directive_guard.dart';\n",
)

replace_once(
    "lib/screens/stylist_chat_screen.dart",
    "      response = await _recoverIfOffline(response, jobId);\n"
    "      debugPrint('STYLIST CHAT timing apiMs=${timing.elapsedMilliseconds}');\n",
    "      response = await _recoverIfOffline(response, jobId);\n"
    "      final repairedDirective = StylistOutfitDirectiveGuard.repair(\n"
    "        rawDirective: response['outfitDirective'],\n"
    "        userText: text,\n"
    "        hasCurrentOutfit: _conversationAlreadyHasOutfitCards(),\n"
    "      );\n"
    "      if (repairedDirective != null) {\n"
    "        final previousScope = response['outfitDirective'] is Map\n"
    "            ? (response['outfitDirective']['scope'] ?? '').toString()\n"
    "            : '';\n"
    "        response['outfitDirective'] = repairedDirective;\n"
    "        if (previousScope != repairedDirective['scope']) {\n"
    "          debugPrint(\n"
    "            'STYLIST CHAT directive_guard '\n"
    "            'from=${previousScope.isEmpty ? \"none\" : previousScope} '\n"
    "            'to=${repairedDirective['scope']} '\n"
    "            'layer=${repairedDirective['layerFamily']}',\n"
    "          );\n"
    "        }\n"
    "      }\n"
    "      debugPrint('STYLIST CHAT timing apiMs=${timing.elapsedMilliseconds}');\n",
)

replace_once(
    "lib/screens/stylist_chat_screen.dart",
    "      final focusedReply = brainReply ?? fallbackReply;\n",
    "      // A one-slot reply must name the item that was ACTUALLY changed.\n"
    "      // The frozen explanation describes the whole candidate and can mention a\n"
    "      // different slot, so deterministic changed-item copy has display priority.\n"
    "      final focusedReply = fallbackReply ?? brainReply;\n",
)

replace_once(
    "lib/screens/stylist_chat_screen.dart",
    "${brainReply != null ? 'brain_locked_swap' : 'local_swap_fallback'} ",
    "${fallbackReply != null ? 'local_swap_fallback' : 'brain_locked_swap'} ",
)

replace_once(
    "test/brain_v1_v2_offline_bundle_test.dart",
    "import 'package:outfitofTheDay/utils/stylist_semantic_activity.dart';\n",
    "import 'package:outfitofTheDay/utils/stylist_semantic_activity.dart';\n"
    "import 'package:outfitofTheDay/utils/stylist_outfit_directive_guard.dart';\n",
)

test_path = Path("test/brain_v1_v2_offline_bundle_test.dart")
test_text = test_path.read_text(encoding="utf-8")
insert = r'''

  test('explicit additive layer cannot collapse into a top swap', () {
    final repaired = StylistOutfitDirectiveGuard.repair(
      rawDirective: <String, dynamic>{
        'scope': 'single_slot',
        'slot': 'top',
        'family': 'none',
        'extraLayer': 'none',
        'layerFamily': 'none',
        'presentation': 'focused_item',
      },
      userText: 'ukáž mi celý outfit a pridaj mi do neho aj mikinu',
      hasCurrentOutfit: true,
    );

    expect(repaired, isNotNull);
    expect(repaired!['scope'], 'full_outfit');
    expect(repaired['slot'], 'none');
    expect(repaired['preserveCurrentOutfit'], isTrue);
    expect(repaired['extraLayer'], 'required_upper_layer');
    expect(repaired['layerFamily'], 'hoodie');
    expect(repaired['presentation'], 'concise_full');

    final replacement = StylistOutfitDirectiveGuard.repair(
      rawDirective: <String, dynamic>{
        'scope': 'single_slot',
        'slot': 'top',
      },
      userText: 'vymeň tričko za mikinu',
      hasCurrentOutfit: true,
    );
    expect(replacement!['scope'], 'single_slot');
    expect(replacement['slot'], 'top');
  });

  test('single-slot display prefers the actually changed item copy', () {
    final screen = _read('lib/screens/stylist_chat_screen.dart');
    expect(screen, contains('final focusedReply = fallbackReply ?? brainReply;'));
    expect(
      screen,
      contains("fallbackReply != null ? 'local_swap_fallback' : 'brain_locked_swap'"),
    );
  });
'''

final_close = test_text.rfind("\n}")
if final_close < 0:
    raise SystemExit("test main closing brace not found")
test_path.write_text(
    test_text[:final_close] + insert + test_text[final_close:],
    encoding="utf-8",
)
