import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import '../data/outfit_intent.dart';
import '../data/stylist_opinion.dart';
import '../data/wardrobe_analysis.dart';
import 'activity_outfit_identity.dart';
import 'bottom_family_guidance.dart';
import 'comfort_target.dart';
import 'footwear_family_guidance.dart';
import 'layer_harmony_guard.dart';
import 'outfit_intent_scorer.dart';
import 'stylist_occasion_guidance.dart';
import 'stylist_opinion_phrases.dart';

/// Deterministický engine osobného názoru stylistu (M7).
///
/// Read-only hodnotenie — nemení vybraný outfit.
class StylistOpinionEngine {
  const StylistOpinionEngine._();

  static const _weights = <String, double>{
    'dress_code_fit': 25,
    'weather_fit': 20,
    'completeness': 25,
    'color_harmony': 15,
    'activity_identity': 15,
  };

  static StylistOpinion evaluate({
    required OutfitPreview preview,
    required OutfitIntent intent,
    required OutfitWeatherSnapshot weather,
    required WardrobeAnalysis wardrobeAnalysis,
    required StylistOccasionProfile occasionProfile,
    ActivityIdentityResult? activityIdentity,
    bool wetGroundMuddy = false,
  }) {
    // Opinion má vlastný, prísnejší pohľad na identitu (napr. penalizuje outdoor
    // obuv na rande/kino/večeru). Nepoužívame preto selection identitu, ale
    // počítame vlastnú s forOpinion:true. Selection outfit sa tým nemení.
    final identity = ActivityOutfitIdentity.evaluate(
      preview: preview,
      intent: intent,
      wetGroundMuddy: wetGroundMuddy,
      forOpinion: true,
    );
    final comfortTarget = ComfortTarget.fromWeather(
      ComfortWeatherInput.fromOutfitWeatherSnapshot(weather),
    );

    final factors = <StylistOpinionFactor>[
      _dressCodeFit(
        preview: preview,
        intent: intent,
        occasionProfile: occasionProfile,
      ),
      _weatherFit(
        preview: preview,
        weather: weather,
        wardrobeAnalysis: wardrobeAnalysis,
        comfortTarget: comfortTarget,
        wetGroundMuddy: wetGroundMuddy,
      ),
      _completeness(wardrobeAnalysis: wardrobeAnalysis),
      _colorHarmony(preview: preview, weather: weather),
      _activityIdentity(identity: identity),
    ];

    var confidence = factors
        .map((f) => f.weightedPoints)
        .fold<double>(0, (sum, v) => sum + v)
        .round()
        .clamp(0, 100);

    final topEligibility = OutfitIntentScorer.classifyTopEligibility(
      item: preview.top.item,
      intent: intent,
    );
    final blockingGaps = wardrobeAnalysis.missingItems
        .where((g) => g.blocksIdealOutfit)
        .toList(growable: false);
    final formality = occasionProfile.dressCode.formalityTarget;

    final activityType = intent.activityType;
    final socialSmartCasual =
        ActivityOutfitIdentity.socialSmartCasualTypes.contains(activityType);
    final footwearOutdoor =
        ActivityOutfitIdentity.isOutdoorFootwearItem(preview.shoes.item);
    final bottomShorts = classifyBottomFamily(preview.bottom.item).wireName ==
        BottomFamily.shorts.wireName;
    // Rande/dinner so šortkami nemá byť „excellent" (rule 3).
    final socialShorts =
        (activityType == 'date' || activityType == 'dinner') && bottomShorts;

    confidence = _applyHonestyCaps(
      confidence: confidence,
      topForbidden: topEligibility.eligibility == ItemEligibility.forbidden,
      usedCompromise: wardrobeAnalysis.usedCompromise,
      blockingGapCount: blockingGaps.length,
      formality: formality,
      socialSmartOutdoor: socialSmartCasual && footwearOutdoor,
      socialShorts: socialShorts,
    );

    var level = _levelFromConfidence(confidence);
    level = _applyLevelOverrides(
      level: level,
      confidence: confidence,
      topForbidden: topEligibility.eligibility == ItemEligibility.forbidden,
      usedCompromise: wardrobeAnalysis.usedCompromise,
      blockingGapCount: blockingGaps.length,
      formality: formality,
      socialSmartOutdoor: socialSmartCasual && footwearOutdoor,
      socialShorts: socialShorts,
    );

    final biggestMissing = _biggestMissingPiece(blockingGaps);
    final weatherConcern =
        factors.firstWhere((f) => f.id == 'weather_fit').score < 0.5;

    final strengths = _buildStrengths(factors, intent.activityType);
    final compromises = _buildCompromises(
      wardrobeAnalysis: wardrobeAnalysis,
      blockingGaps: blockingGaps,
    );

    final occasionLabel = _occasionLabel(
      intent.activityType,
      occasionProfile.label,
    );

    final opinion = StylistOpinion(
      overallConfidence: confidence,
      opinionLevel: level,
      strengths: strengths,
      compromises: compromises,
      biggestMissingPiece: biggestMissing,
      shortOpinionSk: StylistOpinionPhrases.shortOpinion(
        level: level,
        occasionLabel: occasionLabel,
        biggestMissingPiece: biggestMissing,
        usedCompromise: wardrobeAnalysis.usedCompromise,
        weatherConcern: weatherConcern,
      ),
      factors: factors,
    );

    log(opinion);
    return opinion;
  }

  static void log(StylistOpinion opinion) {
    debugPrint(
      'STYLIST CHAT stylist_opinion { '
      'overallConfidence=${opinion.overallConfidence}, '
      'opinionLevel=${opinion.opinionLevel.wireName}, '
      'factors=${opinion.factors.map((f) => '${f.id}:${f.score.toStringAsFixed(2)}').join('|')}, '
      'biggestMissingPiece=${opinion.biggestMissingPiece ?? 'none'}, '
      'shortOpinionSk=${opinion.shortOpinionSk} '
      '}',
    );
  }

  static StylistOpinionFactor _dressCodeFit({
    required OutfitPreview preview,
    required OutfitIntent intent,
    required StylistOccasionProfile occasionProfile,
  }) {
    var raw = 1.0;
    final notes = <String>[];

    final topResult = OutfitIntentScorer.classifyTopEligibility(
      item: preview.top.item,
      intent: intent,
    );
    switch (topResult.eligibility) {
      case ItemEligibility.preferred:
        raw += 0.1;
        notes.add('top_preferred');
      case ItemEligibility.acceptable:
        raw -= 0.05;
        notes.add('top_acceptable');
      case ItemEligibility.compromise:
        raw -= 0.25;
        notes.add('top_compromise');
      case ItemEligibility.forbidden:
        raw -= 0.5;
        notes.add('top_forbidden');
    }

    final bottomFamily = classifyBottomFamily(preview.bottom.item).wireName;
    if (intent.bottomForbidden.contains(bottomFamily)) {
      raw -= 0.4;
      notes.add('bottom_forbidden');
    } else if (intent.bottomPreferred.isNotEmpty &&
        !intent.bottomPreferred.contains(bottomFamily)) {
      raw -= 0.15;
      notes.add('bottom_not_preferred');
    }

    final footwearFamily = classifyFootwearFamily(preview.shoes.item).wireName;
    if (intent.footwearForbidden.contains(footwearFamily)) {
      raw -= 0.4;
      notes.add('footwear_forbidden');
    } else if (intent.footwearPreferred.isNotEmpty &&
        !intent.footwearPreferred.contains(footwearFamily)) {
      raw -= 0.15;
      notes.add('footwear_not_preferred');
    }

    if (occasionProfile.isElevated && topResult.eligibility == ItemEligibility.compromise) {
      raw -= 0.1;
      notes.add('elevated_occasion_top_compromise');
    }

    return _factor(
      id: 'dress_code_fit',
      raw: raw,
      noteSk: notes.isEmpty ? 'dress_code_ok' : notes.join('|'),
    );
  }

  static StylistOpinionFactor _weatherFit({
    required OutfitPreview preview,
    required OutfitWeatherSnapshot weather,
    required WardrobeAnalysis wardrobeAnalysis,
    required ComfortTarget comfortTarget,
    required bool wetGroundMuddy,
  }) {
    final warmth = calculateEffectiveOutfitWarmthForPreview(
      preview,
      target: comfortTarget,
    );
    var raw = warmth.comfortScore;
    final notes = <String>['comfort=${warmth.comfortScore.toStringAsFixed(2)}'];

    final bottomFamily = classifyBottomFamily(preview.bottom.item).wireName;
    final footwearFamily = classifyFootwearFamily(preview.shoes.item).wireName;

    if ((weather.isRainy || wetGroundMuddy) &&
        bottomFamily == BottomFamily.shorts.wireName) {
      raw -= 0.3;
      notes.add('shorts_in_rain');
    }
    if (wetGroundMuddy &&
        footwearFamily == FootwearFamily.sandals.wireName) {
      raw -= 0.5;
      notes.add('sandals_wet_ground');
    }
    if (weather.tempC >= 24 &&
        _isDark(preview.top.item) &&
        _isDark(preview.bottom.item)) {
      raw -= 0.2;
      notes.add('dark_warm_weather');
    }
    if (wardrobeAnalysis.missingItems.any((g) => g.category == 'rain_jacket') &&
        preview.outerwear == null) {
      raw -= 0.15;
      notes.add('missing_outer_rain');
    }

    return _factor(
      id: 'weather_fit',
      raw: raw,
      noteSk: notes.join('|'),
    );
  }

  static StylistOpinionFactor _completeness({
    required WardrobeAnalysis wardrobeAnalysis,
  }) {
    var raw = 1.0;
    final notes = <String>[];

    for (final gap in wardrobeAnalysis.missingItems) {
      if (gap.blocksIdealOutfit) {
        raw -= 0.35;
        notes.add('gap_blocking:${gap.wireKey}');
      } else {
        raw -= 0.1;
        notes.add('gap_soft:${gap.wireKey}');
      }
    }
    if (wardrobeAnalysis.usedCompromise) {
      raw -= 0.2;
      notes.add('used_compromise');
    }
    if (wardrobeAnalysis.compromiseItems.length >= 2) {
      raw -= 0.1;
      notes.add('multiple_compromises');
    }

    return _factor(
      id: 'completeness',
      raw: raw,
      noteSk: notes.isEmpty ? 'wardrobe_complete' : notes.join('|'),
    );
  }

  static StylistOpinionFactor _colorHarmony({
    required OutfitPreview preview,
    required OutfitWeatherSnapshot weather,
  }) {
    final penalty = OutfitGenerationService.consistencyPenaltyForPreview(
      preview: preview,
    );
    var raw = (1.0 - penalty / 5.0).clamp(0.0, 1.0);
    final notes = <String>['penalty=${penalty.toStringAsFixed(2)}'];

    if (previewPassesLayerHarmonyGuard(
      preview: preview,
      tempC: weather.tempC,
      log: false,
    )) {
      raw = (raw + 0.1).clamp(0.0, 1.0);
      notes.add('layer_harmony_pass');
    }

    return _factor(
      id: 'color_harmony',
      raw: raw,
      noteSk: notes.join('|'),
    );
  }

  static StylistOpinionFactor _activityIdentity({
    required ActivityIdentityResult identity,
  }) {
    final raw = ((identity.score + 5) / 17).clamp(0.0, 1.0);
    return _factor(
      id: 'activity_identity',
      raw: raw,
      noteSk: identity.reasons.isEmpty
          ? 'identity_neutral'
          : identity.reasons.join('|'),
    );
  }

  static StylistOpinionFactor _factor({
    required String id,
    required double raw,
    required String noteSk,
  }) {
    return StylistOpinionFactor(
      id: id,
      score: raw.clamp(0.0, 1.0),
      weight: _weights[id]!,
      noteSk: noteSk,
    );
  }

  static int _applyHonestyCaps({
    required int confidence,
    required bool topForbidden,
    required bool usedCompromise,
    required int blockingGapCount,
    required int formality,
    bool socialSmartOutdoor = false,
    bool socialShorts = false,
  }) {
    var capped = confidence;
    if (topForbidden) capped = capped.clamp(0, 40);
    if (usedCompromise) capped = capped.clamp(0, 70);
    if (blockingGapCount > 0) capped = capped.clamp(0, 80);
    if (usedCompromise && formality >= 7) capped = capped.clamp(0, 60);
    if (blockingGapCount > 0) capped = capped.clamp(0, 65);
    // Rule 3: date/cinema/dinner + outdoor obuv → max 70.
    if (socialSmartOutdoor) capped = capped.clamp(0, 70);
    // Rule 3: date/dinner so šortkami → max 65.
    if (socialShorts) capped = capped.clamp(0, 65);
    return capped;
  }

  static StylistOpinionLevel _levelFromConfidence(int confidence) {
    if (confidence >= 82) return StylistOpinionLevel.excellent;
    if (confidence >= 65) return StylistOpinionLevel.good;
    if (confidence >= 45) return StylistOpinionLevel.acceptable;
    return StylistOpinionLevel.weak;
  }

  static StylistOpinionLevel _applyLevelOverrides({
    required StylistOpinionLevel level,
    required int confidence,
    required bool topForbidden,
    required bool usedCompromise,
    required int blockingGapCount,
    required int formality,
    bool socialSmartOutdoor = false,
    bool socialShorts = false,
  }) {
    if (topForbidden) return StylistOpinionLevel.weak;
    // Rule 3: date/dinner + šortky → max acceptable (najprísnejšie).
    if (socialShorts &&
        (level == StylistOpinionLevel.excellent ||
            level == StylistOpinionLevel.good)) {
      return StylistOpinionLevel.acceptable;
    }
    // Rule 3: date/cinema/dinner + outdoor obuv → max good.
    if (socialSmartOutdoor && level == StylistOpinionLevel.excellent) {
      return StylistOpinionLevel.good;
    }
    if (usedCompromise && level == StylistOpinionLevel.excellent) {
      return StylistOpinionLevel.good;
    }
    if (usedCompromise && formality >= 7) {
      if (level == StylistOpinionLevel.excellent ||
          level == StylistOpinionLevel.good) {
        return StylistOpinionLevel.acceptable;
      }
    }
    if (blockingGapCount >= 2 &&
        (level == StylistOpinionLevel.excellent ||
            level == StylistOpinionLevel.good)) {
      return StylistOpinionLevel.acceptable;
    }
    if (blockingGapCount > 0 && level == StylistOpinionLevel.excellent) {
      return StylistOpinionLevel.good;
    }
    return level;
  }

  static String _occasionLabel(String activityType, String dressCodeLabel) {
    final mapped = _activityLabel(activityType);
    if (activityType != 'casual' && mapped != activityType) return mapped;
    return dressCodeLabel.trim().isEmpty ? mapped : dressCodeLabel;
  }

  static String? _biggestMissingPiece(List<WardrobeGap> blockingGaps) {
    if (blockingGaps.isEmpty) return null;
    return StylistOpinionPhrases.missingPieceLabel(blockingGaps.first.category) ??
        blockingGaps.first.category;
  }

  static List<String> _buildStrengths(
    List<StylistOpinionFactor> factors,
    String activityType,
  ) {
    final strengths = <String>[];
    for (final factor in factors) {
      if (factor.score < 0.75) continue;
      var text = StylistOpinionPhrases.strengthForFactor(factor.id);
      if (factor.id == 'activity_identity' && text != null) {
        text = 'Outfit sedí na ${_activityLabel(activityType)}';
      }
      if (text != null) strengths.add(text);
      if (strengths.length >= 3) break;
    }
    return strengths;
  }

  static List<String> _buildCompromises({
    required WardrobeAnalysis wardrobeAnalysis,
    required List<WardrobeGap> blockingGaps,
  }) {
    final compromises = <String>[];
    for (final item in wardrobeAnalysis.compromiseItems) {
      compromises.add(StylistOpinionPhrases.compromiseForItem(item));
      if (compromises.length >= 3) return compromises;
    }
    for (final gap in blockingGaps) {
      if (gap.explanationSk.isNotEmpty) {
        compromises.add(gap.explanationSk);
      }
      if (compromises.length >= 3) break;
    }
    return compromises;
  }

  static String _activityLabel(String activityType) {
    return switch (activityType) {
      'wedding' => 'svadbu',
      'interview' => 'pohovor',
      'work' => 'prácu',
      'hike' => 'túru',
      'mushroom' => 'hubovanie',
      'barbecue' => 'grilovačku',
      'date' => 'rande',
      'cinema' => 'kino',
      'dinner' => 'večeru',
      _ => activityType,
    };
  }

  static bool _isDark(Map<String, dynamic> item) {
    final blob = [
      item['name'],
      item['category'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
    return blob.contains('čier') ||
        blob.contains('cier') ||
        blob.contains('black') ||
        blob.contains('tmav') ||
        blob.contains('dark') ||
        blob.contains('navy');
  }
}
