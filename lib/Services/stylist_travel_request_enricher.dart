import 'dart:math' as math;

import '../models/stylist_resolved_location.dart';
import '../utils/stylist_destination_mention.dart';
import '../utils/stylist_travel_context.dart';
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
/// No named city/country/airport exists in this file.
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
    final travelPayload = Map<String, dynamic>.from(travel.toApiPayload());
    state['travelContext'] = travelPayload;

    final unresolved = _stringSet(state['unresolvedMaterialFields']);
    final allowBareLatest = unresolved.contains('destination');
    final mention =
        StylistDestinationMentionExtractor.extract(
          message,
          allowBareReply: allowBareLatest,
        ) ??
        StylistDestinationMentionExtractor.extract(conversation);

    StylistResolvedLocation? resolved;
    if (mention != null) {
      resolved = await StylistGlobalLocationService.resolve(
        conversation: conversation,
        latestUserText: message,
        allowBareLatest: allowBareLatest,
      );
      _applyLocationAuthority(
        state: state,
        unresolved: unresolved,
        mention: mention,
        resolved: resolved,
        travel: travel,
      );
    }

    final timing = await _deriveTravelTiming(
      travel: travel,
      state: state,
      client: client,
      resolved: resolved,
    );
    if (timing.isNotEmpty) {
      client['derivedTravelTiming'] = timing;
      travelPayload['derivedTravelTiming'] = timing;
    }

    if (resolved?.weatherSpecific == true &&
        travel.scope != StylistTravelScope.unknown &&
        travel.arrivalWeatherCouldHelp) {
      final arrivalWeather = await _arrivalWeather(
        resolved: resolved!,
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

    // Never preserve a legacy named-place guess after a provider-backed
    // destination mention has been attempted. A broad/unknown place may still
    // be perfectly fine for a transit-only outfit, but it is not weather truth.
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
    required Map<String, dynamic> state,
    required Map<String, dynamic> client,
    required StylistResolvedLocation? resolved,
  }) async {
    if (!travel.travelMentioned) return const {};
    final now = DateTime.tryParse((client['now'] ?? '').toString()) ?? DateTime.now();
    final nowUtc = now.toUtc();

    DateTime? departureUtc;
    String? departureSource;
    if (travel.departureOffsetMinutes != null) {
      departureUtc = nowUtc.add(Duration(minutes: travel.departureOffsetMinutes!));
      departureSource = 'user_relative';
    } else if (travel.departureHourLocal != null) {
      final localDate = _eventDate(state, client, now);
      final localDeparture = DateTime(
        localDate.year,
        localDate.month,
        localDate.day,
        travel.departureHourLocal!,
      );
      departureUtc = localDeparture.toUtc();
      departureSource = 'user_clock';
    }

    final out = <String, dynamic>{
      if (departureUtc != null) 'departureAtUtc': departureUtc.toIso8601String(),
      if (departureSource != null) 'departureSource': departureSource,
      if (travel.departureOffsetMinutes != null)
        'departureOffsetMinutes': travel.departureOffsetMinutes,
    };

    if (travel.arrivalHourLocal != null) {
      out['arrivalHourLocal'] = travel.arrivalHourLocal;
      out['arrivalTimeSource'] = 'user_explicit';
      final date = _eventDate(state, client, now);
      out['arrivalLocalDateKey'] = _dateKey(date);
      return out;
    }

    if (travel.transportMode != StylistTransportMode.road ||
        departureUtc == null ||
        resolved == null) {
      return out;
    }

    final originLat = _double(client['latitude']);
    final originLon = _double(client['longitude']);
    if (originLat == null || originLon == null) return out;

    final directKm = greatCircleDistanceKm(
      originLat,
      originLon,
      resolved.latitude,
      resolved.longitude,
    );
    final durationMinutes = estimateRoadDurationMinutes(directKm);
    if (durationMinutes == null) return out;

    final arrivalUtc = departureUtc.add(Duration(minutes: durationMinutes));
    out.addAll(<String, dynamic>{
      'directDistanceKm': directKm.round(),
      'estimatedRoadDurationMinutes': durationMinutes,
      'estimatedArrivalAtUtc': arrivalUtc.toIso8601String(),
      'arrivalTimeSource': 'geodesic_road_estimate',
      'arrivalEstimateConfidence': 'rough',
    });

    // For a near-term trip, convert the UTC estimate into the destination's
    // provider-backed local clock. Failure is non-fatal: UTC/duration remain.
    if (departureUtc.difference(nowUtc).abs() <= const Duration(days: 7)) {
      final offset = await StylistDestinationTimeService.utcOffsetMinutes(
        latitude: resolved.latitude,
        longitude: resolved.longitude,
      );
      if (offset != null) {
        final wallClock = arrivalUtc.add(Duration(minutes: offset)).toUtc();
        out['destinationUtcOffsetMinutes'] = offset;
        out['estimatedArrivalHourLocal'] = wallClock.hour;
        out['estimatedArrivalMinuteLocal'] = wallClock.minute;
        out['arrivalLocalDateKey'] = _dateKey(wallClock);
      }
    }
    return out;
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
    final snapshot = await service.getWeatherForCityAndDate(
      city: resolved.weatherLabel,
      date: date,
    );
    if (!snapshot.fromOpenMeteo) return null;

    final arrivalHour = _int(timing['estimatedArrivalHourLocal']) ??
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

  /// Deliberately rough fallback, never a navigation promise. It exists so a
  /// conversational stylist can distinguish "arrive around lunchtime" from
  /// "arrive late evening" when no routing provider is configured.
  static int? estimateRoadDurationMinutes(double directDistanceKm) {
    if (!directDistanceKm.isFinite || directDistanceKm <= 0) return null;
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
    var minutes = (roadKm / averageKmh * 60).round();
    if (minutes > 270) {
      // Small generic rest allowance. Traffic, borders and stops remain outside
      // this estimate and are why confidence is explicitly `rough`.
      minutes += (minutes ~/ 180) * 10;
    }
    return minutes.clamp(5, 24 * 60);
  }
}
