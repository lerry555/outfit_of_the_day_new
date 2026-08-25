import 'date_weather_service.dart';
import 'hourly_weather_service.dart';
import 'user_location_service.dart';

/// Maps HourlyWeatherService results into Calendar's [DateWeatherSnapshot]
/// and decides Predpoveď vs Odhad from Open-Meteo provenance only.
abstract final class CalendarWeatherMapper {
  static const forecastLabel = 'Predpoveď';
  static const estimateLabel = 'Odhad';

  static String dateKey(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final y = normalized.year.toString().padLeft(4, '0');
    final m = normalized.month.toString().padLeft(2, '0');
    final d = normalized.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateWeatherSnapshot fromHourlySnapshot(
    OutfitWeatherDaySnapshot snap, {
    String? cityLabel,
    DateTime? fetchedAt,
  }) {
    final seasonal = DateWeatherService.getFallbackWeatherForDate(snap.date);
    return _labeled(
      date: snap.date,
      tempC: snap.mainChipTempC,
      isRainy: snap.willRain,
      isWindy: snap.isWindy,
      seasonLabel: seasonal.seasonLabel,
      seasonKey: seasonal.seasonKey,
      fromOpenMeteo: snap.fromOpenMeteo,
      cityLabel: _resolvedCityLabel(cityLabel, snap.cityName),
      fetchedAt: fetchedAt,
      eveningTempC: snap.eveningTempC,
    );
  }

  /// Seasonal heuristic with an honest estimate label. Never "Predpoveď".
  static DateWeatherSnapshot fromFallbackDate(
    DateTime date, {
    String? cityLabel,
    DateTime? fetchedAt,
  }) {
    final seasonal = DateWeatherService.getFallbackWeatherForDate(date);
    return _labeled(
      date: date,
      tempC: seasonal.tempC,
      isRainy: seasonal.isRainy,
      isWindy: seasonal.isWindy,
      seasonLabel: seasonal.seasonLabel,
      seasonKey: seasonal.seasonKey,
      fromOpenMeteo: false,
      cityLabel: _resolvedCityLabel(cityLabel, null),
      fetchedAt: fetchedAt,
    );
  }

  static String? _resolvedCityLabel(String? preferred, String? fallback) {
    final primary = preferred?.trim() ?? '';
    if (primary.isNotEmpty) return primary;
    final secondary = fallback?.trim() ?? '';
    return secondary.isEmpty ? null : secondary;
  }

  static DateWeatherSnapshot _labeled({
    required DateTime date,
    required int tempC,
    required bool isRainy,
    required bool isWindy,
    required String seasonLabel,
    required String seasonKey,
    required bool fromOpenMeteo,
    String? cityLabel,
    DateTime? fetchedAt,
    int? eveningTempC,
  }) {
    final parts = <String>[seasonLabel, '$tempC°C'];
    if (isWindy) parts.add('vietor');
    if (isRainy) parts.add('dážď');
    if (!isWindy && !isRainy) parts.add('jasno');
    return DateWeatherSnapshot(
      tempC: tempC,
      isRainy: isRainy,
      isWindy: isWindy,
      seasonLabel: seasonLabel,
      seasonKey: seasonKey,
      forecastAvailable: fromOpenMeteo,
      sourceLabel: fromOpenMeteo ? forecastLabel : estimateLabel,
      summarySubtitle: parts.join(' • '),
      fromOpenMeteo: fromOpenMeteo,
      cityLabel: cityLabel,
      fetchedAt: fetchedAt ?? DateTime.now(),
      dateKey: dateKey(date),
      eveningTempC: eveningTempC,
    );
  }
}

/// Resolves Calendar weather through Home's location + Open-Meteo stack.
class CalendarWeatherResolver {
  CalendarWeatherResolver({
    HourlyWeatherService? weatherService,
    Future<void> Function()? ensureLocationResolved,
    String Function()? resolvedCityLabel,
  }) : _weatherService = weatherService ?? HourlyWeatherService(),
       _ensureLocationResolved =
           ensureLocationResolved ??
           (() => UserLocationService.instance.ensureResolved()),
       _resolvedCityLabel =
           resolvedCityLabel ??
           (() => UserLocationService.instance.cityLabel);

  final HourlyWeatherService _weatherService;
  final Future<void> Function() _ensureLocationResolved;
  final String Function() _resolvedCityLabel;

  Future<DateWeatherSnapshot> resolveForDate(DateTime date) async {
    final normalized = DateTime(date.year, date.month, date.day);
    String city = '';
    try {
      await _ensureLocationResolved();
      city = _resolvedCityLabel().trim();
      final requestCity = city.isEmpty
          ? HourlyWeatherService.defaultWeatherCityShortLabel
          : city;
      final hourly = await _weatherService.getWeatherForCityAndDate(
        city: requestCity,
        date: normalized,
      );
      return CalendarWeatherMapper.fromHourlySnapshot(
        hourly,
        cityLabel: requestCity,
      );
    } catch (_) {
      return CalendarWeatherMapper.fromFallbackDate(
        normalized,
        cityLabel: city.isEmpty
            ? HourlyWeatherService.defaultWeatherCityShortLabel
            : city,
      );
    }
  }
}
