import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/outfit_generation_service.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_engine_adapter.dart';
import 'package:outfitofTheDay/utils/home_wardrobe_normalizer.dart';
import 'package:outfitofTheDay/utils/home_wardrobe_read_path.dart';
import 'package:outfitofTheDay/utils/stylist_chat_wardrobe_read_path.dart';

void main() {
  Map<String, dynamic> item({
    String id = 'item-1',
    String canonical = 'hoodie',
    int warmth = 6,
    int formality = 3,
    String layerRole = 'mid_layer',
  }) => <String, dynamic>{
    'id': id,
    'name': 'Fixture',
    'canonical_type': canonical,
    'mainGroupKey': 'oblecenie',
    'categoryKey': 'mikiny',
    'subCategoryKey': 'mikina_s_kapucnou',
    'layer_role': layerRole,
    'warmth_level': warmth,
    'formality': formality,
    'colors': const ['black', 'blue'],
    'styles': const ['casual'],
    'seasons': const ['autumn', 'winter'],
  };

  test('flag OFF preserves the legacy Chat path', () {
    final raw = [item()];
    final result = const StylistChatWardrobeReadPath(
      useResolvedProfiles: false,
    ).build(raw);

    expect(result.usedResolvedProfiles, isFalse);
    expect(
      result.items,
      HomeWardrobeNormalizer.normalizeWardrobeForHome(raw, log: false),
    );
  });

  test('flag ON uses the shared resolved path', () {
    final result = const StylistChatWardrobeReadPath(
      useResolvedProfiles: true,
    ).build([item()]);

    expect(result.usedResolvedProfiles, isTrue);
    expect(result.resolvedWithoutFallback, 1);
    expect(result.compatibilityFallbackItems, 0);
  });

  test('Home and Chat have decision-field parity for one raw item', () {
    final raw = [item()];
    final home = const HomeWardrobeReadPath(
      useResolvedProfiles: true,
    ).build(raw);
    final chat = const StylistChatWardrobeReadPath(
      useResolvedProfiles: true,
    ).build(raw);

    expect(
      _decisionFields(chat.items.single),
      _decisionFields(home.items.single),
    );
  });

  test('Home and Chat have parity for a wardrobe snapshot', () {
    final raw = [
      item(id: 'a'),
      item(
        id: 'b',
        canonical: 't_shirt',
        warmth: 2,
        formality: 2,
        layerRole: 'base_layer',
      ),
    ];
    final home = const HomeWardrobeReadPath(
      useResolvedProfiles: true,
    ).build(raw);
    final chat = const StylistChatWardrobeReadPath(
      useResolvedProfiles: true,
    ).build(raw);

    expect(chat.items.map(_decisionFields), home.items.map(_decisionFields));
    expect(chat.wardrobeSignature, home.wardrobeSignature);
  });

  test('canonical unknown fallback is explicit and auditable', () {
    final result = const StylistChatWardrobeReadPath(useResolvedProfiles: true)
        .build([
          {
            'id': 'ambiguous-shoe',
            'mainGroupKey': 'obuv',
            'categoryKey': 'tenisky',
            'subCategoryKey': 'tenisky_sportove',
            'layer_role': 'footwear',
            'warmth_level': 3,
            'formality': 2,
          },
        ]);
    final metadata =
        result.items.single[WardrobeProfileEngineAdapter.debugMetadataKey]
            as Map;

    expect(result.compatibilityFallbackItems, 1);
    expect(result.fallbackProperties, {
      WardrobeProfileProperty.canonicalType: 1,
    });
    expect(metadata['mode'], 'legacy_item_fallback');
  });

  test('resolved decision fields are not reclassified or overwritten', () {
    final output = const StylistChatWardrobeReadPath(useResolvedProfiles: true)
        .build([item(warmth: 8, formality: 7, layerRole: 'outer_layer')])
        .items
        .single;

    expect(output['warmth_level'], 8);
    expect(output['formality'], 7);
    expect(output['layer_role'], 'outer_layer');
  });

  test('raw Firestore map remains immutable', () {
    final raw = item();
    final before = Map<String, dynamic>.from(raw);

    const StylistChatWardrobeReadPath(useResolvedProfiles: true).build([raw]);

    expect(raw, before);
    expect(
      raw.containsKey(WardrobeProfileEngineAdapter.debugMetadataKey),
      false,
    );
  });

  test('resolver failure safely falls back to legacy Chat projection', () {
    final raw = [item()];
    final result = StylistChatWardrobeReadPath(
      useResolvedProfiles: true,
      itemProjector: (_) => throw StateError('fixture failure'),
    ).build(raw);

    expect(result.compatibilityFallbackItems, 1);
    expect(result.fallbackProperties['pipeline.itemFailure'], 1);
    expect(
      result.items.single['canonical_type'],
      HomeWardrobeNormalizer.normalizeWardrobeForHome(
        raw,
        log: false,
      ).single['canonical_type'],
    );
  });

  test('same input produces the same resolved Chat projection', () {
    const path = StylistChatWardrobeReadPath(useResolvedProfiles: true);
    final raw = [item(id: 'b'), item(id: 'a')];

    expect(path.build(raw).items, path.build(raw).items);
    expect(
      path.build(raw).wardrobeSignature,
      path.build(raw.reversed.toList()).wardrobeSignature,
    );
  });

  test('legacy and resolved paths preserve candidate pool and ordering', () {
    final raw = [
      item(
        id: 'top',
        canonical: 't_shirt',
        warmth: 2,
        formality: 2,
        layerRole: 'base_layer',
      ),
      {
        'id': 'bottom',
        'name': 'Bottom',
        'canonical_type': 'jeans',
        'mainGroupKey': 'oblecenie',
        'categoryKey': 'nohavice',
        'subCategoryKey': 'dzinsy',
        'layer_role': 'bottom',
        'warmth_level': 4,
        'formality': 3,
        'colors': const ['blue'],
        'styles': const ['casual'],
        'seasons': const ['spring', 'summer', 'autumn'],
      },
      {
        'id': 'shoes',
        'name': 'Shoes',
        'canonical_type': 'sneakers',
        'mainGroupKey': 'obuv',
        'categoryKey': 'tenisky',
        'subCategoryKey': 'tenisky_volnocasove',
        'layer_role': 'footwear',
        'warmth_level': 3,
        'formality': 2,
        'colors': const ['white'],
        'styles': const ['casual'],
        'seasons': const ['spring', 'summer', 'autumn'],
      },
    ];
    final legacy = const StylistChatWardrobeReadPath(
      useResolvedProfiles: false,
    ).build(raw);
    final resolved = const StylistChatWardrobeReadPath(
      useResolvedProfiles: true,
    ).build(raw);

    expect(resolved.itemIds.toSet(), legacy.itemIds.toSet());
    const weather = OutfitWeatherSnapshot(
      tempC: 22,
      isRainy: false,
      isWindy: false,
      seasonKey: 'let',
    );
    List<String> candidates(List<Map<String, dynamic>> wardrobe) =>
        OutfitGenerationService.generateCandidatePreviews(
              wardrobeItems: wardrobe,
              weather: weather,
              limit: 4,
            )
            .map(
              (preview) => OutfitGenerationService.combinationSignature(
                preview.top.item,
                preview.bottom.item,
                preview.shoes.item,
                preview.outerwear?.item,
              ),
            )
            .toList(growable: false);

    expect(candidates(resolved.items), candidates(legacy.items));
  });
}

Map<String, Object?> _decisionFields(Map<String, dynamic> item) =>
    <String, Object?>{
      'id': item['id'],
      'canonical_type': item['canonical_type'],
      'mainGroupKey': item['mainGroupKey'],
      'categoryKey': item['categoryKey'],
      'subCategoryKey': item['subCategoryKey'],
      'layer_role': item['layer_role'],
      'warmth_level': item['warmth_level'],
      'formality': item['formality'],
      'colors': item['colors'],
      'styles': item['styles'],
      'seasons': item['seasons'],
    };
