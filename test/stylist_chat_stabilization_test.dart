import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/Services/outfit_generation_service.dart';
import 'package:outfitofTheDay/data/outfit_intent.dart';
import 'package:outfitofTheDay/utils/bottom_family_guidance.dart';
import 'package:outfitofTheDay/utils/dress_code_resolver.dart';
import 'package:outfitofTheDay/utils/footwear_family_guidance.dart';
import 'package:outfitofTheDay/utils/layer_harmony_guard.dart';
import 'package:outfitofTheDay/utils/outfit_intent_builder.dart';
import 'package:outfitofTheDay/utils/stylist_chat_candidate_pipeline.dart';
import 'package:outfitofTheDay/utils/stylist_intent_matrix_generator.dart';
import 'package:outfitofTheDay/utils/activity_outfit_identity.dart';
import 'package:outfitofTheDay/utils/comfort_target.dart';
import 'package:outfitofTheDay/utils/outfit_intent_scorer.dart';
import 'package:outfitofTheDay/utils/stylist_intent_resolver.dart';
import 'package:outfitofTheDay/utils/stylist_occasion_guidance.dart';
import 'package:outfitofTheDay/utils/stylist_outfit_explain_builder.dart';
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

class _ScenarioResult {
  const _ScenarioResult({
    required this.prompt,
    required this.outfitLabels,
    required this.reply,
    required this.usedCompromise,
  });

  final String prompt;
  final String outfitLabels;
  final String reply;
  final bool usedCompromise;
}

_ScenarioResult _runScenario({
  required String prompt,
  required List<Map<String, dynamic>> wardrobe,
  required OutfitWeatherSnapshot weather,
  bool wetGroundMuddy = false,
}) {
  final stylistIntent = StylistIntentResolver.resolve(
    conversationText: prompt,
    tempC: weather.tempC,
  );
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
    stylistIntent: stylistIntent,
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
  ActivityOutfitIdentity.log(
    activityType: outfitIntent.activityType,
    preview: preview,
    result: ActivityOutfitIdentity.evaluate(
      preview: preview,
      intent: outfitIntent,
      wetGroundMuddy: wetGroundMuddy,
    ),
  );
  final analysis = WardrobeGapAnalysis.analyze(
    wardrobe: wardrobe,
    intent: outfitIntent,
    preview: preview,
    weather: weather,
    wetGroundMuddy: wetGroundMuddy,
  );
  final suggestedItems = [
    preview.top.item,
    preview.bottom.item,
    preview.shoes.item,
  ];
      final reply = StylistOutfitExplainBuilder.buildLocalExplainSk(
        suggestedItems: suggestedItems,
        profile: profile,
        wardrobeAnalysis: analysis,
        activityType: StylistIntentResolver.resolve(
          conversationText: prompt,
          tempC: weather.tempC,
        ).activityType,
      );

  return _ScenarioResult(
    prompt: prompt,
    outfitLabels: '${preview.top.label} + ${preview.bottom.label} + ${preview.shoes.label}',
    reply: reply,
    usedCompromise: analysis.usedCompromise,
  );
}

void main() {
  group('Stylist Chat stabilization — 6 scenárov', () {
    late List<Map<String, dynamic>> wardrobe;

    setUp(() {
      wardrobe = _stabilizationWardrobe();
    });

    test('všetkých 6 scenárov: outfit + ľudská odpoveď', () {
      final scenarios = <_ScenarioResult>[
        _runScenario(
          prompt: 'Večer idem na svadbu.',
          wardrobe: wardrobe,
          weather: _weather(tempC: 22, season: 'let'),
        ),
        _runScenario(
          prompt: 'Zajtra idem na pohovor.',
          wardrobe: wardrobe,
          weather: _weather(tempC: 18, season: 'jar'),
        ),
        _runScenario(
          prompt: 'Čo si mám obliecť dnes do práce?',
          wardrobe: wardrobe,
          weather: _weather(tempC: 22, season: 'let'),
        ),
        _runScenario(
          prompt: 'Zajtra idem do hory.',
          wardrobe: wardrobe,
          weather: _weather(tempC: 16, season: 'jese', rain: true),
        ),
        _runScenario(
          prompt: 'Ráno idem na huby.',
          wardrobe: wardrobe,
          weather: _weather(tempC: 14, season: 'jese', rain: true),
          wetGroundMuddy: true,
        ),
        _runScenario(
          prompt: 'Idem na grilovačku.',
          wardrobe: wardrobe,
          weather: _weather(tempC: 26, season: 'let'),
        ),
      ];

      for (final result in scenarios) {
        expect(result.outfitLabels, isNotEmpty);
        expect(result.reply, isNotEmpty);
        expect(
          StylistOutfitExplainBuilder.containsTechnicalJargon(result.reply),
          isFalse,
          reason: 'Technický žargón v: ${result.prompt}',
        );
        expect(
          result.reply.toLowerCase(),
          isNot(contains('formalitytarget')),
        );
        expect(
          result.reply.toLowerCase(),
          isNot(contains('fallback')),
        );

        // ignore: avoid_print
        print('\n--- ${result.prompt} ---');
        // ignore: avoid_print
        print('Outfit: ${result.outfitLabels}');
        // ignore: avoid_print
        print('Compromise: ${result.usedCompromise}');
        // ignore: avoid_print
        print('Odpoveď: ${result.reply}');
      }

      final wedding = scenarios[0];
      final interview = scenarios[1];
      final work = scenarios[2];
      final hike = scenarios[3];
      final mushroom = scenarios[4];
      final bbq = scenarios[5];

      expect(wedding.usedCompromise, isTrue);
      final weddingLower = wedding.reply.toLowerCase();
      expect(
        weddingLower.contains('kompromis') ||
            weddingLower.contains('vhodnejší') ||
            weddingLower.contains('z dostupných') ||
            weddingLower.contains('rozumné riešenie') ||
            weddingLower.contains('najlepšie'),
        isTrue,
        reason: 'Wedding explain má úprimne komunikovať kompromis: '
            '${wedding.reply}',
      );
      expect(wedding.reply.toLowerCase(), contains('košeľ'));
      expect(wedding.reply.toLowerCase(), isNot(contains('ideálny outfit')));

      expect(bbq.reply.toLowerCase(), isNot(contains('formality')));

      // Activity identity — outfity sa musia líšiť podľa aktivity.
      expect(work.outfitLabels, contains('rifle'));
      expect(work.outfitLabels, isNot(equals(wedding.outfitLabels)));

      expect(hike.outfitLabels.toLowerCase(), contains('turist'));
      expect(hike.outfitLabels, isNot(equals(wedding.outfitLabels)));

      expect(mushroom.outfitLabels.toLowerCase(), contains('turist'));
      expect(mushroom.outfitLabels.toLowerCase(), contains('čiern'));

      expect(bbq.outfitLabels.toLowerCase(), contains('šortk'));

      final formalOutfits = {wedding.outfitLabels, interview.outfitLabels};
      final outdoorOutfits = {hike.outfitLabels, mushroom.outfitLabels};
      expect(formalOutfits.intersection(outdoorOutfits), isEmpty);
    });
  });
}
