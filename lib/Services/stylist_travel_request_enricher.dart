import 'dart:math' as math;

import '../models/stylist_resolved_location.dart';
import '../utils/stylist_destination_mention.dart';
import '../utils/stylist_travel_context.dart';
import '../utils/stylist_travel_endpoints.dart';
import 'hourly_weather_service.dart';
import 'stylist_destination_time_service.dart';
import 'stylist_global_location_service.dart';

class StylistTravelRequestEnrichment {
  final Map<String, dynamic> outfitContextState;
  final Map<String, dynamic> clientContext;
  final Map<String, dynamic> weatherContext;

  const StylistTravelRequestEnrichment({
    required this.outfitContextState,
    required this.clientContext,
    required this.weatherContext,
  });
}

/// Request-time travel enrichment for the Brain experiment.
///
/// Responsibilities are deliberately separated:
/// - language layer says *what the user means* (transit/destination/mixed),
/// - global provider says *what geographic thing a name is*,
/// - this layer derives non-authoritative travel timing and arrival weather.
///
/// No named city/country/airport exists in this file. When no timetable or
/// routing provider is configured, derived arrival times are explicitly marked
/// as estimates and are used to choose a weather window, never presented as a
/// guaranteed schedule.
abstract final class StylistTravelRequestEnricher {
  static Future<StylistTravelRequestEnrichment> enrich({
    required String message,
    required List<Map<String, String>> history,
    required Map<String, dynamic>? clientContext,
    required Map<String, dynamic>? outfitContextState,
    required Map<String, dynamic>? weatherContext,
    HourlyWeatherService? weatherService,
  }) async {
    final client = Map<String, dynamic>.from(clientContext ?? const {});
    final state = Map<String, dynamic>.from(outfitContextState ?? const {});
    final weather = Map<String, dynamic>.from(weatherContext ?? const {});
    final conversation = _userConversation(message, history);
    final travel = StylistTravelContextResolver.resolve(conversation);
    final latestTravel = StylistTravelContextResolver.resolve(message);
    final travelPayload = Map<String, dynamic>.from(travel.toApiPayload());
    state['travelContext'] = travelPayload;

    final unresolved = _stringSet(state['unresolvedMaterialFields']);
    final allowBareLatest = unresolved.contains('destination');
    final endpointPair = StylistTravelEndpointsExtractor.extract(message).hasAny
        ? StylistTravelEndpointsExtractor.extract(message)
        : StylistTravelEndpointsExtractor.extract(conversation);

    final destinationMention = endpointPair.destination != null
        ? StylistDestinationMention(
            evidence: endpointPair.destination!.evidence,
            query: endpointPair.destination!.query,
          )
        : StylistDestinationMentionExtractor.extract(
              message,
              allowBareReply: allowBareLatest,
            ) ??
            StylistDestinationMentionExtractor.extract(conversation);

    StylistResolvedLocation? resolvedDestination;
    if (destinationMention != null) {
      resolvedDestination = await StylistGlobalLocationService.resolveQuery(
        destinationMention.query,
        evidence: destinationMention.evidence,
      );
      _applyLocationAuthority(
        state: state,
        unresolved: unresolved,
        mention: destinationMention,
        resolved: resolvedDestination,
        travel: travel,
      );
    }

    StylistResolvedLocation? explicitOrigin;
    if (endpointPair.origin != null) {
      explicitOrigin = await StylistGlobalLocationService.resolveQuery(
        endpointPair.origin!.query,
        evidence: endpointPair.origin!.evidence,
      );
      if (explicitOrigin != null) {
        client['travelOrigin'] = <String, dynamic>{
          'providerVerified': true,
          ...explicitOrigin.toApiPayload(),
        };
      }
    }

    final timing = await _deriveTravelTiming(
      travel: travel,
      latestTravel: latestTravel,
      state: state,
      client: client,
      destination: resolvedDestination,
      explicitOrigin: explicitOrigin,
    );
    if (timing.isNotEmpty) {
      client['derivedTravelTiming'] = timing;
      travelPayload['derivedTravelTiming'] = timing;
    }

    if (resolvedDestination?.weatherSpecific == true &&
        travel.arrivalWeatherCouldHelp) {
      final arrivalWeather = await _arrivalWeather(
        resolved: resolvedDestination!,
        travel: travel,
        timing: timing,
        state: state,
        client: client,
        service: weatherService ?? HourlyWeatherService(),
      );
      if (arrivalWeather != null) {
        weather['arrivalWeather'] = arrivalWeather;
      }
    }

    state['unresolvedMaterialFields'] = unresolved.toList(growable: false);
    state['groundingStatus'] = unresolved.isEmpty
        ? 'sufficient'
        : 'needs_grounding';
    return StylistTravelRequestEnrichment(
      outfitContextState: state,
      clientContext: client,
      weatherContext: weather,
    );
  }

  static void _applyLocationAuthority({
    required Map<String, dynamic> state,
    required Set<String> unresolved,
    required StylistDestinationMention mention,
    required StylistResolvedLocation? resolved,
    required StylistTravelContext travel,
  }) {
    final locationContext = <String, dynamic>{
      'providerAuthorityEnabled': true,
      'providerVerified': resolved?.providerVerified == true,
      'evidence': mention.evidence,
      'query': mention.query,
      if (resolved != null) ...resolved.toApiPayload(),
    };
    state['locationContext'] = locationContext;

    final destinationRequired = travel.destinationRequiredForPrimaryOutfit;
    if (resolved?.weatherSpecific == true) {
      state['activityLocationLabel'] = resolved!.weatherLabel;
      state['activityLocationKnown'] = true;
      unresolved.remove('destination');
      return;
    }

    // A broad country/region can still be useful conversational context, but it
    // is not precise enough to become weather truth for a destination outfit.
    state.remove('activityLocationLabel');
    state['activityLocationKnown'] = false;
    if (destinationRequired) {
      unresolved.add('destination');
    } else {
      unresolved.remove('destination');
    }
  }

  static Future<Map<String, dynamic>> _deriveTravelTiming({
    required StylistTravelContext travel,
    required StylistTravelContext latestTravel,
    required Map<String, dynamic> state,
    required Map<String, dynamic> client,
    required StylistResolvedLocation? destination,
    required StylistResolvedLocation? explicitOrigin,
  }) async {
    if (!travel.travelMentioned) return const {};
    final now = DateTime.tryParse((client['now'] ?? '').toString()) ?? DateTime.now();
    final nowUtc = now.toUtc();
    final eventDate = _eventDate(state, client, now);

    final origin = explicitOrigin != null && explicitOrigin.weatherSpecific
        ? (
            latitude: explicitOrigin.latitude,
            longitude: explicitOrigin.longitude,
            source: 'user_explicit_provider',
          )
        : await _verifiedTravelOrigin(client);

    DateTime? departureUtc;
    String? departureSource;
    int? relativeOffsetMinutes;

    if (latestTravel.departureOffsetMinutes != null) {
      relativeOffsetMinutes = latestTravel.departureOffsetMinutes;
      departureUtc = nowUtc.add(Duration(minutes: relativeOffsetMinutes!));
      departureSource = 'user_relative';
    } else if (travel.departureHourLocal != null) {
      final minute = travel.departureMinuteLocal ?? 0;
      if (origin != null) {
        departureUtc = await _localClockToUtcForCoordinates(
          date: eventDate,
          hour: travel.departureHourLocal!,
          minute: minute,
          latitude: origin.latitude,
          longitude: origin.longitude,
        );
      }
      departureUtc ??= localWallClockToUtc(
        date: eventDate,
        hour: travel.departureHourLocal!,
        minute: minute,
        utcOffsetMinutes:
            _int(client['timezoneOffsetMinutes']) ?? now.timeZoneOffset.inMinutes,
      );
      departureSource = origin != null
          ? 'user_clock_origin_timezone'
          : 'user_clock_device_timezone';
    }

    final out = <String, dynamic>{
      if (departureUtc != null) 'departureAtUtc': departureUtc.toIso8601String(),
      if (departureSource != null) 'departureSource': departureSource,
      if (relativeOffsetMinutes != null)
        'departureOffsetMinutes': relativeOffsetMinutes,
      if (origin != null) 'originCoordinateSource': origin.source,
    };

    if (travel.arrivalHourLocal != null && destination?.weatherSpecific == true) {
      var localArrivalDate = eventDate;
      DateTime? arrivalUtc = await _localClockToUtcForCoordinates(
        date: localArrivalDate,
        hour: travel.arrivalHourLocal!,
        minute: travel.arrivalMinuteLocal ?? 0,
        latitude: destination!.latitude,
        longitude: destination.longitude,
      );
      if (arrivalUtc != null && departureUtc != null) {
        var guard = 0;
        while (!arrivalUtc!.isAfter(departureUtc) && guard < 3) {
          localArrivalDate = localArrivalDate.add(const Duration(days: 1));
          arrivalUtc = await _localClockToUtcForCoordinates(
            date: localArrivalDate,
            hour: travel.arrivalHourLocal!,
            minute: travel.arrivalMinuteLocal ?? 0,
            latitude: destination.latitude,
            longitude: destination.longitude,
          );
          guard += 1;
        }
      }
      out.addAll(<String, dynamic>{
        'arrivalHourLocal': travel.arrivalHourLocal,
        'arrivalMinuteLocal': travel.arrivalMinuteLocal ?? 0,
        'arrivalLocalDateKey': _dateKey(localArrivalDate),
        'arrivalTimeSource': 'user_explicit',
        'arrivalEstimateConfidence': 'explicit',
        if (arrivalUtc != null) 'arrivalAtUtc': arrivalUtc.toIso8601String(),
      });
      return out;
    }

    if (travel.arrivalHourLocal != null) {
      out.addAll(<String, dynamic>{
        'arrivalHourLocal': travel.arrivalHourLocal,
        'arrivalMinuteLocal': travel.arrivalMinuteLocal ?? 0,
        'arrivalLocalDateKey': _dateKey(eventDate),
        'arrivalTimeSource': 'user_explicit_unconverted',
        'arrivalEstimateConfidence': 'explicit',
      });
      return out;
    }

    if (departureUtc == null ||
        destination == null ||
        !destination.weatherSpecific ||
        origin == null ||
        travel.transportMode == StylistTransportMode.unknown) {
      return out;
    }

    final directKm = greatCircleDistanceKm(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    final durationMinutes = estimateTravelDurationMinutes(
      travel.transportMode,
      directKm,
    );
    if (durationMinutes == null) return out;
    final uncertaintyMinutes = estimateTravelUncertaintyMinutes(
      travel.transportMode,
      durationMinutes,
    );
    final arrivalUtc = departureUtc.add(Duration(minutes: durationMinutes));

    out.addAll(<String, dynamic>{
      'directDistanceKm': directKm.round(),
      'estimatedDurationMinutes': durationMinutes,
      if (travel.transportMode == StylistTransportMode.road)
        'estimatedRoadDurationMinutes': durationMinutes,
      'estimatedArrivalAtUtc': arrivalUtc.toIso8601String(),
      'arrivalTimeSource': '${travel.transportMode.wireName}_distance_estimate',
      'arrivalEstimateConfidence': 'rough',
      'arrivalEstimateUncertaintyMinutes': uncertaintyMinutes,
      'arrivalWindowStartAtUtc': arrivalUtc
          .subtract(Duration(minutes: uncertaintyMinutes))
          .toIso8601String(),
      'arrivalWindowEndAtUtc': arrivalUtc
          .add(Duration(minutes: uncertaintyMinutes))
          .toIso8601String(),
    });

    final offset = await StylistDestinationTimeService.utcOffsetMinutes(
      latitude: destination.latitude,
      longitude: destination.longitude,
      atUtc: arrivalUtc,
    );
    if (offset != null) {
      final wallClock = arrivalUtc.add(Duration(minutes: offset)).toUtc();
      out['destinationUtcOffsetMinutes'] = offset;
      out['estimatedArrivalHourLocal'] = wallClock.hour;
      out['estimatedArrivalMinuteLocal'] = wallClock.minute;
      out['arrivalLocalDateKey'] = _dateKey(wallClock);
    }
    return out;
  }

  static Future<({double latitude, double longitude, String source})?>
      _verifiedTravelOrigin(Map<String, dynamic> client) async {
    final rawLat = _double(client['latitude']);
    final rawLon = _double(client['longitude']);
    final label = (client['userGpsLocation'] ?? client['defaultWeatherCity'] ?? '')
        .toString()
        .trim();

    if (label.isEmpty) {
      if (rawLat == null || rawLon == null) return null;
      return (latitude: rawLat, longitude: rawLon, source: 'device_coordinates');
    }

    final provider = await StylistGlobalLocationService.resolveQuery(
      label,
      evidence: label,
    );
    if (provider == null || !provider.weatherSpecific) return null;

    if (rawLat == null || rawLon == null) {
      return (
        latitude: provider.latitude,
        longitude: provider.longitude,
        source: 'gps_label_provider',
      );
    }

    final mismatchKm = greatCircleDistanceKm(
      rawLat,
      rawLon,
      provider.latitude,
      provider.longitude,
    );
    if (mismatchKm > 80) {
      return (
        latitude: provider.latitude,
        longitude: provider.longitude,
        source: 'gps_label_provider_coordinate_repair',
      );
    }
    return (latitude: rawLat, longitude: rawLon, source: 'device_coordinates');
  }

  static Future<DateTime?> _localClockToUtcForCoordinates({
    required DateTime date,
    required int hour,
    required int minute,
    required double latitude,
    required double longitude,
  }) async {
    // Noon is a stable first anchor for finding that date's offset. Re-check at
    // the derived instant so DST transition nights use the correct side.
    final anchor = DateTime.utc(date.year, date.month, date.day, 12);
    var offset = await StylistDestinationTimeService.utcOffsetMinutes(
      latitude: latitude,
      longitude: longitude,
      atUtc: anchor,
    );
    if (offset == null) return null;
    var utc = localWallClockToUtc(
      date: date,
      hour: hour,
      minute: minute,
      utcOffsetMinutes: offset,
    );
    final exactOffset = await StylistDestinationTimeService.utcOffsetMinutes(
      latitude: latitude,
      longitude: longitude,
      atUtc: utc,
    );
    if (exactOffset != null && exactOffset != offset) {
      offset = exactOffset;
      utc = localWallClockToUtc(
        date: date,
        hour: hour,
        minute: minute,
        utcOffsetMinutes: offset,
      );
    }
    return utc;
  }

  static Future<Map<String, dynamic>?> _arrivalWeather({
    required StylistResolvedLocation resolved,
    required StylistTravelContext travel,
    required Map<String, dynamic> timing,
    required Map<String, dynamic> state,
    required Map<String, dynamic> client,
    required HourlyWeatherService service,
  }) async {
    final now = DateTime.tryParse((client['now'] ?? '').toString()) ?? DateTime.now();
    final timingDate = DateTime.tryParse(
      (timing['arrivalLocalDateKey'] ?? '').toString(),
    );
    final date = timingDate ?? _eventDate(state, client, now);
    final snapshots = await service.getOpenMeteoForCoordinatesAndDates(
      latitude: resolved.latitude,
      longitude: resolved.longitude,
      dates: <DateTime>[date],
      locationLabel: resolved.weatherLabel,
    );
    final snapshot = snapshots[_dateKey(date)];
    if (snapshot == null || !snapshot.fromOpenMeteo) return null;

    final arrivalHour = _int(timing['estimatedArrivalHourLocal']) ??
        _int(timing['arrivalHourLocal']) ??
        travel.arrivalHourLocal;
    return <String, dynamic>{
      'providerVerifiedDestination': true,
      'cityName': resolved.weatherLabel,
      'dateKey': _dateKey(snapshot.date),
      'willRain': snapshot.willRain,
      'isWindy': snapshot.isWindy,
      'minTempC': snapshot.minTempC,
      'maxTempC': snapshot.maxTempC,
      'morningTempC': snapshot.morningTempC,
      'noonTempC': snapshot.noonTempC,
      'eveningTempC': snapshot.eveningTempC,
      if (arrivalHour != null) 'arrivalHourLocal': arrivalHour,
      if (arrivalHour != null)
        'arrivalTempC': snapshot.tempAtLocalHour(arrivalHour),
      if (timing['arrivalEstimateUncertaintyMinutes'] != null)
        'arrivalEstimateUncertaintyMinutes':
            timing['arrivalEstimateUncertaintyMinutes'],
      'timingSource': timing['arrivalTimeSource'] ??
          (travel.arrivalHourLocal != null ? 'user_explicit' : 'day_only'),
    };
  }

  static DateTime _eventDate(
    Map<String, dynamic> state,
    Map<String, dynamic> client,
    DateTime now,
  ) {
    final key = (state['dateKey'] ?? '').toString();
    final parsed = DateTime.tryParse(key);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    if (key == 'tomorrow') {
      final tomorrow = DateTime.tryParse(
        (client['tomorrowDateKey'] ?? '').toString(),
      );
      if (tomorrow != null) return tomorrow;
      return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    }
    final today = DateTime.tryParse((client['todayDateKey'] ?? '').toString());
    return today ?? DateTime(now.year, now.month, now.day);
  }

  static String _userConversation(
    String message,
    List<Map<String, String>> history,
  ) {
    final parts = <String>[];
    for (final item in history) {
      if ((item['role'] ?? '').trim().toLowerCase() != 'user') continue;
      final text = (item['content'] ?? '').trim();
      if (text.isNotEmpty && (parts.isEmpty || parts.last != text)) {
        parts.add(text);
      }
    }
    final latest = message.trim();
    if (latest.isNotEmpty && (parts.isEmpty || parts.last != latest)) {
      parts.add(latest);
    }
    return parts.join(' ');
  }

  static Set<String> _stringSet(Object? raw) {
    if (raw is! Iterable) return <String>{};
    return raw
        .map((value) => value.toString().trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static DateTime localWallClockToUtc({
    required DateTime date,
    required int hour,
    required int minute,
    required int utcOffsetMinutes,
  }) {
    final wallAsUtc = DateTime.utc(date.year, date.month, date.day, hour, minute);
    return wallAsUtc.subtract(Duration(minutes: utcOffsetMinutes));
  }

  static double greatCircleDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    double rad(double degrees) => degrees * math.pi / 180.0;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2).toDouble() +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.pow(math.sin(dLon / 2), 2).toDouble();
    return 2 * earthRadiusKm * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  static int? estimateTravelDurationMinutes(
    StylistTransportMode mode,
    double directDistanceKm,
  ) {
    if (!directDistanceKm.isFinite || directDistanceKm <= 0) return null;
    double minutes;
    switch (mode) {
      case StylistTransportMode.road:
        final factor = directDistanceKm < 50
            ? 1.28
            : directDistanceKm < 200
                ? 1.24
                : 1.25;
        final roadKm = directDistanceKm * factor;
        final averageKmh = directDistanceKm < 30
            ? 35.0
            : directDistanceKm < 100
                ? 55.0
                : directDistanceKm < 350
                    ? 75.0
                    : 88.0;
        minutes = roadKm / averageKmh * 60;
        if (minutes > 270) minutes += (minutes ~/ 180) * 10;
        break;
      case StylistTransportMode.air:
        final cruiseKmh = directDistanceKm < 500
            ? 560.0
            : directDistanceKm < 1800
                ? 700.0
                : 830.0;
        final blockOverheadMinutes = directDistanceKm < 500 ? 55.0 : 65.0;
        minutes = directDistanceKm / cruiseKmh * 60 + blockOverheadMinutes;
        break;
      case StylistTransportMode.rail:
        final railKm = directDistanceKm *
            (directDistanceKm < 250 ? 1.18 : 1.12);
        final averageKmh = directDistanceKm < 100
            ? 65.0
            : directDistanceKm < 500
                ? 105.0
                : directDistanceKm < 1200
                    ? 135.0
                    : 155.0;
        minutes = railKm / averageKmh * 60 + 15;
        break;
      case StylistTransportMode.sea:
        final seaKm = directDistanceKm * 1.08;
        final averageKmh = directDistanceKm < 120 ? 42.0 : 32.0;
        minutes = seaKm / averageKmh * 60 + 30;
        break;
      case StylistTransportMode.unknown:
        return null;
    }
    final rounded = (minutes / 5).round() * 5;
    return rounded.clamp(5, 72 * 60);
  }

  static int estimateTravelUncertaintyMinutes(
    StylistTransportMode mode,
    int durationMinutes,
  ) {
    final proportional = switch (mode) {
      StylistTransportMode.air => (durationMinutes * 0.18).round(),
      StylistTransportMode.rail => (durationMinutes * 0.22).round(),
      StylistTransportMode.road => (durationMinutes * 0.20).round(),
      StylistTransportMode.sea => (durationMinutes * 0.30).round(),
      StylistTransportMode.unknown => (durationMinutes * 0.30).round(),
    };
    final floor = switch (mode) {
      StylistTransportMode.air => 35,
      StylistTransportMode.rail => 25,
      StylistTransportMode.road => 25,
      StylistTransportMode.sea => 45,
      StylistTransportMode.unknown => 45,
    };
    return math.max(floor, proportional).clamp(floor, 180);
  }

  static int? estimateRoadDurationMinutes(double directDistanceKm) =>
      estimateTravelDurationMinutes(StylistTransportMode.road, directDistanceKm);
}
