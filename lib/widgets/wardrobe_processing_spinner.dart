import 'package:flutter/material.dart';

/// Blue processing indicator used on wardrobe tiles and the processing banner.
class WardrobeProcessingSpinner extends StatelessWidget {
  const WardrobeProcessingSpinner({
    super.key,
    this.size = 12,
    this.strokeWidth = 1.6,
  });

  /// Default badge size on clothing card (top-left).
  static const double badgeSize = 12;

  /// Slightly larger for banner / in-tile center states.
  static const double bannerSize = 18;

  static const Color color = Color(0xFF4A6CF7);

  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: const AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
