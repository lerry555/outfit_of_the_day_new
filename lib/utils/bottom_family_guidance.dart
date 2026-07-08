import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import 'home_debug_logging.dart';

/// Bottom family for outfit generation and stylist final review.
enum BottomFamily {
  shorts,
  jeans,
  pants,
  joggers,
  other,
}

extension BottomFamilyWire on BottomFamily {
  String get wireName {
    switch (this) {
      case BottomFamily.shorts:
        return 'shorts';
      case BottomFamily.jeans:
        return 'jeans';
      case BottomFamily.pants:
        return 'pants';
      case BottomFamily.joggers:
        return 'joggers';
      case BottomFamily.other:
        return 'other';
    }
  }
}

class BottomFamilyGuidance {
  const BottomFamilyGuidance({
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

  bool isPreferred(BottomFamily family) =>
      preferredFamilies.contains(family.wireName);

  bool isAllowed(BottomFamily family) =>
      allowedFamilies.contains(family.wireName);

  bool isDiscouraged(BottomFamily family) =>
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

String _normKey(String raw) {
  var out = _normToken(raw);
  out = out.replaceAll(RegExp(r'[\s_\-/]+'), '');
  return out;
}

const Set<String> _nonBottomLayers = {
  'base_layer',
  'mid_layer',
  'outer_layer',
  'footwear',
  'accessory',
  'main_top',
};

const Set<String> _bottomLayerRoles = {
  'bottom',
  'base_bottom',
  'main_bottom',
  'one_piece',
};

const Set<String> _bottomCategoryKeys = {
  'nohavicerifle',
  'nohavice',
  'sortkysukne',
};

const Set<String> _bottomSubCategoryKeys = {
  'rifle',
  'rifleskinny',
  'riflewideleg',
  'riflemom',
  'nohaviceklasicke',
  'nohavicechino',
  'nohaviceteplakove',
  'nohavicejoggery',
  'nohaviceelegantne',
  'nohavicecargo',
  'sortky',
  'sortkysportove',
  'plaveckesortky',
  'sukna',
  'suknamini',
  'suknamidi',
  'suknamaxi',
  'leginy',
};

const Set<String> _shortsSubCategoryKeys = {
  'sortky',
  'sortkysportove',
  'plaveckesortky',
  'sportsortky',
};

bool _isShortSleeveTopName(String name) {
  final n = _normKey(name);
  if (n.isEmpty) return false;
  return n.contains('kratkymrukavom') ||
      n.contains('shortsleeve') ||
      n.contains('shortsleev') ||
      (n.contains('kratkym') && n.contains('rukav'));
}

bool _isBottomCanonical(String canonical) {
  final c = _normToken(canonical);
  if (c.isEmpty) return false;
  if (c.contains('sleeve')) return false;

  return c.contains('jean') ||
      c.contains('denim') ||
      c.contains('pant') ||
      c.contains('chino') ||
      c.contains('trouser') ||
      c.contains('jogger') ||
      c.contains('legging') ||
      c.contains('skirt') ||
      _isShortsCanonical(c);
}

bool _isShortsCanonical(String canonical) {
  final c = _normToken(canonical);
  if (c.isEmpty || c.contains('sleeve')) return false;
  return c == 'shorts' ||
      c.endsWith('shorts') ||
      c.contains('shorts') ||
      c.contains('bermuda');
}

bool _nameIndicatesShorts(String name) {
  if (_isShortSleeveTopName(name)) return false;
  final n = _normKey(name);
  return n.contains('sortky') ||
      n.contains('shortky') ||
      n.contains('bermuda') ||
      n.contains('swimshort');
}

bool _hasExplicitBottomIdentity(Map<String, dynamic> item) {
  final canonical =
      (item['canonical_type'] ?? item['canonicalType'] ?? '').toString().trim();
  final sub =
      (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString().trim();
  final cat = (item['categoryKey'] ?? item['category'] ?? '').toString().trim();

  final catNorm = _normKey(cat);
  final subNorm = _normKey(sub);

  if (_bottomCategoryKeys.contains(catNorm)) return true;
  if (_bottomSubCategoryKeys.contains(subNorm)) return true;
  if (_isBottomCanonical(canonical)) return true;
  return false;
}

bool _isBlockedNonBottomLayer(Map<String, dynamic> item) {
  final layer =
      (item['layer_role'] ?? item['layerRole'] ?? '').toString().trim();
  if (layer.isEmpty) return false;
  if (_bottomLayerRoles.contains(layer)) return false;
  return _nonBottomLayers.contains(layer);
}

int _warmthOf(Map<String, dynamic> item) {
  final raw = item['warmth_level'] ?? item['warmthLevel'];
  final n = num.tryParse(raw?.toString() ?? '');
  return n?.toInt() ?? 0;
}

/// Heavier bottoms (winter denim, fleece joggers, wool pants).
bool isHeavyBottomItem(Map<String, dynamic> item) {
  if (_warmthOf(item) >= 7) return true;
  final canonical =
      (item['canonical_type'] ?? item['canonicalType'] ?? '').toString();
  final sub =
      (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString();
  final cat = (item['categoryKey'] ?? item['category'] ?? '').toString();
  final name = (item['name'] ?? '').toString();
  final blob = '$canonical $sub $cat $name';
  return _blobContainsAny(blob, [
    'heavy',
    'winter',
    'zimn',
    'fleece',
    'flannel',
    'flanel',
    'wool',
    'vlnen',
    'corduroy',
    'manšestr',
    'mansetr',
    'thermal',
    'termo',
    'cargo',
    'teplak',
    'teplaky',
    'sherpa',
    'lined',
    'podšív',
    'podsiv',
  ]);
}

/// Classify bottom item into a family using canonical type, keys, and name.
BottomFamily classifyBottomFamily(Map<String, dynamic> item) {
  final canonical =
      (item['canonical_type'] ?? item['canonicalType'] ?? '').toString().trim();
  final sub =
      (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString().trim();
  final cat = (item['categoryKey'] ?? item['category'] ?? '').toString().trim();
  final name = (item['name'] ?? '').toString().trim();

  if (_isBlockedNonBottomLayer(item) && !_hasExplicitBottomIdentity(item)) {
    return BottomFamily.other;
  }
  if (_isShortSleeveTopName(name) && !_hasExplicitBottomIdentity(item)) {
    return BottomFamily.other;
  }

  final catNorm = _normKey(cat);
  final subNorm = _normKey(sub);
  final canonicalNorm = _normToken(canonical);

  if (_isShortsCanonical(canonicalNorm)) {
    return BottomFamily.shorts;
  }
  if (_shortsSubCategoryKeys.contains(subNorm)) {
    return BottomFamily.shorts;
  }
  if (catNorm == 'sortkysukne') {
    if (subNorm.contains('sukn')) return BottomFamily.pants;
    if (subNorm.contains('sortky') || _nameIndicatesShorts(name)) {
      return BottomFamily.shorts;
    }
  }

  if (canonicalNorm.contains('jogger') ||
      canonicalNorm.contains('sweatpant') ||
      subNorm == 'nohavicejoggery' ||
      subNorm == 'nohaviceteplakove') {
    return BottomFamily.joggers;
  }

  if (canonicalNorm.contains('jean') ||
      canonicalNorm.contains('denim') ||
      subNorm == 'rifle' ||
      subNorm.startsWith('rifle')) {
    return BottomFamily.jeans;
  }

  if (canonicalNorm.contains('pant') ||
      canonicalNorm.contains('chino') ||
      canonicalNorm.contains('trouser') ||
      canonicalNorm.contains('legging') ||
      canonicalNorm.contains('skirt') ||
      subNorm.startsWith('nohavice') ||
      subNorm.contains('sukn')) {
    return BottomFamily.pants;
  }

  if (_nameIndicatesShorts(name)) {
    return BottomFamily.shorts;
  }

  final nameNorm = _normKey(name);
  if (nameNorm.contains('rifle') || nameNorm.contains('dzins')) {
    return BottomFamily.jeans;
  }
  if (nameNorm.contains('nohavice') ||
      nameNorm.contains('leginy') ||
      nameNorm.contains('sukn')) {
    return BottomFamily.pants;
  }
  if (nameNorm.contains('jogger') || nameNorm.contains('teplak')) {
    return BottomFamily.joggers;
  }

  final layer =
      (item['layer_role'] ?? item['layerRole'] ?? '').toString().trim();
  if (_bottomLayerRoles.contains(layer)) return BottomFamily.pants;

  return BottomFamily.other;
}

bool isBottomDiscouragedForGuidance(
  Map<String, dynamic> item,
  BottomFamilyGuidance guidance,
) {
  final family = classifyBottomFamily(item);
  if (guidance.isPreferred(family)) return false;

  final heavy = isHeavyBottomItem(item);

  for (final wire in guidance.discouragedFamilies) {
    if (wire == 'heavy_jeans' &&
        family == BottomFamily.jeans &&
        heavy) {
      return true;
    }
    if (wire == 'heavy_pants' &&
        family == BottomFamily.pants &&
        heavy) {
      return true;
    }
    if (wire == family.wireName) return true;
  }
  return false;
}

bool isBottomAllowedForGuidance(
  Map<String, dynamic> item,
  BottomFamilyGuidance guidance,
) {
  if (isBottomDiscouragedForGuidance(item, guidance)) return false;

  final family = classifyBottomFamily(item);
  final heavy = isHeavyBottomItem(item);

  for (final wire in guidance.allowedFamilies) {
    if (wire == 'light_pants' &&
        family == BottomFamily.pants &&
        !heavy) {
      return true;
    }
    if (wire == family.wireName) return true;
  }
  return false;
}

bool isBottomPreferredForGuidance(
  Map<String, dynamic> item,
  BottomFamilyGuidance guidance,
) {
  final family = classifyBottomFamily(item);
  return guidance.isPreferred(family);
}

/// Heat comfort rules — rain alone does not change bottom guidance.
BottomFamilyGuidance computeBottomFamilyGuidance({
  required OutfitWeatherSnapshot weather,
}) {
  final temp = weather.tempC;
  final isSummer = weather.seasonKey == 'let';

  final preferred = <String>[];
  final allowed = <String>[];
  final discouraged = <String>[];
  late String reason;

  if (temp >= 26) {
    preferred.add(BottomFamily.shorts.wireName);
    allowed.add(BottomFamily.shorts.wireName);
    discouraged.addAll([
      BottomFamily.jeans.wireName,
      'heavy_pants',
      BottomFamily.joggers.wireName,
    ]);
    reason =
        'Heat (≥26°C): shorts preferred; long/heavy bottoms too warm (rain does not override).';
  } else if (temp >= 22) {
    preferred.add(BottomFamily.shorts.wireName);
    allowed.addAll([
      BottomFamily.shorts.wireName,
      'light_pants',
    ]);
    discouraged.add('heavy_jeans');
    reason = 'Warm (22–25°C): shorts preferred; heavy denim too warm.';
  } else if (temp >= 18) {
    preferred.addAll([
      BottomFamily.shorts.wireName,
      BottomFamily.pants.wireName,
    ]);
    allowed.addAll([
      BottomFamily.shorts.wireName,
      BottomFamily.pants.wireName,
      BottomFamily.jeans.wireName,
    ]);
    reason =
        'Mild (18–21°C): shorts and pants both comfortable; rain alone does not force long pants.';
  } else if (temp >= 15) {
    preferred.addAll([
      BottomFamily.pants.wireName,
      BottomFamily.jeans.wireName,
    ]);
    allowed.addAll([
      BottomFamily.pants.wireName,
      BottomFamily.jeans.wireName,
      BottomFamily.shorts.wireName,
    ]);
    reason = 'Cool (15–17°C): pants/jeans preferred; shorts still allowed.';
  } else {
    preferred.addAll([
      BottomFamily.pants.wireName,
      BottomFamily.jeans.wireName,
    ]);
    allowed.addAll([
      BottomFamily.pants.wireName,
      BottomFamily.jeans.wireName,
    ]);
    discouraged.add(BottomFamily.shorts.wireName);
    reason = 'Cold (≤14°C): long bottoms preferred.';
  }

  // V LETE pri miernom počasí (17–21 °C) ľudia bežne nosia kraťasy, nie dlhé
  // nohavice. Preto kraťasy spravíme jedinou preferovanou rodinou; dlhé nohavice
  // ostávajú len ako záloha (keď kraťasy v šatníku nie sú). Dážď to nemení.
  if (isSummer && temp >= 17 && temp < 22) {
    preferred
      ..clear()
      ..add(BottomFamily.shorts.wireName);
    allowed
      ..clear()
      ..addAll([
        BottomFamily.shorts.wireName,
        'light_pants',
        BottomFamily.jeans.wireName,
      ]);
    discouraged
      ..clear()
      ..addAll(['heavy_jeans', 'heavy_pants']);
    reason =
        'Leto, mierne (17–21°C): kraťasy preferované; dlhé nohavice len ako záloha.';
  }

  for (final p in preferred) {
    if (!allowed.contains(p)) allowed.add(p);
  }

  return BottomFamilyGuidance(
    preferredFamilies: preferred,
    allowedFamilies: allowed,
    discouragedFamilies: discouraged,
    reason: reason,
  );
}

/// Keď si používateľ VÝSLOVNE vyžiada konkrétny typ spodku (napr. šortky),
/// jeho voľba má prednosť pred počasím: daná rodina sa stane jedinou
/// preferovanou a ostatné spodné rodiny potlačíme, takže outfit naozaj
/// dostane to, čo si pýtal (ak to má v šatníku).
BottomFamilyGuidance forceBottomFamilyGuidance({
  required BottomFamily family,
  required BottomFamilyGuidance base,
}) {
  final others = <String>[
    BottomFamily.shorts.wireName,
    BottomFamily.jeans.wireName,
    BottomFamily.pants.wireName,
    BottomFamily.joggers.wireName,
  ]..remove(family.wireName);

  return BottomFamilyGuidance(
    preferredFamilies: <String>[family.wireName],
    allowedFamilies: <String>[family.wireName],
    discouragedFamilies: others,
    reason:
        'Používateľ si výslovne vyžiadal: ${family.wireName}. Ostatné spodné '
        'kúsky potlačené. (${base.reason})',
  );
}

void logBottomFamilyGuidance({
  required OutfitWeatherSnapshot weather,
  required BottomFamilyGuidance guidance,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[BOTTOM_FAMILY_GUIDANCE] temp=${weather.tempC} rain=${weather.isRainy} '
    'preferred=${guidance.preferredFamilies.join(",")} '
    'allowed=${guidance.allowedFamilies.join(",")} '
    'discouraged=${guidance.discouragedFamilies.join(",")} '
    'reason=${guidance.reason}',
  );
}

bool isBottomWardrobeItem(Map<String, dynamic> item) {
  final layer =
      (item['layer_role'] ?? item['layerRole'] ?? '').toString().trim();
  if (_bottomLayerRoles.contains(layer)) return true;

  if (_isBlockedNonBottomLayer(item) && !_hasExplicitBottomIdentity(item)) {
    return false;
  }

  if (_hasExplicitBottomIdentity(item)) return true;

  final catNorm =
      _normKey((item['categoryKey'] ?? item['category'] ?? '').toString());
  final subNorm = _normKey(
    (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString(),
  );

  if (_bottomCategoryKeys.contains(catNorm)) return true;
  if (_bottomSubCategoryKeys.contains(subNorm)) return true;

  return false;
}

/// Preferovaný spodok reálne použiteľný v matrix bottom poole (M6).
bool hasUsablePreferredBottom({
  required List<Map<String, dynamic>> wardrobe,
  required BottomFamilyGuidance guidance,
  Set<String> excludedItemIds = const {},
}) {
  for (final item in wardrobe) {
    if (!isBottomWardrobeItem(item)) continue;
    final id = OutfitGenerationService.wardrobeItemId(item);
    if (id.isEmpty || excludedItemIds.contains(id)) continue;
    if (guidance.isPreferred(classifyBottomFamily(item))) return true;
  }
  return false;
}

class BottomFamilyInventory {
  BottomFamilyInventory(this.itemsByFamily);

  final Map<BottomFamily, List<Map<String, dynamic>>> itemsByFamily;

  int countPreferred(BottomFamilyGuidance guidance) {
    var n = 0;
    for (final items in itemsByFamily.values) {
      for (final item in items) {
        if (isBottomPreferredForGuidance(item, guidance)) n++;
      }
    }
    return n;
  }

  int countAllowed(BottomFamilyGuidance guidance) {
    var n = 0;
    for (final items in itemsByFamily.values) {
      for (final item in items) {
        if (isBottomAllowedForGuidance(item, guidance)) n++;
      }
    }
    return n;
  }

  int countDiscouraged(BottomFamilyGuidance guidance) {
    var n = 0;
    for (final items in itemsByFamily.values) {
      for (final item in items) {
        if (isBottomDiscouragedForGuidance(item, guidance)) n++;
      }
    }
    return n;
  }

  bool hasPreferred(BottomFamilyGuidance guidance) =>
      countPreferred(guidance) > 0;

  bool hasAllowed(BottomFamilyGuidance guidance) => countAllowed(guidance) > 0;

  List<String> idsForPreferred(BottomFamilyGuidance guidance) {
    final ids = <String>[];
    for (final items in itemsByFamily.values) {
      for (final item in items) {
        if (!isBottomPreferredForGuidance(item, guidance)) continue;
        final id = OutfitGenerationService.wardrobeItemId(item);
        if (id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  List<String> idsForDiscouraged(BottomFamilyGuidance guidance) {
    final ids = <String>[];
    for (final items in itemsByFamily.values) {
      for (final item in items) {
        if (!isBottomDiscouragedForGuidance(item, guidance)) continue;
        final id = OutfitGenerationService.wardrobeItemId(item);
        if (id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }
}

BottomFamilyInventory bottomFamilyInventoryFromWardrobe(
  List<Map<String, dynamic>> wardrobe,
) {
  final byFamily = <BottomFamily, List<Map<String, dynamic>>>{
    for (final f in BottomFamily.values) f: <Map<String, dynamic>>[],
  };
  for (final raw in wardrobe) {
    if (!isBottomWardrobeItem(raw)) continue;
    final family = classifyBottomFamily(raw);
    byFamily[family]!.add(raw);
  }
  return BottomFamilyInventory(byFamily);
}

void logBottomFamilyAudit({
  required List<Map<String, dynamic>> wardrobe,
  required BottomFamilyGuidance guidance,
  required BottomFamilyInventory inventory,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;

  final bottomPool = <Map<String, dynamic>>[];
  for (final raw in wardrobe) {
    if (isBottomWardrobeItem(raw)) bottomPool.add(raw);
  }

  String describeItem(Map<String, dynamic> item) {
    final id = OutfitGenerationService.wardrobeItemId(item);
    final name = (item['name'] ?? '').toString().trim();
    final family = classifyBottomFamily(item).wireName;
    final layer =
        (item['layer_role'] ?? item['layerRole'] ?? '').toString().trim();
    final sub =
        (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString().trim();
    final cat =
        (item['categoryKey'] ?? item['category'] ?? '').toString().trim();
    final label = name.isNotEmpty ? name : sub;
    return '$label(id=$id,family=$family,layer=$layer,cat=$cat,sub=$sub)';
  }

  final preferredItems = <String>[];
  final discouragedItems = <String>[];
  for (final item in bottomPool) {
    if (isBottomPreferredForGuidance(item, guidance)) {
      preferredItems.add(describeItem(item));
    }
    if (isBottomDiscouragedForGuidance(item, guidance)) {
      discouragedItems.add(describeItem(item));
    }
  }

  debugPrint(
    '[BOTTOM_FAMILY_AUDIT] '
    'wardrobeCount=${wardrobe.length} '
    'sourcePoolCount=${wardrobe.length} '
    'bottomPoolCount=${bottomPool.length}',
  );
  debugPrint(
    '[BOTTOM_FAMILY_AUDIT] '
    'preferredItems=${preferredItems.isEmpty ? "(none)" : preferredItems.join(" | ")}',
  );
  debugPrint(
    '[BOTTOM_FAMILY_AUDIT] '
    'discouragedItems=${discouragedItems.isEmpty ? "(none)" : discouragedItems.join(" | ")}',
  );
  debugPrint(
    '[BOTTOM_FAMILY_AUDIT] '
    'inventoryPreferredCount=${inventory.countPreferred(guidance)} '
    'inventoryDiscouragedCount=${inventory.countDiscouraged(guidance)}',
  );
}

void logBottomFamilyFilter({
  required BottomFamilyGuidance guidance,
  required BottomFamilyInventory inventory,
  List<Map<String, dynamic>>? wardrobe,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[BOTTOM_FAMILY_FILTER] '
    'availablePreferredCount=${inventory.countPreferred(guidance)} '
    'availableAllowedCount=${inventory.countAllowed(guidance)} '
    'availableDiscouragedCount=${inventory.countDiscouraged(guidance)}',
  );
  if (wardrobe != null) {
    logBottomFamilyAudit(
      wardrobe: wardrobe,
      guidance: guidance,
      inventory: inventory,
    );
  }
}

bool previewHasDiscouragedBottom({
  required OutfitPreview preview,
  required BottomFamilyGuidance guidance,
}) {
  return isBottomDiscouragedForGuidance(preview.bottom.item, guidance);
}

bool previewHasPreferredBottom({
  required OutfitPreview preview,
  required BottomFamilyGuidance guidance,
}) {
  return isBottomPreferredForGuidance(preview.bottom.item, guidance);
}

List<Map<String, dynamic>> filterSwapBottomCandidates({
  required List<Map<String, dynamic>> candidates,
  required BottomFamilyGuidance guidance,
  required BottomFamilyInventory inventory,
}) {
  final preferredExists = inventory.hasPreferred(guidance);
  final allowedExists = inventory.hasAllowed(guidance);
  if (!preferredExists && !allowedExists) return candidates;

  return candidates
      .where((raw) {
        if (!isBottomWardrobeItem(raw)) return true;
        return !isBottomDiscouragedForGuidance(raw, guidance);
      })
      .toList(growable: false);
}

int applyPreferredBottomGuard({
  required int selectedIndex,
  required List<OutfitPreview> candidates,
  required BottomFamilyGuidance guidance,
  required List<double> ruleScores,
}) {
  if (guidance.preferredFamilies.isEmpty) return selectedIndex;
  if (selectedIndex < 0 || selectedIndex >= candidates.length) return selectedIndex;

  final selected = candidates[selectedIndex].bottom.item;
  if (isBottomPreferredForGuidance(selected, guidance)) return selectedIndex;

  int? bestPreferredIdx;
  var bestPreferredScore = -1e9;
  for (var i = 0; i < candidates.length; i++) {
    final bottom = candidates[i].bottom.item;
    if (!isBottomPreferredForGuidance(bottom, guidance)) continue;
    final score = i < ruleScores.length ? ruleScores[i] : 0.0;
    if (score > bestPreferredScore) {
      bestPreferredScore = score;
      bestPreferredIdx = i;
    }
  }
  return bestPreferredIdx ?? selectedIndex;
}

int applyBottomFamilyGuard({
  required int selectedIndex,
  required List<OutfitPreview> candidates,
  required BottomFamilyGuidance guidance,
  required List<double> ruleScores,
}) {
  if (selectedIndex < 0 || selectedIndex >= candidates.length) return 0;

  final selected = candidates[selectedIndex].bottom.item;
  if (!isBottomDiscouragedForGuidance(selected, guidance)) {
    return selectedIndex;
  }

  int? bestPreferredIdx;
  double bestPreferredScore = -1e9;
  int? bestAllowedIdx;
  double bestAllowedScore = -1e9;

  for (var i = 0; i < candidates.length; i++) {
    final bottom = candidates[i].bottom.item;
    final score = i < ruleScores.length ? ruleScores[i] : 0.0;

    if (isBottomPreferredForGuidance(bottom, guidance) &&
        score > bestPreferredScore) {
      bestPreferredScore = score;
      bestPreferredIdx = i;
    }
    if (isBottomAllowedForGuidance(bottom, guidance) &&
        !isBottomDiscouragedForGuidance(bottom, guidance) &&
        score > bestAllowedScore) {
      bestAllowedScore = score;
      bestAllowedIdx = i;
    }
  }

  final overrideIdx = bestPreferredIdx ?? bestAllowedIdx;
  if (overrideIdx == null || overrideIdx == selectedIndex) {
    return selectedIndex;
  }

  final fromFamily = classifyBottomFamily(selected);
  final toFamily = classifyBottomFamily(candidates[overrideIdx].bottom.item);
  debugPrint(
    '[STYLIST_FINAL_REVIEW_GUARD_OVERRIDE] reason=discouraged_bottom_family '
    'fromIndex=$selectedIndex toIndex=$overrideIdx '
    'fromFamily=${fromFamily.wireName} toFamily=${toFamily.wireName}',
  );
  return overrideIdx;
}
