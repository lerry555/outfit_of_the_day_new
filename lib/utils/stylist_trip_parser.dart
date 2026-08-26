import '../models/stylist_trip_window.dart';

/// Parsuje časy výletu zo slovenskej konverzácie.
///
/// Zámerne NEparsuje „kedy vyrazím z domu“ ako samostatnú otázku — to je pre
/// usera otravné. Pracujeme s: začiatok udalosti, prípadne koniec/návrat,
/// a rozsah „od X do Y“.
class StylistTripParser {
  const StylistTripParser._();

  static final RegExp _rangePattern = RegExp(
    r'od\s*(?:cca\s*)?(\d{1,2})(?::\d{2})?\s*(?:do|-|–|az|až)\s*(?:cca\s*)?(\d{1,2})(?::\d{2})?',
    caseSensitive: false,
  );

  static final RegExp _doPattern = RegExp(
    r'\bdo\s*(?:cca\s*)?(\d{1,2})(?::\d{2})?',
    caseSensitive: false,
  );

  static final RegExp _odPattern = RegExp(
    r'\bod\s*(?:cca\s*)?(\d{1,2})(?::\d{2})?',
    caseSensitive: false,
  );

  static final RegExp _oPattern = RegExp(
    r'(?:^|\s)(?:o|okolo)\s+(?:cca\s*)?(\d{1,2})(?::\d{2})?',
    caseSensitive: false,
  );

  static final RegExp _zacinaPattern = RegExp(
    r'za[čc][ií]na\w*\s*(?:to|sa|o|cca|\s)*\s*(\d{1,2})(?::\d{2})?',
    caseSensitive: false,
  );

  static final RegExp _clockPattern = RegExp(r'\b(\d{1,2}):\d{2}\b');

  static final RegExp _durationPattern = RegExp(
    r'\b(?:asi|cca|približne|priblizne)?\s*(\d{1,2})\s*(?:hod(?:inu|iny|ín|in)?|h)\b',
    caseSensitive: false,
  );

  static final RegExp _returnPattern = RegExp(
    r'(?:domov|sp[äa]t[ʼ\u0165]?|nasp[äa]t[ʼ\u0165]?|vr[áa]t[ií]m?e?)\s*'
    r'(?:o|okolo|po|do|cca)?\s*(\d{1,2})(?::\d{2})?',
    caseSensitive: false,
  );

  static StylistTripWindow parseFromConversation(String conversation) {
    final blob = conversation.toLowerCase();
    if (blob.trim().isEmpty) return const StylistTripWindow();

    int? eventStart;
    int? tripStart;
    int? tripEnd;

    final range = _rangePattern.firstMatch(blob);
    if (range != null) {
      tripStart = _hour(range.group(1));
      eventStart = tripStart;
      tripEnd = _hour(range.group(2));
    } else {
      final od = _odPattern.firstMatch(blob);
      if (od != null) {
        tripStart = _hour(od.group(1));
        eventStart = tripStart;
      }
      final doMatch = _doPattern.firstMatch(blob);
      if (doMatch != null) {
        tripEnd = _hour(doMatch.group(1));
      }
    }

    final returnMatch = _returnPattern.firstMatch(blob);
    if (returnMatch != null) {
      final h = _hour(returnMatch.group(1));
      if (h != null) tripEnd = h;
    }

    // Explicitný začiatok „o 18 / okolo 18“ má prednosť pre eventStart.
    final oMatch = _oPattern.firstMatch(blob);
    if (oMatch != null) {
      final h = _hour(oMatch.group(1));
      if (h != null) eventStart = h;
    }

    // „začína to 14:00 ...“
    if (eventStart == null) {
      final za = _zacinaPattern.firstMatch(blob);
      if (za != null) {
        final h = _hour(za.group(1));
        if (h != null) eventStart = h;
      }
    }

    // Posledná záchrana: holé časy typu „14:00 ... 22:00“ bez predložky.
    if (eventStart == null || tripEnd == null) {
      final clockHours =
          _clockPattern
              .allMatches(blob)
              .map((m) => _hour(m.group(1)))
              .whereType<int>()
              .toList()
            ..sort();
      if (clockHours.isNotEmpty) {
        eventStart ??= clockHours.first;
        if (clockHours.length >= 2) {
          tripEnd ??= clockHours.last;
        }
      }
    }

    // A duration belongs to the event window, not merely to prose.  This lets
    // weather reasoning inspect a long hike/day out as a range instead of one
    // arbitrary start-hour snapshot.
    if (eventStart != null && tripEnd == null) {
      final duration = _durationPattern.firstMatch(blob);
      final hours = duration == null ? null : _hour(duration.group(1));
      if (hours != null && hours > 0) {
        tripEnd = eventStart + hours > 23 ? 23 : eventStart + hours;
      }
    }

    if (eventStart != null && tripEnd != null && eventStart > tripEnd) {
      final tmp = eventStart;
      eventStart = tripEnd;
      tripEnd = tmp;
    }

    if (eventStart == null && tripStart == null && tripEnd == null) {
      return const StylistTripWindow();
    }

    return StylistTripWindow(
      tripStartHour: tripStart,
      eventStartHour: eventStart ?? tripStart,
      tripEndHour: tripEnd,
      tripEndEstimated: tripEnd == null && eventStart != null,
    );
  }

  static int? _hour(String? raw) {
    if (raw == null) return null;
    final h = int.tryParse(raw);
    if (h == null || h < 0 || h > 23) return null;
    return h;
  }
}
