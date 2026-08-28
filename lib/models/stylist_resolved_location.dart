enum StylistResolvedLocationGranularity {
  locality,
  adminRegion,
  country,
  continent,
  airport,
  other,
  unknown,
}

class StylistResolvedLocation {
  final String evidence;
  final String query;
  final String displayName;
  final String weatherLabel;
  final String? country;
  final String? adminRegion;
  final double latitude;
  final double longitude;
  final String? featureCode;
  final StylistResolvedLocationGranularity granularity;
  final bool providerVerified;

  const StylistResolvedLocation({
    required this.evidence,
    required this.query,
    required this.displayName,
    required this.weatherLabel,
    this.country,
    this.adminRegion,
    required this.latitude,
    required this.longitude,
    this.featureCode,
    required this.granularity,
    this.providerVerified = true,
  });

  bool get weatherSpecific =>
      providerVerified &&
      (granularity == StylistResolvedLocationGranularity.locality ||
          granularity == StylistResolvedLocationGranularity.airport ||
          granularity == StylistResolvedLocationGranularity.other);

  bool get needsMoreSpecificity =>
      providerVerified &&
      (granularity == StylistResolvedLocationGranularity.country ||
          granularity == StylistResolvedLocationGranularity.continent ||
          granularity == StylistResolvedLocationGranularity.adminRegion);

  Map<String, dynamic> toApiPayload() => <String, dynamic>{
    'providerVerified': providerVerified,
    'evidence': evidence,
    'query': query,
    'displayName': displayName,
    'weatherLabel': weatherLabel,
    if (country != null && country!.isNotEmpty) 'country': country,
    if (adminRegion != null && adminRegion!.isNotEmpty)
      'adminRegion': adminRegion,
    'latitude': latitude,
    'longitude': longitude,
    if (featureCode != null && featureCode!.isNotEmpty)
      'featureCode': featureCode,
    'granularity': granularity.name,
    'weatherSpecific': weatherSpecific,
    'needsMoreSpecificity': needsMoreSpecificity,
  };
}
