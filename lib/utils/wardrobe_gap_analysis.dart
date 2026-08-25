import 'package:flutter/foundation.dart';

import '../Services/outfit_generation_service.dart';
import '../data/outfit_intent.dart';
import '../data/wardrobe_analysis.dart';
import 'bottom_family_guidance.dart';
import 'footwear_family_guidance.dart';
import 'outfit_intent_scorer.dart';
import 'stylist_layer_filter.dart';

/// Analýza medzier v šatníku oproti [OutfitIntent] — po matrix výbere.
class WardrobeGapAnalysis {
  const WardrobeGapAnalysis._();

  static WardrobeAnalysis analyze({
    required List<Map<String, dynamic>> wardrobe,
    required OutfitIntent intent,
    required OutfitPreview? preview,
    required OutfitWeatherSnapshot weather,
    bool wetGroundMuddy = false,
  }) {
    final missingItems = <WardrobeGap>[
      ..._detectTopGaps(wardrobe: wardrobe, intent: intent),
      ..._detectFootwearGaps(wardrobe: wardrobe, intent: intent),
      ..._detectBottomGaps(wardrobe: wardrobe, intent: intent),
      ..._detectOuterGaps(
        wardrobe: wardrobe,
        weather: weather,
        wetGroundMuddy: wetGroundMuddy,
      ),
    ];

    final compromiseItems = <String>[];
    var usedCompromise = false;

    if (preview != null) {
      final topResult = OutfitIntentScorer.classifyTopEligibility(
        item: preview.top.item,
        intent: intent,
      );
      if (topResult.eligibility == ItemEligibility.compromise ||
          topResult.eligibility == ItemEligibility.forbidden) {
        usedCompromise = true;
        compromiseItems.add(preview.top.label);
      }

      final bottomFamily =
          classifyBottomFamily(preview.bottom.item).wireName;
      if (intent.bottomPreferred.isNotEmpty &&
          !intent.bottomPreferred.contains(bottomFamily) &&
          !intent.bottomForbidden.contains(bottomFamily)) {
        usedCompromise = true;
        compromiseItems.add(preview.bottom.label);
      }

      final footwearFamily =
          classifyFootwearFamily(preview.shoes.item).wireName;
      if (intent.footwearPreferred.isNotEmpty &&
          !intent.footwearPreferred.contains(footwearFamily) &&
          !intent.footwearForbidden.contains(footwearFamily)) {
        usedCompromise = true;
        compromiseItems.add(preview.shoes.label);
      }
    }

    if (usedCompromise && missingItems.isEmpty) {
      missingItems.addAll(_inferGapsFromCompromise(intent: intent));
    }

    final analysis = WardrobeAnalysis(
      usedCompromise: usedCompromise,
      missingItems: missingItems,
      compromiseItems: compromiseItems.toSet().toList(growable: false),
    );
    log(analysis);
    return analysis;
  }

  static void log(WardrobeAnalysis analysis) {
    final missing = analysis.missingItems
        .map((g) => g.wireKey)
        .join('|');
    final compromise = analysis.compromiseItems.join('|');
    debugPrint(
      'STYLIST CHAT wardrobe_analysis { '
      'usedCompromise=${analysis.usedCompromise}, '
      'missingItems=$missing, '
      'compromiseItems=$compromise '
      '}',
    );
  }

  static List<WardrobeGap> _detectTopGaps({
    required List<Map<String, dynamic>> wardrobe,
    required OutfitIntent intent,
  }) {
    final gaps = <WardrobeGap>[];
    final tops = wardrobe.where(_isTop).toList(growable: false);
    if (tops.isEmpty) return gaps;

    bool hasEligibility(ItemEligibility tier) {
      return tops.any(
        (item) =>
            OutfitIntentScorer.classifyTopEligibility(
              item: item,
              intent: intent,
            ).eligibility ==
            tier,
      );
    }

    switch (intent.topPreference) {
      case 'shirt_or_blouse':
        if (!hasEligibility(ItemEligibility.preferred)) {
          gaps.add(
            WardrobeGap(
              category: 'shirt',
              reason: intent.activityType,
              blocksIdealOutfit: true,
              explanationSk: _shirtExplanation(intent.activityType),
            ),
          );
        }
      case 'polo_or_shirt':
        if (!hasEligibility(ItemEligibility.preferred) &&
            intent.activityType == 'work') {
          gaps.add(
            const WardrobeGap(
              category: 'polo',
              reason: 'work',
              blocksIdealOutfit: true,
              explanationSk:
                  'Na prácu by sa hodilo polo alebo košeľa s lepším vzhľadom.',
            ),
          );
        }
    }
    return gaps;
  }

  static List<WardrobeGap> _detectFootwearGaps({
    required List<Map<String, dynamic>> wardrobe,
    required OutfitIntent intent,
  }) {
    final gaps = <WardrobeGap>[];
    if (!intent.footwearPreferred.contains('formal_shoes')) return gaps;

    final hasFormal = wardrobe.any((item) {
      if (!isFootwearWardrobeItem(item)) return false;
      return classifyFootwearFamily(item) == FootwearFamily.formalShoes;
    });
    if (!hasFormal) {
      gaps.add(
        WardrobeGap(
          category: 'formal_shoes',
          reason: intent.activityType,
          blocksIdealOutfit: true,
          explanationSk: _formalShoesExplanation(intent.activityType),
        ),
      );
    }
    return gaps;
  }

  static List<WardrobeGap> _detectBottomGaps({
    required List<Map<String, dynamic>> wardrobe,
    required OutfitIntent intent,
  }) {
    if (intent.activityType != 'hike') return const [];
    final hasHikingBottom = wardrobe.any((item) {
      if (!isBottomWardrobeItem(item)) return false;
      final family = classifyBottomFamily(item);
      return family == BottomFamily.pants ||
          family == BottomFamily.joggers ||
          family == BottomFamily.jeans;
    });
    if (hasHikingBottom) return const [];
    return const [
      WardrobeGap(
        category: 'hiking_pants',
        reason: 'hike',
        blocksIdealOutfit: true,
        explanationSk:
            'Na túru by boli vhodnejšie nohavice alebo tepláky odolné voči terénu.',
      ),
    ];
  }

  static List<WardrobeGap> _detectOuterGaps({
    required List<Map<String, dynamic>> wardrobe,
    required OutfitWeatherSnapshot weather,
    bool wetGroundMuddy = false,
  }) {
    if (!weather.isRainy && !wetGroundMuddy) return const [];

    final hasRainShell = wardrobe.any((item) {
      final role =
          (item['layer_role'] ?? item['layerRole'] ?? '').toString();
      if (role != 'outer_layer') return false;
      final name = (item['name'] ?? '').toString().toLowerCase();
      return name.contains('bunda') ||
          name.contains('kabát') ||
          name.contains('kabat') ||
          name.contains('plášť') ||
          name.contains('plast') ||
          name.contains('rain') ||
          name.contains('shell');
    });
    if (hasRainShell) return const [];
    return const [
      WardrobeGap(
        category: 'rain_jacket',
        reason: 'rain',
        blocksIdealOutfit: false,
        explanationSk:
            'Pri daždi by sa hodila nepremokavá bunda alebo plášť.',
      ),
    ];
  }

  static List<WardrobeGap> _inferGapsFromCompromise({
    required OutfitIntent intent,
  }) {
    switch (intent.topPreference) {
      case 'shirt_or_blouse':
        return [
          WardrobeGap(
            category: 'shirt',
            reason: intent.activityType,
            blocksIdealOutfit: true,
            explanationSk: _shirtExplanation(intent.activityType),
          ),
        ];
      case 'polo_or_shirt':
        return [
          const WardrobeGap(
            category: 'polo',
            reason: 'work',
            blocksIdealOutfit: true,
            explanationSk:
                'Na prácu by sa hodilo polo alebo košeľa s lepším vzhľadom.',
          ),
        ];
      default:
        return const [];
    }
  }

  static String _shirtExplanation(String activity) {
    switch (activity) {
      case 'wedding':
        return 'Na svadbu by bola vhodnejšia biela alebo svetlomodrá košeľa.';
      case 'interview':
        return 'Na pohovor by bola vhodnejšia jednoduchá košeľa.';
      case 'funeral':
        return 'Na pohreb by bola vhodnejšia tmavá košeľa.';
      case 'work':
        return 'Do práce by bola vhodnejšia košeľa alebo polo.';
      default:
        return 'Na túto príležitosť by bol vhodnejší košeľový vrch.';
    }
  }

  static String _formalShoesExplanation(String activity) {
    switch (activity) {
      case 'wedding':
        return 'Na svadbu by sa hodila elegantná uzavretá obuv.';
      case 'interview':
        return 'Na pohovor by sa hodila čistá formálna obuv.';
      default:
        return 'Na túto príležitosť by sa hodila elegantnejšia obuv.';
    }
  }

  static bool _isTop(Map<String, dynamic> item) {
    if (StylistLayerFilter.isTankTopItem(item)) return true;
    final blob = [
      item['name'],
      item['category'],
      item['subCategory'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
    return blob.contains('trič') ||
        blob.contains('trick') ||
        blob.contains('koše') ||
        blob.contains('kosel') ||
        blob.contains('shirt') ||
        blob.contains('polo') ||
        blob.contains('tielko') ||
        blob.contains('blúz') ||
        blob.contains('bluz');
  }
}
