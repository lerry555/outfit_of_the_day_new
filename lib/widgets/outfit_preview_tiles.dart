import 'package:flutter/material.dart';

import '../models/calendar_outfit_models.dart';
import '../Services/outfit_generation_service.dart';
import '../utils/wardrobe_image_url_priority.dart';

class OutfitPreviewTiles extends StatelessWidget {
  const OutfitPreviewTiles({
    super.key,
    required this.items,
    this.showLabels = true,
  });

  final List<CalendarOutfitItem> items;
  final bool showLabels;

  IconData _iconForType(OutfitWearType type) {
    switch (type) {
      case OutfitWearType.top:
        return Icons.checkroom;
      case OutfitWearType.bottom:
        return Icons.style;
      case OutfitWearType.shoes:
        return Icons.directions_run;
      case OutfitWearType.outerwear:
        return Icons.umbrella;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items
          .map((item) => _Tile(
                item: item,
                icon: _iconForType(item.type),
                showLabel: showLabels,
              ))
          .toList(),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.icon,
    required this.showLabel,
  });

  final CalendarOutfitItem item;
  final IconData icon;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final m = <String, dynamic>{
      'productImageUrl': item.productImageUrl,
      'cutoutImageUrl': item.cutoutImageUrl,
      'cleanImageUrl': item.cleanImageUrl,
      'originalImageUrl': item.originalImageUrl,
      'imageUrl': item.imageUrl,
    };
    final resolvedUrl = resolveWardrobeImageUrl(m);
    final hasImage = resolvedUrl != null && resolvedUrl.trim().isNotEmpty;

    return Container(
      width: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
        color: Colors.black.withOpacity(0.18),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 78,
              height: 78,
              child: hasImage
                  ? Image.network(
                      resolvedUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.white.withOpacity(0.05),
                          child: Center(
                            child: Icon(icon,
                                color: Colors.white38, size: 22),
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.white.withOpacity(0.03),
                          child: const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: Colors.white.withOpacity(0.05),
                      child: Center(
                        child: Icon(icon,
                            color: Colors.white38, size: 24),
                      ),
                    ),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: 8),
            Text(
              item.label.trim().isNotEmpty ? item.label : 'Kúsok',
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

