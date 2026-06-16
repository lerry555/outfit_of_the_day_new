import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import 'home_debug_logging.dart';
import 'outerwear_policy.dart';
import 'stylist_layer_filter.dart';

/// Weather inputs for [ComfortTarget.fromWeather].
///
/// Supports the full Home weather snapshot as well as the slim
/// [OutfitWeatherSnapshot] used by the rule engine.
class ComfortWeatherInput {
  final int mainTempC;
  final int? morningTempC;
  final int? afternoonTempC;
  final int? eveningTempC;
  final int? minTempC;
  final int? maxTempC;
  final bool isRainy;
  final String? rainIntensity;
  final bool morningRainSegment;
  final bool afternoonRainSegment;
  final bool eveningRainSegment;
  final String? rainTimeText;
  final bool isWindy;
  final String? dayLabel;
  final bool fromOpenMeteo;

  const ComfortWeatherInput({
    required this.mainTempC,
    this.morningTempC,
    this.afternoonTempC,
    this.eveningTempC,
    this.minTempC,
    this.maxTempC,
    this.isRainy = false,
    this.rainIntensity,
    this.morningRainSegment = false,
    this.afternoonRainSegment = false,
    this.eveningRainSegment = false,
    this.rainTimeText,
    this.isWindy = false,
    this.dayLabel,
    this.fromOpenMeteo = false,
  });

  factory ComfortWeatherInput.fromOutfitWeatherSnapshot(
    OutfitWeatherSnapshot snap, {
    String? dayLabel,
  }) {
    return ComfortWeatherInput(
      mainTempC: snap.tempC,
      isRainy: snap.isRainy,
      isWindy: snap.isWindy,
      rainIntensity: snap.rainIntensity,
      dayLabel: dayLabel,
    );
  }
}

/// Target warmth for the wearer given weather (1.0–10.0).
class ComfortTarget {
  static const double defaultTolerance = 0.8;
  static const double hardBandWidth = 2.0;

  static const List<(double tempC, double ct)> _curvePoints = <(double, double)>[
    (-5, 9.5),
    (0, 8.5),
    (5, 7.5),
    (10, 6.5),
    (15, 5.2),
    (17, 4.8),
    (20, 3.5),
    (25, 2.5),
    (30, 1.8),
  ];

  final double value;
  final double tolerance;
  final double hardMin;
  final double hardMax;
  final String confidence;
  final Map<String, double> drivers;
  final String explanationSk;

  const ComfortTarget({
    required this.value,
    required this.tolerance,
    required this.hardMin,
    required this.hardMax,
    required this.confidence,
    required this.drivers,
    required this.explanationSk,
  });

  factory ComfortTarget.fromWeather(ComfortWeatherInput weather) {
    final effectiveTempC = _effectiveTempC(weather);
    final baseCt = _ctFromTemp(effectiveTempC);
    final rainAdj = _rainAdjustment(weather);
    final windAdj = weather.isWindy ? 0.6 : 0.0;
    final eveningAdj = _eveningAdjustment(weather);

    final rawValue =
        (baseCt + rainAdj + windAdj + eveningAdj).clamp(1.0, 10.0).toDouble();
    final hardMin = (rawValue - hardBandWidth).clamp(1.0, 10.0);
    final hardMax = (rawValue + hardBandWidth).clamp(1.0, 10.0);

    final drivers = <String, double>{
      'effectiveTempC': effectiveTempC,
      'baseCt': baseCt,
      'rainAdj': rainAdj,
      'windAdj': windAdj,
      'eveningAdj': eveningAdj,
    };

    return ComfortTarget(
      value: rawValue,
      tolerance: defaultTolerance,
      hardMin: hardMin,
      hardMax: hardMax,
      confidence: _confidenceFor(weather),
      drivers: drivers,
      explanationSk: _buildExplanationSk(
        weather: weather,
        value: rawValue,
        effectiveTempC: effectiveTempC,
        rainAdj: rainAdj,
        windAdj: windAdj,
        eveningAdj: eveningAdj,
      ),
    );
  }

  static double _effectiveTempC(ComfortWeatherInput weather) {
    final main = weather.mainTempC.toDouble();
    final segmentTemps = <double>[
      if (weather.morningTempC != null) weather.morningTempC!.toDouble(),
      if (weather.afternoonTempC != null) weather.afternoonTempC!.toDouble(),
      if (weather.eveningTempC != null) weather.eveningTempC!.toDouble(),
    ];
    final outingWindow = segmentTemps.isEmpty
        ? main
        : segmentTemps.reduce((a, b) => a + b) / segmentTemps.length;
    final minT = (weather.minTempC ?? weather.mainTempC).toDouble();
    return 0.6 * main + 0.3 * outingWindow + 0.1 * minT;
  }

  static double _ctFromTemp(double tempC) {
    if (tempC >= 30) return 1.8;
    if (tempC <= -5) return 9.5;

    for (var i = 0; i < _curvePoints.length - 1; i++) {
      final (t0, c0) = _curvePoints[i];
      final (t1, c1) = _curvePoints[i + 1];
      if (tempC >= t0 && tempC <= t1) {
        final ratio = (tempC - t0) / (t1 - t0);
        return c0 + (c1 - c0) * ratio;
      }
    }
    return 5.0;
  }

  static double _rainAdjustment(ComfortWeatherInput weather) {
    final intensity = (weather.rainIntensity ?? '').trim().toLowerCase();
    if (intensity == 'heavy' ||
        intensity == 'strong' ||
        intensity == 'intense') {
      return 1.2;
    }
    if (intensity == 'light' || intensity == 'drizzle') {
      return 0.3;
    }
    if (weather.isRainy) {
      return 0.7;
    }
    if (weather.morningRainSegment ||
        weather.afternoonRainSegment ||
        weather.eveningRainSegment) {
      return 0.3;
    }
    return 0.0;
  }

  static double _eveningAdjustment(ComfortWeatherInput weather) {
    final evening = weather.eveningTempC;
    if (evening == null) return 0.0;
    final drop = weather.mainTempC - evening;
    if (drop >= 6) return 0.8;
    if (drop >= 4) return 0.5;
    return 0.0;
  }

  static String _confidenceFor(ComfortWeatherInput weather) {
    final hasSegments = weather.morningTempC != null &&
        weather.afternoonTempC != null &&
        weather.eveningTempC != null;
    if (weather.fromOpenMeteo && hasSegments) return 'high';
    if (hasSegments || weather.isRainy || weather.isWindy) return 'medium';
    return 'low';
  }

  static String _buildExplanationSk({
    required ComfortWeatherInput weather,
    required double value,
    required double effectiveTempC,
    required double rainAdj,
    required double windAdj,
    required double eveningAdj,
  }) {
    final parts = <String>[
      'Cieľová pohoda ${value.toStringAsFixed(1)}/10',
      'pri efektívnej ${effectiveTempC.toStringAsFixed(1)}°C',
    ];
    if (rainAdj > 0) {
      parts.add(
        rainAdj >= 1.0
            ? 'silný dážď zvyšuje potrebu tepla'
            : 'dážď mierne zvyšuje potrebu tepla',
      );
    }
    if (windAdj > 0) {
      parts.add('vietor zvyšuje potrebu vrstiev');
    }
    if (eveningAdj > 0) {
      parts.add('večer bude chladnejšie');
    }
    if (weather.rainTimeText != null &&
        weather.rainTimeText!.trim().isNotEmpty) {
      parts.add('dážď: ${weather.rainTimeText!.trim()}');
    }
    return parts.join('; ');
  }
}

/// Layer-aware effective warmth of a full outfit (shadow metric only).
class EffectiveOutfitWarmth {
  final double value;
  final double deltaFromTarget;
  final double comfortScore;
  final List<String> notes;

  const EffectiveOutfitWarmth({
    required this.value,
    required this.deltaFromTarget,
    required this.comfortScore,
    required this.notes,
  });
}

EffectiveOutfitWarmth calculateEffectiveOutfitWarmth(
  List<Map<String, dynamic>> outfitItems, {
  required ComfortTarget target,
}) {
  final notes = <String>[];

  double? baseWarmth;
  double? midWarmth;
  double? outerWarmth;
  var bottomContribution = 0.0;
  var footwearContribution = 0.0;
  var accessoryContribution = 0.0;

  for (final item in outfitItems) {
    final layerRole = StylistLayerFilter.resolveEffectiveLayerRole(item);
    final warmth = StylistLayerFilter.inferWarmthLevel(item).toDouble();
    final name = (item['name'] ?? '').toString().trim();

    switch (layerRole) {
      case 'base_layer':
      case 'main_top':
        baseWarmth = warmth;
        if (name.isNotEmpty) notes.add('base:$name($warmth)');
      case 'mid_layer':
        midWarmth = warmth;
        if (name.isNotEmpty) notes.add('mid:$name($warmth)');
      case 'outer_layer':
        outerWarmth = warmth;
        if (name.isNotEmpty) notes.add('outer:$name($warmth)');
      case 'bottom':
      case 'base_bottom':
      case 'main_bottom':
      case 'one_piece':
        bottomContribution += warmth * 0.35;
        if (name.isNotEmpty) notes.add('bottom:$name($warmth)');
      case 'footwear':
        footwearContribution += warmth * 0.25;
        if (name.isNotEmpty) notes.add('footwear:$name($warmth)');
      case 'accessory':
        accessoryContribution += warmth * 0.1;
        if (name.isNotEmpty) notes.add('accessory:$name($warmth)');
      default:
        if (baseWarmth == null) {
          baseWarmth = warmth;
        } else if (midWarmth == null) {
          midWarmth = warmth;
        }
    }
  }

  final base = baseWarmth ?? 0.0;
  final midScaled = (midWarmth ?? 0.0) * 0.9;
  final outerScaled = (outerWarmth ?? 0.0) * 0.6;
  final torso = (base > midScaled ? base : midScaled) +
      (base < midScaled ? base : midScaled) * 0.3 +
      outerScaled;

  final eow =
      torso + bottomContribution + footwearContribution + accessoryContribution;
  final delta = eow - target.value;
  final comfortScore = 1.0 - (delta.abs() / 3.0).clamp(0.0, 1.0);

  if (delta.abs() > target.tolerance) {
    notes.add(
      delta > 0
          ? 'outfit_warmer_than_target'
          : 'outfit_cooler_than_target',
    );
  }
  if (eow < target.hardMin) {
    notes.add('below_hard_min');
  } else if (eow > target.hardMax) {
    notes.add('above_hard_max');
  }

  return EffectiveOutfitWarmth(
    value: eow,
    deltaFromTarget: delta,
    comfortScore: comfortScore,
    notes: notes,
  );
}

EffectiveOutfitWarmth calculateEffectiveOutfitWarmthForPreview(
  OutfitPreview preview, {
  required ComfortTarget target,
}) {
  final items = <Map<String, dynamic>>[
    preview.top.item,
    preview.bottom.item,
    preview.shoes.item,
    if (preview.outerwear != null) preview.outerwear!.item,
  ];
  return calculateEffectiveOutfitWarmth(items, target: target);
}

OutfitPreview outfitPreviewWithoutOuter(OutfitPreview preview) {
  if (preview.outerwear == null) return preview;
  return OutfitPreview(
    top: preview.top,
    bottom: preview.bottom,
    shoes: preview.shoes,
    outerwear: null,
  );
}

bool isEowWithinCtTolerance({
  required OutfitPreview preview,
  required ComfortTarget target,
}) {
  final warmth = calculateEffectiveOutfitWarmthForPreview(
    preview,
    target: target,
  );
  return warmth.deltaFromTarget.abs() <= ComfortTarget.defaultTolerance;
}

/// Phase 1: skip unnecessary outer when dry mild weather already fits CT.
bool shouldPreferNoOuterLayer({
  required OutfitPreview preview,
  required ComfortTarget? target,
  required OuterwearPolicy policy,
  required bool isRainy,
  required bool isWindy,
}) {
  if (policy != OuterwearPolicy.optional) return false;
  if (target == null) return false;
  if (isRainy || isWindy) return false;
  return isEowWithinCtTolerance(
    preview: outfitPreviewWithoutOuter(preview),
    target: target,
  );
}

String _formatDrivers(Map<String, double> drivers) {
  return drivers.entries
      .map((e) => '${e.key}=${e.value.toStringAsFixed(2)}')
      .join(',');
}

void logComfortTarget({
  required String? day,
  required ComfortTarget target,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[COMFORT_TARGET] '
    'day=${day ?? 'unknown'} '
    'ct=${target.value.toStringAsFixed(2)} '
    'tolerance=${target.tolerance.toStringAsFixed(2)} '
    'hardMin=${target.hardMin.toStringAsFixed(2)} '
    'hardMax=${target.hardMax.toStringAsFixed(2)} '
    'confidence=${target.confidence} '
    'drivers=${_formatDrivers(target.drivers)} '
    'explanation=${target.explanationSk.replaceAll('\n', ' ')}',
  );
}

void logComfortCandidate({
  required int index,
  required OutfitPreview preview,
  required ComfortTarget target,
  required EffectiveOutfitWarmth warmth,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  final items = [
    preview.top.label,
    preview.bottom.label,
    preview.shoes.label,
    if (preview.outerwear != null) preview.outerwear!.label,
  ].join(' | ');

  debugPrint(
    '[COMFORT_CANDIDATE] '
    'index=$index '
    'items=$items '
    'ct=${target.value.toStringAsFixed(2)} '
    'eow=${warmth.value.toStringAsFixed(2)} '
    'delta=${warmth.deltaFromTarget.toStringAsFixed(2)} '
    'comfortScore=${warmth.comfortScore.toStringAsFixed(2)} '
    'notes=${warmth.notes.join(",")}',
  );
}

void logComfortReviewSummary({
  required int candidateCount,
  required int bestComfortIndex,
  required double bestComfortScore,
  required int selectedByRulesIndex,
  required int currentFinalReviewCandidateCount,
}) {
  if (!kDebugMode || !kVerboseHomeLogs) return;
  debugPrint(
    '[COMFORT_REVIEW_SUMMARY] '
    'candidateCount=$candidateCount '
    'bestComfortIndex=$bestComfortIndex '
    'bestComfortScore=${bestComfortScore.toStringAsFixed(2)} '
    'selectedByRulesIndex=$selectedByRulesIndex '
    'currentFinalReviewCandidateCount=$currentFinalReviewCandidateCount',
  );
}
