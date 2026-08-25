import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/Services/outfit_generation_service.dart';
import 'package:outfitofTheDay/data/outfit_intent.dart';
import 'package:outfitofTheDay/data/stylist_opinion.dart';
import 'package:outfitofTheDay/data/wardrobe_analysis.dart';
import 'package:outfitofTheDay/utils/activity_outfit_identity.dart';
import 'package:outfitofTheDay/utils/bottom_family_guidance.dart';
import 'package:outfitofTheDay/utils/comfort_target.dart';
import 'package:outfitofTheDay/utils/dress_code_resolver.dart';
import 'package:outfitofTheDay/utils/footwear_family_guidance.dart';
import 'package:outfitofTheDay/utils/layer_harmony_guard.dart';
import 'package:outfitofTheDay/utils/outfit_intent_builder.dart';
import 'package:outfitofTheDay/utils/outfit_intent_scorer.dart';
import 'package:outfitofTheDay/utils/stylist_chat_candidate_pipeline.dart';
import 'package:outfitofTheDay/utils/stylist_intent_matrix_generator.dart';
import 'package:outfitofTheDay/utils/stylist_intent_resolver.dart';
import 'package:outfitofTheDay/utils/stylist_occasion_guidance.dart';
import 'package:outfitofTheDay/utils/stylist_opinion_engine.dart';
import 'package:outfitofTheDay/utils/wardrobe_gap_analysis.dart';

OutfitWeatherSnapshot _weather({
  int tempC = 20,
  String season = 'let',
  bool rain = false,
}) {
  return OutfitWeatherSnapshot(
    tempC: tempC,
    isRainy: rain,
    isWindy: false,
    seasonKey: season,
  );
}

List<Map<String, dynamic>> _stabilizationWardrobe() => [
      {
        'id': 't1',
        'name': 'Čisté biele tričko',
        'canonical_type': 't_shirt',
        'layer_role': 'main_top',
      },
      {
        'id': 't2',
        'name': 'Čierne tričko',
        'canonical_type': 't_shirt',
        'layer_role': 'main_top',
      },
      {
        'id': 'p1',
        'name': 'Sivé nohavice',
        'canonical_type': 'pants',
        'layer_role': 'bottom',
      },
      {
        'id': 'j1',
        'name': 'Modré rifle',
        'canonical_type': 'jeans',
        'layer_role': 'bottom',
      },
      {
        'id': 'sh1',
        'name': 'Tmavé šortky',
        'canonical_type': 'shorts',
        'layer_role': 'bottom',
      },
      {
        'id': 'sn1',
        'name': 'Biele tenisky',
        'canonical_type': 'sneakers',
        'layer_role': 'footwear',
      },
      {
        'id': 'boot1',
        'name': 'Turistické topánky',
        'canonical_type': 'hiking_shoes',
        'layer_role': 'footwear',
      },
    ];

class _ScenarioOpinion {
  const _ScenarioOpinion({
    required this.label,
    required this.prompt,
    required this.preview,
    required this.intent,
    required this.profile,
    required this.weather,
    required this.analysis,
    required this.opinion,
    required this.wetGroundMuddy,
  });

  final String label;
  final String prompt;
  final OutfitPreview preview;
  final OutfitIntent intent;
  final StylistOccasionProfile profile;
  final OutfitWeatherSnapshot weather;
  final WardrobeAnalysis analysis;
  final StylistOpinion opinion;
  final bool wetGroundMuddy;
}

_ScenarioOpinion _evaluateScenario({
  required String label,
  required String prompt,
  required List<Map<String, dynamic>> wardrobe,
  required OutfitWeatherSnapshot weather,
  bool wetGroundMuddy = false,
}) {
  final spec = DressCodeResolver.resolve(
    conversationText: prompt,
    tempC: weather.tempC,
  );
  final profile = StylistOccasionProfile(dressCode: spec, tempC: weather.tempC);
  final bottomGuidance = StylistOccasionGuidance.bottomGuidanceFor(
    weather: weather,
    profile: profile,
  );
  final footwearGuidance = StylistOccasionGuidance.footwearGuidanceFor(
    weather: weather,
    profile: profile,
    wetGroundMuddy: wetGroundMuddy,
  );
  final outfitIntent = OutfitIntentBuilder.build(
    stylistIntent: StylistIntentResolver.resolve(
      conversationText: prompt,
      tempC: weather.tempC,
    ),
    dressCode: spec,
    bottomGuidance: bottomGuidance,
    footwearGuidance: footwearGuidance,
    wetGroundMuddy: wetGroundMuddy,
  );
  final bottomInventory = bottomFamilyInventoryFromWardrobe(wardrobe);
  final footwearInventory = footwearFamilyInventoryFromWardrobe(wardrobe);
  final preferredBottomExists = bottomInventory.hasPreferred(bottomGuidance);
  final preferredFootwearExists = footwearInventory.hasPreferred(footwearGuidance);
  final comfortTarget = ComfortTarget.fromWeather(
    ComfortWeatherInput.fromOutfitWeatherSnapshot(weather),
  );

  double combinedBonus(OutfitPreview preview) {
    final intentBonus = OutfitIntentScorer.combinationBonus(
      preview: preview,
      intent: outfitIntent,
    );
    final identity = ActivityOutfitIdentity.evaluate(
      preview: preview,
      intent: outfitIntent,
      wetGroundMuddy: wetGroundMuddy,
    );
    return intentBonus + identity.score;
  }

  final candidates = StylistIntentMatrixGenerator.generateCandidates(
    wardrobe: wardrobe,
    weather: weather,
    outfitIntent: outfitIntent,
    bottomGuidance: bottomGuidance,
    footwearGuidance: footwearGuidance,
    excludedItemIds: const {},
    preferredBottomExists: preferredBottomExists,
    preferredFootwearExists: preferredFootwearExists,
    isPreferredBottom: preferredBottomExists
        ? (p) => !previewHasDiscouragedBottom(
              preview: p,
              guidance: bottomGuidance,
            )
        : null,
    isPreferredFootwear: preferredFootwearExists
        ? (p) => !previewHasDiscouragedFootwear(
              preview: p,
              guidance: footwearGuidance,
            )
        : null,
    isDiscouragedBottom: (p) => previewHasDiscouragedBottom(
      preview: p,
      guidance: bottomGuidance,
    ),
    isDiscouragedFootwear: (p) => previewHasDiscouragedFootwear(
      preview: p,
      guidance: footwearGuidance,
    ),
    passesLayerHarmony: (p) => previewPassesLayerHarmonyGuard(
      preview: p,
      tempC: weather.tempC,
      log: false,
    ),
    comfortBonusScorer: combinedBonus,
    targetCount: 6,
    matrixLimit: 12,
  );
  expect(candidates, isNotEmpty, reason: 'Outfit sa musí vygenerovať: $prompt');

  final scored = <ScoredOutfitCandidate>[];
  for (var i = 0; i < candidates.length; i++) {
    final candidate = StylistChatCandidatePipeline.scoreCandidate(
      preview: candidates[i],
      outfitIntent: outfitIntent,
      comfortTarget: comfortTarget,
      matrixIndex: i,
      wetGroundMuddy: wetGroundMuddy,
      logIntentCandidate: ({required preview, required breakdown}) {},
    );
    if (candidate != null) scored.add(candidate);
  }
  scored.sort((a, b) => b.finalScore.compareTo(a.finalScore));
  expect(scored, isNotEmpty);

  final preview = scored.first.preview;
  final analysis = WardrobeGapAnalysis.analyze(
    wardrobe: wardrobe,
    intent: outfitIntent,
    preview: preview,
    weather: weather,
    wetGroundMuddy: wetGroundMuddy,
  );
  final identity = ActivityOutfitIdentity.evaluate(
    preview: preview,
    intent: outfitIntent,
    wetGroundMuddy: wetGroundMuddy,
  );
  final opinion = StylistOpinionEngine.evaluate(
    preview: preview,
    intent: outfitIntent,
    weather: weather,
    wardrobeAnalysis: analysis,
    occasionProfile: profile,
    activityIdentity: identity,
    wetGroundMuddy: wetGroundMuddy,
  );

  return _ScenarioOpinion(
    label: label,
    prompt: prompt,
    preview: preview,
    intent: outfitIntent,
    profile: profile,
    weather: weather,
    analysis: analysis,
    opinion: opinion,
    wetGroundMuddy: wetGroundMuddy,
  );
}

void main() {
  group('StylistOpinionEngine — deterministika', () {
    test('confidence vychádza zo súčtu vážených faktorov', () {
      final wardrobe = _stabilizationWardrobe();
      final result = _evaluateScenario(
        label: 'práca',
        prompt: 'Čo si mám obliecť dnes do práce?',
        wardrobe: wardrobe,
        weather: _weather(tempC: 22, season: 'let'),
      );

      final expected = result.opinion.factors
          .map((f) => f.weightedPoints)
          .fold<double>(0, (sum, v) => sum + v)
          .round();

      var capped = expected.clamp(0, 100);
      if (result.analysis.usedCompromise) capped = capped.clamp(0, 70);
      if (result.analysis.missingItems.any((g) => g.blocksIdealOutfit)) {
        capped = capped.clamp(0, 65);
      }
      if (result.analysis.usedCompromise && result.profile.dressCode.formalityTarget >= 7) {
        capped = capped.clamp(0, 60);
      }

      expect(result.opinion.overallConfidence, capped);
      expect(result.opinion.factors.length, 5);
    });
  });

  group('StylistOpinionEngine — úprimnosť', () {
    test('kompromis na formálnej udalosti nie je excellent', () {
      final wardrobe = _stabilizationWardrobe();
      final wedding = _evaluateScenario(
        label: 'svadba',
        prompt: 'Večer idem na svadbu.',
        wardrobe: wardrobe,
        weather: _weather(tempC: 22, season: 'let'),
      );

      expect(wedding.analysis.usedCompromise, isTrue);
      expect(wedding.opinion.overallConfidence, lessThanOrEqualTo(60));
      expect(wedding.opinion.opinionLevel, isNot(StylistOpinionLevel.excellent));
      expect(
        wedding.opinion.shortOpinionSk.toLowerCase(),
        isNot(contains('pokojne odporučil')),
      );
      expect(
        wedding.opinion.shortOpinionSk.toLowerCase(),
        anyOf(contains('kompromis'), contains('nie je to ideál'), contains('úprimne')),
      );
    });

    test('weak pri forbidden top', () {
      final preview = OutfitPreview(
        top: OutfitPreviewItem(
          type: OutfitWearType.top,
          item: const {
            'id': 'tank',
            'name': 'Tielko',
            'canonical_type': 'tank_top',
            'layer_role': 'main_top',
          },
          label: 'Tielko',
          imageUrl: null,
        ),
        bottom: OutfitPreviewItem(
          type: OutfitWearType.bottom,
          item: const {
            'id': 'p1',
            'name': 'Sivé nohavice',
            'canonical_type': 'pants',
            'layer_role': 'bottom',
          },
          label: 'Sivé nohavice',
          imageUrl: null,
        ),
        shoes: OutfitPreviewItem(
          type: OutfitWearType.shoes,
          item: const {
            'id': 'sn1',
            'name': 'Biele tenisky',
            'canonical_type': 'sneakers',
            'layer_role': 'footwear',
          },
          label: 'Biele tenisky',
          imageUrl: null,
        ),
        outerwear: null,
      );
      final weather = _weather(tempC: 22);
      final spec = DressCodeResolver.resolve(
        conversationText: 'Zajtra idem na pohovor.',
        tempC: weather.tempC,
      );
      final profile = StylistOccasionProfile(dressCode: spec, tempC: weather.tempC);
      final bottomGuidance = StylistOccasionGuidance.bottomGuidanceFor(
        weather: weather,
        profile: profile,
      );
      final footwearGuidance = StylistOccasionGuidance.footwearGuidanceFor(
        weather: weather,
        profile: profile,
      );
      final intent = OutfitIntentBuilder.build(
        stylistIntent: StylistIntentResolver.resolve(
          conversationText: 'Zajtra idem na pohovor.',
          tempC: weather.tempC,
        ),
        dressCode: spec,
        bottomGuidance: bottomGuidance,
        footwearGuidance: footwearGuidance,
      );
      final analysis = WardrobeGapAnalysis.analyze(
        wardrobe: _stabilizationWardrobe(),
        intent: intent,
        preview: preview,
        weather: weather,
      );

      final opinion = StylistOpinionEngine.evaluate(
        preview: preview,
        intent: intent,
        weather: weather,
        wardrobeAnalysis: analysis,
        occasionProfile: profile,
      );

      expect(opinion.opinionLevel, StylistOpinionLevel.weak);
      expect(opinion.overallConfidence, lessThanOrEqualTo(40));
      expect(opinion.shortOpinionSk.toLowerCase(), contains('úprimne'));
    });
  });

  group('StylistOpinionEngine — 6 scenárov', () {
    late List<Map<String, dynamic>> wardrobe;
    late List<_ScenarioOpinion> scenarios;

    setUpAll(() {
      wardrobe = _stabilizationWardrobe();
      scenarios = [
        _evaluateScenario(
          label: 'svadba',
          prompt: 'Večer idem na svadbu.',
          wardrobe: wardrobe,
          weather: _weather(tempC: 22, season: 'let'),
        ),
        _evaluateScenario(
          label: 'pohovor',
          prompt: 'Zajtra idem na pohovor.',
          wardrobe: wardrobe,
          weather: _weather(tempC: 18, season: 'jar'),
        ),
        _evaluateScenario(
          label: 'práca',
          prompt: 'Čo si mám obliecť dnes do práce?',
          wardrobe: wardrobe,
          weather: _weather(tempC: 22, season: 'let'),
        ),
        _evaluateScenario(
          label: 'hory',
          prompt: 'Zajtra idem do hory.',
          wardrobe: wardrobe,
          weather: _weather(tempC: 16, season: 'jese', rain: true),
        ),
        _evaluateScenario(
          label: 'huby',
          prompt: 'Ráno idem na huby.',
          wardrobe: wardrobe,
          weather: _weather(tempC: 14, season: 'jese', rain: true),
          wetGroundMuddy: true,
        ),
        _evaluateScenario(
          label: 'grilovačka',
          prompt: 'Idem na grilovačku.',
          wardrobe: wardrobe,
          weather: _weather(tempC: 26, season: 'let'),
        ),
      ];

      for (final s in scenarios) {
        // ignore: avoid_print
        print(
          '\n[${s.label}] confidence=${s.opinion.overallConfidence} '
          'level=${s.opinion.opinionLevel.wireName} '
          'outfit=${s.preview.top.label} + ${s.preview.bottom.label} + ${s.preview.shoes.label}\n'
          'opinion: ${s.opinion.shortOpinionSk}',
        );
      }
    });

    test('svadba — kompromis, nie excellent', () {
      final s = scenarios[0];
      expect(s.analysis.usedCompromise, isTrue);
      expect(s.opinion.opinionLevel, isNot(StylistOpinionLevel.excellent));
      expect(s.opinion.biggestMissingPiece, isNotNull);
    });

    test('pohovor — kompromis, nie excellent', () {
      final s = scenarios[1];
      expect(s.analysis.usedCompromise, isTrue);
      expect(s.opinion.opinionLevel, isNot(StylistOpinionLevel.excellent));
    });

    test('práca — rozumný názor, nie vychvaľovanie', () {
      final s = scenarios[2];
      expect(s.preview.bottom.label, contains('rifle'));
      expect(s.opinion.opinionLevel, isNot(StylistOpinionLevel.excellent));
    });

    test('hory — vyšší confidence než svadba', () {
      final wedding = scenarios[0];
      final hike = scenarios[3];
      expect(hike.opinion.overallConfidence, greaterThan(wedding.opinion.overallConfidence));
      expect(hike.preview.shoes.label.toLowerCase(), contains('turist'));
    });

    test('huby — outdoor obuv, nie najslabší level', () {
      final s = scenarios[4];
      expect(s.preview.shoes.label.toLowerCase(), contains('turist'));
      expect(s.opinion.opinionLevel, isNot(StylistOpinionLevel.weak));
    });

    test('grilovačka — casual, nie formálny kompromis', () {
      final s = scenarios[5];
      expect(s.preview.bottom.label.toLowerCase(), contains('šortk'));
      expect(s.analysis.usedCompromise, isFalse);
      expect(s.opinion.overallConfidence, greaterThan(50));
    });

    test('outfity sa líšia medzi aktivitami', () {
      final outfits = scenarios
          .map((s) => '${s.preview.top.label}|${s.preview.bottom.label}|${s.preview.shoes.label}')
          .toSet();
      expect(outfits.length, greaterThan(3));
    });
  });

  group('StylistOpinionEngine — social smart casual (date/cinema/dinner)', () {
    late List<Map<String, dynamic>> wardrobe;

    setUp(() {
      wardrobe = _stabilizationWardrobe();
    });

    test('rande s turistickými + šortkami nie je excellent (max acceptable/65)',
        () {
      final s = _evaluateScenario(
        label: 'rande',
        prompt: 'Večer idem na rande.',
        wardrobe: wardrobe,
        weather: _weather(tempC: 20, season: 'let'),
      );
      expect(s.intent.activityType, 'date');
      expect(s.preview.shoes.label.toLowerCase(), contains('turist'));
      expect(s.preview.bottom.label.toLowerCase(), contains('šortk'));
      expect(s.opinion.opinionLevel, isNot(StylistOpinionLevel.excellent));
      expect(s.opinion.opinionLevel, isNot(StylistOpinionLevel.good));
      expect(s.opinion.overallConfidence, lessThanOrEqualTo(65));
      expect(
        s.opinion.shortOpinionSk.toLowerCase(),
        isNot(contains('pokojne odporučil')),
      );
    });

    test('kino s turistickými topánkami nie je excellent (max good/70)', () {
      final s = _evaluateScenario(
        label: 'kino',
        prompt: 'Dnes večer idem do kina.',
        wardrobe: wardrobe,
        weather: _weather(tempC: 19, season: 'jese'),
      );
      expect(s.intent.activityType, 'cinema');
      expect(s.preview.shoes.label.toLowerCase(), contains('turist'));
      expect(s.opinion.opinionLevel, isNot(StylistOpinionLevel.excellent));
      expect(s.opinion.overallConfidence, lessThanOrEqualTo(70));
    });

    test('večera s turistickými topánkami nie je excellent (max good/70)', () {
      final s = _evaluateScenario(
        label: 'večera',
        prompt: 'Idem na večeru v reštaurácii.',
        wardrobe: wardrobe,
        weather: _weather(tempC: 21, season: 'let'),
      );
      expect(s.intent.activityType, 'dinner');
      expect(s.opinion.opinionLevel, isNot(StylistOpinionLevel.excellent));
      expect(s.opinion.overallConfidence, lessThanOrEqualTo(70));
    });

    test('výber outfitu sa nezmenil — social identity je opinion-only', () {
      // Selection identity (bez forOpinion) nesmie penalizovať outdoor obuv,
      // inak by sa zmenil výber. Overíme, že rande stále vyberie turistické.
      final selectionIdentity = ActivityOutfitIdentity.evaluate(
        preview: _evaluateScenario(
          label: 'rande',
          prompt: 'Večer idem na rande.',
          wardrobe: wardrobe,
          weather: _weather(tempC: 20, season: 'let'),
        ).preview,
        intent: OutfitIntentBuilder.build(
          stylistIntent: StylistIntentResolver.resolve(
            conversationText: 'Večer idem na rande.',
            tempC: 20,
          ),
          dressCode: DressCodeResolver.resolve(
            conversationText: 'Večer idem na rande.',
            tempC: 20,
          ),
          bottomGuidance: StylistOccasionGuidance.bottomGuidanceFor(
            weather: _weather(tempC: 20, season: 'let'),
            profile: StylistOccasionProfile(
              dressCode: DressCodeResolver.resolve(
                conversationText: 'Večer idem na rande.',
                tempC: 20,
              ),
              tempC: 20,
            ),
          ),
          footwearGuidance: StylistOccasionGuidance.footwearGuidanceFor(
            weather: _weather(tempC: 20, season: 'let'),
            profile: StylistOccasionProfile(
              dressCode: DressCodeResolver.resolve(
                conversationText: 'Večer idem na rande.',
                tempC: 20,
              ),
              tempC: 20,
            ),
          ),
        ),
      );
      // Selection identity nesmie obsahovať opinion-only outdoor penalty.
      expect(
        selectionIdentity.reasons,
        isNot(contains('social_outdoor_footwear_not_ideal')),
      );
    });
  });
}
