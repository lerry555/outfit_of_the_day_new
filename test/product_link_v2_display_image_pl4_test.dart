import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/clothing_analyzer_pipeline.dart';
import 'package:outfitofTheDay/Services/product_link_image_cleanup.dart';
import 'package:outfitofTheDay/Services/product_link_v2_display_policy.dart';
import 'package:outfitofTheDay/utils/wardrobe_image_url_priority.dart';

const _uid = 'user-1';
const _base = '1700000000000';
const _storagePath = 'wardrobe/$_uid/$_base.jpg';
const _cleanPath = 'wardrobe_clean/$_uid/$_base.png';
const _productPath = 'wardrobe_product/$_uid/$_base.png';
const _otherProductPath = 'wardrobe_product/$_uid/other.png';
const _remoteSeed = 'https://assets.adidas.com/images/w_600/hoodie.jpg';
const _serperWinner = 'https://img.shopcdn.com/other-garment.jpg';

String _firebaseUrl(String objectPath) {
  return 'https://firebasestorage.googleapis.com/v0/b/'
      'outfitoftheday-4d401.appspot.com/o/'
      '${Uri.encodeComponent(objectPath)}?alt=media';
}

final _ownedUrl = _firebaseUrl(_storagePath);
final _cleanUrl = _firebaseUrl(_cleanPath);
final _studioUrl = _firebaseUrl(_productPath);
final _unrelatedStudioUrl = _firebaseUrl(_otherProductPath);

Map<String, dynamic> _ownedV2Item({
  String? cleanImageUrl,
  String? cutoutImageUrl,
  String? productImageUrl,
  String? cleanStoragePath,
  String? productStoragePath,
  String? originalImageUrl = _remoteSeed,
  Map<String, dynamic>? processing,
  Map<String, dynamic>? colorProfile,
}) {
  return <String, dynamic>{
    'storagePath': _storagePath,
    'imageUrl': _ownedUrl,
    'originalImageUrl': originalImageUrl,
    'productLinkSeedImageUrl': _remoteSeed,
    'sourceUrl': 'https://www.adidas.com/sk/hoodie',
    if (cleanImageUrl != null) 'cleanImageUrl': cleanImageUrl,
    if (cutoutImageUrl != null) 'cutoutImageUrl': cutoutImageUrl,
    if (productImageUrl != null) 'productImageUrl': productImageUrl,
    if (cleanStoragePath != null) 'cleanStoragePath': cleanStoragePath,
    if (productStoragePath != null) 'productStoragePath': productStoragePath,
    if (processing != null) 'processing': processing,
    'canonicalType': 'hoodie',
    'colorProfile': colorProfile ??
        {
          'primary': {'family': 'black', 'hex': '#000000'},
        },
    'warmth': 5,
    'formality': 2,
  };
}

Map<String, dynamic> _legacyProductLinkItem() {
  return <String, dynamic>{
    'sourceUrl': 'https://www.zalando.sk/item',
    'imageUrl': _remoteSeed,
    'originalImageUrl': _remoteSeed,
    'productImageUrl': _serperWinner,
    'processing': {'product': 'done', 'cutout': 'done'},
    'imageProcessingReason': 'searching_better_image',
  };
}

void main() {
  group('canonical source', () {
    test('owned wardrobe/{uid}/... remains the semantic source', () {
      expect(isOwnedV2CanonicalStoragePath(_storagePath), isTrue);
      expect(
        ClothingAnalyzerPipeline.isOwnedAnalyzerStoragePath(_storagePath),
        isTrue,
      );
      expect(ownedV2SourceBasename(_storagePath), _base);
      expect(
        isOwnedV2CanonicalStoragePath('wardrobe_product/$_uid/$_base.png'),
        isFalse,
      );

      final item = _ownedV2Item();
      final pick = pickBestWardrobeImageUrl(item);
      expect(pick.url, _ownedUrl);
      expect(pick.reason, 'imageUrl');
      expect(
        isOwnedV2SameSourceDisplayUrl(item: item, url: _ownedUrl),
        isTrue,
      );
    });
  });

  group('safe same-source derivatives', () {
    test('clean/cutout derived from the owned original may be preferred', () {
      final item = _ownedV2Item(
        cleanImageUrl: _cleanUrl,
        cutoutImageUrl: _cleanUrl,
        cleanStoragePath: _cleanPath,
        processing: {'cutout': 'done', 'product': 'queued'},
      );
      expect(
        isOwnedV2SameSourceDisplayUrl(item: item, url: _cleanUrl),
        isTrue,
      );
      final pick = pickBestWardrobeImageUrl(item);
      expect(pick.url, _cleanUrl);
      expect(pick.reason, 'cutout');
      expect(pickHomeOutfitImageUrl(item).url, _cleanUrl);
    });

    test('same-source studio product photo may still display', () {
      final item = _ownedV2Item(
        cleanImageUrl: _cleanUrl,
        cutoutImageUrl: _cleanUrl,
        cleanStoragePath: _cleanPath,
        productImageUrl: _studioUrl,
        productStoragePath: _productPath,
        processing: {'cutout': 'done', 'product': 'done'},
      );
      expect(canUseProductImageUrl(item), isTrue);
      final pick = pickBestWardrobeImageUrl(item);
      expect(pick.url, _studioUrl);
      expect(pick.reason, 'product_done');
    });
  });

  group('no unproven product-image override', () {
    test('legacy productImageUrl cannot replace owned-V2 source', () {
      final item = _ownedV2Item(
        productImageUrl: _serperWinner,
        processing: {'cutout': 'done', 'product': 'done'},
      );
      expect(canUseProductImageUrl(item), isFalse);
      expect(
        isOwnedV2SameSourceDisplayUrl(item: item, url: _serperWinner),
        isFalse,
      );
      final pick = pickBestWardrobeImageUrl(item);
      expect(pick.url, _ownedUrl);
      expect(pick.reason, 'imageUrl');
      expect(pickHomeOutfitImageUrl(item).url, _ownedUrl);
      expect(
        wardrobeImageUrlCandidates(item),
        isNot(contains(_serperWinner)),
      );
    });

    test('unrelated wardrobe_product object is not treated as same-source', () {
      final item = _ownedV2Item(
        productImageUrl: _unrelatedStudioUrl,
        productStoragePath: _otherProductPath,
        processing: {'product': 'done'},
      );
      expect(canUseProductImageUrl(item), isFalse);
      expect(pickBestWardrobeImageUrl(item).url, _ownedUrl);
    });

    test('unproven cutout URL is ignored in favor of owned original', () {
      final item = _ownedV2Item(
        cutoutImageUrl: _serperWinner,
        cleanImageUrl: _serperWinner,
        processing: {'cutout': 'done'},
      );
      final pick = pickBestWardrobeImageUrl(item);
      expect(pick.url, _ownedUrl);
      expect(pick.reason, 'imageUrl');
    });
  });

  group('color integrity', () {
    test('display processing cannot modify V2 colorProfile', () {
      final rembgPatch = <String, dynamic>{
        'cleanImageUrl': _cleanUrl,
        'cutoutImageUrl': _cleanUrl,
        'cleanStoragePath': _cleanPath,
        'processing': {'cutout': 'done'},
      };
      expect(ownedV2DisplayPatchTouchesIdentity(rembgPatch), isFalse);

      final heuristicPatch = <String, dynamic>{
        'productImageUrl': _serperWinner,
        'colors': ['zelená'],
        'baseColors': ['zelená'],
        'colorHex': ['#008000'],
        'colorProfile': {
          'primary': {'family': 'green'},
        },
        'name': 'Zelená mikina',
      };
      expect(ownedV2DisplayPatchTouchesIdentity(heuristicPatch), isTrue);
      expect(
        heuristicPatch.keys.any(kOwnedV2ProtectedIdentityKeys.contains),
        isTrue,
      );

      final before = Map<String, dynamic>.from(
        _ownedV2Item()['colorProfile'] as Map,
      );
      expect(before['primary']['family'], 'black');
    });
  });

  group('rembg failure', () {
    test('owned original remains valid display fallback', () {
      final item = _ownedV2Item(
        processing: {'cutout': 'error', 'product': 'queued'},
      );
      item['cleanImageUrl'] = null;
      item['cutoutImageUrl'] = null;
      expect(ownedV2KeepsOriginalWhenDerivativeMissing(item), isTrue);
      final pick = pickBestWardrobeImageUrl(item);
      expect(pick.url, _ownedUrl);
      expect(pick.reason, 'imageUrl');
      expect(item['canonicalType'], 'hoodie');
      expect(item['colorProfile']['primary']['family'], 'black');
    });
  });

  group('legacy product-link items', () {
    test('legacy product-done winner still displays without owned storagePath', () {
      final item = _legacyProductLinkItem();
      expect(isOwnedV2CanonicalStoragePath(item['storagePath']?.toString()), isFalse);
      expect(canUseProductImageUrl(item), isTrue);
      final pick = pickBestWardrobeImageUrl(item);
      expect(pick.url, _serperWinner);
      expect(pick.reason, 'product_done');
    });
  });

  group('processing decision', () {
    test('owned-V2 product-link continues to skip the unsafe post-save job', () {
      final decision = decideProductLinkImageProcessing(
        sourceUrl: 'https://www.adidas.com/sk/hoodie',
        selectedImageUrl: _ownedUrl,
        ownedWardrobeStoragePath: _storagePath,
      );
      expect(decision.needsProcessing, isFalse);
      expect(decision.reason, kOwnedV2AnalyzerSourceSkipReason);

      final legacy = decideProductLinkImageProcessing(
        sourceUrl: 'https://www.zalando.sk/item',
        selectedImageUrl: _remoteSeed,
      );
      expect(legacy.needsProcessing, isTrue);
      expect(legacy.reason, 'searching_better_image');
    });
  });
}
