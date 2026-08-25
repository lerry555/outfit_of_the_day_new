import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_engine_adapter.dart';

void main() {
  const adapter = WardrobeProfileEngineAdapter();

  ResolvedField<T> known<T>(
    T value, {
    EvidenceSource source = EvidenceSource.visualObservation,
    bool userCorrected = false,
  }) => ResolvedField<T>.known(
    value: value,
    nature: EvidenceNature.observed,
    winningSource: source,
    confidence: 0.9,
    winningEvidenceIds: const ['evidence-1'],
    userCorrected: userCorrected,
    resolutionReason: 'test',
  );

  ResolvedWardrobeItemProfile profile({
    ResolvedField<String> name = const ResolvedField<String>.unknown(),
    ResolvedField<String> brand = const ResolvedField<String>.unknown(),
    ResolvedField<String> canonicalType = const ResolvedField<String>.unknown(),
    ResolvedField<String> mainCategory = const ResolvedField<String>.unknown(),
    ResolvedField<String> category = const ResolvedField<String>.unknown(),
    ResolvedField<String> subcategory = const ResolvedField<String>.unknown(),
    ResolvedField<WardrobeLayerRole> layerRole =
        const ResolvedField<WardrobeLayerRole>.unknown(),
    ResolvedField<int> warmth = const ResolvedField<int>.unknown(),
    ResolvedField<int> formality = const ResolvedField<int>.unknown(),
    ResolvedField<List<String>> colors =
        const ResolvedField<List<String>>.unknown(),
    ResolvedField<List<String>> baseColors =
        const ResolvedField<List<String>>.unknown(),
    ResolvedField<List<String>> styles =
        const ResolvedField<List<String>>.unknown(),
    ResolvedField<List<String>> patterns =
        const ResolvedField<List<String>>.unknown(),
    ResolvedField<String> fit = const ResolvedField<String>.unknown(),
    ResolvedField<String> vibe = const ResolvedField<String>.unknown(),
    ResolvedField<Set<String>> seasons =
        const ResolvedField<Set<String>>.unknown(),
    ResolvedField<Set<String>> occasions =
        const ResolvedField<Set<String>>.unknown(),
    List<ProfileEvidence> evidence = const [],
  }) => ResolvedWardrobeItemProfile(
    itemId: 'item-1',
    identity: WardrobeItemIdentity(
      displayName: name,
      brand: brand,
      canonicalType: canonicalType,
      mainCategory: mainCategory,
      category: category,
      subcategory: subcategory,
    ),
    visual: WardrobeItemVisualProfile(
      colors: colors,
      baseColors: baseColors,
      styles: styles,
      patterns: patterns,
      fit: fit,
      vibe: vibe,
    ),
    capabilities: WardrobeItemCapabilities(
      layerRole: layerRole,
      warmth: warmth,
      formality: formality,
    ),
    suitability: WardrobeItemSuitability(
      seasons: seasons,
      occasions: occasions,
    ),
    evidence: evidence,
  );

  Map<String, dynamic> debugMetadata(Map<String, dynamic> output) =>
      Map<String, dynamic>.from(
        output[WardrobeProfileEngineAdapter.debugMetadataKey] as Map,
      );

  Map<String, String> fallbacks(Map<String, dynamic> output) =>
      Map<String, String>.from(
        debugMetadata(output)['delegatedFallbacks'] as Map,
      );

  test('projects a fully resolved modern profile', () {
    final output = adapter.toEngineMap(
      profile(
        name: known('Čierna softshell bunda'),
        brand: known('Northfinder'),
        canonicalType: known('softshell_jacket'),
        mainCategory: known('oblecenie'),
        category: known('bundy'),
        subcategory: known('softshell_bunda'),
        layerRole: known(WardrobeLayerRole.outerLayer),
        warmth: known(4),
        formality: known(3),
        colors: known(['čierna']),
        baseColors: known(['black']),
        styles: known(['outdoor']),
        patterns: known(['solid']),
        fit: known('regular'),
        vibe: known('sporty'),
        seasons: known({'jeseň', 'jar'}),
        occasions: known({'turistika'}),
      ),
    );

    expect(output['id'], 'item-1');
    expect(output['name'], 'Čierna softshell bunda');
    expect(output['brand'], 'Northfinder');
    expect(output['canonical_type'], 'softshell_jacket');
    expect(output['canonicalType'], 'softshell_jacket');
    expect(output['mainGroupKey'], 'oblecenie');
    expect(output['categoryKey'], 'bundy');
    expect(output['subCategoryKey'], 'softshell_bunda');
    expect(output['layer_role'], 'outer_layer');
    expect(output['warmth_level'], 4);
    expect(output['formality'], 3);
    expect(output['colors'], ['čierna']);
    expect(output['styles'], ['outdoor']);
    expect(output['patterns'], ['solid']);
    expect(output['fit'], 'regular');
    expect(output['vibe'], 'sporty');
    expect(output['occasion_fit'], ['turistika']);
    expect(fallbacks(output), isEmpty);
  });

  test('unknown warmth is omitted and legacy engine fallback is declared', () {
    final output = adapter.toEngineMap(profile());

    expect(output.containsKey('warmth_level'), isFalse);
    expect(
      fallbacks(output)['warmth_level'],
      'legacy_engine_item_inference_then_5',
    );
  });

  test('unknown formality remains absent without invented fallback', () {
    final output = adapter.toEngineMap(profile());

    expect(output.containsKey('formality'), isFalse);
    expect(fallbacks(output).containsKey('formality'), isFalse);
    expect(
      debugMetadata(output)['unknownResolvedProperties'],
      contains(WardrobeProfileProperty.formality),
    );
  });

  test('unknown layer role delegates explicitly to legacy behavior', () {
    final output = adapter.toEngineMap(profile());

    expect(output.containsKey('layer_role'), isFalse);
    expect(
      fallbacks(output)['layer_role'],
      'legacy_engine_category_then_base_layer',
    );
  });

  test('missing canonical type stays absent and fallback is visible', () {
    final output = adapter.toEngineMap(profile());

    expect(output.containsKey('canonical_type'), isFalse);
    expect(
      fallbacks(output)['canonical_type'],
      'legacy_engine_name_category_classification',
    );
  });

  test('user-corrected canonical type is preserved exactly', () {
    final output = adapter.toEngineMap(
      profile(
        canonicalType: known(
          'light_softshell',
          source: EvidenceSource.userCorrection,
          userCorrected: true,
        ),
      ),
    );

    expect(output['canonical_type'], 'light_softshell');
    expect(output['canonicalType'], 'light_softshell');
    expect(fallbacks(output).containsKey('canonical_type'), isFalse);
  });

  test('resolved concrete warmth is never replaced by a default', () {
    final output = adapter.toEngineMap(profile(warmth: known(2)));

    expect(output['warmth_level'], 2);
    expect(output['warmthLevel'], 2);
    expect(fallbacks(output).containsKey('warmth_level'), isFalse);
  });

  test('collections are projected deterministically', () {
    final output = adapter.toEngineMap(
      profile(
        colors: known(['navy', 'white']),
        styles: known(['sport', 'casual']),
        patterns: known(['striped']),
        seasons: known({'zima', 'Jeseň', 'jar'}),
        occasions: known({'work', 'casual'}),
      ),
    );

    expect(output['colors'], ['navy', 'white']);
    expect(output['styles'], ['sport', 'casual']);
    expect(output['patterns'], ['striped']);
    expect(output['seasons'], ['jar', 'Jeseň', 'zima']);
    expect(output['occasion_fit'], ['casual', 'work']);
  });

  test('same profile produces the same projection', () {
    final input = profile(
      name: known('Biele tenisky'),
      canonicalType: known('fashion_sneakers'),
      seasons: known({'leto', 'jar'}),
    );

    expect(adapter.toEngineMap(input), adapter.toEngineMap(input));
  });

  test('adapter does not mutate the input profile or its collections', () {
    final sourceColors = <String>['white', 'black'];
    final input = profile(colors: known(sourceColors));
    final before = input.visual.colors.toMap();

    final output = adapter.toEngineMap(input);

    expect(input.visual.colors.toMap(), before);
    expect(sourceColors, ['white', 'black']);
    expect(output['colors'], ['white', 'black']);
  });

  test('compatibility fallback creates no evidence or resolved value', () {
    final existingEvidence = ProfileEvidence(
      id: 'legacy',
      property: WardrobeProfileProperty.displayName,
      value: 'Mikina',
      source: EvidenceSource.legacyFallback,
      nature: EvidenceNature.unknown,
      confidence: 0,
      method: 'test',
      createdAt: DateTime.utc(2026, 7, 27),
    );
    final input = profile(evidence: [existingEvidence]);
    final evidenceBefore = input.evidence.map((item) => item.toMap()).toList();

    final output = adapter.toEngineMap(input);

    expect(fallbacks(output), isNotEmpty);
    expect(input.capabilities.warmth.isKnown, isFalse);
    expect(input.capabilities.layerRole.isKnown, isFalse);
    expect(input.identity.canonicalType.isKnown, isFalse);
    expect(input.evidence.map((item) => item.toMap()).toList(), evidenceBefore);
    expect(input.evidence, hasLength(1));
  });
}
