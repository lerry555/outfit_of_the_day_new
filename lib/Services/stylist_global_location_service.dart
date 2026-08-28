import '../models/stylist_resolved_location.dart';
import '../utils/stylist_destination_mention.dart';
import 'destination_search_service.dart';

/// Resolves user-authored destination mentions through the global geocoder.
///
/// The provider is authoritative for whether a phrase is a locality, broad
/// administrative region, country, airport, etc. No named place is encoded in
/// this layer.
abstract final class StylistGlobalLocationService {
  static Future<StylistResolvedLocation?> resolve({
    required String conversation,
    String latestUserText = '',
    bool allowBareLatest = false,
  }) async {
    final latest = latestUserText.trim();
    final mention = latest.isNotEmpty
        ? StylistDestinationMentionExtractor.extract(
            latest,
            allowBareReply: allowBareLatest,
          )
        : null;
    final effectiveMention =
        mention ?? StylistDestinationMentionExtractor.extract(conversation);
    if (effectiveMention == null) return null;

    for (final query in StylistDestinationMentionExtractor.providerQueryVariants(
      effectiveMention.query,
    )) {
      final results = await DestinationSearchService.search(query);
      final best = _bestVerifiedMatch(query, results);
      if (best == null) continue;
      return StylistResolvedLocation(
        evidence: effectiveMention.evidence,
        query: query,
        displayName: best.displayName,
        weatherLabel: best.name,
        country: best.country,
        adminRegion: best.adminRegion,
        latitude: best.latitude,
        longitude: best.longitude,
        featureCode: best.featureCode,
        granularity: _granularity(best.granularity),
      );
    }
    return null;
  }

  static DestinationSuggestion? _bestVerifiedMatch(
    String query,
    List<DestinationSuggestion> results,
  ) {
    if (results.isEmpty) return null;
    final q = DestinationSearchService.normalizeQuery(query);
    for (final item in results) {
      final name = DestinationSearchService.normalizeQuery(item.name);
      final country = DestinationSearchService.normalizeQuery(item.country);
      final admin = DestinationSearchService.normalizeQuery(item.adminRegion ?? '');
      if (_closeEnough(q, name) || _closeEnough(q, country) || _closeEnough(q, admin)) {
        return item;
      }
    }
    return null;
  }

  static bool _closeEnough(String query, String candidate) {
    if (query.isEmpty || candidate.isEmpty) return false;
    if (query == candidate) return true;
    if (query.contains(candidate) || candidate.contains(query)) {
      final shorter = query.length < candidate.length ? query.length : candidate.length;
      return shorter >= 4;
    }
    final distance = _editDistance(query, candidate);
    final maxLength = query.length > candidate.length ? query.length : candidate.length;
    final allowed = maxLength >= 10 ? 3 : maxLength >= 6 ? 2 : 1;
    return distance <= allowed && distance / maxLength <= 0.30;
  }

  static int _editDistance(String left, String right) {
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 1; i <= left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0)..[0] = i;
      for (var j = 1; j <= right.length; j++) {
        final substitution =
            previous[j - 1] +
            (left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1);
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        current[j] = substitution < deletion
            ? (substitution < insertion ? substitution : insertion)
            : (deletion < insertion ? deletion : insertion);
      }
      previous = current;
    }
    return previous.last;
  }

  static StylistResolvedLocationGranularity _granularity(
    DestinationGranularity value,
  ) => switch (value) {
    DestinationGranularity.locality => StylistResolvedLocationGranularity.locality,
    DestinationGranularity.adminRegion => StylistResolvedLocationGranularity.adminRegion,
    DestinationGranularity.country => StylistResolvedLocationGranularity.country,
    DestinationGranularity.continent => StylistResolvedLocationGranularity.continent,
    DestinationGranularity.airport => StylistResolvedLocationGranularity.airport,
    DestinationGranularity.other => StylistResolvedLocationGranularity.other,
    DestinationGranularity.unknown => StylistResolvedLocationGranularity.unknown,
  };
}
