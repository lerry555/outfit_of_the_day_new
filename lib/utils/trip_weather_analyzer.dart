import '../Services/hourly_weather_service.dart';
import '../models/stylist_trip_window.dart';

/// Počasie pre celé časové okno výletu (nie jednu hodinu).
class TripWeatherSummary {
  final int tripStartHour;
  final int tripEndHour;
  final int eventStartHour;
  final int minTempC;
  final int maxTempC;
  final int outfitTempC;
  final bool rainDuringTrip;
  final bool rainBeforeEvent;
  final bool rainDuringEvent;
  final bool rainOnReturn;
  final String? rainTimeText;
  final String advisorySk;

  const TripWeatherSummary({
    required this.tripStartHour,
    required this.tripEndHour,
    required this.eventStartHour,
    required this.minTempC,
    required this.maxTempC,
    required this.outfitTempC,
    required this.rainDuringTrip,
    required this.rainBeforeEvent,
    required this.rainDuringEvent,
    required this.rainOnReturn,
    this.rainTimeText,
    required this.advisorySk,
  });

  Map<String, dynamic> toWeatherContextPayload() => <String, dynamic>{
        'tripStartHour': tripStartHour,
        'tripEndHour': tripEndHour,
        'eventStartHour': eventStartHour,
        'tripMinTempC': minTempC,
        'tripMaxTempC': maxTempC,
        'tripOutfitTempC': outfitTempC,
        'rainDuringTrip': rainDuringTrip,
        'rainBeforeEvent': rainBeforeEvent,
        'rainDuringEvent': rainDuringEvent,
        'rainOnReturn': rainOnReturn,
        if (rainTimeText != null) 'rainTimeText': rainTimeText,
        'tripWeatherAdvisory': advisorySk,
      };
}

class TripWeatherAnalyzer {
  const TripWeatherAnalyzer._();

  static TripWeatherSummary analyze({
    required OutfitWeatherDaySnapshot day,
    required StylistTripWindow window,
    bool timeKnown = true,
  }) {
    // Keď používateľ nezadal čas, nevymýšľame poludňajšie okno ani tvrdenia
    // „pred/počas udalosti“. Skenujeme bežný denný rozsah a dávame všeobecnú radu.
    final start = timeKnown ? window.effectiveTripStart : 8;
    final end = timeKnown ? window.effectiveTripEnd : 20;
    final eventStart = window.effectiveEventStart;
    final eventEnd = window.effectiveEventEnd;

    final temps = <int>[];
    for (var h = start; h <= end; h++) {
      final t = _tempEstimateForHour(day, h);
      if (t != null) temps.add(t);
    }
    if (temps.isEmpty) {
      temps.add(day.mainChipTempC);
    }

    final minT = temps.reduce((a, b) => a < b ? a : b);
    final maxT = temps.reduce((a, b) => a > b ? a : b);
    final eventTemp = _tempEstimateForHour(day, eventStart) ?? day.mainChipTempC;
    final outfitTemp = ((minT + eventTemp) / 2).round();

    final rainBefore = timeKnown &&
        _rainInRange(day, start, eventStart > start ? eventStart - 1 : start);
    final rainEvent = timeKnown && _rainInRange(day, eventStart, eventEnd);
    final rainReturn = timeKnown &&
        eventEnd < end &&
        _rainInRange(day, eventEnd + 1, end);
    final rainTrip = timeKnown
        ? (rainBefore || rainEvent || rainReturn || day.willRain)
        : day.willRain;

    final advisory = timeKnown
        ? _buildAdvisory(
            day: day,
            start: start,
            end: end,
            eventStart: eventStart,
            minT: minT,
            maxT: maxT,
            rainBefore: rainBefore,
            rainEvent: rainEvent,
            rainReturn: rainReturn,
            tripEndEstimated: window.tripEndEstimated,
          )
        : _buildGeneralAdvisory(day: day, minT: minT, maxT: maxT);

    return TripWeatherSummary(
      tripStartHour: start,
      tripEndHour: end,
      eventStartHour: eventStart,
      minTempC: minT,
      maxTempC: maxT,
      outfitTempC: outfitTemp,
      rainDuringTrip: rainTrip,
      rainBeforeEvent: rainBefore,
      rainDuringEvent: rainEvent,
      rainOnReturn: rainReturn,
      rainTimeText: day.rainTimeText,
      advisorySk: advisory,
    );
  }

  static int? tempAtHour(OutfitWeatherDaySnapshot day, int hour) {
    final exact = day.tempAtLocalHour(hour);
    if (exact != null) return exact;
    if (hour >= 5 && hour < 12) {
      return day.morningTempC ?? day.noonTempC ?? day.mainChipTempC;
    }
    if (hour >= 12 && hour < 18) {
      return day.noonTempC ?? day.eveningTempC ?? day.mainChipTempC;
    }
    return day.eveningTempC ?? day.noonTempC ?? day.mainChipTempC;
  }

  static int? _tempEstimateForHour(OutfitWeatherDaySnapshot day, int hour) {
    return tempAtHour(day, hour);
  }

  static bool _rainInRange(OutfitWeatherDaySnapshot day, int fromH, int toH) {
    if (!day.fromOpenMeteo || !day.willRain) return false;
    if (fromH > toH) return false;
    for (var h = fromH; h <= toH; h++) {
      if (h >= 5 && h < 12 && day.morningRainSegment) return true;
      if (h >= 12 && h < 18 && day.afternoonRainSegment) return true;
      if (h >= 18 && h <= 23 && day.eveningRainSegment) return true;
    }
    final rainText = (day.rainTimeText ?? '').toLowerCase();
    if (rainText.isEmpty) return false;
    final hourMatch = RegExp(r'(\d{1,2})').allMatches(rainText);
    for (final m in hourMatch) {
      final h = int.tryParse(m.group(1) ?? '');
      if (h != null && h >= fromH && h <= toH) return true;
    }
    return false;
  }

  static String _buildAdvisory({
    required OutfitWeatherDaySnapshot day,
    required int start,
    required int end,
    required int eventStart,
    required int minT,
    required int maxT,
    required bool rainBefore,
    required bool rainEvent,
    required bool rainReturn,
    required bool tripEndEstimated,
  }) {
    if (!day.fromOpenMeteo) {
      return 'Počasie na celý výlet sa mi nepodarilo overiť — outfit ber ako návrh.';
    }

    final buffer = StringBuffer();
    if (start != eventStart) {
      buffer.write('Od $start:00 do $end:00');
    } else {
      buffer.write('Okolo $eventStart:00');
    }
    buffer.write(' teplota približne $minT–$maxT °C');

    if (rainBefore) {
      buffer.write('; pred udalosťou môže pršať — zober si dáždnik už pri odchode');
    }
    if (rainEvent && !rainBefore) {
      buffer.write('; počas udalosti môže pršať — zíde sa dáždnik');
    }
    if (rainReturn) {
      buffer.write('; na návrate večer môže pršať alebo bude chladnejšie (~$minT °C)');
    } else if (minT + 4 <= maxT) {
      buffer.write('; večer bude chladnejšie (~$minT °C)');
    }

    if (tripEndEstimated) {
      buffer.write(' (návrat odhadujem okolo $end:00 — ak budeš vonku dlhšie, napíš)');
    }
    buffer.write('.');
    return buffer.toString();
  }

  /// Všeobecná rada pre prípad, že čas nepoznáme: žiadne „pred/počas udalosti“,
  /// žiadna bunda — len denný teplotný rozsah a (pri daždi) dáždnik.
  static String _buildGeneralAdvisory({
    required OutfitWeatherDaySnapshot day,
    required int minT,
    required int maxT,
  }) {
    if (!day.fromOpenMeteo) {
      return 'Počasie sa mi nepodarilo overiť — outfit ber ako návrh.';
    }
    final buffer = StringBuffer('Cez deň bude teplota približne $minT–$maxT °C');
    if (day.willRain) {
      buffer.write('; cez deň môže pršať, tak si pre istotu zober dáždnik');
    } else if (minT + 4 <= maxT) {
      buffer.write('; večer býva chladnejšie (~$minT °C)');
    }
    buffer.write('.');
    return buffer.toString();
  }
}
