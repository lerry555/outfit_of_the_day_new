import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/add_clothing_analyzer_mapper.dart';
import 'package:outfitofTheDay/Services/add_clothing_v2_save_coordinator.dart';
import 'package:outfitofTheDay/Services/clothing_analyzer_pipeline.dart';
import 'package:outfitofTheDay/Services/product_link_analyzer_service.dart';
import 'package:outfitofTheDay/Services/product_link_image_cleanup.dart';
import 'package:outfitofTheDay/Services/product_link_owned_image_handoff.dart';
import 'package:outfitofTheDay/Services/wardrobe_v2_user_override.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_ontology_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v1_retirement.dart';

import 'add_clothing_analyzer_fixtures.dart';

const _ownedPath = 'wardrobe/user-1/1700000000000.jpg';
const _productNsPath = 'wardrobe_product/user-1/seed.jpg';
const _remoteSeed = 'https://assets.adidas.com/images/w_600/hoodie.jpg';
const _ownedDownloadUrl =
    'https://firebasestorage.googleapis.com/v0/b/outfitoftheday-4d401.appspot.com/o/wardrobe%2Fuser-1%2F1700000000000.jpg?alt=media';

Map<String, dynamic> _pl1BackendFixture({
  String canonicalType = 'hoodie',
  List<String> colors = const ['čierna'],
}) {
  return <String, dynamic>{
    'sourceUrl': 'https://www.adidas.com/sk/hoodie',
    'name': 'Adidas Adicolor Hoodie',
    'brand': 'Adidas',
    'imageUrl': _remoteSeed,
    'productImageUrl': _remoteSeed,
    'originalImageUrl': _remoteSeed,
    'canonical_type': canonicalType,
    'canonicalType': canonicalType,
    'mainGroupKey': 'oblecenie',
    'categoryKey': 'mikiny',
    'subCategoryKey': 'mikina_s_kapucnou',
    'colors': colors,
    'baseColors': colors,
    'colorHex': <String>['#000000'],
    'seasons': <String>['zima'],
    'styles': <String>['streetwear'],
    'patterns': <String>['jednofarebné'],
    'warmth': 7,
    'formality': 2,
    'layer_role': 'mid',
    'canonicalFamily': 'mid_layer',
    'bodySlots': <String>['upper_body'],
    'colorProfile': {
      'primary': {'family': 'black'},
    },
    'wardrobeV2': {
      'canonicalType': canonicalType,
      'canonicalFamily': 'mid_layer',
    },
  };
}

ProductLinkAnalysis _pageFromPl1() => mapProductLinkSourcePageResponse(
      _pl1BackendFixture(),
      fallbackSourceUrl: 'https://www.adidas.com/sk/hoodie',
    );

Map<String, dynamic> _pl3SaveMerge({
  required ProductLinkAnalysis page,
  required AddClothingAnalyzerMapperResult mapped,
  WardrobeV2UserOverrideResult? override,
}) {
  final v2 = Map<String, dynamic>.from(
    override?.payload ?? mapped.wardrobeV2!,
  );
  final hidden = Map<String, dynamic>.from(mapped.hiddenAiMetadata)
    ..remove('wardrobeV2');
  if (override?.typeOverrideApplied == true) hidden.remove('formality');
  return WardrobeV1Retirement.stripRetiredFields({
    ...v2,
    'name': mapped.suggestedName,
    'brand': preferProductLinkBrand(
      existingBrand: page.brand ?? '',
      analyzerBrand: mapped.brand,
    ),
    'sourceUrl': page.sourceUrl,
    'productPageTitle': page.name,
    'seasons': mapped.seasons,
    'styles': mapped.styles,
    'patterns': mapped.patterns,
    ...hidden,
  });
}

void main() {
  late WardrobeOntologyV2 ontology;

  setUpAll(() {
    ontology = WardrobeOntologyV2.fromJsonString(
      File('assets/data/wardrobe_ontology_v2.json').readAsStringSync(),
    );
  });

  group('owned image analysis source', () {
    test('valid wardrobe/{uid}/ path is allowed as PL-3 analyzer source', () {
      expect(
        ClothingAnalyzerPipeline.requireOwnedAnalyzerStoragePath(_ownedPath),
        _ownedPath,
      );
      expect(
        ClothingAnalyzerPipeline.isOwnedAnalyzerStoragePath(_ownedPath),
        isTrue,
      );
      final body = ClothingAnalyzerPipeline.buildAnalyzeRequestBody(
        storagePath: _ownedPath,
        imageUrl: _ownedDownloadUrl,
      );
      expect(body['storagePath'], _ownedPath);
      expect(body['imageUrl'], _ownedDownloadUrl);
    });

    test('wardrobe_product/{uid}/ must not be used as PL-3 analyzer source', () {
      expect(
        ClothingAnalyzerPipeline.isOwnedAnalyzerStoragePath(_productNsPath),
        isFalse,
      );
      expect(
        () => ClothingAnalyzerPipeline.buildAnalyzeRequestBody(
          storagePath: _productNsPath,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('remote seed URL is not analyzer authority', () {
      expect(
        ClothingAnalyzerPipeline.storagePathFromFirebaseUrl(_remoteSeed),
        isNull,
      );
      expect(
        () => ClothingAnalyzerPipeline.buildAnalyzeRequestBody(
          storagePath: _remoteSeed,
        ),
        throwsA(isA<Exception>()),
      );
      final body = ClothingAnalyzerPipeline.buildAnalyzeRequestBody(
        storagePath: _ownedPath,
        imageUrl: _remoteSeed,
      );
      expect(body['storagePath'], _ownedPath);
      expect(body.containsKey('imageUrl'), isFalse);
      expect(body.values, isNot(contains(_remoteSeed)));
    });

    test('PL-3 uses the same wardrobe-analyzer-v2 contract as photo Add', () {
      expect(
        ClothingAnalyzerPipeline.contractVersion,
        'wardrobe-analyzer-v2',
      );
      expect(
        ClothingAnalyzerPipeline.analyzeEndpoint,
        'https://us-east1-outfitoftheday-4d401.cloudfunctions.net/analyzeClothingImage',
      );
      final body = ClothingAnalyzerPipeline.buildAnalyzeRequestBody(
        storagePath: _ownedPath,
        imageUrl: _ownedDownloadUrl,
      );
      expect(body['contractVersion'], 'wardrobe-analyzer-v2');
      expect(body.keys, unorderedEquals(['contractVersion', 'storagePath', 'imageUrl']));
    });
  });

  group('analyzer mapping and metadata merge', () {
    test('fixture response maps to the same V2 form identity as photo Add', () {
      final response = addClothingAnalyzerHoodieFixture();
      final mapped = AddClothingAnalyzerMapper.map(response);
      expect(mapped.wardrobeV2!['canonicalType'], 'hoodie');
      expect(mapped.mappedCanonicalType, 'hoodie');
      expect(mapped.subCategoryKey, 'mikina_s_kapucnou');
      expect(mapped.categoryKey, 'mikiny');
      expect(mapped.displayColors, ['čierna']);
      expect(mapped.warmthLevel, 5);
      expect(mapped.formalityLevel, 2);
      expect(mapped.usedAuthoritativeV2, isTrue);
      expect(mapped.hiddenAiMetadata['wardrobeV2'], mapped.wardrobeV2);
    });

    test('product title, brand, and source URL survive analyzer fill', () {
      final page = _pageFromPl1();
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerHoodieFixture(),
      );
      expect(mapped.brand, isEmpty);
      final saved = _pl3SaveMerge(page: page, mapped: mapped);
      expect(saved['brand'], 'Adidas');
      expect(saved['sourceUrl'], 'https://www.adidas.com/sk/hoodie');
      expect(saved['productPageTitle'], 'Adidas Adicolor Hoodie');
      expect(saved['canonicalType'], 'hoodie');
      expect(preferProductLinkBrand(existingBrand: 'Nike', analyzerBrand: ''), 'Nike');
      expect(
        preferProductLinkBrand(existingBrand: '', analyzerBrand: 'Puma'),
        'Puma',
      );
    });
  });

  group('save and analyzer failure', () {
    test('successful analyzer result enables normal V2 save', () async {
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerHoodieFixture(),
      );
      final v2 = Map<String, dynamic>.from(mapped.wardrobeV2!);
      expect(validateAddClothingV2Payload(v2).isValid, isTrue);
      final coordinator = AddClothingV2SaveCoordinator();
      final order = <String>[];
      await coordinator.persist(
        v2Payload: v2,
        write: () async {
          order.add('write');
          return 'item-pl3';
        },
        afterWrite: (_) async => order.add('after'),
        navigateAfterSave: (_) => order.add('navigate'),
      );
      expect(order, ['write', 'after', 'navigate']);
    });

    test('analyzer failure keeps Save blocked and owned image retryable', () {
      final page = _pageFromPl1();
      expect(validateAddClothingV2Payload(page.toInitialData()).isValid, isFalse);
      expect(page.toInitialData().containsKey('wardrobeV2'), isFalse);
      expect(
        ClothingAnalyzerPipeline.isOwnedAnalyzerStoragePath(_ownedPath),
        isTrue,
      );
      expect(
        productLinkFailureRetryKind(
          hasOwnedAnalyzerSource: true,
          imageHandoffFailed: false,
        ),
        ProductLinkFailureRetryKind.analyzer,
      );
      expect(
        productLinkFailureRetryKind(
          hasOwnedAnalyzerSource: false,
          imageHandoffFailed: true,
        ),
        ProductLinkFailureRetryKind.imageHandoff,
      );
      expect(
        productLinkFailureRetryKind(
          hasOwnedAnalyzerSource: false,
          imageHandoffFailed: false,
        ),
        ProductLinkFailureRetryKind.metadata,
      );
    });
  });

  group('user correction and identity isolation', () {
    test('PL-3 hoodie → user jacket persists corrected V2 identity', () {
      final page = _pageFromPl1();
      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerHoodieFixture(),
      );
      final override = WardrobeV2UserOverride.apply(
        original: Map<String, dynamic>.from(mapped.wardrobeV2!),
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'bunda_riflova',
        selectedCategory: 'bundy_kabaty',
        currentCanonicalType: 'hoodie',
      );
      expect(override.typeOverrideApplied, isTrue);
      expect(override.payload['canonicalType'], 'denim_jacket');
      expect(override.payload['canonicalFamily'], 'outerwear');
      final saved = _pl3SaveMerge(
        page: page,
        mapped: mapped,
        override: override,
      );
      expect(saved['canonicalType'], 'denim_jacket');
      expect(saved['brand'], 'Adidas');
      expect(saved['sourceUrl'], 'https://www.adidas.com/sk/hoodie');
    });

    test('PL-1 legacy identity cannot poison PL-3 V2 save', () {
      final page = _pageFromPl1();
      final pageData = page.toInitialData();
      expect(pageData.containsKey('canonical_type'), isFalse);
      expect(pageData.containsKey('canonicalType'), isFalse);
      expect(pageData.containsKey('colors'), isFalse);
      expect(pageData.containsKey('colorProfile'), isFalse);
      expect(pageData.containsKey('wardrobeV2'), isFalse);
      expect(pageData.containsKey('warmth'), isFalse);
      expect(pageData.containsKey('formality'), isFalse);

      final mapped = AddClothingAnalyzerMapper.map(
        addClothingAnalyzerJeansFixture(),
      );
      final saved = _pl3SaveMerge(page: page, mapped: mapped);
      expect(saved['canonicalType'], 'jeans');
      expect(saved['canonicalFamily'], 'bottom');
      expect(saved['colorProfile']['primary']['family'], 'blue');
      expect(saved['warmth'], 5);
      expect(saved['formality'], 3);
      expect(saved['canonicalType'], isNot('hoodie'));
      expect(saved['brand'], 'Adidas');
      expect(saved['sourceUrl'], page.sourceUrl);
    });
  });

  group('post-save product-link image job', () {
    test('owned V2 analyzer source disables heuristic color-patch job', () {
      final owned = decideProductLinkImageProcessing(
        sourceUrl: 'https://www.adidas.com/sk/hoodie',
        selectedImageUrl: _ownedDownloadUrl,
        ownedWardrobeStoragePath: _ownedPath,
      );
      expect(owned.needsProcessing, isFalse);
      expect(owned.reason, 'owned_v2_analyzer_source');

      final productNs = decideProductLinkImageProcessing(
        sourceUrl: 'https://www.adidas.com/sk/hoodie',
        selectedImageUrl: _remoteSeed,
        ownedWardrobeStoragePath: _productNsPath,
      );
      expect(productNs.reason, isNot('owned_v2_analyzer_source'));

      final legacy = decideProductLinkImageProcessing(
        sourceUrl: 'https://www.adidas.com/sk/hoodie',
        selectedImageUrl: _remoteSeed,
      );
      expect(legacy.needsProcessing, isTrue);
      expect(legacy.reason, 'searching_better_image');
    });
  });
}
