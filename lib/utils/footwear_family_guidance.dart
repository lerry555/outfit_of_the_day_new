import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import 'home_debug_logging.dart';

/// Footwear family for stylist final review (not item-level scoring).
enum FootwearFamily { sneakers, boots, sandals, formalShoes, other }

extension FootwearFamilyWire on FootwearFamily {
  String get wireName {
    switch (this) {
      case FootwearFamily.sneakers:
        return 'sneakers';
      case FootwearFamily.boots:
        return 'boots';
      case FootwearFamily.sandals:
        return 'sandals';
      case FootwearFamily.formalShoes:
        return 'formal_shoes';
      case FootwearFamily.other:
        return 'other';
    }
  }
}

class FootwearFamilyGuidance {
  const FootwearFamilyGuidance({
    required this.preferredFamilies,
    required this.allowedFamilies,
    required this.discouragedFamilies,
    required this.reason,
  });

  final List<String> preferredFamilies;
  final List<String> allowedFamilies;
  final List<String> discouragedFamilies;
  final String reason;

  Map<String, dynamic> toPayload() => <String, dynamic>{
    'preferredFamilies': preferredFamilies,
    'allowedFamilies': allowedFamilies,
    'discouragedFamilies': discouragedFamilies,
    'reason': reason,
  };

  bool isPreferred(FootwearFamily family) =>
      preferredFamilies.contains(family.wireName);

  bool isAllowed(FootwearFamily family) =>
      allowedFamilies.contains(family.wireName);

  bool isDiscouraged(FootwearFamily family) =>
      discouragedFamilies.contains(family.wireName);
}

String _normToken(String s) {
  return s
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

bool _blobContainsAny(String blob, List<String> needles) {
  final h = _normToken(blob);
  return needles.any((n) => h.contains(_normToken(n)));
}

String _normCanonicalKey(String raw) {
  return _normToken(raw).replaceAll(RegExp(r'[\s_\-/]+'), '');
}

const Set<String> _sneakerCanonicalKeys = {
  'basketballshoes',
  'runningshoes',
  'sportshoes',
  'athleticshoes',
  'trainingshoes',
  'sneakers',
  'fashionsneakers',
  'runningshoe',
  'sportshoe',
  'athleticshoe',
  'trainingshoe',
  'basketballshoe',
};

bool _isSneakerFamilyBlob(String blob) {
  return _blobContainsAny(blob, [
    'sneaker',
    'tenisk',
    'tenis',
    'runner',
    'trainer',
    'running_shoe',
    'running_shoes',
    'basketball_shoe',
    'basketball_shoes',
    'sport_shoe',
    'sport_shoes',
    'athletic_shoe',
    'athletic_shoes',
    'training_shoe',
    'training_shoes',
    'sportove tenisky',
    'sportové tenisky',
  ]);
}

bool _isFormalFamilyBlob(String blob) {
  return _blobContainsAny(blob, [
    'oxford',
    'derby',
    'loafer',
    'dress_shoe',
    'dress_shoes',
    'formal_shoe',
    'formal_shoes',
    'mokasin',
    'moccasin',
    'brogue',
    'elegant',
    'spolocenske',
    'spolocenska',
    'lodick',
    'lodičk',
    'heel',
    'pump',
    'balerin',
  ]);
}

String _footwearBlob(Map<String, dynamic> item) {
  return [
    item['name'],
    item['label'],
    item['canonical_type'],
    item['canonicalType'],
    item['category'],
    item['categoryKey'],
    item['subCategory'],
    item['subCategoryKey'],
    item['mainGroup'],
    item['mainGroupKey'],
    item['material'],
    item['materialFeel'],
    item['visual_description'],
    item['visualDescription'],
  ].map((e) => (e ?? '').toString()).join(' ');
}

bool isRainRiskSportSneakerItem(Map<String, dynamic> item) {
  final blob = _normToken(_footwearBlob(item));
  final canonical = _normCanonicalKey(
    (item['canonical_type'] ?? item['canonicalType'] ?? '').toString(),
  );
  return blob.contains('siet') ||
      blob.contains('mesh') ||
      blob.contains('bezeck') ||
      blob.contains('running') ||
      blob.contains('sportove tenisky') ||
      blob.contains('sport shoe') ||
      blob.contains('sport shoes') ||
      blob.contains('training shoe') ||
      blob.contains('training shoes') ||
      blob.contains('athletic shoe') ||
      blob.contains('athletic shoes') ||
      canonical.contains('running') ||
      canonical.contains('training') ||
      canonical.contains('athletic') ||
      canonical.contains('sportshoe');
}

bool isRainDiscouragedFootwearItem({
  required Map<String, dynamic> item,
  required OutfitWeatherSnapshot weather,
}) {
  return weather.isRainy &&
      weather.tempC > 12 &&
      classifyFootwearFamily(item) == FootwearFamily.sneakers &&
      isRainRiskSportSneakerItem(item);
}

/// Classify footwear item into a family using canonical type, keys, and name.
FootwearFamily classifyFootwearFamily(Map<String, dynamic> item) {
  final canonical = (item['canonical_type'] ?? item['canonicalType'] ?? '')
      .toString()
      .trim();
  final sub = (item['subCategoryKey'] ?? item['subCategory'] ?? '')
      .toString()
      .trim();
  final cat = (item['categoryKey'] ?? item['category'] ?? '').toString().trim();
  final name = (item['name'] ?? '').toString().trim();
  final blob = '$canonical $sub $cat $name';

  if (_blobContainsAny(blob, [
    'sandal',
    'sandale',
    'sandál',
    'flip',
    'slapky',
    'šľapky',
    'slipper_open',
  ])) {
    return FootwearFamily.sandals;
  }

  if (_blobContainsAny(blob, [
    'boot',
    'cizm',
    'čižm',
    'chelsea',
    'kotnik',
    'kotník',
    'timberland',
    'work_boot',
    'hiking_boot',
    'winter_boot',
  ])) {
    return FootwearFamily.boots;
  }

  final canonicalNorm = _normCanonicalKey(canonical);
  if (canonicalNorm.contains('hiking') ||
      _blobContainsAny(blob, [
        'hiking_shoe',
        'hiking shoe',
        'turistick',
        'treking',
        'trekking',
      ])) {
    return FootwearFamily.sneakers;
  }
  if (_sneakerCanonicalKeys.contains(canonicalNorm) ||
      canonicalNorm.contains('sneaker') ||
      _isSneakerFamilyBlob(blob)) {
    return FootwearFamily.sneakers;
  }

  if (_isFormalFamilyBlob(blob)) {
    return FootwearFamily.formalShoes;
  }

  final c = _normToken(canonical);
  if (c.contains('sneaker') || c == 'sneakers') return FootwearFamily.sneakers;
  if (c.contains('boot')) return FootwearFamily.boots;
  if (c.contains('sandal')) return FootwearFamily.sandals;
  if (c.contains('loafer') || c.contains('oxford') || c.contains('heel')) {
    return FootwearFamily.formalShoes;
  }

  if (_blobContainsAny(blob, ['footwear', 'obuv'])) {
    return FootwearFamily.other;
  }

  return FootwearFamily.other;
}

FootwearFamilyGuidance computeFootwearFamilyGuidance({
  required OutfitWeatherSnapshot weather,
  bool wetGroundMuddy = false,
}) {
  final temp = weather.tempC;
  final rainy = weather.isRainy;
  final heavyRain = weather.isHeavyRain;
  final mildRain = rainy && !heavyRain;

  final preferred = <String>[];
  final allowed = <String>[];
  final discouraged = <String>[];
  var reason = '';

  if (temp <= 10 || heavyRain) {
    preferred.add(FootwearFamily.boots.wireName);
    allowed.addAll([
      FootwearFamily.boots.wireName,
      FootwearFamily.sneakers.wireName,
      FootwearFamily.formalShoes.wireName,
    ]);
    discouraged.add(FootwearFamily.sandals.wireName);
    reason = heavyRain
        ? 'Silný dážď alebo zima: čižmy/boots sú praktickejšie.'
        : 'Chladno (≤10°C): čižmy/boots sú vhodnejšie.';
  } else if (temp >= 18 && mildRain) {
    preferred.add(FootwearFamily.sneakers.wireName);
    allowed.add(FootwearFamily.sneakers.wireName);
    discouraged.addAll([
      FootwearFamily.boots.wireName,
      FootwearFamily.sandals.wireName,
    ]);
    reason =
        'Mild warm rain: sneakers are preferred; boots are too warm/heavy.';
  } else if (temp >= 16) {
    preferred.add(FootwearFamily.sneakers.wireName);
    allowed.addAll([
      FootwearFamily.sneakers.wireName,
      FootwearFamily.formalShoes.wireName,
    ]);

    if (!rainy && temp >= 22) {
      allowed.add(FootwearFamily.sandals.wireName);
    } else {
      discouraged.add(FootwearFamily.sandals.wireName);
    }

    if (!heavyRain) {
      discouraged.add(FootwearFamily.boots.wireName);
    }

    reason = rainy
        ? 'Teplo (${temp}°C) a dážď: preferuj tenisky; čižmy sú príliš ťažké.'
        : 'Teplo (${temp}°C): preferuj tenisky; čižmy len pri extrémnom počasí.';
  } else {
    // 11–15°C transitional
    if (rainy) {
      preferred.add(FootwearFamily.boots.wireName);
    }
    preferred.add(FootwearFamily.sneakers.wireName);
    allowed.addAll([
      FootwearFamily.sneakers.wireName,
      FootwearFamily.boots.wireName,
      FootwearFamily.formalShoes.wireName,
    ]);
    discouraged.add(FootwearFamily.sandals.wireName);
    reason = rainy
        ? 'Mierne chladno s dažďom: tenisky alebo čižmy; sandále nie.'
        : 'Prechodné počasie: tenisky alebo ľahšia obuv; sandále nie.';
  }

  // Po daždi na tráve/hline (hory, lúka): radšej uzavretá obuv než sandále.
  if (wetGroundMuddy) {
    discouraged.add(FootwearFamily.sandals.wireName);
    if (!preferred.contains(FootwearFamily.sneakers.wireName)) {
      preferred.insert(0, FootwearFamily.sneakers.wireName);
    }
    if (!allowed.contains(FootwearFamily.sneakers.wireName)) {
      allowed.add(FootwearFamily.sneakers.wireName);
    }
    reason =
        'Po daždi na tráve alebo hline: radšej uzavretú obuv (tenisky), nie sandále.';
  }

  // Ensure preferred ⊆ allowed
  for (final p in preferred) {
    if (!allowed.contains(p)) allowed.add(p);
  }

  return FootwearFamilyGuidance(
    preferredFamilies: preferred,
    allowedFamilies: allowed,
    discouragedFamilies: discouraged,
    reason: reason,
  );
}

void logFootwearFamilyGuidance({
  required OutfitWeatherSnapshot weather,
  required FootwearFamilyGuidance guidance,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[FOOTWEAR_FAMILY_GUIDANCE] temp=${weather.tempC} rain=${weather.isRainy} '
    'heavyRain=${weather.isHeavyRain} '
    'preferred=${guidance.preferredFamilies.join(",")} '
    'allowed=${guidance.allowedFamilies.join(",")} '
    'discouraged=${guidance.discouragedFamilies.join(",")} '
    'reason=${guidance.reason}',
  );
}

bool isFootwearWardrobeItem(Map<String, dynamic> item) {
  final layer = (item['layer_role'] ?? item['layerRole'] ?? '')
      .toString()
      .trim();
  if (layer == 'footwear' || layer == 'shoes') return true;

  if (classifyFootwearFamily(item) != FootwearFamily.other) return true;

  final cat = (item['categoryKey'] ?? item['category'] ?? '').toString();
  final sub = (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString();
  final name = (item['name'] ?? '').toString();
  final blob = '$cat $sub $name'.toLowerCase();
  return _blobContainsAny(blob, [
    'topán',
    'topan',
    'tenis',
    'sneaker',
    'boot',
    'čižm',
    'cizm',
    'sandál',
    'sandal',
    'obuv',
    'shoes',
    'footwear',
  ]);
}

/// Preferovaná obuv reálne použiteľná v matrix shoes poole (M6).
bool hasUsablePreferredFootwear({
  required List<Map<String, dynamic>> wardrobe,
  required FootwearFamilyGuidance guidance,
  Set<String> excludedItemIds = const {},
}) {
  for (final item in wardrobe) {
    if (!isFootwearWardrobeItem(item)) continue;
    final id = OutfitGenerationService.wardrobeItemId(item);
    if (id.isEmpty || excludedItemIds.contains(id)) continue;
    if (guidance.isPreferred(classifyFootwearFamily(item))) return true;
  }
  return false;
}

/// Footwear items in wardrobe grouped by family.
class FootwearFamilyInventory {
  FootwearFamilyInventory(this.itemsByFamily);

  final Map<FootwearFamily, List<Map<String, dynamic>>> itemsByFamily;

  int countForWireFamily(String wireName) {
    for (final entry in itemsByFamily.entries) {
      if (entry.key.wireName == wireName) return entry.value.length;
    }
    return 0;
  }

  int preferredCount(FootwearFamilyGuidance guidance) {
    var n = 0;
    for (final wire in guidance.preferredFamilies) {
      n += countForWireFamily(wire);
    }
    return n;
  }

  int allowedCount(FootwearFamilyGuidance guidance) {
    var n = 0;
    for (final wire in guidance.allowedFamilies) {
      n += countForWireFamily(wire);
    }
    return n;
  }

  int discouragedCount(FootwearFamilyGuidance guidance) {
    var n = 0;
    for (final wire in guidance.discouragedFamilies) {
      n += countForWireFamily(wire);
    }
    return n;
  }

  bool hasPreferred(FootwearFamilyGuidance guidance) =>
      preferredCount(guidance) > 0;

  bool hasAllowed(FootwearFamilyGuidance guidance) =>
      allowedCount(guidance) > 0;

  List<String> idsForWireFamilies(List<String> wireFamilies) {
    final ids = <String>[];
    for (final wire in wireFamilies) {
      for (final entry in itemsByFamily.entries) {
        if (entry.key.wireName != wire) continue;
        for (final item in entry.value) {
          final id = OutfitGenerationService.wardrobeItemId(item);
          if (id.isNotEmpty) ids.add(id);
        }
      }
    }
    return ids;
  }

  List<String> idsForPreferredFamilies(FootwearFamilyGuidance guidance) =>
      idsForWireFamilies(guidance.preferredFamilies);

  List<String> idsForDiscouragedFamilies(FootwearFamilyGuidance guidance) =>
      idsForWireFamilies(guidance.discouragedFamilies);
}

FootwearFamilyInventory footwearFamilyInventoryFromWardrobe(
  List<Map<String, dynamic>> wardrobe,
) {
  final byFamily = <FootwearFamily, List<Map<String, dynamic>>>{
    for (final f in FootwearFamily.values) f: <Map<String, dynamic>>[],
  };
  for (final raw in wardrobe) {
    if (!isFootwearWardrobeItem(raw)) continue;
    final family = classifyFootwearFamily(raw);
    byFamily[family]!.add(raw);
  }
  return FootwearFamilyInventory(byFamily);
}

void logFootwearFamilyFilter({
  required FootwearFamilyGuidance guidance,
  required FootwearFamilyInventory inventory,
  required bool excludedBoots,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[FOOTWEAR_FAMILY_FILTER] '
    'preferred=${guidance.preferredFamilies.join(",")} '
    'allowed=${guidance.allowedFamilies.join(",")} '
    'discouraged=${guidance.discouragedFamilies.join(",")} '
    'availablePreferredCount=${inventory.preferredCount(guidance)} '
    'availableAllowedCount=${inventory.allowedCount(guidance)} '
    'availableDiscouragedCount=${inventory.discouragedCount(guidance)} '
    'excludedBoots=$excludedBoots',
  );
}

bool previewHasDiscouragedFootwear({
  required OutfitPreview preview,
  required FootwearFamilyGuidance guidance,
}) {
  return guidance.isDiscouraged(classifyFootwearFamily(preview.shoes.item));
}

bool previewHasPreferredFootwear({
  required OutfitPreview preview,
  required FootwearFamilyGuidance guidance,
}) {
  return guidance.isPreferred(classifyFootwearFamily(preview.shoes.item));
}

void logHomeSwapFootwearGuidance({
  required OutfitWeatherSnapshot weather,
  required FootwearFamilyGuidance guidance,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[HOME_SWAP_FOOTWEAR_GUIDANCE] temp=${weather.tempC} rain=${weather.isRainy} '
    'preferred=${guidance.preferredFamilies.join(",")} '
    'allowed=${guidance.allowedFamilies.join(",")} '
    'discouraged=${guidance.discouragedFamilies.join(",")}',
  );
}

void logHomeSwapFootwearFilter({
  required FootwearFamilyGuidance guidance,
  required FootwearFamilyInventory inventory,
  required int shownCount,
  required int excludedCount,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[HOME_SWAP_FOOTWEAR_FILTER] '
    'availablePreferredCount=${inventory.preferredCount(guidance)} '
    'availableAllowedCount=${inventory.allowedCount(guidance)} '
    'availableDiscouragedCount=${inventory.discouragedCount(guidance)} '
    'shownCount=$shownCount '
    'excludedCount=$excludedCount',
  );
}

/// Excludes discouraged footwear when preferred/allowed footwear exists in wardrobe.
List<Map<String, dynamic>> filterSwapFootwearCandidates({
  required List<Map<String, dynamic>> candidates,
  required FootwearFamilyGuidance guidance,
  required FootwearFamilyInventory inventory,
}) {
  final preferredExists = inventory.hasPreferred(guidance);
  final allowedExists = inventory.hasAllowed(guidance);
  if (!preferredExists && !allowedExists) {
    logHomeSwapFootwearFilter(
      guidance: guidance,
      inventory: inventory,
      shownCount: candidates.length,
      excludedCount: 0,
    );
    return candidates;
  }

  final shown = candidates
      .where((raw) {
        if (!isFootwearWardrobeItem(raw)) return true;
        final family = classifyFootwearFamily(raw);
        return !guidance.isDiscouraged(family);
      })
      .toList(growable: false);

  logHomeSwapFootwearFilter(
    guidance: guidance,
    inventory: inventory,
    shownCount: shown.length,
    excludedCount: candidates.length - shown.length,
  );
  return shown;
}

/// If AI picked discouraged footwear but a better family exists, override index.
int applyFootwearFamilyGuard({
  required int selectedIndex,
  required List<OutfitPreview> candidates,
  required FootwearFamilyGuidance guidance,
  required List<double> ruleScores,
  required OutfitWeatherSnapshot weather,
}) {
  if (selectedIndex < 0 || selectedIndex >= candidates.length) return 0;

  final selectedShoes = candidates[selectedIndex].shoes.item;
  final selectedFamily = classifyFootwearFamily(selectedShoes);
  final selectedRainRisk = isRainDiscouragedFootwearItem(
    item: selectedShoes,
    weather: weather,
  );
  if (!guidance.isDiscouraged(selectedFamily) && !selectedRainRisk) {
    return selectedIndex;
  }

  int? bestPreferredIdx;
  double bestPreferredScore = -1e9;
  int? bestAllowedIdx;
  double bestAllowedScore = -1e9;

  for (var i = 0; i < candidates.length; i++) {
    final shoes = candidates[i].shoes.item;
    final family = classifyFootwearFamily(shoes);
    if (isRainDiscouragedFootwearItem(item: shoes, weather: weather)) {
      continue;
    }
    final score = i < ruleScores.length ? ruleScores[i] : 0.0;

    if (guidance.isPreferred(family) && score > bestPreferredScore) {
      bestPreferredScore = score;
      bestPreferredIdx = i;
    }
    if (guidance.isAllowed(family) &&
        !guidance.isDiscouraged(family) &&
        score > bestAllowedScore) {
      bestAllowedScore = score;
      bestAllowedIdx = i;
    }
  }

  final overrideIdx = bestPreferredIdx ?? bestAllowedIdx;
  if (overrideIdx == null || overrideIdx == selectedIndex) {
    return selectedIndex;
  }

  final toFamily = classifyFootwearFamily(candidates[overrideIdx].shoes.item);
  logVerboseHome(
    '[STYLIST_FINAL_REVIEW_GUARD_OVERRIDE] reason=${selectedRainRisk ? 'rain_risk_sport_sneaker' : 'discouraged_footwear_family'} '
    'fromIndex=$selectedIndex toIndex=$overrideIdx '
    'fromFamily=${selectedFamily.wireName} toFamily=${toFamily.wireName}',
  );
  return overrideIdx;
}
