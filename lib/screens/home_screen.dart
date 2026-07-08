import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../widgets/home/home_ai_explanation_card.dart';
import '../widgets/home/home_outfit_item_info_sheet.dart';
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
import 'wardrobe_reanalyze_review_screen.dart';
import '../utils/outfit_reason_builder.dart';
import '../utils/briefing_weather_condition.dart';
import '../utils/luxury_weather_emoji.dart';
import '../Services/hourly_weather_service.dart';
import '../Services/user_location_service.dart';
import '../Services/home_ai_outfit_service.dart';
import '../Services/home_stylist_final_review_service.dart';
import '../Services/home_outfit_stylist_explanation_service.dart';
import '../Services/home_daily_outfit_cache_service.dart';
import '../Services/outfit_generation_service.dart';
import '../Services/wardrobe_metadata_migration_service.dart';
import '../Services/wardrobe_reanalyze_apply_service.dart';
import '../Services/wardrobe_name_grammar_fix_service.dart';
import '../Services/stylist_day_brief.dart';
import '../utils/bottom_family_guidance.dart';
import '../utils/candidate_generation_audit.dart';
import '../utils/comfort_target.dart';
import '../utils/outer_variant_selection.dart';
import '../utils/outerwear_policy.dart';
import '../utils/outfit_explanation.dart';
import '../utils/family_guidance_exclusion_audit.dart';
import '../utils/footwear_family_guidance.dart';
import '../utils/layer_harmony_guard.dart';
import '../utils/home_debug_logging.dart';
import '../utils/home_wardrobe_normalizer.dart';
import '../utils/wardrobe_image_url_priority.dart';
import '../utils/wardrobe_image_processing.dart';

part 'home_screen_models.dart';
part 'home_screen_edit_widgets.dart';
part 'home_screen_action_widgets.dart';
part 'home_screen_hero_image_widgets.dart';
part 'home_screen_hero_grid_widgets.dart';

/// Hero outfit tiles — transparent PNG on dark canvas ([getHomeOutfitImageUrlOrNull]).
final Map<String, String?> _heroImagePickByItemVersion = <String, String?>{};
final Set<String> _heroImagePickLoggedMissKeys = <String>{};
/// Network images already displayed on Home hero — avoids placeholder flash on resume.
final Set<String> _homeHeroNetworkImageLoadedUrls = <String>{};
final Set<String> _homeHeroImagePrecacheScheduled = <String>{};
const int _homeDailyOutfitCacheSchemaVersion = 3;

String _heroImagePickVersionKey(Map<String, dynamic> raw) {
  final id = OutfitGenerationService.wardrobeItemId(raw);
  if (id.isEmpty) return '';
  final updatedAt = (raw['updatedAt'] ??
          raw['updatedAtMs'] ??
          raw['imageVersion'] ??
          '')
      .toString()
      .trim();
  final processing = [
    _processingStatusForCache(raw, 'product'),
    _processingStatusForCache(raw, 'cutout'),
  ].join('|');
  return '$id|$updatedAt|$processing';
}

String? _heroWardrobeDisplayImageUrl(
  Map<String, dynamic> raw, {
  bool allowPick = true,
}) {
  final versionKey = _heroImagePickVersionKey(raw);
  if (versionKey.isNotEmpty && _heroImagePickByItemVersion.containsKey(versionKey)) {
    return _heroImagePickByItemVersion[versionKey];
  }
  if (!allowPick) return null;
  final picked = getHomeOutfitImageUrlOrNull(raw);
  if (versionKey.isNotEmpty) {
    _heroImagePickByItemVersion[versionKey] = picked;
    if (picked == null && !_heroImagePickLoggedMissKeys.contains(versionKey)) {
      _heroImagePickLoggedMissKeys.add(versionKey);
      logVerboseHome('[HOME_IMAGE_PICK] cache_miss=true key=$versionKey');
    }
  }
  return picked;
}

String _processingStatusForCache(Map<String, dynamic> raw, String key) {
  final p = raw['processing'];
  if (p is Map) {
    final v = (p.cast<String, dynamic>()[key] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return (raw['processing.$key'] ?? '').toString().trim();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static Future<void>? _sharedHomeWeatherLoad;
  static bool _sharedHomeWeatherFetchInFlight = false;
  static OutfitWeatherDaySnapshot? _sharedWeatherSnapToday;
  static OutfitWeatherDaySnapshot? _sharedWeatherSnapTomorrow;
  static bool _sharedWeatherLoaded = false;
  static DateTime? _sharedLastWeatherFetchAt;
  static const Duration _weatherFreshDuration = Duration(minutes: 15);
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final HomeAiOutfitService _homeAiOutfitService = const HomeAiOutfitService();
  final HomeOutfitStylistExplanationService _stylistExplanationService =
      const HomeOutfitStylistExplanationService();
  final HomeDailyOutfitCacheService _dailyOutfitCacheService =
      HomeDailyOutfitCacheService();
  List<Map<String, dynamic>> _lastWardrobeForCache = const [];
  /// KB-normalized wardrobe maps — sole clothing metadata source for Home outfit generation.
  List<Map<String, dynamic>> _normalizedWardrobeForHomeBrain = const [];
  bool _persistedDailyHydrationDone = false;
  bool _persistedDailyHydrationInFlight = false;
  bool _nameGrammarFixCanApply = false;

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
  final Map<String, DateTime> _homeDayCacheUpdatedAtByDateKey = {};
  final Map<String, List<String>> _lastSavedNewOutfitIdsByDateKey = {};
  /// Kombinácie outfitov, ktoré používateľ už odmietol („Nový outfit“).
  final Map<int, Set<String>> _rejectedOutfitCombinationKeysByDay = {};
  final Map<String, _HomeAiCacheEntry> _homeAiCacheBySignature = {};
  final Set<String> _homeAiRequestInFlight = <String>{};
  final Set<String> _stylistFinalReviewInFlight = <String>{};
  final Set<String> _stylistFinalReviewDone = <String>{};
  final Set<String> _stylistReasonRefreshInFlight = <String>{};
  final Map<String, String> _homeAiLatestSignatureByDateKey = {};
  final Map<String, String> _homeAiLastWeatherSignatureByDateKey = {};
  final Map<String, String> _homeAiLastWardrobeSignatureByDateKey = {};
  String? _homeAiLastTriggeredDateKey;
  final Map<String, bool> _homeAiForceDifferentNextByDateKey = {};
  int _homeAiRefreshNonce = 0;
  bool _weatherFetchInFlight = false;
  DateTime? _lastWeatherFetchAt;
  String? _lastWardrobeStreamSig;
  final Map<String, String> _cachedHeroBuildKeyByDateKey = {};
  final Map<String, _HeroTodayState> _cachedHeroBuildStateByDateKey = {};
  final Map<String, _HeroOutfitRecommendation?> _localRecCacheByDateSig = {};
  final Map<String, List<_HeroOutfitItem>> _heroItemsCacheByIdSet = {};
  String? _lastAiPreservedSignatureLogged;
  String? _lastFallbackReasonLoggedKey;
  final Map<String, String> _lastHeroRenderLogKeyByDayLabel = {};
  String? _lastHomeRebuildLogKey;
  final Map<int, String> _cachedHeroPanelContentSigByDayIndex = {};
  final Map<int, ({
    List<_HeroOutfitItem> displayItems,
    List<_HeroOutfitItem> effectiveItems,
    String renderHeroSource,
  })> _cachedHeroPanelContentByDayIndex = {};
  String? _lastHomeAiOutfitLogKey;
  String? _lastPreservedDateKey;
  String? _lastPreservedOutfitSignature;
  String? _lastSyncedEditableOutfitKey;
  final Set<String> _loggedRestoreDateKeys = {};
  final Set<String> _restoredFootwearValidatedKeys = {};
  final Set<String> _hydratedHomeCacheDateKeys = {};
  final Set<String> _hydratedDailyOutfitWithWardrobeDateKeys = {};
  bool _homePreloadInFlight = false;
  bool _homePreloadPassCompleted = false;
  bool _isRestoringHomeCache = false;
  final Set<String> _generatingDateKeys = {};
  final Set<String> _loggedHomeDayCacheCheckLines = {};
  final Set<String> _loggedHomeDayCacheHits = {};
  final Set<String> _loggedHomeDayCacheMisses = {};
  final Set<String> _loggedHomeDayCacheMemoryHits = {};
  bool _loggedHomeBootSnapshot = false;
  final Map<String, _HeroTodayState> _stickyVisibleHeroByDateKey = {};
  final Map<String, String> _lastVisibleHomeImageUrlByItemId = {};
  final Map<String, Map<String, String>> _homeImageUrlByDateKeyAndItemId = {};
  final Map<String, List<_HeroOutfitItem>> _homeHydratedOutfitItemsByDateKey = {};
  final Map<String, _HeroTodayState> _daySwitchPinnedHeroByDateKey = {};
  final Map<String, String> _homeOutfitIdsSignatureByDateKey = {};
  String? _currentHeroBuildDateKey;
  final Set<String> _loggedHomeHeroImageMemoryHits = {};
  final Set<String> _loggedHomeHeroImageMemoryMisses = {};
  final Set<String> _loggedHomeHeroUsingCachedImages = {};
  bool _homePreloadRanChecks = false;
  bool _lastIsPremiumUser = false;
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
    WidgetsBinding.instance.addObserver(this);
    UserLocationService.instance.addListener(_onUserLocationCityChanged);
    unawaited(_bootstrapHomeWithGps());
  }

  void _onUserLocationCityChanged(String cityLabel) {
    if (!mounted) return;
    debugPrint('[HOME_WEATHER] reload reason=gps_city_changed city=$cityLabel');
    unawaited(_loadWeather(force: true));
  }

  Future<void> _bootstrapHomeWithGps() async {
    _syncWeatherFromSharedCache();
    await UserLocationService.instance.ensureResolved();
    if (!mounted) return;
    final gpsCity = UserLocationService.instance.cityShortLabel;
    final cachedCity = _weatherSnapToday?.cityName.split(',').first.trim();
    final cityMismatch = cachedCity != null &&
        cachedCity.toLowerCase() != gpsCity.toLowerCase();
    await _loadWeather(force: cityMismatch || !_weatherLoaded);
  }

  bool _syncWeatherFromSharedCache({bool triggerRebuild = false}) {
    if (!_sharedWeatherLoaded) return false;
    if (_sharedLastWeatherFetchAt != null &&
        DateTime.now().difference(_sharedLastWeatherFetchAt!) >
            _weatherFreshDuration) {
      return false;
    }
    if (_sharedWeatherSnapToday == null || _sharedWeatherSnapTomorrow == null) {
      return false;
    }
    final alreadySynced = _weatherLoaded &&
        _weatherSnapToday == _sharedWeatherSnapToday &&
        _weatherSnapTomorrow == _sharedWeatherSnapTomorrow;
    if (alreadySynced) return true;

    void apply() {
      _weatherSnapToday = _sharedWeatherSnapToday;
      _weatherSnapTomorrow = _sharedWeatherSnapTomorrow;
      _weatherLoaded = true;
      _weatherLoadError = null;
      _lastWeatherFetchAt = _sharedLastWeatherFetchAt;
      _weatherUpdatedAt = _sharedLastWeatherFetchAt ?? DateTime.now();
    }

    if (mounted && triggerRebuild) {
      setState(apply);
    } else {
      apply();
    }
    return true;
  }

  void _commitHomeWeatherSnapshots({
    required OutfitWeatherDaySnapshot todaySnapshot,
    required OutfitWeatherDaySnapshot tomorrowSnapshot,
  }) {
    final now = DateTime.now();
    _sharedWeatherSnapToday = todaySnapshot;
    _sharedWeatherSnapTomorrow = tomorrowSnapshot;
    _sharedWeatherLoaded = true;
    _sharedLastWeatherFetchAt = now;

    void applyLocal() {
      _weatherSnapToday = todaySnapshot;
      _weatherSnapTomorrow = tomorrowSnapshot;
      _weatherLoaded = true;
      _weatherLoadError = null;
      _weatherUpdatedAt = now;
      _lastWeatherFetchAt = now;
    }

    if (mounted) {
      setState(applyLocal);
    } else {
      applyLocal();
    }

    logVerboseHome('[HOME_WEATHER] assigned today=true tomorrow=true');
    _invalidateHomeHeroBuildCache();
    _homePreloadPassCompleted = false;
    _homePreloadRanChecks = false;
    _debugHomeBootState(force: true);
    if (mounted) {
      _tryScheduleHomeOutfitPreload();
    }
  }

  Future<void> _awaitSharedHomeWeatherLoad() async {
    final load = _sharedHomeWeatherLoad;
    if (load == null) return;
    await load;
    if (_syncWeatherFromSharedCache(triggerRebuild: true)) {
      _debugHomeBootState(force: true);
      if (mounted) {
        _tryScheduleHomeOutfitPreload();
      }
    }
  }

  @override
  void dispose() {
    UserLocationService.instance.removeListener(_onUserLocationCityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_weatherLoaded &&
          _lastWeatherFetchAt != null &&
          DateTime.now().difference(_lastWeatherFetchAt!) < _weatherFreshDuration) {
        logVerboseHome('[HOME_WEATHER] skip reason=fresh');
      }
      _tryScheduleHomeOutfitPreload();
    }
  }

  Future<void> _loadWeather({bool force = false}) async {
    if (_weatherFetchInFlight || _sharedHomeWeatherFetchInFlight) {
      logVerboseHome('[HOME_WEATHER] skip reason=in_flight');
      await _awaitSharedHomeWeatherLoad();
      return;
    }
    if (!force &&
        _weatherLoaded &&
        _weatherSnapToday != null &&
        _weatherSnapTomorrow != null &&
        _lastWeatherFetchAt != null &&
        DateTime.now().difference(_lastWeatherFetchAt!) < _weatherFreshDuration) {
      logVerboseHome('[HOME_WEATHER] skip reason=fresh');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tryScheduleHomeOutfitPreload();
      });
      return;
    }
    if (!force && _sharedWeatherLoaded && _sharedLastWeatherFetchAt != null) {
      if (DateTime.now().difference(_sharedLastWeatherFetchAt!) <
          _weatherFreshDuration) {
        if (_syncWeatherFromSharedCache(triggerRebuild: true)) {
          _debugHomeBootState(force: true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _tryScheduleHomeOutfitPreload();
          });
        }
        logVerboseHome('[HOME_WEATHER] skip reason=fresh');
        return;
      }
    }
    if (!force && _sharedHomeWeatherLoad != null) {
      await _awaitSharedHomeWeatherLoad();
      if (_weatherLoaded &&
          _weatherSnapToday != null &&
          _weatherSnapTomorrow != null) {
        logVerboseHome('[HOME_WEATHER] skip reason=fresh');
        return;
      }
      _sharedHomeWeatherLoad = null;
    }
    _weatherFetchInFlight = true;
    _sharedHomeWeatherFetchInFlight = true;
    _sharedHomeWeatherLoad = _loadWeatherOnce();
    try {
      await _sharedHomeWeatherLoad;
      _syncWeatherFromSharedCache();
      if (_weatherLoaded &&
          _weatherSnapToday != null &&
          _weatherSnapTomorrow != null &&
          mounted) {
        _debugHomeBootState(force: true);
        _tryScheduleHomeOutfitPreload();
      }
    } finally {
      _weatherFetchInFlight = false;
      _sharedHomeWeatherFetchInFlight = false;
    }
  }

  Future<void> _loadWeatherOnce() async {
    await UserLocationService.instance.ensureResolved();
    final city = UserLocationService.instance.cityLabel;
    final svc = HourlyWeatherService();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    try {
      final results = await Future.wait([
        svc.getWeatherForCityAndDate(city: city, date: today),
        svc.getWeatherForCityAndDate(city: city, date: tomorrow),
      ]);
      _commitHomeWeatherSnapshots(
        todaySnapshot: results[0],
        tomorrowSnapshot: results[1],
      );
      logVerboseHome(
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
      if (mounted) {
        unawaited(
          _ensurePersistedDailyOutfitsHydrated(wardrobe: _lastWardrobeForCache),
        );
      }
    } catch (e) {
      final failedAt = DateTime.now();
      _sharedWeatherLoaded = true;
      _sharedLastWeatherFetchAt = failedAt;
      void applyError() {
        _weatherLoaded = true;
        _weatherLoadError = e.toString();
        _weatherUpdatedAt = failedAt;
        _lastWeatherFetchAt = failedAt;
      }
      if (mounted) {
        setState(applyError);
      } else {
        applyError();
      }
      _invalidateHomeHeroBuildCache();
      _homePreloadPassCompleted = false;
      _homePreloadRanChecks = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tryScheduleHomeOutfitPreload();
      });
      debugPrint('[HOME_WEATHER_DEBUG][fallback_reason] load_exception: $e');
      _scheduleHomeWeatherDebugLogAfterFrame(today, tomorrow);
      _debugHomeBootState(force: true);
      if (mounted) {
        unawaited(
          _ensurePersistedDailyOutfitsHydrated(wardrobe: _lastWardrobeForCache),
        );
      }
    } finally {
      _sharedHomeWeatherLoad = null;
    }
  }

  void _invalidateHomeHeroBuildCache({String? dateKey}) {
    if (dateKey == null) {
      _cachedHeroBuildKeyByDateKey.clear();
      _cachedHeroBuildStateByDateKey.clear();
      _invalidateHeroPanelContentCache();
    } else {
      _cachedHeroBuildKeyByDateKey.remove(dateKey);
      _cachedHeroBuildStateByDateKey.remove(dateKey);
      final dayIdx = _dayIndexForDateKey(dateKey);
      if (dayIdx != null) {
        _invalidateHeroPanelContentCache(dayIndex: dayIdx);
      }
    }
  }

  int? _dayIndexForDateKey(String dateKey) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (dateKey == _dateKey(today)) return 0;
    if (dateKey == _dateKey(today.add(const Duration(days: 1)))) return 1;
    return null;
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
    final city = UserLocationService.instance.cityShortLabel;
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
      logVerboseHome(
        '[HOME_WEATHER_DEBUG][fallback_reason] snapshot_cache_miss date=$norm '
        '(expected only non-home calendar days)',
      );
    } else if (snap != null && !snap.fromOpenMeteo) {
      logVerboseHome(
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

    logVerboseHome(
      '[HOME_WEATHER_DEBUG][$contextTag] date=$norm isToday=$isToday isTomorrow=$isTomorrow '
      'city=$city source=$source updatedAt=$_weatherUpdatedAt '
      'mainChipTempC=$chipT mainChipHour=$chipHour mainChipBasis=$chipBasis '
      'morningTempC=$morn afternoonTempC=$aft eveningTempC=$eve '
      'rainSegMorning=$rm rainSegAfternoon=$ra rainSegEvening=$re '
      'outfitTempC=${w.tempC} rain=$rain wind=$wind summary=$summary',
    );
  }

  void _setDayIndex(int index) {
    if (_dayIndex == index) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = index == 1 ? today.add(const Duration(days: 1)) : today;
    final dateKey = _dateKey(date);

    setState(() {
      _dayIndex = index;
      _isOutfitEditMode = false;
      _focusedEditType = null;
      _likePulseTick = 0;
      _showLikeInlineFeedback = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _logHomeWeatherDebug(contextTag: 'toggle_day', selectedDate: date);
      if (_lastWardrobeForCache.isNotEmpty && _weatherLoaded) {
        _refreshMissingHomeImageUrlsInBackground(
          dateKey: dateKey,
          items: _homeHydratedOutfitItemsByDateKey[dateKey] ??
              _daySwitchPinnedHeroByDateKey[dateKey]?.outfitItems ??
              const <_HeroOutfitItem>[],
          wardrobe: _lastWardrobeForCache,
        );
        unawaited(
          _ensureDailyOutfit(
            date: date,
            wardrobe: _lastWardrobeForCache,
            isPremiumUser: _lastIsPremiumUser,
          ),
        );
        _maybeRefreshPendingReasonForDate(date);
      }
    });
  }

  bool _skipHomeImagePickForDateKey(String dateKey) {
    final hydrated = _homeHydratedOutfitItemsByDateKey[dateKey];
    if (hydrated != null &&
        hydrated.length >= 3 &&
        _heroOutfitTilesHaveVisibleImages(hydrated)) {
      return true;
    }
    final pinned = _daySwitchPinnedHeroByDateKey[dateKey];
    return pinned != null && _heroOutfitTilesHaveVisibleImages(pinned.outfitItems);
  }

  bool _allowHomeImagePickForBuild(String dateKey) {
    return !_skipHomeImagePickForDateKey(dateKey);
  }

  List<_HeroOutfitItem> _effectiveOutfitItems(
    List<_HeroOutfitItem> source, {
    required int dayIndex,
  }) {
    return _editedOutfitByDay[dayIndex] ?? source;
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

  void _syncEditableOutfitFromSourceIfNeeded(
    List<_HeroOutfitItem> source, {
    required int dayIndex,
  }) {
    final sourceSig = source.isEmpty
        ? 'empty'
        : _heroOutfitSignatureFromItems(source);
    final syncKey = '$dayIndex|$sourceSig';
    if (_lastSyncedEditableOutfitKey == syncKey) return;
    _lastSyncedEditableOutfitKey = syncKey;
    _syncEditableOutfitFromSource(source, dayIndex: dayIndex);
  }

  bool _hasSameHomeCachePreserveSignature({
    required String dateKey,
    required List<_HeroOutfitItem> items,
  }) {
    final sig = _heroOutfitSignatureFromItems(items);
    return _lastPreservedDateKey == dateKey &&
        _lastPreservedOutfitSignature == sig;
  }

  void _markHomeCachePreserveSignature({
    required String dateKey,
    required List<_HeroOutfitItem> items,
  }) {
    _lastPreservedDateKey = dateKey;
    _lastPreservedOutfitSignature = _heroOutfitSignatureFromItems(items);
  }

  void _logHomeCacheRestoreIfNeeded({
    required String dateKey,
    required List<_HeroOutfitItem> items,
  }) {
    if (_hasSameHomeCachePreserveSignature(dateKey: dateKey, items: items)) {
      return;
    }
    if (_loggedRestoreDateKeys.contains(dateKey) &&
        _lastPreservedDateKey == dateKey) {
      return;
    }
    _markHomeCachePreserveSignature(dateKey: dateKey, items: items);
    _loggedRestoreDateKeys.add(dateKey);
    debugPrint('[HOME_DAY_CACHE] restored user_modified=true date=$dateKey');
  }

  void _logHomeCacheUserPreserveIfNeeded({
    required String dateKey,
    required List<_HeroOutfitItem> items,
    required String reason,
  }) {
    if (_hasSameHomeCachePreserveSignature(dateKey: dateKey, items: items)) {
      return;
    }
    _markHomeCachePreserveSignature(dateKey: dateKey, items: items);
    debugPrint('[HOME_DAY_CACHE] preserved_edited_outfit=true');
    debugPrint('[HOME_DAY_CACHE] preserved_swap_state=true');
  }

  List<String> _heroOutfitItemIds(List<_HeroOutfitItem> items) {
    return items
        .map((e) => e.wardrobeItemId)
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _heroOutfitItemNames(List<_HeroOutfitItem> items) {
    return items.map((e) => e.label.trim()).where((e) => e.isNotEmpty).toList(
          growable: false,
        );
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _reasonItemIdsMatchOutfit({
    required List<String>? reasonItemIds,
    required List<String> outfitItemIds,
  }) {
    final reasonIds = reasonItemIds
        ?.map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final outfitIds = outfitItemIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (reasonIds == null || reasonIds.isEmpty || outfitIds.isEmpty) {
      return false;
    }
    if (reasonIds.length != outfitIds.length) return false;
    final outfitSet = outfitIds.toSet();
    return reasonIds.every(outfitSet.contains);
  }

  void _touchHomeDayCacheUpdatedAt(String dateKey, DateTime at) {
    _homeDayCacheUpdatedAtByDateKey[dateKey] = at;
  }

  DateTime _homeDayCacheUpdatedAtFor(String dateKey) {
    return _homeDayCacheUpdatedAtByDateKey[dateKey] ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _homeDayCacheSourcePriority(String persistSource) {
    switch (persistSource) {
      case 'manual_new_outfit':
        return 4;
      case 'manual_replaced':
        return 3;
      case 'restore_footwear_fix':
        return 2;
      default:
        return 1;
    }
  }

  void _logHomeDayCacheSaveDebug({
    required String reason,
    required String dateKey,
    required List<String> ids,
    required List<String> names,
    required DateTime updatedAt,
    required String targetCache,
  }) {
    logVerboseHome(
      '[HOME_DAY_CACHE_SAVE_DEBUG] reason=$reason dateKey=$dateKey '
      'ids=$ids names=$names updatedAt=${updatedAt.toIso8601String()} '
      'targetCache=$targetCache',
    );
  }

  void _logHomeDayCacheRestoreDebug({
    required String dateKey,
    required String chosenSource,
    required List<String> ids,
    required List<String> names,
    required DateTime updatedAt,
    required List<String> availableSources,
  }) {
    logVerboseHome(
      '[HOME_DAY_CACHE_RESTORE_DEBUG] dateKey=$dateKey chosenSource=$chosenSource '
      'ids=$ids names=$names updatedAt=${updatedAt.toIso8601String()} '
      'availableSources=$availableSources',
    );
  }

  void _logHomeDayCacheRestoreMismatch({
    required List<String> savedIds,
    required List<String> restoredIds,
  }) {
    debugPrint(
      '[HOME_DAY_CACHE_RESTORE_MISMATCH] savedIds=$savedIds restoredIds=$restoredIds',
    );
  }

  List<_HeroOutfitItem> _heroItemsFromPersistedSlots({
    required List<Map<String, dynamic>> slotMaps,
    required List<String> ids,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    if (slotMaps.isEmpty || ids.isEmpty) {
      return _heroItemsFromPersistedMaps(slotMaps, wardrobe);
    }
    if (slotMaps.length != ids.length) {
      return _heroItemsFromPersistedMaps(slotMaps, wardrobe);
    }
    final patched = <Map<String, dynamic>>[];
    for (var i = 0; i < slotMaps.length; i++) {
      patched.add(<String, dynamic>{
        ...slotMaps[i],
        'wardrobeItemId': ids[i],
      });
    }
    return _heroItemsFromPersistedMaps(patched, wardrobe);
  }

  List<_HeroOutfitItem> _heroItemsFromPersistedIds({
    required List<String> ids,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    if (ids.isEmpty || wardrobe.isEmpty) return const <_HeroOutfitItem>[];
    final byId = <String, Map<String, dynamic>>{};
    for (final raw in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(raw);
      if (id.isNotEmpty) byId[id] = raw;
    }
    final orderedTypes = <_HeroWearType>[
      _HeroWearType.top,
      _HeroWearType.bottom,
      _HeroWearType.shoes,
      _HeroWearType.outerwear,
    ];
    final out = <_HeroOutfitItem>[];
    for (var i = 0; i < ids.length && i < orderedTypes.length; i++) {
      final id = ids[i].trim();
      final raw = byId[id];
      if (raw == null) continue;
      out.add(_heroItemFromWardrobe(raw: raw, type: orderedTypes[i]));
    }
    return _orderedHeroOutfitItems(out);
  }

  DateTime _resolvedDocUpdatedAt(HomeDailyOutfitCacheDocument doc) {
    if (doc.clientUpdatedAtMs != null && doc.clientUpdatedAtMs! > 0) {
      return DateTime.fromMillisecondsSinceEpoch(doc.clientUpdatedAtMs!);
    }
    return doc.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  _HomeDayCacheSnapshot? _snapshotFromFirestoreDoc(
    HomeDailyOutfitCacheDocument doc, {
    required String chosenSource,
    required List<String> itemIds,
    required DateTime updatedAt,
  }) {
    if (itemIds.isEmpty || doc.items.isEmpty) return null;
    return _HomeDayCacheSnapshot(
      chosenSource: chosenSource,
      itemIds: List<String>.from(itemIds),
      slotMaps: doc.items,
      reasonText: doc.reasonText,
      reasonItemIds: doc.reasonItemIds,
      userModified: doc.userModified,
      persistSource: doc.source,
      updatedAt: updatedAt,
      weatherSignature: doc.weatherSignature,
      wardrobeSignature: doc.wardrobeSignature,
      likedOutfitKey: doc.likedOutfitKey,
    );
  }

  _HomeDayCacheSnapshot? _snapshotFromHeroState({
    required String chosenSource,
    required _HeroTodayState state,
    required String weatherSignature,
    required String wardrobeSignature,
    required bool userModified,
    required String persistSource,
    required DateTime updatedAt,
    String? likedOutfitKey,
  }) {
    if (!_heroStateHasValidOutfit(state)) return null;
    final ids = _heroOutfitItemIds(state.outfitItems);
    if (ids.isEmpty) return null;
    return _HomeDayCacheSnapshot(
      chosenSource: chosenSource,
      itemIds: ids,
      heroItems: List<_HeroOutfitItem>.from(state.outfitItems),
      reasonText: state.vm.description,
      reasonItemIds: ids,
      userModified: userModified,
      persistSource: persistSource,
      updatedAt: updatedAt,
      weatherSignature: weatherSignature,
      wardrobeSignature: wardrobeSignature,
      likedOutfitKey: likedOutfitKey,
    );
  }

  List<_HomeDayCacheSnapshot> _collectHomeDayCacheSnapshots({
    required String dateKey,
    required int dayIdx,
    HomeDailyOutfitCacheDocument? firestoreDoc,
  }) {
    final snapshots = <_HomeDayCacheSnapshot>[];

    if (firestoreDoc != null) {
      final mainUpdatedAt = _resolvedDocUpdatedAt(firestoreDoc);
      final main = _snapshotFromFirestoreDoc(
        firestoreDoc,
        chosenSource: 'daily_firestore',
        itemIds: firestoreDoc.itemIds,
        updatedAt: mainUpdatedAt,
      );
      if (main != null) snapshots.add(main);

      final lastNewOutfitIds = firestoreDoc.lastNewOutfitItemIds;
      final lastNewOutfitAtMs = firestoreDoc.lastNewOutfitSavedAtMs;
      if (lastNewOutfitIds != null &&
          lastNewOutfitIds.isNotEmpty &&
          lastNewOutfitAtMs != null &&
          lastNewOutfitAtMs > 0 &&
          !_sameStringList(lastNewOutfitIds, firestoreDoc.itemIds)) {
        final lastNewOutfit = _HomeDayCacheSnapshot(
          chosenSource: 'daily_firestore_last_new_outfit',
          itemIds: List<String>.from(lastNewOutfitIds),
          slotMaps: firestoreDoc.items,
          reasonText: firestoreDoc.reasonText,
          reasonItemIds: firestoreDoc.reasonItemIds,
          userModified: true,
          persistSource: 'manual_new_outfit',
          updatedAt: DateTime.fromMillisecondsSinceEpoch(lastNewOutfitAtMs),
          weatherSignature: firestoreDoc.weatherSignature,
          wardrobeSignature: firestoreDoc.wardrobeSignature,
          likedOutfitKey: firestoreDoc.likedOutfitKey,
        );
        snapshots.add(lastNewOutfit);
      }
    }

    final memoryUpdatedAt = _homeDayCacheUpdatedAtFor(dateKey);
    final cache = _homeDayHeroCacheByDateKey[dateKey];
    if (cache != null) {
      final memory = _snapshotFromHeroState(
        chosenSource: 'memory_hero',
        state: cache.state,
        weatherSignature: cache.weatherSignature,
        wardrobeSignature: cache.wardrobeSignature,
        userModified: cache.userModified,
        persistSource: cache.persistSource ?? 'memory',
        updatedAt: cache.updatedAt ?? memoryUpdatedAt,
        likedOutfitKey: _likedOutfitKeyByDay[dayIdx],
      );
      if (memory != null) snapshots.add(memory);
    }

    final edited = _editedOutfitByDay[dayIdx];
    final editedManual = _editedManuallyByDay[dayIdx] ?? false;
    if (editedManual && edited != null && edited.length >= 3) {
      snapshots.add(
        _HomeDayCacheSnapshot(
          chosenSource: 'edited_outfit',
          itemIds: _heroOutfitItemIds(edited),
          heroItems: List<_HeroOutfitItem>.from(edited),
          reasonText: cache?.state.vm.description ?? '',
          reasonItemIds: _heroOutfitItemIds(edited),
          userModified: true,
          persistSource: cache?.persistSource ?? 'manual_replaced',
          updatedAt: memoryUpdatedAt,
          weatherSignature: cache?.weatherSignature ?? '',
          wardrobeSignature: cache?.wardrobeSignature ?? '',
          likedOutfitKey: _likedOutfitKeyByDay[dayIdx],
        ),
      );
    }

    final sticky = _stickyVisibleHeroByDateKey[dateKey];
    if (sticky != null) {
      final stickySnapshot = _snapshotFromHeroState(
        chosenSource: 'sticky_visible_hero',
        state: sticky,
        weatherSignature: cache?.weatherSignature ?? '',
        wardrobeSignature: cache?.wardrobeSignature ?? '',
        userModified: cache?.userModified ?? editedManual,
        persistSource: cache?.persistSource ?? 'sticky',
        updatedAt: memoryUpdatedAt,
        likedOutfitKey: _likedOutfitKeyByDay[dayIdx],
      );
      if (stickySnapshot != null) snapshots.add(stickySnapshot);
    }

    final pinned = _daySwitchPinnedHeroByDateKey[dateKey];
    if (pinned != null) {
      final pinnedSnapshot = _snapshotFromHeroState(
        chosenSource: 'day_switch_pinned_hero',
        state: pinned,
        weatherSignature: cache?.weatherSignature ?? '',
        wardrobeSignature: cache?.wardrobeSignature ?? '',
        userModified: cache?.userModified ?? editedManual,
        persistSource: cache?.persistSource ?? 'pinned',
        updatedAt: memoryUpdatedAt,
        likedOutfitKey: _likedOutfitKeyByDay[dayIdx],
      );
      if (pinnedSnapshot != null) snapshots.add(pinnedSnapshot);
    }

    final hydrated = _homeHydratedOutfitItemsByDateKey[dateKey];
    if (hydrated != null && hydrated.length >= 3) {
      snapshots.add(
        _HomeDayCacheSnapshot(
          chosenSource: 'hydrated_outfit',
          itemIds: _heroOutfitItemIds(hydrated),
          heroItems: List<_HeroOutfitItem>.from(hydrated),
          reasonText: cache?.state.vm.description ?? sticky?.vm.description ?? '',
          reasonItemIds: _heroOutfitItemIds(hydrated),
          userModified: cache?.userModified ?? editedManual,
          persistSource: cache?.persistSource ?? 'hydrated',
          updatedAt: memoryUpdatedAt,
          weatherSignature: cache?.weatherSignature ?? '',
          wardrobeSignature: cache?.wardrobeSignature ?? '',
          likedOutfitKey: _likedOutfitKeyByDay[dayIdx],
        ),
      );
    }

    return snapshots;
  }

  List<_HomeDayCacheSnapshot> _validHomeDayCacheSnapshots({
    required List<_HomeDayCacheSnapshot> snapshots,
    required String weatherSignature,
    required String wardrobeSignature,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    final valid = <_HomeDayCacheSnapshot>[];
    for (final snapshot in snapshots) {
      final isUserPinnedOutfit =
          snapshot.userModified || snapshot.persistSource == 'manual_new_outfit';
      if (snapshot.weatherSignature.isNotEmpty &&
          snapshot.weatherSignature != weatherSignature &&
          !isUserPinnedOutfit) {
        continue;
      }
      if (wardrobe.isNotEmpty &&
          !isUserPinnedOutfit &&
          snapshot.wardrobeSignature.isNotEmpty &&
          snapshot.wardrobeSignature != wardrobeSignature) {
        continue;
      }
      if (isUserPinnedOutfit &&
          wardrobe.isNotEmpty &&
          !_validatePersistedItemIds(snapshot.itemIds, wardrobe)) {
        continue;
      }
      if (snapshot.itemIds.isEmpty) continue;
      valid.add(snapshot);
    }
    return valid;
  }

  _HomeDayCacheSnapshot? _chooseNewestHomeDayCacheSnapshot(
    List<_HomeDayCacheSnapshot> snapshots,
  ) {
    if (snapshots.isEmpty) return null;
    final sorted = List<_HomeDayCacheSnapshot>.from(snapshots)
      ..sort((a, b) {
        final cmp = b.updatedAt.compareTo(a.updatedAt);
        if (cmp != 0) return cmp;
        return _homeDayCacheSourcePriority(b.persistSource)
            .compareTo(_homeDayCacheSourcePriority(a.persistSource));
      });
    return sorted.first;
  }

  List<_HeroOutfitItem> _heroItemsFromCacheSnapshot(
    _HomeDayCacheSnapshot snapshot,
    List<Map<String, dynamic>> wardrobe,
  ) {
    if (snapshot.heroItems != null && snapshot.heroItems!.length >= 3) {
      return _orderedHeroOutfitItems(snapshot.heroItems!);
    }
    if (snapshot.slotMaps != null && snapshot.slotMaps!.isNotEmpty) {
      return _heroItemsFromPersistedSlots(
        slotMaps: snapshot.slotMaps!,
        ids: snapshot.itemIds,
        wardrobe: wardrobe,
      );
    }
    return const <_HeroOutfitItem>[];
  }

  void _syncEditableOutfitFromSource(
    List<_HeroOutfitItem> source, {
    required int dayIndex,
  }) {
    if (source.isEmpty) {
      final existing = _editedOutfitByDay[dayIndex];
      final wasManual = _editedManuallyByDay[dayIndex] ?? false;
      // Keep accepted manual edits stable through transient loading/source-empty frames.
      if (wasManual && existing != null && existing.isNotEmpty) {
        return;
      }
      _editedOutfitByDay.remove(dayIndex);
      _lastSourceSignatureByDay.remove(dayIndex);
      _editedManuallyByDay.remove(dayIndex);
      return;
    }
    final sourceSig = _heroRenderSignature(source);
    final existing = _editedOutfitByDay[dayIndex];
    final wasManual = _editedManuallyByDay[dayIndex] ?? false;
    final lastSourceSig = _lastSourceSignatureByDay[dayIndex];
    final shouldReplace = existing == null || (!wasManual && lastSourceSig != sourceSig);
    if (shouldReplace) {
      _editedOutfitByDay[dayIndex] = List<_HeroOutfitItem>.from(source);
      _lastSourceSignatureByDay[dayIndex] = sourceSig;
      _editedManuallyByDay[dayIndex] = false;
    }
  }

  void _invalidateHeroPanelContentCache({int? dayIndex}) {
    if (dayIndex == null) {
      _cachedHeroPanelContentSigByDayIndex.clear();
      _cachedHeroPanelContentByDayIndex.clear();
    } else {
      _cachedHeroPanelContentSigByDayIndex.remove(dayIndex);
      _cachedHeroPanelContentByDayIndex.remove(dayIndex);
    }
  }

  String _heroPanelContentSignature({
    required int panelDayIndex,
    required _HeroTodayState hero,
    required DateTime activeDate,
  }) {
    final weatherSig = _homeWeatherSignature(_weatherForDate(activeDate));
    final editSig = (_editedManuallyByDay[panelDayIndex] ?? false)
        ? _heroRenderSignature(_editedOutfitByDay[panelDayIndex] ?? const [])
        : '';
    return '${hero.source}|${_heroRenderSignature(hero.outfitItems)}|$weatherSig|$editSig';
  }

  void _logHomeRebuild({
    required String reason,
    required bool todayChanged,
    required bool tomorrowChanged,
  }) {
    final key = '$reason|$todayChanged|$tomorrowChanged';
    if (_lastHomeRebuildLogKey == key) return;
    _lastHomeRebuildLogKey = key;
    logVerboseHome('[HOME_REBUILD] reason=$reason');
    logVerboseHome('[HOME_REBUILD] today_changed=$todayChanged');
    logVerboseHome('[HOME_REBUILD] tomorrow_changed=$tomorrowChanged');
  }

  void _syncHomeOutfitStateToAllCaches({
    required int dayIndex,
    required String dateKey,
    required String dayLabel,
    required List<_HeroOutfitItem> normalized,
    required _HeroTodayState heroState,
  }) {
    final hydrated = _heroTodayStateWithStableImages(dateKey, heroState);
    final items = _heroOutfitTilesHaveVisibleImages(hydrated.outfitItems)
        ? List<_HeroOutfitItem>.from(hydrated.outfitItems)
        : _heroItemsFromCachedUrlsOnly(
            dateKey: dateKey,
            dayLabel: dayLabel,
            items: hydrated.outfitItems,
            logUsingCached: false,
          );
    final stored = _HeroTodayState(
      vm: hydrated.vm,
      outfitItems: items,
      source: hydrated.source,
      loadingReason: hydrated.loadingReason,
    );
    _homeHydratedOutfitItemsByDateKey[dateKey] = items;
    _stickyVisibleHeroByDateKey[dateKey] = stored;
    _daySwitchPinnedHeroByDateKey[dateKey] = stored;
    _touchHomeDayCacheUpdatedAt(dateKey, DateTime.now());
    for (final item in items) {
      final id = (item.wardrobeItemId ?? '').trim();
      final url = (item.imageUrl ?? '').trim();
      if (id.isNotEmpty && url.isNotEmpty) {
        _rememberHomeImageUrl(dateKey, id, url, dayLabel: dayLabel);
      }
    }
    _cachedHeroBuildKeyByDateKey.remove(dateKey);
    _cachedHeroBuildStateByDateKey.remove(dateKey);
    _invalidateHeroPanelContentCache(dayIndex: dayIndex);
    debugPrint('[HOME_REPLACE] updated_memory_cache day=$dayLabel');
    debugPrint('[HOME_REPLACE] updated_home_state day=$dayLabel');
  }

  OutfitWeatherSnapshot _outfitWeatherSnapshotForActiveDay() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = _dayIndex == 1 ? today.add(const Duration(days: 1)) : today;
    return _outfitWeatherSnapshotForDate(date);
  }

  FootwearFamilyInventory _footwearInventoryForSwap() {
    final wardrobe = _normalizedWardrobeForHomeBrain.isNotEmpty
        ? _normalizedWardrobeForHomeBrain
        : _wardrobeForOutfitGeneration(
            _lastWardrobeForCache,
            logNormalization: false,
          );
    return footwearFamilyInventoryFromWardrobe(wardrobe);
  }

  Map<String, dynamic> _footwearMapFromHeroItem(_HeroOutfitItem item) {
    final id = (item.wardrobeItemId ?? '').trim();
    if (id.isNotEmpty) {
      for (final raw in _normalizedWardrobeForHomeBrain) {
        if (OutfitGenerationService.wardrobeItemId(raw) == id) return raw;
      }
      for (final raw in _lastWardrobeForCache) {
        if (OutfitGenerationService.wardrobeItemId(raw) == id) return raw;
      }
    }
    return <String, dynamic>{
      if (id.isNotEmpty) 'id': id,
      'name': item.label,
      'categoryKey': item.categoryKey,
      'subCategoryKey': item.subCategoryKey,
    };
  }

  bool _shouldBlockDiscouragedFootwearSwap(_HeroOutfitItem newItem) {
    final snap = _outfitWeatherSnapshotForActiveDay();
    final guidance = computeFootwearFamilyGuidance(weather: snap);
    final inventory = _footwearInventoryForSwap();
    if (!inventory.hasPreferred(guidance) && !inventory.hasAllowed(guidance)) {
      return false;
    }
    final family = classifyFootwearFamily(_footwearMapFromHeroItem(newItem));
    return guidance.isDiscouraged(family);
  }

  List<Map<String, dynamic>> _applyFootwearGuidanceToSwapCandidates({
    required List<Map<String, dynamic>> candidates,
    required List<Map<String, dynamic>> wardrobeForInventory,
  }) {
    final snap = _outfitWeatherSnapshotForActiveDay();
    final guidance = computeFootwearFamilyGuidance(weather: snap);
    logHomeSwapFootwearGuidance(weather: snap, guidance: guidance);
    final inventory = footwearFamilyInventoryFromWardrobe(wardrobeForInventory);
    return filterSwapFootwearCandidates(
      candidates: candidates,
      guidance: guidance,
      inventory: inventory,
    );
  }

  Map<String, dynamic> _bottomMapFromHeroItem(
    _HeroOutfitItem item,
    List<Map<String, dynamic>> wardrobe,
  ) {
    return _footwearRawFromWardrobe(item, wardrobe);
  }

  bool _shouldBlockDiscouragedBottomSwap(_HeroOutfitItem newItem) {
    final snap = _outfitWeatherSnapshotForActiveDay();
    final guidance = computeBottomFamilyGuidance(weather: snap);
    final inventory = bottomFamilyInventoryFromWardrobe(
      _normalizedWardrobeForHomeBrain.isNotEmpty
          ? _normalizedWardrobeForHomeBrain
          : _wardrobeForOutfitGeneration(
              _lastWardrobeForCache,
              logNormalization: false,
            ),
    );
    if (!inventory.hasPreferred(guidance) && !inventory.hasAllowed(guidance)) {
      return false;
    }
    final raw = _bottomMapFromHeroItem(
      newItem,
      _normalizedWardrobeForHomeBrain.isNotEmpty
          ? _normalizedWardrobeForHomeBrain
          : _lastWardrobeForCache,
    );
    return isBottomDiscouragedForGuidance(raw, guidance);
  }

  List<Map<String, dynamic>> _applyBottomGuidanceToSwapCandidates({
    required List<Map<String, dynamic>> candidates,
    required List<Map<String, dynamic>> wardrobeForInventory,
  }) {
    final snap = _outfitWeatherSnapshotForActiveDay();
    final guidance = computeBottomFamilyGuidance(weather: snap);
    logBottomFamilyGuidance(weather: snap, guidance: guidance);
    final inventory = bottomFamilyInventoryFromWardrobe(wardrobeForInventory);
    logBottomFamilyFilter(
      guidance: guidance,
      inventory: inventory,
      wardrobe: wardrobeForInventory,
    );
    return filterSwapBottomCandidates(
      candidates: candidates,
      guidance: guidance,
      inventory: inventory,
    );
  }

  OutfitWeatherSnapshot _outfitWeatherSnapshotForDate(DateTime date) {
    final w = _weatherForDate(date);
    return OutfitWeatherSnapshot(
      tempC: w.tempC,
      isRainy: w.isRainy,
      isWindy: w.isWindy,
      seasonKey: w.seasonKey,
    );
  }

  OutfitExplanationResult _buildOutfitExplanations({
    required List<_HeroOutfitItem> items,
    required _LocalWeather weather,
    required List<Map<String, dynamic>> wardrobe,
    String dayOpener = 'Dnes',
  }) {
    if (items.isEmpty) {
      return const OutfitExplanationResult(items: []);
    }
    final wardrobeForGen =
        _wardrobeForOutfitGeneration(wardrobe, logNormalization: false);
    final preview = _outfitPreviewForFootwearScoring(
      items: items,
      wardrobe: wardrobeForGen,
    );
    return OutfitExplanationBuilder.build(
      preview: preview,
      comfortWeather: _comfortWeatherInputFor(weather),
      weatherSnap: OutfitWeatherSnapshot(
        tempC: weather.tempC,
        isRainy: weather.isRainy,
        isWindy: weather.isWindy,
        seasonKey: weather.seasonKey,
      ),
      dayOpener: dayOpener,
    );
  }

  Map<_HeroWearType, String> _optionalHintsForHero({
    required List<_HeroOutfitItem> items,
    required _LocalWeather weather,
    required List<Map<String, dynamic>> wardrobe,
    String dayOpener = 'Dnes',
  }) {
    if (items.isEmpty) return const {};
    final explanations = _buildOutfitExplanations(
      items: items,
      weather: weather,
      wardrobe: wardrobe,
      dayOpener: dayOpener,
    );
    final hints = <_HeroWearType, String>{};
    for (final hint in explanations.optionalTileHints) {
      if (hint.wearTypeKey == 'outerwear') {
        hints[_HeroWearType.outerwear] = hint.hint;
      }
    }
    return hints;
  }

  ComfortWeatherInput _comfortWeatherInputFor(_LocalWeather weather) {
    final snap = _weatherSnapForNormalizedDate(weather.calendarDate);
    final d = weather.calendarDate;
    final dayLabel =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return ComfortWeatherInput(
      mainTempC: weather.tempC,
      morningTempC: weather.briefingMorningC,
      afternoonTempC: weather.briefingAfternoonC,
      eveningTempC: weather.briefingEveningC,
      minTempC: snap?.minTempC,
      maxTempC: snap?.maxTempC,
      isRainy: weather.isRainy,
      morningRainSegment: weather.morningRainSegment,
      afternoonRainSegment: weather.afternoonRainSegment,
      eveningRainSegment: weather.eveningRainSegment,
      rainTimeText: weather.rainTimeText,
      isWindy: weather.isWindy,
      dayLabel: dayLabel,
      fromOpenMeteo: snap?.fromOpenMeteo ?? false,
    );
  }

  Map<String, dynamic> _footwearRawFromWardrobe(
    _HeroOutfitItem item,
    List<Map<String, dynamic>> wardrobe,
  ) {
    final id = (item.wardrobeItemId ?? '').trim();
    if (id.isNotEmpty) {
      for (final raw in wardrobe) {
        if (OutfitGenerationService.wardrobeItemId(raw) == id) return raw;
      }
    }
    return <String, dynamic>{
      if (id.isNotEmpty) 'id': id,
      'name': item.label,
      'categoryKey': item.categoryKey,
      'subCategoryKey': item.subCategoryKey,
    };
  }

  OutfitPreview? _outfitPreviewForFootwearScoring({
    required List<_HeroOutfitItem> items,
    required List<Map<String, dynamic>> wardrobe,
    Map<String, dynamic>? overrideShoeRaw,
  }) {
    final byId = <String, Map<String, dynamic>>{};
    for (final raw in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(raw);
      if (id.isNotEmpty) byId[id] = raw;
    }

    Map<String, dynamic>? rawForType(_HeroWearType type) {
      for (final it in items) {
        if (it.type != type) continue;
        final id = (it.wardrobeItemId ?? '').trim();
        if (id.isEmpty) return null;
        return byId[id];
      }
      return null;
    }

    final topRaw = rawForType(_HeroWearType.top);
    final bottomRaw = rawForType(_HeroWearType.bottom);
    final shoesRaw = overrideShoeRaw ?? rawForType(_HeroWearType.shoes);
    final outerRaw = rawForType(_HeroWearType.outerwear);
    if (topRaw == null || bottomRaw == null || shoesRaw == null) return null;

    String labelFor(Map<String, dynamic> raw, String fallback) {
      final name = (raw['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
      final sub =
          (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString().trim();
      if (sub.isNotEmpty) return sub;
      return fallback;
    }

    OutfitPreviewItem previewItem(
      OutfitWearType type,
      Map<String, dynamic> raw,
      String fallback,
    ) {
      return OutfitPreviewItem(
        type: type,
        item: raw,
        label: labelFor(raw, fallback),
        imageUrl: null,
      );
    }

    return OutfitPreview(
      top: previewItem(OutfitWearType.top, topRaw, 'Vrchný diel'),
      bottom: previewItem(OutfitWearType.bottom, bottomRaw, 'Spodný diel'),
      shoes: previewItem(OutfitWearType.shoes, shoesRaw, 'Obuv'),
      outerwear: outerRaw == null
          ? null
          : previewItem(OutfitWearType.outerwear, outerRaw, 'Vrstva'),
    );
  }

  Map<String, dynamic>? _bestPreferredFootwearForRestore({
    required FootwearFamilyGuidance guidance,
    required FootwearFamilyInventory inventory,
    required List<Map<String, dynamic>> wardrobe,
    required List<_HeroOutfitItem> currentItems,
    required OutfitWeatherSnapshot weather,
    String? currentShoeId,
  }) {
    final preferredIds = inventory.idsForPreferredFamilies(guidance).toSet();
    if (preferredIds.isEmpty) return null;

    final byId = <String, Map<String, dynamic>>{};
    for (final raw in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(raw);
      if (id.isNotEmpty) byId[id] = raw;
    }

    final candidates = preferredIds
        .where((id) => id.isNotEmpty && id != (currentShoeId ?? '').trim())
        .map((id) => byId[id])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (candidates.isEmpty) return null;

    Map<String, dynamic>? best;
    var bestScore = -1e9;
    for (final shoeRaw in candidates) {
      final preview = _outfitPreviewForFootwearScoring(
        items: currentItems,
        wardrobe: wardrobe,
        overrideShoeRaw: shoeRaw,
      );
      if (preview == null) continue;
      final score = OutfitGenerationService.ruleBasedOutfitScoreForPreview(
        preview: preview,
        weather: weather,
      );
      if (score > bestScore) {
        bestScore = score;
        best = shoeRaw;
      }
    }
    return best ?? candidates.first;
  }

  _HeroOutfitItem? _hydrateRestoredFootwearReplacementImage({
    required String dateKey,
    required String dayLabel,
    required _HeroOutfitItem replacementShoe,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    final id = (replacementShoe.wardrobeItemId ?? '').trim();
    final name = replacementShoe.label;
    String? resolvedUrl;

    if (id.isNotEmpty) {
      final cached = _cachedHomeImageUrlForItem(dateKey, id);
      if (cached != null && cached.isNotEmpty) {
        resolvedUrl = cached;
      } else {
        final wardrobeNorm =
            _wardrobeForOutfitGeneration(wardrobe, logNormalization: false);
        for (final raw in wardrobeNorm) {
          if (OutfitGenerationService.wardrobeItemId(raw) == id) {
            resolvedUrl = getHomeOutfitImageUrlOrNull(raw);
            if (resolvedUrl == null || resolvedUrl.isEmpty) {
              resolvedUrl = _heroWardrobeDisplayImageUrlForHome(
                raw,
                dateKey: dateKey,
                allowPick: true,
              );
            }
            break;
          }
        }
      }
    }

    final existing = replacementShoe.imageUrl?.trim();
    if ((resolvedUrl == null || resolvedUrl.isEmpty) &&
        existing != null &&
        existing.isNotEmpty) {
      resolvedUrl = existing;
    }

    final success = resolvedUrl != null && resolvedUrl.isNotEmpty;
    debugPrint(
      '[HOME_RESTORE_FOOTWEAR_IMAGE_SYNC] itemId=$id name=$name '
      'success=$success url=${success ? resolvedUrl : ''}',
    );
    if (!success) return null;

    _rememberHomeImageUrl(dateKey, id, resolvedUrl, dayLabel: dayLabel);
    return _heroItemWithDisplayImageUrl(replacementShoe, resolvedUrl);
  }

  ({
    List<_HeroOutfitItem> items,
    bool replaced,
    bool abortedDueToMissingImage,
  }) _validateAndReplaceRestoredFootwear({
    required DateTime date,
    required String dateKey,
    required String dayLabel,
    required List<_HeroOutfitItem> items,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    final shoesIdx = items.indexWhere((it) => it.type == _HeroWearType.shoes);
    if (shoesIdx < 0) {
      return (
        items: items,
        replaced: false,
        abortedDueToMissingImage: false,
      );
    }

    final snap = _outfitWeatherSnapshotForDate(date);
    final guidance = computeFootwearFamilyGuidance(weather: snap);
    final wardrobeNorm =
        _wardrobeForOutfitGeneration(wardrobe, logNormalization: false);
    final inventory = footwearFamilyInventoryFromWardrobe(wardrobeNorm);

    final shoeItem = items[shoesIdx];
    final shoeRaw = _footwearRawFromWardrobe(shoeItem, wardrobeNorm);
    final family = classifyFootwearFamily(shoeRaw);

    debugPrint(
      '[HOME_RESTORE_FOOTWEAR_VALIDATE] day=$dayLabel item=${shoeItem.label} '
      'family=${family.wireName} allowed=${guidance.isAllowed(family)} '
      'preferredAvailable=${inventory.hasPreferred(guidance)}',
    );

    if (!guidance.isDiscouraged(family)) {
      return (
        items: items,
        replaced: false,
        abortedDueToMissingImage: false,
      );
    }
    if (!inventory.hasPreferred(guidance)) {
      return (
        items: items,
        replaced: false,
        abortedDueToMissingImage: false,
      );
    }

    final bestRaw = _bestPreferredFootwearForRestore(
      guidance: guidance,
      inventory: inventory,
      wardrobe: wardrobeNorm,
      currentItems: items,
      weather: snap,
      currentShoeId: shoeItem.wardrobeItemId,
    );
    if (bestRaw == null) {
      return (
        items: items,
        replaced: false,
        abortedDueToMissingImage: false,
      );
    }

    final prevBuildDateKey = _currentHeroBuildDateKey;
    _currentHeroBuildDateKey = dateKey;
    try {
      final newShoe =
          _heroItemFromWardrobe(raw: bestRaw, type: _HeroWearType.shoes);
      final hydratedShoe = _hydrateRestoredFootwearReplacementImage(
        dateKey: dateKey,
        dayLabel: dayLabel,
        replacementShoe: newShoe,
        wardrobe: wardrobe,
      );
      if (hydratedShoe == null) {
        debugPrint('[HOME_RESTORE_FOOTWEAR_ABORT] reason=missing_image_url');
        return (
          items: items,
          replaced: false,
          abortedDueToMissingImage: true,
        );
      }

      final updated = List<_HeroOutfitItem>.from(items);
      updated[shoesIdx] = hydratedShoe;
      debugPrint(
        '[HOME_RESTORE_FOOTWEAR_REPLACED] day=$dayLabel '
        'old=${shoeItem.label} new=${hydratedShoe.label} '
        'reason=discouraged_cached_footwear',
      );
      return (
        items: _orderedHeroOutfitItems(updated),
        replaced: true,
        abortedDueToMissingImage: false,
      );
    } finally {
      _currentHeroBuildDateKey = prevBuildDateKey;
    }
  }

  void _syncRestoredFootwearFixToCaches({
    required String dateKey,
    required DateTime date,
    required int dayIdx,
    required String dayLabel,
    required List<_HeroOutfitItem> items,
    required List<Map<String, dynamic>> wardrobe,
    String? existingReason,
    String? likedOutfitKey,
  }) {
    final w = _weatherForDate(date);
    final weatherSig = _homeWeatherSignature(w);
    final wardrobeSig = _wardrobeSignature(wardrobe);
    final savedAt = DateTime.now();
    final reason = _regenerateStylistReason(
      date: date,
      outfitItems: items,
      source: 'swap',
      wardrobe: wardrobe,
    );
    final heroState = _HeroTodayState(
      vm: _HeroBannerVM(
        description: reason.isNotEmpty
            ? reason
            : (existingReason ?? 'Upravený outfit pre tento deň.'),
      ),
      outfitItems: items,
      source: 'edited',
    );

    _editedOutfitByDay[dayIdx] = List<_HeroOutfitItem>.from(items);
    _editedManuallyByDay[dayIdx] = true;
    _lastSourceSignatureByDay[dayIdx] = _heroRenderSignature(items);
    _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
      state: heroState,
      weatherSignature: weatherSig,
      wardrobeSignature: wardrobeSig,
      userModified: true,
      persistSource: 'restore_footwear_fix',
      updatedAt: savedAt,
    );
    _touchHomeDayCacheUpdatedAt(dateKey, savedAt);
    _syncHomeImageCacheForDateKey(dateKey, items);
    _syncHomeOutfitStateToAllCaches(
      dayIndex: dayIdx,
      dateKey: dateKey,
      dayLabel: dayLabel,
      normalized: items,
      heroState: heroState,
    );
    _invalidateHomeHeroBuildCache(dateKey: dateKey);
    _invalidateHeroPanelContentCache(dayIndex: dayIdx);

    unawaited(
      _persistDailyOutfitCache(
        date: date,
        items: items,
        reasonText: heroState.vm.description,
        persistSource: 'restore_footwear_fix',
        userModified: true,
        wardrobe: wardrobe,
        likedOutfitKey: likedOutfitKey,
        fullReplace: true,
        targetCache: 'daily_firestore',
      ),
    );
  }

  List<_HeroOutfitItem> _applyRestoredFootwearValidationIfNeeded({
    required String dateKey,
    required DateTime date,
    required int dayIdx,
    required String dayLabel,
    required List<_HeroOutfitItem> items,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    if (wardrobe.isEmpty || items.length < 3) return items;

    final validationKey = '$dateKey|${_homeWeatherSignature(_weatherForDate(date))}';
    if (_restoredFootwearValidatedKeys.contains(validationKey)) return items;

    final result = _validateAndReplaceRestoredFootwear(
      date: date,
      dateKey: dateKey,
      dayLabel: dayLabel,
      items: items,
      wardrobe: wardrobe,
    );
    if (!result.abortedDueToMissingImage) {
      _restoredFootwearValidatedKeys.add(validationKey);
    }

    if (!result.replaced) return result.items;

    _syncRestoredFootwearFixToCaches(
      dateKey: dateKey,
      date: date,
      dayIdx: dayIdx,
      dayLabel: dayLabel,
      items: result.items,
      wardrobe: wardrobe,
      likedOutfitKey: _likedOutfitKeyByDay[dayIdx],
    );
    return result.items;
  }

  _HeroTodayState _heroStateWithRestoredFootwearValidation({
    required _HeroTodayState state,
    required DateTime date,
    required String dateKey,
    required int dayIdx,
    required String dayLabel,
    required List<Map<String, dynamic>> wardrobe,
    required bool dataReady,
  }) {
    if (!dataReady || wardrobe.isEmpty || !_heroStateHasValidOutfit(state)) {
      return state;
    }
    final validatedItems = _applyRestoredFootwearValidationIfNeeded(
      dateKey: dateKey,
      date: date,
      dayIdx: dayIdx,
      dayLabel: dayLabel,
      items: state.outfitItems,
      wardrobe: wardrobe,
    );
    if (_sameHeroItemsById(validatedItems, state.outfitItems)) {
      return state;
    }
    final fixedCache = _homeDayHeroCacheByDateKey[dateKey];
    if (fixedCache?.persistSource == 'restore_footwear_fix') {
      return fixedCache!.state;
    }
    return _HeroTodayState(
      vm: state.vm,
      outfitItems: validatedItems,
      source: 'edited',
      loadingReason: state.loadingReason,
    );
  }

  Future<void> _validateRestoredFootwearForTodayAndTomorrow({
    required List<Map<String, dynamic>> wardrobe,
  }) async {
    if (!_weatherLoaded || wardrobe.isEmpty) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var anyChanged = false;

    for (final date in [today, today.add(const Duration(days: 1))]) {
      final dateKey = _dateKey(date);
      final dayIdx = _dayIndexForDate(date);
      final dayLabel = dayIdx == 0 ? 'today' : 'tomorrow';
      final cache = _homeDayHeroCacheByDateKey[dateKey];
      List<_HeroOutfitItem>? items;

      if (cache != null && _heroStateHasValidOutfit(cache.state)) {
        items = cache.state.outfitItems;
      } else {
        final hydrated = _homeHydratedOutfitItemsByDateKey[dateKey];
        if (hydrated != null && hydrated.length >= 3) {
          items = hydrated;
        }
      }
      if (items == null || items.length < 3) continue;

      final beforeSig = _heroOutfitSignatureFromItems(items);
      final validated = _applyRestoredFootwearValidationIfNeeded(
        dateKey: dateKey,
        date: date,
        dayIdx: dayIdx,
        dayLabel: dayLabel,
        items: items,
        wardrobe: wardrobe,
      );
      if (_heroOutfitSignatureFromItems(validated) != beforeSig) {
        anyChanged = true;
      }
    }

    if (anyChanged && mounted) {
      _invalidateHomeHeroBuildCache();
      setState(() {});
    }
  }

  void _commitHomeOutfitItemReplacement({
    required _HeroWearType wearType,
    required _HeroOutfitItem newItem,
    required List<_HeroOutfitItem> updatedOutfit,
    _HeroOutfitItem? replacedItem,
  }) {
    final dayLabel = _dayIndex == 0 ? 'today' : 'tomorrow';
    final oldId = (replacedItem?.wardrobeItemId ?? '').trim();
    final newId = (newItem.wardrobeItemId ?? '').trim();

    if (wearType == _HeroWearType.shoes &&
        _shouldBlockDiscouragedFootwearSwap(newItem)) {
      final family =
          classifyFootwearFamily(_footwearMapFromHeroItem(newItem)).wireName;
      debugPrint(
        '[HOME_SWAP_BLOCKED] reason=discouraged_footwear_family '
        'oldId=$oldId newId=$newId family=$family',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tieto topánky sa dnes veľmi nehodia k počasiu.'),
          ),
        );
      }
      return;
    }

    if (wearType == _HeroWearType.bottom &&
        _shouldBlockDiscouragedBottomSwap(newItem)) {
      final raw = _bottomMapFromHeroItem(
        newItem,
        _normalizedWardrobeForHomeBrain.isNotEmpty
            ? _normalizedWardrobeForHomeBrain
            : _lastWardrobeForCache,
      );
      final family = classifyBottomFamily(raw).wireName;
      debugPrint(
        '[HOME_SWAP_BLOCKED] reason=discouraged_bottom_family '
        'oldId=$oldId newId=$newId family=$family',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tento spodný diel sa dnes veľmi nehodí k teplote.',
            ),
          ),
        );
      }
      return;
    }

    debugPrint(
      '[HOME_REPLACE] day=$dayLabel slot=${wearType.name} old=$oldId new=$newId',
    );
    _setEditedItems(
      updatedOutfit,
      markManual: true,
      reasonSource: 'replace_item',
    );
  }

  Future<void> _setEditedItems(
    List<_HeroOutfitItem> items, {
    bool markManual = true,
    String reasonSource = 'swap',
    List<Map<String, dynamic>>? wardrobe,
    String? reasonOverride,
  }) async {
    final normalized = _orderedHeroOutfitItems(items);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = _dayIndex == 1 ? today.add(const Duration(days: 1)) : today;
    final dateKey = _dateKey(date);
    final dayLabel = _dayIndex == 0 ? 'today' : 'tomorrow';
    final weather = _weatherForDate(date);
    final weatherSig = _homeWeatherSignature(weather);
    final effectiveWardrobe = wardrobe ?? _lastWardrobeForCache;
    final reason = (reasonOverride ?? '').trim().isNotEmpty
        ? reasonOverride!.trim()
        : _regenerateStylistReason(
            date: date,
            outfitItems: normalized,
            source: reasonSource,
            wardrobe: effectiveWardrobe,
          );
    final wardrobeSig = _wardrobeSignature(effectiveWardrobe);
    final persistSource = _persistSourceForReason(reasonSource);
    final existing = _homeDayHeroCacheByDateKey[dateKey];
    final heroState = _HeroTodayState(
      vm: _HeroBannerVM(
        description: reason.isNotEmpty
            ? reason
            : (existing?.state.vm.description ?? 'Upravený outfit pre tento deň.'),
      ),
      outfitItems: normalized,
      source: markManual ? 'edited' : (existing?.state.source ?? 'local'),
    );
    _touchHomeDayCacheUpdatedAt(dateKey, now);
    setState(() {
      _editedOutfitByDay[_dayIndex] = normalized;
      _editedManuallyByDay[_dayIndex] = markManual;
      _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
        state: heroState,
        weatherSignature: weatherSig,
        wardrobeSignature: wardrobeSig.isNotEmpty
            ? wardrobeSig
            : (existing?.wardrobeSignature ?? ''),
        userModified: markManual,
        persistSource: persistSource,
        updatedAt: now,
      );
      _syncHomeOutfitStateToAllCaches(
        dayIndex: _dayIndex,
        dateKey: dateKey,
        dayLabel: dayLabel,
        normalized: normalized,
        heroState: heroState,
      );
      if (_focusedEditType != null &&
          !_editedOutfitByDay[_dayIndex]!.any((it) => it.type == _focusedEditType)) {
        _focusedEditType = null;
      }
    });
    final persistFuture = _persistDailyOutfitCache(
      date: date,
      items: normalized,
      reasonText: reason,
      persistSource: persistSource,
      userModified: markManual,
      wardrobe: effectiveWardrobe,
      likedOutfitKey: _likedOutfitKeyByDay[_dayIndex],
      fullReplace: reasonSource == 'new_outfit',
      targetCache: 'daily_firestore',
    );
    if (reasonSource == 'new_outfit') {
      await persistFuture;
    } else {
      unawaited(persistFuture);
    }
    if (markManual) {
      _logHomeCacheUserPreserveIfNeeded(
        dateKey: dateKey,
        items: normalized,
        reason: reasonSource == 'new_outfit' ? 'new_outfit' : 'replace_item',
      );
    }
  }

  String _persistSourceForReason(String reasonSource) {
    if (reasonSource == 'new_outfit') return 'manual_new_outfit';
    if (reasonSource == 'swap' || reasonSource == 'replace_item') {
      return 'manual_replaced';
    }
    return 'manual_replaced';
  }

  String _persistLogReasonForSource(String persistSource) {
    if (persistSource == 'manual_replaced') return 'replace_item';
    if (persistSource == 'manual_new_outfit') return 'new_outfit';
    return persistSource;
  }

  Map<String, dynamic> _heroItemToCacheMap(_HeroOutfitItem item) {
    return <String, dynamic>{
      'type': item.type.name,
      'label': item.label,
      if (item.brandLine != null) 'brandLine': item.brandLine,
      if (item.imageUrl != null) 'imageUrl': item.imageUrl,
      if (item.categoryKey != null) 'categoryKey': item.categoryKey,
      if (item.subCategoryKey != null) 'subCategoryKey': item.subCategoryKey,
      if (item.wardrobeItemId != null) 'wardrobeItemId': item.wardrobeItemId,
      'imageProcessing': item.imageProcessing,
    };
  }

  _HeroWearType? _heroWearTypeFromName(String name) {
    for (final t in _HeroWearType.values) {
      if (t.name == name) return t;
    }
    return null;
  }

  List<_HeroOutfitItem> _heroItemsFromPersistedMaps(
    List<Map<String, dynamic>> maps,
    List<Map<String, dynamic>> wardrobe,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final raw in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(raw);
      if (id.isNotEmpty) byId[id] = raw;
    }
    final out = <_HeroOutfitItem>[];
    for (final m in maps) {
      final type = _heroWearTypeFromName((m['type'] ?? '').toString()) ??
          _HeroWearType.top;
      final wid = (m['wardrobeItemId'] ?? m['id'] ?? '').toString().trim();
      final raw = wid.isNotEmpty ? byId[wid] : null;
      if (raw != null) {
        out.add(_heroItemFromWardrobe(raw: raw, type: type));
      } else {
        out.add(
          _HeroOutfitItem(
            type: type,
            icon: _heroIconForType(type),
            label: (m['label'] ?? _heroFallbackLabelForType(type)).toString(),
            brandLine: (m['brandLine'] as String?)?.trim().isNotEmpty == true
                ? (m['brandLine'] as String).trim()
                : null,
            imageUrl: (m['imageUrl'] as String?)?.trim().isNotEmpty == true
                ? (m['imageUrl'] as String).trim()
                : null,
            categoryKey: (m['categoryKey'] as String?)?.trim().isNotEmpty == true
                ? (m['categoryKey'] as String).trim()
                : null,
            subCategoryKey:
                (m['subCategoryKey'] as String?)?.trim().isNotEmpty == true
                ? (m['subCategoryKey'] as String).trim()
                : null,
            wardrobeItemId: wid.isEmpty ? null : wid,
            imageProcessing: m['imageProcessing'] == true,
          ),
        );
      }
    }
    return _orderedHeroOutfitItems(out);
  }

  bool _validatePersistedItemIds(
    List<String> itemIds,
    List<Map<String, dynamic>> wardrobe,
  ) {
    if (itemIds.isEmpty) return false;
    final ids = wardrobe
        .map((e) => OutfitGenerationService.wardrobeItemId(e))
        .where((e) => e.isNotEmpty)
        .toSet();
    for (final id in itemIds) {
      if (!ids.contains(id)) return false;
    }
    return true;
  }

  Future<void> _persistDailyOutfitCache({
    required DateTime date,
    required List<_HeroOutfitItem> items,
    required String reasonText,
    required String persistSource,
    required bool userModified,
    required List<Map<String, dynamic>> wardrobe,
    String? likedOutfitKey,
    bool fullReplace = false,
    String targetCache = 'daily_firestore',
  }) async {
    final user = _auth.currentUser;
    if (user == null || items.isEmpty) return;
    final dateKey = _dateKey(date);
    final weatherSig = _homeWeatherSignature(_weatherForDate(date));
    final wardrobeSig = _wardrobeSignature(wardrobe);
    final itemIds = _heroOutfitItemIds(items);
    if (itemIds.isEmpty) return;

    final savedAt = DateTime.now();
    final clientUpdatedAtMs = savedAt.millisecondsSinceEpoch;
    _touchHomeDayCacheUpdatedAt(dateKey, savedAt);

    if (persistSource == 'ai_generated') {
      final hero = _homeDayHeroCacheByDateKey[dateKey];
      if (hero?.userModified == true) {
        debugPrint(
          '[HOME_DAY_CACHE] skip_save reason=user_modified_cache_hit date=$dateKey',
        );
        return;
      }
    }

    if (persistSource == 'manual_new_outfit') {
      _lastSavedNewOutfitIdsByDateKey[dateKey] = List<String>.from(itemIds);
    }

    final doc = HomeDailyOutfitCacheDocument(
      dateKey: dateKey,
      itemIds: itemIds,
      items: items.map(_heroItemToCacheMap).toList(growable: false),
      reasonText: reasonText,
      reasonItemIds: itemIds,
      weatherSignature: weatherSig,
      wardrobeSignature: wardrobeSig,
      source: persistSource,
      userModified: userModified,
      likedOutfitKey: likedOutfitKey,
      updatedAt: savedAt,
      clientUpdatedAtMs: clientUpdatedAtMs,
      lastNewOutfitItemIds:
          persistSource == 'manual_new_outfit' ? itemIds : null,
      lastNewOutfitSavedAtMs:
          persistSource == 'manual_new_outfit' ? clientUpdatedAtMs : null,
      cacheSchemaVersion: _homeDailyOutfitCacheSchemaVersion,
    );
    await _dailyOutfitCacheService.save(
      uid: user.uid,
      document: doc,
      merge: !fullReplace,
      waitForPendingWrites: fullReplace,
    );
    debugPrint(
      '[HOME_DAY_CACHE] saved reason=${_persistLogReasonForSource(persistSource)} date=$dateKey',
    );
    _logHomeDayCacheSaveDebug(
      reason: _persistLogReasonForSource(persistSource),
      dateKey: dateKey,
      ids: itemIds,
      names: _heroOutfitItemNames(items),
      updatedAt: savedAt,
      targetCache: targetCache,
    );
  }

  Future<void> _ensurePersistedDailyOutfitsHydrated({
    required List<Map<String, dynamic>> wardrobe,
  }) async {
    if (_persistedDailyHydrationInFlight) {
      while (_persistedDailyHydrationInFlight) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      return;
    }
    final user = _auth.currentUser;
    if (user == null || !_weatherLoaded) return;
    if (_persistedDailyHydrationDone &&
        wardrobe.isEmpty &&
        _hasRestoredDailyOutfitCacheForBoot()) {
      return;
    }
    _persistedDailyHydrationInFlight = true;
    try {
      await _hydratePersistedDailyOutfits(wardrobe: wardrobe);
      _persistedDailyHydrationDone = true;
    } finally {
      _persistedDailyHydrationInFlight = false;
    }
  }

  bool _hasRestoredDailyOutfitCacheForBoot() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    for (final date in [today, tomorrow]) {
      final dateKey = _dateKey(date);
      final cache = _homeDayHeroCacheByDateKey[dateKey];
      if (cache != null && _heroStateHasValidOutfit(cache.state)) {
        return true;
      }
    }
    return false;
  }

  String _homeBootCacheLabel(String dateKey) {
    final cache = _homeDayHeroCacheByDateKey[dateKey];
    if (cache != null && _heroStateHasValidOutfit(cache.state)) {
      return 'hit';
    }
    if (_hydratedHomeCacheDateKeys.contains(dateKey)) {
      return 'hydrated';
    }
    return 'miss';
  }

  void _debugHomeBootState({bool force = false}) {
    if (!force && _loggedHomeBootSnapshot) return;
    _loggedHomeBootSnapshot = true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final weatherReady = _weatherLoaded &&
        _weatherSnapToday != null &&
        _weatherSnapTomorrow != null;
    logVerboseHome(
      '[HOME_BOOT] weatherReady=$weatherReady wardrobeReady=${_lastWardrobeForCache.isNotEmpty} '
      'todayCache=${_homeBootCacheLabel(_dateKey(today))} '
      'tomorrowCache=${_homeBootCacheLabel(_dateKey(tomorrow))}',
    );
  }

  void _logHomeRestoreSkipped(String dayLabel, String reason) {
    debugPrint('[HOME_RESTORE] skipped reason=$reason day=$dayLabel');
  }

  void _logHomeRestoreFromDailyCache(String dayLabel) {
    debugPrint('[HOME_RESTORE] from_daily_cache day=$dayLabel');
  }

  Future<void> _hydratePersistedDailyOutfits({
    required List<Map<String, dynamic>> wardrobe,
  }) async {
    final user = _auth.currentUser;
    if (user == null || !_weatherLoaded) return;
    _isRestoringHomeCache = true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = [today, today.add(const Duration(days: 1))];
    var anyRestored = false;

    try {
      for (final date in dates) {
        final dateKey = _dateKey(date);
        final dayLabel = _dayIndexForDate(date) == 0 ? 'today' : 'tomorrow';
        if (_hydratedDailyOutfitWithWardrobeDateKeys.contains(dateKey)) {
          final cached = _homeDayHeroCacheByDateKey[dateKey];
          if (cached != null && _heroStateHasValidOutfit(cached.state)) {
            continue;
          }
        }
        final doc = await _dailyOutfitCacheService.load(
          user.uid,
          dateKey,
          preferServer: true,
        );
        final dayIdx = _dayIndexForDate(date);
        final w = _weatherForDate(date);
        final weatherSig = _homeWeatherSignature(w);
        final wardrobeSig = _wardrobeSignature(wardrobe);
        if (doc != null && doc.userModified && doc.cacheSchemaVersion < 2) {
          _logHomeRestoreSkipped(dayLabel, 'legacy_user_modified_cache');
          debugPrint(
            '[HOME_DAY_CACHE] skip_restore reason=legacy_user_modified_cache '
            'date=$dateKey version=${doc.cacheSchemaVersion}',
          );
          continue;
        }

        final snapshots = _collectHomeDayCacheSnapshots(
          dateKey: dateKey,
          dayIdx: dayIdx,
          firestoreDoc: doc,
        );
        if (snapshots.isEmpty) {
          _logHomeRestoreSkipped(dayLabel, 'no_document');
          continue;
        }

        final validSnapshots = _validHomeDayCacheSnapshots(
          snapshots: snapshots,
          weatherSignature: weatherSig,
          wardrobeSignature: wardrobeSig,
          wardrobe: wardrobe,
        );
        if (validSnapshots.isEmpty) {
          if (doc != null && doc.weatherSignature != weatherSig) {
            _logHomeRestoreSkipped(dayLabel, 'weather_changed');
            debugPrint(
              '[HOME_DAY_CACHE] skip_restore reason=weather_changed date=$dateKey',
            );
          } else if (doc != null &&
              wardrobe.isNotEmpty &&
              !doc.userModified &&
              doc.wardrobeSignature != wardrobeSig) {
            _logHomeRestoreSkipped(dayLabel, 'wardrobe_signature_mismatch');
          } else if (doc != null &&
              doc.userModified &&
              wardrobe.isNotEmpty &&
              !_validatePersistedItemIds(doc.itemIds, wardrobe)) {
            _logHomeRestoreSkipped(dayLabel, 'missing_items');
            debugPrint(
              '[HOME_DAY_CACHE] skip_restore reason=missing_items date=$dateKey',
            );
          } else {
            _logHomeRestoreSkipped(dayLabel, 'no_valid_snapshot');
          }
          continue;
        }

        final chosen = _chooseNewestHomeDayCacheSnapshot(validSnapshots);
        if (chosen == null) {
          _logHomeRestoreSkipped(dayLabel, 'no_chosen_snapshot');
          continue;
        }

        var items = _heroItemsFromCacheSnapshot(chosen, wardrobe);
        if (items.length < 3) {
          _logHomeRestoreSkipped(dayLabel, 'too_few_items');
          continue;
        }

        _logHomeDayCacheRestoreDebug(
          dateKey: dateKey,
          chosenSource: chosen.chosenSource,
          ids: chosen.itemIds,
          names: _heroOutfitItemNames(items),
          updatedAt: chosen.updatedAt,
          availableSources: validSnapshots
              .map(
                (s) =>
                    '${s.chosenSource}@${s.updatedAt.millisecondsSinceEpoch}',
              )
              .toList(growable: false),
        );

        String? correctedReasonText;
        var restoredFromLastNewOutfit = false;
        final savedNewOutfitIds = doc?.lastNewOutfitItemIds ??
            _lastSavedNewOutfitIdsByDateKey[dateKey];
        if (savedNewOutfitIds != null &&
            savedNewOutfitIds.isNotEmpty &&
            !_sameStringList(savedNewOutfitIds, chosen.itemIds)) {
          _logHomeDayCacheRestoreMismatch(
            savedIds: savedNewOutfitIds,
            restoredIds: chosen.itemIds,
          );
          if (doc != null && doc.lastNewOutfitItemIds != null) {
            var corrected = _heroItemsFromPersistedIds(
              ids: doc.lastNewOutfitItemIds!,
              wardrobe: wardrobe,
            );
            if (corrected.length < 3) {
              corrected = _heroItemsFromPersistedSlots(
                slotMaps: doc.items,
                ids: doc.lastNewOutfitItemIds!,
                wardrobe: wardrobe,
              );
            }
            if (corrected.length >= 3) {
              items = corrected;
              correctedReasonText = doc.reasonText;
              restoredFromLastNewOutfit = true;
              debugPrint(
                '[HOME_DAY_CACHE] restore_corrected_to_last_new_outfit date=$dateKey',
              );
            }
          }
        }

        var effectiveUserModified =
            restoredFromLastNewOutfit ? true : chosen.userModified;
        var effectivePersistSource = restoredFromLastNewOutfit
            ? 'manual_new_outfit'
            : chosen.persistSource;
        if (wardrobe.isNotEmpty) {
          items = _applyRestoredFootwearValidationIfNeeded(
            dateKey: dateKey,
            date: date,
            dayIdx: dayIdx,
            dayLabel: dayLabel,
            items: items,
            wardrobe: wardrobe,
          );
          final footwearFixed = _homeDayHeroCacheByDateKey[dateKey];
          if (footwearFixed?.persistSource == 'restore_footwear_fix') {
            items = footwearFixed!.state.outfitItems;
            effectiveUserModified = true;
            effectivePersistSource = 'restore_footwear_fix';
            _hydratedDailyOutfitWithWardrobeDateKeys.add(dateKey);
            _hydratedHomeCacheDateKeys.add(dateKey);
            _logHomeRestoreFromDailyCache(dayLabel);
            anyRestored = true;
            if (mounted) setState(() {});
            continue;
          }
        }
        final cachedReason = (correctedReasonText ?? chosen.reasonText).trim();
        final restoredReasonItemIds = restoredFromLastNewOutfit
            ? doc?.reasonItemIds
            : chosen.reasonItemIds;
        final restoredItemIds = _heroOutfitItemIds(items);
        final cachedReasonItemIdsMismatch = cachedReason.isNotEmpty &&
            !_reasonItemIdsMatchOutfit(
              reasonItemIds: restoredReasonItemIds,
              outfitItemIds: restoredItemIds,
            );
        if (cachedReasonItemIdsMismatch) {
          debugPrint(
            '[HOME_DAY_CACHE] reason_item_ids_mismatch date=$dateKey '
            'reasonIds=${restoredReasonItemIds?.join(",") ?? ""} '
            'outfitIds=${restoredItemIds.join(",")}',
          );
        }
        final cachedReasonWasStale = cachedReason.isEmpty ||
            _isStaleHomeReason(cachedReason) ||
            cachedReasonItemIdsMismatch;
        var reason = cachedReasonWasStale
            ? ''
            : cachedReason;
        if (cachedReasonWasStale) {
          final preview = _outfitPreviewForFootwearScoring(
            items: items,
            wardrobe: _wardrobeForOutfitGeneration(
              wardrobe,
              logNormalization: false,
            ),
          );
          if (preview != null) {
            reason = (await _generateAiStylistReasonForPreview(
                  preview: preview,
                  weather: _weatherForDate(date),
                  selectedReason: 'Obnov uložený outfit a napíš nové vysvetlenie podľa vizuálnych metadata.',
                )) ??
                '';
          }
          if (reason.trim().isEmpty) {
            reason = _regenerateStylistReason(
              date: date,
              outfitItems: items,
              source: effectiveUserModified ? 'swap' : 'ai',
              wardrobe: wardrobe,
              scheduleRefresh: false,
            );
          }
          debugPrint(
            '[HOME_DAY_CACHE] stale_reason_refreshed date=$dateKey '
            'source=${reason.trim().isEmpty ? "empty" : "restore"}',
          );
        }
        final heroSource = effectiveUserModified
            ? 'edited'
            : (effectivePersistSource == 'fallback' ? 'local' : 'ai');

        final existingHero = _homeDayHeroCacheByDateKey[dateKey];
        final nextState = _HeroTodayState(
          vm: _HeroBannerVM(
            description: reason.isNotEmpty
                ? reason
                : 'Upravený outfit pre tento deň.',
          ),
          outfitItems: items,
          source: heroSource,
        );
        if (existingHero != null &&
            existingHero.weatherSignature == weatherSig &&
            existingHero.wardrobeSignature == wardrobeSig &&
            existingHero.userModified == effectiveUserModified &&
            _sameHeroTodayState(existingHero.state, nextState)) {
          _hydratedHomeCacheDateKeys.add(dateKey);
          continue;
        }

        _editedOutfitByDay[dayIdx] = List<_HeroOutfitItem>.from(items);
        _editedManuallyByDay[dayIdx] = effectiveUserModified;
        if (effectiveUserModified) {
          _lastSourceSignatureByDay[dayIdx] = _heroRenderSignature(items);
          _logHomeCacheRestoreIfNeeded(dateKey: dateKey, items: items);
        }
        if (chosen.likedOutfitKey != null && chosen.likedOutfitKey!.isNotEmpty) {
          _likedOutfitKeyByDay[dayIdx] = chosen.likedOutfitKey!;
        }

        _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
          state: nextState,
          weatherSignature: weatherSig,
          wardrobeSignature: wardrobeSig,
          userModified: effectiveUserModified,
          persistSource: effectivePersistSource,
          updatedAt: chosen.updatedAt,
        );
        _syncHomeOutfitStateToAllCaches(
          dayIndex: dayIdx,
          dateKey: dateKey,
          dayLabel: dayLabel,
          normalized: items,
          heroState: nextState,
        );
        _touchHomeDayCacheUpdatedAt(dateKey, chosen.updatedAt);
        _hydratedHomeCacheDateKeys.add(dateKey);
        if (wardrobe.isNotEmpty) {
          _hydratedDailyOutfitWithWardrobeDateKeys.add(dateKey);
        }
        if (restoredFromLastNewOutfit ||
            (cachedReasonWasStale && !_isPendingAiStylistReason(reason))) {
          unawaited(
            _persistDailyOutfitCache(
              date: date,
              items: items,
              reasonText: reason,
              persistSource: restoredFromLastNewOutfit
                  ? 'manual_new_outfit'
                  : effectivePersistSource,
              userModified: effectiveUserModified,
              wardrobe: wardrobe,
              likedOutfitKey: chosen.likedOutfitKey,
              fullReplace: true,
              targetCache: restoredFromLastNewOutfit
                  ? 'daily_firestore_restore_fix'
                  : 'daily_firestore_stale_reason_fix',
            ),
          );
        }
        if (_isPendingAiStylistReason(reason)) {
          unawaited(
            _refreshStylistReasonInBackground(
              date: date,
              outfitItems: items,
              source: 'restore_pending',
              wardrobe: wardrobe,
            ),
          );
        }
        _logHomeRestoreFromDailyCache(dayLabel);
        anyRestored = true;
      }
    } finally {
      _isRestoringHomeCache = false;
    }

    if (anyRestored) {
      _invalidateHomeHeroBuildCache();
      if (mounted) setState(() {});
    }
    _refreshPendingStylistReasons(wardrobe: wardrobe);
    _debugHomeBootState(force: true);
  }

  String _pendingAiStylistReasonText() {
    return 'Pripravujem stylistické vysvetlenie k tomuto outfitu.';
  }

  bool _isPendingAiStylistReason(String text) {
    final normalized = _normalizedScaleToken(text);
    return normalized.contains('pripravujem stylisticke vysvetlenie');
  }

  void _refreshPendingStylistReasons({
    required List<Map<String, dynamic>> wardrobe,
  }) {
    if (wardrobe.isEmpty) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final date in [today, today.add(const Duration(days: 1))]) {
      final dateKey = _dateKey(date);
      final cache = _homeDayHeroCacheByDateKey[dateKey];
      if (cache == null || !_heroStateHasValidOutfit(cache.state)) continue;
      if (!_isPendingAiStylistReason(cache.state.vm.description)) continue;
      unawaited(
        _refreshStylistReasonInBackground(
          date: date,
          outfitItems: cache.state.outfitItems,
          source: 'boot_pending',
          wardrobe: wardrobe,
        ),
      );
    }
  }

  Future<void> _refreshStylistReasonInBackground({
    required DateTime date,
    required List<_HeroOutfitItem> outfitItems,
    required String source,
    List<Map<String, dynamic>>? wardrobe,
    String? selectedReason,
    int maxAttempts = 3,
  }) async {
    final effectiveWardrobe = wardrobe ?? _lastWardrobeForCache;
    if (effectiveWardrobe.isEmpty) {
      debugPrint('[HOME_STYLIST_REASON_AI] skip refresh reason=empty_wardrobe');
      return;
    }

    final dateKey = _dateKey(date);
    final dayIdx = _dayIndexForDate(date);
    final dayLabel = dayIdx == 0 ? 'today' : 'tomorrow';
    final outfitIds = outfitItems
        .map((e) => e.wardrobeItemId)
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .join(',');
    final refreshKey = '$dateKey|$outfitIds';
    if (!_stylistReasonRefreshInFlight.add(refreshKey)) return;

    try {
      final preview = _outfitPreviewForFootwearScoring(
        items: outfitItems,
        wardrobe: _wardrobeForOutfitGeneration(
          effectiveWardrobe,
          logNormalization: false,
        ),
      );
      if (preview == null) {
        debugPrint('[HOME_STYLIST_REASON_AI] skip refresh reason=no_preview');
        return;
      }

      String? reason;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        reason = await _generateAiStylistReasonForPreview(
          preview: preview,
          weather: _weatherForDate(date),
          selectedReason: selectedReason ??
              'Napíš stylistické vysvetlenie podľa vizuálnych metadata vybraného outfitu.',
          timeout: Duration(seconds: 12 + (attempt * 4)),
        );
        if (reason != null && reason.trim().isNotEmpty) break;
        if (attempt < maxAttempts) {
          debugPrint(
            '[HOME_STYLIST_REASON_AI] retry day=$dayLabel attempt=${attempt + 1}/$maxAttempts',
          );
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
      if (reason == null || reason.trim().isEmpty || !mounted) return;

      final cache = _homeDayHeroCacheByDateKey[dateKey];
      final currentItems = _editedOutfitByDay[dayIdx] ??
          cache?.state.outfitItems ??
          const <_HeroOutfitItem>[];
      if (!_sameHeroItemsById(currentItems, outfitItems)) {
        debugPrint('[HOME_STYLIST_REASON_AI] skip apply reason=outfit_changed');
        return;
      }

      debugPrint(
        '[HOME_STYLIST_REASON_AI] applied source=$source day=$dayLabel '
        'length=${reason.length}',
      );
      _applyStylistReasonUpdate(
        date: date,
        dateKey: dateKey,
        dayIdx: dayIdx,
        dayLabel: dayLabel,
        outfitItems: outfitItems,
        reason: reason,
        wardrobe: effectiveWardrobe,
      );
    } finally {
      _stylistReasonRefreshInFlight.remove(refreshKey);
    }
  }

  void _maybeRefreshPendingReasonForDate(DateTime date) {
    final dateKey = _dateKey(date);
    final cache = _homeDayHeroCacheByDateKey[dateKey];
    if (cache == null || !_heroStateHasValidOutfit(cache.state)) return;
    if (!_isPendingAiStylistReason(cache.state.vm.description)) return;
    unawaited(
      _refreshStylistReasonInBackground(
        date: date,
        outfitItems: cache.state.outfitItems,
        source: 'pending_day',
        wardrobe: _lastWardrobeForCache,
      ),
    );
  }

  void _applyStylistReasonUpdate({
    required DateTime date,
    required String dateKey,
    required int dayIdx,
    required String dayLabel,
    required List<_HeroOutfitItem> outfitItems,
    required String reason,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    final cache = _homeDayHeroCacheByDateKey[dateKey];
    if (cache == null) return;

    final heroState = _HeroTodayState(
      vm: _HeroBannerVM(description: reason),
      outfitItems: List<_HeroOutfitItem>.from(outfitItems),
      source: cache.state.source,
    );
    _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
      state: heroState,
      weatherSignature: cache.weatherSignature,
      wardrobeSignature: cache.wardrobeSignature,
      userModified: cache.userModified,
      persistSource: cache.persistSource,
      updatedAt: DateTime.now(),
    );
    _syncHomeOutfitStateToAllCaches(
      dayIndex: dayIdx,
      dateKey: dateKey,
      dayLabel: dayLabel,
      normalized: outfitItems,
      heroState: heroState,
    );
    _invalidateHomeHeroBuildCache(dateKey: dateKey);
    if (mounted) setState(() {});

    unawaited(
      _persistDailyOutfitCache(
        date: date,
        items: outfitItems,
        reasonText: reason,
        persistSource: cache.persistSource ?? 'ai_generated',
        userModified: cache.userModified,
        wardrobe: wardrobe,
        likedOutfitKey: _likedOutfitKeyByDay[dayIdx],
      ),
    );
  }

  String _regenerateStylistReason({
    required DateTime date,
    required List<_HeroOutfitItem> outfitItems,
    required String source,
    List<Map<String, dynamic>>? wardrobe,
    bool scheduleRefresh = true,
  }) {
    final ids = outfitItems
        .map((e) => e.wardrobeItemId)
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .join(',');
    final text = _pendingAiStylistReasonText();
    debugPrint('[HOME_STYLIST_REASON] pending_ai_only=true');
    debugPrint('[HOME_STYLIST_REASON] source=$source');
    debugPrint('[HOME_STYLIST_REASON] currentOutfitIds=$ids');
    if (scheduleRefresh) {
      unawaited(
        _refreshStylistReasonInBackground(
          date: date,
          outfitItems: outfitItems,
          source: source,
          wardrobe: wardrobe,
        ),
      );
    }
    return text;
  }

  bool _isStaleHomeReason(String text) {
    final normalized = _normalizedScaleToken(text);
    const banned = [
      'nezbytocne tazky',
      'outfit je nastaveny tak aby bol pohodlny cez den',
      'rano je okolo',
      'poobede sa to vytiahne',
      'zvolil som',
      'zvol tricko',
      'zvol tricko a nohavice',
      'dnes je teplo ale poobede',
      'poobede a vecer sa ocakava dazd',
      'aby si bol pohodlne',
      'tmave topanky',
      'mokrym bielym teniskam',
      'vziat nieco na prehodenie',
      'pripravujem stylisticke vysvetlenie',
    ];
    return banned.any((phrase) => normalized.contains(phrase));
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = _dayIndex == 1 ? today.add(const Duration(days: 1)) : today;
    final dateKey = _dateKey(date);
    final cache = _homeDayHeroCacheByDateKey[dateKey];
    final persistSource = cache?.persistSource ??
        (_editedManuallyByDay[_dayIndex] == true
            ? 'manual_replaced'
            : 'ai_generated');
    final reason = cache?.state.vm.description ??
        _regenerateStylistReason(
          date: date,
          outfitItems: items,
          source: 'swap',
          wardrobe: _lastWardrobeForCache,
        );
    unawaited(
      _persistDailyOutfitCache(
        date: date,
        items: items,
        reasonText: reason,
        persistSource: persistSource,
        userModified: _editedManuallyByDay[_dayIndex] ?? false,
        wardrobe: _lastWardrobeForCache,
        likedOutfitKey: key,
      ),
    );
    _logHomeCacheUserPreserveIfNeeded(
      dateKey: dateKey,
      items: items,
      reason: 'like',
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 4100), () {
        if (!mounted || token != _likeFeedbackToken) return;
        setState(() => _showLikeInlineFeedback = false);
      }),
    );
  }

  void _enterOutfitEditMode(List<_HeroOutfitItem> currentItems) {
    if (currentItems.isEmpty) return;
    _syncEditableOutfitFromSource(currentItems, dayIndex: _dayIndex);
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

  List<_HeroOutfitItem> _heroOutfitItemsForNewOutfitBaseline({
    required int dayIndex,
    required String dateKey,
  }) {
    final edited = _editedOutfitByDay[dayIndex];
    if (edited != null && edited.length >= 3) {
      return List<_HeroOutfitItem>.from(edited);
    }
    final cache = _homeDayHeroCacheByDateKey[dateKey];
    if (cache != null && _heroStateHasValidOutfit(cache.state)) {
      return List<_HeroOutfitItem>.from(cache.state.outfitItems);
    }
    final dayLabel = dayIndex == 0 ? 'today' : 'tomorrow';
    final render = _renderHeroStateForDateKey(dateKey, dayLabel);
    if (render != null && render.outfitItems.length >= 3) {
      return List<_HeroOutfitItem>.from(render.outfitItems);
    }
    return const <_HeroOutfitItem>[];
  }

  String _stylistFinalReviewSignatureKey({
    required String dateKey,
    required String weatherSignature,
    required String wardrobeSignature,
    required bool isPremiumUser,
  }) {
    return '$dateKey|$weatherSignature|$wardrobeSignature|p=${isPremiumUser ? 1 : 0}';
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

  int _coreHeroPieceCount(List<_HeroOutfitItem> items) {
    return items
        .where(
          (it) =>
              it.type == _HeroWearType.top ||
              it.type == _HeroWearType.bottom ||
              it.type == _HeroWearType.shoes,
        )
        .length;
  }

  Set<String> _peerDayOutfitItemIdsForDate(
    DateTime date, {
    bool clothingOnly = false,
  }) {
    final dayIdx = _dayIndexForDate(date);
    final peerIdx = dayIdx == 0 ? 1 : 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final peerDate = peerIdx == 1 ? today.add(const Duration(days: 1)) : today;
    final peerDateKey = _dateKey(peerDate);
    final items = _heroOutfitItemsForNewOutfitBaseline(
      dayIndex: peerIdx,
      dateKey: peerDateKey,
    );
    final ids = <String>{};
    for (final item in items) {
      if (clothingOnly &&
          item.type != _HeroWearType.top &&
          item.type != _HeroWearType.bottom) {
        continue;
      }
      final id = (item.wardrobeItemId ?? '').trim();
      if (id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  Future<void> _handleNewOutfitPressed() async {
    if (_newOutfitGenerating) return;
    final user = _auth.currentUser;
    if (user == null || !mounted) return;

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final activeDate = _isTomorrow ? todayDate.add(const Duration(days: 1)) : todayDate;
    final activeDateKey = _dateKey(activeDate);
    _clearDaySwitchPinnedHero(activeDateKey);

    setState(() => _newOutfitGenerating = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Skúsim úplne inú kombináciu.'),
        duration: Duration(seconds: 2),
      ),
    );

    String? reviewBlockKey;
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
      final weatherSignature = _homeWeatherSignature(w);
      final wardrobeSignature = _wardrobeSignature(wardrobe);
      reviewBlockKey = _stylistFinalReviewSignatureKey(
        dateKey: activeDateKey,
        weatherSignature: weatherSignature,
        wardrobeSignature: wardrobeSignature,
        isPremiumUser: isPremiumUser,
      );
      _stylistFinalReviewInFlight.add(reviewBlockKey);

      final effectiveItems = _heroOutfitItemsForNewOutfitBaseline(
        dayIndex: _dayIndex,
        dateKey: activeDateKey,
      );

      final excluded = <String>{
        for (final it in effectiveItems)
          if ((it.wardrobeItemId ?? '').isNotEmpty) it.wardrobeItemId!,
      };
      final peerClothingItemIds = _peerDayOutfitItemIdsForDate(
        activeDate,
        clothingOnly: true,
      );
      final effectiveExcluded = <String>{
        ...excluded,
        ...peerClothingItemIds,
      };
      final effectivePreviousItemIds = <String>{
        ...excluded,
        ..._peerDayOutfitItemIdsForDate(activeDate),
      };

      final rejectedSigs =
          Set<String>.from(_rejectedOutfitCombinationKeysByDay[_dayIndex] ?? {});
      final prevSig = _heroOutfitSignatureFromItems(effectiveItems);
      if (prevSig.isNotEmpty) {
        rejectedSigs.add(prevSig);
      }
      _rejectedOutfitCombinationKeysByDay[_dayIndex] = rejectedSigs;

      final prevBuildDateKey = _currentHeroBuildDateKey;
      _currentHeroBuildDateKey = activeDateKey;
      _StylistFinalReviewSelection? selection;
      try {
        selection = await _recommendOutfitWithStylistFinalReview(
          wardrobe: wardrobe,
          weather: w,
          isPremiumUser: isPremiumUser,
          excludedItemIds: effectiveExcluded,
          rejectedCombinationSignatures: rejectedSigs,
          previousOutfitItemIds: effectivePreviousItemIds,
          forceDifferentOutfit: effectiveItems.isNotEmpty,
        );
      } finally {
        _currentHeroBuildDateKey = prevBuildDateKey;
      }

      if (!mounted) return;

      if (selection == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nepodarilo sa poskladať nový outfit z šatníka.'),
          ),
        );
        return;
      }

      final newIds = selection.finalSelectedItemIds;
      final changed =
          _countChangedHeroPieces(effectiveItems, selection.heroItems);
      final newSig = selection.finalSelectedSignature;

      debugPrint(
        '[NEW_OUTFIT] originalIds=$excluded rejectedCombinations=${rejectedSigs.length} '
        'peerClothingExcluded=${peerClothingItemIds.join(",")} '
        'newIds=$newIds changedPieces=$changed prevSig=$prevSig newSig=$newSig '
        'finalSelectedIndex=${selection.finalSelectedIndex}',
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

      final coreOldCount = _coreHeroPieceCount(effectiveItems);
      if (changed <= 1 && coreOldCount >= 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'V šatníku nemáš dosť alternatív, vymenil som aspoň dostupné kúsky.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      final dayLabel = _dayIndex == 0 ? 'today' : 'tomorrow';
      final hydratedItems = _hydrateAndValidateStylistFinalReviewSelection(
        selection: selection,
        dateKey: activeDateKey,
        dayLabel: dayLabel,
        wardrobe: wardrobe,
      );
      if (hydratedItems == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Nepodarilo sa načítať obrázky nového outfitu — ponechávam aktuálny.',
              ),
            ),
          );
        }
        return;
      }

      await _setEditedItems(
        hydratedItems,
        reasonSource: 'new_outfit',
        wardrobe: wardrobe,
        reasonOverride: selection.reason,
      );
      _cachedHeroBuildKeyByDateKey.remove(activeDateKey);
      _cachedHeroBuildStateByDateKey.remove(activeDateKey);
      _stylistFinalReviewDone.add(reviewBlockKey);
      _precacheHomeOutfitImages(hydratedItems);
      setState(() {
        _likedOutfitKeyByDay.remove(_dayIndex);
        _likePulseTick = 0;
        _showLikeInlineFeedback = false;
      });
    } finally {
      if (reviewBlockKey != null) {
        _stylistFinalReviewInFlight.remove(reviewBlockKey);
      }
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

  bool _heroStateHasValidOutfit(_HeroTodayState state) {
    if (state.source == 'loading') return false;
    final items = state.outfitItems;
    if (items.length < 3) return false;
    final withId = items
        .where((it) => (it.wardrobeItemId ?? '').trim().isNotEmpty)
        .length;
    if (withId >= 3) return true;
    return items
            .where((it) => (it.imageUrl ?? '').trim().isNotEmpty)
            .length >=
        3;
  }

  _HeroOutfitRecommendation? _validAiRecommendationForSignature(String signature) {
    final rec = _homeAiCacheBySignature[signature]?.recommendation;
    if (rec == null || rec.items.length < 3) return null;
    return rec;
  }

  bool _hasValidDailyOutfitForDate({
    required String dateKey,
    required String weatherSignature,
    required String wardrobeSignature,
  }) {
    final hero = _homeDayHeroCacheByDateKey[dateKey];
    if (hero != null && _heroStateHasValidOutfit(hero.state)) {
      if (hero.userModified) {
        return true;
      }
      if (hero.weatherSignature == weatherSignature) {
        if (hero.wardrobeSignature == wardrobeSignature) {
          return true;
        }
        if (hero.state.source == 'ai' || hero.state.source == 'local') {
          return true;
        }
      }
    }
    final latestSig = _homeAiLatestSignatureByDateKey[dateKey];
    if (latestSig != null &&
        latestSig.startsWith('$dateKey|$weatherSignature|') &&
        _validAiRecommendationForSignature(latestSig) != null) {
      return true;
    }
    return false;
  }

  bool _sameHeroTodayState(_HeroTodayState a, _HeroTodayState b) {
    if (a.source != b.source) return false;
    if (a.vm.description != b.vm.description) return false;
    if (a.loadingReason != b.loadingReason) return false;
    return _sameHeroItemsById(a.outfitItems, b.outfitItems);
  }

  void _writeHomeDayHeroCacheIfChanged({
    required String dateKey,
    required _HeroTodayState state,
    required String weatherSignature,
    required String wardrobeSignature,
    bool userModified = false,
    String? persistSource,
  }) {
    final existing = _homeDayHeroCacheByDateKey[dateKey];
    if (existing != null &&
        existing.weatherSignature == weatherSignature &&
        existing.wardrobeSignature == wardrobeSignature &&
        existing.userModified == userModified &&
        (existing.persistSource ?? '') == (persistSource ?? '') &&
        _sameHeroTodayState(existing.state, state)) {
      return;
    }
    _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
      state: state,
      weatherSignature: weatherSignature,
      wardrobeSignature: wardrobeSignature,
      userModified: userModified,
      persistSource: persistSource,
    );
  }

  void _logHomeDayCacheCheckOnce(String dayLabel, String dateKey) {
    final key = '$dayLabel|$dateKey';
    if (!_loggedHomeDayCacheCheckLines.add(key)) return;
    logVerboseHome('[HOME_DAY_CACHE] check day=$dayLabel date=$dateKey');
  }

  void _logHomeDayCacheHitOnce(String dayLabel) {
    if (!_loggedHomeDayCacheHits.add(dayLabel)) return;
    logVerboseHome('[HOME_DAY_CACHE] hit day=$dayLabel');
  }

  void _logHomeDayCacheMissOnce(String dayLabel) {
    if (!_loggedHomeDayCacheMisses.add(dayLabel)) return;
    logVerboseHome('[HOME_DAY_CACHE] miss day=$dayLabel');
  }

  void _logHomeDayCacheMemoryHitOnce(String dayLabel) {
    if (!_loggedHomeDayCacheMemoryHits.add(dayLabel)) return;
    logVerboseHome('[HOME_DAY_CACHE] memory_hit day=$dayLabel');
  }

  void _tryScheduleHomeOutfitPreload() {
    if (!_weatherLoaded) return;
    unawaited(_ensurePersistedDailyOutfitsHydrated(wardrobe: _lastWardrobeForCache));
    if (_lastWardrobeForCache.isEmpty) return;
    _scheduleHomeOutfitPreloadOnce(
      wardrobe: _lastWardrobeForCache,
      isPremiumUser: _lastIsPremiumUser,
    );
  }

  void _scheduleHomeOutfitPreloadOnce({
    required List<Map<String, dynamic>> wardrobe,
    required bool isPremiumUser,
  }) {
    if (wardrobe.isEmpty || !_weatherLoaded) return;
    if (_homePreloadPassCompleted || _homePreloadInFlight) return;
    _homePreloadInFlight = true;
    _lastIsPremiumUser = isPremiumUser;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _runHomeOutfitPreload(
          wardrobe: wardrobe,
          isPremiumUser: isPremiumUser,
        ).whenComplete(() {
          _homePreloadInFlight = false;
          if (_homePreloadRanChecks) {
            _homePreloadPassCompleted = true;
          }
        }),
      );
    });
  }

  Future<void> _runHomeOutfitPreload({
    required List<Map<String, dynamic>> wardrobe,
    required bool isPremiumUser,
  }) async {
    if (!mounted) return;
    await _ensurePersistedDailyOutfitsHydrated(wardrobe: wardrobe);
    if (!mounted) return;
    await _validateRestoredFootwearForTodayAndTomorrow(wardrobe: wardrobe);
    if (!mounted) return;
    await _ensureDailyOutfitsForTodayAndTomorrow(
      wardrobe: wardrobe,
      isPremiumUser: isPremiumUser,
    );
  }

  Future<void> _ensureDailyOutfitsForTodayAndTomorrow({
    required List<Map<String, dynamic>> wardrobe,
    required bool isPremiumUser,
  }) async {
    if (!_weatherLoaded || wardrobe.isEmpty) return;
    _homePreloadRanChecks = true;
    logVerboseHome('[HOME_PRELOAD] ensure_today_tomorrow started');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    await Future.wait([
      _ensureDailyOutfitChecked(
        date: today,
        wardrobe: wardrobe,
        isPremiumUser: isPremiumUser,
      ),
      _ensureDailyOutfitChecked(
        date: tomorrow,
        wardrobe: wardrobe,
        isPremiumUser: isPremiumUser,
      ),
    ]);
  }

  Future<void> _ensureDailyOutfitChecked({
    required DateTime date,
    required List<Map<String, dynamic>> wardrobe,
    required bool isPremiumUser,
  }) async {
    if (!_weatherLoaded || wardrobe.isEmpty) return;
    final dateKey = _dateKey(date);
    final dayLabel = _dayIndexForDate(date) == 0 ? 'today' : 'tomorrow';
    final weather = _weatherForDate(date);
    final weatherSignature = _homeWeatherSignature(weather);
    final wardrobeSignature = _wardrobeSignature(wardrobe);

    _logHomeDayCacheCheckOnce(dayLabel, dateKey);
    if (_hasValidDailyOutfitForDate(
      dateKey: dateKey,
      weatherSignature: weatherSignature,
      wardrobeSignature: wardrobeSignature,
    )) {
      _logHomeDayCacheHitOnce(dayLabel);
    } else {
      _logHomeDayCacheMissOnce(dayLabel);
    }

    await _ensureDailyOutfit(
      date: date,
      wardrobe: wardrobe,
      isPremiumUser: isPremiumUser,
    );

    if (dayLabel == 'today') {
      logVerboseHome('[HOME_PRELOAD] ensure_today done');
    } else {
      logVerboseHome('[HOME_PRELOAD] ensure_tomorrow done');
    }
  }

  Future<void> _ensureDailyOutfit({
    required DateTime date,
    required List<Map<String, dynamic>> wardrobe,
    required bool isPremiumUser,
  }) async {
    if (!_weatherLoaded || wardrobe.isEmpty) return;
    final weather = _weatherForDate(date);
    _maybeTriggerHomeAiRecommendation(
      date: date,
      wardrobe: wardrobe,
      weather: weather,
      isPremiumUser: isPremiumUser,
    );
  }

  String _dayLabelForDateKey(String dateKey) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (dateKey == _dateKey(today)) return 'today';
    return 'tomorrow';
  }

  void _logHomeHeroImageMemoryHitOnce(String dayLabel, String itemId) {
    final key = '$dayLabel|$itemId';
    if (!_loggedHomeHeroImageMemoryHits.add(key)) return;
    logVerboseHome('[HOME_HERO_IMAGE] memory_url_hit day=$dayLabel item=$itemId');
  }

  void _logHomeHeroImageMemoryMissOnce(String dayLabel, String itemId) {
    final key = '$dayLabel|$itemId';
    if (!_loggedHomeHeroImageMemoryMisses.add(key)) return;
    logVerboseHome('[HOME_HERO_IMAGE] memory_url_miss day=$dayLabel item=$itemId');
  }

  void _logHomeHeroUsingCachedImagesOnce(String dayLabel) {
    if (!_loggedHomeHeroUsingCachedImages.add(dayLabel)) return;
    logVerboseHome('[HOME_HERO_RENDER] using_cached_images=true day=$dayLabel');
  }

  String? _cachedHomeImageUrlForItem(String dateKey, String itemId) {
    if (itemId.isEmpty) return null;
    final byItem = _homeImageUrlByDateKeyAndItemId[dateKey];
    final dayCached = byItem?[itemId]?.trim();
    if (dayCached != null && dayCached.isNotEmpty) return dayCached;
    return _lastVisibleHomeImageUrlByItemId[itemId]?.trim();
  }

  String? _heroWardrobeDisplayImageUrlForHome(
    Map<String, dynamic> raw, {
    String? dateKey,
    bool allowPick = true,
  }) {
    final id = OutfitGenerationService.wardrobeItemId(raw);
    if (dateKey != null && id.isNotEmpty) {
      final dayCached = _cachedHomeImageUrlForItem(dateKey, id);
      if (dayCached != null && dayCached.isNotEmpty) {
        return dayCached;
      }
      if (!allowPick) return null;
    }
    return _heroWardrobeDisplayImageUrl(raw, allowPick: allowPick);
  }

  void _refreshMissingHomeImageUrlsInBackground({
    required String dateKey,
    required List<_HeroOutfitItem> items,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    if (items.isEmpty || wardrobe.isEmpty) return;
    final byId = <String, Map<String, dynamic>>{};
    for (final raw in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(raw);
      if (id.isNotEmpty) byId[id] = raw;
    }
    final dayLabel = _dayLabelForDateKey(dateKey);
    for (final item in items) {
      final id = (item.wardrobeItemId ?? '').trim();
      if (id.isEmpty) continue;
      final existing = _cachedHomeImageUrlForItem(dateKey, id);
      if (existing != null && existing.isNotEmpty) continue;
      final raw = byId[id];
      if (raw == null) continue;
      final picked = _heroWardrobeDisplayImageUrlForHome(
        raw,
        dateKey: dateKey,
        allowPick: true,
      );
      if (picked != null && picked.isNotEmpty) {
        _rememberHomeImageUrl(dateKey, id, picked, dayLabel: dayLabel);
      }
    }
  }

  /// Resolves image URLs for AI final-review selections before hero render.
  /// Uses [getHomeOutfitImageUrlOrNull] (same priority as Home hero).
  /// Returns null if any selected item lacks a usable URL.
  List<_HeroOutfitItem>? _hydrateFinalReviewOutfitImages({
    required String dateKey,
    required String dayLabel,
    required List<_HeroOutfitItem> items,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    if (items.isEmpty) {
      debugPrint('[HOME_FINAL_REVIEW_ABORT] reason=missing_image_url');
      return null;
    }

    final byId = <String, Map<String, dynamic>>{};
    for (final raw in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(raw);
      if (id.isNotEmpty) byId[id] = raw;
    }

    final pending = <({ _HeroOutfitItem item, String id, String url })>[];
    var allOk = true;

    for (final item in items) {
      final id = (item.wardrobeItemId ?? '').trim();
      final name = item.label;
      String? resolvedUrl;

      if (id.isNotEmpty) {
        final cached = _cachedHomeImageUrlForItem(dateKey, id);
        if (cached != null && cached.isNotEmpty) {
          resolvedUrl = cached;
        } else {
          final raw = byId[id];
          if (raw != null) {
            resolvedUrl = getHomeOutfitImageUrlOrNull(raw);
          }
        }
      }

      final existing = item.imageUrl?.trim();
      if ((resolvedUrl == null || resolvedUrl.isEmpty) &&
          existing != null &&
          existing.isNotEmpty) {
        resolvedUrl = existing;
      }

      final success = resolvedUrl != null && resolvedUrl.isNotEmpty;
      debugPrint(
        '[HOME_FINAL_REVIEW_IMAGE_SYNC] itemId=$id name=$name '
        'resolvedUrl=${success ? resolvedUrl : ''} success=$success',
      );

      if (!success) {
        allOk = false;
        continue;
      }

      pending.add((item: item, id: id, url: resolvedUrl));
    }

    if (!allOk || pending.length < 3) {
      debugPrint('[HOME_FINAL_REVIEW_ABORT] reason=missing_image_url');
      return null;
    }

    final hydrated = <_HeroOutfitItem>[
      for (final entry in pending)
        _heroItemWithDisplayImageUrl(entry.item, entry.url),
    ];

    for (final entry in pending) {
      if (entry.id.isNotEmpty) {
        _rememberHomeImageUrl(dateKey, entry.id, entry.url, dayLabel: dayLabel);
      }
    }

    _syncHomeImageCacheForDateKey(dateKey, hydrated);
    return hydrated;
  }

  _HeroTodayState? _renderHeroStateForDateKey(String dateKey, String dayLabel) {
    final pinned = _daySwitchPinnedHeroByDateKey[dateKey];
    if (pinned != null && _heroOutfitTilesHaveVisibleImages(pinned.outfitItems)) {
      _logHomeDayCacheMemoryHitOnce(dayLabel);
      _logHomeHeroUsingCachedImagesOnce(dayLabel);
      return pinned;
    }
    final hydrated = _homeHydratedOutfitItemsByDateKey[dateKey];
    if (hydrated != null &&
        hydrated.length >= 3 &&
        _heroOutfitTilesHaveVisibleImages(hydrated)) {
      _logHomeDayCacheMemoryHitOnce(dayLabel);
      _logHomeHeroUsingCachedImagesOnce(dayLabel);
      final cache = _homeDayHeroCacheByDateKey[dateKey];
      final sticky = _stickyVisibleHeroByDateKey[dateKey];
      return _HeroTodayState(
        vm: cache?.state.vm ??
            sticky?.vm ??
            const _HeroBannerVM(description: ''),
        outfitItems: List<_HeroOutfitItem>.from(hydrated),
        source: cache?.state.source ?? sticky?.source ?? 'cached',
      );
    }
    final sticky = _stickyVisibleHeroByDateKey[dateKey];
    if (sticky != null && _heroOutfitTilesHaveVisibleImages(sticky.outfitItems)) {
      _logHomeDayCacheMemoryHitOnce(dayLabel);
      _logHomeHeroUsingCachedImagesOnce(dayLabel);
      return sticky;
    }
    return null;
  }

  void _clearDaySwitchPinnedHero(String dateKey) {
    _daySwitchPinnedHeroByDateKey.remove(dateKey);
  }

  void _rememberHomeImageUrl(
    String dateKey,
    String itemId,
    String url, {
    required String dayLabel,
  }) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    _homeImageUrlByDateKeyAndItemId.putIfAbsent(dateKey, () => <String, String>{})[itemId] =
        trimmed;
    _lastVisibleHomeImageUrlByItemId[itemId] = trimmed;
    _homeHeroNetworkImageLoadedUrls.add(trimmed);
  }

  void _syncHomeImageCacheForDateKey(String dateKey, List<_HeroOutfitItem> items) {
    final ids = <String>[
      for (final it in items)
        if ((it.wardrobeItemId ?? '').trim().isNotEmpty)
          (it.wardrobeItemId ?? '').trim(),
    ]..sort();
    final sig = ids.join('|');
    if (_homeOutfitIdsSignatureByDateKey[dateKey] != sig) {
      _homeOutfitIdsSignatureByDateKey[dateKey] = sig;
      final keep = ids.toSet();
      final byItem = _homeImageUrlByDateKeyAndItemId[dateKey];
      byItem?.removeWhere((id, _) => !keep.contains(id));
    }
    final dayLabel = _dayLabelForDateKey(dateKey);
    for (final item in items) {
      final id = (item.wardrobeItemId ?? '').trim();
      if (id.isEmpty) continue;
      final url = item.imageUrl?.trim();
      if (url != null && url.isNotEmpty) {
        _rememberHomeImageUrl(dateKey, id, url, dayLabel: dayLabel);
      }
    }
  }

  ({String? url, bool fromMemory}) _resolveHomeOutfitDisplayImageUrlWithMeta({
    required String dateKey,
    required String dayLabel,
    required _HeroOutfitItem item,
  }) {
    final id = (item.wardrobeItemId ?? '').trim();
    final byItem = _homeImageUrlByDateKeyAndItemId[dateKey];
    final memory =
        id.isNotEmpty && byItem != null ? byItem[id]?.trim() : null;

    final current = item.imageUrl?.trim();
    if (current != null && current.isNotEmpty) {
      if (id.isNotEmpty) {
        _rememberHomeImageUrl(dateKey, id, current, dayLabel: dayLabel);
      } else {
        _homeHeroNetworkImageLoadedUrls.add(current);
      }
      return (url: current, fromMemory: false);
    }

    if (memory != null && memory.isNotEmpty) {
      _logHomeHeroImageMemoryHitOnce(dayLabel, id);
      _homeHeroNetworkImageLoadedUrls.add(memory);
      return (url: memory, fromMemory: true);
    }

    if (id.isNotEmpty) {
      final last = _lastVisibleHomeImageUrlByItemId[id]?.trim();
      if (last != null && last.isNotEmpty) {
        _rememberHomeImageUrl(dateKey, id, last, dayLabel: dayLabel);
        return (url: last, fromMemory: false);
      }
      _logHomeHeroImageMemoryMissOnce(dayLabel, id);
    }
    return (url: null, fromMemory: false);
  }

  String? _resolveHomeOutfitDisplayImageUrl({
    required String dateKey,
    required String dayLabel,
    required _HeroOutfitItem item,
  }) {
    return _resolveHomeOutfitDisplayImageUrlWithMeta(
      dateKey: dateKey,
      dayLabel: dayLabel,
      item: item,
    ).url;
  }

  _HeroOutfitItem _heroItemWithDisplayImageUrl(
    _HeroOutfitItem item,
    String? displayUrl,
  ) {
    return _HeroOutfitItem(
      type: item.type,
      icon: item.icon,
      label: item.label,
      brandLine: item.brandLine,
      imageUrl: displayUrl,
      categoryKey: item.categoryKey,
      subCategoryKey: item.subCategoryKey,
      wardrobeItemId: item.wardrobeItemId,
      imageProcessing: item.imageProcessing,
    );
  }

  List<_HeroOutfitItem> _heroItemsFromCachedUrlsOnly({
    required String dateKey,
    required String dayLabel,
    required List<_HeroOutfitItem> items,
    bool logUsingCached = true,
  }) {
    if (logUsingCached && items.isNotEmpty) {
      _logHomeHeroUsingCachedImagesOnce(dayLabel);
    }
    _syncHomeImageCacheForDateKey(dateKey, items);
    return [
      for (final item in items)
        _heroItemWithDisplayImageUrl(
          item,
          _resolveHomeOutfitDisplayImageUrl(
            dateKey: dateKey,
            dayLabel: dayLabel,
            item: item,
          ),
        ),
    ];
  }

  List<_HeroOutfitItem> _heroItemsWithStableImageUrls({
    required String dateKey,
    required String dayLabel,
    required List<_HeroOutfitItem> items,
  }) {
    if (_heroOutfitTilesHaveVisibleImages(items)) {
      return items;
    }
    return _heroItemsFromCachedUrlsOnly(
      dateKey: dateKey,
      dayLabel: dayLabel,
      items: items,
      logUsingCached: false,
    );
  }

  _HeroTodayState _heroTodayStateWithStableImages(
    String dateKey,
    _HeroTodayState state,
  ) {
    final dayLabel = _dayLabelForDateKey(dateKey);
    final items = _heroItemsWithStableImageUrls(
      dateKey: dateKey,
      dayLabel: dayLabel,
      items: state.outfitItems,
    );
    return _HeroTodayState(
      vm: state.vm,
      outfitItems: items,
      source: state.source,
      loadingReason: state.loadingReason,
    );
  }

  void _persistHomeHydratedOutfit(String dateKey, _HeroTodayState state) {
    if (!_heroStateHasValidOutfit(state)) return;
    final dayLabel = _dayLabelForDateKey(dateKey);
    final hydrated = _heroOutfitTilesHaveVisibleImages(state.outfitItems)
        ? state
        : _heroTodayStateWithStableImages(dateKey, state);
    final items = _heroOutfitTilesHaveVisibleImages(hydrated.outfitItems)
        ? hydrated.outfitItems
        : _heroItemsFromCachedUrlsOnly(
            dateKey: dateKey,
            dayLabel: dayLabel,
            items: hydrated.outfitItems,
            logUsingCached: false,
          );
    final stored = _HeroTodayState(
      vm: hydrated.vm,
      outfitItems: items,
      source: hydrated.source,
      loadingReason: hydrated.loadingReason,
    );
    _homeHydratedOutfitItemsByDateKey[dateKey] = items;
    _stickyVisibleHeroByDateKey[dateKey] = stored;
  }

  _HeroTodayState? _instantHeroStateForDateKey(String dateKey) {
    final sticky = _stickyVisibleHeroByDateKey[dateKey];
    if (sticky != null && _heroStateHasValidOutfit(sticky)) {
      return sticky;
    }
    final hydrated = _homeHydratedOutfitItemsByDateKey[dateKey];
    if (hydrated != null && hydrated.length >= 3) {
      final cache = _homeDayHeroCacheByDateKey[dateKey];
      return _HeroTodayState(
        vm: cache?.state.vm ??
            sticky?.vm ??
            const _HeroBannerVM(description: ''),
        outfitItems: hydrated,
        source: cache?.state.source ?? sticky?.source ?? 'cached',
      );
    }
    final cache = _homeDayHeroCacheByDateKey[dateKey];
    if (cache != null && _heroStateHasValidOutfit(cache.state)) {
      return _heroTodayStateWithStableImages(dateKey, cache.state);
    }
    return null;
  }

  bool _heroOutfitTilesHaveVisibleImages(List<_HeroOutfitItem> items) {
    if (items.isEmpty) return false;
    final withUrl =
        items.where((i) => (i.imageUrl?.trim().isNotEmpty ?? false)).length;
    return withUrl >= 3 || withUrl == items.length;
  }

  _HeroTodayState _finalizeHeroState({
    required String dateKey,
    required _HeroTodayState state,
  }) {
    var resolved = state;
    if (!_heroStateHasValidOutfit(resolved)) {
      final instant = _instantHeroStateForDateKey(dateKey);
      if (instant != null) resolved = instant;
    } else {
      resolved = _heroTodayStateWithStableImages(dateKey, resolved);
    }
    if (_heroStateHasValidOutfit(resolved)) {
      _persistHomeHydratedOutfit(dateKey, resolved);
      if (mounted) {
        _precacheHomeOutfitImages(resolved.outfitItems);
      }
      return resolved;
    }
    if (state.source == 'loading') {
      return _instantHeroStateForDateKey(dateKey) ?? resolved;
    }
    return resolved;
  }

  void _precacheHomeOutfitImages(List<_HeroOutfitItem> items) {
    if (!mounted) return;
    final ctx = context;
    for (final item in items) {
      final url = item.imageUrl?.trim();
      if (url == null || url.isEmpty) continue;
      if (!_homeHeroImagePrecacheScheduled.add(url)) continue;
      unawaited(
        precacheImage(NetworkImage(url), ctx).then((_) {
          _homeHeroNetworkImageLoadedUrls.add(url);
        }),
      );
    }
  }

  void _logHomeAiOutfitOnce(String message) {
    if (_lastHomeAiOutfitLogKey == message) return;
    _lastHomeAiOutfitLogKey = message;
    debugPrint(message);
  }

  _HeroTodayState _buildTodayHero({
    required DateTime date,
    required List<Map<String, dynamic>> wardrobe,
    required bool isPremiumUser,
    bool dataReady = true,
  }) {
    final dayIdx = _dayIndexForDate(date);
    final dateKey = _dateKey(date);
    final previousBuildDateKey = _currentHeroBuildDateKey;
    _currentHeroBuildDateKey = dateKey;
    try {
      return _buildTodayHeroInner(
        date: date,
        wardrobe: wardrobe,
        isPremiumUser: isPremiumUser,
        dataReady: dataReady,
        dayIdx: dayIdx,
        dateKey: dateKey,
      );
    } finally {
      _currentHeroBuildDateKey = previousBuildDateKey;
    }
  }

  _HeroTodayState _buildTodayHeroInner({
    required DateTime date,
    required List<Map<String, dynamic>> wardrobe,
    required bool isPremiumUser,
    required bool dataReady,
    required int dayIdx,
    required String dateKey,
  }) {
    final w = _weatherForDate(date);
    final weatherSignature = _homeWeatherSignature(w);
    final wardrobeSignature = _wardrobeSignature(wardrobe);
    final dayLabel = dayIdx == 0 ? 'today' : 'tomorrow';

    final immediate = _renderHeroStateForDateKey(dateKey, dayLabel);
    if (immediate != null) {
      return _finalizeHeroState(
        dateKey: dateKey,
        state: _heroStateWithRestoredFootwearValidation(
          state: immediate,
          date: date,
          dateKey: dateKey,
          dayIdx: dayIdx,
          dayLabel: dayLabel,
          wardrobe: wardrobe,
          dataReady: dataReady,
        ),
      );
    }

    final cache = _homeDayHeroCacheByDateKey[dateKey];

    if (cache != null && _heroStateHasValidOutfit(cache.state)) {
      _logHomeDayCacheMemoryHitOnce(dayLabel);
      var cacheState = _heroStateWithRestoredFootwearValidation(
        state: cache.state,
        date: date,
        dateKey: dateKey,
        dayIdx: dayIdx,
        dayLabel: dayLabel,
        wardrobe: wardrobe,
        dataReady: dataReady,
      );
      final fixedCache = _homeDayHeroCacheByDateKey[dateKey];
      if (fixedCache?.persistSource == 'restore_footwear_fix') {
        cacheState = fixedCache!.state;
      }
      final hydrated = _homeHydratedOutfitItemsByDateKey[dateKey];
      if (hydrated != null && _heroOutfitTilesHaveVisibleImages(hydrated)) {
        _logHomeHeroUsingCachedImagesOnce(dayLabel);
        final hydratedItems = dataReady && wardrobe.isNotEmpty
            ? cacheState.outfitItems
            : hydrated;
        return _finalizeHeroState(
          dateKey: dateKey,
          state: _HeroTodayState(
            vm: cacheState.vm,
            outfitItems: List<_HeroOutfitItem>.from(hydratedItems),
            source: cacheState.source,
          ),
        );
      }
      return _finalizeHeroState(dateKey: dateKey, state: cacheState);
    }

    final instant = _instantHeroStateForDateKey(dateKey);
    if (instant != null) {
      if (_heroOutfitTilesHaveVisibleImages(instant.outfitItems)) {
        return instant;
      }
      return _finalizeHeroState(dateKey: dateKey, state: instant);
    }

    var manualItems = _editedOutfitByDay[dayIdx] ?? const <_HeroOutfitItem>[];
    final isManual = (_editedManuallyByDay[dayIdx] ?? false) && manualItems.isNotEmpty;
    if (isManual) {
      if (dataReady && wardrobe.isNotEmpty) {
        manualItems = _applyRestoredFootwearValidationIfNeeded(
          dateKey: dateKey,
          date: date,
          dayIdx: dayIdx,
          dayLabel: dayLabel,
          items: manualItems,
          wardrobe: wardrobe,
        );
      }
      final reason = _regenerateStylistReason(
        date: date,
        outfitItems: manualItems,
        source: 'swap',
        wardrobe: wardrobe,
      );
      final state = _HeroTodayState(
        vm: _HeroBannerVM(
          description:
              reason.isNotEmpty ? reason : 'Upravený outfit pre tento deň.',
        ),
        outfitItems: manualItems,
        source: 'edited',
      );
      _writeHomeDayHeroCacheIfChanged(
        dateKey: dateKey,
        state: state,
        weatherSignature: weatherSignature,
        wardrobeSignature: wardrobeSignature,
        userModified: true,
        persistSource: 'manual_replaced',
      );
      return _finalizeHeroState(dateKey: dateKey, state: state);
    }
    final swapVisibleItems = _editedOutfitByDay[dayIdx] ?? const <_HeroOutfitItem>[];
    if (_isOutfitEditMode && swapVisibleItems.isNotEmpty) {
      final state = _HeroTodayState(
        vm: const _HeroBannerVM(description: 'Vyber kúsok, ktorý chceš vymeniť.'),
        outfitItems: swapVisibleItems,
        source: 'edited',
      );
      _writeHomeDayHeroCacheIfChanged(
        dateKey: dateKey,
        state: state,
        weatherSignature: weatherSignature,
        wardrobeSignature: wardrobeSignature,
        userModified: true,
        persistSource: 'manual_replaced',
      );
      return _finalizeHeroState(dateKey: dateKey, state: state);
    }
    if (_isRestoringHomeCache) {
      final restoringCache = _homeDayHeroCacheByDateKey[dateKey];
      if (restoringCache != null && _heroStateHasValidOutfit(restoringCache.state)) {
        return _finalizeHeroState(dateKey: dateKey, state: restoringCache.state);
      }
    }
    if (!dataReady) {
      final cachedWhileLoading = _renderHeroStateForDateKey(dateKey, dayLabel);
      if (cachedWhileLoading != null) return cachedWhileLoading;
      final instantWhileLoading = _instantHeroStateForDateKey(dateKey);
      if (instantWhileLoading != null) return instantWhileLoading;
      final memCache = _homeDayHeroCacheByDateKey[dateKey];
      if (memCache != null && _heroStateHasValidOutfit(memCache.state)) {
        return _finalizeHeroState(dateKey: dateKey, state: memCache.state);
      }
      if (!_weatherLoaded) {
        return _finalizeHeroState(
          dateKey: dateKey,
          state: _HeroTodayState(
            vm: const _HeroBannerVM(description: 'Pripravujem dnešný outfit...'),
            outfitItems: const <_HeroOutfitItem>[],
            source: 'loading',
            loadingReason: 'wardrobe_or_weather_pending',
          ),
        );
      }
      // Weather ready — wait for wardrobe/preload without blanking cached hero.
      return _finalizeHeroState(
        dateKey: dateKey,
        state: _HeroTodayState(
          vm: const _HeroBannerVM(description: 'Pripravujem dnešný outfit...'),
          outfitItems: const <_HeroOutfitItem>[],
          source: 'loading',
          loadingReason: 'wardrobe_pending',
        ),
      );
    }
    final latestAiSignature = _homeAiLatestSignatureByDateKey[dateKey];
    final aiEntry =
        latestAiSignature == null ? null : _homeAiCacheBySignature[latestAiSignature];
    final aiCachedRec = aiEntry?.recommendation;
    final aiPendingForDate = _homeAiRequestInFlight.any(
      (sig) => sig.startsWith('$dateKey|'),
    );
    if (aiCachedRec != null && aiCachedRec.items.length >= 3) {
      if (_lastAiPreservedSignatureLogged != latestAiSignature) {
        _lastAiPreservedSignatureLogged = latestAiSignature;
        debugPrint('[HOME_AI_OUTFIT] ai_result_preserved=true');
      }
      final state = _HeroTodayState(
        vm: _HeroBannerVM(description: aiCachedRec.reason),
        outfitItems: aiCachedRec.items,
        source: 'ai',
      );
      _writeHomeDayHeroCacheIfChanged(
        dateKey: dateKey,
        state: state,
        weatherSignature: weatherSignature,
        wardrobeSignature: wardrobeSignature,
        persistSource: 'ai_generated',
      );
      return _finalizeHeroState(dateKey: dateKey, state: state);
    }

    if (aiEntry == null || aiPendingForDate) {
      final cachedWhilePending = _renderHeroStateForDateKey(dateKey, dayLabel);
      if (cachedWhilePending != null) return cachedWhilePending;
      return _finalizeHeroState(
        dateKey: dateKey,
        state: _HeroTodayState(
          vm: const _HeroBannerVM(description: 'Pripravujem dnešný outfit...'),
          outfitItems: const <_HeroOutfitItem>[],
          source: 'loading',
          loadingReason: 'ai_pending_no_cached_ai',
        ),
      );
    }

    if (_skipHomeImagePickForDateKey(dateKey)) {
      final cachedBeforePick = _renderHeroStateForDateKey(dateKey, dayLabel);
      if (cachedBeforePick != null) return cachedBeforePick;
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
      _writeHomeDayHeroCacheIfChanged(
        dateKey: dateKey,
        state: state,
        weatherSignature: weatherSignature,
        wardrobeSignature: wardrobeSignature,
      );
      return _finalizeHeroState(dateKey: dateKey, state: state);
    }

    final state = _HeroTodayState(
      vm: _HeroBannerVM(
        description: rec.reason,
      ),
      outfitItems: rec.items,
      source: 'local',
    );
    _writeHomeDayHeroCacheIfChanged(
      dateKey: dateKey,
      state: state,
      weatherSignature: weatherSignature,
      wardrobeSignature: wardrobeSignature,
      persistSource: 'fallback',
    );
    if (_isPendingAiStylistReason(rec.reason)) {
      unawaited(
        _refreshStylistReasonInBackground(
          date: date,
          outfitItems: rec.items,
          source: 'local_fallback',
          wardrobe: wardrobe,
        ),
      );
    }
    unawaited(
      _maybeRunStylistFinalReviewForDateKey(
        dateKey: dateKey,
        dayLabel: dayLabel,
        wardrobe: wardrobe,
        w: w,
        isPremiumUser: isPremiumUser,
        weatherSignature: weatherSignature,
        wardrobeSignature: wardrobeSignature,
      ),
    );
    return _finalizeHeroState(dateKey: dateKey, state: state);
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
    final targetDayIdx = _dayIndexForDate(date);
    final dayLabel = targetDayIdx == 0 ? 'today' : 'tomorrow';
    if (_editedManuallyByDay[targetDayIdx] == true) {
      final manualItems =
          _editedOutfitByDay[targetDayIdx] ?? const <_HeroOutfitItem>[];
      if (manualItems.isNotEmpty) {
        _logHomeAiOutfitOnce(
          '[HOME_AI_OUTFIT] skip_generate reason=user_modified_cache_hit',
        );
        return;
      }
    }
    final cached = _homeDayHeroCacheByDateKey[dateKey];
    if (cached != null &&
        cached.userModified &&
        cached.weatherSignature == weatherSignature &&
        _heroStateHasValidOutfit(cached.state)) {
      _logHomeAiOutfitOnce(
        '[HOME_AI_OUTFIT] skip_generate reason=user_modified_cache_hit',
      );
      return;
    }
    if (_hasValidDailyOutfitForDate(
      dateKey: dateKey,
      weatherSignature: weatherSignature,
      wardrobeSignature: wardrobeSignature,
    )) {
      _logHomeAiOutfitOnce(
        '[HOME_AI_OUTFIT] skip_generate reason=cache_hit day=$dayLabel',
      );
      return;
    }
    final existing = _editedOutfitByDay[targetDayIdx] ?? const <_HeroOutfitItem>[];
    if (_isOutfitEditMode && existing.isNotEmpty) {
      _logHomeAiOutfitOnce('[HOME_AI_OUTFIT] skip reason=swap_mode_existing_outfit');
      return;
    }
    final forceDifferent =
        (_homeAiForceDifferentNextByDateKey[dateKey] ?? false) == true;
    if (_generatingDateKeys.contains(dateKey)) {
      _logHomeAiOutfitOnce('[HOME_AI_OUTFIT] skip reason=generation_in_progress');
      return;
    }
    if (_homeAiRequestInFlight.any((sig) => sig.startsWith('$dateKey|'))) {
      _logHomeAiOutfitOnce('[HOME_AI_OUTFIT] skip reason=generation_in_progress');
      return;
    }
    final aiSignature =
        '$dateKey|$weatherSignature|$wardrobeSignature|fd=${forceDifferent ? 1 : 0}|n=$_homeAiRefreshNonce';
    final excluded = <String>{};
    final rejected =
        Set<String>.from(_rejectedOutfitCombinationKeysByDay[targetDayIdx] ?? {});

    final effectiveCurrent = _editedOutfitByDay[targetDayIdx] ?? const <_HeroOutfitItem>[];
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

    if (_validAiRecommendationForSignature(aiSignature) != null) {
      _homeAiLatestSignatureByDateKey[dateKey] = aiSignature;
      _logHomeAiOutfitOnce(
        '[HOME_AI_OUTFIT] skip_generate reason=cache_hit day=$dayLabel',
      );
      return;
    }

    if (_homeAiCacheBySignature.containsKey(aiSignature)) {
      _homeAiCacheBySignature.remove(aiSignature);
    }

    _logHomeAiOutfitOnce(
      '[HOME_AI_OUTFIT] generate reason=cache_missing day=$dayLabel',
    );
    _generatingDateKeys.add(dateKey);

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
      final dayLabel = targetDayIndex == 0 ? 'today' : 'tomorrow';
      final displayed = _editedOutfitByDay[targetDayIndex] ?? const <_HeroOutfitItem>[];
      final displayedDiffers = !_sameHeroItemsById(displayed, rec.items);
      final footwearPrepared = _validateAndReplaceRestoredFootwear(
        date: request.date,
        dateKey: dateKey,
        dayLabel: dayLabel,
        items: rec.items,
        wardrobe: wardrobe,
      );
      if (footwearPrepared.abortedDueToMissingImage) {
        debugPrint(
          '[HOME_AI_OUTFIT] skip_apply reason=discouraged_footwear_missing_replacement_image '
          'day=$dayLabel',
        );
        if (!mounted) return;
        setState(() {
          _homeAiCacheBySignature[aiSignature] = _HomeAiCacheEntry(
            signature: aiSignature,
            recommendation: rec,
          );
          _homeAiLatestSignatureByDateKey[dateKey] = aiSignature;
          _homeAiForceDifferentNextByDateKey[dateKey] = false;
        });
        return;
      }
      final preparedItems = footwearPrepared.items;
      final footwearReplaced = footwearPrepared.replaced;
      if (!footwearPrepared.abortedDueToMissingImage) {
        _restoredFootwearValidatedKeys.add(
          '$dateKey|${_homeWeatherSignature(_weatherForDate(request.date))}',
        );
      }
      if (!mounted) return;
      if ((_editedManuallyByDay[targetDayIndex] ?? false) && displayedDiffers) {
        debugPrint(
          '[HOME_AI_OUTFIT] skip_apply reason=user_modified_outfit '
          'displayedIds=${displayed.map((e) => e.wardrobeItemId).whereType<String>().where((e) => e.isNotEmpty).join(",")}',
        );
        setState(() {
          _homeAiCacheBySignature[aiSignature] = _HomeAiCacheEntry(
            signature: aiSignature,
            recommendation: rec,
          );
          _homeAiLatestSignatureByDateKey[dateKey] = aiSignature;
          _homeAiForceDifferentNextByDateKey[dateKey] = false;
        });
        return;
      }
      final preparedDiffers = !_sameHeroItemsById(rec.items, preparedItems);
      if (!sameAsCached || displayedDiffers || preparedDiffers) {
        debugPrint('[HOME_STYLIST_REASON] regenerated=true');
        debugPrint('[HOME_STYLIST_REASON] source=ai_refresh');
        debugPrint(
          '[HOME_STYLIST_REASON] currentOutfitIds=${preparedItems.map((e) => e.wardrobeItemId).whereType<String>().where((e) => e.isNotEmpty).join(",")}',
        );
        final preparedRec = _HeroOutfitRecommendation(
          reason: rec.reason,
          items: preparedItems,
        );
        final heroSource = footwearReplaced ? 'edited' : 'ai';
        final persistSource =
            footwearReplaced ? 'restore_footwear_fix' : 'ai_generated';
        final userModified = footwearReplaced;
        final savedAt = DateTime.now();
        setState(() {
          _homeAiCacheBySignature[aiSignature] = _HomeAiCacheEntry(
            signature: aiSignature,
            recommendation: preparedRec,
          );
          _homeAiLatestSignatureByDateKey[dateKey] = aiSignature;
          _homeAiForceDifferentNextByDateKey[dateKey] = false;
          _editedManuallyByDay[targetDayIndex] = userModified;
          _editedOutfitByDay[targetDayIndex] =
              List<_HeroOutfitItem>.from(preparedItems);
          _lastSourceSignatureByDay[targetDayIndex] =
              _heroRenderSignature(preparedItems);
          _homeDayHeroCacheByDateKey[dateKey] = _HomeDayHeroCacheEntry(
            state: _HeroTodayState(
              vm: _HeroBannerVM(description: rec.reason),
              outfitItems: preparedItems,
              source: heroSource,
            ),
            weatherSignature: _homeWeatherSignature(request.weather),
            wardrobeSignature: _wardrobeSignature(wardrobe),
            userModified: userModified,
            persistSource: persistSource,
            updatedAt: savedAt,
          );
        });
        if (footwearReplaced) {
          _touchHomeDayCacheUpdatedAt(dateKey, savedAt);
          _syncHomeImageCacheForDateKey(dateKey, preparedItems);
          _syncHomeOutfitStateToAllCaches(
            dayIndex: targetDayIndex,
            dateKey: dateKey,
            dayLabel: dayLabel,
            normalized: preparedItems,
            heroState: _HeroTodayState(
              vm: _HeroBannerVM(description: rec.reason),
              outfitItems: preparedItems,
              source: heroSource,
            ),
          );
          _invalidateHomeHeroBuildCache(dateKey: dateKey);
        }
        unawaited(
          _persistDailyOutfitCache(
            date: request.date,
            items: preparedItems,
            reasonText: rec.reason,
            persistSource: persistSource,
            userModified: userModified,
            wardrobe: wardrobe,
            likedOutfitKey: _likedOutfitKeyByDay[targetDayIndex],
            fullReplace: footwearReplaced,
            targetCache: 'daily_firestore',
          ),
        );
        _precacheHomeOutfitImages(preparedItems);
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
      _generatingDateKeys.remove(dateKey);
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

  void _syncWardrobeSnapshotIfChanged({
    required AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap,
    required bool isPremiumUser,
  }) {
    if (!snap.hasData || snap.data == null) return;
    final docs = snap.data!.docs;
    final streamSig = '${docs.length}:${docs.map((d) => d.id).join(",")}';
    if (streamSig == _lastWardrobeStreamSig) return;
    final hadWardrobe = _lastWardrobeForCache.isNotEmpty;
    _lastWardrobeStreamSig = streamSig;
    _lastWardrobeForCache = docs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      m['id'] = d.id;
      return m;
    }).toList();
    _normalizedWardrobeForHomeBrain =
        HomeWardrobeNormalizer.normalizeWardrobeForHome(_lastWardrobeForCache);
    _lastIsPremiumUser = isPremiumUser;
    _invalidateHomeHeroBuildCache();
    if (!hadWardrobe && _lastWardrobeForCache.isNotEmpty) {
      _persistedDailyHydrationDone = false;
      _homePreloadPassCompleted = false;
      _homePreloadRanChecks = false;
    }
    _debugHomeBootState(force: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tryScheduleHomeOutfitPreload();
    });
  }

  _HeroTodayState _resolveHomeHero({
    required DateTime activeDate,
    required List<Map<String, dynamic>> wardrobe,
    required bool isPremiumUser,
    required bool dataReady,
  }) {
    final dayIdx = _dayIndexForDate(activeDate);
    final editedSig = (_editedManuallyByDay[dayIdx] ?? false)
        ? _heroRenderSignature(_editedOutfitByDay[dayIdx] ?? const [])
        : '';
    final dateKey = _dateKey(activeDate);
    final buildKey =
        '$dateKey|${_wardrobeSignature(wardrobe)}|$_weatherLoaded|$_homeAiRefreshNonce|ready=$dataReady|edit=$editedSig';
    final cachedKey = _cachedHeroBuildKeyByDateKey[dateKey];
    final cachedState = _cachedHeroBuildStateByDateKey[dateKey];
    if (cachedKey == buildKey && cachedState != null) {
      return cachedState;
    }
    final hero = _buildTodayHero(
      date: activeDate,
      wardrobe: wardrobe,
      isPremiumUser: isPremiumUser,
      dataReady: dataReady,
    );
    if (hero.source != 'loading' || hero.outfitItems.length >= 3) {
      _cachedHeroBuildKeyByDateKey[dateKey] = buildKey;
      _cachedHeroBuildStateByDateKey[dateKey] = hero;
    } else {
      _cachedHeroBuildKeyByDateKey.remove(dateKey);
      _cachedHeroBuildStateByDateKey.remove(dateKey);
    }
    return hero;
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

  List<Map<String, dynamic>> _wardrobeForOutfitGeneration(
    List<Map<String, dynamic>> wardrobe, {
    bool logNormalization = true,
  }) {
    if (_normalizedWardrobeForHomeBrain.isNotEmpty &&
        _wardrobeSignature(wardrobe) == _wardrobeSignature(_lastWardrobeForCache)) {
      return _normalizedWardrobeForHomeBrain;
    }
    return HomeWardrobeNormalizer.normalizeWardrobeForHome(
      wardrobe,
      log: logNormalization,
    );
  }

  List<OutfitPreview> _generateOutfitCandidatePreviews({
    required List<Map<String, dynamic>> wardrobeForGen,
    required OutfitWeatherSnapshot snap,
    ComfortWeatherInput? comfortWeather,
    Set<String> excludedItemIds = const {},
    Set<String> rejectedCombinationSignatures = const {},
    Set<String> previousOutfitItemIds = const {},
    bool forceDifferentOutfit = false,
    int limit = 4,
  }) {
    final comfortInput =
        comfortWeather ?? ComfortWeatherInput.fromOutfitWeatherSnapshot(snap);
    final comfortTarget = ComfortTarget.fromWeather(comfortInput);
    logComfortTarget(
      day: comfortInput.dayLabel,
      target: comfortTarget,
    );

    final footwearGuidance = computeFootwearFamilyGuidance(weather: snap);
    logFootwearFamilyGuidance(weather: snap, guidance: footwearGuidance);

    final footwearInventory =
        footwearFamilyInventoryFromWardrobe(wardrobeForGen);
    final preferredFootwearExists =
        footwearInventory.hasPreferred(footwearGuidance);
    final allowedFootwearExists = footwearInventory.hasAllowed(footwearGuidance);

    final excludedDiscouragedFootwearIds =
        (preferredFootwearExists || allowedFootwearExists)
            ? footwearInventory.idsForDiscouragedFamilies(footwearGuidance).toSet()
            : <String>{};

    final excludeBoots = excludedDiscouragedFootwearIds.isNotEmpty &&
        footwearGuidance.discouragedFamilies
            .contains(FootwearFamily.boots.wireName);
    logFootwearFamilyFilter(
      guidance: footwearGuidance,
      inventory: footwearInventory,
      excludedBoots: excludeBoots,
    );

    final bottomGuidance = computeBottomFamilyGuidance(weather: snap);
    logBottomFamilyGuidance(weather: snap, guidance: bottomGuidance);

    final bottomInventory = bottomFamilyInventoryFromWardrobe(wardrobeForGen);
    final preferredBottomExists = bottomInventory.hasPreferred(bottomGuidance);
    final allowedBottomExists = bottomInventory.hasAllowed(bottomGuidance);

    logBottomFamilyFilter(
      guidance: bottomGuidance,
      inventory: bottomInventory,
      wardrobe: wardrobeForGen,
    );

    final excludedDiscouragedBottomIds =
        (preferredBottomExists || allowedBottomExists)
            ? bottomInventory.idsForDiscouraged(bottomGuidance).toSet()
            : <String>{};

    final effectiveExcluded = <String>{
      ...excludedItemIds,
      ...excludedDiscouragedFootwearIds,
      ...excludedDiscouragedBottomIds,
    };

    logFootwearCanonicalFamilyProbes(guidance: footwearGuidance);
    logBottomCanonicalFamilyProbes(guidance: bottomGuidance);
    logDiscouragedFamilyPoolExclusions(
      wardrobe: wardrobeForGen,
      excludedDiscouragedFootwearIds: excludedDiscouragedFootwearIds,
      excludedDiscouragedBottomIds: excludedDiscouragedBottomIds,
      footwearGuidance: footwearGuidance,
      bottomGuidance: bottomGuidance,
    );
    logPreferredItemsInEffectiveExcluded(
      wardrobe: wardrobeForGen,
      effectiveExcluded: effectiveExcluded,
      callerExcludedItemIds: excludedItemIds,
      excludedDiscouragedFootwearIds: excludedDiscouragedFootwearIds,
      excludedDiscouragedBottomIds: excludedDiscouragedBottomIds,
      footwearGuidance: footwearGuidance,
      bottomGuidance: bottomGuidance,
    );

    final localRejected = Set<String>.from(rejectedCombinationSignatures);

    var generationPassCounter = 0;

    List<OutfitPreview> generateBatch({
      required Set<String> batchExcluded,
      required String passLabel,
    }) {
      final passIndex = generationPassCounter++;
      final pools = OutfitGenerationService.collectGenerationPools(
        wardrobeItems: wardrobeForGen,
        weather: snap,
        excludedItemIds: batchExcluded,
      );
      if (pools != null && kCandidateGenerationAudit) {
        logCandidateGenerationAudit(
          passIndex: passIndex,
          passLabel: passLabel,
          tempC: snap.tempC,
          availableTops: pools.tops,
          availableMidLayers: pools.midLayers,
          availableOuterLayers: pools.outerwear,
          availableBottoms: pools.bottoms,
          availableFootwear: pools.shoes,
          excludedItemIds: batchExcluded,
        );
        logTrackedBottomFootwearPoolStatus(
          wardrobe: wardrobeForGen,
          excludedItemIds: batchExcluded,
          callerExcludedItemIds: excludedItemIds,
          excludedDiscouragedFootwearIds: excludedDiscouragedFootwearIds,
          excludedDiscouragedBottomIds: excludedDiscouragedBottomIds,
          footwearGuidance: footwearGuidance,
          bottomGuidance: bottomGuidance,
          genTops: pools.tops,
          genBottoms: pools.bottoms,
          genFootwear: pools.shoes,
          tempC: snap.tempC,
          passIndex: passIndex,
        );
      }

      final batch = OutfitGenerationService.generateCandidatePreviews(
        wardrobeItems: wardrobeForGen,
        weather: snap,
        excludedItemIds: batchExcluded,
        rejectedCombinationSignatures: localRejected,
        previousItemIds: previousOutfitItemIds,
        forceDifferentOutfit: forceDifferentOutfit,
        limit: limit,
        preferredBottomExists: preferredBottomExists,
        preferredFootwearExists: preferredFootwearExists,
        isPreferredBottom: (p) =>
            previewHasPreferredBottom(preview: p, guidance: bottomGuidance),
        isPreferredFootwear: (p) =>
            previewHasPreferredFootwear(preview: p, guidance: footwearGuidance),
        isDiscouragedBottom: preferredBottomExists
            ? (p) =>
                previewHasDiscouragedBottom(preview: p, guidance: bottomGuidance)
            : null,
        isDiscouragedFootwear: preferredFootwearExists
            ? (p) => previewHasDiscouragedFootwear(
                  preview: p,
                  guidance: footwearGuidance,
                )
            : null,
        passesLayerHarmony: (p) => previewPassesLayerHarmonyGuard(
          preview: p,
          tempC: snap.tempC,
          log: false,
        ),
        comfortBonusScorer: (p) =>
            calculateEffectiveOutfitWarmthForPreview(
              p,
              target: comfortTarget,
            ).comfortScore *
            0.3,
        preferNoOuterWhenComfortable: (p) => shouldPreferNoOuterLayer(
          preview: p,
          target: comfortTarget,
          policy: resolveOuterwearPolicy(
            tempC: snap.tempC,
            isRainy: snap.isRainy,
            isWindy: snap.isWindy,
          ),
          isRainy: snap.isRainy,
          isWindy: snap.isWindy,
        ),
        logOptionalOuterCandidate: (index, preview) {
          final warmth = calculateEffectiveOutfitWarmthForPreview(
            preview,
            target: comfortTarget,
          );
          logOuterOptionalCandidate(
            candidateIndex: index,
            withOuter: preview.outerwear != null,
            eow: warmth.value,
            ct: comfortTarget.value,
            outerLabel: preview.outerwear?.label,
          );
        },
        outerMatrixEowReader: (preview) =>
            calculateEffectiveOutfitWarmthForPreview(
              preview,
              target: comfortTarget,
            ).value,
        outerMatrixCt: comfortTarget.value,
        outerVariantComfortBands: OuterVariantComfortBands(
          ct: comfortTarget.value,
          tolerance: comfortTarget.tolerance,
          hardMax: comfortTarget.hardMax,
        ),
        auditCandidateGeneration: kCandidateGenerationAudit,
        auditPassIndex: passIndex,
        auditPassLabel: passLabel,
      );

      for (final p in batch) {
        final sig = OutfitGenerationService.combinationSignature(
          p.top.item,
          p.bottom.item,
          p.shoes.item,
          p.outerwear?.item,
        );
        if (sig.isNotEmpty) {
          localRejected.add(sig);
        }
      }
      return batch;
    }

    var candidatePreviews = generateBatch(
      batchExcluded: effectiveExcluded,
      passLabel: 'initial_batch',
    );
    if (candidatePreviews.isEmpty) {
      final heavyOuterExclude = layerHarmonyExcludedOuterIdsForRegeneration(
        wardrobe: wardrobeForGen,
        tempC: snap.tempC,
      );
      if (heavyOuterExclude.isNotEmpty) {
        debugPrint(
          '[LAYER_HARMONY_GUARD] regenerate reason=all_rejected '
          'excludedHeavyOuter=${heavyOuterExclude.length}',
        );
        candidatePreviews = generateBatch(
          batchExcluded: {...effectiveExcluded, ...heavyOuterExclude},
          passLabel: 'regenerate_without_heavy_outer',
        );
      }
    }

    var filtered = candidatePreviews;
    if (preferredFootwearExists) {
      filtered = filtered
          .where(
            (p) => !previewHasDiscouragedFootwear(
              preview: p,
              guidance: footwearGuidance,
            ),
          )
          .toList();
    }
    if (preferredBottomExists) {
      filtered = filtered
          .where(
            (p) => !previewHasDiscouragedBottom(
              preview: p,
              guidance: bottomGuidance,
            ),
          )
          .toList();
    }
    filtered = filtered
        .where(
          (p) => previewPassesLayerHarmonyGuard(
            preview: p,
            tempC: snap.tempC,
            log: false,
          ),
        )
        .toList(growable: false);
    // Keď je nejaká rodina spodku PREFEROVANÁ pre dané počasie/sezónu (napr.
    // v lete kraťasy), nech ju ponúkneme namiesto dlhých nohavíc – rovnako ako
    // v Stylist chate. Bez tohto by pri 19 °C v lete vyhrali nohavice cez comfort.
    if (preferredBottomExists) {
      final preferredOnly = filtered
          .where(
            (p) => previewHasPreferredBottom(
              preview: p,
              guidance: bottomGuidance,
            ),
          )
          .toList(growable: false);
      if (preferredOnly.isNotEmpty) filtered = preferredOnly;
    }
    final result = filtered.take(limit).toList(growable: false);
    if (kCandidateGenerationAudit) {
      logFinalCandidateAbsence(
        wardrobe: wardrobeForGen,
        usedBottomIds: result
            .map((p) => OutfitGenerationService.wardrobeItemId(p.bottom.item))
            .where((id) => id.isNotEmpty)
            .toSet(),
        usedShoeIds: result
            .map((p) => OutfitGenerationService.wardrobeItemId(p.shoes.item))
            .where((id) => id.isNotEmpty)
            .toSet(),
        passIndex: generationPassCounter,
      );
      for (var i = 0; i < result.length; i++) {
        logCandidateBuild(
          candidateIndex: i,
          selectedTop: result[i].top.label,
          selectedBottom: result[i].bottom.label,
          selectedFootwear: result[i].shoes.label,
          selectedOuter: result[i].outerwear?.label,
          selectionReason: 'final_candidate_set_after_filters',
        );
      }
    }
    for (var i = 0; i < result.length; i++) {
      final warmth = calculateEffectiveOutfitWarmthForPreview(
        result[i],
        target: comfortTarget,
      );
      logComfortCandidate(
        index: i,
        preview: result[i],
        target: comfortTarget,
        warmth: warmth,
      );
    }
    return result;
  }

  OutfitPreview? _generatePreferredFootwearFallbackPreview({
    required List<Map<String, dynamic>> wardrobeForGen,
    required OutfitWeatherSnapshot snap,
    required FootwearFamilyGuidance guidance,
    required FootwearFamilyInventory inventory,
    Set<String> excludedItemIds = const {},
    Set<String> rejectedCombinationSignatures = const {},
    Set<String> previousOutfitItemIds = const {},
    bool forceDifferentOutfit = false,
  }) {
    final preferredShoeIds =
        inventory.idsForPreferredFamilies(guidance).toSet();
    if (preferredShoeIds.isEmpty) return null;
    return OutfitGenerationService.generatePreview(
      wardrobeItems: wardrobeForGen,
      weather: snap,
      excludedItemIds: excludedItemIds,
      rejectedCombinationSignatures: rejectedCombinationSignatures,
      previousItemIds: previousOutfitItemIds,
      forceDifferentOutfit: forceDifferentOutfit,
      allowedShoeItemIds: preferredShoeIds,
    );
  }

  OutfitPreview? _generatePreferredBottomFallbackPreview({
    required List<Map<String, dynamic>> wardrobeForGen,
    required OutfitWeatherSnapshot snap,
    required BottomFamilyGuidance guidance,
    required BottomFamilyInventory inventory,
    Set<String> excludedItemIds = const {},
    Set<String> rejectedCombinationSignatures = const {},
    Set<String> previousOutfitItemIds = const {},
    bool forceDifferentOutfit = false,
  }) {
    final preferredBottomIds = inventory.idsForPreferred(guidance).toSet();
    if (preferredBottomIds.isEmpty) return null;
    return OutfitGenerationService.generatePreview(
      wardrobeItems: wardrobeForGen,
      weather: snap,
      excludedItemIds: excludedItemIds,
      rejectedCombinationSignatures: rejectedCombinationSignatures,
      previousItemIds: previousOutfitItemIds,
      forceDifferentOutfit: forceDifferentOutfit,
      allowedBottomItemIds: preferredBottomIds,
    );
  }

  OutfitPreview? _outfitPreviewWithSwappedShoes({
    required OutfitPreview preview,
    required Map<String, dynamic> newShoeRaw,
  }) {
    final name = (newShoeRaw['name'] ?? '').toString().trim();
    final sub =
        (newShoeRaw['subCategoryKey'] ?? newShoeRaw['subCategory'] ?? '')
            .toString()
            .trim();
    final label = name.isNotEmpty
        ? name
        : (sub.isNotEmpty ? sub : preview.shoes.label);
    final imageUrl = resolveWardrobeImageUrl(newShoeRaw);
    return OutfitPreview(
      top: preview.top,
      bottom: preview.bottom,
      shoes: OutfitPreviewItem(
        type: OutfitWearType.shoes,
        item: newShoeRaw,
        label: label,
        imageUrl: imageUrl?.trim().isNotEmpty == true ? imageUrl : null,
      ),
      outerwear: preview.outerwear,
    );
  }

  OutfitPreview? _tryApplySuggestedFootwearSwap({
    required OutfitPreview preview,
    required Map<String, dynamic> suggestedSwap,
    required List<Map<String, dynamic>> wardrobe,
    required FootwearFamilyGuidance guidance,
  }) {
    final swapOutRaw = suggestedSwap['swapOutItemIds'];
    final swapInRaw = suggestedSwap['swapInItemIds'];
    final swapOutIds = swapOutRaw is List
        ? swapOutRaw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
        : const <String>[];
    final swapInIds = swapInRaw is List
        ? swapInRaw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
        : const <String>[];

    if (swapInIds.isEmpty) return null;

    final currentShoeId =
        OutfitGenerationService.wardrobeItemId(preview.shoes.item);
    if (swapOutIds.isNotEmpty &&
        currentShoeId.isNotEmpty &&
        !swapOutIds.contains(currentShoeId)) {
      return null;
    }

    final byId = <String, Map<String, dynamic>>{};
    for (final raw in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(raw);
      if (id.isNotEmpty) byId[id] = raw;
    }

    for (final swapInId in swapInIds) {
      final raw = byId[swapInId];
      if (raw == null || !isFootwearWardrobeItem(raw)) continue;

      final family = classifyFootwearFamily(raw);
      if (!guidance.isPreferred(family) && !guidance.isAllowed(family)) {
        continue;
      }
      if (guidance.isDiscouraged(family)) continue;

      final imageUrl = getHomeOutfitImageUrlOrNull(raw);
      if (imageUrl == null || imageUrl.trim().isEmpty) {
        debugPrint(
          '[STYLIST_FINAL_REVIEW_SWAP_SKIP] swapInId=$swapInId '
          'reason=missing_image_url',
        );
        continue;
      }

      debugPrint(
        '[STYLIST_FINAL_REVIEW_SWAP] swapOutId=$currentShoeId swapInId=$swapInId '
        'family=${family.wireName}',
      );
      return _outfitPreviewWithSwappedShoes(
        preview: preview,
        newShoeRaw: raw,
      );
    }

    return null;
  }

  Map<String, dynamic> _stylistFinalReviewWeatherContext(_LocalWeather w) {
    return <String, dynamic>{
      'tempC': w.tempC,
      'isRainy': w.isRainy,
      'isWindy': w.isWindy,
      'seasonLabel': w.seasonLabel,
      'morningRainSegment': w.morningRainSegment,
      'afternoonRainSegment': w.afternoonRainSegment,
      'eveningRainSegment': w.eveningRainSegment,
      'morningTempC': w.briefingMorningC,
      'noonTempC': w.briefingAfternoonC,
      'eveningTempC': w.briefingEveningC,
      'rainTimeText': w.rainTimeText,
      'outfitWhyWeatherNote': w.outfitWhyWeatherNote,
    };
  }

  /// Runs AI stylist final review over rule-based candidates; returns selected index.
  Future<
      ({
        int selectedIndex,
        bool fallback,
        String reason,
        Map<String, dynamic>? suggestedSwap,
      })> _runStylistFinalReviewOnPreviews({
    required List<OutfitPreview> candidatePreviews,
    required _LocalWeather weather,
    required OutfitWeatherSnapshot snap,
  }) async {
    String asString(dynamic v) => (v ?? '').toString().trim();
    int? asInt(dynamic v) {
      final n = num.tryParse(v.toString());
      if (n == null) return null;
      return n.toInt();
    }

    List<String> asStringList(dynamic v) {
      if (v is List) {
        return v
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      }
      final s = v?.toString().trim() ?? '';
      if (s.isEmpty) return const <String>[];
      return [s];
    }

    int warmthOf(Map<String, dynamic> it) =>
        asInt(it['warmth_level'] ?? it['warmthLevel']) ?? 0;

    Map<String, dynamic> itemForAi(
      Map<String, dynamic> raw, {
      required String fallbackName,
    }) {
      final id = OutfitGenerationService.wardrobeItemId(raw);
      final name = asString(raw['name']);
      return <String, dynamic>{
        'id': id,
        'name': name.isNotEmpty ? name : fallbackName,
        'canonicalType': asString(raw['canonical_type'] ?? raw['canonicalType']),
        'layerRole': asString(raw['layer_role'] ?? raw['layerRole']),
        'categoryKey': asString(raw['categoryKey'] ?? raw['category']),
        'subCategoryKey': asString(raw['subCategoryKey'] ?? raw['subCategory']),
        'colors': asStringList(raw['colors']),
        'baseColors': asStringList(raw['baseColors']),
        'styles': asStringList(raw['styles']),
        'season': asStringList(raw['seasons'] ?? raw['season']),
        'warmthLevel': warmthOf(raw),
        'formality': asInt(raw['formality']) ?? 0,
      };
    }

    final footwearGuidance = computeFootwearFamilyGuidance(weather: snap);
    logFootwearFamilyGuidance(weather: snap, guidance: footwearGuidance);

    final bottomGuidance = computeBottomFamilyGuidance(weather: snap);
    logBottomFamilyGuidance(weather: snap, guidance: bottomGuidance);

    final harmonySafeCandidates = candidatePreviews
        .where(
          (p) => previewPassesLayerHarmonyGuard(
            preview: p,
            tempC: snap.tempC,
            log: false,
          ),
        )
        .toList(growable: false);
    if (harmonySafeCandidates.length < candidatePreviews.length) {
      debugPrint(
        '[LAYER_HARMONY_GUARD] filtered_before_ai_review '
        'removed=${candidatePreviews.length - harmonySafeCandidates.length}',
      );
    }
    candidatePreviews = harmonySafeCandidates;
    if (candidatePreviews.isEmpty) {
      debugPrint(
        '[STYLIST_FINAL_REVIEW_RESULT] selectedIndex=0 '
        'reason=layer_harmony_rejected_all fallback=true',
      );
      return (
        selectedIndex: 0,
        fallback: true,
        reason: 'layer_harmony_rejected_all',
        suggestedSwap: null,
      );
    }

    debugPrint(
      '[STYLIST_FINAL_REVIEW_REQUEST] candidateCount=${candidatePreviews.length} '
      'weather=${weather.tempC} rain=${weather.isRainy} wind=${weather.isWindy}',
    );

    final comfortTarget =
        ComfortTarget.fromWeather(_comfortWeatherInputFor(weather));
    var bestComfortIndex = 0;
    var bestComfortScore = -1.0;
    for (var i = 0; i < candidatePreviews.length; i++) {
      final warmth = calculateEffectiveOutfitWarmthForPreview(
        candidatePreviews[i],
        target: comfortTarget,
      );
      if (warmth.comfortScore > bestComfortScore) {
        bestComfortScore = warmth.comfortScore;
        bestComfortIndex = i;
      }
    }

    final candidatesPayload = <Map<String, dynamic>>[];
    final ruleScores = <double>[];
    for (var i = 0; i < candidatePreviews.length; i++) {
      final p = candidatePreviews[i];
      final top = p.top.item;
      final bottom = p.bottom.item;
      final shoes = p.shoes.item;
      final outer = p.outerwear?.item;

      final ruleScore = OutfitGenerationService.ruleBasedOutfitScoreForPreview(
        preview: p,
        weather: snap,
      );
      ruleScores.add(ruleScore);
      final consistencyPenalty =
          OutfitGenerationService.consistencyPenaltyForPreview(preview: p);

      final shoeFamily = classifyFootwearFamily(shoes);
      final shoeName = p.shoes.label;
      final bottomFamily = classifyBottomFamily(bottom);
      final bottomName = p.bottom.label;

      final colorsUnion = <String>{
        ...asStringList(top['baseColors'] ?? top['colors']),
        ...asStringList(bottom['baseColors'] ?? bottom['colors']),
        ...asStringList(shoes['baseColors'] ?? shoes['colors']),
        if (outer != null) ...asStringList(outer['baseColors'] ?? outer['colors']),
      }.toList(growable: false);

      debugPrint(
        '[STYLIST_FINAL_REVIEW_CANDIDATE] index=$i '
        'items=${[p.top.label, p.bottom.label, p.shoes.label, if (outer != null) p.outerwear!.label].join(" | ")} '
        'colors=${colorsUnion.join(",")} '
        'warmth=${[warmthOf(top), warmthOf(bottom), warmthOf(shoes), if (outer != null) warmthOf(outer)].join("/")} '
        'ruleScore=${ruleScore.toStringAsFixed(2)} '
        'consistencyPenalty=${consistencyPenalty.toStringAsFixed(2)} '
        'footwearFamily=${shoeFamily.wireName} '
        'footwearName=$shoeName '
        'footwearAllowed=${footwearGuidance.isAllowed(shoeFamily)} '
        'footwearPreferred=${footwearGuidance.isPreferred(shoeFamily)} '
        'bottomFamily=${bottomFamily.wireName} '
        'bottomName=$bottomName '
        'bottomAllowed=${isBottomAllowedForGuidance(bottom, bottomGuidance)} '
        'bottomPreferred=${isBottomPreferredForGuidance(bottom, bottomGuidance)}',
      );

      final bottomPayload = itemForAi(bottom, fallbackName: p.bottom.label);
      bottomPayload['bottomFamily'] = bottomFamily.wireName;
      bottomPayload['familyAllowed'] =
          isBottomAllowedForGuidance(bottom, bottomGuidance);
      bottomPayload['familyPreferred'] =
          isBottomPreferredForGuidance(bottom, bottomGuidance);

      final shoesPayload = itemForAi(shoes, fallbackName: p.shoes.label);
      shoesPayload['footwearFamily'] = shoeFamily.wireName;
      shoesPayload['familyAllowed'] = footwearGuidance.isAllowed(shoeFamily);
      shoesPayload['familyPreferred'] = footwearGuidance.isPreferred(shoeFamily);

      candidatesPayload.add({
        'candidateIndex': i,
        'ruleScore': ruleScore,
        'consistencyPenalty': consistencyPenalty,
        'footwearFamily': shoeFamily.wireName,
        'footwearName': shoeName,
        'familyAllowed': footwearGuidance.isAllowed(shoeFamily),
        'familyPreferred': footwearGuidance.isPreferred(shoeFamily),
        'bottomFamily': bottomFamily.wireName,
        'bottomName': bottomName,
        'bottomAllowed': isBottomAllowedForGuidance(bottom, bottomGuidance),
        'bottomPreferred': isBottomPreferredForGuidance(bottom, bottomGuidance),
        'items': [
          itemForAi(top, fallbackName: p.top.label),
          bottomPayload,
          shoesPayload,
          if (outer != null) itemForAi(outer, fallbackName: p.outerwear!.label),
        ],
      });
    }

    var selectedByRulesIndex = 0;
    for (var i = 1; i < ruleScores.length; i++) {
      if (ruleScores[i] > ruleScores[selectedByRulesIndex]) {
        selectedByRulesIndex = i;
      }
    }
    logComfortReviewSummary(
      candidateCount: candidatePreviews.length,
      bestComfortIndex: bestComfortIndex,
      bestComfortScore: bestComfortScore < 0 ? 0 : bestComfortScore,
      selectedByRulesIndex: selectedByRulesIndex,
      currentFinalReviewCandidateCount: candidatePreviews.length,
    );

    if (candidatePreviews.length < 2) {
      debugPrint(
        '[STYLIST_FINAL_REVIEW_RESULT] selectedIndex=0 '
        'reason=insufficient_candidates fallback=true',
      );
      return (
        selectedIndex: 0,
        fallback: true,
        reason: 'insufficient_candidates',
        suggestedSwap: null,
      );
    }

    HomeStylistFinalReviewResult res;
    try {
      res = await const HomeStylistFinalReviewService()
          .reviewCandidates(
            weatherContext: _stylistFinalReviewWeatherContext(weather),
            candidates: candidatesPayload,
            footwearGuidance: footwearGuidance.toPayload(),
            bottomGuidance: bottomGuidance.toPayload(),
          )
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint(
        '[STYLIST_FINAL_REVIEW_RESULT] selectedIndex=0 '
        'reason=timeout_or_error fallback=true',
      );
      return (
        selectedIndex: 0,
        fallback: true,
        reason: 'timeout_or_error',
        suggestedSwap: null,
      );
    }

    final selectedIndex = res.selectedCandidateIndex;
    final useFallback = res.fallback ||
        selectedIndex < 0 ||
        selectedIndex >= candidatePreviews.length;
    var effectiveIndex =
        useFallback ? 0 : selectedIndex.clamp(0, candidatePreviews.length - 1);

    if (!useFallback) {
      effectiveIndex = applyFootwearFamilyGuard(
        selectedIndex: effectiveIndex,
        candidates: candidatePreviews,
        guidance: footwearGuidance,
        ruleScores: ruleScores,
        weather: snap,
      );
      effectiveIndex = applyBottomFamilyGuard(
        selectedIndex: effectiveIndex,
        candidates: candidatePreviews,
        guidance: bottomGuidance,
        ruleScores: ruleScores,
      );
    }

    debugPrint(
      '[STYLIST_FINAL_REVIEW_RESULT] selectedIndex=$effectiveIndex '
      'reason=${res.reason.replaceAll('\n', ' ')} fallback=${useFallback ? 'true' : 'false'}',
    );

    return (
      selectedIndex: effectiveIndex,
      fallback: useFallback,
      reason: res.reason,
      suggestedSwap: res.suggestedSwap,
    );
  }

  String _specificLocalReasonFromPreview({
    required OutfitPreview preview,
    required _LocalWeather weather,
  }) {
    return _pendingAiStylistReasonText();
  }

  _HeroOutfitRecommendation? _heroRecommendationFromPreview({
    required OutfitPreview preview,
    required _LocalWeather weather,
    required bool isPremiumUser,
  }) {
    final outfitTiles = <_HeroOutfitItem>[
      _heroItemFromOutfitPreview(preview.top),
      _heroItemFromOutfitPreview(preview.bottom),
      _heroItemFromOutfitPreview(preview.shoes),
      if (preview.outerwear != null) _heroItemFromOutfitPreview(preview.outerwear!),
    ];

    if (outfitTiles.length < 3) return null;
    return _HeroOutfitRecommendation(
      items: outfitTiles,
      reason: _specificLocalReasonFromPreview(
        preview: preview,
        weather: weather,
      ),
    );
  }

  List<String> _itemIdsFromOutfitPreview(OutfitPreview preview) {
    final ids = <String>[
      OutfitGenerationService.wardrobeItemId(preview.top.item),
      OutfitGenerationService.wardrobeItemId(preview.bottom.item),
      OutfitGenerationService.wardrobeItemId(preview.shoes.item),
      if (preview.outerwear != null)
        OutfitGenerationService.wardrobeItemId(preview.outerwear!.item),
    ];
    return ids.where((id) => id.isNotEmpty).toList(growable: false);
  }

  String _signatureFromOutfitPreview(OutfitPreview preview) {
    return OutfitGenerationService.combinationSignature(
      preview.top.item,
      preview.bottom.item,
      preview.shoes.item,
      preview.outerwear?.item,
    );
  }

  List<String> _metadataStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    return const <String>[];
  }

  Map<String, dynamic> _stylistExplanationItemPayload(
    OutfitPreviewItem item, {
    required String slot,
  }) {
    final raw = item.item;
    String firstNonEmpty(List<dynamic> values) {
      for (final value in values) {
        final text = (value ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    return <String, dynamic>{
      'slot': slot,
      'id': OutfitGenerationService.wardrobeItemId(raw),
      'displayName': item.label,
      'name': firstNonEmpty([raw['name'], raw['typePretty'], item.label]),
      'category': firstNonEmpty([raw['category'], raw['categoryKey']]),
      'subCategory': firstNonEmpty([
        raw['subCategory'],
        raw['subCategoryKey'],
        raw['canonical_type'],
        raw['canonicalType'],
      ]),
      'colors': _metadataStringList(raw['colors']),
      'baseColors': _metadataStringList(raw['baseColors']),
      'patterns': _metadataStringList(raw['patterns'] ?? raw['pattern']),
      'visualDescription': firstNonEmpty([
        raw['visual_description'],
        raw['visualDescription'],
        raw['description'],
      ]),
      'materialFeel': firstNonEmpty([
        raw['material_feel'],
        raw['materialFeel'],
      ]),
      'vibe': firstNonEmpty([raw['vibe'], raw['styleVibe']]),
      'fit': firstNonEmpty([raw['fit'], raw['silhouette']]),
      'brand': firstNonEmpty([raw['brand']]),
    };
  }

  List<Map<String, dynamic>> _stylistExplanationPayloadFromPreview(
    OutfitPreview preview,
  ) {
    return <Map<String, dynamic>>[
      _stylistExplanationItemPayload(preview.top, slot: 'top'),
      _stylistExplanationItemPayload(preview.bottom, slot: 'bottom'),
      _stylistExplanationItemPayload(preview.shoes, slot: 'shoes'),
      if (preview.outerwear != null)
        _stylistExplanationItemPayload(preview.outerwear!, slot: 'outerwear'),
    ];
  }

  bool _looksLikeUsefulStylistExplanation(String text) {
    final t = text.trim();
    if (t.length < 90) return false;
    final lower = _normalizedScaleToken(t);
    const weakPhrases = [
      'tieto kusky spolu davaju zmysel',
      'jednoducha denna kombinacia',
      'kombinacia moze zostat jednoducha',
      'outfit je vhodny',
      'cisty akcent',
      'cistym akcentom',
    ];
    if (weakPhrases.any((phrase) => lower.contains(phrase))) return false;
    return lower.contains('vzor') ||
        lower.contains('farb') ||
        lower.contains('kontrast') ||
        lower.contains('akcent') ||
        lower.contains('material') ||
        lower.contains('strih') ||
        lower.contains('modr') ||
        lower.contains('cerven') ||
        lower.contains('biel') ||
        lower.contains('cier');
  }

  String _sanitizeStylistExplanationText(String text) {
    var out = text.trim();
    const brandNames = [
      'Nike',
      'Adidas',
      'Puma',
      'Reebok',
      'Converse',
      'Vans',
      'New Balance',
      'Under Armour',
    ];
    for (final brand in brandNames) {
      out = out.replaceAll(' z $brand ', ' od $brand ');
      out = out.replaceAll(' Z $brand ', ' od $brand ');
      out = out.replaceAll(' z $brand,', ' od $brand,');
      out = out.replaceAll(' z $brand.', ' od $brand.');
      out = out.replaceAll(' "z $brand"', ' "od $brand"');
      out = out.replaceAll('"z $brand"', '"od $brand"');
    }
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<String?> _generateAiStylistReasonForPreview({
    required OutfitPreview preview,
    required _LocalWeather weather,
    required String selectedReason,
    Duration timeout = const Duration(seconds: 7),
  }) async {
    try {
      final result = await _stylistExplanationService
          .generateExplanation(
            date: weather.calendarDate,
            weatherContext: _stylistFinalReviewWeatherContext(weather),
            outfitItems: _stylistExplanationPayloadFromPreview(preview),
            selectedReason: selectedReason,
          )
          .timeout(timeout);
      final explanation = _sanitizeStylistExplanationText(result.explanation);
      if (!result.fallback && _looksLikeUsefulStylistExplanation(explanation)) {
        debugPrint(
          '[HOME_STYLIST_REASON_AI] source=cloud length=${explanation.length}',
        );
        return explanation;
      }
      debugPrint('[HOME_STYLIST_REASON_AI] fallback reason=weak_or_empty');
    } catch (e) {
      debugPrint('[HOME_STYLIST_REASON_AI] fallback error=$e');
    }
    return null;
  }

  Future<_StylistFinalReviewSelection?>
  _stylistFinalReviewSelectionFromChosenCandidate({
    required int finalSelectedIndex,
    required OutfitPreview finalSelectedCandidate,
    required _LocalWeather weather,
    required bool isPremiumUser,
    required List<Map<String, dynamic>> wardrobe,
    String selectedReason = '',
  }) async {
    final finalSelectedItemIds =
        _itemIdsFromOutfitPreview(finalSelectedCandidate);
    final finalSelectedSignature =
        _signatureFromOutfitPreview(finalSelectedCandidate);
    final rec = _heroRecommendationFromPreview(
      preview: finalSelectedCandidate,
      weather: weather,
      isPremiumUser: isPremiumUser,
    );
    if (rec == null || rec.items.length < 3) return null;
    final fallbackReason = rec.reason;
    unawaited(
      _refreshStylistReasonInBackground(
        date: weather.calendarDate,
        outfitItems: rec.items,
        source: 'final_review',
        wardrobe: wardrobe,
        selectedReason: selectedReason.isNotEmpty
            ? selectedReason
            : 'Napíš stylistické vysvetlenie pre vybraný outfit.',
      ),
    );
    final selection = _StylistFinalReviewSelection(
      finalSelectedIndex: finalSelectedIndex,
      finalSelectedCandidate: finalSelectedCandidate,
      finalSelectedSignature: finalSelectedSignature,
      finalSelectedItemIds: finalSelectedItemIds,
      heroItems: rec.items,
      reason: fallbackReason,
    );
    debugPrint(
      '[STYLIST_FINAL_REVIEW_SELECTION] index=$finalSelectedIndex '
      'signature=$finalSelectedSignature ids=${finalSelectedItemIds.join(",")}',
    );
    return selection;
  }

  List<_HeroOutfitItem>? _hydrateAndValidateStylistFinalReviewSelection({
    required _StylistFinalReviewSelection selection,
    required String dateKey,
    required String dayLabel,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    final p = selection.finalSelectedCandidate;
    final shoeFamily = classifyFootwearFamily(p.shoes.item);
    final itemNames = [
      p.top.label,
      p.bottom.label,
      p.shoes.label,
      if (p.outerwear != null) p.outerwear!.label,
    ].join(' | ');

    debugPrint(
      '[STYLIST_FINAL_REVIEW_APPLY] selectedIndex=${selection.finalSelectedIndex} '
      'selectedItems=$itemNames '
      'selectedIds=${selection.finalSelectedItemIds.join(",")} '
      'selectedFootwear=${p.shoes.label} '
      'selectedFootwearFamily=${shoeFamily.wireName}',
    );

    final hydrated = _hydrateFinalReviewOutfitImages(
      dateKey: dateKey,
      dayLabel: dayLabel,
      items: selection.heroItems,
      wardrobe: wardrobe,
    );
    if (hydrated == null) return null;

    final actualIds = hydrated
        .map((e) => e.wardrobeItemId)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();
    final expectedIds = List<String>.from(selection.finalSelectedItemIds)..sort();
    if (expectedIds.join('|') != actualIds.join('|')) {
      debugPrint(
        '[STYLIST_FINAL_REVIEW_APPLY_MISMATCH] expectedIds=${expectedIds.join(",")} '
        'actualIds=${actualIds.join(",")} reason=selected_candidate_mismatch',
      );
      return null;
    }
    return hydrated;
  }

  /// Rule-based candidate generation + AI stylist final review.
  Future<_StylistFinalReviewSelection?> _recommendOutfitWithStylistFinalReview({
    required List<Map<String, dynamic>> wardrobe,
    required _LocalWeather weather,
    required bool isPremiumUser,
    Set<String> excludedItemIds = const {},
    Set<String> rejectedCombinationSignatures = const {},
    Set<String> previousOutfitItemIds = const {},
    bool forceDifferentOutfit = false,
  }) async {
    final snap = OutfitWeatherSnapshot(
      tempC: weather.tempC,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
      seasonKey: weather.seasonKey,
    );
    final wardrobeForGen = _wardrobeForOutfitGeneration(wardrobe);
    final footwearGuidance = computeFootwearFamilyGuidance(weather: snap);
    final footwearInventory =
        footwearFamilyInventoryFromWardrobe(wardrobeForGen);
    final preferredFootwearExists =
        footwearInventory.hasPreferred(footwearGuidance);

    final bottomGuidance = computeBottomFamilyGuidance(weather: snap);
    final bottomInventory = bottomFamilyInventoryFromWardrobe(wardrobeForGen);
    final preferredBottomExists = bottomInventory.hasPreferred(bottomGuidance);
    final peerClothingItemIds = _peerDayOutfitItemIdsForDate(
      weather.calendarDate,
      clothingOnly: true,
    );
    final effectiveExcludedItemIds = <String>{
      ...excludedItemIds,
      ...peerClothingItemIds,
    };
    final effectivePreviousOutfitItemIds = <String>{
      ...previousOutfitItemIds,
      ..._peerDayOutfitItemIdsForDate(weather.calendarDate),
    };

    final candidates = _generateOutfitCandidatePreviews(
      wardrobeForGen: wardrobeForGen,
      snap: snap,
      comfortWeather: _comfortWeatherInputFor(weather),
      excludedItemIds: effectiveExcludedItemIds,
      rejectedCombinationSignatures: rejectedCombinationSignatures,
      previousOutfitItemIds: effectivePreviousOutfitItemIds,
      forceDifferentOutfit: forceDifferentOutfit,
    );

    if (candidates.isEmpty) {
      if (!preferredFootwearExists) return null;
      final fallback = _generatePreferredFootwearFallbackPreview(
        wardrobeForGen: wardrobeForGen,
        snap: snap,
        guidance: footwearGuidance,
        inventory: footwearInventory,
        excludedItemIds: effectiveExcludedItemIds,
        rejectedCombinationSignatures: rejectedCombinationSignatures,
        previousOutfitItemIds: effectivePreviousOutfitItemIds,
        forceDifferentOutfit: forceDifferentOutfit,
      );
      if (fallback == null) return null;
      debugPrint(
        '[STYLIST_FINAL_REVIEW_ABORT] reason=only_discouraged_footwear_candidates',
      );
      return await _stylistFinalReviewSelectionFromChosenCandidate(
        finalSelectedIndex: 0,
        finalSelectedCandidate: fallback,
        weather: weather,
        isPremiumUser: isPremiumUser,
        wardrobe: wardrobe,
      );
    }

    final onlyDiscouragedFootwear = preferredFootwearExists &&
        candidates.every(
          (p) => previewHasDiscouragedFootwear(
            preview: p,
            guidance: footwearGuidance,
          ),
        );
    if (onlyDiscouragedFootwear) {
      debugPrint(
        '[STYLIST_FINAL_REVIEW_ABORT] reason=only_discouraged_footwear_candidates',
      );
      final fallback = _generatePreferredFootwearFallbackPreview(
        wardrobeForGen: wardrobeForGen,
        snap: snap,
        guidance: footwearGuidance,
        inventory: footwearInventory,
        excludedItemIds: effectiveExcludedItemIds,
        rejectedCombinationSignatures: rejectedCombinationSignatures,
        previousOutfitItemIds: effectivePreviousOutfitItemIds,
        forceDifferentOutfit: forceDifferentOutfit,
      );
      if (fallback == null) return null;
      return await _stylistFinalReviewSelectionFromChosenCandidate(
        finalSelectedIndex: 0,
        finalSelectedCandidate: fallback,
        weather: weather,
        isPremiumUser: isPremiumUser,
        wardrobe: wardrobe,
      );
    }

    final review = await _runStylistFinalReviewOnPreviews(
      candidatePreviews: candidates,
      weather: weather,
      snap: snap,
    );

    var chosen = candidates[review.selectedIndex];
    if (review.suggestedSwap != null) {
      final swapped = _tryApplySuggestedFootwearSwap(
        preview: chosen,
        suggestedSwap: review.suggestedSwap!,
        wardrobe: wardrobe,
        guidance: footwearGuidance,
      );
      if (swapped != null) {
        chosen = swapped;
      }
    }

    final ruleScores = candidates
        .map(
          (p) => OutfitGenerationService.ruleBasedOutfitScoreForPreview(
            preview: p,
            weather: snap,
          ),
        )
        .toList();

    if (preferredFootwearExists &&
        previewHasDiscouragedFootwear(
          preview: chosen,
          guidance: footwearGuidance,
        )) {
      final guarded = applyFootwearFamilyGuard(
        selectedIndex: review.selectedIndex,
        candidates: candidates,
        guidance: footwearGuidance,
        ruleScores: ruleScores,
        weather: snap,
      );
      chosen = candidates[guarded];
      if (previewHasDiscouragedFootwear(
        preview: chosen,
        guidance: footwearGuidance,
      )) {
        final fallback = _generatePreferredFootwearFallbackPreview(
          wardrobeForGen: wardrobeForGen,
          snap: snap,
          guidance: footwearGuidance,
          inventory: footwearInventory,
          excludedItemIds: effectiveExcludedItemIds,
          rejectedCombinationSignatures: rejectedCombinationSignatures,
          previousOutfitItemIds: effectivePreviousOutfitItemIds,
          forceDifferentOutfit: forceDifferentOutfit,
        );
        if (fallback == null) return null;
        chosen = fallback;
      }
    }

    if (preferredBottomExists &&
        previewHasDiscouragedBottom(
          preview: chosen,
          guidance: bottomGuidance,
        )) {
      final guardedBottom = applyBottomFamilyGuard(
        selectedIndex: review.selectedIndex,
        candidates: candidates,
        guidance: bottomGuidance,
        ruleScores: ruleScores,
      );
      chosen = candidates[guardedBottom];
      if (previewHasDiscouragedBottom(
        preview: chosen,
        guidance: bottomGuidance,
      )) {
        final fallbackBottom = _generatePreferredBottomFallbackPreview(
          wardrobeForGen: wardrobeForGen,
          snap: snap,
          guidance: bottomGuidance,
          inventory: bottomInventory,
          excludedItemIds: effectiveExcludedItemIds,
          rejectedCombinationSignatures: rejectedCombinationSignatures,
          previousOutfitItemIds: effectivePreviousOutfitItemIds,
          forceDifferentOutfit: forceDifferentOutfit,
        );
        if (fallbackBottom == null) return null;
        chosen = fallbackBottom;
      }
    }

    return await _stylistFinalReviewSelectionFromChosenCandidate(
      finalSelectedIndex: review.selectedIndex,
      finalSelectedCandidate: chosen,
      weather: weather,
      isPremiumUser: isPremiumUser,
      wardrobe: wardrobe,
      selectedReason: review.reason,
    );
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
    final wardrobeForGen = _wardrobeForOutfitGeneration(wardrobe);
    final preview = OutfitGenerationService.generatePreview(
      wardrobeItems: wardrobeForGen,
      weather: snap,
      excludedItemIds: excludedItemIds,
      rejectedCombinationSignatures: rejectedCombinationSignatures,
      previousItemIds: previousOutfitItemIds,
      forceDifferentOutfit: forceDifferentOutfit,
    );
    if (preview == null) return null;
    return _heroRecommendationFromPreview(
      preview: preview,
      weather: weather,
      isPremiumUser: isPremiumUser,
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
    final dateKey = _currentHeroBuildDateKey;
    final allowPick =
        dateKey == null || _allowHomeImagePickForBuild(dateKey);
    return _HeroOutfitItem(
      type: type,
      icon: _heroIconForType(type),
      label: p.label,
      brandLine: brandRaw.isNotEmpty ? brandRaw : null,
      imageUrl: dateKey == null
          ? _heroWardrobeDisplayImageUrl(raw, allowPick: allowPick)
          : _heroWardrobeDisplayImageUrlForHome(
              raw,
              dateKey: dateKey,
              allowPick: allowPick,
            ),
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

  Map<String, dynamic> _normalizedWardrobeMapForHome(Map<String, dynamic> raw) {
    final id = OutfitGenerationService.wardrobeItemId(raw);
    if (id.isNotEmpty) {
      for (final n in _normalizedWardrobeForHomeBrain) {
        if (OutfitGenerationService.wardrobeItemId(n) == id) return n;
      }
    }
    return HomeWardrobeNormalizer.normalize(raw, log: false).toOutfitMap();
  }

  _HeroOutfitItem _heroItemFromWardrobe({
    required Map<String, dynamic> raw,
    required _HeroWearType type,
  }) {
    final normalized = _normalizedWardrobeMapForHome(raw);
    final brandRaw = (normalized['brand'] ?? '').toString().trim();
    final categoryKey =
        (normalized['categoryKey'] ?? normalized['category'] ?? '').toString().trim();
    final subCategoryKey = (normalized['subCategoryKey'] ?? normalized['subCategory'] ?? '')
        .toString()
        .trim();
    final wid = OutfitGenerationService.wardrobeItemId(normalized);
    final dateKey = _currentHeroBuildDateKey;
    final allowPick =
        dateKey == null || _allowHomeImagePickForBuild(dateKey);
    final skName = (normalized['type_pretty'] ?? normalized['typePretty'] ?? '')
        .toString()
        .trim();
    return _HeroOutfitItem(
      type: type,
      icon: _heroIconForType(type),
      label: skName.isNotEmpty
          ? skName
          : _heroLabelForWardrobeItem(
              normalized,
              fallback: _heroFallbackLabelForType(type),
            ),
      brandLine: brandRaw.isNotEmpty ? brandRaw : null,
      imageUrl: dateKey == null
          ? _heroWardrobeDisplayImageUrl(normalized, allowPick: allowPick)
          : _heroWardrobeDisplayImageUrlForHome(
              normalized,
              dateKey: dateKey,
              allowPick: allowPick,
            ),
      categoryKey: categoryKey.isNotEmpty ? categoryKey : null,
      subCategoryKey: subCategoryKey.isNotEmpty ? subCategoryKey : null,
      wardrobeItemId: wid.isEmpty ? null : wid,
      imageProcessing: wardrobeItemShowsImageProcessingBadge(normalized),
    );
  }

  Future<void> _maybeRunStylistFinalReviewForDateKey({
    required String dateKey,
    required String dayLabel,
    required List<Map<String, dynamic>> wardrobe,
    required _LocalWeather w,
    required bool isPremiumUser,
    required String weatherSignature,
    required String wardrobeSignature,
  }) async {
    final signatureKey =
        '$dateKey|$weatherSignature|$wardrobeSignature|p=${isPremiumUser ? 1 : 0}';

    if (_stylistFinalReviewDone.contains(signatureKey) ||
        _stylistFinalReviewInFlight.contains(signatureKey)) {
      return;
    }

    final targetDayIdx = _dayIndexForDate(w.calendarDate);
    if ((_editedManuallyByDay[targetDayIdx] ?? false) == true) return;

    final existing = _homeDayHeroCacheByDateKey[dateKey];
    if (existing?.userModified == true) return;
    if (existing?.state.source == 'ai') return;

    _stylistFinalReviewInFlight.add(signatureKey);

    try {
      final prevBuildDateKey = _currentHeroBuildDateKey;
      _currentHeroBuildDateKey = dateKey;
      _StylistFinalReviewSelection? selection;
      try {
        selection = await _recommendOutfitWithStylistFinalReview(
          wardrobe: wardrobe,
          weather: w,
          isPremiumUser: isPremiumUser,
        );
      } finally {
        _currentHeroBuildDateKey = prevBuildDateKey;
      }

      if (selection == null || selection.heroItems.length < 3) return;

      final currentEntry = _homeDayHeroCacheByDateKey[dateKey];
      if (currentEntry?.userModified == true) return;
      if (currentEntry?.state.source == 'ai') return;
      if ((_editedManuallyByDay[targetDayIdx] ?? false) == true) return;

      final currentSig = currentEntry != null
          ? _heroOutfitSignatureFromItems(currentEntry.state.outfitItems)
          : '';
      final chosenSig = selection.finalSelectedSignature;
      if (currentSig == chosenSig) {
        _stylistFinalReviewDone.add(signatureKey);
        return;
      }

      final hydratedItems = _hydrateAndValidateStylistFinalReviewSelection(
        selection: selection,
        dateKey: dateKey,
        dayLabel: dayLabel,
        wardrobe: wardrobe,
      );
      if (hydratedItems == null) return;

      final state = _HeroTodayState(
        vm: _HeroBannerVM(description: selection.reason),
        outfitItems: hydratedItems,
        source: 'local',
      );

      _writeHomeDayHeroCacheIfChanged(
        dateKey: dateKey,
        state: state,
        weatherSignature: weatherSignature,
        wardrobeSignature: wardrobeSignature,
        persistSource: 'stylist_final_review',
      );

      _syncHomeOutfitStateToAllCaches(
        dayIndex: targetDayIdx,
        dateKey: dateKey,
        dayLabel: dayLabel,
        normalized: hydratedItems,
        heroState: state,
      );

      _cachedHeroBuildKeyByDateKey.remove(dateKey);
      _cachedHeroBuildStateByDateKey.remove(dateKey);
      _finalizeHeroState(dateKey: dateKey, state: state);
      if (mounted) setState(() {});

      if (_isPendingAiStylistReason(selection.reason)) {
        unawaited(
          _refreshStylistReasonInBackground(
            date: w.calendarDate,
            outfitItems: hydratedItems,
            source: 'final_review_apply',
            wardrobe: wardrobe,
          ),
        );
      }

      _stylistFinalReviewDone.add(signatureKey);
    } catch (_) {
      _stylistFinalReviewDone.add(signatureKey);
    } finally {
      _stylistFinalReviewInFlight.remove(signatureKey);
    }
  }

  String _heroBlob(Map<String, dynamic> raw) {
    final cat = (raw['categoryKey'] ?? raw['category'] ?? '').toString();
    final sub = (raw['subCategoryKey'] ?? raw['subCategory'] ?? '').toString();
    final main = (raw['mainGroupKey'] ?? raw['mainGroup'] ?? '').toString();
    final name = (raw['name'] ?? '').toString();
    return '$name $cat $sub $main'.toLowerCase();
  }

  bool _heroWardrobeMatchesType(Map<String, dynamic> raw, _HeroWearType type) {
    if (raw['home_kb_applied'] == true ||
        raw['home_legacy_fallback'] == true) {
      final layer = (raw['layer_role'] ?? '').toString().trim();
      switch (type) {
        case _HeroWearType.top:
          return layer == 'base_layer' || layer == 'mid_layer';
        case _HeroWearType.bottom:
          return layer == 'bottom';
        case _HeroWearType.shoes:
          return layer == 'footwear';
        case _HeroWearType.outerwear:
          return layer == 'outer_layer' || layer == 'mid_layer';
      }
    }
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

  ({
    List<_HeroOutfitItem> displayItems,
    List<_HeroOutfitItem> effectiveItems,
    String renderHeroSource,
  }) _getHeroPanelContent({
    required int panelDayIndex,
    required String dayLabel,
    required DateTime activeDate,
    required _HeroTodayState hero,
    String? heroLoadingReason,
  }) {
    final sig = _heroPanelContentSignature(
      panelDayIndex: panelDayIndex,
      hero: hero,
      activeDate: activeDate,
    );
    final cachedSig = _cachedHeroPanelContentSigByDayIndex[panelDayIndex];
    final cached = _cachedHeroPanelContentByDayIndex[panelDayIndex];
    if (cachedSig == sig && cached != null) {
      return cached;
    }
    final todayChanged = panelDayIndex == 0;
    final tomorrowChanged = panelDayIndex == 1;
    _logHomeRebuild(
      reason: 'panel_content_refresh',
      todayChanged: todayChanged,
      tomorrowChanged: tomorrowChanged,
    );
    final content = _resolveHeroPanelContent(
      panelDayIndex: panelDayIndex,
      dayLabel: dayLabel,
      activeDate: activeDate,
      outfitItems: hero.outfitItems,
      heroSource: hero.source,
      heroLoadingReason: heroLoadingReason ?? hero.loadingReason,
    );
    _cachedHeroPanelContentSigByDayIndex[panelDayIndex] = sig;
    _cachedHeroPanelContentByDayIndex[panelDayIndex] = content;
    return content;
  }

  ({
    List<_HeroOutfitItem> displayItems,
    List<_HeroOutfitItem> effectiveItems,
    String renderHeroSource,
  }) _resolveHeroPanelContent({
    required int panelDayIndex,
    required String dayLabel,
    required DateTime activeDate,
    required List<_HeroOutfitItem> outfitItems,
    required String heroSource,
    String? heroLoadingReason,
  }) {
    final dateKey = _dateKey(activeDate);

    List<_HeroOutfitItem> effectiveItems;
    final isManual = _editedManuallyByDay[panelDayIndex] ?? false;
    final editedItems = _editedOutfitByDay[panelDayIndex];
    final cacheEntry = _homeDayHeroCacheByDateKey[dateKey];
    if (isManual &&
        editedItems != null &&
        editedItems.length >= 3 &&
        _heroOutfitTilesHaveVisibleImages(editedItems)) {
      effectiveItems = List<_HeroOutfitItem>.from(editedItems);
    } else if (cacheEntry?.userModified == true &&
        _heroStateHasValidOutfit(cacheEntry!.state)) {
      effectiveItems = List<_HeroOutfitItem>.from(cacheEntry.state.outfitItems);
    } else if (_heroOutfitTilesHaveVisibleImages(outfitItems) &&
        outfitItems.length >= 3) {
      _syncEditableOutfitFromSourceIfNeeded(
        outfitItems,
        dayIndex: panelDayIndex,
      );
      effectiveItems = _effectiveOutfitItems(
        outfitItems,
        dayIndex: panelDayIndex,
      );
    } else {
      final cachedRender =
          _daySwitchPinnedHeroByDateKey[dateKey] ??
              _renderHeroStateForDateKey(dateKey, dayLabel);
      if (cachedRender != null &&
          _heroOutfitTilesHaveVisibleImages(cachedRender.outfitItems)) {
        effectiveItems = cachedRender.outfitItems;
      } else {
        _syncEditableOutfitFromSourceIfNeeded(
          outfitItems,
          dayIndex: panelDayIndex,
        );
        effectiveItems = _effectiveOutfitItems(
          outfitItems,
          dayIndex: panelDayIndex,
        );
        if (!_heroOutfitTilesHaveVisibleImages(effectiveItems)) {
          final hydrated = _homeHydratedOutfitItemsByDateKey[dateKey];
          if (hydrated != null && hydrated.length >= 3) {
            effectiveItems = hydrated;
            _logHomeHeroUsingCachedImagesOnce(dayLabel);
          }
        }
      }
    }

    final displayItems = _heroOutfitTilesHaveVisibleImages(effectiveItems)
        ? effectiveItems
        : _heroItemsFromCachedUrlsOnly(
            dateKey: dateKey,
            dayLabel: dayLabel,
            items: effectiveItems,
          );
    final hasVisibleImages = _heroOutfitTilesHaveVisibleImages(displayItems);
    final renderHeroSource = hasVisibleImages && heroSource == 'loading'
        ? (cacheEntry?.state.source ?? 'cached')
        : heroSource;
    final renderedNames = effectiveItems.map((e) => e.label).join(', ');
    final renderLogKey = '$renderHeroSource|${_heroRenderSignature(effectiveItems)}';
    if (_lastHeroRenderLogKeyByDayLabel[dayLabel] != renderLogKey) {
      _lastHeroRenderLogKeyByDayLabel[dayLabel] = renderLogKey;
      final renderSource = (_editedManuallyByDay[panelDayIndex] ?? false)
          ? 'edited'
          : renderHeroSource;
      if (renderHeroSource == 'loading' &&
          heroLoadingReason != null &&
          !hasVisibleImages) {
        logVerboseHome(
          '[HOME_HERO_RENDER] day=$dayLabel source=loading reason=$heroLoadingReason',
        );
      } else if (renderHeroSource != 'loading') {
        logVerboseHome(
          '[HOME_HERO_RENDER] day=$dayLabel source=$renderSource names=$renderedNames',
        );
      }
    }
    return (
      displayItems: displayItems,
      effectiveItems: effectiveItems,
      renderHeroSource: renderHeroSource,
    );
  }

  Widget _buildHeroDayPanel({
    required int panelDayIndex,
    required String heroPanelId,
    required _HeroBannerVM vm,
    required DateTime activeDate,
    required bool cardIsTomorrow,
    required _LocalWeather w,
    required ({
      List<_HeroOutfitItem> displayItems,
      List<_HeroOutfitItem> effectiveItems,
      String renderHeroSource,
    }) resolved,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    if (panelDayIndex == _dayIndex) {
      _editSpotlightVm = vm;
      _editSpotlightWeather = w;
      _editSpotlightIsTomorrow = cardIsTomorrow;
    }
    return _HomeHeroDayPanel(
      panelDayIndex: panelDayIndex,
      selectedDayIndex: _dayIndex,
      heroPanelId: heroPanelId,
      onChangeDay: _setDayIndex,
      vm: vm,
      weather: w,
      isTomorrow: cardIsTomorrow,
      displayItems: resolved.displayItems,
      loadingMode:
          resolved.renderHeroSource == 'loading' && resolved.displayItems.isEmpty,
      outfitSpotlightTargetKey:
          panelDayIndex == _dayIndex ? _editSpotlightTargetKey : null,
      outfitSpotlightLink: panelDayIndex == _dayIndex ? _editSpotlightLink : null,
      optionalItemHints: _optionalHintsForHero(
        items: resolved.displayItems,
        weather: w,
        wardrobe: wardrobe,
        dayOpener: cardIsTomorrow ? 'Zajtra' : 'Dnes',
      ),
    );
  }

  /// Both hero panels stay mounted; Dnes/Zajtra only changes [IndexedStack] index.
  Widget _buildDualHeroRow({
    required BuildContext context,
    required _HeroTodayState todayHero,
    required _HeroTodayState tomorrowHero,
    required DateTime todayDate,
    required DateTime tomorrowDate,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    final todayResolved = _getHeroPanelContent(
      panelDayIndex: 0,
      dayLabel: 'today',
      activeDate: todayDate,
      hero: todayHero,
      heroLoadingReason: todayHero.loadingReason,
    );
    final tomorrowResolved = _getHeroPanelContent(
      panelDayIndex: 1,
      dayLabel: 'tomorrow',
      activeDate: tomorrowDate,
      hero: tomorrowHero,
      heroLoadingReason: tomorrowHero.loadingReason,
    );
    final activeResolved = _dayIndex == 0 ? todayResolved : tomorrowResolved;
    final likeActive = _isCurrentOutfitLiked(activeResolved.effectiveItems);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IndexedStack(
          index: _dayIndex,
          sizing: StackFit.passthrough,
          children: [
            KeyedSubtree(
              key: const ValueKey('home_hero_today'),
              child: _buildHeroDayPanel(
                panelDayIndex: 0,
                heroPanelId: 'today',
                vm: todayHero.vm,
                activeDate: todayDate,
                cardIsTomorrow: false,
                w: _weatherForDate(todayDate),
                resolved: todayResolved,
                wardrobe: wardrobe,
              ),
            ),
            KeyedSubtree(
              key: const ValueKey('home_hero_tomorrow'),
              child: _buildHeroDayPanel(
                panelDayIndex: 1,
                heroPanelId: 'tomorrow',
                vm: tomorrowHero.vm,
                activeDate: tomorrowDate,
                cardIsTomorrow: true,
                w: _weatherForDate(tomorrowDate),
                resolved: tomorrowResolved,
                wardrobe: wardrobe,
              ),
            ),
          ],
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
            await _handleSwapPieceTap(context, activeResolved.effectiveItems);
          },
          onLike: () => _handleLikeTap(activeResolved.effectiveItems),
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

  /// Guest / signed-out single-day hero (no dual cache).
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
    final panelDayIndex = cardIsTomorrow ? 1 : 0;
    final heroPanelId = cardIsTomorrow ? 'tomorrow' : 'today';
    final hero = _HeroTodayState(
      vm: vm,
      outfitItems: outfitItems,
      source: heroSource,
      loadingReason: heroLoadingReason,
    );
    final resolved = _getHeroPanelContent(
      panelDayIndex: panelDayIndex,
      dayLabel: heroPanelId,
      activeDate: activeDate,
      hero: hero,
      heroLoadingReason: heroLoadingReason,
    );
    _editSpotlightVm = vm;
    _editSpotlightWeather = w;
    _editSpotlightIsTomorrow = cardIsTomorrow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UnifiedHeroSurface(
          dayIndex: _dayIndex,
          heroDayKey: heroPanelId,
          onChangeDay: _setDayIndex,
          vm: vm,
          weather: w,
          isTomorrow: cardIsTomorrow,
          outfitItems: resolved.displayItems,
          loadingMode:
              resolved.renderHeroSource == 'loading' && resolved.displayItems.isEmpty,
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
            await _handleSwapPieceTap(context, resolved.effectiveItems);
          },
          onLike: () => _handleLikeTap(resolved.effectiveItems),
          likeActive: _isCurrentOutfitLiked(resolved.effectiveItems),
          likePulseTick: _likePulseTick,
        ),
      ],
    );
  }

  Widget _homeSectionsAfterHero({
    required BuildContext context,
    required _HeroBannerVM vm,
    required List<_HeroOutfitItem> outfitItems,
    required _LocalWeather weather,
    required List<Map<String, dynamic>> wardrobe,
    String dayOpener = 'Dnes',
  }) {
    final explanations = _buildOutfitExplanations(
      items: outfitItems,
      weather: weather,
      wardrobe: wardrobe,
      dayOpener: dayOpener,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        HomeAiExplanationCard(
          explanations: explanations,
          supplementalBody: vm.description,
          isPlaceholder: outfitItems.isEmpty,
          isLoadingReason: _isPendingAiStylistReason(vm.description),
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
    final sameRole = docs
        .map(_normalizedWardrobeMapForHome)
        .where((raw) => _heroWardrobeMatchesType(raw, type))
        .toList();
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
    var candidates =
        tier1.isNotEmpty ? tier1 : (tier2.isNotEmpty ? tier2 : tier3);
    if (type == _HeroWearType.shoes && candidates.isNotEmpty) {
      candidates = _applyFootwearGuidanceToSwapCandidates(
        candidates: candidates,
        wardrobeForInventory: sameRole,
      );
    }
    if (type == _HeroWearType.bottom && candidates.isNotEmpty) {
      candidates = _applyBottomGuidanceToSwapCandidates(
        candidates: candidates,
        wardrobeForInventory: sameRole,
      );
    }
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == _HeroWearType.shoes
                ? 'Pre dnešné počasie nemáš vhodnejšiu obuv na výmenu.'
                : type == _HeroWearType.bottom
                ? 'Pre dnešnú teplotu nemáš vhodnejší spodný diel na výmenu.'
                : 'Pre tento typ nemáš ďalší vhodný kúsok.',
          ),
        ),
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
    final replaced = current[idx];
    current[idx] = replacement;
    _commitHomeOutfitItemReplacement(
      wearType: type,
      newItem: replacement,
      updatedOutfit: current,
      replacedItem: replaced,
    );
    debugPrint('[HOME_SWAP] accept replacement oldId=$oldId newId=$newId');
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
                      final allNormalized = docs
                          .map((d) {
                            final m = Map<String, dynamic>.from(d.data());
                            m['id'] = d.id;
                            return _normalizedWardrobeMapForHome(m);
                          })
                          .toList(growable: false);
                      final defaultGroup = _manualDefaultGroupForCurrentItem(type, currentItem);
                      final activeGroup = overrideGroup ?? defaultGroup;
                      var filtered = allNormalized
                          .where((raw) => _matchesManualGroup(raw, activeGroup, type))
                          .toList();
                      if (type == _HeroWearType.shoes && filtered.isNotEmpty) {
                        filtered = _applyFootwearGuidanceToSwapCandidates(
                          candidates: filtered,
                          wardrobeForInventory: allNormalized,
                        );
                      }
                      if (type == _HeroWearType.bottom && filtered.isNotEmpty) {
                        filtered = _applyBottomGuidanceToSwapCandidates(
                          candidates: filtered,
                          wardrobeForInventory: allNormalized,
                        );
                      }
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
                            child: filtered.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Text(
                                        type == _HeroWearType.shoes
                                            ? 'Pre dnešné počasie nemáš vhodnejšiu obuv na výmenu.'
                                            : type == _HeroWearType.bottom
                                            ? 'Pre dnešnú teplotu nemáš vhodnejší spodný diel na výmenu.'
                                            : 'V tejto kategórii zatiaľ nemáš ďalší kúsok.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: HomeLuxuryPalette.textSecondary
                                              .withOpacity(0.88),
                                          fontSize: 14,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  )
                                : GridView.builder(
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
                                    final replaced =
                                        idx >= 0 ? current[idx] : null;
                                    if (idx >= 0) {
                                      current[idx] = item;
                                    } else {
                                      current.add(item);
                                    }
                                    final newId = (item.wardrobeItemId ?? '').trim();
                                    _commitHomeOutfitItemReplacement(
                                      wearType: type,
                                      newItem: item,
                                      updatedOutfit: current,
                                      replacedItem: replaced,
                                    );
                                    if (newId.isNotEmpty) {
                                      _swapLastSuggestedItemIdByTypeByDay
                                          .putIfAbsent(_dayIndex, () => {})[type] = newId;
                                    }
                                    debugPrint(
                                      '[HOME_SWAP] accept replacement oldId=$oldId newId=$newId',
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
                                                heroDayKey: 'manual_picker',
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
          heroDayKey: _editSpotlightIsTomorrow ? 'tomorrow' : 'today',
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
              weather: w,
              wardrobe: const [],
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
              weather: w,
              wardrobe: const [],
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
              _syncWardrobeSnapshotIfChanged(
                snap: snap,
                isPremiumUser: isPremiumUser,
              );
              final wardrobe = _lastWardrobeForCache;
              final todayDateKey = _dateKey(todayDate);
              final tomorrowDateKey = _dateKey(tomorrowDate);
              final hasCachedOutfitToday =
                  (_homeDayHeroCacheByDateKey[todayDateKey] != null &&
                      _heroStateHasValidOutfit(
                        _homeDayHeroCacheByDateKey[todayDateKey]!.state,
                      )) ||
                  ((_homeHydratedOutfitItemsByDateKey[todayDateKey]?.length ??
                          0) >=
                      3);
              final hasCachedOutfitTomorrow =
                  (_homeDayHeroCacheByDateKey[tomorrowDateKey] != null &&
                      _heroStateHasValidOutfit(
                        _homeDayHeroCacheByDateKey[tomorrowDateKey]!.state,
                      )) ||
                  ((_homeHydratedOutfitItemsByDateKey[tomorrowDateKey]
                              ?.length ??
                          0) >=
                      3);
              final wardrobeReady = wardrobe.isNotEmpty || snap.hasData;
              final dataReadyToday = _weatherLoaded &&
                  (wardrobeReady || hasCachedOutfitToday);
              final dataReadyTomorrow = _weatherLoaded &&
                  (wardrobeReady || hasCachedOutfitTomorrow);
              _debugHomeBootState();
              final todayHero = _resolveHomeHero(
                activeDate: todayDate,
                wardrobe: wardrobe,
                isPremiumUser: isPremiumUser,
                dataReady: dataReadyToday,
              );
              final tomorrowHero = _resolveHomeHero(
                activeDate: tomorrowDate,
                wardrobe: wardrobe,
                isPremiumUser: isPremiumUser,
                dataReady: dataReadyTomorrow,
              );
              final activeHero =
                  _dayIndex == 0 ? todayHero : tomorrowHero;
              final vm = _HeroBannerVM(description: activeHero.vm.description);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  greetingHeader(),
                  const SizedBox(height: 26),
                  _buildDualHeroRow(
                    context: context,
                    todayHero: todayHero,
                    tomorrowHero: tomorrowHero,
                    todayDate: todayDate,
                    tomorrowDate: tomorrowDate,
                    wardrobe: wardrobe,
                  ),
                  _homeSectionsAfterHero(
                    context: context,
                    vm: vm,
                    outfitItems: activeHero.outfitItems,
                    weather: _weatherForDate(
                      _dayIndex == 0 ? todayDate : tomorrowDate,
                    ),
                    wardrobe: wardrobe,
                    dayOpener: _dayIndex == 0 ? 'Dnes' : 'Zajtra',
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
            if (kDebugMode)
              ListTile(
                iconColor: HomeLuxuryPalette.accent,
                textColor: HomeLuxuryPalette.accent,
                leading: Icon(Icons.science_outlined, color: HomeLuxuryPalette.accent),
                title: Text(
                  'Wardrobe Reanalyze Review',
                  style: TextStyle(color: HomeLuxuryPalette.accent, fontSize: 14),
                ),
                subtitle: Text(
                  'Dry run — visual review, no Firestore writes',
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.85),
                    fontSize: 11,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WardrobeReanalyzeReviewScreen(),
                    ),
                  );
                },
              ),
            if (kDebugMode)
              ListTile(
                iconColor: HomeLuxuryPalette.accent,
                textColor: HomeLuxuryPalette.accent,
                leading: Icon(Icons.cloud_upload_outlined, color: HomeLuxuryPalette.accent),
                title: Text(
                  'Reanalyze wardrobe metadata',
                  style: TextStyle(color: HomeLuxuryPalette.accent, fontSize: 14),
                ),
                subtitle: Text(
                  'Re-run AI on photos → save patterns/logo to Firestore',
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.85),
                    fontSize: 11,
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Reanalýza metadát beží…'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    final summary =
                        await WardrobeReanalyzeApplyService.applyMetadataRefresh();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Hotovo: ${summary.updated} aktualizovaných, '
                          '${summary.skipped} bez zmeny, ${summary.failed} chýb',
                        ),
                      ),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Chyba: $e')),
                    );
                  }
                },
              ),
            if (kDebugMode)
              ListTile(
                iconColor: HomeLuxuryPalette.accent,
                textColor: HomeLuxuryPalette.accent,
                leading: Icon(Icons.refresh, color: HomeLuxuryPalette.accent),
                title: Text(
                  'Reanalyze only missing',
                  style: TextStyle(color: HomeLuxuryPalette.accent, fontSize: 14),
                ),
                subtitle: Text(
                  'Dokonči kúsky, ktoré ešte nemajú metadáta (po rate limite)',
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.85),
                    fontSize: 11,
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Dopĺňam chýbajúce metadáta…'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    final summary = await WardrobeReanalyzeApplyService
                        .applyMetadataRefresh(onlyMissing: true);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Hotovo: ${summary.updated} aktualizovaných, '
                          '${summary.skipped} bez zmeny, ${summary.failed} chýb',
                        ),
                      ),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Chyba: $e')),
                    );
                  }
                },
              ),
            if (kDebugMode)
              ListTile(
                iconColor: HomeLuxuryPalette.accent,
                textColor: HomeLuxuryPalette.accent,
                leading: Icon(Icons.sync_alt, color: HomeLuxuryPalette.accent),
                title: Text(
                  'Fix Mikina Layers',
                  style: TextStyle(color: HomeLuxuryPalette.accent, fontSize: 14),
                ),
                subtitle: Text(
                  'Set existing mikiny to mid_layer',
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.85),
                    fontSize: 11,
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: HomeLuxuryPalette.surfaceSoft,
                      title: const Text(
                        'Fix Existing Mikina Layers?',
                        style: TextStyle(color: HomeLuxuryPalette.textPrimary),
                      ),
                      content: const Text(
                        'Updates existing mikiny in your wardrobe from '
                        'outer_layer to mid_layer.\n\n'
                        'Does not change names, colors, or images.\n\n'
                        'This writes to your wardrobe in Firestore.',
                        style: TextStyle(
                          color: HomeLuxuryPalette.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Fix mikiny'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;

                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Mikina layer migration running…'),
                      duration: Duration(seconds: 3),
                    ),
                  );

                  try {
                    final summary = await WardrobeMetadataMigrationService
                        .applyMikinaMidLayerFix();
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Mikina layer fix done: ${summary.updated} updated, '
                          '${summary.skipped} skipped, ${summary.failed} failed '
                          '(${summary.total} total)',
                        ),
                        duration: const Duration(seconds: 6),
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Mikina layer fix failed: $e'),
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                },
              ),
            if (kDebugMode)
              ListTile(
                iconColor: HomeLuxuryPalette.accent,
                textColor: HomeLuxuryPalette.accent,
                leading: Icon(Icons.spellcheck, color: HomeLuxuryPalette.accent),
                title: Text(
                  'Name Grammar Fix (Dry Run)',
                  style: TextStyle(color: HomeLuxuryPalette.accent, fontSize: 14),
                ),
                subtitle: Text(
                  'Preview Slovak adjective fixes — no writes',
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.85),
                    fontSize: 11,
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Name grammar dry run — check debug console.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                  try {
                    final summary = await WardrobeNameGrammarFixService.dryRun();
                    if (!mounted) return;
                    setState(() {
                      _nameGrammarFixCanApply =
                          WardrobeNameGrammarFixService.canApply;
                    });
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          summary.fixed > 0
                              ? 'Dry run done: ${summary.fixed} would fix, '
                                  '${summary.skipped} skipped (${summary.total} total). '
                                  'Apply is now unlocked.'
                              : 'Dry run done: no grammar fixes needed.',
                        ),
                        duration: const Duration(seconds: 6),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    setState(() => _nameGrammarFixCanApply = false);
                    messenger.showSnackBar(
                      SnackBar(content: Text('Dry run failed: $e')),
                    );
                  }
                },
              ),
            if (kDebugMode)
              ListTile(
                iconColor: HomeLuxuryPalette.accent,
                textColor: HomeLuxuryPalette.accent,
                leading: Icon(Icons.edit_note, color: HomeLuxuryPalette.accent),
                title: Text(
                  'Apply Name Grammar Fix',
                  style: TextStyle(color: HomeLuxuryPalette.accent, fontSize: 14),
                ),
                subtitle: Text(
                  _nameGrammarFixCanApply
                      ? 'Apply ${WardrobeNameGrammarFixService.pendingFixes.length} '
                          'pending fix(es) — name field only'
                      : WardrobeNameGrammarFixService.dryRunCompletedThisSession
                          ? 'No pending fixes from dry-run'
                          : 'Run dry-run first to unlock',
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.85),
                    fontSize: 11,
                  ),
                ),
                enabled: _nameGrammarFixCanApply,
                onTap: () async {
                  if (!_nameGrammarFixCanApply) return;
                  Navigator.of(context).pop();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: HomeLuxuryPalette.surfaceSoft,
                      title: const Text(
                        'Apply name grammar fixes?',
                        style: TextStyle(color: HomeLuxuryPalette.textPrimary),
                      ),
                      content: const Text(
                        'Fixes only obvious Slovak color adjective mistakes in '
                        'the name field.\n\n'
                        'Does not change colors, categories, metadata, or images.',
                        style: TextStyle(
                          color: HomeLuxuryPalette.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Apply fixes'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;

                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final summary = await WardrobeNameGrammarFixService.apply();
                    if (!mounted) return;
                    setState(() => _nameGrammarFixCanApply = false);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Applied: ${summary.fixed} names fixed, '
                          '${summary.failed} failed (${summary.total} total)',
                        ),
                        duration: const Duration(seconds: 6),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('Apply failed: $e')),
                    );
                  }
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
/// Mounted hero panel for one day — keeps [IndexedStack] child stable.
class _HomeHeroDayPanel extends StatelessWidget {
  const _HomeHeroDayPanel({
    required this.panelDayIndex,
    required this.selectedDayIndex,
    required this.heroPanelId,
    required this.onChangeDay,
    required this.vm,
    required this.weather,
    required this.isTomorrow,
    required this.displayItems,
    required this.loadingMode,
    this.outfitSpotlightTargetKey,
    this.outfitSpotlightLink,
    this.optionalItemHints = const {},
  });

  final int panelDayIndex;
  final int selectedDayIndex;
  final String heroPanelId;
  final ValueChanged<int> onChangeDay;
  final _HeroBannerVM vm;
  final _LocalWeather weather;
  final bool isTomorrow;
  final List<_HeroOutfitItem> displayItems;
  final bool loadingMode;
  final GlobalKey? outfitSpotlightTargetKey;
  final LayerLink? outfitSpotlightLink;
  final Map<_HeroWearType, String> optionalItemHints;

  @override
  Widget build(BuildContext context) {
    return _UnifiedHeroSurface(
      dayIndex: selectedDayIndex,
      heroDayKey: heroPanelId,
      onChangeDay: onChangeDay,
      vm: vm,
      weather: weather,
      isTomorrow: isTomorrow,
      outfitItems: displayItems,
      loadingMode: loadingMode,
      editMode: false,
      focusedType: null,
      onItemTap: null,
      onRemoveTap: null,
      outfitSpotlightTargetKey: outfitSpotlightTargetKey,
      outfitSpotlightLink: outfitSpotlightLink,
      optionalItemHints: optionalItemHints,
    );
  }
}

class _UnifiedHeroSurface extends StatelessWidget {
  const _UnifiedHeroSurface({
    required this.dayIndex,
    required this.heroDayKey,
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
    this.optionalItemHints = const {},
  });

  final int dayIndex;
  final String heroDayKey;
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
  final Map<_HeroWearType, String> optionalItemHints;

  @override
  Widget build(BuildContext context) {
    const compact = true;
    final hasOutfitTiles = outfitItems.isNotEmpty;
    const minGridEmpty = 100.0;
    final radius = BorderRadius.circular(20);
    final sharedBodyH = _heroSharedBodyHeight(context);

    final Widget outfitBody;
    if (hasOutfitTiles) {
      outfitBody = _HeroOutfitTilesGrid(
        key: ValueKey('home_hero_grid_$heroDayKey'),
        heroDayKey: heroDayKey,
        items: outfitItems,
        compact: compact,
        editMode: editMode,
        focusedType: focusedType,
        onItemTap: onItemTap,
        onRemoveTap: onRemoveTap,
        optionalItemHints: optionalItemHints,
      );
    } else if (loadingMode) {
      outfitBody = const SizedBox.expand();
    } else {
      outfitBody = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            vm.description,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.92),
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ),
      );
    }
    final outfitSwitcher = outfitBody;

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
                                          heroDayKey: 'manual_picker',
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
                  heroDayKey: 'composer_preview',
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
                heroDayKey: 'composer_preview',
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

