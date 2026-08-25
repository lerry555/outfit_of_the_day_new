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
