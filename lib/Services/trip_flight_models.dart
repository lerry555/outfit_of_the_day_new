/// Metadáta pre odhad letu (Firestore / UI). Samostatný súbor kvôli importom medzi službami.
enum TripTimezoneConfidence {
  known,
  fallback,
  unknown,
}

TripTimezoneConfidence tripTimezoneConfidenceFromWire(Object? v) {
  final s = v?.toString().toLowerCase().trim();
  switch (s) {
    case 'known':
      return TripTimezoneConfidence.known;
    case 'fallback':
      return TripTimezoneConfidence.fallback;
    default:
      return TripTimezoneConfidence.unknown;
  }
}

String tripTimezoneConfidenceToWire(TripTimezoneConfidence c) {
  switch (c) {
    case TripTimezoneConfidence.known:
      return 'known';
    case TripTimezoneConfidence.fallback:
      return 'fallback';
    case TripTimezoneConfidence.unknown:
      return 'unknown';
  }
}

enum TripFlightPlanConfidence {
  high,
  medium,
  low,
  unknown,
}

TripFlightPlanConfidence tripFlightPlanConfidenceFromWire(Object? v) {
  final s = v?.toString().toLowerCase().trim();
  switch (s) {
    case 'high':
      return TripFlightPlanConfidence.high;
    case 'medium':
      return TripFlightPlanConfidence.medium;
    case 'low':
      return TripFlightPlanConfidence.low;
    default:
      return TripFlightPlanConfidence.unknown;
  }
}

String tripFlightPlanConfidenceToWire(TripFlightPlanConfidence c) {
  switch (c) {
    case TripFlightPlanConfidence.high:
      return 'high';
    case TripFlightPlanConfidence.medium:
      return 'medium';
    case TripFlightPlanConfidence.low:
      return 'low';
    case TripFlightPlanConfidence.unknown:
      return 'unknown';
  }
}
