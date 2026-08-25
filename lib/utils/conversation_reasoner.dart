import '../data/activity_traits.dart';
import '../data/conversation_decision.dart';
import '../data/parsed_destination.dart';
import 'activity_traits_inferencer.dart';
import 'dress_code_resolver.dart';
import 'event_clarification.dart';
import 'stylist_destination_parser.dart';
import 'stylist_occasion_guidance.dart';

/// Rozhodovacia vrstva pred weather / AI / outfit — „mám všetko, čo potrebujem?“
abstract final class ConversationReasoner {
  static ConversationDecision evaluate({
    required String conversation,
    String latestMessage = '',
    String? gpsCityLabel,
    Set<String> excludeDestinations = const <String>{},
  }) {
    final blob = conversation.toLowerCase();
    final wantsOutfit = StylistDestinationParser.userWantsOutfitFromWardrobe(
          conversation,
        ) ||
        (latestMessage.isNotEmpty &&
            StylistDestinationParser.userWantsOutfitFromWardrobe(latestMessage));

    if (!wantsOutfit && !_impliesOutingPlan(blob)) {
      return ConversationDecision.passthrough();
    }

    final traits = ActivityTraitsInferencer.infer(conversation);

    // 1) Destinácia (M9) — krajina, POI bez mesta, neznámy názov…
    final destination = StylistDestinationParser.parseDestination(
      conversation,
      exclude: excludeDestinations,
    );
    if (destination.hasTravelDestination &&
        destination.needsClarification &&
        _destinationClarificationRequired(destination, traits)) {
      return ConversationDecision.clarify(
        missing: MissingInformation.destination,
        questionSk: destination.clarificationQuestionSk ??
            'V ktorom meste alebo lokalite sa to nachádza?',
        reason: 'destination_${destination.type.label}',
        wantsOutfit: wantsOutfit,
      );
    }

    final explicitLocation = _explicitResolvableLocation(
      conversation,
      destination,
      excludeDestinations,
    );
    final gps = (gpsCityLabel ?? '').split(',').first.trim();

    // 2) Aktivita vyžaduje konkrétnu lokalitu — GPS nestačí (túra, hory, ZOO…).
    if (traits.requiresSpecificLocation && explicitLocation == null) {
      return ConversationDecision.clarify(
        missing: MissingInformation.specificLocation,
        questionSk: _specificLocationQuestion(traits),
        reason: 'activity_requires_location_${traits.reason}',
        wantsOutfit: wantsOutfit,
      );
    }

    // 3) POI v destinácii bez mesta (aj keď stem nezachytil).
    if (_poiNeedsCity(destination, traits)) {
      return ConversationDecision.clarify(
        missing: MissingInformation.specificLocation,
        questionSk: destination.clarificationQuestionSk ??
            'V ktorom meste sa to nachádza?',
        reason: 'poi_without_city',
        wantsOutfit: wantsOutfit,
      );
    }

    // 4) Aktivita / dress code / čas — existujúca logika otázok.
    if (StylistOccasionGuidance.needsActivityClarification(conversation)) {
      return ConversationDecision.clarify(
        missing: MissingInformation.activity,
        questionSk: StylistOccasionGuidance.clarificationMessageFor(conversation),
        reason: 'activity_clarification',
        wantsOutfit: wantsOutfit,
      );
    }

    if (DressCodeResolver.needsVenueClarification(conversation)) {
      return ConversationDecision.clarify(
        missing: MissingInformation.venueType,
        questionSk:
            'Je to vonku (amfik, festival, štadión), alebo v sále '
            '(filharmónia, klub)? Pri koncerte vonku v teple je iný outfit ako '
            'v hale.',
        reason: 'venue_type',
        wantsOutfit: wantsOutfit,
      );
    }

    // EventClarification — čas, performer; lokáciu riešime vyššie s GPS pravidlom.
    final eventGap = EventClarification.missingMessage(
      conversation,
      gpsCityLabel: gps,
      gpsSufficientForLocation: !traits.requiresSpecificLocation,
    );
    if (eventGap != null) {
      final missing = _mapEventGapToMissing(eventGap, blob);
      return ConversationDecision.clarify(
        missing: missing,
        questionSk: eventGap,
        reason: 'event_${missing.label}',
        wantsOutfit: wantsOutfit,
      );
    }

    return ConversationDecision.generate(
      reason: wantsOutfit ? 'outfit_context_complete' : 'outing_plan_ok',
      wantsOutfit: wantsOutfit,
    );
  }

  static bool _destinationClarificationRequired(
    ParsedDestination destination,
    ActivityTraits traits,
  ) {
    return switch (destination.type) {
      DestinationType.country ||
      DestinationType.region ||
      DestinationType.airport ||
      DestinationType.ambiguous =>
        true,
      DestinationType.unknown ||
      DestinationType.pointOfInterest ||
      DestinationType.venue ||
      DestinationType.address =>
        traits.poiDependent ||
            traits.outdoor ||
            traits.travel ||
            (!traits.routineLocal && !traits.venueBound),
      _ => false,
    };
  }

  static String? _explicitResolvableLocation(
    String conversation,
    ParsedDestination destination,
    Set<String> excludeDestinations,
  ) {
    final fromParser = destination.weatherCity;
    if (fromParser != null &&
        fromParser.trim().isNotEmpty &&
        !excludeDestinations.contains(fromParser.toLowerCase())) {
      return fromParser;
    }
    final inferred = StylistDestinationParser.inferFromConversation(
      conversation,
      exclude: excludeDestinations,
    );
    if (StylistDestinationParser.isConfidentResolvableCity(inferred)) {
      return inferred;
    }
    return null;
  }

  static bool _poiNeedsCity(
    ParsedDestination destination,
    ActivityTraits traits,
  ) {
    if (!destination.hasTravelDestination) return false;
    if (traits.routineLocal || (traits.venueBound && !traits.poiDependent)) {
      return false;
    }
    if (destination.type == DestinationType.pointOfInterest ||
        destination.type == DestinationType.venue ||
        destination.type == DestinationType.unknown) {
      return destination.needsClarification && destination.weatherCity == null;
    }
    return false;
  }

  static String _specificLocationQuestion(ActivityTraits traits) {
    final label = traits.activityLabelSk;
    if (label != null) {
      return 'Kam presne idete — $label? Lokalita výrazne ovplyvňuje outfit '
          'a počasie, takže GPS nestačí.';
    }
    return 'Kam presne to bude? Pri tejto aktivite záleží na konkrétnej '
        'lokalite — GPS nestačí.';
  }

  static MissingInformation _mapEventGapToMissing(String message, String blob) {
    final lower = message.toLowerCase();
    if (lower.contains('meste') || lower.contains('lokalit')) {
      return MissingInformation.specificLocation;
    }
    if (lower.contains('koľkej') ||
        lower.contains('kolk') ||
        lower.contains('o koľkej') ||
        lower.contains('dokedy')) {
      return MissingInformation.time;
    }
    if (blob.contains('koncert') &&
        (lower.contains('kto hrá') || lower.contains('kto hra'))) {
      return MissingInformation.performer;
    }
    if (lower.contains('vonku') || lower.contains('sále') || lower.contains('sale')) {
      return MissingInformation.venueType;
    }
    return MissingInformation.activity;
  }

  static bool _impliesOutingPlan(String blob) {
    return blob.contains('zajtra') ||
        blob.contains('pozajtra') ||
        blob.contains('vikend') ||
        blob.contains('víkend') ||
        blob.contains('dovolen') ||
        blob.contains('cest');
  }
}
