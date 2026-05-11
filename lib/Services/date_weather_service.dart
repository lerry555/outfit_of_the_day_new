/// Deterministic, production-safe weather snapshot generator.
///
/// The current codebase already uses a local fallback weather logic inside
/// `HomeScreen`. Calendar needs a shared, reusable helper for day-specific UI.
///
/// This implementation:
/// - creates weather based on the calendar date (season + deterministic deltas)
/// - marks near-future dates as "predpoveď" (forecast-like)
/// - marks older/farther dates as "odhad" (graceful fallback)
///
/// Note: If you later plug in a real weather API, this file is the only place
/// you should need to update.
library date_weather_service;

class DateWeatherSnapshot {
  final int tempC;
  final bool isRainy;
  final bool isWindy;
  final String seasonLabel; // Jar/Leto/Jeseň/Zima
  final String seasonKey; // jar|let|jese|zim
  final bool forecastAvailable;
  final String sourceLabel; // Predpoveď / Odhad
  final String summarySubtitle; // "Jar • 12°C • vietor ..."

  const DateWeatherSnapshot({
    required this.tempC,
    required this.isRainy,
    required this.isWindy,
    required this.seasonLabel,
    required this.seasonKey,
    required this.forecastAvailable,
    required this.sourceLabel,
    required this.summarySubtitle,
  });

  Map<String, dynamic> toJson() => {
        'tempC': tempC,
        'isRainy': isRainy,
        'isWindy': isWindy,
        'seasonLabel': seasonLabel,
        'seasonKey': seasonKey,
        'forecastAvailable': forecastAvailable,
        'sourceLabel': sourceLabel,
        'summarySubtitle': summarySubtitle,
      };

  factory DateWeatherSnapshot.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;
    bool asBool(dynamic v) =>
        v is bool ? v : v.toString().toLowerCase() == 'true';

    String asStr(dynamic v) => v?.toString() ?? '';

    final tempC = asInt(json['tempC']);
    final isRainy = asBool(json['isRainy']);
    final isWindy = asBool(json['isWindy']);
    final seasonLabel = asStr(json['seasonLabel']);
    final seasonKey = asStr(json['seasonKey']);
    final forecastAvailable = asBool(json['forecastAvailable']);
    final sourceLabel = asStr(json['sourceLabel']);
    final summarySubtitle = asStr(json['summarySubtitle']);

    return DateWeatherSnapshot(
      tempC: tempC,
      isRainy: isRainy,
      isWindy: isWindy,
      seasonLabel: seasonLabel.isEmpty
          ? _seasonLabelForSeasonKey(seasonKey)
          : seasonLabel,
      seasonKey:
          seasonKey.isEmpty ? _seasonKeyFromLabel(seasonLabel) : seasonKey,
      forecastAvailable: forecastAvailable,
      sourceLabel: sourceLabel.isEmpty
          ? (forecastAvailable ? 'Predpoveď' : 'Odhad')
          : sourceLabel,
      summarySubtitle: summarySubtitle.isEmpty
          ? _buildSummarySubtitle(
              seasonLabel.isEmpty
                  ? _seasonLabelForSeasonKey(seasonKey)
                  : seasonLabel,
              tempC,
              isWindy,
              isRainy,
            )
          : summarySubtitle,
    );
  }

  static String _seasonLabelForSeasonKey(String seasonKey) {
    switch (seasonKey) {
      case 'jar':
        return 'Jar';
      case 'let':
        return 'Leto';
      case 'jese':
        return 'Jeseň';
      default:
        return 'Zima';
    }
  }

  static String _seasonKeyFromLabel(String seasonLabel) {
    final s = seasonLabel.toLowerCase();
    if (s.contains('jar')) return 'jar';
    if (s.contains('let')) return 'let';
    if (s.contains('jese')) return 'jese';
    return 'zim';
  }

  static String _buildSummarySubtitle(
    String seasonLabel,
    int tempC,
    bool isWindy,
    bool isRainy,
  ) {
    final parts = <String>[seasonLabel, '$tempC°C'];
    if (isWindy) parts.add('vietor');
    if (isRainy) parts.add('dážď');
    if (!isWindy && !isRainy) parts.add('jasno');
    return parts.join(' • ');
  }
}

class DateWeatherService {
  const DateWeatherService._();

  /// Shared deterministic fallback used by weather-dependent features.
  static DateWeatherSnapshot getFallbackWeatherForDate(DateTime date) {
    return getWeatherForDate(date);
  }

  static DateWeatherSnapshot getWeatherForDate(DateTime date) {
    // Normalize to local date (avoid timezone surprises).
    final d = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diffDays = d.difference(today).inDays;

    final forecastAvailable = diffDays >= 0 && diffDays <= 5;
    final sourceLabel = forecastAvailable ? 'Predpoveď' : 'Odhad';

    final seasonLabel = (d.month >= 3 && d.month <= 5)
        ? 'Jar'
        : (d.month >= 6 && d.month <= 8)
            ? 'Leto'
            : (d.month >= 9 && d.month <= 11)
                ? 'Jeseň'
                : 'Zima';

    final seasonKey = (() {
      final s = seasonLabel.toLowerCase();
      if (s.contains('jar')) return 'jar';
      if (s.contains('let')) return 'let';
      if (s.contains('jese')) return 'jese';
      return 'zim';
    })();

    int baseTemp;
    if (seasonKey == 'zim') {
      baseTemp = 2;
    } else if (seasonKey == 'jar') {
      baseTemp = 10;
    } else if (seasonKey == 'let') {
      baseTemp = 24;
    } else {
      baseTemp = 12; // jeseň
    }

    // delta in [-2..+2], deterministic.
    final delta = (d.day % 5) - 2;
    final tempC = baseTemp + delta;

    final rainyMonths = <int>{3, 4, 5, 9, 10, 11};
    final isRainy = rainyMonths.contains(d.month) && (d.day % 3 == 0);
    final isWindy = d.day % 4 == 0;

    final summarySubtitle = DateWeatherSnapshot._buildSummarySubtitle(
      seasonLabel,
      tempC,
      isWindy,
      isRainy,
    );

    return DateWeatherSnapshot(
      tempC: tempC,
      isRainy: isRainy,
      isWindy: isWindy,
      seasonLabel: seasonLabel,
      seasonKey: seasonKey,
      forecastAvailable: forecastAvailable,
      sourceLabel: sourceLabel,
      summarySubtitle: summarySubtitle,
    );
  }
}

