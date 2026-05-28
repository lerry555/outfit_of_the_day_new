import '../utils/product_link_image_resolve.dart';

const String kImageProcessingStatusNone = 'none';
const String kImageProcessingStatusProcessing = 'processing';
const String kImageProcessingStatusDone = 'done';
const String kImageProcessingStatusFailed = 'failed';

class ProductImageProcessingSaveDecision {
  const ProductImageProcessingSaveDecision({
    required this.needsProcessing,
    required this.reason,
  });

  final bool needsProcessing;
  final String reason;
}

ProductImageProcessingSaveDecision decideProductLinkImageProcessing({
  required String sourceUrl,
  required String selectedImageUrl,
  bool personDetected = false,
  String? cleanImageUrl,
  String? imageProcessingReason,
}) {
  final src = sourceUrl.trim();
  final selected = selectedImageUrl.trim();

  if (src.isEmpty) {
    return const ProductImageProcessingSaveDecision(
      needsProcessing: false,
      reason: 'no_product_link',
    );
  }

  if (!isValidProductLinkImageUrl(selected)) {
    return const ProductImageProcessingSaveDecision(
      needsProcessing: false,
      reason: 'no_valid_image',
    );
  }

  if (personDetected) {
    return const ProductImageProcessingSaveDecision(
      needsProcessing: true,
      reason: 'searching_better_image',
    );
  }

  if (isValidProductLinkImageUrl(cleanImageUrl)) {
    return const ProductImageProcessingSaveDecision(
      needsProcessing: false,
      reason: 'already_product_asset',
    );
  }

  return const ProductImageProcessingSaveDecision(
    needsProcessing: true,
    reason: 'searching_better_image',
  );
}
