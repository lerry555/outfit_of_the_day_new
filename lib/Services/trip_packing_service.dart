/// Balenie na cesty — výber z reálneho šatníka (Firestore). Bez AI.
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/wardrobe_image_url_priority.dart';
import 'destination_search_service.dart';
import 'trip_flight_models.dart';

enum TripKind { holiday, cityBreak, business, hiking, beach, festival }
enum TripTransport { car, plane, train, bus }
enum TripTravelStyle { comfy, elegant, subtle, stylish }

/// Zdroj času príchodu / príletu (Firestore / staré dokumenty: `auto_estimated` | `manual` | `unknown`).
enum TripArrivalTimeSource {
  autoEstimated,
  manual,
  unknown,
}

String tripArrivalTimeSourceToWire(TripArrivalTimeSource s) {
  switch (s) {
    case TripArrivalTimeSource.autoEstimated:
      return 'auto_estimated';
    case TripArrivalTimeSource.manual:
      return 'manual';
    case TripArrivalTimeSource.unknown:
      return 'unknown';
  }
}

/// Bezpečný fallback pri starých mapách / dynamických poliach.
TripArrivalTimeSource tripArrivalTimeSourceFromWire(Object? value) {
  final raw = value?.toString().toLowerCase().trim();
  switch (raw) {
    case 'auto_estimated':
    case 'autoestimated':
      return TripArrivalTimeSource.autoEstimated;
    case 'manual':
      return TripArrivalTimeSource.manual;
    default:
      return TripArrivalTimeSource.unknown;
  }
}

/// Jedna hodnota pre nadpisy dní / šablóny pri kombinácii viacerých typov cesty.
TripKind tripPrimaryKindForTitles(Set<TripKind> kinds) {
  if (kinds.isEmpty) return TripKind.cityBreak;
  if (kinds.contains(TripKind.business)) return TripKind.business;
  if (kinds.contains(TripKind.hiking)) return TripKind.hiking;
  if (kinds.contains(TripKind.festival)) return TripKind.festival;
  if (kinds.contains(TripKind.cityBreak)) return TripKind.cityBreak;
  if (kinds.contains(TripKind.beach)) return TripKind.beach;
  if (kinds.contains(TripKind.holiday)) return TripKind.holiday;
  return kinds.first;
}

class TripPlanInput {
  final String? userId;
  final String destinationText;
  final String? selectedDestinationName;
  final String? destinationCountry;
  final double? destinationLatitude;
  final double? destinationLongitude;

  /// Krátke názvy miest z dopravných detailov (karty počasia, trasy).
  final String? outboundOriginLabel;
  final String? outboundDestinationLabel;
  final String? returnOriginLabel;
  final String? returnDestinationLabel;

  /// Môže byť viac súčasne (napr. dovolenka + pláž + turistika).
  final Set<TripKind> tripKinds;
  final TripTransport transport;
  /// Viaceré naraz ovplyvňujú výber (pohodlie, elegancia, …).
  final Set<TripTravelStyle> travelStyles;
  final String activityNotes;

  /// Časy cesty — od nich sa odvodzuje dĺžka výletu a dni v destinácii.
  final DateTime? outboundDeparture;
  final DateTime? outboundArrival;
  final DateTime? returnDeparture;
  final DateTime? returnArrival;

  /// Či bol čas príchodu dopočítaný, zadaný ručne, alebo nie je známy (staré dáta → [unknown]).
  final TripArrivalTimeSource outboundArrivalTimeSource;
  final TripArrivalTimeSource returnArrivalTimeSource;

  /// Lietadlo: IATA kódy (voliteľné; staré dokumenty bez týchto polí).
  final String? planeOutboundDepartureIata;
  final String? planeOutboundArrivalIata;
  final String? planeReturnDepartureIata;
  final String? planeReturnArrivalIata;

  /// Metadáta odhadu letu tam / späť (null pri starých záznamoch alebo ne-lietadlo).
  final int? planeOutboundEstimatedFlightDurationMinutes;
  final double? planeOutboundEstimatedDistanceKm;
  final TripFlightPlanConfidence planeOutboundEstimateConfidence;
  final String? planeOutboundEstimatedArrivalTimezone;
  final TripTimezoneConfidence planeOutboundTimezoneConfidence;

  final int? planeReturnEstimatedFlightDurationMinutes;
  final double? planeReturnEstimatedDistanceKm;
  final TripFlightPlanConfidence planeReturnEstimateConfidence;
  final String? planeReturnEstimatedArrivalTimezone;
  final TripTimezoneConfidence planeReturnTimezoneConfidence;

  const TripPlanInput({
    this.userId,
    required this.destinationText,
    this.selectedDestinationName,
    this.destinationCountry,
    this.destinationLatitude,
    this.destinationLongitude,
    this.outboundOriginLabel,
    this.outboundDestinationLabel,
    this.returnOriginLabel,
    this.returnDestinationLabel,
    required this.tripKinds,
    required this.transport,
    this.travelStyles = const {},
    this.activityNotes = '',
    this.outboundDeparture,
    this.outboundArrival,
    this.returnDeparture,
    this.returnArrival,
    this.outboundArrivalTimeSource = TripArrivalTimeSource.unknown,
    this.returnArrivalTimeSource = TripArrivalTimeSource.unknown,
    this.planeOutboundDepartureIata,
    this.planeOutboundArrivalIata,
    this.planeReturnDepartureIata,
    this.planeReturnArrivalIata,
    this.planeOutboundEstimatedFlightDurationMinutes,
    this.planeOutboundEstimatedDistanceKm,
    this.planeOutboundEstimateConfidence = TripFlightPlanConfidence.unknown,
    this.planeOutboundEstimatedArrivalTimezone,
    this.planeOutboundTimezoneConfidence = TripTimezoneConfidence.unknown,
    this.planeReturnEstimatedFlightDurationMinutes,
    this.planeReturnEstimatedDistanceKm,
    this.planeReturnEstimateConfidence = TripFlightPlanConfidence.unknown,
    this.planeReturnEstimatedArrivalTimezone,
    this.planeReturnTimezoneConfidence = TripTimezoneConfidence.unknown,
  });

  TripKind get primaryKindForTitles => tripPrimaryKindForTitles(tripKinds);

  /// Minimálny rozvrh: oba odchody; príchody môžu chýbať (nový model).
  bool get hasCompleteSchedule =>
      outboundDeparture != null && returnDeparture != null;

  /// Kalendárne dni od prvého dňa odchodu po posledný deň návratu domov.
  int get tripDayCount {
    final start = outboundDeparture ?? outboundArrival;
    final end = returnArrival ?? returnDeparture;
    if (start != null && end != null) {
      final a = DateTime(start.year, start.month, start.day);
      final b = DateTime(end.year, end.month, end.day);
      return (b.difference(a).inDays + 1).clamp(1, 14);
    }
    return 1;
  }

  /// Rozsah pre jednoduché sezónne odporúčania (chlad / teplo).
  DateTime get climateRangeStart =>
      outboundDeparture ?? outboundArrival ?? DateTime.now();
  DateTime get climateRangeEnd =>
      returnArrival ?? returnDeparture ?? climateRangeStart;
}

class TripWardrobePiece {
  final String id;
  final String nameSk;
  final String? imageUrl;
  /// Hero-order URLs (cutout → clean → product → legacy → original) for resilient tiles.
  final List<String> imageDisplayUrls;

  TripWardrobePiece({
    required this.id,
    required this.nameSk,
    required this.imageUrl,
    List<String>? imageDisplayUrls,
  }) : imageDisplayUrls = _freezeTripImageUrls(imageDisplayUrls, imageUrl);

  static List<String> _freezeTripImageUrls(List<String>? explicit, String? primary) {
    if (explicit != null && explicit.isNotEmpty) {
      final u = explicit.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      return List<String>.unmodifiable(u);
    }
    final p = primary?.trim();
    if (p != null && p.isNotEmpty) return List<String>.unmodifiable([p]);
    return const <String>[];
  }

  List<String> get effectiveImageUrls => imageDisplayUrls;
}

class TripWeatherDayPreview {
  final String label;
  final int highTempC;
  final int lowTempC;
  final String conditionSk;
  const TripWeatherDayPreview({
    required this.label,
    required this.highTempC,
    required this.lowTempC,
    required this.conditionSk,
  });
}

/// Karta trasy s dátumom a počasím na oboch koncoch (ikonky mapuje UI z conditionSk).
class TripWeatherRoutePreview {
  /// Napr. „Pi 22. 5.“ — deň odletu / odchodu tam alebo spiatočný deň.
  final String travelDateLabelSk;
  final String routeTitleSk;
  final String conditionFromSk;
  final String conditionToSk;
  final int tempFromC;
  final int tempToC;
  const TripWeatherRoutePreview({
    required this.travelDateLabelSk,
    required this.routeTitleSk,
    required this.conditionFromSk,
    required this.conditionToSk,
    required this.tempFromC,
    required this.tempToC,
  });
}

/// Počasie: odletová trasa, dni v destinácii, návratová trasa.
class TripWeatherBundle {
  final TripWeatherRoutePreview? outboundRoute;
  final List<TripWeatherDayPreview> destinationStayDays;
  final TripWeatherRoutePreview? returnRoute;

  const TripWeatherBundle({
    required this.outboundRoute,
    required this.destinationStayDays,
    required this.returnRoute,
  });
}

class TripDailyOutfitPreview {
  final int dayIndex;
  final String titleSk;
  final String summarySk;
  /// Voliteľný kontext (vrstva na let, návrat domov, …).
  final String? dayHintSk;
  final List<TripWardrobePiece> pieces;

  /// Inline počasie v náhľade dňa v destinácii (žiaden samostatný weather strip).
  final String? weatherDateLabelSk;
  final String? weatherPlaceSk;
  final int? weatherHighC;
  final int? weatherLowC;
  final String? weatherConditionSk;

  const TripDailyOutfitPreview({
    required this.dayIndex,
    required this.titleSk,
    required this.summarySk,
    this.dayHintSk,
    required this.pieces,
    this.weatherDateLabelSk,
    this.weatherPlaceSk,
    this.weatherHighC,
    this.weatherLowC,
    this.weatherConditionSk,
  });
}

class TripMissingItemSuggestion {
  final String nameSk;
  final String reasonSk;
  const TripMissingItemSuggestion({required this.nameSk, required this.reasonSk});
}

class TripPackingPlaceholderResult {
  final int tripDays;
  final TripWeatherBundle weather;
  final List<TripWardrobePiece> travelOutboundPieces;
  final List<TripWardrobePiece> travelReturnPieces;
  final List<TripWardrobePiece> luggageItems;
  /// Len outfity pobytu v destinácii (nie letisko ani návrat).
  final List<TripDailyOutfitPreview> destinationDailyPlans;
  final List<TripMissingItemSuggestion> missingItems;
  /// Šatník mal aspoň jeden kandidát pri generovaní (Firestore načítaný).
  final bool hadWardrobeCandidates;
  const TripPackingPlaceholderResult({
    required this.tripDays,
    required this.weather,
    required this.travelOutboundPieces,
    required this.travelReturnPieces,
    required this.luggageItems,
    required this.destinationDailyPlans,
    required this.missingItems,
    required this.hadWardrobeCandidates,
  });
}

/// Interný riadok šatníka + normalizovaný text na vyhľadávanie vo všetkých poliach.
class _WardrobeCandidate {
  final TripWardrobePiece piece;
  final String blob;

  const _WardrobeCandidate({required this.piece, required this.blob});
}

enum _PieceReuseCategory { low, medium, high }

enum _RotPickAxis { top, bottom, shoe, layer }

/// Stav rotácie outfitov počas výletu (penalizácia opakovania).
final class _TripOutfitRotation {
  final Map<String, int> usesInTrip = {};
  String? prevTopId;
  String? prevBottomId;
  String? prevShoeId;
  String? prevLayerId;
}

abstract final class TripPackingService {
  TripPackingService._();

  // --- Aliasy (normalizované cez _normList) ---
  static final List<String> _topsAliases = _normList(const [
    'tričko', 'tricko', 't-shirt', 'tshirt', 'tee', 'top', 'tielko', 'tank', 'crop', 'polo',
    'shirt', 'blúzka', 'bluzka', 'košeľa', 'kosela', 'blouse',
  ]);
  static final List<String> _shortsAliases = _normList(const [
    'kraťasy', 'kratasy', 'šortky', 'sortky', 'shorts', 'short', 'bermuda',
  ]);
  static final List<String> _sneakerAliases = _normList(const [
    'tenisk', 'tenisky', 'sneaker', 'sneakers', 'trainer', 'running',
  ]);
  static final List<String> _sandalAliases = _normList(const [
    'sandál', 'sandale', 'sandals', 'šľapky', 'slapky', 'flip', 'slide', 'slides', 'slipper',
  ]);
  static final List<String> _shoesAllAliases = _normList(const [
    'tenisk', 'tenisky', 'sneaker', 'topánky', 'topanky', 'obuv', 'shoe', 'sandál', 'sandale',
    'šľapky', 'slapky', 'loafer', 'mokas', 'členok', 'chelsea',
  ]);
  static final List<String> _swimAliases = _normList(const [
    'plavk', 'swim', 'bikini', 'boardshort', 'swimwear',
  ]);
  static final List<String> _layerAliases = _normList(const [
    'mikina', 'hoodie', 'sweatshirt', 'sveter', 'cardigan', 'zip', 'fleece',
    'ľahká bunda', 'lahka bunda', 'bunda', 'jacket', 'windbreaker',
  ]);
  static final List<String> _longPantsAliases = _normList(const [
    'chinos', 'jeans', 'nohavice', 'pants', 'trouser', 'teplák', 'teplak', 'legín',
  ]);
  static final List<String> _hatAliases = _normList(const [
    'čiap', 'šilt', 'klobú', 'cap', 'hat', 'bucket',
  ]);
  static final List<String> _tankOnlyAliases = _normList(const [
    'tielko', 'tank', 'crop',
  ]);
  static final List<String> _sunglassesAliases = _normList(const [
    'okuliar', 'slneč', 'sunglass',
  ]);
  static final List<String> _linenLightShirtAliases = _normList(const [
    'ľan', 'linen', 'košeľa', 'kosela', 'shirt', 'button',
  ]);
  static final List<String> _bagAliases = _normList(const [
    'batoh', 'tašk', 'bag', 'crossbody', 'ruksak', 'backpack',
  ]);
  static final List<String> _workShirtAliases = _normList(const [
    'košeľa', 'kosela', 'shirt', 'blúzka', 'bluzka', 'blouse',
  ]);
  static final List<String> _workPantsAliases = _normList(const [
    'chinos', 'nohavice', 'tailor', 'formál', 'formal', 'dress pant',
  ]);
  static final List<String> _workShoeAliases = _normList(const [
    'loafer', 'oxford', 'chelsea', 'mokas', 'topán', 'topan',
  ]);
  static final List<String> _blazerAliases = _normList(const [
    'sako', 'blazer', 'suit',
  ]);
  static final List<String> _hikeBootAliases = _normList(const [
    'turist', 'hike', 'trail', 'boot', 'goretex',
  ]);
  static final List<String> _hikeShellAliases = _normList(const [
    'fleece', 'softshell', 'nepromok', 'bunda', 'shell',
  ]);

  static Future<TripPackingPlaceholderResult> generatePlaceholderPlan(TripPlanInput input) async {
    await Future<void>.delayed(const Duration(milliseconds: 2000));

    final warmBeach = _isWarmBeachContext(input);
    final kinds = input.tripKinds;
    final cityTrip = kinds.contains(TripKind.cityBreak);
    final workTrip = kinds.contains(TripKind.business);
    final hikingTrip = kinds.contains(TripKind.hiking);
    final festivalTrip = kinds.contains(TripKind.festival);
    final hasWorkEvent = _hasWorkEvent(input.activityNotes);
    final coolSeason = _isCoolSeason(input.climateRangeStart, input.climateRangeEnd);

    final candidates = await _loadCandidates(input.userId);
    final weather = _buildWeatherBundle(input, warmBeach: warmBeach, cityTrip: cityTrip);

    if (candidates.isNotEmpty) {
      _timelineDestinationDates(input, logTimeline: true);
    }

    late final List<TripMissingItemSuggestion> missing;
    late final List<TripWardrobePiece> outbound;
    late List<TripWardrobePiece> return_;
    late final List<TripDailyOutfitPreview> destinationPlans;
    var luggagePieces = const <TripWardrobePiece>[];

    if (candidates.isEmpty) {
      outbound = const [];
      return_ = const [];
      destinationPlans = _mergeDestinationInlineWeather(
        input: input,
        weather: weather,
        plans: _emptyDestinationDailyPlans(input),
      );
      luggagePieces = const [];
      missing = _missingWhenNoWardrobe(warmBeach: warmBeach, workTrip: workTrip, cityTrip: cityTrip);
    } else if (warmBeach) {
      final packed = _packWarmBeachSplit(input, candidates);
      outbound = packed.outbound;
      return_ = packed.return_;
      destinationPlans = _mergeDestinationInlineWeather(
        input: input,
        weather: weather,
        plans: _destinationPlansPreferringNotOutboundWear(
          packed.destination,
          outbound,
          candidates,
        ),
      );
      missing = _appendRainShellMissingIfNeeded(
        _missingForTripContext(
          input: input,
          candidates: candidates,
          warmBeach: warmBeach,
          cityTrip: cityTrip,
          workTrip: workTrip,
          hikingTrip: hikingTrip,
          festivalTrip: festivalTrip,
          coolSeason: coolSeason,
          hasWorkEvent: hasWorkEvent,
        ),
        weather,
        candidates,
      );
      _logUsageSplit(outbound, return_, destinationPlans);
    } else {
      final destDayCount = _timelineDestinationDates(input, logTimeline: false).length;
      final full = _buildDailyOutfitsFirst(
        input: input,
        candidates: candidates,
        warmBeach: warmBeach,
        cityTrip: cityTrip,
        workTrip: workTrip,
        hikingTrip: hikingTrip,
        festivalTrip: festivalTrip,
        coolSeason: coolSeason,
        hasWorkEvent: hasWorkEvent,
        destinationDayCount: destDayCount,
      );
      outbound = _genericOutboundTravelPieces(
        input,
        candidates,
        cityTrip: cityTrip,
        workTrip: workTrip,
        hikingTrip: hikingTrip,
        festivalTrip: festivalTrip,
        coolSeason: coolSeason,
        hasWorkEvent: hasWorkEvent,
      );
      return_ = _genericReturnTravelPieces(
        input,
        candidates,
        outbound,
        full,
        cityTrip: cityTrip,
        workTrip: workTrip,
        hikingTrip: hikingTrip,
        festivalTrip: festivalTrip,
        coolSeason: coolSeason,
        hasWorkEvent: hasWorkEvent,
      );
      final destAdjusted = _destinationPlansPreferringNotOutboundWear(
        full,
        outbound,
        candidates,
      );
      destinationPlans = _mergeDestinationInlineWeather(
        input: input,
        weather: weather,
        plans: destAdjusted,
      );
      missing = _appendRainShellMissingIfNeeded(
        _missingForTripContext(
          input: input,
          candidates: candidates,
          warmBeach: warmBeach,
          cityTrip: cityTrip,
          workTrip: workTrip,
          hikingTrip: hikingTrip,
          festivalTrip: festivalTrip,
          coolSeason: coolSeason,
          hasWorkEvent: hasWorkEvent,
        ),
        weather,
        candidates,
      );
      _logUsageSplit(outbound, return_, destinationPlans);
    }

    final hadWardrobe = candidates.isNotEmpty;
    if (hadWardrobe) {
      return_ = _ensureReturnTravelNeverEmptyIfNeeded(
        input: input,
        candidates: candidates,
        outbound: outbound,
        destinationPlans: destinationPlans,
        returnSoFar: return_,
      );
      luggagePieces = _deriveLuggagePieces(
        destinationPlans: destinationPlans,
        candidates: candidates,
        outboundTravel: outbound,
        returnTravel: return_,
      );
      final requestedDays = _timelineDestinationDates(input, logTimeline: false).length;
      debugPrint(
        '[TRIP_DAILY_COUNT] requested=$requestedDays totalGenerated=${destinationPlans.length}',
      );
    }

    debugPrint(
      '[TRIP_PACKING] finalOutbound=${outbound.map((p) => '${p.id}:${p.nameSk}').toList()}',
    );
    debugPrint('[TRIP_PACKING] finalReturn=${return_.map((p) => '${p.id}:${p.nameSk}').toList()}');
    debugPrint(
      '[TRIP_PACKING] finalLuggageItems=${luggagePieces.map((p) => '${p.id}:${p.nameSk}').toList()}',
    );
    debugPrint('[TRIP_PACKING] missingNeeds=${missing.map((m) => m.nameSk).toList()}');

    if (candidates.isNotEmpty) {
      final wornIds = outbound.map((p) => p.id).toSet();
      final usable = candidates.where((c) => !wornIds.contains(c.piece.id)).length;
      debugPrint(
        '[DESTINATION_POOL] usableItems=$usable totalWardrobe=${candidates.length} travelWornCount=${outbound.length}',
      );
    }

    final ow = weather.outboundRoute;
    if (ow != null) {
      debugPrint(
        '[TRIP_WEATHER_INLINE] section=outbound label=${ow.travelDateLabelSk} route=${ow.routeTitleSk} temps=${ow.tempFromC}→${ow.tempToC}°',
      );
    }
    final rw = weather.returnRoute;
    if (rw != null) {
      debugPrint(
        '[TRIP_WEATHER_INLINE] section=return label=${rw.travelDateLabelSk} route=${rw.routeTitleSk} temps=${rw.tempFromC}→${rw.tempToC}°',
      );
    }

    final orderedDest =
        candidates.isEmpty ? destinationPlans : _orderAllDestinationPieces(destinationPlans, candidates);
    final orderedOb =
        candidates.isEmpty ? outbound : _orderPiecesTravelVisual(outbound, candidates);
    final orderedRet =
        candidates.isEmpty ? return_ : _orderPiecesTravelVisual(return_, candidates);

    return TripPackingPlaceholderResult(
      tripDays: input.tripDayCount,
      weather: weather,
      travelOutboundPieces: orderedOb,
      travelReturnPieces: orderedRet,
      luggageItems: luggagePieces,
      destinationDailyPlans: orderedDest,
      missingItems: missing,
      hadWardrobeCandidates: hadWardrobe,
    );
  }

  /// Zaručí neprázdny návratový travel outfit ak existuje čokoľvek v šatníku (uvoľnené filtre A→D).
  static List<TripWardrobePiece> _ensureReturnTravelNeverEmptyIfNeeded({
    required TripPlanInput input,
    required List<_WardrobeCandidate> candidates,
    required List<TripWardrobePiece> outbound,
    required List<TripDailyOutfitPreview> destinationPlans,
    required List<TripWardrobePiece> returnSoFar,
  }) {
    void log(String m) => debugPrint('[TRIP_RETURN_BUILD] $m');

    if (returnSoFar.isNotEmpty) {
      log('skip repair — already ${returnSoFar.length} pieces');
      return returnSoFar;
    }

    log('repair=start outbound=${outbound.length} destPlans=${destinationPlans.length}');

    final usedIds = <String>{};
    for (final p in outbound) {
      usedIds.add(p.id);
    }
    for (final d in destinationPlans) {
      for (final p in d.pieces) {
        usedIds.add(p.id);
      }
    }

    final tops = _piecesMatching(candidates, _topsAliases);
    final shorts = _piecesMatching(candidates, _shortsAliases);
    final longPants = _filter(candidates, _longPantsAliases)
        .where((c) => !_blobMatchesAnyAlias(c.blob, _shortsAliases))
        .map((c) => c.piece)
        .toList();
    final layers = _piecesMatching(candidates, _layerAliases);
    final shoesMix = _buildShoesMix(candidates);
    final anyShoe = _piecesMatching(candidates, _shoesAllAliases);

    final retAnchor = input.returnArrival ?? input.returnDeparture ?? input.climateRangeEnd;
    final retCold = _homeClimateFeelsCold(retAnchor);
    final wantTransportLayer = _transportSuggestsAirportLayer(input.transport);
    final preferLayer = retCold || wantTransportLayer;

    log(
      'pools tops=${tops.length} shorts=${shorts.length} longPants=${longPants.length} '
      'layers=${layers.length} shoesMix=${shoesMix.length} anyShoe=${anyShoe.length} '
      'usedIds=${usedIds.length} retCold=$retCold transport=${input.transport.name}',
    );

    for (var level = 0; level <= 4; level++) {
      final avoid = Set<String>.from(usedIds);

      if (level >= 1) {
        for (final c in candidates) {
          if (_reuseCategoryForPiece(c.piece, candidates) == _PieceReuseCategory.medium) {
            avoid.remove(c.piece.id);
          }
        }
      }
      if (level >= 2) {
        for (final p in [...shoesMix, ...anyShoe]) {
          avoid.remove(p.id);
        }
      }
      if (level >= 3) {
        for (final p in layers) {
          avoid.remove(p.id);
        }
      }
      if (level >= 4) {
        avoid.clear();
      }

      final freshCandidates =
          tops.where((t) => !usedIds.contains(t.id)).map((e) => e.nameSk).toList();
      final relaxedCandidates =
          tops.where((t) => !avoid.contains(t.id)).map((e) => e.nameSk).toList();

      log('freshCandidates=$freshCandidates');
      log('relaxedCandidates=$relaxedCandidates');

      final pieces = <TripWardrobePiece>[];
      void addP(TripWardrobePiece? p) {
        if (p != null && !pieces.any((e) => e.id == p.id)) pieces.add(p);
      }

      if (preferLayer && layers.isNotEmpty) {
        final lp = _pickPieceAvoiding(layers, avoid) ?? (level >= 3 ? layers.first : null);
        addP(lp);
      }

      addP(_pickPieceAvoiding(tops, avoid) ?? (tops.isNotEmpty ? tops.first : null));

      TripWardrobePiece? bottomPick;
      if (retCold) {
        bottomPick =
            _pickPieceAvoiding(longPants, avoid) ?? (longPants.isNotEmpty ? longPants.first : null);
      } else {
        bottomPick = _pickPieceAvoiding(shorts, avoid) ??
            _pickPieceAvoiding(longPants, avoid) ??
            (shorts.isNotEmpty ? shorts.first : null) ??
            (longPants.isNotEmpty ? longPants.first : null);
      }
      addP(bottomPick);

      addP(
        _pickPieceAvoiding(shoesMix, avoid) ??
            _pickPieceAvoiding(anyShoe, avoid) ??
            (shoesMix.isNotEmpty ? shoesMix.first : null) ??
            (anyShoe.isNotEmpty ? anyShoe.first : null),
      );

      if (wantTransportLayer &&
          layers.isNotEmpty &&
          !pieces.any((p) => _blobMatchesAnyAlias(_blobForPiece(p, candidates), _layerAliases))) {
        addP(_pickPieceAvoiding(layers, avoid) ?? layers.first);
      }

      if (pieces.isNotEmpty) {
        final ordered = _orderPiecesTravelVisual(pieces, candidates);
        log('selected=${ordered.map((p) => p.nameSk).toList()}');
        log('fallbackLevel=$level');
        return ordered;
      }
    }

    final emergency = <TripWardrobePiece>[];
    void tryAddPool(List<TripWardrobePiece> pool) {
      for (final p in pool) {
        if (emergency.length >= 4) return;
        if (!emergency.any((e) => e.id == p.id)) emergency.add(p);
      }
    }

    tryAddPool(layers);
    tryAddPool(tops);
    tryAddPool(shorts);
    tryAddPool(longPants);
    tryAddPool(shoesMix);
    tryAddPool(anyShoe);
    for (final c in candidates) {
      if (emergency.length >= 4) break;
      if (!emergency.any((e) => e.id == c.piece.id)) emergency.add(c.piece);
    }

    log('selected=${emergency.map((p) => p.nameSk).toList()}');
    log('fallbackLevel=emergency_any');
    return _orderPiecesTravelVisual(emergency, candidates);
  }

  static DateTime _dateOnlyCalendar(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Jednotný model: dni s realisticky použiteľným časom v destinácii (hodiny podľa zadania).
  static List<DateTime> _timelineDestinationDates(TripPlanInput input, {bool logTimeline = true}) {
    final arrAnchor = input.outboundArrival ?? input.outboundDeparture ?? input.climateRangeStart;
    final retAnchor = input.returnDeparture ?? input.returnArrival ?? input.climateRangeEnd;
    final arrDay = _dateOnlyCalendar(arrAnchor);
    final retDay = _dateOnlyCalendar(retAnchor);
    final arrival = input.outboundArrival;
    final retDep = input.returnDeparture;

    final arrivalAllowsDestinationDay =
        arrival == null ? true : arrival.hour < 16;
    final returnAllowsDestinationDay =
        retDep == null ? true : retDep.hour >= 13;

    void tl(String m) {
      if (logTimeline) debugPrint('[TRIP_TIMELINE] $m');
    }

    tl('arrival=${arrival ?? arrAnchor}');
    tl('departure=${retDep ?? retAnchor}');

    if (retDay.isBefore(arrDay)) {
      tl('arrivalDayIncluded=false returnDayIncluded=false destinationDates=[]');
      return [];
    }

    final out = <DateTime>[];
    for (var d = arrDay; !d.isAfter(retDay); d = d.add(const Duration(days: 1))) {
      final isArr = _dateOnlyCalendar(d) == arrDay;
      final isRet = _dateOnlyCalendar(d) == retDay;
      final middle = !isArr && !isRet;

      bool include;
      if (middle) {
        include = true;
      } else if (arrDay == retDay) {
        include = arrivalAllowsDestinationDay && returnAllowsDestinationDay;
      } else if (isArr) {
        include = arrivalAllowsDestinationDay;
      } else if (isRet) {
        include = returnAllowsDestinationDay;
      } else {
        include = false;
      }
      if (include) out.add(_dateOnlyCalendar(d));
    }

    const maxDestDays = 30;
    final capped = out.length > maxDestDays ? out.sublist(0, maxDestDays) : out;
    final arrivalIncluded = capped.any((x) => _dateOnlyCalendar(x) == arrDay);
    final returnIncluded = capped.any((x) => _dateOnlyCalendar(x) == retDay);

    tl('arrivalDayIncluded=$arrivalIncluded');
    tl('returnDayIncluded=$returnIncluded');
    tl('destinationDates=${capped.map((e) => '${e.year}-${e.month}-${e.day}').toList()}');

    return capped;
  }

  /// Kalendárne dni s použiteľným časom v destinácii (deleguje na [_timelineDestinationDates]).
  static List<DateTime> _destinationCalendarDays(TripPlanInput input) =>
      _timelineDestinationDates(input, logTimeline: false);

  /// Počet kariet „Deň N“ len pre pobyt v destinácii.
  static int _destinationOutfitDayCount(TripPlanInput input) {
    return _timelineDestinationDates(input, logTimeline: false).length.clamp(0, 30);
  }

  /// Len názov mesta pre kompaktné karty (žiadne letiská, kódy ani „Medzinárodné letisko“).
  static String? _cityDisplayFromNormalizedTokens(String n) {
    const cityHit = <String, String>{
      'london': 'Londýn',
      'heathrow': 'Londýn',
      'gatwick': 'Londýn',
      'stansted': 'Londýn',
      'luton': 'Londýn',
      'city airport': 'Londýn',
      'vienna': 'Viedeň',
      'schwechat': 'Viedeň',
      'wien': 'Viedeň',
      'bratislava': 'Bratislava',
      'stefanik': 'Bratislava',
      'stefánik': 'Bratislava',
      'hurghada': 'Hurghada',
      'sharm': 'Sharm El Sheikh',
      'paris': 'Paríž',
      'rome': 'Rím',
      'milan': 'Miláno',
      'munich': 'Mníchov',
      'venice': 'Benátky',
      'frankfurt': 'Frankfurt',
      'amsterdam': 'Amsterdam',
      'prague': 'Praha',
      'praha': 'Praha',
      'budapest': 'Budapest',
      'barcelona': 'Barcelona',
      'madrid': 'Madrid',
      'dublin': 'Dublin',
      'istanbul': 'Istanbul',
      'dubai': 'Dubai',
      'antalya': 'Antalya',
      'cairo': 'Káhira',
      'tel aviv': 'Tel Aviv',
    };
    for (final e in cityHit.entries) {
      if (n.contains(e.key)) return e.value;
    }
    return null;
  }

  static bool _normalizedLooksLikeAirportLine(String n) {
    return n.contains('letisko') ||
        n.contains('airport') ||
        n.contains('international') ||
        n.contains('medzinarodne') ||
        n.contains('flughafen') ||
        n.contains('lufthavn') ||
        n.contains(' aeroport') ||
        n.contains('aeroporto');
  }

  /// Krátke mestské názvy pre karty počasia — výhradne mesto, bez letísk a kódov.
  static String _compactEndpointCitySk(String? raw, {required String fallback}) {
    var s = (raw ?? '').trim();
    if (s.isEmpty) return fallback;

    s = s.replaceFirst(RegExp(r'^\(?[A-Z]{3}\)?\s*[—\-–]\s*'), '');
    s = s.replaceFirst(RegExp(r'^[A-Z]{3}\s*[—\-–]\s*'), '');
    s = s.replaceFirst(RegExp(r'\([A-Z]{3}\)'), '');

    const stripPrefixes = [
      'medzinárodné letisko ',
      'medzinarodne letisko ',
      'letisko m. r. ',
      'letisko m r ',
      'letisko ',
      'international airport ',
      'international ',
      'regional airport ',
    ];
    var low = s.toLowerCase();
    for (final p in stripPrefixes) {
      final pl = p.toLowerCase();
      if (low.startsWith(pl)) {
        s = s.substring(pl.length).trim();
        low = s.toLowerCase();
      }
    }

    for (final suf in [
      ' international airport',
      ' international',
      ' airport',
      'airport',
      ' letisko',
      ' letiště',
      ', airport',
    ]) {
      while (low.endsWith(suf)) {
        s = s.substring(0, s.length - suf.length).trim();
        low = s.toLowerCase();
      }
    }

    s = s.split(',').first.trim();

    final n = DestinationSearchService.normalizeQuery(s);
    final hit = _cityDisplayFromNormalizedTokens(n);
    if (hit != null) return hit;

    if (_normalizedLooksLikeAirportLine(n) && fallback.trim().isNotEmpty) {
      return fallback;
    }

    if (s.length <= 22 && !_normalizedLooksLikeAirportLine(n)) {
      return s;
    }
    return fallback.trim().isNotEmpty ? fallback : '···';
  }

  static String _compactTravelRouteArrowSk(TripPlanInput input, {required bool returnLeg}) {
    final dest = _shortDestLabel(input);
    if (returnLeg) {
      final from = _compactEndpointCitySk(
        input.returnOriginLabel ?? input.selectedDestinationName ?? input.destinationText,
        fallback: dest,
      );
      final to = _compactEndpointCitySk(
        input.returnDestinationLabel ?? input.outboundOriginLabel,
        fallback: 'Domov',
      );
      return '$from → $to';
    }
    final from = _compactEndpointCitySk(input.outboundOriginLabel, fallback: 'Domov');
    final to = _compactEndpointCitySk(
      input.outboundDestinationLabel ?? input.selectedDestinationName ?? input.destinationText,
      fallback: dest,
    );
    return '$from → $to';
  }

  static List<DateTime> _stayCalendarDatesForDestinationPlans(TripPlanInput input, int planCount) {
    final cal = _timelineDestinationDates(input, logTimeline: false);
    if (cal.length == planCount && planCount > 0) return cal;
    if (planCount == 1) {
      final a = input.outboundArrival ?? input.outboundDeparture ?? DateTime.now();
      return [DateTime(a.year, a.month, a.day)];
    }
    final anchor = input.outboundArrival ?? input.outboundDeparture ?? DateTime.now();
    final base = DateTime(anchor.year, anchor.month, anchor.day);
    return List.generate(planCount, (i) => base.add(Duration(days: i)));
  }

  static String _destinationCardTitleSk(
    TripPlanInput input,
    DateTime date,
    int destOrdinal,
    int totalDestDays,
  ) {
    final dayLabel = _skDayLabel(date);
    final suffix = _activitySuffixForNotes(input.activityNotes, destOrdinal, totalDestDays, input.primaryKindForTitles);
    return suffix == null ? dayLabel : '$dayLabel – $suffix';
  }

  static bool _looksUkOrLondon(String destinationText) {
    final t = destinationText.toLowerCase();
    return t.contains('london') ||
        t.contains('londýn') ||
        t.contains('united kingdom') ||
        t.contains(', uk') ||
        t.contains('england');
  }

  static bool _conditionImpliesRain(String condSk) {
    final n = DestinationSearchService.normalizeQuery(condSk);
    const keys = ['dazd', 'daz', 'burk', 'prehan', 'raz', 'storm', 'show', 'rain', 'wet'];
    return keys.any(n.contains);
  }

  /// Chlad, dážď alebo typické „počasím zlé“ dni → mikina/bunda/nohavice namiesto pláže / tielka.
  static bool _needsCoolRainUrbanLook((int high, int low, String cond) w, String destText) {
    final nc = DestinationSearchService.normalizeQuery(w.$3);
    final cloudyCool = (nc.contains('oblac') || nc.contains('cloud')) && w.$1 < 22;

    if (_conditionImpliesRain(w.$3)) return true;
    if (w.$1 < 20) return true;
    if (cloudyCool) return true;

    if (_looksUkOrLondon(destText)) {
      if (w.$1 >= 24 && !_conditionImpliesRain(w.$3) && !cloudyCool) return false;
      return true;
    }
    return false;
  }

  /// Spoločná logika pre chladné / daždivé mestské dni (destinácia aj city break).
  static List<TripWardrobePiece> _buildCoolUrbanDestinationPieces(
    List<_WardrobeCandidate> all,
    (int high, int low, String cond) w,
    int dayIndex,
    String destText,
    Set<String> avoidTopIds,
    Set<String> avoidMediumIds,
    Set<String> avoidShoeIds,
    _TripOutfitRotation? rotation,
  ) {
    final rain = _conditionImpliesRain(w.$3);
    final nc = DestinationSearchService.normalizeQuery(w.$3);
    final cloudyCool = (nc.contains('oblac') || nc.contains('cloud')) && w.$1 < 22;
    final warmDry = w.$1 >= 23 && !rain && !cloudyCool;

    final tops = _piecesMatching(all, _topsAliases);
    final longPants = _filter(all, _longPantsAliases)
        .where((c) => !_blobMatchesAnyAlias(c.blob, _shortsAliases))
        .map((c) => c.piece)
        .toList();
    final shorts = _piecesMatching(all, _shortsAliases);
    final layers = _piecesMatching(all, _layerAliases);
    final sneakers = _piecesMatching(all, _sneakerAliases);
    final shoesMix = _buildShoesMix(all);
    final anyShoe = _piecesMatching(all, _shoesAllAliases);

    String blobFor(TripWardrobePiece p) =>
        all.where((c) => c.piece.id == p.id).firstOrNull?.blob ?? '';

    TripWardrobePiece? pickUrbanLayer() {
      return _pickIntelligentOuterLayer(
        layers: layers,
        all: all,
        tempHighC: w.$1,
        rain: rain,
        avoidIds: avoidTopIds,
        destinationText: destText,
        slot: 'urban_destination',
      );
    }

    TripWardrobePiece? pickTop() {
      final eligible = tops.where((t) => !avoidTopIds.contains(t.id)).toList();
      final nonTank =
          eligible.where((t) => !_blobMatchesAnyAlias(blobFor(t), _tankOnlyAliases)).toList();
      final pool = nonTank.isNotEmpty ? nonTank : eligible;
      final fallbackPool = pool.isNotEmpty ? pool : tops;
      if (fallbackPool.isEmpty) return null;
      if (rotation != null) {
        return _pickRotatedFromPool(
          pool: fallbackPool,
          avoidIds: avoidTopIds,
          rot: rotation,
          all: all,
          axis: _RotPickAxis.top,
          logCategory: 'top',
        );
      }
      if (nonTank.isNotEmpty) return nonTank[dayIndex % nonTank.length];
      if (eligible.isNotEmpty) return eligible[dayIndex % eligible.length];
      return tops[dayIndex % tops.length];
    }

    final i = dayIndex;
    final pieces = <TripWardrobePiece>[];
    void addP(TripWardrobePiece? p) {
      if (p != null && !pieces.any((e) => e.id == p.id)) pieces.add(p);
    }

    final wantLayer = rain ||
        w.$1 < 22 ||
        cloudyCool ||
        (_looksUkOrLondon(destText) && w.$1 < 24);
    if (wantLayer) {
      addP(pickUrbanLayer());
    }

    addP(pickTop());

    TripWardrobePiece? pickBottom() {
      final pool = warmDry && shorts.isNotEmpty
          ? shorts
          : longPants.isNotEmpty
              ? longPants
              : shorts;
      if (pool.isEmpty) return null;
      if (rotation != null) {
        return _pickRotatedFromPool(
          pool: pool,
          avoidIds: avoidMediumIds,
          rot: rotation,
          all: all,
          axis: _RotPickAxis.bottom,
          logCategory: warmDry && shorts.isNotEmpty ? 'shorts' : 'bottoms',
        );
      }
      final a = _pickPieceAvoiding(pool, avoidMediumIds);
      return a ?? pool[i % pool.length];
    }

    final bottomPick = pickBottom();
    addP(bottomPick);

    TripWardrobePiece? pickShoe() {
      if (rotation != null) {
        if (sneakers.isNotEmpty) {
          return _pickRotatedFromPool(
            pool: sneakers,
            avoidIds: avoidShoeIds,
            rot: rotation,
            all: all,
            axis: _RotPickAxis.shoe,
            logCategory: 'sneakers',
          );
        }
        if (shoesMix.isNotEmpty) {
          return _pickRotatedFromPool(
            pool: shoesMix,
            avoidIds: avoidShoeIds,
            rot: rotation,
            all: all,
            axis: _RotPickAxis.shoe,
            logCategory: 'shoes',
          );
        }
        if (anyShoe.isEmpty) return null;
        final nonSand =
            anyShoe.where((p) => !_blobMatchesAnyAlias(blobFor(p), _sandalAliases)).toList();
        final pool = nonSand.isNotEmpty ? nonSand : anyShoe;
        return _pickRotatedFromPool(
          pool: pool,
          avoidIds: avoidShoeIds,
          rot: rotation,
          all: all,
          axis: _RotPickAxis.shoe,
          logCategory: 'shoes',
        );
      }
      if (sneakers.isNotEmpty) {
        final a = _pickPieceAvoiding(sneakers, avoidShoeIds);
        return a ?? sneakers[i % sneakers.length];
      }
      if (shoesMix.isNotEmpty) {
        final a = _pickPieceAvoiding(shoesMix, avoidShoeIds);
        return a ?? shoesMix[i % shoesMix.length];
      }
      if (anyShoe.isEmpty) return null;
      final nonSand =
          anyShoe.where((p) => !_blobMatchesAnyAlias(blobFor(p), _sandalAliases)).toList();
      final pool = nonSand.isNotEmpty ? nonSand : anyShoe;
      final a = _pickPieceAvoiding(pool, avoidShoeIds);
      return a ?? pool[i % pool.length];
    }

    addP(pickShoe());

    return _orderPiecesTravelVisual(pieces, all);
  }

  static bool _lateNightArrival(DateTime? t) {
    if (t == null) return false;
    final h = t.hour;
    return h >= 23 || h <= 5;
  }

  static ({
    List<TripWardrobePiece> outbound,
    List<TripWardrobePiece> return_,
    List<TripDailyOutfitPreview> destination,
  }) _packWarmBeachSplit(TripPlanInput input, List<_WardrobeCandidate> all) {
    final ledger = _TripPackLedger(all);
    final rotation = _TripOutfitRotation();
    final destDays = _timelineDestinationDates(input, logTimeline: false);
    final calendarSpan = input.tripDayCount;
    final cityTrip = input.tripKinds.contains(TripKind.cityBreak);
    final destText =
        '${input.destinationText} ${input.selectedDestinationName ?? ''} ${input.destinationCountry ?? ''}';
    const warmBeachCtx = true;

    final outboundPieces = _warmBeachOutboundPieces(input, all);
    ledger.registerWear(outboundPieces, 'outbound');
    debugPrint(
      '[TRIP_TRAVEL_OUTFIT] direction=outbound items=${outboundPieces.map((p) => p.nameSk).toList()}',
    );

    final destPlans = <TripDailyOutfitPreview>[];
    if (destDays.isEmpty) {
      // žiadna destinácia s použiteľným dňom podľa časov príchodu/odchodu
    } else if (destDays.length == 1) {
      final single = _warmBeachSingleDestinationDayV2(
        input,
        all,
        ledger,
        rotation: rotation,
        destText: destText,
        cityTrip: cityTrip,
        warmBeach: warmBeachCtx,
      );
      ledger.registerDestinationDay(single.pieces, 1);
      _rotationNoteDestinationDay(rotation, single.pieces, all);
      destPlans.add(single);
    } else {
      var ordinal = 1;
      for (var i = 0; i < destDays.length; i++) {
        final lightDay =
            i == 0 && _lateNightArrival(input.outboundArrival) && destDays.length > 1;
        final plan = _warmBeachDestinationDayV2(
          input,
          all,
          ledger,
          rotation: rotation,
          destDayOrdinal: ordinal,
          totalDestDays: destDays.length,
          preferLightOutfit: lightDay,
          destText: destText,
          cityTrip: cityTrip,
          warmBeach: warmBeachCtx,
          stayDayIndex: i,
        );
        ledger.registerDestinationDay(plan.pieces, ordinal);
        _rotationNoteDestinationDay(rotation, plan.pieces, all);
        destPlans.add(plan);
        ordinal++;
      }
    }

    final returnPieces = calendarSpan >= 2
        ? _warmBeachReturnPiecesV2(input, all, outboundPieces, ledger)
        : <TripWardrobePiece>[];
    _ensureDistinctLowTops(outboundPieces, returnPieces, all);
    if (returnPieces.isNotEmpty) {
      ledger.registerWear(returnPieces, 'return');
    }
    debugPrint(
      '[TRIP_TRAVEL_OUTFIT] direction=return items=${returnPieces.map((p) => p.nameSk).toList()}',
    );

    return (outbound: outboundPieces, return_: returnPieces, destination: destPlans);
  }

  /// Návratový outfit (ne-plážové výlety): vyhni sa topom a spodkom už „opotrebovaným“ v destinácii.
  static void _ensureReturnAvoidsDestinationWear(
    List<TripWardrobePiece> return_,
    List<TripDailyOutfitPreview> destPlans,
    List<_WardrobeCandidate> all,
    TripPlanInput input,
    List<TripWardrobePiece> outboundPieces,
  ) {
    final wornLow = <String>{};
    final wornMed = <String>{};
    for (final d in destPlans) {
      for (final p in d.pieces) {
        final c = _reuseCategoryForPiece(p, all);
        if (c == _PieceReuseCategory.low) wornLow.add(p.id);
        if (c == _PieceReuseCategory.medium) wornMed.add(p.id);
      }
    }

    final tops = _piecesMatching(all, _topsAliases);
    final shorts = _piecesMatching(all, _shortsAliases);
    final longPants = _filter(all, _longPantsAliases)
        .where((c) => !_blobMatchesAnyAlias(c.blob, _shortsAliases))
        .map((c) => c.piece)
        .toList();

    void trySwapTop(int i, TripWardrobePiece p) {
      if (_reuseCategoryForPiece(p, all) != _PieceReuseCategory.low) return;
      if (!wornLow.contains(p.id)) return;
      final alt = _pickPieceAvoiding(tops, wornLow);
      if (alt != null && alt.id != p.id) return_[i] = alt;
    }

    void trySwapBottom(int i, TripWardrobePiece p) {
      if (_reuseCategoryForPiece(p, all) != _PieceReuseCategory.medium) return;
      if (!wornMed.contains(p.id)) return;
      final pool = [...shorts, ...longPants];
      final alt = _pickPieceAvoiding(pool, wornMed);
      if (alt != null && alt.id != p.id) return_[i] = alt;
    }

    for (var i = 0; i < return_.length; i++) {
      trySwapTop(i, return_[i]);
    }
    for (var i = 0; i < return_.length; i++) {
      trySwapBottom(i, return_[i]);
    }

    final obLayer = _firstLayerFromPieces(outboundPieces, all);
    _WardrobeCandidate? obCand;
    for (final c in all) {
      if (c.piece.id == obLayer?.id) {
        obCand = c;
        break;
      }
    }
    if (input.transport == TripTransport.plane &&
        obLayer != null &&
        obCand != null &&
        _blobMatchesAnyAlias(obCand.blob, _layerAliases)) {
      if (!return_.any((e) => e.id == obLayer.id)) {
        return_.insert(0, obLayer);
      }
    }

    debugPrint(
      '[TRIP_RETURN_OUTFIT] selected=${return_.map((p) => p.nameSk).toList()} avoidedUsedLowReuse=${wornLow.length} avoidedMedium=${wornMed.length}',
    );
  }

  static void _ensureDistinctLowTops(
    List<TripWardrobePiece> outbound,
    List<TripWardrobePiece> return_,
    List<_WardrobeCandidate> all,
  ) {
    TripWardrobePiece? outboundLow;
    for (final p in outbound) {
      if (_reuseCategoryForPiece(p, all) == _PieceReuseCategory.low) {
        outboundLow = p;
        break;
      }
    }
    if (outboundLow == null) return;

    var reIdx = -1;
    for (var i = 0; i < return_.length; i++) {
      if (_reuseCategoryForPiece(return_[i], all) == _PieceReuseCategory.low) {
        reIdx = i;
        break;
      }
    }
    if (reIdx < 0 || return_[reIdx].id != outboundLow.id) return;

    final tops = _piecesMatching(all, _topsAliases);
    TripWardrobePiece? alt;
    for (final t in tops) {
      if (t.id != outboundLow.id) {
        alt = t;
        break;
      }
    }
    if (alt != null) {
      return_[reIdx] = alt;
    }
  }

  static List<TripDailyOutfitPreview> _emptyDestinationDailyPlans(TripPlanInput input) {
    final timelineN = _timelineDestinationDates(input, logTimeline: false).length;
    final n = timelineN > 0 ? timelineN : (input.tripDayCount <= 1 ? 1 : 0);
    if (n == 0) return [];
    return List.generate(
      n,
      (i) => TripDailyOutfitPreview(
        dayIndex: i + 1,
        titleSk: 'Deň ${i + 1}',
        summarySk:
            'Do šatníka zatiaľ nemáme žiadny kúsok s fotkou na zobrazenie. Pridaj oblečenie so snímkou.',
        dayHintSk: null,
        pieces: const [],
      ),
    );
  }

  static String _destinationTitleSk(
    int destOrdinal,
    int totalDestDays,
    String notes,
    TripKind kind,
  ) {
    final suffix = _activitySuffixForNotes(notes, destOrdinal, totalDestDays, kind);
    return suffix == null ? 'Deň $destOrdinal' : 'Deň $destOrdinal – $suffix';
  }

  static String? _activitySuffixForNotes(
    String notes,
    int destOrdinal,
    int totalDestDays,
    TripKind kind,
  ) {
    final n = notes.trim().toLowerCase();
    if (n.isEmpty) return null;
    if ((n.contains('večera pri mori') || (n.contains('večera') && n.contains('mor'))) &&
        destOrdinal == totalDestDays) {
      return 'večera pri mori';
    }
    if ((n.contains('stretnutie') || n.contains('meeting') || n.contains('konferenc')) &&
        destOrdinal == 1 &&
        kind == TripKind.business) {
      return 'pracovné stretnutie';
    }
    if ((n.contains('loď') || n.contains('lod') || n.contains('boat')) && destOrdinal == 1) {
      return 'výlet loďou';
    }
    return null;
  }

  /// Do batožiny: všetky kusy z outfity v destinácii + všetky z návratu (musia ísť z domu).
  /// Kusy len na „cestu tam“ sa sem nepridávajú samostatne; ak sa opakujú v destinácii alebo na návrate, zostanú v zozname cez tie sekcie.
  static List<TripWardrobePiece> _deriveLuggagePieces({
    required List<TripDailyOutfitPreview> destinationPlans,
    required List<_WardrobeCandidate> candidates,
    List<TripWardrobePiece> outboundTravel = const [],
    List<TripWardrobePiece> returnTravel = const [],
  }) {
    final byId = {for (final c in candidates) c.piece.id: c.piece};
    final seen = <String>{};
    final luggage = <TripWardrobePiece>[];

    final destItems = <TripWardrobePiece>[];
    for (final d in destinationPlans) {
      for (final p in d.pieces) {
        destItems.add(byId[p.id] ?? p);
      }
    }

    for (final p in destItems) {
      if (seen.add(p.id)) luggage.add(p);
    }

    for (final p in returnTravel) {
      final full = byId[p.id] ?? p;
      if (seen.add(full.id)) luggage.add(full);
    }

    debugPrint(
      '[TRIP_LUGGAGE_REQUIRED] destinationItems=${destItems.map((p) => '${p.id}:${p.nameSk}').toList()}',
    );
    debugPrint(
      '[TRIP_LUGGAGE_REQUIRED] returnItems=${returnTravel.map((p) => '${p.id}:${p.nameSk}').toList()}',
    );
    debugPrint(
      '[LUGGAGE_FILTER] outboundOnlyNotAddedAlone=${outboundTravel.map((p) => p.nameSk).toList()} '
      '(ids=${outboundTravel.map((p) => p.id).join(',')})',
    );

    var sorted = _orderLuggageVisual(luggage, candidates);

    final luggageIds = sorted.map((p) => p.id).toSet();
    final missingFromLuggage = <TripWardrobePiece>[];
    for (final p in returnTravel) {
      final full = byId[p.id] ?? p;
      if (!luggageIds.contains(full.id)) {
        missingFromLuggage.add(full);
        luggageIds.add(full.id);
      }
    }
    if (missingFromLuggage.isNotEmpty) {
      sorted = _orderLuggageVisual([...sorted, ...missingFromLuggage], candidates);
    }

    debugPrint(
      '[TRIP_CONSISTENCY_CHECK] returnItemsMissingFromLuggage=${missingFromLuggage.map((p) => p.nameSk).toList()}',
    );
    debugPrint(
      '[TRIP_LUGGAGE_FINAL] items=${sorted.map((p) => '${p.id}:${p.nameSk}').toList()}',
    );
    debugPrint('[TRIP_LUGGAGE_ORDER] orderedItems=${sorted.map((p) => p.nameSk).join('|')}');
    return sorted;
  }

  /// Destinačné outfity: nahradí rovnaké top/spodok/obuv ako na odlete, ak existuje alternatíva v šatníku.
  static List<TripDailyOutfitPreview> _destinationPlansPreferringNotOutboundWear(
    List<TripDailyOutfitPreview> plans,
    List<TripWardrobePiece> outboundWear,
    List<_WardrobeCandidate> all,
  ) {
    if (plans.isEmpty || outboundWear.isEmpty) return plans;

    final obLow = <String>{};
    final obMed = <String>{};
    final obShoe = <String>{};
    for (final p in outboundWear) {
      final c = _reuseCategoryForPiece(p, all);
      if (c == _PieceReuseCategory.low) obLow.add(p.id);
      if (c == _PieceReuseCategory.medium) obMed.add(p.id);
      final blob = all.where((x) => x.piece.id == p.id).firstOrNull?.blob ?? '';
      if (_blobMatchesAnyAlias(blob, _shoesAllAliases)) obShoe.add(p.id);
    }

    final tops = _piecesMatching(all, _topsAliases);
    final shorts = _piecesMatching(all, _shortsAliases);
    final longPants = _filter(all, _longPantsAliases)
        .where((c) => !_blobMatchesAnyAlias(c.blob, _shortsAliases))
        .map((c) => c.piece)
        .toList();
    final bottomPool = _uniquePieces([...shorts, ...longPants]);
    final shoesMix = _buildShoesMix(all);
    final shoePool = shoesMix.isNotEmpty ? shoesMix : _piecesMatching(all, _shoesAllAliases);

    List<TripWardrobePiece> swapPieces(List<TripWardrobePiece> pieces) {
      final used = <String>{};
      final out = <TripWardrobePiece>[];
      for (final p in pieces) {
        var q = p;
        final c = _reuseCategoryForPiece(p, all);
        if (c == _PieceReuseCategory.low && obLow.contains(p.id)) {
          final alt = _pickPieceAvoiding(tops, {...obLow, ...used});
          if (alt != null && alt.id != p.id) q = alt;
        } else if (c == _PieceReuseCategory.medium && obMed.contains(p.id)) {
          final alt = _pickPieceAvoiding(bottomPool, {...obMed, ...used});
          if (alt != null && alt.id != p.id) q = alt;
        } else if (obShoe.contains(p.id)) {
          final alt = _pickPieceAvoiding(shoePool, {...obShoe, ...used});
          if (alt != null && alt.id != p.id) q = alt;
        }
        if (!used.contains(q.id)) {
          used.add(q.id);
          out.add(q);
        } else {
          used.add(p.id);
          out.add(p);
        }
      }
      return out;
    }

    final out = <TripDailyOutfitPreview>[];
    for (final d in plans) {
      final newPieces = swapPieces(d.pieces);
      out.add(
        TripDailyOutfitPreview(
          dayIndex: d.dayIndex,
          titleSk: d.titleSk,
          summarySk: _summaryFromPieces(newPieces),
          dayHintSk: d.dayHintSk,
          pieces: newPieces,
          weatherDateLabelSk: d.weatherDateLabelSk,
          weatherPlaceSk: d.weatherPlaceSk,
          weatherHighC: d.weatherHighC,
          weatherLowC: d.weatherLowC,
          weatherConditionSk: d.weatherConditionSk,
        ),
      );
    }
    return out;
  }

  static String _summaryFromPieces(List<TripWardrobePiece> pieces) {
    return pieces.isEmpty
        ? 'Z aktuálneho výberu neviem poskladať kombináciu.'
        : pieces.map((e) => e.nameSk).join(', ');
  }

  static List<TripDailyOutfitPreview> _mergeDestinationInlineWeather({
    required TripPlanInput input,
    required TripWeatherBundle weather,
    required List<TripDailyOutfitPreview> plans,
  }) {
    final place = _shortDestLabel(input);
    final stay = weather.destinationStayDays;
    final dates = _stayCalendarDatesForDestinationPlans(input, plans.length);
    final total = plans.length;
    for (var i = 0; i < plans.length; i++) {
      if (i >= stay.length) continue;
      final w = stay[i];
      debugPrint(
        '[TRIP_WEATHER_INLINE] section=destination day=${plans[i].dayIndex} label=${w.label} place=$place temps=${w.highTempC}/${w.lowTempC}° ${w.conditionSk}',
      );
    }
    return [
      for (var i = 0; i < plans.length; i++)
        TripDailyOutfitPreview(
          dayIndex: plans[i].dayIndex,
          titleSk: i < dates.length
              ? _destinationCardTitleSk(input, dates[i], plans[i].dayIndex, total)
              : plans[i].titleSk,
          summarySk: plans[i].summarySk,
          dayHintSk: plans[i].dayHintSk,
          pieces: plans[i].pieces,
          weatherDateLabelSk: null,
          weatherPlaceSk: place,
          weatherHighC: i < stay.length ? stay[i].highTempC : null,
          weatherLowC: i < stay.length ? stay[i].lowTempC : null,
          weatherConditionSk: i < stay.length ? stay[i].conditionSk : null,
        ),
    ];
  }

  static void _logUsageSplit(
    List<TripWardrobePiece> outbound,
    List<TripWardrobePiece> return_,
    List<TripDailyOutfitPreview> destination,
  ) {
    debugPrint('[TRAVEL_WORN] items=${outbound.map((p) => p.nameSk).toList()}');
    debugPrint('[TRIP_PACKING_USAGE] outbound=${outbound.map((p) => p.nameSk).toList()}');
    debugPrint('[TRIP_PACKING_USAGE] return=${return_.map((p) => p.nameSk).toList()}');
    for (final d in destination) {
      debugPrint(
        '[TRIP_PACKING_USAGE] dest ${d.titleSk} => ${d.pieces.map((p) => p.nameSk).toList()}',
      );
    }
  }

  static List<TripMissingItemSuggestion> _missingWhenNoWardrobe({
    required bool warmBeach,
    required bool workTrip,
    required bool cityTrip,
  }) {
    if (warmBeach) {
      return [
        const TripMissingItemSuggestion(
          nameSk: 'Nemáš žiadne kúsky s fotkou v šatníku',
          reasonSk: 'Pridaj oblečenie alebo sa prihlás.',
        ),
        const TripMissingItemSuggestion(nameSk: 'Nemáš ľahké kraťasy', reasonSk: 'Na horúce dni.'),
        const TripMissingItemSuggestion(nameSk: 'Nemáš vhodné sandále', reasonSk: 'Na pláž a teplo.'),
      ];
    }
    return const [
      TripMissingItemSuggestion(
        nameSk: 'Nemáš žiadne kúsky s fotkou v šatníku',
        reasonSk: 'Pridaj oblečenie alebo sa prihlás.',
      ),
    ];
  }

  /// Rovnaká priorita ako [resolveHeroHomeOutfitImageUrl]: cutout → clean → product → imageUrl → original.
  static List<String> _heroOrderedTripImageUrlsFromRaw(Map<String, dynamic> raw) {
    String? g(String k) {
      final v = raw[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final out = <String>[];
    void add(String? s) {
      if (s == null || s.isEmpty) return;
      if (!out.contains(s)) out.add(s);
    }

    add(g('cutoutImageUrl'));
    add(g('cleanImageUrl'));
    add(g('productImageUrl'));
    add(g('imageUrl'));
    add(g('originalImageUrl'));
    return out;
  }

  static Future<List<_WardrobeCandidate>> _loadCandidates(String? userId) async {
    if (userId == null || userId.isEmpty) return const [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('wardrobe')
          .get();
      final out = <_WardrobeCandidate>[];
      for (final d in snap.docs) {
        final raw = Map<String, dynamic>.from(d.data());
        final name = (raw['name'] ?? raw['title'] ?? raw['displayName'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final urls = _heroOrderedTripImageUrlsFromRaw(raw);
        final url = urls.isNotEmpty ? urls.first : resolveHeroHomeOutfitImageUrl(raw);
        if (url == null || url.isEmpty) continue;
        final cut = (raw['cutoutImageUrl'] ?? '').toString();
        final cln = (raw['cleanImageUrl'] ?? '').toString();
        final prd = (raw['productImageUrl'] ?? '').toString();
        final leg = (raw['imageUrl'] ?? '').toString();
        final org = (raw['originalImageUrl'] ?? '').toString();
        debugPrint(
          '[TRIP_IMAGE_PICK] item=$name cutout=$cut clean=$cln product=$prd imageUrl=$leg original=$org picked=$url',
        );
        final blob = _buildSearchBlob(raw, fallbackName: name);
        out.add(
          _WardrobeCandidate(
            piece: TripWardrobePiece(
              id: d.id,
              nameSk: name,
              imageUrl: url,
              imageDisplayUrls: urls,
            ),
            blob: blob,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Spojí všetky zmysluplné textové polia dokumentu do jedného normalizovaného reťazca.
  static String _buildSearchBlob(Map<String, dynamic> raw, {required String fallbackName}) {
    final parts = <String>[fallbackName];

    void add(dynamic v) {
      if (v == null) return;
      if (v is String) {
        if (v.trim().isNotEmpty) parts.add(v);
      } else if (v is num) {
        parts.add(v.toString());
      } else if (v is List) {
        for (final e in v) {
          add(e);
        }
      } else if (v is Map) {
        v.forEach((_, val) => add(val));
      }
    }

    for (final key in [
      'type',
      'type_pretty',
      'canonical_type',
      'categoryKey',
      'subCategoryKey',
      'mainGroupKey',
      'subtype',
      'category',
      'subcategory',
      'brand',
      'description',
      'notes',
    ]) {
      add(raw[key]);
    }
    add(raw['colors']);
    add(raw['seasons']);
    add(raw['styles']);
    add(raw['patterns']);
    add(raw['tags']);
    add(raw['materials']);

    return _norm(parts.join(' '));
  }

  static String _norm(String s) {
    const diacritics = {
      'á': 'a',
      'ä': 'a',
      'č': 'c',
      'ď': 'd',
      'é': 'e',
      'ě': 'e',
      'í': 'i',
      'ľ': 'l',
      'ĺ': 'l',
      'ň': 'n',
      'ó': 'o',
      'ô': 'o',
      'ř': 'r',
      'š': 's',
      'ť': 't',
      'ú': 'u',
      'ů': 'u',
      'ý': 'y',
      'ž': 'z',
    };
    final lower = s.toLowerCase().trim();
    final b = StringBuffer();
    for (final r in lower.runes) {
      final ch = String.fromCharCode(r);
      b.write(diacritics[ch] ?? ch);
    }
    return b.toString();
  }

  static List<String> _normList(List<String> raw) => raw.map(_norm).toList();

  static bool _blobMatchesAnyAlias(String blob, List<String> aliases) {
    for (final a in aliases) {
      if (a.isEmpty) continue;
      if (blob.contains(a)) return true;
    }
    return false;
  }

  // --- Vrstvy: izolácia / styling (nie „dážď = zimná bunda“) ---

  /// 2 = mikina/hoodie, 3 = ľahká bunda/dážďovka/bomber, 4 = kabát/prechodný plášť, 5 = zima/perovka.
  static int _layerInsulationWeight(String blob, String nameSk) {
    final fused = _norm('$blob $nameSk');

    if (_blobMatchesAnyAlias(
      fused,
      _normList(const [
        'zimna bunda',
        'zimná bunda',
        'winter jacket',
        'winter coat',
        'parka',
        'puffer',
        'puff ',
        'down jacket',
        'duvet',
        'perova',
        'péřová',
        'perova bunda',
        'husky',
        'arctic',
        'insulated jacket',
        'thermal jacket',
        'tepla bunda',
        'teplá bunda',
      ]),
    )) {
      return 5;
    }

    if (_blobMatchesAnyAlias(
      fused,
      _normList(const [
        'kabat',
        'kabát',
        'wool coat',
        'coat dress',
        'long coat',
        'overcoat',
        'plášť',
        'plast',
        'trenchcoat',
      ]),
    )) {
      return 4;
    }

    if (_blobMatchesAnyAlias(
      fused,
      _normList(const [
        'mikina',
        'hoodie',
        'sweatshirt',
        'sveter',
        'cardigan',
        'fleece mikina',
        'fleece pulover',
        'pulover',
        'rollneck',
      ]),
    )) {
      return 2;
    }

    if (_blobMatchesAnyAlias(
      fused,
      _normList(const [
        'bomber',
        'trench',
        'prechodna',
        'prechodná',
        'lahka bunda',
        'ľahká bunda',
        'rain jacket',
        'raincoat',
        'nepromok',
        'windbreaker',
        'wind breaker',
        'softshell',
        'shell jacket',
        'anorak',
      ]),
    )) {
      return 3;
    }

    if (_blobMatchesAnyAlias(fused, _normList(const ['fleece', 'fleeceová']))) {
      return 2;
    }

    if (_blobMatchesAnyAlias(fused, _normList(const ['bunda', 'jacket', 'coat']))) {
      return 3;
    }

    return 3;
  }

  static String _layerWarmthLabel(int w) {
    switch (w) {
      case 2:
        return 'medium_knit';
      case 3:
        return 'light_outer';
      case 4:
        return 'transitional_coat';
      case 5:
        return 'heavy_winter';
      default:
        return 'outer_unknown';
    }
  }

  /// Horná hranica izolácie vrstvy podľa °C (nízka teplota = vyššie číslo povolené).
  static int _maxLayerInsulationForTemp(int tempHighC) {
    if (tempHighC >= 28) return 0;
    if (tempHighC >= 20) return 3;
    if (tempHighC >= 14) return 3;
    if (tempHighC >= 5) return 4;
    return 5;
  }

  static bool _isMildEuropeanUrbanDestination(String destText) {
    final n = DestinationSearchService.normalizeQuery(destText);
    const keys = [
      'london',
      'londyn',
      'amsterdam',
      'prague',
      'praha',
      'vienna',
      'vieden',
      'wien',
      'berlin',
      'paris',
      'barcelona',
      'madrid',
      'dublin',
      'edinburgh',
      'brussels',
      'brussel',
      'budapest',
      'warsaw',
      'krakow',
      'krakov',
    ];
    return keys.any(n.contains);
  }

  /// Nižší = lepší pri výbere medzi vhodnými vrstvami (stylista).
  static int _layerStylistPriorityRank(
    TripWardrobePiece p,
    String blob,
    int insulation,
    bool rain,
    int tempHighC,
  ) {
    final n = DestinationSearchService.normalizeQuery(blob);
    final hasHood = n.contains('kapuc') || n.contains('hood');
    final rainShell =
        n.contains('nepromok') || n.contains('rain') || n.contains('waterproof') || n.contains('storm');

    if (rain) {
      if (insulation <= 2 && hasHood) return 0;
      if (insulation <= 2) return 1;
      if (rainShell || n.contains('shell') || n.contains('windbreaker')) return 2;
      if (insulation <= 3) return 3;
      return 10 + insulation;
    }
    if (tempHighC >= 20) {
      if (insulation <= 2) return 0;
      if (insulation <= 3) return 2;
      return 10 + insulation;
    }
    if (insulation <= 2) return 0;
    if (insulation <= 3) return 1;
    return 5 + insulation;
  }

  /// Vyber jednu vrstvu podľa počasia; zimná bunda len pri nízkych °C alebo ako úplne posledná možnosť.
  static TripWardrobePiece? _pickIntelligentOuterLayer({
    required List<TripWardrobePiece> layers,
    required List<_WardrobeCandidate> all,
    required int tempHighC,
    required bool rain,
    required Set<String> avoidIds,
    required String destinationText,
    required String slot,
  }) {
    if (layers.isEmpty) return null;

    String blobFor(TripWardrobePiece p) =>
        all.where((c) => c.piece.id == p.id).firstOrNull?.blob ?? '';

    var maxInsulation = _maxLayerInsulationForTemp(tempHighC);
    if (_isMildEuropeanUrbanDestination(destinationText) && tempHighC >= 8 && tempHighC <= 19) {
      maxInsulation = maxInsulation.clamp(1, 3);
    }

    void logScores() {
      for (final p in layers) {
        final b = blobFor(p);
        final w = _layerInsulationWeight(b, p.nameSk);
        debugPrint(
          '[WEATHER_LAYER_SCORE] slot=$slot item=${p.nameSk} warmth=${_layerWarmthLabel(w)} insulation=$w temp=${tempHighC}C rain=$rain',
        );
      }
    }

    logScores();

    if (maxInsulation <= 0) {
      debugPrint(
        '[WEATHER_LAYER_REASON] slot=$slot skip outer layer — temp=${tempHighC}C warm enough for light clothing only',
      );
      return null;
    }

    TripWardrobePiece? pickFromPool(List<TripWardrobePiece> pool, String reason) {
      final ranked = pool
          .where((p) => !avoidIds.contains(p.id))
          .map((p) {
            final b = blobFor(p);
            final ins = _layerInsulationWeight(b, p.nameSk);
            final rank = _layerStylistPriorityRank(p, b, ins, rain, tempHighC);
            return (p, ins, rank);
          })
          .toList()
        ..sort((a, b) {
          final c = a.$3.compareTo(b.$3);
          if (c != 0) return c;
          return a.$2.compareTo(b.$2);
        });

      if (ranked.isEmpty) return null;
      final chosen = ranked.first.$1;
      final chosenBlob = blobFor(chosen);
      final chosenIns = _layerInsulationWeight(chosenBlob, chosen.nameSk);
      final rejected = pool
          .where((p) => p.id != chosen.id)
          .map((p) => '${p.nameSk}:${_layerWarmthLabel(_layerInsulationWeight(blobFor(p), p.nameSk))}')
          .join(', ');
      debugPrint(
        '[WEATHER_LAYER_PICK] slot=$slot weather=${tempHighC}C rain=$rain selected=${chosen.nameSk}(${_layerWarmthLabel(chosenIns)}) rejected=[$rejected]',
      );
      debugPrint('[WEATHER_LAYER_REASON] slot=$slot $reason');
      final hadHeavy = pool.any((p) => _layerInsulationWeight(blobFor(p), p.nameSk) >= 5);
      if (hadHeavy && chosenIns <= 3 && tempHighC >= 5) {
        debugPrint(
          '[WEATHER_LAYER_REASON] slot=$slot selected ${_layerWarmthLabel(chosenIns)} over winter jacket because temp=${tempHighC}C',
        );
      }
      return chosen;
    }

    final eligible = layers.where((p) {
      final ins = _layerInsulationWeight(blobFor(p), p.nameSk);
      return ins <= maxInsulation;
    }).toList();

    if (eligible.isNotEmpty) {
      return pickFromPool(
        eligible,
        'prefer knit/light outer (cap≤${_layerWarmthLabel(maxInsulation)}) for temp=${tempHighC}C rain=$rain — '
        'avoid heavy winter unless cold',
      );
    }

    final softer = layers.where((p) {
      final ins = _layerInsulationWeight(blobFor(p), p.nameSk);
      return ins < 5;
    }).toList();
    if (softer.isNotEmpty) {
      return pickFromPool(
        softer,
        'no piece within strict cap; avoided heavy winter — picking softer layer for temp=${tempHighC}C',
      );
    }

    final fallback = pickFromPool(
      layers,
      'last resort only: wardrobe appears heavy-only; temp=${tempHighC}C — using warmest available',
    );
    if (fallback != null) {
      debugPrint(
        '[WEATHER_LAYER_REASON] slot=$slot selected winter/heavy only because no lighter outerwear matched',
      );
    }
    return fallback;
  }

  static TripWardrobePiece? _pickTravelOuterLayerForHomeClimate({
    required List<TripWardrobePiece> layers,
    required List<_WardrobeCandidate> all,
    required int estimatedTempC,
    required TripPlanInput input,
    required String slot,
  }) {
    return _pickIntelligentOuterLayer(
      layers: layers,
      all: all,
      tempHighC: estimatedTempC,
      rain: false,
      avoidIds: const {},
      destinationText:
          '${input.destinationText} ${input.selectedDestinationName ?? ''} ${input.destinationCountry ?? ''}',
      slot: slot,
    );
  }

  static _PieceReuseCategory _reuseCategoryFromBlob(String blob) {
    if (_blobMatchesAnyAlias(blob, _layerAliases)) return _PieceReuseCategory.high;
    if (_blobMatchesAnyAlias(blob, _bagAliases)) return _PieceReuseCategory.high;
    if (_blobMatchesAnyAlias(blob, _hatAliases)) return _PieceReuseCategory.high;
    if (_blobMatchesAnyAlias(blob, _sunglassesAliases)) return _PieceReuseCategory.high;
    if (_blobMatchesAnyAlias(blob, _shoesAllAliases)) return _PieceReuseCategory.high;
    if (_blobMatchesAnyAlias(blob, _topsAliases)) return _PieceReuseCategory.low;
    if (_blobMatchesAnyAlias(blob, _shortsAliases) || _blobMatchesAnyAlias(blob, _longPantsAliases)) {
      return _PieceReuseCategory.medium;
    }
    if (_blobMatchesAnyAlias(blob, _swimAliases)) return _PieceReuseCategory.medium;
    return _PieceReuseCategory.medium;
  }

  static _PieceReuseCategory _reuseCategoryForPiece(TripWardrobePiece p, List<_WardrobeCandidate> all) {
    for (final c in all) {
      if (c.piece.id == p.id) return _reuseCategoryFromBlob(c.blob);
    }
    return _PieceReuseCategory.medium;
  }

  static List<_WardrobeCandidate> _filter(
    List<_WardrobeCandidate> src,
    List<String> aliases,
  ) {
    return src.where((c) => _blobMatchesAnyAlias(c.blob, aliases)).toList();
  }

  static List<TripWardrobePiece> _piecesMatching(List<_WardrobeCandidate> all, List<String> aliases) {
    final out = <TripWardrobePiece>[];
    final seen = <String>{};
    for (final wc in all) {
      if (!_blobMatchesAnyAlias(wc.blob, aliases)) continue;
      if (seen.add(wc.piece.id)) out.add(wc.piece);
    }
    return out;
  }

  static List<TripWardrobePiece> _buildShoesMix(List<_WardrobeCandidate> all) {
    final sneakersList = _piecesMatching(all, _sneakerAliases);
    final sandals = _piecesMatching(all, _sandalAliases);
    final mix = <TripWardrobePiece>[];
    final seen = <String>{};
    for (final p in [...sneakersList, ...sandals]) {
      if (seen.add(p.id)) mix.add(p);
    }
    if (mix.isEmpty) return _piecesMatching(all, _shoesAllAliases);
    return mix;
  }

  static void _tripMatchLog(String need, List<_WardrobeCandidate> candidates, List<_WardrobeCandidate> selected) {
    debugPrint(
      '[TRIP_MATCH] need=$need candidates=${candidates.map((c) => '${c.piece.id}:${c.piece.nameSk}').toList()} '
      'selected=${selected.map((c) => '${c.piece.id}:${c.piece.nameSk}').toList()}',
    );
  }

  /// Kúsky klasifikované ako tenisky (nie sandále — tie majú vlastné aliasy).
  static List<_WardrobeCandidate> _sneakersOnly(List<_WardrobeCandidate> all) {
    return _filter(all, _sneakerAliases);
  }

  static List<TripMissingItemSuggestion> _appendRainShellMissingIfNeeded(
    List<TripMissingItemSuggestion> missing,
    TripWeatherBundle weather,
    List<_WardrobeCandidate> candidates,
  ) {
    if (candidates.isEmpty) return missing;
    if (_filter(candidates, _layerAliases).isNotEmpty) return missing;
    var rainyStay = false;
    for (final d in weather.destinationStayDays) {
      if (_conditionImpliesRain(d.conditionSk)) {
        rainyStay = true;
        break;
      }
    }
    if (!rainyStay) return missing;
    return [
      ...missing,
      const TripMissingItemSuggestion(
        nameSk: 'Nemáš vhodnú vrstvu do dažďa',
        reasonSk: 'Mikina s kapucňou alebo ľahká bunda.',
      ),
    ];
  }

  static List<TripMissingItemSuggestion> _missingForTripContext({
    required TripPlanInput input,
    required List<_WardrobeCandidate> candidates,
    required bool warmBeach,
    required bool cityTrip,
    required bool workTrip,
    required bool hikingTrip,
    required bool festivalTrip,
    required bool coolSeason,
    required bool hasWorkEvent,
  }) {
    final seen = <String>{};
    final out = <TripMissingItemSuggestion>[];
    void addList(List<TripMissingItemSuggestion> list) {
      for (final m in list) {
        if (seen.add(m.nameSk)) out.add(m);
      }
    }

    if (warmBeach) addList(_missingWarmBeach(input, candidates));
    if (workTrip) addList(_missingWork(hasWorkEvent, candidates));
    if (cityTrip) addList(_missingCity(coolSeason, candidates));
    if (hikingTrip) addList(_missingHiking(candidates));
    if (festivalTrip) addList(_missingFestival(candidates));
    addList(_missingForTravelStyles(input, candidates));
    return out;
  }

  static List<TripMissingItemSuggestion> _missingForTravelStyles(
    TripPlanInput input,
    List<_WardrobeCandidate> all,
  ) {
    if (!input.travelStyles.contains(TripTravelStyle.elegant)) return const [];
    final blazers = _filter(all, _blazerAliases);
    if (blazers.isNotEmpty) return const [];
    return const [
      TripMissingItemSuggestion(
        nameSk: 'Nemáš elegantnejšiu vrstvu (sako)',
        reasonSk: 'Zodpovedá tvojmu výberu „Elegantnejšie“.',
      ),
    ];
  }

  static List<TripMissingItemSuggestion> _missingWarmBeach(TripPlanInput input, List<_WardrobeCandidate> all) {
    final tops = _filter(all, _topsAliases);
    final shorts = _filter(all, _shortsAliases);
    final swim = _filter(all, _swimAliases);
    final sandals = _filter(all, _sandalAliases);
    final sneakers = _sneakersOnly(all);
    final layers = _filter(all, _layerAliases);
    final sunnies = _filter(all, _sunglassesAliases);
    final hats = _filter(all, _hatAliases);
    final linenShirts = _filter(all, _linenLightShirtAliases)
        .where((c) => _blobMatchesAnyAlias(c.blob, _normList(const ['ľan', 'linen', 'košeľa', 'shirt'])))
        .toList();

    _tripMatchLog('tops', tops, tops);
    _tripMatchLog('shorts', shorts, shorts);
    _tripMatchLog('shoes_sneakers', all, sneakers);
    _tripMatchLog('shoes_sandals', all, sandals);
    _tripMatchLog('swim', swim, swim);
    _tripMatchLog('layers', all, layers);

    final missing = <TripMissingItemSuggestion>[];
    if (tops.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš ľahký top alebo tričko',
        reasonSk: 'Na horúce dni ako základ outfitu.',
      ));
    }
    if (shorts.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš ľahké kraťasy',
        reasonSk: 'Na teplo a pohyb pri vode.',
      ));
    }
    if (swim.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš plavky',
        reasonSk: 'Na kúpanie a pláž.',
      ));
    }
    if (sandals.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš vhodné sandále',
        reasonSk: 'Na horúci piesok a prestupy.',
      ));
    }
    if (sneakers.isEmpty && _filter(all, _shoesAllAliases).isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš pohodlnú obuv',
        reasonSk: 'Na presuny a celodenné nosenie.',
      ));
    }
    if (input.transport == TripTransport.plane && layers.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš vrstvu na lietadlo',
        reasonSk: 'Mikina alebo ľahká bunda do klímy v kabíne.',
      ));
    }
    if (sunnies.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš slnečné okuliare',
        reasonSk: 'Pri silnom slnku.',
      ));
    }
    if (hats.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš pokrývku hlavy',
        reasonSk: 'Šiltovka alebo klobúk pred úpalom.',
      ));
    }
    if (linenShirts.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš ľanovú alebo ľahkú košeľu',
        reasonSk: 'Na večer a vzdušný outfit.',
      ));
    }

    return missing;
  }

  static List<TripMissingItemSuggestion> _missingWork(
    bool hasWorkEvent,
    List<_WardrobeCandidate> all,
  ) {
    final shirts = _filter(all, _workShirtAliases);
    final pants = _filter(all, _workPantsAliases);
    final shoes = _filter(all, _workShoeAliases);
    final blazers = _filter(all, _blazerAliases);
    final tops = _filter(all, _topsAliases);

    final missing = <TripMissingItemSuggestion>[];
    if (shirts.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš košeľu alebo blúzku',
        reasonSk: 'Smart casual základ.',
      ));
    }
    if (pants.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš vhodné nohavice do práce',
        reasonSk: 'Chinos alebo tmavšie nohavice.',
      ));
    }
    if (shoes.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš čistejšie mestské topánky',
        reasonSk: 'Namiesto športových tenisiek.',
      ));
    }
    if (hasWorkEvent && blazers.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš elegantnejšiu vrstvu (sako)',
        reasonSk: 'Na stretnutie alebo večeru.',
      ));
    }

    _tripMatchLog('tops', tops, tops);
    _tripMatchLog('work_shirts', shirts, shirts);

    return missing;
  }

  static List<TripMissingItemSuggestion> _missingCity(
    bool coolSeason,
    List<_WardrobeCandidate> all,
  ) {
    final pants = _filter(all, _longPantsAliases);
    final shorts = _filter(all, _shortsAliases);
    final layers = _filter(all, _layerAliases);

    final missing = <TripMissingItemSuggestion>[];
    if (_sneakersOnly(all).isEmpty && _filter(all, _shoesAllAliases).isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš pohodlnú obuv na chodenie',
        reasonSk: 'Na celodenné presuny.',
      ));
    }
    if (pants.isEmpty && shorts.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš univerzálne nohavice',
        reasonSk: 'Jeans alebo chinos na mesto.',
      ));
    }
    if (coolSeason && layers.isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš ľahkú bundu alebo vrstvu',
        reasonSk: 'Na chladnejší večer.',
      ));
    }

    return missing;
  }

  static List<TripMissingItemSuggestion> _missingHiking(List<_WardrobeCandidate> all) {
    final missing = <TripMissingItemSuggestion>[];
    if (_filter(all, _hikeBootAliases).isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš turistickú obuv',
        reasonSk: 'Na terén a stabilitu.',
      ));
    }
    if (_filter(all, _hikeShellAliases).isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš funkčnú vrstvu',
        reasonSk: 'Pri zmene počasia.',
      ));
    }

    return missing;
  }

  static List<TripMissingItemSuggestion> _missingFestival(List<_WardrobeCandidate> all) {
    final missing = <TripMissingItemSuggestion>[];
    if (_filter(all, _topsAliases).isEmpty) {
      missing.add(const TripMissingItemSuggestion(
        nameSk: 'Nemáš pohodlný top',
        reasonSk: 'Na celý deň v dave.',
      ));
    }

    return missing;
  }

  static List<TripDailyOutfitPreview> _buildDailyOutfitsFirst({
    required TripPlanInput input,
    required List<_WardrobeCandidate> candidates,
    required bool warmBeach,
    required bool cityTrip,
    required bool workTrip,
    required bool hikingTrip,
    required bool festivalTrip,
    required bool coolSeason,
    required bool hasWorkEvent,
    required int destinationDayCount,
  }) {
    if (candidates.isEmpty) return _emptyDestinationDailyPlans(input);
    if (warmBeach) return [];
    if (destinationDayCount <= 0) return [];
    if (workTrip) {
      return _dailyWork(input, candidates, hasWorkEvent: hasWorkEvent, maxDaysOverride: destinationDayCount);
    }
    if (hikingTrip) return _dailyHiking(input, candidates, maxDaysOverride: destinationDayCount);
    if (cityTrip) return _dailyCity(input, candidates, coolSeason: coolSeason, maxDaysOverride: destinationDayCount);
    if (festivalTrip) return _dailyFestival(input, candidates, maxDaysOverride: destinationDayCount);
    return _dailyGeneral(input, candidates, maxDaysOverride: destinationDayCount);
  }

  static List<TripWardrobePiece> _genericOutboundTravelPieces(
    TripPlanInput input,
    List<_WardrobeCandidate> all, {
    required bool cityTrip,
    required bool workTrip,
    required bool hikingTrip,
    required bool festivalTrip,
    required bool coolSeason,
    required bool hasWorkEvent,
  }) {
    List<TripDailyOutfitPreview> previews;
    if (workTrip) {
      previews = _dailyWork(input, all, hasWorkEvent: hasWorkEvent, maxDaysOverride: 1);
    } else if (hikingTrip) {
      previews = _dailyHiking(input, all, maxDaysOverride: 1);
    } else if (festivalTrip) {
      previews = _dailyFestival(input, all, maxDaysOverride: 1);
    } else if (cityTrip) {
      previews = _dailyCity(input, all, coolSeason: coolSeason, maxDaysOverride: 1);
    } else {
      previews = _dailyGeneral(input, all, maxDaysOverride: 1);
    }
    if (previews.isEmpty) return [];
    return List<TripWardrobePiece>.from(previews.first.pieces);
  }

  static List<TripWardrobePiece> _genericReturnTravelPieces(
    TripPlanInput input,
    List<_WardrobeCandidate> all,
    List<TripWardrobePiece> outboundPieces,
    List<TripDailyOutfitPreview> destinationPlans, {
    required bool cityTrip,
    required bool workTrip,
    required bool hikingTrip,
    required bool festivalTrip,
    required bool coolSeason,
    required bool hasWorkEvent,
  }) {
    if (input.tripDayCount < 2) return [];

    List<TripDailyOutfitPreview> previews;
    if (workTrip) {
      previews = _dailyWork(input, all, hasWorkEvent: hasWorkEvent, maxDaysOverride: 2);
    } else if (hikingTrip) {
      previews = _dailyHiking(input, all, maxDaysOverride: 2);
    } else if (festivalTrip) {
      previews = _dailyFestival(input, all, maxDaysOverride: 2);
    } else if (cityTrip) {
      previews = _dailyCity(input, all, coolSeason: coolSeason, maxDaysOverride: 2);
    } else {
      previews = _dailyGeneral(input, all, maxDaysOverride: 2);
    }
    if (previews.isEmpty) return [];
    final lastPieces = List<TripWardrobePiece>.from(previews.last.pieces);
    _ensureReturnAvoidsDestinationWear(
      lastPieces,
      destinationPlans,
      all,
      input,
      outboundPieces,
    );
    return lastPieces;
  }

  /// Domovské počasie (SK): nov–mar chlad, jún–aug teplo, ostatné mierne.
  static bool _homeClimateFeelsCold(DateTime d) {
    final m = d.month;
    return m == 11 || m == 12 || m <= 3;
  }

  static bool _transportSuggestsAirportLayer(TripTransport t) {
    return t == TripTransport.plane || t == TripTransport.train || t == TripTransport.bus;
  }

  static TripWardrobePiece? _pickTravelSneaker(List<_WardrobeCandidate> all) {
    final sn = _piecesMatching(all, _sneakerAliases);
    if (sn.isNotEmpty) return sn.first;
    final mix = _buildShoesMix(all);
    if (mix.isNotEmpty) return mix.first;
    final any = _piecesMatching(all, _shoesAllAliases);
    return any.isNotEmpty ? any.first : null;
  }

  static TripWardrobePiece? _pickBeachShoe(List<_WardrobeCandidate> all) {
    final sand = _piecesMatching(all, _sandalAliases);
    if (sand.isNotEmpty) return sand.first;
    return _pickTravelSneaker(all);
  }

  static int _estimateHomeHighC(DateTime d) {
    final m = d.month;
    if (m == 12 || m <= 2) return 3;
    if (m >= 6 && m <= 8) return 27;
    if (m >= 3 && m <= 5) return 15;
    return 11;
  }

  static String _shortDestLabel(TripPlanInput input) {
    final raw = (input.selectedDestinationName ?? input.destinationText).trim();
    if (raw.isEmpty) return 'Destinácia';
    final first = raw.split(',').first.trim();
    if (first.length <= 24) return first;
    return '${first.substring(0, 22)}…';
  }

  /// Odhad „domáceho“ počasia podľa ročného obdobia (bez API).
  static (int high, int low, String condSk) _homeWeatherTriple(DateTime d) {
    final high = _estimateHomeHighC(d);
    final low = (high - (_homeClimateFeelsCold(d) ? 5 : 8)).clamp(-8, 38);
    final condSk = _homeClimateFeelsCold(d)
        ? (d.day % 2 == 0 ? 'Oblačno' : 'Dážď')
        : (high >= 24 ? 'Jasno' : 'Polooblačno');
    return (high, low, condSk);
  }

  static TripWeatherBundle _buildWeatherBundle(
    TripPlanInput input, {
    required bool warmBeach,
    required bool cityTrip,
  }) {
    final dest = _shortDestLabel(input);
    final destText =
        '${input.destinationText} ${input.selectedDestinationName ?? ''} ${input.destinationCountry ?? ''}';

    final outboundAnchor = input.outboundDeparture ?? input.outboundArrival ?? input.climateRangeStart;
    final returnAnchor = input.returnDeparture ?? input.returnArrival ?? input.climateRangeEnd;

    final homeOutTriple = _homeWeatherTriple(outboundAnchor);
    final homeRetTriple = _homeWeatherTriple(input.returnArrival ?? input.returnDeparture ?? input.climateRangeEnd);

    final routeOut = _compactTravelRouteArrowSk(input, returnLeg: false);
    final routeRet = _compactTravelRouteArrowSk(input, returnLeg: true);

    int destHighForDay(int dayIx) {
      final w = _weatherForContext(
        warmBeach: warmBeach,
        cityTrip: cityTrip,
        destinationText: destText,
        dayIndex: dayIx,
      );
      return w.$1;
    }

    String destCondForDay(int dayIx) {
      final w = _weatherForContext(
        warmBeach: warmBeach,
        cityTrip: cityTrip,
        destinationText: destText,
        dayIndex: dayIx,
      );
      return w.$3;
    }

    final destLeg = _weatherForContext(
      warmBeach: warmBeach,
      cityTrip: cityTrip,
      destinationText: destText,
      dayIndex: 0,
    );

    final outboundDateLabel = _skDayLabel(
      DateTime(outboundAnchor.year, outboundAnchor.month, outboundAnchor.day),
    );

    final outboundRoute = TripWeatherRoutePreview(
      travelDateLabelSk: outboundDateLabel,
      routeTitleSk: routeOut,
      conditionFromSk: homeOutTriple.$3,
      conditionToSk: destLeg.$3,
      tempFromC: homeOutTriple.$1,
      tempToC: destLeg.$1,
    );

    debugPrint(
      '[TRIP_WEATHER_CARD] type=departure route=$routeOut '
      'temps=${homeOutTriple.$1}°/${destLeg.$1}° cond=${homeOutTriple.$3}/${destLeg.$3}',
    );

    final stayDays = <TripWeatherDayPreview>[];
    final destCalDays = _destinationCalendarDays(input);
    final anchorStay = input.outboundArrival ?? input.outboundDeparture ?? DateTime.now();

    if (destCalDays.isEmpty && input.tripDayCount == 1) {
      final date = DateTime(anchorStay.year, anchorStay.month, anchorStay.day);
      final w = _weatherForContext(
        warmBeach: warmBeach,
        cityTrip: cityTrip,
        destinationText: destText,
        dayIndex: 0,
      );
      stayDays.add(
        TripWeatherDayPreview(
          label: _skDayLabel(date),
          highTempC: w.$1,
          lowTempC: w.$2,
          conditionSk: w.$3,
        ),
      );
      debugPrint(
        '[TRIP_WEATHER_CARD] type=stay route=$dest temps=${w.$1}°/${w.$2}° cond=${w.$3}',
      );
    } else {
      for (var i = 0; i < destCalDays.length; i++) {
        final date = destCalDays[i];
        final w = _weatherForContext(
          warmBeach: warmBeach,
          cityTrip: cityTrip,
          destinationText: destText,
          dayIndex: i,
        );
        stayDays.add(
          TripWeatherDayPreview(
            label: _skDayLabel(date),
            highTempC: w.$1,
            lowTempC: w.$2,
            conditionSk: w.$3,
          ),
        );
        debugPrint(
          '[TRIP_WEATHER_CARD] type=stay route=$dest day=$i temps=${w.$1}°/${w.$2}° cond=${w.$3}',
        );
      }
    }

    TripWeatherRoutePreview? returnRoute;
    if (input.tripDayCount >= 2) {
      final retDestHigh = destHighForDay(1);
      final retDestCond = destCondForDay(1);
      final returnDateLabel = _skDayLabel(
        DateTime(returnAnchor.year, returnAnchor.month, returnAnchor.day),
      );
      returnRoute = TripWeatherRoutePreview(
        travelDateLabelSk: returnDateLabel,
        routeTitleSk: routeRet,
        conditionFromSk: retDestCond,
        conditionToSk: homeRetTriple.$3,
        tempFromC: retDestHigh,
        tempToC: homeRetTriple.$1,
      );
      debugPrint(
        '[TRIP_WEATHER_CARD] type=return route=$routeRet '
        'temps=${retDestHigh}°/${homeRetTriple.$1}° cond=$retDestCond/${homeRetTriple.$3}',
      );
    }

    return TripWeatherBundle(
      outboundRoute: outboundRoute,
      destinationStayDays: stayDays,
      returnRoute: returnRoute,
    );
  }

  static TripWardrobePiece? _pickPieceAvoiding(List<TripWardrobePiece> pool, Set<String> avoid) {
    for (final p in pool) {
      if (!avoid.contains(p.id)) return p;
    }
    return pool.isNotEmpty ? pool.first : null;
  }

  static String _blobForPiece(TripWardrobePiece p, List<_WardrobeCandidate> all) =>
      all.where((c) => c.piece.id == p.id).firstOrNull?.blob ?? '';

  /// Vonkajšia vrstva → top → spodok/plávanie → obuv → doplnky (čiapka, okuliare, batoh).
  static int _travelVisualLane(String blob) {
    if (_blobMatchesAnyAlias(blob, _layerAliases)) return 0;
    if (_blobMatchesAnyAlias(blob, _shoesAllAliases)) return 3;
    if (_blobMatchesAnyAlias(blob, _hatAliases) ||
        _blobMatchesAnyAlias(blob, _sunglassesAliases) ||
        _blobMatchesAnyAlias(blob, _bagAliases)) {
      return 4;
    }
    if (_blobMatchesAnyAlias(blob, _shortsAliases) ||
        _blobMatchesAnyAlias(blob, _longPantsAliases) ||
        _blobMatchesAnyAlias(blob, _swimAliases)) {
      return 2;
    }
    if (_blobMatchesAnyAlias(blob, _topsAliases)) return 1;
    return 5;
  }

  static List<TripWardrobePiece> _orderPiecesTravelVisual(
    List<TripWardrobePiece> pieces,
    List<_WardrobeCandidate> all,
  ) {
    if (pieces.length <= 1) return List<TripWardrobePiece>.from(pieces);
    final indexed = List<TripWardrobePiece>.from(pieces)
      ..sort((a, b) {
        final ba = _blobForPiece(a, all);
        final bb = _blobForPiece(b, all);
        final la = _travelVisualLane(ba);
        final lb = _travelVisualLane(bb);
        if (la != lb) return la.compareTo(lb);
        return a.nameSk.compareTo(b.nameSk);
      });
    return indexed;
  }

  static List<TripWardrobePiece> _orderLuggageVisual(
    List<TripWardrobePiece> pieces,
    List<_WardrobeCandidate> all,
  ) {
    return _orderPiecesTravelVisual(pieces, all);
  }

  static List<TripDailyOutfitPreview> _orderAllDestinationPieces(
    List<TripDailyOutfitPreview> plans,
    List<_WardrobeCandidate> candidates,
  ) {
    return plans.map((d) {
      final ordered = _orderPiecesTravelVisual(d.pieces, candidates);
      return TripDailyOutfitPreview(
        dayIndex: d.dayIndex,
        titleSk: d.titleSk,
        summarySk: _summaryFromPieces(ordered),
        dayHintSk: d.dayHintSk,
        pieces: ordered,
        weatherDateLabelSk: d.weatherDateLabelSk,
        weatherPlaceSk: d.weatherPlaceSk,
        weatherHighC: d.weatherHighC,
        weatherLowC: d.weatherLowC,
        weatherConditionSk: d.weatherConditionSk,
      );
    }).toList();
  }

  static double _rotationPenalty(_TripOutfitRotation r, TripWardrobePiece p, _RotPickAxis axis) {
    final uses = r.usesInTrip[p.id] ?? 0;
    var pen = uses * 4.0;
    switch (axis) {
      case _RotPickAxis.top:
        if (r.prevTopId == p.id) pen += 22.0;
        break;
      case _RotPickAxis.bottom:
        if (r.prevBottomId == p.id) pen += 14.0;
        break;
      case _RotPickAxis.shoe:
        if (r.prevShoeId == p.id) pen += 10.0;
        break;
      case _RotPickAxis.layer:
        if (r.prevLayerId == p.id) pen += 4.0;
        break;
    }
    return pen;
  }

  static TripWardrobePiece? _pickRotatedFromPool({
    required List<TripWardrobePiece> pool,
    required Set<String> avoidIds,
    required _TripOutfitRotation rot,
    required List<_WardrobeCandidate> all,
    required _RotPickAxis axis,
    required String logCategory,
  }) {
    if (pool.isEmpty) return null;
    final viable = pool.where((p) => !avoidIds.contains(p.id)).toList();
    final usePool = viable.isNotEmpty ? viable : pool;
    TripWardrobePiece? best;
    var bestScore = double.infinity;
    final rnd = math.Random();
    for (final p in usePool) {
      final score = _rotationPenalty(rot, p, axis) + rnd.nextDouble() * 0.001;
      if (score < bestScore) {
        bestScore = score;
        best = p;
      }
    }
    final chosen = best ?? pool.first;
    final prevUses = rot.usesInTrip[chosen.id] ?? 0;
    final penLog = _rotationPenalty(rot, chosen, axis);
    debugPrint(
      '[TRIP_ROTATION] item=${chosen.nameSk} previousUses=$prevUses penalty=${penLog.toStringAsFixed(1)}',
    );
    final alts = usePool.where((p) => p.id != chosen.id).map((p) => p.nameSk).join('|');
    debugPrint('[TRIP_SELECTION] category=$logCategory selected=${chosen.nameSk} alternatives=$alts');
    return chosen;
  }

  static void _rotationNoteDestinationDay(
    _TripOutfitRotation r,
    List<TripWardrobePiece> pieces,
    List<_WardrobeCandidate> all,
  ) {
    final ordered = _orderPiecesTravelVisual(pieces, all);
    String? layerId;
    String? topId;
    String? botId;
    String? shoeId;
    for (final p in ordered) {
      final b = _blobForPiece(p, all);
      if (_blobMatchesAnyAlias(b, _layerAliases)) {
        layerId ??= p.id;
        continue;
      }
      if (_blobMatchesAnyAlias(b, _shoesAllAliases)) {
        shoeId ??= p.id;
        continue;
      }
      if (_reuseCategoryFromBlob(b) == _PieceReuseCategory.medium) {
        botId ??= p.id;
        continue;
      }
      if (_reuseCategoryFromBlob(b) == _PieceReuseCategory.low && _blobMatchesAnyAlias(b, _topsAliases)) {
        topId ??= p.id;
      }
    }
    if (layerId != null) r.prevLayerId = layerId;
    if (topId != null) r.prevTopId = topId;
    if (botId != null) r.prevBottomId = botId;
    if (shoeId != null) r.prevShoeId = shoeId;

    for (final p in pieces) {
      r.usesInTrip[p.id] = (r.usesInTrip[p.id] ?? 0) + 1;
    }
  }

  static TripWardrobePiece? _firstLayerFromPieces(
    List<TripWardrobePiece> pieces,
    List<_WardrobeCandidate> all,
  ) {
    for (final p in pieces) {
      final c = all.where((x) => x.piece.id == p.id).firstOrNull;
      if (c != null && _blobMatchesAnyAlias(c.blob, _layerAliases)) return p;
    }
    return null;
  }

  static List<TripWardrobePiece> _warmBeachOutboundPieces(
    TripPlanInput input,
    List<_WardrobeCandidate> all,
  ) {
    final tops = _piecesMatching(all, _topsAliases);
    final shorts = _piecesMatching(all, _shortsAliases);
    final layers = _piecesMatching(all, _layerAliases);
    final longPants = _filter(all, _longPantsAliases)
        .where((c) => !_blobMatchesAnyAlias(c.blob, _shortsAliases))
        .map((c) => c.piece)
        .toList();
    final bags = _piecesMatching(all, _bagAliases);
    final shoesMix = _buildShoesMix(all);
    final anyShoe = _piecesMatching(all, _shoesAllAliases);

    final depCold = _homeClimateFeelsCold(input.outboundDeparture ?? input.climateRangeStart);
    final nightOutbound =
        _lateNightArrival(input.outboundDeparture) || _lateNightArrival(input.outboundArrival);
    final wantOutboundLayer = layers.isNotEmpty &&
        (input.transport == TripTransport.plane ||
            (_transportSuggestsAirportLayer(input.transport) && (depCold || nightOutbound)));

    final pieces = <TripWardrobePiece>[];
    void addP(TripWardrobePiece? p) {
      if (p != null && !pieces.any((e) => e.id == p.id)) pieces.add(p);
    }

    if (depCold) {
      if (tops.isNotEmpty) addP(tops.first);
      if (longPants.isNotEmpty) {
        addP(longPants.first);
      } else if (shorts.isNotEmpty) {
        addP(shorts.first);
      }
      addP(_pickTravelSneaker(all));
      if (wantOutboundLayer) {
        final dep = input.outboundDeparture ?? input.climateRangeStart;
        final est = _estimateHomeHighC(dep);
        final layerPick = _pickTravelOuterLayerForHomeClimate(
          layers: layers,
          all: all,
          estimatedTempC: est,
          input: input,
          slot: 'outbound_travel',
        );
        addP(layerPick);
      }
      if (bags.isNotEmpty) addP(bags.first);
    } else {
      if (tops.isNotEmpty) addP(tops.first);
      if (shorts.isNotEmpty) {
        addP(shorts.first);
      } else if (longPants.isNotEmpty) {
        addP(longPants.first);
      }
      if (shoesMix.isNotEmpty) {
        addP(shoesMix.first);
      } else if (anyShoe.isNotEmpty) {
        addP(anyShoe.first);
      }
      if (wantOutboundLayer) {
        final dep = input.outboundDeparture ?? input.climateRangeStart;
        final est = _estimateHomeHighC(dep);
        final layerPick = _pickTravelOuterLayerForHomeClimate(
          layers: layers,
          all: all,
          estimatedTempC: est,
          input: input,
          slot: 'outbound_travel',
        );
        addP(layerPick);
      }
      if (bags.isNotEmpty) addP(bags.first);
    }
    return _orderPiecesTravelVisual(pieces, all);
  }

  static List<TripWardrobePiece> _warmBeachReturnPiecesV2(
    TripPlanInput input,
    List<_WardrobeCandidate> all,
    List<TripWardrobePiece> outboundPieces,
    _TripPackLedger ledger,
  ) {
    if (input.tripDayCount < 2) return [];

    final tops = _piecesMatching(all, _topsAliases);
    final shorts = _piecesMatching(all, _shortsAliases);
    final layers = _piecesMatching(all, _layerAliases);
    final longPants = _filter(all, _longPantsAliases)
        .where((c) => !_blobMatchesAnyAlias(c.blob, _shortsAliases))
        .map((c) => c.piece)
        .toList();
    final shoesMix = _buildShoesMix(all);
    final anyShoe = _piecesMatching(all, _shoesAllAliases);
    final linenShirts = _filter(all, _linenLightShirtAliases)
        .where((c) => _blobMatchesAnyAlias(c.blob, _normList(const ['ľan', 'linen', 'košeľa', 'shirt'])))
        .map((c) => c.piece)
        .toList();

    final avoidLowForReturn = ledger.wornLowIdsForReturnAvoidance();
    final avoidMediumForReturn = ledger.wornMediumIdsAcrossDestination();

    TripWardrobePiece? pickReturnTop() {
      final alt = _pickPieceAvoiding(tops, avoidLowForReturn);
      return alt ?? (tops.isNotEmpty ? tops.first : null);
    }

    TripWardrobePiece? pickReturnBottom(bool retCold) {
      if (retCold) {
        final alt = _pickPieceAvoiding(longPants, avoidMediumForReturn);
        if (alt != null) return alt;
        return longPants.isNotEmpty ? longPants.first : null;
      }
      final altS = _pickPieceAvoiding(shorts, avoidMediumForReturn);
      if (altS != null) return altS;
      if (shorts.isNotEmpty) return shorts.first;
      final altL = _pickPieceAvoiding(longPants, avoidMediumForReturn);
      return altL ?? (longPants.isNotEmpty ? longPants.first : null);
    }

    final outboundLayer = _firstLayerFromPieces(outboundPieces, all);
    final retCold = _homeClimateFeelsCold(input.returnArrival ?? input.climateRangeEnd);
    final layerForReturnTransport =
        retCold && _transportSuggestsAirportLayer(input.transport) && layers.isNotEmpty;
    final nightReturn =
        _lateNightArrival(input.returnDeparture) || _lateNightArrival(input.returnArrival);
    final mirrorOutboundLayer = outboundLayer != null &&
        _transportSuggestsAirportLayer(input.transport) &&
        layers.isNotEmpty &&
        (retCold || nightReturn);

    bool wantReturnLayer() {
      if (layers.isEmpty) return false;
      if (input.transport == TripTransport.plane && outboundLayer != null) return true;
      return layerForReturnTransport || mirrorOutboundLayer;
    }

    TripWardrobePiece preferredReturnLayer() {
      final ol = outboundLayer;
      if (input.transport == TripTransport.plane && ol != null) return ol;
      if (ol != null &&
          layers.any((l) => l.id == ol.id) &&
          (layerForReturnTransport || mirrorOutboundLayer)) {
        return ol;
      }
      final retAnchor = input.returnArrival ?? input.returnDeparture ?? input.climateRangeEnd;
      final est = _estimateHomeHighC(retAnchor);
      return _pickTravelOuterLayerForHomeClimate(
            layers: layers,
            all: all,
            estimatedTempC: est,
            input: input,
            slot: 'return_travel',
          ) ??
          layers.first;
    }

    final pieces = <TripWardrobePiece>[];
    void addP(TripWardrobePiece? p) {
      if (p != null && !pieces.any((e) => e.id == p.id)) pieces.add(p);
    }

    var layerAlreadyAdded = false;
    void addReturnLayerIfNeeded() {
      if (layerAlreadyAdded || layers.isEmpty) return;
      if (!wantReturnLayer()) return;
      final preferred = preferredReturnLayer();
      if (!pieces.any((e) => e.id == preferred.id)) {
        pieces.add(preferred);
        layerAlreadyAdded = true;
      }
    }

    addP(pickReturnTop());
    if (retCold) {
      addP(pickReturnBottom(true));
      addP(_pickTravelSneaker(all));
      addReturnLayerIfNeeded();
    } else {
      addP(pickReturnBottom(false));
      if (shoesMix.isNotEmpty) {
        addP(shoesMix.first);
      } else if (anyShoe.isNotEmpty) {
        addP(anyShoe.first);
      }
      if (linenShirts.isNotEmpty) addP(linenShirts.first);
      addReturnLayerIfNeeded();
    }

    debugPrint(
      '[TRIP_RETURN_OUTFIT] selected=${pieces.map((p) => p.nameSk).toList()} avoidedUsedLowReuse=${avoidLowForReturn.length} avoidedMedium=${avoidMediumForReturn.length}',
    );
    return _orderPiecesTravelVisual(pieces, all);
  }

  static TripDailyOutfitPreview _coolRainUrbanDestinationDayV2(
    TripPlanInput input,
    List<_WardrobeCandidate> all,
    _TripPackLedger ledger, {
    required _TripOutfitRotation rotation,
    required int destDayOrdinal,
    required int totalDestDays,
    required (int, int, String) weather,
  }) {
    final destText =
        '${input.destinationText} ${input.selectedDestinationName ?? ''} ${input.destinationCountry ?? ''}';
    final avoidTops = ledger.avoidTopIdsForDestinationDay(destDayOrdinal);
    final pieces = _buildCoolUrbanDestinationPieces(
      all,
      weather,
      destDayOrdinal - 1,
      destText,
      avoidTops,
      ledger.avoidMediumIdsForDestinationDay(destDayOrdinal),
      ledger.outboundShoeIds,
      rotation,
    );

    final titleSk = _destinationTitleSk(destDayOrdinal, totalDestDays, input.activityNotes, TripKind.beach);
    final summary = pieces.isEmpty
        ? 'Z aktuálneho výberu neviem poskladať kombináciu.'
        : pieces.map((e) => e.nameSk).join(', ');

    debugPrint(
      '[TRIP_OUTFIT_BUILD] mode=coolUrban day=$destDayOrdinal items=${pieces.map((p) => p.nameSk).toList()}',
    );

    return TripDailyOutfitPreview(
      dayIndex: destDayOrdinal,
      titleSk: titleSk,
      summarySk: summary,
      dayHintSk: null,
      pieces: pieces,
    );
  }

  static TripDailyOutfitPreview _warmBeachDestinationDayV2(
    TripPlanInput input,
    List<_WardrobeCandidate> all,
    _TripPackLedger ledger, {
    required _TripOutfitRotation rotation,
    required int destDayOrdinal,
    required int totalDestDays,
    required bool preferLightOutfit,
    required String destText,
    required bool cityTrip,
    required bool warmBeach,
    required int stayDayIndex,
  }) {
    final w = _weatherForContext(
      warmBeach: warmBeach,
      cityTrip: cityTrip,
      destinationText: destText,
      dayIndex: stayDayIndex,
    );
    if (_needsCoolRainUrbanLook(w, destText)) {
      return _coolRainUrbanDestinationDayV2(
        input,
        all,
        ledger,
        rotation: rotation,
        destDayOrdinal: destDayOrdinal,
        totalDestDays: totalDestDays,
        weather: w,
      );
    }

    final tops = _piecesMatching(all, _topsAliases);
    final shorts = _piecesMatching(all, _shortsAliases);
    final swimPieces = _piecesMatching(all, _swimAliases);
    final hats = _piecesMatching(all, _hatAliases);
    final sunnies = _piecesMatching(all, _sunglassesAliases);
    final linenShirts = _filter(all, _linenLightShirtAliases)
        .where((c) => _blobMatchesAnyAlias(c.blob, _normList(const ['ľan', 'linen', 'košeľa', 'shirt'])))
        .map((c) => c.piece)
        .toList();
    final longPants = _filter(all, _longPantsAliases)
        .where((c) => !_blobMatchesAnyAlias(c.blob, _shortsAliases))
        .map((c) => c.piece)
        .toList();
    final shoesMix = _buildShoesMix(all);
    final anyShoe = _piecesMatching(all, _shoesAllAliases);

    final destHigh = w.$1;
    final hotPack = warmBeach && destHigh >= 28;

    final avoidTops = ledger.avoidTopIdsForDestinationDay(destDayOrdinal);
    final avoidMed = ledger.avoidMediumIdsForDestinationDay(destDayOrdinal);
    final avoidShoes = ledger.outboundShoeIds;
    TripWardrobePiece? pickTop() {
      if (tops.isEmpty) return null;
      return _pickRotatedFromPool(
        pool: tops,
        avoidIds: avoidTops,
        rot: rotation,
        all: all,
        axis: _RotPickAxis.top,
        logCategory: 'top',
      );
    }

    TripWardrobePiece? pickBeachShoeAvoidingOutbound() {
      if (hotPack && warmBeach) {
        final sandals = _piecesMatching(all, _sandalAliases);
        if (sandals.isNotEmpty) {
          final s = _pickRotatedFromPool(
            pool: sandals,
            avoidIds: avoidShoes,
            rot: rotation,
            all: all,
            axis: _RotPickAxis.shoe,
            logCategory: 'sandals',
          );
          if (s != null) return s;
        }
      }
      final sneakerPool = _piecesMatching(all, _sneakerAliases);
      if (sneakerPool.isNotEmpty) {
        final sn = _pickRotatedFromPool(
          pool: sneakerPool,
          avoidIds: avoidShoes,
          rot: rotation,
          all: all,
          axis: _RotPickAxis.shoe,
          logCategory: 'sneakers',
        );
        if (sn != null) return sn;
      }
      if (shoesMix.isNotEmpty) {
        return _pickRotatedFromPool(
          pool: shoesMix,
          avoidIds: avoidShoes,
          rot: rotation,
          all: all,
          axis: _RotPickAxis.shoe,
          logCategory: 'shoes',
        );
      }
      if (anyShoe.isNotEmpty) {
        return _pickRotatedFromPool(
          pool: anyShoe,
          avoidIds: avoidShoes,
          rot: rotation,
          all: all,
          axis: _RotPickAxis.shoe,
          logCategory: 'shoes',
        );
      }
      return _pickBeachShoe(all);
    }

    TripWardrobePiece? pickWarmDestinationShoe() {
      if (hotPack && warmBeach) {
        final sandals = _piecesMatching(all, _sandalAliases);
        if (sandals.isNotEmpty) {
          final s = _pickRotatedFromPool(
            pool: sandals,
            avoidIds: avoidShoes,
            rot: rotation,
            all: all,
            axis: _RotPickAxis.shoe,
            logCategory: 'sandals',
          );
          if (s != null) return s;
        }
      }
      final sneakerPool = _piecesMatching(all, _sneakerAliases);
      if (sneakerPool.isNotEmpty) {
        final sn = _pickRotatedFromPool(
          pool: sneakerPool,
          avoidIds: avoidShoes,
          rot: rotation,
          all: all,
          axis: _RotPickAxis.shoe,
          logCategory: 'sneakers',
        );
        if (sn != null) return sn;
      }
      if (shoesMix.isNotEmpty) {
        return _pickRotatedFromPool(
          pool: shoesMix,
          avoidIds: avoidShoes,
          rot: rotation,
          all: all,
          axis: _RotPickAxis.shoe,
          logCategory: 'shoes',
        );
      }
      if (anyShoe.isNotEmpty) {
        return _pickRotatedFromPool(
          pool: anyShoe,
          avoidIds: avoidShoes,
          rot: rotation,
          all: all,
          axis: _RotPickAxis.shoe,
          logCategory: 'shoes',
        );
      }
      return null;
    }

    final effectiveLight = preferLightOutfit && !(hotPack && shorts.isNotEmpty);

    final pieces = <TripWardrobePiece>[];
    void addP(TripWardrobePiece? p) {
      if (p != null && !pieces.any((e) => e.id == p.id)) pieces.add(p);
    }

    if (effectiveLight) {
      addP(pickTop());
      addP(pickBeachShoeAvoidingOutbound());
    } else {
      addP(pickTop());
      if (hotPack && shorts.isNotEmpty) {
        addP(
          _pickRotatedFromPool(
            pool: shorts,
            avoidIds: avoidMed,
            rot: rotation,
            all: all,
            axis: _RotPickAxis.bottom,
            logCategory: 'shorts',
          ),
        );
      } else {
        if (shorts.isNotEmpty) {
          addP(
            _pickRotatedFromPool(
              pool: shorts,
              avoidIds: avoidMed,
              rot: rotation,
              all: all,
              axis: _RotPickAxis.bottom,
              logCategory: 'shorts',
            ),
          );
        } else if (longPants.isNotEmpty) {
          addP(
            _pickRotatedFromPool(
              pool: longPants,
              avoidIds: avoidMed,
              rot: rotation,
              all: all,
              axis: _RotPickAxis.bottom,
              logCategory: 'bottoms',
            ),
          );
        }
      }
      addP(pickWarmDestinationShoe());
      if (swimPieces.isNotEmpty) {
        addP(
          _pickRotatedFromPool(
            pool: swimPieces,
            avoidIds: const {},
            rot: rotation,
            all: all,
            axis: _RotPickAxis.bottom,
            logCategory: 'swim',
          ),
        );
      }
      if (destDayOrdinal <= 2) {
        if (hats.isNotEmpty) addP(hats.first);
        if (sunnies.isNotEmpty) addP(sunnies.first);
      }
      if (destDayOrdinal == totalDestDays && linenShirts.isNotEmpty) {
        addP(linenShirts.first);
      }
    }

    final orderedPieces = _orderPiecesTravelVisual(pieces, all);

    final titleSk = _destinationTitleSk(destDayOrdinal, totalDestDays, input.activityNotes, TripKind.beach);
    final summary = orderedPieces.isEmpty
        ? 'Z aktuálneho výberu neviem poskladať kombináciu.'
        : orderedPieces.map((e) => e.nameSk).join(', ');

    final topDbg = orderedPieces
            .where((p) => _reuseCategoryForPiece(p, all) == _PieceReuseCategory.low)
            .map((p) => p.nameSk)
            .firstOrNull ??
        '-';
    final botDbg = orderedPieces
            .where((p) => _reuseCategoryForPiece(p, all) == _PieceReuseCategory.medium)
            .map((p) => p.nameSk)
            .join(',');
    final shoeDbg = orderedPieces
            .where((p) {
          final b = all.where((c) => c.piece.id == p.id).firstOrNull?.blob ?? '';
          return _blobMatchesAnyAlias(b, _shoesAllAliases);
        })
            .map((p) => p.nameSk)
            .join(',');
    debugPrint(
      '[TRIP_OUTFIT_BUILD] day=$destDayOrdinal selectedTop=$topDbg selectedBottom=${botDbg.isEmpty ? '-' : botDbg} selectedShoes=${shoeDbg.isEmpty ? '-' : shoeDbg}',
    );

    return TripDailyOutfitPreview(
      dayIndex: destDayOrdinal,
      titleSk: titleSk,
      summarySk: summary,
      dayHintSk: null,
      pieces: orderedPieces,
    );
  }

  static TripDailyOutfitPreview _warmBeachSingleDestinationDayV2(
    TripPlanInput input,
    List<_WardrobeCandidate> all,
    _TripPackLedger ledger, {
    required _TripOutfitRotation rotation,
    required String destText,
    required bool cityTrip,
    required bool warmBeach,
  }) {
    return _warmBeachDestinationDayV2(
      input,
      all,
      ledger,
      rotation: rotation,
      destDayOrdinal: 1,
      totalDestDays: 1,
      preferLightOutfit: false,
      destText: destText,
      cityTrip: cityTrip,
      warmBeach: warmBeach,
      stayDayIndex: 0,
    );
  }

  static List<TripDailyOutfitPreview> _dailyWork(
    TripPlanInput input,
    List<_WardrobeCandidate> all, {
    required bool hasWorkEvent,
    int? maxDaysOverride,
  }) {
    final shirts = _piecesMatching(all, _workShirtAliases);
    final pants = _piecesMatching(all, _workPantsAliases);
    final workShoes = _piecesMatching(all, _workShoeAliases);
    final sneakersList = _piecesMatching(all, _sneakerAliases);
    final blazers = _piecesMatching(all, _blazerAliases);
    final shoesMix = _buildShoesMix(all);

    TripWardrobePiece? shoeForDay(int di) {
      if (workShoes.isNotEmpty) return workShoes[di % workShoes.length];
      if (sneakersList.isNotEmpty) return sneakersList[di % sneakersList.length];
      if (shoesMix.isNotEmpty) return shoesMix[di % shoesMix.length];
      return null;
    }

    final maxDays = maxDaysOverride ?? _destinationOutfitDayCount(input);
    final totalLabelDays = maxDays;
    final out = <TripDailyOutfitPreview>[];
    String? prevSig;

    for (var i = 0; i < maxDays; i++) {
      final day = i + 1;
      final title =
          _dayTitle(day: day, totalDays: totalLabelDays, warmBeach: false, kind: input.primaryKindForTitles);
      final pieces = <TripWardrobePiece>[];

      void addP(TripWardrobePiece? p) {
        if (p != null && !pieces.any((e) => e.id == p.id)) pieces.add(p);
      }

      if (shirts.isNotEmpty) addP(shirts[i % shirts.length]);
      if (pants.isNotEmpty) addP(pants[i % pants.length]);
      addP(shoeForDay(i));
      if (hasWorkEvent && day == 1 && blazers.isNotEmpty) addP(blazers.first);

      var sig = pieces.map((p) => p.id).join('|');
      if (prevSig != null && sig == prevSig && shirts.length > 1) {
        pieces.clear();
        if (shirts.isNotEmpty) addP(shirts[(i + 1) % shirts.length]);
        if (pants.isNotEmpty) addP(pants[i % pants.length]);
        addP(shoeForDay(i + 1));
        if (hasWorkEvent && day == 1 && blazers.isNotEmpty) addP(blazers.first);
        sig = pieces.map((p) => p.id).join('|');
      }
      prevSig = sig;

      final summary = pieces.isEmpty
          ? 'Z aktuálneho výberu neviem poskladať kombináciu.'
          : pieces.map((e) => e.nameSk).join(', ');

      out.add(TripDailyOutfitPreview(dayIndex: day, titleSk: title, summarySk: summary, pieces: pieces));
    }
    return out;
  }

  static List<TripDailyOutfitPreview> _dailyCity(
    TripPlanInput input,
    List<_WardrobeCandidate> all, {
    required bool coolSeason,
    int? maxDaysOverride,
  }) {
    final tops = _piecesMatching(all, _topsAliases);
    final pants = _piecesMatching(all, _longPantsAliases);
    final shorts = _piecesMatching(all, _shortsAliases);
    final shoes = _piecesMatching(all, _sneakerAliases);
    final layers = _piecesMatching(all, _layerAliases);
    final bags = _piecesMatching(all, _bagAliases);
    final shoesMix = _buildShoesMix(all);

    List<TripWardrobePiece> pickBottoms() => pants.isNotEmpty ? pants : shorts;

    final maxDays = maxDaysOverride ?? _destinationOutfitDayCount(input);
    final totalLabelDays = maxDays;
    final out = <TripDailyOutfitPreview>[];
    String? prevSig;
    final destText =
        '${input.destinationText} ${input.selectedDestinationName ?? ''} ${input.destinationCountry ?? ''}';
    final rotation = _TripOutfitRotation();

    for (var i = 0; i < maxDays; i++) {
      final day = i + 1;
      final title =
          _dayTitle(day: day, totalDays: totalLabelDays, warmBeach: false, kind: TripKind.cityBreak);
      final pieces = <TripWardrobePiece>[];

      void addP(TripWardrobePiece? p) {
        if (p != null && !pieces.any((e) => e.id == p.id)) pieces.add(p);
      }

      final w = _weatherForContext(
        warmBeach: false,
        cityTrip: true,
        destinationText: destText,
        dayIndex: i,
      );
      final urbanLook = _needsCoolRainUrbanLook(w, destText);

      if (urbanLook) {
        for (final p in _buildCoolUrbanDestinationPieces(
          all,
          w,
          i,
          destText,
          const {},
          const {},
          const {},
          rotation,
        )) {
          addP(p);
        }
        if (bags.isNotEmpty && day == 1) addP(bags.first);
      } else {
        final bottoms = pickBottoms();
        final bottomCat = pants.isNotEmpty ? 'bottoms' : 'shorts';

        if (tops.isNotEmpty) {
          addP(
            _pickRotatedFromPool(
              pool: tops,
              avoidIds: const {},
              rot: rotation,
              all: all,
              axis: _RotPickAxis.top,
              logCategory: 'top',
            ),
          );
        }
        if (bottoms.isNotEmpty) {
          addP(
            _pickRotatedFromPool(
              pool: bottoms,
              avoidIds: const {},
              rot: rotation,
              all: all,
              axis: _RotPickAxis.bottom,
              logCategory: bottomCat,
            ),
          );
        }
        if (shoesMix.isNotEmpty) {
          addP(
            _pickRotatedFromPool(
              pool: shoesMix,
              avoidIds: const {},
              rot: rotation,
              all: all,
              axis: _RotPickAxis.shoe,
              logCategory: 'shoes',
            ),
          );
        } else if (shoes.isNotEmpty) {
          addP(
            _pickRotatedFromPool(
              pool: shoes,
              avoidIds: const {},
              rot: rotation,
              all: all,
              axis: _RotPickAxis.shoe,
              logCategory: 'sneakers',
            ),
          );
        }
        if (bags.isNotEmpty && day == 1) addP(bags.first);

        if (coolSeason && layers.isNotEmpty && day >= 2) {
          addP(
            _pickIntelligentOuterLayer(
              layers: layers,
              all: all,
              tempHighC: w.$1,
              rain: _conditionImpliesRain(w.$3),
              avoidIds: const {},
              destinationText: destText,
              slot: 'city_cool_season',
            ),
          );
        }
      }

      var sig = pieces.map((p) => p.id).join('|');
      if (!urbanLook &&
          prevSig != null &&
          sig == prevSig &&
          (tops.length > 1 || pickBottoms().length > 1)) {
        if (tops.length > 1) {
          pieces.clear();
          final bottoms = pickBottoms();
          if (tops.isNotEmpty) addP(tops[(i + 1) % tops.length]);
          if (bottoms.isNotEmpty) addP(bottoms[(i + 1) % bottoms.length]);
          if (shoesMix.isNotEmpty) {
            addP(shoesMix[(i + 1) % shoesMix.length]);
          } else if (shoes.isNotEmpty) {
            addP(shoes[(i + 1) % shoes.length]);
          }
          if (bags.isNotEmpty && day == 1) addP(bags.first);
          if (coolSeason && layers.isNotEmpty && day >= 2) {
            addP(
              _pickIntelligentOuterLayer(
                layers: layers,
                all: all,
                tempHighC: w.$1,
                rain: _conditionImpliesRain(w.$3),
                avoidIds: const {},
                destinationText: destText,
                slot: 'city_cool_season',
              ),
            );
          }
          sig = pieces.map((p) => p.id).join('|');
        }
      }
      prevSig = sig;

      _rotationNoteDestinationDay(rotation, pieces, all);
      final ordered = _orderPiecesTravelVisual(pieces, all);
      final summary = ordered.isEmpty
          ? 'Z aktuálneho výberu neviem poskladať kombináciu.'
          : ordered.map((e) => e.nameSk).join(', ');

      out.add(TripDailyOutfitPreview(dayIndex: day, titleSk: title, summarySk: summary, pieces: ordered));
    }
    return out;
  }

  static List<TripDailyOutfitPreview> _dailyHiking(
    TripPlanInput input,
    List<_WardrobeCandidate> all, {
    int? maxDaysOverride,
  }) {
    final boots = _piecesMatching(all, _hikeBootAliases);
    final shells = _piecesMatching(all, _hikeShellAliases);
    final tops = _piecesMatching(all, _topsAliases);
    final pants = _piecesMatching(all, _longPantsAliases);
    final maxDays = maxDaysOverride ?? _destinationOutfitDayCount(input);
    final out = <TripDailyOutfitPreview>[];

    for (var i = 0; i < maxDays; i++) {
      final day = i + 1;
      final title =
          _dayTitle(day: day, totalDays: maxDays, warmBeach: false, kind: TripKind.hiking);
      final pieces = <TripWardrobePiece>[];

      void addP(TripWardrobePiece? p) {
        if (p != null && !pieces.any((e) => e.id == p.id)) pieces.add(p);
      }

      if (boots.isNotEmpty) addP(boots.first);
      if (shells.isNotEmpty) addP(shells[i % shells.length]);
      if (tops.isNotEmpty) addP(tops[i % tops.length]);
      if (pants.isNotEmpty) addP(pants.first);

      final summary = pieces.isEmpty
          ? 'Z aktuálneho výberu neviem poskladať kombináciu.'
          : pieces.map((e) => e.nameSk).join(', ');

      out.add(TripDailyOutfitPreview(dayIndex: day, titleSk: title, summarySk: summary, pieces: pieces));
    }
    return out;
  }

  static List<TripDailyOutfitPreview> _dailyFestival(
    TripPlanInput input,
    List<_WardrobeCandidate> all, {
    int? maxDaysOverride,
  }) {
    final tops = _piecesMatching(all, _topsAliases);
    final shorts = _piecesMatching(all, _shortsAliases);
    final shoesMix = _buildShoesMix(all);
    final maxDays = maxDaysOverride ?? _destinationOutfitDayCount(input);
    final out = <TripDailyOutfitPreview>[];
    String? prevSig;

    for (var i = 0; i < maxDays; i++) {
      final day = i + 1;
      final title =
          _dayTitle(day: day, totalDays: maxDays, warmBeach: false, kind: TripKind.festival);
      final pieces = <TripWardrobePiece>[];

      void addP(TripWardrobePiece? p) {
        if (p != null && !pieces.any((e) => e.id == p.id)) pieces.add(p);
      }

      if (tops.isNotEmpty) addP(tops[i % tops.length]);
      if (shorts.isNotEmpty) addP(shorts[i % shorts.length]);
      if (shoesMix.isNotEmpty) addP(shoesMix[i % shoesMix.length]);

      var sig = pieces.map((p) => p.id).join('|');
      if (prevSig != null && sig == prevSig && (tops.length > 1 || shorts.length > 1)) {
        pieces.clear();
        if (tops.isNotEmpty) addP(tops[(i + 1) % tops.length]);
        if (shorts.isNotEmpty) addP(shorts[(i + 1) % shorts.length]);
        if (shoesMix.isNotEmpty) addP(shoesMix[(i + 1) % shoesMix.length]);
        sig = pieces.map((p) => p.id).join('|');
      }
      prevSig = sig;

      final summary = pieces.isEmpty
          ? 'Z aktuálneho výberu neviem poskladať kombináciu.'
          : pieces.map((e) => e.nameSk).join(', ');

      out.add(TripDailyOutfitPreview(dayIndex: day, titleSk: title, summarySk: summary, pieces: pieces));
    }
    return out;
  }

  static List<TripDailyOutfitPreview> _dailyGeneral(
    TripPlanInput input,
    List<_WardrobeCandidate> all, {
    int? maxDaysOverride,
  }) {
    final tops = _piecesMatching(all, _topsAliases);
    final bottoms = _uniquePieces(_filter(all, [..._longPantsAliases, ..._shortsAliases]).map((c) => c.piece));
    final shoesMix = _buildShoesMix(all);
    final fallbackShoes = _piecesMatching(all, _shoesAllAliases);
    final maxDays = maxDaysOverride ?? _destinationOutfitDayCount(input);
    final out = <TripDailyOutfitPreview>[];
    String? prevSig;

    for (var i = 0; i < maxDays; i++) {
      final day = i + 1;
      final title =
          _dayTitle(day: day, totalDays: maxDays, warmBeach: false, kind: input.primaryKindForTitles);
      final pieces = <TripWardrobePiece>[];

      void addP(TripWardrobePiece? p) {
        if (p != null && !pieces.any((e) => e.id == p.id)) pieces.add(p);
      }

      if (tops.isNotEmpty) addP(tops[i % tops.length]);
      if (bottoms.isNotEmpty) addP(bottoms[i % bottoms.length]);
      if (shoesMix.isNotEmpty) {
        addP(shoesMix[i % shoesMix.length]);
      } else if (fallbackShoes.isNotEmpty) {
        addP(fallbackShoes[i % fallbackShoes.length]);
      }

      var sig = pieces.map((p) => p.id).join('|');
      if (prevSig != null &&
          sig == prevSig &&
          (tops.length > 1 || bottoms.length > 1 || shoesMix.length > 1 || fallbackShoes.length > 1)) {
        if (tops.length > 1) {
          pieces.clear();
          addP(tops[(i + 1) % tops.length]);
          if (bottoms.isNotEmpty) addP(bottoms[(i + 1) % bottoms.length]);
          if (shoesMix.isNotEmpty) {
            addP(shoesMix[(i + 1) % shoesMix.length]);
          } else if (fallbackShoes.isNotEmpty) {
            addP(fallbackShoes[(i + 1) % fallbackShoes.length]);
          }
          sig = pieces.map((p) => p.id).join('|');
        }
      }
      prevSig = sig;

      final summary = pieces.isEmpty
          ? 'Z aktuálneho výberu neviem poskladať kombináciu.'
          : pieces.map((e) => e.nameSk).join(', ');

      out.add(TripDailyOutfitPreview(dayIndex: day, titleSk: title, summarySk: summary, pieces: pieces));
    }
    return out;
  }

  static List<TripWardrobePiece> _uniquePieces(Iterable<TripWardrobePiece> raw) {
    final seen = <String>{};
    final out = <TripWardrobePiece>[];
    for (final p in raw) {
      if (seen.add(p.id)) out.add(p);
    }
    return out;
  }

  static String _skDayLabel(DateTime day) {
    const w = ['Po', 'Ut', 'St', 'Št', 'Pi', 'So', 'Ne'];
    return '${w[day.weekday - 1]} ${day.day}. ${day.month}.';
  }

  static (int, int, String) _weatherForContext({
    required bool warmBeach,
    required bool cityTrip,
    required String destinationText,
    required int dayIndex,
  }) {
    final text = destinationText.toLowerCase();
    final isLondon =
        text.contains('london') || text.contains('londýn') || text.contains('uk') || text.contains('england');
    if (warmBeach) return (29 + (dayIndex % 6), 22 + (dayIndex % 4), ['Jasno', 'Jasno', 'Polooblačno'][dayIndex % 3]);
    if (isLondon) {
      final conds = ['Dážď', 'Oblačno', 'Polooblačno', 'Dážď', 'Oblačno'];
      return (14 + (dayIndex % 5), 9 + (dayIndex % 4), conds[dayIndex % conds.length]);
    }
    if (cityTrip) return (18 + (dayIndex % 7), 11 + (dayIndex % 4), ['Polooblačno', 'Jasno', 'Oblačno'][dayIndex % 3]);
    return (18 + (dayIndex % 6), 10 + (dayIndex % 4), ['Jasno', 'Polooblačno', 'Oblačno'][dayIndex % 3]);
  }

  static bool _isWarmBeachContext(TripPlanInput input) {
    final text =
        '${input.destinationText} ${input.selectedDestinationName ?? ''} ${input.destinationCountry ?? ''}'.toLowerCase();
    if (text.contains('london') ||
        text.contains('londýn') ||
        text.contains('united kingdom') ||
        text.contains(', uk')) {
      return false;
    }
    const warm = [
      'egypt',
      'hurghada',
      'sharm',
      'dubai',
      'cyprus',
      'greece',
      'spain',
      'malaga',
      'málaga',
      'mallorca',
      'tenerife',
      'turkey',
      'antalya',
    ];
    return input.tripKinds.contains(TripKind.beach) || warm.any(text.contains);
  }

  static bool _hasWorkEvent(String note) {
    final n = note.toLowerCase();
    const keys = ['meeting', 'stretnutie', 'pracovné stretnutie', 'konferencia', 'večera', 'dinner'];
    return keys.any(n.contains);
  }

  static bool _isCoolSeason(DateTime from, DateTime to) {
    final coolMonths = {10, 11, 12, 1, 2, 3};
    return coolMonths.contains(from.month) || coolMonths.contains(to.month);
  }

  static String _dayTitle({
    required int day,
    required int totalDays,
    required bool warmBeach,
    required TripKind kind,
  }) {
    if (warmBeach) {
      if (day == 1) return 'Deň 1 – cesta a ľahký večer';
      if (day == 2) return 'Deň 2 – plážový deň';
      if (day == totalDays) return 'Deň $day – návrat a pohodlný outfit';
      return 'Deň $day – pláž / výlet';
    }
    if (kind == TripKind.cityBreak) return 'Deň $day – mesto a chodenie';
    if (kind == TripKind.business) return day == 1 ? 'Deň 1 – pracovný štart' : 'Deň $day – pracovný program';
    return 'Deň $day – cesty podľa plánu';
  }
}

extension _IterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final i = iterator;
    return i.moveNext() ? i.current : null;
  }
}

/// Stav nosenia — nízko-reuse topy z cesty a predošlého dňa v destinácii.
final class _TripPackLedger {
  _TripPackLedger(this.all);

  final List<_WardrobeCandidate> all;

  final Map<String, _PieceReuseCategory> _cache = {};
  final Set<String> _travelLowTopIds = {};
  final Set<String> _travelOutboundMediumIds = {};
  final Set<String> _travelOutboundShoeIds = {};
  final Map<int, Set<String>> _destLowTopIdsByDay = {};
  final Map<int, Set<String>> _destMediumBottomIdsByDay = {};

  _PieceReuseCategory categoryOf(TripWardrobePiece p) =>
      _cache[p.id] ??= TripPackingService._reuseCategoryForPiece(p, all);

  void registerWear(List<TripWardrobePiece> pieces, String slot) {
    for (final p in pieces) {
      final c = categoryOf(p);
      final blob = all.where((x) => x.piece.id == p.id).firstOrNull?.blob ?? '';
      debugPrint('[TRIP_USAGE] item=${p.nameSk} usedIn=$slot');
      if (slot == 'outbound') {
        if (c == _PieceReuseCategory.low) _travelLowTopIds.add(p.id);
        if (c == _PieceReuseCategory.medium) _travelOutboundMediumIds.add(p.id);
        if (TripPackingService._blobMatchesAnyAlias(blob, TripPackingService._shoesAllAliases)) {
          _travelOutboundShoeIds.add(p.id);
        }
      }
    }
  }

  void registerDestinationDay(List<TripWardrobePiece> pieces, int dayOrdinal) {
    registerWear(pieces, 'dest_day_$dayOrdinal');
    final lows = pieces.where((p) => categoryOf(p) == _PieceReuseCategory.low).map((p) => p.id).toSet();
    _destLowTopIdsByDay[dayOrdinal] = lows;
    final meds =
        pieces.where((p) => categoryOf(p) == _PieceReuseCategory.medium).map((p) => p.id).toSet();
    _destMediumBottomIdsByDay[dayOrdinal] = meds;
  }

  Set<String> avoidTopIdsForDestinationDay(int dayOrdinal) {
    final out = <String>{..._travelLowTopIds};
    for (var d = 1; d < dayOrdinal; d++) {
      out.addAll(_destLowTopIdsByDay[d] ?? const {});
    }
    return out;
  }

  Set<String> avoidMediumIdsForDestinationDay(int dayOrdinal) {
    final out = <String>{..._travelOutboundMediumIds};
    for (var d = 1; d < dayOrdinal; d++) {
      out.addAll(_destMediumBottomIdsByDay[d] ?? const {});
    }
    return out;
  }

  Set<String> get outboundShoeIds => Set.unmodifiable(_travelOutboundShoeIds);

  Set<String> wornLowIdsAcrossDestination() =>
      _destLowTopIdsByDay.values.expand((s) => s).toSet();

  Set<String> wornMediumIdsAcrossDestination() =>
      _destMediumBottomIdsByDay.values.expand((s) => s).toSet();

  Set<String> wornLowIdsForReturnAvoidance() =>
      {..._travelLowTopIds, ...wornLowIdsAcrossDestination()};
}
