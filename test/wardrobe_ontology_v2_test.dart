import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_ontology_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_composition_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_adapters.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_write_builder.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/native_outfit_engine_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_outfit_result_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/Services/native_wardrobe_v2_runtime.dart';
import 'package:outfitofTheDay/models/calendar_outfit_models.dart';
import 'package:outfitofTheDay/Services/outfit_generation_service.dart';

WardrobeItemV2 item(
  String type,
  String family,
  List<String> slots,
  String layer, {
  int formality = 5,
  List<String> functions = const [],
  String? accessoryGroup,
  SetMembershipV2? setMembership,
}) => WardrobeItemV2(
  canonicalType: type,
  canonicalFamily: family,
  bodySlots: slots,
  layerPosition: layer,
  outfitFunctions: functions,
  accessoryGroup: accessoryGroup,
  setMembership: setMembership,
  colorProfile: const ColorProfileV2(
    primary: SemanticColorV2(family: 'black'),
    metalTone: 'none',
    hardwareTone: 'none',
  ),
  formality: formality,
  styles: const [],
  occasionFit: const [],
  seasons: const [],
  warmth: 4,
  attributes: const {},
  fieldSources: const {'canonicalType': 'visual_ai'},
  fieldConfidence: const {'canonicalType': .9},
  userOverrideFields: const [],
);
void main() {
  late WardrobeOntologyV2 ontology;
  setUpAll(() async {
    ontology = WardrobeOntologyV2.fromJsonString(
      await File('assets/data/wardrobe_ontology_v2.json').readAsString(),
    );
  });
  test('asset taxonomy has 170 types and parent-safe accessories', () {
    final o = ontology;
    expect(o.types.length, 170);
    expect(o.definition('earrings')?.parentType, 'jewelry');
    expect(o.resolveAlias('shoulder purse'), 'shoulder_bag');
    expect(o.definition('dress')?.defaultBodySlots, ['full_body']);
    expect(
      o.definition('thermal_underwear_bottom')?.defaultLayerPosition,
      'skin_base',
    );
  });
  test('one-piece and separates completeness are distinct', () {
    final dress = item('dress', 'one_piece', ['full_body'], 'outer'),
        shoe = item('sneakers', 'footwear', ['feet'], 'not_applicable');
    final one = OutfitCompositionV2(
      template: OutfitTemplateV2.onePiece,
      items: [
        OutfitCompositionItemV2(
          itemId: 'd',
          item: dress,
          role: CompositionRoleV2.core,
          compositionGroup: 'full_body_core',
          required: true,
          selectionReason: 'core',
        ),
        OutfitCompositionItemV2(
          itemId: 's',
          item: shoe,
          role: CompositionRoleV2.core,
          compositionGroup: 'footwear',
          required: true,
          selectionReason: 'core',
        ),
      ],
    );
    expect(
      one
          .completeness(weatherProtectionRequired: false, minimumFormality: 1)
          .coreComplete,
      true,
    );
  });
  test('accessory multiplicity is conservative', () {
    final watch = item(
      'watch',
      'accessory',
      ['wrist'],
      'not_applicable',
      accessoryGroup: 'watch',
    );
    final c = OutfitCompositionV2(
      template: OutfitTemplateV2.separates,
      items: [
        for (final id in ['a', 'b'])
          OutfitCompositionItemV2(
            itemId: id,
            item: watch,
            role: CompositionRoleV2.functional,
            compositionGroup: 'watch',
            required: false,
            selectionReason: 'finish',
          ),
      ],
    );
    expect(c.compatibilityErrors(), contains('max_per_group:watch'));
  });
  test('set membership remains item relationship only', () {
    final x = WardrobeItemV2(
      canonicalType: 'blazer',
      canonicalFamily: 'outerwear',
      bodySlots: const ['upper_body'],
      layerPosition: 'outer',
      colorProfile: const ColorProfileV2(
        primary: SemanticColorV2(family: 'navy'),
        metalTone: 'none',
        hardwareTone: 'none',
      ),
      formality: 8,
      styles: const [],
      occasionFit: const [],
      seasons: const [],
      warmth: 5,
      attributes: const {},
      fieldSources: const {'canonicalType': 'visual_ai'},
      fieldConfidence: const {'canonicalType': .9},
      userOverrideFields: const [],
      setMembership: const SetMembershipV2(setId: 'suit-1', setType: 'suit'),
    );
    expect(x.toMap().containsKey('compositionRole'), false);
    expect((x.toMap()['setMembership'] as Map)['setId'], 'suit-1');
  });
  test('downstream adapters keep flexible composition and capabilities', () {
    final bag = item('shoulder_bag', 'bag', [
      'shoulder_carried',
    ], 'not_applicable');
    expect(WardrobeCapabilityQueryV2.carriedItems([bag]), hasLength(1));
    final payload = CalendarOutfitV2Payload(
      template: 'one_piece',
      items: const [
        FlexibleOutfitItemV2(
          itemId: 'dress-1',
          compositionGroup: 'full_body_core',
          compositionRole: 'core',
          requiredness: 'required',
          selectionReason: 'one_piece_template',
        ),
      ],
    ).toMap();
    expect((payload['outfitItems'] as List), hasLength(1));
    expect(payload.containsKey('top'), false);
  });

  test('strict resolver accepts V2 and never guesses legacy identity', () {
    final resolver = WardrobeV2Resolver(ontology);
    final trousers = item('trousers', 'bottom', ['lower_body'], 'outer');
    expect(
      resolver.resolve('grey', trousers.toMap()).item.canonicalType,
      'trousers',
    );
    expect(
      () => resolver.resolve('legacy', {
        'name': 'Sivé nohavice',
        'category': 'nohavice',
      }),
      throwsA(isA<WardrobeV2DataQualityException>()),
    );
  });

  test('necklace and neckwear constraints are conservative', () {
    OutfitCompositionItemV2 wrapped(String id, WardrobeItemV2 value) =>
        OutfitCompositionItemV2(
          itemId: id,
          item: value,
          role: CompositionRoleV2.finishing,
          compositionGroup: 'neckwear',
          required: false,
          selectionReason: 'test',
        );
    final necklace = item('necklace', 'jewelry', ['neck'], 'not_applicable');
    final tie = item('tie', 'neckwear', ['neck'], 'not_applicable');
    final bow = item('bow_tie', 'neckwear', ['neck'], 'not_applicable');
    expect(
      OutfitCompositionV2(
        template: OutfitTemplateV2.separates,
        items: [wrapped('n1', necklace), wrapped('n2', necklace)],
      ).compatibilityErrors(),
      contains('max_per_group:necklace'),
    );
    expect(
      OutfitCompositionV2(
        template: OutfitTemplateV2.separates,
        items: [wrapped('t', tie), wrapped('b', bow)],
      ).compatibilityErrors(),
      contains('mutually_exclusive:neckwear'),
    );
  });

  test('Add Clothing builder enriches KB and preserves user authority', () {
    final built = WardrobeV2WriteBuilder.fromAnalyzerAndKb(
      ontology: ontology,
      analyzer: {
        'identity': {'canonicalType': 't_shirt', 'confidence': .94},
        'observed': {
          'colorProfile': {
            'primary': {'family': 'white'},
            'secondary': null,
            'accents': [
              {'family': 'black', 'proportion': .03},
            ],
            'metalTone': 'none',
            'hardwareTone': 'none',
          },
          'attributes': {},
        },
        'inferred': {
          'formality': 3,
          'styles': ['casual'],
          'occasionFit': ['casual'],
          'warmth': 2,
        },
        'evidence': {
          'fieldConfidence': {'colorProfile': .9},
        },
      },
      existing: {
        'styles': ['minimal'],
      },
      manuallyEditedFields: {'styles'},
    );
    expect(built.bodySlots, ['upper_body']);
    expect(built.layerPosition, 'base');
    expect(built.colorProfile.accents.single.family, 'black');
    expect(built.styles, ['minimal']);
    expect(built.fieldSources['styles'], 'user_correction');
  });

  test(
    'Add Clothing builder keeps light Chelsea warmth in range and defaults to its KB typical value',
    () {
      final inferred = WardrobeV2WriteBuilder.fromAnalyzerAndKb(
        ontology: ontology,
        analyzer: {
          'identity': {'canonicalType': 'chelsea_boots', 'confidence': .94},
          'observed': {
            'colorProfile': {
              'primary': {'family': 'black'},
              'secondary': null,
              'accents': [],
              'metalTone': 'none',
              'hardwareTone': 'none',
            },
            'attributes': {},
          },
          'inferred': {
            'formality': 5,
            'styles': ['smart_casual'],
            'occasionFit': ['business_casual'],
            'warmth': 4,
          },
        },
      );
      expect(inferred.warmth, 4);
      expect(inferred.fieldSources['warmth'], 'visual_ai');
      expect(inferred.seasons, ['jar', 'jeseň']);
      expect(inferred.fieldConfidence['seasons'], 1.0);

      final defaulted = WardrobeV2WriteBuilder.fromAnalyzerAndKb(
        ontology: ontology,
        analyzer: {
          'identity': {'canonicalType': 'chelsea_boots', 'confidence': .94},
          'observed': {
            'colorProfile': {
              'primary': {'family': 'black'},
              'secondary': null,
              'accents': [],
              'metalTone': 'none',
              'hardwareTone': 'none',
            },
            'attributes': {},
          },
          'inferred': {
            'formality': 5,
            'styles': ['smart_casual'],
            'occasionFit': ['business_casual'],
          },
        },
      );
      expect(defaulted.warmth, 6);
      expect(defaulted.fieldSources['warmth'], 'knowledge_base');
      expect(defaulted.fieldSources['seasons'], 'system');
      expect(defaulted.seasons, ['jar', 'jeseň']);
    },
  );

  test('Add Clothing builder never replaces a user season override', () {
    final built = WardrobeV2WriteBuilder.fromAnalyzerAndKb(
      ontology: ontology,
      analyzer: {
        'identity': {'canonicalType': 'winter_boots', 'confidence': .94},
        'observed': {
          'colorProfile': {
            'primary': {'family': 'black'},
            'secondary': null,
            'accents': [],
            'metalTone': 'none',
            'hardwareTone': 'none',
          },
          'attributes': {},
        },
        'inferred': {
          'formality': 3,
          'styles': ['casual'],
          'occasionFit': ['casual'],
          'warmth': 8,
        },
      },
      existing: {
        'seasons': ['celoročne'],
        'userOverrideFields': ['seasons'],
        'fieldSources': {'seasons': 'user_correction'},
      },
    );
    expect(built.seasons, ['celoročne']);
    expect(built.fieldSources['seasons'], 'user_correction');
  });

  test(
    'Add Clothing builder rejects a Chelsea warmth outside its ontology range',
    () {
      expect(
        () => WardrobeV2WriteBuilder.fromAnalyzerAndKb(
          ontology: ontology,
          analyzer: {
            'identity': {'canonicalType': 'chelsea_boots', 'confidence': .94},
            'observed': {
              'colorProfile': {
                'primary': {'family': 'black'},
                'secondary': null,
                'accents': [],
                'metalTone': 'none',
                'hardwareTone': 'none',
              },
              'attributes': {},
            },
            'inferred': {
              'formality': 5,
              'styles': ['smart_casual'],
              'occasionFit': ['business_casual'],
              'warmth': 9,
            },
          },
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('swap, search and trip projections consume V2 semantics', () {
    final earrings = item('earrings', 'jewelry', ['ears'], 'not_applicable');
    final hoops = item('hoop_earrings', 'jewelry', ['ears'], 'not_applicable');
    final bag = item('handbag', 'bag', ['carried'], 'not_applicable');
    expect(
      SwapCandidateSelectorV2.compatible(
        replaced: earrings,
        candidates: [hoops, bag],
      ),
      [hoops],
    );
    expect(WardrobeCapabilityQueryV2.carriedItems([earrings, bag]), [bag]);
    expect(WardrobeSearchProjectionV2.tokens(earrings), contains('earrings'));
  });
  test('native engine produces one-piece flexible composition', () {
    ResolvedWardrobeItemV2 resolved(String id, WardrobeItemV2 value) =>
        ResolvedWardrobeItemV2(itemId: id, item: value, raw: const {});
    final dress = item('dress', 'one_piece', ['full_body'], 'outer');
    final shoes = item('sneakers', 'footwear', ['feet'], 'not_applicable');
    final watch = item(
      'watch',
      'accessory',
      ['wrist'],
      'not_applicable',
      accessoryGroup: 'watch',
    );
    final outfit = NativeOutfitEngineV2.compose([
      resolved('dress', dress),
      resolved('shoes', shoes),
      resolved('watch', watch),
    ], const NativeOutfitRequestV2(preferOnePiece: true))!;
    final completeness = outfit.completeness(
      weatherProtectionRequired: false,
      minimumFormality: 1,
    );
    expect(outfit.template, OutfitTemplateV2.onePiece);
    expect(completeness.coreComplete, true);
    expect(completeness.enhanced, true);
    expect(
      outfit.items.map((x) => x.compositionGroup),
      containsAll(['full_body_core', 'footwear']),
    );
  });

  test('thermal bottom remains conditional and trousers remain core outer', () {
    ResolvedWardrobeItemV2 resolved(String id, WardrobeItemV2 value) =>
        ResolvedWardrobeItemV2(itemId: id, item: value, raw: const {});
    final upper = item('t_shirt', 'top', ['upper_body'], 'base');
    final trousers = item('trousers', 'bottom', ['lower_body'], 'outer');
    final thermal = item(
      'thermal_bottom',
      'undergarment',
      ['lower_body'],
      'skin_base',
      functions: const ['thermal'],
    );
    final shoes = item('sneakers', 'footwear', ['feet'], 'not_applicable');
    final outfit = NativeOutfitEngineV2.compose([
      resolved('upper', upper),
      resolved('trousers', trousers),
      resolved('thermal', thermal),
      resolved('shoes', shoes),
    ], const NativeOutfitRequestV2(requiredFunctions: {'thermal'}))!;
    expect(
      outfit.items.singleWhere((x) => x.itemId == 'trousers').role,
      CompositionRoleV2.core,
    );
    expect(
      outfit.items.singleWhere((x) => x.itemId == 'thermal').role,
      CompositionRoleV2.conditional,
    );
  });

  test('production runtime entrypoint rejects legacy-only identity', () {
    final valid = <String, dynamic>{
      ...item('dress', 'one_piece', ['full_body'], 'outer').toMap(),
      'id': 'dress',
    };
    final legacyOnly = <String, dynamic>{
      'id': 'legacy',
      'type': 'dress',
      'categoryKey': 'saty_overaly',
    };
    final telemetry = WardrobeV2Telemetry();
    final resolved = NativeWardrobeV2Runtime.resolveAll(
      [valid, legacyOnly],
      telemetry: telemetry,
      ontology: ontology,
    );
    expect(resolved.map((x) => x.itemId), ['dress']);
    expect(telemetry.parseSuccess, 1);
    expect(telemetry.parseFailure, 1);
    expect(telemetry.legacyFallbackUse, 0);
  });

  test('calendar V2 item persists flexible composition metadata', () {
    const value = CalendarOutfitItem(
      type: OutfitWearType.top,
      label: 'Šaty',
      productImageUrl: null,
      cutoutImageUrl: null,
      cleanImageUrl: null,
      originalImageUrl: null,
      imageUrl: null,
      itemId: 'dress',
      canonicalType: 'dress',
      compositionRole: 'core',
      compositionGroup: 'full_body_core',
      requiredness: 'required',
      selectionReason: 'one_piece_template',
    );
    final roundTrip = CalendarOutfitItem.fromMap(value.toMap());
    expect(roundTrip.itemId, 'dress');
    expect(roundTrip.compositionGroup, 'full_body_core');
    expect(roundTrip.selectionReason, 'one_piece_template');
  });

  test('production swap selector enforces V2 context constraints', () {
    final replaced = item('earrings', 'jewelry', ['ears'], 'not_applicable');
    final casual = item(
      'hoop_earrings',
      'jewelry',
      ['ears'],
      'not_applicable',
      formality: 3,
    );
    final formal = item(
      'stud_earrings',
      'jewelry',
      ['ears'],
      'not_applicable',
      formality: 8,
    );
    expect(
      SwapCandidateSelectorV2.compatible(
        replaced: replaced,
        candidates: [casual, formal],
        minimumFormality: 6,
      ),
      [formal],
    );
  });

  test('flexible production result round-trips one-piece without slots', () {
    final raw = [
      <String, dynamic>{
        ...item('dress', 'one_piece', ['full_body'], 'outer').toMap(),
        'id': 'dress',
      },
      <String, dynamic>{
        ...item('sneakers', 'footwear', ['feet'], 'not_applicable').toMap(),
        'id': 'shoes',
      },
    ];
    final result = NativeWardrobeV2Runtime.recommend(
      documents: raw,
      request: const NativeOutfitRequestV2(preferOnePiece: true),
      ontology: ontology,
    )!;
    final restored = V2FlexibleOutfitResult.fromMap(result.toMap());
    expect(restored.template, OutfitTemplateV2.onePiece);
    expect(restored.completeness.coreComplete, true);
    expect(
      restored.items.map((x) => x.compositionGroup),
      containsAll(['full_body_core', 'footwear']),
    );
    expect(restored.toMap().containsKey('top'), false);
    expect(restored.toMap().containsKey('bottom'), false);
  });

  test('flexible swap preserves group and validates full composition', () {
    final raw = [
      <String, dynamic>{
        ...item('t_shirt', 'top', ['upper_body'], 'base').toMap(),
        'id': 'top',
      },
      <String, dynamic>{
        ...item('trousers', 'bottom', ['lower_body'], 'outer').toMap(),
        'id': 'bottom',
      },
      <String, dynamic>{
        ...item('sneakers', 'footwear', ['feet'], 'not_applicable').toMap(),
        'id': 'shoes',
      },
    ];
    final result = NativeWardrobeV2Runtime.recommend(
      documents: raw,
      request: const NativeOutfitRequestV2(),
      ontology: ontology,
    )!;
    final swapped = result.replaceItem(
      itemId: 'bottom',
      replacementId: 'jeans',
      replacement: item('jeans', 'bottom', ['lower_body'], 'outer'),
    );
    expect(swapped.validate(), isEmpty);
    expect(
      swapped.items.singleWhere((x) => x.itemId == 'jeans').compositionGroup,
      'lower_body_core',
    );
  });

  test('shared candidate matrix yields separates and one-piece candidates', () {
    ResolvedWardrobeItemV2 r(String id, WardrobeItemV2 value) =>
        ResolvedWardrobeItemV2(itemId: id, item: value, raw: {'id': id});
    final matrix = V2FlexibleCandidateMatrix.generate(
      wardrobe: [
        r('shirt', item('shirt', 'top', ['upper_body'], 'base')),
        r('trousers', item('trousers', 'bottom', ['lower_body'], 'outer')),
        r('dress', item('dress', 'one_piece', ['full_body'], 'outer')),
        r('shoes', item('sneakers', 'footwear', ['feet'], 'not_applicable')),
        r(
          'watch',
          item(
            'watch',
            'accessory',
            ['wrist'],
            'not_applicable',
            accessoryGroup: 'watch',
          ),
        ),
      ],
      context: const V2CandidateMatrixContext(maxCandidates: 8),
    );
    expect(
      matrix.map((x) => x.outfit.template),
      containsAll([OutfitTemplateV2.separates, OutfitTemplateV2.onePiece]),
    );
    expect(matrix.every((x) => x.outfit.validate().isEmpty), true);
  });

  test(
    'Home scorer prefers a valid matching partner but can split by context',
    () {
      const set = SetMembershipV2(
        setId: 'tracksuit-a',
        setType: 'tracksuit',
        relationshipSource: 'manufacturer_matching',
      );
      final matching = V2FlexibleOutfitResult(
        template: OutfitTemplateV2.separates,
        items: [
          V2FlexibleOutfitItem(
            itemId: 'hoodie',
            item: item(
              'hoodie',
              'top',
              ['upper_body'],
              'mid',
              setMembership: set,
            ),
            compositionRole: CompositionRoleV2.core,
            compositionGroup: 'upper_body_core',
            requiredness: 'required',
            selectionReason: 'core',
          ),
          V2FlexibleOutfitItem(
            itemId: 'sweatpants',
            item: item(
              'sweatpants',
              'bottom',
              ['lower_body'],
              'outer',
              setMembership: set,
            ),
            compositionRole: CompositionRoleV2.core,
            compositionGroup: 'lower_body_core',
            requiredness: 'required',
            selectionReason: 'core',
          ),
          V2FlexibleOutfitItem(
            itemId: 'shoes',
            item: item('sneakers', 'footwear', ['feet'], 'not_applicable'),
            compositionRole: CompositionRoleV2.core,
            compositionGroup: 'footwear',
            requiredness: 'required',
            selectionReason: 'core',
          ),
        ],
        completeness: const OutfitCompletenessV2(
          coreComplete: true,
          weatherComplete: true,
          dressCodeComplete: true,
          functionalComplete: true,
          enhanced: false,
          gaps: [],
        ),
      );
      final split = matching.replaceItem(
        itemId: 'sweatpants',
        replacementId: 'trousers',
        replacement: item(
          'trousers',
          'bottom',
          ['lower_body'],
          'outer',
          formality: 8,
        ),
      );
      final casual = const V2CandidateMatrixContext(minimumFormality: 1);
      expect(
        V2FlexibleOutfitScorer.score(matching, casual)['setCompatibility'],
        greaterThan(
          V2FlexibleOutfitScorer.score(split, casual)['setCompatibility']!,
        ),
      );
      final formal = const V2CandidateMatrixContext(minimumFormality: 8);
      expect(
        V2FlexibleOutfitScorer.score(split, formal)['dressCode'],
        equals(V2FlexibleOutfitScorer.score(matching, formal)['dressCode']),
      );
    },
  );

  test('flexible swap orchestrator replaces full-body with full-body', () {
    ResolvedWardrobeItemV2 r(String id, WardrobeItemV2 value) =>
        ResolvedWardrobeItemV2(itemId: id, item: value, raw: {'id': id});
    final wardrobe = [
      r('dress-a', item('dress', 'one_piece', ['full_body'], 'outer')),
      r('dress-b', item('jumpsuit', 'one_piece', ['full_body'], 'outer')),
      r('shoes', item('sneakers', 'footwear', ['feet'], 'not_applicable')),
    ];
    final current = V2FlexibleCandidateMatrix.generate(
      wardrobe: wardrobe,
      context: const V2CandidateMatrixContext(preferOnePiece: true),
    ).first.outfit;
    final swapped = V2FlexibleSwapOrchestrator.replace(
      current: current,
      itemId: current.items
          .singleWhere((x) => x.item.bodySlots.contains('full_body'))
          .itemId,
      wardrobe: wardrobe,
      context: const V2CandidateMatrixContext(preferOnePiece: true),
    );
    expect(swapped, isNotNull);
    expect(swapped!.completeness.coreComplete, true);
    expect(swapped.items.any((x) => x.itemId == 'dress-b'), true);
  });

  test('engine does not treat bottoms or dresses as outerwear jackets', () {
    ResolvedWardrobeItemV2 resolved(String id, WardrobeItemV2 value) =>
        ResolvedWardrobeItemV2(itemId: id, item: value, raw: const {});
    final outfit = NativeOutfitEngineV2.compose([
      resolved('top', item('t_shirt', 'top', ['upper_body'], 'base')),
      resolved('shorts', item('shorts', 'bottom', ['lower_body'], 'outer')),
      resolved('trousers', item('trousers', 'bottom', ['lower_body'], 'outer')),
      resolved('dress', item('dress', 'one_piece', ['full_body'], 'outer')),
      resolved(
        'shoes',
        item('sneakers', 'footwear', ['feet'], 'not_applicable'),
      ),
    ], const NativeOutfitRequestV2(tempC: 28))!;
    expect(
      outfit.items.any(
        (x) =>
            x.compositionGroup == 'layer_outer' &&
            (x.item.bodySlots.contains('lower_body') ||
                x.item.bodySlots.contains('full_body')),
      ),
      isFalse,
    );
    expect(outfit.items.any((x) => x.itemId == 'dress'), isFalse);
  });

  test(
    'engine skips heavy outerwear on a hot day when a lighter option exists',
    () {
      ResolvedWardrobeItemV2 resolved(String id, WardrobeItemV2 value) =>
          ResolvedWardrobeItemV2(itemId: id, item: value, raw: const {});
      WardrobeItemV2 warm(
        String type,
        String family,
        List<String> slots,
        String layer,
        int warmth,
      ) => WardrobeItemV2(
        canonicalType: type,
        canonicalFamily: family,
        bodySlots: slots,
        layerPosition: layer,
        outfitFunctions: const [],
        colorProfile: const ColorProfileV2(
          primary: SemanticColorV2(family: 'black'),
          metalTone: 'none',
          hardwareTone: 'none',
        ),
        formality: 3,
        styles: const [],
        occasionFit: const [],
        seasons: const [],
        warmth: warmth,
        attributes: const {},
        fieldSources: const {'canonicalType': 'visual_ai'},
        fieldConfidence: const {'canonicalType': .9},
        userOverrideFields: const [],
      );
      final outfit = NativeOutfitEngineV2.compose(
        [
          resolved('top', item('t_shirt', 'top', ['upper_body'], 'base')),
          resolved('jeans', item('jeans', 'bottom', ['lower_body'], 'outer')),
          resolved(
            'winter',
            warm('winter_jacket', 'outerwear', ['upper_body'], 'outer', 9),
          ),
          resolved(
            'rain',
            warm('rain_jacket', 'outerwear', ['upper_body'], 'outer', 4),
          ),
          resolved(
            'shoes',
            item('sneakers', 'footwear', ['feet'], 'not_applicable'),
          ),
        ],
        const NativeOutfitRequestV2(tempC: 32, weatherProtectionRequired: true),
      )!;
      expect(outfit.items.any((x) => x.itemId == 'winter'), isFalse);
      expect(outfit.items.any((x) => x.itemId == 'rain'), isTrue);
    },
  );
}
