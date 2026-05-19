/// Jednoslovný štítok počasia pre kompaktný „Prehľad dňa“ — bez náladových fráz.
/// Mapovanie podľa WMO weather_code (Open-Meteo).

enum BriefingDaySegment {
  morning,
  afternoon,
  evening,
}

abstract final class BriefingWeatherCondition {
  BriefingWeatherCondition._();

  /// Bez API kódu (fallback): len dážď / vietor / neutrálna oblačnosť.
  static String fallback({
    required bool segmentRain,
    required bool segmentWindy,
    required BriefingDaySegment segment,
  }) {
    return label(
      wmoCode: null,
      segmentRain: segmentRain,
      segmentWindy: segmentWindy,
      segment: segment,
    );
  }

  /// Vyhodnotenie jedného okna dňa.
  static String label({
    required int? wmoCode,
    required bool segmentRain,
    required bool segmentWindy,
    required BriefingDaySegment segment,
  }) {
    final c = wmoCode;

    if (c != null && c >= 95 && c <= 99) {
      return 'Búrka';
    }

    if (segmentRain) {
      if (c != null && c >= 80 && c <= 82) return 'Prehánky';
      if (c != null && c >= 61 && c <= 67) return 'Dážď';
      return 'Dážď';
    }

    if (c != null) {
      if (c >= 80 && c <= 82) return 'Prehánky';
      if (c >= 61 && c <= 67) return 'Dážď';
      if (c >= 51 && c <= 57) return 'Sychravo';
      if (c == 45 || c == 48) return 'Mlhavo';
      if (c >= 71 && c <= 77) return 'Zamračené';
      if (c == 85 || c == 86) return 'Zamračené';
      if (c == 0) {
        if (segmentWindy) return 'Veterno';
        return segment == BriefingDaySegment.afternoon ? 'Slnečno' : 'Jasno';
      }
      if (c == 1 || c == 2) {
        if (segmentWindy) return 'Veterno';
        return 'Polooblačno';
      }
      if (c == 3) {
        return segmentWindy ? 'Veterno' : 'Oblačno';
      }
    }

    if (segmentWindy) return 'Veterno';

    return 'Polooblačno';
  }

  /// Krátke štítky pre UI (bez „ráno/večer“ v texte — ten dáva riadok).
  static String briefingUiSk(String internalSlug) {
    switch (internalSlug) {
      case 'Slnečno':
        return 'Jasno';
      case 'Zamračené':
        return 'Oblačno';
      case 'Prehánky':
        return 'Dážď';
      case 'Búrka':
        return 'Búrky';
      case 'Mlhavo':
      case 'Sychravo':
        return 'Hmlisto';
      default:
        return internalSlug;
    }
  }

  static bool _briefingLabelIsWet(String s) {
    final t = s.trim();
    return t == 'Dážď' || t == 'Búrky';
  }

  /// Jedna hlavička pod Dnes/Zajtra — súlad ráno / poobedie / večer (nie jeden náhodný štítok).
  ///
  /// Postup: ak súčasne mokré a suché segmenty → „Premenlivé“. Inak väčšina (2× rovnaký štítok).
  /// Bez väčšiny: reprezentant **poobedie** (stred dňa).
  static String dailyHeadlineSk(String morning, String afternoon, String evening) {
    final m = morning.trim();
    final a = afternoon.trim();
    final e = evening.trim();
    final parts = <String>[m, a, e].where((s) => s.isNotEmpty).toList(growable: false);
    if (parts.isEmpty) return 'Polooblačno';

    final hasWet = parts.any(_briefingLabelIsWet);
    final hasDry = parts.any((s) => !_briefingLabelIsWet(s));
    if (hasWet && hasDry) {
      return 'Premenlivé';
    }

    final tally = <String, int>{};
    for (final p in parts) {
      tally[p] = (tally[p] ?? 0) + 1;
    }
    for (final entry in tally.entries) {
      if (entry.value >= 2) {
        return entry.key;
      }
    }

    if (a.isNotEmpty) return a;
    if (m.isNotEmpty) return m;
    return e;
  }
}
