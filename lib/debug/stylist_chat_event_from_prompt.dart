import '../Services/stylist_chat_outfit_service.dart';
import '../Services/user_location_service.dart';
import '../models/stylist_trip_window.dart';
import '../utils/stylist_day_parser.dart';
import '../utils/stylist_destination_parser.dart';
import '../utils/stylist_occasion_guidance.dart';
import '../utils/stylist_trip_parser.dart';

/// Debug helper — zostaví [StylistChatEventContext] z testovacieho promptu.
class StylistChatEventFromPrompt {
  const StylistChatEventFromPrompt._();

  static StylistChatEventContext build(
    String prompt, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final conversation = prompt.trim();
    final tripParsed = StylistTripParser.parseFromConversation(conversation);
    final explicitDate = StylistDayParser.resolveDate(conversation, now: clock);
    final date = explicitDate ?? DateTime(clock.year, clock.month, clock.day);
    final hour = tripParsed.eventStartHour ?? _inferHour(conversation, clock);
    final location = _resolveLocation();
    final profile = StylistOccasionGuidance.profileFor(
      conversationText: conversation,
    );

    return StylistChatEventContext(
      date: date,
      hourLocal: hour,
      locationLabel: location,
      occasion: profile.label.isNotEmpty ? profile.label : null,
      tripWindow: tripParsed,
    );
  }

  static String _resolveLocation() {
    final gps = UserLocationService.instance.cityLabel.trim();
    if (gps.isNotEmpty) return gps.split(',').first.trim();
    return 'Bratislava';
  }

  static int? _inferHour(String conversation, DateTime now) {
    final explicit = RegExp(
      r'(?:\b(o|okolo)\s*(\d{1,2})(?::\d{2})?|\b(\d{1,2}):\d{2}\b)',
      caseSensitive: false,
    ).firstMatch(conversation);
    if (explicit != null) {
      final hour = int.tryParse(explicit.group(2) ?? explicit.group(3) ?? '');
      if (hour != null && hour >= 0 && hour <= 23) return hour;
    }

    final blob = conversation.toLowerCase();
    if (blob.contains('večer') || blob.contains('vecer')) return 19;
    if (blob.contains('ráno') || blob.contains('rano')) return 7;
    if (blob.contains('teraz') || blob.contains('hned') || blob.contains('ihned')) {
      return now.hour;
    }
    if (StylistDestinationParser.userWantsOutfitFromWardrobe(conversation)) {
      return 12;
    }
    return null;
  }
}
