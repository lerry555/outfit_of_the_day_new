import 'package:flutter/material.dart';

/// Shared wardrobe photo preview — same layout on AI processing and Add Clothing form.
class ClothingImagePreview extends StatelessWidget {
  static const double defaultHeight = 190;

  final Widget image;
  final double height;

  const ClothingImagePreview({
    super.key,
    required this.image,
    this.height = defaultHeight,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: Colors.white10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: height,
            width: double.infinity,
            color: Colors.white.withOpacity(0.04),
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [image],
            ),
          ),
        ),
      ),
    );
  }
}
