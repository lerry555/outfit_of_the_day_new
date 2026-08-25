import '../data/event_dress_code.dart';
import '../data/stylist_intent.dart';

/// Hrubá skupina aktivít pre lacnú deterministickú vrstvu identity outfitu.
///
/// Filozofia: archetyp je len FALLBACK a lacná deterministická vrstva.
/// Dlhodobo má výber riadiť [ActivityTraits] (odvodené z AI/heuristiky), nie
/// hardcodovaný `activityType`. Preto tu zámerne NEmapujeme každú možnú
/// aktivitu — držíme malú explicitnú mapu bežných typov a zvyšok necháme
/// spadnúť do najbližšieho archetypu cez už existujúce signály (dress code,
/// impressions).
enum ActivityArchetype { formal, business, outdoor, casual, date, sport }

extension ActivityArchetypeWire on ActivityArchetype {
  String get wireName {
    switch (this) {
      case ActivityArchetype.formal:
        return 'formal';
      case ActivityArchetype.business:
        return 'business';
      case ActivityArchetype.outdoor:
        return 'outdoor';
      case ActivityArchetype.casual:
        return 'casual';
      case ActivityArchetype.date:
        return 'date';
      case ActivityArchetype.sport:
        return 'sport';
    }
  }
}

/// Zdroj, z ktorého sa archetyp odvodil — pre logy a ladenie fallbacku.
enum ActivityArchetypeSource { explicitMap, dressCode, impressions, defaultCasual }

extension ActivityArchetypeSourceWire on ActivityArchetypeSource {
  String get wireName {
    switch (this) {
      case ActivityArchetypeSource.explicitMap:
        return 'explicit_map';
      case ActivityArchetypeSource.dressCode:
        return 'dress_code';
      case ActivityArchetypeSource.impressions:
        return 'impressions';
      case ActivityArchetypeSource.defaultCasual:
        return 'default_casual';
    }
  }
}

/// Výsledok rozlíšenia archetypu — archetyp + odkiaľ pochádza.
class ActivityArchetypeResult {
  const ActivityArchetypeResult({
    required this.archetype,
    required this.source,
  });

  final ActivityArchetype archetype;
  final ActivityArchetypeSource source;
}

/// Rozlíšenie [ActivityArchetype] pre daný `activityType`.
///
/// Poradie (bez veľkého hardcodu):
/// 1. malá explicitná mapa bežných typov,
/// 2. dress code (formalita/venue), ak je dostupný,
/// 3. impressions z [StylistIntent], ak sú dostupné,
/// 4. default `casual`.
abstract final class ActivityArchetypeResolver {
  /// Malá, zámerne NEvyčerpávajúca mapa. Slúži len na to, aby najbežnejšie
  /// aktivity mali stabilný archetyp bez behu fallbacku. Nové aktivity
  /// nepridávame sem automaticky — nech spadnú cez fallback.
  static const Map<String, ActivityArchetype> _explicitMap = {
    // formal
    'wedding': ActivityArchetype.formal,
    'funeral': ActivityArchetype.formal,
    'interview': ActivityArchetype.formal,
    'gala': ActivityArchetype.formal,

    // business
    'work': ActivityArchetype.business,
    'meeting': ActivityArchetype.business,
    'office': ActivityArchetype.business,

    // outdoor
    'hike': ActivityArchetype.outdoor,
    'mushroom': ActivityArchetype.outdoor,
    'forest': ActivityArchetype.outdoor,
    'walk_nature': ActivityArchetype.outdoor,

    // casual
    'barbecue': ActivityArchetype.casual,
    'city_walk': ActivityArchetype.casual,
    'free_time': ActivityArchetype.casual,
    'casual': ActivityArchetype.casual,

    // date
    'date': ActivityArchetype.date,
    'dinner': ActivityArchetype.date,
    'drink': ActivityArchetype.date,
    'cinema': ActivityArchetype.date,

    // sport
    'gym': ActivityArchetype.sport,
    'run': ActivityArchetype.sport,
    'cycling': ActivityArchetype.sport,
  };

  static ActivityArchetypeResult resolve({
    required String activityType,
    EventDressCodeSpec? dressCode,
    StylistIntent? stylistIntent,
  }) {
    final normalized = activityType.trim().toLowerCase();

    final explicit = _explicitMap[normalized];
    if (explicit != null) {
      return ActivityArchetypeResult(
        archetype: explicit,
        source: ActivityArchetypeSource.explicitMap,
      );
    }

    final fromDressCode = _fromDressCode(dressCode);
    if (fromDressCode != null) {
      return ActivityArchetypeResult(
        archetype: fromDressCode,
        source: ActivityArchetypeSource.dressCode,
      );
    }

    final fromImpressions = _fromImpressions(stylistIntent);
    if (fromImpressions != null) {
      return ActivityArchetypeResult(
        archetype: fromImpressions,
        source: ActivityArchetypeSource.impressions,
      );
    }

    return const ActivityArchetypeResult(
      archetype: ActivityArchetype.casual,
      source: ActivityArchetypeSource.defaultCasual,
    );
  }

  /// Skrátený prístup, keď nepotrebuješ zdroj.
  static ActivityArchetype archetypeFor({
    required String activityType,
    EventDressCodeSpec? dressCode,
    StylistIntent? stylistIntent,
  }) {
    return resolve(
      activityType: activityType,
      dressCode: dressCode,
      stylistIntent: stylistIntent,
    ).archetype;
  }

  static ActivityArchetype? _fromDressCode(EventDressCodeSpec? dressCode) {
    if (dressCode == null) return null;
    if (dressCode.formalityTarget >= 7) return ActivityArchetype.formal;
    if (dressCode.venue == EventVenueType.outdoor) {
      return ActivityArchetype.outdoor;
    }
    if (dressCode.formalityTarget >= 5) return ActivityArchetype.business;
    return null;
  }

  static ActivityArchetype? _fromImpressions(StylistIntent? stylistIntent) {
    if (stylistIntent == null) return null;
    final impressions = <ImpressionTag>{
      ...stylistIntent.primaryImpressions,
      ...stylistIntent.secondaryImpressions,
    };
    if (impressions.isEmpty) return null;

    // Poradie kontrol = priorita (najšpecifickejší dojem vyhráva).
    if (impressions.contains(ImpressionTag.sportovy)) {
      return ActivityArchetype.sport;
    }
    if (impressions.contains(ImpressionTag.elegantny) ||
        impressions.contains(ImpressionTag.reprezentativny)) {
      return ActivityArchetype.formal;
    }
    if (impressions.contains(ImpressionTag.prakticky) ||
        impressions.contains(ImpressionTag.funkcny)) {
      return ActivityArchetype.outdoor;
    }
    if (impressions.contains(ImpressionTag.profesionalny)) {
      return ActivityArchetype.business;
    }
    if (impressions.contains(ImpressionTag.sympaticky)) {
      return ActivityArchetype.date;
    }
    if (impressions.contains(ImpressionTag.pohodlny) ||
        impressions.contains(ImpressionTag.uvolneny) ||
        impressions.contains(ImpressionTag.neformalny) ||
        impressions.contains(ImpressionTag.prirodzeny)) {
      return ActivityArchetype.casual;
    }
    return null;
  }
}
