/// Časové okno celého výletu (odchod → udalosť → návrat), nie jedna hodina.
class StylistTripWindow {
  final int? tripStartHour;
  final int? eventStartHour;
  final int? eventEndHour;
  final int? tripEndHour;
  final bool tripEndEstimated;

  const StylistTripWindow({
    this.tripStartHour,
    this.eventStartHour,
    this.eventEndHour,
    this.tripEndHour,
    this.tripEndEstimated = false,
  });

  int get effectiveEventStart => eventStartHour ?? tripStartHour ?? 12;

  int get effectiveTripStart {
    final start = tripStartHour;
    if (start != null) return start.clamp(0, 23);
    final event = eventStartHour;
    if (event != null) return (event - 1).clamp(0, 23);
    return effectiveEventStart;
  }

  int get effectiveTripEnd {
    final end = tripEndHour;
    if (end != null) return end.clamp(0, 23);
    final eventEnd = eventEndHour;
    if (eventEnd != null) return eventEnd.clamp(0, 23);
    return (effectiveEventStart + 4).clamp(0, 23);
  }

  int get effectiveEventEnd {
    final end = eventEndHour;
    if (end != null) return end.clamp(0, 23);
    return effectiveTripEnd;
  }

  bool get spansMultipleSegments =>
      effectiveTripEnd - effectiveTripStart >= 3;

  /// True iba ak používateľ reálne uviedol nejaký čas (hodinu odchodu, udalosti
  /// alebo návratu). Keď je false, nemáme právo tvrdiť „pred/počas udalosti“.
  bool get hasExplicitTime =>
      eventStartHour != null ||
      tripStartHour != null ||
      eventEndHour != null ||
      tripEndHour != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (tripStartHour != null) 'tripStartHour': tripStartHour,
        if (eventStartHour != null) 'eventStartHour': eventStartHour,
        if (eventEndHour != null) 'eventEndHour': eventEndHour,
        if (tripEndHour != null) 'tripEndHour': tripEndHour,
        if (tripEndEstimated) 'tripEndEstimated': true,
      };

  factory StylistTripWindow.fromDynamic(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const StylistTripWindow();
    int? parseHour(Object? value) {
      if (value == null) return null;
      final h = int.tryParse(value.toString());
      if (h == null || h < 0 || h > 23) return null;
      return h;
    }

    final tripStart = parseHour(raw['tripStartHour'] ?? raw['departureHour']);
    final eventStart =
        parseHour(raw['eventStartHour'] ?? raw['hourLocal'] ?? raw['hour']);
    final eventEnd = parseHour(raw['eventEndHour']);
    final tripEnd =
        parseHour(raw['tripEndHour'] ?? raw['returnHour'] ?? raw['homeHour']);
    final estimated = raw['tripEndEstimated'] == true;

    return StylistTripWindow(
      tripStartHour: tripStart,
      eventStartHour: eventStart,
      eventEndHour: eventEnd,
      tripEndHour: tripEnd,
      tripEndEstimated: estimated,
    );
  }

  StylistTripWindow merge(StylistTripWindow other) {
    return StylistTripWindow(
      tripStartHour: tripStartHour ?? other.tripStartHour,
      eventStartHour: eventStartHour ?? other.eventStartHour,
      eventEndHour: eventEndHour ?? other.eventEndHour,
      tripEndHour: tripEndHour ?? other.tripEndHour,
      tripEndEstimated: tripEndEstimated || other.tripEndEstimated,
    );
  }
}
