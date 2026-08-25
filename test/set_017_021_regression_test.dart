import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_chat_service.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_set_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_adapters.dart';
import 'package:outfitofTheDay/utils/stylist_destination_parser.dart';
import 'package:outfitofTheDay/data/parsed_destination.dart';
import 'package:outfitofTheDay/utils/stylist_wardrobe_context_need.dart';
import 'package:outfitofTheDay/utils/home_manual_group_match.dart';
import 'package:outfitofTheDay/utils/layer_harmony_guard.dart';
import 'package:outfitofTheDay/utils/stylist_layer_filter.dart';

void main() {
  group('SET-017 destination noise', () {
    test('do satnika / košeľa are not travel destinations', () {
      for (final text in [
        'Pozri do satnika. Navrhni outfit okolo bielej klasickej koselie.',
        'Navrhni outfit okolo bielej klasickej košele.',
        'Čo dať k tej košeli z šatníka?',
      ]) {
        final p = StylistDestinationParser.parseDestination(text);
        expect(p.hasTravelDestination, isFalse, reason: text);
        expect(p.type, DestinationType.none, reason: text);
      }
    });

    test('real destinations still parse', () {
      final washington = StylistDestinationParser.parseDestination(
        'Idem do Washingtonu, potrebujem outfit.',
      );
      expect(washington.hasTravelDestination, isTrue);
      expect(washington.weatherCity, isNotNull);

      final zoo = StylistDestinationParser.parseDestination(
        'Zajtra idem do ZOO, potrebujem outfit.',
      );
      expect(zoo.hasTravelDestination, isTrue);
    });
  });

  group('SET-018 Timestamp callable payload', () {
    test('nested Timestamp and DateTime become JSON-safe', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1700000000000);
      final dt = DateTime.utc(2026, 8, 13, 12);
      final out = StylistChatService.jsonSafeMapForCallable({
        'occasionContext': {
          'items': [
            {
              'display': {
                'createdAt': ts,
                'name': 'Biela klasická košeľa',
              },
            },
          ],
        },
        'clientNow': dt,
      });
      final item =
          (out['occasionContext'] as Map)['items'] as List;
      final display = (item.first as Map)['display'] as Map;
      expect(display['createdAt'], 1700000000000);
      expect(display['name'], 'Biela klasická košeľa');
      expect(out['clientNow'], '2026-08-13T12:00:00.000Z');
      expect(out, isA<Map<String, dynamic>>());
    });

    test('final review callable sanitizes Timestamp payloads', () {
      final src = File(
        'lib/Services/home_stylist_final_review_service.dart',
      ).readAsStringSync();
      expect(src.contains('jsonSafeMapForCallable'), isTrue);
    });
  });

  group('SET-019 Home Košele swap category', () {
    test('dress shirts match Košele and T-shirts do not', () {
      expect(
        homeManualGroupMatches(
          blob: homeManualHeroBlob({
            'name': 'Biela klasická košeľa',
            'canonicalType': 'dress_shirt',
            'category': 'Košele',
          }),
          group: 'shirt',
        ),
        isTrue,
      );
      expect(
        homeManualGroupMatches(
          blob: homeManualHeroBlob({
            'name': 'Bordové tričko s krátkym rukávom',
            'canonicalType': 't-shirt',
            'category': 'Tričká',
          }),
          group: 'shirt',
        ),
        isFalse,
      );
      expect(
        homeManualGroupMatches(
          blob: homeManualHeroBlob({
            'name': 'Čierne tielko',
            'canonicalType': 'tank_top',
            'category': 'Tielka',
          }),
          group: 'shirt',
        ),
        isFalse,
      );
    });

    test('home swap options expose always-visible Košele chips', () {
      final src = File('lib/screens/home_screen.dart').readAsStringSync();
      final sheet = File(
        'lib/screens/home_screen_edit_widgets.dart',
      ).readAsStringSync();
      expect(src.contains("_ManualCategoryOption(id: 'shirt', label: 'Košele')"),
          isTrue);
      expect(src.contains('canonicalType'), isTrue);
      expect(sheet.contains('Always visible'), isTrue);
      expect(sheet.contains('FilterChip'), isFalse);
      expect(sheet.contains('showCategoryPicker'), isFalse);
      expect(sheet.contains('CustomScrollView'), isTrue);
      expect(src.contains('_rankHomeSwapCandidatesByV2Score'), isTrue);
      expect(src.contains('[HOME_SET_SIGNAL]'), isTrue);
      expect(src.contains('V2FlexibleOutfitScorer.score'), isTrue);
      expect(
        src.contains('layerHarmonyExcludedOuterIdsForRegeneration'),
        isTrue,
      );
      expect(src.contains('outerwear_layer_harmony'), isTrue);
      expect(
        src.contains('draft.toComposition().completeness'),
        isTrue,
      );
    });

    test('edit mode exposes empty outerwear slot without persisting it', () {
      final grid = File(
        'lib/screens/home_screen_hero_grid_widgets.dart',
      ).readAsStringSync();
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(grid.contains('_heroEditDisplayItems'), isTrue);
      expect(grid.contains("label: 'Pridať vrstvu'"), isTrue);
      expect(
        File('lib/screens/home_screen_hero_image_widgets.dart')
            .readAsStringSync()
            .contains('ootd_edit_empty_outerwear'),
        isTrue,
      );
      expect(grid.contains('_HeroWearType.outerwear'), isTrue);
      expect(home.contains('if (_isEmptyHeroEditSlot(item)) return;'), isTrue);
      expect(
        home.contains(
          '[HOME_PRELOAD] ensure_today_only started',
        ),
        isTrue,
      );
      expect(
        home.contains('[HOME_PRELOAD] tomorrow_deferred_until_zajtra'),
        isTrue,
      );
      expect(home.contains('_deferTomorrowDailyOutfitEnsure'), isFalse);
      expect(
        home.contains(
          "[HOME_DAY] on_demand_ensure day=\${index == 1 ? 'tomorrow' : 'today'}",
        ),
        isTrue,
      );
    });

    test('warm weather excludes winter outerwear from Home swap pool', () {
      final excluded = layerHarmonyExcludedOuterIdsForRegeneration(
        wardrobe: const [
          {
            'id': 'H9mj2D4fgJxFWlOLLXeQ',
            'name': 'Čierna zimná bunda',
            'canonicalType': 'winter_jacket',
            'subCategory': 'bunda_zimna',
            'warmth': 8,
            'layerRole': 'outer_layer',
          },
          {
            'id': '9ajGS1WO9jtRvCXKScLF',
            'name': 'Čierna rifľová bunda',
            'canonicalType': 'denim_jacket',
            'subCategory': 'riflova_bunda',
            'warmth': 4,
            'layerRole': 'outer_layer',
          },
        ],
        tempC: 26,
      );
      expect(excluded, contains('H9mj2D4fgJxFWlOLLXeQ'));
      expect(excluded, isNot(contains('9ajGS1WO9jtRvCXKScLF')));
    });

    test('V2 warmth keeps denim jacket in warm-weather outerwear pool', () {
      expect(
        StylistLayerFilter.inferWarmthLevel(const {
          'canonicalType': 'denim_jacket',
          'subCategoryKey': 'bunda_riflova',
          'layerRole': 'outer_layer',
          'warmth': 5,
        }),
        5,
      );
      final excluded = layerHarmonyExcludedOuterIdsForRegeneration(
        wardrobe: const [
          {
            'id': 'H9mj2D4fgJxFWlOLLXeQ',
            'name': 'Čierna zimná bunda',
            'canonicalType': 'winter_jacket',
            'subCategoryKey': 'bunda_zimna',
            'warmth': 7,
            'layerRole': 'outer_layer',
          },
          {
            'id': 'UDIPnt3X77T5vkCpRiXI',
            'name': 'Olivová zimná bunda',
            'canonicalType': 'winter_jacket',
            'subCategoryKey': 'bunda_zimna',
            'warmth': 7,
            'layerRole': 'outer_layer',
          },
          {
            'id': '9ajGS1WO9jtRvCXKScLF',
            'name': 'Čierna rifľová bunda',
            'canonicalType': 'denim_jacket',
            'subCategoryKey': 'bunda_riflova',
            'warmth': 5,
            'layerRole': 'outer_layer',
          },
          {
            'id': 't1Ed6qZMKdMKUyBeRMQk',
            'name': 'Biela tréningová bunda',
            'canonicalType': 'track_jacket',
            'warmth': 5,
            'layerRole': 'outer_layer',
          },
        ],
        tempC: 24,
      );
      expect(excluded, containsAll(['H9mj2D4fgJxFWlOLLXeQ', 'UDIPnt3X77T5vkCpRiXI']));
      expect(excluded, isNot(contains('9ajGS1WO9jtRvCXKScLF')));
      expect(excluded, isNot(contains('t1Ed6qZMKdMKUyBeRMQk')));
    });

    test('clothing image preview must not use BackdropFilter', () {
      expect(
        File('lib/widgets/clothing_image_preview.dart')
            .readAsStringSync()
            .contains('BackdropFilter'),
        isFalse,
      );
    });
  });

  group('SET-020 localized setType search tokens', () {
    test('matching_set members are findable as Zladený set', () {
      final item = WardrobeItemV2(
        canonicalType: 'dress_shirt',
        canonicalFamily: 'top',
        bodySlots: const ['upper_body'],
        layerPosition: 'mid',
        outfitFunctions: const [],
        setMembership: const SetMembershipV2(
          setId: 'hK3bcSdoW3FBS07QV9Z1',
          setType: 'matching_set',
          relationshipSource: 'manufacturer_matching',
          displayName: 'E2E Test Set',
        ),
        colorProfile: const ColorProfileV2(
          primary: SemanticColorV2(family: 'white'),
          metalTone: 'none',
          hardwareTone: 'none',
        ),
        formality: 6,
        styles: const [],
        occasionFit: const [],
        seasons: const [],
        warmth: 4,
        attributes: const {},
        fieldSources: const {'canonicalType': 'visual_ai'},
        fieldConfidence: const {'canonicalType': .9},
        userOverrideFields: const [],
      );
      final tokens = WardrobeSearchProjectionV2.tokens(item);
      expect(tokens, contains('matching_set'));
      expect(tokens, contains('Zladený set'));
      expect(tokens, contains('manufacturer_matching'));
      expect(tokens, contains('E2E Test Set'));
    });
  });

  group('SET-021 wardrobe context trigger', () {
    test('ordinary outfit / košeľa prompts need wardrobe without ukaz', () {
      expect(
        stylistMessageNeedsWardrobeContext(
          'Navrhni outfit okolo bielej klasickej košele na dnes o 18:00 v Martine.',
        ),
        isTrue,
      );
      expect(
        stylistMessageNeedsWardrobeContext('Čo k tej koseli?'),
        isTrue,
      );
      expect(
        stylistMessageNeedsWardrobeContext('matching set partner k bunde'),
        isTrue,
      );
    });

    test('unrelated small talk does not force wardrobe', () {
      expect(
        stylistMessageNeedsWardrobeContext('Ahoj, ako sa máš?'),
        isFalse,
      );
    });
  });

  group('Trip packing Set is preference not a collapsed object', () {
    test('packing prefers confirmed Set partner without forcing co-wear', () {
      final src = File(
        'lib/Services/trip_packing_service.dart',
      ).readAsStringSync();
      expect(src.contains('_preferConfirmedSetPartner'), isTrue);
      expect(src.contains('preference=true constraint=false'), isTrue);
      expect(src.contains('[TRIP_COMPONENT_INDEPENDENCE]'), isTrue);
      expect(src.contains('TripWardrobePiece'), isTrue);
      expect(src.contains('class TripPackingPlaceholderResult'), isTrue);
      expect(src.contains('List<TripWardrobePiece> luggageItems'), isTrue);
    });
  });

  group('Garment delete uses Set removeMember not whole-Set delete', () {
    test('wardrobe delete removes membership then deletes only that item', () {
      final src = File('lib/screens/wardrobe_screen.dart').readAsStringSync();
      expect(src.contains("Vymazať celý set"), isFalse);
      expect(src.contains('WardrobeSetRepository().removeMember(setId, id)'), isTrue);
      expect(src.contains('.doc(id)'), isTrue);
      expect(src.contains('.delete()'), isTrue);
    });
  });
}
