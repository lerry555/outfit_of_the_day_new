import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_edit_executor_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_edit_delta_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_edit_plan_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';
import 'package:outfitofTheDay/utils/stylist_outfit_edit_routing.dart';
import 'package:outfitofTheDay/utils/stylist_swap_request.dart';

WardrobeItemV2 _item({
  required String type,
  required String family,
  required List<String> slots,
  required String layer,
  String color = 'black',
  String? secondaryColor,
  double? secondaryProportion,
  List<SemanticColorV2> accents = const <SemanticColorV2>[],
  int warmth = 4,
  int formality = 4,
  List<String> occasionFit = const <String>[],
  String? accessoryGroup,
}) => WardrobeItemV2(
  canonicalType: type,
  canonicalFamily: family,
  bodySlots: slots,
  layerPosition: layer,
  colorProfile: ColorProfileV2(
    primary: SemanticColorV2(family: color),
    secondary: secondaryColor == null
        ? null
        : SemanticColorV2(
            family: secondaryColor,
            proportion: secondaryProportion,
          ),
    accents: accents,
    metalTone: 'none',
    hardwareTone: 'none',
  ),
  formality: formality,
  styles: const <String>[],
  occasionFit: occasionFit,
  seasons: const <String>['all_season'],
  warmth: warmth,
  attributes: const <String, dynamic>{},
  fieldSources: const <String, dynamic>{'canonicalType': 'fixture'},
  fieldConfidence: const <String, dynamic>{'canonicalType': 1.0},
  userOverrideFields: const <String>[],
  accessoryGroup: accessoryGroup,
);

ResolvedWardrobeItemV2 _resolved(String id, WardrobeItemV2 item) =>
    ResolvedWardrobeItemV2(
      itemId: id,
      item: item,
      raw: <String, dynamic>{'id': id, 'name': id},
    );

final _wardrobe = <ResolvedWardrobeItemV2>[
  _resolved(
    'top-current',
    _item(
      type: 't_shirt',
      family: 'top',
      slots: const <String>['upper_body'],
      layer: 'base',
      warmth: 2,
    ),
  ),
  _resolved(
    'top-next',
    _item(
      type: 'polo',
      family: 'top',
      slots: const <String>['upper_body'],
      layer: 'base',
      color: 'white',
      warmth: 3,
    ),
  ),
  _resolved(
    'jeans-current',
    _item(
      type: 'jeans',
      family: 'bottom',
      slots: const <String>['lower_body'],
      layer: 'outer',
      color: 'blue',
      warmth: 5,
    ),
  ),
  _resolved(
    'shorts-next',
    _item(
      type: 'shorts',
      family: 'bottom',
      slots: const <String>['lower_body'],
      layer: 'outer',
      color: 'beige',
      warmth: 2,
    ),
  ),
  _resolved(
    'shoes-current',
    _item(
      type: 'sneakers',
      family: 'footwear',
      slots: const <String>['feet'],
      layer: 'not_applicable',
      color: 'white',
      warmth: 3,
    ),
  ),
  _resolved(
    'shoes-red',
    _item(
      type: 'sneakers',
      family: 'footwear',
      slots: const <String>['feet'],
      layer: 'not_applicable',
      color: 'red',
      warmth: 3,
    ),
  ),
  _resolved(
    'shoes-blue',
    _item(
      type: 'sneakers',
      family: 'footwear',
      slots: const <String>['feet'],
      layer: 'not_applicable',
      color: 'blue',
      warmth: 3,
    ),
  ),
  _resolved(
    'shoes-white-red-accent',
    _item(
      type: 'sneakers',
      family: 'footwear',
      slots: const <String>['feet'],
      layer: 'not_applicable',
      color: 'white',
      accents: const <SemanticColorV2>[
        SemanticColorV2(family: 'red', proportion: 0.08),
      ],
      warmth: 3,
    ),
  ),
  _resolved(
    'hoodie-next',
    _item(
      type: 'hoodie',
      family: 'top',
      slots: const <String>['upper_body'],
      layer: 'mid',
      color: 'gray',
      warmth: 5,
    ),
  ),
  _resolved(
    'thermal-base',
    _item(
      type: 'thermal_top',
      family: 'base_layer',
      slots: const <String>['upper_body'],
      layer: 'skin_base',
      warmth: 7,
    ),
  ),
  _resolved(
    'watch-next',
    _item(
      type: 'watch',
      family: 'accessory',
      slots: const <String>['wrist'],
      layer: 'not_applicable',
      accessoryGroup: 'watch',
    ),
  ),
  _resolved(
    'belt-next',
    _item(
      type: 'belt',
      family: 'accessory',
      slots: const <String>['waist'],
      layer: 'not_applicable',
      accessoryGroup: 'belt',
    ),
  ),
];

const _context = V2CandidateMatrixContext(maxCandidates: 8, tempC: 20);
const _currentIds = <String>{'top-current', 'jeans-current', 'shoes-current'};

Map<String, dynamic> _plan(
  List<Map<String, dynamic>> operations, {
  String intent = 'edit_current_outfit',
}) => <String, dynamic>{
  'contractVersion': 'outfit_edit_plan_v1',
  'intent': intent,
  'operations': operations,
  'presentation': intent == 'edit_current_outfit' ? 'concise_full' : 'normal',
};

void main() {
  final current = OutfitEditExecutorV1.restoreCurrent(
    wardrobe: _wardrobe,
    currentItemIds: _currentIds,
    context: _context,
  )!;

  test(
    'canonical multi-slot edit keeps all operations and default preserves',
    () {
      final plan = OutfitEditPlanV1.tryParse(
        _plan(<Map<String, dynamic>>[
          <String, dynamic>{
            'slot': 'top',
            'action': 'replace',
            'constraints': <String, dynamic>{},
          },
          <String, dynamic>{
            'slot': 'bottom',
            'action': 'replace',
            'constraints': <String, dynamic>{},
          },
          <String, dynamic>{
            'slot': 'shoes',
            'action': 'replace',
            'constraints': <String, dynamic>{'color': 'red'},
          },
        ]),
      )!;

      expect(plan.operations, hasLength(7));
      expect(
        plan.operationFor(OutfitEditSlotV1.layers).action,
        OutfitEditActionV1.preserve,
      );
      expect(
        plan.operationFor(OutfitEditSlotV1.shoes).constraints.color,
        'red',
      );
      expect(
        OutfitEditPlanV1.tryParse(
          _plan(<Map<String, dynamic>>[
            <String, dynamic>{
              'slot': 'shoes',
              'action': 'replace',
              'constraints': <String, dynamic>{'colour': 'red'},
            },
          ]),
        ),
        isNull,
      );
    },
  );

  test('add and replace execute atomically while preserving top and shoes', () {
    final plan = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'bottom',
          'action': 'replace',
          'constraints': <String, dynamic>{'family': 'shorts'},
        },
        <String, dynamic>{
          'slot': 'layers',
          'action': 'add',
          'constraints': <String, dynamic>{'type': 'hoodie'},
        },
      ]),
    )!;
    final candidates = OutfitEditExecutorV1.generateCandidates(
      plan: plan,
      current: current,
      wardrobe: _wardrobe,
      context: _context,
    );

    expect(candidates, isNotEmpty);
    for (final candidate in candidates) {
      final ids = candidate.outfit.items.map((item) => item.itemId).toSet();
      expect(ids, containsAll(<String>['top-current', 'shoes-current']));
      expect(ids, containsAll(<String>['shorts-next', 'hoodie-next']));
      expect(ids, isNot(contains('jeans-current')));
      expect(candidate.outfit.validate(), isEmpty);
    }
  });

  test(
    'red shoes constraint excludes otherwise valid non-red replacements',
    () {
      final plan = OutfitEditPlanV1.tryParse(
        _plan(<Map<String, dynamic>>[
          <String, dynamic>{
            'slot': 'shoes',
            'action': 'replace',
            'constraints': <String, dynamic>{'color': 'red'},
          },
        ]),
      )!;
      final candidates = OutfitEditExecutorV1.generateCandidates(
        plan: plan,
        current: current,
        wardrobe: _wardrobe,
        context: _context,
      );

      expect(candidates, isNotEmpty);
      expect(
        candidates.every(
          (candidate) =>
              candidate.outfit.items.any((item) => item.itemId == 'shoes-red'),
        ),
        isTrue,
      );
      expect(
        candidates.any(
          (candidate) => candidate.outfit.items.any(
            (item) => const <String>{
              'shoes-blue',
              'shoes-white-red-accent',
            }.contains(item.itemId),
          ),
        ),
        isFalse,
      );
    },
  );

  test('warmer, cooler and excluded-color constraints are hard filters', () {
    final warmerTop = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'top',
          'action': 'replace',
          'constraints': <String, dynamic>{
            'thermal': 'warmer',
            'excludedColor': 'black',
          },
        },
      ]),
    )!;
    final warmerCandidates = OutfitEditExecutorV1.generateCandidates(
      plan: warmerTop,
      current: current,
      wardrobe: _wardrobe,
      context: _context,
    );
    expect(warmerCandidates, isNotEmpty);
    expect(
      warmerCandidates.every(
        (candidate) =>
            candidate.outfit.items.any((item) => item.itemId == 'top-next'),
      ),
      isTrue,
    );

    final coolerBottom = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'bottom',
          'action': 'replace',
          'constraints': <String, dynamic>{
            'family': 'shorts',
            'thermal': 'cooler',
          },
        },
      ]),
    )!;
    expect(
      OutfitEditExecutorV1.generateCandidates(
        plan: coolerBottom,
        current: current,
        wardrobe: _wardrobe,
        context: _context,
      ),
      isNotEmpty,
    );
  });

  test('remove operation emits only complete atomic candidates', () {
    final layeredCurrent = OutfitEditExecutorV1.restoreCurrent(
      wardrobe: _wardrobe,
      currentItemIds: <String>{..._currentIds, 'hoodie-next'},
      context: _context,
    )!;
    final removeLayer = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'layers',
          'action': 'remove',
          'constraints': <String, dynamic>{},
        },
      ]),
    )!;
    final candidates = OutfitEditExecutorV1.generateCandidates(
      plan: removeLayer,
      current: layeredCurrent,
      wardrobe: _wardrobe,
      context: _context,
    );

    expect(candidates, isNotEmpty);
    expect(
      candidates.every(
        (candidate) => candidate.outfit.items.every(
          (item) => item.itemId != 'hoodie-next',
        ),
      ),
      isTrue,
    );
  });

  test('explanation plan has no mutation and never invokes legacy parser', () {
    var legacyCalls = 0;
    final routing = StylistOutfitEditRoutingV1.resolve(
      response: <String, dynamic>{
        'outfitEditPlan': _plan(const <Map<String, dynamic>>[], intent: 'none'),
      },
      userText: 'preco rifle a nie kratasy?',
      legacyResolver: (_, _) {
        legacyCalls++;
        return StylistSwapRequest.parse('daj ine topanky');
      },
    );

    expect(routing.canonicalPlanPresent, isTrue);
    expect(routing.canonicalPlan!.mutatesCurrentOutfit, isFalse);
    expect(routing.legacySwap, isNull);
    expect(legacyCalls, 0);
  });

  test(
    'impossible edit yields no partial candidate and leaves current untouched',
    () {
      final plan = OutfitEditPlanV1.tryParse(
        _plan(<Map<String, dynamic>>[
          <String, dynamic>{
            'slot': 'bottom',
            'action': 'replace',
            'constraints': <String, dynamic>{'family': 'shorts'},
          },
          <String, dynamic>{
            'slot': 'layers',
            'action': 'add',
            'constraints': <String, dynamic>{'type': 'cashmere_cardigan'},
          },
        ]),
      )!;
      final before = current.items.map((item) => item.itemId).toList();
      final candidates = OutfitEditExecutorV1.generateCandidates(
        plan: plan,
        current: current,
        wardrobe: _wardrobe,
        context: _context,
      );

      expect(candidates, isEmpty);
      expect(current.items.map((item) => item.itemId).toList(), before);
      expect(
        current.items.any((item) => item.itemId == 'shorts-next'),
        isFalse,
      );
    },
  );

  test('Brain plan cannot be overwritten by a conflicting legacy parser', () {
    var legacyCalls = 0;
    final routing = StylistOutfitEditRoutingV1.resolve(
      response: <String, dynamic>{
        'outfitEditPlan': _plan(<Map<String, dynamic>>[
          <String, dynamic>{
            'slot': 'shoes',
            'action': 'replace',
            'constraints': <String, dynamic>{'color': 'red'},
          },
        ]),
      },
      userText: 'legacy would choose a bottom',
      legacyResolver: (_, _) {
        legacyCalls++;
        return const StylistSwapRequest(slot: StylistSwapSlot.bottom);
      },
    );

    expect(legacyCalls, 0);
    expect(routing.legacySwap, isNull);
    expect(
      routing.canonicalPlan!
          .operationFor(OutfitEditSlotV1.shoes)
          .constraints
          .color,
      'red',
    );
    expect(
      routing.canonicalPlan!.operationFor(OutfitEditSlotV1.bottom).action,
      OutfitEditActionV1.preserve,
    );
  });

  test(
    'canonical focused edit exposes real focus and deterministic delta copy',
    () {
      final plan = OutfitEditPlanV1.tryParse(<String, dynamic>{
        ..._plan(<Map<String, dynamic>>[
          <String, dynamic>{
            'slot': 'shoes',
            'action': 'replace',
            'constraints': <String, dynamic>{'color': 'red'},
          },
        ]),
        'presentation': 'focused_item',
      })!;
      final candidate = OutfitEditExecutorV1.generateCandidates(
        plan: plan,
        current: current,
        wardrobe: _wardrobe,
        context: _context,
      ).single;
      final delta = OutfitEditDeltaV1.between(
        before: current,
        after: candidate.outfit,
        plan: plan,
      );

      expect(plan.focusSlotWireName, 'shoes');
      expect(delta.actualFocusSlot, 'shoes');
      expect(delta.changedAfterItemIds, <String>{'shoes-red'});
      expect(delta.followUpTextSk, contains('shoes-current'));
      expect(delta.followUpTextSk, contains('shoes-red'));
      expect(delta.followUpTextSk, isNot(contains('top-current')));
    },
  );

  test('multi edit explanation names actual changes and preserved items', () {
    final plan = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'bottom',
          'action': 'replace',
          'constraints': <String, dynamic>{'family': 'shorts'},
        },
        <String, dynamic>{
          'slot': 'layers',
          'action': 'add',
          'constraints': <String, dynamic>{'type': 'hoodie'},
        },
      ]),
    )!;
    final candidate = OutfitEditExecutorV1.generateCandidates(
      plan: plan,
      current: current,
      wardrobe: _wardrobe,
      context: _context,
    ).first;
    final text = OutfitEditDeltaV1.between(
      before: current,
      after: candidate.outfit,
      plan: plan,
    ).followUpTextSk;

    expect(text, contains('jeans-current'));
    expect(text, contains('shorts-next'));
    expect(text, contains('hoodie-next'));
    expect(text, contains('top-current'));
    expect(text, contains('shoes-current'));
  });

  test('create plan hard-enforces shorts and dominant red shoes', () {
    final plan = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'bottom',
          'action': 'add',
          'constraints': <String, dynamic>{'family': 'shorts'},
        },
        <String, dynamic>{
          'slot': 'shoes',
          'action': 'add',
          'constraints': <String, dynamic>{'color': 'red'},
        },
      ], intent: 'create_outfit'),
    )!;
    final eligible = OutfitEditExecutorV1.wardrobeForCreatePlan(
      plan: plan,
      wardrobe: _wardrobe,
    );

    expect(plan.operations, hasLength(2));
    expect(eligible.map((item) => item.itemId), contains('shorts-next'));
    expect(eligible.map((item) => item.itemId), contains('shoes-red'));
    expect(
      eligible.map((item) => item.itemId),
      isNot(contains('jeans-current')),
    );
    expect(
      eligible.map((item) => item.itemId),
      isNot(contains('shoes-white-red-accent')),
    );
    expect(
      OutfitEditExecutorV1.candidateSatisfiesCreatePlan(
        plan: plan,
        candidate: current,
      ),
      isFalse,
    );
    final generated =
        V2FlexibleCandidateMatrix.generate(
          wardrobe: eligible,
          context: _context,
        ).where(
          (candidate) => OutfitEditExecutorV1.candidateSatisfiesCreatePlan(
            plan: plan,
            candidate: candidate.outfit,
          ),
        );
    expect(generated, isNotEmpty);
    expect(
      generated.every(
        (candidate) => candidate.outfit.items
            .map((item) => item.itemId)
            .toSet()
            .containsAll(<String>{'shorts-next', 'shoes-red'}),
      ),
      isTrue,
    );
    final equivalentEdit = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'bottom',
          'action': 'replace',
          'constraints': <String, dynamic>{'family': 'shorts'},
        },
        <String, dynamic>{
          'slot': 'shoes',
          'action': 'replace',
          'constraints': <String, dynamic>{'color': 'red'},
        },
      ]),
    )!;
    final matchingCandidate = OutfitEditExecutorV1.generateCandidates(
      plan: equivalentEdit,
      current: current,
      wardrobe: _wardrobe,
      context: _context,
    ).first.outfit;
    expect(
      OutfitEditExecutorV1.candidateSatisfiesCreatePlan(
        plan: plan,
        candidate: matchingCandidate,
      ),
      isTrue,
    );
  });

  test('edit candidate pool does not require occasionFit metadata', () {
    final plan = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'top',
          'action': 'replace',
          'constraints': <String, dynamic>{'type': 'polo'},
        },
      ]),
    )!;
    final candidates = OutfitEditExecutorV1.generateCandidates(
      plan: plan,
      current: current,
      wardrobe: _wardrobe,
      context: const V2CandidateMatrixContext(
        maxCandidates: 8,
        tempC: 20,
        requiredOccasions: <String>{'casual'},
      ),
    );

    expect(candidates, isNotEmpty);
    expect(
      candidates.first.outfit.items.any((item) => item.itemId == 'top-next'),
      isTrue,
    );
  });

  test('generic added layer excludes skin_base thermal underwear', () {
    final plan = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'layers',
          'action': 'add',
          'constraints': <String, dynamic>{},
        },
      ]),
    )!;
    final candidates = OutfitEditExecutorV1.generateCandidates(
      plan: plan,
      current: current,
      wardrobe: _wardrobe,
      context: _context,
    );

    expect(candidates, isNotEmpty);
    expect(
      candidates.every(
        (candidate) => candidate.outfit.items.every(
          (item) => item.itemId != 'thermal-base',
        ),
      ),
      isTrue,
    );
  });

  test('multiple accessory adds are atomic and use distinct owned items', () {
    final plan = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'accessories',
          'action': 'add',
          'constraints': <String, dynamic>{'type': 'watch'},
        },
        <String, dynamic>{
          'slot': 'accessories',
          'action': 'add',
          'constraints': <String, dynamic>{'type': 'belt'},
        },
      ]),
    )!;
    final candidates = OutfitEditExecutorV1.generateCandidates(
      plan: plan,
      current: current,
      wardrobe: _wardrobe,
      context: _context,
    );

    expect(plan.operationsFor(OutfitEditSlotV1.accessories), hasLength(2));
    expect(candidates, isNotEmpty);
    expect(
      candidates.every(
        (candidate) => candidate.outfit.items
            .map((item) => item.itemId)
            .toSet()
            .containsAll(<String>{'watch-next', 'belt-next'}),
      ),
      isTrue,
    );
    expect(
      OutfitEditPlanV1.tryParse(
        _plan(<Map<String, dynamic>>[
          <String, dynamic>{
            'slot': 'bottom',
            'action': 'replace',
            'constraints': <String, dynamic>{},
          },
          <String, dynamic>{
            'slot': 'bottom',
            'action': 'remove',
            'constraints': <String, dynamic>{},
          },
        ]),
      ),
      isNull,
    );
  });
}
