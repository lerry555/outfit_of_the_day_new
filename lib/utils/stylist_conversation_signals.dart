/// Signály z konverzácie pre stylist chat (preferencie, zámer).
class StylistConversationSignals {
  const StylistConversationSignals._();

  /// SLOVENČINA: „no" = skrátené „áno" (súhlas). NIE je to anglické „no".
  /// Odmietnutie je „nie", nie „no".

  static bool _mentionsRain(String blob) {
    if (RegExp(r'd[aá][zž][dď]', caseSensitive: false).hasMatch(blob)) {
      return true;
    }
    return blob.contains('dáždnik') ||
        blob.contains('dazdnik') ||
        blob.contains('prehánk') ||
        blob.contains('prehank');
  }

  /// User výslovne nechce počuť o daždi (nie krátke „no" — to je áno).
  static bool userDeclinedRainAdvice(String conversation) {
    final blob = conversation.toLowerCase();
    const decline = [
      'nechcem dážd',
      'nechcem dazd',
      'nechcem dažd',
      'nechcem riešiť dážd',
      'nechcem riešiť dážď',
      'nechcem riesit dazd',
      'nepotrebujem dážd',
      'nepotrebujem dazd',
      'nechcem počuť o daždi',
      'nechcem pocut o dazdi',
      'bez dažď',
      'bez dazd',
    ];
    return decline.any(blob.contains);
  }

  /// A plan/activity statement gives the conversation context but does not, by
  /// itself, authorize generating an outfit. Keep this broad and semantic:
  /// it applies to city plans, events, trips and other activities alike.
  static bool isContextOnlyPlanStatement(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return false;

    final explicitlyRequestsStyling = RegExp(
      r'(outfit|co\s+si\s+mam\s+(?:dat|obliect)|čo\s+si\s+mám\s+(?:dať|obliecť)|co\s+na\s+seba|čo\s+na\s+seba|oblec|obleč|obliec|porad|odporuc|odporúč|navrh|vyber|pomoz|pomôž|daj\s+mi|chcem|ukaz|ukáž|zobraz|kombinac|kombinác)',
      caseSensitive: false,
    ).hasMatch(lower);
    if (explicitlyRequestsStyling) return false;

    return RegExp(
      r'\b(idem|ideme|pojdem|pôjdem|pojdeme|pôjdeme|chystam\s+sa|chystám\s+sa|chystame\s+sa|chystáme\s+sa|cestujem|cestujeme|letim|letím|letime|letíme|vyrazam|vyrážam|vyrazame|vyrážame|caka\s+ma|čaká\s+ma|caka\s+nas|čaká\s+nás)\b',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  static bool userExplicitlyWantsOutfitShown(String text) {
    final lower = text.toLowerCase();
    final wantsShow = lower.contains('ukaz') ||
        lower.contains('ukáž') ||
        lower.contains('zobraz') ||
        lower.contains('ukážeš') ||
        lower.contains('ukazes');
    if (!wantsShow) return false;
    return lower.contains('outfit') ||
        lower.contains('oblec') ||
        lower.contains('obliect') ||
        lower.contains(' ten ') ||
        lower.endsWith(' ten') ||
        lower.contains('kombin');
  }
}
