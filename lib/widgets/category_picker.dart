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

  InputDecoration _fieldDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.white.withOpacity(0.22),
          width: 1.2,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  TextStyle get _labelStyle => const TextStyle(
    color: Colors.white70,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

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

    return Theme(
      data: Theme.of(context).copyWith(
        canvasColor: const Color(0xFF121212),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hlavná skupina',
            style: _labelStyle,
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: selectedMainGroup,
            dropdownColor: const Color(0xFF121212),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
            iconEnabledColor: Colors.white70,
            decoration: _fieldDecoration(),
            items: mainCategoryGroups.entries.map((e) {
              return DropdownMenuItem<String>(
                value: e.key,
                child: Text(
                  e.value,
                  style: const TextStyle(color: Colors.white),
                ),
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
            style: _labelStyle,
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: availableCategories.contains(selectedCategory)
                ? selectedCategory
                : null,
            dropdownColor: const Color(0xFF121212),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
            iconEnabledColor: Colors.white70,
            decoration: _fieldDecoration(),
            items: availableCategories.map((catKey) {
              final label = categoryLabels[catKey] ?? catKey;
              return DropdownMenuItem<String>(
                value: catKey,
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white),
                ),
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

          if (!hideSubCategory) ...[
            const SizedBox(height: 16),
            Text(
              'Typ oblečenia',
              style: _labelStyle,
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: availableSubCategories.contains(selectedSubCategory)
                  ? selectedSubCategory
                  : null,
              dropdownColor: const Color(0xFF121212),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
              iconEnabledColor: Colors.white70,
              decoration: _fieldDecoration(),
              items: availableSubCategories.map((subKey) {
                final label = subCategoryLabels[subKey] ?? subKey;
                return DropdownMenuItem<String>(
                  value: subKey,
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white),
                  ),
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
      ),
    );
  }
}