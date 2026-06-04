import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:outfitofTheDay/utils/wardrobe_image_processing.dart';

/// Recency timestamp for wardrobe ordering (newest-first lists).
DateTime wardrobeItemRecency(Map<String, dynamic> data) {
  DateTime? fromField(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  return fromField(data['createdAt']) ??
      fromField(data['updatedAt']) ??
      fromField(data['uploadedAt']) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

int compareWardrobeByRecency(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required bool desc,
}) {
  final cmp = wardrobeItemRecency(a).compareTo(wardrobeItemRecency(b));
  return desc ? -cmp : cmp;
}

void sortWardrobeItemsNewestFirst(List<Map<String, dynamic>> items) {
  items.sort((a, b) => compareWardrobeByRecency(a, b, desc: true));
}

int wardrobeCompareItems(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required String sortOption,
}) {
  switch (sortOption) {
    case 'Najnovšie':
      return compareWardrobeByRecency(a, b, desc: true);
    case 'Najstaršie':
      return compareWardrobeByRecency(a, b, desc: false);
    case 'Značka':
      return ((a['brand'] as String?) ?? '')
          .toLowerCase()
          .compareTo(((b['brand'] as String?) ?? '').toLowerCase());
    case 'Farba':
      String firstColor(Map<String, dynamic> d) {
        final v = d['color'];
        if (v is List && v.isNotEmpty) return v.first.toString();
        if (v is String && v.isNotEmpty) return v;
        return '';
      }

      return firstColor(a).toLowerCase().compareTo(firstColor(b).toLowerCase());
    case 'Najčastejšie nosené':
      final wa = (a['wearCount'] is int) ? a['wearCount'] as int : 0;
      final wb = (b['wearCount'] is int) ? b['wearCount'] as int : 0;
      return wb.compareTo(wa);
    default:
      return 0;
  }
}

bool wardrobeListHasActiveProcessing(Iterable<Map<String, dynamic>> items) {
  for (final item in items) {
    if (wardrobeItemHasActiveProcessing(item)) return true;
  }
  return false;
}
