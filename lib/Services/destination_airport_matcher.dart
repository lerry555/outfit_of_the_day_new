import 'airport_record.dart';
import 'airport_repository.dart';
import 'destination_search_service.dart';

abstract final class DestinationAirportMatcher {
  DestinationAirportMatcher._();

  static Future<AirportRecord?> matchBest({
    required String displayName,
    String? cityName,
    String? adminRegion,
    String? countryName,
    double? latitude,
    double? longitude,
    int? population,
    String? featureCode,
  }) async {
    await AirportRepository.ensureLoaded();
    final queries = <String>[
      if (cityName != null && cityName.trim().isNotEmpty) cityName.trim(),
      displayName.trim(),
      if (adminRegion != null && adminRegion.trim().isNotEmpty) adminRegion.trim(),
      if (countryName != null && countryName.trim().isNotEmpty) countryName.trim(),
    ];

    for (final q in queries) {
      final hits = await AirportRepository.search(q, limit: 1);
      if (hits.isNotEmpty) return hits.first;
    }

    final normalized = DestinationSearchService.normalizeQuery(displayName);
    if (normalized.length >= 3) {
      return AirportRepository.resolveBest(normalized);
    }
    return null;
  }
}
