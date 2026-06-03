import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../widgets/home/home_ai_explanation_card.dart';
import '../widgets/home/home_daily_briefing_row.dart';
import '../widgets/home/home_glass_surface.dart';
import '../widgets/home/home_greeting_header.dart';
import '../widgets/home/home_inspiration_carousel.dart';
import '../widgets/home/home_luxury_palette.dart';
import '../widgets/home/home_quick_action_orb.dart';
import '../widgets/home/home_recommended_section.dart';

import 'friends_screen.dart';
import 'messages_screen.dart';
import 'premium_screen.dart';
import 'profile_screen.dart';
import 'recommended_screen.dart';
import 'calendar_outfit_screen.dart';
import 'trip_packing_screen.dart';
import 'user_preferences_screen.dart';
import 'wardrobe_analysis_screen.dart';
import '../utils/outfit_reason_builder.dart';
import '../utils/briefing_weather_condition.dart';
import '../utils/luxury_weather_emoji.dart';
import '../Services/hourly_weather_service.dart';
import '../Services/home_ai_outfit_service.dart';
import '../Services/outfit_generation_service.dart';
import '../Services/stylist_day_brief.dart';
import '../utils/wardrobe_image_url_priority.dart';
import '../utils/wardrobe_image_processing.dart';

/// Hero outfit: transparent PNG pred produktovou fotkou ([resolveHeroHomeOutfitImageUrl]).
final Map<String, String?> _heroImageUrlCache = <String, String?>{};
final Set<String> _heroImageLoggedHitKeys = <String>{};
String? _heroWardrobeDisplayImageUrl(Map<String, dynamic> raw) {
  final id = OutfitGenerationService.wardrobeItemId(raw);
  final cacheKey = [
    id,
    (raw['cutoutImageUrl'] ?? '').toString().trim(),
    (raw['cleanImageUrl'] ?? '').toString().trim(),
    (raw['productImageUrl'] ?? '').toString().trim(),
    (raw['originalImageUrl'] ?? '').toString().trim(),
    (raw['imageUrl'] ?? '').toString().trim(),
  ].join('|');
  if (_heroImageUrlCache.containsKey(cacheKey)) {
    if (!_heroImageLoggedHitKeys.contains(cacheKey)) {
      _heroImageLoggedHitKeys.add(cacheKey);
      debugPrint('[HOME_IMAGE_PICK] cache_hit=true key=$cacheKey');
    }
    return _heroImageUrlCache[cacheKey];
  }
  final picked = resolveHeroHomeOutfitImageUrl(raw);
  _heroImageUrlCache[cacheKey] = picked;
  debugPrint('[HOME_IMAGE_PICK] cache_miss=true key=$cacheKey');
  String t(String k) => (raw[k]?.toString().trim() ?? '');
  debugPrint(
    '[HOME_IMAGE_PICK] name=${t('name')} cutout=${t('cutoutImageUrl')} clean=${t('cleanImageUrl')} '
    'product=${t('productImageUrl')} original=${t('originalImageUrl')} picked=$picked',
  );
  return picked;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final HomeAiOutfitService _homeAiOutfitService = const HomeAiOutfitService();

  // ✅ prepínač Dnes/Zajtra (UI)
  int _dayIndex = 0; // 0 = dnes, 1 = zajtra
  bool get _isTomorrow => _dayIndex == 1;
  bool _isOutfitEditMode = false;
  _HeroWearType? _focusedEditType;
  final Map<int, List<_HeroOutfitItem>> _editedOutfitByDay = {};
  final Map<int, String> _lastSourceSignatureByDay = {};
  final Map<int, bool> _editedManuallyByDay = {};
  final Map<int, Set<String>> _swapRejectedReplacementItemIdsByDay = {};
  final Map<int, Map<_HeroWearType, String>> _swapOriginalItemIdByTypeByDay = {};
  final Map<int, Map<_HeroWearType, String>> _swapLastSuggestedItemIdByTypeByDay = {};
  final Map<String, _HomeDayHeroCacheEntry> _homeDayHeroCacheByDateKey = {};
  /// Kombinácie outfitov, ktoré používateľ už odmietol („Nový outfit“).
  final Map<int, Set<String>> _rejectedOutfitCombinationKeysByDay = {};
  final Map<String, _HomeAiCacheEntry> _homeAiCacheBySignature = {};
  final Set<String> _homeAiRequestInFlight = <String>{};
  final Map<String, String> _homeAiLatestSignatureByDateKey = {};
  final Map<String, String> _homeAiLastWeatherSignatureByDateKey = {};
  final Map<String, String> _homeAiLastWardrobeSignatureByDateKey = {};
  String? _homeAiLastTriggeredDateKey;
  final Map<String, bool> _homeAiForceDifferentNextByDateKey = {};
  int _homeAiRefreshNonce = 0;
  bool _weatherLoading = false;
  final Map<String, _HeroOutfitRecommendation?> _localRecCacheByDateSig = {};
  final Map<String, List<_HeroOutfitItem>> _heroItemsCacheByIdSet = {};
  String? _lastAiPreservedSignatureLogged;
  String? _lastFallbackReasonLoggedKey;
  String? _lastHeroRenderLogKey;
  bool _newOutfitGenerating = false;
  final Map<int, String> _likedOutfitKeyByDay = {};
  int _likePulseTick = 0;
  bool _showLikeInlineFeedback = false;
  int _likeFeedbackToken = 0;
  final LayerLink _editSpotlightLink = LayerLink();
  final GlobalKey _editSpotlightTargetKey = GlobalKey();
  Size? _editSpotlightSize;
  _HeroBannerVM? _editSpotlightVm;
  _LocalWeather? _editSpotlightWeather;
  bool _editSpotlightIsTomorrow = false;

  // Real weather cache (loaded once on init, fallback to fake if API fails).
  OutfitWeatherDaySnapshot? _weatherSnapToday;
  OutfitWeatherDaySnapshot? _weatherSnapTomorrow;
  bool _weatherLoaded = false;
  String? _weatherLoadError;
  DateTime? _weatherUpdatedAt;

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    if (_weatherLoaded || _weatherLoading) return;
    _weatherLoading = true;
    final svc = HourlyWeatherService();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    try {
      final results = await Future.wait([
        svc.getWeatherForCityAndDate(city: 'Martin', date: today),
        svc.getWeatherForCityAndDate(city: 'Martin', date: tomorrow),
      ]);
      if (!mounted) return;
      setState(() {
        _weatherSnapToday = results[0];
        _weatherSnapTomorrow = results[1];
        _weatherLoaded = true;
        _weatherLoadError = null;
        _weatherUpdatedAt = DateTime.now();
      });
      debugPrint(
        'HOME_WEATHER_LOAD api_assign today_openMeteo=${results[0].fromOpenMeteo} '
        'tomorrow_openMeteo=${results[1].fromOpenMeteo} '
        'today_basis=${results[0].mainChipBasis} tomorrow_basis=${results[1].mainChipBasis}',
      );
      for (final label in ['today', 'tomorrow']) {
        final s = label == 'today' ? results[0] : results[1];
        if (!s.fromOpenMeteo) {
          debugPrint(
            '[HOME_WEATHER_DEBUG][fallback_reason] $label: ${s.openMeteoFailureNote ?? 'unknown_service_fallback'}',
          );
        }
      }
      _scheduleHomeWeatherDebugLogAfterFrame(today, tomorrow);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weatherLoaded = true;
        _weatherLoadError = e.toString();
        _weatherUpdatedAt = DateTime.now();
      });
      debugPrint('[HOME_WEATHER_DEBUG][fallback_reason] load_exception: $e');
      _scheduleHomeWeatherDebugLogAfterFrame(today, tomorrow);
    } finally {
      _weatherLoading = false;
    }
  }

  void _scheduleHomeWeatherDebugLogAfterFrame(DateTime today, DateTime tomorrow) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _logHomeWeatherDebug(contextTag: 'fetch_done', selectedDate: today);
      _logHomeWeatherDebug(contextTag: 'fetch_done', selectedDate: tomorrow);
    });
  }

  OutfitWeatherDaySnapshot? _weatherSnapForNormalizedDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return _weatherSnapToday;
    if (d == today.add(const Duration(days: 1))) return _weatherSnapTomorrow;
    return null;
  }

  String _shortWeatherErr(String raw) {
    final s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length <= 72) return s;
    return '${s.substring(0, 69)}...';
  }

  void _logHomeWeatherDebug({
    required String contextTag,
    required DateTime selectedDate,
  }) {
    const city = 'Martin';
    final norm = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final snap = _weatherSnapForNormalizedDate(norm);
    final w = _weatherForDate(selectedDate);

    late final String source;
    if (!_weatherLoaded && _weatherLoadError == null) {
      source = 'Loading';
    } else if (_weatherLoadError != null) {
      source = 'Error: ${_shortWeatherErr(_weatherLoadError!)}';
    } else if (snap == null) {
      source = 'Fallback';
    } else {
      source = snap.fromOpenMeteo ? 'Open-Meteo' : 'Fallback';
    }

    if (snap == null && _weatherLoaded && _weatherLoadError == null) {
      debugPrint(
        '[HOME_WEATHER_DEBUG][fallback_reason] snapshot_cache_miss date=$norm '
        '(expected only non-home calendar days)',
      );
    } else if (snap != null && !snap.fromOpenMeteo) {
      debugPrint(
        '[HOME_WEATHER_DEBUG][fallback_reason] ${snap.openMeteoFailureNote ?? 'service_internal_fallback'}',
      );
    }

    final rain = snap?.willRain ?? w.isRainy;
    final wind = snap?.isWindy ?? w.isWindy;
    final summary = snap?.summaryText ?? w.summarySubtitle;

    final now = DateTime.now();
    final todayNorm = DateTime(now.year, now.month, now.day);
    final isToday = norm == todayNorm;
    final isTomorrow = norm == todayNorm.add(const Duration(days: 1));

    final chipHour = snap?.mainChipHour;
    final chipBasis = snap?.mainChipBasis ?? 'n/a';
    final morn = snap?.morningTempC;
    final aft = snap?.noonTempC;
    final eve = snap?.eveningTempC;
    final chipT = snap?.mainChipTempC ?? w.tempC;

    final rm = snap?.morningRainSegment;
    final ra = snap?.afternoonRainSegment;
    final re = snap?.eveningRainSegment;

    debugPrint(
      '[HOME_WEATHER_DEBUG][$contextTag] date=$norm isToday=$isToday isTomorrow=$isTomorrow '
      'city=$city source=$source updatedAt=$_weatherUpdatedAt '
      'mainChipTempC=$chipT mainChipHour=$chipHour mainChipBasis=$chipBasis '
      'morningTempC=$morn afternoonTempC=$aft eveningTempC=$eve '
      'rainSegMorning=$rm rainSegAfternoon=$ra rainSegEvening=$re '
      'outfitTempC=${w.tempC} rain=$rain wind=$wind summary=$summary',
    );
  }

  void _setDayIndex(int index) {
    setState(() {
      _dayIndex = index;
      _isOutfitEditMode = false;
      _focusedEditType = null;
      _likePulseTick = 0;
      _showLikeInlineFeedback = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final date = index == 1 ? today.add(const Duration(days: 1)) : today;
      _logHomeWeatherDebug(contextTag: 'toggle_day', selectedDate: date);
    });
  }

  List<_HeroOutfitItem> _effectiveOutfitItems(List<_HeroOutfitItem> source) {
    return _editedOutfitByDay[_dayIndex] ?? source;
  }

  String _heroRenderSignature(List<_HeroOutfitItem> items) {
    return items
        .map((e) => '${e.type.name}:${e.wardrobeItemId ?? ''}:${e.label}')
        .join('|');
  }

  String _canonicalTypeFromRaw(Map<String, dynamic> raw) {
    final blob = _normalizedScaleToken(
      '${raw['name'] ?? ''} ${raw['categoryKey'] ?? raw['category'] ?? ''} '
      '${raw['subCategoryKey'] ?? raw['subCategory'] ?? ''} ${raw['mainGroupKey'] ?? raw['mainGroup'] ?? ''}',
    );
    bool has(List<String> words) =>
        words.any((w) => blob.contains(_normalizedScaleToken(w)));
    if (has(['short', 'kratasy', 'kraťasy'])) return 'shorts';
    if (has(['jeans', 'rifle', 'nohavice', 'pants'])) return 'long_pants';
    if (has(['t-shirt', 'tricko', 'tričko'])) return 'tshirt';
    if (has(['tank', 'tielko'])) return 'tank_top';
    if (has(['hoodie', 'mikina'])) return 'hoodie';
    if (has(['sneaker', 'tenisky', 'shoes', 'obuv'])) return 'sneakers';
    if (has(['coat', 'kabat', 'kabát', 'jacket', 'bunda', 'blazer', 'sako'])) {
      return 'outerwear';
    }
    return 'other';
  }

  String _canonicalTypeFromHeroItem(_HeroOutfitItem item) {
    return _canonicalTypeFromRaw(<String, dynamic>{
      'name': item.label,
      'categoryKey': item.categoryKey ?? '',
      'subCategoryKey': item.subCategoryKey ?? '',
      'mainGroupKey': item.type.name,
    });
  }

  void _syncEditableOutfitFromSource(List<_HeroOutfitItem> source) {
    if (source.isEmpty) {
      final existing = _editedOutfitByDay[_dayIndex];
      final wasManual = _editedManuallyByDay[_dayIndex] ?? false;
      // Keep accepted manual edits stable through transient loading/source-empty frames.
      if (wasManual && existing != null && existing.isNotEmpty) {
        return;
      }
      _editedOutfitByDay.remove(_dayIndex);
      _lastSourceSignatureByDay.remove(_dayIndex);
      _editedManuallyByDay.remove(_dayIndex);
      return;
    }
    final sourceSig = _heroRenderSignature(source);
    final existing = _editedOutfitByDay[_dayIndex];
    final wasManual = _editedManuallyByDay[_dayIndex] ?? false;
    final lastSourceSig = _lastSourceSignatureByDay[_dayIndex];
    final shouldReplace = existing == null || (!wasManual && lastSourceSig != sourceSig);
    if (shouldReplace) {
      _editedOutfitByDay[_dayIndex] = List<_HeroOutfitItem>.from(source);
      _lastSourceSignatureByDay[_dayIndex] = sourceSig;
      _editedManuallyByDay[_dayIndex] = false;
    }
  }

  void _setEditedItems(
    List<_HeroOutfitItem> items, {
    bool markManual = true,
    String reasonSource = 'swap',
  }) {
    setState(() {
      final normalized = _orderedHeroOutfitItems(items);
      _editedOutfitByDay[_dayIndex] = normalized;
      _editedManuallyByDay[_dayIndex] = markManual;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final date = _dayIndex == 1 ? today.add(const Duration(days: 1)) : today;
      final dateKey = _dateKey(date);
      final existing = _homeDayHeroCacheByDateKey[dateKey];
      final weather = _weatherForDate(date);
      final weatherSig = _homeWeatherSignature(weather);
      final reason = _regenerateStylistReason(
        date: date,
        outfitItems: normalized,
        source: reasonSource,
      );
      _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
        state: _HeroTodayState(
          vm: _HeroBannerVM(
            description: reason.isNotEmpty
                ? reason
                : (existing?.state.vm.description ?? 'Upravený outfit pre tento deň.'),
          ),
          outfitItems: normalized,
          source: markManual ? 'edited' : (existing?.state.source ?? 'local'),
        ),
        weatherSignature: weatherSig,
        wardrobeSignature: existing?.wardrobeSignature ?? '',
      );
      if (_focusedEditType != null &&
          !_editedOutfitByDay[_dayIndex]!.any((it) => it.type == _focusedEditType)) {
        _focusedEditType = null;
      }
    });
  }

  String _regenerateStylistReason({
    required DateTime date,
    required List<_HeroOutfitItem> outfitItems,
    required String source,
  }) {
    final weather = _weatherForDate(date);
    final ids = outfitItems
        .map((e) => e.wardrobeItemId)
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .join(',');
    final bottom = outfitItems.firstWhere(
      (it) => it.type == _HeroWearType.bottom,
      orElse: () => const _HeroOutfitItem(
        type: _HeroWearType.bottom,
        icon: Icons.style,
        label: '',
      ),
    );
    final hasLayer = outfitItems.any((it) => it.type == _HeroWearType.outerwear);
    final bottomLabel = _normalizedScaleToken(bottom.label);
    final isShorts = bottomLabel.contains('short') ||
        bottomLabel.contains('krat') ||
        bottomLabel.contains('sukn');
    final isJeans = bottomLabel.contains('jeans') ||
        bottomLabel.contains('rifl') ||
        bottomLabel.contains('nohav');
    final rainIncoming = weather.isRainy || weather.afternoonRainSegment || weather.eveningRainSegment;

    final lines = <String>[];
    if (weather.briefingMorningC != null &&
        weather.briefingAfternoonC != null &&
        weather.briefingEveningC != null) {
      lines.add(
        'Ráno je okolo ${weather.briefingMorningC} °C a poobede sa to vytiahne na ${weather.briefingAfternoonC} °C.',
      );
    } else {
      lines.add('Dnes je približne ${weather.tempC} °C, takže sa oplatí ísť skôr prakticky než ťažko.');
    }

    if (isShorts && weather.tempC >= 19 && !rainIncoming) {
      lines.add('Cez deň bude príjemne, takže šortky dnes dávajú väčší zmysel než rifle.');
    } else if (isJeans && weather.tempC >= 20 && !rainIncoming) {
      lines.add('Aj keď je teplejšie, tento spodok je stále OK, ak chceš viac krytia počas dňa.');
    } else {
      lines.add('Outfit je nastavený tak, aby bol pohodlný cez deň a nezbytočne ťažký.');
    }

    if (rainIncoming) {
      final rainTime = (weather.rainTimeText ?? '').trim();
      if (rainTime.isNotEmpty) {
        lines.add('Okolo $rainTime môže prísť dážď, tak sa oplatí myslieť na praktickejšiu obuv.');
      } else {
        lines.add('Neskôr môže pršať, takže sa hodí mať praktickejšiu obuv a jednu vrstvu navyše.');
      }
    } else if ((weather.briefingEveningC ?? weather.tempC) <= 10 || hasLayer) {
      lines.add('Večer sa môže ochladiť, tak sa hodí mať jednu vrstvu navyše.');
    }

    final text = lines.take(4).join(' ');
    debugPrint('[HOME_STYLIST_REASON] regenerated=true');
    debugPrint('[HOME_STYLIST_REASON] source=$source');
    debugPrint('[HOME_STYLIST_REASON] currentOutfitIds=$ids');
    return text;
  }

  String _outfitFeedbackKey(List<_HeroOutfitItem> items) {
    final b = StringBuffer();
    for (final it in items) {
      b
        ..write(it.type.name)
        ..write('|')
        ..write(it.label)
        ..write('|')
        ..write(it.imageUrl ?? '')
        ..write(';');
    }
    return b.toString();
  }

  bool _isCurrentOutfitLiked(List<_HeroOutfitItem> items) {
    if (items.isEmpty) return false;
    return _likedOutfitKeyByDay[_dayIndex] == _outfitFeedbackKey(items);
  }

  void _handleLikeTap(List<_HeroOutfitItem> items) {
    if (items.isEmpty) return;
    final key = _outfitFeedbackKey(items);
    final token = ++_likeFeedbackToken;
    setState(() {
      _likedOutfitKeyByDay[_dayIndex] = key;
      _likePulseTick++;
      _showLikeInlineFeedback = true;
    });
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 4100), () {
        if (!mounted || token != _likeFeedbackToken) return;
        setState(() => _showLikeInlineFeedback = false);
      }),
    );
  }

  void _enterOutfitEditMode(List<_HeroOutfitItem> currentItems) {
    if (currentItems.isEmpty) return;
    _syncEditableOutfitFromSource(currentItems);
    final originals = <_HeroWearType, String>{};
    for (final it in currentItems) {
      final id = (it.wardrobeItemId ?? '').trim();
      if (id.isNotEmpty) originals[it.type] = id;
    }
    setState(() {
      _isOutfitEditMode = true;
      _focusedEditType = null;
      _swapRejectedReplacementItemIdsByDay[_dayIndex] = <String>{};
      _swapOriginalItemIdByTypeByDay[_dayIndex] = originals;
      _swapLastSuggestedItemIdByTypeByDay[_dayIndex] = <_HeroWearType, String>{};
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureEditSpotlightSize());
  }

  void _exitOutfitEditMode() {
    setState(() {
      _isOutfitEditMode = false;
      _focusedEditType = null;
      _editSpotlightSize = null;
      _editSpotlightVm = null;
      _editSpotlightWeather = null;
    });
  }

  void _captureEditSpotlightSize() {
    final ctx = _editSpotlightTargetKey.currentContext;
    if (ctx == null) return;
    final rb = ctx.findRenderObject();
    if (rb is! RenderBox) return;
    final newSize = rb.size;
    if (!mounted) return;
    if (_editSpotlightSize == newSize) return;
    setState(() => _editSpotlightSize = newSize);
  }

  Future<bool> _isCurrentUserPremium() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final snap = await _firestore.collection('users').doc(user.uid).get();
      final data = snap.data();
      final status = (data?['subscriptionStatus'] ?? '').toString().toLowerCase();
      final isPremium = data?['isPremium'] == true;
      return isPremium || status == 'premium';
    } catch (_) {
      return false;
    }
  }

  String _heroOutfitSignatureFromItems(List<_HeroOutfitItem> items) {
    final ids = items
        .map((e) => e.wardrobeItemId)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();
    return ids.join('|');
  }

  int _countChangedHeroPieces(List<_HeroOutfitItem> oldList, List<_HeroOutfitItem> newList) {
    final oldByType = {for (final o in oldList) o.type: o};
    var changes = 0;
    for (final n in newList) {
      final o = oldByType[n.type];
      if (o == null) {
        changes++;
        continue;
      }
      final oid = o.wardrobeItemId;
      final nid = n.wardrobeItemId;
      if (oid != null && nid != null) {
        if (oid != nid) changes++;
      } else if (o.label != n.label) {
        changes++;
      }
    }
    return changes;
  }

  Future<void> _handleNewOutfitPressed() async {
    if (_newOutfitGenerating) return;
    final user = _auth.currentUser;
    if (user == null || !mounted) return;

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final activeDate = _isTomorrow ? todayDate.add(const Duration(days: 1)) : todayDate;
      final activeDateKey = _dateKey(activeDate);
      _homeAiForceDifferentNextByDateKey[activeDateKey] = true;
      _homeAiRefreshNonce++;

    setState(() => _newOutfitGenerating = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Skúsim úplne inú kombináciu.'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final wardrobeSnap =
          await _firestore.collection('users').doc(user.uid).collection('wardrobe').get();
      final wardrobe = wardrobeSnap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final ud = userDoc.data();
      final isPremiumUser =
          ud?['isPremium'] == true || ud?['subscriptionStatus'] == 'premium';

      final w = _weatherForDate(activeDate);
      final baseHero =
          _buildTodayHero(date: activeDate, wardrobe: wardrobe, isPremiumUser: isPremiumUser);

      final effectiveItems =
          List<_HeroOutfitItem>.from(_editedOutfitByDay[_dayIndex] ?? baseHero.outfitItems);

      final excluded = <String>{
        for (final it in effectiveItems)
          if ((it.wardrobeItemId ?? '').isNotEmpty) it.wardrobeItemId!,
      };

      final rejectedSigs =
          Set<String>.from(_rejectedOutfitCombinationKeysByDay[_dayIndex] ?? {});
      final prevSig = _heroOutfitSignatureFromItems(effectiveItems);
      if (prevSig.isNotEmpty) {
        rejectedSigs.add(prevSig);
      }
      _rejectedOutfitCombinationKeysByDay[_dayIndex] = rejectedSigs;

      final rec = _recommendOutfitForWeather(
        wardrobe: wardrobe,
        weather: w,
        isPremiumUser: isPremiumUser,
        excludedItemIds: excluded,
        rejectedCombinationSignatures: rejectedSigs,
        previousOutfitItemIds: excluded,
        forceDifferentOutfit: effectiveItems.isNotEmpty,
      );

      if (!mounted) return;

      if (rec == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nepodarilo sa poskladať nový outfit z šatníka.'),
          ),
        );
        return;
      }

      final newIds = rec.items
          .map((e) => e.wardrobeItemId)
          .whereType<String>()
          .toList(growable: false);
      final changed = _countChangedHeroPieces(effectiveItems, rec.items);
      final newSig = _heroOutfitSignatureFromItems(rec.items);

      debugPrint(
        '[NEW_OUTFIT] originalIds=$excluded rejectedCombinations=${rejectedSigs.length} '
        'newIds=$newIds changedPieces=$changed prevSig=$prevSig newSig=$newSig',
      );

      final identical = effectiveItems.isNotEmpty &&
          (changed == 0 || (prevSig.isNotEmpty && prevSig == newSig));

      if (identical) {
        debugPrint('[NEW_OUTFIT] WARNING identical or zero-change outfit — UI neprepísané');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nepodarilo sa nájsť dosť odlišnú kombináciu — skontroluj šatník.',
            ),
          ),
        );
        return;
      }

      if (changed < effectiveItems.length && effectiveItems.length >= 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'V šatníku nemáš dosť alternatív, vymenil som aspoň dostupné kúsky.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      _setEditedItems(rec.items, reasonSource: 'new_outfit');
      setState(() {
        _likedOutfitKeyByDay.remove(_dayIndex);
        _likePulseTick = 0;
        _showLikeInlineFeedback = false;
      });
    } finally {
      if (mounted) {
        setState(() => _newOutfitGenerating = false);
      }
    }
  }

  Future<void> _openVibeComposerPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (sheetContext) {
        return _VibeComposerSheet(onPhotoSelected: _openVibeWorkspaceFromPhoto);
      },
    );
  }

  void _openVibeWorkspaceFromPhoto(XFile photo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VibeRecreationWorkspaceScreen(
          photo: photo,
          onAnalyzeInspiration: _analyzeAndBuildVibeResult,
        ),
      ),
    );
  }

  Future<_VibeRecreationResult?> _analyzeAndBuildVibeResult(XFile photo) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final bytes = await photo.readAsBytes();
    if (bytes.isEmpty) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final resized = img.copyResize(decoded, width: 72, height: 72, interpolation: img.Interpolation.average);
    final analysis = _analyzeInspirationImage(resized);

    final snap = await _firestore.collection('users').doc(user.uid).collection('wardrobe').get();
    final wardrobe = snap.docs.map((d) => d.data()).toList();
    if (wardrobe.isEmpty) return null;

    final composition = _buildVibeInspiredOutfit(wardrobe: wardrobe, analysis: analysis);
    final pools = _buildVibeCandidatePools(wardrobe: wardrobe, analysis: analysis);
    final picks = composition.picks;
    final items = _orderedHeroOutfitItems(
      picks.map((p) => _heroItemFromWardrobe(raw: p.item, type: p.type)).toList(),
    );
    return _VibeRecreationResult(
      items: items,
      summary: _buildVibeSummary(analysis),
      candidatePools: pools,
      honestyMessage: composition.honestyMessage,
      missingPieces: composition.missingPieces,
      suggestedFillers: composition.suggestedFillers,
    );
  }

  _VibeImageAnalysis _analyzeInspirationImage(img.Image image) {
    final bins = List<int>.filled(6, 0);
    var lumSum = 0.0;
    var satSum = 0.0;
    final lumValues = <double>[];
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
        final sat = maxC == 0 ? 0.0 : (maxC - minC) / maxC;
        lumSum += lum;
        satSum += sat;
        lumValues.add(lum);
        final hueBin = _rgbHueBin(r: r, g: g, b: b);
        bins[hueBin]++;
      }
    }
    final total = (image.width * image.height).toDouble();
    final avgLum = lumSum / total;
    final avgSat = satSum / total;
    var variance = 0.0;
    for (final v in lumValues) {
      final d = v - avgLum;
      variance += d * d;
    }
    final contrast = math.sqrt(variance / total);
    final dominant = <int>[0, 1, 2];
    dominant.sort((a, b) => bins[b].compareTo(bins[a]));
    final layeringScore = (contrast * 1.4 + avgSat * 0.35).clamp(0.0, 1.0);
    final layering = layeringScore > 0.42 ? 4 : 3;
    final layeredOutfit = layering >= 4 || contrast > 0.17 || (avgLum < 0.50 && avgSat > 0.18);
    final redAccentImportant = bins[1] > total * 0.14;
    final denimLightImportant = bins[4] > total * 0.12 && avgLum > 0.36;
    final darkBottomImportant = avgLum < 0.50 || bins[0] > total * 0.20;
    final style = avgSat > 0.48
        ? _VibeStyle.sporty
        : (avgLum < 0.34 && contrast > 0.24 ? _VibeStyle.street : _VibeStyle.clean);
    return _VibeImageAnalysis(
      avgLuminance: avgLum,
      avgSaturation: avgSat,
      contrast: contrast,
      dominantHueBins: dominant,
      layeringCount: layering,
      layeredOutfit: layeredOutfit,
      redAccentImportant: redAccentImportant,
      denimLightImportant: denimLightImportant,
      darkBottomImportant: darkBottomImportant,
      style: style,
    );
  }

  int _rgbHueBin({required double r, required double g, required double b}) {
    final rn = r / 255.0;
    final gn = g / 255.0;
    final bn = b / 255.0;
    final maxC = math.max(rn, math.max(gn, bn));
    final minC = math.min(rn, math.min(gn, bn));
    final delta = maxC - minC;
    if (delta < 0.01) return 0; // neutral
    double hue;
    if (maxC == rn) {
      hue = 60 * (((gn - bn) / delta) % 6);
    } else if (maxC == gn) {
      hue = 60 * (((bn - rn) / delta) + 2);
    } else {
      hue = 60 * (((rn - gn) / delta) + 4);
    }
    if (hue < 0) hue += 360;
    if (hue < 35 || hue >= 330) return 1; // red
    if (hue < 75) return 2; // yellow
    if (hue < 165) return 3; // green
    if (hue < 255) return 4; // blue
    return 5; // purple/pink
  }

  _VibeComposition _buildVibeInspiredOutfit({
    required List<Map<String, dynamic>> wardrobe,
    required _VibeImageAnalysis analysis,
  }) {
    final used = <int>{};
    final results = <_TypedWardrobePick>[];
    final missing = <String>[];
    final fillers = <String>{};
    _ScoredRaw? pickType(
      _HeroWearType type, {
      List<String> preferred = const [],
      List<String> discouraged = const [],
      bool preferDarkBottom = false,
      double minScore = 0.0,
    }) {
      final candidates = <(int, Map<String, dynamic>)>[];
      for (var i = 0; i < wardrobe.length; i++) {
        if (used.contains(i)) continue;
        final raw = wardrobe[i];
        if (!_heroWardrobeMatchesType(raw, type)) continue;
        candidates.add((i, raw));
      }
      if (candidates.isEmpty) return null;
      (int, Map<String, dynamic>)? best;
      var bestScore = -1e9;
      for (final c in candidates) {
        final score = _scoreWardrobeForVibe(
          raw: c.$2,
          type: type,
          analysis: analysis,
          preferredKeywords: preferred,
          discouragedKeywords: discouraged,
          preferDarkBottom: preferDarkBottom,
        );
        if (score > bestScore) {
          bestScore = score;
          best = c;
        }
      }
      if (best == null) return null;
      if (bestScore < minScore) return null;
      used.add(best.$1);
      return _ScoredRaw(raw: best.$2, score: bestScore);
    }

    final layeredStreet = analysis.style == _VibeStyle.street || analysis.layeredOutfit;

    // Real vibe slots for layered composition.
    final outerwear = layeredStreet
        ? pickType(
            _HeroWearType.outerwear,
            preferred: const [
              'jacket',
              'bunda',
              'denim',
              'overshirt',
              'coat',
              'blazer',
              'bomber',
            ],
            discouraged: const ['hoodie', 'mikina', 'sweatshirt', 'sveter', 'winter', 'puffer', 'parka'],
            minScore: 1.15,
          )
        : null;

    final innerTop = pickType(
      _HeroWearType.top,
      preferred: layeredStreet
          ? const [
              'hoodie',
              'mikina',
              'sweatshirt',
              'sveter',
              'crewneck',
            ]
          : const ['shirt', 'tricko', 'tričko', 'top'],
      discouraged: [
        if (layeredStreet) ...const ['tank', 'tielko'],
        if (analysis.redAccentImportant) ...const ['white', 'biela', 'cream'],
      ],
      minScore: layeredStreet ? 1.05 : 0.75,
    );

    final bottom = pickType(
      _HeroWearType.bottom,
      preferred: const ['jeans', 'rifle', 'pants', 'nohav'],
      preferDarkBottom: analysis.darkBottomImportant,
      discouraged: analysis.darkBottomImportant ? const ['blue jeans', 'modre rifle', 'light blue'] : const [],
      minScore: analysis.darkBottomImportant ? 1.00 : 0.75,
    );

    final shoes = pickType(
      _HeroWearType.shoes,
      preferred: const ['sneaker', 'tenis', 'sport', 'runner'],
      minScore: 0.70,
    );

    if (innerTop != null) {
      results.add(_TypedWardrobePick(type: _HeroWearType.top, item: innerTop.raw));
    } else if (analysis.redAccentImportant) {
      missing.add('Červená mikina');
      fillers.add('Červená mikina');
    }
    if (bottom != null) {
      results.add(_TypedWardrobePick(type: _HeroWearType.bottom, item: bottom.raw));
    } else if (analysis.darkBottomImportant) {
      missing.add('Čierne nohavice');
      fillers.add('Čierne slim jeans');
    }
    if (shoes != null) results.add(_TypedWardrobePick(type: _HeroWearType.shoes, item: shoes.raw));
    if (outerwear != null) {
      results.add(_TypedWardrobePick(type: _HeroWearType.outerwear, item: outerwear.raw));
    } else if (layeredStreet) {
      missing.add(analysis.denimLightImportant ? 'Svetlá denim bunda' : 'Ľahká bunda');
      fillers.add(analysis.denimLightImportant ? 'Svetlá denim bunda' : 'Ľahká bunda');
    }

    // If inspiration is layered, strongly prefer 4-piece composition.
    if (layeredStreet && outerwear == null) {
      final emergencyOuter = pickType(
        _HeroWearType.outerwear,
        preferred: const ['jacket', 'bunda', 'coat', 'blazer', 'overshirt'],
        minScore: 1.25,
      );
      if (emergencyOuter != null) {
        results.add(_TypedWardrobePick(type: _HeroWearType.outerwear, item: emergencyOuter.raw));
        missing.remove('Svetlá denim bunda');
        missing.remove('Ľahká bunda');
      }
    }

    if (analysis.redAccentImportant && innerTop != null) {
      final topBlob = _normalizedClothingToken(_heroBlob(innerTop.raw));
      final topIsRedish = _containsAnyNormalized(topBlob, ['red', 'cerven', 'bordo', 'wine']);
      if (!topIsRedish) {
        missing.add('Červená mikina');
        fillers.add('Červená mikina');
      }
    }
    if (analysis.denimLightImportant && outerwear != null) {
      final outerBlob = _normalizedClothingToken(_heroBlob(outerwear.raw));
      final denimLight = _containsAnyNormalized(
        outerBlob,
        ['denim', 'light blue', 'svetla bunda', 'modra denim', 'riflova bunda'],
      );
      if (!denimLight) {
        missing.add('Svetlá denim bunda');
        fillers.add('Svetlá denim bunda');
      }
    }
    if (analysis.darkBottomImportant && bottom != null) {
      final bottomBlob = _normalizedClothingToken(_heroBlob(bottom.raw));
      final bottomDark = _containsAnyNormalized(bottomBlob, ['black', 'cier', 'tmav', 'navy']);
      if (!bottomDark) {
        missing.add('Čierne nohavice');
        fillers.add('Čierne slim jeans');
      }
    }
    final uniqueMissing = missing.toSet().toList(growable: false);
    final honesty = uniqueMissing.isEmpty
        ? null
        : 'Tento vibe sa z tvojho šatníka nedá poskladať.';
    return _VibeComposition(
      picks: results,
      missingPieces: uniqueMissing,
      suggestedFillers: fillers.toList(growable: false),
      honestyMessage: honesty,
    );
  }

  Map<_HeroWearType, List<_HeroOutfitItem>> _buildVibeCandidatePools({
    required List<Map<String, dynamic>> wardrobe,
    required _VibeImageAnalysis analysis,
  }) {
    final pools = <_HeroWearType, List<_HeroOutfitItem>>{};
    for (final type in _HeroWearType.values) {
      final scored = <(Map<String, dynamic>, double)>[];
      for (final raw in wardrobe) {
        if (!_heroWardrobeMatchesType(raw, type)) continue;
        final score = _scoreWardrobeForVibe(raw: raw, type: type, analysis: analysis);
        scored.add((raw, score));
      }
      scored.sort((a, b) => b.$2.compareTo(a.$2));
      final uniqueLabels = <String>{};
      final result = <_HeroOutfitItem>[];
      for (final e in scored) {
        final item = _heroItemFromWardrobe(raw: e.$1, type: type);
        final sig = '${item.label}_${item.imageUrl ?? ''}'.toLowerCase();
        if (uniqueLabels.contains(sig)) continue;
        uniqueLabels.add(sig);
        result.add(item);
        if (result.length >= 8) break;
      }
      if (result.isNotEmpty) {
        pools[type] = _orderedHeroOutfitItems(result.where((i) => i.type == type).toList());
      }
    }
    return pools;
  }

  double _scoreWardrobeForVibe({
    required Map<String, dynamic> raw,
    required _HeroWearType type,
    required _VibeImageAnalysis analysis,
    List<String> preferredKeywords = const [],
    List<String> discouragedKeywords = const [],
    bool preferDarkBottom = false,
  }) {
    final blob = _normalizedClothingToken(_heroBlob(raw));
    final colorScore = _colorMatchScore(blob: blob, analysis: analysis);
    var styleScore = 0.0;
    switch (analysis.style) {
      case _VibeStyle.sporty:
        if (_containsAnyNormalized(blob, ['sneaker', 'tenis', 'hoodie', 'mikina', 'jogger', 'track'])) {
          styleScore += 0.9;
        }
        break;
      case _VibeStyle.clean:
        if (_containsAnyNormalized(blob, ['shirt', 'kosela', 'koše', 'blazer', 'sako', 'coat', 'kabat'])) {
          styleScore += 0.85;
        }
        break;
      case _VibeStyle.street:
        if (_containsAnyNormalized(blob, ['oversize', 'hoodie', 'mikina', 'jacket', 'bunda', 'jeans'])) {
          styleScore += 0.88;
        }
        break;
    }
    final darknessPref = analysis.avgLuminance < 0.45;
    final hasDark = _containsAnyNormalized(blob, ['black', 'cier', 'tmav', 'navy', 'antracit']);
    final hasLight = _containsAnyNormalized(blob, ['white', 'biel', 'beige', 'krem', 'cream']);
    var toneScore = 0.0;
    if (darknessPref && hasDark) toneScore = 0.55;
    if (!darknessPref && hasLight) toneScore = 0.55;
    if (type == _HeroWearType.outerwear && analysis.layeringCount >= 4) toneScore += 0.35;
    var keywordScore = 0.0;
    if (preferredKeywords.isNotEmpty && _containsAnyNormalized(blob, preferredKeywords)) {
      keywordScore += 0.75;
    }
    if (discouragedKeywords.isNotEmpty && _containsAnyNormalized(blob, discouragedKeywords)) {
      keywordScore -= 0.40;
    }
    if (preferDarkBottom &&
        type == _HeroWearType.bottom &&
        _containsAnyNormalized(blob, ['black', 'cier', 'tmav', 'dark', 'navy', 'antracit'])) {
      keywordScore += 0.55;
    }
    if (type == _HeroWearType.shoes &&
        _containsAnyNormalized(blob, ['sneaker', 'tenis', 'sport', 'runner'])) {
      keywordScore += 0.45;
    }
    return colorScore * 1.1 + styleScore + toneScore + keywordScore;
  }

  double _colorMatchScore({required String blob, required _VibeImageAnalysis analysis}) {
    final dominantNames = analysis.dominantHueBins
        .map((b) => _hueBinKeywords(b))
        .expand((x) => x)
        .toList(growable: false);
    var score = 0.0;
    for (final key in dominantNames) {
      if (_containsAnyNormalized(blob, [key])) {
        score += 0.26;
      }
    }
    if (analysis.avgLuminance < 0.38 &&
        _containsAnyNormalized(blob, ['black', 'cier', 'tmav', 'dark', 'navy'])) {
      score += 0.34;
    }
    if (analysis.avgLuminance > 0.60 &&
        _containsAnyNormalized(blob, ['white', 'biel', 'cream', 'beige', 'light'])) {
      score += 0.30;
    }
    return score;
  }

  List<String> _hueBinKeywords(int bin) {
    switch (bin) {
      case 1:
        return const ['red', 'bordo', 'vín', 'wine'];
      case 2:
        return const ['yellow', 'mustard', 'horcic'];
      case 3:
        return const ['green', 'olive', 'khaki'];
      case 4:
        return const ['blue', 'navy', 'modr', 'denim'];
      case 5:
        return const ['purple', 'lila', 'pink', 'fuchsia'];
      default:
        return const ['black', 'white', 'gray', 'grey', 'beige', 'neutral'];
    }
  }

  String _buildVibeSummary(_VibeImageAnalysis analysis) {
    if (analysis.style == _VibeStyle.street && analysis.avgLuminance < 0.42) {
      return 'Streetwear layered vibe';
    }
    if (analysis.avgLuminance < 0.42) {
      return 'Tmavý kontrastný outfit';
    }
    if (analysis.style == _VibeStyle.clean) {
      return 'Clean mestský štýl';
    }
    return 'Casual mestský štýl';
  }

  Future<void> _handleSwapPieceTap(
    BuildContext context,
    List<_HeroOutfitItem> currentItems,
  ) async {
    final isPremiumMode = await _isCurrentUserPremium();
    if (!mounted) return;
    if (currentItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Najprv potrebujeme kompletný outfit.')),
      );
      return;
    }
    final currentIds = currentItems
        .map((e) => e.wardrobeItemId)
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .join(',');
    debugPrint('[HOME_SWAP] opened currentOutfitIds=$currentIds');
    debugPrint('[HOME_SWAP] keeping_existing_hero=true');
    if (isPremiumMode) {
      _enterOutfitEditMode(currentItems);
      return;
    }
    _enterOutfitEditMode(currentItems);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _wardrobeStream(String uid) {
    return _firestore.collection('users').doc(uid).collection('wardrobe').snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  _LocalWeather _weatherForDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final normalizedDate = DateTime(date.year, date.month, date.day);
    OutfitWeatherDaySnapshot? snap;
    if (normalizedDate == today) {
      snap = _weatherSnapToday;
    } else if (normalizedDate == today.add(const Duration(days: 1))) {
      snap = _weatherSnapTomorrow;
    }
    if (snap != null) {
      return _LocalWeather.fromSnapshot(snap);
    }
    return _LocalWeather.fallbackFor(date);
  }

  String _emptyHeroOutfitDescription(_LocalWeather w) {
    const base =
        'Dnes zatiaľ nemám dosť vhodných kúskov na kompletný outfit. Skús pridať viac oblečenia do šatníka.';
    if (!w.isRainy && !w.isWindy && w.tempC >= 12) return base;
    if (w.isRainy && w.isWindy) {
      return '$base Keď už budeš vonku, oplatí sa mať poruke dáždnik a niečo, čo drží tvar aj pri vetre.';
    }
    if (w.isRainy) {
      return '$base Keď plánuješ deň mimo domu, dáždnik vie ušetriť nervy aj outfit.';
    }
    if (w.isWindy) {
      return '$base Pri silnejšom vetre sa oplatí myslieť na pevnejší strih a komfort pri pohybe.';
    }
    return '$base Pri chladnejšom počasí sa vyplatí mať po ruke aspoň jednu teplejšiu vrstvu.';
  }

  _HeroTodayState _buildTodayHero({
    required DateTime date,
    required List<Map<String, dynamic>> wardrobe,
    required bool isPremiumUser,
    bool dataReady = true,
  }) {
    final dayIdx = _dayIndexForDate(date);
    final dateKey = _dateKey(date);
    final w = _weatherForDate(date);
    final weatherSignature = _homeWeatherSignature(w);
    final wardrobeSignature = _wardrobeSignature(wardrobe);
    final dayLabel = dayIdx == 0 ? 'today' : 'tomorrow';
    final cache = _homeDayHeroCacheByDateKey[dateKey];

    if (cache != null &&
        cache.weatherSignature == weatherSignature &&
        cache.wardrobeSignature == wardrobeSignature) {
      if (cache.state.source == 'edited') {
        debugPrint('[HOME_DAY_CACHE] preserved_edited_outfit=true');
        debugPrint('[HOME_DAY_CACHE] preserved_swap_state=true');
      }
      debugPrint('[HOME_DAY_CACHE] instant_restore=true day=$dayLabel');
      return cache.state;
    }
    debugPrint('[HOME_DAY_CACHE] miss day=$dayLabel');

    final manualItems = _editedOutfitByDay[dayIdx] ?? const <_HeroOutfitItem>[];
    final isManual = (_editedManuallyByDay[dayIdx] ?? false) && manualItems.isNotEmpty;
    if (isManual) {
      final reason = _regenerateStylistReason(
        date: date,
        outfitItems: manualItems,
        source: 'swap',
      );
      final state = _HeroTodayState(
        vm: _HeroBannerVM(
          description:
              reason.isNotEmpty ? reason : 'Upravený outfit pre tento deň.',
        ),
        outfitItems: manualItems,
        source: 'edited',
      );
      _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
        state: state,
        weatherSignature: weatherSignature,
        wardrobeSignature: wardrobeSignature,
      );
      return state;
    }
    final swapVisibleItems = _editedOutfitByDay[dayIdx] ?? const <_HeroOutfitItem>[];
    if (_isOutfitEditMode && swapVisibleItems.isNotEmpty) {
      final state = _HeroTodayState(
        vm: const _HeroBannerVM(description: 'Vyber kúsok, ktorý chceš vymeniť.'),
        outfitItems: swapVisibleItems,
        source: 'edited',
      );
      _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
        state: state,
        weatherSignature: weatherSignature,
        wardrobeSignature: wardrobeSignature,
      );
      return state;
    }
    if (!dataReady) {
      return _HeroTodayState(
        vm: const _HeroBannerVM(description: 'Pripravujem dnešný outfit...'),
        outfitItems: const <_HeroOutfitItem>[],
        source: 'loading',
        loadingReason: 'wardrobe_or_weather_pending',
      );
    }
    final latestAiSignature = _homeAiLatestSignatureByDateKey[dateKey];
    final aiEntry =
        latestAiSignature == null ? null : _homeAiCacheBySignature[latestAiSignature];
    final aiCachedRec = aiEntry?.recommendation;
    final aiPendingForDate = _homeAiRequestInFlight.any(
      (sig) => sig.startsWith('$dateKey|'),
    );
    if (aiCachedRec != null) {
      if (_lastAiPreservedSignatureLogged != latestAiSignature) {
        _lastAiPreservedSignatureLogged = latestAiSignature;
        debugPrint('[HOME_AI_OUTFIT] ai_result_preserved=true');
      }
      final state = _HeroTodayState(
        vm: _HeroBannerVM(description: aiCachedRec.reason),
        outfitItems: aiCachedRec.items,
        source: 'ai',
      );
      _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
        state: state,
        weatherSignature: weatherSignature,
        wardrobeSignature: wardrobeSignature,
      );
      return state;
    }

    if (aiEntry == null || aiPendingForDate) {
      return _HeroTodayState(
        vm: const _HeroBannerVM(description: 'Pripravujem dnešný outfit...'),
        outfitItems: const <_HeroOutfitItem>[],
        source: 'loading',
        loadingReason: 'ai_pending_no_cached_ai',
      );
    }

    const localReason = 'ai_failed_or_fallback';
    final fallbackLogKey = '$dateKey|$latestAiSignature|$localReason';
    if (_lastFallbackReasonLoggedKey != fallbackLogKey) {
      _lastFallbackReasonLoggedKey = fallbackLogKey;
      debugPrint('[HOME_AI_OUTFIT] local_fallback_applied reason=ai_failed_or_timeout');
    }
    final localRec = _recommendOutfitForWeatherCached(
      dateKey: dateKey,
      wardrobe: wardrobe,
      weather: w,
      isPremiumUser: isPremiumUser,
    );
    final rec = localRec;

    if (rec == null) {
      final state = _HeroTodayState(
        vm: _HeroBannerVM(
          description: _emptyHeroOutfitDescription(w),
        ),
        outfitItems: const <_HeroOutfitItem>[],
        source: 'local',
      );
      _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
        state: state,
        weatherSignature: weatherSignature,
        wardrobeSignature: wardrobeSignature,
      );
      return state;
    }

    final state = _HeroTodayState(
      vm: _HeroBannerVM(
        description: rec.reason,
      ),
      outfitItems: rec.items,
      source: 'local',
    );
    _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
      state: state,
      weatherSignature: weatherSignature,
      wardrobeSignature: wardrobeSignature,
    );
    return state;
  }

  void _maybeTriggerHomeAiRecommendation({
    required DateTime date,
    required List<Map<String, dynamic>> wardrobe,
    required _LocalWeather weather,
    required bool isPremiumUser,
  }) {
    final user = _auth.currentUser;
    if (user == null) return;
    if (!_weatherLoaded) return;
    if (wardrobe.isEmpty) return;
    final dateKey = _dateKey(date);
    final weatherSignature = _homeWeatherSignature(weather);
    final wardrobeSignature = _wardrobeSignature(wardrobe);
    final cached = _homeDayHeroCacheByDateKey[dateKey];
    if (cached != null &&
        cached.weatherSignature == weatherSignature &&
        cached.wardrobeSignature == wardrobeSignature) {
      return;
    }
    final targetDayIdx = _dayIndexForDate(date);
    final existing = _editedOutfitByDay[targetDayIdx] ?? const <_HeroOutfitItem>[];
    if (_isOutfitEditMode && existing.isNotEmpty) {
      debugPrint('[HOME_AI_OUTFIT] skip reason=swap_mode_existing_outfit');
      return;
    }
    final forceDifferent =
        (_homeAiForceDifferentNextByDateKey[dateKey] ?? false) == true;
    final aiSignature =
        '$dateKey|$weatherSignature|$wardrobeSignature|fd=${forceDifferent ? 1 : 0}|n=$_homeAiRefreshNonce';
    final excluded = <String>{};
    final rejected = Set<String>.from(_rejectedOutfitCombinationKeysByDay[_dayIndex] ?? {});

    final effectiveCurrent = _effectiveOutfitItems(
      _editedOutfitByDay[_dayIndex] ?? const <_HeroOutfitItem>[],
    );
    for (final it in effectiveCurrent) {
      final id = (it.wardrobeItemId ?? '').trim();
      if (id.isNotEmpty) excluded.add(id);
    }
    final prevSig = _heroOutfitSignatureFromItems(effectiveCurrent);
    if (prevSig.isNotEmpty) rejected.add(prevSig);

    final request = _HomeAiRequestContext(
      date: date,
      weather: weather,
      excludedItemIds: excluded,
      rejectedCombinationSignatures: rejected,
      previousOutfitItemIds: excluded,
      forceDifferentOutfit: forceDifferent,
      isPremiumUser: isPremiumUser,
    );

    if (_homeAiCacheBySignature.containsKey(aiSignature)) {
      _homeAiLatestSignatureByDateKey[dateKey] = aiSignature;
      debugPrint('[HOME_AI_OUTFIT] skip reason=cached_signature');
      return;
    }

    if (_homeAiRequestInFlight.contains(aiSignature)) {
      debugPrint('[HOME_AI_OUTFIT] skip reason=in_flight_same_signature');
      return;
    }

    final source = _homeAiTriggerSource(
      dateKey: dateKey,
      weatherSignature: weatherSignature,
      wardrobeSignature: wardrobeSignature,
      forceDifferent: forceDifferent,
    );
    debugPrint('[HOME_AI_OUTFIT] trigger source=$source');
    _homeAiLastTriggeredDateKey = dateKey;
    _homeAiLastWeatherSignatureByDateKey[dateKey] = weatherSignature;
    _homeAiLastWardrobeSignatureByDateKey[dateKey] = wardrobeSignature;
    _homeAiRequestInFlight.add(aiSignature);
    unawaited(_fetchHomeAiRecommendation(
      dateKey: dateKey,
      aiSignature: aiSignature,
      wardrobe: wardrobe,
      request: request,
    ));
  }

  Future<void> _fetchHomeAiRecommendation({
    required String dateKey,
    required String aiSignature,
    required List<Map<String, dynamic>> wardrobe,
    required _HomeAiRequestContext request,
  }) async {
    final weatherContext = _homeAiWeatherContext(request.weather);
    debugPrint(
      '[HOME_AI_OUTFIT] request date=$dateKey forceDifferent=${request.forceDifferentOutfit} '
      'excluded=${request.excludedItemIds.length} rejected=${request.rejectedCombinationSignatures.length}',
    );
    try {
      final result = await _homeAiOutfitService
          .generateHomeOutfit(
            date: request.date,
            weatherContext: weatherContext,
            excludedItemIds: request.excludedItemIds.toList(growable: false),
            rejectedCombinationSignatures: request.rejectedCombinationSignatures.toList(
              growable: false,
            ),
            previousOutfitItemIds: request.previousOutfitItemIds.toList(growable: false),
            forceDifferentOutfit: request.forceDifferentOutfit,
          )
          .timeout(const Duration(seconds: 9));

      if (result.fallback) {
        debugPrint('[HOME_AI_OUTFIT] fallback reason=server_fallback_marker');
        if (!mounted) return;
        setState(() {
          _homeAiCacheBySignature[aiSignature] = _HomeAiCacheEntry(
            signature: aiSignature,
            recommendation: null,
          );
          _homeAiLatestSignatureByDateKey[dateKey] = aiSignature;
          _homeAiForceDifferentNextByDateKey[dateKey] = false;
        });
        return;
      }
      final rec = _mapAiResultToHeroRecommendation(
        aiReply: result.reply,
        aiOutfitItemIds: result.outfitItemIds,
        wardrobe: wardrobe,
        weather: request.weather,
        isPremiumUser: request.isPremiumUser,
      );
      if (rec == null || rec.items.length < 3) {
        debugPrint('[HOME_AI_OUTFIT] fallback reason=invalid_or_short_result');
        if (!mounted) return;
        setState(() {
          _homeAiCacheBySignature[aiSignature] = _HomeAiCacheEntry(
            signature: aiSignature,
            recommendation: null,
          );
          _homeAiLatestSignatureByDateKey[dateKey] = aiSignature;
          _homeAiForceDifferentNextByDateKey[dateKey] = false;
        });
        return;
      }
      final names = rec.items.map((e) => e.label).join(', ');
      final prevRec = _homeAiCacheBySignature[aiSignature]?.recommendation;
      final sameAsCached = _sameHeroRecommendation(prevRec, rec);
      final targetDayIndex = _dayIndexForDate(request.date);
      final displayed = _editedOutfitByDay[targetDayIndex] ?? const <_HeroOutfitItem>[];
      final displayedDiffers = !_sameHeroItemsById(displayed, rec.items);
      if (!mounted) return;
      if (!sameAsCached || displayedDiffers) {
        debugPrint('[HOME_STYLIST_REASON] regenerated=true');
        debugPrint('[HOME_STYLIST_REASON] source=ai_refresh');
        debugPrint(
          '[HOME_STYLIST_REASON] currentOutfitIds=${rec.items.map((e) => e.wardrobeItemId).whereType<String>().where((e) => e.isNotEmpty).join(",")}',
        );
        setState(() {
          _homeAiCacheBySignature[aiSignature] = _HomeAiCacheEntry(
            signature: aiSignature,
            recommendation: rec,
          );
          _homeAiLatestSignatureByDateKey[dateKey] = aiSignature;
          _homeAiForceDifferentNextByDateKey[dateKey] = false;
          _editedManuallyByDay[targetDayIndex] = false;
          _editedOutfitByDay[targetDayIndex] = List<_HeroOutfitItem>.from(rec.items);
          _lastSourceSignatureByDay[targetDayIndex] = _heroRenderSignature(rec.items);
          _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
            state: _HeroTodayState(
              vm: _HeroBannerVM(description: rec.reason),
              outfitItems: rec.items,
              source: 'ai',
            ),
            weatherSignature: _homeWeatherSignature(request.weather),
            wardrobeSignature: _wardrobeSignature(wardrobe),
          );
        });
      } else {
        _homeAiLatestSignatureByDateKey[dateKey] = aiSignature;
        _homeAiForceDifferentNextByDateKey[dateKey] = false;
      }
      debugPrint(
        '[HOME_AI_OUTFIT] success ids=${result.outfitItemIds.join(",")} '
        'confidence=${result.confidence.toStringAsFixed(2)}',
      );
      debugPrint('[HOME_AI_OUTFIT] success names=$names');
      debugPrint('[HOME_AI_OUTFIT] applied_to_hero=true');
    } catch (e) {
      debugPrint('[HOME_AI_OUTFIT] error=$e');
      if (!mounted) return;
      setState(() {
        _homeAiCacheBySignature[aiSignature] = _HomeAiCacheEntry(
          signature: aiSignature,
          recommendation: null,
        );
        _homeAiLatestSignatureByDateKey[dateKey] = aiSignature;
        _homeAiForceDifferentNextByDateKey[dateKey] = false;
      });
    } finally {
      _homeAiRequestInFlight.remove(aiSignature);
    }
  }

  _HeroOutfitRecommendation? _mapAiResultToHeroRecommendation({
    required String aiReply,
    required List<String> aiOutfitItemIds,
    required List<Map<String, dynamic>> wardrobe,
    required _LocalWeather weather,
    required bool isPremiumUser,
  }) {
    if (aiOutfitItemIds.isEmpty) return null;
    final byId = <String, Map<String, dynamic>>{};
    for (final raw in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(raw);
      if (id.isNotEmpty) byId[id] = raw;
    }
    final selected = <Map<String, dynamic>>[];
    for (final id in aiOutfitItemIds) {
      final item = byId[id];
      if (item != null) selected.add(item);
    }
    if (selected.length < 3) return null;

    final typed = _typedPicksFromAiSelected(selected);
    final top = typed[_HeroWearType.top];
    final bottom = typed[_HeroWearType.bottom];
    final shoes = typed[_HeroWearType.shoes];
    if (top == null || bottom == null || shoes == null) {
      return null;
    }
    final orderedIds = <String>[
      OutfitGenerationService.wardrobeItemId(top),
      OutfitGenerationService.wardrobeItemId(bottom),
      OutfitGenerationService.wardrobeItemId(shoes),
      if (typed[_HeroWearType.outerwear] != null)
        OutfitGenerationService.wardrobeItemId(typed[_HeroWearType.outerwear]!),
    ].where((e) => e.isNotEmpty).toList(growable: false);
    final heroCacheKey = 'ai|${orderedIds.join('|')}';
    final ordered = _heroItemsCacheByIdSet[heroCacheKey] ??
        <_HeroOutfitItem>[
          _heroItemFromWardrobe(raw: top, type: _HeroWearType.top),
          _heroItemFromWardrobe(raw: bottom, type: _HeroWearType.bottom),
          _heroItemFromWardrobe(raw: shoes, type: _HeroWearType.shoes),
          if (typed[_HeroWearType.outerwear] != null)
            _heroItemFromWardrobe(
              raw: typed[_HeroWearType.outerwear]!,
              type: _HeroWearType.outerwear,
            ),
        ];
    _heroItemsCacheByIdSet[heroCacheKey] = ordered;
    if (ordered.length < 3) return null;

    final selectedReasonItems = <Map<String, dynamic>>[
      {...top, 'typeKey': 'top'},
      {...bottom, 'typeKey': 'bottom'},
      {...shoes, 'typeKey': 'shoes'},
      if (typed[_HeroWearType.outerwear] != null)
        {...typed[_HeroWearType.outerwear]!, 'typeKey': 'outerwear'},
    ];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(
      weather.calendarDate.year,
      weather.calendarDate.month,
      weather.calendarDate.day,
    );
    final isTomorrowDay = d == today.add(const Duration(days: 1));
    final localReason = OutfitReasonBuilder.build(
      tempC: weather.tempC,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
      isPremium: isPremiumUser,
      selectedItems: selectedReasonItems,
      hasOuterwear: typed[_HeroWearType.outerwear] != null,
      isTomorrow: isTomorrowDay,
      morningTempC: weather.briefingMorningC,
      noonTempC: weather.briefingAfternoonC,
      eveningTempC: weather.briefingEveningC,
      morningRainSegment: weather.morningRainSegment,
      afternoonRainSegment: weather.afternoonRainSegment,
      eveningRainSegment: weather.eveningRainSegment,
    );
    final reason = aiReply.trim().isNotEmpty ? aiReply.trim() : localReason;
    return _HeroOutfitRecommendation(items: ordered, reason: reason);
  }

  Map<_HeroWearType, Map<String, dynamic>> _typedPicksFromAiSelected(
    List<Map<String, dynamic>> selected,
  ) {
    final out = <_HeroWearType, Map<String, dynamic>>{};
    for (final raw in selected) {
      if (!out.containsKey(_HeroWearType.top) && _heroWardrobeMatchesType(raw, _HeroWearType.top)) {
        out[_HeroWearType.top] = raw;
        continue;
      }
      if (!out.containsKey(_HeroWearType.bottom) &&
          _heroWardrobeMatchesType(raw, _HeroWearType.bottom)) {
        out[_HeroWearType.bottom] = raw;
        continue;
      }
      if (!out.containsKey(_HeroWearType.shoes) &&
          _heroWardrobeMatchesType(raw, _HeroWearType.shoes)) {
        out[_HeroWearType.shoes] = raw;
        continue;
      }
      if (!out.containsKey(_HeroWearType.outerwear) &&
          _heroWardrobeMatchesType(raw, _HeroWearType.outerwear)) {
        out[_HeroWearType.outerwear] = raw;
      }
    }
    return out;
  }

  String _dateKey(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.toIso8601String().substring(0, 10);
  }

  String _homeWeatherSignature(_LocalWeather weather) {
    return [
      weather.tempC,
      weather.isRainy ? 1 : 0,
      weather.isWindy ? 1 : 0,
      weather.seasonKey,
      weather.morningRainSegment ? 1 : 0,
      weather.afternoonRainSegment ? 1 : 0,
      weather.eveningRainSegment ? 1 : 0,
      weather.briefingMorningC ?? -999,
      weather.briefingAfternoonC ?? -999,
      weather.briefingEveningC ?? -999,
      weather.rainTimeText ?? '',
    ].join('|');
  }

  String _wardrobeSignature(List<Map<String, dynamic>> wardrobe) {
    final ids = wardrobe
        .map((e) => OutfitGenerationService.wardrobeItemId(e))
        .where((e) => e.isNotEmpty)
        .toList()
      ..sort();
    return '${wardrobe.length}:${ids.join(",")}';
  }

  Map<String, dynamic> _homeAiWeatherContext(_LocalWeather weather) {
    return <String, dynamic>{
      'tempC': weather.tempC,
      'seasonKey': weather.seasonKey,
      'isRainy': weather.isRainy,
      'isWindy': weather.isWindy,
      'morningTempC': weather.briefingMorningC,
      'noonTempC': weather.briefingAfternoonC,
      'eveningTempC': weather.briefingEveningC,
      'morningRainSegment': weather.morningRainSegment,
      'afternoonRainSegment': weather.afternoonRainSegment,
      'eveningRainSegment': weather.eveningRainSegment,
      'rainTimeText': weather.rainTimeText,
      'summary': weather.summarySubtitle,
    };
  }

  String _homeAiTriggerSource({
    required String dateKey,
    required String weatherSignature,
    required String wardrobeSignature,
    required bool forceDifferent,
  }) {
    if (forceDifferent) return 'regenerate';
    if (_homeAiLastTriggeredDateKey != null && _homeAiLastTriggeredDateKey != dateKey) {
      return 'date_change';
    }
    final prevWeather = _homeAiLastWeatherSignatureByDateKey[dateKey];
    final prevWardrobe = _homeAiLastWardrobeSignatureByDateKey[dateKey];
    if (prevWeather == null && prevWardrobe == null) return 'initial_load';
    if (prevWeather != weatherSignature) return 'weather_change';
    if (prevWardrobe != wardrobeSignature) return 'initial_load';
    return 'initial_load';
  }

  bool _sameHeroRecommendation(
    _HeroOutfitRecommendation? a,
    _HeroOutfitRecommendation? b,
  ) {
    if (a == null || b == null) return false;
    if (a.reason != b.reason) return false;
    if (a.items.length != b.items.length) return false;
    for (var i = 0; i < a.items.length; i++) {
      final ai = a.items[i];
      final bi = b.items[i];
      if (ai.type != bi.type) return false;
      if ((ai.wardrobeItemId ?? '') != (bi.wardrobeItemId ?? '')) return false;
      if (ai.label != bi.label) return false;
    }
    return true;
  }

  bool _sameHeroItemsById(List<_HeroOutfitItem> a, List<_HeroOutfitItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].type != b[i].type) return false;
      if ((a[i].wardrobeItemId ?? '') != (b[i].wardrobeItemId ?? '')) return false;
    }
    return true;
  }

  int _dayIndexForDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (d == today.add(const Duration(days: 1))) return 1;
    return 0;
  }

  _HeroOutfitRecommendation? _recommendOutfitForWeather({
    required List<Map<String, dynamic>> wardrobe,
    required _LocalWeather weather,
    required bool isPremiumUser,
    Set<String> excludedItemIds = const {},
    Set<String> rejectedCombinationSignatures = const {},
    Set<String> previousOutfitItemIds = const {},
    bool forceDifferentOutfit = false,
  }) {
    final snap = OutfitWeatherSnapshot(
      tempC: weather.tempC,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
      seasonKey: weather.seasonKey,
    );
    final preview = OutfitGenerationService.generatePreview(
      wardrobeItems: wardrobe,
      weather: snap,
      excludedItemIds: excludedItemIds,
      rejectedCombinationSignatures: rejectedCombinationSignatures,
      previousItemIds: previousOutfitItemIds,
      forceDifferentOutfit: forceDifferentOutfit,
    );
    if (preview == null) return null;

    final topRaw = preview.top.item;
    final bottomRaw = preview.bottom.item;
    final shoesRaw = preview.shoes.item;
    final outerRaw = preview.outerwear?.item;

    final hasOuter = preview.outerwear != null;

    final selectedReasonItems = <Map<String, dynamic>>[
      {...topRaw, 'typeKey': 'top'},
      {...bottomRaw, 'typeKey': 'bottom'},
      {...shoesRaw, 'typeKey': 'shoes'},
      if (outerRaw != null) {...outerRaw, 'typeKey': 'outerwear'},
    ];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(
      weather.calendarDate.year,
      weather.calendarDate.month,
      weather.calendarDate.day,
    );
    final isTomorrowDay = d == today.add(const Duration(days: 1));

    final reasonParagraph = OutfitReasonBuilder.build(
      tempC: weather.tempC,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
      isPremium: isPremiumUser,
      selectedItems: selectedReasonItems,
      hasOuterwear: hasOuter,
      isTomorrow: isTomorrowDay,
      morningTempC: weather.briefingMorningC,
      noonTempC: weather.briefingAfternoonC,
      eveningTempC: weather.briefingEveningC,
      morningRainSegment: weather.morningRainSegment,
      afternoonRainSegment: weather.afternoonRainSegment,
      eveningRainSegment: weather.eveningRainSegment,
    );

    final outfitTiles = <_HeroOutfitItem>[
      _heroItemFromOutfitPreview(preview.top),
      _heroItemFromOutfitPreview(preview.bottom),
      _heroItemFromOutfitPreview(preview.shoes),
      if (preview.outerwear != null) _heroItemFromOutfitPreview(preview.outerwear!),
    ];

    if (outfitTiles.length < 3) return null;
    return _HeroOutfitRecommendation(
      items: outfitTiles,
      reason: reasonParagraph,
    );
  }

  _HeroOutfitRecommendation? _recommendOutfitForWeatherCached({
    required String dateKey,
    required List<Map<String, dynamic>> wardrobe,
    required _LocalWeather weather,
    required bool isPremiumUser,
  }) {
    final localSig = '$dateKey|${_homeWeatherSignature(weather)}|${_wardrobeSignature(wardrobe)}|p=${isPremiumUser ? 1 : 0}';
    if (_localRecCacheByDateSig.containsKey(localSig)) {
      return _localRecCacheByDateSig[localSig];
    }
    final rec = _recommendOutfitForWeather(
      wardrobe: wardrobe,
      weather: weather,
      isPremiumUser: isPremiumUser,
    );
    _localRecCacheByDateSig[localSig] = rec;
    return rec;
  }

  _HeroWearType _heroWearFromOutfitWear(OutfitWearType t) {
    switch (t) {
      case OutfitWearType.top:
        return _HeroWearType.top;
      case OutfitWearType.bottom:
        return _HeroWearType.bottom;
      case OutfitWearType.shoes:
        return _HeroWearType.shoes;
      case OutfitWearType.outerwear:
        return _HeroWearType.outerwear;
    }
  }

  _HeroOutfitItem _heroItemFromOutfitPreview(OutfitPreviewItem p) {
    final type = _heroWearFromOutfitWear(p.type);
    final raw = p.item;
    final id = OutfitGenerationService.wardrobeItemId(raw);
    final brandRaw = (raw['brand'] ?? '').toString().trim();
    final categoryKey = (raw['categoryKey'] ?? raw['category'] ?? '').toString().trim();
    final subCategoryKey = (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString().trim();
    return _HeroOutfitItem(
      type: type,
      icon: _heroIconForType(type),
      label: p.label,
      brandLine: brandRaw.isNotEmpty ? brandRaw : null,
      imageUrl: _heroWardrobeDisplayImageUrl(raw),
      categoryKey: categoryKey.isNotEmpty ? categoryKey : null,
      subCategoryKey: subCategoryKey.isNotEmpty ? subCategoryKey : null,
      wardrobeItemId: id.isEmpty ? null : id,
      imageProcessing: wardrobeItemShowsImageProcessingBadge(raw),
    );
  }

  IconData _heroIconForType(_HeroWearType type) {
    if (type == _HeroWearType.top) return Icons.checkroom;
    if (type == _HeroWearType.bottom) return Icons.style;
    if (type == _HeroWearType.shoes) return Icons.directions_run;
    return Icons.umbrella;
  }

  String _heroFallbackLabelForType(_HeroWearType type) {
    if (type == _HeroWearType.top) return 'Vrchný diel';
    if (type == _HeroWearType.bottom) return 'Spodný diel';
    if (type == _HeroWearType.shoes) return 'Obuv';
    return 'Vrstva';
  }

  String _heroLabelForWardrobeItem(Map<String, dynamic> raw, {required String fallback}) {
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final sub = (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString().trim();
    if (sub.isNotEmpty) return sub;
    final cat = (raw['categoryKey'] ?? raw['category'] ?? '').toString().trim();
    if (cat.isNotEmpty) return cat;
    return fallback;
  }

  _HeroOutfitItem _heroItemFromWardrobe({
    required Map<String, dynamic> raw,
    required _HeroWearType type,
  }) {
    final brandRaw = (raw['brand'] ?? '').toString().trim();
    final categoryKey = (raw['categoryKey'] ?? raw['category'] ?? '').toString().trim();
    final subCategoryKey = (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString().trim();
    final wid = OutfitGenerationService.wardrobeItemId(raw);
    return _HeroOutfitItem(
      type: type,
      icon: _heroIconForType(type),
      label: _heroLabelForWardrobeItem(raw, fallback: _heroFallbackLabelForType(type)),
      brandLine: brandRaw.isNotEmpty ? brandRaw : null,
      imageUrl: _heroWardrobeDisplayImageUrl(raw),
      categoryKey: categoryKey.isNotEmpty ? categoryKey : null,
      subCategoryKey: subCategoryKey.isNotEmpty ? subCategoryKey : null,
      wardrobeItemId: wid.isEmpty ? null : wid,
      imageProcessing: wardrobeItemShowsImageProcessingBadge(raw),
    );
  }

  String _heroBlob(Map<String, dynamic> raw) {
    final cat = (raw['categoryKey'] ?? raw['category'] ?? '').toString();
    final sub = (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString();
    final main = (raw['mainGroupKey'] ?? raw['mainGroup'] ?? '').toString();
    final name = (raw['name'] ?? '').toString();
    return '$name $cat $sub $main'.toLowerCase();
  }

  bool _heroWardrobeMatchesType(Map<String, dynamic> raw, _HeroWearType type) {
    final b = _heroBlob(raw);
    bool has(List<String> needles) => needles.any((n) => b.contains(n));
    switch (type) {
      case _HeroWearType.top:
        return has([
          'trič',
          'tricko',
          't-shirt',
          'top',
          'koše',
          'blúz',
          'bluz',
          'sveter',
          'shirt',
          'hoodie',
          'mikina',
          'sweatshirt',
          'crewneck',
          'sweater',
        ]);
      case _HeroWearType.bottom:
        return has(['nohav', 'rifl', 'jeans', 'pants', 'sukn', 'skirt', 'short']);
      case _HeroWearType.shoes:
        return has(['topán', 'topan', 'tenis', 'sneaker', 'boots', 'sand', 'obuv', 'shoes']);
      case _HeroWearType.outerwear:
        return has([
          'bunda',
          'kabát',
          'kabat',
          'sako',
          'blazer',
          'coat',
          'jacket',
          'overshirt',
          'shacket',
          'parka',
          'bomber',
        ]);
    }
  }

  String _normalizedClothingToken(String? raw) {
    return (raw ?? '')
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('č', 'c')
        .replaceAll('ď', 'd')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ľ', 'l')
        .replaceAll('ĺ', 'l')
        .replaceAll('ň', 'n')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ŕ', 'r')
        .replaceAll('š', 's')
        .replaceAll('ť', 't')
        .replaceAll('ú', 'u')
        .replaceAll('ý', 'y')
        .replaceAll('ž', 'z');
  }

  bool _containsAnyNormalized(String haystack, List<String> needles) {
    return needles.any((n) => haystack.contains(_normalizedClothingToken(n)));
  }

  String _manualDefaultGroupForCurrentItem(_HeroWearType type, _HeroOutfitItem? currentItem) {
    final source = _normalizedClothingToken(
      '${currentItem?.subCategoryKey ?? ''} ${currentItem?.categoryKey ?? ''} ${currentItem?.label ?? ''}',
    );
    if (type == _HeroWearType.shoes) return 'shoes';
    if (_containsAnyNormalized(source, ['hoodie', 'mikina'])) return 'hoodie';
    if (_containsAnyNormalized(source, ['jacket', 'bunda'])) return 'jacket';
    if (_containsAnyNormalized(source, ['coat', 'kabat', 'kabat', 'kabát'])) return 'coat';
    if (_containsAnyNormalized(source, ['t-shirt', 'tricko', 'tričko', 'tank', 'tielko'])) {
      return 'tee_tank';
    }
    return type == _HeroWearType.bottom ? 'bottom' : 'type_default';
  }

  bool _matchesManualGroup(Map<String, dynamic> raw, String group, _HeroWearType type) {
    final blob = _normalizedClothingToken(_heroBlob(raw));
    bool has(List<String> words) => _containsAnyNormalized(blob, words);
    switch (group) {
      case 'tee_tank':
        return has(['t-shirt', 'tricko', 'tričko', 'tank', 'tielko']);
      case 'hoodie':
        return has(['hoodie', 'mikina']);
      case 'jacket':
        return has(['jacket', 'bunda']);
      case 'coat':
        return has(['coat', 'kabat', 'kabát']);
      case 'bottom':
        return has(['nohav', 'rifl', 'jeans', 'pants', 'sukn', 'skirt', 'short']);
      case 'shoes':
        return has(['topan', 'topán', 'tenis', 'sneaker', 'boots', 'sand', 'obuv', 'shoes']);
      case 'type_default':
      default:
        return _heroWardrobeMatchesType(raw, type);
    }
  }

  List<_ManualCategoryOption> _manualOverrideOptions(_HeroWearType type) {
    switch (type) {
      case _HeroWearType.top:
      case _HeroWearType.outerwear:
        return const [
          _ManualCategoryOption(id: 'tee_tank', label: 'Tričká a tielka'),
          _ManualCategoryOption(id: 'hoodie', label: 'Mikiny'),
          _ManualCategoryOption(id: 'jacket', label: 'Bundy'),
          _ManualCategoryOption(id: 'coat', label: 'Kabáty'),
        ];
      case _HeroWearType.bottom:
        return const [
          _ManualCategoryOption(id: 'bottom', label: 'Nohavice, rifle, sukne'),
        ];
      case _HeroWearType.shoes:
        return const [
          _ManualCategoryOption(id: 'shoes', label: 'Obuv'),
        ];
    }
  }

  /// Visual experiment: outfit (~65%) + daily briefing (~35%) on one row; action bar below.
  Widget _heroRowExperiment({
    required BuildContext context,
    required _HeroBannerVM vm,
    required DateTime activeDate,
    required bool cardIsTomorrow,
    required List<_HeroOutfitItem> outfitItems,
    required _LocalWeather w,
    required String heroSource,
    String? heroLoadingReason,
  }) {
    _editSpotlightVm = vm;
    _editSpotlightWeather = w;
    _editSpotlightIsTomorrow = cardIsTomorrow;
    _syncEditableOutfitFromSource(outfitItems);
    final effectiveItems = _effectiveOutfitItems(outfitItems);
    final likeActive = _isCurrentOutfitLiked(effectiveItems);
    final renderedNames = effectiveItems.map((e) => e.label).join(', ');
    final renderLogKey = '$heroSource|${_heroRenderSignature(effectiveItems)}';
    if (_lastHeroRenderLogKey != renderLogKey) {
      _lastHeroRenderLogKey = renderLogKey;
      final renderSource =
          (_editedManuallyByDay[_dayIndex] ?? false) ? 'edited' : heroSource;
      if (heroSource == 'loading' && heroLoadingReason != null) {
        debugPrint('[HOME_HERO_RENDER] source=loading reason=$heroLoadingReason');
      } else {
        debugPrint('[HOME_HERO_RENDER] source=$renderSource names=$renderedNames');
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UnifiedHeroSurface(
          dayIndex: _dayIndex,
          onChangeDay: _setDayIndex,
          vm: vm,
          weather: w,
          isTomorrow: cardIsTomorrow,
          outfitItems: effectiveItems,
          loadingMode: heroSource == 'loading',
          editMode: false,
          focusedType: null,
          onItemTap: null,
          onRemoveTap: null,
          outfitSpotlightTargetKey: _editSpotlightTargetKey,
          outfitSpotlightLink: _editSpotlightLink,
        ),
        const SizedBox(height: 22),
        _HeroOutfitActionBar(
          onNewOutfit: () {
            if (_newOutfitGenerating && !_isOutfitEditMode) return;
            if (_isOutfitEditMode) {
              _exitOutfitEditMode();
            } else {
              unawaited(_handleNewOutfitPressed());
            }
          },
          newOutfitLoading: _newOutfitGenerating && !_isOutfitEditMode,
          onSwapPiece: () async {
            if (_isOutfitEditMode) {
              _exitOutfitEditMode();
              return;
            }
            await _handleSwapPieceTap(context, effectiveItems);
          },
          onLike: () => _handleLikeTap(effectiveItems),
          likeActive: likeActive,
          likePulseTick: _likePulseTick,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                axisAlignment: -1,
                sizeFactor: animation,
                child: child,
              ),
            );
          },
          child: _showLikeInlineFeedback
              ? Padding(
                  key: const ValueKey('like_feedback_visible'),
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(
                    'Appka si zapamätá, že sa ti tento vibe páči ✨',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      color: HomeLuxuryPalette.textSecondary.withOpacity(0.84),
                      fontSize: 12.2,
                      fontWeight: FontWeight.w500,
                      height: 1.22,
                      letterSpacing: 0.03,
                    ),
                  ),
                )
              : const SizedBox(
                  key: ValueKey('like_feedback_hidden'),
                ),
        ),
      ],
    );
  }

  Widget _homeSectionsAfterHero({
    required BuildContext context,
    required _HeroBannerVM vm,
    required List<_HeroOutfitItem> outfitItems,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        HomeAiExplanationCard(
          body: vm.description,
          isPlaceholder: outfitItems.isEmpty,
        ),
        const SizedBox(height: 26),
        HomeRecommendedSection(onOpenRecommended: _openRecommended),
        const SizedBox(height: 26),
        HomeInspirationCarousel(
          onOpenInspiration: () {
            // Placeholder for future outfit detail flow from inspiration posts.
          },
        ),
        const SizedBox(height: 120),
      ],
    );
  }

  Future<void> _onEditTileTap(_HeroOutfitItem item) async {
    setState(() => _focusedEditType = item.type);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: _HeroEditActionSheet(
            onAiSuggest: () async {
              Navigator.of(sheetContext).pop();
              await _handleAiSuggestForType(item.type);
            },
            onManualPick: () async {
              Navigator.of(sheetContext).pop();
              await _openManualSelectionForType(item.type);
            },
            onFeedback: () async {
              Navigator.of(sheetContext).pop();
              await _openEditFeedbackInput(item.type);
            },
          ),
        );
      },
    );
  }

  Future<void> _onRemoveTileTap(_HeroOutfitItem item) async {
    final shouldRemove = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: HomeLuxuryPalette.surfaceSoft.withOpacity(0.96),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text(
                'Odstrániť tento kúsok z outfitu?',
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Zrušiť'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Odstrániť'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!shouldRemove) return;
    final current = List<_HeroOutfitItem>.from(_editedOutfitByDay[_dayIndex] ?? const []);
    current.removeWhere((it) => it.type == item.type);
    _setEditedItems(current);
  }

  Future<void> _handleAiSuggestForType(_HeroWearType type) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final current = List<_HeroOutfitItem>.from(_editedOutfitByDay[_dayIndex] ?? const []);
    final idx = current.indexWhere((it) => it.type == type);
    if (idx < 0) return;
    final old = current[idx];
    final oldId = (old.wardrobeItemId ?? '').trim();
    final rejected = _swapRejectedReplacementItemIdsByDay.putIfAbsent(
      _dayIndex,
      () => <String>{},
    );
    final lastSuggested = _swapLastSuggestedItemIdByTypeByDay[_dayIndex]?[type];
    if (lastSuggested != null && lastSuggested.isNotEmpty) {
      rejected.add(lastSuggested);
    }
    if (oldId.isNotEmpty) {
      rejected.add(oldId);
    }

    final originalsByType = _swapOriginalItemIdByTypeByDay[_dayIndex] ?? const {};
    final originalId = (originalsByType[type] ?? '').trim();
    if (originalId.isNotEmpty) {
      rejected.add(originalId);
    }

    final usedInOtherSlots = <String>{
      for (final it in current)
        if (it.type != type && (it.wardrobeItemId ?? '').trim().isNotEmpty)
          (it.wardrobeItemId ?? '').trim(),
    };

    final snap = await _firestore.collection('users').doc(user.uid).collection('wardrobe').get();
    final docs = snap.docs.map((d) {
      final raw = Map<String, dynamic>.from(d.data());
      raw['id'] = d.id;
      return raw;
    }).toList();
    final sameRole = docs.where((raw) => _heroWardrobeMatchesType(raw, type)).toList();
    bool validRaw(Map<String, dynamic> raw) {
      final id = OutfitGenerationService.wardrobeItemId(raw);
      if (id.isEmpty) return false;
      if (rejected.contains(id)) return false;
      if (usedInOtherSlots.contains(id)) return false;
      return true;
    }

    final oldSubKey = _normalizedScaleToken(old.subCategoryKey ?? '');
    final oldCanonical = _canonicalTypeFromHeroItem(old);
    final tier1 = sameRole.where((raw) {
      if (!validRaw(raw)) return false;
      final sub = _normalizedScaleToken(
        (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString(),
      );
      return oldSubKey.isNotEmpty && sub == oldSubKey;
    }).toList();
    final tier2 = sameRole.where((raw) {
      if (!validRaw(raw)) return false;
      return _canonicalTypeFromRaw(raw) == oldCanonical;
    }).toList();
    final tier3 = sameRole.where(validRaw).toList();
    final candidates =
        tier1.isNotEmpty ? tier1 : (tier2.isNotEmpty ? tier2 : tier3);
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pre tento typ nemáš ďalší vhodný kúsok.')),
      );
      return;
    }
    candidates.sort((a, b) {
      final ia = OutfitGenerationService.wardrobeItemId(a);
      final ib = OutfitGenerationService.wardrobeItemId(b);
      return ia.compareTo(ib);
    });
    final replacementRaw = candidates.first;
    final replacement = _heroItemFromWardrobe(raw: replacementRaw, type: type);
    final newId = (replacement.wardrobeItemId ?? '').trim();
    if (newId.isNotEmpty) {
      _swapLastSuggestedItemIdByTypeByDay.putIfAbsent(_dayIndex, () => {})[type] =
          newId;
    }
    current[idx] = replacement;
    _setEditedItems(current);
    debugPrint('[HOME_SWAP] accept replacement oldId=$oldId newId=$newId');
    debugPrint('[HOME_SWAP] updated_edited_outfit=true');
    debugPrint('[HOME_SWAP] persisted_to_home=true dayIndex=$_dayIndex');
    debugPrint('[HOME_SWAP] marked_manual_edit=true');
    debugPrint('[HOME_SWAP] prevented_ai_restore=true');
  }

  Future<void> _openEditFeedbackInput(_HeroWearType type) async {
    final ctrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        final safeBottom = MediaQuery.paddingOf(sheetContext).bottom;
        final base = Theme.of(sheetContext);
        final localTheme = base.copyWith(
          colorScheme: base.colorScheme.copyWith(
            primary: HomeLuxuryPalette.accent,
            secondary: HomeLuxuryPalette.accent,
            surface: HomeLuxuryPalette.surface,
            onSurface: HomeLuxuryPalette.textPrimary,
          ),
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: HomeLuxuryPalette.accent.withOpacity(0.96),
            selectionColor: HomeLuxuryPalette.accent.withOpacity(0.30),
            selectionHandleColor: HomeLuxuryPalette.accent.withOpacity(0.96),
          ),
          splashColor: HomeLuxuryPalette.accent.withOpacity(0.10),
          highlightColor: HomeLuxuryPalette.accent.withOpacity(0.06),
          hoverColor: HomeLuxuryPalette.accent.withOpacity(0.05),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: HomeLuxuryPalette.accent.withOpacity(0.95),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              overlayColor: WidgetStateProperty.all(
                HomeLuxuryPalette.accent.withOpacity(0.10),
              ),
            ),
          ),
        );
        return Theme(
          data: localTheme,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + safeBottom + 26),
            child: HomeGlassSurface(
              borderRadius: 22,
              blurSigma: 18,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Čo ti na kúsku nesedí?',
                    style: TextStyle(
                      color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    cursorColor: HomeLuxuryPalette.accent.withOpacity(0.96),
                    minLines: 3,
                    maxLines: 5,
                    style: TextStyle(color: HomeLuxuryPalette.textPrimary.withOpacity(0.94)),
                    decoration: InputDecoration(
                      hintText: 'Napíš čo ti na kúsku nesedí\na aký vibe chceš skúsiť.',
                      hintStyle: TextStyle(
                        color: HomeLuxuryPalette.textSecondary.withOpacity(0.84),
                        height: 1.35,
                      ),
                      filled: true,
                      fillColor: HomeLuxuryPalette.bgTop.withOpacity(0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: HomeLuxuryPalette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: HomeLuxuryPalette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: HomeLuxuryPalette.accent.withOpacity(0.72),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Nepovinné — AI môže vybrať nový kúsok aj sama.',
                    style: TextStyle(
                      color: HomeLuxuryPalette.textSecondary.withOpacity(0.82),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _handleAiSuggestForType(type);
                      },
                      child: const Text('Použiť návrh AI'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openManualSelectionForType(_HeroWearType type) async {
    final user = _auth.currentUser;
    if (user == null) return;
    _HeroOutfitItem? currentItem;
    final currentItems = _editedOutfitByDay[_dayIndex] ?? const <_HeroOutfitItem>[];
    for (final it in currentItems) {
      if (it.type == type) {
        currentItem = it;
        break;
      }
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        String? overrideGroup;
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.56,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                return HomeGlassSurface(
                  borderRadius: 22,
                  blurSigma: 16,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _wardrobeStream(user.uid),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? const [];
                      final defaultGroup = _manualDefaultGroupForCurrentItem(type, currentItem);
                      final activeGroup = overrideGroup ?? defaultGroup;
                      final filtered = docs
                          .map((d) => d.data())
                          .where((raw) => _matchesManualGroup(raw, activeGroup, type))
                          .toList();
                      final overrideOptions = _manualOverrideOptions(type);
                      final matching = overrideOptions.where((o) => o.id == activeGroup).toList();
                      final activeLabel = matching.isEmpty ? null : matching.first.label;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Čím chceš nahradiť tento kúsok?',
                                  style: TextStyle(
                                    color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.12,
                                  ),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: HomeLuxuryPalette.accent.withOpacity(0.96),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  textStyle: TextStyle(
                                    fontSize: 12.6,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.08,
                                  ),
                                ),
                                onPressed: () async {
                                  final selected = await showModalBottomSheet<String>(
                                    context: sheetContext,
                                    backgroundColor: Colors.transparent,
                                    builder: (ctx) {
                                      return SafeArea(
                                        top: false,
                                        child: HomeGlassSurface(
                                          borderRadius: 18,
                                          blurSigma: 16,
                                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              for (final option in overrideOptions)
                                                ListTile(
                                                  dense: true,
                                                  onTap: () => Navigator.of(ctx).pop(option.id),
                                                  title: Text(
                                                    option.label,
                                                    style: TextStyle(
                                                      color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                  if (selected == null) return;
                                  setModalState(() => overrideGroup = selected);
                                },
                                child: const Text('Použiť inú kategóriu'),
                              ),
                            ],
                          ),
                          if (activeLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 1, bottom: 6),
                              child: Text(
                                activeLabel,
                                style: TextStyle(
                                  color: HomeLuxuryPalette.textSecondary.withOpacity(0.86),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: GridView.builder(
                              controller: controller,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.76,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final raw = filtered[i];
                                final label = _heroLabelForWardrobeItem(
                                  raw,
                                  fallback: _heroFallbackLabelForType(type),
                                );
                                final item = _heroItemFromWardrobe(raw: raw, type: type);
                                final current = currentItem;
                                final isCurrent = current != null &&
                                    current.label == item.label &&
                                    current.type == item.type;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () {
                                    final current = List<_HeroOutfitItem>.from(
                                      _editedOutfitByDay[_dayIndex] ?? const [],
                                    );
                                    final idx = current.indexWhere((it) => it.type == type);
                                    final oldId = idx >= 0
                                        ? (current[idx].wardrobeItemId ?? '').trim()
                                        : '';
                                    if (idx >= 0) {
                                      current[idx] = item;
                                    } else {
                                      current.add(item);
                                    }
                                    final newId = (item.wardrobeItemId ?? '').trim();
                                    _setEditedItems(current);
                                    if (newId.isNotEmpty) {
                                      _swapLastSuggestedItemIdByTypeByDay
                                          .putIfAbsent(_dayIndex, () => {})[type] = newId;
                                    }
                                    debugPrint(
                                      '[HOME_SWAP] accept replacement oldId=$oldId newId=$newId',
                                    );
                                    debugPrint('[HOME_SWAP] updated_edited_outfit=true');
                                    debugPrint(
                                      '[HOME_SWAP] persisted_to_home=true dayIndex=$_dayIndex',
                                    );
                                    debugPrint('[HOME_SWAP] marked_manual_edit=true');
                                    debugPrint('[HOME_SWAP] prevented_ai_restore=true');
                                    Navigator.of(sheetContext).pop();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      color: HomeLuxuryPalette.surface.withOpacity(0.56),
                                      border: Border.all(
                                        color: isCurrent
                                            ? HomeLuxuryPalette.accent.withOpacity(0.46)
                                            : HomeLuxuryPalette.border,
                                      ),
                                      boxShadow: [
                                        if (isCurrent)
                                          BoxShadow(
                                            color: HomeLuxuryPalette.accent.withOpacity(0.18),
                                            blurRadius: 16,
                                            spreadRadius: 0,
                                          ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(11),
                                            child: ColoredBox(
                                              color: HomeLuxuryPalette.bgMid.withOpacity(0.34),
                                              child: _HeroOutfitImageView(
                                                imageUrl: item.imageUrl,
                                                fallbackIcon: item.icon,
                                                wearType: item.type,
                                                compact: true,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 9),
                                        Expanded(
                                          child: Text(
                                            label,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: HomeLuxuryPalette.textPrimary.withOpacity(0.92),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              height: 1.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEditSpotlightOverlay() {
    final size = _editSpotlightSize;
    final items = _editedOutfitByDay[_dayIndex] ?? const <_HeroOutfitItem>[];
    final vm = _editSpotlightVm;
    final weather = _editSpotlightWeather;
    if (!_isOutfitEditMode ||
        size == null ||
        items.isEmpty ||
        vm == null ||
        weather == null) {
      return const SizedBox.shrink();
    }
    return CompositedTransformFollower(
      link: _editSpotlightLink,
      showWhenUnlinked: false,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: _UnifiedHeroSurface(
          dayIndex: _dayIndex,
          onChangeDay: _setDayIndex,
          vm: vm,
          weather: weather,
          isTomorrow: _editSpotlightIsTomorrow,
          outfitItems: items,
          editMode: true,
          focusedType: _focusedEditType,
          onItemTap: _onEditTileTap,
          onRemoveTap: _onRemoveTileTap,
        ),
      ),
    );
  }

  List<HomeQuickActionEntry> _quickActionEntries(BuildContext context) {
    return [
      (
        emoji: '✨',
        label: 'Poskladaj podobný vibe',
        onTap: _openVibeComposerPanel,
      ),
      (
        emoji: '✈️',
        label: 'Čo si zbaliť?',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TripPackingScreen()),
          );
        },
      ),
      (
        emoji: '📅',
        label: 'Kalendár',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CalendarOutfitScreen()),
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const wardrobeBg = HomeLuxuryPalette.bgBottom;
    final user = _auth.currentUser;
    final greetingName = _getGreetingName(user);

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final tomorrowDate = todayDate.add(const Duration(days: 1));
    final activeDate = _isTomorrow ? tomorrowDate : todayDate;

    Widget greetingHeader() {
      return Builder(
        builder: (innerContext) {
          return HomeGreetingHeader(
            greetingLine: greetingName,
            onOpenMenu: () => Scaffold.of(innerContext).openDrawer(),
          );
        },
      );
    }

    Widget scrollContent() {
      if (_isTomorrow && user == null) {
        final w = _weatherForDate(tomorrowDate);
        final vm = _HeroBannerVM(
          description:
              'Prihlás sa, aby som vedel odporučiť outfit podľa tvojho šatníka aj na zajtra.',
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            greetingHeader(),
            const SizedBox(height: 26),
            _heroRowExperiment(
              context: context,
              vm: vm,
              activeDate: activeDate,
              cardIsTomorrow: true,
              outfitItems: const <_HeroOutfitItem>[],
              w: w,
              heroSource: 'local',
              heroLoadingReason: null,
            ),
            _homeSectionsAfterHero(
              context: context,
              vm: vm,
              outfitItems: const <_HeroOutfitItem>[],
            ),
          ],
        );
      }

      if (user == null) {
        final w = _weatherForDate(todayDate);
        final vm = _HeroBannerVM(
          description:
              'Prihlás sa, aby som vedel odporučiť outfit podľa tvojho šatníka.',
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            greetingHeader(),
            const SizedBox(height: 26),
            _heroRowExperiment(
              context: context,
              vm: vm,
              activeDate: activeDate,
              cardIsTomorrow: false,
              outfitItems: const <_HeroOutfitItem>[],
              w: w,
              heroSource: 'local',
              heroLoadingReason: null,
            ),
            _homeSectionsAfterHero(
              context: context,
              vm: vm,
              outfitItems: const <_HeroOutfitItem>[],
            ),
          ],
        );
      }

      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userDocStream(user.uid),
        builder: (context, userSnap) {
          final data = userSnap.data?.data();
          final isPremiumUser = data?['isPremium'] == true ||
              data?['subscriptionStatus'] == 'premium';
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _wardrobeStream(user.uid),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? const [];
              final wardrobe = docs.map((d) {
                final m = Map<String, dynamic>.from(d.data());
                m['id'] = d.id;
                return m;
              }).toList();
              final w = _weatherForDate(activeDate);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _maybeTriggerHomeAiRecommendation(
                  date: activeDate,
                  wardrobe: wardrobe,
                  weather: w,
                  isPremiumUser: isPremiumUser,
                );
              });
              final dataReady = _weatherLoaded &&
                  userSnap.connectionState != ConnectionState.waiting &&
                  snap.connectionState != ConnectionState.waiting;
              final hero = _buildTodayHero(
                date: activeDate,
                wardrobe: wardrobe,
                isPremiumUser: isPremiumUser,
                dataReady: dataReady,
              );
              final vm = _HeroBannerVM(description: hero.vm.description);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  greetingHeader(),
                  const SizedBox(height: 26),
                  _heroRowExperiment(
                    context: context,
                    vm: vm,
                    activeDate: activeDate,
                    cardIsTomorrow: _isTomorrow,
                    outfitItems: hero.outfitItems,
                    w: w,
                    heroSource: hero.source,
                    heroLoadingReason: hero.loadingReason,
                  ),
                  _homeSectionsAfterHero(
                    context: context,
                    vm: vm,
                    outfitItems: hero.outfitItems,
                  ),
                ],
              );
            },
          );
        },
      );
    }

    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: wardrobeBg,
        drawer: _buildDrawer(context),
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      HomeLuxuryPalette.bgTop,
                      HomeLuxuryPalette.bgMid,
                      HomeLuxuryPalette.bgBottom,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.1, -0.9),
                      radius: 1.05,
                      colors: [
                        HomeLuxuryPalette.accentGlow.withOpacity(0.22),
                        HomeLuxuryPalette.accentGlow.withOpacity(0.10),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.28, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0B0B0D).withOpacity(0.32),
                      Colors.transparent,
                      const Color(0xFF09090A).withOpacity(0.24),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      HomeLuxuryPalette.horizontalPadding,
                      18,
                      HomeLuxuryPalette.horizontalPadding,
                      36 + MediaQuery.of(context).padding.bottom + 72,
                    ),
                    child: scrollContent(),
                  ),
                  HomeQuickActionOrb(
                    actions: _quickActionEntries(context),
                    bottomOffset: 52,
                    rightOffset: 12,
                  ),
                  if (_isOutfitEditMode)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _exitOutfitEditMode,
                        child: ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Quick-orb-like atmosphere: stronger dim + subtle blur, kept lightweight.
                              BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
                                child: const SizedBox.expand(),
                              ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      const Color(0xAA000000),
                                      const Color(0xB3000000),
                                      const Color(0xB8000000),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_isOutfitEditMode) _buildEditSpotlightOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRecommended() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecommendedScreen(initialTab: 0)),
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    final user = _auth.currentUser;
    final displayName = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : 'Používateľ';
    final email = (user?.email?.trim().isNotEmpty ?? false)
        ? user!.email!.trim()
        : 'bez emailu';
    final initial = displayName.isNotEmpty
        ? displayName.characters.first.toUpperCase()
        : 'P';
    final photoUrl = user?.photoURL;

    return Drawer(
      backgroundColor: HomeLuxuryPalette.bgMid,
      child: Stack(
        children: [
      const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
        gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          HomeLuxuryPalette.bgTop,
          HomeLuxuryPalette.bgMid,
          HomeLuxuryPalette.bgBottom,
        ],
      ),
    ),
    ),
    ),
    Positioned.fill(
    child: IgnorePointer(
    child: DecoratedBox(
    decoration: BoxDecoration(
    gradient: RadialGradient(
    center: const Alignment(-0.4, -0.9),
    radius: 1.1,
    colors: [
    HomeLuxuryPalette.accent.withOpacity(0.25),
    HomeLuxuryPalette.accent.withOpacity(0.10),
    Colors.transparent,
    ],
    stops: const [0.0, 0.35, 1.0],
    ),
    ),
    ),
    ),
    ),
    Positioned.fill(
    child: DecoratedBox(
    decoration: BoxDecoration(
    gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
    Colors.transparent,
    Color(0xFF09090A).withOpacity(0.25),
    ],
    ),
    ),
    ),
    ),
    SafeArea(
    child: Column(
    children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: HomeLuxuryPalette.border),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    HomeLuxuryPalette.bgTop,
                    HomeLuxuryPalette.bgMid,
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: HomeLuxuryPalette.accent.withOpacity(0.45),
                      ),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFC8A36A),
                          Color(0xFF9D7C4C),
                        ],
                      ),
                    ),
                    child: ClipOval(
                      child: (photoUrl != null && photoUrl.trim().isNotEmpty)
                          ? Image.network(
                              photoUrl.trim(),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Center(
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                      color: Color(0xFF191512),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 22,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Color(0xFF191512),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HomeLuxuryPalette.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: HomeLuxuryPalette.textSecondary.withOpacity(0.9),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                children: [
            _drawerSectionLabel('SOCIÁLNE'),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.people_outline, color: HomeLuxuryPalette.accent),
              title: Text(
                'Priatelia',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FriendsScreen()),
                );
              },
            ),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.diversity_2, color: HomeLuxuryPalette.accent),
              title: Text(
                'Správy a zladenie outfitov',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MessagesScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _drawerSectionLabel('AI'),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.auto_awesome, color: HomeLuxuryPalette.accent),
              title: Text(
                'Analýza šatníka',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WardrobeAnalysisScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PremiumScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        HomeLuxuryPalette.surfaceSoft.withOpacity(0.92),
                        HomeLuxuryPalette.bgTop.withOpacity(0.95),
                      ],
                    ),
                    border: Border.all(
                      color: HomeLuxuryPalette.accent.withOpacity(0.42),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: HomeLuxuryPalette.accent.withOpacity(0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: HomeLuxuryPalette.accent.withOpacity(0.16),
                          border: Border.all(
                            color: HomeLuxuryPalette.accent.withOpacity(0.40),
                          ),
                        ),
                        child: const Icon(
                          Icons.workspace_premium,
                          size: 18,
                          color: HomeLuxuryPalette.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Premium',
                              style: TextStyle(
                                color: HomeLuxuryPalette.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Odomkni pokročilé AI funkcie',
                              style: TextStyle(
                                color: HomeLuxuryPalette.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _drawerSectionLabel('ÚČET'),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.person_outline, color: HomeLuxuryPalette.accent),
              title: Text(
                'Profil',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
            ),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.settings, color: HomeLuxuryPalette.accent),
              title: Text(
                'Nastavenia',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UserPreferencesScreen()),
                );
              },
            ),
                ],
              ),
            ),
            Divider(color: HomeLuxuryPalette.border),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.logout, color: HomeLuxuryPalette.accent),
              title: Text(
                'Odhlásiť sa',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await _auth.signOut();
              },
            ),
    ],
    )
    ),
    ],
      ),
    );
  }

  Widget _drawerSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          color: HomeLuxuryPalette.textSecondary.withOpacity(0.72),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  String _getGreetingName(User? user) {
    if (user == null) return 'Ahoj';
    final name = user.displayName;
    if (name == null || name.trim().isEmpty) return 'Ahoj';
    return 'Ahoj ${name.split(' ').first}';
  }
}

/// Inline weather — editorial typography only (no chips/capsules).
class _HeroInlineWeather extends StatelessWidget {
  const _HeroInlineWeather({
    required this.weather,
    required this.compact,
  });

  final _LocalWeather weather;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final emojiStyle = TextStyle(
      fontSize: compact ? 13 : 14,
      height: 1.2,
    );

    final headlineLabel = BriefingWeatherCondition.dailyHeadlineSk(
      weather.briefingMorningCondition,
      weather.briefingAfternoonCondition,
      weather.briefingEveningCondition,
    );
    final condEmoji = LuxuryWeatherEmoji.forConditionSk(headlineLabel);
    final condLabel = headlineLabel;

    final tempStyle = TextStyle(
      color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
      fontSize: compact ? 12.5 : 13,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
      height: 1.2,
    );
    final conditionStyle = TextStyle(
      color: HomeLuxuryPalette.textSecondary.withOpacity(0.82),
      fontSize: compact ? 11.5 : 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.08,
      height: 1.2,
    );
    final rowGap = compact ? 4.0 : 5.0;
    final inlineGap = compact ? 5.0 : 6.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('${weather.tempC}°C', style: tempStyle),
            SizedBox(width: inlineGap),
            Text(condEmoji, style: emojiStyle),
          ],
        ),
        SizedBox(height: rowGap),
        Text(condLabel, style: conditionStyle),
      ],
    );
  }
}

/// Gaps in unified hero — keep in sync with [HomeDailyBriefingRow] `_kEmbeddedGapAfterToggle` / `_kEmbeddedGapBeforeGrid`.
const double _kHeroGapAfterToggle = 8.0;
const double _kHeroGapBeforeGrid = 14.0;

/// Matches [_HeroInlineWeather] compact/non-compact layout (sync if that widget changes).
double _heroInlineWeatherBandHeight({required bool compact}) {
  final rowGap = compact ? 4.0 : 5.0;
  final tempRowH = (compact ? 12.5 : 13) * 1.2;
  final condRowH = (compact ? 11.5 : 12) * 1.2;
  return tempRowH + rowGap + condRowH;
}

/// Briefing-only glass inset — subtle separation from outfit tiles (luxury radius matches embedded rows ~14).
const double _kBriefingGlassRadius = 14.0;

/// Soft inset for „Prehľad dňa“ — content-sized only (no infinite height, no nested BackdropFilter).
/// Top spacer pre zarovnanie s togglom patrí **nad** kartu (mimo dekorácie), nie do pozadia karty.
class _UnifiedHeroBriefingGlassPanel extends StatelessWidget {
  const _UnifiedHeroBriefingGlassPanel({
    required this.gapBeforeGrid,
    required this.briefing,
    this.sectionTitle = 'Prehľad dňa',
  });

  final double gapBeforeGrid;
  final Widget briefing;
  final String? sectionTitle;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(_kBriefingGlassRadius);
    return ClipRRect(
      borderRadius: r,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
        decoration: BoxDecoration(
          borderRadius: r,
          border: Border.all(
            color: Colors.white.withOpacity(0.078),
            width: 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.052),
              Colors.white.withOpacity(0.030),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.20),
              blurRadius: 14,
              offset: const Offset(0, 6),
              spreadRadius: -3,
            ),
            BoxShadow(
              color: HomeLuxuryPalette.accent.withOpacity(0.05),
              blurRadius: 20,
              spreadRadius: -8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sectionTitle != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  sectionTitle!,
                  style: homeUnifiedHeroPrehladTitleStyle(),
                ),
              ),
              SizedBox(height: gapBeforeGrid),
            ],
            briefing,
          ],
        ),
      ),
    );
  }
}

/// Shared outfit / briefing body: bounded height — kept moderate so tiles stay elegant, not oversized.
double _heroSharedBodyHeight(BuildContext context) {
  final h = MediaQuery.sizeOf(context).height;
  return (h * 0.198).clamp(226.0, 286.0);
}

/// =======================
/// UNIFIED HERO (outfit + briefing)
/// =======================
class _UnifiedHeroSurface extends StatelessWidget {
  const _UnifiedHeroSurface({
    required this.dayIndex,
    required this.onChangeDay,
    required this.vm,
    required this.weather,
    required this.isTomorrow,
    required this.outfitItems,
    this.loadingMode = false,
    this.editMode = false,
    this.focusedType,
    this.onItemTap,
    this.onRemoveTap,
    this.outfitSpotlightTargetKey,
    this.outfitSpotlightLink,
  });

  final int dayIndex;
  final ValueChanged<int> onChangeDay;
  final _HeroBannerVM vm;
  final _LocalWeather weather;
  final bool isTomorrow;
  final List<_HeroOutfitItem> outfitItems;
  final bool loadingMode;
  final bool editMode;
  final _HeroWearType? focusedType;
  final ValueChanged<_HeroOutfitItem>? onItemTap;
  final ValueChanged<_HeroOutfitItem>? onRemoveTap;
  final GlobalKey? outfitSpotlightTargetKey;
  final LayerLink? outfitSpotlightLink;

  @override
  Widget build(BuildContext context) {
    const compact = true;
    final hasOutfitTiles = outfitItems.isNotEmpty;
    const minGridEmpty = 100.0;
    final radius = BorderRadius.circular(20);
    final sharedBodyH = _heroSharedBodyHeight(context);

    final outfitSwitcher = AnimatedSwitcher(
      duration: const Duration(milliseconds: 0),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final slide = Tween<Offset>(
          begin: const Offset(0.02, 0),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(isTomorrow ? 'tomorrow' : 'today'),
        child: loadingMode
            ? const SizedBox.expand()
            : !hasOutfitTiles
                ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    vm.description,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          HomeLuxuryPalette.textSecondary.withOpacity(0.92),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
              )
            : _HeroOutfitTilesGrid(
                items: outfitItems,
                compact: compact,
                editMode: editMode,
                focusedType: focusedType,
                onItemTap: onItemTap,
                onRemoveTap: onRemoveTap,
              ),
      ),
    );

    /// Matches [_HeroSegmentedDay] `compact` height — keep synced with briefing `_kEmbeddedToggleBand`.
    const segmentedToggleBandHeight = 42.0;

    final toggleWeatherBandHeight =
        segmentedToggleBandHeight + _kHeroGapAfterToggle;
    final rightColumnTopInset = editMode
        ? toggleWeatherBandHeight +
            _heroInlineWeatherBandHeight(compact: compact) +
            _kHeroGapBeforeGrid
        : toggleWeatherBandHeight;

    final heroBodyColumn = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 11,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HeroSegmentedDay(
                      index: dayIndex,
                      onChange: onChangeDay,
                      compact: compact,
                    ),
                    const SizedBox(height: _kHeroGapAfterToggle),
                  ],
                ),
                _HeroInlineWeather(
                  weather: weather,
                  compact: compact,
                ),
                const SizedBox(height: _kHeroGapBeforeGrid),
                SizedBox(
                  height: sharedBodyH,
                  width: double.infinity,
                  child: hasOutfitTiles
                      ? outfitSwitcher
                      : ConstrainedBox(
                          constraints:
                              const BoxConstraints(minHeight: minGridEmpty),
                          child: outfitSwitcher,
                        ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 9,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: rightColumnTopInset),
              _UnifiedHeroBriefingGlassPanel(
                gapBeforeGrid: _kHeroGapBeforeGrid,
                sectionTitle: editMode ? null : 'Prehľad dňa',
                briefing: editMode
                    ? const _EditHelperPanel()
                    : HomeDailyBriefingRow(
                        key: ValueKey<String>(
                          'prehlad_${weather.tempC}_${weather.briefingMorningC}_${weather.briefingAfternoonC}_${weather.briefingEveningC}_${weather.briefingMorningCondition}_${weather.briefingAfternoonCondition}_${weather.briefingEveningCondition}_$isTomorrow',
                        ),
                        unifiedEmbedded: true,
                        unifiedSharedBodyHeight: sharedBodyH,
                        baseTempC: weather.tempC,
                        briefingMorningCondition:
                            weather.briefingMorningCondition,
                        briefingAfternoonCondition:
                            weather.briefingAfternoonCondition,
                        briefingEveningCondition:
                            weather.briefingEveningCondition,
                        sideColumn: true,
                        compact: true,
                        briefingMorningTempC: weather.briefingMorningC,
                        briefingAfternoonTempC: weather.briefingAfternoonC,
                        briefingEveningTempC: weather.briefingEveningC,
                      ),
              ),
            ],
          ),
        ),
      ],
    );

    final heroShell = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                HomeLuxuryPalette.surfaceSoft.withOpacity(0.34),
                HomeLuxuryPalette.surface.withOpacity(0.22),
                HomeLuxuryPalette.bgMid.withOpacity(0.28),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: heroBodyColumn,
        ),
      ),
    );
    if (outfitSpotlightLink == null && outfitSpotlightTargetKey == null) {
      return heroShell;
    }
    return CompositedTransformTarget(
      link: outfitSpotlightLink ?? LayerLink(),
      child: KeyedSubtree(
        key: outfitSpotlightTargetKey,
        child: heroShell,
      ),
    );
  }
}

enum _VibeComposerStage {
  initial,
  linkInput,
  linkPlaceholder,
}

class _VibeComposerSheet extends StatefulWidget {
  const _VibeComposerSheet({required this.onPhotoSelected});

  final ValueChanged<XFile> onPhotoSelected;

  @override
  State<_VibeComposerSheet> createState() => _VibeComposerSheetState();
}

class _VibeComposerSheetState extends State<_VibeComposerSheet> {
  final TextEditingController _linkController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  _VibeComposerStage _stage = _VibeComposerStage.initial;

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _pickInspirationPhoto() async {
    final selected = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 86,
    );
    if (!mounted || selected == null) return;
    Navigator.of(context).pop();
    widget.onPhotoSelected(selected);
  }

  void _openLinkInput() {
    setState(() => _stage = _VibeComposerStage.linkInput);
  }

  void _submitLinkPlaceholder() {
    setState(() => _stage = _VibeComposerStage.linkPlaceholder);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final baseTheme = Theme.of(context);
    final localTheme = baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: HomeLuxuryPalette.accent,
        secondary: HomeLuxuryPalette.accent,
        surface: HomeLuxuryPalette.surface,
        onSurface: HomeLuxuryPalette.textPrimary,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: HomeLuxuryPalette.accent.withOpacity(0.96),
        selectionColor: HomeLuxuryPalette.accent.withOpacity(0.28),
        selectionHandleColor: HomeLuxuryPalette.accent.withOpacity(0.96),
      ),
      splashColor: HomeLuxuryPalette.accent.withOpacity(0.10),
      highlightColor: HomeLuxuryPalette.accent.withOpacity(0.06),
      hoverColor: HomeLuxuryPalette.accent.withOpacity(0.05),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: HomeLuxuryPalette.accent.withOpacity(0.95),
          textStyle: const TextStyle(
            fontSize: 13.2,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.06,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.all(
            HomeLuxuryPalette.accent.withOpacity(0.10),
          ),
        ),
      ),
    );
    return SafeArea(
      top: false,
      child: Theme(
        data: localTheme,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, insets + bottomSafe + 12),
          child: HomeGlassSurface(
            borderRadius: 26,
            blurSigma: 18,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _buildStage(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    switch (_stage) {
      case _VibeComposerStage.initial:
        return _buildInitial();
      case _VibeComposerStage.linkInput:
        return _buildLinkInput();
      case _VibeComposerStage.linkPlaceholder:
        return _buildLinkPlaceholder(context);
    }
  }

  Widget _buildInitial() {
    return Column(
      key: const ValueKey('vibe_initial'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ukáž outfit, ktorý sa ti páči',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.22,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Appka sa pokúsi vytvoriť podobný vibe z tvojho šatníka.',
          style: TextStyle(
            color: HomeLuxuryPalette.textSecondary.withOpacity(0.86),
            fontSize: 13.2,
            fontWeight: FontWeight.w500,
            height: 1.34,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _VibeActionCard(
                emoji: '📷',
                title: 'Pridať fotku outfitu',
                subtitle: 'Inšpiráciu vyberieš z galérie.',
                onTap: _pickInspirationPhoto,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _VibeActionCard(
                emoji: '🔗',
                title: 'Pridať link',
                subtitle: 'Vlož odkaz na outfit inšpiráciu.',
                onTap: _openLinkInput,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLinkInput() {
    return Column(
      key: const ValueKey('vibe_link_input'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pridaj link na outfit inšpiráciu',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _linkController,
          keyboardType: TextInputType.url,
          cursorColor: HomeLuxuryPalette.accent.withOpacity(0.96),
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
            fontSize: 13.5,
          ),
          decoration: InputDecoration(
            hintText: 'https://',
            hintStyle: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.60),
              fontSize: 13.4,
            ),
            filled: true,
            fillColor: HomeLuxuryPalette.bgMid.withOpacity(0.35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: HomeLuxuryPalette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: HomeLuxuryPalette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(
                color: HomeLuxuryPalette.accent.withOpacity(0.44),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _stage = _VibeComposerStage.initial),
              child: const Text('Späť'),
            ),
            const Spacer(),
            TextButton(
              onPressed: _submitLinkPlaceholder,
              child: const Text('Pokračovať'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLinkPlaceholder(BuildContext context) {
    return Column(
      key: const ValueKey('vibe_link_placeholder'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pripravujeme podporu outfit linkov ✨',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.12,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'V ďalšej verzii ti z linku prečítame vibe a vyskladáme podobný outfit.',
          style: TextStyle(
            color: HomeLuxuryPalette.textSecondary.withOpacity(0.86),
            fontSize: 12.8,
            fontWeight: FontWeight.w500,
            height: 1.34,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _stage = _VibeComposerStage.initial),
              child: const Text('Späť'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Zavrieť'),
            ),
          ],
        ),
      ],
    );
  }
}

class _VibeRecreationWorkspaceScreen extends StatefulWidget {
  const _VibeRecreationWorkspaceScreen({
    required this.photo,
    required this.onAnalyzeInspiration,
  });

  final XFile photo;
  final Future<_VibeRecreationResult?> Function(XFile photo) onAnalyzeInspiration;

  @override
  State<_VibeRecreationWorkspaceScreen> createState() => _VibeRecreationWorkspaceScreenState();
}

class _VibeRecreationWorkspaceScreenState extends State<_VibeRecreationWorkspaceScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  _VibeRecreationResult? _result;
  List<_HeroOutfitItem> _items = const [];
  final Map<_HeroWearType, int> _poolIndex = {};
  bool _isOutfitEditMode = false;
  _HeroWearType? _focusedEditType;
  bool _likeActive = false;
  int _likePulseTick = 0;
  bool _showLikeFeedback = false;
  int _feedbackToken = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_runAnalysis());
  }

  Future<void> _runAnalysis() async {
    setState(() => _isLoading = true);
    final res = await widget.onAnalyzeInspiration(widget.photo);
    if (!mounted) return;
    setState(() {
      _result = res;
      _isLoading = false;
      _items = _orderedHeroOutfitItems(res?.items ?? const []);
      _poolIndex
        ..clear()
        ..addEntries((_result?.candidatePools.keys ?? const <_HeroWearType>{}).map((t) => MapEntry(t, 0)));
      _likeActive = false;
      _showLikeFeedback = false;
      _likePulseTick = 0;
    });
  }

  void _applyFromPools() {
    final pools = _result?.candidatePools;
    if (pools == null || pools.isEmpty) return;
    final out = <_HeroOutfitItem>[];
    for (final type in const [
      _HeroWearType.outerwear,
      _HeroWearType.top,
      _HeroWearType.bottom,
      _HeroWearType.shoes,
    ]) {
      final pool = pools[type];
      if (pool == null || pool.isEmpty) continue;
      final i = (_poolIndex[type] ?? 0) % pool.length;
      out.add(pool[i]);
    }
    if (out.length < 3) return;
    setState(() {
      _items = _orderedHeroOutfitItems(out);
      _likeActive = false;
      _showLikeFeedback = false;
      _likePulseTick = 0;
    });
  }

  void _handleNewOutfitTap() {
    final pools = _result?.candidatePools;
    if (pools == null || pools.isEmpty) return;
    for (final e in pools.entries) {
      final len = e.value.length;
      if (len <= 1) continue;
      _poolIndex[e.key] = ((_poolIndex[e.key] ?? 0) + 1) % len;
    }
    _applyFromPools();
  }

  void _handleSwapPieceTap() {
    if (_items.isEmpty) return;
    if (_isOutfitEditMode) {
      _exitOutfitEditMode();
      return;
    }
    _enterOutfitEditMode();
  }

  void _enterOutfitEditMode() {
    setState(() {
      _isOutfitEditMode = true;
      _focusedEditType = null;
    });
  }

  void _exitOutfitEditMode() {
    setState(() {
      _isOutfitEditMode = false;
      _focusedEditType = null;
    });
  }

  Future<void> _onEditTileTap(_HeroOutfitItem item) async {
    setState(() => _focusedEditType = item.type);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: _HeroEditActionSheet(
            onAiSuggest: () async {
              Navigator.of(sheetContext).pop();
              await _handleAiSuggestForType(item.type);
            },
            onManualPick: () async {
              Navigator.of(sheetContext).pop();
              await _openManualSelectionForType(item.type);
            },
            onFeedback: () async {
              Navigator.of(sheetContext).pop();
              await _openEditFeedbackInput(item.type);
            },
          ),
        );
      },
    );
  }

  Future<void> _handleAiSuggestForType(_HeroWearType type) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final current = _currentItemForType(type);
    final snap = await _firestore.collection('users').doc(user.uid).collection('wardrobe').get();
    final docs = snap.docs.map((d) => d.data()).toList();
    final candidates = docs
        .where((raw) => _heroWardrobeMatchesTypeLocal(raw, type))
        .map((raw) => _heroItemFromWardrobeLocal(raw: raw, type: type))
        .toList();
    final alternatives = candidates.where((it) => !_isSameOutfitItem(current, it)).toList();
    if (alternatives.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nemáš v šatníku vhodnú alternatívu.')),
      );
      return;
    }
    final chosen = alternatives.first;
    _replaceItemForType(type, chosen);
  }

  Future<void> _openManualSelectionForType(_HeroWearType type) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final current = _currentItemForType(type);
    final snap = await _firestore.collection('users').doc(user.uid).collection('wardrobe').get();
    final docs = snap.docs.map((d) => d.data()).toList();
    final allInCategory = docs
        .where((raw) => _heroWardrobeMatchesTypeLocal(raw, type))
        .map((raw) => _heroItemFromWardrobeLocal(raw: raw, type: type))
        .toList();
    if (allInCategory.length <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('V tejto kategórii zatiaľ nemáš ďalší kúsok.')),
      );
      return;
    }
    final pool = <_HeroOutfitItem>[
      ...allInCategory.where((it) => !_isSameOutfitItem(current, it)),
      ...allInCategory.where((it) => _isSameOutfitItem(current, it)),
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: HomeGlassSurface(
              borderRadius: 22,
              blurSigma: 16,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: SizedBox(
                height: 440,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Čím chceš nahradiť tento kúsok?',
                      style: TextStyle(
                        color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
                        fontSize: 16.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.76,
                        ),
                        itemCount: pool.length,
                        itemBuilder: (_, i) {
                          final item = pool[i];
                          final isCurrent = _isSameOutfitItem(current, item);
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              _replaceItemForType(type, item);
                              Navigator.of(sheetContext).pop();
                            },
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: HomeLuxuryPalette.surface.withOpacity(0.56),
                                border: Border.all(
                                  color: isCurrent
                                      ? HomeLuxuryPalette.accent.withOpacity(0.34)
                                      : HomeLuxuryPalette.border,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(11),
                                      child: ColoredBox(
                                        color: HomeLuxuryPalette.bgMid.withOpacity(0.34),
                                        child: _HeroOutfitImageView(
                                          imageUrl: item.imageUrl,
                                          fallbackIcon: item.icon,
                                          wearType: item.type,
                                          categoryKey: item.categoryKey,
                                          subCategoryKey: item.subCategoryKey,
                                          itemLabel: item.label,
                                          compact: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  Text(
                                    item.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isCurrent
                                          ? HomeLuxuryPalette.textSecondary.withOpacity(0.78)
                                          : HomeLuxuryPalette.textPrimary.withOpacity(0.92),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEditFeedbackInput(_HeroWearType type) async {
    final ctrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        final safeBottom = MediaQuery.paddingOf(sheetContext).bottom;
        final base = Theme.of(sheetContext);
        final localTheme = base.copyWith(
          colorScheme: base.colorScheme.copyWith(
            primary: HomeLuxuryPalette.accent,
            secondary: HomeLuxuryPalette.accent,
            surface: HomeLuxuryPalette.surface,
            onSurface: HomeLuxuryPalette.textPrimary,
          ),
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: HomeLuxuryPalette.accent.withOpacity(0.96),
            selectionColor: HomeLuxuryPalette.accent.withOpacity(0.30),
            selectionHandleColor: HomeLuxuryPalette.accent.withOpacity(0.96),
          ),
          splashColor: HomeLuxuryPalette.accent.withOpacity(0.10),
          highlightColor: HomeLuxuryPalette.accent.withOpacity(0.06),
          hoverColor: HomeLuxuryPalette.accent.withOpacity(0.05),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: HomeLuxuryPalette.accent.withOpacity(0.95),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ).copyWith(
              overlayColor: WidgetStateProperty.all(
                HomeLuxuryPalette.accent.withOpacity(0.10),
              ),
            ),
          ),
        );
        return Theme(
          data: localTheme,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + safeBottom + 24),
            child: HomeGlassSurface(
              borderRadius: 22,
              blurSigma: 18,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Napíš čo ti vadí',
                    style: TextStyle(
                      color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
                      fontSize: 15.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ctrl,
                    maxLines: 4,
                    cursorColor: HomeLuxuryPalette.accent.withOpacity(0.96),
                    style: TextStyle(color: HomeLuxuryPalette.textPrimary.withOpacity(0.94)),
                    decoration: InputDecoration(
                      hintText: 'Napíš čo ti na kúsku nesedí a aký vibe chceš skúsiť.',
                      hintStyle: TextStyle(
                        color: HomeLuxuryPalette.textSecondary.withOpacity(0.66),
                        fontSize: 12.6,
                      ),
                      filled: true,
                      fillColor: HomeLuxuryPalette.bgMid.withOpacity(0.34),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: HomeLuxuryPalette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: HomeLuxuryPalette.accent.withOpacity(0.48),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Zrušiť'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await _handleAiSuggestForType(type);
                        },
                        child: const Text('Použiť návrh AI'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isSameOutfitItem(_HeroOutfitItem? a, _HeroOutfitItem b) {
    if (a == null) return false;
    return a.type == b.type && a.label == b.label && a.imageUrl == b.imageUrl;
  }

  _HeroOutfitItem? _currentItemForType(_HeroWearType type) {
    for (final it in _items) {
      if (it.type == type) return it;
    }
    return null;
  }

  String _heroBlobLocal(Map<String, dynamic> raw) {
    final cat = (raw['categoryKey'] ?? raw['category'] ?? '').toString();
    final sub = (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString();
    final main = (raw['mainGroupKey'] ?? raw['mainGroup'] ?? '').toString();
    final name = (raw['name'] ?? '').toString();
    return '$name $cat $sub $main'.toLowerCase();
  }

  bool _heroWardrobeMatchesTypeLocal(Map<String, dynamic> raw, _HeroWearType type) {
    final b = _heroBlobLocal(raw);
    bool has(List<String> needles) => needles.any((n) => b.contains(n));
    switch (type) {
      case _HeroWearType.top:
        return has([
          'trič', 'tricko', 't-shirt', 'top', 'koše', 'blúz', 'bluz', 'sveter', 'shirt', 'hoodie', 'mikina',
        ]);
      case _HeroWearType.bottom:
        return has(['nohav', 'rifl', 'jeans', 'pants', 'sukn', 'skirt', 'short']);
      case _HeroWearType.shoes:
        return has(['topán', 'topan', 'tenis', 'sneaker', 'boots', 'sand', 'obuv', 'shoes']);
      case _HeroWearType.outerwear:
        return has(['bunda', 'kabát', 'kabat', 'sako', 'blazer', 'coat', 'jacket', 'overshirt', 'bomber']);
    }
  }

  String _heroLabelForWardrobeItemLocal(Map<String, dynamic> raw, {required String fallback}) {
    final name = (raw['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final sub = (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString().trim();
    if (sub.isNotEmpty) return sub;
    final cat = (raw['categoryKey'] ?? raw['category'] ?? '').toString().trim();
    if (cat.isNotEmpty) return cat;
    return fallback;
  }

  _HeroOutfitItem _heroItemFromWardrobeLocal({
    required Map<String, dynamic> raw,
    required _HeroWearType type,
  }) {
    final brandRaw = (raw['brand'] ?? '').toString().trim();
    final categoryKey = (raw['categoryKey'] ?? raw['category'] ?? '').toString().trim();
    final subCategoryKey = (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString().trim();
    return _HeroOutfitItem(
      type: type,
      icon: type == _HeroWearType.top
          ? Icons.checkroom
          : type == _HeroWearType.bottom
          ? Icons.style
          : type == _HeroWearType.shoes
          ? Icons.directions_run
          : Icons.umbrella,
      label: _heroLabelForWardrobeItemLocal(
        raw,
        fallback: type == _HeroWearType.top
            ? 'Vrchný diel'
            : type == _HeroWearType.bottom
            ? 'Spodný diel'
            : type == _HeroWearType.shoes
            ? 'Obuv'
            : 'Vrstva',
      ),
      brandLine: brandRaw.isNotEmpty ? brandRaw : null,
      imageUrl: _heroWardrobeDisplayImageUrl(raw),
      categoryKey: categoryKey.isNotEmpty ? categoryKey : null,
      subCategoryKey: subCategoryKey.isNotEmpty ? subCategoryKey : null,
      imageProcessing: wardrobeItemShowsImageProcessingBadge(raw),
    );
  }

  Future<void> _onRemoveTileTap(_HeroOutfitItem item) async {
    final remove = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: HomeLuxuryPalette.surfaceSoft.withOpacity(0.96),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text(
              'Odstrániť tento kúsok z outfitu?',
              style: TextStyle(
                color: HomeLuxuryPalette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Zrušiť')),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Odstrániť')),
            ],
          ),
        ) ??
        false;
    if (!remove) return;
    setState(() {
      _items = List<_HeroOutfitItem>.from(_items)..removeWhere((it) => it.type == item.type);
      if (_focusedEditType == item.type) _focusedEditType = null;
    });
  }

  void _replaceItemForType(_HeroWearType type, _HeroOutfitItem newItem) {
    final current = List<_HeroOutfitItem>.from(_items);
    final idx = current.indexWhere((it) => it.type == type);
    if (idx >= 0) {
      current[idx] = newItem;
    } else {
      current.add(newItem);
    }
    setState(() {
      _items = _orderedHeroOutfitItems(current);
    });
  }

  void _handleLikeTap() {
    final token = ++_feedbackToken;
    setState(() {
      _likeActive = true;
      _likePulseTick++;
      _showLikeFeedback = true;
    });
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 4100), () {
        if (!mounted || token != _feedbackToken) return;
        setState(() => _showLikeFeedback = false);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeLuxuryPalette.bgBottom,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Podobný vibe z tvojho šatníka',
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary.withOpacity(0.97),
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Podľa inšpirácie, ktorú si pridal.',
                style: TextStyle(
                  color: HomeLuxuryPalette.textSecondary.withOpacity(0.88),
                  fontSize: 13.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: _generatedPanel()),
                        const SizedBox(width: 10),
                        Expanded(flex: 4, child: _referencePanel()),
                      ],
                    ),
                    if (_isOutfitEditMode)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _exitOutfitEditMode,
                          child: ClipRect(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
                                  child: const SizedBox.expand(),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        const Color(0xAA000000),
                                        const Color(0xB3000000),
                                        const Color(0xB8000000),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_isOutfitEditMode)
                      Positioned.fill(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: _editModeOutfitPanel()),
                            const SizedBox(width: 10),
                            const Expanded(
                              flex: 4,
                              child: _EditHelperPanel(withGlassBackground: true),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (!_isLoading && _items.isNotEmpty) ...[
                const SizedBox(height: 12),
                _workspaceActionSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _generatedPanel() {
    final itemCount = _items.length;
    final imageScale = itemCount >= 6
        ? 0.58
        : itemCount == 5
        ? 0.64
        : itemCount == 4
        ? 0.70
        : 0.78;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLoading) ...[
            SizedBox(
              height: 320,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(HomeLuxuryPalette.accent),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Analyzujeme štýl outfitu ✨',
                    style: TextStyle(
                      color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
                      fontSize: 14.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hľadáme podobné kúsky vo tvojom šatníku.',
                    style: TextStyle(
                      color: HomeLuxuryPalette.textSecondary.withOpacity(0.86),
                      fontSize: 12.6,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_items.isEmpty) ...[
            SizedBox(
              height: 300,
              child: Center(
                child: Text(
                  'Nenašli sme dosť vhodných kúskov pre podobný vibe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ] else ...[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430, maxHeight: 420),
                child: _HeroOutfitTilesGrid(
                  items: _items,
                  compact: true,
                  imageScaleMultiplier: imageScale,
                  recreatedShoeScaleBoost: 1.12,
                  spacingMultiplier: 0.84,
                  horizontalSpacingMultiplier: 0.82,
                  verticalSpacingMultiplier: 0.42,
                  fourItemRowSpacingExtra: 1.4,
                  disableBoundedScroll: true,
                ),
              ),
            ),
            if ((_result?.honestyMessage ?? '').isNotEmpty ||
                (_result?.missingPieces.length ?? 0) > 0 ||
                (_result?.suggestedFillers.length ?? 0) > 0) ...[
              const SizedBox(height: 12),
              _wardrobeLimitationsSection(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _editModeOutfitPanel() {
    final itemCount = _items.length;
    final imageScale = itemCount >= 6
        ? 0.58
        : itemCount == 5
        ? 0.64
        : itemCount == 4
        ? 0.70
        : 0.78;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430, maxHeight: 420),
              child: _HeroOutfitTilesGrid(
                items: _items,
                compact: true,
                imageScaleMultiplier: imageScale,
                recreatedShoeScaleBoost: 1.12,
                spacingMultiplier: 0.84,
                horizontalSpacingMultiplier: 0.82,
                verticalSpacingMultiplier: 0.42,
                fourItemRowSpacingExtra: 1.4,
                disableBoundedScroll: true,
                editMode: true,
                focusedType: _focusedEditType,
                onItemTap: _onEditTileTap,
                onRemoveTap: _onRemoveTileTap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wardrobeLimitationsSection() {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((_result?.honestyMessage ?? '').isNotEmpty)
              Text(
                _result!.honestyMessage!,
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary.withOpacity(0.92),
                  fontSize: 12.4,
                  fontWeight: FontWeight.w600,
                  height: 1.32,
                ),
              ),
            if ((_result?.missingPieces.length ?? 0) > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Chýbajú tieto kúsky:',
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary.withOpacity(0.9),
                  fontSize: 12.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              for (final piece in _result!.missingPieces)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '- $piece',
                    style: TextStyle(
                      color: HomeLuxuryPalette.textSecondary.withOpacity(0.9),
                      fontSize: 12.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
            if ((_result?.suggestedFillers.length ?? 0) > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Doplniť vibe',
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
                  fontSize: 14.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Tieto kúsky by pomohli dotvoriť podobný vibe.',
                style: TextStyle(
                  color: HomeLuxuryPalette.textSecondary.withOpacity(0.86),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: _result!.suggestedFillers
                    .take(3)
                    .map((label) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: HomeLuxuryPalette.surfaceSoft.withOpacity(0.42),
                            border: Border.all(
                              color: HomeLuxuryPalette.accent.withOpacity(0.22),
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: HomeLuxuryPalette.textPrimary.withOpacity(0.93),
                              fontSize: 11.7,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _workspaceActionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroOutfitActionBar(
          onNewOutfit: _handleNewOutfitTap,
          onSwapPiece: _handleSwapPieceTap,
          onLike: _handleLikeTap,
          likeActive: _likeActive,
          likePulseTick: _likePulseTick,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _showLikeFeedback
              ? Padding(
                  key: const ValueKey('workspace_like_feedback_visible'),
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(
                    'Appka si zapamätá, že sa ti tento vibe páči ✨',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      color: HomeLuxuryPalette.textSecondary.withOpacity(0.84),
                      fontSize: 12.2,
                      fontWeight: FontWeight.w500,
                      height: 1.22,
                      letterSpacing: 0.03,
                    ),
                  ),
                )
              : const SizedBox(key: ValueKey('workspace_like_feedback_hidden')),
        ),
      ],
    );
  }

  Widget _referencePanel() {
    return HomeGlassSurface(
      borderRadius: 22,
      blurSigma: 14,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inšpirácia',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
              fontSize: 14.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 0.86,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: HomeLuxuryPalette.bgMid.withOpacity(0.42),
                child: Image.file(
                  File(widget.photo.path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(
                      Icons.photo_outlined,
                      color: HomeLuxuryPalette.textSecondary.withOpacity(0.75),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'O outfite',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
              fontSize: 14.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _outfitInfoLine('Clean streetwear vibe'),
          _outfitInfoLine('Vrstvenie: mikina + bunda'),
          _outfitInfoLine('Kontrast červenej a denimu'),
          _outfitInfoLine('Tmavé nohavice, športové tenisky'),
        ],
      ),
    );
  }

  Widget _outfitInfoLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.auto_awesome,
              size: 13,
              color: HomeLuxuryPalette.accent.withOpacity(0.92),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: HomeLuxuryPalette.textSecondary.withOpacity(0.9),
                fontSize: 12.3,
                fontWeight: FontWeight.w500,
                height: 1.27,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VibeActionCard extends StatelessWidget {
  const _VibeActionCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: HomeLuxuryPalette.accent.withOpacity(0.10),
        highlightColor: HomeLuxuryPalette.accent.withOpacity(0.06),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 13, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: HomeLuxuryPalette.accent.withOpacity(0.22),
              width: 0.9,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                HomeLuxuryPalette.surfaceSoft.withOpacity(0.64),
                HomeLuxuryPalette.surface.withOpacity(0.52),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.08,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(
                  color: HomeLuxuryPalette.textSecondary.withOpacity(0.83),
                  fontSize: 11.8,
                  fontWeight: FontWeight.w500,
                  height: 1.26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass segmented controls — replaces stacked gold CTAs.
class _HeroOutfitActionBar extends StatelessWidget {
  const _HeroOutfitActionBar({
    required this.onNewOutfit,
    required this.onSwapPiece,
    required this.onLike,
    this.likeActive = false,
    this.likePulseTick = 0,
    this.newOutfitLoading = false,
  });

  final VoidCallback onNewOutfit;
  final VoidCallback onSwapPiece;
  final VoidCallback onLike;
  final bool likeActive;
  final int likePulseTick;
  final bool newOutfitLoading;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.09)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                HomeLuxuryPalette.surfaceSoft.withOpacity(0.62),
                HomeLuxuryPalette.surface.withOpacity(0.42),
              ],
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: _BarHit(
                  emoji: '❌',
                  label: newOutfitLoading ? 'Generujem…' : 'Nový outfit',
                  onTap: onNewOutfit,
                ),
              ),
              _barDivider(),
              Expanded(
                child: _BarHit(
                  emoji: '🔄',
                  label: 'Vymeniť kúsok',
                  onTap: onSwapPiece,
                ),
              ),
              _barDivider(),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('likePulse_$likePulseTick'),
                  tween: Tween<double>(begin: 1.06, end: 1.0),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  builder: (context, scale, child) {
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: _BarHit(
                    emoji: '✅',
                    label: 'Páči sa mi',
                    onTap: onLike,
                    active: likeActive,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barDivider() {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      color: HomeLuxuryPalette.textSecondary.withOpacity(0.12),
    );
  }
}

class _BarHit extends StatelessWidget {
  const _BarHit({
    required this.emoji,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: HomeLuxuryPalette.accent.withOpacity(active ? 0.10 : 0.06),
        highlightColor: HomeLuxuryPalette.accent.withOpacity(active ? 0.06 : 0.04),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: active
                ? Border.all(
                    color: HomeLuxuryPalette.accent.withOpacity(0.34),
                    width: 0.8,
                  )
                : null,
            gradient: active
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      HomeLuxuryPalette.accent.withOpacity(0.14),
                      HomeLuxuryPalette.accent.withOpacity(0.05),
                    ],
                  )
                : null,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: HomeLuxuryPalette.accent.withOpacity(0.20),
                      blurRadius: 14,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  emoji,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? HomeLuxuryPalette.accent : null,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active
                          ? HomeLuxuryPalette.textPrimary.withOpacity(0.96)
                          : HomeLuxuryPalette.textPrimary.withOpacity(0.88),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      letterSpacing: 0.05,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroSegmentedDay extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChange;
  final bool compact;

  const _HeroSegmentedDay({
    required this.index,
    required this.onChange,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final height = compact ? 42.0 : 46.0;
    final outerPad = compact ? 5.0 : 6.0;
    final gap = compact ? 6.0 : 8.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          height: height,
          padding: EdgeInsets.all(outerPad),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.11)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.09),
                Colors.white.withOpacity(0.03),
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _SegItem(
                  label: 'Dnes',
                  active: index == 0,
                  compact: compact,
                  onTap: () => onChange(0),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _SegItem(
                  label: 'Zajtra',
                  active: index == 1,
                  compact: compact,
                  onTap: () => onChange(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegItem extends StatelessWidget {
  final String label;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  const _SegItem({
    required this.label,
    required this.active,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final fs = compact ? 13.5 : 14.5;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        splashColor: Colors.white.withOpacity(0.07),
        highlightColor: Colors.white.withOpacity(0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 7 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? HomeLuxuryPalette.accent.withOpacity(0.42)
                  : Colors.transparent,
            ),
            gradient: active
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      HomeLuxuryPalette.accent.withOpacity(0.26),
                      HomeLuxuryPalette.accent.withOpacity(0.10),
                    ],
                  )
                : null,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: HomeLuxuryPalette.accent.withOpacity(0.32),
                      blurRadius: 16,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: active
                    ? HomeLuxuryPalette.textPrimary
                    : HomeLuxuryPalette.textSecondary.withOpacity(0.92),
                fontSize: fs,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// =======================
/// Ostatné widgety (nezmenené)
/// =======================
class _HeroEditActionSheet extends StatelessWidget {
  const _HeroEditActionSheet({
    required this.onAiSuggest,
    required this.onManualPick,
    required this.onFeedback,
  });

  final VoidCallback onAiSuggest;
  final VoidCallback onManualPick;
  final VoidCallback onFeedback;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + safeBottom),
      child: HomeGlassSurface(
        borderRadius: 20,
        blurSigma: 18,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeroEditSheetAction(
              emoji: '✨',
              title: 'AI navrhne inú',
              onTap: onAiSuggest,
            ),
            const SizedBox(height: 8),
            _HeroEditSheetAction(
              emoji: '👕',
              title: 'Vyberiem si sám',
              onTap: onManualPick,
            ),
            const SizedBox(height: 8),
            _HeroEditSheetAction(
              emoji: '💬',
              title: 'Napíš čo ti vadí',
              onTap: onFeedback,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroEditSheetAction extends StatelessWidget {
  const _HeroEditSheetAction({
    required this.emoji,
    required this.title,
    required this.onTap,
  });
  final String emoji;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: HomeLuxuryPalette.surface.withOpacity(0.5),
            border: Border.all(color: HomeLuxuryPalette.border),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualCategoryOption {
  const _ManualCategoryOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class _EditHelperPanel extends StatelessWidget {
  const _EditHelperPanel({
    this.withGlassBackground = false,
  });

  final bool withGlassBackground;

  @override
  Widget build(BuildContext context) {
    final helperContent = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vyber kúsok na úpravu',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.08,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Môžeš ho zmeniť alebo odstrániť z outfitu.',
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.92),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, right: 6),
        child: withGlassBackground
            ? Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: HomeLuxuryPalette.surfaceSoft.withOpacity(0.26),
                  border: Border.all(
                    color: HomeLuxuryPalette.accent.withOpacity(0.12),
                  ),
                ),
                child: HomeGlassSurface(
                  borderRadius: 16,
                  blurSigma: 10,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: helperContent,
                ),
              )
            : helperContent,
      ),
    );
  }
}

class _HeroOutfitItem {
  final _HeroWearType type;
  final IconData icon;
  final String label;
  final String? brandLine;
  final String? imageUrl;
  final String? categoryKey;
  final String? subCategoryKey;
  /// Firestore dokument šatníka — na výklik „Nový outfit“ / porovnanie kombinácie.
  final String? wardrobeItemId;
  final bool imageProcessing;

  const _HeroOutfitItem({
    required this.type,
    required this.icon,
    required this.label,
    this.brandLine,
    this.imageUrl,
    this.categoryKey,
    this.subCategoryKey,
    this.wardrobeItemId,
    this.imageProcessing = false,
  });
}

class _HeroBannerVM {
  final String description;

  const _HeroBannerVM({
    required this.description,
  });
}

class _HeroTodayState {
  final _HeroBannerVM vm;
  final List<_HeroOutfitItem> outfitItems;
  final String source;
  final String? loadingReason;

  const _HeroTodayState({
    required this.vm,
    required this.outfitItems,
    required this.source,
    this.loadingReason,
  });
}

enum _HeroWearType { top, bottom, shoes, outerwear }

class _TypedWardrobePick {
  final _HeroWearType type;
  final Map<String, dynamic> item;

  const _TypedWardrobePick({required this.type, required this.item});
}

class _HeroOutfitRecommendation {
  final List<_HeroOutfitItem> items;
  final String reason;

  const _HeroOutfitRecommendation({
    required this.items,
    required this.reason,
  });
}

enum _VibeStyle { sporty, clean, street }

class _VibeImageAnalysis {
  final double avgLuminance;
  final double avgSaturation;
  final double contrast;
  final List<int> dominantHueBins;
  final int layeringCount;
  final bool layeredOutfit;
  final bool redAccentImportant;
  final bool denimLightImportant;
  final bool darkBottomImportant;
  final _VibeStyle style;

  const _VibeImageAnalysis({
    required this.avgLuminance,
    required this.avgSaturation,
    required this.contrast,
    required this.dominantHueBins,
    required this.layeringCount,
    required this.layeredOutfit,
    required this.redAccentImportant,
    required this.denimLightImportant,
    required this.darkBottomImportant,
    required this.style,
  });
}

class _VibeRecreationResult {
  final List<_HeroOutfitItem> items;
  final String summary;
  final Map<_HeroWearType, List<_HeroOutfitItem>> candidatePools;
  final String? honestyMessage;
  final List<String> missingPieces;
  final List<String> suggestedFillers;

  const _VibeRecreationResult({
    required this.items,
    required this.summary,
    required this.candidatePools,
    this.honestyMessage,
    this.missingPieces = const [],
    this.suggestedFillers = const [],
  });
}

class _ScoredRaw {
  final Map<String, dynamic> raw;
  final double score;
  const _ScoredRaw({required this.raw, required this.score});
}

class _VibeComposition {
  final List<_TypedWardrobePick> picks;
  final List<String> missingPieces;
  final List<String> suggestedFillers;
  final String? honestyMessage;

  const _VibeComposition({
    required this.picks,
    required this.missingPieces,
    required this.suggestedFillers,
    required this.honestyMessage,
  });
}

class _HomeAiCacheEntry {
  final String signature;
  final _HeroOutfitRecommendation? recommendation;

  const _HomeAiCacheEntry({
    required this.signature,
    required this.recommendation,
  });
}

class _HomeAiRequestContext {
  final DateTime date;
  final _LocalWeather weather;
  final Set<String> excludedItemIds;
  final Set<String> rejectedCombinationSignatures;
  final Set<String> previousOutfitItemIds;
  final bool forceDifferentOutfit;
  final bool isPremiumUser;

  const _HomeAiRequestContext({
    required this.date,
    required this.weather,
    required this.excludedItemIds,
    required this.rejectedCombinationSignatures,
    required this.previousOutfitItemIds,
    required this.forceDifferentOutfit,
    required this.isPremiumUser,
  });
}

class _HomeDayHeroCacheEntry {
  final _HeroTodayState state;
  final String weatherSignature;
  final String wardrobeSignature;

  const _HomeDayHeroCacheEntry({
    required this.state,
    required this.weatherSignature,
    required this.wardrobeSignature,
  });
}

class _LocalWeather {
  final int tempC;
  final bool isRainy;
  final bool isWindy;
  final String seasonLabel; // Jar/Leto/Jeseň/Zima
  /// Kalendárny deň počasia (deň pre výber outfitu / kontext).
  final DateTime calendarDate;
  final bool morningRainSegment;
  final bool afternoonRainSegment;
  final bool eveningRainSegment;
  /// Hodinové teploty segmentov; null → [HomeDailyBriefingRow] odvodí z [tempC].
  final int? briefingMorningC;
  final int? briefingAfternoonC;
  final int? briefingEveningC;
  /// Krátke štítky počasia pre „Prehľad dňa“.
  final String briefingMorningCondition;
  final String briefingAfternoonCondition;
  final String briefingEveningCondition;
  final String outfitWhyWeatherNote;
  /// Ľudsky napísané okná dažďa (napr. „ráno 08:00“) — pre stylistický text, nie hero počasie.
  final String? rainTimeText;

  const _LocalWeather({
    required this.tempC,
    required this.isRainy,
    required this.isWindy,
    required this.seasonLabel,
    required this.calendarDate,
    this.morningRainSegment = false,
    this.afternoonRainSegment = false,
    this.eveningRainSegment = false,
    this.briefingMorningC,
    this.briefingAfternoonC,
    this.briefingEveningC,
    required this.briefingMorningCondition,
    required this.briefingAfternoonCondition,
    required this.briefingEveningCondition,
    this.outfitWhyWeatherNote = '',
    this.rainTimeText,
  });

  static _LocalWeather fromSnapshot(OutfitWeatherDaySnapshot snap) {
    final month = snap.date.month;
    final seasonLabel = (month >= 3 && month <= 5)
        ? 'Jar'
        : (month >= 6 && month <= 8)
        ? 'Leto'
        : (month >= 9 && month <= 11)
        ? 'Jeseň'
        : 'Zima';
    return _LocalWeather(
      tempC: snap.mainChipTempC,
      isRainy: snap.willRain,
      isWindy: snap.isWindy,
      seasonLabel: seasonLabel,
      calendarDate: DateTime(snap.date.year, snap.date.month, snap.date.day),
      morningRainSegment: snap.morningRainSegment,
      afternoonRainSegment: snap.afternoonRainSegment,
      eveningRainSegment: snap.eveningRainSegment,
      briefingMorningC: snap.morningTempC,
      briefingAfternoonC: snap.noonTempC,
      briefingEveningC: snap.eveningTempC,
      briefingMorningCondition: snap.briefingMorningCondition,
      briefingAfternoonCondition: snap.briefingAfternoonCondition,
      briefingEveningCondition: snap.briefingEveningCondition,
      outfitWhyWeatherNote: snap.outfitWhyWeatherNote,
      rainTimeText: snap.rainTimeText,
    );
  }

  static _LocalWeather fallbackFor(DateTime date) {
    // Jednoduché, deterministické hodnoty aby UI fungovalo aj offline.
    final month = date.month;
    final seasonLabel = (month >= 3 && month <= 5)
        ? 'Jar'
        : (month >= 6 && month <= 8)
        ? 'Leto'
        : (month >= 9 && month <= 11)
        ? 'Jeseň'
        : 'Zima';

    int baseTemp;
    if (seasonLabel == 'Zima') {
      baseTemp = 2;
    } else if (seasonLabel == 'Jar') {
      baseTemp = 10;
    } else if (seasonLabel == 'Leto') {
      baseTemp = 24;
    } else {
      baseTemp = 12; // Jeseň
    }

    // jemné kolísanie podľa dňa v mesiaci (-2..+2)
    final delta = (date.day % 5) - 2;
    final tempC = baseTemp + delta;

    // šanca na dážď častejšie na jar/jeseň (deterministicky)
    final rainyMonths = <int>{3, 4, 5, 9, 10, 11};
    final isRainy = rainyMonths.contains(month) && (date.day % 3 == 0);
    final isWindy = date.day % 4 == 0;

    final mt = tempC - 1;
    final at = tempC;
    final et = tempC - 2;
    const morningRainSeg = false;
    final afternoonRainSeg = isRainy;
    const eveningRainSeg = false;
    final d = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isTomorrow = d == today.add(const Duration(days: 1));
    final minT = tempC - 3;
    final maxT = tempC + 1;
    final ux = buildDayWeatherUx(
      date: d,
      isTomorrow: isTomorrow,
      morningTempC: mt,
      afternoonTempC: at,
      eveningTempC: et,
      mainChipTempC: tempC,
      minTempC: minT,
      maxTempC: maxT,
      willRain: isRainy,
      morningRain: morningRainSeg,
      afternoonRain: afternoonRainSeg,
      eveningRain: eveningRainSeg,
      isWindy: isWindy,
      windMorning: isWindy,
      windAfternoon: isWindy,
      windEvening: isWindy,
    );

    return _LocalWeather(
      tempC: tempC,
      isRainy: isRainy,
      isWindy: isWindy,
      seasonLabel: seasonLabel,
      calendarDate: d,
      morningRainSegment: morningRainSeg,
      afternoonRainSegment: afternoonRainSeg,
      eveningRainSegment: eveningRainSeg,
      briefingMorningC: mt,
      briefingAfternoonC: at,
      briefingEveningC: et,
      briefingMorningCondition: BriefingWeatherCondition.briefingUiSk(
        BriefingWeatherCondition.fallback(
          segmentRain: morningRainSeg,
          segmentWindy: isWindy,
          segment: BriefingDaySegment.morning,
        ),
      ),
      briefingAfternoonCondition: BriefingWeatherCondition.briefingUiSk(
        BriefingWeatherCondition.fallback(
          segmentRain: afternoonRainSeg,
          segmentWindy: isWindy,
          segment: BriefingDaySegment.afternoon,
        ),
      ),
      briefingEveningCondition: BriefingWeatherCondition.briefingUiSk(
        BriefingWeatherCondition.fallback(
          segmentRain: eveningRainSeg,
          segmentWindy: isWindy,
          segment: BriefingDaySegment.evening,
        ),
      ),
      outfitWhyWeatherNote: ux.outfitWhyWeatherNote,
      rainTimeText: isRainy ? 'poobedie okolo 17:00' : null,
    );
  }

  String get seasonKey {
    final s = seasonLabel.toLowerCase();
    if (s.contains('jar')) return 'jar';
    if (s.contains('let')) return 'let';
    if (s.contains('jese')) return 'jese';
    return 'zim';
  }

  String get summarySubtitle {
    final parts = <String>[seasonLabel, '$tempC°C'];
    if (isWindy) parts.add('vietor');
    if (isRainy) parts.add('dážď');
    if (!isWindy && !isRainy) parts.add('jasno');
    return parts.join(' • ');
  }

}

List<_HeroOutfitItem> _orderedHeroOutfitItems(List<_HeroOutfitItem> items) {
  final orderedItems = <_HeroOutfitItem>[];
  void addByType(_HeroWearType type) {
    for (final item in items) {
      if (item.type == type) {
        orderedItems.add(item);
        break;
      }
    }
  }

  addByType(_HeroWearType.outerwear);
  addByType(_HeroWearType.top);
  addByType(_HeroWearType.bottom);
  addByType(_HeroWearType.shoes);
  return orderedItems;
}

class _HeroOutfitTilesGrid extends StatelessWidget {
  final List<_HeroOutfitItem> items;
  final bool compact;
  final double imageScaleMultiplier;
  final double recreatedShoeScaleBoost;
  final double spacingMultiplier;
  final double horizontalSpacingMultiplier;
  final double verticalSpacingMultiplier;
  final double fourItemRowSpacingExtra;
  final bool disableBoundedScroll;
  final bool editMode;
  final _HeroWearType? focusedType;
  final ValueChanged<_HeroOutfitItem>? onItemTap;
  final ValueChanged<_HeroOutfitItem>? onRemoveTap;

  const _HeroOutfitTilesGrid({
    required this.items,
    this.compact = false,
    this.imageScaleMultiplier = 1.0,
    this.recreatedShoeScaleBoost = 1.0,
    this.spacingMultiplier = 1.0,
    this.horizontalSpacingMultiplier = 1.0,
    this.verticalSpacingMultiplier = 1.0,
    this.fourItemRowSpacingExtra = 10.0,
    this.disableBoundedScroll = false,
    this.editMode = false,
    this.focusedType,
    this.onItemTap,
    this.onRemoveTap,
  });

  /// Same layouts as before, without a bounded parent — used inside [SingleChildScrollView].
  Widget _buildLooseLayout({
    required double maxW,
    required int n,
    required double spacingMultiplier,
    required double horizontalSpacingMultiplier,
    required double verticalSpacingMultiplier,
    required Widget Function(int i) tile,
  }) {
    final narrow = maxW < 168;
    final baseGap = narrow ? 8.0 : (compact ? 10.0 : 14.0);
    final hGap = (baseGap * spacingMultiplier * horizontalSpacingMultiplier).clamp(6.0, 16.0);
    final vGap = (baseGap * spacingMultiplier * verticalSpacingMultiplier).clamp(4.0, 16.0);

    if (n <= 3) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) SizedBox(height: vGap),
            tile(i),
          ],
        ],
      );
    }

    if (n == 4) {
      final rowGap = (vGap + fourItemRowSpacingExtra).clamp(3.0, 22.0);
      const tileAspect = 0.82;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: hGap,
          mainAxisSpacing: rowGap,
          childAspectRatio: tileAspect,
        ),
        itemCount: 4,
        itemBuilder: (_, i) => tile(i),
      );
    }

    if (n == 5) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: hGap,
            mainAxisSpacing: vGap,
            childAspectRatio: 1,
            children: [tile(0), tile(1), tile(2), tile(3)],
          ),
          SizedBox(height: vGap),
          Align(
            alignment: Alignment.center,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: AspectRatio(
                aspectRatio: 1,
                child: tile(4),
              ),
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: hGap,
        mainAxisSpacing: vGap,
        childAspectRatio: 1,
      ),
      itemCount: n,
      itemBuilder: (_, i) => tile(i),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _orderedHeroOutfitItems(items);
    final display = ordered.length > 6 ? ordered.sublist(0, 6) : ordered;
    final n = display.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final narrow = maxW < 168;
        final baseGap = narrow ? 8.0 : (compact ? 10.0 : 14.0);
        final hGap = (baseGap * spacingMultiplier * horizontalSpacingMultiplier).clamp(6.0, 16.0);
        final vGap = (baseGap * spacingMultiplier * verticalSpacingMultiplier).clamp(4.0, 16.0);
        final maxH = constraints.maxHeight;
        final heightBounded =
            maxH.isFinite && maxH < double.infinity && maxH > 1;

        Widget tile(int i) => _HeroOutfitTileCard(
              item: display[i],
              compact: compact,
              imageScaleMultiplier: imageScaleMultiplier,
              recreatedShoeScaleBoost: recreatedShoeScaleBoost,
              editMode: editMode,
              selected: focusedType == null || focusedType == display[i].type,
              onTap: onItemTap == null ? null : () => onItemTap!(display[i]),
              onRemoveTap: onRemoveTap == null ? null : () => onRemoveTap!(display[i]),
            );

        Widget tileFill(int i) => _HeroOutfitTileCard(
              item: display[i],
              compact: compact,
              imageScaleMultiplier: imageScaleMultiplier,
              recreatedShoeScaleBoost: recreatedShoeScaleBoost,
              expandCell: true,
              editMode: editMode,
              selected: focusedType == null || focusedType == display[i].type,
              onTap: onItemTap == null ? null : () => onItemTap!(display[i]),
              onRemoveTap: onRemoveTap == null ? null : () => onRemoveTap!(display[i]),
            );

        if (n == 0) {
          return const SizedBox.shrink();
        }

        // Exactly 3 items: 2 tiles on top row, 1 tile on bottom-left.
        // Keeps the outfit compact and fully visible in shared hero body.
        if (n == 3 && heightBounded && !disableBoundedScroll) {
          final rowGap = (vGap * 0.92).clamp(4.0, 12.0);
          return AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: tileFill(0)),
                      SizedBox(width: hGap),
                      Expanded(child: tileFill(1)),
                    ],
                  ),
                ),
                SizedBox(height: rowGap),
                Expanded(child: tileFill(2)),
              ],
            ),
          );
        }

        // 2×2 fills the shared hero body; equal row heights; no shrink-wrap grid height.
        if (n == 4 && heightBounded && !disableBoundedScroll) {
          final rowGap = vGap + 4;
          return AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: tileFill(0)),
                      SizedBox(width: hGap),
                      Expanded(child: tileFill(1)),
                    ],
                  ),
                ),
                SizedBox(height: rowGap),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: tileFill(2)),
                      SizedBox(width: hGap),
                      Expanded(child: tileFill(3)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final loose = _buildLooseLayout(
          maxW: maxW,
          n: n,
          spacingMultiplier: spacingMultiplier,
          horizontalSpacingMultiplier: horizontalSpacingMultiplier,
          verticalSpacingMultiplier: verticalSpacingMultiplier,
          tile: tile,
        );

        if (heightBounded && !disableBoundedScroll) {
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: loose,
          );
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: loose,
        );
      },
    );
  }
}


/// Scale factors for PNG previews — tops/pants run large if over-scaled; shoes stay slightly bolder.
double _heroOutfitImageScale(_HeroWearType type, {required bool compact}) {
  if (compact) {
    switch (type) {
      case _HeroWearType.top:
        return 1.02;
      case _HeroWearType.bottom:
        return 0.94;
      case _HeroWearType.outerwear:
        return 0.98;
      case _HeroWearType.shoes:
        return 1.08;
    }
  }
  switch (type) {
    case _HeroWearType.top:
      return 1.0;
    case _HeroWearType.bottom:
      return 0.92;
    case _HeroWearType.outerwear:
      return 0.96;
    case _HeroWearType.shoes:
      return 1.06;
  }
}

enum _HeroImageRole { top, outerwear, pants, shorts, shoes, other }

_HeroImageRole _heroImageRole({
  required _HeroWearType wearType,
  required String? categoryKey,
  required String? subCategoryKey,
  required String? label,
}) {
  final blob = _normalizedScaleToken('$categoryKey $subCategoryKey $label');
  bool has(List<String> words) => words.any((w) => blob.contains(_normalizedScaleToken(w)));
  if (wearType == _HeroWearType.shoes || has(['sneaker', 'tenisky', 'topanky', 'topánky', 'obuv', 'shoes'])) {
    return _HeroImageRole.shoes;
  }
  if (has(['short', 'kratasy', 'kraťasy'])) return _HeroImageRole.shorts;
  if (has(['jeans', 'rifle', 'nohavice', 'pants'])) return _HeroImageRole.pants;
  if (wearType == _HeroWearType.outerwear ||
      has(['hoodie', 'mikina', 'jacket', 'bunda', 'coat', 'kabat', 'kabát', 'blazer', 'sako'])) {
    return _HeroImageRole.outerwear;
  }
  if (wearType == _HeroWearType.top || has(['t-shirt', 'tricko', 'tričko', 'tank', 'tielko', 'shirt', 'kosela', 'koše'])) {
    return _HeroImageRole.top;
  }
  return _HeroImageRole.other;
}

double _heroCategoryScaleBoost({
  required _HeroWearType wearType,
  required String? categoryKey,
  required String? subCategoryKey,
  required String? label,
  required bool compact,
}) {
  final role = _heroImageRole(
    wearType: wearType,
    categoryKey: categoryKey,
    subCategoryKey: subCategoryKey,
    label: label,
  );
  switch (role) {
    case _HeroImageRole.top:
      return 0.0;
    case _HeroImageRole.outerwear:
      return compact ? -0.02 : -0.02;
    case _HeroImageRole.pants:
      return compact ? -0.08 : -0.07;
    case _HeroImageRole.shorts:
      return 0.0;
    case _HeroImageRole.shoes:
      return compact ? 0.02 : 0.02;
    case _HeroImageRole.other:
      return 0.0;
  }
}

double _heroCategoryInsetAdjust({
  required _HeroWearType wearType,
  required String? categoryKey,
  required String? subCategoryKey,
  required String? label,
  required bool compact,
}) {
  final role = _heroImageRole(
    wearType: wearType,
    categoryKey: categoryKey,
    subCategoryKey: subCategoryKey,
    label: label,
  );
  switch (role) {
    case _HeroImageRole.top:
      return 0.0;
    case _HeroImageRole.outerwear:
      return compact ? 0.2 : 0.2;
    case _HeroImageRole.pants:
      return compact ? 0.9 : 0.8;
    case _HeroImageRole.shorts:
      return 0.0;
    case _HeroImageRole.shoes:
      return -0.2;
    case _HeroImageRole.other:
      return 0.0;
  }
}

String _normalizedScaleToken(String raw) {
  return raw
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('č', 'c')
      .replaceAll('ď', 'd')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ľ', 'l')
      .replaceAll('ĺ', 'l')
      .replaceAll('ň', 'n')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ŕ', 'r')
      .replaceAll('š', 's')
      .replaceAll('ť', 't')
      .replaceAll('ú', 'u')
      .replaceAll('ý', 'y')
      .replaceAll('ž', 'z');
}

class _HeroOutfitTileCard extends StatelessWidget {
  const _HeroOutfitTileCard({
    required this.item,
    this.compact = false,
    this.imageScaleMultiplier = 1.0,
    this.recreatedShoeScaleBoost = 1.0,
    this.expandCell = false,
    this.editMode = false,
    this.selected = true,
    this.onTap,
    this.onRemoveTap,
  });

  final _HeroOutfitItem item;
  final bool compact;
  final double imageScaleMultiplier;
  final double recreatedShoeScaleBoost;

  /// Fill a flex cell in the 2×2 shared-height grid (non-square cell).
  final bool expandCell;
  final bool editMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRemoveTap;

  @override
  Widget build(BuildContext context) {
    final outerR = compact ? 16.0 : 18.0;
    final innerR = compact ? 14.0 : 14.0;
    final pad = compact ? 5.0 : 5.0;

    final core = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerR),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HomeLuxuryPalette.surface.withOpacity(0.34),
            HomeLuxuryPalette.surfaceSoft.withOpacity(0.14),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          if (editMode)
            BoxShadow(
              color: HomeLuxuryPalette.accent.withOpacity(selected ? 0.24 : 0.12),
              blurRadius: selected ? 20 : 14,
              spreadRadius: 0,
            ),
        ],
        border: Border.all(
          color: editMode
              ? HomeLuxuryPalette.accent.withOpacity(selected ? 0.34 : 0.12)
              : Colors.transparent,
          width: editMode ? 1.1 : 0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(innerR),
        child: ColoredBox(
          color: HomeLuxuryPalette.surface.withOpacity(0.12),
          child: _HeroOutfitImageView(
            imageUrl: item.imageUrl,
            fallbackIcon: item.icon,
            wearType: item.type,
            categoryKey: item.categoryKey,
            subCategoryKey: item.subCategoryKey,
            itemLabel: item.label,
            compact: compact,
            imageScaleMultiplier: imageScaleMultiplier,
            recreatedShoeScaleBoost: recreatedShoeScaleBoost,
            showProcessingBadge: item.imageProcessing,
          ),
        ),
      ),
    );

    final body = editMode
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(outerR),
                    splashColor: HomeLuxuryPalette.accent.withOpacity(0.08),
                    highlightColor: HomeLuxuryPalette.accent.withOpacity(0.04),
                    child: core,
                  ),
                ),
              ),
              Positioned(
                top: 7,
                right: 7,
                child: _HeroRemoveChip(onTap: onRemoveTap),
              ),
            ],
          )
        : core;

    if (expandCell) {
      return SizedBox.expand(child: body);
    }

    return AspectRatio(
      aspectRatio: 1,
      child: body,
    );
  }
}

class _HeroRemoveChip extends StatelessWidget {
  const _HeroRemoveChip({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: HomeGlassSurface(
          borderRadius: 999,
          blurSigma: 10,
          padding: const EdgeInsets.all(6),
          child: Text(
            '✕',
            style: TextStyle(
              color: HomeLuxuryPalette.accent.withOpacity(0.95),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroOutfitImageView extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;
  final _HeroWearType wearType;
  final String? categoryKey;
  final String? subCategoryKey;
  final String? itemLabel;
  final bool compact;
  final double imageScaleMultiplier;
  final double recreatedShoeScaleBoost;
  final bool showProcessingBadge;

  const _HeroOutfitImageView({
    required this.imageUrl,
    required this.fallbackIcon,
    required this.wearType,
    this.categoryKey,
    this.subCategoryKey,
    this.itemLabel,
    this.compact = false,
    this.imageScaleMultiplier = 1.0,
    this.recreatedShoeScaleBoost = 1.0,
    this.showProcessingBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedImageUrl = imageUrl?.trim();
    final hasImage = normalizedImageUrl != null && normalizedImageUrl.isNotEmpty;
    final ph = compact ? 26.0 : 36.0;
    final baseInset = compact ? 5.0 : 6.0;
    final baseScale = _heroOutfitImageScale(wearType, compact: compact);
    final categoryBoost = _heroCategoryScaleBoost(
      wearType: wearType,
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
      label: itemLabel,
      compact: compact,
    );
    final insetAdjust = _heroCategoryInsetAdjust(
      wearType: wearType,
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
      label: itemLabel,
      compact: compact,
    );
    final role = _heroImageRole(
      wearType: wearType,
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
      label: itemLabel,
    );
    final inset = (baseInset + insetAdjust).clamp(2.2, 7.0).toDouble();
    double insetX = inset;
    double insetY = inset;
    if (role == _HeroImageRole.pants) {
      insetY = (inset + (compact ? 1.0 : 0.8)).clamp(2.2, 8.0);
      insetX = (inset - 0.4).clamp(1.8, 6.6);
    } else if (role == _HeroImageRole.shoes) {
      insetX = (inset - (compact ? 0.7 : 0.5)).clamp(1.6, 6.4);
      insetY = (inset + 0.2).clamp(2.2, 7.6);
    } else if (role == _HeroImageRole.outerwear) {
      insetY = (inset + 0.3).clamp(2.2, 7.6);
    }
    final localShoeBoost = wearType == _HeroWearType.shoes ? recreatedShoeScaleBoost : 1.0;
    final scale = ((baseScale + categoryBoost) * imageScaleMultiplier * localShoeBoost)
        .clamp(0.72, compact ? 2.08 : 1.84)
        .toDouble();

    Widget previewBody({required Widget child}) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: insetX, vertical: insetY),
        child: Center(
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        ),
      );
    }

    if (!hasImage) {
      return previewBody(
        child: _OutfitPreviewPlaceholder(icon: fallbackIcon, size: ph),
      );
    }

    final imageChild = Image.network(
      normalizedImageUrl,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      alignment: Alignment.center,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _OutfitPreviewPlaceholder(icon: fallbackIcon, size: ph);
      },
      errorBuilder: (context, error, stackTrace) =>
          _OutfitPreviewPlaceholder(icon: fallbackIcon, size: ph),
    );

    if (!showProcessingBadge) {
      return previewBody(child: imageChild);
    }

    return previewBody(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          imageChild,
          Positioned(
            top: compact ? 4 : 6,
            right: compact ? 4 : 6,
            child: Container(
              width: compact ? 20 : 22,
              height: compact ? 20 : 22,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.35)),
              ),
              padding: const EdgeInsets.all(3),
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutfitPreviewPlaceholder extends StatelessWidget {
  final IconData icon;
  final double size;

  const _OutfitPreviewPlaceholder({
    required this.icon,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        icon,
        color: HomeLuxuryPalette.textSecondary.withOpacity(0.92),
        size: size,
      ),
    );
  }
}

