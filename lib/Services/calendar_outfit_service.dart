import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/calendar_outfit_models.dart';
import 'date_weather_service.dart';
import 'outfit_generation_service.dart';
import '../utils/outfit_reason_builder.dart';
class CalendarOutfitService {
  CalendarOutfitService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  CollectionReference<Map<String, dynamic>> _calendarOutfitsRef(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('calendar_outfits');
  }

  DocumentReference<Map<String, dynamic>> _dayDocRef({
    required String uid,
    required String dateKey,
  }) {
    return _calendarOutfitsRef(uid).doc(dateKey);
  }

  Stream<Set<String>> watchMonthOutfitDateKeys({
    required String uid,
    required DateTime month,
  }) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);
    final startKey = dateKey(start);
    final endKey = dateKey(end);

    return _calendarOutfitsRef(uid)
        .where(FieldPath.documentId,
            isGreaterThanOrEqualTo: startKey)
        .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  Stream<CalendarOutfitDay?> watchDayOutfit({
    required String uid,
    required DateTime date,
  }) {
    final key = dateKey(date);
    return _dayDocRef(uid: uid, dateKey: key).snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      return CalendarOutfitDay.fromFirestore(dateKey: key, data: data);
    });
  }

  Future<CalendarOutfitDay> generateAndSaveDay({
    required DateTime date,
    required DateWeatherSnapshot weatherSnapshot,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('User nie je prihlásený.');
    }

    final uid = user.uid;
    final key = dateKey(date);
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final userData = userDoc.data();
    final subscriptionStatus =
        (userData?['subscriptionStatus'] ?? '').toString().toLowerCase();
    final bool isPremiumUser =
        userData?['isPremium'] == true || subscriptionStatus == 'premium';

    final wardrobe = await _loadWardrobe(uid);

    final preview = OutfitGenerationService.generatePreview(
      wardrobeItems: wardrobe,
      weather: OutfitWeatherSnapshot(
        tempC: weatherSnapshot.tempC,
        isRainy: weatherSnapshot.isRainy,
        isWindy: weatherSnapshot.isWindy,
        seasonKey: weatherSnapshot.seasonKey,
      ),
    );
    if (preview == null) {
      throw StateError('Nepodarilo sa vygenerovať outfit (chýbajú kusy v šatníku).');
    }
    final selectedReasonItems = <Map<String, dynamic>>[
      {
        ...preview.top.item,
        'typeKey': 'top',
      },
      {
        ...preview.bottom.item,
        'typeKey': 'bottom',
      },
      {
        ...preview.shoes.item,
        'typeKey': 'shoes',
      },
      if (preview.outerwear != null)
        {
          ...preview.outerwear!.item,
          'typeKey': 'outerwear',
        },
    ];

    final reason = OutfitReasonBuilder.build(
      tempC: weatherSnapshot.tempC,
      isRainy: weatherSnapshot.isRainy,
      isWindy: weatherSnapshot.isWindy,
      isPremium: isPremiumUser,
      selectedItems: selectedReasonItems,
      hasOuterwear: preview.outerwear != null,
    );
    final items = <CalendarOutfitItem>[
      if (preview.outerwear != null) _toCalendarOutfitItem(preview.outerwear!),
      _toCalendarOutfitItem(preview.top),
      _toCalendarOutfitItem(preview.bottom),
      _toCalendarOutfitItem(preview.shoes),
    ];

    final now = FieldValue.serverTimestamp();
    final existing = await _dayDocRef(uid: uid, dateKey: key).get();
    final isExisting = existing.exists;

    await _dayDocRef(uid: uid, dateKey: key).set({
      'dateKey': key,
      'weatherSnapshot': weatherSnapshot.toJson(),
      'outfitItems': items.map((e) => e.toMap()).toList(),
      'generationSource': 'calendar',
      'version': 1,
      'reason': reason,
      'generatedAt': now,
      'updatedAt': now,
      if (!isExisting) 'createdAt': now,
    }, SetOptions(merge: true));

    return CalendarOutfitDay(
      dateKey: key,
      weatherSnapshot: weatherSnapshot,
      outfitItems: items,
      generationSource: 'calendar',
      version: 1,
      reason: reason,
    );
  }

  Future<List<Map<String, dynamic>>> _loadWardrobe(String uid) async {
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('wardrobe')
        .get();
    return snap.docs.map((d) => Map<String, dynamic>.from(d.data())).toList();
  }

  CalendarOutfitItem _toCalendarOutfitItem(OutfitPreviewItem item) {
    final it = item.item;

    String? getStr(String k) {
      final v = it[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return CalendarOutfitItem(
      type: item.type,
      label: item.label,
      productImageUrl: getStr('productImageUrl'),
      cutoutImageUrl: getStr('cutoutImageUrl'),
      cleanImageUrl: getStr('cleanImageUrl'),
      originalImageUrl: getStr('originalImageUrl'),
      imageUrl: getStr('imageUrl'),
    );
  }
}

