import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_engine_adapter.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_ontology_v2.dart';
import 'package:outfitofTheDay/utils/home_wardrobe_normalizer.dart';
import 'package:outfitofTheDay/utils/home_wardrobe_read_path.dart';

void main() {
  Map<String, dynamic> modernItem({
    String id = 'item-1',
    String canonical = 'hoodie',
    int warmth = 5,
    int formality = 3,
    int revision = 0,
    List<String> colors = const ['black'],
    List<String> styles = const ['casual'],
    List<String> seasons = const ['autumn'],
  }) => <String, dynamic>{
    'id': id,
    'name': 'Test item',
    'canonical_type': canonical,
    'mainGroupKey': 'oblecenie',
    'categoryKey': 'mikiny',
    'subCategoryKey': canonical == 'hoodie'
        ? 'mikina_s_kapucnou'
        : 'mikina_klasicka',
    'layer_role': 'mid_layer',
    'warmth_level': warmth,
    'formality': formality,
    'colors': colors,
    'styles': styles,
    'seasons': seasons,
    'profileRevision': revision,
    'imageUrl': 'https://example.test/item.png',
  };

  test('feature flag OFF uses the unchanged legacy pipeline', () {
    final raw = [modernItem()];
    const path = HomeWardrobeReadPath(useResolvedProfiles: false);

    final result = path.build(raw);
    final legacy = HomeWardrobeNormalizer.normalizeWardrobeForHome(raw);

    expect(result.usedResolvedProfiles, isFalse);
    expect(result.items, legacy);
    expect(
      result.wardrobeSignature,
      HomeWardrobeReadPath.legacyWardrobeSignature(raw),
    );
  });

  test('feature flag ON uses the resolved pipeline without fallback', () {
    final result = const HomeWardrobeReadPath(
      useResolvedProfiles: true,
    ).build([modernItem()]);

    expect(result.usedResolvedProfiles, isTrue);
    expect(result.wholePipelineFallback, isFalse);
    expect(result.resolvedWithoutFallback, 1);
    expect(result.compatibilityFallbackItems, 0);
    expect(result.items.single['canonical_type'], 'hoodie');
    expect(result.items.single['imageUrl'], 'https://example.test/item.png');
    expect(
      result.wardrobeSignature,
      matches(RegExp(r'^resolved-v1\.1\.1:[0-9a-f]{16}$')),
    );
  });

  test('canonical unknown uses an auditable compatibility fallback', () {
    final raw = <String, dynamic>{
      'id': 'sport-shoe',
      'name': 'Structured name is ignored',
      'mainGroupKey': 'obuv',
      'categoryKey': 'tenisky',
      'subCategoryKey': 'tenisky_sportove',
      'layer_role': 'footwear',
      'warmth_level': 3,
      'formality': 2,
    };

    final result = const HomeWardrobeReadPath(
      useResolvedProfiles: true,
    ).build([raw]);
    final metadata =
        result.items.single[WardrobeProfileEngineAdapter.debugMetadataKey]
            as Map;

    expect(result.compatibilityFallbackItems, 1);
    expect(result.canonicalUnknownItems, 1);
    expect(metadata['mode'], 'legacy_item_fallback');
    expect(
      metadata['fallbackProperties'],
      contains(WardrobeProfileProperty.canonicalType),
    );
  });

  test('item resolver failure falls back to the old Home item', () {
    final raw = [modernItem()];
    final result = HomeWardrobeReadPath(
      useResolvedProfiles: true,
      itemProjector: (_) => throw StateError('resolver failure'),
    ).build(raw);
    final legacy = HomeWardrobeNormalizer.normalizeWardrobeForHome(raw);

    expect(
      result.items.single['canonical_type'],
      legacy.single['canonical_type'],
    );
    expect(result.compatibilityFallbackItems, 1);
    expect(result.fallbackProperties['pipeline.itemFailure'], 1);
  });

  test('resolved path never mutates a raw Firestore map', () {
    final raw = modernItem();
    final before = Map<String, dynamic>.from(raw);

    const HomeWardrobeReadPath(useResolvedProfiles: true).build([raw]);

    expect(raw, before);
    expect(raw.containsKey('_wardrobeProfileCompatibility'), isFalse);
  });

  test('profile revision changes the resolved wardrobe signature', () {
    const path = HomeWardrobeReadPath(useResolvedProfiles: true);

    expect(
      path.build([modernItem(revision: 1)]).wardrobeSignature,
      isNot(path.build([modernItem(revision: 2)]).wardrobeSignature),
    );
  });

  test('canonical type changes the resolved wardrobe signature', () {
    const path = HomeWardrobeReadPath(useResolvedProfiles: true);

    expect(
      path.build([modernItem(canonical: 'hoodie')]).wardrobeSignature,
      isNot(
        path.build([modernItem(canonical: 'sweatshirt')]).wardrobeSignature,
      ),
    );
  });

  test('warmth or formality changes the resolved wardrobe signature', () {
    const path = HomeWardrobeReadPath(useResolvedProfiles: true);
    final baseline = path.build([modernItem()]).wardrobeSignature;

    expect(
      path.build([modernItem(warmth: 8)]).wardrobeSignature,
      isNot(baseline),
    );
    expect(
      path.build([modernItem(formality: 7)]).wardrobeSignature,
      isNot(baseline),
    );
  });

  test('color, style or season changes the resolved wardrobe signature', () {
    const path = HomeWardrobeReadPath(useResolvedProfiles: true);
    final baseline = path.build([modernItem()]).wardrobeSignature;

    expect(
      path.build([
        modernItem(colors: const ['blue']),
      ]).wardrobeSignature,
      isNot(baseline),
    );
    expect(
      path.build([
        modernItem(styles: const ['formal']),
      ]).wardrobeSignature,
      isNot(baseline),
    );
    expect(
      path.build([
        modernItem(seasons: const ['winter']),
      ]).wardrobeSignature,
      isNot(baseline),
    );
  });

  test('same profile has the same signature regardless of item order', () {
    const path = HomeWardrobeReadPath(useResolvedProfiles: true);
    final first = modernItem(id: 'a');
    final second = modernItem(id: 'b');

    expect(
      path.build([first, second]).wardrobeSignature,
      path.build([second, first]).wardrobeSignature,
    );
  });

  test('new and legacy paths preserve the same item IDs', () {
    final raw = [modernItem(id: 'a'), modernItem(id: 'b')];
    final legacy = const HomeWardrobeReadPath(
      useResolvedProfiles: false,
    ).build(raw);
    final resolved = const HomeWardrobeReadPath(
      useResolvedProfiles: true,
    ).build(raw);

    expect(resolved.itemIds.toSet(), legacy.itemIds.toSet());
  });

  test('kill switch immediately restores legacy behavior', () {
    final raw = [modernItem()];
    final enabled = const HomeWardrobeReadPath(
      useResolvedProfiles: true,
    ).build(raw);
    final disabled = const HomeWardrobeReadPath(
      useResolvedProfiles: false,
    ).build(raw);
    final legacy = HomeWardrobeNormalizer.normalizeWardrobeForHome(raw);

    expect(enabled.usedResolvedProfiles, isTrue);
    expect(disabled.usedResolvedProfiles, isFalse);
    expect(disabled.items, legacy);
    expect(disabled.wardrobeSignature, '1:item-1');
  });

  test('cheap document identity ignores profile projection and tracks Set membership', () {
    final base = modernItem();
    final withSet = modernItem();
    withSet['setMembership'] = {'setId': 'set-1'};
    final renamed = modernItem();
    renamed['name'] = 'Renamed';

    expect(
      HomeWardrobeReadPath.cheapDocumentIdentity([base]),
      HomeWardrobeReadPath.cheapDocumentIdentity([modernItem()]),
    );
    expect(
      HomeWardrobeReadPath.cheapDocumentIdentity([base]),
      isNot(HomeWardrobeReadPath.cheapDocumentIdentity([withSet])),
    );
    expect(
      HomeWardrobeReadPath.cheapDocumentIdentity([base]),
      isNot(HomeWardrobeReadPath.cheapDocumentIdentity([renamed])),
    );
  });

  test(
    'V2 path does not run the legacy normalizer when every item resolves',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await WardrobeOntologyV2.load();
      var legacyCalls = 0;
      final item = <String, dynamic>{
        'id': 'item-1',
        'name': 'Test cardigan',
        'canonicalType': 'cardigan',
        'canonicalFamily': 'mid_layer',
        'bodySlots': ['upper_body'],
        'layerPosition': 'mid',
        'colorProfile': {
          'primary': {'family': 'white'},
        },
        'formality': 4,
        'warmth': 5,
        'styles': ['classic'],
        'occasionFit': ['casual'],
        'seasons': ['autumn'],
        'attributes': <String, dynamic>{},
        'fieldSources': {'canonicalType': 'visual_ai'},
        'fieldConfidence': {'canonicalType': 0.98},
        'userOverrideFields': <String>[],
        'ontologyVersion': '2.0.0',
        'taxonomyVersion': '2.0.0',
        'kbVersion': '2.0.0',
      };
      final result = HomeWardrobeReadPath(
        useResolvedProfiles: true,
        legacyNormalizer: (raw) {
          legacyCalls++;
          return HomeWardrobeNormalizer.normalizeWardrobeForHome(raw);
        },
      ).build([item]);

      expect(result.wardrobeSignature, startsWith('wardrobe-v2:'));
      expect(result.compatibilityFallbackItems, 0);
      expect(legacyCalls, 0);
    },
  );
}
