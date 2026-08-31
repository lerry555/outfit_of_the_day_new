import '../Services/hourly_weather_service.dart';
import 'slovak_city_locative.dart';
import 'stylist_activity_terrain.dart';

/// Krátke, konkrétne počasové tipy pre stylist chat (dáždnik, mokrá pôda…).
class StylistWeatherTipBuilder {
  const StylistWeatherTipBuilder._();

  /// True, keď po nedávnom daždi na tráve/hline treba radšej uzavretú obuv
  /// (tenisky/čižmy) než sandále — ovplyvní výber obuvi v outfite.
  static bool wetGroundNeedsClosedFootwear({
    required OutfitWeatherDaySnapshot snapshot,
    required DateTime now,
    required StylistActivityTerrain terrain,
    int? eventHour,
    bool antecedentPrecipitation = false,
  }) {
    if (terrain != StylistActivityTerrain.wetGround) return false;
    // A prior wet day remains material for trail/grass/forest footwear even
    // when the event starts dry.
    if (antecedentPrecipitation) return true;
    if (!snapshot.fromOpenMeteo || !snapshot.willRain) return false;

    final nowH = now.hour;
    final windows = _allRainWindows(snapshot.rainTimeText);
    final effectiveHour = eventHour ?? nowH;

    final inWindow = windows.any((w) => nowH >= w.start && nowH < w.end);
    if (inWindow) return true;

    final pastRecent = windows.any((w) => w.end <= nowH && w.end > nowH - 6);
    if (pastRecent) return true;

    return windows.any((w) => _hourInRainWindow(effectiveHour, w));
  }

  /// Rada o daždi podľa aktivity, aktuálneho času a toho, či user povedal návrat.
  ///
  /// Mestská prechádzka: minulý dážď nespomíname; len teraz / dážď počas výjazdu /
  /// večer ak nevie kedy sa vracia.
  /// Hory/tráva: minulý dážď = mokrá pôda + radšej uzavretá obuv.
  static String? rainAdviceForNow({
    required OutfitWeatherDaySnapshot snapshot,
    required DateTime now,
    int? eventHour,
    StylistActivityTerrain terrain = StylistActivityTerrain.urban,
    bool returnTimeKnown = false,
  }) {
    if (!snapshot.fromOpenMeteo || !snapshot.willRain) return null;

    final nowH = now.hour;
    final effectiveHour = eventHour ?? nowH;
    final windows = _allRainWindows(snapshot.rainTimeText);

    final inWindow = windows.any((w) => nowH >= w.start && nowH < w.end);
    final rainDuringOuting = windows.any(
      (w) => _hourInRainWindow(effectiveHour, w) || (w.start > nowH && w.start <= effectiveHour + 2),
    );
    final futureWindows = windows.where((w) => w.start > nowH).toList();
    final pastWindows = windows.where((w) => w.end <= nowH).toList();
    final eveningRainLater = _eveningRainExpected(snapshot, nowH, futureWindows);

    // --- Teraz prší ---
    if (inWindow) {
      if (terrain == StylistActivityTerrain.wetGround) {
        return 'Teraz prší — po tráve a hline môže byť mokro, '
            'nezabudni dáždnik a radšej uzavretú obuv než sandále.';
      }
      return 'Teraz vonku prší — nezabudni si dáždnik.';
    }

    final parts = <String>[];

    // --- Budúci dážď počas výjazdu (relevantné pre obe aktivity) ---
    if (futureWindows.isNotEmpty && (rainDuringOuting || eventHour != null)) {
      final relevant = futureWindows.firstWhere(
        (w) => eventHour == null || _hourInRainWindow(effectiveHour, w) || w.start >= effectiveHour,
        orElse: () => futureWindows.first,
      );
      if (eventHour == null || relevant.start <= effectiveHour + 1 || _hourInRainWindow(effectiveHour, relevant)) {
        parts.add(
          'Okolo ${relevant.start}:00 sa očakáva dážď — zober si dáždnik.',
        );
      }
    } else if (futureWindows.isNotEmpty &&
        eventHour == null &&
        terrain == StylistActivityTerrain.urban &&
        futureWindows.first.start <= nowH + 3) {
      // Mesto, „teraz idem von“ — spomeň len blízky budúci dážď (do ~3 hodín).
      parts.add(
        'Okolo ${futureWindows.first.start}:00 môže pršať — dáždnik sa môže hodiť.',
      );
    }

    // --- Minulý dážď: LEN pri mokrej pôde (hory, tráva) ---
    if (terrain == StylistActivityTerrain.wetGround && pastWindows.isNotEmpty) {
      parts.add(
        'Pred chvíľou pršalo — na tráve a hline môže byť ešte mokro, '
        'radšej tenisky alebo uzavretú obuv než sandále.',
      );
    }

    // --- Večerný dážď: ak user nepovedal, kedy sa vracia ---
    if (!returnTimeKnown && eveningRainLater && nowH < 20) {
      parts.add(
        'Večer môže prísť dážď — ak budeš vonku dlhšie, zober si dáždnik.',
      );
    }

    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  static bool _eveningRainExpected(
    OutfitWeatherDaySnapshot snapshot,
    int nowH,
    List<({int start, int end})> futureWindows,
  ) {
    if (futureWindows.any((w) => w.start >= 18)) return true;
    if (snapshot.eveningRainSegment && nowH < 18) return true;
    return false;
  }

  static List<({int start, int end})> _allRainWindows(String? rainTimeText) {
    if (rainTimeText == null || rainTimeText.trim().isEmpty) return const [];
    final windows = <({int start, int end})>[];
    for (final match in RegExp(r'(\d{1,2}):\d{2}-(\d{1,2}):\d{2}')
        .allMatches(rainTimeText)) {
      final start = int.tryParse(match.group(1) ?? '');
      final end = int.tryParse(match.group(2) ?? '');
      if (start == null || end == null) continue;
      if (start < 0 || end > 24 || end <= start) continue;
      windows.add((start: start, end: end));
    }
    return windows;
  }

  static String? outfitContextLine({
    required OutfitWeatherDaySnapshot snapshot,
    required int? eventHour,
    required String locationLabel,
    required bool isTomorrow,
    required bool isSmartCasual,
    String smartCasualPhrase = 'smart-casual',
    DateTime? now,
    StylistActivityTerrain terrain = StylistActivityTerrain.urban,
  }) {
    if (!snapshot.fromOpenMeteo && locationLabel.trim().isEmpty) return null;

    final place = locationLabel.split(',').first.trim();
    final placePhrase =
        place.isNotEmpty ? SlovakCityLocative.inCity(place) : '';
    final hour = eventHour;
    final buffer = StringBuffer();

    if (placePhrase.isNotEmpty && hour != null) {
      if (isTomorrow) {
        buffer.write('Zajtra $placePhrase okolo $hour:00');
      } else {
        buffer.write('$placePhrase okolo $hour:00');
      }
    } else if (placePhrase.isNotEmpty) {
      buffer.write(isTomorrow ? 'Zajtra $placePhrase' : placePhrase);
    } else if (hour != null) {
      buffer.write('Okolo $hour:00');
    }

    if (buffer.isEmpty) return null;

    if (snapshot.fromOpenMeteo) {
      final effectiveNow = now ?? DateTime.now();
      final effectiveHour = eventHour ?? effectiveNow.hour;
      if (snapshot.willRain && _rainLikelyAtHour(snapshot, effectiveHour)) {
        final windows = _allRainWindows(snapshot.rainTimeText);
        final inWindow = windows.any(
          (w) => effectiveNow.hour >= w.start && effectiveNow.hour < w.end,
        );
        final pastOnly = windows.isNotEmpty &&
            windows.every((w) => w.end <= effectiveNow.hour) &&
            terrain == StylistActivityTerrain.urban;
        if (pastOnly) {
          buffer.write(' by to malo sedieť');
        } else if (inWindow) {
          buffer.write(' môže pršať');
        } else if (effectiveHour > effectiveNow.hour) {
          buffer.write(' očakávaj dážď');
        } else {
          buffer.write(' by to malo sedieť');
        }
      } else if (snapshot.willRain) {
        buffer.write(' môžu sa vyskytnúť prehánky');
      } else {
        buffer.write(' by to malo sedieť');
      }
    } else {
      buffer.write(' — počasie sa mi nepodarilo overiť, outfit ber ako návrh');
    }

    if (isSmartCasual) {
      buffer.write(' — $smartCasualPhrase');
    }
    buffer.write('.');
    return buffer.toString();
  }

  static bool _rainLikelyAtHour(OutfitWeatherDaySnapshot snapshot, int? hour) {
    if (hour == null) return snapshot.willRain;
    final window = _firstRainWindow(snapshot.rainTimeText);
    if (window != null && _hourInRainWindow(hour, window)) return true;
    if (hour >= 5 && hour <= 11) return snapshot.morningRainSegment;
    if (hour >= 12 && hour <= 17) return snapshot.afternoonRainSegment;
    return snapshot.eveningRainSegment;
  }

  static String? outfitAddon({
    required OutfitWeatherDaySnapshot snapshot,
    int? eventHour,
    DateTime? now,
    StylistActivityTerrain terrain = StylistActivityTerrain.urban,
    bool returnTimeKnown = false,
  }) {
    if (!snapshot.fromOpenMeteo) return null;
    final advice = rainAdviceForNow(
      snapshot: snapshot,
      now: now ?? DateTime.now(),
      eventHour: eventHour,
      terrain: terrain,
      returnTimeKnown: returnTimeKnown,
    );
    if (advice == null || advice.isEmpty) return null;
    return advice;
  }

  static String? temperatureChatReply({
    required OutfitWeatherDaySnapshot snapshot,
    int? eventHour,
    String? locationLabel,
    String? conversationText,
    bool returnTimeKnown = false,
  }) {
    if (!snapshot.fromOpenMeteo) return null;

    final terrain = StylistActivityTerrainClassifier.classify(
      conversationText: conversationText,
    );
    final hour = eventHour;
    final temp = _tempForHour(snapshot, hour);
    final place = (locationLabel ?? snapshot.cityName).split(',').first.trim();
    final placePhrase = place.isNotEmpty ? SlovakCityLocative.inCity(place) : '';
    final now = DateTime.now();
    final isToday = snapshot.date.year == now.year &&
        snapshot.date.month == now.month &&
        snapshot.date.day == now.day;
    final buffer = StringBuffer();

    if (hour != null) {
      if (placePhrase.isNotEmpty) {
        buffer.write('$placePhrase okolo $hour:00 bude približne $temp °C');
      } else {
        buffer.write('Okolo $hour:00 bude približne $temp °C');
      }
    } else if (isToday) {
      if (placePhrase.isNotEmpty) {
        buffer.write('$placePhrase je teraz okolo ${snapshot.mainChipTempC} °C');
      } else {
        buffer.write('Teraz je okolo ${snapshot.mainChipTempC} °C');
      }
    } else if (snapshot.morningTempC != null) {
      buffer.write('Ráno bude okolo ${snapshot.morningTempC} °C');
      if (placePhrase.isNotEmpty) buffer.write(' $placePhrase');
    } else {
      buffer.write('Teplota bude okolo $temp °C');
      if (placePhrase.isNotEmpty) buffer.write(' $placePhrase');
    }
    buffer.write('.');

    final rainLine = rainAdviceForNow(
      snapshot: snapshot,
      now: DateTime.now(),
      eventHour: eventHour,
      terrain: terrain,
      returnTimeKnown: returnTimeKnown,
    );
    if (rainLine != null) {
      buffer.write(' $rainLine');
    }

    return buffer.toString().trim();
  }

  static bool _hourInRainWindow(int hour, ({int start, int end})? window) {
    if (window == null) return false;
    return hour >= window.start && hour < window.end;
  }

  static ({int start, int end})? _firstRainWindow(String? rainTimeText) {
    final all = _allRainWindows(rainTimeText);
    if (all.isEmpty) return null;
    return all.first;
  }

  static int _tempForHour(OutfitWeatherDaySnapshot snapshot, int? hour) {
    if (hour == null) return snapshot.mainChipTempC;
    if (hour >= 5 && hour < 12) {
      return snapshot.morningTempC ?? snapshot.noonTempC ?? snapshot.mainChipTempC;
    }
    if (hour >= 12 && hour < 18) {
      return snapshot.noonTempC ?? snapshot.eveningTempC ?? snapshot.mainChipTempC;
    }
    return snapshot.eveningTempC ?? snapshot.noonTempC ?? snapshot.mainChipTempC;
  }

  /// Ľudsky znejúce zhrnutie dňa pre AI chat — jedna-dve vety, nie surové segmenty.
  static String? naturalDaySummarySk({
    required OutfitWeatherDaySnapshot snapshot,
    required String locationLabel,
    required bool isTomorrow,
    int? eventHour,
    StylistActivityTerrain terrain = StylistActivityTerrain.urban,
    bool includeRain = true,
  }) {
    if (!snapshot.fromOpenMeteo) return null;

    final place = locationLabel.split(',').first.trim();
    final minT = snapshot.minTempC ??
        snapshot.morningTempC ??
        snapshot.noonTempC ??
        snapshot.mainChipTempC;
    final maxT = snapshot.maxTempC ??
        snapshot.noonTempC ??
        snapshot.eveningTempC ??
        snapshot.mainChipTempC;

    final buffer = StringBuffer();
    if (place.isNotEmpty) {
      if (terrain == StylistActivityTerrain.wetGround) {
        buffer.write(
          isTomorrow ? 'Zajtra v okolí $place' : 'V okolí $place',
        );
      } else {
        buffer.write(
          isTomorrow
              ? 'Zajtra ${SlovakCityLocative.inCity(place)}'
              : SlovakCityLocative.inCity(place),
        );
      }
    } else {
      buffer.write(isTomorrow ? 'Zajtra' : 'Dnes');
    }

    if (minT != null && maxT != null && minT != maxT) {
      buffer.write(' bude približne $minT–$maxT °C');
    } else {
      final t = snapshot.noonTempC ?? snapshot.mainChipTempC;
      buffer.write(' bude okolo $t °C');
    }

    if (includeRain && snapshot.willRain) {
      final rainPhrase = _compactRainPhrase(
        snapshot: snapshot,
        eventHour: eventHour,
        terrain: terrain,
      );
      if (rainPhrase != null) {
        buffer.write('. $rainPhrase');
      }
    } else if (!snapshot.willRain) {
      buffer.write(', sucho');
    }

    buffer.write('.');
    return buffer.toString();
  }

  static String? _compactRainPhrase({
    required OutfitWeatherDaySnapshot snapshot,
    int? eventHour,
    StylistActivityTerrain terrain = StylistActivityTerrain.urban,
  }) {
    final windows = _allRainWindows(snapshot.rainTimeText);
    if (windows.isNotEmpty) {
      final relevant = eventHour != null
          ? windows.firstWhere(
              (w) => _hourInRainWindow(eventHour, w),
              orElse: () => windows.first,
            )
          : windows.firstWhere(
              (w) => w.start >= 11 && w.start < 18,
              orElse: () => windows.first,
            );
      if (terrain == StylistActivityTerrain.wetGround) {
        return 'Okolo ${relevant.start}:00 sa môžu vyskytnúť prehánky — v teréne môže byť mokro';
      }
      return 'Okolo ${relevant.start}:00 sa môžu vyskytnúť prehánky';
    }

    if (snapshot.afternoonRainSegment) {
      if (terrain == StylistActivityTerrain.wetGround) {
        return 'Poobede sa môžu vyskytnúť prehánky — v teréne môže byť mokro';
      }
      return 'Poobede sa môžu vyskytnúť prehánky';
    }
    if (snapshot.morningRainSegment && !snapshot.afternoonRainSegment) {
      return 'Ráno sa môžu vyskytnúť prehánky';
    }
    if (snapshot.eveningRainSegment &&
        eventHour != null &&
        eventHour >= 17) {
      return 'Večer môže pršať';
    }
    return 'Občas sa môžu vyskytnúť prehánky';
  }
}
