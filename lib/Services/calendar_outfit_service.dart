import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/calendar_outfit_models.dart';
import '../domain/wardrobe_v2/native_outfit_engine_v2.dart';
import '../domain/wardrobe_v2/outfit_composition_v2.dart';
import '../domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import '../domain/wardrobe_v2/wardrobe_v2_resolver.dart';
import 'calendar_outfit_ownership.dart';
import 'calendar_weather_stale_policy.dart';
import 'date_weather_service.dart';
import 'home_daily_outfit_cache_service.dart';
import 'outfit_generation_service.dart';
import 'native_wardrobe_v2_runtime.dart';
import '../utils/outfit_reason_builder.dart';

class CalendarOutfitService {
  CalendarOutfitService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    HomeDailyOutfitCacheService? dailyOutfitCache,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _dailyOutfitCache =
           dailyOutfitCache ?? HomeDailyOutfitCacheService(firestore: firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final HomeDailyOutfitCacheService _dailyOutfitCache;

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
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
        .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  /// Month dots: Calendar docs, plus today/tomorrow Home daily outfits in this month.
  Stream<Set<String>> watchMonthVisibleOutfitDateKeys({
    required String uid,
    required DateTime month,
    DateTime? now,
  }) {
    final calendarKeys = watchMonthOutfitDateKeys(uid: uid, month: month);
    final extra = _homeCanonicalKeysInMonth(uid: uid, month: month, now: now);
    return _combineLatest2<Set<String>, Set<String>, Set<String>>(
      calendarKeys,
      extra,
      (calendar, home) => calendar.union(home),
    );
  }

  Stream<Set<String>> _homeCanonicalKeysInMonth({
    required String uid,
    required DateTime month,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final tomorrow = today.add(const Duration(days: 1));
    final monthStart = DateTime(month.year, month.month, 1);
    bool inMonth(DateTime date) =>
        date.year == monthStart.year && date.month == monthStart.month;
    final candidates = <DateTime>[
      if (inMonth(today)) today,
      if (inMonth(tomorrow)) tomorrow,
    ];
    if (candidates.isEmpty) {
      return Stream<Set<String>>.value(const <String>{});
    }
    Stream<String?> watchIfValid(DateTime date) {
      final key = dateKey(date);
      return _dailyDocRef(uid, key).snapshots().map((snap) {
        if (!snap.exists) return null;
        final data = snap.data();
        if (data == null) return null;
        final parsed = HomeDailyOutfitCacheService.parseDocument(key, data);
        final mapped = CalendarDailyOutfitAdapter.toCalendarDay(
          dateKey: key,
          daily: parsed,
        );
        return mapped == null ? null : key;
      });
    }

    if (candidates.length == 1) {
      return watchIfValid(candidates.first).map((key) => {?key});
    }
    return _combineLatest2<String?, String?, Set<String>>(
      watchIfValid(candidates[0]),
      watchIfValid(candidates[1]),
      (a, b) => {?a, ?b},
    );
  }

  DocumentReference<Map<String, dynamic>> _dailyDocRef(String uid, String key) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('daily_outfits')
        .doc(key);
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

  Stream<CalendarDayResolution> watchResolvedDayOutfit({
    required String uid,
    required DateTime date,
    DateTime? now,
  }) {
    final key = dateKey(date);
    final calendarStream = watchDayOutfit(uid: uid, date: date);
    if (!CalendarOutfitOwnership.isHomeCanonicalDate(date, now: now)) {
      return calendarStream.map(
        (day) => CalendarOutfitOwnership.resolve(
          date: date,
          now: now ?? DateTime.now(),
          daily: null,
          calendar: day,
        ),
      );
    }

    final dailyStream = _dailyDocRef(uid, key).snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      return HomeDailyOutfitCacheService.parseDocument(key, data);
    });

    return _combineLatest2<
      HomeDailyOutfitCacheDocument?,
      CalendarOutfitDay?,
      CalendarDayResolution
    >(
      dailyStream,
      calendarStream,
      (daily, calendar) => CalendarOutfitOwnership.resolve(
        date: date,
        now: now ?? DateTime.now(),
        daily: daily,
        calendar: calendar,
      ),
    );
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

    if (CalendarOutfitOwnership.isHomeCanonicalDate(date)) {
      final existingDaily = await _dailyOutfitCache.load(uid, key);
      final mapped = CalendarDailyOutfitAdapter.toCalendarDay(
        dateKey: key,
        daily: existingDaily,
      );
      if (mapped != null) return mapped;
    }

    final userDoc = await _firestore.collection('users').doc(uid).get();
    final userData = userDoc.data();
    final subscriptionStatus = (userData?['subscriptionStatus'] ?? '')
        .toString()
        .toLowerCase();
    final bool isPremiumUser =
        userData?['isPremium'] == true || subscriptionStatus == 'premium';

    final wardrobe = await _loadWardrobe(uid);

    final resolved = NativeWardrobeV2Runtime.resolveAll(wardrobe);
    final composition = composeForCalendar(resolved, weatherSnapshot);
    if (composition == null) {
      throw StateError(
        'Nepodarilo sa vygenerovať outfit (chýbajú kusy v šatníku).',
      );
    }
    final byId = {for (final item in resolved) item.itemId: item.raw};
    final selectedReasonItems = composition.items
        .map(
          (item) => <String, dynamic>{
            ...item.item.toMap(),
            'typeKey': item.compositionGroup,
          },
        )
        .toList(growable: false);

    final reason = OutfitReasonBuilder.build(
      tempC: weatherSnapshot.tempC,
      isRainy: weatherSnapshot.isRainy,
      isWindy: weatherSnapshot.isWindy,
      isPremium: isPremiumUser,
      selectedItems: selectedReasonItems,
      hasOuterwear: composition.items.any(
        (item) =>
            item.item.layerPosition == 'outer' ||
            item.item.layerPosition == 'shell',
      ),
    );
    final items = composition.items
        .map(
          (item) => _toCalendarOutfitItem(item, byId[item.itemId] ?? const {}),
        )
        .toList(growable: false);

    final now = FieldValue.serverTimestamp();
    final existing = await _dayDocRef(uid: uid, dateKey: key).get();
    final isExisting = existing.exists;

    await _dayDocRef(uid: uid, dateKey: key).set({
      'dateKey': key,
      'weatherSnapshot': weatherSnapshot.toJson(),
      'outfitItems': items.map((e) => e.toMap()).toList(),
      'generationSource': 'calendar',
      'version': 2,
      'ontologyVersion': '2.0.0',
      'template': composition.template.name,
      'reason': reason,
      'generatedAt': now,
      'updatedAt': now,
      if (!isExisting) 'createdAt': now,
    }, SetOptions(merge: true));

    return CalendarOutfitDay(
      dateKey: key,
      weatherSnapshot: weatherSnapshot,
      generationWeather:
          CalendarGenerationWeather.fromSnapshot(weatherSnapshot),
      outfitItems: items,
      generationSource: 'calendar',
      source: CalendarOutfitSource.calendar,
      version: 2,
      reason: reason,
    );
  }

  /// Weather input for Calendar composition. Callers must pass the same
  /// snapshot shown in the Calendar day UI — do not recompute synthetically.
  ///
  /// V2 engine contract: [NativeOutfitRequestV2.weatherProtectionRequired]
  /// is rain OR wind (same as Home/Stylist deterministic context).
  /// [eveningTempC] is passed through when HourlyWeatherService provided it.
  /// Feels-like is omitted: Open-Meteo hourly snapshot has no apparent temp.
  static NativeOutfitRequestV2 compositionRequestFor(
    DateWeatherSnapshot weather,
  ) {
    return NativeOutfitRequestV2(
      weatherProtectionRequired: weather.isRainy || weather.isWindy,
      tempC: weather.tempC,
      eveningTempC: weather.eveningTempC,
    );
  }

  /// Shared Home/Stylist deterministic matrix context for Calendar scoring.
  /// No occasion/activity is invented; Calendar does not collect one.
  static V2CandidateMatrixContext compositionContextFor(
    DateWeatherSnapshot weather,
  ) {
    return V2CandidateMatrixContext(
      weatherProtectionRequired: weather.isRainy || weather.isWindy,
      tempC: weather.tempC,
      eveningTempC: weather.eveningTempC,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
      outdoor: true,
      maxCandidates: 4,
    );
  }

  /// Deterministic Calendar composition: scored V2 matrix, then engine compose.
  static OutfitCompositionV2? composeForCalendar(
    Iterable<ResolvedWardrobeItemV2> wardrobe,
    DateWeatherSnapshot weather,
  ) {
    final matrix = V2FlexibleCandidateMatrix.generate(
      wardrobe: wardrobe,
      context: compositionContextFor(weather),
    );
    if (matrix.isNotEmpty) {
      return matrix.first.outfit.toComposition();
    }
    return NativeOutfitEngineV2.compose(
      wardrobe,
      compositionRequestFor(weather),
    );
  }

  Future<List<Map<String, dynamic>>> _loadWardrobe(String uid) async {
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('wardrobe')
        .get();
    return snap.docs
        .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
        .toList();
  }

  CalendarOutfitItem _toCalendarOutfitItem(
    OutfitCompositionItemV2 item,
    Map<String, dynamic> raw,
  ) {
    String? getStr(String k) {
      final v = raw[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return CalendarOutfitItem(
      type: _legacyDisplayType(item),
      itemId: item.itemId,
      canonicalType: item.item.canonicalType,
      compositionRole: item.role.name,
      compositionGroup: item.compositionGroup,
      requiredness: item.required ? 'required' : 'optional',
      selectionReason: item.selectionReason,
      label: (raw['name'] ?? item.item.canonicalType).toString(),
      productImageUrl: getStr('productImageUrl'),
      cutoutImageUrl: getStr('cutoutImageUrl'),
      cleanImageUrl: getStr('cleanImageUrl'),
      originalImageUrl: getStr('originalImageUrl'),
      imageUrl: getStr('imageUrl'),
    );
  }

  OutfitWearType _legacyDisplayType(OutfitCompositionItemV2 item) {
    if (item.item.bodySlots.contains('feet')) return OutfitWearType.shoes;
    if (item.item.bodySlots.contains('lower_body')) {
      return OutfitWearType.bottom;
    }
    if (item.item.layerPosition == 'outer' ||
        item.item.layerPosition == 'shell' ||
        item.role != CompositionRoleV2.core) {
      return OutfitWearType.outerwear;
    }
    return OutfitWearType.top;
  }

  Stream<R> _combineLatest2<A, B, R>(
    Stream<A> a,
    Stream<B> b,
    R Function(A a, B b) combine,
  ) {
    late final StreamController<R> controller;
    StreamSubscription<A>? subA;
    StreamSubscription<B>? subB;
    A? latestA;
    B? latestB;
    var hasA = false;
    var hasB = false;

    controller = StreamController<R>(
      onListen: () {
        subA = a.listen(
          (value) {
            latestA = value;
            hasA = true;
            if (hasA && hasB) {
              controller.add(combine(latestA as A, latestB as B));
            }
          },
          onError: controller.addError,
        );
        subB = b.listen(
          (value) {
            latestB = value;
            hasB = true;
            if (hasA && hasB) {
              controller.add(combine(latestA as A, latestB as B));
            }
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
      },
    );
    return controller.stream;
  }
}
