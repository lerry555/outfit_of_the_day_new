import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/add_clothing_analyzer_mapper.dart';
import 'package:outfitofTheDay/Services/clothing_analyzer_pipeline.dart';
import 'package:outfitofTheDay/Services/wardrobe_reanalyze_apply_service.dart';
import 'package:outfitofTheDay/Services/wardrobe_reanalyze_dry_run_service.dart';
import 'package:outfitofTheDay/Services/wardrobe_v2_user_override.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_ontology_v2.dart';

import 'add_clothing_analyzer_fixtures.dart';

void main() {
  late WardrobeOntologyV2 ontology;

  setUpAll(() {
    ontology = WardrobeOntologyV2.fromJsonString(
      File('assets/data/wardrobe_ontology_v2.json').readAsStringSync(),
    );
  });

  Map<String, dynamic> v2Of(Map<String, dynamic> response) =>
      Map<String, dynamic>.from(response['wardrobeV2'] as Map);

  group('interpretation parity', () {
    test('logo_print is interpreted the same as Add', () {
      final response = addClothingAnalyzerHoodieFixture();
      final add = AddClothingAnalyzerMapper.map(response);
      final pipeline = ClothingAnalyzerPipeline.analyzeResponse(response);
      expect(add.patterns, ['grafická potlač']);
      expect(pipeline.patterns, add.patterns);
      expect(pipeline.canonicalType, add.mappedCanonicalType);
      expect(pipeline.detectedColors, add.displayColors);
    });
  });

  group('metadata apply contract', () {
    test('allowed patch never includes V2 identity keys', () {
      final pipeline = ClothingAnalyzerPipeline.analyzeResponse(
        addClothingAnalyzerHoodieFixture(),
      );
      final fields = WardrobeReanalyzeApplyService.metadataFieldsFromPipeline(
        pipeline,
      );
      expect(
        fields.keys.toSet().intersection(
          WardrobeReanalyzeApplyService.protectedIdentityKeys,
        ),
        isEmpty,
      );
      expect(
        fields.keys.every(
          WardrobeReanalyzeApplyService.allowedMetadataKeys.contains,
        ),
        isTrue,
      );
      expect(fields.containsKey('canonicalType'), isFalse);
      expect(fields.containsKey('colorProfile'), isFalse);
      expect(fields.containsKey('warmth'), isFalse);
      expect(fields.containsKey('formality'), isFalse);
      expect(fields['patterns'], ['grafická potlač']);
      expect(fields['confidence'], 98);
    });

    test('allowed metadata still updates on a stored item', () {
      final stored = {
        ...v2Of(addClothingAnalyzerHoodieFixture()),
        'patterns': ['jednofarebné'],
        'visual_description': 'old',
      };
      final response = Map<String, dynamic>.from(
        addClothingAnalyzerHoodieFixture(),
      );
      response['visual_description'] = 'black hoodie with logo';
      response['logo_prominence'] = 'high';
      response['visual_identity'] = 'graphic hoodie';
      final pipeline = ClothingAnalyzerPipeline.analyzeResponse(response);
      final merged = WardrobeReanalyzeApplyService.mergeMetadataPatch(
        stored,
        WardrobeReanalyzeApplyService.metadataFieldsFromPipeline(pipeline),
      );
      expect(merged['patterns'], ['grafická potlač']);
      expect(merged['visual_description'], 'black hoodie with logo');
      expect(merged['logo_prominence'], 'high');
      expect(merged['visual_identity'], 'graphic hoodie');
      expect(merged['canonicalType'], 'hoodie');
    });

    test('user-corrected jacket identity survives hoodie reanalyze', () {
      final original = v2Of(addClothingAnalyzerHoodieFixture());
      final corrected = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'bunda_riflova',
        selectedCategory: 'bundy_kabaty',
        currentCanonicalType: 'hoodie',
      ).payload;
      expect(corrected['canonicalType'], 'denim_jacket');

      final analyzerSaysHoodie = addClothingAnalyzerHoodieFixture();
      final pipeline = ClothingAnalyzerPipeline.analyzeResponse(
        analyzerSaysHoodie,
      );
      expect(pipeline.canonicalType, 'hoodie');

      final merged = WardrobeReanalyzeApplyService.mergeMetadataPatch(
        corrected,
        WardrobeReanalyzeApplyService.metadataFieldsFromPipeline(pipeline),
      );
      expect(merged['canonicalType'], 'denim_jacket');
      expect(merged['canonicalFamily'], 'outerwear');
      expect(merged['bodySlots'], ['upper_body']);
      expect(merged['layerPosition'], 'outer');
      expect(merged['fieldSources']['canonicalType'], 'user_correction');
      expect(merged['userOverrideFields'], contains('canonicalType'));
      expect(merged['patterns'], pipeline.patterns);
    });

    test('user-corrected red colorProfile survives white reanalyze', () {
      final original = v2Of(addClothingAnalyzerTShirtFixture());
      final corrected = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        colorEdited: true,
        selectedDisplayColors: const ['červená'],
      ).payload;
      expect(corrected['colorProfile']['primary']['family'], 'red');

      final analyzerSaysWhite = addClothingAnalyzerTShirtFixture();
      final pipeline = ClothingAnalyzerPipeline.analyzeResponse(
        analyzerSaysWhite,
      );
      expect(pipeline.detectedColors.first, 'biela');

      final merged = WardrobeReanalyzeApplyService.mergeMetadataPatch(
        corrected,
        WardrobeReanalyzeApplyService.metadataFieldsFromPipeline(pipeline),
      );
      expect(merged['colorProfile']['primary']['family'], 'red');
      expect(merged['fieldSources']['colorProfile'], 'user_correction');
      expect(merged['canonicalType'], 't_shirt');
    });
  });

  group('dry-run', () {
    test('review fields do not mutate stored item state', () {
      final stored = {
        ...v2Of(addClothingAnalyzerHoodieFixture()),
        'name': 'Čierna mikina s kapucňou',
        'patterns': ['jednofarebné'],
      };
      final before = Map<String, dynamic>.from(stored);
      final pipeline = ClothingAnalyzerPipeline.analyzeResponse(
        addClothingAnalyzerHoodieFixture(),
      );
      final old = WardrobeReanalyzeFields.fromStored(stored);
      final neu = WardrobeReanalyzeFields.fromPipeline(pipeline);
      expect(stored, before);
      expect(old.canonicalType, 'hoodie');
      expect(neu.canonicalType, pipeline.canonicalType);
      expect(neu.patterns, pipeline.patterns);
    });
  });
}
