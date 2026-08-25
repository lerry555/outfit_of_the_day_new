import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/add_clothing_v2_save_coordinator.dart';
import 'package:outfitofTheDay/Services/product_link_analyzer_service.dart';
import 'package:outfitofTheDay/Services/product_link_url_fallback.dart';
import 'package:outfitofTheDay/screens/add_clothing_screen.dart';
import 'package:outfitofTheDay/utils/product_link_image_resolve.dart';
import 'package:outfitofTheDay/utils/product_link_url_sanitize.dart';

Map<String, dynamic> backendSourcePageFixture({
  String? name = 'Adidas Adicolor Hoodie',
  String? brand = 'Adidas',
  String? imageUrl =
      'https://assets.adidas.com/images/w_600/hoodie.jpg',
  bool includeLegacyIdentity = true,
}) {
  return <String, dynamic>{
    'sourceUrl': 'https://www.adidas.com/sk/hoodie',
    'name': name,
    'brand': brand,
    'imageUrl': imageUrl,
    'productImageUrl': imageUrl,
    'originalImageUrl': imageUrl,
    if (includeLegacyIdentity) ...<String, dynamic>{
      'canonical_type': 'hoodie',
      'canonicalType': 'hoodie',
      'mainGroupKey': 'oblecenie',
      'categoryKey': 'mikiny',
      'subCategoryKey': 'mikina_s_kapucnou',
      'colors': <String>['čierna'],
      'baseColors': <String>['čierna'],
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
        'canonicalType': 'hoodie',
        'canonicalFamily': 'mid_layer',
      },
    },
  };
}

void main() {
  tearDown(() {
    debugOverrideProductLinkAnalyzerService(null);
  });

  group('URL normalization', () {
    test('strips tracking params from product URLs', () {
      const raw =
          'https://www.zalando.sk/item?utm_source=ig&utm_medium=cpc&gclid=abc&color=black';
      expect(
        canonicalProductLinkUrl(raw),
        'https://www.zalando.sk/item?color=black',
      );
      expect(
        normalizeProductLinkUrl(raw),
        'https://www.zalando.sk/item?color=black',
      );
      expect(
        canonicalProductLinkUrl(
          'https://www.adidas.com/sk/hoodie?utm_source=x',
        ),
        'https://www.adidas.com/sk/hoodie',
      );
    });

    test('rejects invalid product URLs', () {
      expect(isValidProductLinkUrl(''), isFalse);
      expect(isValidProductLinkUrl('not-a-url'), isTrue);
      expect(isValidProductLinkUrl('https://aboutyou.sk/p/hoodie'), isTrue);
      expect(isValidProductLinkUrl('ftp://example.com/x'), isFalse);
    });
  });

  group('source-page-only request', () {
    test('live service sends only url + sourcePageOnly true', () async {
      Map<String, dynamic>? captured;
      final client = ProductLinkAnalyzerService(
        transport: (payload) async {
          captured = Map<String, dynamic>.from(payload);
          return backendSourcePageFixture();
        },
      );

      await client.fetchSourcePage(
        'https://www.adidas.com/sk/hoodie?utm_source=x',
      );

      expect(captured, isNotNull);
      expect(captured!.keys, unorderedEquals(['url', 'sourcePageOnly']));
      expect(captured!['sourcePageOnly'], isTrue);
      expect(captured!['url'], 'https://www.adidas.com/sk/hoodie');
      expect(captured!.containsKey('imageCleanupOnly'), isFalse);
      expect(captured!.containsKey('metadataOnly'), isFalse);
    });

    test('request builder refuses identity-capable flags', () {
      expect(
        () => assertProductLinkSourcePageOnlyRequest({
          'url': 'https://example.com',
          'sourcePageOnly': false,
        }),
        throwsStateError,
      );
      expect(
        () => assertProductLinkSourcePageOnlyRequest({
          'url': 'https://example.com',
          'sourcePageOnly': true,
          'imageCleanupOnly': true,
        }),
        throwsStateError,
      );
    });
  });

  group('metadata mapping', () {
    test('maps backend title, brand, and seed image', () {
      final mapped = mapProductLinkSourcePageResponse(
        backendSourcePageFixture(),
        fallbackSourceUrl: 'https://www.adidas.com/sk/hoodie',
      );

      expect(mapped.name, 'Adidas Adicolor Hoodie');
      expect(mapped.brand, 'Adidas');
      expect(mapped.sourceUrl, 'https://www.adidas.com/sk/hoodie');
      expect(
        resolveProductLinkImageUrl(mapped),
        'https://assets.adidas.com/images/w_600/hoodie.jpg',
      );
      expect(mapped.missingImage, isFalse);
      expect(mapped.sourcePageOnly, isTrue);
    });

    test('partial metadata without brand/title/image does not crash', () {
      final mapped = mapProductLinkSourcePageResponse(
        <String, dynamic>{'sourceUrl': 'https://shop.example/p/1'},
        fallbackSourceUrl: 'https://shop.example/p/1',
      );
      expect(mapped.name, kProductLinkGenericName);
      expect(mapped.brand, isNull);
      expect(resolveProductLinkImageUrl(mapped), isNull);
      expect(mapped.partial, isTrue);
      expect(mapped.missingImage, isTrue);
      expect(mapped.toInitialData()['sourceUrl'], 'https://shop.example/p/1');
    });
  });

  group('identity isolation', () {
    test('legacy backend identity fields do not enter form prefill', () {
      final mapped = mapProductLinkSourcePageResponse(
        backendSourcePageFixture(),
        fallbackSourceUrl: 'https://www.adidas.com/sk/hoodie',
      );
      final data = mapped.toInitialData();

      for (final key in kProductLinkIgnoredIdentityKeys) {
        expect(data.containsKey(key), isFalse, reason: key);
      }
      expect(mapped.canonicalType, isNull);
      expect(mapped.mainGroupKey, isNull);
      expect(mapped.categoryKey, isNull);
      expect(mapped.subCategoryKey, isNull);
      expect(mapped.colors, isEmpty);
      expect(data.containsKey('wardrobeV2'), isFalse);
      expect(data.containsKey('canonical_type'), isFalse);
      expect(data.containsKey('categoryKey'), isFalse);
      expect(data.containsKey('colors'), isFalse);
    });

    test('URL fallback identity cannot leak through toInitialData', () {
      final fallback = ProductLinkUrlFallback.detect(
        'https://www.adidas.com/hoodie-black',
      );
      expect(fallback.subCategoryKey, isNotNull);
      final data = fallback.toInitialData();
      expect(data.containsKey('canonical_type'), isFalse);
      expect(data.containsKey('mainGroupKey'), isFalse);
      expect(data.containsKey('categoryKey'), isFalse);
      expect(data.containsKey('subCategoryKey'), isFalse);
      expect(data.containsKey('colors'), isFalse);
      expect(data.containsKey('wardrobeV2'), isFalse);
    });

    test('PL-1 metadata cannot satisfy V2 save validation', () {
      final mapped = mapProductLinkSourcePageResponse(
        backendSourcePageFixture(),
        fallbackSourceUrl: 'https://www.adidas.com/sk/hoodie',
      );
      expect(
        validateAddClothingV2Payload(mapped.toInitialData()).isValid,
        isFalse,
      );
      expect(
        validateAddClothingV2Payload(
          mapped.toInitialData()['wardrobeV2'] is Map
              ? Map<String, dynamic>.from(
                  mapped.toInitialData()['wardrobeV2'] as Map,
                )
              : const <String, dynamic>{},
        ).isValid,
        isFalse,
      );
    });
  });

  group('failure', () {
    test('callable not-found is surfaced and is not fake success', () async {
      final client = ProductLinkAnalyzerService(
        transport: (_) async {
          throw FirebaseFunctionsException(
            code: 'not-found',
            message: 'analyzeClothingProductUrl',
          );
        },
      );

      final outcome = await client.analyzeForForm(
        'https://www.adidas.com/sk/hoodie',
      );
      expect(outcome.callableNotFound, isTrue);
      expect(outcome.fetchFailed, isTrue);
      expect(outcome.remoteAiUsed, isFalse);
      expect(outcome.sourcePageOnly, isTrue);
      expect(outcome.analysis.missingImage, isTrue);
      expect(outcome.analysis.canonicalType, isNull);
      expect(outcome.analysis.toInitialData().containsKey('subCategoryKey'),
          isFalse);
    });

    test('generic fetch failure does not invent clothing identity', () async {
      final client = ProductLinkAnalyzerService(
        transport: (_) async {
          throw FirebaseFunctionsException(
            code: 'internal',
            message: 'fetch failed',
          );
        },
      );
      final outcome = await client.analyzeForForm(
        'https://www.adidas.com/sk/hoodie',
      );
      expect(outcome.fetchFailed, isTrue);
      expect(outcome.callableNotFound, isFalse);
      expect(outcome.remoteAiUsed, isFalse);
      expect(outcome.analysis.colors, isEmpty);
      expect(outcome.analysis.subCategoryKey, isNull);
    });

    test('prefetched metadata skips a second callable', () async {
      var calls = 0;
      final client = ProductLinkAnalyzerService(
        transport: (_) async {
          calls++;
          return backendSourcePageFixture();
        },
      );
      final prefetched = await client.fetchSourcePage(
        'https://www.adidas.com/sk/hoodie',
      );
      final outcome = await client.analyzeForForm(
        'https://www.adidas.com/sk/hoodie',
        skipMetadataFetch: true,
        prefetchedMetadata: prefetched,
      );
      expect(calls, 1);
      expect(outcome.fetchFailed, isFalse);
      expect(outcome.analysis.name, 'Adidas Adicolor Hoodie');
    });
  });
}
