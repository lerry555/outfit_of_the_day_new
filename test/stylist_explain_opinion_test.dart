import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/data/stylist_opinion.dart';
import 'package:outfitofTheDay/data/wardrobe_analysis.dart';
import 'package:outfitofTheDay/utils/stylist_occasion_guidance.dart';
import 'package:outfitofTheDay/utils/stylist_outfit_explain_builder.dart';

StylistOpinion _opinion({
  required StylistOpinionLevel level,
  required String shortOpinionSk,
  String? biggestMissingPiece,
  int confidence = 60,
}) {
  return StylistOpinion(
    overallConfidence: confidence,
    opinionLevel: level,
    strengths: const [],
    compromises: const [],
    biggestMissingPiece: biggestMissingPiece,
    shortOpinionSk: shortOpinionSk,
    factors: const [],
  );
}

List<Map<String, dynamic>> _items() => [
      {'name': 'Čisté biele tričko'},
      {'name': 'Sivé nohavice'},
      {'name': 'Biele tenisky'},
    ];

void main() {
  const profile = StylistOccasionProfile();

  group('buildLocalExplainSk — rešpektuje StylistOpinion', () {
    test('weak → úprimný tón, spomenie biggestMissingPiece, žiadne vychvaľovanie',
        () {
      final explain = StylistOutfitExplainBuilder.buildLocalExplainSk(
        suggestedItems: _items(),
        profile: profile,
        wardrobeAnalysis: const WardrobeAnalysis(usedCompromise: true),
        stylistOpinion: _opinion(
          level: StylistOpinionLevel.weak,
          confidence: 43,
          biggestMissingPiece: 'košeľa',
          shortOpinionSk:
              'Úprimne, nie som z neho úplne presvedčený na svadbu. '
              'Najviac by pomohlo košeľa.',
        ),
      );
      final lower = explain.toLowerCase();
      expect(lower, contains('košeľa'));
      expect(lower, isNot(contains('pokojne odporučil')));
      expect(lower, isNot(contains('ideálny outfit')));
      expect(
        lower.contains('úprimne') ||
            lower.contains('úprimný') ||
            lower.contains('chýba') ||
            lower.contains('zmeniť') ||
            lower.contains('presvedčen') ||
            lower.contains('pomohlo') ||
            lower.contains('kompromis') ||
            lower.contains('limity') ||
            lower.contains('nadšen') ||
            lower.contains('spokojn') ||
            lower.contains('tvrdiť') ||
            lower.contains('nie je ono') ||
            lower.contains('mrzí'),
        isTrue,
      );
    });

    test('acceptable → rozumný kompromis, netvrdí ideál', () {
      final explain = StylistOutfitExplainBuilder.buildLocalExplainSk(
        suggestedItems: _items(),
        profile: profile,
        wardrobeAnalysis: const WardrobeAnalysis(usedCompromise: true),
        stylistOpinion: _opinion(
          level: StylistOpinionLevel.acceptable,
          shortOpinionSk:
              'Z toho, čo máš v šatníku, je to rozumný kompromis na pohovor. '
              'Nie je to ideál, ale dá sa.',
        ),
      );
      expect(explain.toLowerCase(), contains('kompromis'));
      expect(explain.toLowerCase(), isNot(contains('pokojne odporučil')));
    });

    test('excellent → môže znieť sebavedomo', () {
      final explain = StylistOutfitExplainBuilder.buildLocalExplainSk(
        suggestedItems: _items(),
        profile: profile,
        wardrobeAnalysis: const WardrobeAnalysis(),
        activityType: 'hike',
        stylistOpinion: _opinion(
          level: StylistOpinionLevel.excellent,
          confidence: 88,
          shortOpinionSk: 'Tento outfit by som na túru pokojne odporučil.',
        ),
      );
      final lower = explain.toLowerCase();
      expect(
        lower.contains('odporučil') ||
            lower.contains('vydaren') ||
            lower.contains('sedí') ||
            lower.contains('zmysel') ||
            lower.contains('dobré') ||
            lower.contains('výborne') ||
            lower.contains('poslúži') ||
            lower.contains('vzal') ||
            lower.contains('prirodzene') ||
            lower.contains('sebavedomo') ||
            lower.contains('nemenil'),
        isTrue,
      );
      expect(lower, isNot(contains('poskladal som ti')));
    });
  });

  group('replyIsMisleading — AI nesmie byť optimistickejší než opinion', () {
    test('acceptable + „ideálny outfit" → misleading', () {
      final misleading = StylistOutfitExplainBuilder.replyIsMisleading(
        reply: 'Toto je ideálny outfit, sedí ti perfektne.',
        profile: profile,
        stylistOpinion:
            _opinion(level: StylistOpinionLevel.acceptable, shortOpinionSk: ''),
      );
      expect(misleading, isTrue);
    });

    test('weak + „skvelá voľba" → misleading', () {
      final misleading = StylistOutfitExplainBuilder.replyIsMisleading(
        reply: 'Skvelá voľba, vyzeráš výborne.',
        profile: profile,
        stylistOpinion:
            _opinion(level: StylistOpinionLevel.weak, shortOpinionSk: ''),
      );
      expect(misleading, isTrue);
    });

    test('excellent + sebavedomý tón → nie je misleading', () {
      final misleading = StylistOutfitExplainBuilder.replyIsMisleading(
        reply: 'Tento outfit je ideálny na túru, pokojne ho odporúčam.',
        profile: profile,
        stylistOpinion:
            _opinion(level: StylistOpinionLevel.excellent, shortOpinionSk: ''),
      );
      expect(misleading, isFalse);
    });

    test('acceptable + úprimný kompromisný tón → nie je misleading', () {
      final misleading = StylistOutfitExplainBuilder.replyIsMisleading(
        reply: 'Je to rozumný kompromis z tvojho šatníka, nie úplný ideál.',
        profile: profile,
        stylistOpinion:
            _opinion(level: StylistOpinionLevel.acceptable, shortOpinionSk: ''),
      );
      // „nie úplný ideál" je úprimné priznanie kompromisu, nie vychvaľovanie.
      expect(misleading, isFalse);
    });
  });
}
