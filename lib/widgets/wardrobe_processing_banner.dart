import 'package:flutter/material.dart';

import 'package:outfitofTheDay/widgets/wardrobe_processing_spinner.dart';

/// Shared processing notice for main wardrobe and category screens.
class WardrobeProcessingBanner extends StatelessWidget {
  const WardrobeProcessingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40, maxHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1B1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: const Color(0x224A6CF7),
              border: Border.all(
                color: WardrobeProcessingSpinner.color.withOpacity(0.35),
              ),
            ),
            child: const WardrobeProcessingSpinner(
              size: WardrobeProcessingSpinner.bannerSize,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Niektoré fotky sa ešte upravujú. Modrý kruh zmizne po dokončení.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11.8,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
