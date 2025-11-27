// lib/screens/clothing_detail_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'add_clothing_screen.dart';

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
    final String name = clothingItemData['name'] as String? ?? 'Neznámy kúsok';
    final String? imageUrl = clothingItemData['imageUrl'] as String?;
    final String mainCategory =
        clothingItemData['mainCategory'] as String? ?? '';
    final String category = clothingItemData['category'] as String? ?? '';

    final List<String> colors = _toStringList(clothingItemData['color']);
    final List<String> styles = _toStringList(clothingItemData['style']);
    final List<String> patterns = _toStringList(clothingItemData['pattern']);
    final List<String> seasons = _toStringList(clothingItemData['season']);

    final String brand = clothingItemData['brand'] as String? ?? '';
    final int wearCount =
        clothingItemData['wearCount'] is int ? clothingItemData['wearCount'] : 0;

    final Timestamp? uploadedAtTs =
        clothingItemData['uploadedAt'] as Timestamp?;
    final DateTime? uploadedAt =
        uploadedAtTs != null ? uploadedAtTs.toDate() : null;

    String categoryLine = '';
    if (category.isNotEmpty && seasons.isNotEmpty) {
      categoryLine = '$category • ${seasons.join(', ')}';
    } else if (category.isNotEmpty) {
      categoryLine = category;
    } else if (seasons.isNotEmpty) {
      categoryLine = seasons.join(', ');
    }

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
                  errorBuilder: (_, __, ___) => Container(
                    height: 260,
                    color: Colors.grey.shade200,
                    child: const Center(
                        child: Icon(Icons.broken_image, size: 48)),
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
                  child: Icon(Icons.image_outlined, size: 48),
                ),
              ),
            const SizedBox(height: 16),

            // Názov
            Text(
              name,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),

            if (mainCategory.isNotEmpty || categoryLine.isNotEmpty)
              Text(
                [
                  if (mainCategory.isNotEmpty) mainCategory,
                  if (categoryLine.isNotEmpty) categoryLine,
                ].join(' • '),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey.shade700),
              ),

            const SizedBox(height: 12),

            if (stylePatternLine.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.style_outlined,
                      size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      stylePatternLine,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey.shade800),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Farby
            if (colors.isNotEmpty) ...[
              Text('Farby', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: colors.map((c) => Chip(label: Text(c))).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Značka
            if (brand.isNotEmpty) ...[
              Text('Značka', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                brand,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],

            // Sezóny
            if (seasons.isNotEmpty) ...[
              Text('Sezóna nosenia',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(seasons.join(', '),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],

            // Štýl
            if (styles.isNotEmpty) ...[
              Text('Štýl', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(styles.join(', '),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],

            // Pattern
            if (patterns.isNotEmpty) ...[
              Text('Vzor', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(patterns.join(', '),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 16),

            // Upraviť kúsok
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddClothingScreen(
                      initialData: clothingItemData,
                      imageUrl: clothingItemData['imageUrl'] ?? '',
                      itemId: clothingItemId,
                      isEditing: true,
                    ),
                  ),
                );
              },
              child: const Text('Upraviť kúsok'),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static List<String> _toStringList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    if (val is String && val.isNotEmpty) return [val];
    return [];
  }
}