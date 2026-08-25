/// Typ rozpoznanej destinácie v konverzácii.
enum DestinationType {
  /// Žiadna cestovná destinácia v texte.
  none,

  /// Konkrétne mesto — vhodné pre počasie.
  city,

  /// Krajina bez mesta.
  country,

  /// Región / subnárodná oblasť bez mesta.
  region,

  /// Bod záujmu (atrakcia, park, komplex…) — môže obsahovať mesto.
  pointOfInterest,

  /// Miesto konania (nákupné centrum, hala…) — môže obsahovať mesto.
  venue,

  /// Letisko — môže byť nešpecifikované.
  airport,

  /// Adresa / ulica s číslom.
  address,

  /// Viac významov bez jednoznačného mesta.
  ambiguous,

  /// Neznámy názov bez jednoznačnej lokality.
  unknown,
}

extension DestinationTypeLabel on DestinationType {
  String get label => switch (this) {
        DestinationType.none => 'none',
        DestinationType.city => 'city',
        DestinationType.country => 'country',
        DestinationType.region => 'region',
        DestinationType.pointOfInterest => 'point_of_interest',
        DestinationType.venue => 'venue',
        DestinationType.airport => 'airport',
        DestinationType.address => 'address',
        DestinationType.ambiguous => 'ambiguous',
        DestinationType.unknown => 'unknown',
      };
}

/// Výsledok inteligentného parsovania destinácie.
class ParsedDestination {
  const ParsedDestination({
    required this.rawText,
    this.normalizedName,
    required this.type,
    required this.confidence,
    required this.reason,
    required this.needsClarification,
    this.clarificationQuestionSk,
    this.parentLocation,
    this.embeddedCity,
    this.extractedPhrase,
  });

  /// Žiadna cestovná destinácia — gate sa neaplikuje.
  factory ParsedDestination.none({String rawText = ''}) => ParsedDestination(
        rawText: rawText,
        type: DestinationType.none,
        confidence: 1.0,
        reason: 'no_travel_destination',
        needsClarification: false,
      );

  /// Pôvodný text konverzácie.
  final String rawText;

  /// Normalizovaný názov pre geokóder / počasie (mesto).
  final String? normalizedName;

  final DestinationType type;
  final double confidence;
  final String reason;
  final bool needsClarification;
  final String? clarificationQuestionSk;

  /// Krajina alebo región (pre doplňujúcu otázku).
  final String? parentLocation;

  /// Mesto vložené v názve POI („Zoo Praha“ → Praha).
  final String? embeddedCity;

  /// Fráza extrahovaná po predložke (do/v/vo/pri).
  final String? extractedPhrase;

  /// True ak používateľ spomenul cestovnú destináciu (nie [DestinationType.none]).
  bool get hasTravelDestination => type != DestinationType.none;

  /// Mesto použiteľné pre počasie — len pri jednoznačnej lokalite.
  String? get weatherCity {
    if (needsClarification) return null;
    return switch (type) {
      DestinationType.city ||
      DestinationType.address =>
        normalizedName,
      DestinationType.pointOfInterest ||
      DestinationType.venue ||
      DestinationType.airport =>
        embeddedCity ?? normalizedName,
      _ => null,
    };
  }
}
