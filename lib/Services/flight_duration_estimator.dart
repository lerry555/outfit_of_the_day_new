import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'airport_record.dart';

/// Spoľahlivosť heuristického odhadu (nie letové poriadky).
enum FlightEstimateConfidence {
  high,
  medium,
  low,
}

/// Haversine + heuristika trvania letu podľa vzdialenosti (bez reálnych letov).
abstract final class FlightDurationEstimator {
  FlightDurationEstimator._();

  static double greatCircleDistanceKm({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const r = 6371.0;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dp = (lat2 - lat1) * math.pi / 180;
    final dl = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  /// Odhad block-time (taxi, vzlet, pristátie, taxenie) — nie block z airline schedules.
  static FlightDurationEstimate estimate({
    required AirportRecord from,
    required AirportRecord to,
  }) {
    final km = greatCircleDistanceKm(
      lat1: from.lat,
      lon1: from.lon,
      lat2: to.lat,
      lon2: to.lon,
    );

    late final double speedKmh;
    late final int bufferMin;
    FlightEstimateConfidence conf;
    String? warning;

    if (km < 800) {
      speedKmh = 580;
      bufferMin = 30;
      conf = FlightEstimateConfidence.high;
    } else if (km < 3500) {
      speedKmh = 820;
      bufferMin = 30;
      conf = FlightEstimateConfidence.medium;
    } else if (km < 8000) {
      speedKmh = 870;
      bufferMin = 75;
      conf = FlightEstimateConfidence.medium;
    } else {
      speedKmh = 880;
      bufferMin = 120;
      conf = FlightEstimateConfidence.low;
      warning =
          'Ak ti čas nesedí napríklad kvôli prestupom, môžeš ho upraviť manuálne.';
    }

    final cruiseHours = km / speedKmh;
    final int totalMin = (cruiseHours * 60).ceil() + bufferMin;

    if (km >= 3500 && warning == null) {
      warning = 'Pri tejto trase môže reálny čas závisieť od konkrétneho letu.';
    }

    if (kDebugMode) {
      debugPrint(
        '[FLIGHT_DURATION] ${from.iata}->${to.iata} distKm=${km.toStringAsFixed(1)} '
        'estMin=$totalMin conf=$conf',
      );
    }

    return FlightDurationEstimate(
      distanceKm: km,
      estimatedDurationMinutes: totalMin,
      confidence: conf,
      warningText: warning,
    );
  }
}

class FlightDurationEstimate {
  final double distanceKm;
  final int estimatedDurationMinutes;
  final FlightEstimateConfidence confidence;
  final String? warningText;

  const FlightDurationEstimate({
    required this.distanceKm,
    required this.estimatedDurationMinutes,
    required this.confidence,
    this.warningText,
  });
}
