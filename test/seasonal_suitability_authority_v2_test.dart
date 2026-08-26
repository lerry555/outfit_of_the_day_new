import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/native_outfit_engine_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_suitability_policy_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/season_compatibility_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';

WardrobeItemV2 _item({
  required String type,
  required String family,
  required List<String> slots,
  required String layer,
  required int warmth,
  List<String> seasons = const [],
  List<String> functions = const [],
}) => WardrobeItemV2(
  canonicalType: type,
  canonicalFamily: family,
  bodySlots: slots,
  layerPosition: layer,
  outfitFunctions: functions,
  colorProfile: const ColorProfileV2(
    primary: SemanticColorV2(family: 'black'),
    metalTone: 'none',
    hardwareTone: 'none',
  ),
  formality: 4,
  styles: const [],
  occasionFit: const [],
  seasons: seasons,
  warmth: warmth,
  attributes: const {},
  fieldSources: const {'canonicalType': 'fixture'},
  fieldConfidence: const {'canonicalType': 1.0},
  userOverrideFields: const [],
);

ResolvedWardrobeItemV2 _resolved(String id, WardrobeItemV2 item) =>
    ResolvedWardrobeItemV2(itemId: id, item: item, raw: {'id': id});

final _winterBoots = _item(
  type: 'winter_boots',
  family: 'footwear',
  slots: const ['feet'],
  layer: 'not_applicable',
  warmth: 9,
  seasons: const ['zima'],
);

final _summerSandals = _item(
  type: 'sandals',
  family: 'footwear',
  slots: const ['feet'],
  layer: 'not_applicable',
  warmth: 1,
  seasons: const ['leto'],
);

void main() {
  group('seasonal suitability authority', () {
    test(
      'cold weather permits winter boots across autumn, winter and spring',
      () {
        for (final (:seasonKey, :tempC) in const [
          (seasonKey: 'jese', tempC: 1),
          (seasonKey: 'jese', tempC: -4),
          (seasonKey: 'jar', tempC: -2),
          (seasonKey: 'jar', tempC: 4),
        ]) {
          expect(
            OutfitSuitabilityPolicyV2.isFootwearPhysicallyUnsuitableForConditions(
              _winterBoots,
              seasonKey: seasonKey,
              tempC: tempC,
            ),
            isFalse,
            reason: '$seasonKey/$tempC must follow physical cold, not calendar',
          );
        }
      },
    );

    test('warm weather rejects heavy winter boots even in calendar winter', () {
      expect(
        OutfitSuitabilityPolicyV2.isFootwearPhysicallyUnsuitableForConditions(
          _winterBoots,
          seasonKey: 'zim',
          tempC: 14,
        ),
        isTrue,
      );
    });

    test(
      'hot spring and autumn allow summer footwear, but cold rain does not',
      () {
        for (final seasonKey in const ['jar', 'jese']) {
          expect(
            OutfitSuitabilityPolicyV2.isFootwearPhysicallyUnsuitableForConditions(
              _summerSandals,
              seasonKey: seasonKey,
              tempC: 25,
            ),
            isFalse,
          );
        }
        expect(
          OutfitSuitabilityPolicyV2.isPhysicallyUnsuitable(
            _summerSandals,
            seasonKey: 'let',
            tempC: 8,
            isRainy: true,
          ),
          isTrue,
        );
      },
    );

    test(
      'warm August rejects very warm boots regardless of rain and season metadata',
      () {
        expect(
          OutfitSuitabilityPolicyV2.isFootwearPhysicallyUnsuitableForConditions(
            _winterBoots,
            seasonKey: 'let',
            tempC: 25,
          ),
          isTrue,
        );
      },
    );

    test(
      'calendar mismatch is a soft ranking prior, never an eligibility gate',
      () {
        final lightChelsea = _item(
          type: 'chelsea_boots',
          family: 'footwear',
          slots: const ['feet'],
          layer: 'not_applicable',
          warmth: 4,
          seasons: const ['jeseň', 'zima'],
        );
        expect(
          OutfitSuitabilityPolicyV2.isFootwearPhysicallyUnsuitableForConditions(
            lightChelsea,
            seasonKey: 'let',
            tempC: 14,
          ),
          isFalse,
        );
        expect(
          OutfitSuitabilityPolicyV2.calendarSeasonCompatibilityAdjustment(
            lightChelsea,
            seasonKey: 'let',
          ),
          lessThan(0),
        );
      },
    );

    test('all-season items receive no calendar penalty', () {
      final allSeasonChelsea = _item(
        type: 'chelsea_boots',
        family: 'footwear',
        slots: const ['feet'],
        layer: 'not_applicable',
        warmth: 4,
        seasons: const ['celoročne'],
      );
      expect(
        OutfitSuitabilityPolicyV2.calendarSeasonCompatibilityAdjustment(
          allSeasonChelsea,
          seasonKey: 'zim',
        ),
        0,
      );
    });

    test(
      'dry 14C calendar-winter composition does not add a heavy winter outer layer',
      () {
        final core = [
          _resolved(
            'top',
            _item(
              type: 't_shirt',
              family: 'top',
              slots: const ['upper_body'],
              layer: 'base',
              warmth: 2,
            ),
          ),
          _resolved(
            'bottom',
            _item(
              type: 'jeans',
              family: 'bottom',
              slots: const ['lower_body'],
              layer: 'outer',
              warmth: 4,
            ),
          ),
          _resolved(
            'shoes',
            _item(
              type: 'sneakers',
              family: 'footwear',
              slots: const ['feet'],
              layer: 'not_applicable',
              warmth: 3,
            ),
          ),
          _resolved(
            'puffer',
            _item(
              type: 'winter_jacket',
              family: 'outerwear',
              slots: const ['upper_body'],
              layer: 'outer',
              warmth: 9,
              seasons: const ['zima'],
            ),
          ),
        ];
        final outfit = NativeOutfitEngineV2.compose(
          core,
          const NativeOutfitRequestV2(tempC: 14, seasonKey: 'zim'),
        );
        expect(outfit, isNotNull);
        expect(
          outfit!.items.map((item) => item.itemId),
          isNot(contains('puffer')),
        );
      },
    );

    test(
      'candidate generation keeps cold-weather winter footwear across a calendar boundary',
      () {
        final matrix = V2FlexibleCandidateMatrix.generate(
          wardrobe: [
            _resolved(
              'top',
              _item(
                type: 'longsleeve',
                family: 'top',
                slots: const ['upper_body'],
                layer: 'base',
                warmth: 4,
              ),
            ),
            _resolved(
              'bottom',
              _item(
                type: 'jeans',
                family: 'bottom',
                slots: const ['lower_body'],
                layer: 'outer',
                warmth: 4,
              ),
            ),
            _resolved('winter', _winterBoots),
          ],
          context: const V2CandidateMatrixContext(tempC: -2, seasonKey: 'jar'),
        );
        expect(matrix, isNotEmpty);
        expect(
          matrix.first.outfit.items.map((item) => item.itemId),
          contains('winter'),
        );
      },
    );
  });

  group('deterministic season derivation', () {
    test(
      'derives compatibility metadata from thermal/type facts without calendar dates',
      () {
        expect(
          SeasonCompatibilityV2.derive(
            canonicalType: 'winter_boots',
            canonicalFamily: 'footwear',
            layerPosition: 'not_applicable',
            warmth: 8,
          ),
          const ['jeseň', 'zima'],
        );
        expect(
          SeasonCompatibilityV2.derive(
            canonicalType: 'sneakers',
            canonicalFamily: 'footwear',
            layerPosition: 'not_applicable',
            warmth: 3,
          ),
          const ['jar', 'leto', 'jeseň'],
        );
        expect(
          SeasonCompatibilityV2.derive(
            canonicalType: 'light_jacket',
            canonicalFamily: 'outerwear',
            layerPosition: 'outer',
            warmth: 4,
            outfitFunctions: const ['weather_protection'],
          ),
          const ['jar', 'leto', 'jeseň'],
        );
      },
    );
  });
}
