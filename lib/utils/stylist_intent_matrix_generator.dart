import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import '../data/outfit_intent.dart';
import 'bottom_family_guidance.dart';
import 'footwear_family_guidance.dart';

List<String> _uniqueOrderedFamilies(List<String> values) {
  final seen = <String>{};
  final out = <String>[];
  for (final value in values) {
    if (seen.add(value)) out.add(value);
  }
  return out;
}

/// Vlna generovania matrixu — preferred → fallback → compromise (M3b).
enum MatrixGenerationWave { preferred, fallback, compromise }

/// Rodinové plány pre jednu vlnu matrixu.
class IntentMatrixWaveFamilies {
  const IntentMatrixWaveFamilies({
    required this.bottomFamilies,
    required this.footwearFamilies,
  });

  final List<String> bottomFamilies;
  final List<String> footwearFamilies;

  bool get isEmpty =>
      bottomFamilies.isEmpty && footwearFamilies.isEmpty;
}

/// Plán vĺn podľa OutfitIntent (M3a).
class IntentMatrixWavePlan {
  const IntentMatrixWavePlan({
    required this.preferred,
    required this.fallback,
    required this.compromise,
    required this.bottomPreferred,
    required this.bottomFallback,
    required this.bottomCompromise,
    required this.footwearPreferred,
    required this.footwearFallback,
    required this.footwearCompromise,
  });

  final IntentMatrixWaveFamilies preferred;
  final IntentMatrixWaveFamilies fallback;
  final IntentMatrixWaveFamilies compromise;

  final List<String> bottomPreferred;
  final List<String> bottomFallback;
  final List<String> bottomCompromise;
  final List<String> footwearPreferred;
  final List<String> footwearFallback;
  final List<String> footwearCompromise;

  String preferredFamiliesLog() =>
      'bottom:${bottomPreferred.join(">")}|footwear:${footwearPreferred.join(">")}';

  String fallbackFamiliesLog() =>
      'bottom:${bottomFallback.join(">")}|footwear:${footwearFallback.join(">")}';

  IntentMatrixWaveFamilies familiesFor(MatrixGenerationWave wave) {
    switch (wave) {
      case MatrixGenerationWave.preferred:
        return preferred;
      case MatrixGenerationWave.compromise:
        return compromise;
      case MatrixGenerationWave.fallback:
        return fallback;
    }
  }

  /// Kumulatívne rodiny pre vlnu — fallback zahŕňa preferred, compromise všetko povolené.
  IntentMatrixWaveFamilies cumulativeFamiliesFor(MatrixGenerationWave wave) {
    switch (wave) {
      case MatrixGenerationWave.preferred:
        return preferred;
      case MatrixGenerationWave.fallback:
        return IntentMatrixWaveFamilies(
          bottomFamilies: _uniqueOrderedFamilies([
            ...bottomPreferred,
            ...bottomFallback,
          ]),
          footwearFamilies: _uniqueOrderedFamilies([
            ...footwearPreferred,
            ...footwearFallback,
          ]),
        );
      case MatrixGenerationWave.compromise:
        return IntentMatrixWaveFamilies(
          bottomFamilies: _uniqueOrderedFamilies([
            ...bottomPreferred,
            ...bottomFallback,
            ...bottomCompromise,
          ]),
          footwearFamilies: _uniqueOrderedFamilies([
            ...footwearPreferred,
            ...footwearFallback,
            ...footwearCompromise,
          ]),
        );
    }
  }
}

/// Intent-first matrix generátor (M3a–M3d).
class StylistIntentMatrixGenerator {
  const StylistIntentMatrixGenerator._();

  static const _allBottomFamilies = [
    'shorts',
    'jeans',
    'pants',
    'joggers',
    'other',
  ];

  static const _allFootwearFamilies = [
    'sneakers',
    'boots',
    'sandals',
    'formal_shoes',
    'other',
  ];

  /// Koľko kandidátov stačí z vlny preferred na preskočenie ďalších vĺn.
  static const preferredWaveSufficientCount = 4;

  /// Penalizácia za opakovanie rovnakého kusu medzi kandidátmi (M3d).
  static const topRepeatPenalty = 2.4;
  static const bottomRepeatPenalty = 2.0;
  static const footwearRepeatPenalty = 1.6;

  static IntentMatrixWavePlan planWaves({
    required OutfitIntent intent,
    required BottomFamilyGuidance bottomGuidance,
    required FootwearFamilyGuidance footwearGuidance,
  }) {
    final bottomPreferred = List<String>.from(intent.bottomPreferred);
    final footwearPreferred = List<String>.from(intent.footwearPreferred);
    final bottomForbidden = intent.bottomForbidden.toSet();
    final footwearForbidden = intent.footwearForbidden.toSet();

    final bottomOrder = _buildBottomFamilyOrder(
      intent: intent,
      guidance: bottomGuidance,
      forbidden: bottomForbidden,
    );
    final footwearOrder = _buildFootwearFamilyOrder(
      intent: intent,
      guidance: footwearGuidance,
      forbidden: footwearForbidden,
    );

    final bottomPreferredSet = bottomPreferred.toSet();
    final footwearPreferredSet = footwearPreferred.toSet();

    final bottomFallback = <String>[];
    final bottomCompromise = <String>[];
    for (final family in bottomOrder) {
      if (bottomPreferredSet.contains(family) ||
          bottomForbidden.contains(family)) {
        continue;
      }
      if (_isCompromiseBottomFamily(
        family: family,
        intent: intent,
        guidance: bottomGuidance,
      )) {
        bottomCompromise.add(family);
      } else {
        bottomFallback.add(family);
      }
    }

    final footwearFallback = <String>[];
    final footwearCompromise = <String>[];
    for (final family in footwearOrder) {
      if (footwearPreferredSet.contains(family) ||
          footwearForbidden.contains(family)) {
        continue;
      }
      if (_isCompromiseFootwearFamily(
        family: family,
        intent: intent,
        guidance: footwearGuidance,
      )) {
        footwearCompromise.add(family);
      } else {
        footwearFallback.add(family);
      }
    }

    return IntentMatrixWavePlan(
      preferred: IntentMatrixWaveFamilies(
        bottomFamilies: bottomPreferred,
        footwearFamilies: footwearPreferred,
      ),
      fallback: IntentMatrixWaveFamilies(
        bottomFamilies: bottomFallback,
        footwearFamilies: footwearFallback,
      ),
      compromise: IntentMatrixWaveFamilies(
        bottomFamilies: bottomCompromise,
        footwearFamilies: footwearCompromise,
      ),
      bottomPreferred: bottomPreferred,
      bottomFallback: bottomFallback,
      bottomCompromise: bottomCompromise,
      footwearPreferred: footwearPreferred,
      footwearFallback: footwearFallback,
      footwearCompromise: footwearCompromise,
    );
  }

  static List<String> _buildBottomFamilyOrder({
    required OutfitIntent intent,
    required BottomFamilyGuidance guidance,
    required Set<String> forbidden,
  }) {
    final ordered = <String>[];
    final seen = <String>{};
    void add(String family) {
      if (forbidden.contains(family)) return;
      if (seen.add(family)) ordered.add(family);
    }

    for (final family in intent.bottomPreferred) {
      add(family);
    }
    for (final family in _orderedBottomFamilies(guidance)) {
      add(family);
    }
    return ordered;
  }

  static List<String> _buildFootwearFamilyOrder({
    required OutfitIntent intent,
    required FootwearFamilyGuidance guidance,
    required Set<String> forbidden,
  }) {
    final ordered = <String>[];
    final seen = <String>{};
    void add(String family) {
      if (forbidden.contains(family)) return;
      if (seen.add(family)) ordered.add(family);
    }

    for (final family in intent.footwearPreferred) {
      add(family);
    }
    for (final family in _orderedFootwearFamilies(guidance)) {
      add(family);
    }
    return ordered;
  }

  /// Compromise = posledná možnosť (šortky na túre, rifle na túre), nie soft fallback (rifle na svadbe).
  static bool _isCompromiseBottomFamily({
    required String family,
    required OutfitIntent intent,
    required BottomFamilyGuidance guidance,
  }) {
    final mapped = _bottomWireToFamily(family);
    if (mapped == null) return guidance.discouragedFamilies.contains(family);

    if (family == 'shorts') {
      return intent.activityType == 'hike' ||
          intent.activityType == 'mushroom' ||
          guidance.isDiscouraged(BottomFamily.shorts);
    }
    return false;
  }

  static bool _isCompromiseFootwearFamily({
    required String family,
    required OutfitIntent intent,
    required FootwearFamilyGuidance guidance,
  }) {
    for (final f in FootwearFamily.values) {
      if (f.wireName != family) continue;
      if (family == 'sandals') {
        return guidance.isDiscouraged(f) &&
            intent.footwearForbidden.contains(family);
      }
      return false;
    }
    return false;
  }

  static List<String> _orderedBottomFamilies(BottomFamilyGuidance guidance) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final wire in guidance.allowedFamilies) {
      final family = _bottomWireToFamily(wire);
      if (family == null) continue;
      final name = family.wireName;
      if (seen.add(name)) ordered.add(name);
    }
    for (final name in _allBottomFamilies) {
      if (seen.add(name)) ordered.add(name);
    }
    return ordered;
  }

  static List<String> _orderedFootwearFamilies(
    FootwearFamilyGuidance guidance,
  ) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final wire in guidance.allowedFamilies) {
      if (seen.add(wire)) ordered.add(wire);
    }
    for (final name in _allFootwearFamilies) {
      if (seen.add(name)) ordered.add(name);
    }
    return ordered;
  }

  static BottomFamily? _bottomWireToFamily(String wire) {
    switch (wire) {
      case 'shorts':
        return BottomFamily.shorts;
      case 'jeans':
      case 'heavy_jeans':
        return BottomFamily.jeans;
      case 'pants':
      case 'light_pants':
      case 'heavy_pants':
        return BottomFamily.pants;
      case 'joggers':
        return BottomFamily.joggers;
      default:
        return null;
    }
  }

  /// M3c — compromise len keď v šatníku nie sú preferred rodiny.
  static bool preferredOutfitPossible({
    required List<Map<String, dynamic>> wardrobe,
    required IntentMatrixWavePlan plan,
    required OutfitIntent intent,
    required Set<String> excludedItemIds,
  }) {
    final hasPreferredBottom = plan.bottomPreferred.isNotEmpty &&
        _bottomIdsForFamilies(
          wardrobe: wardrobe,
          families: plan.bottomPreferred,
          forbidden: intent.bottomForbidden.toSet(),
          excludedItemIds: excludedItemIds,
        ).isNotEmpty;
    final hasPreferredFootwear = plan.footwearPreferred.isNotEmpty &&
        _footwearIdsForFamilies(
          wardrobe: wardrobe,
          families: plan.footwearPreferred,
          forbidden: intent.footwearForbidden.toSet(),
          excludedItemIds: excludedItemIds,
        ).isNotEmpty;
    return hasPreferredBottom && hasPreferredFootwear;
  }

  static Set<String> _bottomIdsForFamilies({
    required List<Map<String, dynamic>> wardrobe,
    required List<String> families,
    required Set<String> forbidden,
    required Set<String> excludedItemIds,
  }) {
    if (families.isEmpty) return const {};
    final familySet = families.toSet();
    return wardrobe
        .where(isBottomWardrobeItem)
        .where(
          (item) => familySet.contains(classifyBottomFamily(item).wireName),
        )
        .where(
          (item) => !forbidden.contains(classifyBottomFamily(item).wireName),
        )
        .map(OutfitGenerationService.wardrobeItemId)
        .where((id) => id.isNotEmpty && !excludedItemIds.contains(id))
        .toSet();
  }

  static Set<String> _footwearIdsForFamilies({
    required List<Map<String, dynamic>> wardrobe,
    required List<String> families,
    required Set<String> forbidden,
    required Set<String> excludedItemIds,
  }) {
    if (families.isEmpty) return const {};
    final familySet = families.toSet();
    return wardrobe
        .where(isFootwearWardrobeItem)
        .where(
          (item) => familySet.contains(classifyFootwearFamily(item).wireName),
        )
        .where(
          (item) =>
              !forbidden.contains(classifyFootwearFamily(item).wireName),
        )
        .map(OutfitGenerationService.wardrobeItemId)
        .where((id) => id.isNotEmpty && !excludedItemIds.contains(id))
        .toSet();
  }

  /// Preferred vlna: ak chýba obuv/spodok v šatníku, rozšíri druhý slot o fallback rodiny.
  static ({
    Set<String> bottomIds,
    Set<String> footwearIds,
    List<String> bottomFamiliesUsed,
    List<String> footwearFamiliesUsed,
  }) _resolveWavePools({
    required MatrixGenerationWave wave,
    required IntentMatrixWavePlan plan,
    required List<Map<String, dynamic>> wardrobe,
    required Set<String> bottomForbidden,
    required Set<String> footwearForbidden,
    required Set<String> excludedItemIds,
  }) {
    final families = wave == MatrixGenerationWave.preferred
        ? plan.familiesFor(wave)
        : plan.cumulativeFamiliesFor(wave);

    var bottomFamilies = List<String>.from(families.bottomFamilies);
    var footwearFamilies = List<String>.from(families.footwearFamilies);

    var bottomIds = _bottomIdsForFamilies(
      wardrobe: wardrobe,
      families: bottomFamilies,
      forbidden: bottomForbidden,
      excludedItemIds: excludedItemIds,
    );
    var footwearIds = _footwearIdsForFamilies(
      wardrobe: wardrobe,
      families: footwearFamilies,
      forbidden: footwearForbidden,
      excludedItemIds: excludedItemIds,
    );

    if (wave == MatrixGenerationWave.preferred) {
      if (bottomIds.isNotEmpty && footwearIds.isEmpty) {
        footwearFamilies = _uniqueOrderedFamilies([
          ...plan.footwearPreferred,
          ...plan.footwearFallback,
        ]);
        footwearIds = _footwearIdsForFamilies(
          wardrobe: wardrobe,
          families: footwearFamilies,
          forbidden: footwearForbidden,
          excludedItemIds: excludedItemIds,
        );
      } else if (footwearIds.isNotEmpty && bottomIds.isEmpty) {
        bottomFamilies = _uniqueOrderedFamilies([
          ...plan.bottomPreferred,
          ...plan.bottomFallback,
        ]);
        bottomIds = _bottomIdsForFamilies(
          wardrobe: wardrobe,
          families: bottomFamilies,
          forbidden: bottomForbidden,
          excludedItemIds: excludedItemIds,
        );
      }
    }

    return (
      bottomIds: bottomIds,
      footwearIds: footwearIds,
      bottomFamiliesUsed: bottomFamilies,
      footwearFamiliesUsed: footwearFamilies,
    );
  }

  /// Verejný wrapper pre unit testy (M4).
  @visibleForTesting
  static ({
    Set<String> bottomIds,
    Set<String> footwearIds,
    List<String> bottomFamiliesUsed,
    List<String> footwearFamiliesUsed,
  }) resolveWavePoolsForTest({
    required MatrixGenerationWave wave,
    required IntentMatrixWavePlan plan,
    required List<Map<String, dynamic>> wardrobe,
    required Set<String> bottomForbidden,
    required Set<String> footwearForbidden,
    required Set<String> excludedItemIds,
  }) {
    return _resolveWavePools(
      wave: wave,
      plan: plan,
      wardrobe: wardrobe,
      bottomForbidden: bottomForbidden,
      footwearForbidden: footwearForbidden,
      excludedItemIds: excludedItemIds,
    );
  }

  static double diversityPenaltyForPreview({
    required OutfitPreview preview,
    required Set<String> usedTopIds,
    required Set<String> usedBottomIds,
    required Set<String> usedFootwearIds,
  }) {
    var penalty = 0.0;
    final topId = OutfitGenerationService.wardrobeItemId(preview.top.item);
    final bottomId = OutfitGenerationService.wardrobeItemId(preview.bottom.item);
    final shoeId = OutfitGenerationService.wardrobeItemId(preview.shoes.item);
    if (topId.isNotEmpty && usedTopIds.contains(topId)) {
      penalty += topRepeatPenalty;
    }
    if (bottomId.isNotEmpty && usedBottomIds.contains(bottomId)) {
      penalty += bottomRepeatPenalty;
    }
    if (shoeId.isNotEmpty && usedFootwearIds.contains(shoeId)) {
      penalty += footwearRepeatPenalty;
    }
    return penalty;
  }

  static void _logMatrixGeneration({
    required MatrixGenerationWave wave,
    required IntentMatrixWavePlan plan,
    required int generatedCandidates,
    required int skippedCandidates,
    required double diversityPenalty,
  }) {
    debugPrint(
      'STYLIST CHAT matrix_generation { '
      'wave=${wave.name}, '
      'preferredFamilies=${plan.preferredFamiliesLog()}, '
      'fallbackFamilies=${plan.fallbackFamiliesLog()}, '
      'generatedCandidates=$generatedCandidates, '
      'skippedCandidates=$skippedCandidates, '
      'diversityPenalty=${diversityPenalty.toStringAsFixed(2)} '
      '}',
    );
  }

  static int _countUsableTops(List<Map<String, dynamic>> wardrobe) {
    return wardrobe.where((item) {
      if (isBottomWardrobeItem(item) || isFootwearWardrobeItem(item)) {
        return false;
      }
      final layer =
          (item['layer_role'] ?? item['layerRole'] ?? '').toString().trim();
      if (layer == 'main_top' ||
          layer == 'base_layer' ||
          layer == 'mid_layer') {
        return true;
      }
      final name = (item['name'] ?? '').toString().toLowerCase();
      final canonical = (item['canonical_type'] ?? item['canonicalType'] ?? '')
          .toString()
          .toLowerCase();
      final blob = '$name $canonical';
      return blob.contains('trič') ||
          blob.contains('trick') ||
          blob.contains('shirt') ||
          blob.contains('kosel') ||
          blob.contains('bluz') ||
          blob.contains('polo') ||
          blob.contains('sveter') ||
          blob.contains('blouse');
    }).length;
  }

  /// Minimálny počet kandidátov podľa scenára (M6).
  static int minimumCandidatesForIntent({
    required OutfitIntent intent,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    final topCount = _countUsableTops(wardrobe);
    final shortsCount = wardrobe
        .where(
          (item) =>
              isBottomWardrobeItem(item) &&
              classifyBottomFamily(item) == BottomFamily.shorts,
        )
        .length;

    switch (intent.activityType) {
      case 'wedding':
      case 'interview':
        return 2;
      case 'work':
        return topCount >= 2 ? 4 : 1;
      case 'barbecue':
        return (topCount >= 2 || shortsCount >= 2) ? 4 : 1;
      case 'mushroom':
        return 4;
      case 'hike':
        return 2;
      default:
        return 2;
    }
  }

  static List<OutfitPreview> _filterHikeShortsWhenLongBottomsExist({
    required List<OutfitPreview> kept,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    if (kept.isEmpty) return kept;
    final longBottomExists = wardrobe.any((item) {
      if (!isBottomWardrobeItem(item)) return false;
      final family = classifyBottomFamily(item);
      return family == BottomFamily.jeans ||
          family == BottomFamily.pants ||
          family == BottomFamily.joggers;
    });
    if (!longBottomExists) return kept;
    final withoutShorts = kept
        .where(
          (preview) =>
              classifyBottomFamily(preview.bottom.item) != BottomFamily.shorts,
        )
        .toList(growable: false);
    return withoutShorts.isNotEmpty ? withoutShorts : kept;
  }

  /// Generuje intent-first kandidátov vo vlnách (M3a–M3d).
  static List<OutfitPreview> generateCandidates({
    required List<Map<String, dynamic>> wardrobe,
    required OutfitWeatherSnapshot weather,
    required OutfitIntent outfitIntent,
    required BottomFamilyGuidance bottomGuidance,
    required FootwearFamilyGuidance footwearGuidance,
    required Set<String> excludedItemIds,
    Set<String> rejectedCombinationSignatures = const {},
    Set<String> previousItemIds = const {},
    bool forceDifferentOutfit = false,
    int targetCount = 6,
    int matrixLimit = 12,
    bool preferredBottomExists = false,
    bool preferredFootwearExists = false,
    OutfitPreviewPredicate? isPreferredBottom,
    OutfitPreviewPredicate? isPreferredFootwear,
    OutfitPreviewPredicate? isDiscouragedBottom,
    OutfitPreviewPredicate? isDiscouragedFootwear,
    OutfitPreviewPredicate? passesLayerHarmony,
    OutfitPreviewBonusScorer? comfortBonusScorer,
  }) {
    final plan = planWaves(
      intent: outfitIntent,
      bottomGuidance: bottomGuidance,
      footwearGuidance: footwearGuidance,
    );
    final bottomForbidden = outfitIntent.bottomForbidden.toSet();
    final footwearForbidden = outfitIntent.footwearForbidden.toSet();
    final skipCompromise = preferredOutfitPossible(
      wardrobe: wardrobe,
      plan: plan,
      intent: outfitIntent,
      excludedItemIds: excludedItemIds,
    );

    final minRequired = minimumCandidatesForIntent(
      intent: outfitIntent,
      wardrobe: wardrobe,
    );
    final effectiveTarget = targetCount > minRequired ? targetCount : minRequired;

    final waves = <MatrixGenerationWave>[
      MatrixGenerationWave.preferred,
      MatrixGenerationWave.fallback,
      if (!skipCompromise) MatrixGenerationWave.compromise,
    ];

    final kept = <OutfitPreview>[];
    final keptCoreSigs = <String>{};
    final usedTopIds = <String>{};
    final usedBottomIds = <String>{};
    final usedFootwearIds = <String>{};

    for (final wave in waves) {
      if (kept.length >= effectiveTarget) break;
      if (wave == MatrixGenerationWave.preferred &&
          kept.length >= preferredWaveSufficientCount &&
          kept.length >= minRequired) {
        break;
      }

      final waveFamilies = wave == MatrixGenerationWave.preferred
          ? plan.familiesFor(wave)
          : plan.cumulativeFamiliesFor(wave);
      if (waveFamilies.isEmpty) {
        _logMatrixGeneration(
          wave: wave,
          plan: plan,
          generatedCandidates: 0,
          skippedCandidates: 0,
          diversityPenalty: 0,
        );
        continue;
      }

      var waveKept = 0;
      var waveSkipped = 0;
      var waveDiversityPenalty = 0.0;

      // Soft diversity: bez hard exclude top/bottom/shoe ID medzi kandidátmi.
      for (var diversityPass = 0;
          diversityPass < effectiveTarget && kept.length < effectiveTarget;
          diversityPass++) {
        final pools = _resolveWavePools(
          wave: wave,
          plan: plan,
          wardrobe: wardrobe,
          bottomForbidden: bottomForbidden,
          footwearForbidden: footwearForbidden,
          excludedItemIds: excludedItemIds,
        );

        if (pools.bottomIds.isEmpty && pools.footwearIds.isEmpty) {
          break;
        }

        final waveCandidates = OutfitGenerationService.generateCandidatePreviews(
          wardrobeItems: wardrobe,
          weather: weather,
          excludedItemIds: excludedItemIds,
          rejectedCombinationSignatures: rejectedCombinationSignatures,
          previousItemIds: previousItemIds,
          forceDifferentOutfit: forceDifferentOutfit,
          limit: matrixLimit,
          allowedBottomItemIds: pools.bottomIds,
          allowedShoeItemIds: pools.footwearIds,
          preferredBottomExists: preferredBottomExists,
          preferredFootwearExists: preferredFootwearExists,
          bottomGuidance: bottomGuidance,
          footwearGuidance: footwearGuidance,
          topPreference: outfitIntent.topPreference,
          activityType: outfitIntent.activityType,
          outfitIntent: outfitIntent,
          bottomPreferredFamilies: outfitIntent.bottomPreferred,
          bottomForbiddenFamilies: outfitIntent.bottomForbidden,
          footwearPreferredFamilies: outfitIntent.footwearPreferred,
          footwearForbiddenFamilies: outfitIntent.footwearForbidden,
          logMatrixPoolDebug: true,
          isPreferredBottom: isPreferredBottom,
          isPreferredFootwear: isPreferredFootwear,
          isDiscouragedBottom: isDiscouragedBottom,
          isDiscouragedFootwear: isDiscouragedFootwear,
          passesLayerHarmony: passesLayerHarmony,
          comfortBonusScorer: comfortBonusScorer,
        );

        if (waveCandidates.isEmpty) break;

        final ranked = waveCandidates.asMap().entries.map((entry) {
          final preview = entry.value;
          final penalty = diversityPenaltyForPreview(
            preview: preview,
            usedTopIds: usedTopIds,
            usedBottomIds: usedBottomIds,
            usedFootwearIds: usedFootwearIds,
          );
          final bonus = comfortBonusScorer?.call(preview) ?? 0.0;
          return (
            preview: preview,
            diversityPenalty: penalty,
            bonusScore: bonus,
            originalIndex: entry.key,
          );
        }).toList()
          ..sort((a, b) {
            final divCmp = a.diversityPenalty.compareTo(b.diversityPenalty);
            if (divCmp != 0) return divCmp;
            final bonusCmp = b.bonusScore.compareTo(a.bonusScore);
            if (bonusCmp != 0) return bonusCmp;
            return a.originalIndex.compareTo(b.originalIndex);
          });

        var addedThisPass = false;
        for (final entry in ranked) {
          if (kept.length >= effectiveTarget) break;
          final coreSig = OutfitGenerationService.coreCombinationSignature(
            entry.preview.top.item,
            entry.preview.bottom.item,
            entry.preview.shoes.item,
          );
          if (coreSig.isEmpty || keptCoreSigs.contains(coreSig)) {
            waveSkipped++;
            continue;
          }
          if (passesLayerHarmony != null &&
              !passesLayerHarmony(entry.preview)) {
            waveSkipped++;
            continue;
          }

          kept.add(entry.preview);
          keptCoreSigs.add(coreSig);
          waveKept++;
          waveDiversityPenalty += entry.diversityPenalty;
          addedThisPass = true;

          final topId =
              OutfitGenerationService.wardrobeItemId(entry.preview.top.item);
          final bottomId =
              OutfitGenerationService.wardrobeItemId(entry.preview.bottom.item);
          final shoeId =
              OutfitGenerationService.wardrobeItemId(entry.preview.shoes.item);
          if (topId.isNotEmpty) usedTopIds.add(topId);
          if (bottomId.isNotEmpty) usedBottomIds.add(bottomId);
          if (shoeId.isNotEmpty) usedFootwearIds.add(shoeId);
        }

        if (!addedThisPass) break;
      }

      _logMatrixGeneration(
        wave: wave,
        plan: plan,
        generatedCandidates: waveKept,
        skippedCandidates: waveSkipped,
        diversityPenalty: waveDiversityPenalty,
      );

      if (wave == MatrixGenerationWave.preferred &&
          kept.length >= preferredWaveSufficientCount &&
          kept.length >= minRequired) {
        break;
      }
    }

    return OutfitGenerationService.dedupePreviewsByCore(
      _filterHikeShortsWhenLongBottomsExist(
        kept: kept,
        wardrobe: wardrobe,
      ),
    );
  }
}
