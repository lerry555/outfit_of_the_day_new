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
  final bool transitOutfitExplicit;
  final bool destinationUseExplicit;
  final bool packingExplicit;
  final int? departureHourLocal;
  final int? arrivalHourLocal;

  const StylistTravelContext({
    this.travelMentioned = false,
    this.scope = StylistTravelScope.none,
    this.transportMode = StylistTransportMode.unknown,
    this.transitOutfitExplicit = false,
    this.destinationUseExplicit = false,
    this.packingExplicit = false,
    this.departureHourLocal,
    this.arrivalHourLocal,
  });

  bool get destinationRequiredForPrimaryOutfit => !transitOutfitExplicit;

  bool get arrivalWeatherCouldHelp =>
      travelMentioned && (transitOutfitExplicit || destinationUseExplicit);

  Map<String, dynamic> toApiPayload() => <String, dynamic>{
    'travelMentioned': travelMentioned,
    'scope': scope.wireName,
    'transportMode': transportMode.wireName,
    'transitOutfitExplicit': transitOutfitExplicit,
    'destinationUseExplicit': destinationUseExplicit,
    'packingExplicit': packingExplicit,
    'destinationRequiredForPrimaryOutfit': destinationRequiredForPrimaryOutfit,
    'arrivalWeatherCouldHelp': arrivalWeatherCouldHelp,
    if (departureHourLocal != null) 'departureHourLocal': departureHourLocal,
    if (arrivalHourLocal != null) 'arrivalHourLocal': arrivalHourLocal,
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

    // Transit is a request about what to wear DURING the movement itself. A
    // generic sentence such as "cestujem ... čo si obliecť na mieste" must not
    // become transit merely because it contains both "cestujem" and "obliecť".
    final explicitTransitPhrase = _has(
      text,
      r'\b(?:do|na|pocas|po)\s+(?:lietadl\w*|let\w*|palub\w*|vlak\w*|cest\w*|presun\w*|aut\w*|bus\w*|trajekt\w*|lod\w*)\b',
    );
    final outfitPlusConcreteTransport =
        _has(
          text,
          r'\b(?:outfit\w*|obliec\w*|oblecen\w*|na\s+seba|co\s+si\s+mam)\b',
        ) &&
        _has(
          text,
          r'\b(?:lietadl\w*|let\w*|palub\w*|vlak\w*|presun\w*|aut\w*|bus\w*|trajekt\w*|lod\w*)\b',
        );
    final transitOutfitExplicit =
        explicitTransitPhrase || outfitPlusConcreteTransport;

    final destinationUseExplicit = _has(
      text,
      r'\b(?:po\s+prilete|po\s+pristati|po\s+prichode|na\s+mieste|v\s+cieli|v\s+destinacii|pocas\s+pobytu|na\s+pobyt|tam\s+(?:budem|budeme|chcem|chceme|pojdem|pojdeme))\b',
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
      transitOutfitExplicit: transitOutfitExplicit,
      destinationUseExplicit: destinationUseExplicit,
      packingExplicit: packingExplicit,
      departureHourLocal: _departureHour(text),
      arrivalHourLocal: _arrivalHour(text),
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
