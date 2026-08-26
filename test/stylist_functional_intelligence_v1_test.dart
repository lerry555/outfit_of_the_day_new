import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_chat_outfit_service.dart';
import 'package:outfitofTheDay/domain/style_preferences/styling_presentation.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_outfit_result_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/functional_suitability_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_composition_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_suitability_policy_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';

void main() {
  group('presentation authority', () {
    test(
      'menswear excludes strongly womenswear pieces but keeps unknown/unisex',
      () {
        final skirt = resolved(
          'skirt',
          type: 'maxi_skirt',
          slots: const ['lower_body'],
        );
        final tee = resolved(
          'tee',
          type: 't_shirt',
          slots: const ['upper_body'],
        );

        expect(
          FunctionalSuitabilityEvaluatorV1.presentationAllowed(
            skirt,
            StylingPresentation.menswear,
          ),
          isFalse,
        );
        expect(
          FunctionalSuitabilityEvaluatorV1.presentationAllowed(
            tee,
            StylingPresentation.menswear,
          ),
          isTrue,
        );
        expect(
          FunctionalSuitabilityEvaluatorV1.presentationAllowed(
            skirt,
            StylingPresentation.noPreference,
          ),
          isTrue,
        );
      },
    );

    test('wardrobe contents never infer the owner preference', () {
      expect(StylingPresentation.parse(null), StylingPresentation.noPreference);
      expect(
        StylingPresentation.parse('menswear'),
        StylingPresentation.menswear,
      );
    });

    test(
      'an explicit item request can override the saved presentation filter',
      () {
        final wardrobe = <ResolvedWardrobeItemV2>[
          resolved('tee', type: 't_shirt', slots: const ['upper_body']),
          resolved('skirt', type: 'maxi_skirt', slots: const ['lower_body']),
          resolved('shoes', type: 'sneakers', slots: const ['feet']),
        ];
        final filtered = V2FlexibleCandidateMatrix.generate(
          wardrobe: wardrobe,
          context: const V2CandidateMatrixContext(
            stylingPresentation: StylingPresentation.menswear,
          ),
        );
        final explicitlyRequested = V2FlexibleCandidateMatrix.generate(
          wardrobe: wardrobe,
          context: const V2CandidateMatrixContext(
            stylingPresentation: StylingPresentation.menswear,
            requestedItemIds: {'skirt'},
          ),
        );

        expect(filtered, isEmpty);
        expect(explicitlyRequested, isNotEmpty);
        expect(
          explicitlyRequested.first.outfit.items.map((item) => item.itemId),
          contains('skirt'),
        );
      },
    );
  });

  group('general functional suitability', () {
    test('winter ankle boots are not promoted to hiking footwear', () {
      final boots = resolved(
        'boots',
        type: 'winter_boots',
        slots: const ['feet'],
        warmth: 9,
      );
      final result = assess(
        [boots],
        const ActivityFunctionalRequirementsV1(
          activityType: 'hiking',
          outdoor: true,
          isRainy: false,
          wetGroundRisk: false,
          minimumFormality: 1,
          durationMinutes: 360,
          terrain: 'mountain_trail',
          tempC: 2,
        ),
      );

      expect(result.tier, FunctionalSuitabilityTierV1.strongCompromise);
      expect(
        result.reasonCodes,
        contains('footwear_not_hiking_or_trail_rated'),
      );
      expect(result.missingCapabilities, contains('hiking_footwear'));
    });

    test('real hiking footwear remains ideal for a long mountain hike', () {
      final boots = resolved(
        'hiking',
        type: 'hiking_boots',
        slots: const ['feet'],
        warmth: 6,
      );
      final result = assess(
        [boots],
        const ActivityFunctionalRequirementsV1(
          activityType: 'hiking',
          outdoor: true,
          isRainy: true,
          wetGroundRisk: true,
          minimumFormality: 1,
          durationMinutes: 360,
          terrain: 'mountain_trail',
          tempC: 5,
        ),
      );
      expect(result.tier, FunctionalSuitabilityTierV1.ideal);
    });

    test('legacy ranking no longer treats every boot as a hiking boot', () {
      final winterBoots = resolved(
        'winter',
        type: 'winter_boots',
        slots: const ['feet'],
        warmth: 9,
      );
      final hikingBoots = resolved(
        'hiking',
        type: 'hiking_boots',
        slots: const ['feet'],
        warmth: 6,
      );
      expect(
        OutfitSuitabilityPolicyV2.footwearPreferenceRank(
          hikingBoots.item,
          activityType: 'hiking',
          formalityFloorValue: 1,
          isRainy: false,
          tempC: 3,
        ),
        lessThan(
          OutfitSuitabilityPolicyV2.footwearPreferenceRank(
            winterBoots.item,
            activityType: 'hiking',
            formalityFloorValue: 1,
            isRainy: false,
            tempC: 3,
          ),
        ),
      );
    });

    test(
      'frozen matrix prefers actual hiking footwear over winter fashion boots',
      () {
        final wardrobe = <ResolvedWardrobeItemV2>[
          resolved(
            'top',
            type: 'technical_base_layer',
            slots: const ['upper_body'],
            layer: 'base',
            outfitFunctions: const ['sport', 'outdoor'],
          ),
          resolved(
            'bottom',
            type: 'hiking_pants',
            slots: const ['lower_body'],
            outfitFunctions: const ['sport', 'outdoor', 'mobility'],
          ),
          resolved(
            'winter',
            type: 'winter_boots',
            slots: const ['feet'],
            warmth: 9,
          ),
          resolved(
            'hiking',
            type: 'hiking_boots',
            slots: const ['feet'],
            warmth: 6,
          ),
        ];
        final matrix = V2FlexibleCandidateMatrix.generate(
          wardrobe: wardrobe,
          context: const V2CandidateMatrixContext(
            activityType: 'hiking',
            activityDurationMinutes: 360,
            terrain: 'mountainTrail',
            tempC: 3,
            maxCandidates: 8,
          ),
        );

        expect(matrix, isNotEmpty);
        expect(
          matrix.first.outfit.items
              .singleWhere((item) => item.item.bodySlots.contains('feet'))
              .item
              .canonicalType,
          'hiking_boots',
        );
        final winterCandidates = matrix.where(
          (candidate) => candidate.outfit.items.any(
            (item) => item.item.canonicalType == 'winter_boots',
          ),
        );
        expect(
          winterCandidates.every(
            (candidate) =>
                candidate.functionalAssessment?.tier ==
                FunctionalSuitabilityTierV1.strongCompromise,
          ),
          isTrue,
        );
      },
    );

    test('jeans are a disclosed compromise, not a global outdoor ban', () {
      final jeans = resolved(
        'jeans',
        type: 'jeans',
        slots: const ['lower_body'],
      );
      final longHike = assess(
        [jeans],
        const ActivityFunctionalRequirementsV1(
          activityType: 'hiking',
          outdoor: true,
          isRainy: false,
          wetGroundRisk: false,
          minimumFormality: 1,
          durationMinutes: 360,
        ),
      );
      final shortWalk = assess(
        [jeans],
        const ActivityFunctionalRequirementsV1(
          activityType: 'nature_walk',
          outdoor: true,
          isRainy: false,
          wetGroundRisk: false,
          minimumFormality: 1,
          durationMinutes: 45,
        ),
      );
      expect(longHike.tier, FunctionalSuitabilityTierV1.strongCompromise);
      expect(shortWalk.tier, FunctionalSuitabilityTierV1.good);
    });

    test(
      'wet forest fashion sneakers remain selectable only as honest compromise',
      () {
        final sneakers = resolved(
          'fashion-shoes',
          type: 'sneakers',
          slots: const ['feet'],
        );
        final wet = assess(
          [sneakers],
          const ActivityFunctionalRequirementsV1(
            activityType: 'nature_walk',
            outdoor: true,
            isRainy: false,
            wetGroundRisk: true,
            minimumFormality: 1,
            durationMinutes: 180,
          ),
        );
        final dry = assess(
          [sneakers],
          const ActivityFunctionalRequirementsV1(
            activityType: 'nature_walk',
            outdoor: true,
            isRainy: false,
            wetGroundRisk: false,
            minimumFormality: 1,
            durationMinutes: 90,
          ),
        );
        expect(wet.tier, FunctionalSuitabilityTierV1.strongCompromise);
        expect(wet.reasonCodes, contains('wet_terrain_grip_unverified'));
        expect(dry.tier, FunctionalSuitabilityTierV1.acceptableCompromise);
      },
    );

    test('unknown rain performance never turns denim into a rain shell', () {
      final denim = resolved(
        'denim',
        type: 'denim_jacket',
        slots: const ['upper_body'],
        layer: 'outer',
      );
      final result = assess(
        [denim],
        const ActivityFunctionalRequirementsV1(
          activityType: 'city_walk',
          outdoor: true,
          isRainy: true,
          wetGroundRisk: false,
          minimumFormality: 1,
        ),
      );
      expect(result.tier, FunctionalSuitabilityTierV1.strongCompromise);
      expect(result.missingCapabilities, contains('rain_shell'));
    });

    test('formal and athletic requirements remain distinct', () {
      final dress = resolved(
        'dress',
        type: 'dress',
        slots: const ['full_body'],
        formality: 8,
      );
      final gym = assess(
        [dress],
        const ActivityFunctionalRequirementsV1(
          activityType: 'gym',
          outdoor: false,
          isRainy: false,
          wetGroundRisk: false,
          minimumFormality: 1,
        ),
      );
      final dinner = assess(
        [dress],
        const ActivityFunctionalRequirementsV1(
          activityType: 'dinner',
          outdoor: false,
          isRainy: false,
          wetGroundRisk: false,
          minimumFormality: 6,
        ),
      );
      expect(gym.tier, FunctionalSuitabilityTierV1.inappropriate);
      expect(dinner.tier, FunctionalSuitabilityTierV1.good);
    });

    test(
      'cross-category functional benchmark preserves material distinctions',
      () {
        final scenarios =
            <
              ({
                String label,
                ResolvedWardrobeItemV2 item,
                ActivityFunctionalRequirementsV1 requirements,
                FunctionalSuitabilityTierV1 expected,
              })
            >[
              (
                label: 'running shoe supports an all-day zoo visit',
                item: resolved(
                  'run',
                  type: 'running_shoes',
                  slots: const ['feet'],
                ),
                requirements: const ActivityFunctionalRequirementsV1(
                  activityType: 'zoo',
                  outdoor: true,
                  isRainy: false,
                  wetGroundRisk: false,
                  minimumFormality: 1,
                  durationMinutes: 420,
                ),
                expected: FunctionalSuitabilityTierV1.good,
              ),
              (
                label: 'formal footwear is a walking-day compromise',
                item: resolved(
                  'oxford',
                  type: 'oxford_shoes',
                  slots: const ['feet'],
                ),
                requirements: const ActivityFunctionalRequirementsV1(
                  activityType: 'sightseeing',
                  outdoor: true,
                  isRainy: false,
                  wetGroundRisk: false,
                  minimumFormality: 1,
                  durationMinutes: 420,
                ),
                expected: FunctionalSuitabilityTierV1.strongCompromise,
              ),
              (
                label: 'fashion blouse is not a technical hiking top',
                item: resolved(
                  'blouse',
                  type: 'blouse',
                  slots: const ['upper_body'],
                ),
                requirements: const ActivityFunctionalRequirementsV1(
                  activityType: 'hiking',
                  outdoor: true,
                  isRainy: false,
                  wetGroundRisk: false,
                  minimumFormality: 1,
                  durationMinutes: 360,
                ),
                expected: FunctionalSuitabilityTierV1.strongCompromise,
              ),
              (
                label:
                    'ordinary top with unknown moisture handling stays a disclosed compromise',
                item: resolved(
                  'tee',
                  type: 't_shirt',
                  slots: const ['upper_body'],
                ),
                requirements: const ActivityFunctionalRequirementsV1(
                  activityType: 'hiking',
                  outdoor: true,
                  isRainy: false,
                  wetGroundRisk: false,
                  minimumFormality: 1,
                  durationMinutes: 360,
                ),
                expected: FunctionalSuitabilityTierV1.acceptableCompromise,
              ),
              (
                label: 'maxi skirt is rejected for a demanding trail',
                item: resolved(
                  'skirt',
                  type: 'maxi_skirt',
                  slots: const ['lower_body'],
                ),
                requirements: const ActivityFunctionalRequirementsV1(
                  activityType: 'hiking',
                  outdoor: true,
                  isRainy: false,
                  wetGroundRisk: false,
                  minimumFormality: 1,
                  durationMinutes: 360,
                ),
                expected: FunctionalSuitabilityTierV1.inappropriate,
              ),
              (
                label: 'rain shell is not confused with fashion outerwear',
                item: resolved(
                  'shell',
                  type: 'rain_shell',
                  slots: const ['upper_body'],
                  layer: 'shell',
                ),
                requirements: const ActivityFunctionalRequirementsV1(
                  activityType: 'city_walk',
                  outdoor: true,
                  isRainy: true,
                  wetGroundRisk: false,
                  minimumFormality: 1,
                ),
                expected: FunctionalSuitabilityTierV1.ideal,
              ),
              (
                label: 'formal dress remains valid for an indoor dinner',
                item: resolved(
                  'dress',
                  type: 'dress',
                  slots: const ['full_body'],
                  formality: 8,
                ),
                requirements: const ActivityFunctionalRequirementsV1(
                  activityType: 'dinner',
                  outdoor: false,
                  isRainy: false,
                  wetGroundRisk: false,
                  minimumFormality: 6,
                ),
                expected: FunctionalSuitabilityTierV1.good,
              ),
            ];

        for (final scenario in scenarios) {
          expect(
            assess([scenario.item], scenario.requirements).tier,
            scenario.expected,
            reason: scenario.label,
          );
        }
      },
    );

    test('shopping handoff prioritizes the most material owned-item gap', () {
      final items = <ResolvedWardrobeItemV2>[
        resolved('tee', type: 't_shirt', slots: const ['upper_body']),
        resolved('jeans', type: 'jeans', slots: const ['lower_body']),
        resolved('shoes', type: 'fashion_sneakers', slots: const ['feet']),
      ];
      const requirements = ActivityFunctionalRequirementsV1(
        activityType: 'hiking',
        outdoor: true,
        isRainy: false,
        wetGroundRisk: true,
        minimumFormality: 1,
        durationMinutes: 360,
        terrain: 'mountain_trail',
      );
      final functional = assess(items, requirements);
      final analysis = StylistChatOutfitService.wardrobeGapAnalysisForTest(
        outfitFor(items),
        functional,
      );

      expect(analysis.usedCompromise, isTrue);
      expect(analysis.missingItems, isNotEmpty);
      expect(analysis.missingItems.first.category, 'hiking_footwear');
      expect(analysis.compromiseItems, containsAll(<String>['jeans', 'shoes']));
    });
  });
}

CandidateFunctionalAssessmentV1 assess(
  List<ResolvedWardrobeItemV2> items,
  ActivityFunctionalRequirementsV1 requirements,
) {
  return FunctionalSuitabilityEvaluatorV1.assessCandidate(
    outfit: outfitFor(items),
    source: items,
    requirements: requirements,
  );
}

V2FlexibleOutfitResult outfitFor(List<ResolvedWardrobeItemV2> items) {
  final wrapped = items
      .map(
        (resolved) => V2FlexibleOutfitItem(
          itemId: resolved.itemId,
          item: resolved.item,
          compositionRole: CompositionRoleV2.core,
          compositionGroup: resolved.item.bodySlots.contains('feet')
              ? 'footwear'
              : resolved.item.bodySlots.contains('lower_body')
              ? 'lower_body_core'
              : 'upper_body_core',
          requiredness: 'required',
          selectionReason: 'fixture',
          display: resolved.raw,
        ),
      )
      .toList(growable: false);
  return V2FlexibleOutfitResult(
    template: OutfitTemplateV2.separates,
    items: wrapped,
    completeness: const OutfitCompletenessV2(
      coreComplete: true,
      weatherComplete: true,
      dressCodeComplete: true,
      functionalComplete: true,
      enhanced: false,
      gaps: <String>[],
    ),
  );
}

ResolvedWardrobeItemV2 resolved(
  String id, {
  required String type,
  required List<String> slots,
  String layer = 'not_applicable',
  int warmth = 4,
  int formality = 4,
  List<String> outfitFunctions = const <String>[],
}) {
  final item = WardrobeItemV2(
    canonicalType: type,
    canonicalFamily: slots.contains('feet') ? 'footwear' : 'clothing',
    bodySlots: slots,
    layerPosition: layer,
    colorProfile: const ColorProfileV2(
      primary: SemanticColorV2(family: 'black'),
    ),
    formality: formality,
    outfitFunctions: outfitFunctions,
    styles: const <String>[],
    occasionFit: const <String>['everyday'],
    seasons: const <String>['all_season'],
    warmth: warmth,
    attributes: const <String, dynamic>{},
    fieldSources: const <String, dynamic>{'canonicalType': 'visual_ai'},
    fieldConfidence: const <String, dynamic>{'canonicalType': 0.9},
    userOverrideFields: const <String>[],
  );
  return ResolvedWardrobeItemV2(
    itemId: id,
    item: item,
    raw: <String, dynamic>{'id': id, ...item.toMap()},
  );
}
