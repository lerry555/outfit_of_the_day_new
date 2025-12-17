// lib/widgets/category_picker.dart

import 'package:flutter/material.dart';
import 'package:outfitofTheDay/constants/app_constants.dart';

class CategoryPicker extends StatelessWidget {
  final String? initialMainGroup;    // napr. "oblecenie"
  final String? initialCategory;     // napr. "bundy_kabaty"
  final String? initialSubCategory;  // napr. "bunda_zimna"

  /// ✅ Keď true, skryje "Typ oblečenia" (subCategory) z UI
  final bool hideSubCategory;

  /// onChanged dostane vždy mapu:
  /// { "mainGroup": ..., "category": ..., "subCategory": ... }
  final void Function(Map<String, String?> data) onChanged;

  const CategoryPicker({
    Key? key,
    required this.initialMainGroup,
    required this.initialCategory,
    required this.initialSubCategory,
    required this.onChanged,
    this.hideSubCategory = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final String? selectedMainGroup = initialMainGroup;
    final String? selectedCategory = initialCategory;
    final String? selectedSubCategory = initialSubCategory;

    final List<String> availableCategories = selectedMainGroup == null
        ? <String>[]
        : (categoryTree[selectedMainGroup] ?? []);

    final List<String> availableSubCategories = selectedCategory == null
        ? <String>[]
        : (subCategoryTree[selectedCategory] ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hlavná skupina',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: selectedMainGroup,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          items: mainCategoryGroups.entries.map((e) {
            return DropdownMenuItem<String>(
              value: e.key,
              child: Text(e.value),
            );
          }).toList(),
          onChanged: (value) {
            onChanged({
              'mainGroup': value,
              'category': null,
              'subCategory': null,
            });
          },
        ),
        const SizedBox(height: 16),

        Text(
          'Kategória',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: availableCategories.contains(selectedCategory)
              ? selectedCategory
              : null,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          items: availableCategories.map((catKey) {
            final label = categoryLabels[catKey] ?? catKey;
            return DropdownMenuItem<String>(
              value: catKey,
              child: Text(label),
            );
          }).toList(),
          onChanged: selectedMainGroup == null
              ? null
              : (value) {
            onChanged({
              'mainGroup': selectedMainGroup,
              'category': value,
              'subCategory': null,
            });
          },
        ),

        // ✅ Typ oblečenia zobrazíme len ak ho nechceš skryť
        if (!hideSubCategory) ...[
          const SizedBox(height: 16),
          Text(
            'Typ oblečenia',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: availableSubCategories.contains(selectedSubCategory)
                ? selectedSubCategory
                : null,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            items: availableSubCategories.map((subKey) {
              final label = subCategoryLabels[subKey] ?? subKey;
              return DropdownMenuItem<String>(
                value: subKey,
                child: Text(label),
              );
            }).toList(),
            onChanged: (selectedMainGroup == null || selectedCategory == null)
                ? null
                : (value) {
              onChanged({
                'mainGroup': selectedMainGroup,
                'category': selectedCategory,
                'subCategory': value,
              });
            },
          ),
        ],
      ],
    );
  }
}
