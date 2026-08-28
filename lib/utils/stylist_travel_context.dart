import 'stylist_semantic_activity.dart';

enum StylistTravelScope { none, transit, destination, packing, mixed, unknown }

enum StylistTransportMode { unknown, air, rail, road, sea }

extension StylistTravelScopeWire on StylistTravelScope {
  String get wireName => switch (this) {
    StylistTravelScope.none => 'none',
    StylistTravelScope.transit => 'transit',
    StylistTravelScope.destination => 'destination',
    StylistTravelScope.packing => 'packing',
    StylistTravelScope.mixed => 'mixed',
    StylistTravelScope.unknown => 'unknown',
  };
}

extension StylistTransportModeWire on StylistTransportMode {
  String get wireName => switch (this) {
    StylistTransportMode.unknown => 'unknown',
    StylistTransportMode.air => 'air',
    StylistTransportMode.rail => 'rail',
    StylistTransportMode.road => 'road',
    StylistTransportMode.sea => 'sea',
  };
}

class StylistTravelContext {
  final bool travelMentioned;
  final StylistTravelScope scope;
  final StylistTransportMode transportMode;
  final bool outfitRequestPresent;
  final bool transitOutfitExplicit;
  final bool destinationUseExplicit;
  final bool packingExplicit;
  final int? departureHourLocal;
  final int? arrivalHourLocal;
  final int? departureOffsetMinutes;

  const StylistTravelContext({
    this.travelMentioned = false,
    this.scope = StylistTravelScope.none,
    this.transportMode = StylistTransportMode.unknown,
    this.outfitRequestPresent = false,
    this.transitOutfitExplicit = false,
    this.destinationUseExplicit = false,
    this.packingExplicit = false,
    this.departureHourLocal,
    this.arrivalHourLocal,
    this.departureOffsetMinutes,
  });

  /// A destination is mandatory for the *primary* outfit only when the user
  /// explicitly wants the destination part of the trip. Unknown travel scope
  /// must be clarified for purpose rather than silently treated as transit.
  bool get destinationRequiredForPrimaryOutfit =>
      destinationUseExplicit || packingExplicit;

  bool get scopeNeedsClarification =>
      travelMentioned && outfitRequestPresent && scope == StylistTravelScope.unknown;

  bool get arrivalWeatherCouldHelp =>
      travelMentioned &&
      (destinationUseExplicit || transitOutfitExplicit || scopeNeedsClarification);

  Map<String, dynamic> toApiPayload() => <String, dynamic>{
    'travelMentioned': travelMentioned,
    'scope': scope.wireName,
    'transportMode': transportMode.wireName,
    'outfitRequestPresent': outfitRequestPresent,
    'scopeNeedsClarification': scopeNeedsClarification,
    'transitOutfitExplicit': transitOutfitExplicit,
    'destinationUseExplicit': destinationUseExplicit,
    'packingExplicit': packingExplicit,
    'destinationRequiredForPrimaryOutfit': destinationRequiredForPrimaryOutfit,
    'arrivalWeatherCouldHelp': arrivalWeatherCouldHelp,
    if (departureHourLocal != null) 'departureHourLocal': departureHourLocal,
    if (arrivalHourLocal != null) 'arrivalHourLocal': arrivalHourLocal,
    if (departureOffsetMinutes != null)
      'departureOffsetMinutes': departureOffsetMinutes,
  };
}

/// Meaning-first travel classifier used by the Stylist grounding gate.
///
/// It deliberately contains no country, city, airport, airline or attraction
/// names. Those are external facts and must be resolved by location/search
/// services, not by a hard-coded language whitelist.
abstract final class StylistTravelContextResolver {
  static StylistTravelContext resolve(String input) {
    final text = StylistSemanticActivity.normalize(input);
    if (text.isEmpty) return const StylistTravelContext();

    final mode = _transportMode(text);
    final genericTravel = _has(
      text,
      r'\b(?:cest\w*|presun\w*|dovolen\w*|trip\w*|travel\w*)\b',
    );
    final travelMentioned = mode != StylistTransportMode.unknown || genericTravel;
    final outfitRequestPresent = _has(
      text,
      r'\b(?:outfit\w*|obliec\w*|oblecen\w*|na\s+seba|co\s+si\s+mam|co\s+na\s+seba|potrebujem\s+nieco\s+na\s+seba)\b',
    );

    // Transit means the user explicitly targets what they wear DURING the
    // movement. Merely mentioning a car/plane/train next to the word "outfit"
    // is not enough: "idem autom do Berlína, potrebujem outfit" is intentionally
    // ambiguous until we know whether the outfit is for the drive, destination,
    // or both.
    final transitOutfitExplicit = _has(
          text,
          r'\b(?:do|na|v|vo|pocas)\s+(?:lietadl\w*|palub\w*|let\w*|vlak\w*|aut\w*|bus\w*|autobus\w*|cest\w*|presun\w*|trajekt\w*|lod\w*|jazd\w*)\b',
        ) ||
        _has(
          text,
          r'\b(?:pocas\s+(?:cesty|letu|jazdy|presunu)|na\s+cestovanie|na\s+presun|cestovny\s+outfit)\b',
        );

    final explicitActivity = StylistSemanticActivity.resolveExplicit(input);
    final explicitDestinationActivity =
        travelMentioned &&
        explicitActivity != null &&
        explicitActivity != 'travel' &&
        !transitOutfitExplicit;

    final destinationUseExplicit =
        explicitDestinationActivity ||
        _has(
          text,
          r'\b(?:po\s+prilete|po\s+pristati|po\s+prichode|po\s+vystupeni|na\s+mieste|v\s+cieli|v\s+destinacii|pocas\s+pobytu|na\s+pobyt|tam\s+(?:budem|budeme|chcem|chceme|pojdem|pojdeme))\b',
        );
    final packingExplicit = _has(
      text,
      r'\b(?:zbal\w*|balen\w*|packing\w*|kufr\w*|batozin\w*|zobrat\w*\s+so\s+sebou|vziat\w*\s+so\s+sebou)\b',
    );

    final scope = !travelMentioned
        ? StylistTravelScope.none
        : transitOutfitExplicit && (destinationUseExplicit || packingExplicit)
            ? StylistTravelScope.mixed
            : transitOutfitExplicit
                ? StylistTravelScope.transit
                : packingExplicit
                    ? StylistTravelScope.packing
                    : destinationUseExplicit
                        ? StylistTravelScope.destination
                        : StylistTravelScope.unknown;

    return StylistTravelContext(
      travelMentioned: travelMentioned,
      scope: scope,
      transportMode: mode,
      outfitRequestPresent: outfitRequestPresent,
      transitOutfitExplicit: transitOutfitExplicit,
      destinationUseExplicit: destinationUseExplicit,
      packingExplicit: packingExplicit,
      departureHourLocal: _departureHour(text),
      arrivalHourLocal: _arrivalHour(text),
      departureOffsetMinutes: _departureOffsetMinutes(text),
    );
  }

  static StylistTransportMode _transportMode(String text) {
    if (_has(
      text,
      r'\b(?:lietadl\w*|letim\w*|letime\w*|letiet\w*|odlet\w*|prilet\w*|pristav\w*|letisk\w*|flight\w*|plane\w*|palub\w*)\b',
    )) {
      return StylistTransportMode.air;
    }
    if (_has(text, r'\b(?:vlak\w*|zeleznic\w*|train\w*)\b')) {
      return StylistTransportMode.rail;
    }
    if (_has(
      text,
      r'\b(?:autom\w*|auto\w*|autobus\w*|bus\w*|car\w*|road\s+trip)\b',
    )) {
      return StylistTransportMode.road;
    }
    if (_has(
      text,
      r'\b(?:lod\w*|trajekt\w*|ferry\w*|cruise\w*|plavb\w*)\b',
    )) {
      return StylistTransportMode.sea;
    }
    return StylistTransportMode.unknown;
  }

  static int? _departureHour(String text) => _hourAfter(
    text,
    r'\b(?:odlet\w*|odchadz\w*|vyraz\w*|letim\w*|letime\w*|cestuj\w*)\b',
  );

  static int? _arrivalHour(String text) => _hourAfter(
    text,
    r'\b(?:prilet\w*|pristav\w*|doraz\w*|prichadz\w*|pridem\w*|prideme\w*)\b',
  );

  static int? _departureOffsetMinutes(String text) {
    if (_has(text, r'\b(?:za|o)\s+pol\s+hodin\w*\b')) return 30;
    if (_has(text, r'\b(?:za|o)\s+stvrt\w*\s+hodin\w*\b')) return 15;
    if (_has(text, r'\b(?:za|o)\s+tri\s+stvrt\w*\s+hodin\w*\b')) return 45;

    final minutes = RegExp(
      r'\b(?:za|o)\s+(\d{1,3})\s*(?:min|minut\w*)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (minutes != null) {
      final value = int.tryParse(minutes.group(1) ?? '');
      if (value != null && value > 0 && value <= 720) return value;
    }

    final hours = RegExp(
      r'\b(?:za|o)\s+(\d{1,2})\s*(?:h|hod|hodin\w*)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (hours != null) {
      final value = int.tryParse(hours.group(1) ?? '');
      if (value != null && value > 0 && value <= 48) return value * 60;
    }

    final wordHours = RegExp(
      r'\b(?:za|o)\s+(jednu|jeden|dve|dva|tri|styri|pat|sest|sedem|osem|devat|desat)\s+hodin\w*\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (wordHours != null) {
      const values = <String, int>{
        'jednu': 1,
        'jeden': 1,
        'dve': 2,
        'dva': 2,
        'tri': 3,
        'styri': 4,
        'pat': 5,
        'sest': 6,
        'sedem': 7,
        'osem': 8,
        'devat': 9,
        'desat': 10,
      };
      final value = values[wordHours.group(1)];
      if (value != null) return value * 60;
    }
    return null;
  }

  static int? _hourAfter(String text, String leadPattern) {
    final match = RegExp(
      '$leadPattern[^0-9]{0,28}(?:o|okolo)?\\s*(\\d{1,2})(?::\\d{2})?',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    final value = int.tryParse(match.group(1) ?? '');
    if (value == null || value < 0 || value > 23) return null;
    return value;
  }

  static bool _has(String text, String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(text);
}
