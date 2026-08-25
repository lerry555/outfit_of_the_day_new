import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/Services/outfit_generation_service.dart';
import 'package:outfitofTheDay/data/outfit_intent.dart';
import 'package:outfitofTheDay/debug/stylist_chat_pipeline_debug_runner.dart';
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

OutfitWeatherSnapshot _weatherForScenario(String label) {
  return switch (label) {
    'svadba' => _weather(tempC: 22, season: 'let'),
    'pohovor' => _weather(tempC: 18, season: 'jar'),
    'práca' => _weather(tempC: 22, season: 'let'),
    'hory' => _weather(tempC: 16, season: 'jese', rain: true),
    'huby' => _weather(tempC: 14, season: 'jese', rain: true),
    'grilovačka' => _weather(tempC: 26, season: 'let'),
    'rande' => _weather(tempC: 20, season: 'let'),
    'kino' => _weather(tempC: 19, season: 'jese'),
    'večera' => _weather(tempC: 21, season: 'let'),
    'meeting' => _weather(tempC: 22, season: 'let'),
    _ => _weather(),
  };
}

bool _wetGroundForScenario(String label) => label == 'huby';

StylistChatScenarioReport _buildScenarioReport({
  required StylistChatDebugScenario scenario,
  required List<Map<String, dynamic>> wardrobe,
}) {
  final prompt = scenario.prompt;
  final weather = _weatherForScenario(scenario.label);
  final wetGroundMuddy = _wetGroundForScenario(scenario.label);

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
  final preferredFootwearExists =
      footwearInventory.hasPreferred(footwearGuidance);
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

  final outfitItems = [
    preview.top.label,
    preview.bottom.label,
    preview.shoes.label,
    if (preview.outerwear != null) preview.outerwear!.label,
  ];
  final explain = StylistOutfitExplainBuilder.buildLocalExplainSk(
    suggestedItems: [
      preview.top.item,
      preview.bottom.item,
      preview.shoes.item,
      if (preview.outerwear != null) preview.outerwear!.item,
    ],
    profile: profile,
    wardrobeAnalysis: analysis,
    activityType: outfitIntent.activityType,
    stylistOpinion: opinion,
    weatherIsRainy: weather.isRainy,
    wetGroundMuddy: wetGroundMuddy,
    tempC: weather.tempC,
    conversationText: prompt,
  );

  return StylistChatScenarioReport(
    label: scenario.label,
    prompt: prompt,
    ok: true,
    outfitItems: outfitItems,
    explain: explain,
    usedCompromise: analysis.usedCompromise,
    missingItems: analysis.missingItems,
    compromiseItems: analysis.compromiseItems,
    identityScore: identity.score,
    identityReasons: identity.reasons,
    replySource: StylistChatReplySource.local,
    stylistOpinion: opinion,
  );
}

void main() {
  group('StylistChatPipelineDebugRunner — StylistOpinion report', () {
    test('10 scenárov obsahuje StylistOpinion blok', () {
      final wardrobe = _stabilizationWardrobe();
      final reports = <StylistChatScenarioReport>[];

      for (final scenario in StylistChatPipelineDebugRunner.defaultScenarios) {
        reports.add(_buildScenarioReport(scenario: scenario, wardrobe: wardrobe));
      }

      expect(reports.length, 10);
      for (var i = 0; i < reports.length; i++) {
        final report = reports[i];
        expect(report.ok, isTrue);
        expect(report.stylistOpinion, isNotNull);
        final block = report.formatBlock(index: i + 1);
        expect(block, contains('SCENÁR ${i + 1}:'));
        expect(block, contains('Prompt:'));
        expect(block, contains('Outfit:'));
        expect(block, contains('Explain:'));
        expect(block, contains('WardrobeAnalysis:'));
        expect(block, contains('- missingItems:'));
        expect(block, contains('StylistOpinion:'));
        expect(block, contains('- confidence:'));
        expect(block, contains('- level:'));
        expect(block, contains('- opinion:'));
        expect(block, contains('- biggestMissingPiece:'));
        expect(block, contains('Reply source:'));

        // QA report nesmie obsahovať interné/technické polia.
        expect(block, isNot(contains('- factors:')));
        expect(block, isNot(contains('IdentityScore')));
        expect(block, isNot(contains('Použitý compromise')));
        expect(block, isNot(contains('- strengths:')));
      }

      final run = StylistChatDebugRunResult(
        reports: reports,
        summary: StylistChatDebugSummary.fromReports(reports),
      );

      final header = run.summary.formatBlock();
      expect(header, contains('STYLIST CHAT QA REPORT'));
      expect(header, contains('Úspešne: 10/10'));
      expect(header, contains('Priemerná confidence:'));

      final footer = run.footerText();
      expect(footer, contains('Najslabšie scenáre:'));
      expect(footer, contains('Najčastejšie missingItems:'));

      final full = run.fullText();
      // ignore: avoid_print
      print('\n$full');
    });
  });
}
