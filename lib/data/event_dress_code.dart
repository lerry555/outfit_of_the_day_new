/// Katalóg dress-code profilov pre udalosti — jeden zdroj pravdy namiesto if/else po celom kóde.
///
/// Formálnosť + typ miesta + teplota rozhodujú o outfite. Konkrétny interpret,
/// značka ani pomenované miesto nikdy samy neurčujú venue či formálnosť.
enum EventVenueType {
  outdoor,
  indoorCasual,
  indoorFormal,
  any,
}

class EventDressCodeSpec {
  final String id;
  final String labelSk;
  final int formalityTarget;
  final EventVenueType venue;
  final bool preferJeans;

  const EventDressCodeSpec({
    required this.id,
    required this.labelSk,
    required this.formalityTarget,
    this.venue = EventVenueType.any,
    this.preferJeans = false,
  });

  static const EventDressCodeSpec casual = EventDressCodeSpec(
    id: 'casual',
    labelSk: 'voľný čas',
    formalityTarget: 2,
    venue: EventVenueType.any,
  );

  bool allowShorts(int tempC) {
    if (formalityTarget >= 7) return false;
    if (formalityTarget >= 5 && venue != EventVenueType.outdoor) return false;
    if (venue == EventVenueType.outdoor && tempC >= 17) return true;
    if (formalityTarget <= 3 && tempC >= 17) return true;
    return formalityTarget <= 4 && tempC >= 26;
  }

  bool get isElevated => formalityTarget >= 5;

  String explainPhrase() {
    if (formalityTarget >= 7) {
      return 'na túto príležitosť je vhodnejší elegantnejší look';
    }
    if (formalityTarget >= 5) {
      return 'na toto je smart-casual — radšej rifle alebo nohavice';
    }
    if (venue == EventVenueType.outdoor) {
      return 'vonku pri teple môžu byť aj šortky';
    }
    return 'pohodlný casual';
  }
}

extension EventVenueTypeWire on EventVenueType {
  String get wireName => switch (this) {
    EventVenueType.outdoor => 'outdoor',
    EventVenueType.indoorCasual => 'indoor_casual',
    EventVenueType.indoorFormal => 'indoor_formal',
    EventVenueType.any => 'any',
  };
}

class EventDressCodeArchetype {
  final String id;
  final List<String> keywords;
  final EventDressCodeSpec spec;
  final bool requiresVenueClarification;

  const EventDressCodeArchetype({
    required this.id,
    required this.keywords,
    required this.spec,
    this.requiresVenueClarification = false,
  });
}

abstract final class EventDressCodeCatalog {
  static const String concertClarificationMessage =
      'Je to vonku (festival, štadión, amfiteáter), alebo v sále či klube? '
      'Typ priestoru môže zmeniť vrstvy aj formálnosť.';

  static const List<EventDressCodeArchetype> archetypes = [
    EventDressCodeArchetype(
      id: 'philharmonic',
      keywords: [
        'filharmon',
        'opera',
        'balet',
        'galavečer',
        'gala vecer',
        'gala večer',
      ],
      spec: EventDressCodeSpec(
        id: 'philharmonic',
        labelSk: 'filharmónia / gala',
        formalityTarget: 8,
        venue: EventVenueType.indoorFormal,
      ),
    ),
    EventDressCodeArchetype(
      id: 'funeral',
      keywords: [
        'pohreb',
        'pohrebu',
        'pohrebe',
        'pohrebom',
        'posledná rozlúčka',
        'posledna rozlucka',
        'smútočn',
        'smutocn',
      ],
      spec: EventDressCodeSpec(
        id: 'funeral',
        labelSk: 'pohreb',
        formalityTarget: 8,
        venue: EventVenueType.indoorFormal,
      ),
    ),
    EventDressCodeArchetype(
      id: 'wedding',
      keywords: ['svadb', 'svadbu', 'svadbe', 'svadbou', 'svadobn'],
      spec: EventDressCodeSpec(
        id: 'wedding',
        labelSk: 'svadba',
        formalityTarget: 8,
        venue: EventVenueType.indoorFormal,
      ),
    ),
    EventDressCodeArchetype(
      id: 'interview',
      keywords: ['pohovor', 'pohovore', 'pohovoru', 'pohovorom', 'job interview', 'interview'],
      spec: EventDressCodeSpec(
        id: 'interview',
        labelSk: 'pohovor',
        formalityTarget: 7,
        venue: EventVenueType.indoorFormal,
      ),
    ),
    EventDressCodeArchetype(
      id: 'work',
      keywords: [
        'práca',
        'prace',
        'práce',
        'pracov',
        'pracovn',
        'robot',
        'zamestnan',
        'kancelár',
        'kancelar',
        'do kancel',
      ],
      spec: EventDressCodeSpec(
        id: 'work',
        labelSk: 'práca (business casual)',
        formalityTarget: 5,
        venue: EventVenueType.indoorCasual,
        preferJeans: true,
      ),
    ),
    EventDressCodeArchetype(
      id: 'celebration',
      keywords: [
        'oslav',
        'oslavy',
        'oslave',
        'osláv',
        'promóci',
        'promoci',
        'stužkov',
        'stuzkov',
        'banket',
      ],
      spec: EventDressCodeSpec(
        id: 'celebration',
        labelSk: 'oslava',
        formalityTarget: 6,
        venue: EventVenueType.indoorCasual,
        preferJeans: true,
      ),
    ),
    EventDressCodeArchetype(
      id: 'outdoor_concert',
      keywords: [
        'koncert vonku',
        'vonkajs koncert',
        'vonkajší koncert',
        'festival',
        'stadion',
        'štadión',
        'open air',
        'open-air',
        'amfik',
        'amfite',
        'amfiteáter',
        'amfiteater',
      ],
      spec: EventDressCodeSpec(
        id: 'outdoor_concert',
        labelSk: 'koncert vonku',
        formalityTarget: 3,
        venue: EventVenueType.outdoor,
      ),
    ),
    EventDressCodeArchetype(
      id: 'theater',
      keywords: ['divadl', 'predstaven', 'musical', 'muzikal', 'muzikál'],
      spec: EventDressCodeSpec(
        id: 'theater',
        labelSk: 'divadlo',
        formalityTarget: 6,
        venue: EventVenueType.indoorCasual,
        preferJeans: true,
      ),
    ),
    EventDressCodeArchetype(
      id: 'cinema',
      keywords: ['kino', 'cinema', 'premiéra', 'premiera'],
      spec: EventDressCodeSpec(
        id: 'cinema',
        labelSk: 'kino',
        formalityTarget: 4,
        venue: EventVenueType.indoorCasual,
      ),
    ),
    EventDressCodeArchetype(
      id: 'restaurant_evening',
      keywords: [
        'reštaur',
        'restaur',
        'reštauráci',
        'restauraci',
        'luxus',
        'večeru v',
        'veceru v',
      ],
      spec: EventDressCodeSpec(
        id: 'restaurant_evening',
        labelSk: 'večera v reštaurácii',
        formalityTarget: 6,
        venue: EventVenueType.indoorCasual,
        preferJeans: true,
      ),
    ),
    EventDressCodeArchetype(
      id: 'ice_cream',
      keywords: ['zmrzlin', 'zmrzk'],
      spec: EventDressCodeSpec(
        id: 'ice_cream',
        labelSk: 'zmrzlina',
        formalityTarget: 2,
        venue: EventVenueType.outdoor,
      ),
    ),
    EventDressCodeArchetype(
      id: 'park_walk',
      keywords: ['park', 'prechádz', 'prechadz', 'pláž', 'plaz', 'kúpal', 'kupal'],
      spec: EventDressCodeSpec.casual,
    ),
    EventDressCodeArchetype(
      id: 'hike',
      keywords: ['hory', 'hor', 'turist', 'trek', 'hiking', 'do hory', 'v hor'],
      spec: EventDressCodeSpec(
        id: 'hike',
        labelSk: 'turistika / hory',
        formalityTarget: 2,
        venue: EventVenueType.outdoor,
      ),
    ),
    EventDressCodeArchetype(
      id: 'mushroom',
      keywords: ['hubovan', 'huby', 'hrib', 'hriby', 'hribov'],
      spec: EventDressCodeSpec(
        id: 'mushroom',
        labelSk: 'huby / les',
        formalityTarget: 2,
        venue: EventVenueType.outdoor,
      ),
    ),
    EventDressCodeArchetype(
      id: 'barbecue',
      keywords: ['grilov', 'grill', 'bbq', 'barbecue', 'opekac', 'opekač'],
      spec: EventDressCodeSpec(
        id: 'barbecue',
        labelSk: 'grilovanie',
        formalityTarget: 2,
        venue: EventVenueType.outdoor,
      ),
    ),
    EventDressCodeArchetype(
      id: 'concert_ambiguous',
      keywords: ['koncert'],
      spec: EventDressCodeSpec(
        id: 'concert_ambiguous',
        labelSk: 'koncert',
        formalityTarget: 5,
        venue: EventVenueType.indoorCasual,
        preferJeans: true,
      ),
      requiresVenueClarification: true,
    ),
  ];
}
