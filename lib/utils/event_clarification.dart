import '../models/stylist_trip_window.dart';
import 'dress_code_resolver.dart';
import 'slovak_city_locative.dart';
import 'stylist_destination_parser.dart';
import 'stylist_occasion_guidance.dart';
import 'stylist_trip_parser.dart';

/// Legacy deterministic clarification helper.
///
/// It may reason about generic event structure, but never about named artists,
/// places or brands. Brain V1 remains the conversational wording authority.
class EventClarification {
  const EventClarification._();

  static bool needsMoreContext(
    String conversation, {
    required String gpsCityLabel,
  }) => missingMessage(conversation, gpsCityLabel: gpsCityLabel) != null;

  static String? missingMessage(
    String conversation, {
    required String gpsCityLabel,
    bool gpsSufficientForLocation = true,
  }) {
    final blob = conversation.toLowerCase();
    if (blob.trim().isEmpty) return null;

    if (!StylistDestinationParser.userWantsOutfitFromWardrobe(conversation) &&
        !_impliesOutingPlan(blob)) {
      return null;
    }

    if (DressCodeResolver.needsDateActivityClarification(conversation)) {
      return StylistOccasionGuidance.activityClarificationMessage;
    }

    if (DressCodeResolver.needsVenueClarification(conversation)) {
      return 'Je to vonku (festival, štadión, amfiteáter), alebo v sále či klube? '
          'Typ priestoru môže zmeniť vrstvy aj formálnosť.';
    }

    if (gpsSufficientForLocation) {
      final inferred = StylistDestinationParser.inferFromConversation(conversation);
      final needsDest = StylistDestinationParser.needsDestinationForOutfit(
        conversationText: conversation,
        inferredDestination: inferred,
        gpsCityLabel: gpsCityLabel,
      );
      if (needsDest) {
        final place =
            SlovakCityLocative.inCity(gpsCityLabel.split(',').first.trim());
        return 'V ktorom meste alebo lokalite to je? Zostaneš $place, alebo ideš inde?';
      }
    }

    final isConcert = blob.contains('koncert') ||
        blob.contains('festival') ||
        blob.contains('amfik') ||
        blob.contains('amfite');
    if (isConcert && !_hasPerformerOrGenre(conversation)) {
      if (!_userSpecifiedHour(conversation)) {
        return 'Vieš aj interpreta alebo aspoň žáner? Ak áno, pomôže mi to doladiť štýl.';
      }
    }

    final window = StylistTripParser.parseFromConversation(conversation);
    final startMissing =
        window.eventStartHour == null && !_userSpecifiedHour(conversation);
    final endMissing = _needsTripEndTime(blob) && window.tripEndHour == null;
    if (startMissing || endMissing) {
      if (startMissing && endMissing) {
        return _needsTripEndTime(blob)
            ? 'O koľkej to začína a dokedy tam plánuješ byť?'
            : _timeQuestionFor(blob);
      }
      if (startMissing) return _timeQuestionFor(blob);
      if (_needsTripEndTime(blob)) return 'A dokedy tam plánuješ byť?';
    }

    return null;
  }

  static bool _needsTripEndTime(String blob) {
    if (blob.contains('divadl') ||
        blob.contains('kino') ||
        blob.contains('múze') ||
        blob.contains('muze') ||
        blob.contains('galér') ||
        blob.contains('galer') ||
        blob.contains('balet') ||
        blob.contains('oper')) {
      return false;
    }
    if ((blob.contains('festival') || blob.contains('koncert')) &&
        RegExp(r'(?:o|okolo)\s*\d', caseSensitive: false).hasMatch(blob)) {
      return false;
    }
    return _isLongOuting(blob);
  }

  static String _timeQuestionFor(String blob) =>
      _isCasualOutdoorWalk(blob) ? 'O koľkej plánuješ ísť?' : 'O koľkej vyrazíš?';

  static bool _userSpecifiedHour(String conversation) {
    final blob = conversation.toLowerCase();
    if (blob.contains('teraz') || blob.contains('hned') || blob.contains('ihned')) {
      return true;
    }
    return RegExp(
      r'(?:o|okolo)\s*(\d{1,2})(?::\d{2})?',
      caseSensitive: false,
    ).hasMatch(blob);
  }

  static bool _hasPerformerOrGenre(String conversation) {
    final blob = conversation.toLowerCase();
    const genres = [
      'rock',
      'rap',
      'pop',
      'metal',
      'techno',
      'klasik',
      'jazz',
      'folk',
      'hiphop',
      'hip hop',
      'rnb',
      'punk',
      'opera',
      'dychov',
      'ludov',
      'ľudov',
      'dj ',
    ];
    if (genres.any(blob.contains)) return true;

    final explicitPerformer = RegExp(
      r'(?:hr[áa]|hraje|hraj[úu]|vystupuje|kapela|skupina|interpret(?:a|i)?)\s+'
      r'([a-zá-ž0-9][a-zá-ž0-9\-]{2,})',
      caseSensitive: false,
    ).firstMatch(blob);
    if (explicitPerformer != null) {
      final token = (explicitPerformer.group(1) ?? '').trim();
      const stop = {
        'vonku',
        'dnu',
        'vnutri',
        'vnútri',
        'tam',
        'dlho',
        'naživo',
        'nazivo',
        'live',
        'dobre',
        'super',
      };
      if (!stop.contains(token)) return true;
    }

    // A bare "na <word>" is only weak structural evidence. It is accepted
    // after excluding generic event/activity nouns; no artist whitelist exists.
    final match = RegExp(
      r'\bna\s+([a-zá-žäôĺľŕ][\wá-žäôĺľŕ\-]{2,})',
      caseSensitive: false,
    ).firstMatch(blob);
    if (match == null) return false;
    final token = (match.group(1) ?? '').toLowerCase();
    const notPerformer = {
      'koncert',
      'koncerte',
      'festival',
      'seba',
      'sebe',
      'rande',
      'zmrzlinu',
      'prechadzku',
      'prechádzku',
      'prechadzke',
      'prechádzke',
      'vylet',
      'výlet',
      'akciu',
      'akcii',
      'amfik',
      'amfiku',
      'cestu',
      'ceste',
      'spat',
      'späť',
      'obed',
      'veceru',
      'večeru',
      'kavu',
      'kávu',
      'pivo',
      'predstavenie',
      'vystupenie',
      'mna',
      'mňa',
      'teba',
      'neho',
      'nieho',
    };
    return token.length >= 3 && !notPerformer.contains(token);
  }

  static bool _impliesOutingPlan(String blob) =>
      blob.contains('idem') ||
      blob.contains('ideme') ||
      blob.contains('chcem') ||
      blob.contains('chceme') ||
      blob.contains('koncert') ||
      blob.contains('divadl') ||
      blob.contains('festival') ||
      blob.contains('amfik') ||
      blob.contains('amfite');

  static bool _isLongOuting(String blob) =>
      blob.contains('koncert') ||
      blob.contains('festival') ||
      blob.contains('divadl') ||
      blob.contains('amfik') ||
      blob.contains('amfite') ||
      blob.contains('predstaven');

  static bool isCasualOutdoorWalk(String conversation) =>
      _isCasualOutdoorWalk(conversation.toLowerCase());

  static bool _isCasualOutdoorWalk(String blob) =>
      blob.contains('prech') ||
      blob.contains('hory') ||
      blob.contains(' do hor') ||
      blob.contains('v hor') ||
      blob.contains('výlet') ||
      blob.contains('vylet') ||
      blob.contains('turist');

  static StylistTripWindow tripWindowFromConversation(String conversation) =>
      StylistTripParser.parseFromConversation(conversation);
}
