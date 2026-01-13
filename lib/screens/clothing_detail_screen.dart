// lib/screens/clothing_detail_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import 'add_clothing_screen.dart';

class ClothingDetailScreen extends StatelessWidget {
  final String clothingItemId;

  /// Fallback dáta z listu vo wardrobe – použijú sa kým sa nenačíta stream.
  final Map<String, dynamic> clothingItemData;

  const ClothingDetailScreen({
    Key? key,
    required this.clothingItemId,
    required this.clothingItemData,
  }) : super(key: key);

  // ---------------------------------------------------------
  // IMAGE PICKER (rovnaká logika ako v šatníku)
  // productImageUrl → cutout/clean → original/imageUrl
  // ---------------------------------------------------------
  static String? _bestImageUrl(Map<String, dynamic> d) {
    String? str(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final product = str(d['productImageUrl']);
    if (product != null) return product;

    final cutout = str(d['cutoutImageUrl']) ?? str(d['cleanImageUrl']);
    if (cutout != null) return cutout;

    final original = str(d['originalImageUrl']) ?? str(d['imageUrl']);
    if (original != null) return original;

    return null;
  }

  static List<String> _toStringList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    if (val is String && val.isNotEmpty) return [val];
    return [];
  }

  static List<String> _readList(
      Map<String, dynamic> d,
      String pluralKey,
      String singularKey,
      ) {
    final v = d[pluralKey] ?? d[singularKey];
    return _toStringList(v);
  }

  static String _labelForSubCategory(Map<String, dynamic> d) {
    final String? key = (d['subCategoryKey'] ?? d['subCategory'])?.toString();
    if (key != null && key.isNotEmpty) {
      return subCategoryLabels[key] ?? key;
    }
    final String? cat = d['category']?.toString();
    return (cat ?? '').trim();
  }

  Widget _buildImage(Map<String, dynamic> d) {
    final url = _bestImageUrl(d);

    if (url == null) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.grey.shade200,
        ),
        child: const Center(child: Icon(Icons.image_outlined, size: 48)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 320,
        width: double.infinity,
        color: Colors.grey.shade100, // jemné pozadie
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        child: Image.network(
          url,
          fit: BoxFit.contain, // ✅ celé sa zmestí (žiadne orezanie)
          errorBuilder: (_, __, ___) => Container(
            height: 320,
            color: Colors.grey.shade200,
            child: const Center(child: Icon(Icons.broken_image, size: 48)),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> d) {
    final String name = d['name'] as String? ?? 'Neznámy kúsok';

    // kategórie / fallbacky
    final String mainGroup =
    (d['mainGroupKey'] ?? d['mainGroup'] ?? d['mainCategory'] ?? '')
        .toString();
    final String categoryKey = (d['categoryKey'] ?? d['category'] ?? '')
        .toString();
    final String subLabel = _labelForSubCategory(d);

    final List<String> colors = _readList(d, 'colors', 'color');
    final List<String> styles = _readList(d, 'styles', 'style');
    final List<String> patterns = _readList(d, 'patterns', 'pattern');
    final List<String> seasons = _readList(d, 'seasons', 'season');

    final String brand = (d['brand'] ?? '').toString();
    final int wearCount = d['wearCount'] is int ? d['wearCount'] as int : 0;

    // dátumy (fallback na staré polia)
    final Timestamp? createdAtTs = d['createdAt'] as Timestamp?;
    final Timestamp? uploadedAtTs = d['uploadedAt'] as Timestamp?;
    final DateTime? createdAt = (createdAtTs ?? uploadedAtTs)?.toDate();

    final List<String> categoryBits = [];
    if (subLabel.trim().isNotEmpty) categoryBits.add(subLabel.trim());
    if (seasons.isNotEmpty) categoryBits.add(seasons.join(', '));
    final String categoryLine = categoryBits.join(' • ');

    final List<String> sp = [];
    if (styles.isNotEmpty) sp.add(styles.join(', '));
    if (patterns.isNotEmpty) sp.add(patterns.join(', '));
    final String stylePatternLine = sp.join(' • ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildImage(d),
        const SizedBox(height: 16),

        Text(
          name,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),

        if (brand.trim().isNotEmpty)
          Text(
            brand,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey.shade800),
          ),

        if (categoryLine.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.category_outlined,
                  size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  categoryLine,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey.shade800),
                ),
              ),
            ],
          ),
        ],

        if (stylePatternLine.isNotEmpty) ...[
          const SizedBox(height: 8),
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
        ],

        const SizedBox(height: 12),
        Row(
          children: [
            if (mainGroup.isNotEmpty)
              Expanded(
                child: _InfoChip(icon: Icons.layers_outlined, label: mainGroup),
              ),
            if (categoryKey.isNotEmpty) ...[
              if (mainGroup.isNotEmpty) const SizedBox(width: 8),
              Expanded(
                child: _InfoChip(
                    icon: Icons.grid_view_rounded, label: categoryKey),
              ),
            ],
          ],
        ),

        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),

        if (colors.isNotEmpty) ...[
          Text('Farby', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((c) => _TagChip(text: c)).toList(),
          ),
          const SizedBox(height: 16),
        ],

        if (styles.isNotEmpty) ...[
          Text('Štýly', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: styles.map((s) => _TagChip(text: s)).toList(),
          ),
          const SizedBox(height: 16),
        ],

        if (patterns.isNotEmpty) ...[
          Text('Vzor', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: patterns.map((p) => _TagChip(text: p)).toList(),
          ),
          const SizedBox(height: 16),
        ],

        if (wearCount > 0 || createdAt != null) ...[
          Text('Info', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (wearCount > 0)
            Row(
              children: [
                Icon(Icons.repeat_rounded,
                    size: 18, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Text('Nosené: $wearCount×'),
              ],
            ),
          if (createdAt != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 18, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Text(
                    'Pridané: ${createdAt.day}.${createdAt.month}.${createdAt.year}'),
              ],
            ),
          ],
          const SizedBox(height: 16),
        ],

        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddClothingScreen(
                  isEditing: true,
                  itemId: clothingItemId,
                  imageUrl: _bestImageUrl(d),
                  initialData: d,
                ),
              ),
            );

            if (result == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Uložené.')),
              );
            }
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Upraviť'),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Detail')),
      body: (user == null)
          ? const Center(child: Text('Musíš byť prihlásený.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('wardrobe')
            .doc(clothingItemId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? clothingItemData;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildContent(context, data),
          );
        },
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String text;
  const _TagChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Text(text),
    );
  }
}
