/// Uzavretý slovník dojmov — čo má outfit vyjadriť, nie technické constraints.
enum ImpressionTag {
  elegantny,
  reprezentativny,
  decentny,
  nenapadny,
  profesionalny,
  upraveny,
  sebavedomy,
  prakticky,
  funkcny,
  pohodlny,
  uvolneny,
  prirodzeny,
  sympaticky,
  sportovy,
  neformalny,
}

extension ImpressionTagWire on ImpressionTag {
  String get wireName => name;
}

/// Špecifikácia požadovaného dojmu outfitu — vrstva nad technickým OutfitIntent.
class StylistIntent {
  final String activityType;
  final List<ImpressionTag> primaryImpressions;
  final List<ImpressionTag> secondaryImpressions;
  final List<ImpressionTag> avoidImpressions;
  final String impressionSummarySk;

  const StylistIntent({
    required this.activityType,
    required this.primaryImpressions,
    this.secondaryImpressions = const [],
    this.avoidImpressions = const [],
    required this.impressionSummarySk,
  });

  String get _avoidWire =>
      avoidImpressions.map((t) => t.wireName).join(',');

  /// Log riadok pre STYLIST CHAT stylist_intent.
  String toLogLine() {
    return 'STYLIST CHAT stylist_intent { '
        'activityType=$activityType, '
        'primaryImpressions=${primaryImpressions.map((t) => t.wireName).join(",")}, '
        'secondaryImpressions=${secondaryImpressions.map((t) => t.wireName).join(",")}, '
        'avoidImpressions=$_avoidWire, '
        'impressionSummarySk=$impressionSummarySk '
        '}';
  }
}

class StylistIntentProfile {
  final String activityType;
  final List<ImpressionTag> primary;
  final List<ImpressionTag> secondary;
  final List<ImpressionTag> avoid;
  final String impressionSummarySk;

  const StylistIntentProfile({
    required this.activityType,
    required this.primary,
    this.secondary = const [],
    this.avoid = const [],
    required this.impressionSummarySk,
  });

  StylistIntent toIntent() {
    return StylistIntent(
      activityType: activityType,
      primaryImpressions: List<ImpressionTag>.from(primary),
      secondaryImpressions: List<ImpressionTag>.from(secondary),
      avoidImpressions: List<ImpressionTag>.from(avoid),
      impressionSummarySk: impressionSummarySk,
    );
  }
}

/// Katalóg dojmov podľa typu aktivity — jeden zdroj pravdy pre M1a.
abstract final class StylistIntentCatalog {
  static const StylistIntentProfile wedding = StylistIntentProfile(
    activityType: 'wedding',
    primary: [ImpressionTag.elegantny, ImpressionTag.reprezentativny],
    avoid: [
      ImpressionTag.sportovy,
      ImpressionTag.uvolneny,
      ImpressionTag.neformalny,
    ],
    impressionSummarySk:
        'chcem pôsobiť elegantne a reprezentatívne',
  );

  static const StylistIntentProfile funeral = StylistIntentProfile(
    activityType: 'funeral',
    primary: [ImpressionTag.decentny, ImpressionTag.nenapadny],
    avoid: [
      ImpressionTag.sportovy,
      ImpressionTag.uvolneny,
      ImpressionTag.elegantny,
    ],
    impressionSummarySk: 'chcem pôsobiť decentne a nenápadne',
  );

  static const StylistIntentProfile interview = StylistIntentProfile(
    activityType: 'interview',
    primary: [
      ImpressionTag.profesionalny,
      ImpressionTag.upraveny,
      ImpressionTag.sebavedomy,
    ],
    avoid: [ImpressionTag.uvolneny, ImpressionTag.sportovy, ImpressionTag.neformalny],
    impressionSummarySk:
        'chcem pôsobiť profesionálne, upravene a sebavedomo',
  );

  static const StylistIntentProfile work = StylistIntentProfile(
    activityType: 'work',
    primary: [ImpressionTag.profesionalny, ImpressionTag.upraveny],
    avoid: [ImpressionTag.sportovy, ImpressionTag.neformalny],
    impressionSummarySk: 'chcem pôsobiť profesionálne a upravene',
  );

  static const StylistIntentProfile hike = StylistIntentProfile(
    activityType: 'hike',
    primary: [
      ImpressionTag.prakticky,
      ImpressionTag.funkcny,
      ImpressionTag.pohodlny,
    ],
    avoid: [
      ImpressionTag.elegantny,
      ImpressionTag.reprezentativny,
      ImpressionTag.upraveny,
    ],
    impressionSummarySk: 'chcem byť praktický, funkčný a pohodlný',
  );

  static const StylistIntentProfile mushroom = StylistIntentProfile(
    activityType: 'mushroom',
    primary: [
      ImpressionTag.prakticky,
      ImpressionTag.funkcny,
      ImpressionTag.nenapadny,
    ],
    avoid: [
      ImpressionTag.elegantny,
      ImpressionTag.reprezentativny,
    ],
    impressionSummarySk: 'chcem byť praktický, funkčný a nenápadný',
  );

  static const StylistIntentProfile barbecue = StylistIntentProfile(
    activityType: 'barbecue',
    primary: [
      ImpressionTag.pohodlny,
      ImpressionTag.uvolneny,
      ImpressionTag.prirodzeny,
    ],
    avoid: [
      ImpressionTag.reprezentativny,
      ImpressionTag.upraveny,
      ImpressionTag.elegantny,
    ],
    impressionSummarySk: 'chcem byť pohodlný, uvoľnený a prirodzený',
  );

  static const StylistIntentProfile date = StylistIntentProfile(
    activityType: 'date',
    primary: [
      ImpressionTag.upraveny,
      ImpressionTag.sympaticky,
      ImpressionTag.uvolneny,
    ],
    avoid: [
      ImpressionTag.sportovy,
      ImpressionTag.reprezentativny,
    ],
    impressionSummarySk:
        'chcem pôsobiť upravene, sympaticky a uvoľnene',
  );

  static const StylistIntentProfile casual = StylistIntentProfile(
    activityType: 'casual',
    primary: [ImpressionTag.pohodlny, ImpressionTag.prirodzeny],
    avoid: [ImpressionTag.reprezentativny],
    impressionSummarySk: 'chcem byť pohodlný a prirodzený',
  );

  // Kino a večera zdieľajú casual preferencie (rovnaký výber outfitu), líšia sa
  // len [activityType] — aby ich opinion/identity vedeli rozlíšiť ako
  // „neat casual / smart casual" a nie outdoor.
  static const StylistIntentProfile cinema = StylistIntentProfile(
    activityType: 'cinema',
    primary: [ImpressionTag.pohodlny, ImpressionTag.prirodzeny],
    avoid: [ImpressionTag.reprezentativny],
    impressionSummarySk: 'chcem byť pohodlný a prirodzený',
  );

  static const StylistIntentProfile dinner = StylistIntentProfile(
    activityType: 'dinner',
    primary: [ImpressionTag.pohodlny, ImpressionTag.prirodzeny],
    avoid: [ImpressionTag.reprezentativny],
    impressionSummarySk: 'chcem byť pohodlný a prirodzený',
  );

  static const Map<String, StylistIntentProfile> byActivityType = {
    'wedding': wedding,
    'funeral': funeral,
    'interview': interview,
    'work': work,
    'hike': hike,
    'mushroom': mushroom,
    'barbecue': barbecue,
    'date': date,
    'cinema': cinema,
    'dinner': dinner,
    'casual': casual,
  };

  static StylistIntent intentFor(String activityType) {
    return (byActivityType[activityType] ?? casual).toIntent();
  }
}
