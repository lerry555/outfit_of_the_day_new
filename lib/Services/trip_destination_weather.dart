import 'calendar_weather_resolver.dart';
import 'hourly_weather_service.dart';

/// Real Open-Meteo day used by Trip before synthetic fallback is applied.
class TripOpenMeteoDay {
  const TripOpenMeteoDay({
    required this.date,
    required this.highTempC,
    required this.lowTempC,
    required this.conditionSk,
    required this.isRainy,
    required this.isWindy,
  });

  final DateTime date;
  final int highTempC;
  final int lowTempC;
  final String conditionSk;
  final bool isRainy;
  final bool isWindy;
}

/// Per-stay-day weather after real-or-fallback resolution.
class TripResolvedDayWeather {
  const TripResolvedDayWeather({
    required this.date,
    required this.highTempC,
    required this.lowTempC,
    required this.conditionSk,
    required this.forecastAvailable,
    required this.sourceLabelSk,
    required this.isRainy,
    required this.isWindy,
  });

  final DateTime date;
  final int highTempC;
  final int lowTempC;
  final String conditionSk;
  final bool forecastAvailable;
  final String sourceLabelSk;
  final bool isRainy;
  final bool isWindy;

  String get dateKey => CalendarWeatherMapper.dateKey(date);
}

/// Fetches only days that actually have Open-Meteo hourly data.
abstract class TripDestinationWeatherSource {
  Future<Map<String, TripOpenMeteoDay>> fetchRealForecastDays({
    required double latitude,
    required double longitude,
    required List<DateTime> dates,
    String? locationLabel,
  });
}

/// Reuses [HourlyWeatherService] coordinate+window fetch. Does not geocode.
class HourlyTripDestinationWeatherSource implements TripDestinationWeatherSource {
  HourlyTripDestinationWeatherSource([HourlyWeatherService? weatherService])
    : _weatherService = weatherService ?? HourlyWeatherService();

  final HourlyWeatherService _weatherService;

  @override
  Future<Map<String, TripOpenMeteoDay>> fetchRealForecastDays({
    required double latitude,
    required double longitude,
    required List<DateTime> dates,
    String? locationLabel,
  }) async {
    final snaps = await _weatherService.getOpenMeteoForCoordinatesAndDates(
      latitude: latitude,
      longitude: longitude,
      dates: dates,
      locationLabel: locationLabel ?? '',
    );
    final out = <String, TripOpenMeteoDay>{};
    snaps.forEach((key, snap) {
      if (!snap.fromOpenMeteo) return;
      final high = snap.maxTempC ?? snap.mainChipTempC;
      final low = snap.minTempC ?? snap.eveningTempC ?? high;
      out[key] = TripOpenMeteoDay(
        date: snap.date,
        highTempC: high,
        lowTempC: low,
        conditionSk: snap.briefingAfternoonCondition,
        isRainy: snap.willRain,
        isWindy: snap.isWindy,
      );
    });
    return out;
  }
}
