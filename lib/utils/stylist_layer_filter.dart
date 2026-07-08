import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import 'home_debug_logging.dart';

/// Weather context for layer-aware wardrobe filtering (primary over season tags).
class StylistWeatherContext {
  final int tempC;
  final bool isRainy;
  final bool isWindy;
  final String seasonKey;
  final int? morningTempC;
  final int? eveningTempC;

  const StylistWeatherContext({
    required this.tempC,
    required this.isRainy,
    required this.isWindy,
    required this.seasonKey,
    this.morningTempC,
    this.eveningTempC,
  });

  bool get isCold => tempC < 10;
  bool get isWarm => tempC >= 20;
  bool get isMild => tempC >= 10 && tempC < 20;
  bool get isFreezing => tempC < 0;
}

class StylistLayerFilterResult {
  final bool allowed;
  final String reason;

  const StylistLayerFilterResult({required this.allowed, required this.reason});
}

/// Layer-first wardrobe usability (V2 layer_role + warmth_level + weather).
class StylistLayerFilter {
  StylistLayerFilter._();

  static const Set<String> _midLayerSubKeys = {
    'mikina_klasicka',
    'mikina_na_zips',
    'mikina_s_kapucnou',
    'mikina_oversize',
    'sport_mikina',
    'flisova_bunda',
    'bunda_prechodna',
    'bunda_bomber',
    'softshell_bunda',
    'sveter_klasicky',
    'sveter_rolak',
    'sveter_kardigan',
    'sveter_pleteny',
  };

  static const Set<String> _baseLayerSubKeys = {
    'tricko',
    'tricko_dlhy_rukav',
    'tielko',
    'undershirt',
    'top_basic',
    'crop_top',
    'polo_tricko',
    'sport_tricko',
  };

  static const Set<String> _heavyOuterSubKeys = {
    'bunda_zimna',
    'kabat',
    'trenchcoat',
  };

  static int? parseWarmthLevel(Map<String, dynamic> item) {
    final raw = item['warmth_level'] ?? item['warmthLevel'];
    if (raw == null) return null;
    final n = num.tryParse(raw.toString());
    if (n == null || !n.isFinite) return null;
    return n.round().clamp(1, 10);
  }

  /// Sleeveless tank top (tielko) — not undershirt / spodné tielko.
  static bool isTankTopItem(Map<String, dynamic> item) {
    final sub = _subKey(item);
    if (sub == 'undershirt') return false;
    if (sub == 'tielko') return true;

    final canonical = _normToken(
      (item['canonical_type'] ?? item['canonicalType'] ?? '').toString(),
    );
    if (canonical == 'tank_top' || canonical == 'tanktop') return true;

    final name =
        (item['name'] ?? item['typePretty'] ?? item['type_pretty'] ?? '')
            .toString()
            .toLowerCase();
    if (name.contains('spodné tielko') || name.contains('spodne tielko')) {
      return false;
    }
    if (name.contains('tielko')) return true;
    if (name.contains('tank top') || name.contains('tanktop')) return true;
    if (name.contains('sleeveless') &&
        (name.contains('top') ||
            name.contains('shirt') ||
            name.contains('tee'))) {
      return true;
    }
    return false;
  }

  static bool isSportOrBeachOccasionItem(Map<String, dynamic> item) {
    final tokens = <String>[];
    for (final key in ['occasion_fit', 'occasionFit', 'styles', 'vibe']) {
      final v = item[key];
      if (v is List) {
        tokens.addAll(v.map((e) => e.toString().trim().toLowerCase()));
      } else if (v is String && v.trim().isNotEmpty) {
        tokens.add(v.trim().toLowerCase());
      }
    }
    final blob = tokens.join(' ');
    final catBlob = [
      item['categoryKey'],
      item['category'],
      item['subCategoryKey'],
      item['subCategory'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');

    return blob.contains('sport') ||
        blob.contains('beach') ||
        blob.contains('plaz') ||
        blob.contains('pláž') ||
        blob.contains('gym') ||
        blob.contains('pool') ||
        catBlob.contains('sport');
  }

  static int inferWarmthLevel(Map<String, dynamic> item) {
    if (isTankTopItem(item)) return 1;

    final stored = parseWarmthLevel(item);
    if (stored != null) return stored;

    final sub = _subKey(item);
    if (sub == 'undershirt') return 1;
    if (_baseLayerSubKeys.contains(sub) || sub == 'tricko_dlhy_rukav') return 3;
    if (_midLayerSubKeys.contains(sub)) return 5;
    if (sub == 'bunda_zimna' || sub == 'kabat') return 9;
    if (sub == 'prsiplast' || sub == 'softshell_bunda') return 6;
    if (subCategoryLayerRoles[sub] == 'outer_layer') return 7;
    if (subCategoryLayerRoles[sub] == 'main_top') return 3;

    final layer =
        (item['layer_role'] ?? item['layerRole'] ?? '').toString().trim();
    if (layer == 'main_top') return 2;

    final canonical = _normToken(
      (item['canonical_type'] ?? item['canonicalType'] ?? '').toString(),
    );
    if (canonical.contains('tshirt') ||
        canonical.contains('t_shirt') ||
        canonical.contains('polo') ||
        canonical.contains('shirt') ||
        canonical.contains('tank')) {
      return 2;
    }
    if (canonical.contains('short')) return 1;

    return 5;
  }

  static String resolveEffectiveLayerRole(Map<String, dynamic> item) {
    if (item['home_kb_applied'] == true ||
        item['home_legacy_fallback'] == true) {
      final normalizedLayer = _normToken((item['layer_role'] ?? '').toString());
      if (normalizedLayer == 'base_layer' ||
          normalizedLayer == 'mid_layer' ||
          normalizedLayer == 'outer_layer' ||
          normalizedLayer == 'bottom' ||
          normalizedLayer == 'footwear' ||
          normalizedLayer == 'accessory') {
        return normalizedLayer;
      }
    }

    final v2 = _normToken(
      (item['layer_role'] ?? item['stylingLayerRole'] ?? '').toString(),
    );
    if (v2 == 'base_layer' ||
        v2 == 'mid_layer' ||
        v2 == 'outer_layer' ||
        v2 == 'bottom' ||
        v2 == 'footwear' ||
        v2 == 'accessory') {
      return v2;
    }

    final appRole = _normToken((item['layerRole'] ?? '').toString());
    if (appRole == 'footwear' ||
        appRole == 'accessory' ||
        appRole == 'base_bottom' ||
        appRole == 'main_bottom' ||
        appRole == 'one_piece') {
      return appRole;
    }
    if (appRole == 'base_layer' || appRole == 'mid_layer') return appRole;

    final sub = _subKey(item);
    if (_baseLayerSubKeys.contains(sub)) return 'base_layer';
    if (_midLayerSubKeys.contains(sub)) return 'mid_layer';

    final warmth = inferWarmthLevel(item);
    if (appRole == 'outer_layer' ||
        subCategoryLayerRoles[sub] == 'outer_layer') {
      if (warmth <= 6 && !_heavyOuterSubKeys.contains(sub)) {
        return 'mid_layer';
      }
      return 'outer_layer';
    }

    if (appRole == 'main_top') {
      if (_midLayerSubKeys.contains(sub)) return 'mid_layer';
      return 'base_layer';
    }

    return 'base_layer';
  }

  static StylistLayerFilterResult shouldAllowItemForWeather({
    required Map<String, dynamic> item,
    required StylistWeatherContext weather,
    bool log = false,
  }) {
    final layerRole = resolveEffectiveLayerRole(item);
    final warmthLevel = inferWarmthLevel(item);
    final sub = _subKey(item);
    final name = (item['name'] ?? item['typePretty'] ?? '').toString();

    if (isTankTopItem(item) &&
        (layerRole == 'base_layer' || layerRole == 'main_top') &&
        weather.tempC < 18 &&
        !isSportOrBeachOccasionItem(item)) {
      if (log || kDebugMode) {
        debugPrint(
          '[TANK_TOP_REJECTED] '
          'item=${name.isEmpty ? sub : name} '
          'reason=too_cold_for_tank_top '
          'temp=${weather.tempC}',
        );
      }
      return const StylistLayerFilterResult(
        allowed: false,
        reason: 'too_cold_for_tank_top',
      );
    }

    final StylistLayerFilterResult result;
    if (layerRole == 'base_layer' || layerRole == 'mid_layer') {
      result = _allowBaseOrMid(weather, warmthLevel);
    } else if (layerRole == 'outer_layer') {
      result = _allowOuter(weather, warmthLevel);
    } else {
      result = _allowSlot(weather, warmthLevel, layerRole);
    }

    if (log) {
      _logFilter(
        name: name.isEmpty ? sub : name,
        layerRole: layerRole,
        warmthLevel: warmthLevel,
        weather: weather,
        allowed: result.allowed,
        reason: result.reason,
      );
    }

    return result;
  }

  static bool isItemUsableForWeather(
    Map<String, dynamic> item,
    StylistWeatherContext weather, {
    bool log = false,
  }) {
    return shouldAllowItemForWeather(
      item: item,
      weather: weather,
      log: log,
    ).allowed;
  }

  static StylistLayerFilterResult _allowBaseOrMid(
    StylistWeatherContext weather,
    int warmth,
  ) {
    if (weather.tempC >= 24 && warmth >= 5) {
      return const StylistLayerFilterResult(
        allowed: false,
        reason: 'too_warm_for_mid_layer',
      );
    }
    if (weather.isWarm && warmth >= 9) {
      return const StylistLayerFilterResult(
        allowed: false,
        reason: 'heavy_piece_in_hot_weather',
      );
    }
    return const StylistLayerFilterResult(
      allowed: true,
      reason: 'layer_usable_any_season',
    );
  }

  static StylistLayerFilterResult _allowOuter(
    StylistWeatherContext weather,
    int warmth,
  ) {
    if (weather.tempC >= 24 && warmth >= 5) {
      return const StylistLayerFilterResult(
        allowed: false,
        reason: 'too_warm_outer_for_hot_day',
      );
    }
    if (weather.isWarm && warmth >= 7) {
      return const StylistLayerFilterResult(
        allowed: false,
        reason: 'heavy_outer_in_warm_weather',
      );
    }
    if (weather.isCold || weather.isFreezing) {
      if (warmth >= 6) {
        return const StylistLayerFilterResult(
          allowed: true,
          reason: 'warm_outer_for_cold',
        );
      }
      return const StylistLayerFilterResult(
        allowed: true,
        reason: 'light_outer_as_mid_layer',
      );
    }
    if (weather.isMild) {
      if (warmth >= 8) {
        return const StylistLayerFilterResult(
          allowed: false,
          reason: 'too_warm_outer_for_mild_day',
        );
      }
      return const StylistLayerFilterResult(
        allowed: true,
        reason: 'outer_ok_for_mild',
      );
    }
    if (warmth <= 4) {
      return const StylistLayerFilterResult(
        allowed: true,
        reason: 'light_outer_default',
      );
    }
    return const StylistLayerFilterResult(
      allowed: true,
      reason: 'outer_default',
    );
  }

  static StylistLayerFilterResult _allowSlot(
    StylistWeatherContext weather,
    int warmth,
    String layerRole,
  ) {
    if (weather.isWarm && warmth >= 8) {
      return const StylistLayerFilterResult(
        allowed: false,
        reason: 'heavy_slot_in_hot_weather',
      );
    }
    if ((weather.isCold || weather.isRainy) &&
        warmth <= 2 &&
        layerRole == 'footwear') {
      return const StylistLayerFilterResult(
        allowed: false,
        reason: 'too_light_shoes_for_cold_rain',
      );
    }
    return const StylistLayerFilterResult(
      allowed: true,
      reason: 'slot_weather_ok',
    );
  }

  static void _logFilter({
    required String name,
    required String layerRole,
    required int warmthLevel,
    required StylistWeatherContext weather,
    required bool allowed,
    required String reason,
  }) {
    if (!kVerboseHomeLogs) return;
    debugPrint(
      '[STYLIST_LAYER_FILTER] item=$name layer_role=$layerRole '
      'warmth_level=$warmthLevel temp=${weather.tempC}C '
      'rain=${weather.isRainy} wind=${weather.isWindy} '
      'allowed=$allowed reason=$reason',
    );
  }

  static String _subKey(Map<String, dynamic> item) {
    return _normToken(
      (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString(),
    );
  }

  static String _normToken(String s) => s.toLowerCase().trim();
}
