import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:outfitofTheDay/Services/add_clothing_v2_save_coordinator.dart';
import 'package:outfitofTheDay/Services/product_link_owned_image_handoff.dart';
import 'package:outfitofTheDay/utils/add_clothing_image_prep.dart';

Uint8List _tinyJpeg() {
  final image = img.Image(width: 12, height: 10);
  img.fill(image, color: img.ColorRgb8(30, 60, 90));
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

void main() {
  group('validateProductLinkImageResponse', () {
    test('accepts 2xx image bytes within size', () {
      final jpeg = _tinyJpeg();
      expect(
        validateProductLinkImageResponse(
          statusCode: 200,
          contentType: 'image/jpeg',
          bytes: jpeg,
        ),
        isNull,
      );
    });

    test('rejects HTML content type', () {
      expect(
        validateProductLinkImageResponse(
          statusCode: 200,
          contentType: 'text/html; charset=utf-8',
          bytes: Uint8List.fromList('<html>not an image</html>'.codeUnits),
        ),
        ProductLinkImageHandoffError.notImage,
      );
    });

    test('rejects empty bytes', () {
      expect(
        validateProductLinkImageResponse(
          statusCode: 200,
          contentType: 'image/jpeg',
          bytes: Uint8List(0),
        ),
        ProductLinkImageHandoffError.empty,
      );
    });

    test('rejects oversize payloads', () {
      expect(
        validateProductLinkImageResponse(
          statusCode: 200,
          contentType: 'image/jpeg',
          bytes: Uint8List(kProductLinkImageMaxBytes + 1),
        ),
        ProductLinkImageHandoffError.oversize,
      );
    });

    test('rejects HTTP errors', () {
      expect(
        validateProductLinkImageResponse(
          statusCode: 404,
          contentType: 'image/jpeg',
          bytes: _tinyJpeg(),
        ),
        ProductLinkImageHandoffError.httpError,
      );
    });
  });

  group('owned wardrobe path', () {
    test('builds wardrobe/{uid}/... and never wardrobe_product/', () {
      final path = buildOwnedWardrobeImagePath(
        uid: 'user-1',
        timestampMs: 1700000000000,
      );
      expect(path, 'wardrobe/user-1/1700000000000.jpg');
      expect(isOwnedWardrobeStoragePath(path, uid: 'user-1'), isTrue);
      expect(path.startsWith('wardrobe_product/'), isFalse);
      expect(isOwnedWardrobeStoragePath(path, uid: 'other'), isFalse);
    });
  });

  group('handoff', () {
    test('uploads normalized jpeg under owned wardrobe path', () async {
      final jpeg = _tinyJpeg();
      String? uploadedPath;
      String? uploadedType;
      final handoff = ProductLinkOwnedImageHandoff(
        httpGet: (uri) async {
          expect(uri.toString(), 'https://cdn.example/a.jpg');
          return ProductLinkImageHttpResponse(
            statusCode: 200,
            contentType: 'image/jpeg',
            body: jpeg,
          );
        },
        normalize: (bytes) async => prepareJpgForUpload({
          'bytes': bytes,
          'maxSide': kAddClothingUploadMaxSide,
          'quality': kAddClothingUploadJpegQuality,
        }),
        upload: ({
          required storagePath,
          required bytes,
          required contentType,
        }) async {
          uploadedPath = storagePath;
          uploadedType = contentType;
          expect(bytes, isNotEmpty);
          return 'https://firebasestorage.googleapis.com/v0/b/app/o/${Uri.encodeComponent(storagePath)}';
        },
      );

      const source = 'https://shop.example/p/hoodie?utm_source=ig';
      final result = await handoff.run(
        uid: 'user-1',
        sourceUrl: source,
        seedImageUrl: 'https://cdn.example/a.jpg',
        timestampMs: 1700000000123,
      );

      expect(result.sourceUrl, 'https://shop.example/p/hoodie');
      expect(result.seedImageUrl, 'https://cdn.example/a.jpg');
      expect(result.storagePath, 'wardrobe/user-1/1700000000123.jpg');
      expect(result.storagePath.startsWith('wardrobe/user-1/'), isTrue);
      expect(result.storagePath.startsWith('wardrobe_product/'), isFalse);
      expect(uploadedPath, result.storagePath);
      expect(uploadedType, 'image/jpeg');
      expect(result.ownedImageUrl, contains('wardrobe%2Fuser-1%2F'));
      expect(productLinkHandoffContainsIdentity(result.toMap()), isFalse);
      expect(result.toMap().containsKey('wardrobeV2'), isFalse);
      expect(result.toMap().containsKey('canonicalType'), isFalse);
      expect(result.toMap().containsKey('colors'), isFalse);
      expect(result.toMap().containsKey('warmth'), isFalse);
      expect(result.toMap().containsKey('formality'), isFalse);
      expect(validateAddClothingV2Payload(result.toMap()).isValid, isFalse);
    });

    test('preserves canonical source URL after image handoff', () async {
      final jpeg = _tinyJpeg();
      final handoff = ProductLinkOwnedImageHandoff(
        httpGet: (_) async => ProductLinkImageHttpResponse(
          statusCode: 200,
          contentType: 'image/png',
          body: jpeg,
        ),
        normalize: (bytes) async => bytes,
        upload: ({
          required storagePath,
          required bytes,
          required contentType,
        }) async => 'https://owned.example/$storagePath',
      );
      final result = await handoff.run(
        uid: 'owner',
        sourceUrl: 'https://zara.com/item?fbclid=abc',
        seedImageUrl: 'https://static.zara.net/photo.jpg',
        timestampMs: 1,
      );
      expect(result.sourceUrl, 'https://zara.com/item');
      expect(result.seedImageUrl, isNot(result.sourceUrl));
      expect(result.ownedImageUrl, isNot(result.seedImageUrl));
    });

    test('rejects HTML download before upload', () async {
      var uploaded = false;
      final handoff = ProductLinkOwnedImageHandoff(
        httpGet: (_) async => ProductLinkImageHttpResponse(
          statusCode: 200,
          contentType: 'text/html',
          body: Uint8List.fromList('<html>login</html>'.codeUnits),
        ),
        upload: ({
          required storagePath,
          required bytes,
          required contentType,
        }) async {
          uploaded = true;
          return 'https://owned.example/x';
        },
      );
      await expectLater(
        handoff.run(
          uid: 'user-1',
          sourceUrl: 'https://shop.example/p/1',
          seedImageUrl: 'https://cdn.example/a.jpg',
        ),
        throwsA(
          isA<ProductLinkImageHandoffException>().having(
            (e) => e.kind,
            'kind',
            ProductLinkImageHandoffError.notImage,
          ),
        ),
      );
      expect(uploaded, isFalse);
    });

    test('rejects HTTP errors before upload', () async {
      var uploaded = false;
      final handoff = ProductLinkOwnedImageHandoff(
        httpGet: (_) async => ProductLinkImageHttpResponse(
          statusCode: 500,
          contentType: 'image/jpeg',
          body: _tinyJpeg(),
        ),
        upload: ({
          required storagePath,
          required bytes,
          required contentType,
        }) async {
          uploaded = true;
          return 'https://owned.example/x';
        },
      );
      await expectLater(
        handoff.run(
          uid: 'user-1',
          sourceUrl: 'https://shop.example/p/1',
          seedImageUrl: 'https://cdn.example/a.jpg',
        ),
        throwsA(
          isA<ProductLinkImageHandoffException>().having(
            (e) => e.kind,
            'kind',
            ProductLinkImageHandoffError.httpError,
          ),
        ),
      );
      expect(uploaded, isFalse);
    });

    test('maps timeout to a handoff timeout error', () async {
      final handoff = ProductLinkOwnedImageHandoff(
        httpGet: (_) async => throw TimeoutException('download'),
      );
      await expectLater(
        handoff.run(
          uid: 'user-1',
          sourceUrl: 'https://shop.example/p/1',
          seedImageUrl: 'https://cdn.example/a.jpg',
        ),
        throwsA(
          isA<ProductLinkImageHandoffException>().having(
            (e) => e.kind,
            'kind',
            ProductLinkImageHandoffError.timeout,
          ),
        ),
      );
    });

    test('missing seed image does not upload', () async {
      var uploaded = false;
      final handoff = ProductLinkOwnedImageHandoff(
        upload: ({
          required storagePath,
          required bytes,
          required contentType,
        }) async {
          uploaded = true;
          return 'https://owned.example/x';
        },
      );
      await expectLater(
        handoff.run(
          uid: 'user-1',
          sourceUrl: 'https://shop.example/p/1',
          seedImageUrl: '',
        ),
        throwsA(
          isA<ProductLinkImageHandoffException>().having(
            (e) => e.kind,
            'kind',
            ProductLinkImageHandoffError.noSeedImage,
          ),
        ),
      );
      expect(uploaded, isFalse);
    });
  });
}
