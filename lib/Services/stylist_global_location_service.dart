import '../models/stylist_resolved_location.dart';
import '../utils/stylist_destination_mention.dart';
import 'destination_search_service.dart';

class _LocationCacheEntry {
  final StylistResolvedLocation value;
  final DateTime fetchedAt;

  const _LocationCacheEntry(this.value, this.fetchedAt);
}

class _VerifiedCandidate {
  final DestinationSuggestion item;
  final DestinationGranularity granularity;
  final String resolvedName;

  const _VerifiedCandidate({
    required this.item,
    required this.granularity,
    required this.resolvedName,
  });
}

/// Resolves user-authored destination mentions through the global geocoder.
///
/// The provider is authoritative for whether a phrase is a locality, broad
/// administrative region, country, airport, etc. No named place is encoded in
/// this layer.
abstract final class StylistGlobalLocationService {
  static const Duration _cacheTtl = Duration(minutes: 30);
  static final Map<String, _LocationCacheEntry> _cache = {};

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
    return resolveQuery(
      effectiveMention.query,
      evidence: effectiveMention.evidence,
    );
  }

  /// Resolve a provider query that already came from trusted app context, such
  /// as the GPS city label. This is also used to sanity-check device coordinates
  /// before deriving road-arrival timing.
  static Future<StylistResolvedLocation?> resolveQuery(
    String rawQuery, {
    String? evidence,
  }) async {
    final original = rawQuery.trim();
    if (original.length < 2) return null;
    for (final query in StylistDestinationMentionExtractor.providerQueryVariants(
      original,
    )) {
      final cacheKey = DestinationSearchService.normalizeQuery(query);
      final cached = _cache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
        final value = cached.value;
        return StylistResolvedLocation(
          evidence: evidence?.trim().isNotEmpty == true ? evidence!.trim() : original,
          query: value.query,
          displayName: value.displayName,
          weatherLabel: value.weatherLabel,
          country: value.country,
          adminRegion: value.adminRegion,
          latitude: value.latitude,
          longitude: value.longitude,
          featureCode: value.featureCode,
          granularity: value.granularity,
        );
      }

      final results = await DestinationSearchService.search(query);
      final best = _bestVerifiedMatch(query, results);
      if (best == null) continue;
      final item = best.item;
      final resolved = StylistResolvedLocation(
        evidence: evidence?.trim().isNotEmpty == true ? evidence!.trim() : original,
        query: query,
        displayName: item.displayName,
        weatherLabel: best.resolvedName,
        country: item.country,
        adminRegion: item.adminRegion,
        latitude: item.latitude,
        longitude: item.longitude,
        featureCode: item.featureCode,
        granularity: _granularity(best.granularity),
      );
      _cache[cacheKey] = _LocationCacheEntry(resolved, DateTime.now());
      return resolved;
    }
    return null;
  }

  static _VerifiedCandidate? _bestVerifiedMatch(
    String query,
    List<DestinationSuggestion> results,
  ) {
    if (results.isEmpty) return null;
    final q = DestinationSearchService.normalizeQuery(query);
    final acronymLike = RegExp(r'^[A-Z]{2,4}$').hasMatch(query.trim());

    // Exact city-state names (same exact city and country) are usefully
    // weather-specific. Otherwise an exact country/admin match wins over a
    // merely similar locality name, preventing country phrases from becoming
    // arbitrary cities just because the provider returned one nearby.
    for (final item in results) {
      final name = DestinationSearchService.normalizeQuery(item.name);
      final country = DestinationSearchService.normalizeQuery(item.country);
      if (q == name && q == country && item.granularity == DestinationGranularity.locality) {
        return _VerifiedCandidate(
          item: item,
          granularity: DestinationGranularity.locality,
          resolvedName: item.name,
        );
      }
    }

    for (final item in results) {
      final country = DestinationSearchService.normalizeQuery(item.country);
      final code = DestinationSearchService.normalizeQuery(item.countryCode ?? '');
      if (q == country || (q.length == 2 && q == code)) {
        return _VerifiedCandidate(
          item: item,
          granularity: DestinationGranularity.country,
          resolvedName: item.country.isNotEmpty ? item.country : query,
        );
      }
      final admin = DestinationSearchService.normalizeQuery(item.adminRegion ?? '');
      if (q == admin && admin.isNotEmpty) {
        return _VerifiedCandidate(
          item: item,
          granularity: DestinationGranularity.adminRegion,
          resolvedName: item.adminRegion ?? query,
        );
      }
    }

    for (final item in results) {
      final name = DestinationSearchService.normalizeQuery(item.name);
      if (q == name) {
        // Short all-uppercase tokens are frequently country/region/airport
        // abbreviations. A random locality with the same short name is not
        // strong enough evidence to drive weather; fail conservative instead.
        if (acronymLike && item.granularity == DestinationGranularity.locality) {
          continue;
        }
        return _VerifiedCandidate(
          item: item,
          granularity: item.granularity,
          resolvedName: item.name,
        );
      }
    }

    for (final item in results) {
      final country = DestinationSearchService.normalizeQuery(item.country);
      if (_closeEnough(q, country)) {
        return _VerifiedCandidate(
          item: item,
          granularity: DestinationGranularity.country,
          resolvedName: item.country,
        );
      }
      final admin = DestinationSearchService.normalizeQuery(item.adminRegion ?? '');
      if (_closeEnough(q, admin)) {
        return _VerifiedCandidate(
          item: item,
          granularity: DestinationGranularity.adminRegion,
          resolvedName: item.adminRegion ?? query,
        );
      }
    }

    for (final item in results) {
      final name = DestinationSearchService.normalizeQuery(item.name);
      if (_closeEnough(q, name)) {
        if (acronymLike && item.granularity == DestinationGranularity.locality) {
          continue;
        }
        return _VerifiedCandidate(
          item: item,
          granularity: item.granularity,
          resolvedName: item.name,
        );
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
