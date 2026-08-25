/// Použiteľnosť jedného kusu šatníka pre daný [OutfitIntent].
///
/// Generický model — zatiaľ len pre top, neskôr bottom / footwear / outerwear.
enum ItemEligibility {
  preferred,
  acceptable,
  compromise,
  forbidden;

  String get wireName => name;
}

/// Výsledok klasifikácie topu pre intent.
class TopEligibilityResult {
  const TopEligibilityResult({
    required this.eligibility,
    required this.reason,
  });

  final ItemEligibility eligibility;
  final String reason;
}

/// Technické constraints outfitu — preklad StylistIntent na matching pravidlá (M1b/M1c).
class OutfitIntent {
  final String activityType;
  final String idealSummarySk;
  final List<String> bottomPreferred;
  final List<String> bottomForbidden;
  final List<String> footwearPreferred;
  final List<String> footwearForbidden;
  final String topPreference;
  final List<String> nonNegotiables;

  const OutfitIntent({
    required this.activityType,
    required this.idealSummarySk,
    required this.bottomPreferred,
    required this.bottomForbidden,
    required this.footwearPreferred,
    required this.footwearForbidden,
    required this.topPreference,
    this.nonNegotiables = const [],
  });

  String _join(List<String> values) => values.join(',');

  /// Log riadok pre STYLIST CHAT outfit_intent.
  String toLogLine() {
    return 'STYLIST CHAT outfit_intent { '
        'activityType=$activityType, '
        'idealSummarySk=$idealSummarySk, '
        'bottomPreferred=${_join(bottomPreferred)}, '
        'bottomForbidden=${_join(bottomForbidden)}, '
        'footwearPreferred=${_join(footwearPreferred)}, '
        'footwearForbidden=${_join(footwearForbidden)}, '
        'topPreference=$topPreference, '
        'nonNegotiables=${_join(nonNegotiables)} '
        '}';
  }
}
