import 'package:flutter/material.dart';

import '../Services/product_link_image_cleanup.dart';
import '../widgets/wardrobe_processing_spinner.dart';
import 'wardrobe_image_url_priority.dart';

/// Single light well — matches typical clean/cutout PNG canvas (pure white).
const Color wardrobeItemImageBackground = Color(0xFFFFFFFF);

/// Tiles: no inset so [BoxFit.contain] fills the card.
const EdgeInsets wardrobeTileImagePadding = EdgeInsets.zero;

/// Detail hero: same well, no extra inner box.
const EdgeInsets wardrobeDetailImagePadding = EdgeInsets.zero;

bool wardrobeItemShowsImageProcessingBadge(Map<String, dynamic> raw) {
  final s = (raw['imageProcessingStatus'] ?? kImageProcessingStatusNone).toString();
  return s == kImageProcessingStatusProcessing;
}

/// Same priority as [ClothingDetailScreen] / [getBestWardrobeImageUrl].
String wardrobeTileDisplayImageUrl(Map<String, dynamic> data) {
  return getBestWardrobeImageUrl(data);
}

/// True when cutout/product pipeline is still running (banner + tile spinner).
bool wardrobeItemHasActiveProcessing(Map<String, dynamic> data) {
  String statusFromProcessing(String key) {
    final p = data['processing'];
    if (p is Map) {
      final m = p.cast<String, dynamic>();
      final v = (m[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final dotted = data['processing.$key'];
    if (dotted != null) {
      final v = dotted.toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  bool isUrlFilled(String? s) => s != null && s.trim().isNotEmpty;

  final String? productImage = data['productImageUrl'] as String?;
  final String? cleanImage = data['cleanImageUrl'] as String?;
  final String? cutoutImage = data['cutoutImageUrl'] as String?;

  final cutoutStatus = statusFromProcessing('cutout');
  final productStatus = statusFromProcessing('product');

  final hasCutoutOrClean = isUrlFilled(cleanImage) || isUrlFilled(cutoutImage);
  final hasProduct = isUrlFilled(productImage);

  final cutoutInProgress =
      !hasCutoutOrClean && (cutoutStatus == 'queued' || cutoutStatus == 'running');
  final productInProgress = hasCutoutOrClean &&
      !hasProduct &&
      (productStatus == 'queued' || productStatus == 'running');

  return cutoutInProgress || productInProgress;
}

String? wardrobeTileImageFallbackUrl(Map<String, dynamic> data, String failedUrl) {
  final failed = failedUrl.trim();
  for (final u in wardrobeImageUrlCandidates(data)) {
    if (u != failed) return u;
  }
  return null;
}

Widget _networkImage({
  required String url,
  required Map<String, dynamic> data,
  required bool showSpinner,
  required BoxFit fit,
}) {
  return Image.network(
    url,
    fit: fit,
    width: double.infinity,
    height: double.infinity,
    alignment: Alignment.center,
    gaplessPlayback: true,
    errorBuilder: (context, error, stackTrace) {
      if (showSpinner) {
        return const Center(
          child: WardrobeProcessingSpinner(size: 28, strokeWidth: 2),
        );
      }
      final fallback = wardrobeTileImageFallbackUrl(data, url);
      if (fallback == null) {
        return const SizedBox.expand();
      }
      return Image.network(
        fallback,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.expand(),
      );
    },
  );
}

/// One opaque light well + [BoxFit.contain] image (cards, grids, detail).
Widget wardrobeItemImage({
  required Map<String, dynamic> data,
  required String imageUrl,
  required bool showSpinner,
  BoxFit fit = BoxFit.contain,
  EdgeInsets padding = wardrobeTileImagePadding,
  Color backgroundColor = wardrobeItemImageBackground,
}) {
  final trimmed = imageUrl.trim();

  Widget child;
  if (trimmed.isEmpty) {
    child = showSpinner
        ? const Center(
            child: WardrobeProcessingSpinner(size: 28, strokeWidth: 2),
          )
        : const SizedBox.expand();
  } else {
    final image = _networkImage(
      url: trimmed,
      data: data,
      showSpinner: showSpinner,
      fit: fit,
    );
    child = padding == EdgeInsets.zero
        ? image
        : Padding(padding: padding, child: image);
  }

  return ColoredBox(
    color: backgroundColor,
    child: child,
  );
}
