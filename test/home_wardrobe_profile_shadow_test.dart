import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/debug/home_wardrobe_profile_shadow.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

void main() {
  const runner = HomeWardrobeProfileShadowRunner();

  Map<String, dynamic> completeRaw(String id) => {
    'id': id,
    'name': 'Čierna mikina',
    'brand': 'Nike',
    'canonical_type': 'hoodie',
    'mainGroupKey': 'oblecenie',
    'categoryKey': 'mikiny',
    'subCategoryKey': 'mikina_s_kapucnou',
    'layer_role': 'mid_layer',
    'warmth_level': 5,
    'formality': 2,
    'colors': ['čierna', 'biela'],
    'styles': ['casual'],
    'seasons': ['jeseň', 'zima'],
  };

  Map<String, dynamic> matchingProduction(String id) => {
    ...completeRaw(id),
    'canonicalType': 'hoodie',
    'category': 'mikiny',
    'subCategory': 'mikina_s_kapucnou',
    'layerRole': 'mid_layer',
    'warmthLevel': 5,
    'color': ['čierna', 'biela'],
    'season': ['jeseň', 'zima'],
    'home_kb_applied': false,
    'home_legacy_fallback': false,
  };

  test('old and shadow projections can fully match', () {
    final run = runner.compare(
      rawItems: [completeRaw('item-1')],
      productionItems: [matchingProduction('item-1')],
    );

    expect(run.items, hasLength(1));
    expect(run.items.single.hasDifference, isFalse);
    expect(run.summary.analyzedItems, 1);
    expect(run.summary.fullyMatchingItems, 1);
    expect(run.summary.itemsWithDifference, 0);
  });

  test('old warmth fallback 5 versus new unknown is distinguished', () {
    final raw = <String, dynamic>{'id': 'item-1', 'name': 'Neznámy kus'};
    final production = <String, dynamic>{
      ...raw,
      'warmth_level': 5,
      'home_kb_applied': false,
      'home_legacy_fallback': false,
    };

    final run = runner.compare(rawItems: [raw], productionItems: [production]);
    final warmth = run.items.single.field(WardrobeProfileProperty.warmth);

    expect(
      warmth.difference,
      HomeWardrobeShadowDifference.oldFallbackNewUnknown,
    );
    expect(run.summary.oldFallbackNewUnknownItems, 1);
    expect(run.summary.warmthDifferences, 1);
  });

  test('old base layer fallback versus new unknown is distinguished', () {
    final raw = <String, dynamic>{'id': 'item-1', 'name': 'Neznámy kus'};
    final production = <String, dynamic>{
      ...raw,
      'layer_role': 'base_layer',
      'home_kb_applied': false,
      'home_legacy_fallback': true,
    };

    final run = runner.compare(rawItems: [raw], productionItems: [production]);
    final layer = run.items.single.field(WardrobeProfileProperty.layerRole);

    expect(
      layer.difference,
      HomeWardrobeShadowDifference.oldFallbackNewUnknown,
    );
    expect(run.summary.layerRoleDifferences, 1);
  });

  test('different canonical type is reported', () {
    final raw = completeRaw('item-1');
    final production = matchingProduction('item-1')
      ..['canonical_type'] = 'jacket'
      ..['canonicalType'] = 'jacket';

    final run = runner.compare(rawItems: [raw], productionItems: [production]);
    final canonical = run.items.single.field(
      WardrobeProfileProperty.canonicalType,
    );

    expect(canonical.difference, HomeWardrobeShadowDifference.different);
    expect(canonical.oldValue, 'jacket');
    expect(canonical.newValue, 'hoodie');
  });

  test(
    'different concrete warmth is reported without replacing either value',
    () {
      final raw = completeRaw('item-1')..['warmth_level'] = 2;
      final production = matchingProduction('item-1')
        ..['warmth_level'] = 5
        ..['warmthLevel'] = 5;

      final run = runner.compare(
        rawItems: [raw],
        productionItems: [production],
      );
      final warmth = run.items.single.field(WardrobeProfileProperty.warmth);

      expect(warmth.difference, HomeWardrobeShadowDifference.different);
      expect(warmth.oldValue, 5);
      expect(warmth.newValue, 2);
      expect(production['warmth_level'], 5);
      expect(raw['warmth_level'], 2);
    },
  );

  test('collection equality is independent of order and duplicates', () {
    final raw = completeRaw('item-1')
      ..['colors'] = ['biela', 'čierna', 'biela']
      ..['seasons'] = ['zima', 'jeseň'];
    final production = matchingProduction('item-1')
      ..['colors'] = ['čierna', 'biela']
      ..['seasons'] = ['jeseň', 'zima'];

    final run = runner.compare(rawItems: [raw], productionItems: [production]);

    expect(
      run.items.single.field(WardrobeProfileProperty.colors).difference,
      HomeWardrobeShadowDifference.same,
    );
    expect(
      run.items.single.field(WardrobeProfileProperty.seasons).difference,
      HomeWardrobeShadowDifference.same,
    );
  });

  test('comparison does not mutate raw or production inputs', () {
    final raw = completeRaw('item-1');
    final production = matchingProduction('item-1');
    final rawColors = List<String>.from(raw['colors'] as List);
    final productionColors = List<String>.from(production['colors'] as List);
    final rawKeys = raw.keys.toList();
    final productionKeys = production.keys.toList();

    runner.compare(rawItems: [raw], productionItems: [production]);

    expect(raw.keys, rawKeys);
    expect(production.keys, productionKeys);
    expect(raw['colors'], rawColors);
    expect(production['colors'], productionColors);
  });

  test('shadow failure cannot alter the production Home result', () {
    final raw = completeRaw('item-1');
    final production = matchingProduction('item-1');
    final productionBefore = Map<String, dynamic>.from(production);

    final run = runner.compare(
      rawItems: [raw],
      productionItems: [production],
      projector: (_) => throw StateError('shadow failed'),
    );

    expect(run.summary.failedItems, 1);
    expect(run.items.single.error, 'StateError');
    expect(production, productionBefore);
    expect(identical(run.items, production), isFalse);
  });

  test('summary counts are deterministic regardless of item order', () {
    final rawA = completeRaw('a');
    final rawB = <String, dynamic>{'id': 'b', 'name': 'Neznámy kus'};
    final productionA = matchingProduction('a');
    final productionB = <String, dynamic>{
      ...rawB,
      'warmth_level': 5,
      'layer_role': 'base_layer',
      'formality': 5,
      'home_legacy_fallback': true,
    };

    final forward = runner.compare(
      rawItems: [rawA, rawB],
      productionItems: [productionA, productionB],
    );
    final reverse = runner.compare(
      rawItems: [rawB, rawA],
      productionItems: [productionB, productionA],
    );

    expect(reverse.summary.toLogLine(), forward.summary.toLogLine());
    expect(
      reverse.items.map((item) => item.toLogLine()).toList(),
      forward.items.map((item) => item.toLogLine()).toList(),
    );
    expect(forward.summary.analyzedItems, 2);
    expect(forward.summary.fullyMatchingItems, 1);
    expect(forward.summary.itemsWithDifference, 1);
    expect(forward.summary.oldFallbackNewUnknownItems, 1);
    expect(forward.summary.warmthDifferences, 1);
    expect(forward.summary.layerRoleDifferences, 1);
    expect(forward.summary.formalityDifferences, 1);
    expect(
      forward.items
          .singleWhere((item) => item.itemId == 'b')
          .field(WardrobeProfileProperty.formality)
          .difference,
      HomeWardrobeShadowDifference.oldFallbackNewUnknown,
    );
  });

  test(
    'comparison creates no evidence and does not feed shadow into production',
    () {
      final raw = <String, dynamic>{'id': 'item-1', 'name': 'Neznámy kus'};
      final production = <String, dynamic>{
        ...raw,
        'warmth_level': 5,
        'layer_role': 'base_layer',
      };

      final run = runner.compare(
        rawItems: [raw],
        productionItems: [production],
      );

      expect(raw.containsKey('evidence'), isFalse);
      expect(production.containsKey('evidence'), isFalse);
      expect(production['warmth_level'], 5);
      expect(run.items.single.hasDifference, isTrue);
    },
  );

  test('shadow reports KB winners and degraded legacy defaults read-only', () {
    final raw = <String, dynamic>{
      'id': 'item-1',
      'name': 'Biela mikina',
      'canonical_type': 'hoodie',
      'layer_role': 'mid_layer',
      'warmth_level': 7,
      'formality': 5,
      'kb_migration_version': 2,
    };
    final production = <String, dynamic>{
      ...raw,
      'warmth_level': 5,
      'formality': 2,
      'home_kb_applied': true,
    };
    final rawBefore = Map<String, dynamic>.from(raw);
    final productionBefore = Map<String, dynamic>.from(production);

    final run = runner.compare(rawItems: [raw], productionItems: [production]);

    expect(run.items.single.kbPriorWinner, isTrue);
    expect(run.items.single.degradedLegacyDefaults, 4);
    expect(run.summary.kbPriorWinnerItems, 1);
    expect(run.summary.degradedLegacyDefaultItems, 1);
    expect(run.summary.degradedLegacyDefaults, 4);
    expect(raw, rawBefore);
    expect(production, productionBefore);
  });

  test('shadow identifies structured canonical prior winners', () {
    final raw = <String, dynamic>{
      'id': 'item-1',
      'categoryKey': 'tricka_topy',
      'subCategoryKey': 'tricko',
    };
    final production = <String, dynamic>{...raw, 'canonical_type': 't_shirt'};

    final run = runner.compare(rawItems: [raw], productionItems: [production]);

    expect(
      run.items.single.structuredCanonicalPrior,
      'structured_taxonomy:|tricka_topy|tricko',
    );
    expect(run.summary.structuredCanonicalPriorWinnerItems, 1);
    expect(production.containsKey('_wardrobeProfileCompatibility'), isFalse);
  });
}
