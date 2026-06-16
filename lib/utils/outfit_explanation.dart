import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import 'bottom_family_guidance.dart';
import 'comfort_target.dart';
import 'footwear_family_guidance.dart';
import 'home_debug_logging.dart';
import 'outerwear_policy.dart';
import 'stylist_layer_filter.dart';

enum ExplanationImportance {
  required,
  recommended,
  optional,
}

extension ExplanationImportanceWire on ExplanationImportance {
  String get wireName {
    switch (this) {
      case ExplanationImportance.required:
        return 'required';
      case ExplanationImportance.recommended:
        return 'recommended';
      case ExplanationImportance.optional:
        return 'optional';
    }
  }
}

/// Category for explanation entries (incl. future accessory recommendations).
enum OutfitExplanationKind {
  top,
  bottom,
  footwear,
  outerwear,
  weatherComfort,
  rainOutlook,
  wind,
  umbrella,
  sunglasses,
  hat,
  gloves,
  scarf,
}

extension OutfitExplanationKindWire on OutfitExplanationKind {
  String get logType {
    switch (this) {
      case OutfitExplanationKind.top:
        return 'top';
      case OutfitExplanationKind.bottom:
        return 'bottom';
      case OutfitExplanationKind.footwear:
        return 'footwear';
      case OutfitExplanationKind.outerwear:
        return 'outerwear';
      case OutfitExplanationKind.weatherComfort:
      case OutfitExplanationKind.rainOutlook:
      case OutfitExplanationKind.wind:
        return 'weather';
      case OutfitExplanationKind.umbrella:
      case OutfitExplanationKind.sunglasses:
      case OutfitExplanationKind.hat:
      case OutfitExplanationKind.gloves:
      case OutfitExplanationKind.scarf:
        return 'accessory';
    }
  }

  bool get isClothingPiece {
    switch (this) {
      case OutfitExplanationKind.top:
      case OutfitExplanationKind.bottom:
      case OutfitExplanationKind.footwear:
      case OutfitExplanationKind.outerwear:
        return true;
      default:
        return false;
    }
  }
}

class OutfitExplanationItem {
  const OutfitExplanationItem({
    required this.title,
    required this.description,
    required this.importance,
    required this.kind,
    required this.reason,
  });

  final String title;
  final String description;
  final ExplanationImportance importance;
  final OutfitExplanationKind kind;
  final String reason;
}

/// Hint for optional hero tiles (outerwear, umbrella, etc.) — not core staples.
class OutfitOptionalTileHint {
  const OutfitOptionalTileHint({
    required this.wearTypeKey,
    required this.title,
    required this.hint,
  });

  /// Matches hero wear slots, e.g. `outerwear`.
  final String wearTypeKey;
  final String title;
  final String hint;
}

class OutfitExplanationResult {
  const OutfitExplanationResult({
    required this.items,
    this.narrative = '',
    this.optionalTileHints = const [],
  });

  final List<OutfitExplanationItem> items;
  final String narrative;
  final List<OutfitOptionalTileHint> optionalTileHints;

  String get teaser {
    final story = narrative.trim();
    if (story.isNotEmpty) {
      for (final paragraph in story.split('\n\n')) {
        final p = paragraph.trim();
        if (p.contains('pridal aj') || p.contains('pridal ako')) {
          final dot = p.indexOf('.');
          if (dot > 20 && dot < 180) {
            return p.substring(0, dot + 1);
          }
        }
      }
      final dot = story.indexOf('.');
      if (dot > 24 && dot < 140) {
        return story.substring(0, dot + 1);
      }
      final words = story.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      final take = words.take(14).join(' ');
      return take.isEmpty ? story : '$take…';
    }
    if (items.isEmpty) return '';
    final clothing = items.where((e) => e.kind.isClothingPiece).toList();
    final source = clothing.isNotEmpty ? clothing : items;
    final first = source.first.description.trim();
    if (first.isEmpty) return '';
    final words = first.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final take = words.take(6).join(' ');
    return take.isEmpty ? first : '$take…';
  }
}

class OutfitStylistNarrative {
  const OutfitStylistNarrative._();

  static String compose({
    required List<OutfitExplanationItem> items,
    required OutfitPreview? preview,
    required ComfortWeatherInput weather,
    String dayOpener = 'Dnes',
  }) {
    if (items.isEmpty || preview == null) return '';

    final paragraphs = <String>[];

    final weatherParagraph = _paragraphWeather(
      weather: weather,
      dayOpener: dayOpener,
    );
    if (weatherParagraph.isNotEmpty) {
      paragraphs.add(weatherParagraph);
    }

    final hasOptionalOuter = _hasOptionalOuterInOutfit(preview, items);
    final coreParagraph = _paragraphCoreOutfit(
      items: items,
      preview: preview,
      briefBecauseOptionalOuter: hasOptionalOuter,
    );
    if (coreParagraph.isNotEmpty) {
      paragraphs.add(coreParagraph);
    }

    final optionalParagraph = _paragraphOptionalPieces(
      items: items,
      preview: preview,
      weather: weather,
    );
    if (optionalParagraph.isNotEmpty) {
      paragraphs.add(optionalParagraph);
    }

    final practicalParagraph = _paragraphPracticalAdvice(
      items: items,
      weather: weather,
      dayOpener: dayOpener,
      preview: preview,
    );
    if (practicalParagraph.isNotEmpty) {
      paragraphs.add(practicalParagraph);
    }

    return paragraphs.map(_ensurePeriod).join('\n\n');
  }

  static List<String> explainedOptionalItemLabels({
    required List<OutfitExplanationItem> items,
    required OutfitPreview? preview,
  }) {
    if (preview == null) return const [];
    final explained = <String>[];
    final outer = _first(items, OutfitExplanationKind.outerwear);
    if (outer != null && preview.outerwear != null) {
      explained.add(outer.title);
    }
    for (final item in items) {
      if (!_showsInfoOnTile(item, preview: preview)) continue;
      if (item.kind == OutfitExplanationKind.outerwear) continue;
      explained.add(item.title);
    }
    return explained;
  }

  static List<OutfitOptionalTileHint> optionalTileHints(
    List<OutfitExplanationItem> items, {
    required OutfitPreview? preview,
    required ComfortWeatherInput weather,
  }) {
    if (preview == null) return const [];
    final hints = <OutfitOptionalTileHint>[];
    for (final item in items) {
      if (!_showsInfoOnTile(item, preview: preview)) continue;
      final wearKey = _wearTypeKeyForKind(item.kind);
      if (wearKey == null) continue;
      hints.add(
        OutfitOptionalTileHint(
          wearTypeKey: wearKey,
          title: item.title,
          hint: _optionalHintText(item, weather: weather),
        ),
      );
    }
    return hints;
  }

  static bool _hasOptionalOuterInOutfit(
    OutfitPreview preview,
    List<OutfitExplanationItem> items,
  ) {
    if (preview.outerwear == null) return false;
    final outer = _first(items, OutfitExplanationKind.outerwear);
    return outer != null &&
        outer.importance == ExplanationImportance.optional;
  }

  static String _paragraphWeather({
    required ComfortWeatherInput weather,
    required String dayOpener,
  }) {
    final morning = weather.morningTempC;
    final afternoon = weather.afternoonTempC;
    final evening = weather.eveningTempC;
    final main = weather.mainTempC;

    if (morning != null && afternoon != null) {
      final tone = _dayTone(main, morning, afternoon);
      var text =
          '$dayOpener ťa čaká $tone deň — ráno okolo $morning °C, popoludní približne $afternoon °C';
      if (evening != null) {
        text += ', večer okolo $evening °C';
      }
      return '$text.';
    }
    return '$dayOpener počítame s teplotou okolo $main °C.';
  }

  static String _paragraphCoreOutfit({
    required List<OutfitExplanationItem> items,
    required OutfitPreview preview,
    required bool briefBecauseOptionalOuter,
  }) {
    final top = _first(items, OutfitExplanationKind.top);
    final bottom = _first(items, OutfitExplanationKind.bottom);
    final footwear = _first(items, OutfitExplanationKind.footwear);
    final corePieces =
        [top, bottom, footwear].whereType<OutfitExplanationItem>().toList();
    if (corePieces.isEmpty) return '';

    if (briefBecauseOptionalOuter && corePieces.length >= 3) {
      final titles =
          corePieces.map((e) => e.title.toLowerCase()).toList(growable: false);
      return 'Základ outfitu tvorí ${titles[0]}, ${titles[1]} a ${titles[2]} — '
          'jednoduchá a pohodlná kombinácia na takýto deň.';
    }

    final titles =
        corePieces.map((e) => e.title.toLowerCase()).toList(growable: false);
    final whyClauses = corePieces
        .map(_stylistClause)
        .where((c) => c.isNotEmpty)
        .toList(growable: false);
    if (titles.length >= 2 && whyClauses.isNotEmpty) {
      return 'Pre takýto deň som zvolil ${titles.join(', ')} — '
          '${whyClauses.join(' ')}';
    }
    if (whyClauses.isNotEmpty) {
      return 'Pre takýto deň ${whyClauses.first}';
    }
    return 'Základ outfitu tvorí ${titles.join(', ')}.';
  }

  static String _paragraphOptionalPieces({
    required List<OutfitExplanationItem> items,
    required OutfitPreview preview,
    required ComfortWeatherInput weather,
  }) {
    final segments = <String>[];

    final outer = _first(items, OutfitExplanationKind.outerwear);
    if (outer != null && preview.outerwear != null) {
      segments.add(
        _optionalOuterNarrative(
          outer: outer,
          preview: preview,
          weather: weather,
        ),
      );
    }

    for (final item in items) {
      if (item.kind == OutfitExplanationKind.outerwear) continue;
      if (!_showsInfoOnTile(item, preview: preview)) continue;
      segments.add(_optionalAccessoryNarrative(item));
    }

    return segments.join(' ');
  }

  static String _optionalOuterNarrative({
    required OutfitExplanationItem outer,
    required OutfitPreview preview,
    required ComfortWeatherInput weather,
  }) {
    final outerTitle = outer.title.toLowerCase();
    final topTitle = _coreTopLabel(preview);
    final morning = weather.morningTempC;
    final afternoon = weather.afternoonTempC;
    final evening = weather.eveningTempC;

    if (outer.importance == ExplanationImportance.required) {
      return '${_capitalizeFirst(outer.title)} je dôležitou súčasťou outfitu — '
          '${_lowercaseFirst(outer.description.trim())}';
    }

    if (morning != null && afternoon != null && afternoon >= morning + 3) {
      var text = 'Preto som k $topTitle pridal aj $outerTitle.';
      text += ' Počas dňa sa oteplí približne na $afternoon °C';
      if (evening != null) {
        text += ', takže ju pravdepodobne nebudeš potrebovať celý deň, '
            'ale ráno okolo $morning °C a večer okolo $evening °C sa môže hodiť';
      } else {
        text += ', takže ju pravdepodobne nebudeš potrebovať celý deň, '
            'ale ráno okolo $morning °C sa môže hodiť';
      }
      return text;
    }

    if (morning != null) {
      var text =
          'Preto som k $topTitle pridal aj $outerTitle — ráno bude okolo $morning °C';
      if (evening != null) {
        text += ' a večer okolo $evening °C';
      }
      text += ', takže ju odporúčame ako ľahkú vrstvu';
      return text;
    }

    return 'Preto som pridal aj $outerTitle — ${_lowercaseFirst(outer.description.trim())}';
  }

  static String _optionalAccessoryNarrative(OutfitExplanationItem item) {
    return _adaptDayLabel(item.description.trim(), 'Dnes');
  }

  static String _paragraphPracticalAdvice({
    required List<OutfitExplanationItem> items,
    required ComfortWeatherInput weather,
    required String dayOpener,
    required OutfitPreview preview,
  }) {
    final tips = <String>[];

    final rain = _first(items, OutfitExplanationKind.rainOutlook);
    if (rain != null) {
      tips.add(_adaptDayLabel(rain.description.trim(), dayOpener));
    }

    final wind = _first(items, OutfitExplanationKind.wind);
    if (wind != null) {
      tips.add(wind.description.trim());
    }

    final evening = weather.eveningTempC;
    final afternoon = weather.afternoonTempC;
    final hasOptionalOuter = preview.outerwear != null &&
        _first(items, OutfitExplanationKind.outerwear)?.importance ==
            ExplanationImportance.optional;
    if (hasOptionalOuter &&
        evening != null &&
        afternoon != null &&
        afternoon - evening >= 3 &&
        rain == null) {
      tips.add(
        'Večer môže byť chladnejšie okolo $evening °C — vrchnú vrstvu si '
        'môžeš nechať poruke.',
      );
    }

    if (tips.isEmpty) {
      return _humanComfortTip(weather: weather, dayOpener: dayOpener);
    }

    return tips.join(' ');
  }

  static String _humanComfortTip({
    required ComfortWeatherInput weather,
    required String dayOpener,
  }) {
    final morning = weather.morningTempC;
    final afternoon = weather.afternoonTempC;
    if (morning != null &&
        afternoon != null &&
        afternoon >= morning + 5) {
      return '$dayOpener sa výrazne oteplí — oblečenie by malo byť '
          'pohodlné počas celého dňa.';
    }
    if (morning != null && afternoon != null) {
      return 'Outfit by mal byť pohodlný od rána až do večera.';
    }
    return '';
  }

  static String _coreTopLabel(OutfitPreview preview) {
    final label = preview.top.label.trim();
    if (label.isEmpty) return 'tričku';
    return label.toLowerCase();
  }

  static bool _showsInfoOnTile(
    OutfitExplanationItem item, {
    required OutfitPreview preview,
  }) {
    switch (item.kind) {
      case OutfitExplanationKind.outerwear:
        return preview.outerwear != null &&
            item.importance == ExplanationImportance.optional;
      case OutfitExplanationKind.umbrella:
      case OutfitExplanationKind.sunglasses:
      case OutfitExplanationKind.hat:
      case OutfitExplanationKind.gloves:
      case OutfitExplanationKind.scarf:
        return item.importance == ExplanationImportance.optional;
      default:
        return false;
    }
  }

  static String? _wearTypeKeyForKind(OutfitExplanationKind kind) {
    switch (kind) {
      case OutfitExplanationKind.outerwear:
        return 'outerwear';
      case OutfitExplanationKind.umbrella:
      case OutfitExplanationKind.sunglasses:
      case OutfitExplanationKind.hat:
      case OutfitExplanationKind.gloves:
      case OutfitExplanationKind.scarf:
        return null;
      default:
        return null;
    }
  }

  static String _optionalHintText(
    OutfitExplanationItem item, {
    required ComfortWeatherInput weather,
  }) {
    if (item.kind == OutfitExplanationKind.outerwear) {
      return _optionalOuterHintText(item, weather);
    }
    final desc = item.description.trim();
    if (desc.isEmpty) return '${item.title} je voliteľná.';
    final lower = desc.toLowerCase();
    if (lower.startsWith('odporúčame')) {
      return desc;
    }
    return '${item.title} nie je nutná, ale odporúčame ju — $desc';
  }

  static String _optionalOuterHintText(
    OutfitExplanationItem item,
    ComfortWeatherInput weather,
  ) {
    final morning = weather.morningTempC;
    final evening = weather.eveningTempC;
    final reasons = <String>[];
    if (morning != null) {
      reasons.add('chladnejšiemu ránu okolo $morning °C');
    }
    if (evening != null) {
      reasons.add('večernej teplote $evening °C');
    }
    if (reasons.isEmpty) {
      return '${item.title} nie je nutná, ale môže sa hodiť ako ľahká rezerva.';
    }
    return '${item.title} nie je nutná, ale odporúčame ju kvôli '
        '${reasons.join(' a ')}.';
  }

  static OutfitExplanationItem? _first(
    List<OutfitExplanationItem> items,
    OutfitExplanationKind kind,
  ) {
    for (final item in items) {
      if (item.kind == kind) return item;
    }
    return null;
  }

  static String _dayTone(int main, int morning, int afternoon) {
    if (main >= 24 || afternoon >= 26) return 'teplý';
    if (main <= 5 || morning <= 2) return 'chladný';
    if (afternoon - morning >= 8) return 'premenlivý';
    return 'príjemný';
  }

  static String _stylistClause(OutfitExplanationItem item) {
    var desc = item.description.trim();
    if (desc.isEmpty) return '';

    final lower = desc.toLowerCase();
    final pretoIdx = lower.indexOf('preto ');
    if (pretoIdx >= 0) {
      desc = desc.substring(pretoIdx);
    } else if (lower.startsWith(item.title.toLowerCase())) {
      desc = desc.substring(item.title.length).trim();
      if (desc.startsWith('nie je')) {
        return _lowercaseFirst(desc);
      }
    }

    return _lowercaseFirst(desc);
  }

  static String _adaptDayLabel(String text, String dayOpener) {
    if (dayOpener == 'Dnes') return text;
    return text.replaceFirst(RegExp(r'^Dnes\b'), dayOpener);
  }

  static String _lowercaseFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toLowerCase() + text.substring(1);
  }

  static String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  static String _ensurePeriod(String text) {
    final t = text.trim();
    if (t.isEmpty) return t;
    if (t.endsWith('.') || t.endsWith('!') || t.endsWith('?')) return t;
    return '$t.';
  }
}

void logOutfitExplanation({
  required String item,
  required ExplanationImportance importance,
  required String reason,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[OUTFIT_EXPLANATION] '
    'item=$item '
    'importance=${importance.wireName} '
    'reason=$reason',
  );
}

void logOutfitExplanationItem({
  required String type,
  required String title,
  required String reason,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[OUTFIT_EXPLANATION_ITEM] '
    'type=$type '
    'title=$title '
    'reason=$reason',
  );
}

void logOutfitExplanationCoverage({
  required bool top,
  required bool bottom,
  required bool footwear,
  required bool weather,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[OUTFIT_EXPLANATION_COVERAGE] '
    'top=$top '
    'bottom=$bottom '
    'footwear=$footwear '
    'weather=$weather',
  );
}

void logOutfitExplanationSummary({required int count}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  logVerboseHome('[OUTFIT_EXPLANATION_SUMMARY] count=$count');
}

void logOutfitNarrativeAudit({
  required List<String> outfitItems,
  required List<String> optionalItems,
  required List<String> explainedOptionalItems,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[OUTFIT_NARRATIVE_AUDIT] '
    'outfitItems=${outfitItems.join('|')} '
    'optionalItems=${optionalItems.join('|')} '
    'explainedOptionalItems=${explainedOptionalItems.join('|')}',
  );
}

class OutfitExplanationBuilder {
  const OutfitExplanationBuilder._();

  static OutfitExplanationResult build({
    required OutfitPreview? preview,
    required ComfortWeatherInput comfortWeather,
    required OutfitWeatherSnapshot weatherSnap,
    String dayOpener = 'Dnes',
  }) {
    if (preview == null) {
      return const OutfitExplanationResult(items: []);
    }

    final clothingItems = <OutfitExplanationItem>[];
    final supplementalItems = <OutfitExplanationItem>[];

    final target = ComfortTarget.fromWeather(comfortWeather);
    final warmth = calculateEffectiveOutfitWarmthForPreview(
      preview,
      target: target,
    );
    final bottomGuidance = computeBottomFamilyGuidance(weather: weatherSnap);
    final footwearGuidance = computeFootwearFamilyGuidance(weather: weatherSnap);
    final outerPolicy = resolveOuterwearPolicy(
      tempC: weatherSnap.tempC,
      isRainy: weatherSnap.isRainy,
      isWindy: weatherSnap.isWindy,
    );

    _addTop(
      clothingItems,
      preview: preview,
      comfortWeather: comfortWeather,
      weatherSnap: weatherSnap,
    );
    _addBottom(
      clothingItems,
      preview: preview,
      guidance: bottomGuidance,
      comfortWeather: comfortWeather,
    );
    _addFootwear(
      clothingItems,
      preview: preview,
      guidance: footwearGuidance,
      weatherSnap: weatherSnap,
    );
    _addOuterwear(
      clothingItems,
      preview: preview,
      policy: outerPolicy,
      comfortWeather: comfortWeather,
      weatherSnap: weatherSnap,
    );

    _addWeatherComfort(
      supplementalItems,
      target: target,
      warmth: warmth,
    );
    _addRainOutlook(
      supplementalItems,
      comfortWeather: comfortWeather,
      weatherSnap: weatherSnap,
    );
    _addWind(
      supplementalItems,
      comfortWeather: comfortWeather,
      target: target,
    );
    _addFutureAccessories(
      supplementalItems,
      comfortWeather: comfortWeather,
      weatherSnap: weatherSnap,
    );

    final items = <OutfitExplanationItem>[
      ...clothingItems,
      ...supplementalItems,
    ];

    var hasTop = false;
    var hasBottom = false;
    var hasFootwear = false;
    var hasWeather = false;
    for (final entry in items) {
      logOutfitExplanation(
        item: entry.title,
        importance: entry.importance,
        reason: entry.reason,
      );
      logOutfitExplanationItem(
        type: entry.kind.logType,
        title: entry.title,
        reason: entry.reason,
      );
      hasTop = hasTop || entry.kind == OutfitExplanationKind.top;
      hasBottom = hasBottom || entry.kind == OutfitExplanationKind.bottom;
      hasFootwear = hasFootwear || entry.kind == OutfitExplanationKind.footwear;
      hasWeather = hasWeather || entry.kind.logType == 'weather';
    }

    logOutfitExplanationCoverage(
      top: hasTop,
      bottom: hasBottom,
      footwear: hasFootwear,
      weather: hasWeather,
    );
    logOutfitExplanationSummary(count: items.length);

    final narrative = OutfitStylistNarrative.compose(
      items: items,
      preview: preview,
      weather: comfortWeather,
      dayOpener: dayOpener,
    );
    final optionalTileHints = OutfitStylistNarrative.optionalTileHints(
      items,
      preview: preview,
      weather: comfortWeather,
    );
    logOutfitNarrativeAudit(
      outfitItems: _outfitItemLabels(preview),
      optionalItems: _optionalItemLabels(preview, items),
      explainedOptionalItems: OutfitStylistNarrative.explainedOptionalItemLabels(
        items: items,
        preview: preview,
      ),
    );

    return OutfitExplanationResult(
      items: items,
      narrative: narrative,
      optionalTileHints: optionalTileHints,
    );
  }

  static void _addTop(
    List<OutfitExplanationItem> items, {
    required OutfitPreview preview,
    required ComfortWeatherInput comfortWeather,
    required OutfitWeatherSnapshot weatherSnap,
  }) {
    final topItem = preview.top.item;
    final title = _itemTitle(preview.top.label, fallback: 'Vrchný diel');
    final morning = comfortWeather.morningTempC;
    final afternoon = comfortWeather.afternoonTempC;
    final main = comfortWeather.mainTempC;
    final isTank = StylistLayerFilter.isTankTopItem(topItem);
    final isShortSleeve = _isShortSleeveTop(topItem);
    final isLongSleeve = _isLongSleeveTop(topItem);
    final topWarmth = StylistLayerFilter.inferWarmthLevel(topItem);

    String description;
    String reason;

    if (isTank && main >= 22) {
      description =
          'Pri $main°C je tielko ľahkou a priedušnou voľbou na teplý deň.';
      reason = 'top_tank_warm_day';
    } else if (isShortSleeve && main >= 16) {
      if (morning != null &&
          afternoon != null &&
          afternoon >= morning + 4) {
        description =
            'Ráno bude okolo $morning°C a počas dňa približne $afternoon°C, preto je tričko vhodnou voľbou.';
        reason = 'top_short_sleeve_day_warms';
      } else {
        description =
            'Dnešných $main°C je ideálnych pre tričko s krátkym rukávom.';
        reason = 'top_short_sleeve_mild_temp';
      }
    } else if (isLongSleeve || topWarmth >= 5) {
      if (morning != null && morning < main - 1) {
        description =
            'Dlhší rukáv poskytuje pohodlie pri chladnejšom ráne okolo $morning°C.';
        reason = 'top_long_sleeve_cool_morning';
      } else {
        description =
            'Dlhší rukáv lepšie sedí k dnešnej teplote okolo $main°C.';
        reason = 'top_long_sleeve_cool_day';
      }
    } else if (morning != null &&
        afternoon != null &&
        afternoon >= morning + 4 &&
        main >= 14) {
      description =
          'Ráno bude okolo $morning°C a počas dňa približne $afternoon°C, preto je $title vhodnou voľbou.';
      reason = 'top_day_warms';
    } else if (weatherSnap.isRainy) {
      description =
          '$title drží vrstvy ľahké, no stále praktické pri dnešnom daždi okolo $main°C.';
      reason = 'top_rainy_day';
    } else {
      description =
          '$title sedí k dnešnej teplote okolo $main°C.';
      reason = 'top_temp_matched';
    }

    items.add(
      OutfitExplanationItem(
        title: title,
        description: description,
        importance: ExplanationImportance.required,
        kind: OutfitExplanationKind.top,
        reason: reason,
      ),
    );
  }

  static void _addBottom(
    List<OutfitExplanationItem> items, {
    required OutfitPreview preview,
    required BottomFamilyGuidance guidance,
    required ComfortWeatherInput comfortWeather,
  }) {
    final family = classifyBottomFamily(preview.bottom.item);
    final title = _itemTitle(
      preview.bottom.label,
      fallback: _bottomFamilyTitleSk(family),
    );
    final morning = comfortWeather.morningTempC;
    final afternoon = comfortWeather.afternoonTempC;
    final main = comfortWeather.mainTempC;
    final discouraged = guidance.isDiscouraged(family) ||
        isBottomDiscouragedForGuidance(preview.bottom.item, guidance);

    String description;
    String reason;
    var importance = ExplanationImportance.required;

    if (family == BottomFamily.shorts) {
      if (afternoon != null && morning != null && afternoon > morning + 2) {
        final hi = afternoon;
        final lo = afternoon > morning + 1 ? morning : afternoon - 1;
        description =
            'Počas dňa sa oteplí na približne $lo–$hi°C, preto sú šortky pohodlnou voľbou.';
        reason = 'bottom_shorts_day_warms';
      } else if (main >= 18) {
        description =
            'Pri $main°C sú šortky pohodlnou voľbou na suchý deň.';
        reason = 'bottom_shorts_warm_day';
      } else {
        description =
            'Šortky sú stále povolené, hoci pri $main°C uprednostňujeme dlhšie nohavice.';
        reason = 'bottom_shorts_allowed_cooler';
        importance = ExplanationImportance.optional;
      }
    } else if ((family == BottomFamily.jeans || family == BottomFamily.pants) &&
        morning != null &&
        morning < main - 1) {
      description =
          '$title sú vhodné na chladnejšie ráno okolo $morning°C.';
      reason = 'bottom_long_morning_cold';
    } else if (family == BottomFamily.jeans) {
      description =
          'Rifle poskytujú pohodlnú vrstvu pri dnešných $main°C.';
      reason = 'bottom_jeans_mild_day';
    } else if (family == BottomFamily.pants) {
      description =
          'Nohavice sú praktickou voľbou pri dnešných $main°C.';
      reason = 'bottom_pants_mild_day';
    } else if (family == BottomFamily.joggers) {
      description =
          'Tepláky sú pohodlné pri dnešných $main°C a menej formálnom dni.';
      reason = 'bottom_joggers_comfort';
    } else if (discouraged) {
      description =
          '$title nie je ideálna voľba pri $main°C, no stále ju považujeme za prijateľnú.';
      reason = 'bottom_discouraged_but_allowed';
      importance = ExplanationImportance.optional;
    } else if (guidance.isPreferred(family)) {
      description =
          '$title sú preferovanou voľbou pri dnešných $main°C.';
      reason = 'bottom_preferred_family';
    } else {
      description =
          '$title sú vhodné pri dnešných $main°C.';
      reason = 'bottom_allowed_family';
    }

    items.add(
      OutfitExplanationItem(
        title: title,
        description: description,
        importance: importance,
        kind: OutfitExplanationKind.bottom,
        reason: reason,
      ),
    );
  }

  static void _addFootwear(
    List<OutfitExplanationItem> items, {
    required OutfitPreview preview,
    required FootwearFamilyGuidance guidance,
    required OutfitWeatherSnapshot weatherSnap,
  }) {
    final family = classifyFootwearFamily(preview.shoes.item);
    final title = _itemTitle(
      preview.shoes.label,
      fallback: _footwearFamilyTitleSk(family),
    );

    String description;
    String reason;
    var importance = ExplanationImportance.required;

    if (guidance.isDiscouraged(family)) {
      description =
          '$title nie je pre dnešné počasie preferovaná, no zostáva použiteľná.';
      reason = 'footwear_discouraged_family';
      importance = ExplanationImportance.optional;
    } else if (family == FootwearFamily.sneakers && !weatherSnap.isRainy) {
      description =
          'Tenisky sú vhodné pre suché počasie a celodenné nosenie.';
      reason = 'footwear_sneakers_dry_day';
    } else if (family == FootwearFamily.sneakers && weatherSnap.isRainy) {
      description =
          'Tenisky sú praktické pri miernom daždi okolo ${weatherSnap.tempC}°C.';
      reason = 'footwear_sneakers_mild_rain';
    } else if (family == FootwearFamily.boots) {
      description = weatherSnap.isRainy
          ? 'Čižmy chránia pred dažďom a chladnejším povrchom.'
          : 'Čižmy poskytujú teplejšiu a stabilnejšiu voľbu pri ${weatherSnap.tempC}°C.';
      reason = 'footwear_boots_weather_match';
    } else if (family == FootwearFamily.sandals) {
      description =
          'Sandále sú ľahkou voľbou pri teplých $weatherSnap.tempC°C.';
      reason = 'footwear_sandals_warm_day';
    } else if (family == FootwearFamily.formalShoes) {
      description =
          'Elegantná obuv dopĺňa outfit pri dnešných ${weatherSnap.tempC}°C.';
      reason = 'footwear_formal_day';
    } else {
      description =
          '$title je vhodná pre dnešné počasie okolo ${weatherSnap.tempC}°C.';
      reason = guidance.isPreferred(family)
          ? 'footwear_preferred_family'
          : 'footwear_allowed_family';
    }

    items.add(
      OutfitExplanationItem(
        title: title,
        description: description,
        importance: importance,
        kind: OutfitExplanationKind.footwear,
        reason: reason,
      ),
    );
  }

  static void _addOuterwear(
    List<OutfitExplanationItem> items, {
    required OutfitPreview preview,
    required OuterwearPolicy policy,
    required ComfortWeatherInput comfortWeather,
    required OutfitWeatherSnapshot weatherSnap,
  }) {
    final hasOuter = preview.outerwear != null;
    if (!hasOuter) return;

    final title = _itemTitle(
      preview.outerwear!.label,
      fallback: 'Vrchná vrstva',
    );
    final morning = comfortWeather.morningTempC;
    final afternoon = comfortWeather.afternoonTempC;
    final evening = comfortWeather.eveningTempC;
    final eveningCools =
        evening != null && comfortWeather.mainTempC - evening >= 4;
    final policyReason = outerwearPolicyReason(
      tempC: weatherSnap.tempC,
      isRainy: weatherSnap.isRainy,
      isWindy: weatherSnap.isWindy,
      policy: policy,
    );

    String description;
    String reason;
    var importance = ExplanationImportance.optional;

    if (policy == OuterwearPolicy.required) {
      importance = ExplanationImportance.required;
      description = _outerRequiredDescription(
        weatherSnap: weatherSnap,
        policyReason: policyReason,
      );
      reason = policyReason;
    } else if (morning != null &&
        afternoon != null &&
        afternoon >= morning + 3) {
      description =
          'Nie je nutná celý deň — ráno okolo $morning °C sa môže hodiť, '
          'popoludní bude približne $afternoon °C'
          '${evening != null ? ', večer okolo $evening °C' : ''}.';
      reason = 'optional_outer_day_warms';
    } else if (morning != null && morning < weatherSnap.tempC - 1) {
      description =
          'Odporúčame ju kvôli chladnejšiemu ránu okolo $morning °C'
          '${evening != null ? ' a večernej teplote $evening °C' : ''}.';
      reason = 'optional_outer_cool_morning';
    } else if (eveningCools) {
      description =
          'Nie je nutná, ale môže sa hodiť večer, keď teplota klesne '
          'na $evening °C.';
      reason = 'optional_outer_evening_cooldown';
    } else if (weatherSnap.isWindy) {
      description =
          'Nie je nutná, ale vietor môže zvýšiť pocit chladu — '
          'môže sa hodiť ako ľahká vrstva.';
      reason = 'optional_outer_windy_day';
    } else {
      description =
          'Nie je nutná pre dennú teplotu, ale môže poslúžiť ako ľahká rezerva.';
      reason = 'optional_outer_reserve';
    }

    items.add(
      OutfitExplanationItem(
        title: title,
        description: description,
        importance: importance,
        kind: OutfitExplanationKind.outerwear,
        reason: reason,
      ),
    );
  }

  static void _addWeatherComfort(
    List<OutfitExplanationItem> items, {
    required ComfortTarget target,
    required EffectiveOutfitWarmth warmth,
  }) {
    final comfortNote = target.explanationSk.trim();
    if (comfortNote.isEmpty) return;

    var fitNote = '';
    if (warmth.deltaFromTarget.abs() <= target.tolerance) {
      fitNote = ' Outfit sedí do cieľovej tepelnej zóny.';
    } else if (warmth.deltaFromTarget > 0) {
      fitNote = ' Outfit je o niečo teplejší než cieľ.';
    } else {
      fitNote = ' Outfit je o niečo chladnejší než cieľ.';
    }

    items.add(
      OutfitExplanationItem(
        title: 'Pohoda v počasí',
        description: '$comfortNote$fitNote',
        importance: ExplanationImportance.recommended,
        kind: OutfitExplanationKind.weatherComfort,
        reason: 'comfort_target_${target.confidence}',
      ),
    );
  }

  static void _addRainOutlook(
    List<OutfitExplanationItem> items, {
    required ComfortWeatherInput comfortWeather,
    required OutfitWeatherSnapshot weatherSnap,
  }) {
    final hasRain = weatherSnap.isRainy ||
        comfortWeather.morningRainSegment ||
        comfortWeather.afternoonRainSegment ||
        comfortWeather.eveningRainSegment;

    if (!hasRain) return;

    final rainText = comfortWeather.rainTimeText?.trim();
    final description = rainText != null && rainText.isNotEmpty
        ? 'Dnes počítame s dažďom: $rainText.'
        : 'Dnes počítame s dažďom — zvoľte vhodné vrstvy a obuv.';

    items.add(
      OutfitExplanationItem(
        title: 'Dážď',
        description: description,
        importance: ExplanationImportance.recommended,
        kind: OutfitExplanationKind.rainOutlook,
        reason: weatherSnap.isHeavyRain ? 'heavy_rain_forecast' : 'rain_forecast',
      ),
    );
  }

  static void _addWind(
    List<OutfitExplanationItem> items, {
    required ComfortWeatherInput comfortWeather,
    required ComfortTarget target,
  }) {
    if (!comfortWeather.isWindy) return;
    final windAdj = target.drivers['windAdj'] ?? 0;
    items.add(
      OutfitExplanationItem(
        title: 'Vietor',
        description: windAdj > 0
            ? 'Vietor zvyšuje pocit chladu — vrstvy a uzavretá obuv pomáhajú.'
            : 'Dnes je veterno — zvážte vrstvy proti vetru.',
        importance: ExplanationImportance.recommended,
        kind: OutfitExplanationKind.wind,
        reason: 'windy_weather',
      ),
    );
  }

  static void _addFutureAccessories(
    List<OutfitExplanationItem> items, {
    required ComfortWeatherInput comfortWeather,
    required OutfitWeatherSnapshot weatherSnap,
  }) {
    final wantsUmbrella = weatherSnap.isRainy ||
        comfortWeather.morningRainSegment ||
        comfortWeather.afternoonRainSegment ||
        comfortWeather.eveningRainSegment;
    if (wantsUmbrella) {
      items.add(
        OutfitExplanationItem(
          title: 'Dáždnik',
          description: comfortWeather.rainTimeText?.trim().isNotEmpty == true
              ? 'Odporúčame dáždnik (${comfortWeather.rainTimeText!.trim()}).'
              : 'Odporúčame mať dáždnik poruke.',
          importance: ExplanationImportance.optional,
          kind: OutfitExplanationKind.umbrella,
          reason: 'umbrella_rain_expected',
        ),
      );
    }
  }

  static String _itemTitle(String label, {required String fallback}) {
    final trimmed = label.trim();
    return trimmed.isNotEmpty ? trimmed : fallback;
  }

  static bool _isShortSleeveTop(Map<String, dynamic> item) {
    if (StylistLayerFilter.isTankTopItem(item)) return false;

    final sub = _normKey(
      (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString(),
    );
    if (sub == 'tricko' ||
        sub == 'sporttricko' ||
        sub == 'polotricko' ||
        sub == 'croptop') {
      return true;
    }

    final canonical = _normToken(
      (item['canonical_type'] ?? item['canonicalType'] ?? '').toString(),
    );
    if (canonical.contains('t_shirt') ||
        canonical.contains('tshirt') ||
        canonical.contains('tee') ||
        canonical == 'tricko') {
      return true;
    }

    final name = _normToken((item['name'] ?? '').toString());
    return name.contains('kratkymrukavom') ||
        name.contains('shortsleeve') ||
        name.contains('tricko') && !name.contains('dlhym');
  }

  static bool _isLongSleeveTop(Map<String, dynamic> item) {
    final sub = _normKey(
      (item['subCategoryKey'] ?? item['subCategory'] ?? '').toString(),
    );
    if (sub == 'trickodlhyrukav') return true;

    final canonical = _normToken(
      (item['canonical_type'] ?? item['canonicalType'] ?? '').toString(),
    );
    if (canonical.contains('long_sleeve') || canonical.contains('longsleeve')) {
      return true;
    }

    final name = _normToken((item['name'] ?? '').toString());
    return name.contains('dlhymrukavom') ||
        name.contains('longsleeve') ||
        name.contains('rolak') ||
        name.contains('sveter');
  }

  static String _normToken(String raw) {
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

  static String _normKey(String raw) {
    return _normToken(raw).replaceAll(RegExp(r'[\s_\-/]+'), '');
  }

  static String _bottomFamilyTitleSk(BottomFamily family) {
    switch (family) {
      case BottomFamily.jeans:
        return 'Rifle';
      case BottomFamily.pants:
        return 'Nohavice';
      case BottomFamily.shorts:
        return 'Šortky';
      case BottomFamily.joggers:
        return 'Tepláky';
      case BottomFamily.other:
        return 'Spodný diel';
    }
  }

  static String _footwearFamilyTitleSk(FootwearFamily family) {
    switch (family) {
      case FootwearFamily.sneakers:
        return 'Tenisky';
      case FootwearFamily.boots:
        return 'Čižmy';
      case FootwearFamily.sandals:
        return 'Sandále';
      case FootwearFamily.formalShoes:
        return 'Elegantná obuv';
      case FootwearFamily.other:
        return 'Obuv';
    }
  }

  static String _outerRequiredDescription({
    required OutfitWeatherSnapshot weatherSnap,
    required String policyReason,
  }) {
    if (weatherSnap.isRainy) {
      return 'Dážď vyžaduje vrchnú vrstvu na ochranu pred počasím.';
    }
    if (weatherSnap.tempC < 10) {
      return 'Pri teplote okolo ${weatherSnap.tempC}°C je vrchná vrstva potrebná.';
    }
    if (weatherSnap.isWindy) {
      return 'Vietor zvyšuje pocit chladu — vrchná vrstva je vhodná.';
    }
    return 'Počasie vyžaduje vrchnú vrstvu ($policyReason).';
  }

  static List<String> _outfitItemLabels(OutfitPreview preview) {
    final labels = <String>[
      _itemTitle(preview.top.label, fallback: 'top'),
      _itemTitle(preview.bottom.label, fallback: 'bottom'),
      _itemTitle(preview.shoes.label, fallback: 'footwear'),
    ];
    if (preview.outerwear != null) {
      labels.add(
        _itemTitle(preview.outerwear!.label, fallback: 'outerwear'),
      );
    }
    return labels;
  }

  static List<String> _optionalItemLabels(
    OutfitPreview preview,
    List<OutfitExplanationItem> items,
  ) {
    final optional = <String>[];
    if (preview.outerwear != null) {
      final outer = items
          .where((e) => e.kind == OutfitExplanationKind.outerwear)
          .firstOrNull;
      if (outer != null &&
          outer.importance == ExplanationImportance.optional) {
        optional.add(outer.title);
      }
    }
    for (final item in items) {
      if (item.kind == OutfitExplanationKind.outerwear) continue;
      if (item.importance != ExplanationImportance.optional) continue;
      if (item.kind == OutfitExplanationKind.umbrella ||
          item.kind == OutfitExplanationKind.sunglasses ||
          item.kind == OutfitExplanationKind.hat ||
          item.kind == OutfitExplanationKind.gloves ||
          item.kind == OutfitExplanationKind.scarf) {
        optional.add(item.title);
      }
    }
    return optional;
  }
}
