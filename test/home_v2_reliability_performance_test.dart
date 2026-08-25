import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/home_final_review_payload.dart';
import 'package:outfitofTheDay/Services/home_generation_telemetry.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_outfit_result_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_composition_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/utils/home_user_facing_reason.dart';

WardrobeItemV2 _item(String type, String family, List<String> slots) {
  return WardrobeItemV2(
    canonicalType: type,
    canonicalFamily: family,
    bodySlots: slots,
    layerPosition: family == 'footwear' ? 'not_applicable' : 'base',
    colorProfile: const ColorProfileV2(
      primary: SemanticColorV2(family: 'navy'),
    ),
    formality: 4,
    styles: const ['casual'],
    occasionFit: const ['everyday'],
    seasons: const ['summer'],
    warmth: 3,
    attributes: const {'unused': true},
    fieldSources: const {'canonicalType': 'visual_ai'},
    fieldConfidence: const {'canonicalType': 0.9},
    userOverrideFields: const [],
    analyzerProvenance: const {'model': 'secret'},
  );
}

V2FlexibleCandidate _candidate() {
  final shirt = _item('t_shirt', 'top', const ['upper_body']);
  final jeans = _item('jeans', 'bottom', const ['lower_body']);
  final shoes = _item('sneakers', 'footwear', const ['feet']);
  return V2FlexibleCandidate(
    candidateId: 'v2_1',
    score: 12,
    scoreBreakdown: const {'core': 4, 'weather': 2},
    outfit: V2FlexibleOutfitResult(
      template: OutfitTemplateV2.separates,
      completeness: const OutfitCompletenessV2(
        coreComplete: true,
        weatherComplete: true,
        dressCodeComplete: true,
        functionalComplete: true,
        enhanced: false,
        gaps: [],
      ),
      items: [
        V2FlexibleOutfitItem(
          itemId: 'shirt-1',
          item: shirt,
          compositionRole: CompositionRoleV2.core,
          compositionGroup: 'upper_body_core',
          requiredness: 'required',
          selectionReason: 'core',
          display: const {
            'imageUrl': 'https://example.invalid/secret.jpg',
            'name': 'should-not-ship',
          },
        ),
        V2FlexibleOutfitItem(
          itemId: 'jeans-1',
          item: jeans,
          compositionRole: CompositionRoleV2.core,
          compositionGroup: 'lower_body_core',
          requiredness: 'required',
          selectionReason: 'core',
        ),
        V2FlexibleOutfitItem(
          itemId: 'shoes-1',
          item: shoes,
          compositionRole: CompositionRoleV2.core,
          compositionGroup: 'footwear_core',
          requiredness: 'required',
          selectionReason: 'core',
        ),
      ],
    ),
  );
}

void main() {
  group('Home user-facing reasons', () {
    test('internal pipeline labels are never displayable', () {
      expect(HomeUserFacingReason.isInternal('v2_rule_score_fallback'), isTrue);
      expect(HomeUserFacingReason.isInternal('v2_flexible_selection'), isTrue);
      expect(
        HomeUserFacingReason.isInternal(
          'V2 separates: core=true, weather=true, dressCode=true, functional=true, enhanced=false',
        ),
        isTrue,
      );
      expect(HomeUserFacingReason.forDisplay('v2_rule_score_fallback'), isNull);
      expect(HomeUserFacingReason.forDisplay('openai_error'), isNull);
    });

    test('local fallback copy is human Slovak without internal names', () {
      final text = HomeUserFacingReason.fromLocalSelection(
        tempC: 24,
        isRainy: false,
        isWindy: false,
        garmentLabels: const [
          'Bordové tričko',
          'Modré rifle',
          'Biele tenisky',
        ],
      );
      expect(text.toLowerCase(), contains('24'));
      expect(text.toLowerCase(), contains('tričko'));
      expect(text.contains('v2_rule_score_fallback'), isFalse);
      expect(text.contains('_'), isFalse);
    });
  });

  group('Final-review payload', () {
    test('omits display docs, resolvedItem, images and provenance', () {
      final payload = HomeFinalReviewPayload.fromCandidates([_candidate()]);
      expect(payload, hasLength(1));
      expect(HomeFinalReviewPayload.isCompact(payload.first), isTrue);
      expect(payload.first['candidateIndex'], 0);
      expect(payload.first['ruleScore'], 12);
      final items = payload.first['items'] as List;
      expect(items.length, 3);
      expect(
        items.first['id'],
        'shirt-1',
      );
      expect(jsonEncode(payload).contains('secret.jpg'), isFalse);
      expect(jsonEncode(payload).contains('analyzerProvenance'), isFalse);
      expect(jsonEncode(payload).contains('https://'), isFalse);
      final bytes = HomeFinalReviewPayload.utf8ByteLength({
        'candidates': payload,
      });
      final fatBytes = HomeFinalReviewPayload.utf8ByteLength({
        'candidates': [
          {
            ..._candidate().outfit.toMap(),
            'score': 12,
          },
        ],
      });
      expect(bytes, lessThan(fatBytes));
      expect(bytes, lessThan(2500));
    });

    test('caps candidates at 4', () {
      final many = List<V2FlexibleCandidate>.generate(8, (_) => _candidate());
      expect(HomeFinalReviewPayload.fromCandidates(many), hasLength(4));
    });
  });

  group('Timeout policy', () {
    test('final review stays at 8s and generateHomeOutfit at 9s', () {
      expect(kHomeFinalReviewTimeout, const Duration(seconds: 8));
      expect(kHomeGenerateOutfitTimeout, const Duration(seconds: 9));
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(home.contains('timeout(const Duration(seconds: 6))'), isFalse);
      expect(home.contains('kHomeGenerateOutfitTimeout'), isTrue);
      expect(home.contains('kHomeFinalReviewTimeout'), isTrue);
      expect(
        home.contains('timeout(const Duration(seconds: 6))'),
        isFalse,
      );
      final runner = File(
        'lib/Services/outfit_stylist_final_review_runner.dart',
      ).readAsStringSync();
      expect(runner.contains('kHomeFinalReviewTimeout'), isTrue);
      expect(runner.contains('Duration(seconds: 8)'), isFalse);
    });
  });

  group('Home control flow', () {
    test('Tomorrow stays lazy and late final-review replace is skipped', () {
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(home.contains('[HOME_PRELOAD] ensure_today_only started'), isTrue);
      expect(
        home.contains('[HOME_PRELOAD] tomorrow_deferred_until_zajtra'),
        isTrue,
      );
      expect(home.contains('_deferTomorrowDailyOutfitEnsure'), isFalse);
      expect(
        home.contains(
          '[HOME_FINAL_REVIEW] skip_late_replace reason=keep_visible_local_fallback',
        ),
        isTrue,
      );
      expect(home.contains("selectedReason = 'v2_rule_score_fallback'"), isFalse);
      expect(
        home.contains('HomeFinalReviewPayload.fromCandidates'),
        isFalse,
      );
      expect(
        home.contains('OutfitStylistFinalReviewRunner()'),
        isTrue,
      );
    });

    test('Home explanation card strips internal labels', () {
      final card = File(
        'lib/widgets/home/home_ai_explanation_card.dart',
      ).readAsStringSync();
      expect(card.contains('HomeUserFacingReason.forDisplay'), isTrue);
    });

    test('hero images keep bounded decode and no BackdropFilter restore', () {
      final hero = File(
        'lib/screens/home_screen_hero_image_widgets.dart',
      ).readAsStringSync();
      expect(hero.contains('cacheWidth: kHomeHeroImageCacheWidth'), isTrue);
      expect(hero.contains('BackdropFilter'), isFalse);
      expect(hero.contains('FilterQuality.high'), isFalse);
    });
  });
}
