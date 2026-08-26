/// Deterministic, non-calendar season compatibility for Wardrobe V2.
///
/// This is descriptive metadata for browsing and ranking, never a literal
/// permission window. Live weather and physical suitability remain the
/// authority when selecting an outfit.
abstract final class SeasonCompatibilityV2 {
  static const allSeason = 'celoročne';

  static List<String> derive({
    required String canonicalType,
    required String canonicalFamily,
    required String layerPosition,
    required int warmth,
    Iterable<String> outfitFunctions = const [],
    Map<String, dynamic> attributes = const {},
  }) {
    final type = canonicalType.trim().toLowerCase();
    final family = canonicalFamily.trim().toLowerCase();
    final functions = outfitFunctions.map((x) => x.toLowerCase()).toSet();
    final safeWarmth = warmth.clamp(1, 10);

    if (_isExplicitWarmWeatherType(type)) return const ['jar', 'leto'];
    if (_isExplicitWinterType(type)) return const ['jeseň', 'zima'];

    if (family == 'footwear') {
      if (type.contains('boot')) {
        if (safeWarmth >= 7) return const ['jeseň', 'zima'];
        return const ['jar', 'jeseň'];
      }
      if (_isOpenFootwear(type)) return const ['jar', 'leto'];
      if (type.contains('sneaker') ||
          type.contains('trainer') ||
          type.contains('running')) {
        return const ['jar', 'leto', 'jeseň'];
      }
      return const [allSeason];
    }

    if (layerPosition == 'outer' || layerPosition == 'shell') {
      if (safeWarmth >= 7) return const ['jeseň', 'zima'];
      if (safeWarmth >= 5) return const ['jar', 'jeseň', 'zima'];
      if (functions.contains('weather_protection')) {
        return const ['jar', 'leto', 'jeseň'];
      }
      return const ['jar', 'leto', 'jeseň'];
    }

    if (safeWarmth >= 8) return const ['jeseň', 'zima'];
    if (safeWarmth >= 6) return const ['jar', 'jeseň', 'zima'];
    if (safeWarmth <= 2) return const ['jar', 'leto'];
    return const [allSeason];
  }

  static bool _isExplicitWinterType(String type) =>
      type.contains('winter') ||
      type.contains('snow') ||
      type.contains('thermal');

  static bool _isExplicitWarmWeatherType(String type) =>
      type.contains('swim') ||
      type.contains('bikini') ||
      type.contains('short');

  static bool _isOpenFootwear(String type) =>
      type.contains('sandal') ||
      type.contains('flip_flop') ||
      type.contains('slide') ||
      type.contains('espadrille');
}
