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
}
