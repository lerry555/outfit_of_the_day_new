import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_set_policy_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_set_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_set_session_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_ontology_v2.dart';
import 'dart:io';

void main() {
  test('semantic vocabulary is count-independent and versioned', () {
    expect(
      WardrobeSetTypeV2.values.map((e) => e.wireName),
      containsAll([
        'suit',
        'tracksuit',
        'matching_set',
        'pajama_set',
        'swim_set',
        'underwear_set',
        'accessory_set',
        'other',
      ]),
    );
    expect(
      WardrobeSetTypeV2.values.map((e) => e.wireName),
      isNot(contains('two_piece')),
    );
  });

  test('two, three and six components complete; UI stops at six', () {
    expect(WardrobeSetPolicyV2.canComplete(['a']), isFalse);
    expect(WardrobeSetPolicyV2.canComplete(['a', 'b']), isTrue);
    expect(WardrobeSetPolicyV2.canComplete(['a', 'b', 'c']), isTrue);
    expect(
      WardrobeSetPolicyV2.canAddInInitialUi(['1', '2', '3', '4', '5']),
      isTrue,
    );
    expect(
      WardrobeSetPolicyV2.canAddInInitialUi(['1', '2', '3', '4', '5', '6']),
      isFalse,
    );
  });

  test('removing to one member dissolves without deleting remaining item', () {
    final plan = WardrobeSetPolicyV2.removeMember(['hoodie', 'pants'], 'pants');
    expect(plan.dissolve, isTrue);
    expect(plan.remainingMemberIds, ['hoodie']);
  });

  test('same set has stable color and icon identity', () {
    expect(
      WardrobeSetPresentationV2.borderColor('set-a'),
      WardrobeSetPresentationV2.borderColor('set-a'),
    );
    expect(
      WardrobeSetPresentationV2.stableIndex('set-a'),
      inInclusiveRange(0, 7),
    );
  });

  test('formal suit and curated relationships receive contextual strength', () {
    final formal = WardrobeSetPolicyV2.contextualCompatibility(
      setType: WardrobeSetTypeV2.suit,
      source: WardrobeSetRelationshipSourceV2.manufacturerMatching,
      minimumFormality: 8,
      comparableAlternative: true,
    );
    final casual = WardrobeSetPolicyV2.contextualCompatibility(
      setType: WardrobeSetTypeV2.tracksuit,
      source: WardrobeSetRelationshipSourceV2.manufacturerMatching,
      minimumFormality: 2,
      comparableAlternative: true,
    );
    final curated = WardrobeSetPolicyV2.contextualCompatibility(
      setType: WardrobeSetTypeV2.matchingSet,
      source: WardrobeSetRelationshipSourceV2.userCurated,
      minimumFormality: 2,
      comparableAlternative: true,
    );
    expect(formal, greaterThan(casual));
    expect(curated, greaterThan(casual));
  });

  test('partial success survives and retry does not repeat cached AI', () {
    var session = const WardrobeSetSessionV2(
      draftId: 'draft-1',
      components: [],
    );
    session = session.update(
      const WardrobeSetDraftComponentV2(
        componentId: 'hoodie',
        status: WardrobeSetComponentStatusV2.saved,
        itemId: 'item-1',
        cachedAnalyzerPayload: {'canonicalType': 'hoodie'},
      ),
      inferenceStarted: true,
    );
    session = session.update(
      const WardrobeSetDraftComponentV2(
        componentId: 'pants',
        status: WardrobeSetComponentStatusV2.failed,
        failureStage: 'save',
        cachedAnalyzerPayload: {'canonicalType': 'sweatpants'},
      ),
      inferenceStarted: true,
    );
    expect(session.savedCount, 1);
    expect(session.canComplete, isFalse);
    expect(session.shouldRunInference('hoodie'), isFalse);
    expect(session.shouldRunInference('pants'), isFalse);
    expect(session.inferenceCount, 2);
  });

  test('AI suggestion alone cannot become authoritative membership', () async {
    final ontology = WardrobeOntologyV2.fromJsonString(
      await File('assets/data/wardrobe_ontology_v2.json').readAsString(),
    );
    final suggested = WardrobeItemV2(
      canonicalType: 'hoodie',
      canonicalFamily: ontology.definition('hoodie')!.canonicalFamily,
      bodySlots: ontology.definition('hoodie')!.defaultBodySlots,
      layerPosition: ontology.definition('hoodie')!.defaultLayerPosition,
      colorProfile: const ColorProfileV2(
        primary: SemanticColorV2(family: 'blue'),
        metalTone: 'none',
        hardwareTone: 'none',
      ),
      formality: 3,
      styles: const [],
      occasionFit: const [],
      seasons: const [],
      warmth: 5,
      attributes: const {},
      fieldSources: const {
        'canonicalType': 'visual_ai',
        'setMembership': 'ai_suggestion',
      },
      fieldConfidence: const {'canonicalType': .9, 'setMembership': .8},
      userOverrideFields: const ['setMembership'],
      setMembership: const SetMembershipV2(
        setId: 'suggested-only',
        setType: 'tracksuit',
        authority: 'ai_suggestion',
      ),
    );
    expect(
      WardrobeItemV2Validator(ontology).validate(suggested),
      contains('userOverrideFields.source_mismatch:setMembership'),
    );
  });
}
