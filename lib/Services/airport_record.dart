/// Záznam letiska z lokálneho OurAirports JSON (assets/data/airports.json).
class AirportRecord {
  final String iata;
  final String icao;
  final String name;
  final String city;
  final String country;
  final String isoCountry;
  final double lat;
  final double lon;
  final String? timezone;
  final String airportType;

  const AirportRecord({
    required this.iata,
    required this.icao,
    required this.name,
    required this.city,
    required this.country,
    required this.isoCountry,
    required this.lat,
    required this.lon,
    this.timezone,
    this.airportType = 'large_airport',
  });

  bool get isLargeHub => airportType == 'large_airport';

  /// Riadok pre UI (konzistentné s požiadavkou „presné letisko“).
  String get displayTitle => '$name ($iata)';

  String get displaySubtitle {
    final c = city.trim();
    if (c.isNotEmpty) return '$c, $country';
    return country;
  }

  factory AirportRecord.fromJson(Map<String, dynamic> json) {
    return AirportRecord(
      iata: (json['iata'] as String? ?? '').trim().toUpperCase(),
      icao: (json['icao'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      city: (json['city'] as String? ?? '').trim(),
      country: (json['country'] as String? ?? '').trim(),
      isoCountry: (json['iso_country'] as String? ?? '').trim(),
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0,
      timezone: (json['timezone'] as String?)?.trim(),
      airportType: (json['airport_type'] as String? ?? 'large_airport').trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'iata': iata,
        'icao': icao,
        'name': name,
        'city': city,
        'country': country,
        'iso_country': isoCountry,
        'lat': lat,
        'lon': lon,
        'timezone': timezone,
        'airport_type': airportType,
      };
}
