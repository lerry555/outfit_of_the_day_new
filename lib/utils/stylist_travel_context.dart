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
  final int? departureMinuteLocal;
  final int? arrivalHourLocal;
  final int? arrivalMinuteLocal;
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
    this.departureMinuteLocal,
    this.arrivalHourLocal,
    this.arrivalMinuteLocal,
    this.departureOffsetMinutes,
  });

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
        if (departureMinuteLocal != null)
          'departureMinuteLocal': departureMinuteLocal,
        if (arrivalHourLocal != null) 'arrivalHourLocal': arrivalHourLocal,
        if (arrivalMinuteLocal != null) 'arrivalMinuteLocal': arrivalMinuteLocal,
        if (departureOffsetMinutes != null)
          'departureOffsetMinutes': departureOffsetMinutes,
      };
}

/// Meaning-first travel classifier used by the Stylist grounding gate.
/// Geographic proper nouns are never semantic evidence here.
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
      r'\b(?:outfit\w*|obliec\w*|oblecen\w*|na\s+seba|co\s+si\s+mam|co\s+na\s+seba|potrebujem\s+nieco\s+na\s+seba|potrebujem\s+outfit)\b',
    );

    // Mentioning a transport mode beside "outfit" is intentionally not enough
    // to infer transit use. The user must target the movement phase itself.
    final transitOutfitExplicit = _has(
          text,
          r'\b(?:do|na|v|vo|pocas)\s+(?:lietadl\w*|palub\w*|let\w*|vlak\w*|auto|auta|aute|autom|autu|bus\w*|autobus\w*|cest\w*|presun\w*|trajekt\w*|lod\w*|jazd\w*)\b',
        ) ||
        _has(
          text,
          r'\b(?:pocas\s+(?:cesty|letu|jazdy|presunu|plavby)|na\s+cestovanie|na\s+presun|cestovny\s+outfit)\b',
        );

    final explicitActivity = StylistSemanticActivity.resolveExplicit(input);
    // A real non-travel activity remains destination use even when the user
    // ALSO explicitly asks for transit clothing; that is exactly mixed scope.
    final explicitDestinationActivity =
        travelMentioned && explicitActivity != null && explicitActivity != 'travel';

    // "Po príchode idem do hotela" is route context, not proof that the outfit
    // must serve the hotel. Destination use needs an actual activity or explicit
    // wording about what is worn/needed after arrival.
    final destinationUseExplicit =
        explicitDestinationActivity ||
        _has(
          text,
          r'\b(?:na\s+mieste|v\s+cieli|v\s+destinacii|pocas\s+pobytu|na\s+pobyt|'
          r'(?:outfit\w*|obliec\w*|oblecen\w*|na\s+seba)\s+(?:po\s+prilete|po\s+pristati|po\s+prichode|po\s+vystupeni)|'
          r'(?:po\s+prilete|po\s+pristati|po\s+prichode|po\s+vystupeni)\s+(?:chcem|potrebujem)\s+(?:outfit\w*|nieco\s+na\s+seba|vyzerat\w*))\b',
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

    final departureClock = _departureClock(text);
    final arrivalClock = _arrivalClock(text);
    return StylistTravelContext(
      travelMentioned: travelMentioned,
      scope: scope,
      transportMode: mode,
      outfitRequestPresent: outfitRequestPresent,
      transitOutfitExplicit: transitOutfitExplicit,
      destinationUseExplicit: destinationUseExplicit,
      packingExplicit: packingExplicit,
      departureHourLocal: departureClock?.$1,
      departureMinuteLocal: departureClock?.$2,
      arrivalHourLocal: arrivalClock?.$1,
      arrivalMinuteLocal: arrivalClock?.$2,
      departureOffsetMinutes: _departureOffsetMinutes(text),
    );
  }

  static StylistTransportMode _transportMode(String text) {
    if (_has(
      text,
      r'\b(?:lietadl\w*|letim\w*|letime\w*|letiet\w*|letu|lete|letom|odlet\w*|prilet\w*|odliet\w*|priliet\w*|pristav\w*|letisk\w*|flight\w*|plane\w*|palub\w*)\b',
    )) {
      return StylistTransportMode.air;
    }
    if (_has(
      text,
      r'\b(?:vlak\w*|zeleznic\w*|nadraz\w*|train\w*|rail\w*)\b',
    )) {
      return StylistTransportMode.rail;
    }
    if (_has(
      text,
      r'\b(?:auto|auta|aute|autom|autu|autobus\w*|bus\w*|taxi\w*|car\w*|road\s+trip|motork\w*|motocyk\w*)\b',
    )) {
      return StylistTransportMode.road;
    }
    if (_has(
      text,
      r'\b(?:lod\w*|trajekt\w*|ferry\w*|cruise\w*|plavb\w*|ship\w*)\b',
    )) {
      return StylistTransportMode.sea;
    }
    return StylistTransportMode.unknown;
  }

  static (int, int)? _departureClock(String text) => _clockAfter(
        text,
        r'\b(?:odlet\w*|odliet\w*|odchadz\w*|vyraz\w*|startuj\w*|letim\w*|letime\w*|cestuj\w*|'
        r'(?:vlak\w*|autobus\w*|bus\w*|trajekt\w*|lod\w*)\s+(?:ide|odchadz\w*|vyraz\w*))\b',
      );

  static (int, int)? _arrivalClock(String text) => _clockAfter(
        text,
        r'\b(?:prilet\w*|priliet\w*|pristav\w*|doraz\w*|prichadz\w*|pridem\w*|prideme\w*|'
        r'(?:vlak\w*|autobus\w*|bus\w*|trajekt\w*|lod\w*)\s+(?:pride|doraz\w*))\b',
      );

  static int? _departureOffsetMinutes(String text) {
    if (_has(text, r'\b(?:za|o)\s+pol\s+hodin\w*\b')) return 30;
    if (_has(text, r'\b(?:za|o)\s+stvrt\w*\s+hodin\w*\b')) return 15;
    if (_has(text, r'\b(?:za|o)\s+tri\s+stvrt\w*\s+hodin\w*\b')) return 45;

    final compound = RegExp(
      r'\b(?:za|o)\s+(\d{1,2})\s*(?:h|hod|hodin\w*)\s*(?:a\s*)?(\d{1,2})\s*(?:min|minut\w*)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (compound != null) {
      final hours = int.tryParse(compound.group(1) ?? '');
      final minutes = int.tryParse(compound.group(2) ?? '');
      if (hours != null && minutes != null && hours <= 24 && minutes < 60) {
        return hours * 60 + minutes;
      }
    }

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

  static (int, int)? _clockAfter(String text, String leadPattern) {
    final match = RegExp(
      '$leadPattern[^0-9]{0,40}(?:o|okolo)?\\s*(\\d{1,2})(?:(?::|\\s)(\\d{2}))?',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    if (hour == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return (hour, minute);
  }

  static bool _has(String text, String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(text);
}
