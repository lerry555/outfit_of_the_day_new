abstract final class StylistOutfitDirectiveGuard {
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
