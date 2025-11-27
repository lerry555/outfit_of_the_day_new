// lib/screens/clothing_detail_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ClothingDetailScreen extends StatelessWidget {
  final String clothingItemId;
  final Map<String, dynamic> clothingItemData;

  const ClothingDetailScreen({
    Key? key,
    required this.clothingItemId,
    required this.clothingItemData,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Bezpečné vytiahnutie dát
    final String name = clothingItemData['name'] as String? ?? 'Neznámy kúsok';
    final String? imageUrl = clothingItemData['imageUrl'] as String?;
    final String mainCategory =
        clothingItemData['mainCategory'] as String? ?? '';
    final String category = clothingItemData['category'] as String? ?? '';

    // farby – môžu byť list alebo string
    final dynamic colorData = clothingItemData['color'];
    final List<String> colors = _toStringList(colorData);

    // štýl – list alebo string
    final dynamic styleData = clothingItemData['style'];
    final List<String> styles = _toStringList(styleData);

    // vzory – list alebo string
    final dynamic patternData = clothingItemData['pattern'];
    final List<String> patterns = _toStringList(patternData);

    // sezóny – list alebo string
    final dynamic seasonData = clothingItemData['season'];
    final List<String> seasons = _toStringList(seasonData);

    final String brand = clothingItemData['brand'] as String? ?? '';
    final int wearCount =
        clothingItemData['wearCount'] is int ? clothingItemData['wearCount'] as int : 0;

    final Timestamp? uploadedAtTs =
        clothingItemData['uploadedAt'] as Timestamp?;
    final DateTime? uploadedAt =
        uploadedAtTs != null ? uploadedAtTs.toDate() : null;

    // pomocný text pre hlavičku (napr. "Bunda • Zima")
    String categoryLine = '';
    if (category.isNotEmpty && seasons.isNotEmpty) {
      categoryLine = '$category • ${seasons.join(', ')}';
    } else if (category.isNotEmpty) {
      categoryLine = category;
    } else if (seasons.isNotEmpty) {
      categoryLine = seasons.join(', ');
    }

    // pomocný text pre štýl + vzor (napr. "Casual • Jednofarebné")
    String stylePatternLine = '';
    if (styles.isNotEmpty && patterns.isNotEmpty) {
      stylePatternLine = '${styles.join(', ')} • ${patterns.join(', ')}';
    } else if (styles.isNotEmpty) {
      stylePatternLine = styles.join(', ');
    } else if (patterns.isNotEmpty) {
      stylePatternLine = patterns.join(', ');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Obrázok
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  imageUrl,
                  height: 260,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 260,
                    color: Colors.grey.shade200,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.grey.shade200,
                ),
                child: const Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 48,
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Názov
            Text(
              name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),

            // Hlavná kategória + podkategória + sezóna
            if (mainCategory.isNotEmpty || categoryLine.isNotEmpty)
              Text(
                [
                  if (mainCategory.isNotEmpty) mainCategory,
                  if (categoryLine.isNotEmpty) categoryLine,
                ].join(' • '),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
            const SizedBox(height: 12),

            // Štýl + vzor
            if (stylePatternLine.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.style_outlined, size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      stylePatternLine,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade800,
                          ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Farby – chips
            if (colors.isNotEmpty) ...[
              Text(
                'Farby',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: colors
                    .map(
                      (c) => Chip(
                        label: Text(c),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Značka
            if (brand.isNotEmpty) ...[
              Text(
                'Značka',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                brand,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // Sezóna – ak chceme ešte raz detailnejšie
            if (seasons.isNotEmpty) ...[
              Text(
                'Sezóna nosenia',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                seasons.join(', '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // Štýl – detailnejšie
            if (styles.isNotEmpty) ...[
              Text(
                'Štýl',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                styles.join(', '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // Vzor – detailnejšie
            if (patterns.isNotEmpty) ...[
              Text(
                'Vzor',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                patterns.join(', '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // Štatistiky – nosenie a dátum pridania
            Text(
              'Informácie o kúsku',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (wearCount > 0)
              Text(
                'Počet nosení: $wearCount',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Text(
                'Zatiaľ neevidujeme žiadne nosenie.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (uploadedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Pridané do šatníka: '
                '${uploadedAt.day.toString().padLeft(2, '0')}.'
                '${uploadedAt.month.toString().padLeft(2, '0')}.'
                '${uploadedAt.year}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
            ],

            const SizedBox(height: 24),

            // (Do budúcna sem vieme dať tlačidlo "Upraviť kúsok" alebo "Označiť ako oblečené dnes")
            // Zatiaľ len info text
            Text(
              'Tieto informácie sa využijú pri generovaní outfitov a odporúčaniach AI stylistu.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pomocná funkcia, ktorá z dynamic spraví List<String>
  static List<String> _toStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String && value.isNotEmpty) {
      return [value];
    }
    return [];
  }
}