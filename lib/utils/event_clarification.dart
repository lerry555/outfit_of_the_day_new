import '../models/stylist_trip_window.dart';
import 'dress_code_resolver.dart';
import 'slovak_city_locative.dart';
import 'stylist_day_parser.dart';
import 'stylist_destination_parser.dart';
import 'stylist_occasion_guidance.dart';
import 'stylist_trip_parser.dart';

/// Čo ešte chýba pred outfitom — jednotná logika otázok.
///
/// Namiesto pýtania sa po jednej veci zlúči chýbajúce info (mesto, čas,
/// dokedy, vonku/sála) do jednej prirodzenej otázky ako reálny stylista.
class EventClarification {
  const EventClarification._();

  static bool needsMoreContext(
    String conversation, {
    required String gpsCityLabel,
  }) {
    return missingMessage(conversation, gpsCityLabel: gpsCityLabel) != null;
  }

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

    // Pýtame sa POSTUPNE — jedna vec na jednu otázku, aby sa user nestrácal
    // a aby sa tá istá dlhá otázka nezopakovala dookola.

    // 1) Vonku / v sále (kvôli dress code pri koncerte).
    if (DressCodeResolver.needsVenueClarification(conversation)) {
      return 'Je to vonku (amfik, festival, štadión), alebo v sále '
          '(filharmónia, klub)? Pri koncerte vonku v teple je iný outfit ako '
          'v hale.';
    }

    // 2) Mesto — samostatná otázka (GPS len ak aktivita to dovoľuje).
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
        return 'V ktorom meste to je? Zostaneš $place, alebo ideš inde?';
      }
    }

    // 3) Kto hrá — samostatná otázka (len pri koncerte a len ak to ešte nevieme).
    final isConcert = blob.contains('koncert') ||
        blob.contains('festival') ||
        blob.contains('amfik') ||
        blob.contains('amfite');
    if (isConcert && !_hasPerformerOrGenre(conversation)) {
      if (!_userSpecifiedHour(conversation)) {
        return 'A na koho idete — kto hrá? Podľa štýlu (rock, pop, klasika…) '
            'doladím outfit.';
      }
    }

    // 4) Čas — bez neho nevieme zložiť správny outfit (ráno ≠ popoludnie).
    final window = StylistTripParser.parseFromConversation(conversation);
    final startMissing = window.eventStartHour == null &&
        !_userSpecifiedHour(conversation);
    final endMissing =
        _needsTripEndTime(blob) && window.tripEndHour == null;
    if (startMissing || endMissing) {
      if (startMissing && endMissing) {
        if (_needsTripEndTime(blob)) {
          return 'O koľkej to začína a dokedy tam plánuješ byť?';
        }
        return _timeQuestionFor(blob);
      }
      if (startMissing) {
        return _timeQuestionFor(blob);
      }
      if (_needsTripEndTime(blob)) {
        return 'A dokedy tam plánuješ byť?';
      }
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

  static String _timeQuestionFor(String blob) {
    if (_isCasualOutdoorWalk(blob)) {
      return 'O koľkej plánuješ ísť?';
    }
    return 'O koľkej vyrazíš?';
  }

  static bool _userSpecifiedHour(String conversation) {
    final blob = conversation.toLowerCase();
    if (blob.contains('teraz') ||
        blob.contains('hned') ||
        blob.contains('ihned')) {
      return true;
    }
    return RegExp(
      r'(?:o|okolo)\s*(\d{1,2})(?::\d{2})?',
      caseSensitive: false,
    ).hasMatch(blob);
  }

  /// Známi interpreti/kapely — aby sme ich rozpoznali aj malými písmenami.
  static const Set<String> _knownPerformers = {
    'rytmus',
    'rytmusa',
    'rytmicu',
    'rytmusovi',
    'elan',
    'elán',
    'kabát',
    'kabat',
    'desmod',
    'imt smile',
    'horkýže',
    'horkyze',
    'kollárovci',
    'kollarovci',
    'gladiator',
    'tublatanka',
    'kandráčovci',
    'kandracovci',
    'majk spirit',
    'separ',
    'ego',
    'kali',
    'no name',
    'iné kafe',
    'ine kafe',
    'acdc',
    'ac/dc',
    'metallica',
    'nightwish',
  };

  /// Pozná appka interpreta alebo žáner? Ak nie, opýta sa naňho.
  static bool _hasPerformerOrGenre(String conversation) {
    final blob = conversation.toLowerCase();
    if (_knownPerformers.any(blob.contains)) return true;
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
      'elan',
      'elán',
      'kabát',
      'kabat',
    ];
    if (genres.any(blob.contains)) return true;

    // Meno po „hrá / hraje / hrajú / vystupuje / kapela / skupina / interpret“.
    final playMatch = RegExp(
      r'(?:hr[áa]|hraje|hraj[úu]|vystupuje|kapela|skupina|interpret(?:a|i)?)\s+'
      r'([a-zá-ž0-9]{3,})',
      caseSensitive: false,
    ).firstMatch(blob);
    if (playMatch != null) {
      final token = (playMatch.group(1) ?? '').trim();
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

    // Meno v akuzatíve po „na “ (na rytmicu, na elán, na fitipal) — aj malými
    // písmenami, aby sa appka necyklila pri neznámom interpretovi.
    final match = RegExp(
      r'\bna\s+([a-zá-žäôĺľŕ][\wá-žäôĺľŕ]{2,})',
      caseSensitive: false,
    ).firstMatch(blob);
    if (match != null) {
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
      if (token.length >= 3 && !notPerformer.contains(token)) return true;
    }
    return false;
  }

  static bool _impliesOutingPlan(String blob) {
    return blob.contains('idem') ||
        blob.contains('ideme') ||
        blob.contains('chcem') ||
        blob.contains('chceme') ||
        blob.contains('koncert') ||
        blob.contains('divadl') ||
        blob.contains('festival') ||
        blob.contains('amfik') ||
        blob.contains('amfite');
  }

  static bool _isLongOuting(String blob) {
    return blob.contains('koncert') ||
        blob.contains('festival') ||
        blob.contains('divadl') ||
        blob.contains('elan') ||
        blob.contains('elán') ||
        blob.contains('amfik') ||
        blob.contains('amfite') ||
        blob.contains('predstaven');
  }

  static bool isCasualOutdoorWalk(String conversation) {
    return _isCasualOutdoorWalk(conversation.toLowerCase());
  }

  static bool _isCasualOutdoorWalk(String blob) {
    return blob.contains('prech') ||
        blob.contains('hory') ||
        blob.contains(' do hor') ||
        blob.contains('v hor') ||
        blob.contains('výlet') ||
        blob.contains('vylet') ||
        blob.contains('turist');
  }

  static StylistTripWindow tripWindowFromConversation(String conversation) {
    return StylistTripParser.parseFromConversation(conversation);
  }
}
