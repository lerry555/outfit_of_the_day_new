import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../utils/add_clothing_image_prep.dart';
import '../utils/product_link_image_resolve.dart';
import '../utils/product_link_url_sanitize.dart';
import 'product_link_analyzer_service.dart';

/// Conservative download cap before JPEG normalization.
/// Photo Add already resizes to 1600px / q88; 8 MiB rejects huge CDN originals.
const int kProductLinkImageMaxBytes = 8 * 1024 * 1024;
const Duration kProductLinkImageDownloadTimeout = Duration(seconds: 20);
const Duration kProductLinkImageUploadTimeout = Duration(seconds: 25);

typedef ProductLinkImageHttpGet = Future<ProductLinkImageHttpResponse> Function(
  Uri url,
);

typedef ProductLinkOwnedImageUploader = Future<String> Function({
  required String storagePath,
  required Uint8List bytes,
  required String contentType,
});

typedef ProductLinkImageNormalizer = Future<Uint8List> Function(Uint8List bytes);

class ProductLinkImageHttpResponse {
  const ProductLinkImageHttpResponse({
    required this.statusCode,
    required this.body,
    this.contentType,
  });

  final int statusCode;
  final Uint8List body;
  final String? contentType;
}

enum ProductLinkImageHandoffError {
  noSeedImage,
  invalidUrl,
  timeout,
  httpError,
  notImage,
  empty,
  oversize,
  decodeFailed,
  uploadFailed,
}

class ProductLinkImageHandoffException implements Exception {
  const ProductLinkImageHandoffException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final ProductLinkImageHandoffError kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'ProductLinkImageHandoffException($kind: $message)';
}

class ProductLinkOwnedImageHandoffResult {
  const ProductLinkOwnedImageHandoffResult({
    required this.sourceUrl,
    required this.seedImageUrl,
    required this.storagePath,
    required this.ownedImageUrl,
  });

  final String sourceUrl;
  final String seedImageUrl;
  final String storagePath;
  final String ownedImageUrl;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'sourceUrl': sourceUrl,
        'seedImageUrl': seedImageUrl,
        'storagePath': storagePath,
        'ownedImageUrl': ownedImageUrl,
      };
}

enum ProductLinkFailureRetryKind { metadata, imageHandoff, analyzer }

ProductLinkFailureRetryKind productLinkFailureRetryKind({
  required bool hasOwnedAnalyzerSource,
  required bool imageHandoffFailed,
}) {
  if (hasOwnedAnalyzerSource) return ProductLinkFailureRetryKind.analyzer;
  if (imageHandoffFailed) return ProductLinkFailureRetryKind.imageHandoff;
  return ProductLinkFailureRetryKind.metadata;
}

String buildOwnedWardrobeImagePath({
  required String uid,
  required int timestampMs,
}) {
  final safeUid = uid.trim();
  if (safeUid.isEmpty ||
      safeUid.contains('/') ||
      safeUid.contains('..') ||
      safeUid.contains('://')) {
    throw ArgumentError('invalid_wardrobe_uid');
  }
  return 'wardrobe/$safeUid/$timestampMs.jpg';
}

bool isOwnedWardrobeStoragePath(String path, {required String uid}) {
  final trimmed = path.trim();
  final expectedPrefix = 'wardrobe/${uid.trim()}/';
  return trimmed.startsWith(expectedPrefix) &&
      !trimmed.startsWith('wardrobe_product/') &&
      !trimmed.contains('..') &&
      trimmed.split('/').length >= 3;
}

bool _isHtmlOrTextContentType(String contentType) {
  final ct = contentType.toLowerCase();
  return ct.contains('text/html') ||
      ct.contains('text/plain') ||
      ct.contains('application/json') ||
      ct.contains('application/xml') ||
      ct.contains('text/xml') ||
      ct.contains('application/javascript');
}

bool _hasImageContentType(String contentType) {
  final ct = contentType.toLowerCase().split(';').first.trim();
  return ct.startsWith('image/') && ct != 'image/*';
}

bool _bytesLookLikeHtml(Uint8List bytes) {
  final head = String.fromCharCodes(
    bytes.take(64).where((b) => b >= 32 || b == 9 || b == 10 || b == 13),
  ).trimLeft().toLowerCase();
  return head.startsWith('<!doctype') ||
      head.startsWith('<html') ||
      head.startsWith('<head') ||
      head.startsWith('<body');
}

bool _bytesLookLikeImageMagic(Uint8List bytes) {
  if (bytes.length < 12) return false;
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return true;
  }
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }
  return false;
}

ProductLinkImageHandoffError? validateProductLinkImageResponse({
  required int statusCode,
  required Uint8List bytes,
  String? contentType,
  int maxBytes = kProductLinkImageMaxBytes,
}) {
  if (statusCode < 200 || statusCode >= 300) {
    return ProductLinkImageHandoffError.httpError;
  }
  if (bytes.isEmpty) return ProductLinkImageHandoffError.empty;
  if (bytes.length > maxBytes) return ProductLinkImageHandoffError.oversize;

  final ct = (contentType ?? '').trim();
  if (ct.isNotEmpty && _isHtmlOrTextContentType(ct)) {
    return ProductLinkImageHandoffError.notImage;
  }
  if (_bytesLookLikeHtml(bytes)) {
    return ProductLinkImageHandoffError.notImage;
  }
  if (ct.isNotEmpty && !_hasImageContentType(ct) && !_bytesLookLikeImageMagic(bytes)) {
    return ProductLinkImageHandoffError.notImage;
  }
  if (ct.isEmpty && !_bytesLookLikeImageMagic(bytes)) {
    return ProductLinkImageHandoffError.notImage;
  }
  return null;
}

class ProductLinkOwnedImageHandoff {
  ProductLinkOwnedImageHandoff({
    ProductLinkImageHttpGet? httpGet,
    ProductLinkOwnedImageUploader? upload,
    ProductLinkImageNormalizer? normalize,
    FirebaseStorage? storage,
  }) : _httpGet = httpGet,
       _upload = upload,
       _normalize = normalize,
       _storage = storage;

  static ProductLinkOwnedImageHandoff instance = ProductLinkOwnedImageHandoff();

  final ProductLinkImageHttpGet? _httpGet;
  final ProductLinkOwnedImageUploader? _upload;
  final ProductLinkImageNormalizer? _normalize;
  final FirebaseStorage? _storage;

  Future<ProductLinkOwnedImageHandoffResult> run({
    required String uid,
    required String sourceUrl,
    required String seedImageUrl,
    int? timestampMs,
  }) async {
    final canonicalSource = canonicalProductLinkUrl(sourceUrl);
    final seed = seedImageUrl.trim();
    if (seed.isEmpty || !isValidProductLinkImageUrl(seed)) {
      throw const ProductLinkImageHandoffException(
        kind: ProductLinkImageHandoffError.noSeedImage,
        message: 'no_seed_image',
      );
    }

    final uri = Uri.tryParse(seed);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      throw const ProductLinkImageHandoffException(
        kind: ProductLinkImageHandoffError.invalidUrl,
        message: 'invalid_seed_image_url',
      );
    }

    final response = await _download(uri);
    final validation = validateProductLinkImageResponse(
      statusCode: response.statusCode,
      bytes: response.body,
      contentType: response.contentType,
    );
    if (validation != null) {
      throw ProductLinkImageHandoffException(
        kind: validation,
        message: validation.name,
      );
    }

    if (img.decodeImage(response.body) == null) {
      throw const ProductLinkImageHandoffException(
        kind: ProductLinkImageHandoffError.decodeFailed,
        message: 'image_decode_failed',
      );
    }

    final jpeg = await (_normalize ?? _defaultNormalize)(response.body);
    if (jpeg.isEmpty) {
      throw const ProductLinkImageHandoffException(
        kind: ProductLinkImageHandoffError.empty,
        message: 'normalized_image_empty',
      );
    }

    final storagePath = buildOwnedWardrobeImagePath(
      uid: uid,
      timestampMs: timestampMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    if (!isOwnedWardrobeStoragePath(storagePath, uid: uid) ||
        storagePath.startsWith('wardrobe_product/')) {
      throw const ProductLinkImageHandoffException(
        kind: ProductLinkImageHandoffError.uploadFailed,
        message: 'storage_path_not_wardrobe',
      );
    }

    try {
      final ownedUrl = await _putOwnedJpeg(storagePath: storagePath, bytes: jpeg);
      return ProductLinkOwnedImageHandoffResult(
        sourceUrl: canonicalSource,
        seedImageUrl: seed,
        storagePath: storagePath,
        ownedImageUrl: ownedUrl,
      );
    } on ProductLinkImageHandoffException {
      rethrow;
    } catch (e) {
      throw ProductLinkImageHandoffException(
        kind: ProductLinkImageHandoffError.uploadFailed,
        message: e.toString(),
        cause: e,
      );
    }
  }

  Future<ProductLinkImageHttpResponse> _download(Uri uri) async {
    try {
      final get = _httpGet;
      if (get != null) return await get(uri);
      final response = await http
          .get(
            uri,
            headers: const {
              'Accept': 'image/jpeg,image/png,image/webp,image/*;q=0.8',
            },
          )
          .timeout(kProductLinkImageDownloadTimeout);
      return ProductLinkImageHttpResponse(
        statusCode: response.statusCode,
        body: response.bodyBytes,
        contentType: response.headers['content-type'],
      );
    } on TimeoutException catch (e) {
      throw ProductLinkImageHandoffException(
        kind: ProductLinkImageHandoffError.timeout,
        message: e.toString(),
        cause: e,
      );
    } on ProductLinkImageHandoffException {
      rethrow;
    } catch (e) {
      throw ProductLinkImageHandoffException(
        kind: ProductLinkImageHandoffError.httpError,
        message: e.toString(),
        cause: e,
      );
    }
  }

  Future<Uint8List> _defaultNormalize(Uint8List bytes) {
    return compute(prepareJpgForUpload, <String, dynamic>{
      'bytes': bytes,
      'maxSide': kAddClothingUploadMaxSide,
      'quality': kAddClothingUploadJpegQuality,
    });
  }

  Future<String> _putOwnedJpeg({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    final upload = _upload;
    if (upload != null) {
      return upload(
        storagePath: storagePath,
        bytes: bytes,
        contentType: 'image/jpeg',
      );
    }
    final storage = _storage ?? FirebaseStorage.instance;
    final ref = storage.ref().child(storagePath);
    final task = await ref
        .putData(bytes, SettableMetadata(contentType: 'image/jpeg'))
        .timeout(kProductLinkImageUploadTimeout);
    return task.ref.getDownloadURL().timeout(const Duration(seconds: 15));
  }
}

ProductLinkOwnedImageHandoff? _debugOverride;

@visibleForTesting
void debugOverrideProductLinkOwnedImageHandoff(
  ProductLinkOwnedImageHandoff? value,
) {
  _debugOverride = value;
}

ProductLinkOwnedImageHandoff get productLinkOwnedImageHandoff =>
    _debugOverride ?? ProductLinkOwnedImageHandoff.instance;

String productLinkImageHandoffUserMessage(ProductLinkImageHandoffError kind) {
  switch (kind) {
    case ProductLinkImageHandoffError.noSeedImage:
      return 'Nepodarilo sa nájsť obrázok produktu.';
    case ProductLinkImageHandoffError.timeout:
      return 'Sťahovanie obrázka vypršalo. Skús znova.';
    case ProductLinkImageHandoffError.httpError:
      return 'Obrázok produktu sa nepodarilo stiahnuť.';
    case ProductLinkImageHandoffError.notImage:
      return 'Odkaz nevrátil obrázok oblečenia.';
    case ProductLinkImageHandoffError.empty:
      return 'Stiahnutý obrázok je prázdny.';
    case ProductLinkImageHandoffError.oversize:
      return 'Obrázok produktu je príliš veľký.';
    case ProductLinkImageHandoffError.decodeFailed:
      return 'Obrázok produktu sa nepodarilo spracovať.';
    case ProductLinkImageHandoffError.uploadFailed:
      return 'Nahratie obrázka do šatníka zlyhalo.';
    case ProductLinkImageHandoffError.invalidUrl:
      return 'Neplatný odkaz na obrázok produktu.';
  }
}

/// PL-2 result must never be treated as clothing identity.
bool productLinkHandoffContainsIdentity(Map<String, dynamic> data) {
  for (final key in kProductLinkIgnoredIdentityKeys) {
    if (data.containsKey(key)) return true;
  }
  return false;
}
