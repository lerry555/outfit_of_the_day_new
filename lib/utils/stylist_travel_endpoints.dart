class StylistTravelEndpointMention {
  final String evidence;
  final String query;

  const StylistTravelEndpointMention({
    required this.evidence,
    required this.query,
  });
}

class StylistTravelEndpoints {
  final StylistTravelEndpointMention? origin;
  final StylistTravelEndpointMention? destination;

  const StylistTravelEndpoints({this.origin, this.destination});

  bool get hasAny => origin != null || destination != null;
}

/// Pulls explicit route endpoints from user text without deciding what those
/// names geographically are. The global location provider remains the only
/// authority for city/country/airport identity.
abstract final class StylistTravelEndpointsExtractor {
  static StylistTravelEndpoints extract(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return const StylistTravelEndpoints();

    // Generic route shape: "z X do Y" / "zo X do Y" / "from X to Y".
    // This deliberately has no city, country, station or airport names.
    final route = RegExp(
      r'(?:^|\s)(?:z|zo|from)\s+(.+?)\s+(?:do|to)\s+(.+?)(?='
      r'\s+(?:o|okolo|za|a|ale|potrebujem|chcem|chceme|budem|budeme|idem|ideme|'
      r'po\s+prichode|po\s+prilete|na\s+mieste)\b|[,;.!?\n]|$)',
      caseSensitive: false,
    ).allMatches(raw).toList(growable: false);

    if (route.isNotEmpty) {
      final match = route.last;
      final origin = _endpoint(match.group(1) ?? '');
      final destination = _endpoint(match.group(2) ?? '');
      return StylistTravelEndpoints(origin: origin, destination: destination);
    }

    // A common form omits an explicit origin but still names the destination,
    // e.g. "letím do Londýna". Destination extraction elsewhere handles that;
    // this class intentionally focuses on route pairs so origin can override GPS.
    return const StylistTravelEndpoints();
  }

  static StylistTravelEndpointMention? _endpoint(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(
      RegExp(
        r'^(?:letiska?|airportu?|stanice?|nadrazia?|nadr\.?|pristavu?)\s+',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.length < 2 || value.length > 100) return null;
    return StylistTravelEndpointMention(evidence: value, query: value);
  }
}
