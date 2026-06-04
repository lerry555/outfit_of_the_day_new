import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Persisted daily outfit for Home (`users/{uid}/daily_outfits/{dateKey}`).
class HomeDailyOutfitCacheDocument {
  final String dateKey;
  final List<String> itemIds;
  final List<Map<String, dynamic>> items;
  final String reasonText;
  final String weatherSignature;
  final String wardrobeSignature;
  final String source;
  final bool userModified;
  final String? likedOutfitKey;
  final DateTime? updatedAt;

  const HomeDailyOutfitCacheDocument({
    required this.dateKey,
    required this.itemIds,
    required this.items,
    required this.reasonText,
    required this.weatherSignature,
    required this.wardrobeSignature,
    required this.source,
    required this.userModified,
    this.likedOutfitKey,
    this.updatedAt,
  });
}

class HomeDailyOutfitCacheService {
  HomeDailyOutfitCacheService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static String dateKeyFromDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.toIso8601String().substring(0, 10);
  }

  DocumentReference<Map<String, dynamic>> _docRef(String uid, String dateKey) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('daily_outfits')
        .doc(dateKey);
  }

  Future<HomeDailyOutfitCacheDocument?> load(String uid, String dateKey) async {
    try {
      final snap = await _docRef(uid, dateKey).get();
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      return _fromFirestore(dateKey, data);
    } catch (e) {
      debugPrint('[HOME_DAY_CACHE] load_error date=$dateKey error=$e');
      return null;
    }
  }

  Future<void> save({
    required String uid,
    required HomeDailyOutfitCacheDocument document,
  }) async {
    try {
      await _docRef(uid, document.dateKey).set(
        _toFirestore(document),
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint(
        '[HOME_DAY_CACHE] save_error date=${document.dateKey} error=$e',
      );
    }
  }

  HomeDailyOutfitCacheDocument? _fromFirestore(
    String dateKey,
    Map<String, dynamic> data,
  ) {
    final rawItems = data['items'];
    final items = <Map<String, dynamic>>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map) {
          items.add(Map<String, dynamic>.from(entry));
        }
      }
    }

    final rawIds = data['itemIds'];
    final itemIds = <String>[];
    if (rawIds is List) {
      for (final id in rawIds) {
        final s = id?.toString().trim() ?? '';
        if (s.isNotEmpty) itemIds.add(s);
      }
    }
    if (itemIds.isEmpty) {
      for (final m in items) {
        final id = (m['wardrobeItemId'] ?? m['id'] ?? '').toString().trim();
        if (id.isNotEmpty) itemIds.add(id);
      }
    }

    if (items.isEmpty && itemIds.isEmpty) return null;

    final updatedAt = data['updatedAt'];
    DateTime? updated;
    if (updatedAt is Timestamp) {
      updated = updatedAt.toDate();
    } else if (updatedAt is DateTime) {
      updated = updatedAt;
    }

    return HomeDailyOutfitCacheDocument(
      dateKey: dateKey,
      itemIds: itemIds,
      items: items,
      reasonText: (data['reasonText'] ?? data['reason'] ?? '').toString(),
      weatherSignature: (data['weatherSignature'] ?? '').toString(),
      wardrobeSignature: (data['wardrobeSignature'] ?? '').toString(),
      source: (data['source'] ?? 'ai_generated').toString(),
      userModified: data['userModified'] == true,
      likedOutfitKey: (data['likedOutfitKey'] as String?)?.trim().isNotEmpty == true
          ? (data['likedOutfitKey'] as String).trim()
          : null,
      updatedAt: updated,
    );
  }

  Map<String, dynamic> _toFirestore(HomeDailyOutfitCacheDocument doc) {
    return <String, dynamic>{
      'dateKey': doc.dateKey,
      'itemIds': doc.itemIds,
      'items': doc.items,
      'reasonText': doc.reasonText,
      'weatherSignature': doc.weatherSignature,
      'wardrobeSignature': doc.wardrobeSignature,
      'source': doc.source,
      'userModified': doc.userModified,
      if (doc.likedOutfitKey != null && doc.likedOutfitKey!.isNotEmpty)
        'likedOutfitKey': doc.likedOutfitKey,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
