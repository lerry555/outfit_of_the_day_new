import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import 'airport_record.dart';
import 'flight_duration_estimator.dart';
import 'trip_flight_models.dart';

/// Výsledok odhadu príletu (nie letové poriadky).
class FlightArrivalEstimate {
  /// Lokálny „stena“ čas na letisku príchodu (bez DateTime.zoneName), ak je známe pásma cieľa.
  final DateTime? estimatedArrivalLocalNaive;
  final String? estimatedArrivalTimezoneIana;
  final TripTimezoneConfidence timezoneConfidence;
  final FlightDurationEstimate duration;
  final String? extraWarningSk;

  const FlightArrivalEstimate({
    required this.estimatedArrivalLocalNaive,
    required this.estimatedArrivalTimezoneIana,
    required this.timezoneConfidence,
    required this.duration,
    this.extraWarningSk,
  });
}

abstract final class FlightArrivalEstimator {
  FlightArrivalEstimator._();

  /// [departureWallClock] — komponenty z pickera; ak je známe [from.timezone], interpretujeme ako lokálny čas na odletovom letisku.
  static FlightArrivalEstimate estimate({
    required AirportRecord from,
    required AirportRecord to,
    required DateTime departureWallClock,
  }) {
    final dur = FlightDurationEstimator.estimate(from: from, to: to);

    final fromTz = from.timezone?.trim();
    final toTz = to.timezone?.trim();

    late final tz.TZDateTime depAtFrom;
    var depKnown = false;

    if (fromTz != null && fromTz.isNotEmpty) {
      try {
        final locFrom = tz.getLocation(fromTz);
        depAtFrom = tz.TZDateTime(
          locFrom,
          departureWallClock.year,
          departureWallClock.month,
          departureWallClock.day,
          departureWallClock.hour,
          departureWallClock.minute,
        );
        depKnown = true;
      } catch (e, st) {
        debugPrint('[FLIGHT_ARRIVAL] bad departure TZ "$fromTz" $e\n$st');
        depAtFrom = tz.TZDateTime.utc(
          departureWallClock.year,
          departureWallClock.month,
          departureWallClock.day,
          departureWallClock.hour,
          departureWallClock.minute,
        );
      }
    } else {
      depAtFrom = tz.TZDateTime.utc(
        departureWallClock.year,
        departureWallClock.month,
        departureWallClock.day,
        departureWallClock.hour,
        departureWallClock.minute,
      );
    }

    final arrivalInstant = depAtFrom.add(Duration(minutes: dur.estimatedDurationMinutes));

    DateTime? localNaive;
    String? usedToTz = toTz;
    TripTimezoneConfidence tzConf = TripTimezoneConfidence.unknown;
    String? extra;

    if (toTz != null && toTz.isNotEmpty) {
      try {
        final locTo = tz.getLocation(toTz);
        final wall = tz.TZDateTime.from(arrivalInstant.toUtc(), locTo);
        localNaive = DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute);
        tzConf = TripTimezoneConfidence.known;
      } catch (e, st) {
        debugPrint('[FLIGHT_ARRIVAL] bad arrival TZ "$toTz" $e\n$st');
        localNaive = null;
      }
    }

    if (localNaive == null && fromTz != null && fromTz.isNotEmpty) {
      try {
        final locFrom = tz.getLocation(fromTz);
        final wall = tz.TZDateTime.from(arrivalInstant.toUtc(), locFrom);
        localNaive = DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute);
        tzConf = TripTimezoneConfidence.fallback;
        usedToTz = fromTz;
        extra = 'Čas príchodu je zobrazený v časovom pásme odletu (pásma cieľa sa nepodarilo načítať).';
      } catch (_) {}
    }

    if (localNaive == null) {
      final utc = arrivalInstant.toUtc();
      localNaive = DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
      tzConf = TripTimezoneConfidence.unknown;
      usedToTz = null;
      extra = 'Čas príchodu je len orientačný (chýba spoľahlivý prevod do lokálneho času cieľa).';
    } else if (!depKnown) {
      extra = 'Odlet bol dopočítaný bez presného časového pásma letiska (predpoklad UTC).';
      if (tzConf == TripTimezoneConfidence.known) {
        tzConf = TripTimezoneConfidence.fallback;
      }
    }

    if (kDebugMode) {
      debugPrint(
        '[FLIGHT_ARRIVAL] dep=${from.iata} arr=${to.iata} depKnown=$depKnown '
        'estArrLocal=$localNaive tz=$usedToTz tzConf=$tzConf durationMin=${dur.estimatedDurationMinutes}',
      );
    }

    return FlightArrivalEstimate(
      estimatedArrivalLocalNaive: localNaive,
      estimatedArrivalTimezoneIana: usedToTz,
      timezoneConfidence: tzConf,
      duration: dur,
      extraWarningSk: extra,
    );
  }
}
