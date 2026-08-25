import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/add_clothing_analyzer_mapper.dart';
import 'package:outfitofTheDay/Services/clothing_analyzer_pipeline.dart';
import 'package:outfitofTheDay/Services/wardrobe_v2_edit_prepopulation.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v1_retirement.dart';

import 'add_clothing_analyzer_fixtures.dart';

void main() {
  group('AddClothingAnalyzerMapper characterization', () {
    test('t-shirt V2 passthrough, form projection, and overlays', () {
      final response = addClothingAnalyzerTShirtFixture();
      final mapped = AddClothingAnalyzerMapper.map(response);

      expect(identical(mapped.wardrobeV2, response['wardrobeV2']), isTrue);
      expect(mapped.wardrobeV2!['canonicalType'], 't_shirt');
      expect(mapped.wardrobeV2!['colorProfile']['primary']['family'], 'white');
      expect(mapped.mappedCanonicalType, 't_shirt');
      expect(mapped.kbMatched, isTrue);
      expect(mapped.kbTypeDisplayName, 'Tričko s krátkym rukávom');
      expect(mapped.categoryKey, 'tricka_topy');
      expect(mapped.subCategoryKey, 'tricko');
      expect(mapped.displayColors, ['biela', 'čierna']);
      expect(mapped.styles, contains('casual'));
      expect(mapped.patterns, ['jednofarebné']);
      expect(mapped.formPatterns, ['jednofarebné']);
      expect(mapped.seasons, ['celoročne']);
      expect(mapped.brand, isEmpty);
      expect(mapped.warmthLevel, 2);
      expect(mapped.formalityLevel, 3);
      expect(mapped.usedAuthoritativeV2, isTrue);
      expect(mapped.confidenceRaw, 98);
      expect(mapped.suggestedName.toLowerCase(), contains('tričko'));
    });

    test('hoodie maps mid-layer UI and graphic pattern overlay', () {
      final response = addClothingAnalyzerHoodieFixture();
      final mapped = AddClothingAnalyzerMapper.map(response);

      expect(mapped.wardrobeV2!['canonicalType'], 'hoodie');
      expect(mapped.mappedCanonicalType, 'hoodie');
      expect(mapped.subCategoryKey, 'mikina_s_kapucnou');
      expect(mapped.categoryKey, 'mikiny');
      expect(mapped.displayColors, ['čierna']);
      expect(mapped.styles, containsAll(['casual', 'streetwear']));
      expect(mapped.patterns, ['grafická potlač']);
      expect(mapped.warmthLevel, 5);
      expect(mapped.formalityLevel, 2);
      expect(mapped.aiStylingLayerRole, isNotEmpty);
    });

    test('puffer jacket uses KB warmth for winter jacket seasons', () {
      final response = addClothingAnalyzerPufferJacketFixture();
      final mapped = AddClothingAnalyzerMapper.map(response);

      expect(mapped.wardrobeV2!['canonicalType'], 'puffer_jacket');
      expect(mapped.wardrobeV2!['warmth'], 9);
      expect(mapped.mappedCanonicalType, 'puffer_jacket');
      expect(mapped.subCategoryKey, 'bunda_zimna');
      expect(mapped.seasons, ['jeseň', 'zima']);
      expect(mapped.displayColors, ['tmavomodrá']);
      expect(mapped.warmthLevel, 9);
    });

    test('jeans project bottom category and plural name color', () {
      final response = addClothingAnalyzerJeansFixture();
      final mapped = AddClothingAnalyzerMapper.map(response);

      expect(mapped.wardrobeV2!['canonicalType'], 'jeans');
      expect(mapped.subCategoryKey, 'rifle');
      expect(mapped.displayColors, ['modrá']);
      expect(mapped.styles, contains('casual'));
      expect(mapped.patterns, ['jednofarebné']);
      expect(mapped.suggestedName.toLowerCase(), contains('rifle'));
    });

    test('sneakers skip canonical parser then fall back to fashion trainers', () {
      final response = addClothingAnalyzerSneakersFixture();
      final mapped = AddClothingAnalyzerMapper.map(response);

      expect(mapped.wardrobeV2!['canonicalType'], 'sneakers');
      expect(mapped.subCategoryKey, 'tenisky_fashion');
      expect(mapped.displayColors, ['biela', 'čierna']);
      expect(mapped.seasons, ['jar', 'leto', 'jeseň']);
      expect(mapped.patterns, ['grafická potlač']);
    });

    test('multicolor profile keeps V2 colorProfile and normalizes form colors', () {
      final response = addClothingAnalyzerMulticolorTopFixture();
      final mapped = AddClothingAnalyzerMapper.map(response);

      expect(
        mapped.wardrobeV2!['colorProfile']['primary']['family'],
        'blue',
      );
      expect(
        mapped.wardrobeV2!['colorProfile']['secondary']['family'],
        'white',
      );
      expect(mapped.displayColors, ['modrá', 'biela', 'červená']);
      expect(mapped.patterns, ['pruhované']);
      expect(mapped.seasons, ['celoročne']);
    });

    test('unknown V2 jacket still uses jacket→hoodie fallback for UI only', () {
      final response = addClothingAnalyzerJacketHoodieGuardFixture();
      final mapped = AddClothingAnalyzerMapper.map(response);

      expect(mapped.usedAuthoritativeV2, isFalse);
      expect(mapped.mappedCanonicalType, 'hoodie');
      expect(mapped.subCategoryKey, 'mikina_s_kapucnou');
      expect(mapped.wardrobeV2!['canonicalType'], 'jacket');
      expect(identical(mapped.wardrobeV2, response['wardrobeV2']), isTrue);
    });
  });

  group('Add Clothing persistence overlay characterization', () {
    test('post-save document keeps server V2 identity and client overlays', () {
      final response = addClothingAnalyzerTShirtFixture();
      final mapped = AddClothingAnalyzerMapper.map(response);
      final saved = AddClothingAnalyzerMapper.characterizePostSaveDocument(
        mapped,
      );

      expect(saved['canonicalType'], 't_shirt');
      expect(saved['canonicalFamily'], mapped.wardrobeV2!['canonicalFamily']);
      expect(saved['bodySlots'], mapped.wardrobeV2!['bodySlots']);
      expect(saved['layerPosition'], mapped.wardrobeV2!['layerPosition']);
      expect(saved['colorProfile'], mapped.wardrobeV2!['colorProfile']);
      expect(saved['warmth'], mapped.wardrobeV2!['warmth']);
      expect(saved['attributes'], mapped.wardrobeV2!['attributes']);
      expect(saved['formality'], mapped.wardrobeV2!['formality']);
      expect(saved['formality'], 3);
      expect(saved['formality'], isNot(2));

      expect(saved['seasons'], mapped.seasons);
      expect(saved['styles'], mapped.styles);
      expect(saved['patterns'], mapped.patterns);
      expect(saved['name'], mapped.suggestedName);
      expect(saved['brand'], mapped.brand);

      for (final field in WardrobeV1Retirement.retiredWardrobeFieldPaths) {
        expect(saved.containsKey(field), isFalse, reason: field);
      }
      expect(saved.containsKey('wardrobeV2'), isFalse);
    });

    test('hoodie guard does not overwrite persisted V2 canonicalType', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerJacketHoodieGuardFixture(),
      );
      final saved = AddClothingAnalyzerMapper.characterizePostSaveDocument(
        mapped,
      );
      expect(mapped.mappedCanonicalType, 'hoodie');
      expect(saved['canonicalType'], 'jacket');
      expect(saved['colorProfile'], mapped.wardrobeV2!['colorProfile']);
    });

    test('untouched AI fill persists the same V2 identity the form displays', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerTShirtFixture(),
      );
      final saved = AddClothingAnalyzerMapper.characterizePostSaveDocument(
        mapped,
      );
      final v2 = mapped.wardrobeV2!;

      expect(mapped.usedAuthoritativeV2, isTrue);
      expect(mapped.mappedCanonicalType, v2['canonicalType']);
      expect(mapped.formalityLevel, v2['formality']);
      expect(mapped.warmthLevel, v2['warmth']);
      expect(
        mapped.displayColors,
        WardrobeV2EditPrepopulation.displayColorsFromProfile(v2['colorProfile']),
      );

      expect(saved['canonicalType'], v2['canonicalType']);
      expect(saved['canonicalFamily'], v2['canonicalFamily']);
      expect(saved['bodySlots'], v2['bodySlots']);
      expect(saved['layerPosition'], v2['layerPosition']);
      expect(saved['colorProfile'], v2['colorProfile']);
      expect(saved['warmth'], v2['warmth']);
      expect(saved['formality'], v2['formality']);
    });

    test('identity keys stay disjoint from named client overlays', () {
      expect(
        AddClothingAnalyzerMapper.serverV2IdentityKeys.intersection(
          AddClothingAnalyzerMapper.clientOverlayKeys,
        ),
        isEmpty,
      );
      expect(
        AddClothingAnalyzerMapper.clientOverlayKeys,
        containsAll(['seasons', 'styles', 'patterns', 'name', 'brand']),
      );
      expect(
        AddClothingAnalyzerMapper.v2KeysCurrentlyOverlaidByClient,
        containsAll(['styles', 'seasons']),
      );
      expect(
        AddClothingAnalyzerMapper.v2KeysCurrentlyOverlaidByClient.contains(
          'formality',
        ),
        isFalse,
      );
    });
  });

  group('Phase 2 V2 form projection authority', () {
    test('V2 canonicalType hoodie wins over jacket bridge/heuristics', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerV2HoodieVsJacketBridgeFixture(),
      );

      expect(mapped.usedAuthoritativeV2, isTrue);
      expect(mapped.wardrobeV2!['canonicalType'], 'hoodie');
      expect(mapped.mappedCanonicalType, 'hoodie');
      expect(mapped.categoryKey, 'mikiny');
      expect(mapped.subCategoryKey, 'mikina_s_kapucnou');
      expect(mapped.kbTypeDisplayName, 'Mikina s kapucňou');
      expect(mapped.displayColors, ['čierna']);
      expect(mapped.suggestedName.toLowerCase(), contains('mikina'));
    });

    test('V2 denim_jacket wins over jacket→hoodie client guard', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerV2DenimJacketVsHoodieGuardFixture(),
      );

      expect(mapped.usedAuthoritativeV2, isTrue);
      expect(mapped.mappedCanonicalType, 'denim_jacket');
      expect(mapped.categoryKey, 'bundy_kabaty');
      expect(mapped.subCategoryKey, 'bunda_riflova');
      expect(mapped.kbTypeDisplayName, 'Rifľová bunda');
      expect(mapped.wardrobeV2!['canonicalType'], 'denim_jacket');
      final saved = AddClothingAnalyzerMapper.characterizePostSaveDocument(
        mapped,
      );
      expect(saved['canonicalType'], 'denim_jacket');
      expect(saved['canonicalFamily'], mapped.wardrobeV2!['canonicalFamily']);
      expect(saved['layerPosition'], 'outer');
    });

    test('V2 puffer_jacket wins over jacket classifier subtype', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerV2PufferVsJacketClassifierFixture(),
      );

      expect(mapped.usedAuthoritativeV2, isTrue);
      expect(mapped.mappedCanonicalType, 'puffer_jacket');
      expect(mapped.subCategoryKey, 'bunda_zimna');
      expect(mapped.seasons, ['jeseň', 'zima']);
      expect(mapped.displayColors, ['tmavomodrá']);
      expect(mapped.warmthLevel, 9);
    });

    test('V2 colorProfile wins over conflicting bridge colors', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerV2ColorConflictFixture(),
      );

      expect(mapped.usedAuthoritativeV2, isTrue);
      expect(
        mapped.wardrobeV2!['colorProfile']['primary']['family'],
        'navy',
      );
      expect(mapped.displayColors, ['tmavomodrá']);
      expect(mapped.suggestedName.toLowerCase(), contains('tričko'));
    });

    test('V2 warmth and formality stay aligned with server identity', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerTShirtFixture(),
      );

      expect(mapped.warmthLevel, mapped.wardrobeV2!['warmth']);
      expect(mapped.formalityLevel, mapped.wardrobeV2!['formality']);
      expect(mapped.formalityLevel, 3);
      expect(mapped.layerRole, isNotEmpty);
    });

    test('Add projection and Edit prepopulation share type/category/color', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerTShirtFixture(),
      );
      final saved = AddClothingAnalyzerMapper.characterizePostSaveDocument(
        mapped,
      );
      final edit = WardrobeV2EditPrepopulation.fromDocument(saved);

      expect(edit.canonicalType, mapped.mappedCanonicalType);
      expect(edit.mainCategory, mapped.mainGroupKey);
      expect(edit.category, mapped.categoryKey);
      expect(edit.subcategory, mapped.subCategoryKey);
      expect(edit.displayColors, mapped.displayColors);
      expect(edit.warmth, mapped.warmthLevel);
      expect(edit.formality, mapped.formalityLevel);
    });

    test('generated name matches V2-backed form type and color', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerV2HoodieVsJacketBridgeFixture(),
      );
      expect(
        mapped.suggestedName,
        AddClothingAnalyzerMapper.computeSuggestedName(
          displayColors: mapped.displayColors,
          subCategoryKey: mapped.subCategoryKey,
          kbTypeDisplayName: mapped.kbTypeDisplayName,
        ),
      );
      expect(mapped.displayColors.first, 'čierna');
      expect(mapped.suggestedName.toLowerCase(), contains('mikina'));
    });
  });

  group('ClothingAnalyzerPipeline shared interpretation', () {
    test('same V2 response agrees on type, colors, and patterns', () {
      final response = addClothingAnalyzerHoodieFixture();
      final add = AddClothingAnalyzerMapper.map(response);
      final pipeline = ClothingAnalyzerPipeline.analyzeResponse(response);

      expect(pipeline.canonicalType, add.mappedCanonicalType);
      expect(pipeline.detectedColors, add.displayColors);
      expect(pipeline.patterns, add.patterns);
      expect(pipeline.categoryKey, add.categoryKey);
      expect(pipeline.subCategoryKey, add.subCategoryKey);
      expect(pipeline.suggestedName, add.suggestedName);
      expect(pipeline.patterns, ['grafická potlač']);
      expect(pipeline.detectedColors, ['čierna']);
    });

    test('puffer jacket subtype matches Add V2 projection', () {
      final response = addClothingAnalyzerPufferJacketFixture();
      final add = AddClothingAnalyzerMapper.map(response);
      final pipeline = ClothingAnalyzerPipeline.analyzeResponse(response);

      expect(pipeline.canonicalType, add.mappedCanonicalType);
      expect(pipeline.subCategoryKey, 'bunda_zimna');
      expect(pipeline.detectedColors, add.displayColors);
      expect(pipeline.detectedColors, ['tmavomodrá']);
    });

    test('sneakers colors and category match Add projection', () {
      final response = addClothingAnalyzerSneakersFixture();
      final add = AddClothingAnalyzerMapper.map(response);
      final pipeline = ClothingAnalyzerPipeline.analyzeResponse(response);

      expect(pipeline.subCategoryKey, add.subCategoryKey);
      expect(pipeline.detectedColors, add.displayColors);
      expect(pipeline.detectedColors, ['biela', 'čierna']);
    });
  });

  group('malformed analyzer responses', () {
    test('missing wardrobeV2 is mapped without throwing; save characterization has no identity', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerMissingWardrobeV2Fixture(),
      );
      expect(mapped.hasWardrobeV2Map, isFalse);
      expect(mapped.mappedCanonicalType, 't_shirt');
      expect(mapped.displayColors, ['biela']);
      final saved = AddClothingAnalyzerMapper.characterizePostSaveDocument(
        mapped,
      );
      expect(saved.containsKey('canonicalType'), isFalse);
    });

    test('malformed wardrobeV2 is not treated as a V2 map', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerMalformedWardrobeV2Fixture(),
      );
      expect(mapped.hasWardrobeV2Map, isFalse);
      expect(mapped.wardrobeV2Raw, 'not-an-object');
      expect(mapped.hiddenAiMetadata['wardrobeV2'], 'not-an-object');
    });

    test('empty colors leave displayColors empty and keep V2 colorProfile', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerEmptyColorsFixture(),
      );
      expect(mapped.displayColors, isEmpty);
      expect(mapped.wardrobeV2!['colorProfile']['primary']['family'], '');
    });

    test('unknown canonical type still passthroughs wardrobeV2', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerUnknownCanonicalFixture(),
      );
      expect(mapped.wardrobeV2!['canonicalType'], 'not_a_real_type');
      expect(mapped.kbMatched, isFalse);
      expect(mapped.mappedCanonicalType, 'not_a_real_type');
    });

    test('missing optional bridge fields still read nested wardrobeV2', () {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerMissingBridgeFieldsFixture(),
      );
      expect(mapped.hasWardrobeV2Map, isTrue);
      expect(mapped.usedAuthoritativeV2, isTrue);
      expect(mapped.wardrobeV2!['canonicalType'], 't_shirt');
      expect(mapped.mappedCanonicalType, 't_shirt');
      expect(mapped.displayColors, ['biela']);
    });

    test('jsonDecode of a V2 envelope preserves wardrobeV2 object identity path', () {
      final encoded = jsonEncode(addClothingAnalyzerTShirtFixture());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final mapped = AddClothingAnalyzerMapper.map(decoded);
      expect(mapped.wardrobeV2, decoded['wardrobeV2']);
      expect(mapped.wardrobeV2!['canonicalType'], 't_shirt');
    });
  });
}
