/// Emoji línia zarovnaná s TripPackingScreen — zdieľané s Home briefing kartami.
abstract final class LuxuryWeatherEmoji {
  LuxuryWeatherEmoji._();

  /// Jednoslovný štítok počasia (SK) z API / briefing logiky.
  static String forConditionSk(String conditionSk) {
    final n = conditionSk.trim();
    switch (n) {
      case 'Jasno':
      case 'Slnečno':
        return '☀️';
      case 'Polooblačno':
        return '🌤️';
      case 'Oblačno':
      case 'Zamračené':
        return '☁️';
      case 'Dážď':
      case 'Prehánky':
        return '🌧️';
      case 'Búrka':
      case 'Búrky':
        return '⛈️';
      case 'Veterno':
        return '💨';
      case 'Sychravo':
      case 'Mlhavo':
      case 'Hmlisto':
        return '🌫️';
      case 'Sneženie':
        return '🌨️';
      case 'Premenlivé':
        return '🌦️';
      default:
        return '🌤️';
    }
  }
}
