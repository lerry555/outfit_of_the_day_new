import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/data/event_dress_code.dart';
import 'package:outfitofTheDay/data/stylist_intent.dart';
import 'package:outfitofTheDay/utils/activity_archetype.dart';

void main() {
  group('ActivityArchetypeResolver — explicitná mapa', () {
    final cases = <String, ActivityArchetype>{
      'wedding': ActivityArchetype.formal,
      'funeral': ActivityArchetype.formal,
      'interview': ActivityArchetype.formal,
      'gala': ActivityArchetype.formal,
      'work': ActivityArchetype.business,
      'meeting': ActivityArchetype.business,
      'office': ActivityArchetype.business,
      'hike': ActivityArchetype.outdoor,
      'mushroom': ActivityArchetype.outdoor,
      'forest': ActivityArchetype.outdoor,
      'walk_nature': ActivityArchetype.outdoor,
      'barbecue': ActivityArchetype.casual,
      'city_walk': ActivityArchetype.casual,
      'free_time': ActivityArchetype.casual,
      'casual': ActivityArchetype.casual,
      'date': ActivityArchetype.date,
      'dinner': ActivityArchetype.date,
      'drink': ActivityArchetype.date,
      'cinema': ActivityArchetype.date,
      'gym': ActivityArchetype.sport,
      'run': ActivityArchetype.sport,
      'cycling': ActivityArchetype.sport,
    };

    cases.forEach((activityType, expected) {
      test('$activityType → ${expected.wireName}', () {
        final result = ActivityArchetypeResolver.resolve(
          activityType: activityType,
        );
        expect(result.archetype, expected);
        expect(result.source, ActivityArchetypeSource.explicitMap);
      });
    });

    test('normalizuje case a whitespace', () {
      final result = ActivityArchetypeResolver.resolve(
        activityType: '  WEDDING  ',
      );
      expect(result.archetype, ActivityArchetype.formal);
      expect(result.source, ActivityArchetypeSource.explicitMap);
    });
  });

  group('ActivityArchetypeResolver — fallback cez dress code', () {
    ActivityArchetypeResult resolveWith(EventDressCodeSpec spec) {
      return ActivityArchetypeResolver.resolve(
        activityType: 'nieco_nezname',
        dressCode: spec,
      );
    }

    test('vysoká formalita (>=7) → formal', () {
      final result = resolveWith(
        const EventDressCodeSpec(
          id: 'x',
          labelSk: 'x',
          formalityTarget: 8,
        ),
      );
      expect(result.archetype, ActivityArchetype.formal);
      expect(result.source, ActivityArchetypeSource.dressCode);
    });

    test('outdoor venue → outdoor', () {
      final result = resolveWith(
        const EventDressCodeSpec(
          id: 'x',
          labelSk: 'x',
          formalityTarget: 3,
          venue: EventVenueType.outdoor,
        ),
      );
      expect(result.archetype, ActivityArchetype.outdoor);
      expect(result.source, ActivityArchetypeSource.dressCode);
    });

    test('stredná formalita (>=5) indoor → business', () {
      final result = resolveWith(
        const EventDressCodeSpec(
          id: 'x',
          labelSk: 'x',
          formalityTarget: 5,
          venue: EventVenueType.indoorCasual,
        ),
      );
      expect(result.archetype, ActivityArchetype.business);
      expect(result.source, ActivityArchetypeSource.dressCode);
    });

    test('nízka formalita bez signálu → nespadne na dress code', () {
      final result = resolveWith(
        const EventDressCodeSpec(
          id: 'x',
          labelSk: 'x',
          formalityTarget: 2,
          venue: EventVenueType.indoorCasual,
        ),
      );
      expect(result.source, ActivityArchetypeSource.defaultCasual);
      expect(result.archetype, ActivityArchetype.casual);
    });

    test('vysoká formalita má prednosť pred outdoor', () {
      final result = resolveWith(
        const EventDressCodeSpec(
          id: 'x',
          labelSk: 'x',
          formalityTarget: 9,
          venue: EventVenueType.outdoor,
        ),
      );
      expect(result.archetype, ActivityArchetype.formal);
    });
  });

  group('ActivityArchetypeResolver — fallback cez impressions', () {
    ActivityArchetypeResult resolveWith(List<ImpressionTag> primary) {
      return ActivityArchetypeResolver.resolve(
        activityType: 'nieco_nezname',
        stylistIntent: StylistIntent(
          activityType: 'nieco_nezname',
          primaryImpressions: primary,
          impressionSummarySk: 'test',
        ),
      );
    }

    test('sportovy → sport', () {
      final result = resolveWith([ImpressionTag.sportovy]);
      expect(result.archetype, ActivityArchetype.sport);
      expect(result.source, ActivityArchetypeSource.impressions);
    });

    test('elegantny → formal', () {
      final result = resolveWith([ImpressionTag.elegantny]);
      expect(result.archetype, ActivityArchetype.formal);
    });

    test('prakticky/funkcny → outdoor', () {
      final result = resolveWith([ImpressionTag.prakticky]);
      expect(result.archetype, ActivityArchetype.outdoor);
    });

    test('profesionalny → business', () {
      final result = resolveWith([ImpressionTag.profesionalny]);
      expect(result.archetype, ActivityArchetype.business);
    });

    test('sympaticky → date', () {
      final result = resolveWith([ImpressionTag.sympaticky]);
      expect(result.archetype, ActivityArchetype.date);
    });

    test('pohodlny/uvolneny → casual', () {
      final result = resolveWith([ImpressionTag.pohodlny]);
      expect(result.archetype, ActivityArchetype.casual);
    });

    test('sportovy má prednosť pred pohodlny', () {
      final result = resolveWith([
        ImpressionTag.pohodlny,
        ImpressionTag.sportovy,
      ]);
      expect(result.archetype, ActivityArchetype.sport);
    });
  });

  group('ActivityArchetypeResolver — poradie fallbackov', () {
    test('explicitná mapa má prednosť pred dress code aj impressions', () {
      final result = ActivityArchetypeResolver.resolve(
        activityType: 'hike',
        dressCode: const EventDressCodeSpec(
          id: 'x',
          labelSk: 'x',
          formalityTarget: 9,
        ),
        stylistIntent: const StylistIntent(
          activityType: 'hike',
          primaryImpressions: [ImpressionTag.elegantny],
          impressionSummarySk: 'test',
        ),
      );
      expect(result.archetype, ActivityArchetype.outdoor);
      expect(result.source, ActivityArchetypeSource.explicitMap);
    });

    test('dress code má prednosť pred impressions', () {
      final result = ActivityArchetypeResolver.resolve(
        activityType: 'nieco_nezname',
        dressCode: const EventDressCodeSpec(
          id: 'x',
          labelSk: 'x',
          formalityTarget: 8,
        ),
        stylistIntent: const StylistIntent(
          activityType: 'nieco_nezname',
          primaryImpressions: [ImpressionTag.pohodlny],
          impressionSummarySk: 'test',
        ),
      );
      expect(result.archetype, ActivityArchetype.formal);
      expect(result.source, ActivityArchetypeSource.dressCode);
    });

    test('úplne neznáma aktivita bez signálov → casual', () {
      final result = ActivityArchetypeResolver.resolve(
        activityType: 'uplne_nova_aktivita_2077',
      );
      expect(result.archetype, ActivityArchetype.casual);
      expect(result.source, ActivityArchetypeSource.defaultCasual);
    });

    test('archetypeFor vráti len archetyp', () {
      expect(
        ActivityArchetypeResolver.archetypeFor(activityType: 'gym'),
        ActivityArchetype.sport,
      );
    });
  });
}
