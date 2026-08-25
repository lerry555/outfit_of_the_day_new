import 'date_weather_service.dart';

/// Clothing-relevant weather used when a Calendar outfit was generated,
/// or when comparing against the live Calendar chip.
class CalendarGenerationWeather {
  const CalendarGenerationWeather({
    required this.tempC,
    required this.isRainy,
    required this.isWindy,
    this.fromOpenMeteo,
    this.cityLabel,
    this.fetchedAt,
    this.dateKey,
  });

  final int tempC;
  final bool isRainy;
  final bool isWindy;
  final bool? fromOpenMeteo;
  final String? cityLabel;
  final DateTime? fetchedAt;
  final String? dateKey;

  bool get weatherProtectionRequired => isRainy || isWindy;

  factory CalendarGenerationWeather.fromSnapshot(DateWeatherSnapshot snap) {
    return CalendarGenerationWeather(
      tempC: snap.tempC,
      isRainy: snap.isRainy,
      isWindy: snap.isWindy,
      fromOpenMeteo: snap.fromOpenMeteo,
      cityLabel: snap.cityLabel,
      fetchedAt: snap.fetchedAt,
      dateKey: snap.dateKey,
    );
  }

  /// Null when a legacy document does not have enough clothing-weather
  /// evidence to compare confidently.
  static CalendarGenerationWeather? tryFromSavedJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    if (!json.containsKey('tempC') ||
        !json.containsKey('isRainy') ||
        !json.containsKey('isWindy')) {
      return null;
    }
    return CalendarGenerationWeather.fromSnapshot(
      DateWeatherSnapshot.fromJson(json),
    );
  }
}

enum CalendarWeatherStaleReason {
  temperature,
  rain,
  wind,
  location,
}

class CalendarWeatherStaleResult {
  const CalendarWeatherStaleResult._({
    required this.isStale,
    required this.comparable,
    required this.reasons,
  });

  final bool isStale;
  final bool comparable;
  final List<CalendarWeatherStaleReason> reasons;

  static const unknown = CalendarWeatherStaleResult._(
    isStale: false,
    comparable: false,
    reasons: [],
  );

  static const fresh = CalendarWeatherStaleResult._(
    isStale: false,
    comparable: true,
    reasons: [],
  );

  factory CalendarWeatherStaleResult.stale(
    Iterable<CalendarWeatherStaleReason> reasons,
  ) {
    return CalendarWeatherStaleResult._(
      isStale: true,
      comparable: true,
      reasons: List<CalendarWeatherStaleReason>.unmodifiable(reasons),
    );
  }
}

/// Deterministic Calendar stale-weather policy.
///
/// A change is material when it could reasonably change what someone wears.
/// Provenance-only shifts (Odhad → Predpoveď) and tiny temperature noise
/// are ignored. [fetchedAt] is never a stale criterion.
abstract final class CalendarWeatherStalePolicy {
  /// Conservative clothing threshold: 1°C is noise; 4°C can change layers.
  static const int significantTempDeltaC = 4;

  static CalendarWeatherStaleResult evaluate({
    required CalendarGenerationWeather? saved,
    required CalendarGenerationWeather current,
  }) {
    if (saved == null) return CalendarWeatherStaleResult.unknown;

    final reasons = <CalendarWeatherStaleReason>[];
    if ((current.tempC - saved.tempC).abs() >= significantTempDeltaC) {
      reasons.add(CalendarWeatherStaleReason.temperature);
    }
    if (current.isRainy != saved.isRainy) {
      reasons.add(CalendarWeatherStaleReason.rain);
    }
    if (current.isWindy != saved.isWindy) {
      reasons.add(CalendarWeatherStaleReason.wind);
    }

    final savedCity = cityIdentity(saved.cityLabel);
    final currentCity = cityIdentity(current.cityLabel);
    if (savedCity != null &&
        currentCity != null &&
        savedCity != currentCity) {
      reasons.add(CalendarWeatherStaleReason.location);
    }

    if (reasons.isEmpty) return CalendarWeatherStaleResult.fresh;
    return CalendarWeatherStaleResult.stale(reasons);
  }

  /// Short city identity: `"Martin, Slovakia"` and `"Martin"` are the same.
  static String? cityIdentity(String? label) {
    if (label == null) return null;
    var value = label.trim();
    if (value.isEmpty) return null;
    final comma = value.indexOf(',');
    if (comma > 0) value = value.substring(0, comma).trim();
    if (value.isEmpty) return null;
    return value.toLowerCase();
  }
}
