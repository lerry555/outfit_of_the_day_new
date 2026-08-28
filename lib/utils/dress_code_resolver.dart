import '../data/event_dress_code.dart';

/// Resolves dress-code archetypes from generic event meaning.
/// Named performers, partners or locations never determine venue/formality.
class DressCodeResolver {
  const DressCodeResolver._();

  static EventDressCodeSpec? resolveGroundedActivity(String? value) {
    final activity = (value ?? '').trim().toLowerCase();
    if (activity.isEmpty) return null;
    if (activity == 'city_walk' || activity == 'mesto' || activity == 'zoo') {
      return EventDressCodeSpec.casual;
    }
    if (activity.contains('hory') ||
        activity.contains('turist') ||
        activity == 'hike' ||
        activity == 'hiking') {
      return EventDressCodeCatalog.archetypes
          .firstWhere((item) => item.id == 'hike')
          .spec;
    }
    if (activity.contains('les') ||
        activity.contains('prírod') ||
        activity.contains('prirod')) {
      return const EventDressCodeSpec(
        id: 'nature_walk',
        labelSk: 'prechádzka v prírode',
        formalityTarget: 2,
        venue: EventVenueType.outdoor,
      );
    }
    if (activity == 'dinner') {
      return EventDressCodeCatalog.archetypes
          .firstWhere((item) => item.id == 'restaurant_evening')
          .spec;
    }
    if (activity == 'work') {
      return EventDressCodeCatalog.archetypes
          .firstWhere((item) => item.id == 'work')
          .spec;
    }
    return null;
  }

  static EventDressCodeSpec resolve({
    String? occasion,
    String? conversationText,
    Map<String, dynamic>? aiDressCode,
    int? tempC,
  }) {
    final fromAi = _fromAiPayload(aiDressCode);
    if (fromAi != null) return fromAi;

    final blob = '${occasion ?? ''} ${conversationText ?? ''}'.toLowerCase();
    if (blob.trim().isEmpty) return EventDressCodeSpec.casual;

    final archetype = _matchArchetype(blob);
    if (archetype != null) return archetype.spec;
    if (_matchesRestaurantEvening(blob)) {
      return EventDressCodeCatalog.archetypes
          .firstWhere((a) => a.id == 'restaurant_evening')
          .spec;
    }
    if (_matchesNiceDinner(blob)) {
      return const EventDressCodeSpec(
        id: 'nice_dinner',
        labelSk: 'pekná večera',
        formalityTarget: 6,
        venue: EventVenueType.indoorCasual,
        preferJeans: true,
      );
    }
    return EventDressCodeSpec.casual;
  }

  static bool needsVenueClarification(String? conversationText) {
    final blob = (conversationText ?? '').toLowerCase();
    if (!blob.contains('koncert')) return false;
    return !_hasConcertVenueHint(blob);
  }

  static bool needsDateActivityClarification(String? conversationText) {
    final blob = (conversationText ?? '').toLowerCase();
    if (!blob.contains('rande') && !blob.contains('date')) return false;
    return !_hasClearDateActivity(blob);
  }

  static String? styleHintFor(String? conversationText) {
    final spec = resolve(conversationText: conversationText);
    if (spec.id == 'casual') return null;
    final label = spec.labelSk;
    return spec.isElevated
        ? 'Na $label by som šiel ${spec.explainPhrase()}.'
        : 'Na $label ${spec.explainPhrase()}.';
  }

  static EventDressCodeArchetype? ambiguousArchetype(String? conversationText) {
    final blob = (conversationText ?? '').toLowerCase();
    for (final archetype in EventDressCodeCatalog.archetypes) {
      if (!archetype.requiresVenueClarification) continue;
      if (archetype.keywords.any(blob.contains)) return archetype;
    }
    return null;
  }

  static EventDressCodeSpec? _fromAiPayload(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return null;
    final target = _parseInt(raw['formalityTarget'] ?? raw['formality']);
    if (target == null || target < 1 || target > 10) return null;
    final venue = _parseVenue(raw['venueType'] ?? raw['venue']);
    final id = (raw['id'] ?? 'ai').toString();
    final label = (raw['labelSk'] ?? raw['label'] ?? 'udalosť').toString();
    return EventDressCodeSpec(
      id: id,
      labelSk: label,
      formalityTarget: target,
      venue: venue,
      preferJeans: target >= 5 && venue != EventVenueType.outdoor,
    );
  }

  static EventDressCodeArchetype? _matchArchetype(String blob) {
    EventDressCodeArchetype? ambiguous;
    for (final archetype in EventDressCodeCatalog.archetypes) {
      if (!archetype.keywords.any(blob.contains)) continue;
      if (archetype.requiresVenueClarification) {
        ambiguous ??= archetype;
        continue;
      }
      return archetype;
    }
    return ambiguous;
  }

  static bool _hasConcertVenueHint(String blob) => _matchesAny(blob, [
    'vonku',
    'vonkaj',
    'festival',
    'stadion',
    'štadión',
    'amfik',
    'amfite',
    'amfiteáter',
    'amfiteater',
    'open air',
    'open-air',
    'filharmon',
    'sála',
    'sale',
    'v sale',
    'v sále',
    'klub',
    'hala',
    'hall',
  ]);

  static bool _hasClearDateActivity(String blob) {
    if (RegExp(r'(?:o|okolo)\s*\d', caseSensitive: false).hasMatch(blob)) {
      return true;
    }
    return _matchesAny(blob, [
      'zmrzlin',
      'zmrzk',
      'reštaur',
      'restaur',
      'luxus',
      'večer',
      'vecer',
      'kaviar',
      'prechádz',
      'prechadz',
      'kino',
      'cinema',
      'drink',
      'bar ',
      'park',
      'pláž',
      'plaz',
    ]);
  }

  static bool _matchesRestaurantEvening(String blob) =>
      _matchesAny(blob, ['reštaur', 'restaur', 'reštauráci', 'restauraci', 'luxus']);

  static bool _matchesNiceDinner(String blob) {
    final dinner = _matchesAny(blob, ['večer', 'vecer', 'večeru', 'veceru', 'dinner']);
    final nice = _matchesAny(blob, [
      'peknej',
      'peknú',
      'peknu',
      'pekná',
      'pekna',
      'elegant',
      'formál',
      'formal',
      'romant',
    ]);
    return dinner && nice;
  }

  static EventVenueType _parseVenue(Object? raw) {
    final value = (raw ?? '').toString().toLowerCase().trim();
    if (value.contains('outdoor') || value.contains('vonku')) {
      return EventVenueType.outdoor;
    }
    if (value.contains('formal') ||
        value.contains('gala') ||
        value.contains('filharmon')) {
      return EventVenueType.indoorFormal;
    }
    if (value.contains('indoor') ||
        value.contains('vnútri') ||
        value.contains('vnutri')) {
      return EventVenueType.indoorCasual;
    }
    return EventVenueType.any;
  }

  static int? _parseInt(Object? raw) =>
      raw == null ? null : int.tryParse(raw.toString());

  static bool _matchesAny(String blob, List<String> needles) =>
      needles.any(blob.contains);
}
